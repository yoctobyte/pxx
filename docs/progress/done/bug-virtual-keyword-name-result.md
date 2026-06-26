# Bare own-name result of a VIRTUAL intrinsic-named method miscompiles

- **Type:** bug (codegen) — narrow
- **Status:** DONE (2026-06-26, commit on master)
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

## Resolution (2026-06-26, Track A)
The miscompile was resolved by intervening own-name/result fixes since the ticket
opened. Removed the parser guard; the keyword-name branch now builds the same
AN_ASSIGN(Result, expr) as the non-keyword own-name path (incl `.field`/`[i]`).
Verified by test/test_virtual_keyword_result.pas (registered in `make test`):
keyword-name virtual Read/Write result, override, and polymorphic dispatch all
correct (5/6/10/10). Self-host byte-identical; make test green incl cross.
