# C: sqlite offsetof-style field address in array bound

- **Type:** bug (C frontend / parser / constant expression) — Track C
- **Status:** backlog
- **Owner:** unassigned
- **Found / Opened:** 2026-06-27, M5 sqlite bring-up
  ([[feature-c-desktop-lua-sqlite-path]]), after the ternary pointer-array
  indexing wall was fixed.

## Symptom

sqlite now advances to:

```text
Expected: ], but got:  (Kind: 81, Line: 91408)
  near:  Parse     >>>  sLastToken
pascal26:91408: error: unexpected token ()
```

Repro:

```sh
./compiler/pascal26 -Ilibrary_candidates/sqlite library_candidates/sqlite/sqlite3.c /tmp/sqlite3
```

Preprocessed source:

```c
char saveBuf[(sizeof(Parse)-((size_t)&(((Parse *)0)->sLastToken)))];
```

This is sqlite's `offsetof(Parse,sLastToken)` expansion (`PARSE_RECURSE_SZ`) in
an automatic array bound.

## Notes

The parser reaches `sLastToken` while expecting the closing `]`, so the likely
missing shape is a constant-expression path for an address-of field expression
through a casted null pointer: `&(((T *)0)->field)`. This may need either:

- parse support for the full expression in C array bounds, if the declarator
  path is currently using a narrower const evaluator; and/or
- constant folding for `offsetof`-style field addresses.

Do not conflate this with the older lua `__builtin_offsetof` ticket; sqlite is
using the macro-expanded address expression here, not the builtin spelling.

## Acceptance

- sqlite advances past line 91408.
- Add a focused C regression for an automatic array bound using
  `sizeof(struct)-((size_t)&(((struct *)0)->field))`.
