# Rainy Afternoon Backlog

**Snapshot:** 2026-06-02

This is the single compact list of known non-critical bugs, limitations, and
cleanup work worth revisiting when convenient. None of these currently block
the verified compiler milestone. Source and regression tests remain
authoritative.

## Managed Values

- **Exception unwinding does not finalize managed locals.** Normal scope exit
  cleanup works. Add unwind-path cleanup when managed exception lifetime
  semantics become active work.
- **Managed `AnsiString` remains opt-in.** Before making it the default ABI,
  finish globals, exception paths, and remaining class ownership coverage.
  (Params/results, fresh-result move, argument-temp ownership, and nested-level
  copy-on-write all landed 2026-06-04.)

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
- **Runtime support emission still has finer cleanup available.** A coarse
  Pascal gate now omits unused heap startup and managed-string helpers, taking
  hello from 1,134 to 287 bytes. Split helper dependencies and gate argv-stack
  preservation before embedded work or deeper code-size tuning. The measured
  2026-06-02 audit is in
  [`runtime-emission-size-audit-2026-06-02.md`](runtime-emission-size-audit-2026-06-02.md).

## Unexplained Anomalies

- **One-off non-reproducible miscompile (2026-06-02).** During validation of the
  record-value `Exit` fix, the *same* `compiler/pascal26` (md5 unchanged)
  occasionally produced a *different*, crashing binary for
  `test/test_managed_record_exit.pas`. `cmp` showed about ten differing bytes at
  the same total file size (offsets ~97/98, 105/106, 125/126, 205/206, 223/224),
  with several 16-bit-field high bytes shifting `0x0F`→`0x16` together — the
  shape of a single corrupted base/address value propagated to multiple emit
  sites, not ten independent flips.

  **No software source was found, and it self-cleared without any change.** The
  toolchain uses no randomness, no timestamps, and no threads within a single
  compile, and the self-host gate requires byte-identical `build == verify`, so
  output is deterministic by construction. After the event a determinism canary
  of 400 consecutive recompiles (200 compiler self-compiles + 200 of the failing
  test) was byte-identical with zero crashes, and full `bootstrap` / `test` /
  `test-nilpy` were green; the divergence never recurred. The leading suspicion
  is a transient hardware fault
  (a RAM or cache bit flip on non-ECC memory), not a compiler defect — the
  record-`Exit` fix itself is sound (it takes the source *address* for the
  `IR_COPY_REC` source instead of a loaded value).

  If it recurs, the cheap detector is a determinism canary —
  `for i in $(seq 1 200); do ./compiler/pascal26 test/hello.pas /tmp/t; cmp /tmp/t /tmp/golden || echo "DIVERGED $i"; done` —
  alongside `journalctl -k | grep -iE 'mce|edac|hardware error'` and a memtest86
  pass. Prefer ECC RAM for long unattended self-host runs. Full forensic write-up
  (system meta, byte-level `cmp` analysis, timeline):
  [`anomaly_2026-06-02_2000.md`](anomaly_2026-06-02_2000.md).

## C Interoperability

C header import is **delivered for the intended FFI-extraction model**, not an
unfinished active arc. It tolerantly parses large real-world header trees,
extracts callable symbols, typedefs, opaque aggregate pointers, enums, and
constants, strips common GCC/framework annotations, recursively rescans macros,
supports callbacks via `@proc`, and emits SysV AMD64 integer, floating-point,
variadic-vector-count, and stack-spill call ABI behavior.

SQLite is now driven end-to-end from Pascal (open/exec/prepare/step/columns)
and directly from Nil Python through `import sqlite3` (proven by
`test/test_nilpy_sqlite_crud.npy`); `const char*` marshalling (`PChar()`),
callee-return inference, auto `string`→`const char*`, strict trailing `T**`
out-param return-lifting, and returned `char*`→managed-string copying are done.
`lib/rtl/sqlitedb.pas` is now an optional facade, not required interop.

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
