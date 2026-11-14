---
slug: bug-c-indexing-a-pointer-to-pointer-struct-member-loses-a-level
track: C
prio: 70
type: bug
status: done
created: 2026-11-14
found-by: claude-opus (toybox port)
tags: [c-frontend, toybox]
blocked-by: []
summary: "A `char **m` / `int **m` struct member did not record its pointer depth or ultimate base, so `*s.m[i]` and `**s.m` loaded 8 (or 4) bytes and `s.m[i][j]` indexed pointers. toybox's `*toys.optargs[1]` and devmem's 'bad width' came from it. Pre-existing (frozen compiler too). Members now carry UFldPtrDepth/BaseTk/BaseRec like locals carry SymPtr*."
---

# C: pointer-to-pointer members lost a level

The struct builder records depth/base for each member (first declarator from
ParseCDeclType, later declarators from their own stars over the base scalar);
CNodePtrDepth and CNodePtrBaseTk gained AN_FIELD arms via the new
CNodeFieldIdx. Not covered: a member whose base is itself a pointer typedef on
a later declarator (left unrecorded, as before) -- see
bug-c-a-pointer-typedef-loses-its-base-under-indexing. Test:
`test/c_toybox_compiler_shapes.c`.
