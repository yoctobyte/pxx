# C: address of external libc function used as function pointer

- **Type:** bug (C frontend / external symbol codegen) — Track C
- **Status:** backlog
- **Owner:** unassigned
- **Found / Opened:** 2026-06-27, M5 sqlite bring-up
  ([[feature-c-desktop-lua-sqlite-path]]), after function-returning-function-
  pointer declarations were fixed.

## Symptom

sqlite now advances to:

```text
pascal26:33764: error: @ on external routine not supported; wrap it in a local routine ()
```

Repro:

```sh
./compiler/pascal26 -Ilibrary_candidates/sqlite library_candidates/sqlite/sqlite3.c /tmp/sqlite3
```

Preprocessed source around the wall:

```c
static void (*unixDlSym(sqlite3_vfs *NotUsed, void *p, const char*zSym))(void){
  void (*(*x)(void*,const char*))(void);
  (void)(NotUsed);
  x = (void(*(*)(void*,const char*))(void))dlsym;
  return (*x)(p, zSym);
}
```

`dlsym` is declared from `<dlfcn.h>` as an external libc import. The C parser
represents a bare function name as `AN_PROCADDR`; x86-64 codegen currently
rejects `AN_PROCADDR` for external routines.

## Notes

This is not the same as taking the address of an internal C function. It needs a
codegen/linkage strategy for the address of an imported dynamic symbol, or a
frontend rewrite that calls the imported routine through a local wrapper when a
function pointer value is required.

## Acceptance

- A C expression can use an imported external function name as a function-pointer
  value, at least for the sqlite `dlsym` cast-call pattern.
- Add a focused regression using a declared external-like C function address or
  a stable local import shim.
- sqlite advances past `unixDlSym`.
