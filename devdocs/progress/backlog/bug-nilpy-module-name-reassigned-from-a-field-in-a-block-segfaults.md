---
track: N
prio: 55
type: bug
blocked-by: []
summary: "Linked-list traversal at MODULE level segfaults: `n = n.next` inside a while/if block keeps n's class-typed module binding while a variant field is written into it. The identical two statements straight-line are fine, and the identical loop inside a def is fine — it is the module-level block. Sibling of the fixed subscript case, one shape over"
---

# A module name reassigned from a FIELD inside a block segfaults

- **Type:** bug (segfault) — **Track N**
- **Found:** 2026-08-12, differential bug hunting against CPython.
- **Sibling:** [[bug-nilpy-module-name-reassigned-from-a-subscript-in-a-block-reads-garbage]]
  — same site, same cause, one shape over (a subscript there, a field read
  here). That one read garbage; this one crashes.

```python
class Node:
    def __init__(self, v):
        self.v = v
        self.next = None

head = Node(1)
head.next = Node(2)
n = head
total = 0
while n is not None:      # textbook linked-list traversal
    total += n.v
    n = n.next            # <-- second iteration SEGFAULTS
print(total)              # CPython: 3
```

## The boundary — measured, and it is narrow

| shape | result |
| --- | --- |
| module level, `n = n.next` inside `while` / `while True` | **SIGSEGV** |
| module level, the same two statements STRAIGHT-LINE | correct (`2`) |
| the same traversal inside a `def` | correct (`3`) |
| `n = other[k]` inside a block (the sibling) | garbage — fixed |

So the value, the field and the loop are all fine; it is specifically a
**module-level** name bound to a class and then reassigned **inside a block**
from a member read.

## Cause, by analogy with the fixed sibling

`PyCollectModuleLocalsAST`'s depth>0 arm types a name bound inside a block from
a short list of SAFE, no-parse shapes (a literal, a name already resolvable, a
subscript, a constructor call). A member read — `n = n.next` — is not on that
list, so the name keeps the type its module-level binding gave it (`Node`), and
the variant the field actually holds is written into a class-typed slot. The
sibling ticket documents that exact mechanism for `current = table[k]`; a
`.field` source is the same statement one token different.

The subscript arm notes **tyVariant**, which is the honest answer for a
container element, and the same is true of a field: `self.next = None` makes it
variant, so the name that receives it is variant too, and the dunder/dynamic
path then handles `n.v`.

## The fix

One more shape in that arm's safe list: `name = <ident>.<name>` where the
receiver identifier is already visible to the pre-pass (`PyFindConstraint` or
`PyProgSym` answers), typed **tyVariant** — exactly beside the subscript test it
sits next to. Recognising it needs no parse, so it cannot hit the
Error()-and-Halt landmine that arm's header warns about.

Check the chained form (`n = n.next.next`) and the qualified one
(`x = obj.a.b`) in the same change: they are the same token shape and must not
be left as a third case.

## Gate

A `.npy` diffed against CPython: the traversal above at module level and in a
def, the straight-line control, a field read inside `if` / `for` / `while`, a
chained field read, and the sibling's subscript case still working.
