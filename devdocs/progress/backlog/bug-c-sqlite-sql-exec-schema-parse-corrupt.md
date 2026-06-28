# C: sqlite SQL exec reports corrupt sqlite_master during schema parse

- **Type:** bug (C frontend / sqlite bring-up) — Track C+A
- **Status:** backlog
- **Owner:** unassigned
- **Found / Opened:** 2026-06-28, after fixing
  [[bug-c-sqlite-sql-exec-schema-argv-pointer]].

## Symptom

The self-compiled SQLite amalgamation now opens and closes `:memory:` cleanly,
and the first SQL execution no longer segfaults. The current probe:

```c
sqlite3_exec(db, "CREATE TABLE t(id INTEGER, name TEXT);", 0, 0, 0);
```

returns `SQLITE_CORRUPT` (`11`) with:

```text
malformed database schema (sqlite_master)
```

GDB breakpoint at `corruptSchema` shows the schema row is otherwise sensible:

```text
argv[0] = "table"
argv[1] = "sqlite_master"
argv[2] = "sqlite_master"
argv[3] = "1"
argv[4] = "CREATE TABLE x(type text,name text,tbl_name text,rootpage int,sql text)"
zExtra  = ""
```

So the next failing operation is SQLite's internal `sqlite3Prepare(db, argv[4],
...)` while `db->init.busy` is set.

## Acceptance

- Reduce or identify why preparing SQLite's built-in
  `CREATE TABLE x(type text,name text,tbl_name text,rootpage int,sql text)`
  fails.
- `sqlite3_exec(... CREATE TABLE ...)` on the self-compiled amalgamation returns
  `SQLITE_OK`.
- Then add the external-vs-self-compiled SQL parity test
  ([[test-sqlite-external-vs-self-compiled-parity]]).
