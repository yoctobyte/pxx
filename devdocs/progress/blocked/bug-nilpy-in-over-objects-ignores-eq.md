---
track: N
prio: 50
type: bug
status: blocked
owner: ""
blocked-by: bug-nilpy-eq-dunder-skipped-when-either-operand-is-a-variant
---

# `obj in [list of objects]` ignores `__eq__` and compares identity

```python
class V:
    def __init__(self, v: int):
        self.v = v
    def __eq__(self, o) -> bool:
        return self.v == o.v

print(V(1) in [V(1), V(2)])     # CPython: True    pxx: False
```

`==` itself now dispatches `__eq__` (parser.inc, the comparison arm). `in` does
not, because membership is decided at RUN time by pylib's `PyVarEq`, which
compares two object slots by pointer and has a by-content case only for TPyList
and TPyDict. It has no way to reach back into a user method.

The machinery to do it exists in a neighbouring form: `pyvar_callv0..3`
(pyeval.pas) already tells the callable shapes apart at run time and invokes
them, which is how a def, a lambda and a bound method are all callable from a
variant. Membership needs the same trick for a per-class `__eq__` — most
directly, a slot in the object's class record pointing at its `__eq__` proc,
which PyVarEq calls when both operands are user objects.

Same fix covers `list.count(obj)`, `list.remove(obj)` and `dict` keyed by an
object, all of which route through PyVarEq.

Split out of [[bug-nilpy-eq-dunder-ignored]] when that landed.

## Gate

`make test-nilpy` + self-host byte-identical, plus `in`, `count` and `index`
over a list of objects with and without `__eq__`, and an object as a dict key.

## Recon 2026-07-30 — sized, not started

Confirmed the shape above is still the blocker: pylib's `PyVarEq` decides
membership and cannot reach a user method, so this needs a per-class `__eq__`
entry that pylib can call — i.e. a CLASS-RECORD / RTTI change, which is Track A
shared ground, not a pylib-local fix. That makes it a two-track item (A for the
slot, N for the dispatch), which is why it was left rather than started at the
tail of a long session. Note the stride landmine on that table:
[[project_rtti_method_table_multi_consumer_stride_landmine]].


## 2026-08-04 — the premise is WRONG, and the cheap fix is ruled out by measurement

Picked this up to build the frontend-only version: lower `x in xs` into a loop
over `x == xs[i]`, which needs no runtime hook, because this ticket states that
"`==` itself now dispatches `__eq__`".

**It does not.** `==` dispatches `__eq__` only when BOTH operands are statically
class-typed. As soon as one is a VARIANT — which is what a container element and
a for-in variable are — it falls back to `PyVarEq` and compares pointers:

```python
a = V(1); b = V(1); xs = [V(1)]
print(a == b)         # True   correct
print(a == xs[0])     # False  CPython: True
print(a in xs)        # False  CPython: True
print(xs.count(a))    # 0      CPython: 1
```

So the loop rewrite would have expanded `in` into exactly the expression that is
already broken, and would have "fixed" nothing while looking plausible. Not
implemented; nothing changed in the tree.

That is a bigger and more user-visible defect than membership on its own — the
dunder works in the shape a minimal test uses (two named locals) and fails in
the shape real code uses — so it is filed with its own repro as
[[bug-nilpy-eq-dunder-skipped-when-either-operand-is-a-variant]] and carries the
higher priority.

**The 2026-07-30 recon's conclusion stands and is reinforced:** both tickets need
one thing, a way for `PyVarEq` to reach a user `__eq__` at run time, and fixing
it fixes `==`, `in`, `count`/`index`/`remove` and object dict keys together.

### One lead the recon did not have

`__pxxMethodAddress(Instance, Name)` (`compiler/builtin/builtin.pas`) already
walks a class's RTTI method table BY NAME at run time. Two things to settle
before building on it, both recorded on the sibling ticket: whether a NilPy
method carries `PXX_RTTI_METH_PUBLISHED` (that routine skips anything that does
not), and the ABI — `__eq__(self, o)`'s second parameter is a variant when
unannotated and a class pointer when annotated, so one fixed call signature
would miscompile half the cases. The safe shape is a compiler-emitted
fixed-signature wrapper per class, published under a known name.

Returned to `backlog/` with the premise corrected, blocked in practice on the
sibling above.

## 2026-08-10 — the blocker it describes in prose now has a real edge

This ticket's closing line says it was *"returned to `backlog/` with the premise
corrected, blocked in practice on the sibling above"* — but the file sat in
`blocked/` with **no `blocked-by:` in frontmatter**, so the board could not see
why. That is the same failure mode
[[feature-lib-tkinter-callable-options-with-args]] recorded on itself: a blocker
stated in prose is invisible to the ranker, which reads frontmatter.

Added the edge to
[[bug-nilpy-eq-dunder-skipped-when-either-operand-is-a-variant]], which is the
sibling meant. Both `in` and `==` bottom out in pylib's `PyVarEq`, so the same
dispatch fix serves both and this one should not be worked separately.

Correctly stays in `blocked/`: the sibling is genuinely unfinished. But it now
inherits the sibling's priority down the dependency edge instead of ranking on
its own.

## 2026-08-10 — MEASURED: `in` and `count` now pass; `==` against a variant does NOT

The 2026-08-04 probe on this ticket, re-run verbatim on the current binary and
on `pinned` (identical on both, so this predates today's work):

```python
a = V(1); b = V(1); xs = [V(1)]
```

| expression | CPython | pxx now | this ticket's model said |
| --- | --- | --- | --- |
| `a == b` | True | True | correct already |
| `a == xs[0]` | True | **False** | broken (still is) |
| `a in xs` | True | **True** | broken — **now passes** |
| `xs.count(a)` | 1 | **1** | broken — **now passes** |

**This ticket's own headline repro (`V(1) in [V(1), V(2)]`) now answers `True`.**

### Why that matters more than a status update

Both this ticket and its blocker assert that `in`, `count` and `==`-with-a-
variant *bottom out in the same `PyVarEq` call*, and therefore that "the same
dispatch fix serves both and this one should not be worked separately". **The
measurement contradicts that premise**: two of the three now dispatch `__eq__`
and the third does not, so they are no longer one mechanism — whatever fixed
membership did not fix `==`.

That has a concrete consequence: the dependency edge added earlier the same day
now says this ticket waits on a sibling that no longer gates its symptom.

**Do not close this on the table above, and do not just drop the edge.** The
honest next step is one measurement, not a decision: find out whether `in`
reaches `__eq__` through `PyVarEq` at all any more, or through a separate path
added since. That answer decides whether this is closable as-is, or whether
`PyVarEq` still has a hole that `in` happens to route around.

The `==`-against-a-variant row is unchanged and remains the real, user-visible
defect — the dunder works with two named locals and fails the moment one side is
a container element, which is the shape real code writes. That is the sibling
[[bug-nilpy-eq-dunder-skipped-when-either-operand-is-a-variant]] and it is
correctly still open.

No code changed. Left in `blocked/` deliberately: the edge is not wrong yet,
only unproven.
