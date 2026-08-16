---
track: C
prio: 55
type: bug
blocked-by: []
summary: "A C function DEFINITION whose name matches a Pascal intrinsic (`sqrt` `exp` `ln` `sin` `cos` `arctan`) binds to the Pascal proc entry via case-insensitive FindProc and overwrites its BodyAddr. The Pascal implementation then becomes unreachable by ANY spelling — bare `Sqrt`, `math.Sqrt` and `cmath.sqrt` all return the C body — so a C file silently replaces the RTL's math for the whole program. This is what the ten `__crtl_*` prefixes in lib/crtl exist to dodge."
---

# A C definition of an intrinsic name overwrites the Pascal routine, unreachably

Found 2026-08-16 while measuring
[[feature-a-own-language-first-symbol-resolution]] at HEAD. Filed separately
because it is a **silent wrong value from the RTL**, not a resolution-precedence
design question — the compat escape rule in `CLAUDE.md` promotes exactly this to
a `bug-` ticket in the owning lane.

## The boundary, measured

Every row is one four-line program plus a C file whose function returns a
sentinel. `cmath` is `uses './x.c' as cmath`.

| Pascal side | bare call | `unit.Name` | `cmath.name` |
| --- | --- | --- | --- |
| a user unit's `Cube` vs C `cube` | **27 — Pascal** | 27 | 999 |
| math's `Tanh` vs C `tanh` | **0.7616 — Pascal** | 0.7616 | 55.0 |
| math's `Sqrt` vs C `sqrt` | **42 — C** | **42 — C** | `undefined variable (sqrt)` |
| math's `Exp` vs C `exp` | **42 — C** | **42 — C** | `undefined variable (exp)` |

Rows 1-2 are correct in all three columns, and row 1 is **order-independent**
(`uses pcube, './x.c'`, `uses './x.c', pcube`, with and without `as`) — so
cross-language resolution is already own-language-first for ordinary units, and
the alias escape already works. Rows 3-4 are the defect, and it is confined to
the six names the auto-pull scan treats as intrinsics (`parser.inc:34716`):
`sqrt`, `exp`, `ln`, `sin`, `cos`, `arctan`.

`math.pas` itself is NOT damaged — `SqrtSoft(16.0)` still returns 4.0 in the same
program where `Sqrt(16.0)` returns 42.0. Only the `Sqrt` proc ENTRY is hijacked,
which is why both the bare and the `math.`-qualified spelling follow it.

## Mechanism

`cparser.inc:9401`, on a C function with a BODY:

```pascal
procIdx := FindProc(name);          { spans C and Pascal, case-insensitively }
...
Procs[procIdx].BodyAddr := CodeLen; { :9558 — overwrites the Pascal routine }
```

`FindProc` is case-insensitive and spans namespaces, so C's `sqrt` lands on
Pascal's `Sqrt`. Same arity and both sides float, so neither guard fires — the
arity rung (`CCrossNamespaceArityMismatch`) and the float-class rung both pass —
and the C body is installed into the Pascal entry.

The cross-namespace bind itself is **deliberate and must stay**: the comment at
`:9448` records that lua's `<math.h>` `sqrt`/`sin`/`cos` resolve to the RTL math
routines that way. But that is the DECLARATION case (a prototype, no body). A
definition is a different claim: it says *this translation unit provides the
function*, and it should get its own proc in its own unit rather than
overwriting someone else's.

Rows 1-2 escape only because their Pascal counterpart is reached through a
path that does not collide this way (row 2's `Tanh` has no intrinsic entry to
land on), not because anything checks the language.

## Why this is the blocker for the de-prefix acceptance test

`lib/crtl/src/math.c` deliberately misnames ten functions — `__crtl_exp`,
`__crtl_log2`, `__crtl_log10`, `__crtl_sin`, `__crtl_cos`, `__crtl_tan`,
`__crtl_sinh`, `__crtl_cosh`, `__crtl_tanh`, `__crtl_hypot` — with the reason in
the source: *"that name collides case-insensitively with Pascal Exp (two
definitions -> silently broken call binding)"*.

Those `#define`s are the workaround for THIS bug. So
[[feature-a-own-language-first-symbol-resolution]]'s acceptance test (de-prefix
the ten, delete the `#define`s in crtl's `math.h`) cannot pass until a C
definition stops overwriting the Pascal entry. That ticket's own measurement
(2026-08-14) found the C -> Pascal direction closed and concluded the prefixes
were "probably vestigial" — that holds for a C program compiled alone, and this
row is the case it did not cover: a MIXED program, where the Pascal side is
still live.

## Suggested shape (not prescriptive — Track C owns the file)

Split the definition case from the declaration case at `cparser.inc:9401`: when
the C function has a body, do not accept a `FindProc` hit that landed on a proc
of another language / another unit — register a fresh proc in the C unit
instead. That is also what makes `cmath.sqrt` resolve, since the qualified
lookup (`MatchProcCallInUnit`) needs a proc whose `ProcUnitIdx` IS the C unit,
and today none exists.

There is no `ProcLang` parallel array yet;
[[feature-a-own-language-first-symbol-resolution]] notes one is needed and that
`ProcCdecl` is the wrong instrument for it (it is a calling-convention decorator
and a Pascal routine may carry it). If this fix needs the language tag, that
array is a Track A change — file it rather than deriving the language from
`ProcCdecl`.

## Repro

```pascal
{ cm.c:  double sqrt(double x) { return 42.0; } }
program p; uses math, './cm.c' as cmath;
begin
  WriteLn(Sqrt(16.0):0:4);        { 42.0000 — want 4.0000 }
  WriteLn(math.Sqrt(16.0):0:4);   { 42.0000 — want 4.0000 }
  WriteLn(SqrtSoft(16.0):0:4);    {  4.0000 — math.pas is intact }
end.
```

## Gate

C tests green + `make test` + self-host byte-identical. Add a positive test for
all four rows of the table above (the two correct ones are the must-not-regress
controls — they are what proves the fix did not disturb the deliberate
declaration-side cross-bind that lua depends on).
