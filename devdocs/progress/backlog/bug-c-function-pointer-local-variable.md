# C: function-pointer local variable declaration not parsed

- **Type:** bug (C frontend → local declaration) — Track C
- **Status:** backlog
- **Owner:** unassigned
- **Found / Opened:** 2026-06-27, M5 sqlite bring-up
  ([[feature-c-desktop-lua-sqlite-path]]). Next wall after the fn-ptr struct
  member fix ([[bug-c-function-pointer-struct-member]] +
  [[bug-c-call-inline-function-pointer-struct-member]], both done).

## Symptom

A function-pointer **local variable** declared with an initializer fails:

```c
static int sqlite3OsSectorSize(sqlite3_file *id){
  int (*xSectorSize)(sqlite3_file*) = id->pMethods->xSectorSize;   /* <- here */
  return (xSectorSize ? xSectorSize(id) : 4096);
}
```
```text
pascal26:20679: error: expected C expression
```

So the local-declaration parser (the `<type> name [= init]` path,
`ParseCLocalDecl` or similar) does not handle the `RET (*name)(params) = init`
function-pointer declarator form. The struct-member case was just fixed in
`ParseCStructInto`; the local-variable path needs the same treatment.

## Likely shape of the fix

`ParseCDeclType` already recognises `(*name)(params)` and exposes the name
(`CTypeFnPtrName` + `CTypeFnPtrNameOff/Len`) and signature (`CTypeProcSig`)
(see the struct-member fix). The local-decl parser must, when `CTypeFnPtrName <>
''`, allocate the local under that name as an 8-byte pointer carrying the proc
sig, then parse the `= init` and the rest — instead of expecting to read the
name token itself (which ParseCDeclType already consumed). Mirror the
ParseCStructInto branch.

NB: keep the off/len in mind — and note the `CTypeFnPtrName*` globals get reset
by the parameter recursion inside ParseCDeclType, so read them only after it
returns (already handled at the source; just consume them).

## Repro

```c
typedef int sqlite3_file;
struct M { int (*xSectorSize)(sqlite3_file*); };
struct F { struct M *pMethods; };
static int call(sqlite3_file *id, struct F *f){
  int (*xSectorSize)(sqlite3_file*) = f->pMethods->xSectorSize;
  return (xSectorSize ? xSectorSize(id) : 4096);
}
```
(reduce against the fixed compiler).

## Acceptance

- The repro + sqlite line 20679 compile; `xSectorSize` calls indirectly.
- Test in `test/`; C tests green + self-host byte-identical.

## Log

- 2026-06-27 - Filed at checkpoint, immediately after the fn-ptr struct member
  fix unblocked the earlier wall. Same fn-ptr family, local-variable site.
