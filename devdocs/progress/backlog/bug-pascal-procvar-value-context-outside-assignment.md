---
track: P
prio: 60
type: bug
summary: "A bare procvar is now called on the RHS of an assignment (FPC parity), but not in other value contexts — `Int64(fp)` or `writeln(fp)` still yield the ADDRESS where FPC calls. Same silent-valid-pointer failure as the parent bug, in the contexts the conservative fix deliberately left out."
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
