#!/usr/bin/env sh
# f2s_upload_validator.sh — v4.1. The Shopify ADMIN upload rules that theme-check does not enforce.
#
# the most recent rebuild (decision 0057, two upload-fix rounds): every gate was
# green — codehealth, theme-check 0 errors, editability, functional, self-test — and Shopify's admin
# theme-upload validator still rejected 22 sections. The two rule sets diverge. This gate encodes the
# divergence, as re-derived from the actual rejections, so the NEXT run fails here on the developer's
# machine before `shopify theme push` ever runs:
#
#   U-a  `range` settings: step missing/zero, or the number of selectable values ((max-min)/step + 1)
#        outside 3..101 (observed: columns_mobile 1-2 rejected, 1-3 accepted; 0-200 step 1 rejected).
#        Also: the range `default`, every preset setting and preset block setting that targets a
#        range must sit ON the step grid and inside min..max (the second fix round's miss).
#   U-b  defaults the admin rejects: `url` with "" / "#anchor" / a store-handle path (/pages/x,
#        /products/x, /blogs/x, /collections/x other than all) that cannot resolve on upload —
#        built-in routes like /collections/all pass; `link_list` default other than main-menu/footer.
#        Blank "" defaults on text/textarea/richtext/html are WARNED (the first fix round dropped 53 of them).
#   U-c  setting `label` empty (fail) or > 50 chars (WARN — one live theme shipped a 55-char label in
#        settings_schema.json and the admin accepted it); block `name` empty or > 25 (faq block,
#        one rejected theme); select/radio option `label` > 50 (4 option labels in one rejected theme); header `content`
#        > 50 (one rejected header); range `unit` > 3 chars ('px/s'). `paragraph` content is
#        not capped (live themes ship 268-char paragraphs). `t:` translation keys are exempt everywhere.
#   U-d  unclosed `{% comment %}` `{% schema %}` `{% javascript %}` `{% style %}` `{% stylesheet %}`
#        — including bare `comment`/`endcomment` lines inside `{% liquid %}` blocks, which is the
#        shape that got past theme-check in f2s_comparison_table.liquid.
#   U-e  a Liquid filter pipe inside a `{% render %}` argument value (`alt: x | default: y`):
#        render arguments cannot take filters — it is a syntax error at upload, not at lint.
#        Assign first, then pass the variable. Also matched inside `{% liquid %}` blocks.
#   U-f  `{% schema %}` JSON that does not parse (or >1 schema tag; or a schema in a snippet), and a
#        config/settings_schema.json that does not parse. Trailing commas alone are WARNED, not failed:
#        one rebuild's live legacy sections carry them and the admin tolerates them; theme-check does not.
#   U-g  an output tag `{{ ... }}` cut short by a literal `}}` inside one of its string arguments
#        (pdp_main's `replace: '{{rating}}'`) — the tag closes early and the rest is a parse error.
#
# Scans sections/*.liquid, snippets/*.liquid, config/settings_schema.json. Scope to specific files
# with F2S_UPLOAD_FILES="sections/a.liquid snippets/b.liquid" (the pre-commit hook does).
# Prints `file:line: [U-x] message` per finding. Exit 0 = clean. Non-zero = would be rejected.
#
# This is a static complement, not a replacement: GATE 8 still runs the real
# `shopify theme check --fail-level error` and, with credentials, a `shopify theme push --unpublished`
# dry-run (decision 0057's action item). POSIX sh + python3 -I only.
# Usage: sh f2s_upload_validator.sh [theme_root]
set -u
ROOT="${1:-.}"; cd "$ROOT" || exit 1
command -v python3 >/dev/null 2>&1 || { echo "🔴 python3 missing — upload validator cannot run"; exit 1; }

echo "================ f2s upload validator (Shopify admin rules theme-check misses) ================"
F2S_UPLOAD_FILES="${F2S_UPLOAD_FILES:-}" python3 -I - "$PWD" <<'PY'
import glob, json, os, re, sys

os.chdir(sys.argv[1])
scoped = os.environ.get("F2S_UPLOAD_FILES", "").split()
if scoped:
    files = [f for f in scoped if os.path.isfile(f)]
else:
    files = sorted(glob.glob("sections/*.liquid")) + sorted(glob.glob("snippets/*.liquid"))
    if os.path.isfile("config/settings_schema.json"):
        files.append("config/settings_schema.json")

fails, warns = [], []
def fail(f, line, rule, msg): fails.append(f"{f}:{line}: [{rule}] {msg}")
def warn(f, line, rule, msg): warns.append(f"{f}:{line}: [{rule}] {msg}")
def line_of(text, pos): return text.count("\n", 0, pos) + 1

LABEL_MAX, BLOCK_NAME_MAX, UNIT_MAX = 50, 25, 3
VALUES_MIN, VALUES_MAX = 3, 101
BLANK_WARN_TYPES = ("text", "textarea", "richtext", "inline_richtext", "html")
BUILTIN_ROUTES = {"/", "/collections", "/collections/all", "/products", "/cart", "/search",
                  "/account", "/account/login", "/account/register", "/account/addresses", "/blogs"}
HANDLE_PATH = re.compile(r"^/(pages|products|blogs|articles)/|^/collections/(?!all(?:$|[/?#]))[^/]+")
STR_LIT = re.compile(r"'(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\"")

def is_tkey(v): return isinstance(v, str) and v.startswith("t:")
TRAILING_COMMA = re.compile(r",(\s*[\]}])")
def loads_lenient(raw):
    """strict first; then with trailing commas removed (the admin tolerates them, strict parsers do not).
    Returns (obj, lenient_used) or raises the STRICT error."""
    try: return json.loads(raw), False
    except json.JSONDecodeError as e:
        try: return json.loads(TRAILING_COMMA.sub(r"\1", raw)), True
        except json.JSONDecodeError: raise e
def num(v):
    if isinstance(v, bool): return None
    try: return float(v)
    except (TypeError, ValueError): return None

# ---------- schema rules (U-a U-b U-c) shared by section schemas and settings_schema.json ----------
def check_settings(f, settings, raw, cursor, base_line, where, ranges):
    """raw/cursor/base_line locate each setting's line: search `"id": "<id>"` forward from cursor.
    `ranges` collects id -> (min,max,step,line) so presets can be checked against the grid."""
    if not isinstance(settings, list): return cursor
    for s in settings:
        if not isinstance(s, dict): continue
        sid = s.get("id")
        line = base_line
        if isinstance(sid, str):
            m = re.compile(r'"id"\s*:\s*"' + re.escape(sid) + r'"').search(raw, cursor)
            if m: line = base_line + line_of(raw, m.start()) - 1; cursor = m.end()
        t = s.get("type")
        if t == "range":
            lo, hi, st = num(s.get("min")), num(s.get("max")), num(s.get("step"))
            if "step" not in s or st is None:
                fail(f, line, "U-a", f"range '{sid}'{where}: step missing — the admin rejects a range with no step")
            elif lo is None or hi is None:
                fail(f, line, "U-a", f"range '{sid}'{where}: min/max must be numeric")
            elif st <= 0 or hi <= lo:
                fail(f, line, "U-a", f"range '{sid}'{where}: step must be > 0 and max > min")
            else:
                values = (hi - lo) / st + 1
                if values < VALUES_MIN:
                    fail(f, line, "U-a", f"range '{sid}'{where}: {values:g} selectable values (min {lo:g}, max {hi:g}, step {st:g}) — Shopify needs {VALUES_MIN}..{VALUES_MAX}; widen the range or shrink the step (seen: columns_mobile 1-2 rejected, 1-3 accepted)")
                elif values > VALUES_MAX:
                    fail(f, line, "U-a", f"range '{sid}'{where}: {values:g} selectable values — Shopify's ceiling is {VALUES_MAX}; enlarge the step (seen: 0-200 step 1 rejected, step 5 accepted)")
                else:
                    ranges[sid] = (lo, hi, st, line)
                    d = num(s.get("default"))
                    if "default" in s and (d is None or not on_grid(d, lo, hi, st)):
                        fail(f, line, "U-a", f"range '{sid}'{where}: default {s.get('default')!r} is off the {lo:g}..{hi:g} step-{st:g} grid")
            if isinstance(s.get("unit"), str) and len(s["unit"]) > UNIT_MAX:
                fail(f, line, "U-c", f"range '{sid}'{where}: unit '{s['unit']}' is {len(s['unit'])} chars (> {UNIT_MAX}) — fold it into the label (seen: 'px/s')")
        if t == "url" and "default" in s:
            d = s.get("default")
            ds = "" if d is None else str(d).strip()
            if ds == "":
                fail(f, line, "U-b", f"url '{sid}'{where}: \"default\": \"\" is rejected — omit the default (decision 0057)")
            elif ds.startswith("#"):
                fail(f, line, "U-b", f"url '{sid}'{where}: default '{ds}' — a url setting cannot default to an on-page anchor; use type text")
            elif HANDLE_PATH.match(ds):
                fail(f, line, "U-b", f"url '{sid}'{where}: default '{ds}' names a store handle that cannot resolve at upload — use a built-in route (/collections/all) or type text (seen: /pages/find-us rejected)")
            elif not (ds in BUILTIN_ROUTES or ds.startswith(("http://", "https://"))):
                warn(f, line, "U-b", f"url '{sid}'{where}: default '{ds}' is not a known built-in route — the admin may not resolve it; prefer /collections/all or omit")
        if t == "link_list" and "default" in s and s.get("default") not in ("main-menu", "footer"):
            fail(f, line, "U-b", f"link_list '{sid}'{where}: default {s.get('default')!r} — only main-menu or footer are accepted; name the handle in `info` instead")
        if t in BLANK_WARN_TYPES and "default" in s and (s.get("default") is None or str(s.get("default")).strip() == ""):
            warn(f, line, "U-b", f"{t} '{sid}'{where}: \"default\": \"\" — the first fix round dropped 53 of these as admin rejections; omit the key (blank stays blank)")
        if "label" in s and not is_tkey(s.get("label")):
            lab = "" if s.get("label") is None else str(s.get("label"))
            if lab.strip() == "":
                fail(f, line, "U-c", f"setting '{sid}'{where}: label is empty")
            elif len(lab) > LABEL_MAX:
                warn(f, line, "U-c", f"setting '{sid}'{where}: label is {len(lab)} chars (> {LABEL_MAX}) — decision 0057 reports a ~50 cap; a 55-char label uploaded fine on a live theme, so advisory: shorten it, move detail to `info`")
        if t in ("select", "radio") and isinstance(s.get("options"), list):
            for o in s["options"]:
                ol = o.get("label") if isinstance(o, dict) else None
                if isinstance(ol, str) and not is_tkey(ol) and len(ol) > LABEL_MAX:
                    fail(f, line, "U-c", f"{t} '{sid}'{where}: option label {ol!r} is {len(ol)} chars (> {LABEL_MAX}) (seen: 4 option labels)")
        if t == "header" and isinstance(s.get("content"), str) and not is_tkey(s["content"]) and len(s["content"]) > LABEL_MAX:
            fail(f, line, "U-c", f"header{where}: content is {len(s['content'])} chars (> {LABEL_MAX}) — move the detail into a paragraph setting (seen: quiz_embed header)")
    return cursor

def on_grid(v, lo, hi, st):
    if v < lo - 1e-9 or v > hi + 1e-9: return False
    k = (v - lo) / st
    return abs(k - round(k)) < 1e-6

def check_preset_values(f, values, ranges, line, where):
    if not isinstance(values, dict): return
    for k, v in values.items():
        if k in ranges:
            lo, hi, st, _ = ranges[k]
            n = num(v)
            if n is None or not on_grid(n, lo, hi, st):
                fail(f, line, "U-a", f"preset{where}: '{k}' = {v!r} is off the {lo:g}..{hi:g} step-{st:g} grid — the admin rejects it and the editor moves it on first touch (seen: contact 298 -> 296)")

def check_schema_obj(f, schema, raw, base_line):
    cursor, ranges, block_ranges = 0, {}, {}
    cursor = check_settings(f, schema.get("settings"), raw, cursor, base_line, "", ranges)
    for b in schema.get("blocks") or []:
        if not isinstance(b, dict): continue
        bt = b.get("type", "?")
        bline = base_line
        m = re.compile(r'"type"\s*:\s*"' + re.escape(str(bt)) + r'"').search(raw, cursor)
        if m: bline = base_line + line_of(raw, m.start()) - 1; cursor = m.end()
        if bt != "@app" and "name" in b and not is_tkey(b.get("name")):
            name = "" if b.get("name") is None else str(b.get("name"))
            if name.strip() == "":
                fail(f, bline, "U-c", f"block '{bt}': name (label) is empty")
            elif len(name) > BLOCK_NAME_MAX:
                fail(f, bline, "U-c", f"block '{bt}': name is {len(name)} chars (> {BLOCK_NAME_MAX}) (seen: faq block name)")
        block_ranges[bt] = {}
        cursor = check_settings(f, b.get("settings"), raw, cursor, base_line, f" (block '{bt}')", block_ranges[bt])
    for p in schema.get("presets") or []:
        if not isinstance(p, dict): continue
        pname = p.get("name", "?")
        pline = base_line
        m = re.compile(r'"name"\s*:\s*"' + re.escape(str(pname)) + r'"').search(raw, cursor)
        if m: pline = base_line + line_of(raw, m.start()) - 1; cursor = m.end()
        check_preset_values(f, p.get("settings"), ranges, pline, f" '{pname}'")
        for pb in p.get("blocks") or []:
            if isinstance(pb, dict):
                check_preset_values(f, pb.get("settings"), block_ranges.get(pb.get("type"), {}), pline, f" '{pname}' block '{pb.get('type')}'")

# ---------- liquid files: U-d U-e U-f U-g ----------
TAG_OPEN  = lambda name: re.compile(r"\{%-?\s*" + name + r"\b[^%]*%\}")
TAG_CLOSE = lambda name: re.compile(r"\{%-?\s*end" + name + r"\s*-?%\}")
LIQUID_BLOCK = re.compile(r"\{%-?\s*liquid\b(.*?)-?%\}", re.S)
RENDER_TAG   = re.compile(r"\{%-?\s*render\s+(.*?)-?%\}", re.S)
OUTPUT_TAG   = re.compile(r"\{\{-?(.*?)-?\}\}", re.S)
INNER_COMMENT = re.compile(r"\{%-?\s*comment\s*-?%\}(?:(?!\{%-?\s*(?:end)?comment\s*-?%\}).)*\{%-?\s*endcomment\s*-?%\}", re.S)
OPAQUE_BLOCKS = [re.compile(r"\{%-?\s*raw\s*-?%\}.*?\{%-?\s*endraw\s*-?%\}", re.S),
                 re.compile(r"\{%-?\s*doc\s*-?%\}.*?\{%-?\s*enddoc\s*-?%\}", re.S)]   # Dawn 15 {% doc %} examples are not code

def blank_keep_lines(s):           # replace a span with newlines only, so line numbers survive
    return "\n" * s.count("\n")

def render_args_have_pipe(args):
    """args = everything after the `render` keyword. Blank out string literals; any remaining `|`
    is a filter in an argument value (the snippet name is a literal too, so it is blanked as well)."""
    body = STR_LIT.sub(lambda m: "'" + " " * (len(m.group(0)) - 2) + "'", args)
    return "|" in body

def check_liquid(f):
    text = open(f, encoding="utf-8", errors="replace").read()
    work = text
    # Order matters: balanced {% comment %} blocks go FIRST (a comment may legitimately mention
    # `{% doc %}`, `{% schema %}` or `{% liquid %}` as prose), then {% doc %}/{% raw %} bodies.
    prev = None
    while prev != work:
        prev = work
        work = INNER_COMMENT.sub(lambda m: blank_keep_lines(m.group(0)), work)
    for rx in OPAQUE_BLOCKS:
        work = rx.sub(lambda m: blank_keep_lines(m.group(0)), work)

    # U-d inside {% liquid %} blocks: bare comment/endcomment lines; U-e: bare render lines
    for m in LIQUID_BLOCK.finditer(work):
        body, start = m.group(1), m.start(1)
        opens = closes = 0; first_open = None
        for i, ln in enumerate(body.split("\n")):
            s = ln.strip()
            if s.startswith("#"): continue
            if re.match(r"comment\b", s):
                opens += 1
                if first_open is None: first_open = line_of(work, start) + i
            elif re.match(r"endcomment\b", s):
                closes += 1
            rm = re.match(r"render\s+(.*)$", s)
            if rm and render_args_have_pipe(rm.group(1)):
                fail(f, line_of(work, start) + i, "U-e", "filter pipe inside a `render` argument (in {% liquid %}) — assign first, then pass the variable (post-mortem notes)")
        if opens != closes:
            fail(f, first_open or line_of(work, m.start()), "U-d", f"{{% liquid %}} block: {opens} `comment` vs {closes} `endcomment` — a body line starting with the word 'comment' reads as a nested open; use `#` line comments (seen: comparison_table)")
    work = LIQUID_BLOCK.sub(lambda m: blank_keep_lines(m.group(0)), work)

    # U-d: balanced (possibly nested) comment blocks were stripped innermost-first above; what is left is unbalanced
    co = [m.start() for m in TAG_OPEN("comment").finditer(work)]
    cc = [m.start() for m in TAG_CLOSE("comment").finditer(work)]
    if co or cc:
        pos = (co or cc)[0]
        fail(f, line_of(work, pos), "U-d", f"unbalanced {{% comment %}}: {len(co)} open vs {len(cc)} endcomment after matching pairs — theme-check did not catch this in production")

    for name in ("schema", "javascript", "style", "stylesheet"):
        o = [m.start() for m in TAG_OPEN(name).finditer(work)]
        c = [m.start() for m in TAG_CLOSE(name).finditer(work)]
        if len(o) != len(c):
            pos = (o if len(o) > len(c) else c)[-1] if (o or c) else 0
            fail(f, line_of(work, pos), "U-d", f"{{% {name} %}} opened {len(o)} time(s), closed {len(c)} — unclosed tag")

    # U-e: filter pipes inside {% render %} arguments
    for m in RENDER_TAG.finditer(work):
        if render_args_have_pipe(m.group(1)):
            fail(f, line_of(work, m.start()), "U-e", "filter pipe inside a `render` argument — render arguments cannot take filters; assign first, then pass the variable (seen: marquee alt default)")

    # U-g: an output tag whose body has an odd number of unescaped quotes was cut by a `}}` inside a literal
    for m in OUTPUT_TAG.finditer(work):
        body = STR_LIT.sub("", m.group(1))          # complete literals removed; "it's" is fine
        if "'" in body or '"' in body:
            fail(f, line_of(work, m.start()), "U-g", "output tag `{{ ... }}` closes early on a `}}` inside one of its string literals — move the expression into an `assign` statement tag (seen: pdp_main replace: '{{rating}}')")

    # U-f + schema rules: exactly one schema tag; JSON must parse
    opens = list(TAG_OPEN("schema").finditer(work))
    if f.startswith("snippets/") and opens:
        fail(f, line_of(work, opens[0].start()), "U-f", "snippets cannot carry a {% schema %} tag")
    if len(opens) > 1:
        fail(f, line_of(work, opens[1].start()), "U-f", "more than one {% schema %} tag — a section carries exactly one")
    if opens and not f.startswith("snippets/"):
        close = TAG_CLOSE("schema").search(work, opens[0].end())
        if close:
            raw = work[opens[0].end():close.start()]
            base_line = line_of(work, opens[0].end())
            try:
                schema, lenient = loads_lenient(raw)
            except json.JSONDecodeError as e:
                fail(f, base_line + e.lineno - 1, "U-f", f"schema JSON does not parse: {e.msg} (column {e.colno}) — the admin reports it as 'section type does not refer to an existing section file' on every template that uses it")
            else:
                if lenient: warn(f, base_line, "U-f", "schema JSON has trailing commas — the admin tolerates them (seen live on one rebuild) but theme-check and every strict parser reject them; remove")
                if isinstance(schema, dict): check_schema_obj(f, schema, raw, base_line)
                else: fail(f, base_line, "U-f", "schema JSON is not an object")

def check_settings_schema(f):
    raw = open(f, encoding="utf-8", errors="replace").read()
    try:
        data, lenient = loads_lenient(raw)
    except json.JSONDecodeError as e:
        fail(f, e.lineno, "U-f", f"settings_schema.json does not parse: {e.msg} (column {e.colno})"); return
    if lenient: warn(f, 1, "U-f", "settings_schema.json has trailing commas — tolerated by the admin, rejected by strict parsers; remove")
    if not isinstance(data, list):
        fail(f, 1, "U-f", "settings_schema.json must be a JSON array"); return
    cursor = 0
    for grp in data:
        if isinstance(grp, dict) and isinstance(grp.get("settings"), list):
            cursor = check_settings(f, grp["settings"], raw, cursor, 1, f" (group '{grp.get('name','?')}')", {})

if not files:
    print("RESULT: N/A (no sections/, snippets/ or config/settings_schema.json to scan)"); sys.exit(0)
for f in files:
    try:
        if f.endswith(".json"): check_settings_schema(f)
        else: check_liquid(f)
    except Exception as e:                       # a crash is a finding, never a silent pass
        fail(f, 1, "U-f", f"validator crashed on this file: {e!r}")

for w in warns: print(f"  ⚠️  {w}")
for x in fails: print(f"  🔴 {x}")
print("--------------------------------------------------------")
print(f"scanned {len(files)} file(s): {len(fails)} rejection(s), {len(warns)} warning(s)")
if fails:
    print("RESULT: FAIL — Shopify's admin upload would reject these (decision 0057); fix before push"); sys.exit(1)
print("RESULT: PASS — no admin upload rejections found (static check; GATE 8 still runs the real CLI)"); sys.exit(0)
PY
