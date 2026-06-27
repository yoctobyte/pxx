# C: sqlite offsetof-style field address in array bound

- **Type:** bug (C frontend / parser / constant expression) — Track C
- **Status:** done
- **Owner:** Track CA
- **Found / Opened:** 2026-06-27, M5 sqlite bring-up
  ([[feature-c-desktop-lua-sqlite-path]]), after the ternary pointer-array
  indexing wall was fixed.
- **Closed:** 2026-06-27

## Symptom

sqlite stopped at:

```text
Expected: ], but got:  (Kind: 81, Line: 91408)
  near:  Parse     >>>  sLastToken
pascal26:91408: error: unexpected token ()
```

Preprocessed source:

```c
char saveBuf[(sizeof(Parse)-((size_t)&(((Parse *)0)->sLastToken)))];
```

This is sqlite's `offsetof(Parse,sLastToken)` expansion (`PARSE_RECURSE_SZ`) in
an automatic array bound.

## Cause

`ParseCLocalDeclAST` evaluates fixed array dimensions with `CEvalConstExpr`.
That folder handled integer arithmetic and `sizeof(...)`, but not unary `&`.
For `((size_t)&(((Parse *)0)->sLastToken))`, it consumed the `(size_t)` cast,
then returned `0` at `&` without consuming the field-address expression. The
declarator still saw `sLastToken` while expecting `]`.

## Fix

`CEvalConstPrimary` now recognizes unary `&` for the narrow macro-expanded
`offsetof` shape `&(((T *)0)->field)`. It parses the cast type to recover the
record id, returns `RecFieldOffset(record, field)`, and restores the CType
globals after the nested `ParseCDeclType` call.

## Regression

Added `test/coffsetof_constexpr_array_b104.c`, wired into `make test-core`.

Also rechecked existing nearby coverage:

- `test/csizeof_constexpr_b20.c`
- `test/coffsetof_array_field_b55.c`

## Result

sqlite advances to:

```text
pascal26:105031: error: call to undeclared function: sqlite3OsDlSym ()
```

Filed [[bug-c-function-returning-function-pointer-prototype-sqlite]].
