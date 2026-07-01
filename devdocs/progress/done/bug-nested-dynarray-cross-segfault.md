# Nested dynamic arrays (`array of array of T`) segfault on cross targets

- **Type:** bug (codegen — cross targets) — Track A
- **Status:** done — fixed pin v136, 2026-07-01, for i386/arm32/aarch64.
  riscv32/xtensa left untouched (see Log).
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

## Fixed (2026-07-01, pin v136, i386/arm32/aarch64)

Root cause matched the "Direction" guess almost exactly: these three
backends' `IR_LEA` codegen for a dynamic-array symbol always loaded the heap
data pointer (the handle), with **no gate on `InLValueWrite`** — x86-64
already had this gate (write mode yields the slot's own address; read mode
derefs to the handle). `SetLength` on an array symbol itself needs the
SLOT's address to publish a new handle into. Crucially, this applies not
just to the outer `SetLength(a, n)` but to `SetLength(a[i], n)` too: the
*root* symbol `a`'s own slot is still reached via a plain `IR_LEA` at the
base of the nested-indexing chain (`compiler/ir.inc`'s `IRLowerAddress`,
"nested dynamic-array indexing" branch), so the same missing gate broke the
per-row case directly.

Without the gate: `SetLength(a, n)` silently wrote through `a`'s CURRENT
(nil, before first allocation) handle instead of its slot — a silent no-op
— and one level down, `SetLength(a[i], n)` computed a bogus small-integer
"address" (nil base + `i * elemSize`) and crashed on any `i > 0` (index 0
landed on the nil address itself — also a no-op, not a crash, which is why
the FIRST per-row `SetLength(a[0], ...)` appeared to work while the second,
`SetLength(a[1], ...)`, segfaulted). Found by tracing actual pointer values
through a temporarily-instrumented `PXXDynSetLen`/`PXXDynArrayUnique` on
arm32 (plain Pascal runtime helpers, easy to add `writeln` to) rather than
guessing from static code reading alone — several rounds of static analysis
(elSize computation, COW/refcount logic, register clobbering) all checked
out fine on paper and it took the actual runtime pointer values to find the
real discrepancy.

Fixing `IR_LEA` alone regressed indexed WRITES into a plain array (`g[i] :=
x`, caught by a broader hand-written test before landing, not by the
original repro): indexing always needs to read the array's own handle as a
base regardless of the outer write intent, and x86-64 only gets this right
because its `IR_INDEX` codegen follows up with a full COW-aware
`PXXDynArrayUnique` call that overrides the write-mode `IR_LEA` result.
These three backends have no COW yet ("v1: no COW", pre-existing, documented
scope boundary), so `IR_INDEX` now does the minimal equivalent: deref once
more when the base was a write-mode dynarray `IR_LEA`.

Verified against the x86-64 oracle for the original repro plus global,
local, and by-ref-param (`var a: TDynArr`) dynamic-array scenarios; all
existing i386/arm32/aarch64/riscv32 cross suites stay green (including
`dynarray`, `dynarray-field`, `setlen-str`, `setlen-varparam`).
`test/test_nested_dynarray_setlen.pas` added (oracle-comparison style, no
hardcoded expected string, matching `test_cross_dynarray.pas`'s existing
convention), wired into all three targets' cross `make test` suites.
Self-host byte-identical (these cross backends aren't exercised by
self-hosting), full `make test` green.

**riscv32/xtensa left untouched**: their `IR_LEA` has the exact same missing
`InLValueWrite` gate (confirmed by reading `ir_codegen_riscv32.inc`), but
this precise scenario is blocked there today by an unrelated, pre-existing
gap (`error: managed aggregate locals not yet supported` — riscv32 can't
even compile the depth-2 repro yet), so there's no way to verify a fix
without also lifting that separate limitation. Flagging for whoever picks
up riscv32/xtensa dynamic-array support: apply the same `InLValueWrite`
gate to `IR_LEA` (and the matching "deref once more" fixup to `IR_INDEX`)
there too once the aggregate-locals gap is closed.
