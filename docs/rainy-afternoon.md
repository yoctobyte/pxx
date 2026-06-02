# Rainy Afternoon Backlog

**Snapshot:** 2026-06-02

This is the single compact list of known non-critical bugs, limitations, and
cleanup work worth revisiting when convenient. None of these currently block
the verified compiler milestone. Source and regression tests remain
authoritative.

## Managed Values

- **Fresh managed result leaks one reference.** A dynamic-array function result
  is built with refcount 1, then caller assignment retains it again. Managed
  `AnsiString` results follow the same pattern. Add move semantics for a fresh
  call result so assignment can skip the retain.
- **Managed-record return-by-value ownership is incomplete.** Ordinary
  whole-record assignment uses `IR_COPY_REC_MANAGED`, but aggregate function
  result copy-out still needs equivalent retain handling for records containing
  managed fields.
- **Exception unwinding does not finalize managed locals.** Normal scope exit
  cleanup works. Add unwind-path cleanup when managed exception lifetime
  semantics become active work.
- **Nested dynamic-array sublevels do not copy on write.** Recursive ownership
  is implemented, but mutating an aliased sub-array can still affect both
  aliases. This is documented behavior for now.
- **Managed `AnsiString` remains opt-in.** Before making it the default ABI,
  finish params/results, globals, exception paths, and remaining class
  ownership coverage.

## Runtime And Threads

- **Async, coroutines, and `yield` are a future shared-language arc.** They can
  share one compiler-generated resumable-frame mechanism plus an event loop and
  worker pool. Finish Variant, containers, modules, SQLite, and allocator
  groundwork first. Design: [`plan-async-coroutines.md`](plan-async-coroutines.md).
- **`read` consumes a fresh line like `readln`.** Preserve the unread remainder
  of the current line across separate `read` calls.
- **Compound I/O is not statement-atomic under threads.** Decide locking for
  `write`/`writeln`, shared `read`/`readln` state, and exception output.
- **Exception globals need a thread model.** Move shared exception state to a
  thread-safe design before claiming threaded exception handling.
- **Allocator remains deliberately simple.** The current first-fit free list
  needs a target-neutral contract, a syscall-free fixed-arena profile,
  alignment, splitting, coalescing, and in-place resize attempts. Keep hosted
  `mmap` and future RTOS hooks optional.
- **Runtime support emission is eager.** Plain Pascal hello currently emits
  unused heap startup and the managed-string helper bundle. Add feature
  reachability gates before embedded work or code-size tuning. The measured
  2026-06-02 audit is in
  [`runtime-emission-size-audit-2026-06-02.md`](runtime-emission-size-audit-2026-06-02.md).

## C Interoperability

C header import is **delivered for the intended FFI-extraction model**, not an
unfinished active arc. It tolerantly parses large real-world header trees,
extracts callable symbols, typedefs, opaque aggregate pointers, enums, and
constants, strips common GCC/framework annotations, recursively rescans macros,
supports callbacks via `@proc`, and emits SysV AMD64 integer, floating-point,
variadic-vector-count, and stack-spill call ABI behavior.

Possible breadth improvements, only when a concrete library requires them:

- Add preprocessor token paste (`##`), stringification (`#`), and variadic
  macros.
- Add dynamic soname discovery from the host loader cache or candidate ELF
  files. The current versioned soname table covers exercised libraries.
- Model C struct field layout, bitfields, and packing only for APIs that require
  direct field access. Opaque pointer aggregates are preferable for library
  handles.
- Deepen callback signature metadata and pointer marshalling where a target API
  needs more than the current raw-pointer callback surface.

Older `plan-c-header-import.md`, `todo.md`, `project-state.md`, and
`C_INTEROP.md` passages may describe earlier intermediate stages. Treat this
section and the current regression suite as the compact status summary until
those longer documents are refreshed.

## Language Breadth

- Interfaces remain intentionally deferred until a concrete compatibility
  target needs their dispatch and lifetime model.
- Visibility sections are parsed for RTTI, but private/protected access is not
  enforced.
- Metaclass aliases do not yet enforce every descendant constraint against
  arbitrary pointer-compatible assignments.
- Broaden Pascal directive switch semantics only when compatibility pressure
  justifies it.
- Expand inline asm when needed: labels/branches, global operands, explicit
  memory operands and SIB addressing, operand-size keywords, and SSE/AVX.
- Add richer RTL and package breadth incrementally rather than claiming FPC RTL
  compatibility.

## Documentation Cleanup

- Refresh older feature snapshots that still claim float intrinsics are
  missing. `Trunc`, `Round`, `Frac`, and `Int` are implemented and covered by
  `test/test_float_intrinsics.pas`.
- Fold delivered C-import milestones back into the longer C interop documents
  when those documents are next edited.
