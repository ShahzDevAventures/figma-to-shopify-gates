# How to use this skill

Converts Figma designs into Shopify OS 2.0 theme code, with every checkpoint enforced by a script
rather than a promise. Built for full page/theme builds that run unattended.

---

## Is this the right skill?

| You want to… | Use |
|---|---|
| Build a whole page or theme from Figma | **this skill** |
| Add one section/feature to a theme that already works | a lighter, hand-driven change — this pipeline's intake and gates are sized for whole pages |
| Fix something broken on a live store | a normal bug fix; the gate scripts still run by hand if you want them |
| Make refinements as the engineer who owns the code | **no skill** — see "Handing over" below |

The dividing line: this skill assumes nobody is watching. That premise is what justifies the gates,
and it is why it is the wrong tool once a human owns the repo.

---

## Before your first run

| Requirement | Check | If missing |
|---|---|---|
| `theme-check` gem | `theme-check --version` | `gem install theme-check` — codehealth is a hard gate and depends on it |
| Python 3 | `python3 --version` | required by half the gates |
| A Figma MCP server | `/mcp` | connect one; the run reads designs through it |
| `gh` | `gh auth status` | optional — without it, PR creation needs manual auth |
| Shopify CLI | `shopify version` | optional — the static harness is the fallback render path |
| Playwright | `npx playwright --version` | needed for real-pixel measurement |

**Design side.** The run will stop at the readiness audit if the Figma file can't be read
mechanically. Get these right before starting or you'll be waiting on the designer mid-run:

- Text layers on defined text styles (≥50%)
- Fills bound to variables, not raw hex (≥40%)
- Frames on auto-layout, not hand-positioned (≥60%)
- Every frame annotated with `@section @data @behavior @states @editable` — `@data` and `@states`
  are required; the others are recommended

---

## Install

```bash
git clone https://github.com/ShahzDevAventures/figma-to-shopify-gates ~/.claude/skills/figma-to-shopify-gates
chmod +x ~/.claude/skills/figma-to-shopify-gates/resources/scripts/*.sh
```

That's it — everything else installs itself into the theme repo on the first run.

The `chmod` is a safety net: git preserves executable bits on macOS and Linux, but some Windows
checkouts and archive downloads strip them, and a gate that can't execute is a gate that
isn't running. Confirm with:

```bash
sh ~/.claude/skills/figma-to-shopify-gates/resources/scripts/f2s_gate_selftest.sh
```

`SELFTEST: PASS` means the gates work. Anything else means fix that before running a build —
nothing a broken gate approves is worth having.

---

## Running it

```
/build-page <figma-url> <target-template>
```

### What happens, in order

```
 0. Permissions installed and proven          ← fails fast if the run would sit prompting
 1. Bootstrap — machinery into the repo, hooks armed
 2. Environment + gate self-test
 3. Existing-theme inventory                  ← YOU CLASSIFY: retire / keep / conflict
 4. Figma readiness audit + page inventory
 5. Foundation A — render path, fonts, tokens ← settles VERIFIED vs UNVERIFIED
 6. Research every section → one brief each
 7. ★ CHECK-IN 1 — the plan. Run halts.
 8. Preflight
 9. Foundation B — shared snippets
10. First section built + verified → ★ CHECK-IN 2. Run halts.
11. Remaining sections
12. Page integration → reachability → performance → handoff
13. PR, and the gates are disarmed for the maintainer
```

### The two places it stops for you

**Check-in 1 — the plan** (`plans/BUILD_PLAN.md`). One page: every section with its dependencies
and what it replaces, the retire list, what must survive, open questions, permissions, performance
budget. Nothing is built until you approve it. Read the retire list carefully — it's what stops a
rebuild shipping alongside the old theme instead of replacing it.

**Check-in 2 — the first finished section.** One section beside its design. Everything after it
follows the same interpretation, so this is the cheapest moment to correct course.

Between these, it runs unattended. `plans/STATUS.md` is current at all times.

### The one thing you do by hand

After step 3, `architecture/inventory.md` lists every existing section, snippet and template as
`UNCLASSIFIED`. Mark each:

- **RETIRE** — the new design replaces it; integration asserts it's gone
- **KEEP** — must survive: apps, and pages the design never drew (cart, blog, 404)
- **CONFLICT** — both would serve one purpose; you pick

Preflight blocks until every row is classified. On a theme with a prior custom layer this is 80+
rows the first time. It's tedious once and then it's done.

---

## When it halts

Four things stop everything. Each prints exactly what to fix.

| Halt | Means | Fix |
|---|---|---|
| Gate self-test failed | The gates themselves are broken | Fix the gate. Nothing a broken gate approves is trustworthy |
| Figma audit BLOCKED | The design can't be read mechanically | Send the designer the printed fix-list. This one is upstream of you |
| Preflight BLOCKED | Environment, permissions, or unclassified inventory | Work the shopping list it prints |
| Plan not approved | Waiting on you | Read `BUILD_PLAN.md`, approve or amend |

Everything else parks the affected section and keeps going.

---

## The gates, in one line each

| Gate | Asks |
|---|---|
| `permcheck` | Can this run proceed without prompting a human? |
| `inventory` | What does this theme already have? |
| `coverage` | Did we build **everything** the design contains? |
| `gate_selftest` | Do the gates themselves work? |
| `cache_check` | Is this node's extraction complete, annotations included? |
| `preflight` | Is it safe to start? |
| `precommit` | Spec before build, one section per commit, no dependency trees |
| `codehealth` | theme-check clean, registry current, headers present |
| `editability` | Can a merchant actually edit this? |
| `functional` | The nine production bug classes |
| `reachability` | Can a **customer** reach it? |
| `perf` | CLS-safe images, eager LCP, lazy below fold, CDN resize |
| `research_gap` | Is anything still unanswered? |
| `hooks_mode` | Whose repo is this right now? |

---

## Handing over

The last step of every run disarms the hooks. That's deliberate: the gates exist because an
unattended agent can't be trusted to judge, and that stops being true the moment a developer owns
the repo. They live in `core.hooksPath` — in the repo, not the skill — so left armed they gate
every human commit regardless of what tooling that person is using.

```bash
sh .claude/scripts/f2s_hooks_mode.sh status       # which mode am I in?
sh .claude/scripts/f2s_hooks_mode.sh maintainer    # gates off
sh .claude/scripts/f2s_hooks_mode.sh agent         # gates on (bootstrap does this)
```

The mode is recorded in `.claude/HOOKS_MODE`. Gates that are silently off are worse than gates that
block, so it always says which state you're in and when it changed.

---

## Troubleshooting

**Everything prompts for permission.** `permcheck` will tell you why. The usual cause is the
allowlist naming a Figma MCP server that doesn't exist on your machine — permission rules match the
server name exactly, and the name is whatever `/mcp` shows.

**"settings_data.json does not parse."** Shopify's JSON files carry `/* */` comment headers that
Shopify strips and standard parsers don't. The gates handle this; if you write your own tooling,
strip block comments and whole-line `//` first — never inline `//`, or you'll eat every `https://`.

**Measurements come back AMBIGUOUS.** The selector matched more than one element. This is a broken
assertion, not a build defect — narrow the selector in `spec.json`. Don't send these to a fixer.

**"BLOCKED: no spec.json found" on a section you wrote by hand.** You're in agent mode. If you're
maintaining rather than running a build, switch to maintainer mode.

**A section passes everything but nobody can see it.** That's what `reachability` catches. If a
section only renders when some theme setting is on, declare it in the spec:
`"runtime_requires": {"<setting_key>": <value>}`.

---

## What this skill will not do

- Guess a value the design doesn't specify. It parks the section and asks.
- Claim parity without a committed artifact. No number, no claim.
- Let one agent build and grade its own work.
- Finish a stalled subagent's work — it parks and reports instead.
- End silently. A run that stops early names everything it left behind.
