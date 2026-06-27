# C: local static const multidimensional array initializer in sqlite

- **Type:** bug (C frontend / local static initializer) — Track C
- **Status:** done
- **Owner:** Track CA
- **Found / Opened:** 2026-06-27, M5 sqlite bring-up
  ([[feature-c-desktop-lua-sqlite-path]]), after external function-address
  values were fixed.
- **Closed:** 2026-06-27

## Symptom

sqlite now advances to:

```text
pascal26:139609: error: expected C expression ()
```

Repro:

```sh
./compiler/pascal26 -Ilibrary_candidates/sqlite library_candidates/sqlite/sqlite3.c /tmp/sqlite3
```

Preprocessed source around the wall:

```c
int sqlite3_complete(const char *zSql){
  u8 state = 0;
  u8 token;
  static const u8 trans[8][8] = {
    { 1, 0, 2, 3, 4, 2, 2, 2, },
    { 1, 1, 2, 3, 4, 2, 2, 2, },
    { 2, 2, 2, 3, 2, 2, 2, 2, },
    { 3, 3, 3, 3, 3, 3, 3, 3, },
    { 4, 4, 4, 4, 4, 4, 4, 4, },
    { 5, 5, 5, 3, 5, 5, 5, 5, },
    { 6, 6, 6, 3, 6, 6, 6, 6, },
    { 7, 7, 7, 3, 7, 7, 7, 7, },
  };
```

## Notes

The parser accepts the declaration prefix and first array dimensions, then reaches
the initializer and expects a scalar expression where the nested brace list
begins. This looks like a missing block-scope `static const` multidimensional
array materialization path, distinct from earlier file-scope and record-field
multidimensional array fixes.

## Fix

`ParseCLocalDeclAST` now consumes all bracket dimensions for block-scope C array
declarations, allocates multidimensional arrays as flattened row-major storage,
and records the usual `SymArrNDims`/`SymArrDimSpan` metadata. Nested brace
initializers for ordinal multidimensional arrays are flattened in encounter
order and emitted as declaration-time element assignments.

The C postfix parser now recognizes chained subscripts on symbol-backed
multidimensional arrays and lowers `a[i][j]` to a single `AN_INDEX` with the
existing flat N-D index helper.

## Regression

Added `test/clocal_static_const_2d_init_b107.c`, wired into `make test-core`.

## Result

sqlite advances past `sqlite3_complete` and now stops at:

```text
Expected: ), but got: LOGFUNC_t (Kind: 1, Line: 140250)
  near: xLog  __builtin_va_arg  ap  >>> LOGFUNC_t
pascal26:140250: error: unexpected token ()
```

The new wall is `__builtin_va_arg(ap, LOGFUNC_t)` where `LOGFUNC_t` is a
block-scope function-pointer typedef. Filed
[[bug-c-va-arg-local-fnptr-typedef-sqlite]].
