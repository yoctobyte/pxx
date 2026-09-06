---
slug: bug-p-delphi-mode-binds-a-bare-routine-name-only-for-a-variable-target
track: P
prio: 45
type: bug
status: backlog
created: 2026-09-06
found-by: frankB
owner: ""
blocked-by: []
summary: "`{$mode delphi}` binds a bare routine name to its ADDRESS -- `f := G` -- but ONLY when the target is a plain VARIABLE. `r.f := G` (record field) and `a[0] := G` (array element) never reach that arm: it is keyed on the destination SYMBOL (`idx >= 0 and SymProcSig[idx] >= 0`), and for those two shapes `idx` is the BASE variable, whose SymProcSig is -1. fpc 3.2.2 -Mdelphi prints 7 for all three. On pin v404 the two unbound shapes compiled and SIGSEGV'd; since 2026-09-06 they are REFUSED with `a procedural slot cannot take the RESULT of a call -- write @G`, which is louder and still not what fpc does. Split out of bug-p-a-bare-function-name-assigned-to-a-procedural-variable-segfaults-outside-delphi-mode, whose subject is the DEFAULT-mode crash: that one is now fixed in all four spellings and this is the Delphi arm's own incompleteness."
---

# `{$mode delphi}` binds a bare routine name only for a variable target

## Measured 2026-09-06 against `fpc 3.2.2 -Mdelphi`, and on pin v404

```pascal
{$mode delphi}
type TF = function: Integer; TRec = record f: TF; end;
function G: Integer; begin G := 7; end;
var f: TF; r: TRec; a: array[0..1] of TF;
begin
  f := G;    WriteLn(f());      { fpc 7   pxx 7   -- the arm fires }
  r.f := G;  WriteLn(r.f());    { fpc 7   pxx: refused (pin: SIGSEGV) }
  a[0] := G; WriteLn(a[0]());   { fpc 7   pxx: refused (pin: SIGSEGV) }
end.
```

The argument spelling `Use(G)` is correct in Delphi mode and stays correct — it
reaches the binding by a different route (`TryDelphiBareProcArg` /
`MatchCallDelphiProcAddr`'s retry), so this is specifically about ASSIGNMENT
targets that are not a plain variable.

## Where it is, and the one-line shape of it

`pasparser_stmt.inc`, the `{$MODE DELPHI}` @-optional arm: both of its branches
are guarded on `(idx >= 0) and (SymProcSig[idx] >= 0)`, where `idx` is the
destination symbol. For `r.f := G` that symbol is `r` and for `a[0] := G` it is
`a`; neither is itself proc-typed, so the arm declines and the bare `G` falls to
`ParseExpr`, which reads it as a call.

**The fact the arm needs already exists**, and was written for the other side of
the same flag: `NodeProcSlotSig` in `ir.inc` answers "is this lvalue NODE a
procedural slot" for all three shapes (`SymProcSig` / `UFldProcSig` /
`SymElemProcSig`). It is in `ir.inc`, which is included AFTER the parsers, so
using it here means moving it — `symtab.inc`, beside `ResolveNodeRec`, which it
already calls.

`ProcResultSatisfiesTarget` is the other half and takes a `targetIdx: Integer`
symbol, reading `Syms[targetIdx].TypeKind` to separate a method-pointer target
from a plain procedural one. It needs the same node-keyed treatment, and the
kind is on the node (`ASTTk[valNode]`).

## Why this is filed rather than folded into the default-mode fix

Different arm, different direction, different risk. The default-mode fix is a
REFUSAL and its risk is refusing working code; this is a BINDING and its risk is
binding where FPC calls — which is exactly the trap
`ProcResultSatisfiesTarget` exists for (`m := MakeSel` must CALL, not take an
address). Doing both in one change would put a speculative widening on top of a
refusal, which is the compounding the first attempt at that ticket was reverted
for.

## What a fix has to satisfy

1. All three Delphi-mode targets print 7.
2. `m := MakeSel` (a paramless function whose result fits the target) still
   CALLS — the `ProcResultSatisfiesTarget` rule, now asked per node.
3. Default mode keeps refusing all four spellings; there is a wired test,
   `test_a_bare_routine_name_into_a_procedural_slot_is_refused`.
4. `test_delphi_mode_binds_a_bare_routine_name` keeps passing and grows the two
   new rows.
