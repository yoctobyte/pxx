# C: function returning function pointer prototype not registered

- **Type:** bug (C frontend / declaration parser) — Track C
- **Status:** done
- **Owner:** Track CA
- **Found / Opened:** 2026-06-27, M5 sqlite bring-up
  ([[feature-c-desktop-lua-sqlite-path]]), after the `offsetof` const-array
  bound wall was fixed.
- **Closed:** 2026-06-27

## Symptom

sqlite stopped at:

```text
pascal26:105031: error: call to undeclared function: sqlite3OsDlSym ()
```

Call site:

```c
xInit = (sqlite3_loadext_entry)sqlite3OsDlSym(pVfs, handle, zEntry);
```

But the preprocessed source contained both a prototype and a definition:

```c
static void (*sqlite3OsDlSym(sqlite3_vfs *, void *, const char *))(void);

static void (*sqlite3OsDlSym(sqlite3_vfs *pVfs, void *pHdle, const char *zSym))(void){
  return pVfs->xDlSym(pVfs, pHdle, zSym);
}
```

## Cause

The declaration parser treated `ret (*name(params))(retargs)` like a
function-pointer variable declarator, not like a real function named `name`.
`ParseCDeclType` consumed the whole declarator, leaving no identifier for
`ParseCSubroutine` to register, and `CTopLevelIsFunc` did not recognize the
shape as a function.

## Fix

`ParseCDeclType` now distinguishes:

- `ret (*var)(args)` — function-pointer variable/field/param/typedef.
- `ret (*fn(params))(args)` — function returning a function pointer.

For the second shape it captures the real function's name and parameter
metadata. `ParseCSubroutine` consumes that side-channel and registers/compiles
the routine as a normal C function returning `Pointer`.

## Regression

Added `test/cfn_return_fnptr_b105.c`, wired into `make test-core`.

## Result

sqlite advances to:

```text
pascal26:33764: error: @ on external routine not supported; wrap it in a local routine ()
```

Filed [[bug-c-external-function-address-dlsym-sqlite]].
