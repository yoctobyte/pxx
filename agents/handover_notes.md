# Handover Notes: Pure-Pascal Heap Allocator — DELIVERED

Status: **done** (2026-06-06, commits `2a3b2f6` + `f6de004`). Kept as a record;
durable tracking lives in `devdocs/progress/` (`feature-unified-heap-allocator` in
`done/`, `feature-allocator-quality` follow-up in `backlog/`).

## What shipped

The compiler's heap (GetMem/New/class-new, FreeMem/Dispose, ReallocMem) is
redirected to one pure-Pascal contract — `PXXAlloc`/`PXXFree`/`PXXRealloc` in
`compiler/builtin/builtin.pas` (mmap-backed, 8-byte size header + first-fit free list,
reused blocks zeroed). `make bootstrap` (byte-identical fixedpoint), `make test`
(+ `fpc-check`), and `make test-nilpy` are all green.

## Correction to the original handover

The original handover assumed `builtin.pas` already implemented `Alloc`/`Free`/
`Realloc` and that the stage-2 hang was the asymmetric `FreeMem` (Hypothesis A).
Reality: **those bodies were never committed and were absent from the tree**, so
the redirected ops called bodyless procs. Hypothesis A alone could not have
fixed it.

## Bugs found and fixed en route

1. Reconstructed the missing `PXXAlloc`/`PXXFree`/`PXXRealloc` bodies.
2. `FreeMem` → `EmitHeapFreeLocked` (the real Hypothesis A).
3. Reused blocks must be zeroed (managed runtime assumes fresh = 0).
4. **The "infinite loop" was a codegen regression, not the allocator:** a
   `not`-typing heuristic (keyed on `LastExprTk`) mistyped a boolean `not` in
   the compiler's own source as bitwise, so a `while not done` never terminated.
   Reverted to logical `not`.
5. **Virtual dispatch segfault:** the class-new refactor dropped "save Self /
   return Self as the constructor result", so `obj := T.Create` returned garbage.
   Re-added.
6. **nilpy:** registered the allocator forward-decls and added the missing
   `ApplyCallFixups` so `.npy` patches forward calls (the variant int→string
   crash was an unpatched `call PXXAlloc`).
7. Renamed `Alloc`/`Free`/`Realloc` → `PXX*` to avoid colliding with C
   `free`/`malloc` and user identifiers.

## Follow-ups (tickets)

- `feature-allocator-quality` — split/coalesce/bins/alignment (deferred; the
  simple allocator is correct and may be good enough).
- `feature-static-arena-profile` — the syscall-free / target-hook abstraction
  (mmap optional; bare-metal/ESP32).
