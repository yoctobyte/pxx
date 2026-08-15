---
track: N
prio: 20
type: bug
blocked-by: []
summary: "`getattr(o, nm)` / `hasattr(o, nm)` with a COMPUTED name answers False (and misses the value) for a PROPERTY: the runtime dynamic-attribute predicate is RTTI-based and the RTTI blob carries methods and fields, not properties."
status: done
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

## Resolution (2026-08-15)

Neither of the two interim shapes the ticket sketched: no RTTI property table
(Track A ground) and no frontend comparison chain. The getter is already IN the
RTTI method table — under its MANGLED name. `@property def double` compiles to
the method `__prop_get_double` with the plain name kept for a real Pascal
property (`PyPropAccessorPrefixAt`), so the runtime resolver only had to ask
for the mangled name and CALL it. A property has no storage of its own, so
calling is the only way to answer.

`PyPropertyGet(obj, name, found)` does that, and it serves the return kinds
whose ABI is spelled out — Variant (an unannotated getter, the common case by a
wide margin), Int64/Integer, Double, AnsiString, Boolean. Anything else answers
"not found", which is exactly today's behaviour and never a value read through
the wrong convention.

Wired into **three** predicates, which is the real content of the fix:
`pydynattr_hasattr` and `pydynattr_get` (a class-typed receiver) and
`pydynattr_has_any_v` / `pydynattr_get_v` (a variant receiver). A computed name
reaches the `_v` pair via `PyMakeDynAttrByExpr` — patching only the first pair
left the reported symptom completely unchanged, which is how the fourth site
was found.

## Gate

`make compiler/pascal26` + `tools/gate.sh quick` GREEN; pinned v336.
`test/test_nilpy_computed_name_sees_a_property.npy`, byte-identical to CPython:
a computed name over a property, a field, a method and an absent name; getters
annotated `-> str` / `-> float` / `-> bool` / `-> int` and an unannotated one;
a property whose value changes when the field does; a variant receiver
(`box[0]`); a name built by concatenation at run time; and the literal forms
unchanged.

## Log
- 2026-08-15 — resolved, commit eb0013981.
