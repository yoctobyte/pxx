# Handover: Next Compiler Work

**Snapshot:** 2026-06-02

Use this as the resume checklist after the first managed `AnsiString` and
managed dynamic-array ownership batch.
Source and `make test` remain authoritative; [`todo.md`](todo.md) keeps the
full inventory.

## Delivered In The Latest Batch

- Scalar dynamic-array assignment retains shared storage and releases replaced
  storage.
- Scalar `SetLength` preserves content when growing or shrinking, zeroes new
  slots, reclaims replaced blocks, and releases storage at length zero.
- Local dynamic-array pointer slots initialize to `nil`.
- Dynamic-array refcount operations are atomic only in threaded builds.
- Dynamic-array indexed writes clone shared storage before mutation.
- Dynamic-array locals release storage on normal procedure exit.
- `{$define PXX_MANAGED_STRING}` enables heap-backed managed strings with
  local cleanup, copy-on-write indexed writes, concatenation, coercions, and
  `SetLength`.
- `array of AnsiString` retains copied element references during clone/resize
  and finalizes elements when the final array owner is released.
- The pthread regression now repeatedly resizes local arrays while four
  workers also exercise `GetMem` / `FreeMem`.
- The allocator direction is documented in
  [`allocator-platform-design.md`](allocator-platform-design.md): a
  syscall-free internal heap is required on every target, with optional Linux,
  ESP32 bare-metal, and ESP32 RTOS hooks.

Regression gates:

```text
test/test_dynarray.pas
test/test_dynarray_ansistring.pas
test/test_multithreading.pas
make all
make test
```

## Delivered Aggregate ABI

Record-valued and set-valued function results now use a deliberate hidden
destination-pointer ABI. The caller allocates result storage in its own frame
or global scope; the callee saves the pointer locally so nested calls cannot
clobber it, copies out at return, and returns the destination address. Coverage
includes nested set calls, explicit `Exit(set)`, record results, and recursive
record returns in `test/test_aggregate_results.pas`.

## Recommended Order

The next runtime work should keep hosted optimizations optional:

1. **Allocator contract.** Add central target-neutral `Alloc`, `Free`, and
   `Realloc` emission helpers. Route raw memory, classes, arrays, and later
   strings through them.
2. **Syscall-free profile.** Add a fixed-static-arena test profile. Managed
   runtime tests must pass without `mmap`, `munmap`, or `brk`.
3. **Internal allocator.** Add alignment, splitting, coalescing, and in-place
   resize attempts. Linux `mmap`/`munmap` and future ESP32 RTOS services remain
   optional target hooks.
4. **Managed `AnsiString` depth.** Finish params/results, globals, exception
   paths, and remaining record/class ownership paths before making the
   opt-in ABI the default.
5. **Managed finalization and arrays.** Add recursive element metadata, then
   support params/results, nested dynamic arrays, and arrays of managed records.
6. **Thread audit.** Serialize compound `write`/`writeln`, decide shared
   `readln` state handling, and move exception globals to a thread-safe model.

## Deferred Arcs

- **Interfaces:** postponed intentionally. No current target source requires
  them, while even a no-refcount model adds substantial dispatch, ABI, and
  lifetime-design surface. Revisit when a concrete compatibility target needs
  them.
- **Access-control enforcement:** visibility parsing stays because
  `published` drives RTTI. Rejecting private/protected access enables no new
  programs, so enforcement is intentionally deferred until compatibility
  pressure justifies it.
- **Float conversions and float `Str`/`Val`:** handle with the math-library
  design rather than as isolated intrinsics.
- **Managed `AnsiString`:** the initial opt-in slice is implemented. Keep the
  ABI gated until params/results, globals, exceptions, and remaining
  record/class paths are covered.
- **Dynamic-array depth:** scalar and managed-string element arrays work.
  Recursive ownership still needs richer element metadata for nested arrays,
  managed records, and params/results.
- **Allocator:** use the target-neutral contract in
  [`allocator-platform-design.md`](allocator-platform-design.md). Replace the
  current simple first-fit free list with a syscall-free internal heap
  supporting splitting, coalescing, and in-place resize. Keep Linux
  `mmap`/`munmap` and RTOS services behind optional target hooks.
- **Compiler internal split:** move include-heavy internals toward real Pascal
  units late, after behavioral work settles.

## Known Red

- None. (The hang compiling `test/test_basic_lexer.bas` was resolved by implementing Block IF statements).

## Verification Baseline

The latest batch passed:

```sh
make test
make test-nilpy
git diff --check
```

`make test` includes FPC recovery equivalence, recursive self-hosting, the
expanded regressions above, and final byte-identical fixedpoint comparison.
