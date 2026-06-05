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

### B. `var` / `out` AnsiString parameters — by-ref STORE now implemented (2026-06-05)
Assign-through-`var` and concat-through-`var` now work and are leak/over-free
free under a 2 M churn loop (`test/test_managed_var_param.pas`). The fix had two
parts: lower a managed-string by-ref arg to a USER proc as `IR_SLOTADDR` (the
unconditional slot-address lea) instead of `IRLowerAddress`→`IR_LEA` — `IR_LEA`
auto-loads the handle for a `tyAnsiString` in read mode, so it passed the handle
by value; restricted to `cpi >= 0` so builtins like `Length` (which flag
`isRefArg` but want the handle) are unaffected; and the `IR_STORE_SYM`
`tyAnsiString` path now, for an `IsRef` param, derefs the slot to release the
caller's old handle and publish the new one. An arg that is itself a by-ref
managed param keeps `IR_LEA` (its slot already holds the forwarded address).

**`SetLength` through a `var` string — now done (2026-06-05).** The
`specialId`-102 SetLength codegen read the old data pointer from, and published
the new one into, `Syms[symIdx].Offset` directly; for an `IsRef` param that slot
holds the *address* of the caller's handle, so the resize silently no-op'd at the
caller. The 102 path now branches on `(Kind = skParam) and IsRef` at all three
emit sites — the old-pointer read, the grow/shrink publish, and the zero-length
release publish — derefing the slot to reach the caller's. Regression:
`test/test_managed_setlength_var.pas` (shrink/grow/zero through `var` + plain-local
no-regression). The same no-op exists for `SetLength(var dynarray)` and is fixed
by the same generic branch. Gap B is now fully resolved.

The original analysis, kept for reference:

### B (orig). `var` / `out` AnsiString parameters — CONFIRMED UNIMPLEMENTED (real work)
44 sites across the compiler (`grep "var … : AnsiString"`). This is **not**
touch-up — it is missing managed runtime. A by-ref managed string today is
passed **by value** (a copy of the 8-byte handle), not as the address of the
caller's handle slot, so a store in the callee never reaches the caller and the
borrow/release bookkeeping on the copied handle is wrong. Verified 2026-06-04 on
`/tmp/v{1,2,3}.pas` under `PXX_MANAGED_STRING`:

| Callee op | Frozen | Managed (today) |
|---|---|---|
| `s := 'hello'` (assign-through-var) | caller updated → `hello` | silently no-ops → caller still `OLD` |
| `s := s + '!'` (concat-through-var) | works | **segfault** |
| `SetLength(s, 3)` (setlength-through-var) | works | silently no-ops → caller unchanged |

Frozen var-params work only because the param *is* the buffer — a store copies
bytes in place. Correct managed semantics for a by-ref string store: deref the
ref to reach the caller's slot, **release the old handle there, store the new
handle, retain as needed** (the borrow-on-read path stays as is). That store
path does not exist yet; it is the true first blocker, ahead of the gap-A
builtins. The compiler relies on this idiom heavily (~44 sites), so it is
load-bearing.

### C. `Source` and other whole-file buffers
`Source : AnsiString` holds an entire source file. Frozen caps it at 8 MB
(silently truncates larger inputs); managed sizes it exactly — a correctness
*improvement*, but it depends on gap A (the file read path) being managed-aware.

### D. The unknown error tail
The compile stops at the first error (LoadFile). Errors past it are not yet
enumerated. A dedicated probe phase is required: implement gap A, then iterate
`-dPXX_MANAGED_STRING` compiles collecting each subsequent error/idiom until the
compiler produces a binary.

### F. `SetLength` on a plain-local managed string — NOT a bug (retracted 2026-06-05)
Re-tested under the current build: `s := 'hello'; SetLength(s,3)` correctly
prints `hel` with `Length(s) = 3`; grow + zero-fill, index-write into the grown
region, and `SetLength(s,0)` all behave. The earlier `hel <garbage>` report did
not reproduce — the prior managed-string batch had already aligned the
`tyAnsiString` case of the `-102` path (the `add rax, 17` header + nul-terminator
handling). Only the by-ref case (gap B above) was actually broken, and it is now
fixed.

**Adjacent bug found, not yet fixed:** a *named* dynamic-array type used as a
variable (`type T = array of Integer; var a: T`) misroutes `SetLength(a, n)` to
the `-101` string path → `SetLength expects a string variable in IR codegen`,
even for a plain local. The parser routing (`parser.inc` ~3658) keys on
`Syms[idx].IsArray and ArrLen = -1`, which the named-alias symbol doesn't carry;
the inline form (`var a: array of Integer`) works. Out of scope for the managed
arc; flag for a parser-routing pass.

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
| `var`/`out` string param managed by-ref store | **Resolved** | Assign + concat + `SetLength` through `var` all implemented & tested (2026-06-05); gap B fully closed |
| `SetLength` on a plain-local managed string | **Retracted** | Not a bug — works; gap F report did not reproduce |
| Unknown error tail (gap D) could be long | **High** | Only the first error is known; needs the probe phase to size |
| FPC-seed byte-identical parity (gap E) | **High** | Two string runtimes must emit identical code |
| Compile-time perf change under real workload | Low–Med | First-fit free-list is O(freelist) per alloc; measure compile time, not just RSS |
| Allocator crash under churn | **Retired** | 2 M-concat loop flat at 264 KB |

## Cheap experiments already run

- `pascal26 -dPXX_MANAGED_STRING compiler/compiler.pas` → stops at
  `LoadFile expects string variables in IR codegen` (gap A, expected).
- 2 M-iteration managed concat loop → 264 KB peak RSS, no crash (gap C/churn
  retired).
- Managed by-ref string param (`var s: AnsiString`) assign / concat / SetLength
  → caller-no-op / segfault / caller-no-op (gap B confirmed unimplemented; now
  the first thing being built).
