# Cross-target codegen gaps (deferred v1 shortcuts)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
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

## Acceptance

Each item has a focused cross test (oracle vs x86-64); the v1 shortcut is
removed. Can be closed incrementally — split into sub-tickets if a single item
grows large.
