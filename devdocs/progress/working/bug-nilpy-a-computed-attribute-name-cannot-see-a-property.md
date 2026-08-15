---
track: N
prio: 20
type: bug
blocked-by: []
summary: "`getattr(o, nm)` / `hasattr(o, nm)` with a COMPUTED name answers False (and misses the value) for a PROPERTY: the runtime dynamic-attribute predicate is RTTI-based and the RTTI blob carries methods and fields, not properties."
status: working
owner: claude-AN
---

# A computed attribute name cannot see a property

```python
class W:
    def __init__(self):
        self.v = 1
    @property
    def double(self):
        return self.v * 2

w = W()
print(hasattr(w, "double"))          # True  — the LITERAL form is correct
for nm in ["v", "double"]:
    print(nm, hasattr(w, nm), getattr(w, nm, "MISS"))
# CPython: v True 1 / double True 2
# pxx:     v True 1 / double False MISS
```

Found 2026-08-15 while fixing the literal-name half
([[bug-nilpy-hasattr-does-not-see-a-property]]). The two forms take different
routes by construction: a literal name is answered by the FRONTEND against the
declared class, a computed one by the runtime dynamic-attribute predicate
(`pydynattr_hasattr` / `pydynattr_get`) against the RTTI.

Silent, and the same wrong-branch failure mode as its literal twin — one step
rarer, because the name has to be computed.

## Shape of a fix

The runtime predicate walks the class RTTI. If that blob carries no property
table, this needs one (or a getter-name convention it can recognise), which is
Track A ground — `project_rtti_method_table_multi_consumer_stride_landmine`
says what changing that table costs, and it is why this is filed rather than
folded into the literal fix.

Cheaper interim: the frontend already knows the class when the RECEIVER is
statically typed, even if the name is not. It could emit a chain of literal
comparisons over the class's property names before falling back to the store —
the same shape `PyHasAttrClassChain` already uses for the reverse case (known
name, unknown class).

## Gate

`.npy` diffed against CPython: a computed name over a property, a field, a
method and an absent name; on a class instance and on a variant receiver; and
the literal forms unchanged.
