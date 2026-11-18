---
track: C
tags: [cfront, initialisers, designators, arrays, pathb, st]
prio: 85
type: bug
blocked-by: []
summary: "An unsized array of pointers (or structs) with a `[k] =` designator was sized by its ELEMENT count, not by max index + 1. st's `colorname[] = { ..., [255] = 0, \"#cccccc\", \"#555555\", \"gray90\", \"black\" }` came out 20 long instead of 260, so its default foreground, background and cursor colours were past the end and st drew no text. Flat int lists were already right (CBraceFlatIntInitCountAt)."
status: done
owner: pxx2
---

# A designator in a pointer-array initialiser was not counted

cparser.inc CBraceTopLevelInitCountAt: a `[k] =` at the start of an element
sets the running index. The index is folded with CBraceDesignatorExprIdx,
which handles literals, enumerators and constant expressions. The count is
the highest index written plus one. An index that does not fold keeps the old
element count.

Test: test/c_designator_ptr_array_count.c (row c_desigcnt26) against gcc,
x86-64 and i386. It covers file and block scope, string pointers, structs
and enumerator indices.
