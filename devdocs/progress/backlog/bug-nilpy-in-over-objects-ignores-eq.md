---
track: N
prio: 50
type: bug
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
