---
track: N
prio: 85
type: bug
blocked-by: []
summary: "NOW BLOCKS THE lekkerzeilen CLOSURE AT app.py:3204 — re-prioritised 40 -> 85 on 2026-09-12 once that was measured rather than assumed. `self.nest.inner.visible = <other> = v`, where `inner` is DECLARED as None and only later holds an object, cannot place its store: the receiver fold yields a non-class node and the dynamic setter writes somewhere the declared read does not look. REFUSED BY NAME as of 2026-09-12 rather than silently storing nothing — the diagnostic says to split the chain, and that remedy is real because THE SINGLE-STATEMENT SPELLING IS CORRECT TODAY (`self.nest.inner.visible = 33` works, measured). So this is a gap in the CHAIN path only, and only for a receiver with no static class; statically typed intermediates of any depth work, including app.py:3204's own shape. Nothing that previously compiled is refused — before the nested-target widening a two-level target did not parse at all. The fix is to build the receiver the way the single-statement path does; that path resolves the same source correctly, so the difference between the two is the whole bug."
---

# A chained assignment through a variant-typed intermediate is refused

Residual of the nested-attribute chain widening landed 2026-09-12. Recorded as a
REFUSAL, not a miscompile, which is the only reason it is prio 40 and not 80.

## What happens

```python
class W:
    def __init__(self):
        self.visible = True
        self.inner = None          # <- declared None, so no static class

class A:
    def __init__(self):
        self.nest = W()
        self.nest.inner = W()      # ...but it holds a W at run time

    def go(self):
        self.nest.inner.visible = self.icon.visible = 33
```

```
error: Nil Python: in a chained assignment, the receiver of `visible` has no
static class here, so the store cannot be placed — split the chain into
separate assignments
```

Before the refusal was added this compiled clean and **stored nothing** into
`self.nest.inner.visible`, which is why the refusal is there: a plausible wrong
value with no diagnostic is the one outcome worth refusing over.

## What works, so the boundary is clear

- `self.nest.inner.visible = 33` as a SINGLE statement — **correct**, verified.
- A chain through a statically typed intermediate, at any depth — **correct**,
  verified to three levels.
- `self.icon.visible = self.menu.visible = False` (app.py:3204) — **correct**;
  that receiver is a constructed class.

## The fix

`PyParseChainAssign` folds intermediate levels with `PyMakeAttrLoad`, which
resolves a class off the base node and otherwise yields a dynamic get. The
statement path reaches the same store correctly, so copy its receiver
construction rather than inventing one here — and when it is fixed, move the
THREE row of `test/test_nilpy_chained_assign_nested_attr.npy` back to a
`None`-declared intermediate, which is the arrangement that fails.

## 2026-09-12, same day: this is the lekkerzeilen wall, and the lead is narrowed

**Raised 40 -> 85.** When filed I believed app.py:3204
(`self.icon.visible = self.menu.visible = False`) used statically typed
receivers and was unaffected. It is not: `self.menu = ui.menu(self.panels)` is a
FACTORY return, so that receiver has no static class and the refusal fires on it.

**The refusal is still right, and this is the measurement that says so.** With the
guard temporarily disabled, the same shape compiles and gives:

```
class W:
    def __init__(self, v=True): self.visible = v
def make(p): return W()
class A:
    def __init__(self):
        self.icon = W(); self.menu = make(1)
    def chain(self): self.icon.visible = self.menu.visible = 11
```
```
CPython:  chain 11 11
pxx:      chain 11 True      <- self.menu.visible stored NOTHING
```

So the closure reaching `app.py:3305` before the guard landed was **distance bought
with a silent wrong store**, which on this umbrella is the exact trap already
recorded as "the closure compiling is not the demo running". The guard is worth
the 101 lines.

### The lead, which was not in the ticket when filed

The SINGLE-statement spelling of the same store is correct
(`self.menu.visible = 11` gives 11), and both paths call the same builder — so the
difference is not the builder. Two candidates, both visible in
`PyMakeDynAttrSet`:

1. It returns an **AN_CALL** (`pyvar_setattr(recv, "name", val)`), where
   `PyMakeSubscriptStore` — which DOES work inside a chain sequence — returns an
   **AN_ASSIGN**. A call appended to the chain's `PySeqAppend` sequence may not be
   evaluated the way a statement-position call is.
2. Its receiver argument is `PyForceVariant(recvNode)`. If that COPIES the
   variant, the attribute is set on the copy. This would also have to explain why
   the statement path survives it, so check that before believing it.

Distinguish them before writing code: dump the chain's AST
(`PXXDBG=a.ast:<proc>`) for the working single statement and the failing chain and
diff the two store subtrees. Do not reason from the builders — they are shared.
