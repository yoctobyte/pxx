---
prio: 40  # auto
---

# SQLite SQL parity: external libsqlite3 vs self-compiled amalgamation

- **Type:** test / milestone validation — Track C+A
- **Status:** backlog
- **Owner:** unassigned
- **Found / Opened:** 2026-06-28, while checking sqlite amalgamation progress
  after granular system-library selection.
- **Blocked-by:** [[task-sqlite-libc-free-runtime-bringup]]

## Goal

Once the project-compiled sqlite amalgamation can open an in-memory database
without faulting, add a SQL parity test that runs the same SQL through:

1. the existing external `libsqlite3.so.0` import path (`uses sqlite3` /
   imported `sqlite3.h`), and
2. a self-compiled `library_candidates/sqlite/sqlite3.c` unity driver using the
   project CRTL sources.

Both paths should produce byte-identical output for a small deterministic
`CREATE TABLE` / `INSERT` / `SELECT ... ORDER BY` workload.

## Notes

The external path is already covered by several SQLite CRUD tests. The missing
piece is the self-compiled amalgamation runtime: it compiles, but
`sqlite3_open(":memory:")` currently still hits the CRTL/VFS bring-up wall.

## Acceptance

- A committed test builds both SQLite paths.
- Both binaries execute the same in-memory SQL workload.
- The expected output is shared and compared exactly.
- The test is wired into the appropriate C/SQLite gate once stable enough.
