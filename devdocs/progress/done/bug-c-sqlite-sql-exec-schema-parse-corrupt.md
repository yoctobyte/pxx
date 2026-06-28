# C: sqlite SQL exec reports corrupt sqlite_master during schema parse

- **Type:** bug (C frontend / sqlite bring-up) — Track C+A
- **Status:** done
- **Owner:** unassigned
- **Found / Opened:** 2026-06-28, after fixing
  [[bug-c-sqlite-sql-exec-schema-argv-pointer]].

## Resolution

Done 2026-06-28. The self-compiled SQLite unity driver now executes:

```text
open=0
exec=0
close=0
```

The richer `test/csqlite_extended_test.c` also completes table creation, index
creation, inserts, selects, transaction update/delete, aggregate `COUNT/SUM/AVG`,
and close. The last crash on the path was not schema corruption; it was the
inline nested aggregate pointer-field bug fixed under
`bugfix-cfront-sqlite3-crash-vdbecursor-layout.md`.

## Symptom

The self-compiled SQLite amalgamation now opens and closes `:memory:` cleanly.
The current probe:

```c
sqlite3_exec(db, "CREATE TABLE t(id INTEGER, name TEXT);", 0, 0, 0);
```

now reaches VDBE execution but still fails before `SQLITE_OK`. As of the latest
2026-06-28 run it returns `SQLITE_ERROR` (`1`) with:

```text
unrecognized token: "#"
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

Earlier reductions below describe the previous `SQLITE_CORRUPT` and VDBE crash
states.

## 2026-06-28 update

The original `SQLITE_CORRUPT` return was reduced to two C frontend bugs and is
no longer the current failure:

- `SCHEMA_TABLE(0)` (`cond ? "sqlite_temp_master" : "sqlite_master"`) was
  passed to `const char*` as `"sqlite_master" + 8` (`"aster"`), because C
  ternary string-literal arms lower to a pointer temp but call marshalling still
  applied the frozen-string `+8` adapter from the original AST type. Guard:
  `test/cternary_string_ptr_b118.c`.
- `sizeof(db->aLimit)` returned `8` instead of `48` for a fixed array field
  reached through a struct pointer. SQLite copied only two `aHardLimit[]`
  entries, leaving `SQLITE_LIMIT_COLUMN` as zero and reporting
  `too many columns on sqlite_master`. Guard:
  `test/csizeof_array_field_b119.c`.

Further reduction cleared two more SQLite blockers:

- Inline nested aggregate array members such as SQLite's
  `struct ExprList_item { ... } a[1]` were recorded as a scalar embedded record,
  so `struct ExprList_item *a = pEList->a` loaded the first member instead of
  decaying to the array address. Guard:
  `test/carray_field_decay_nested_item_b120.c`.
- Named C bitfields are now byte-packed with masked loads/stores. This matches
  SQLite's `Column`, `ExprList_item`, and `SrcItem` layout, and exposed/fixed
  `sizeof(p->aCol[0])`, which returned `8` instead of the `Column` element size
  and under-allocated schema columns. Guard:
  `test/csizeof_ptr_field_index_b122.c`.

With these fixes, the public `sqlite3_exec(... CREATE TABLE ...)` advances past
schema parsing, SELECT expansion, and column-array construction. It then hit a
segfault inside `sqlite3VdbeExec`: `OP_OpenRead` did not allocate cursor 0, so
the following `OP_Rewind` dereferenced `p->apCsr[0] == NULL`.

That VDBE crash was a C switch-lowering bug: SQLite has legal case labels inside
the compound block for `case OP_ReopenIdx: { ... case OP_OpenRead: ... }`.
Switch lowering only scanned top-level switch-body statements, so nested
`case OP_OpenRead` / `case OP_OpenWrite` labels emitted body labels but no
dispatch tests. Guard: `test/cswitch_nested_case_block_b127.c`.

With nested switch labels fixed, the clean libc-free probe now reports:

```text
open=0
exec=1
exec-msg=unrecognized token: "#"
close=0
```

The next reduction should identify where that `#` token enters the SQL text or
token stream.

## Acceptance

- Reduce or identify why preparing SQLite's built-in
  `CREATE TABLE x(type text,name text,tbl_name text,rootpage int,sql text)`
  fails.
- `sqlite3_exec(... CREATE TABLE ...)` on the self-compiled amalgamation returns
  `SQLITE_OK`.
- Then add the external-vs-self-compiled SQL parity test
  ([[test-sqlite-external-vs-self-compiled-parity]]).
