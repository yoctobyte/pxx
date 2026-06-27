# C: va_arg with local function-pointer typedef in sqlite

- **Type:** bug (C frontend / typedef / varargs builtin) — Track C
- **Status:** backlog
- **Owner:** unassigned
- **Found / Opened:** 2026-06-27, M5 sqlite bring-up
  ([[feature-c-desktop-lua-sqlite-path]]), after local static multidimensional
  array initializers were fixed.

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

## Acceptance

- `__builtin_va_arg(ap, LocalFnPtrTypedef)` parses and yields a pointer-sized
  value.
- Add a focused regression using a block-scope function-pointer typedef passed
  as the `va_arg` type argument.
- sqlite advances past `sqlite3_config` case 16.
