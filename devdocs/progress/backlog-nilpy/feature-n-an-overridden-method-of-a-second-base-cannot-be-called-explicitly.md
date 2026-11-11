---
track: N
prio: 45
type: feature
status: backlog
owner: unassigned
summary: "`class C(A, B)` whose `__init__` calls `A.__init__(self)` and `B.__init__(self)` is refused at the second call, `error: class method not found: __init__`. CPython runs both. A second base is FLATTENED (its body replayed against the derived class), and a member the derived class overrides is skipped by the C3 conflict rule, so B's own `__init__` is never compiled for C and the explicit call has nothing to reach. This is what stops a two-base class from chaining both constructors."
---

# An overridden method of a second base cannot be called explicitly

Split out of [[bug-n-super-as-an-expression-fails-with-a-misleading-diagnostic]]
on 2026-11-11, when that ticket's `super()` half was found fixed.

```python
class A:
    def __init__(self) -> None:
        self.a = 1
class B:
    def __init__(self) -> None:
        self.b = 2
class C(A, B):
    def __init__(self) -> None:
        A.__init__(self)
        B.__init__(self)    # pascal26: error: class method not found: __init__
c = C()
print(c.a, c.b)             # CPython: 1 2
```

## Mechanism

The first base is a real Pascal parent, so `A.__init__(self)` resolves. Every
further base is flattened (see the "multiple inheritance by FLATTENING" block
in pyparser.inc). Its body span is replayed against C, so its methods compile
with `self` = a C, and conflicts resolve C3 left to right: the derived class
wins, so B's `__init__` is not replayed at all.

## Shape of a fix

During the replay, compile each SKIPPED conflicting method of a flattened base
under a hidden name (for example `__init__$B`), and resolve an explicit
`B.name(self, ...)` inside C, where B is a flattened base of C, to that
hidden method. The method still compiles against C's layout, which is what a
flattened body already does for its non-conflicting members. Only replay
skipped members that an explicit `B.name(` actually reaches, so a mixin with
many overridden methods costs nothing extra (ESP flash/RAM).
