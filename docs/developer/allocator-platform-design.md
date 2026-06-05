# Platform-Neutral Allocator Design

**Updated:** 2026-06-01

The managed runtime must not depend on Linux syscalls. `AnsiString`, dynamic
arrays, classes, and raw `GetMem` users need one allocator contract whose
implementation is selected by the target profile.

## 1. Runtime Contract

Managed values call allocator operations, never syscalls directly:

```text
Alloc(size, align)                  -> pointer or nil
Free(pointer)
Realloc(pointer, newSize, align)    -> pointer or nil
```

`Realloc` preserves `min(oldSize, newSize)` bytes. It may return the same
pointer, move the block, or fail. Managed-value code must not assume that a
resize moves or stays in place.

Allocator metadata belongs to the allocator implementation. Managed values may
keep their own headers for refcount, length, and capacity, but must not inspect
allocator headers such as free-list links or raw block sizes.

## 2. Required Baseline: Internal Heap

Every target gets a syscall-free internal allocator:

- Initialize from one or more memory regions supplied by startup code, the
  linker script, firmware configuration, or a host platform hook.
- Allocate from those regions with alignment support.
- Reuse freed blocks.
- Split oversized free blocks and coalesce adjacent free blocks.
- Attempt in-place grow or shrink before falling back to allocate-copy-free.
- Keep locking conditional on the threading profile.

This is the required implementation for bare-metal targets. It is also the
fallback when hosted platform services are unavailable or undesirable.

## 3. Optional Platform Hooks

A target profile may provide hooks that improve the baseline:

```text
ReserveRegion(minimumSize)          -> region or unavailable
ReleaseRegion(region)               -> success/failure
ResizeRegion(region, newSize)       -> resized region or unavailable
```

These hooks are optional capabilities, not assumptions in the managed runtime.

Examples:

- Linux: reserve arenas with `mmap`; release sufficiently large dedicated
  regions with `munmap`; use a platform resize facility only when it is a
  measured win and its semantics fit the target.
- ESP32 bare metal: initialize the internal allocator from linker-defined RAM
  regions; no syscall layer exists.
- ESP32 with an RTOS: either keep the internal allocator or adapt the target's
  RTOS allocation services behind the same contract. The Pascal runtime must
  not expose RTOS-specific allocation behavior to managed values.
- Small embedded systems: use a fixed static heap region and omit region hooks
  entirely.

## 4. Target Profiles

Allocator selection is a target decision, separate from language semantics:

| Profile | Internal Heap | Platform Hooks | Threading |
| --- | --- | --- | --- |
| Linux hosted | Required fallback | Optional `mmap`/release/resize | Optional |
| ESP32 bare metal | Required primary | Usually none | Optional |
| ESP32 RTOS | Required fallback or primary | Optional RTOS adapter | Optional |
| Small bare metal | Required primary | None | Usually off |

The same compiled language features remain available wherever memory capacity
permits. A target may choose smaller metadata words or stricter limits as part
of its ABI, but that must be explicit in the target profile.

## 5. Threading Boundary

Thread safety belongs around allocator state, not around syscalls:

- Single-threaded builds emit no allocator synchronization.
- Threaded builds protect shared free lists and region metadata.
- A platform hook may already be thread-safe, but the internal allocator still
  needs its own synchronization when shared.
- Thread-local arenas remain an optional optimization after the shared
  allocator is correct.

## 6. Migration From The Current Linux Emitter

The current x86-64 Linux emitter inlines allocator details and calls `mmap`
while growing its heap. Refactor in this order:

1. Define target allocator capabilities and central allocator emission helpers.
2. Route `GetMem`, `FreeMem`, `ReallocMem`, classes, dynamic arrays, and managed
   strings through those helpers.
3. Implement split/coalesce and in-place resize in the syscall-free internal
   heap.
4. Keep Linux `mmap` arena acquisition as one platform hook.
5. Add optional large-region release and resize hooks after correctness tests.
6. Add a syscall-free test profile backed by a fixed static arena before the
   ESP32 backend is implemented.

The static-arena profile is the portability gate: managed values and allocator
tests must pass without emitting `mmap`, `munmap`, or `brk`.
