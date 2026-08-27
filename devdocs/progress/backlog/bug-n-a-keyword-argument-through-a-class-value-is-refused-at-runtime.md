---
track: N
prio: 55
type: bug
owner: unassigned
blocked-by: []
summary: "`cls(x, b=99)` — a keyword argument to a class reached as a VALUE — raises TypeError at run time saying such a callable 'still carries no parameter names'. It does: RTTI_METH_FLAG's paramKinds block has carried param NAMES since the reflection work, and PyClassRefNew does not read them. The static spelling `P(x, b=99)` is correct, so this is one construction path disagreeing with the other."
---

# A keyword argument through a class VALUE is refused at run time

```python
class P:
    def __init__(self, a, b=2):
        self.a = a
        self.b = b
    def kw(self):
        return self.__class__(self.a, b=99)

print(P(5).kw().b)
```

```
CPython: 99
pxx:     Unhandled exception: TypeError: a keyword argument through this kind of
         callable value is not supported yet (an interpreted closure and a class
         reached as a value still carry no parameter names)
```

`P(5).kw()` with the class named literally — `P(self.a, b=99)` — answers 99.
Same call, same defaults, different spelling of the callee.

## PRE-EXISTING

Measured on `stable_linux_amd64/default/pinned` (v384), 2026-08-27, from the
sibling sweep of [[bug-n-self-class-cannot-be-called-as-a-constructor]]. That
ticket made `self.__class__(...)` reach the classref call path, which is why the
limitation is now easy to hit from ordinary code; the limitation itself is
older and belongs to [[feature-nilpy-class-as-a-value]].

## The message is out of date, which is the lead

It says the callee "carries no parameter names". `defs.inc` says otherwise, at
the `RTTI_METH_STARIDX_SHIFT` block:

> paramKinds points at 2*arity words: `arity` kind words THEN `arity` param-NAME
> pointers. [...] Names let a reflected caller bind a KEYWORD argument by name
> instead of by position.

and `PyClassRefNew` is named in that same comment as the reflected caller. So
the names are present in the RTTI it already walks; binding by them is the work,
and the refusal predates them being there. **Check that before designing
anything** — if the names are populated for a NilPy-lowered `__init__` the fix
is local to `PyClassRefNew`; if they are only populated for Pascal classes it is
a wider job in `rtti_emit.inc`.

Defaults are the second half: `cls(x, b=99)` must still apply `__init__`'s own
default for any parameter the caller skipped, which is what the positional path
gets for free today by construction.

## Severity

A loud, accurate-shaped refusal rather than a wrong value — it names the
limitation and does not corrupt anything. That is why it is 55 and not higher.
The cost is that the standard `self.__class__(...)` idiom silently only supports
its positional half, and a caller discovers which half at run time.
