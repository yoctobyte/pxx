---
track: C
prio: 50
type: feature
blocked-by: [bug-c-definition-of-an-intrinsic-name-overwrites-the-pascal-routine]
summary: "Give C an explicit import site for a Pascal unit: `#include \"math.pas\"` declares its routines under mangled C identifiers (`math_pas_Sqrt`), case preserved from the Pascal declaration, path-qualified on collision. Overloads resolve by the declared C signature. AnsiString-bearing signatures are refused by name. Design settled by the user 2026-08-19; this ticket is a SPEC, not a discussion."
status: working
owner: frank2-C
---

# C imports a Pascal unit under a mangled name

- **Track C** — C frontend files (`cparser.inc`, `cpreproc.inc`, C tests). Shared compiler
  internals stay Track A: a new AST node / IR op / symtab field → **file a Track A ticket**,
  do not edit under C.
- **Design settled by the user, 2026-08-19.** Every fork below was raised and closed in
  conversation. Do not reopen them on a hunch; if a MEASUREMENT contradicts one, say so
  here and escalate rather than choosing differently.

## Why

Pascal-into-C is an **intended, existing** capability — a C file today reaches Pascal
routines through implicit, global, case-insensitive `FindProc` matching. What it lacks is
not permission but a **name**.

That namelessness is the actual defect, and it is expensive:

- C has a flat global namespace, and `math.Sqrt` is not valid C, so there is no spelling
  for "the `Sqrt` in unit `math`".
- The match is **case-insensitive** while C is a case-sensitive language, so `sqrt` and
  `Sqrt` are one name. `lib/crtl/src/math.c:43` carries the consequence as a standing
  coding rule: *"never write a wrapper that calls the Pascal twin from its C namesake
  (`double sqrt(double x){ return Sqrt(x); }`): `Sqrt` binds case-insensitively back to the
  C `sqrt` and recurses forever."* A language hazard prevented by remembering.

**Case sensitivity gives distinguishability; mangling gives identity.** Both are needed —
that distinction is the design's hinge, and it is the user's.

## THE SPEC

### 1. The import site is an include

```c
#include "math.pas"
```

Chosen over a `#pragma` deliberately: gcc tries to textually include Pascal source and
**dies loudly**. An unknown pragma is silently ignored, producing a file that compiles
elsewhere and behaves differently — the worst failure shape. Honest non-portability beats
silent divergence.

### 2. Names are mangled, case preserved

`<unit>_<ext>_<Identifier>` — `math.pas` exporting `Sqrt` gives **`math_pas_Sqrt`**.

- **Case is preserved from the Pascal DECLARATION.** This is what makes the mangled name
  unable to collide with C's `sqrt`, so the infinite-recursion hazard above stops being
  spellable rather than being remembered.
- The `_pas_` infix earns its place: `math.pas` and `math.c` would otherwise both mangle
  to `math_`.

### 3. Collisions are path-qualified

Two units named `math` under different `-Fu` roots mangle identically. Then the path
participates: `path_math_pas_Sqrt`.

**State this property in the user docs, because the file that breaks is not the file
someone edited:** the short form is valid only while the unit name is unique across the
search path. Adding a second `math.pas` anywhere on the path invalidates every C file
using the short form. That fails loudly at compile time as an undefined symbol, which is
acceptable — but it is surprising unless documented.

### 4. Overloads resolve by the declared C signature — NOT a fork

Raised as a hard problem and dissolved by the user: it is not one.

```c
extern double math_pas_Max(double, double);
```

The C prototype names the unit, the routine, **and** the signature, in syntax C already
has. Resolve `math` → `Max` → the `(Double, Double)` overload by ordinary signature
matching. Pascal and C scalar types map cleanly, so this is mechanical.

**No suffix scheme. No `_ii` mangling. Nothing new to spell.** A declaration that cannot
discriminate (K&R `extern double math_pas_Max();`) is refused by name rather than guessed.

### 5. Non-mappable types are refused by name

Pascal types with no C spelling — `AnsiString`, sets, variants, open arrays — make a
routine **not importable**. Refuse at the declaration site, naming the routine. Partial
importability is expected and fine: a unit may export twelve importable routines and two
refused ones.

**`AnsiString` specifically, and the reasoning matters more than the rule** (user):

- `PChar` → `AnsiString` is fine; Pascal already owns that conversion.
- `AnsiString` → C has **no correct answer**. Hand C the buffer and you have handed out a
  reference the refcount does not know about; copy it and nobody owns the copy. There is
  no third option, so refusing is the honest one.
- **Returning `AnsiString` is refused unconditionally** — worse than a parameter, because
  there is no caller-side reference keeping the buffer alive and no way for C to release it.

**Recorded, deliberately NOT built:** a **`const AnsiString` parameter** is genuinely safe
— the Pascal caller holds the reference across the call, so the refcount is stable for the
call's duration and C sees an ordinary `const char*`. It is safe *provided the library does
not retain the pointer*, which is unverifiable from our side. That makes it a future
explicit opt-in, never a default. Written down so nobody re-derives it as a discovery.

### 6. The bare name is an EXPERIMENT, not a decision

Open question: should implicit cross-namespace binding be removed once the mangled name
exists? Two mechanisms for one concept is the shape this repo's own rules warn about — the
second path is the one that stays broken.

**Do not decide this by reasoning. Measure it.** `cparser.inc:9448` defends the implicit
bind on one ground: *"lua's `<math.h>` `sqrt`/`exp`/`sin`/… resolve to the RTL math
routines."* That justification may be stale — `lib/crtl/src/math.c` now DEFINES `exp`
(:282), `log` (:341), `sin` (:644), `cos` (:656), `atan` (:724) and `sqrt` (:965) in C,
correctly-rounded, and `CPullCrtlForPrototypes` pulls that module when a C file declares
those prototypes.

**The experiment:** delete the cross-namespace declaration bind and build the C corpus —
lua, tcc, quickjs, zlib. If nothing breaks, it was never a breaking change and there is
nothing to weigh. **If something breaks, those failures ARE the spec for what must stay.**
Report the result; do not quietly keep or quietly remove it.

## Sequencing

**`bug-c-definition-of-an-intrinsic-name-overwrites-the-pascal-routine` (C, p55) lands
first** and is a hard prerequisite. It is correct regardless of every choice above: a C
**definition** must never overwrite a non-C proc's body (`cparser.inc:9401` finds it,
`:9558` overwrites `BodyAddr`). A definition claims *this translation unit provides the
function*; that is a different act from a declaration, and only the declaration case has a
justification.

It is also currently producing a **silent wrong value out of the RTL** — `Sqrt(16.0)`
returns 42.0 when a C file in the same program defines `sqrt`, and `math.Sqrt` follows the
hijacked entry, so the qualified spelling does not save you.

## Gate

Track C's: C tests green + self-host byte-identical + cross. Land only green; incremental
or behind a flag, never a long-lived branch. New C tests should cover: the short form, a
path-qualified collision, an overload selected by prototype, and each refusal (AnsiString
param, AnsiString result, K&R declaration) failing by name at compile time.

## Provenance

Designed in conversation with the user, 2026-08-19, against measured code rather than
recollection. The coordinator raised overloads as a fork (it is not) and initially argued
the implicit bind should simply be deleted (premature — Pascal-into-C is intended and
works; it is the naming that is missing). Both corrections are the user's and are why the
spec has the shape it has.

## Triage 2026-08-19 (Track D re-triage pass, pin **v364**)

**Genuine feature, still wanted, unchanged — and still correctly blocked.**
Measured against v364, after the import/uses work landed:

```c
#include "mymod.pas"
int main(void){ printf("%d\n", mymod_pas_Twice(21)); }
```
```
pascal26:1: error: stray token at top level (not a declaration): 'unit'
```

So `#include` of a `.pas` is still plain textual inclusion — the import site
this ticket specifies does not exist, and nothing about it landed incidentally.
Its `blocked-by`
(`bug-c-definition-of-an-intrinsic-name-overwrites-the-pascal-routine`) is
still open in `backlog/`, so the edge is live and the ticket is correctly out
of `ready`.

## Progress — 2026-08-19 (frank2-C)

Landed and self-host green: the `#include "<unit>.pas"` preprocessor marker
(`cpreproc.inc`), the pass-1 marker handler that runs `ParseUsesUnit`, mangled
lookup by FORWARD re-mangling out of `Procs[]` (never by splitting at `_pas_`,
which is ambiguous in both directions), prototype-selects-the-overload,
and the §5 non-mappable-type refusals.

Verified by hand against a scratch unit:

    use.c       mymod_pas_Twice(21)                             -> 42
    t_ovl2.c    extern double mymod_pas_Max(double,double)      -> 9.2   (picks the Double overload)
    t_redecl.c  identical redeclaration                         -> 9.25
    t_ovl.c     bare call to an overloaded name                 refused, names the fix
    t_ovl3.c    two conflicting prototypes for one name         refused (previously: silent 0)
    t_case.c    mymod_pas_twice                                 refused — case is significant
    AnsiString parameter                                        refused by name
    open/dynamic array parameter                                refused by name

**Not yet exercised: the AnsiString RESULT refusal.** The code is in place and
takes the same path, but it cannot be reached today — ANY Pascal unit whose body
touches a managed string dies at import with `compiler error: call to a runtime
stub that was never emitted`, before the C side ever names the routine. That is a
Track A gap in the C driver's stub emission, filed separately; the result refusal
is testable the day it is fixed.

Still open from the spec: §3 path-qualified collisions, §6 the bare-name
experiment (delete the cross-namespace declaration bind, build the C corpus,
report), real `test/` cases + Makefile recipe lines, and the missing-unit
diagnostic still speaking Pascal (`uses: unit source not found: nosuch`) at a C
author who wrote `#include "nosuch.pas"`.

## §3 and the `test/` cases — 2026-08-20 (frank2-C)

### §3 as specified is not implementable from Track C, and the reason is the finding

§3 says a collision is resolved by letting the PATH participate in the mangled
name (`path_math_pas_Sqrt`). Measured before writing any code, against pin v367:
two files, `r1/math.pas` and `r2/math.pas`, both `unit math`, `Twice` returning
`x*2` and `x*3`.

    #include "r1/math.pas"
    #include "r2/math.pas"
    math_pas_Twice(21)   ->  42        (r1's answer; the author asked for r2's 63)

**The second include is a silent no-op.** `CompiledUnits` (`defs.inc:2418`) is
keyed on the unit NAME, so the loader sees `math` already compiled and returns
without reading r2 at all. A routine present only in r2 does not merely resolve
to the wrong body — it falls through to the "crtl does not define ..." warning
and dies at link with `undefined symbol`.

So the two units never COEXIST, and a path-qualified mangled name would denote a
unit that was never loaded — there would be nothing for it to resolve to.
Making unit identity the FILE rather than the NAME is a change to the shared
unit table: **Track A ground**, and already an open question there
(`decide-one-answer-to-have-i-already-compiled-this-unit`, which
`parser.inc`'s own Python-module dedup cites). Not edited under C, per the lane
rule; escalated here rather than guessed at.

### What landed instead

`CCheckPascalUnitCollision` (`cparser.inc`, above `CParsePascalUnitMarker`):
turn the silent wrong value into a refusal that names both files.

    pascal26:9: error: two Pascal units are both named 'mymod':
      'test/cpasunit/mymod.pas' was imported first and 'test/cpasunit2/mymod.pas'
      cannot also be imported -- a unit's identity is its NAME here, so the second
      include would be silently ignored and every mymod_pas_* would resolve to the
      first. Rename one of the units

Keyed on the RESOLVED path run through `NormalizePath`, so the same file
included twice — including a spelling that differs only by a `./` — stays
allowed. Only when the include spelling is a PATH: a bare `#include "math.pas"`
is answered by the loader's `-Fu` search and this side never learns which file
won, so it records nothing and compares nothing. Reuses `CompiledUnitFile`
(`defs.inc:2429`) for its documented meaning ("the file this compiled unit
resolved to"); it was simply only written on the Python path until now. Nothing
declared, no shared structure changed, no `parser.inc` / `pyparser.inc` edit.

**Limit, stated plainly:** this refuses the collision, it does not resolve it.
Two same-named units still cannot be used from one program. That resolution is
the Track A question above.

### A real bug found by writing the tests

`#include "cpasunit/mymod.pas"` from `test/c_pasunit.c` looked for
`test/test/cpasunit/mymod`. The marker handler prepends the includer's
directory (C's rule), and the unit loader then prepends `CurUnitDir` again
(`parser.inc:33693`) — the same directory twice. It went unnoticed because every
hand-verification so far compiled the C file by an ABSOLUTE path, which takes the
loader's `name[1] = '/'` branch and skips the second prepend. The first
repository-relative test found it immediately.

Fixed in `CParsePascalUnitMarker`: climb back out of `CurUnitDir` with one `..`
per segment and let `NormalizePath` collapse the pair. An include written in a
header in another directory still lands where the C author meant.

### `test/` cases + Makefile recipe lines

`test/cpasunit/mymod.pas` (Twice, and Max overloaded on Integer/Double),
`test/cpasunit2/mymod.pas` (the same unit NAME, `Twice` returning `x*3`),
`test/cpasunit/strmod.pas` (an AnsiString-bearing routine beside an importable
one). Nine recipe lines in `test-core`, beside the existing `test_c_*` block:

| test | covers |
| --- | --- |
| `c_pasunit.c` | the short form (42) + the Integer overload picked by prototype (7) |
| `c_pasunit_ovl.c` | the Double overload of the SAME Pascal name (9.25) |
| `c_pasunit_twice.c` | one file included twice, once spelled `./` — allowed |
| `c_pasunit_collide_fail.c` | two files, one unit name — refused, names both |
| `c_pasunit_case_fail.c` | `mymod_pas_twice` does not reach `Twice` |
| `c_pasunit_ovl_fail.c` | bare call to an overloaded name — refused, names the fix |
| `c_pasunit_knr_fail.c` | K&R `extern double mymod_pas_Max();` — refused |
| `c_pasunit_two_overloads_fail.c` | two overloads in one .c — refused |
| `c_pasunit_ansistring_fail.c` | AnsiString parameter — refused by name |

The **AnsiString RESULT** refusal is still unreachable for the reason recorded
in the previous section (a unit whose body touches a managed string dies at
import in the C driver — a Track A stub-emission gap), so it has no test.

Gate: `make compiler/pascal26` (converged, 1 round) + all nine recipe lines
hand-run green + `tools/gate.sh quick` GREEN. Not pinned — the pin is the
coordinator's.

### Still open

- **§6, the bare-name experiment** — delete the cross-namespace declaration bind
  at `cparser.inc:9448`, build lua / tcc / quickjs / zlib, report what breaks.
  Untouched, and **it needs the user's say-so to run at all**: the measurement IS
  `make test-lua` / `test-zlib` / `test-quickjs` / `test-tcc`, and every one of
  those is refused for this lane by `.claude/hooks/no-full-suite.sh` (rule 1,
  `make test*`). The escape is `PXX_ALLOW_FULL_SUITE=1` "and only when the user
  has asked for it" — a coordinator cannot supply it, and hand-running the
  recipe bodies to get around the refusal would be reshaping a denied command.
  So §6 is parked on that, not on effort: it is one deletion plus four corpus
  builds, and whoever has the escape can do it in an afternoon.
- The **missing-unit diagnostic still speaks Pascal**: `#include "nosuch.pas"`
  answers `uses: unit source not found: nosuch`. The message is raised in
  `parser.inc` (Track A ground), and pre-checking the file in `cparser.inc`
  would have to duplicate the loader's case-insensitive + `.pp` + `-Fu` search
  to avoid refusing files that do exist. Left alone deliberately.
- `test/my_pas_lib.pas` is referenced by nothing — an unused leftover, not this
  feature's.
