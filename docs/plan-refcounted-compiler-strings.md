# Plan: flip the compiler to refcounted (managed) strings

**Status:** mapping only — no code written yet. (Authored 2026-06-04.)

## Why

The compiler self-compiles **without** `PXX_MANAGED_STRING`, so every
`AnsiString` it declares is a *frozen* string: a fixed inline buffer.

- A **global** frozen string reserves `STRING_CAP + 8 = 8 MB` each
  (`symtab.inc` `if CurProc < 0 then sz := STRING_CAP + 8`).
- A frozen string **record field** reserves `LOCAL_STR_CAP + 8 = 264 B` each.

The compiler's static BSS is ≈ **1.6 GB**, almost entirely these inline
buffers:

| Source | Count | Each | Subtotal |
|---|---|---|---|
| Global `AnsiString` scalars (`defs.inc`) | 18 | 8 MB | 144 MB |
| Global string arrays (`ResPendName/File`, `GFSig_PNames`) | 40 elems | 8 MB | 320 MB |
| `string` fields in big record arrays (`Syms[131072]`, `Procs[16384]`, `Strs[8192]`, params, …) | many | 264 B | the rest |

Refcounted strings are an **8-byte handle** plus heap allocated on demand, so
the flip collapses the BSS reserve from ~1.6 GB to tens of MB, with the live
string bytes moving to the existing on-demand managed heap (256 MB mmap arena,
grows as needed). This is the memory win the flip buys.

## What already works in our favour

- **Managed dynamic-array fields, COW, retain/release, scope finalization** —
  landed (`test/test_dynarray_field.pas`, `test/test_collections.pas`).
- **Allocator churn is NOT a blocker.** A 2 M-iteration managed string-concat
  loop runs flat at **264 KB** peak RSS (the result-move + arg-temp-ownership
  fixes from the prior managed-string batch retired the old crash). So heavy
  string churn — which the compiler does harder than anything — is survivable.
- The managed `SetLength` dynamic-array path (specialId 102) already accepts the
  managed lowering (`IR_LOAD_SYM` of a `tyAnsiString`), so the lowering shape is
  understood.

## Gap classes (what blocks `pascal26 -dPXX_MANAGED_STRING compiler/compiler.pas`)

### A. String builtins that read/write a fixed inline buffer
These assume the destination is a frozen 8 MB buffer addressed via `IR_LEA`, and
must be reimplemented to allocate a *sized* managed buffer and publish the
handle. Under managed strings the arg lowers to `IR_LOAD_SYM`/`tyAnsiString`,
not `IR_LEA`, so today they hit hard `Error(...)` guards.

- `LoadFile` (specialId 100, `EmitLoadFile` `symtab.inc:1617`): reads a whole
  file into `dst.data` with `read(fd, dst, STRING_CAP)`. Managed: stat/size the
  file, `SetLength(dst, size)`, read into the managed data pointer.
  **First error hit:** `LoadFile expects string variables in IR codegen`
  (`ir_codegen.inc:2907`).
- `ArgStr` (specialId `Ord(tkArgStr)`, `ir_codegen.inc:3190`): copies
  `argv[i]` C-string into a string var. Managed: size the C-string, allocate,
  copy.
- argv-copy helper (`symtab.inc:1591`): same pattern.
- `SetLength` on a string (specialId 101, guard `ir_codegen.inc:2920`): align
  with the managed array path (102).
- Guard inventory: `ir_codegen.inc` lines 2907, 2920, 2933, 3200.

### B. `var` / `out` AnsiString parameters
44 sites across the compiler (`grep "var … : AnsiString"`). Managed by-ref
string params pass the **handle-slot address**; a callee that assigns or
`SetLength`s the param must update the caller's handle with retain/release.
Verify the managed var-param store path is correct (it is only lightly
exercised today) and add targeted tests before trusting the compiler's heavy
use of this idiom.

### C. `Source` and other whole-file buffers
`Source : AnsiString` holds an entire source file. Frozen caps it at 8 MB
(silently truncates larger inputs); managed sizes it exactly — a correctness
*improvement*, but it depends on gap A (the file read path) being managed-aware.

### D. The unknown error tail
The compile stops at the first error (LoadFile). Errors past it are not yet
enumerated. A dedicated probe phase is required: implement gap A, then iterate
`-dPXX_MANAGED_STRING` compiles collecting each subsequent error/idiom until the
compiler produces a binary.

### E. Byte-identical re-baseline
Once the managed compiler self-compiles, a **new** byte-identical baseline must
be established:
- managed compiler compiles `compiler.pas` → managed compiler′; iterate to
  fixedpoint (`make bootstrap` semantics) until byte-identical.
- `make fpc-check`: the FPC seed builds with FPC's real `AnsiString`. Its output
  must match the managed self-hosted binary. This is the hardest gate — the two
  string runtimes differ in capacity assumptions, but the *emitted* code must
  match if the logic matches. Expect to chase divergences here.

## Staged plan

- **Phase 0 — mapping (this doc).** Done: premise confirmed, win quantified,
  allocator-churn risk retired, gap classes A–E identified.
- **Phase 1 — managed string builtins.** Reimplement gap-A builtins under
  `PXX_MANAGED_STRING` (size + allocate + publish handle); leave the frozen path
  untouched so the current default build stays byte-identical. Add unit tests
  for `LoadFile`/`ArgStr`/`SetLength(string)` on managed strings.
- **Phase 2 — var/out string params.** Audit and fix managed by-ref string
  semantics; regression test assign-through and `SetLength`-through a `var`
  string param.
- **Phase 3 — drive the self-compile.** Iterate
  `pascal26 -dPXX_MANAGED_STRING compiler/compiler.pas`, fixing the error tail
  (gap D) until a managed compiler compiles `hello.pas` correctly.
- **Phase 4 — fixedpoint.** Managed compiler self-compiles to byte-identical
  (gap E, self-hosted half).
- **Phase 5 — FPC-seed parity + flip the default.** Reconcile `fpc-check`,
  switch the build to define `PXX_MANAGED_STRING` by default (keep the frozen
  path available), re-green `test` / `test-nilpy` / `fpc-check`, and measure
  BSS + compile-time RSS before/after.

## Risk register

| Risk | Severity | Note |
|---|---|---|
| Each gap-A builtin is a real codegen rewrite, not a guard tweak | Med | Scoped; 4–5 sites |
| `var`/`out` string param managed semantics latent-buggy | Med | 44 call sites; lightly tested today |
| Unknown error tail (gap D) could be long | **High** | Only the first error is known; needs the probe phase to size |
| FPC-seed byte-identical parity (gap E) | **High** | Two string runtimes must emit identical code |
| Compile-time perf change under real workload | Low–Med | First-fit free-list is O(freelist) per alloc; measure compile time, not just RSS |
| Allocator crash under churn | **Retired** | 2 M-concat loop flat at 264 KB |

## Cheap experiments already run

- `pascal26 -dPXX_MANAGED_STRING compiler/compiler.pas` → stops at
  `LoadFile expects string variables in IR codegen` (gap A, expected).
- 2 M-iteration managed concat loop → 264 KB peak RSS, no crash (gap C/churn
  retired).
