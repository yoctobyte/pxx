---
track: A
prio: 60
type: bug
status: done
found: 2026-08-30
found-by: claude-A
owner: claude-A
---

# `@BodiedProc` passed as an ARGUMENT escapes the cdecl soundness reject and silently miscompiles

A bodied Pascal proc marked `cdecl` receives the **internal** convention (every
param in a GP register by position, >6 all-stack), while an indirect call
through a `cdecl` proc-type value marshals **true SysV** (floats in xmm0..7,
int and SSE classes counted independently). The two coincide only for <=6
integer/pointer params. `compiler/ir.inc` has a loud reject for the unsound
binding — but it is keyed on the **assignment** shape, `AN_ASSIGN` whose RHS is
`AN_PROCADDR`. Passing the same `@proc` as a **call argument** is a different
AST shape and is not checked.

Measured at `82c135761`, self-hosted binary `f2bfbb3c94a5`, clean tree:

```pascal
type TCb = function(a: Double; b: Integer): Integer; cdecl;
function MyCb(a: Double; b: Integer): Integer; cdecl;
begin Result := Trunc(a) + b; end;          { want 9 for (2.5, 7) }
procedure Take(f: TCb);
begin writeln(f(2.5, 7)); end;
```

| shape | result |
| --- | --- |
| `p := @MyCb` (assignment) | `error: ... by-value float parameter is not SysV-callable yet` |
| `Take(@MyCb)` (argument) | compiles clean, prints **4261032** |
| 8 integer params, argument shape | compiles clean, prints **1126281949** (want 36) |

Both halves of the reject — the by-value-float half and the `ParamCount > 6`
half — escape through the argument shape. Deterministic across runs. `4261032`
is `0x410268`, code-address-shaped, consistent with the callee reading `a` from
a GP register while the caller placed it in `xmm0`.

**The control that could have falsified this:** the same argument shape with two
*integer* params prints `9`, correctly. So this is the calling-convention
mismatch the reject describes, not function-pointer arguments being broken in
general.

## Not currently breaking anything in-tree

Every bodied `cdecl` proc in the tree is a GTK trampoline in `lib/pcl` with <=3
pointer params (`ControlClickTramp`, `TimerTramp`, ...), which sits inside the
range where the internal convention and SysV coincide. Real but not on fire.

## The pattern

**The reject is not a conservative wall with a feature behind it. It is a wall
with a door in it.** A guard calibrated to a SPELLING rather than a SHAPE, which
is the third instance of this class recorded on 2026-08-30 alone:

- `bug-a-the-abi-oracle-invariant-is-enforced-by-a-grep-that-cannot-fire` — an
  invariant whose declared check matched nothing on any tree, forever.
- `Patch8` in the rel8 census — a third spelling of a truncating byte store that
  a fix aimed at the two `Byte(` forms would have left untouched at all 21 call
  sites.
- this.

Worth naming, because a repo-wide sweep for guards keyed on one AST shape or one
source spelling is a real piece of work someone should eventually do.

## Fix

Subsumed by `feature-cdecl-bodied-sysv-prologue`: give bodied `cdecl` procs a
genuine SysV prologue on x86-64, after which both shapes are sound and the
reject is obsolete rather than incomplete. Filed separately because a silent
wrong value needs its own slug for tstate and regression citation, because
"fixed as a side effect of a feature ticket" is invisible to anyone searching
the symptom, and because if that feature slips this must not slip with it.

Gate: the repro above prints `9` and `36`.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
