---
slug: bug-c-a-pointer-typedef-loses-its-base-under-indexing
track: C
prio: 50
type: bug
status: done
created: 2026-11-14
found-by: claude-opus (toybox port)
tags: [c-frontend, toybox]
blocked-by: []
summary: "`typedef char *str; str *c; *c[0]` loads 4 bytes instead of 1: a pointer typedef used as the base of a further pointer loses its ultimate base kind. Locals and struct members both; present in the frozen compiler too."
---

# C: pointer typedef as a pointer base

Found while fixing bug-c-indexing-a-pointer-to-pointer-struct-member-loses-a-level; out of that ticket's scope.

## Closed 2026-11-19 (pxx2)

Already correct when re-measured. `typedef char *str; str *c;` gives
`*c[0]`, `c[0][1]` and the struct-member spelling as 65/66, matching gcc. The
stars-over-a-pointer-typedef fold in ParseCDeclType
(bug-c-a-pointer-to-a-pointer-typedef-loses-the-pointee) covers it. Now guarded
by the `str` line of test/c_ptr_ptr_typedef.c (rows c_ppstruct26 and
c_ppstruct26_i386), which went in with the `T **` typedef fix
(bug-c-pointer-to-pointer-struct-member-reads-offset-0).
