# C: address of external libc function used as function pointer

- **Type:** bug (C frontend / external symbol codegen) — Track C
- **Status:** done
- **Owner:** Track CA
- **Found / Opened:** 2026-06-27, M5 sqlite bring-up
  ([[feature-c-desktop-lua-sqlite-path]]), after function-returning-function-
  pointer declarations were fixed.
- **Closed:** 2026-06-27

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

## Fix

`IR_PROCADDR` now allows external routines on x86-64 by loading the routine's
resolved address from the same dynamic GOT slot used by external calls. The new
`EmitExternalProcAddr` helper registers the external if needed and emits
`mov rax, qword ptr [absolute address]`, with the address patched through the
existing dynamic-call fixup table.

Non-x86-64 targets keep the previous explicit rejection until their backends grow
an equivalent address-load sequence.

## Regression

Added `test/cexternal_func_addr_b106.c`, wired into `make test-core`.

## Result

sqlite advances past `unixDlSym` and now stops at:

```text
pascal26:139609: error: expected C expression ()
```

The new wall is a block-scope static 2D initializer in `sqlite3_complete`:

```c
static const u8 trans[8][8] = {
  { 1, 0, 2, 3, 4, 2, 2, 2, },
  ...
};
```

Filed [[bug-c-local-static-const-multidim-array-init-sqlite]].
