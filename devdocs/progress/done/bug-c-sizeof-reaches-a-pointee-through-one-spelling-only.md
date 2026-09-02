---
owner: frankC
---

# C: sizeof of a subscript through a pointer-to-pointer answers the pointer size

- **Type:** bug (Track C — C frontend, the sizeof operand path in
  `compiler/cparser.inc`)
- **prio:** 40
- **Status:** done
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

## Fixed 2026-09-02 — and "Why these two did not fall out" was wrong

The ticket says the general expression path "does not type subscripting through
a pointer-to-pointer correctly yet, so it wants the machinery extended rather
than merely reached." **Measured: it types them correctly and always did.** One
pair of parentheses is the whole experiment —

```
sizeof(p2[0][0])     8      <- CSizeofDescriptorWalk claims the operand
sizeof((p2[0])[0])  40      <- identical operand; the leading `(` stops the walk
sizeof(*(p2[0]))    40
struct big x = p2[0][0];    <- copies all 44 bytes correctly
```

So the walk was not short of a capability; it was ANSWERING WITHOUT ONE. It
peels one pointer level per subscript while carrying only ONE level of pointee
(`PtrElemTk`/`PtrElemRec`): the first peel consumed the last thing it knew, the
second landed on `tyUnknown`, and `TypeSlotSize(tyUnknown)` is 8 — the same
number a correct `sizeof(p2[0])` produces, which is exactly why it read as
working rather than as missing.

Fix: the walk follows `SymPtrDepth` / `SymPtrBaseTk` / `SymPtrBaseRec`, the
chain carriers `ParseCSizeof`'s own `**p` arm already reads. Depth 0 or 1 keeps
the original two lines, so a plain `T *p` is untouched. No new pattern arm.

Also fixed by the same change, not previously recorded here: `sizeof(p2[0]->pad)`
answered **1**. Peeling the pointer dropped the record, so `->` had nothing to
resolve the field against and fell to the element size of the `char[40]`.

## Verified

`test/c_sizeof_subscript_through_pointer_chain.c` (+ `.expected`). Sizes are
compared against the object actually pointed at, never a constant; the
one-subscript-short rows must equal a POINTER while the full-depth rows must
not, and a row asserts the two numbers differ at all — so a chain collapsing to
one default fails in both directions rather than satisfying half the suite. The
already-correct spellings (`**p2`, `*p2[0]`, `*(*p2)`, `(p2[0])[0]`) are the
in-test control, plus a paren-vs-bare agreement row.

Positive control against the **pinned** compiler: exactly 3 rows fail —
`p2[0][0]`, `p3[0][0][0]`, `p2[0]->pad` — and every "must not move" row and
every control passes, so the test isolates this defect and nothing else.
Neighbours `csizeof_pointee_spellings` and `csizeof_deref` still pass.
`gate.sh quick` GREEN, FPC seed canary PASS.

## Banked, not fixed

The walk can still finish with `cOK = True` and `cTk = tyUnknown` and answer
`TypeSlotSize(tyUnknown)` — a size it never established, wearing the pointer
default. Depth removes the case this ticket was about; it does not remove the
shape. See [[bug-c-the-sizeof-descriptor-walk-answers-from-tyunknown]] for why
declining there is not a free change.

## Log
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 536a3e2d0.
