# Dynamic-array `a + b` concat silently miscompiles (compiles, no output)

- **Type:** bug (parser/codegen — silent miscompile) — Track A
- **Status:** DONE (2026-06-30, Track A) — silent miscompile fixed (now a clean error); concat-as-feature deferred
- **Opened:** 2026-06-30
- **Found by:** feature-dynarray-torture-test.

## Symptom

```pascal
var a, b, c: array of Integer;
begin
  SetLength(a,2); a[0]:=1; a[1]:=2; SetLength(b,2); b[0]:=3; b[1]:=4;
  c := a + b;                 { compiles with NO error }
  writeln('len=', Length(c)); { prints NOTHING — program produces no output, exit 0 }
end.
```
The compile succeeds (no diagnostic), but the resulting binary produces **no
output at all** — the `c := a + b` statement corrupts the program (the following
`writeln` never runs / is mis-emitted). A silent miscompile is worse than an
honest "operator + not supported for dynamic arrays".

## Expected

Either implement `+` as element concat (FPC `{$modeswitch arrayoperators}`:
`c = [a..., b...]`, `Length(c) = Length(a)+Length(b)`), **or** reject it at
parse time with a clear error. Do not silently emit a broken binary.

## Fix sketch

Find where a binary `+` over two dynarray operands is lowered (it currently slips
through to some path that emits nothing useful). Minimum viable: detect dynarray
`+` operands and `Error('operator + not supported for dynamic arrays')`. Better:
lower to a concat helper (allocate Length(a)+Length(b), copy both, element-type
aware — same generic-over-T problem as [[feature-copy-intrinsic]]).

## Acceptance

`c := a + b` either concatenates correctly (oracle: `4 / 1 / 4`) or errors at
compile time; never a silent no-output binary. Regression test.

## Fixed (2026-06-30, Track A)

`a + b` (and `-`/`*`/`/`) with a dynamic-array operand fell through the AN_BINOP
lowering to the integer/pointer `IR_BINOP`, which added the two array *handles* →
wild pointer → runtime SIGSEGV. Now rejected at IR lowering with
`arithmetic operator not supported for dynamic arrays (...)` (ir.inc AN_BINOP,
gated on `NodeDynDepth(operand) > 0` + an arithmetic op), so it is a clean
compile-time error instead of a silent crashing binary. Integer `+` and string
concat unchanged; self-host byte-identical; `make test` green
(`test/test_dynarray_concat_rejected.pas`, a negative test).

**Remaining (feature, not this bug):** actually *implementing* `a + b` array
concat (allocate `Length(a)+Length(b)`, copy both, element-type-aware) — the same
generic-over-element-type shape as [[feature-copy-intrinsic]] /
[[feature-dynarray-insert-delete]]. Tracked there; this ticket only owned the
silent-miscompile, which is resolved.
