---
prio: 25
track: N
---

# bug(N): a @staticmethod read through an INSTANCE binds a receiver, so `type(k.stat).__name__` says 'method'

Found while fixing `regression-test-nilpy-test-nilpy-type-name-of-a-big-int`
(the function-vs-method type name). Filed rather than fixed, because it is a
pre-existing divergence of the ATTRIBUTE READ, not of the name table, and it is
a different mechanism.

## Repro

```python
class K:
    @staticmethod
    def stat(a, b):
        return a * 10 + b

k = K()
print(K.stat(1, 2))          # 12   -- agrees
print(k.stat(3, 4))          # 34   -- agrees
f = k.stat
print(f(5, 6))               # 56   -- agrees
print(type(k.stat).__name__) # CPython: function     NilPy: method
```

Every VALUE agrees with CPython. Only the type name diverges.

## Cause

`pydynattr_get_v`'s method arm builds `pybound_new_star(mi^.Code, obj, ...)` for
any method name read as a value — it has no notion of `@staticmethod`, so it
binds the instance as the receiver. `PyVarTypeNameOf` then correctly reports
'method', because "what makes something a bound method is being bound to
something" (the rule `PyCallableStr` and now `PyVarTypeNameOf` share). The
receiver is the thing that is wrong, not the naming.

The values still come out right because the compiled staticmethod body has no
`self` parameter and the dispatcher calls it through the plain-function arm --
the bound receiver is simply never passed. So this is visible ONLY through
`type(...).__name__` (and, presumably, `str()` of the value, which
`PyCallableStr` would render `<bound method ...>` for the same reason).

## Why it is prio 25, not higher

A program that branches on `type(x).__name__` for a staticmethod read off an
instance takes the wrong arm — that is a real defect, and it is why this is a
`bug-` and not a note. But no value is wrong, no program crashes, and the
spelling (staticmethod reached through an instance rather than the class) is
uncommon.

## Deliberately NOT asserted

`test/test_nilpy_type_name_function_vs_method.npy` carries the case as a comment
naming this ticket rather than as an assertion, so the test stays oracle-diffed
and all-green. Turn the comment back into `print(type(k.stat).__name__)` and
regenerate the `.expected` from CPython when this is fixed -- that is the gate.
