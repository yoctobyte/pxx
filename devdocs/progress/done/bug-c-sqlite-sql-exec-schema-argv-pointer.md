# C: sqlite SQL exec crashes in schema callback argv string path

- **Type:** bug (C frontend / pointer lowering) — Track C+A
- **Status:** DONE (2026-06-28)
- **Owner:** unassigned
- **Found / Opened:** 2026-06-28, after self-compiled sqlite
  `sqlite3_open(":memory:")` + close began passing.

## Symptom

A self-compiled sqlite amalgamation can now initialize, register the Unix VFS,
open `:memory:`, and close cleanly. The next SQL step crashes:

```c
sqlite3_exec(db, "CREATE TABLE t(id INTEGER, name TEXT);", 0, 0, 0);
```

With `-g`, gdb maps the fault to the preprocessed SQLite schema init callback
around:

```c
else if( argv[4]
      && 'c'==sqlite3UpperToLower[(unsigned char)argv[4][0]]
      && 'r'==sqlite3UpperToLower[(unsigned char)argv[4][1]] ){
```

The faulting address has the shape `0xffffffff????????`: a valid heap pointer
appears to have been truncated to 32 bits and sign-extended before dereference.
Small standalone reductions of `char **argv` callback indexing pass, so the
trigger is likely deeper in SQLite's row/schema decoding path that populates the
callback argv array.

## Root Cause

The bad pointer was not actually one of the schema `argv[]` strings. SQLite was
calling:

```c
corruptSchema(pData, argv, sqlite3_errmsg(db));
```

Inside `sqlite3_errmsg`, this expression narrowed a pointer through a hidden
ternary temp:

```c
z = db->errCode ? (char*)sqlite3_value_text(db->pErr) : 0;
```

The C frontend did not treat `AN_PTR_CAST` as a pointer-valued expression, so
`(char*)sqlite3_value_text(...) : 0` was typed/lowered as `int`. The call
returned the full heap pointer in `rax`, then the ternary stored only `eax` and
sign-extended it back to a bogus `0xffffffff...` pointer.

## Resolution

Pointer casts now carry cast depth/base metadata and participate in C pointer
detection helpers, so pointer/null ternaries keep pointer-width storage.
Regression: `test/cptr_return_text_b116.c`.

With this fixed, the self-compiled sqlite `CREATE TABLE` probe no longer
segfaults. It now returns `SQLITE_CORRUPT` from the next schema-parse issue,
tracked separately as [[bug-c-sqlite-sql-exec-schema-parse-corrupt]].

## Acceptance

- A focused reducer or the sqlite `CREATE TABLE` probe identifies the exact
  pointer truncation path.
- The self-compiled sqlite `CREATE TABLE` probe no longer faults in the schema
  error path.
