---
track: N
prio: 57
type: bug
blocked-by: []
summary: "`def a(): q = Item(5); return q.n` is typed tyClass (the RECEIVER's class) while the value it returns is the field's int. Printing is correct today only because the wrong type happens to render as an integer — the moment anything treats a tyClass node as an object, the same program SEGFAULTS. It is the blocker under bug-nilpy-str-of-a-plain-instance-prints-the-handle-and-a-class-typed-none-prints-zero"
status: done
owner: claude-AN
---

# A def returning `obj.field` is typed as the receiver's CLASS

- **Type:** bug (wrong static type; currently masked) — **Track N**
- **Found:** 2026-08-12, by a rendering fix that this bug made unsafe to ship.

```python
class Item:
    def __init__(self, n):
        self.n = n

def a():
    q = Item(5)
    return q.n

print(a())        # prints 5 — correct VALUE
```

The value is right and the program looks fine. But `a`'s inferred return type is
**tyClass (Item)**, not the field's type: `PXXDBG=n.locals` shows the local as
`tk=6 rec=0`, and the proof is what happens when anything trusts that type.

## How it was found — and why it matters more than it looks

The fix for
[[bug-nilpy-str-of-a-plain-instance-prints-the-handle-and-a-class-typed-none-prints-zero]]
routes a `tyClass`-typed node through `pyobj_str_of` so an instance renders as
CPython's `<__main__.N object at 0x…>`. With that in place, the program above
**segfaults**: the renderer dereferences the integer 5 as an object pointer.

So today's correct output is a coincidence — the wrong TYPE and the right VALUE
cancel out, because the integer path prints an integer and the value is an
integer. Any change that treats a `tyClass` node as an object (a renderer, a
dunder dispatch, a refcount, an `isinstance`) turns it into a crash. That is
exactly what the rendering fix hit, and why that fix was reverted rather than
shipped: it would have crashed `def f(): return obj.field`, which is one of the
most ordinary bodies in Python.

The name does not matter — `q = Item(5)` fails the same way as `item = Item(5)`,
so this is NOT the case-insensitive class-name collision
([[project_nilpy_name_matching_a_class_is_typed_as_that_class]]); it is the
field read itself losing its type on the way into the return.

## Where to look

`PyInferDefRetType`'s member-read arm: for `return <ident>.<field>` it appears to
answer the receiver's class rather than looking the FIELD up in that class and
taking its recorded type (`UFldTk`). The class registration already knows every
field's type — the field pre-pass records it — so the fix is a lookup, not new
inference. Check `PyMethodRetType` in the same change: the method spelling of
the same body must agree, or the signature and the frame disagree, which is the
silent-ABI-mismatch hazard both sites warn about.

## Gate

A `.npy` diffed against CPython: a def returning a field of each kind (int,
str, float, list, a class-typed field, an unannotated ctor-param field); the
method spelling of each; the value asserted AND `type(...).__name__` asserted so
the type is checked and not just the rendering; a def returning a CHAIN
(`return q.inner.n`); and — the reason this is blocking — `print()`, `str()`
and an f-string of each result.

## Log
- 2026-08-12 — resolved, commit PENDING-COMMIT.
