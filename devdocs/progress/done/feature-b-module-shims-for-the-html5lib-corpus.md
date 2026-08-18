---
track: B
prio: 60
type: feature
blocked-by: []
summary: "~18 corpus files stop on a missing module shim (xml_dom, xml_etree_elementtree, six_moves, bisect, genshi_core, xml_sax_*, colorsys, copy, lxml, urllib_request). Largest single lever on the third-party corpus and the only one that is pure Track B. Measured caveat: 11 of the yield-using library files stop on a shim FIRST, so shims landing alone move them onto the yield wall rather than past it — rank alongside the yield work, not ahead of it."
status: done
owner: frank3-fc
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

---

## What landed — 2026-08-18, frank3-fc

**Measured against `pinned` v347 (`f5da30bc9`)**, which is the ground Track B
builds on. It matters here: the `digits` fix (`65d26b24c`) and the CodecInfo
root-cause landed on master AFTER that pin, so both are still walls in every
number below. `tools/nilpy_ladder.py` uses `pinned` by design.

### Shipped, each verified against CPython by VALUE

Five shims, five differential tests wired into `make lib-test`. Every test file
runs unmodified under CPython against the real stdlib module, and every line was
checked to produce identical output both ways — so the assertions are not typed
from memory, which is how a plausible wrong entry gets encoded twice.

| shim | test | checks | scope |
| --- | --- | --- | --- |
| `mimic_bisect.py` | `lib_mimic_bisect.npy` | 18 | complete (minus `key=`) |
| `mimic_colorsys.py` | `lib_mimic_colorsys.npy` | 20 | HLS+HSV both directions; YIQ deliberately absent |
| `mimic_copy.py` | `lib_mimic_copy.npy` | 13 | builtin containers; raises on anything else |
| `mimic_xml_sax_saxutils.py` | `lib_mimic_xml_sax_saxutils.npy` | 18 | the three string functions; the SAX classes absent |
| `mimic_xml_sax_xmlreader.py` | `lib_mimic_xml_sax_xmlreader.npy` | 21 | `AttributesImpl` + `AttributesNSImpl`, whole interface |
| `mimic_urllib_request.py` | — | — | present and REFUSING; see below |

The tests are built around the failure the ticket warns about — a shim that
imports fine and returns a wrong value. So they assert *boundaries*, not
happy paths: `bisect_left` vs `bisect_right` on a run of equal keys (the only
thing separating the two functions), all six 60-degree hue sectors (hue is
circular, so a wrong sector still returns a plausible colour), `escape` NOT
touching quotes and doing `&` first (both produce well-formed but different
XML if wrong), `copy` mutating the copy and asserting the ORIGINAL is unchanged
(`copy(x) == x` passes for a shim that returns its argument), and the NS
attribute lookups by qname (a string-keyed shim passes everything else).

### The score, reported in the two categories the ticket asks for

Ladder before → after, same command, same pin:

**Moved PAST the wall — 1 file.** `webencodings/mklabels.py` (compile 4/48 → 5/48).
And it is a compile-only win, stated plainly: `mimic_urllib_request` REFUSES —
`urlopen` raises `NotImplementedError`. mklabels is a code generator that
downloads the WHATWG index; the library uses the `labels.py` it already
generated. Filed as
[[feature-b-mimic-urllib-request-over-the-rtl-http-stack]] (B, p30) — and note
the correction recorded there: the client is NOT missing, `lib/rtl/http.pas`
already ships redirects/keepalive/gzip/cookies over the TLS seam, so what is
left is a Python face on an existing unit. The first draft of that ticket said
"an HTTP client is a project" and would have mis-ranked it by an order of
magnitude.

**Moved ONTO the next wall — 8 files.** This is the outcome the ticket predicted;
recorded as progress, not as a compile-count claim:

| file | was | now |
| --- | --- | --- |
| `_trie/__init__.py` | missing module: bisect | unknown base class Mapping |
| `_trie/py.py` | missing module: bisect | unknown base class Mapping |
| `filters/sanitizer.py` | missing module: xml_sax_saxutils | missing module: six_moves |
| `treeadapters/__init__.py` | missing module: xml_sax_xmlreader | undefined variable (digits) |
| `treeadapters/sax.py` | missing module: xml_sax_xmlreader | undefined variable (digits) |
| `treebuilders/etree.py` | missing module: copy | undefined variable (digits) |
| `tinycss2/color3.py` | missing module: colorsys | undefined variable (CodecInfo) |

Four of those seven land on `digits`/`CodecInfo`, both already fixed or
root-caused on master — so they are banked against the next pin rather than
blocked. Zero regressions: no file that compiled before stopped compiling.

### Written and NOT shipped, with the reason

- **`xml_dom` (4 files)** — already measured and refused, unchanged:
  [[feature-nilpy-xml-dom-is-two-questions-not-one]]. Still correct on v347.
- **`xml_etree_elementtree` (2 files, incl. the `_utils.py` chokepoint)** — a
  real XML library, not a shim; same shape as xml_dom's question 2. And the
  chokepoint does not open even with it: with a stub in place `_utils.py` and
  `treebuilders/__init__.py` both land on **`unknown base class dict`**
  ([[feature-nilpy-subclass-a-builtin-type]]). Measured, not assumed — that is
  the "check what a file needs IN FULL" caveat paying off.
- **`six_moves` (4 files, now the largest shim row)** — needs `http.client` and
  `urllib` to exist at all. `mimic_six` already documents why it is absent.
  Filed as [[feature-b-mimic-six-moves-needs-http-client-and-urllib]].
- **`lxml`, `genshi_core` (3 files)** — real third-party packages, not stdlib.
  Shimming them is impersonating a library, and both files are optional
  backends html5lib guards behind an import.
- **`sys` (1 file)** — NOT a shim job. `import sys` works; `from sys import
  version_info` does not. Writing `mimic_sys.py` would create a second,
  competing `sys` and hide the resolver gap:
  [[bug-n-from-sys-import-fails-while-import-sys-works]].

### Four frontend gaps found while measuring — filed, not worked around

- [[bug-n-calling-through-a-function-alias-with-a-default-omitted-segfaults]]
  (N, p65) — **segfault, no diagnostic**. `f = g` then `f(a, b)` where `g` has
  defaulted params. Found because CPython's own `Lib/bisect.py` ends with
  `bisect = bisect_right`. Six-line repro, no imports.
- [[bug-n-from-sys-import-fails-while-import-sys-works]] (N, p55).
- [[bug-n-self-class-cannot-be-called-as-a-constructor]] (N, p45) — the one
  place a workaround was taken, registered in
  `devdocs/dev/track-b-workarounds.md` with its revert condition.
- [[bug-n-a-module-member-named-like-its-module-hides-the-modules-other-members]]
  (N, p40).

The platonic code stayed platonic: `mimic_bisect` keeps the `bisect =
bisect_right` alias CPython has even though calling it through the alias
crashes, and the test works around that at the CALL SITE with the ticket named,
rather than dropping the alias from the shim.

### Verification

`make lib-test` green (the five new differentials included). Ladder re-run after
each shim, not batched.

## Log
- 2026-08-18 — resolved, commit PENDING-COMMIT.
