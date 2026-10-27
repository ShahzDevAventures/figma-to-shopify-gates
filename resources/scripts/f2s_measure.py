#!/usr/bin/env python3
"""Measure a rendered section and check it against its spec's must_haves.

This is the piece an earlier run did not have. Its verification read the built code and
compared it to a screenshot by eye, which cannot see the two things that actually broke:
the CSS cascade (a correct declaration that loses a specificity fight renders wrong) and
anything at a viewport nobody wrote a spec for. Computed style is the only honest source
of truth, because it is what the browser actually resolved.

Usage:
  f2s_measure.py --url URL --spec spec.json --width 1440 --out measurement.json
  f2s_measure.py --url URL --spec spec.json --width 1440 --shot render.png

Reads must_haves entries shaped {element, property, value} — the schema SKILL.md mandates.
Any entry it cannot locate is reported MISSING rather than skipped: a check that quietly
disappears is how 24 must_haves become 19 passes and nobody notices.
"""
import argparse
import json
import re
import sys

TOL_PX = 2.0  # matches the skill's ±2px parity rule


def norm(value):
    """Normalise a CSS value for comparison. Returns (kind, comparable)."""
    if value is None:
        return ("none", None)
    v = str(value).strip().lower().rstrip(";")
    m = re.fullmatch(r"(-?\d*\.?\d+)px", v)
    if m:
        return ("px", float(m.group(1)))
    if re.fullmatch(r"-?\d*\.?\d+", v):
        return ("num", float(v))
    v = re.sub(r"\s+", " ", v)
    v = re.sub(r"\brgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)", r"rgb(\1,\2,\3)", v)
    return ("str", v)


def canon(v):
    """Canonicalise value strings the way Chrome serialises them: hex -> rgb(), rgba spacing, shadow token order.
    (Ported from an earlier run; recorded here as decision 0028.)"""
    v = ("" if v is None else str(v)).strip()   # 0 is a value, not "missing"
    v = re.sub(r"#([0-9a-fA-F]{6})\b", lambda m: "rgb(%d, %d, %d)" % (int(m.group(1)[0:2],16), int(m.group(1)[2:4],16), int(m.group(1)[4:6],16)), v)
    v = re.sub(r"rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*(0?\.\d+|[01]))?\s*\)",
               lambda m: ("rgb(%s, %s, %s)" % (m.group(1), m.group(2), m.group(3))) if m.group(4) in (None, "1") else ("rgba(%s, %s, %s, %s)" % (m.group(1), m.group(2), m.group(3), str(float(m.group(4))).lstrip("0") or "0")), v)
    if v in ("0", "0px", "normal"): v = "normal-or-zero"
    if "-gradient(" in v:
        # Chrome serialises gradients canonically: default centre "at 50% 50%" is dropped, whitespace
        # collapsed, "to bottom" dropped. Normalise both sides so an equivalent input never reads as DRIFT.
        v = re.sub(r"\s+", " ", v).replace(", ", ",").replace(" ,", ",")
        v = re.sub(r"\s*at 50% 50%", "", v)
        v = re.sub(r"linear-gradient\(to bottom,", "linear-gradient(", v)
        v = v.replace("(", "( ").replace(")", " )").replace(",", ", ")
        v = re.sub(r"\s+", " ", v).replace("( ", "(").replace(" )", ")")
    if "px" in v and ("rgb" in v) and len(v.split()) >= 4:   # shadows: compare as a sorted token set
        toks = sorted(t.strip(",") for t in v.split())
        v = " ".join(toks)
    return v


def compare(expected, actual):
    # `contains:<text>` — substring assertion (case-insensitive), e.g. a font stack that must include
    # a family, or a background-image url. Explicit operator; never inferred.
    if isinstance(expected, str) and expected.startswith("contains:"):
        if actual is None: return "MISSING", None
        return ("MATCH" if expected[9:].strip().lower() in str(actual).lower() else "DRIFT"), None
    if actual is not None and canon(expected) == canon(actual):
        return "MATCH", 0
    ek, ev = norm(expected)
    ak, av = norm(actual)
    if actual is None:
        return "MISSING", None
    if ek == "px" and ak == "px":
        d = abs(ev - av)
        return ("MATCH" if d == 0 else "CLOSE" if d <= TOL_PX else "DRIFT"), round(d, 2)
    if ek in ("num", "px") and ak in ("num", "px"):
        d = abs(ev - av)
        return ("MATCH" if d == 0 else "CLOSE" if d <= TOL_PX else "DRIFT"), round(d, 2)
    return ("MATCH" if ev == av else "DRIFT"), None


# Injected into the page: resolve one selector to its computed value. Falls back through
# a few shapes because must_haves are written by a model and are not perfectly uniform.
JS = """
(args) => {
  let [selector, prop, opts] = args;
  let el = null;
  // AMBIGUITY IS A FAILURE, NOT A COIN FLIP (v4). This used to be querySelector — first match
  // only — so an assertion silently resolved against whichever copy happened to come first in
  // the DOM: a hidden duplicate, an overlay, an open-by-design variant. On one build that produced
  // ~50% non-defects on one fixer's worklist, repeated across four agents. Every hour spent
  // "fixing" a difference that was never real. A selector that matches 0 or 2+ elements is a
  // BROKEN ASSERTION and must be fixed where it was authored, not adjudicated at fixer time.
  let all = null;
  // pseudo-element selectors (::placeholder, ::before, ::after): split off, resolve on the host element
  let pseudo = null;
  const pm = selector.match(/::(placeholder|before|after|marker)\s*$/);
  if (pm) { pseudo = '::' + pm[1]; selector = selector.slice(0, pm.index); }
  try { all = document.querySelectorAll(selector); } catch (e) { return {error: 'bad selector'}; }
  // "visible": true on a check restricts matches to rendered elements (display:none / detached excluded)
  if (opts && opts.visible) all = Array.prototype.filter.call(all, function (n) { return n.getClientRects().length > 0; });
  // `count` asserts how many elements match — the only prop for which 0 or many is the answer itself
  if (prop === 'count') return {found: true, value: String(all.length), box: {w: 0, h: 0, x: 0, y: 0}, exact: true};
  if (all.length === 0) return {found: false};
  const nth = (opts && Number.isInteger(opts.nth)) ? opts.nth : null;
  if (all.length > 1 && nth === null) {
    return {found: false, ambiguous: true, matches: all.length,
            error: 'selector matches ' + all.length + ' elements — narrow it, or declare "nth": <index> on the check when one representative element is the intent; a silent first-match guess is how non-defects enter the fixer worklist'};
  }
  el = all[nth === null ? 0 : nth];
  if (!el) return {found: false};
  const cs = getComputedStyle(el, pseudo);
  const box = el.getBoundingClientRect();
  let value = cs.getPropertyValue(prop);
  if (prop.indexOf('box.') === 0) {
    const k = prop.slice(4);
    const v = ({width: box.width, height: box.height, x: box.x, y: box.y, left: box.x, top: box.y})[k];
    value = (v === undefined) ? '' : (v + 'px');
  }
  // `lines` — rendered text line count (box height / computed line-height), for "3 lines, not 4" checks
  if (prop === 'lines') {
    // count rendered line boxes of the element's TEXT (padding-proof): Range client rects grouped by top
    try {
      const range = document.createRange(); range.selectNodeContents(el);
      const tops = new Set(); Array.prototype.forEach.call(range.getClientRects(), r => { if (r.width > 0 && r.height > 0) tops.add(Math.round(r.top)); });
      value = String(Math.max(1, tops.size));
    } catch (e) {
      const lh = parseFloat(cs.lineHeight) || (parseFloat(cs.fontSize) * 1.2);
      value = String(Math.max(1, Math.round(box.height / lh)));
    }
  }
  if (!value) {
    const camel = prop.replace(/-([a-z])/g, (m, c) => c.toUpperCase());
    value = cs[camel];
  }
  if ((prop === 'width' || prop === 'height') && (!value || value === 'auto')) {
    value = (prop === 'width' ? box.width : box.height) + 'px';
  }
  return {
    found: true,
    value: value,
    box: {w: Math.round(box.width * 100) / 100, h: Math.round(box.height * 100) / 100,
          x: Math.round(box.x * 100) / 100, y: Math.round(box.y * 100) / 100},
  };
}
"""


def _norm_entry(m):
    if not isinstance(m, dict):
        return None
    el = m.get("element") or m.get("selector")
    prop = m.get("property") or m.get("prop")
    val = m.get("value") if "value" in m else m.get("expected") if "expected" in m else m.get("expect")
    if not (el and prop):
        return None
    out = {"element": el, "property": prop, "value": val}
    if m.get("id"): out["id"] = m["id"]
    if isinstance(m.get("nth"), int): out["nth"] = m["nth"]          # explicit representative element
    if m.get("visible") is True: out["visible"] = True                # only rendered matches count
    for k in ("superseded_by", "state", "note"):
        if m.get(k) is not None: out[k] = m[k]
    bpv = m.get("breakpoint", m.get("bp"))
    if bpv is not None: out["breakpoint"] = bpv
    return out


def load_must_haves(spec_path, width=None):
    """Accept every shape researchers actually produce (decision 0028):
      - spec.must_haves: list of {element|selector, property|prop, value|expected|expect}
      - spec.checks:     list of {id, selector, prop, expect[, breakpoint]}
      - spec.breakpoints.<w>.must_haves / .checks: the same, scoped to that width
    Entries carrying "breakpoint" are kept only when it equals --width; entries under
    breakpoints.<w> are used INSTEAD of top-level ones when --width == w and any exist.
    Nothing is silently dropped: the count of loaded entries is printed to stderr."""
    spec = json.load(open(spec_path))
    def collect(node):
        res = []
        for key in ("must_haves", "checks"):
            v = node.get(key)
            if isinstance(v, list):
                for m in v:
                    e = _norm_entry(m)
                    if e: res.append(e)
        return res
    top = collect(spec)
    scoped = []
    # Convention used by this run's specs: top-level `checks` = desktop, `checks_mobile` = the mobile
    # breakpoint (breakpoints_designed.mobile). Honour it before the generic breakpoints.<w> scan.
    if width is not None:
        bd = spec.get("breakpoints_designed") or {}
        try:
            mob_w = int(str(bd.get("mobile", "")).strip() or 0)
            desk_w = int(str(bd.get("desktop", "")).strip() or 0)
        except ValueError:
            mob_w = desk_w = 0
        if mob_w and int(width) == mob_w and isinstance(spec.get("checks_mobile"), list):
            scoped = [e for e in (_norm_entry(m) for m in spec["checks_mobile"]) if e]
        elif desk_w and int(width) == desk_w and isinstance(spec.get("checks_mobile"), list):
            # desktop run: exclude nothing, but top-level already excludes checks_mobile by construction
            pass
    if width is not None and not scoped:
        bps = spec.get("breakpoints") or {}
        for k, node in bps.items():
            try:
                if int(str(k).split("_")[-1]) == int(width) and isinstance(node, dict):
                    scoped = collect(node)
            except ValueError:
                pass
    if width is not None:
        top = [e for e in top if e.get("breakpoint") is None or int(e["breakpoint"]) == int(width)]
    out = scoped if scoped else top
    # de-duplicate identical element+property pairs (keep first)
    seen = set(); dedup = []
    for e in out:
        k = (e["element"], e["property"])
        if k in seen: continue
        seen.add(k); dedup.append(e)
    print(f"[measure] loaded {len(dedup)} checks for width {width} from {spec_path}", file=sys.stderr)
    return spec, dedup


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--spec", required=True)
    ap.add_argument("--width", type=int, required=True)
    ap.add_argument("--height", type=int, default=2400)
    ap.add_argument("--out")
    ap.add_argument("--shot")
    ap.add_argument("--selector", help="crop screenshot to this element")
    ap.add_argument("--pre-js", dest="pre_js", action="append", default=[],
                    help="JS to evaluate after load, before measuring (string or @file). Repeatable. "
                         "Use it to put the section in a spec'd interactive state, e.g. "
                         "\"document.querySelector('.x').click()\" — the state used is recorded in the output.")
    ap.add_argument("--wait-ms", dest="wait_ms", type=int, default=0,
                    help="settle time after --pre-js (transitions), default 0")
    ap.add_argument("--integrity", action="store_true",
                    help="skip spec checks; assert generic layout invariants (no horizontal "
                         "overflow, no element wider than viewport) — for breakpoints with no "
                         "designed frame, where parity would invent a ground truth")
    a = ap.parse_args()

    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        sys.exit("playwright missing — run f2s_env_check.sh; do NOT fall back to "
                 "reading the code and calling it verified.")

    spec, musts = load_must_haves(a.spec, a.width)
    results, shot_path = [], None

    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": a.width, "height": a.height},
                                device_scale_factor=2)
        page.goto(a.url, wait_until="networkidle", timeout=60000)
        try:
            page.wait_for_function("document.fonts && document.fonts.status === 'loaded'",
                                   timeout=15000)
        except Exception:
            pass  # recorded below rather than silently ignored

        fonts_ready = page.evaluate("document.fonts ? document.fonts.status : 'unknown'")

        # Interactive states: run the caller's JS (recorded verbatim in the result — a measurement
        # taken in a driven state must say so), then let transitions settle.
        pre_js_run = []
        for js in a.pre_js:
            src = open(js[1:]).read() if js.startswith("@") else js
            page.evaluate("(src) => { (0, eval)(src); }", src)
            pre_js_run.append(src)
        if a.wait_ms:
            page.wait_for_timeout(a.wait_ms)
        elif pre_js_run:
            page.wait_for_timeout(600)

        if a.integrity:
            inv = page.evaluate("""() => {
              const de = document.documentElement;
              const overflow = de.scrollWidth - de.clientWidth;
              const wide = [];
              for (const el of document.querySelectorAll('body *')) {
                const r = el.getBoundingClientRect();
                if (r.width > de.clientWidth + 1 && wide.length < 10)
                  wide.push((el.className && String(el.className).slice(0,60)) || el.tagName);
              }
              return {overflowPx: overflow, wideElements: wide};
            }""")
            results.append({"element": "html", "property": "horizontal-overflow",
                            "value": "0", "actual": str(inv["overflowPx"]),
                            "verdict": "MATCH" if inv["overflowPx"] <= 1 else "DRIFT",
                            "delta_px": inv["overflowPx"]})
            results.append({"element": "body *", "property": "wider-than-viewport",
                            "value": "none", "actual": ", ".join(inv["wideElements"]) or "none",
                            "verdict": "MATCH" if not inv["wideElements"] else "DRIFT",
                            "delta_px": None})
            musts = []  # spec checks skipped by design at undesigned breakpoints

        for m in musts:
            r = page.evaluate(JS, [m["element"], m["property"], {"nth": m.get("nth"), "visible": bool(m.get("visible"))}])
            if isinstance(r, dict) and r.get("ambiguous"):
                # Distinct from MISSING on purpose: MISSING means "the thing isn't there",
                # AMBIGUOUS means "the assertion can't say which thing it meant". The second is
                # an authoring defect and must be fixed in the spec, not pursued in the build.
                verdict, delta, actual = "AMBIGUOUS", None, f"{r.get('matches')} elements match"
            elif isinstance(r, dict) and r.get("error"):
                verdict, delta, actual = "MISSING", None, None
            elif not r or not r.get("found"):
                verdict, delta, actual = "MISSING", None, None
            else:
                actual = r.get("value")
                if isinstance(m.get("value"), str) and m["value"].startswith("contains:"):
                    verdict, delta = compare(m.get("value"), actual)
                elif m.get("property") == "count":
                    # counts are exact integers — no ±2 px tolerance applies
                    verdict, delta = ("MATCH" if str(m.get("value")).strip() == str(actual).strip() else "DRIFT"), None
                elif m.get("property") == "font-family":
                    first = lambda v: str(v or "").split(",")[0].strip().strip('\'"').lower()
                    verdict, delta = ("MATCH" if first(m.get("value")) == first(actual) else "DRIFT"), None
                else:
                    verdict, delta = compare(m.get("value"), actual)
            results.append({**m, "actual": actual, "verdict": verdict, "delta_px": delta})

        if a.shot:
            target = page.query_selector(a.selector) if a.selector else None
            if target: target.screenshot(path=a.shot)          # ElementHandle.screenshot has no full_page
            else: page.screenshot(path=a.shot, full_page=True)
            shot_path = a.shot
        browser.close()

    counts = {k: sum(1 for r in results if r["verdict"] == k)
              for k in ("MATCH", "CLOSE", "DRIFT", "MISSING", "AMBIGUOUS")}
    passed = counts["DRIFT"] == 0 and counts["MISSING"] == 0 and counts["AMBIGUOUS"] == 0

    doc = {
        "section": spec.get("section"),
        "node": spec.get("nodeId"),
        "width": a.width,
        "url": a.url,
        "method": "rendered computed-style measurement (playwright)",
        "fonts_status": fonts_ready,
        "pre_js": pre_js_run,
        "screenshot": shot_path,
        "summary": {**counts, "total": len(results), "result": "PASS" if passed else "FAIL"},
        "checks": results,
    }
    text = json.dumps(doc, indent=2)
    if a.out:
        open(a.out, "w").write(text + "\n")
    print(text if not a.out else
          f"{doc['section']} @{a.width}: {doc['summary']['result']} "
          f"({counts['MATCH']} match, {counts['CLOSE']} close, {counts['DRIFT']} drift, "
          f"{counts['MISSING']} missing, {counts['AMBIGUOUS']} ambiguous) → {a.out}")

    if counts["AMBIGUOUS"]:
        print(f"AMBIGUOUS x{counts['AMBIGUOUS']}: selector(s) matched more than one element. These are "
              "NOT build defects — do not send them to a fixer. Narrow the selector in spec.json.",
              file=sys.stderr)

    if fonts_ready != "loaded":
        print("WARNING: webfonts did not report loaded — typography measurements are "
              "unreliable; fix the font loading before trusting this artifact.",
              file=sys.stderr)
    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()
