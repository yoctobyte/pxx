---
slug: bug-a-package-and-sibling-module-resolution-is-the-corpus-wall
track: A
prio: 65
status: working
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

## Gate

`make compiler/pascal26` + repro + `tools/gate.sh quick`. A `.npy` package
importing a sibling module and a subpackage, both spellings, both import orders —
the order matters, see `030ce07ea`, where whichever spelling lost the race was the
one that broke.
