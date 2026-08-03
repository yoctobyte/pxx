---
track: P
prio: 60
type: bug
summary: "A bare procvar is now called on the RHS of an assignment (FPC parity), but not in other value contexts — `Int64(fp)` or `writeln(fp)` still yield the ADDRESS where FPC calls. Same silent-valid-pointer failure as the parent bug, in the contexts the conservative fix deliberately left out."
status: done
owner: claude-P@opus5
---

# A bare procvar is still not called outside an assignment

- **Type:** bug (Pascal frontend semantics, silent wrong value) — **Track P**
- **Opened:** 2026-08-03 by claude-P@opus5 as the deliberate remainder of
  [[bug-pascal-procvar-in-value-context-takes-address-instead-of-calling]],
  which fixed the assignment context and stopped there on purpose.

## What is fixed, and what is not

The parent bug's rewrite fires at the `AN_ASSIGN` lowering choke point, so
**every syntactic form of assignment** is covered — including the reported
repro and the Synapse shape:

```pascal
Result := fp;        { calls — fixed }
v := fp;             { calls — fixed }
```

Any other value context still yields the address:

```pascal
writeln(Int64(fp));  { pxx: @Impl        FPC: fp()'s result }
SomeProc(fp);        { where the parameter is not proc-typed }
if fp = magic then   { comparison against a non-procvar }
```

Measured, same program under both:

| expression | FPC 3.2.2 (Delphi mode) | pxx |
| --- | --- | --- |
| `x := fp` | calls | **calls** (fixed) |
| `Int64(fp)` in a `writeln` arg | calls | **address** |

FPC's own diagnostics confirm how aggressive the rule is: `Pointer(gp)` for a
`gp` that takes a parameter is rejected with *"Wrong number of parameters
specified for call to `<Procedure Variable>`"* — FPC read the cast operand as a
CALL, not as a pointer to cast.

## Why it was left out

"Value context" has real exceptions, and a wrong call is as silent as the bug:
`fp := f2` must copy the pointer, `@fp` must take the address, `Assigned(fp)`
must not call, and a procvar passed to a procvar-typed parameter must not
either. At the assignment node both sides' types are known and the exceptions
are decidable; in a general expression the parser does not yet know what the
context expects, so the conservative fix took the decidable half rather than
guess at the rest.

## Fix shape

Delphi's own model is the inverse of what pxx does: **default to calling**, and
suppress it in the contexts that want the procvar itself —

1. after `@`;
2. LHS of `:=`;
3. RHS of `:=` when the LHS is proc-typed (already handled);
4. an argument bound to a proc-typed parameter;
5. an operand of `=` / `<>` against a proc-typed value or `nil`;
6. the argument of `Assigned`.

That needs an expected-type channel into `ParseFactor`, which is the real work
here — the same shape as the overload resolver's side channel
(`MatchCallDelphiProcAddr`). A signature with parameters is never callable from
a bare name and needs no context at all.

## Gate

`Int64(fp)`, `writeln(fp)` and a non-procvar parameter each match FPC; all six
suppression contexts above keep their current behaviour;
`test/test_procvar_value_context.pas` extends with the previously-uncovered rows
and still passes under **both** FPC and pxx, as it does today.

## Resolution 2026-08-03 (claude-P@opus5)

Completed — and the ticket's premise needed correcting first.

### The rule is MODE-DEPENDENT, and the parent fix had it wrong

This ticket (and the parent) measured `{$MODE DELPHI}` only. Re-measured across
all three modes, same program, FPC 3.2.2:

| context | `$MODE FPC` / `OBJFPC` | `$MODE DELPHI` |
| --- | --- | --- |
| `p := fp` (p: Pointer) | address | **CALL** |
| `PtrUInt(fp)` (cast) | address | **CALL** |
| `Takes(fp)`, Pointer param | address | **CALL** |
| `fp = nil`, `fp = fp2` | address compare | **CALL both** |
| `Takes(fp)`, procvar param | address | address |
| `Assigned(fp)`, `@fp` | address | address |

FPC's own modes **never** auto-call. This project targets FPC compliance, with
Delphi behaviour only under `{$MODE DELPHI}` — so the parent's rewrite, which
fired in every mode, was a **regression** for `{$MODE FPC}`/`OBJFPC`: `p := fp`
returned the call result where FPC returns the address. Fixed here by gating the
whole rule on `DelphiMode`, and pinned by a new test.

The comparison rows are the ones worth noting: they are the *opposite* between
modes, and both readings are unambiguous only because the probe used two
distinct functions returning the same value (address-compare and result-compare
then disagree). An earlier probe that did not was ambiguous and would have
recorded the wrong answer.

### Implementation

One helper, `IRProcVarAutoCall(node, sinkIsProcVar)` (`ir.inc`), applied at each
sink where the expected type is known at lowering:

- **assignment** — sink = the LHS (the parent's site, now via the helper);
- **call argument** — sink = the parameter;
- **cast** (`AN_PTR_CAST`) and **comparison** (`AN_BINOP` `=`/`<>`) — never
  procvar sinks, so both operands are candidates.

Callers that cannot tell pass `sinkIsProcVar = True`: suppressing is always
safe, auto-calling a sink that wanted the pointer is a silent wrong value.

Two things the implementation turned up:

1. **`Assigned(fp)` desugars at PARSE time into the same `x <> nil` binop as a
   real comparison** — indistinguishable at lowering, and FPC treats them
   oppositely in Delphi mode. Tagged at the desugar site with
   `PAS_BINOP_ASSIGNED` (ASTSLen, the binop's spare marker field, as
   `PY_BINOP_AUGADD` already uses) and exempted. Without this, `Assigned` called
   the procvar and Delphi mode segfaulted.
2. **A caller cannot ask a parameter's SYMBOL whether it is proc-typed** —
   `RegisterProc` leaves `Params[].SymIdx = -1` and a param symbol does not
   outlive the callee's scope. Added `ProcParamProcSig`, a per-proc parallel
   array in the established `ProcParamUntyped` shape, written in `parser.inc`'s
   param loop.

### Verified — 10 contexts x 3 modes, all matching FPC

A harness compiles one program in `$MODE FPC`, `OBJFPC` and `DELPHI` under both
FPC and pxx and diffs per context. All three modes: **ALL MATCH FPC**.

Two gated regression tests, a deliberate pair:
`test/test_procvar_value_context.pas` (Delphi answers, extended with the cast /
argument / comparison / `Assigned` rows) and the new
`test/test_procvar_fpc_mode.pas` (FPC/OBJFPC answers — the guard for the
mode regression). Both print the same line under FPC and pxx.

`tools/gate.sh quick` GREEN.

### Found while doing this, filed urgent

`Procs[i].Params[j].ProcSig := -1` — a field `TParam` does **not have** —
compiled with no diagnostic, stored to a wrong offset, and segfaulted the NilPy
quick canary. Only the FPC seed canary caught it. Filed as
[[bug-pascal-unknown-record-field-accepted-in-compiler-source]] (urgent, prio
80) with a reliable reproduction and the four minimal shapes that do NOT
reproduce it.

## Log
- 2026-08-03 — resolved, commit PENDING.
