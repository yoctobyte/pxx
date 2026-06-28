# C: block-scope static record arrays in sqlite VFS init

- **Type:** bug (C frontend / storage + initializer lowering) — Track C
- **Status:** DONE (2026-06-28)
- **Owner:** Track C+A
- **Found / Opened:** 2026-06-28, while debugging the self-compiled sqlite
  amalgamation after `sqlite3_open(":memory:")` reached SQLite initialization.

## Symptom

SQLite's Unix VFS initializer declares a block-scope static record array:

```c
static sqlite3_vfs aVfs[] = {
  UNIXVFS("unix", posixIoFinder),
  ...
};
```

The frontend effectively dropped `static`, allocated the array as normal stack
storage, inferred the unsized record array as one element, and skipped the
record-field initializers. `sqlite3_os_init()` could return success while
`vfsList` was null or pointed at invalid/zeroed storage, and
`sqlite3MemdbInit()` then failed or crashed.

## Resolution

- Block-scope `static` declarations now parse as declarations and allocate their
  storage globally while still appearing in statement position.
- Local record-array brace initializers now infer the top-level element count
  and emit per-field assignments for scalar/pointer fields.
- SQLite's `sqlite3_os_init()` now registers a persistent `unix` VFS, and
  `sqlite3_open(":memory:")` + `sqlite3_close` succeeds.

Regression: `test/clocal_static_record_array_b115.c`.
