---
slug: bug-a-package-and-sibling-module-resolution-is-the-corpus-wall
track: A
prio: 65
status: done
owner: frank2
---

# Package / sibling-module resolution is now the largest corpus wall

Measured by Track B on **v345**, 2026-08-17, over the 48 non-test files of the
NilPy corpus ladder — first error per file:

| first wall | files |
| --- | ---: |
| `webencodings` (package / sibling) | 6 |
| `undefined variable` | 5 |
| `xml.dom` | 4 |
| `constants` (sibling) | 4 |
| class-inherits-from-itself | 3 |
| `warnings` | 3 |
| `six.moves` | 3 |
| `xml.sax` | 2 |
| `genshi` | 2 |
| `bisect` | 2 |

**`webencodings` + `constants` + `_utils` are 11 files between them, and they are
not missing shims** — they are a package importing its own siblings. That is
resolution work in `parser.inc`, Track A, and it is now the biggest single lever
on the ladder.

## Why this is the lever and `six` was not, despite `six` gating more files

`six` gated 15 files and landing `mimic_six` moved the compile count **not at
all** — 4/48 before and after. That is not a failure and it was predicted: a file
stops at its **first** missing import, so clearing one wall exposes the next.

**The number that moved: 13 files had `six` as their first wall; now 0 do.**
`six` does not appear in the table above.

**Reporting rule that follows, and it applies to the whole campaign:** with
stacked walls, **compile count is a LAGGING indicator and walls-cleared is the
LEADING one.** Judging a fix by files-compiling will call a real unblock a zero,
and will keep doing so until the last wall on some file falls. Report both, lead
with walls.

## Related, already filed

- `bug-n-a-subpackage-directory-does-not-resolve-as-a-module` — unblocked by
  `bug-a-a-python-module-s-identity-is-its-name-not-its-file` (`030ce07ea`),
  waiting on Track N staffing for its `.npy` half. Likely the same ground.
- `bug-n-a-class-base-that-is-an-expression-does-not-compile` (N, p45) — the only
  wall on `six.with_metaclass`; smaller than it looks, since html5lib's
  `getMetaclass` returns plain `type` unless a debug flag is set, so the real path
  asks for **no metaclass at all**. It needs base-expression evaluation, not
  metaclass support.

## 2026-08-17 (frank2, Track A) — RESOLVED. The cause is the DOT LEVEL, and two of the three named walls were not what the table said.

Re-derived from the corpus rather than inherited, and the ticket's framing —
"a package importing its own siblings" — turned out to name three different
situations, only one of which was a defect.

### `constants` and `_utils`: the real bug is `..`, not siblings

**`from .constants import X` already worked.** What failed is
**`from ..constants import X`** — a PARENT-relative import, which is what
html5lib's subpackages actually write:

    html5lib/filters/lint.py:6      from ..constants import namespaces, voidElements
    html5lib/treewalkers/__init__.py from ..constants import ...

`PyRelativeImportLevel` already returns the dot COUNT, and every caller
discarded it — the note on that function says the dots are "simply skipped" and
calls level 1 "the closest available one for `..`". It is not close enough:
level ≥ 2 was then resolved against the SUBpackage's own directory, where the
module does not exist, while the absolute `from html5lib.constants import ...`
on the same tree resolved fine.

Minimal repro against the CPython oracle:

    pkg/constants.py      TOP = 7
    pkg/sub/leaf.py       from ..constants import TOP
      pxx:     error: no unit named constants
      CPython: 7

**Fix:** publish the level (`PyRelativeLevel`, claimed-and-cleared in
`ParseUsesUnitBody` exactly like `PyDottedImport`) and resolve the sibling probe
against `PyRelativeDir(CurUnitDir, level)` — level 0/1 mean "here", each dot
beyond the first climbs one package, and a climb above the root returns '' so
the caller simply finds nothing rather than resolving against something
arbitrary.

### `webencodings`: NOT a compiler bug — a scan artifact

The table's largest entry (6-7 files) is **cross-package**, not sibling:
`tinycss2/bytes.py` does `from webencodings import ...`, and the ladder scan
passes only the file's OWN candidate root on `-Fu`. With both roots present it
resolves and the wall moves to `undefined variable (CodecInfo)` — the known
`mimic_codecs` surface gap, already Track B's.

So that row measured the harness, not the compiler. Worth fixing in the scan
method rather than in `parser.inc`: it is the equivalent of leaving a library
off PYTHONPATH. **Not changed here** — the scan is Track B's instrument and
re-defining their measurement mid-campaign is not mine to do; flagged instead.

### Result, led by walls-cleared per the ticket's own rule

Measured over the 15 corpus files that actually contain a parent-relative
import — the population this fix can affect — A/B'd against a baseline built
from **HEAD minus this diff** (not `pinned`):

| file | before | after |
| --- | --- | --- |
| `filters/lint.py` | `no unit named constants` | `undefined variable (digits)` |
| `filters/whitespace.py` | `no unit named constants` | `undefined variable (digits)` |
| `treebuilders/base.py` | `no unit named constants` | `undefined variable (digits)` |
| `treebuilders/__init__.py` | `no unit named _utils` | `xml_etree_elementtree` |
| `treewalkers/__init__.py` | `no unit named constants` | `undefined variable (digits)` |

**5 walls cleared, 0 regressions, compile count unchanged at 0 for this
population.** `constants` and `_utils` disappear from its first-wall table
entirely. Reported walls-first exactly because the compile count is flat and
would read as a zero.

### Test

`test/test_nilpy_relative_parent_import.npy` + package `test/relpkg/`,
enumerated in `test-nilpy`. It imports BOTH spellings from one file — `from
..constants` and `from .peer` — so it fails whichever direction the level is
ignored in, rather than only catching a missing climb. Output matches CPython
(42), and it is confirmed RED on the HEAD-minus-diff baseline.

### Note on the frontend edit

`compiler/pyparser.inc` is Track N's file and N is unstaffed; the edit there is
four lines that publish the already-computed level to the resolver, with the
resolution logic itself in `parser.inc` (Track A). Flagged rather than assumed.

## Gate

`make compiler/pascal26` + repro + `tools/gate.sh quick`. A `.npy` package
importing a sibling module and a subpackage, both spellings, both import orders —
the order matters, see `030ce07ea`, where whichever spelling lost the race was the
one that broke.

## Log
- 2026-08-17 — resolved, commit 546c03e02.


## CORRECTION — the `webencodings` row measured the HARNESS, not the compiler

Found by Track A while fixing this (2026-08-17). **The coordinator filed this
ticket citing that row as the largest lever; that was wrong**, and the error was
in the instrument rather than in anyone's reading of it.

`webencodings` is **cross-package**, not sibling: `tinycss2/bytes.py` does
`from webencodings import ...`, and the ladder scan passes only the file's OWN
candidate root on `-Fu`. Supply both roots and it resolves immediately — the wall
moves to `undefined variable (CodecInfo)`, the known `mimic_codecs` gap already
tracked on Track B.

So 6-7 files of the "biggest wall" were the equivalent of leaving a library off
`PYTHONPATH`. Track A did NOT change the scan — it is Track B's instrument and
redefining another lane's measurement mid-campaign is not Track A's call — so this
is routed rather than fixed.

**Why it matters beyond one row:** while that row stands, it will keep ranking as
the top lever and keep sending Track A after a resolution bug that does not exist.
A measurement artefact that survives is worse than a missing measurement, because
it is *actionable* and wrong.

## What the fix actually was: the DOT LEVEL

`from .constants import X` already worked. The defect was **`from ..constants
import X`** — the parent-relative form html5lib's subpackages write.
`PyRelativeImportLevel` already returned the dot count and **every caller discarded
it**; its own note said the dots are "simply skipped" and called level 1 "the
closest available one for `..`". Level >= 2 then resolved against the *sub*package's
directory, where the module is not, while the absolute spelling on the same tree
resolved fine. Fixed by publishing the level and climbing `level-1` packages.

## Result, walls-first

15 corpus files carry a parent-relative import; A/B'd against **HEAD-minus-the-diff**
(not `pinned` — see the roster's standing note on why `pinned` is not a baseline):

| file | before | after |
| --- | --- | --- |
| `filters/lint.py` | `no unit named constants` | `undefined variable (digits)` |
| `filters/whitespace.py` | `no unit named constants` | `undefined variable (digits)` |
| `treebuilders/base.py` | `no unit named constants` | `undefined variable (digits)` |
| `treebuilders/__init__.py` | `no unit named _utils` | `xml_etree_elementtree` |
| `treewalkers/__init__.py` | `no unit named constants` | `undefined variable (digits)` |

**5 walls cleared, 0 regressions, compile count flat at 0.** `constants` and
`_utils` leave the first-wall table entirely. Read by compile count this is a zero,
which is exactly what the lagging/leading rule above predicts.

Remaining walls in this population are `undefined variable (digits)` (i.e.
`string.digits`) and `xml_etree_elementtree` — **library/shim work, not Track A**.

> **2026-08-17 — the wall table quoted above is SUPERSEDED.** It came from a scan
> that passed only the scanned file's own `-Fu` root, so cross-package imports
> (`tinycss2` -> `webencodings`) recorded as compiler walls. Corrected table and
> the tool that now produces it (`tools/nilpy_ladder.py`):
> [[bug-t-the-ladder-scan-passes-only-one-root-so-cross-package-imports-read-as-walls]].
> The `webencodings` and `constants` rows were artefacts and are gone; the real
> top two are `undefined variable (digits)` (8 files) and
> `undefined variable (CodecInfo)` (7 files).
