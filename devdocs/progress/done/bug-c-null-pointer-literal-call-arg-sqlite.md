# C: null pointer literal call arg lowers as address in sqlite

- **Type:** bug (C frontend / IR lowering / call arguments) — Track C
- **Status:** DONE (2026-06-27)
- **Owner:** Track C+A
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

## Resolution (2026-06-27, Track C+A)

Root cause was **not** the literal-`0` argument — that path was already correct
(reductions passed). The crash came from `openDatabase`'s body indexing the
file-scope **function-pointer array** `sqlite3BuiltinExtensions[i](db)`. The
inline declarator `static int (*const arr[])(T)` is fully consumed by
`ParseCDeclType` (name → `CTypeFnPtrName`, the `[..]` dimension → new
`CTypeFnPtrArrLen`), so `ParseCGlobalVarDecl`'s name loop saw `=`/`;` instead of
an identifier and **never registered the global** — every `arr[i]` reference
folded to a bare `0`, and `IRLowerAddress(AN_INT_LIT)` (via the `AN_INDEX` base)
fell through to `IR_UNSUPPORTED`.

Fixes (all C-frontend; self-host byte-identical, `make test` green):

1. **`cparser.inc` ParseCDeclType** — capture the `(*name[N])` array dimension
   into a new global `CTypeFnPtrArrLen` (defs.inc); stash it in a local across
   the param-list recursion (which resets the global) and restore it with the
   name, mirroring `CTypeFnPtrName`.
2. **`cparser.inc` ParseCGlobalVarDecl** — a new branch registers the inline
   fn-ptr (array) global as an `AllocArray` of callable pointers (or a scalar
   pointer), guarded by `baseTk = tyPointer` so a struct/union global whose last
   member is a fn pointer (`struct { void (*f)(void); } g;`, e.g. sqlite's
   `sqlite3Hooks`) — which leaves `CTypeFnPtrName` set as leftover but yields
   `baseTk = tyRecord` — falls through to the normal record-var path. The brace
   initializer is materialised as per-element proc-address `PendingInit`s
   (`PendingInitKind = 2` → `AN_PROCADDR`). Element callability is carried on
   `SymElemProcSig` (NOT `SymProcSig`, which would mark the array variable itself
   a proc value and corrupt indexing).
3. **`cparser.inc` CNodeProcSig** — resolve `arr[i](args)` through the base
   array sym's `SymElemProcSig` so the call lowers to `AN_CALL_IND`.
4. **`cparser.inc` ParseCSizeof** — `sizeof(arr[i])`/`sizeof(p[i])` now yields
   ONE element's size (subscript follows the ident), not the whole array. This
   pre-existing bug made the ubiquitous `ArraySize(x)` idiom
   `sizeof(x)/sizeof(x[0])` fold to `1`, so the built-in-extension loop ran a
   single iteration.

Result: `sqlite3.c` fully lowers; with a `main` it links + runs through
`sqlite3_open`. Regression `test/cglobal_fnptr_array_b109.c` (exit 42) exercises
the indexed-call loop + static proc-address init + the struct-field guard.

**Next wall (separate):** running `sqlite3_open(":memory:")` now hits a runtime
`undefined symbol: sqlite3MemSetDefault` — a memory-subsystem function
referenced but compiled out under the current config. Filed as
[[bug-c-sqlite-undefined-symbol-memsetdefault]].
