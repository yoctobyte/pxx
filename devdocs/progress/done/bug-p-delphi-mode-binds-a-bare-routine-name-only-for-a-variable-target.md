---
slug: bug-p-delphi-mode-binds-a-bare-routine-name-only-for-a-variable-target
track: P
prio: 45
type: bug
status: done
created: 2026-09-06
found-by: frankB
owner: frankB
blocked-by: []
summary: "RESOLVED 2026-09-06. `{$mode delphi}` now binds a bare routine name to its ADDRESS for all three destinations -- plain VARIABLE, record FIELD and array ELEMENT -- in both the plain-procedural and the method-pointer branch; fpc 3.2.2 -Mdelphi agrees on 10 rows. Both arms were keyed on the symbol the STATEMENT OPENED WITH, so `r.f := G` asked about `r`; they ask PasNodeProcSig about the destination NODE now, which on an AN_IDENT returns exactly SymProcSig so the variable spelling is unchanged by construction. ProcResultSatisfiesTarget is split over a kind-keyed core, ProcResultSatisfiesKind, because the method-pointer vs plain-procedural distinction also came off that wrong symbol. THIS TICKET GOT ITS OWN REMEDY WRONG: it says the fact is NodeProcSlotSig in ir.inc and would have to be MOVED to symtab.inc, and PasNodeProcSig was already in pasparser_call.inc, which the statement parser already includes -- written for this exact class, whose own note says the question was answered spelling by spelling and only the first spelling was ever taught. I wrote the ticket an hour after writing the ir.inc helper and never looked for a parser-side twin."
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

## RESOLVED 2026-09-06 — the arm asks the destination NODE, and the fact was already in the right file

Test: `test_delphi_mode_binds_a_bare_routine_name`, grown from 3 rows to 10,
`fpc 3.2.2 -Mdelphi`'s own output byte for byte. All three targets — variable,
record field, array element — bind, in both the plain-procedural and the
method-pointer branch.

**THIS TICKET GOT ITS OWN REMEDY WRONG, AND THE ERROR IS WORTH MORE THAN THE
FIX.** It says the fact needed is `NodeProcSlotSig` in `ir.inc` and that using it
here "means moving it — `symtab.inc`, beside `ResolveNodeRec`". No move was
needed. **`PasNodeProcSig` already existed in `pasparser_call.inc`**, which the
statement parser already includes, answering exactly this question for
`AN_IDENT` / `AN_FIELD` / `AN_INDEX` — and its own note says it exists because
*"is this designator a procedural value?" was answered SPELLING BY SPELLING and
never node-keyed, so each spelling had to be taught separately and only the first
one ever was.* This site was one of the ones never taught.

I wrote this ticket an hour after writing `NodeProcSlotSig`, so that is the
helper I reached for, and I never asked whether the parser already had a twin.
**Having just built the tool makes you stop looking for the one already there** —
and the cost is not the wasted move, it is that the ticket sent the next reader
into `ir.inc` and `symtab.inc` for a change that belongs in neither.

**THE SHAPE OF THE FIX.** Both Delphi @-optional arms in `pasparser_stmt.inc`
were guarded on `(idx >= 0) and (SymProcSig[idx] >= 0)`, where `idx` is the
symbol the STATEMENT OPENED WITH. For `r.f := G` that symbol is `r` and for
`a[0] := G` it is `a` — neither is itself proc-typed, so the arm declined and the
bare `G` fell to `ParseExpr`, which reads it as a call. They now ask
`PasNodeProcSig(valNode)`, the destination node. On an `AN_IDENT` that returns
exactly `SymProcSig[idx]`, so the variable spelling is unchanged **by
construction** rather than by measurement.

`ProcResultSatisfiesTarget` was the other half and took a `targetIdx: Integer`,
reading `Syms[targetIdx].TypeKind` to tell a method-pointer target from a plain
procedural one — the same symbol that is wrong here. It is now a thin wrapper
over `ProcResultSatisfiesKind(pi, targetTk)`; the kind comes off `ASTTk[valNode]`
and the symbol-keyed spelling keeps working for its existing caller.

**ROWS E AND F ARE THE ROWS THAT SEPARATE THIS RULE FROM THE NEXT-WIDER ONE.**
`f := MakeCb` is a bare routine name too, and Delphi does **not** take its
address: `MakeCb` is a paramless function whose result FITS a procedural target,
so it is CALLED. A rule spelled *"a bare routine name in Delphi mode is its
address"* passes every other row in the file and fails exactly those two — and
failing them is not a diagnostic, it stores a code address where a value belongs.
Row F is the same test at a FIELD, because the kind now comes off the node and a
field is precisely where a symbol-keyed reading answers about the record instead.

**ROWS G, H AND I ARE THE METHOD-POINTER BRANCH**, which is a separate arm
(`procedure of object` is a 16-byte `Code`/`Data` pair record, `tyRecord`, not a
plain pointer). A fix that reached only the `tyPointer` branch passes A..F. All
three receiver-side spellings — variable, field, element — are asserted.

**WHAT THE DEFAULT MODE DOES IS UNCHANGED AND IS STILL ASSERTED SEPARATELY.**
`test_a_bare_routine_name_into_a_procedural_slot_is_refused` still counts 3 and 1.
This ticket was split out of that one deliberately, because the two run in
opposite directions — that one is a REFUSAL whose risk is refusing working code,
this is a BINDING whose risk is binding where fpc calls — and stacking a
speculative widening on a refusal is what the first attempt at that ticket was
reverted for. Landing them as two commits, refusal first and green, is what made
the binding cheap: it had a wired negative test standing behind it the whole time.

**One incidental, and it is a property of the test harness rather than of pxx.**
The previous version of this file could not have been run through fpc **in the
mode it declares**: its header comment contains a literal `{$mode delphi}`, and
under `-Mdelphi` comments do not nest, so fpc closed the comment at that `}` and
reported `Fatal: Syntax error, "BEGIN" expected but "identifier BINDS" found`.
pxx accepted it. **A test whose ORACLE cannot read it has no oracle**, and this
one's three rows had been asserted against pxx's own output. The directive is
spelled without braces in prose now, and all ten rows come from fpc.

**CORRECTION, AND IT IS THE INTERESTING HALF.** The sentence above originally
read "Pascal comments do not nest, so fpc could never compile the file", with no
mode qualifier, and that is FALSE as written — frank-coordinator measured the
same file compiling with `Warning: Comment level 2 found` and rc 0, and was
right. **Comment nesting in fpc 3.2.2 is MODE-DEPENDENT**: default and
`-Mobjfpc` nest `{ }` and merely warn; `-Mdelphi`, `-Mtp` and `-Miso` do not and
give the Fatal above. Two correct measurements disagreed because an unstated
parameter differed. The rule drawn from it (`6218e8bd7`): when a peer's
measurement contradicts yours on the same input, do not adjudicate the RESULT,
enumerate the PARAMETERS — **a test's own `{$mode}` is part of the invocation
its oracle must use**, and running the oracle in the default mode is running it
on a different language. Do not build a checker for this: the narrowed
population is ~10 files, several of them deliberate tests OF comment nesting.

**Gate:** `tools/gate.sh quick` with the tree DIRTY (FPC seed canary PASS; 16
rows PASS; the only RED is `pinned builds live lib/rtl`, frankZ's `8374118ec`
waiting on an owner-only pin). AND `PXX_ALLOW_FULL_SUITE=1 make test` — the
change is in the assignment statement path, which every Pascal program reaches.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit f919f0cb1.
