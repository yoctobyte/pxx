---
slug: bug-c-a-pointer-typedef-loses-its-base-under-indexing
track: C
prio: 50
type: bug
status: open
created: 2026-11-14
found-by: claude-opus (toybox port)
tags: [c-frontend, toybox]
blocked-by: []
summary: "`typedef char *str; str *c; *c[0]` loads 4 bytes instead of 1: a pointer typedef used as the base of a further pointer loses its ultimate base kind. Locals and struct members both; present in the frozen compiler too."
---

# C: pointer typedef as a pointer base

Found while fixing bug-c-indexing-a-pointer-to-pointer-struct-member-loses-a-level; out of that ticket's scope.
