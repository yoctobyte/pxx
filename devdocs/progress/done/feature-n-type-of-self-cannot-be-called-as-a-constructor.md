---
prio: 35
track: N
type: feature
status: done
owner:
blocked-by: []
summary: "`type(self)(args)` -- Python's other spelling of `self.__class__(args)` -- does not parse: `expected newline after statement` at the second `(`. `self.__class__(...)` works and takes keywords and defaults."
---

# `type(self)(...)` cannot be called as a constructor

```python
class R:
    def __init__(self, x, scale=10):
        self.v = x * scale
    def again(self):
        return type(self)(self.v, scale=2)
print(R(3).again().v)        # CPython: 60
```

pxx: `error: Nil Python: expected newline after statement`, near
`return type ( self ) >>> ( self .`

Found 2026-11-11 while fixing
bug-n-a-keyword-argument-through-a-class-value-is-refused-at-runtime.

## Shape of a fix

`x.__class__` already lowers to a VT_CLASSREF (PyMakeClassRefOf, via
`__pxxRttiOf(x)`), and calling that variant reaches PyClassRefNew. For a CLASS
INSTANCE argument, `type(x)` followed by `(` could lower the same way. Then
PyClassUsedAsValueEx's own-body scan needs the `type(self)(` shape too, or the
ctor is not widened (it was written for it and taken out until this parses).
A builtin-typed `x` (`type(3)(...)`) is a separate question.

## Resolution (2026-11-11)

`type(x)` that is not `.__name__` already lowered to `pytype_of_v`, a
VT_CLASSREF for an instance; the prefix arm Exited before ParseFactor's call
loop could see the `(`. It now takes the call itself through PyMakeDynCall --
the same dynamic call `cls = self.__class__; cls(args)` makes, so keywords and
defaults reach PyClassRefNew. PyClassUsedAsValueEx's own-body scan recognises
`type(<x>)(` beside `.__class__(`, so the constructor is widened.

A subclass instance builds the subclass (`S(1).again()` is an S), and a module-
level `type(r)(5)` works too. Test test_nilpy_type_of_self_called_as_a_constructor.py
(row typeself26), expected = python3. `type(3)(...)` on a builtin was not
claimed.
