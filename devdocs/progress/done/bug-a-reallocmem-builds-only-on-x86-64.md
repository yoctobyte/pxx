---
track: A
prio: 20
type: bug
blocked-by: []
status: done
found-by: frankD (2026-09-29, lib_cross_sweep: lib_charset refused on i386); routed by frankuser
tags: [backend, cross, heap, reallocmem]
summary: "`ReallocMem(p, n)` compiled only for x86-64. The parser lowers it to special call id -103, and only the x86-64 backend implements that id (inline, under the heap lock). i386, arm32, aarch64, riscv32, xtensa and wasm32 refused it with `builtin/special call not yet supported (builtin id 103)`, so lib/rtl/charset.pas, and every program using it, did not build there. On those targets the parser now calls the heap unit's PXXRealloc(p, n, 8), which does the same header-sized copy."
owner: ""
---

# ReallocMem builds only on x86-64

```pascal
GetMem(p, 4); ReallocMem(p, 1000);
{ --target=i386: builtin/special call not yet supported (builtin id 103) }
```

## Cause and fix

The ReallocMem branch in pasparser_stmt.inc builds `p := <call -103>(p, n)`.
Each backend lowers the negative ids it knows. Only ir_codegen.inc (x86-64)
has a case for -103. When the target is not x86-64 and the heap unit is
loaded, the call now names PXXRealloc (builtinheap.pas) and passes an
alignment of 8. x86-64 keeps its inline path unchanged.

## Measured (2026-09-29, fixedpoint 85195073c2f0)

- `test/test_reallocmem_grows_and_shrinks_on_every_target.pas` covers:
  - growing 4 to 1000 bytes and shrinking to 10, checking the contents each time;
  - ReallocMem from nil;
  - a record field grown inside a procedure;
  - an untyped Pointer.

  Its expected output is FPC's. It equals FPC on x86-64, i386, arm32, aarch64,
  riscv32 and xtensa windowed. The previous compiler refuses it on all five
  non-x86-64 targets. Those six are its rows.
- wasm32 now builds the plain-pointer cases. The record-field case fails there
  for a different reason: `slot rec has no wasm value type` (reading the
  field lvalue back). A plain `GetMem(rec.buf, ...)` works, so that is a
  wasm32 gap with field lvalues, not this ticket. That is why wasm32 has no row.
- lib_charset (98 checks) builds and passes on i386, arm32, aarch64, riscv32
  and xtensa with this change.

## Same class: other special ids with one implementation

A census of negative call ids across the backends' codegen files, each
checked with a probe:

- -103 ReallocMem: this ticket.
- -210 bare `Eof`: wasm32 refuses it (`builtin unrecognised -210`). xtensa
  windowed builds it and gives a wrong answer (the previous compiler does
  the same).
- -200/-201 (NilPy `int()`/`str()` of a variant) are lowered before the
  backend and work on every probed target.
- The remaining ids appear in every backend.
