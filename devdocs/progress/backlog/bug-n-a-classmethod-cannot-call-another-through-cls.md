---
slug: bug-n-a-classmethod-cannot-call-another-through-cls
title: "`cls.other(v)` inside a @classmethod raises AttributeError — a METHOD cannot be dispatched on a classref value"
track: N
type: bug
prio: 55
status: open
found: 2026-08-29
found-by: claude-N
---

# A classmethod cannot reach another one through its own receiver

Working CPython code, refused at run time:

```python
class C:
    def __init__(self, v: int):
        self.v = v
    @classmethod
    def make(cls, v: int):
        return cls(v)
    @classmethod
    def twice(cls, v: int):
        return cls.make(v * 2)      # AttributeError: 'type' object has no attribute 'make'
class D(C):
    pass
print(C.twice(5).v)                 # CPython: 10.   pxx: raises
```

`cls(v)` — **constructing** through the receiver — works, including through a
subclass. Only reaching a METHOD through it fails.

## Where it stops

`cls` is a `VT_CLASSREF` variant (tag 11). The tag-11 arm of the attribute
resolver answers class ATTRIBUTES and `__name__`, then raises:

```pascal
if tg = 11 then
begin
  Result := PyClsAttrRefGet(v, name, declFound);
  if declFound then Exit;
  if name = '__name__' then begin Result := PyClsRefName(v); Exit; end;
  raise AttributeError.Create('type object ''' + PyClsRefName(v) + ...);
end;
```

Methods are not in that registry, so a method name falls through to the raise.
Construction avoids it entirely by riding `pyvar_callvN -> PyClassRefNew`,
which reflects `create` over the RTTI — a path that exists precisely because
`cls()` was made to work.

## The shape of a fix, and why it is not obvious

A **compile-time** route looks cheapest and is probably right: inside a
classmethod the receiver's static class is known to be the enclosing class or a
subclass of it, so `cls.other(v)` could compile as a static-marked method call
with slot 0 = the raw `$clsptr` the frame already holds — which is exactly what
`Self.M(...)` does in a Pascal class method. That keeps the runtime class,
needs no new runtime machinery, and reuses the parameter this feature already
introduced.

The catch is that it must not swallow the general case: `k = SomeClass; k.m()`
where `k` is an ordinary variable has the same shape and no enclosing
classmethod to borrow a static type from. Either that stays a runtime raise
(honest, and what happens today) or the tag-11 arm learns method dispatch —
**do not do both half-way**, which is the failure this ticket's parent spent
three revisions avoiding.

## Provenance

Found while implementing [[feature-nilpy-staticmethod-and-classmethod]]'s
`@classmethod` half (landed 2026-08-29). Deliberately **not** folded in: the
rest of `@classmethod` is verified byte-identical to CPython across all four
receiver forms, and this is a separable mechanism whose failure is LOUD.
`test/test_nilpy_classmethod.npy` names the gap in a comment rather than
pinning it, so nothing records the current behaviour as intended.

## Gate

`make test-nilpy` + self-host byte-identical, plus the program above answering
`10` and `type(D.twice(6)).__name__` answering `D` — the runtime class must
survive the hop, which is the whole point of the receiver.
