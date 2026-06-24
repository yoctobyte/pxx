# Bare own-name result of a VIRTUAL intrinsic-named method miscompiles

- **Type:** bug (codegen) — narrow
- **Status:** backlog (Track A)
- **Owner:** —
- **Opened:** 2026-06-24
- **Found-by:** TStream Read/Write methods (bug-read-write-reserved-as-method-names).

## Symptom

Assigning a function's result by its OWN name, when (a) the name is an intrinsic
keyword (`Read`/`Write`/`Readln`/`Writeln`) AND (b) the method is `virtual`,
returns garbage:

```pascal
function TStream.Read(var Buffer; Count: Integer): Integer; { virtual }
begin
  ...
  Read := Count;   { virtual + keyword name → caller gets garbage }
end;
```

Narrowing (all same body shape):
- `Result := Count`            → correct (every layout, virtual or not).
- non-keyword name `Rd := Count` (virtual)   → correct.
- keyword name, NON-virtual `Read := Count`  → correct.
- keyword name + VIRTUAL `Read := Count`     → **garbage return** (a code address).

The result var is always the `Result` slot (RetSymIdx), and the parser builds the
same `AN_ASSIGN(Result, expr)` AST as the non-keyword path — yet codegen differs
by (keyword-name AND virtual). Likely an own-name / VMT-recursion interaction in
the virtual + intrinsic-name case (cf. the "mangling breaks FuncName-result/
recursion" landmine).

## Current handling

`Read := x` (own-name result of an intrinsic-named method) is now a **clear
compile error** directing to `Result := ...` — no silent miscompile. So this bug
is latent behind that guard; `Result :=` is the correct, robust form.

## Done when

- `Read := Count` in a virtual intrinsic-named method returns the assigned value
  (remove the parser guard once codegen is correct).
- Regression test.
