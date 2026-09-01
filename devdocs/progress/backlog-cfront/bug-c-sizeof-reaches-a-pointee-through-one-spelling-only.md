# C: sizeof of a subscript through a pointer-to-pointer answers the pointer size

- **Type:** bug (Track C — C frontend, the sizeof operand path in
  `compiler/cparser.inc`)
- **prio:** 40
- **Status:** open

## What is left

Two spellings, measured against gcc 15.2.0 with
`struct big { char pad[40]; }; struct big **p2; struct big ***p3;`:

```
sizeof(p2[0][0])      pxx 8    gcc 40
sizeof(p3[0][0][0])   pxx 8    gcc 40
```

Everything else in this family is FIXED and guarded. `fde15c1d1` (frankC)
removed the `TokPos = savedPos` gate that stopped the general expression path
from running whenever a pattern arm had consumed part of the operand and then
failed, which took the family from 11 wrong spellings to 4; `e2ba5a1e1`
(frankD) fixed `sizeof(**p)` by counting stars. `*p2[0]`, `**&p2[0]` and
`*(*p2)` all answer 40 now. `test/csizeof_pointee_spellings.c` and
`test/csizeof_deref.c` hold the rows.

## Why these two did not fall out with the rest

Reaching the general expression path is not enough for them: subscripting
THROUGH a pointer-to-pointer is not something that path types correctly yet, so
it wants the machinery extended rather than merely reached. That is the
remaining work and it is why this is not a one-line follow-up to either commit.

`sizeof(x[0])` is a very common idiom, so the subscript spelling is not exotic
— but the specific broken case needs TWO levels (`p2[0][0]`), and a single
subscript on a pointer-to-pointer (`sizeof(p2[0])` = 8) is already right.

## Why it is worth doing

A wrong `sizeof` is not a wrong number, it is a wrong ALLOCATION, and it is
silent. The `**p` half of this family cost a day: ash's
`stzalloc(sizeof(**nlpp))` reserved 8 bytes for a 16-byte struct, the next
allocation's header overwrote the previous node, and the symptom was a command
substitution running a command whose NAME was garbage — three layers from
`sizeof`, with no diagnostic anywhere.

## Do not

Add a seventh token-pattern arm. Six of those is what produced the original
defect, and `fde15c1d1` showed the fix direction is DELETING a condition so the
type machinery runs, not adding another special case
(`devdocs/dev/normalise-dont-special-case.md`).

## Related

`bug-c-a-file-scope-pointer-to-array-crashes-on-indexing` (prio 70) — a
file-scope `int (*gp)[4]` SEGFAULTS on `gp[2][3]` where the byte-identical local
returns 23. Found by frankC while fixing the above; three spellings there moved
from 8 to 4, both wrong, and on a shape that crashes when indexed the sizeof
delta is not the problem. Fix that one first if you are in this area.
