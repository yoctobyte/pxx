---
track: N
prio: 60
type: bug
summary: "A user `class Counter:` is shadowed by pylib's `Counter` function, so `Counter.attr` fails with \"no such member on this record/class\" — the user's own class is unreachable by its own name"
status: done
owner: claude-AN
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

## Resolved 2026-08-03

One comparison at the identifier-resolution site in `ParseFactor`: under
`NilPyUserCode`, an unqualified name that binds to no symbol but DOES name a
class declared in the main program (`FindUClassInUnit(name, -1) >= 0`) drops its
proc binding. The class branches further down then take the name, exactly as
they do for a class pylib never heard of.

`UClsUnitIdx = -1` is the whole guard — "the user wrote this class". A pylib
class still loses to a pylib routine as before, and Pascal is untouched.

`test/test_nilpy_user_class_shadows_builtin.npy` (+ `.expected`, wired into
`make test-nilpy`), byte-identical to CPython: the `Counter` repro with class
attributes, an `__init__` that writes through the class name and a method that
reads it; plus classes named `list`, `dict` and `type`, read through the class
name and through an instance.

`gate.sh quick` GREEN, self-host fixedpoint byte-identical.

### Two things found beside it, both filed rather than folded in

- [[bug-nilpy-user-def-does-not-shadow-a-pylib-builtin]] — the same rule for
  `def`, and SILENT where this one was loud (`def sorted(x)` compiles, never
  runs, and the program prints the builtin's answer). It needs a different
  mechanism: a class and a routine are different kinds of entity, but a user def
  and a pylib routine are both procs and `FindProc` picks by registration order.
- `Counter("hello")["l"]` returns 0 rather than 2 — pylib's own
  `collections.Counter`, unrelated to shadowing and **pre-existing**, confirmed
  by running the same program on the pinned stable binary. Not filed under this
  ticket's slug because it is a pylib container defect, not a name-resolution
  one; needs its own measurement of which Counter operations are affected.

## Log
- 2026-08-03 — resolved.
- 2026-08-03 — resolved, commit HEAD.
