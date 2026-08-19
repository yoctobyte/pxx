---
track: A
prio: 78
type: feature
blocked-by: []
summary: "DECIDED 2026-08-19. A bare NilPy import resolves to Python only (.py/.npy); another language needs an explicit extension (math.pas, math.c); a residual collision is solved by `import ... as ...`. Two whitelists carry it: the language-extension set, and the lib/rtl units that ARE a Python module (re, io, math, json, random). Fixes `from classes import Foo` failing with a message about `Delete` inside a Pascal unit the program never mentioned."
status: working
owner: frank3
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

## SPELLING — SETTLED by the user, 2026-08-19

> **"The dotted form is optional and only if we can do that safe. If quoted names are needed
> it's not really an issue. This may be language dependent."**
>
> **So: the QUOTED form is the baseline and is sufficient.** `import './sysutils.pas' as su`
> — matching the Pascal `uses './x.pas' as m` that already ships — satisfies the decided rule
> on its own. Build that.
>
> **The dotted form (`import math.pas`) is OPTIONAL, and gated on being safe.** It is a
> convenience on top, not the requirement. If making it unambiguous against Python's
> package-submodule syntax costs a whitelist of language extensions that can misfire on a real
> package with a submodule named `c` or `pas`, **that is a reason not to build it**, not a
> problem to engineer around. Ship quoted; add dotted only if it falls out cleanly.
>
> **And the answer may differ per language** — the user said so explicitly. Do not force one
> spelling across NilPy, Pascal and C for symmetry's sake. Pascal already has quoted+`as`; C
> already has `#include "./x.c"`. NilPy matching the quoted convention is consistency with the
> repo, not a compromise.
>
> **This removes the language-extension whitelist from the required work.** A quoted string
> can never be confused with `import xml.dom`, so that half of "it's a matter of whitelisting"
> is only needed *if* the optional dotted form is built. **The other whitelist — which
> `lib/rtl` units ARE Python modules — is unaffected and still required.**

### Original fork, kept for the reasoning (superseded by the above)

#### SPELLING (as raised)

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

## 2026-08-19 (frank3-etree, before standing down) — two hazards banked for this refactor

Not about import spelling; about the *shape* of resolution code. Both were paid
for elsewhere today and import resolution is dense in exactly these.

### 1. A derived discriminator is correct only while a coincidence holds

Fixing the scientific float writer (`354f734c1`), five backends decided *"does
this writer take arguments?"* by testing `decs >= 0`. That was exact **only
because** two different writers happened to be called with `-1`. The moment one
of them carried real arguments the inference was wrong — and wrong *identically
in all five backends*, from one shared assumption. The first attempted fix
(`decs <> -2`) would have shipped it.

> **A derived discriminator that happens to be correct is indistinguishable from
> one that is correct by construction, until the thing it was derived from
> changes.**

The fix was an explicit flag that **records** the fact rather than re-deriving
it. Import resolution is full of this shape: "is this a Python module?" derived
from the absence of an extension, "is this ours?" derived from a path prefix,
"is this already pulled?" derived from a name match. Each is a proxy standing in
for the real question, correct until a new spelling makes the proxy and the
question disagree. Prefer a recorded fact.

`PyImportRootIsConsumedOnly` is already a live instance —
[[bug-n-from-collections-abc-import-is-swallowed-by-the-collections-root-rule]]:
it tests the **root** of a dotted from-import as a proxy for "do we support this
module", which was fine until a real submodule shim existed. Its own comment
states the assumption that broke (*"an unsupported name walls visibly at its use
site"*), and the failure is now silent instead.

### 2. A clean rebase is not a working build

`git rebase` reports that it placed the hunks. It does not report that the
result compiles or behaves — and a sibling's change can be textually distant
from yours while being semantically entangled (a signature, a registration
table, a shared predicate). Rebuild and re-run one probe after every rebase in
this refactor; a signature change plus a pre-registration in a second file is
exactly the pattern that merges cleanly and then does not work.

That two-places-must-agree pattern is not hypothetical here: the float fix
needed `PXXWriteFloatSci`'s definition **and** its pre-registration in
`parser.inc` to change together, and either alone fails — the emitter half
looks like the whole story until the other half bites.

## THE FAILURE MODE TO EXPECT HERE — an import resolver is made of proxies

Added 2026-08-19 from frank3's closing note, because it is aimed at *this* ticket rather than
at the day it came from. Six failures in one session reduced to one shape:

> **Every failure was a mechanism reporting on something ADJACENT to what was actually asked.**
> `; echo` reported the echo, not the suite. `grep FAIL` matched the assertions that check for
> FAIL. `pgrep -f` matched its own command line and killed the run it had just launched.
> `git add <paths>` reported intent while the index held a peer's changes. `git rebase`
> reported text placement, not behaviour. `decs >= 0` reported a coincidence, not a fact.

**An import resolver is made almost entirely of predicates like these**, so this is the
*default* failure mode in this ticket, not an exotic one. Live instances already in this lane:

- `PyImportRootIsConsumedOnly` tested only the **root** of a dotted path, so `collections` on
  a list swallowed `from collections.abc import Mapping`. Fixed by testing the full path.
- The eight `lib/rtl` collisions exist because "a unit with this name exists" was standing in
  for "this unit IS the Python module" — the whole reason this ticket exists.
- `ProcUnitIdx[mpi] >= 0` ("lives in a unit") once stood in for "is a Pascal library facade",
  silently substituting `None` for declared defaults across every cross-module call.

**So when adding the whitelists, prefer a RECORDED fact over a derived one.** The whitelist is
itself the recorded form — that is its main virtue, more than the behaviour it selects. A
derived predicate that is correct today is indistinguishable from one correct by construction,
right up until its premise changes.

**And one mechanical hazard specific to this change**, hit by the float-writer fix earlier the
same day: **a signature and its pre-registration can live in different files, textually distant
enough to merge cleanly and then not work.** `PXXWriteFloatSci` was pre-registered in
`parser.inc` with one parameter while the emitter passed three. A clean rebase means git placed
the hunks — not that the result compiles or behaves. Rebuild and re-run the probe after any
rebase in this area.


---

## PLAN (frank3, 2026-08-19) — measured before writing, parser.inc not yet touched

Written while frank2 holds the A/P slot. Everything below is read/measure only; no
`lexer.inc` / `parser.inc` edit has been made.

### FINDING 1 — the Python-serving whitelist is ~15 units, not the decision's five

The decision names `re io math json random` as the units that ARE the Python module. That
list is **illustrative, not complete**, and shipping it verbatim would silently break six
imports that work today. Measured by intersecting every `lib/rtl/*.pas` unit name (109) with
every bare `import`/`from` root across `test/`, `lib/`, `examples/`:

    ast  atexit  collections  configparser  html  io  json  math  pathlib  random  re  sysutils  tempfile

and by scanning all 109 unit headers for a Python-serving claim, which adds three more that
nothing in-tree imports yet — `base64`, `markdown`, `subprocess` — each stating *"named so
that Python's `import X` resolves here"*.

**Header prose is NOT the discriminator** — it is wrong in both directions, which is the
whole reason this has to be a recorded list:

| unit | header says | truth |
| --- | --- | --- |
| `math`, `json`, `random` | a Pascal math / JSON-tree / entropy library | **serves Python** (decision) |
| `sysutils` | mentions NilPy exception roots | **genuinely Pascal** — population 2 |
| `collections` | "a generic growable list backed by `array of T`" | must **keep resolving** — see below |

`collections` is the subtle one. `from collections import Counter` never reaches the resolver
(`PyImportIsConsumedOnly`), but **plain `import collections` deliberately does** — the comment
on `PyImportRootPlainIsConsumedOnly` says so in as many words: *"`import collections` must keep
reaching the resolver so a `collections.Sym` qualifier has a unit to resolve against"*, and
`test_nilpy_import_spellings.npy:22` exercises it. So it goes on the list even though its
header is pure Pascal.

**Proposed list** (bare NilPy import keeps reaching the Pascal unit):

    ast atexit base64 collections configparser html io json markdown math pathlib random re subprocess tempfile

**Population 2, bare import stops resolving:** `classes`, `types`, `strings`, `sysutils`, and
the other ~90 `lib/rtl` units. Of these only `sysutils` is imported by any test — the three
already-aliased ones the survey found — and they are the rewrite.

### FINDING 2 — `isNilPy` is the WRONG discriminator, and this is the ticket's own failure mode

The obvious guard is "if this is a NilPy compilation, skip the `.pas` lookups". It is wrong,
and wrong in the silent direction: **`isNilPy` is true for the WHOLE compilation**, including
the nested `uses` of every Pascal RTL unit dragged in behind a NilPy program. `lib/rtl/re.pas`'s
own `uses sysutils` would be blocked by rule 1 and the failure would land nowhere near an
import statement. (`compiler/parser.inc:12507` and `:6180` both carry this warning already.)

`NilPyUserCode` (`symtab.inc:25`, `isNilPy and ((CurrentUnitIdx < 0) or PyExprMode)`) is also
wrong, in the other direction: it is false while parsing an imported `.py` module, whose own
imports are just as Python as the main program's.

Neither predicate answers the question actually being asked, which is **"did this `uses` come
from a NilPy `import` statement?"** That is a fact about the call site, so it gets **recorded
at the call site**, exactly as `PyDottedImport` already is — this is the ticket's own
prefer-a-recorded-fact rule applied to its first design decision.

### THE DESIGN — one recorded discriminator, three arms

A new global `PyImportLang` (defs.inc), set by the NilPy import parser and **claimed-and-cleared**
at the top of `ParseUsesUnitBody` exactly like `PyDottedImport`, so a nested unit parse cannot
inherit it:

| value | set by | resolution |
| --- | --- | --- |
| `''` | anything that is not a NilPy `import` statement (Pascal `uses`, C `#include`, the ambient/auto uses, the `mimic_` re-entry) | **unchanged, byte for byte** |
| `'py'` | a bare NilPy `import X` | `.py`/`.npy` + host headers + `mimic_` only. The `.pas`/`.pp` chain runs **only if `PyRtlUnitServesPython(lo)`** |
| `'pas'` / `'c'` | a quoted NilPy `import 'x.pas'` | that language's chain only; the Python probes are skipped |

All six user-import call sites in `pyparser.inc` (33276, 33296, 33334, 33382, 33446, 33669) go
through one thin wrapper that sets the flag, so the fact is recorded in one place rather than
six. The internal `ParseUsesUnit('math')` at `pyparser.inc:34552` and the two
`ParseUsesUnitAmbient` calls deliberately do **not** set it.

**Deliberate narrowing, stated so it is not mistaken for an oversight: rule 1 blocks the
`.pas`/`.pp` chain only, NOT the host C headers.** `import sqlite3` / `import stdlib` reaching
`/usr/include` is a designed, tested NilPy feature (`test_nilpy_import_sqlite`,
`test_nilpy_c_pointer`) and its probe already runs last, after everything Python-shaped. Rule 1
is about the collision the ticket names; widening it to C headers is a separate change nobody
asked for.

### THE QUOTED FORM — and the one detail the settled spelling leaves open

`import './mymod.pas' as m` maps onto the `isPath` branch that already exists and is what
Pascal's shipped form uses. But **`isPath` is keyed on containing a `/`**
(`parser.inc:34027`), and a path is resolved authoritatively against `CurUnitDir` with **no
search chain** — so the quoted form alone cannot reach `lib/rtl/sysutils.pas`, which is
precisely what the three tests needing the escape hatch have to reach. `import
'../lib/rtl/sysutils.pas' as su` would be CWD-fragile nonsense.

So the quoted form gets two shapes, split on the slash — a distinction the resolver already
draws:

- **with a slash** → today's authoritative path, unchanged: `import './mymod.pas' as m`
- **without a slash** → a *unit name carrying an explicit extension*, resolved through the
  normal search chain with the language pinned: `import 'sysutils.pas' as su`

The second is what makes the escape hatch usable, and it stays unambiguous for the same reason
the whole quoted form does — it is a string literal, so it can never collide with
`import xml.dom`. Default binding is the base name (`sysutils`); `as` overrides. Noting rather
than asking: Pascal's *unquoted* `uses 'x.pas'` is unbound by design, but that is about
Pascal's `uses`, and the user has said the answer may be language-dependent.

**The dotted form is NOT being built.** It is optional and gated on being safe, and the only
way to make it safe is the language-extension whitelist that can misfire on a real package with
a submodule named `c` or `pas` — which the user named as a reason not to build it. Nothing is
lost: the quoted form satisfies the decided rule on its own.

### ORDER OF WORK — each piece lands and pushes on its own

1. **`PyRtlUnitServesPython` + the flag plumbing, behaviour unchanged.** The whitelist function
   with its definition-site rule (*adding a new Python-serving `lib/rtl` unit to this list is
   part of writing it — otherwise a bare import silently stops resolving, far from the cause*),
   the `PyImportLang` global, the claim-and-clear, the pyparser wrapper. Nothing reads the flag
   to change resolution yet. Provable no-op: fixedpoint + quick.
2. **The quoted form** (`'x.pas'` / `'./x.pas'` / `'x.c'`), with a new test. This is the escape
   hatch and must exist before rule 1 can take anything away.
3. **Rule 1** — the `.pas` chain gated on the whitelist for `PyImportLang='py'`, with a
   diagnostic that names the collision *and* the quoted spelling that reaches the Pascal unit.
4. **Rewrite the three `sysutils` tests** to `import 'sysutils.pas' as su`, plus a new test for
   the `classes`/`types`/`strings` refusal.

Step 1 is the risky-looking one and is a provable no-op; step 3 is the only step that changes
an existing resolution, and by then the escape hatch is in and tested.

### RISKS I am carrying deliberately

- **The whitelist is a judgement call about ~15 units.** Measured, not derived — but a unit
  nobody imports in-tree (`base64`, `markdown`, `subprocess`) is on it on the strength of its
  header alone. Wrong inclusion is invisible (status quo); wrong *omission* is a silent
  resolution failure, so the list errs inclusive.
- **`math` is auto-used by the NilPy driver** (`pyparser.inc:34552`) through a call that does
  not set the flag, so it is unaffected either way — but it is on the list regardless, because
  a user's `import math` must keep working.
- Rebuild and re-run one probe after every rebase in this area, per the hazard banked above.

### Gate

`make compiler/pascal26` (the fixedpoint) + the repro + `tools/gate.sh quick`. Push each step.
Track T sweeps the matrix. The three `sysutils` tests and the new ones get run individually —
not as a suite.
