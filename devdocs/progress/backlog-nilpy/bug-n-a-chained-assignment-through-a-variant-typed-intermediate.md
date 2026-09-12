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

## 2026-09-13 — both of yesterday's hypotheses are REFUTED, and the fault is the RECEIVER

Measured with the guard temporarily disabled, then the guard restored and the
binary verified byte-identical to the landed one (`127f2f6531d9`), so no probe
survives in the tree.

One program, one variant-typed receiver (`self.menu = make(1)`), three stores:

| store | CPython | pxx |
| --- | --- | --- |
| chain, **DECLARED** field (`.visible`) | `11 11` | **`11 True`** |
| chain, **UNDECLARED** field (`.fresh`) | `22 22` | `22 22` |
| single statement, undeclared field | `33` | `33` |

**Hypothesis 1 — "an AN_CALL store is dropped by the chain's PySeqAppend
sequence" — is false.** The undeclared-field row is a chain, goes through the same
`PyMakeDynAttrSet` AN_CALL, and is correct. The call fires.

**Hypothesis 2 — "PyForceVariant copies the receiver, so the write lands on a
copy" — is false** for the same reason: a write to a copy would not read back, and
`22 22` reads back.

**The actual mechanism.** For a DECLARED field reached through a variant receiver
the chain's STORE resolves dynamically while the READ of that declared field does
not, so the two use different doors: the dynamic write goes to the attribute side
table and the read returns the field's initial value (`True`). An undeclared field
has no second door, which is exactly why that row is correct — and is the control
that separates the two.

**Where the fix is, and where it is NOT.** The single-statement spelling of the
same store is correct, and both paths call the same builder, so the builder is not
the bug. `PyMakeAttrLoad` types `self.menu` from `UFldTk[...]`, which is not a
class here; the expression parser's receiver for the identical source is better
typed. **So fix the type of the receiver node the chain folds, not the store.**
Compare the two receivers with `PXXDBG=a.ast` before touching anything.

**And do not narrow the guard as a shortcut.** Allowing the undeclared-field case
through is correct in itself and would NOT unblock app.py:3204, whose field
`visible` is declared. Measured, not assumed.

### The cheap fix is refuted too — the receiver has NO class identity at all

Probed 2026-09-13, same session, guard restored and binary verified byte-identical
again (`127f2f6531d9`). `PyMakeAttrLoad` sets `ASTRight[node] := UFldRec_[fi]`, so
a field can carry a class RECORD while its KIND is variant, and both
`PyMakeAttrStore` and the guard gate on the KIND (`ASTTk = tyClass`) before ever
asking for the record. That looked like a one-line miss.

**It is not.** Rewritten to ask `ResolveNodeRec` unconditionally, the guard still
fires: for `self.menu` the answer is `< REC_UCLASS_BASE`. The field carries neither
a class kind nor a class record, so there is nothing on the node to recover and no
local fix inside these two routines.

**So the remaining work is genuinely NilPy type inference** — recording that a field
assigned from a function whose body returns `W()` holds a `W` — and its failure mode
is a store placed on the wrong door with no diagnostic. Parked deliberately on that
basis, not for lack of an angle.

**Next step for whoever picks it up, in order:** find how the SINGLE-statement path
obtains a usable class for the same receiver (it demonstrably does — `self.menu.visible = 11`
is correct), because that is an existing working answer to exactly this question, and
copying it beats inventing inference. `PXXDBG=a.ast` on the two procs, diff the
receiver subtrees.

**A measurement hazard that nearly produced a false reading here:** when the compile
FAILS, the previously built test binary is still on disk, so running it prints a full
set of plausible rows that belong to the earlier build. Check the compile's own exit
before reading any value it was supposed to produce.
