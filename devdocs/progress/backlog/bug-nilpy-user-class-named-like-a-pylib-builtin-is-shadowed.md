---
track: N
prio: 60
type: bug
summary: "A user `class Counter:` is shadowed by pylib's `Counter` function, so `Counter.attr` fails with \"no such member on this record/class\" — the user's own class is unreachable by its own name"
---

# A user class named like a pylib builtin loses to the builtin

- **Type:** bug (NilPy name resolution — LOUD, but the diagnostic points at the
  wrong thing) — **Track N**
- **Found:** 2026-08-03, while writing the gate for
  [[bug-nilpy-class-attribute-unreachable-through-the-class-name]]. The test
  used `class Counter` for a counter idiom and failed for a reason that had
  nothing to do with class attributes.

## Repro

```python
class Counter:
    k = 0
    def __init__(self):
        Counter.k += 1
Counter()
print(Counter.k)
```

```
pascal26:4: error: "k": no such member on this record/class
  near:     Counter  >>> k
```

Rename the class to anything else and it prints `1`.

## Cause

`compiler/builtin/pylib.pas` declares `collections.Counter` as a set of overloaded
FUNCTIONS (`function Counter: TPyDict;` and friends, pylib.pas:1024-1027). The
user's `class Counter` does not displace them, so `Counter.k` resolves against
the pylib entity and dies in `RequireRecMember` — an error message about a
missing MEMBER, which sends the reader looking at the class body rather than at
the name.

## Why it matters beyond the one name

`Counter` is only the instance that was tripped over. Every pylib-provided
Python builtin spelled as a Pascal routine is the same hazard, and Python
programs shadow builtins routinely — a user class or function named `list`,
`set`, `bytes`, `type`, `filter`, `map` is legal Python and means the user's
one from that point on. The general rule is that a NilPy module-level
definition must win over anything pylib provides.

## Suggested shape

A user `class`/`def` at module scope should mask the pylib name for the rest of
the module. Worth checking whether the same hole exists for a user `def` with a
builtin's name, and whether the fix belongs at declaration time (mark the pylib
symbol shadowed) or at lookup time (prefer a user class when one exists) — the
declaration-time form is the one that cannot drift between lookup sites.

## Gate

A `.npy` diffed against CPython: a user class named `Counter` with class
attributes and methods, used through its own name and through an instance; the
same for a user `def` named after a builtin; plus a control that the pylib
`Counter`/`collections.Counter` still works in a module that does NOT shadow it.
