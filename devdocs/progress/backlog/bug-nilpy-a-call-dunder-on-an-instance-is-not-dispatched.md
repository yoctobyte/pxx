---
track: N
prio: 45
type: bug
---

# `obj(...)` does not dispatch a user `__call__`

```python
class C:
    def __call__(self, x):
        return x * 2
c = C()
print(c(5))
```

CPython prints `10`. pxx returns a garbage integer (pinned does the same).

Found while fixing `bug-nilpy-calling-a-non-callable-segfaults`, and left out
of that fix deliberately: the guard there refuses a tag-7 instance **only when
its class has no `__call__`**, so a list/dict/tuple now raises TypeError
properly while an instance that defines `__call__` still falls through to the
old path rather than being newly refused. Refusing it would have turned a wrong
value into a wrong error — a regression — so the arm stays narrow and the
dispatch is this ticket.

## Where it goes

`pyvar_callv0..3` in `pyeval.pas` already resolve the class of a tag-7 payload
(`GetInstanceRTTI`), and `PyHostCall(vmobj, name, args, res)` is the existing
machinery for calling a method by name with a `TPyList` of arguments —
`PyFindMethCI(cls, '__call__')` plus `PyHostCall` should be most of it.

Note `pylib.pas` already has `PyNotCallableError` ("object is not callable (no
`__call__`)") written and **never called** — it was authored for this arm and
left unwired.

## Gate

`make test-nilpy` + self-host byte-identical, CPython-diffed over `__call__`
with 0/1/2/3 args, an inherited `__call__`, and a class WITHOUT one still
raising TypeError.
