# Thread-safe layout RTTI helper races

- **Type:** bug
- **Status:** done
- **Owner:** codex
- **Blocked-by:** feature-rtti-layout-table
- **Found / Opened:** 2026-06-11 (post-RTTI layout validation)

## Symptom

The target-independent layout RTTI helpers centralize managed record and dynamic
array retain/release/COW behavior in `builtinheap.pas`, but not every generated
call path has the same thread-safety guarantees as the old inline x86-64 code.

Known risky paths:

- `IR_DYNUNIQUE` emits a direct `PXXDynArrayUnique` call for nested dynamic-array
  writes without wrapping it in `EmitAcquireHeapLock`. The helper can allocate,
  retain copied elements, publish the slot, and release the old block.
- `EmitManagedRecordRetain` delegates to `PXXRecordRetain`, whose string and
  dynamic-array refcount increments use non-atomic helper code. Some callers run
  under the heap lock, but retain is not intrinsically locked and record-copy
  paths can call it before acquiring the release lock.

Single-threaded and current regression tests pass, including `make test` and
`make test-nilpy`, but `{$threadsafe on}` programs that share managed records or
nested dynamic arrays across threads may race refcount updates or free-list
operations.

## Acceptance

- Define a consistent locking/atomicity contract for layout RTTI helpers.
- Ensure every `PXXRecordRetain`, `PXXRecordRelease`, `PXXDynArrayRelease`, and
  `PXXDynArrayUnique` generated call path obeys that contract under
  `ThreadSafeMode`.
- Add a regression that exercises concurrent nested dynamic-array COW and
  managed-record copies with shared managed fields.
- `make test`, `make test-nilpy`, and `git diff --check` pass.

## Log

- 2026-06-11 — Filed after validation of `feature-rtti-layout-table`; tests are
  green, but static review found inconsistent locking around new RTTI helpers.
- 2026-06-11 — Fixed. Contract: Pascal layout RTTI helpers (`PXXRecordRetain`,
  `PXXRecordRelease`, `PXXDynArrayRelease`, `PXXDynArrayUnique`) run under the
  generated heap spinlock when `ThreadSafeMode` is active; call sites already in
  a compound resize/COW critical section use raw retain emitters to avoid
  re-entering the lock. `IR_DYNUNIQUE` now locks around `PXXDynArrayUnique`, and
  ARC-correct managed record copy retains source fields and releases destination
  fields inside one critical section. Public x86-64 string retain/release and
  dynamic-array retain paths now use the same heap lock in threaded mode so
  they cannot race the Pascal helpers' non-atomic refcount updates. Added
  `test/test_threadsafe_layout_rtti.pas`.
