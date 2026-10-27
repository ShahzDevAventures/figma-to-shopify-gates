// f2s_figma_audit.js — design-side preflight (v2 item 10).
// Run via the Figma connector/MCP (use_figma / plugin console) against the target file with
// NODE_IDS set to the frames being implemented. Save the returned JSON verbatim to
// .claude/knowledge/design/figma_audit.json — preflight reads its "verdict".
//
// Cutoffs (tunable, but change them in a decisions/ entry, not silently):
//   BLOCKED if any: textStyleCoverage < 0.5, tokenBindingCoverage < 0.4, autoLayoutCoverage < 0.6,
//                   a target page missing a breakpoint frame is handled by preflight via the manifest.
//   WARN if: defaultNameRatio > 0.3, any top-level child taller than 2000px (mega-frame), absInAL > 30.
// Evidence basis: an audit of one client's file found 0.5–14% text-style coverage, 16–24% token binding,
// 420px mobile frames, and a 3747px anonymous mega-frame — each mapped to a build failure mode.

const NODE_IDS = ["REPLACE:WITH", "TARGET:NODEIDS"];
const T = { textStyle: 0.5, tokenBinding: 0.4, autoLayout: 0.6, defaultNames: 0.3, megaFrameH: 2000, absMax: 30 };
const CAP = 2500;
const defaultName = /^(Frame|Group|Rectangle|Ellipse|Vector|Line|image|Component)\s*\d*$/i;
const results = []; const blockers = []; const warnings = []; const askDesigner = [];

// Semantic half — the five annotation tags. Structure tells us whether values
// can be transcribed; these tell us how the thing WORKS. A file can be structurally immaculate and
// still leave every behaviour and data source unstated (measured: 8 annotations across a whole site,
// 20 of 28 sections with none) — and everything unstated gets invented at build time.
const TAGS = ["@section", "@data", "@behavior", "@states", "@editable"];
const REQUIRED_TAGS = ["@data", "@states"];   // the two whose absence caused the most rework
const ASK = {
  "@section": "which section family is this? (check your section catalog — if you already ship it, adopt it)",
  "@data": "where does each piece of content come from — theme-editor setting, product metafield, or fixed?",
  "@behavior": "does anything move or react (hover, scroll, click, autoplay)? if nothing, say 'static'",
  "@states": "what shows when there's nothing to show — no products/reviews, missing image, very long title?",
  "@editable": "what can the merchant change themselves, and how many of any repeating item?"
};
// Collect annotation + pinned-comment text for a node subtree. Designers write in both; a pipeline
// that reads only dev-mode annotations reports "no annotations" on files full of comments.
function annotationText(n) {
  let out = "";
  try { if (Array.isArray(n.annotations)) for (const a of n.annotations) {
    if (a && a.label) out += " " + a.label;
    if (a && Array.isArray(a.properties)) for (const p of a.properties) out += " " + (p.type || "");
  } } catch (e) {}
  try { if (n.description) out += " " + n.description; } catch (e) {}
  return out;
}

for (const id of NODE_IDS) {
  let root = null;
  try { root = await figma.getNodeByIdAsync(id); } catch (e) { try { root = figma.getNodeById(id); } catch (e2) {} }
  if (!root) { blockers.push(`${id}: node not found`); continue; }
  const s = { id, name: root.name, w: Math.round(root.width), h: Math.round(root.height),
    total: 0, frames: 0, al: 0, groups: 0, absInAL: 0, text: 0, textStyled: 0,
    fillNodes: 0, fillStyled: 0, defNames: 0, megaFrames: [], annoText: "", tagsFound: [], tagsMissing: [] };
  if ("children" in root) for (const c of root.children)
    if (c.height > T.megaFrameH && defaultName.test(c.name)) s.megaFrames.push(`${c.name} (${Math.round(c.width)}x${Math.round(c.height)})`);
  const stack = [root];
  while (stack.length && s.total < CAP) {
    const n = stack.pop(); s.total++;
    s.annoText += annotationText(n);
    if (defaultName.test(n.name)) s.defNames++;
    if (n.type === "FRAME" || n.type === "COMPONENT" || n.type === "INSTANCE") { s.frames++; if (n.layoutMode && n.layoutMode !== "NONE") s.al++; }
    if (n.type === "GROUP") s.groups++;
    try { if (n.parent && n.parent.layoutMode && n.parent.layoutMode !== "NONE" && n.layoutPositioning === "ABSOLUTE") s.absInAL++; } catch (e) {}
    if (n.type === "TEXT") { s.text++; try { if (n.textStyleId && n.textStyleId !== "" && n.textStyleId !== figma.mixed) s.textStyled++; } catch (e) {} }
    try { if ("fills" in n && Array.isArray(n.fills) && n.fills.length && n.type !== "TEXT") { s.fillNodes++;
      const bv = n.boundVariables || {};
      if ((n.fillStyleId && n.fillStyleId !== "" && n.fillStyleId !== figma.mixed) || bv.fills) s.fillStyled++; } } catch (e) {}
    if ("children" in n) for (const c of n.children) stack.push(c);
  }
  s.textStyleCoverage = s.text ? +(s.textStyled / s.text).toFixed(2) : 1;
  s.tokenBindingCoverage = s.fillNodes ? +(s.fillStyled / s.fillNodes).toFixed(2) : 1;
  s.autoLayoutCoverage = s.frames ? +(s.al / s.frames).toFixed(2) : 1;
  s.defaultNameRatio = s.total ? +(s.defNames / s.total).toFixed(2) : 0;
  if (s.textStyleCoverage < T.textStyle) blockers.push(`${s.name}: text-style coverage ${s.textStyleCoverage} < ${T.textStyle} — create/apply text styles (spacing verification depends on a type system)`);
  if (s.tokenBindingCoverage < T.tokenBinding) blockers.push(`${s.name}: color token binding ${s.tokenBindingCoverage} < ${T.tokenBinding} — bind fills to variables/styles (raw hex = 'colors wrong' downstream)`);
  if (s.autoLayoutCoverage < T.autoLayout) blockers.push(`${s.name}: auto-layout coverage ${s.autoLayoutCoverage} < ${T.autoLayout} — freeform frames make spacing a guess`);
  if (s.defaultNameRatio > T.defaultNames) warnings.push(`${s.name}: ${Math.round(s.defaultNameRatio * 100)}% default layer names — annotations have no addressable targets`);
  if (s.megaFrames.length) warnings.push(`${s.name}: anonymous mega-frame(s) wrapping multiple sections: ${s.megaFrames.join("; ")} — split and name per section`);
  if (s.absInAL > T.absMax) warnings.push(`${s.name}: ${s.absInAL} absolute-positioned elements in auto-layout — each is a spec gotcha to capture`);

  // semantic scoring — which of the five tags this frame answers
  const lower = (s.annoText || "").toLowerCase();
  s.tagsFound = TAGS.filter(t => lower.includes(t));
  s.tagsMissing = TAGS.filter(t => !lower.includes(t));
  s.annotationCoverage = +(s.tagsFound.length / TAGS.length).toFixed(2);
  // One plain-language ask per missing tag, addressed to the frame — paste these as pinned
  // comments on that frame. Never send a designer a node id and a tag name.
  for (const t of s.tagsMissing)
    askDesigner.push({ frame: s.name, node: s.id, tag: t, blocking: REQUIRED_TAGS.includes(t), ask: `${s.name} — ${ASK[t]}` });
  results.push(s);
}

const structureOK = blockers.length === 0;
const semanticGaps = askDesigner.filter(a => a.blocking).length;
const verdict = !structureOK ? "BLOCKED" : (semanticGaps ? "GO_ANNOTATIONS_PARTIAL" : "GO");
const summary = {
  sections: results.length,
  annotationCoverage: results.length ? +(results.reduce((a, r) => a + r.annotationCoverage, 0) / results.length).toFixed(2) : 0,
  sectionsFullyAnnotated: results.filter(r => r.tagsMissing.length === 0).length,
  sectionsWithBlockingGaps: new Set(askDesigner.filter(a => a.blocking).map(a => a.frame)).size
};
// GO_ANNOTATIONS_PARTIAL is not a failure: build the answered sections, pin the questions on the
// rest, let those pause. Blocked-and-asked beats built-and-wrong.
return JSON.stringify({ verdict, cutoffs: T, summary, blockers, warnings, askDesigner, results, audited_at: new Date().toISOString() }, null, 1);
