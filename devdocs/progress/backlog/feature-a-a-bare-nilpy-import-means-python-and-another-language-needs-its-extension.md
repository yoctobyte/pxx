---
track: A
prio: 78
type: feature
blocked-by: []
summary: "DECIDED 2026-08-19. A bare NilPy import resolves to Python only (.py/.npy); another language needs an explicit extension (math.pas, math.c); a residual collision is solved by `import ... as ...`. Two whitelists carry it: the language-extension set, and the lib/rtl units that ARE a Python module (re, io, math, json, random). Fixes `from classes import Foo` failing with a message about `Delete` inside a Pascal unit the program never mentioned."
---

# A bare NilPy import means Python; another language needs its extension

**Implements [[decide-nilpy-imports-that-collide-with-a-pascal-rtl-unit]], decided by the
user 2026-08-19.** Filed as work because a decided ticket that is never re-filed is invisible
to `ready`/`next` and gets rediscovered — read the decision ticket before this one; it
carries the scope finding and both whitelists.

**Track A, not N:** the resolution machinery is in the shared `parser.inc`
(`ParseUsesUnit`, the `mimic_` prefix path at ~33743/34554/34576) and `lexer.inc`, so this is
shared-internals ground even though the semantics are NilPy's. Obeys A's gate and the
no-concurrent-edit rule with P.

## MEASURED PRECONDITION — the extension spelling does NOT exist yet, except in C

**Checked on pin v361 (`d1fc7394d348b14866e60cd458044121`) before dispatching any work,
because the plan assumed it already worked.** It works in exactly one of the three:

| spelling | result |
| --- | --- |
| **C** `#include "./lib2.c"` | **WORKS** — compiled, linked, ran, printed 42 |
| NilPy `import mymod.pas as m` | **fails**: *"no unit named mymod_pas and no shim mimic_mymod_pas"* — the dotted form is underscore-mangled as a package path |
| NilPy `import sysutils.pas as su` | same failure |
| Pascal `uses 'mymod.pas';` | **fails**: *"unit source not found"*, even for a local file that exists |
| Pascal `uses mymod in 'mymod.pas';` | **fails to parse** — the FPC/Delphi `in` spelling is not accepted |

> **CORRECTION, same day, and it shrinks this ticket: Pascal ALREADY HAS a working
> extension-bearing cross-language import. My first measurement omitted `as` and I read the
> deliberately-unbound case as "unsupported".**
>
>     uses './mymod.pas' as m;   ->  ok, m.Twice(21) prints 42
>     uses './lib2.c'    as c;   ->  ok, c.twice(21)  prints 42   (cross-language!)
>
> This shipped **2026-06-30** as `feature-uses-alias-as`, and
> `decided/decide-cross-language-qualifier-syntax` (2026-08-16) records the design: the
> alias maps to the REAL unit's `Strs[]` index, which is what lets it reach foreign symbols.
> **Bare `uses './x.c'` without `as` stays unbound DELIBERATELY** — so the failure I
> originally measured was the designed behaviour, not a gap. I checked the unquoted spelling
> and reported the feature missing.

**So the corrected picture is:**

| spelling | result |
| --- | --- |
| C `#include "./lib2.c"` | **works** |
| Pascal `uses './mymod.pas' as m;` | **works** |
| Pascal `uses './lib2.c' as c;` | **works** — cross-language, already |
| Pascal `uses 'mymod.pas';` (no `as`) | unbound **by design** |
| Pascal `uses mymod in 'mymod.pas';` | not supported — see [[feature-p-uses-a-unit-in-an-explicit-file]] |
| **NilPy `import mymod.pas as m`** | **fails — this is the only real gap** |

**Two languages of three already have it.** This ticket is therefore *"give NilPy the
equivalent of a spelling Pascal and C already ship"*, not *"invent a cross-language import"*.

**Two consequences, and they change the plan:**

1. **This ticket must BUILD the NilPy extension spelling.** It is not "add two whitelists to
   an existing resolver". Rule 2 is the escape hatch that makes rule 1 acceptable, and the
   escape hatch does not exist yet. The dotted form currently mangles `a.b` to `a_b`, so the
   language-extension whitelist has to be consulted *before* that mangling, not after.
2. **The test rewrite CANNOT be done as parallel prep.** It is strictly downstream of (1) —
   there is no spelling to rewrite the tests INTO today. See the test survey below.

**Open question for whoever takes this, not settled here:** whether Pascal's `uses` should
gain the same explicit-extension spelling. Nothing in the decision requires it, and no ticket
asks for it. Do not build it speculatively; note it if a caller needs it.

## TEST SURVEY — three tests, and none of them are the ones expected

Also measured, and it is smaller and different from the "21 tests" figure quoted earlier
(that count was every `.npy` importing any of the eight colliding names — almost all of them
population 1, which must keep working untouched).

**No `.npy` imports `classes`, `types` or `strings`.** The population-2 names have **zero**
test dependency, so nothing needs rewriting on their account.

**The only tests reaching a genuinely-Pascal unit by bare name import `sysutils`:**

    test/test_nilpy_import_does_not_publish_names.npy:49   import sysutils as su
    test/test_nilpy_pyexception_bare_vs_qualified.npy:21   import sysutils as su
    test/test_nilpy_rtl_exception_surface.npy:11           import sysutils as su

All three already use the alias form, so the rewrite is mechanical — `import sysutils.pas as
su` — **once the spelling exists.** They are exception-surface tests deliberately reaching
Pascal's RTL, i.e. exactly the legitimate case rule 2 is meant to serve. Note also that
`sysutils` is NOT one of the eight names in the decision ticket; the collision class is
broader than the survey that found it.

## SPELLING — worth one user decision before building, because precedent points elsewhere

The decision names the form `math.pas` (dotted). The **already-shipped** Pascal spelling is a
**quoted path plus `as`** (`uses './mymod.pas' as m`). Mirroring that in NilPy —
`import './sysutils.pas' as su` — has three advantages that were not visible when the dotted
form was chosen:

- **It removes the package-submodule ambiguity entirely**, so the language-extension
  whitelist is not needed at all: a quoted string can never be confused with
  `import xml.dom`. (The whitelist for *which `lib/rtl` units are Python modules* is still
  needed — that half is unaffected.)
- **It matches the convention already in the language**, decided and shipped, rather than
  adding a second cross-language import syntax with different rules.
- **It carries a path**, which the dotted form cannot — and paths are how the C side already
  disambiguates two same-named units.

Against it: `import './sysutils.pas' as su` is not a spelling CPython would accept, whereas
`import sysutils.pas` at least *looks* like Python. Both are already outside CPython, so this
is a taste question about which non-Python spelling to use, not a compatibility one.

**Not settled here.** Build the dotted form as decided unless the user says otherwise; this
section exists so the choice is made knowing the precedent, since the precedent was unknown
when the fork was answered.

## The rule

1. **A bare, extensionless import is PYTHON** — `.py` or `.npy` only.
2. **Another language needs an explicit extension** — `math.pas`, `math.c`. This is what
   makes a Pascal or C unit reachable from NilPy at all, and it is the escape hatch that
   made this preferable to simply refusing the collision.
3. **`import ... as ...` resolves a residual collision** — importing both `math.pas` and
   `math.c` leaves `math.xyz` ambiguous; the alias answers it. No new syntax.

## The two whitelists

- **Language extensions:** `pas`, `c` (later `zig`, `rs`). A trailing dotted component in
  this set selects a language; anything else stays a Python submodule, so `import xml.dom`
  is unaffected.
- **`lib/rtl` units that ARE a Python module:** `re`, `io`, `math`, `json`, `random` —
  reachable by bare name. `classes`, `types`, `strings` are NOT on it and become unreachable
  by bare import, which is the bug being fixed.

**Do not rename the whitelisted units into `mimic_*`.** The user chose a list over a rename
specifically so the 21 existing `.npy` tests that import these names do not churn.

## What this fixes

    from classes import Foo
    -> error: no overload of Delete matches these arguments

A message naming a symbol inside a Pascal unit the program never mentioned, with no path
back to the import. Also `from types import ModuleType`, which binds to `lib/rtl/types.pas`
and fails one token right.

## Acceptance

- The three population-2 names (`classes`, `types`, `strings`) refuse a bare import with a
  message naming the collision and the extension spelling that would reach the Pascal unit.
- **The 21 `.npy` tests importing `math`/`re`/`json`/`io`/`random` pass unchanged.** A test
  rewrite is correct for the population-2 shape and is a REGRESSION if applied here.
- `import math.pas` reaches the Pascal unit; `import xml.dom` still means the submodule.
- The whitelist's definition site says that adding a new Python-serving unit to the list is
  part of writing it — otherwise a bare import silently stops resolving, far from the cause.

## Gate

Track A's: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick`. NilPy is paused
under the backlog-shrink push, so schedule this when the pause lifts or when A's queue
reaches it — the decision is recorded either way.

## Log
- 2026-08-19 — filed from the user's decision.
