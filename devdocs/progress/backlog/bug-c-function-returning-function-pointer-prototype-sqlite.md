# C: function returning function pointer prototype not registered

- **Type:** bug (C frontend / declaration parser) — Track C
- **Status:** backlog
- **Owner:** unassigned
- **Found / Opened:** 2026-06-27, M5 sqlite bring-up
  ([[feature-c-desktop-lua-sqlite-path]]), after the `offsetof` const-array
  bound wall was fixed.

## Symptom

sqlite now advances to:

```text
pascal26:105031: error: call to undeclared function: sqlite3OsDlSym ()
```

Repro:

```sh
./compiler/pascal26 -Ilibrary_candidates/sqlite library_candidates/sqlite/sqlite3.c /tmp/sqlite3
```

Call site:

```c
xInit = (sqlite3_loadext_entry)sqlite3OsDlSym(pVfs, handle, zEntry);
```

But the preprocessed source contains both a prototype and a definition:

```c
static void (*sqlite3OsDlSym(sqlite3_vfs *, void *, const char *))(void);

static void (*sqlite3OsDlSym(sqlite3_vfs *pVfs, void *pHdle, const char *zSym))(void){
  return pVfs->xDlSym(pVfs, pHdle, zSym);
}
```

## Notes

This is likely a declaration-parser gap for C functions returning function
pointers: `RET (*name(args))(retargs)`. The existing function-pointer support
covers variables, params, struct fields, casts, and indirect calls, but this
shape names a real function whose return type is itself a function pointer.

The sqlite VFS struct field involved is:

```c
void (*(*xDlSym)(sqlite3_vfs*,void*, const char *zSymbol))(void);
```

That may also need to be represented correctly for the function body return
expression.

## Acceptance

- Register `sqlite3OsDlSym` from both prototype and definition forms.
- Compile a focused regression where a function returns a function pointer and
  the caller casts/calls or compares the returned pointer.
- sqlite advances past line 105031.
