# Cross-target codegen gaps (deferred v1 shortcuts)

- **Type:** feature
- **Status:** working
- **Owner:** claude
- **Unblocks:** feature-cross-bootstrap-selfhost
- **Opened:** 2026-06-11 (user request)

## Motivation

Collected smaller correctness/coverage gaps left as v1 shortcuts while bringing
the managed runtime up on i386/ARM32/AArch64. Individually minor; several matter
for the cross self-host and for not leaking memory.

## Scope

1. **Managed-local release at scope exit** — the cross epilogues skip the
   managed-local release loop, so AnsiString/dyn-array/record locals **leak**
   (output correct, memory not). Needs the per-target epilogue to walk
   scope-managed syms and call the release helpers. Interacts with
   feature-cross-exceptions (release also runs during unwinding).
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

## Acceptance

Each item has a focused cross test (oracle vs x86-64); the v1 shortcut is
removed. Can be closed incrementally — split into sub-tickets if a single item
grows large.

## Log
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
