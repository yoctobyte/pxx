---
track: N
prio: 70
type: bug
---

# Neither `super().m()` nor `Parent.m(self)` reaches an overridden method

Found 2026-07-28 spot-checking the NilPy object surface.

Both spellings Python offers for calling the parent's version of an overridden
method are rejected:

```python
class A:
    def who(self):
        return "A"

class B(A):
    def who(self):
        return "B" + super().who()      # error: undefined variable (super)

class C(A):
    def who(self):
        return "C" + A.who(self)        # error: cannot call non-static method
                                        #        on class type directly
```

CPython prints `BA` / `CA`. Inheritance itself works — the instance carries the
parent's fields and `isinstance(b, A)` is True — so this is specifically the
call path to an overridden implementation.

Loud rather than silent, which is why it is a p70 and not higher: nothing
miscompiles, the programs simply do not build. But `super().__init__(...)` is in
the first paragraph of every Python class tutorial, so almost any real class
hierarchy hits it immediately — the two shapes above are the ONLY ways Python
spells this.

## Shape of the fix

`super()` has no receiver to resolve at parse time, but the enclosing method's
class is known, so `super().m(args)` can lower exactly like Pascal's
`inherited m(args)` — the same IR the Pascal frontend already emits for an
inherited call. `Parent.m(self)` is the unbound form: the receiver is the first
argument, so it lowers to a NON-virtual call of `Parent.m` with `self` passed
explicitly, which is also an existing Pascal shape (a qualified method call).
Neither needs a new IR op.

`super().__init__(...)` in a constructor ALREADY WORKS — measured:

```python
class A:
    def __init__(self, n):
        self.n = n
class B(A):
    def __init__(self, n):
        super().__init__(n)     # fine
        self.m = n * 2
print(B(3).n, B(3).m)           # 3 6, same as CPython
```

So `super()` is recognised in the constructor path only, and the gap is any
OTHER method through it. That narrows the fix considerably: find where the
constructor case is special-cased and generalise it rather than adding a new
route.

## Gate

`make test-nilpy` plus a `.npy` with a two-level hierarchy exercising
`super().__init__()`, `super().m()` and `Parent.m(self)`, diffed against
CPython.
