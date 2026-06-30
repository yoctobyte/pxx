# Array constructor `[...]` as open-array arg fails at a statement-level call

- **Type:** bug (parser / call lowering — correctness) — Track A
- **Status:** backlog
- **Opened:** 2026-06-30 (Track B latent-bug sweep, against stable v97)
- **Relates:** regresses part of [[feature-open-array-constructor-arg]] (done 2026-06-23)

## Symptom

Passing an inline array constructor `[...]` to an `array of T` parameter works
when the call is an **expression** but is rejected when the same call is a
**statement** (procedure call, or function call with the result discarded):

```pascal
function f(const a: array of integer): integer; begin f := length(a); end;
var r: integer;
begin
  r := f([1,2,3]);   { OK  -> 3 }
  f([4,5]);          { ERROR }
end.
```

```
pascal26: error: by-reference argument must be a variable ()
```

Procedures (which can *only* be called as statements) therefore can never take
an inline constructor:

```pascal
procedure p(const a: array of integer); begin writeln(length(a)); end;
begin p([1,2,3]); end.    { ERROR — same message }
```

## Isolation

| Call site | result |
| --- | --- |
| `writeln(f([1,2,3]))` (expression) | **OK** |
| `r := f([1,2,3])` (expression, assignment RHS) | **OK** |
| `f([4,5]);` (statement, result discarded) | FAIL |
| `p([1,2,3]);` (procedure, statement) | FAIL |

Element type (integer / string) and body (length-only vs indexing) do not matter
— the only axis is expression-context vs statement-context call.

## Likely cause

`feature-open-array-constructor-arg` (done 2026-06-23) added `AN_ARRAY_CTOR` and
wired it into *both* the expression-level (parser ~4243) and statement-level
(~7494) call-arg loops, including a bypass of the by-ref "must be a variable"
check. The expression path still works; the **statement-level** path no longer
applies the `AN_ARRAY_CTOR` handling / by-ref bypass (regressed or never fully
landed). Re-check the statement-call-arg loop against the expression one and
restore the `ParamIsOpenArrayScalar` → `ParseArrayCtorAST` → bypass branch.

## Acceptance

- `p([1,2,3]);` and `f([4,5]);` (statement context) compile and run.
- Expression-context calls stay working; empty `[]` still accepted.
- Add a regression test exercising a **procedure** open-array param called with a
  `[...]` literal as a statement (`test/test_open_array_ctor_stmt.pas`), wired
  into `make test`. Self-host stays byte-identical.
