---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`list.append(self, x)` / `dict.__getitem__(self, k)` — a BUILTIN type's method called unbound with an explicit self — is `undefined variable (list)`. The same call on a USER class (`A.m(self)`) works. It is how a builtin subclass reaches the base implementation it just overrode, so it is the immediate next wall behind feature-nilpy-subclass-a-builtin-type, and both html5lib sites need it."
---

# A builtin type's method cannot be called unbound

- **Type:** bug — **Track N**. **Found:** 2026-08-18 by frank2-7e, landing
  [[feature-nilpy-subclass-a-builtin-type]].
- **Measured at:** HEAD, self-host fixedpoint build, immediately after that
  feature landed.

## Repro

```python
class Stack(list):
    def append(self, x):
        list.append(self, x)      # error: undefined variable (list)
```

The user-class form works and has since
[[bug-nilpy-super-and-unbound-parent-method-calls]]:

```python
class B(A):
    def m(self):
        return A.m(self) + 1      # fine
```

So this is the builtin NAME failing to resolve in a receiver position, not the
unbound-call machinery.

## Why it matters now

Subclassing a builtin landed, and this is what a subclass immediately reaches
for: overriding a method and delegating to the base is the reason to subclass a
container at all. Both html5lib sites are exactly this shape:

| file | line |
| --- | --- |
| `html5lib/treebuilders/base.py:134` | `list.append(self, node)` |
| `html5lib/_utils.py` (`MethodDispatcher`) | `dict.__getitem__(self, key)` |

`treebuilders/base.py` moved onto this wall the moment the base class resolved:
pinned v351 said `unknown base class list`, HEAD says `undefined variable (list)`
at line 134. That is progress ONTO the next wall, not past it.

## Shape of the fix

`PyBuiltinBaseCi` (added by the feature above) already maps `list`/`dict`/`set`/
`bytes` onto their pylib classes for the BASE-CLASS position. The same mapping is
needed where a class NAME is resolved as a receiver — `IsClassType(name)` /
`PyIsClassTypeExact(name)` in the factor paths, several of which live in the
SHARED `compiler/parser.inc`, so this needs the A/P slot.

Deliberately NOT done as part of the feature: it is a separate, nameable
capability (calling a builtin's method unbound), the feature is green and
complete without it, and widening class-name resolution across four shared-file
sites at the end of a session is how a plausible-but-wrong change lands.

## Gate

`make compiler/pascal26` fixedpoint + `tools/gate.sh quick`, plus: a `list`
subclass overriding `append` and delegating, a `dict` subclass overriding
`__getitem__` and delegating, and the user-class `A.m(self)` form unchanged.
