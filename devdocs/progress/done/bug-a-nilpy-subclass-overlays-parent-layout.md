---
track: A
prio: 70
type: bug
status: done
---

# NilPy: a subclass overlaid the parent's fields and VMT slots

Found 2026-07-20 while testing [[bug-a-nilpy-method-call-on-variant-receiver]]
with an inheritance ladder.

## Repro

```python
class A:
    def __init__(self, n: int) -> None:
        self.n = n
    def get(self) -> int:
        return self.n

class B(A):
    def twice(self) -> int:
        return self.n * 2

b = B(3)
print(b.get())     # printed 6 (twice()'s answer), CPython prints 3
print(b.twice())   # 6
```

Silent — no diagnostic, just the wrong method.

## Cause

`PyRegisterClassMembers` started a subclass's field offsets at 8 and its virtual
slot counter at 0, ignoring the parent entirely. So B's fields overlaid A's, and
B's first method took the slot A's first method already owned — an inherited
call went through that slot and landed in the subclass method. The Pascal path
does both continuations (parser.inc: `curFieldOff := UClsSize_[parentCi]` /
`UClsVirtCount[ci] := UClsVirtCount[parentCi]`); the NilPy path never got them.

Fixing the numbering exposed the second half: a subclass VMT is emitted per
class and starts zeroed, and only the class's OWN methods got fixups, so every
inherited-but-not-overridden slot stayed NIL and the call segfaulted.

## Fix

f933cdf4 — subclass fields start past the parent's instance size, slots past the
parent's slot count, an override reuses the parent's slot (so a base-typed
reference dispatches to the override), and each inherited slot gets a VMT fixup
to the nearest ancestor's method.

## Regression test

`test/test_nilpy_inheritance.npy`, wired into `make test-nilpy`; output diffed
against CPython running the same file.
