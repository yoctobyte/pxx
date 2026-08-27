---
track: N
prio: 58
type: bug
owner: ""
blocked-by: []
summary: "`self.w = None` in the ctor, `self.w = Foo()` later, then `self.w.hi()` returns an INTEGER — the receiver's address — instead of calling the method. The idiomatic `self.w: Optional[Foo] = None` spelling is wrong the same way, which is what makes it expensive."
status: backlog
---

# A method call on an Optional class field returns a raw pointer

- **Type:** bug (Track N) — **silent wrong value**, no diagnostic anywhere.
- **Found:** 2026-08-27, while probing the cross-hierarchy field join for
  [[bug-n-a-field-declared-in-an-ancestor-is-not-widened-by-a-descendants-rebind]].
  It is NOT caused by that work: it reproduces identically on pinned **v388**
  (`e8b72f8afeb6`) and on HEAD, and it needs no inheritance at all.

## Repro

```python
class Foo:
    def hi(self):
        return "foo"

class A:
    def __init__(self):
        self.w = None
    def go(self):
        self.w = Foo()
        return self.w.hi()

print(A().go())
```

| | |
| --- | --- |
| CPython | `foo` |
| pxx (v388 and HEAD alike) | `184` — an address, printed as an integer |

## The annotated form is wrong too, and that is the expensive half

```python
from typing import Optional
class A:
    def __init__(self):
        self.w: Optional[Foo] = None
    ...
```

prints `176`. This is the form the frontend's own comments call idiomatic (the
one the uforth VM uses), and it is the form a user reaches for precisely
*because* they were told the annotation carries the type. It does not help here.

## Shape of the defect

The field is declared by `self.w = None`, so its type is decided by whatever
`None` infers to, and the later `self.w = Foo()` does not change the ANSWER at
the call: `self.w.hi()` neither dispatches nor errors — it yields the receiver
itself. So the failure is not "the field is the wrong width" (the value stored
IS the instance) but "an attribute selector on a field of this type degrades to
the bare receiver", which is the same silent degradation shape as
[[bug-n-an-attribute-on-an-unresolved-import-degrades-to-a-bare-name]].

Not investigated further; the diagnosis above is where the probe stopped.
Whoever takes it should start by printing the field's recorded type
(`PXXDBG=n.locals` / the field tables) for both spellings rather than reasoning
about what `None` infers to — measure, do not reason.

## Gate

Both repros above print `foo`, plus a control that a field left `None` and
never assigned still reads as None, and one that `if self.w is not None:`
still narrows the way it does today.
