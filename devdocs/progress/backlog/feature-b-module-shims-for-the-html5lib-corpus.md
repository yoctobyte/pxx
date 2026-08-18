---
track: B
prio: 60
type: feature
blocked-by: []
summary: "~18 corpus files stop on a missing module shim (xml_dom, xml_etree_elementtree, six_moves, bisect, genshi_core, xml_sax_*, colorsys, copy, lxml, urllib_request). Largest single lever on the third-party corpus and the only one that is pure Track B. Measured caveat: 11 of the yield-using library files stop on a shim FIRST, so shims landing alone move them onto the yield wall rather than past it — rank alongside the yield work, not ahead of it."
---

# Module shims for the html5lib / third-party corpus

Filed by the coordinator from the ladder evidence in
[[feature-nilpy-thirdparty-libraries-as-targets]]. **The work was measured but never
filed**, which meant the single largest lever on the corpus was invisible to
`ready`/`next` — the same failure mode as a decided ticket that is never re-filed into
its lane.

## The ask

Write Python-shaped shims for the modules the corpus imports and we do not provide.
From the 2026-08-18 ladder run, ~18 files across these names:

```
xml_dom  xml_etree_elementtree  six_moves  bisect  genshi_core
xml_sax_*  colorsys  copy  lxml  urllib_request
```

Shipping shape is already settled — see `decide-how-python-shaped-shims-should-be-shipped`
(decided, p70): a Python-shaped shim ships as `mimic_<name>.py`, because the tree must
say what each shim is. `mimic_six` and `mimic_codecs` are the worked examples.

## Rank it ALONGSIDE the yield work, not ahead of it

This is the part that changes sequencing, and it was measured rather than assumed:

- 14 **library** files (not 23 — the larger figure counted 9 `html5lib/tests/**` files
  and the decision-relevant number is 14) use `yield`.
- **3** of them stop on `yield` today and nothing else:
  `html5lib/filters/inject_meta_charset.py`, `optionaltags.py`, `whitespace.py`.
- The other **11 stop on a module shim FIRST.**

So neither lever alone opens html5lib's pipeline. **If these shims land without
`yield`, those 11 files move ONTO the yield wall rather than past it** — the work would
read as "11 files advanced" while the compile count barely moves. That is not a reason
to defer the shims; it is a reason not to expect the compile number to reward them on
its own, and to schedule `feature-nilpy-yield-outside-a-for-loop` (N) in the same
window.

The parked recommendation on the campaign ticket implied the opposite sequencing
("further Track N work has low yield until the shims exist — all Track B"). That prose
was written against a pre-correction table, was already contradicted by the corrected
table published the same day, and is superseded. Do not resurrect it.

## Chokepoint worth taking first

`html5lib/_utils.py` is imported by **10 of html5lib's 52 files**. That is the same
shape `constants.py` had for the `digits` wall — the one that actually moved this
morning (8 files → 0). A chokepoint file is worth more than its own row.

Note `_utils.py` carries `MethodDispatcher(dict)`, so it also needs
[[feature-nilpy-subclass-a-builtin-type]] (N). Another compounding pair: check what a
file needs in full before scoring it as shim-only.

## What this is NOT

Not a compiler change. Anything that turns out to be a frontend or core gap while
writing these — a shim that is correct and still does not resolve — is filed into the
owning lane, not worked around in the shim. The live example is
[[bug-a-a-shim-classes-are-invisible-when-two-modules-import-the-same-shim]] (A, p65):
when two modules import the same shim, the shim's CLASSES stop resolving while its
PROCS still do. A shim can be perfect and still hit that.

Related standing warning from the campaign: a **complete, spec-exact** shim on a broken
substrate fails just as silently as a half-written one — a `mimic_xml_dom` would have
been ~20 lines and correct, and would still have produced structurally wrong output
while every `nodeType` comparison read `0 == 0`. Completeness is not the protection;
measuring after each shim lands is. Re-run the ladder per shim rather than batching.

## Gate

Track B's: build with `$(PXX_STABLE)`, never rebuild the compiler. `make lib-test`
green, and the ladder re-run to show which corpus files actually moved. Report files
moved past the wall separately from files moved onto the next wall — conflating them is
what the 11-file caveat above is about.
