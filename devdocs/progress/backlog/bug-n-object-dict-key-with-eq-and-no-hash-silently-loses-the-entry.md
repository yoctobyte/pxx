---
track: N
prio: 50
type: bug
summary: "A class defining `__eq__` without `__hash__` is unhashable in CPython — `d[V(1)] = x` raises TypeError. NilPy stores it and a content-equal lookup then misses, so the entry goes in and never comes out, silently. Refuse the store with CPython's message. Must NOT touch classes with no `__eq__`, which are identity-hashable in both and are the imported-object-pointer use case."
---

# `__eq__` without `__hash__`: the dict entry goes in and never comes out

- **Type:** bug (silent data loss) — **Track N**.
  Re-filed from [[decide-nilpy-object-dict-key-hashing]] on 2026-08-14: the
  user's call was that this is not a design fork, it is a fix.

## Measured

```python
class V:
    def __init__(self, n): self.n = n
    def __eq__(self, o): return self.n == o.n

e = {}
e[V(1)] = "x"
print(len(e), e.get(V(1), "MISS"))
```

| | result |
|---|---|
| CPython | `TypeError: cannot use 'V' as a dict key (unhashable type: 'V')` |
| NilPy | `1 MISS` — stored, then never found |

## Why refusing is right, not merely faithful

The programmer defining `__eq__` has said *"do not compare these by identity,
compare them by content."* Using the same class as a dict key asks for identity
semantics. **The two requests contradict**, and CPython refuses rather than
resolve the contradiction silently — `__hash__` is set to `None` on purpose when
`__eq__` is defined.

NilPy currently honours neither: it stores under identity, so a content-equal
lookup misses. Data in, nothing out, no diagnostic. That is the worst available
outcome and it is what this ticket removes.

It also costs no compatibility. NilPy's promise is one-directional — *code that
works on CPython must work on NilPy* — so refusing what CPython refuses is
inside the rule.

## Do NOT synthesise a hash to "make it work"

Rejected with the decision, and not only on cost: a content hash **reintroduces
the same class of bug in a subtler form**. Mutate the object after insertion and
its hash changes, so the entry silently disappears from the dict. That is
precisely the trap CPython backed away from. If real code ever wants
content-keyed dicts, add a `__hash__` story then, on evidence.

## The path this must not break — a class with NO `__eq__`

Identity-hashable in CPython, works identically in NilPy today, and is the real
use case: an imported Pascal or C object held by pointer as a dict key and
handed straight back to SQLite or a Pascal library.

```python
class Handle:
    def __init__(self, n): self.n = n
a, b = Handle(1), Handle(1)      # same contents, distinct objects
d = {}
d[a] = "from a"; d[b] = "from b"
```

**Both implementations: `len(d) == 2`, `d[a]` and `d[b]` both correct.**

The refusal must key on `__eq__` being **present**, so it cannot reach this
path. A fix that refuses all object keys, or that starts comparing handles by
content, is wrong even if the ticket above goes green.

## Gate

1. The `V` case raises with CPython's wording, at the **store**, not the lookup.
2. The `Handle` case above still gives `len 2` and two correct lookups —
   this is the regression test that matters most.
3. `__eq__` **with** an explicit `__hash__` continues to work as a content key,
   since the programmer has then supplied the missing half.
4. String, int and tuple keys unchanged (verified identical to CPython today).
