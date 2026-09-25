---
prio: 30
track: C
summary: 'sizeof of a ROW reached through a pointer to array answers the element size or the pointer size, silently. The mechanism: ParseCSizeof sizes a general expression by the node''s result type (ASTTk), and a node carries no pointee-array descriptor, so a row is only sized correctly when a per-shape arm recognises the spelling. `sizeof(*p)` on a bare identifier has such an arm (SymPtrElemArrLen, CSizeofTryArrayDeref). Any other spelling of the same row falls through: `sizeof(p[0])`, `sizeof(*(0, p))`, `sizeof(*(int (*)[3])q)`. Found while landing array-typed compound literals, 2026-09-25. Nothing runs wrong until a program uses the size, e.g. memcpy(dst, p[i], sizeof p[i]) copies 4 bytes of a 12-byte row.'
---

# sizeof of a pointer-to-array row reached by an expression

Measured 2026-09-25, x86-64, HEAD at c99f594735 plus the array-CL change.
`int iz[2][3]; int (*p)[3] = iz;`

| expression | gcc | pxx |
| --- | --- | --- |
| `sizeof(*p)` | 12 | 12 |
| `sizeof(p[0])` | 12 | 4 |
| `sizeof(*(0, p))` | 12 | 8 |
| `sizeof(*(int (*)[3])iz)` | 12 | 8 |

The subscripts and derefs themselves are correct: the values read through
every one of these spellings match gcc. Only the size is wrong.

Fix direction: give sizeof a node-level answer. Walk the operand the way
IRPointerStride / ResolveNodeRec do (strip the comma, the cast and the
deref/index), and find the pointer symbol's SymPtrElemArrLen/NDims. Don't add a
fifth per-spelling arm.
