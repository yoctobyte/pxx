# C: local static const multidimensional array initializer in sqlite

- **Type:** bug (C frontend / local static initializer) — Track C
- **Status:** backlog
- **Owner:** unassigned
- **Found / Opened:** 2026-06-27, M5 sqlite bring-up
  ([[feature-c-desktop-lua-sqlite-path]]), after external function-address
  values were fixed.

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

## Acceptance

- Block-scope `static const` multidimensional arrays with nested brace
  initializers parse and materialize correctly.
- Add a focused regression using sqlite's `u8 trans[8][8]` shape.
- sqlite advances past `sqlite3_complete`.
