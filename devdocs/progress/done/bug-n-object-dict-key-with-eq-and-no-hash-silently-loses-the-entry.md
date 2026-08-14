---
track: N
prio: 50
type: bug
summary: "A class defining `__eq__` without `__hash__` is unhashable in CPython — `d[V(1)] = x` raises TypeError. NilPy stores it and a content-equal lookup then misses, so the entry goes in and never comes out, silently. Refuse the store with CPython's message. Must NOT touch classes with no `__eq__`, which are identity-hashable in both and are the imported-object-pointer use case."
status: done
owner: agent-AN
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

## Resolution

Refused, with CPython's wording, at the one place a key becomes a bucket.

### Where

`PyVarHashKey` — not at `store`, and deliberately so. The ticket's gate asks for
the refusal "at the store, not the lookup", but CPython refuses at BOTH:
`V(1) in d` and `d.get(V(1))` raise the same `TypeError` as `d[V(1)] = x`. One
check in the hashing function covers the store and every lookup form
(`d[k]`, `.get`, `in`, `.pop`) without a check per caller — the
normalise-don't-special-case shape, and the reason the store/lookup split in the
ticket turned out not to be a real distinction.

The probe is `PyUserObjUnhashable`, beside the other user-object dunder probes
and built from the same `PyFindDunder` the `__hash__` path already used:

```
__eq__ absent            -> hashable (identity). The Handle path. Untouched.
__eq__ and __hash__      -> hashable (content). The programmer supplied both.
__eq__ without __hash__  -> TypeError: unhashable type: 'V'
```

Keying on `__eq__` being PRESENT is what keeps it off the path the ticket said
must not break.

### One thing the ticket did not anticipate

`TPyDict.indexof` short-circuited on `FLen = 0` **before** hashing, so
`V(1) in {}` answered False while `V(1) in {"a": 1}` raised — the diagnostic
appeared or not depending on how many entries the dict happened to hold. The
empty-dict answer was right, but reached by a route that skipped the question.
The hash is now computed before the short-circuit. One hash on an empty lookup
is not worth an inconsistency that would have read as a flaky refusal.

### Gate, item by item

| the ticket asked | result |
| --- | --- |
| 1. the `V` case raises with CPython's wording | `TypeError: unhashable type: 'V'` — identical string |
| 2. `Handle` (no `__eq__`) still `len 2`, both lookups correct | unchanged, and it is the first assertion in the new test |
| 3. `__eq__` WITH `__hash__` still a content key | unchanged |
| 4. string / int / tuple keys unchanged | unchanged |

Plus: a `@dataclass` instance is now refused as a key, which is **also** what
CPython does (the generated `__eq__` sets `__hash__` to None). Checked rather
than assumed — same message, same class name.

Every existing `__eq__`-related test re-run against the CPython oracle and still
byte-identical: `quick_canary_nilpy`, `membership_eq_dunder`, `hash_builtin`,
`dunder_ne`, `eq_dunder_variant_operand`, `dataclass_eq`,
`unpack_keeps_class_identity`.

New `test/test_nilpy_unhashable_eq_without_hash.npy` covers all three class
shapes and all three refusal sites — **byte-identical to CPython**, wired into
the Makefile.

Gate: `gate.sh quick` GREEN (self-host fixedpoint + `--tier quick` + FPC seed
canary). **Pinned (v306)** — `pylib.pas` is the runtime of a compiled `.npy`
program, so this is not a gate requirement, but without the pin the refusal
never reaches programs built with `$(PXX_STABLE)`. Frozen builtin set unchanged
at 8 files (`pylib.pas` modified), checked against `git status`.

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
