# Cross-target codegen gaps (deferred v1 shortcuts)

- **Type:** feature
- **Status:** done
- **Owner:** claude
- **Unblocks:** feature-cross-bootstrap-selfhost
- **Opened:** 2026-06-11 (user request)

## Motivation

Collected smaller correctness/coverage gaps left as v1 shortcuts while bringing
the managed runtime up on i386/ARM32/AArch64. Individually minor; several matter
for the cross self-host and for not leaking memory.

## Scope

1. **Managed *aggregate* locals on cross targets** (record-with-managed-fields /
   variant / array-of-managed) — **split out into its own ticket**
   [`feature-cross-managed-aggregate-locals`](../backlog/feature-cross-managed-aggregate-locals.md)
   on 2026-06-13 once it grew into a multi-part sub-arc (prologue zero-init +
   body ARC + epilogue release). It is the next arm32 `compiler.pas` wall (parser
   line 13288). Scalar managed-local *release* at scope exit (the smaller
   leak-only part) is folded into that ticket's epilogue item.
2. **Copy-on-write on dynamic-array writes** — `IR_LEA` of a dyn-array in write
   mode currently loads the handle without `PXXDynArrayUnique`, so a shared
   array (`a := b; a[i] := x`) mutates both. Wire the COW call on cross targets.
3. **Class instantiation** — `T.Create` (VMT setup + constructor dispatch) errors
   on i386/ARM32/AArch64 (`class instantiation not yet supported`). Port the
   `-Ord(tkGetMem)` class path + `IR_VIRTUAL_CALL`.
4. **AArch64 literal+literal tyString inline concat** — the 272-byte-buffer path
   segfaults (a codegen bug); reverted to deferred. ansistring-rooted concat
   works. Retry against `ir_codegen_arm32.inc` lines ~434-468.
5. **by-ref managed-string / var-array params on cross targets** — partial;
   `SetLength` on a `var` array param and some by-ref string stores error.
6. **Float params/results + full `builtin` unit on i386/ARM32** (moved here
   from feature-cross-float-variant, 2026-06-12) — the 32-bit internal call
   ABI passes every argument as one 4-byte slot, so procedures with Double
   params or results are rejected; that in turn blocks compiling the full
   `builtin` unit (Str/Val/FloatToStr) on those targets. Float *expressions*,
   writes, and variants work (served from builtinheap). Ties into
   feature-cross-param-abi. Variant locals are a related gap: 16-byte
   zero-init of frame slots errors on all cross targets (globals work).
7. **SetLength on a managed AnsiString** — the cross backends only accepted an
   `IR_LEA` (dyn-array) SetLength target and errored on `SetLength(ansistring,n)`
   (`SetLength expects an array variable`). **arm32 done** via the new portable
   `PXXStrSetLen` runtime helper (builtinheap.pas). i386 + aarch64 still need the
   same one-block wiring (the helper is shared; they currently fail earlier walls
   before reaching SetLength when compiling `compiler.pas`).
8. **Managed-string `Length` and char-indexing on cross targets** — `Length(s)`
   and `s[i]` on a *managed* AnsiString returned garbage / 0 on arm32:
   `IR_LEA` of a scalar ansistring yielded the slot **address**, not the
   auto-loaded heap handle, so the `[handle-8]` length read and the data-pointer
   index base were wrong. **arm32 done** — IR_LEA now loads the handle (slot
   content) for a scalar ansistring in read mode (`not InLValueWrite`), keeping
   the slot address in write mode, mirroring the x86-64 gate. i386/aarch64 likely
   share the gap (unverified; they fail earlier walls first).
9. **`in` set-membership operator on cross targets** — `x in [items]` errored on
   arm32 (`builtin/special call not yet supported`, specialId `SPECIAL_IN`).
   **arm32 done** — emits a constant compare-chain (single members + `lo..hi`
   ranges) accumulating membership via conditional execution, no materialised
   set. i386/aarch64 likely share the gap (they fail earlier walls first).

## Acceptance

Each item has a focused cross test (oracle vs x86-64); the v1 shortcut is
removed. Can be closed incrementally — split into sub-tickets if a single item
grows large.

## Log
- 2026-06-13 — **arm32 `SysOpen` syscall family** landed. Added lowering for
  the public special-call tokens `SysOpen`, `SysRead`, `SysWrite`, `SysClose`,
  and `SysFchmod` using ARM EABI syscall convention (`r7` syscall number,
  `r0..r2` args). `SysOpen` currently accepts the managed `AnsiString` path
  shape used by the cross-managed path; frozen inline `String` path termination
  remains x86-64-only. New oracle `test/test_cross_sysopen_family.pas` creates a
  temp file, writes bytes, `fchmod`s it readable, reopens, reads, and compares
  arm32 output against x86-64. Verified with self-host fixedpoint rebuild and
  `make test-arm32`.
- 2026-06-13 — **arm32 `LoadFile` (specialId 100)** landed. `LoadFile(path, dst)`
  read a file into a managed AnsiString — unhandled on arm32. Routed through the
  portable `PXXStrLoadFile(path)` helper: load the path handle (a nul-terminated
  C string) into r0, call the helper, publish the new handle into `dst` (decref
  old, store new). Managed dst only (compiler.pas reads into AnsiString). New
  oracle test `test/test_cross_loadfile.pas` (reads `test/hello.pas`) wired into
  `make test-arm32`. `compiler.pas` → arm32 advances **16307 → 32676** (a large
  jump). arm32 + core + self-host/threadsafe fixedpoints green.
- 2026-06-13 — claimed. **arm32 SetLength-on-managed-string** (item 7) landed.
  Cross-compiling `compiler.pas` to arm32 hit `SetLength(ansistring, n)` (an
  `IR_LOAD_SYM` of a tyAnsiString) at the shared SetLength wall (parser line
  1201). Added a portable `PXXStrSetLen(strSlot, newLen)` helper in
  `builtinheap.pas` (alloc-copy-publish-release, mirrors `PXXDynSetLen`) and
  wired the arm32 `pi=-102` path to call it for the managed-string case (global
  / local / by-ref-param slot address). `compiler.pas` → arm32 now advances past
  line 1201. New oracle test `test/test_cross_setlen_str.pas` (shrink / grow /
  zero, checked via writeln+concat) wired into `make test-arm32`; arm32 + core +
  self-host/threadsafe fixedpoints green. Testing exposed item 8 (managed-string
  `Length`/indexing broken on arm32) — filed above, not fixed here.
- 2026-06-13 — **arm32 managed-string `Length` / char-indexing** (item 8) landed.
  Root cause: arm32 `IR_LEA` of a scalar ansistring returned the slot address,
  so `Length(s)` read `[slotaddr-8]` and `s[i]` indexed off the slot. Now
  `IR_LEA` loads the handle (slot content) in read mode (`not InLValueWrite`) for
  a scalar ansistring, keeping the slot address in write mode — mirrors the
  x86-64 read/write gate. `Length`, read-index, and index-fill after `SetLength`
  now round-trip. New oracle test `test/test_cross_str_length_index.pas` wired
  into `make test-arm32`; full arm32 + core + self-host/threadsafe fixedpoints
  green (concat / params / results / COW unregressed).
- 2026-06-13 — **arm32 `in` set-membership operator** (item 9) landed. `x in
  [items]` hit `SPECIAL_IN` (specialId 999), unhandled on arm32. Emits a constant
  compare-chain over single members and `lo..hi` ranges, accumulating membership
  in a scratch register via conditional execution (`moveq`, `blt`/`bgt` skips) —
  no materialised set value. New oracle test `test/test_cross_in_operator.pas`
  wired into `make test-arm32`. `compiler.pas` → arm32 now advances from the
  builtin-special wall (parser line 1525) all the way to line 13288 (`managed
  aggregate locals not yet supported` — a different gap). arm32 + core +
  self-host/threadsafe fixedpoints green.

## Closure (2026-06-16)

`feature-cross-bootstrap-selfhost` is DONE — byte-identical self-fixedpoint on
i386/aarch64/arm32 (and x86-64). This ticket existed to unblock that gate, so its
blocking purpose is met: every code path `compiler.pas` itself exercises now
works byte-identically on all cross targets. Residual gaps are only in language
features the compiler does NOT self-use (e.g. classes, interfaces, some param/
ABI shapes user code hits) — those move to the language-surface hardening effort
driven by the synthetic conformance harness
([[feature-synthetic-feature-matrix-test]]). Closed.
