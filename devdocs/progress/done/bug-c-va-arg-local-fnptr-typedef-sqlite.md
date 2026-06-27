# C: va_arg with local function-pointer typedef in sqlite

- **Type:** bug (C frontend / typedef / varargs builtin) — Track C
- **Status:** done
- **Owner:** Track CA
- **Found / Opened:** 2026-06-27, M5 sqlite bring-up
  ([[feature-c-desktop-lua-sqlite-path]]), after local static multidimensional
  array initializers were fixed.
- **Closed:** 2026-06-27

## Symptom

sqlite now advances to:

```text
Expected: ), but got: LOGFUNC_t (Kind: 1, Line: 140250)
  near: xLog  __builtin_va_arg  ap  >>> LOGFUNC_t
pascal26:140250: error: unexpected token ()
```

Preprocessed source around the wall:

```c
case 16: {
  typedef void(*LOGFUNC_t)(void*,int,const char*);
  LOGFUNC_t xLog = __builtin_va_arg(ap, LOGFUNC_t);
  void *pLogArg = __builtin_va_arg(ap, void*);
  (*(&sqlite3Config.xLog) = (xLog));
  (*(&sqlite3Config.pLogArg) = (pLogArg));
  break;
}
```

## Notes

`__builtin_va_arg` parses its second argument via `ParseCDeclType`. Earlier
sqlite uses of `va_arg(ap, int)`, `va_arg(ap, T*)`, and file-scope typedefs
advance, but this local function-pointer typedef is not consumed as a type in
the builtin's type slot. The parser then expects `)` and still sees `LOGFUNC_t`.

Likely area: block-scope `typedef void (*Name)(...)` registration and/or
`ParseCDeclType` recognition of procedural typedef aliases inside the
`__builtin_va_arg` type argument.

## Fix

`ParseCStatementAST` now recognizes block-scope `typedef` declarations, routes
them through the existing `ParseCTypedef` registration path, and emits an empty
statement node because typedefs have no runtime effect.

This lets `typedef void (*LOGFUNC_t)(...)` inside a `case` block register the
function-pointer typedef before `__builtin_va_arg(ap, LOGFUNC_t)` parses its
type argument with `ParseCDeclType`.

## Regression

Added `test/cva_arg_local_fnptr_typedef_b108.c`, wired into `make test-core`.

## Result

sqlite advances past `sqlite3_config` case 16 and now stops at:

```text
Unsupported linear node in IR codegen! Kind=10 node=749 IRA=1 IRB=-1 IRC=-1 IRIVal=0
pascal26:142434: error: Unsupported linear node in IR codegen ()
```

The current source is:

```c
int sqlite3_open(const char *zFilename, sqlite3 **ppDb){
  return openDatabase(zFilename, ppDb, 0x00000002 | 0x00000004, 0);
}
```

`IRA=1` is `AN_INT_LIT`; the likely issue is lowering literal `0` as an
addressable argument for the `const char *zVfs` parameter instead of as a null
pointer value. Filed [[bug-c-null-pointer-literal-call-arg-sqlite]].
