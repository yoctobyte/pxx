# C: null pointer literal call arg lowers as address in sqlite

- **Type:** bug (C frontend / IR lowering / call arguments) — Track C
- **Status:** backlog
- **Owner:** unassigned
- **Found / Opened:** 2026-06-27, M5 sqlite bring-up
  ([[feature-c-desktop-lua-sqlite-path]]), after block-scope function-pointer
  typedefs in `va_arg` were fixed.

## Symptom

sqlite now advances to:

```text
Unsupported linear node in IR codegen! Kind=10 node=749 IRA=1 IRB=-1 IRC=-1 IRIVal=0
pascal26:142434: error: Unsupported linear node in IR codegen ()
```

`IRA=1` is `AN_INT_LIT`.

Preprocessed source at the current line:

```c
static int openDatabase(
  const char *zFilename,
  sqlite3 **ppDb,
  unsigned int flags,
  const char *zVfs
);

int sqlite3_open(const char *zFilename, sqlite3 **ppDb){
  return openDatabase(zFilename, ppDb, 0x00000002 | 0x00000004, 0);
}
```

## Notes

The fourth argument is literal `0` for a `const char *` parameter. The IR error
indicates an address-lowering path received an integer literal, likely treating
the pointer parameter as needing an addressable argument instead of a pointer
value. This should reduce to an internal C function call with a pointer parameter
and `0`/`NULL` as the actual argument.

## Acceptance

- Passing `0`/`NULL` to a pointer parameter lowers as a null pointer value, not
  as the address of an integer literal.
- Add a focused regression around an internal C function with a `const char *`
  parameter called with literal `0`.
- sqlite advances past `sqlite3_open`.
