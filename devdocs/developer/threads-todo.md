# Managed Runtime and Multithreading Roadmap

**Updated:** 2026-06-01

This is the active design for managed runtime values and thread safety. The
older allocator options discussion in
[`threading-and-heap-design.md`](threading-and-heap-design.md) is background
material; this document defines the implementation order.

## 1. Fixed Policy

- Threading remains optional. `--threadsafe` and `{$THREADSAFE ON}` enable
  synchronization; the default remains single-threaded.
- The non-threaded path stays short: no mutexes, spinlocks, atomic prefixes, or
  synchronization syscalls are emitted unless `ThreadSafeMode` is active.
- Managed `AnsiString` and dynamic-array ABIs are not optional dialect modes.
  Their layout and value semantics stay the same in both modes. Only refcount
  updates and shared-runtime critical sections differ.
- Build the simple correct threaded implementation first. Optimize contention
  only after stress tests justify the complexity.

## 2. Current Baseline

Already implemented:

- `--threadsafe` and `{$THREADSAFE ON/OFF}`.
- Conditional heap spinlock emission around IR `GetMem`, `FreeMem`, and
  `ReallocMem`.
- Heap blocks with size headers, a first-fit free list, and `mmap` arena growth
  in the IR allocator path.
- Dynamic arrays with pointer-sized slots, assignment retain/release,
  indexed-write copy-on-write, preserving `SetLength`, zero-initialized
  growth, replacement reclaim, normal local cleanup, and atomic refcount
  updates only under `--threadsafe`, using the provisional layout
  `[refcount:8][length:8][data...]`.
- Managed `AnsiString` is the default and `array of AnsiString` includes
  element retain/finalize during array clone, resize, and final release.
- Dynamic arrays of records recursively containing managed strings use the
  same element lifecycle helpers. Class/object pointers stay unmanaged.
- Nested dynamic arrays of scalar, managed-string, and managed-record bases
  recursively retain and finalize each level.
- A pthread regression that concurrently allocates and frees heap blocks.

Known gaps:

- Frozen fixed-capacity inline strings remain available with
  `-uPXX_MANAGED_STRING`; default managed strings still need thread-level
  synchronization decisions for compound mutation beyond atomic refcounts.
- Dynamic arrays still defer nested-level copy-on-write, exception-path
  cleanup, and fresh-result move semantics.
- The older shared `EmitBumpAlloc` helper still uses the obsolete `brk` model
  and is not protected by the heap lock. Managed values must go through one
  allocator path before threaded stress testing.
- `write`/`writeln`, exception output, and `read`/`readln` use shared output or
  input state without a threaded atomic-operation policy.

## 3. Phase 1: Managed `AnsiString`

Do strings first. They are heavily exercised by the compiler itself and force
the lifetime model needed by dynamic arrays.

### ABI

An `AnsiString` variable is one pointer-sized slot. `nil` represents the empty
string. A non-empty string points directly at its first character for free
`PChar` compatibility:

```text
allocation base
  +0   refcount     qword
  +8   length       qword
  +16  capacity     qword
  +24  data[0]      byte  <-- AnsiString value / PChar
       ...
  +24+length        byte  always #0
```

Always allocate room for `capacity + 1` bytes and write a trailing zero after
creation, resize, concatenation, append, indexed mutation, and input. The
terminator is outside the Pascal `Length`.

The empty string is `nil`; `PChar('')` support can later use a shared static
zero byte if required by compatibility tests.

### Semantics

- Assignment shares the allocation and increments its refcount.
- Scope exit, overwrite, record/class finalization, and global finalization
  decrement the old allocation and free it at zero.
- Mutating operations use copy-on-write when `refcount > 1`.
- Capacity allows append-heavy paths such as lexer preprocessing to grow
  geometrically instead of reallocating for every character.
- Literals may initially materialize into managed allocations. A later
  immortal/static-literal optimization is valid if it preserves the ABI.

### Threaded Delta

- Default mode emits ordinary refcount increment/decrement instructions.
- `ThreadSafeMode` emits atomic memory refcount updates, for example
  `lock inc qword [ptr-24]` and `lock dec qword [ptr-24]`.
- The decrement-to-zero decision must be part of the same atomic decrement
  sequence (`lock dec` followed by flags-based branch), so exactly one thread
  reclaims the allocation.
- Copy-on-write protects separate variables sharing an allocation. Concurrent
  writes through the same variable remain a caller data race; the runtime does
  not turn every variable access into a lock.

### Migration Order

1. Add centralized code-emission helpers for managed retain, release,
   allocation, uniqueness, and trailing-zero maintenance.
2. Change string locals, globals, fields, params, and results to pointer slots.
3. Convert literal assignment, variable assignment, concat, `AppendChar`,
   `SetLength`, indexed reads/writes, comparisons, `Length`, `Str`/`Val`,
   `readln`, and `write`/`writeln`.
4. Inject releases on overwrite and normal scope exit, then cover early
   `Exit`, exception unwinding, records, classes, and globals.
5. Bootstrap and fixedpoint-test in both default and `--threadsafe` modes.

## 4. Phase 2: Managed Dynamic Arrays

Use the same ownership machinery after strings are stable.

### ABI

A dynamic-array variable is one pointer-sized slot. `nil` represents length
zero. A non-empty value points directly at element zero:

```text
allocation base
  +0   refcount     qword
  +8   length       qword
  +16  capacity     qword
  +24  element[0]   <-- dynamic-array value
```

### Semantics

- Assignment retains; overwrite and scope exit release.
- `SetLength` preserves `min(oldLength, newLength)` elements.
- New scalar slots are zero-initialized.
- Resize may occur in place only for a unique allocation with sufficient
  capacity; otherwise allocate-copy-release.
- Dynamic arrays of strings and records come after scalar lifecycle support.
  They need element initialization, copy, and finalization helpers.
- Apply the same conditional atomic refcount strategy as `AnsiString`.

### Verification

Add regressions for alias assignment, copy-on-resize, shrink/grow preservation,
release at scope exit, arrays of strings, arrays of records containing strings,
and multi-threaded retain/release stress.

## 5. Phase 3: Heap and Memory Management

Detailed design: [`allocator-platform-design.md`](allocator-platform-design.md).
Unify allocation behind a target-neutral contract before adding
sophistication. Linux syscalls are optional hooks, not runtime requirements.

1. Route `GetMem`, `FreeMem`, `ReallocMem`, class allocation, managed strings,
   and dynamic arrays through one allocator implementation.
2. Keep the current global heap spinlock only in `ThreadSafeMode`; default
   builds emit no lock code.
3. Implement the required syscall-free internal heap: supplied memory regions,
   alignment, free-list splitting, adjacent-block coalescing, and in-place
   resize attempts.
4. Add optional per-target hooks for region reserve/release/resize. Linux may
   use `mmap`/`munmap`; bare-metal ESP32 may provide no hooks; an ESP32 RTOS
   profile may adapt RTOS allocation services.
5. Add size bins and double-free/debug checks in small independent steps.
6. Add a fixed-static-arena test profile that emits no memory syscalls.
7. Consider thread-local arenas only after measurement. Cross-thread free,
   ownership routing, and TLS ABI details make them a later optimization.

## 6. Phase 4: Thread-Safety Audit

Managed values and the heap are necessary but not sufficient. Audit runtime
operations with shared mutable state:

- `write`/`writeln`: one source statement currently becomes multiple
  `SYS_WRITE` calls. Under `ThreadSafeMode`, protect the whole statement so
  arguments and newline cannot interleave with another thread.
- `read`/`readln`: protect the shared line buffer and cursor for the whole
  source statement, or move them to per-thread state.
- Exception runtime: audit global exception state (`BSS_EXC_*`). It likely
  needs thread-local storage before exceptions are supported across threads.
- Unit initialization/finalization and global managed-value release: define
  single-threaded startup/shutdown ownership.
- Compiler/RTL globals, resource tables, RTTI registries, and external-call
  wrappers: distinguish immutable shared data from mutable state.
- Syscalls: most kernel calls are independently thread-safe, but compound
  runtime operations may still require a lock around several calls.

Use separate BSS locks for unrelated concerns (`heap`, `stdout`, `stdin`) so
output does not serialize allocation.

## 7. Exit Gate

Each phase must pass:

1. Default `make test`.
2. Self-host bootstrap and binary fixedpoint.
3. The same bootstrap and fixedpoint path compiled with `--threadsafe`.
4. Focused pthread stress tests for the phase's shared runtime operations.

Only after these gates should native `BeginThread`/`TThread` wrappers or TLS
allocator optimizations move onto the active roadmap.
