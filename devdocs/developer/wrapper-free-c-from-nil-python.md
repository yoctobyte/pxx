# Wrapper-Free C From Nil Python

PXX is trying to make a small native compiler where each frontend can use the
same real system interfaces. Pascal should not get special C access while Nil
Python is forced through hand-written glue. If a C header is usable, every
frontend should be able to import it directly.

The concrete proof is SQLite. A Nil Python program can now import the system
`sqlite3` header and call the C API itself:

```python
import sqlite3

db = sqlite3_open("/tmp/test_nilpy_sqlite_crud.db")
sqlite3_exec(db, "CREATE TABLE t(id INTEGER, name TEXT);", 0, 0, 0)
sqlite3_exec(db, "INSERT INTO t VALUES(1, 'alice');", 0, 0, 0)

stmt = sqlite3_prepare_v2(db, "SELECT id, name FROM t ORDER BY id;", -1)
while sqlite3_step(stmt) == SQLITE_ROW:
    print(sqlite3_column_int(stmt, 0), sqlite3_column_text(stmt, 1))

sqlite3_finalize(stmt)
sqlite3_close(db)
```

There is no `sqlitedb.pas` wrapper in that path. The program imports `sqlite3`
directly, the compiler reads `/usr/include/sqlite3.h`, emits the dynamic call
metadata for `libsqlite3.so.0`, and generates the native x86-64 call sequence.

## The Magic

SQLite is a useful test because its API is not shaped like Python. It uses C
handles, callback pointers, integer constants, `const char*` strings, returned
`char*` text, and out-parameters such as:

```c
int sqlite3_open(const char *filename, sqlite3 **ppDb);
```

Nil Python has no source-level `&db`, no pointer declarations, and no C string
type. The compiler handles the mismatch:

- `import sqlite3` uses the same unit/header resolver as Pascal `uses sqlite3`.
- Header import records C pointer element types and parameter pointer depth.
- A trailing depth-2 out-param (`T**`) is return-lifted, so
  `db = sqlite3_open(path)` allocates a hidden `T*`, passes its address to C,
  and gives Nil Python the resulting handle.
- Python strings passed to pointer parameters are marshalled as C
  NUL-terminated `const char*` values.
- Returned C `char*` text is copied into a managed PXX string. The C memory
  stays foreign-owned, following the project rule: whoever reserves, frees.
- C integer `#define` constants such as `SQLITE_ROW` become ordinary constants.
- Function-pointer parameters collapse to `Pointer`, so `0` can be passed when
  no callback is needed.

That is compiler sauce with a little magic spice, not wrapper code.
A `sqlitedb.pas` facade was removed 2026-06-06; the direct SQLite proof never
depended on it.

## Why This Matters

The goal is not to clone Python or build a giant runtime. The goal is a small
self-hosting native compiler where frontends share the same backend and the same
interop machinery. When C imports work at the compiler level, handwritten
wrappers become taste and convenience, not infrastructure.

Regression: `test/test_nilpy_sqlite_crud.npy`.
