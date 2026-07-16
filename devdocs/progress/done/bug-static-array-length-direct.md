# `Length`/`High` of a static array used directly returns garbage

- **Type:** bug (codegen)
- **Status:** done
  directly still takes the (broken) runtime path; rare, left as follow-up.
- **Owner:** — (Track A)
- **Opened:** 2026-06-22
- **Closed:** 2026-06-22 (1-D)
- **Found-by:** Synapse recon, while fixing [[bug-var-open-array-fixed-arg-length]].

## Symptom

`Length(a)` / `High(a)` on a **static array variable** referenced directly (not
through an open-array parameter, not a dynamic array) returns garbage:
`Length` = 0, `High` = -1, instead of the compile-time element count.

```pascal
program p;
var f: array[0..2] of Integer;
begin
  WriteLn(Length(f));   { prints 0; expected 3 }
  WriteLn(High(f));     { prints -1; expected 2 }
end.
```

A dynamic array and an open-array parameter both work (they have a `[data-8]`
length header). `High` is `Length - 1`, so both follow the same root cause.

## Cause

The `Length` lowering (x86-64 IR: `ir_codegen.inc`, the `tkLength` block; and the
per-target copies in `ir_codegen386/arm32/aarch64/riscv32/xtensa.inc`) handles
managed strings, dynamic arrays, and open-array params (read `[ptr-8]`), then
falls through to a generic `else` that does `mov rax, [addr]` — for a static
array that loads the FIRST ELEMENT, not the length. A static array has no runtime
length header; its length is a compile-time constant (`Syms[idx].ArrLen`, the
first dimension for N-D).

## Fix

Fold `Length`/`High` of a whole static array to a compile-time constant at parse
time (`parser.inc` `tkLength` / `tkHigh`): when the argument lvalue is a whole
static-array `AN_IDENT` (`idx >= 0`, `Syms[idx].IsArray`, `ArrLen >= 0`), emit an
`AN_INT_LIT` of the element count instead of the `-tkLength` call. Parse-time
folding fixes every backend at once and matches FPC (where it is a constant).
Mind multi-dimensional static arrays: `Length` is the FIRST dimension's count,
not total `ArrLen` — only fold when the dimension count is known (1-D, or use the
first-dim span), else leave the runtime path.

## Gate

`make test` (self-host byte-identical) + `make cross-bootstrap`. Add a test for
`Length`/`High` of a 1-D static array (and, if handled, a 2-D one).

## Fix log

- 2026-06-22 — **1-D FIXED** by parse-time folding (parser.inc `tkLength` /
  `tkHigh`): when the argument is a whole static-array `AN_IDENT` (`idx >= 0`,
  `IsArray`, `ArrLen >= 0`, `Kind <> skParam`, `SymArrNDims <= 1`), emit an
  `AN_INT_LIT` of `ArrLen` (Length) / `ArrLen - 1` (High) instead of the runtime
  `-tkLength` call. Fixes every backend at once and matches FPC. Params (incl.
  open arrays, ArrLen=1000 sentinel) and multi-dim (`SymArrNDims >= 2`) keep the
  runtime path. Test `test/test_static_array_length.pas`, FPC objfpc
  oracle-matched (3 / 2 / 64 / 60). make test + cross-bootstrap byte-identical.
  **REMAINING:** multi-dim static `Length`/`High` used directly (still runtime,
  still wrong; rare — `Length` of a 2-D static array's first dimension).

## Log
- 2026-07-16 — resolved, commit a48a8353.
