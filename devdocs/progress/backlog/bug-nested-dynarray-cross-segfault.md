# Nested dynamic arrays (`array of array of T`) segfault on cross targets

- **Type:** bug (codegen — cross targets) — Track A
- **Status:** backlog
- **Opened:** 2026-06-30
- **Found by:** smoke-testing multidim `SetLength` across targets
  (feature-dynarray-torture-test / bug-setlength-multidim-one-call).

## Symptom

A dynarray-of-dynarray built with **per-row** `SetLength` (no multidim sugar):

```pascal
var a: array of array of Integer; i, j: Integer;
begin
  SetLength(a, 2);
  for i := 0 to 1 do SetLength(a[i], 3);
  for i := 0 to 1 do for j := 0 to 2 do a[i][j] := i*10 + j;
  writeln(Length(a), ' ', Length(a[0]), ' ', a[1][2]);
end.
```

- **x86-64:** correct (`2 3 12`).
- **arm32 / aarch64:** runtime **SIGSEGV** under qemu.
- **i386:** no output (also broken).

The program uses **no** multidim-`SetLength` sugar, so this is a pre-existing
nested-dynarray codegen gap on the 32-bit / cross backends, not related to the
one-call `SetLength(a, x, y)` feature (which exposed it while smoke-testing).

## Scope

`SetLength(a[i], n)` on a sub-array (an `AN_INDEX` lvalue whose value is itself a
dynarray handle) — the inner-handle load/store, or the nested-index addressing,
is wrong on the cross backends. Single-level dynarrays work cross (the torture
test's other cases pass on arm32 in `make test-arm32`).

## Direction

Bisect the cross IR_SETLEN / dynarray-handle path for a **sub-array** target:
`SetLength(a[i], n)` must load the element slot `a[i]` (a handle) by address and
resize *that* handle. Compare the x86-64 lowering (works) against arm32/aarch64.
Likely the address-of-element-slot vs value-of-handle distinction (cf. the var-
param IR_LEA scalar-deref class of bug on the 32-bit targets).

## Acceptance

`array of array of T` (per-row and one-call multidim SetLength) runs correctly on
arm32 / aarch64 / i386 / riscv32 (oracle == x86-64); cross regression test.
