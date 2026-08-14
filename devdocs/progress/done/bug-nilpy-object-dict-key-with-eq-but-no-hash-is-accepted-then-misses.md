---
track: N
prio: 40
type: bug
summary: "A class defining __eq__ without __hash__ is UNHASHABLE in CPython — `d[V(1)] = x` raises TypeError. pxx accepts the store and then never finds the key again, so the dict silently swallows entries instead of refusing them"
status: done
owner: agent-AN
---

# an object key with `__eq__` but no `__hash__` is stored and then never found

- **Type:** bug (NilPy — CPython divergence, silent) — **Track N**
- **Opened:** 2026-08-10, running the gate list of
  [[bug-nilpy-in-over-objects-ignores-eq]] while closing it. Every other row of
  that gate matched CPython; this one did not, in a different way from the
  ticket being closed, so it is filed rather than folded in.

## Measured

```python
class V:
    def __init__(self, v: int): self.v = v
    def __eq__(self, o) -> bool: return self.v == o.v

d = {}
d[V(1)] = "one"
print(d.get(V(1), "MISSING"))
```

```
CPython : TypeError: unhashable type: 'V'   (at the STORE)
pxx     : MISSING                            (store succeeds, lookup misses)
```

CPython's rule: defining `__eq__` sets `__hash__` to None unless `__hash__` is
also defined, because two objects that compare equal must hash equal, and the
default identity hash cannot promise that. So the store is refused outright.

pxx accepts the store, then looks the key up by an identity-ish rule that a
fresh-but-equal `V(1)` does not satisfy — the entry is in the dict and
unreachable.

## Why it is worth filing

The failure is **silent and it loses data**: a dict used as a cache or an index
keyed by a value object accepts every write and answers every read with the
default. Nothing raises, nothing prints, and the program looks like it simply
found nothing — which is the failure class the debugging playbook calls the
expensive one.

Note the asymmetry with what was just fixed: `in`, `count`, `index` and
`remove` over a list of the same objects all dispatch `__eq__` correctly now.
So a value object behaves correctly in a list and silently wrongly in a dict,
which is exactly the kind of split that reads as "dicts are broken" from
application code.

## Two directions, and they are genuinely different

1. **Match CPython: refuse the store.** A class with `__eq__` and no `__hash__`
   is unhashable, so `d[obj] = x` is a `TypeError`. Faithful, and turns a silent
   miss into a diagnostic at the exact line. Risk: any existing NilPy program
   relying on object keys starts failing — check the corpus first.
2. **Make it work: hash by `__eq__`-compatible content.** Friendlier than
   CPython but needs a `__hash__` story, and NilPy's dict is a linear scan
   (`project_nilpy_*`), so a content-equality lookup could reuse the same
   `PyVarEq` route that membership now uses — plausibly small.

(2) is tempting because the dict is already a linear scan and the equality
route already exists. But it makes NilPy accept a program CPython rejects, which
is *allowed* by the upward-compatibility rule (that rule is one-directional) —
so this is a deliberate dialect choice, not a bug fix, and it should be made
explicitly rather than by whoever touches it first. **If it is not obvious, file
`decide-` rather than guessing.**

## Gate

The repro matching whichever direction is chosen; `in`/`count`/`index` over a
list of the same objects still correct (they share the equality route);
`make test-nilpy` green + self-host fixedpoint.

## 2026-08-13 — escalated, per this ticket's own closing instruction

Filed [[decide-nilpy-object-dict-key-hashing]] rather than picking a direction.
Re-measured first, and the divergence is NARROWER than this ticket's framing:

| shape | pxx | CPython |
| --- | --- | --- |
| same OBJECT as key, `__eq__` defined | works | TypeError at the store |
| equal-but-NEW key, `__eq__` defined | MISSING | TypeError at the store |
| no `__eq__` at all, same object | works | works |
| no `__eq__` at all, equal-but-new | MISSING | MISSING — agrees |

So identity-keyed dicts are correct and agree with CPython; only a class that
defines `__eq__` diverges. That matters for option 1: refusing the store would
be a narrow change, not a broad one.

The decide ticket also records the fact that makes option 2 real — `TPyDict`
falls back to a LINEAR SCAN over `PyVarEq` when `FHashCap` is 0, and `PyVarEq`
already dispatches `__eq__`, which is why the same objects behave correctly in
a list — and rules out "just document it": the current behaviour is not
laxness, it loses data silently.


## Resolution — DUPLICATE, already fixed

Same defect as [[bug-n-object-dict-key-with-eq-and-no-hash-silently-loses-the-entry]],
filed independently on 2026-08-14 while re-filing
[[decide-nilpy-object-dict-key-hashing]]. Two tickets, one bug — this one opened
2026-08-10 from the `in`-over-objects gate list, the other four days later from
the decision.

Fixed 2026-08-15. This ticket's exact repro now matches CPython:

```
$ ./compiler/pascal26 dup.npy dup && ./dup
Unhandled exception: TypeError: unhashable type: 'V'
$ python3 dup.npy
TypeError: unhashable type: 'V'
```

Refused in `PyVarHashKey` — the one place a key becomes a bucket — so the store
and every lookup form refuse alike, as CPython does. The probe keys on `__eq__`
being PRESENT, so a class with no `__eq__` stays identity-hashable, which is the
imported-object-by-pointer case. Full write-up, including why a synthesised
content hash was rejected, is on the other ticket.

Closed here rather than merged so the cross-reference survives: anyone arriving
from the `in`-over-objects gate list finds the answer instead of an open ticket.
No code or test change belongs to this one.

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
