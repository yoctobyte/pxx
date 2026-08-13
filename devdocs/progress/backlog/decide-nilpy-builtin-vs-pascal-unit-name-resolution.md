---
track: U
prio: 45
type: decide
blocked-by: []
summary: "A Python builtin whose name is also a Pascal routine (format vs sysutils' Format) is HIDDEN once the program imports anything reaching that unit — a builtin that stops existing when you add an import. Three routes: fix the cross-unit overload merge and declare builtins normally; keep intercepting name by name in the parser; or make NilPy builtins win over used units by rule. The collision surface is small TODAY (2 names) and grows with every builtin added."
---

# How should a NilPy builtin resolve against a same-named Pascal routine?

Raised from Track A+N on 2026-08-13 while adding `format(v[, spec])`
([[bug-nilpy-builtin-surface-gaps-found-by-the-2026-08-12-sweep]] item 4). The
builtin shipped as a parser intercept; this ticket is whether that is the
pattern or a stopgap.

## What is actually true today (measured, not assumed)

- **A `.npy` does NOT drag in sysutils.** pylib uses `pypal, promocore,
  typinfo` and nothing else; a bare program has no `Format` in scope. sysutils
  arrives only through an import that reaches the RTL — `import json` does,
  `import math` and `import os` do not (they are NilPy shims).
- **The hiding is FPC-faithful, not a pxx quirk.** A later unit's routine
  declared WITHOUT `overload` hides an earlier one entirely, overload set and
  all — measured with two toy units, same diagnostic shape as the real one.
  sysutils declares `Format` without `overload`, and it is used AFTER pylib.
- **The collision surface is small today: two names.** Of the 22 Python-named
  free routines pylib exports, only `min` and `max` also name an RTL free
  routine (`math`), and both are frontend-handled so neither breaks. Every
  builtin swept (`max`, `min`, `len`, `sum`, `sorted`, `format`) still answers
  correctly under `import json`, `import math` and `import os`. `format` was
  the first name that would actually have broken — and it broke completely,
  not subtly.
- **The clean Pascal route is blocked by a real defect.** Marking both
  declarations `overload` DOES make pxx merge cross-unit sets (proved) — but an
  `array of const` literal then fails to match when its unit is used LAST,
  which is sysutils' exact position. Filed as
  [[bug-a-array-of-const-literal-does-not-match-in-a-cross-unit-overload-set]].

## The options

1. **Fix the merge defect, then declare builtins normally.** Add `overload` to
   sysutils' `Format` and to the pylib arms; delete the parser intercept.
   FPC-faithful, no special case, generalises to every future collision, and
   the defect is worth fixing on its own merit. Cost: blocked on a Track A
   overload-resolution fix, and it puts a Python builtin and an FPC routine in
   one overload set, where a mis-ranked call is a silently wrong RESULT rather
   than a compile error.
2. **Keep intercepting, name by name** (what shipped). Cost: one parser arm per
   colliding builtin, at two sites each, and the intercept must re-implement
   "does a user `def` shadow this?" every time (today: `ProcUnitIdx = -1`).
   Benefit: the builtin means the same thing no matter what is imported, which
   is arguably the right answer for a NilPy program.
3. **Rule: NilPy builtins win over used units.** In NilPy mode, resolve a name
   in the Python-builtin set against pylib FIRST, falling back to unit routines
   only when no pylib arm fits — the "own language first" principle this repo
   already applies to name resolution, extended to builtins. Removes the whole
   class at once. Cost: needs the builtin set to be explicit (a marker on
   pylib's exports, not a name list in the parser), and a Pascal routine
   deliberately called from `.npy` under a builtin's name becomes unreachable.

## Recommendation

**1 for the mechanism, 3 for the rule, and they compose.** Fix the merge defect
regardless — it is a defect. Then let the builtin set win by rule rather than by
uses order, because "which unit was used last" is not a meaning a program should
depend on; option 1 alone leaves the answer to overload ranking across two
languages' conventions, which is where a silently wrong result would come from.
Option 2 is the honest stopgap and is already in place for `format`; nothing
breaks if this ticket sits.

The question for the user is really: **should a `.npy` be able to reach a Pascal
routine whose name is a Python builtin at all?** If yes, option 1 alone. If no,
option 3 is simpler and safer.

## Gate (whichever is chosen)

`format(7.5, ".1f")` correct with and without `import json`; `Format(fmt,
[args])` still correct from Pascal; a `.npy`'s own `def format` still shadows;
`min`/`max`/`len`/`sum`/`sorted` unchanged under all three imports.
