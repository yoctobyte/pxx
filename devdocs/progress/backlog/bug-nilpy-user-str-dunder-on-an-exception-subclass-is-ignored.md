---
track: N
prio: 45
type: bug
---

# A user `__str__` on an Exception subclass is ignored

```python
class WithStr(Exception):
    def __str__(self):
        return "CUSTOM-STR"

print(str(WithStr("ignored")))
```

```
CPython: CUSTOM-STR
pxx:     ignored
```

**Silent**, and it prints the *other* plausible answer — the constructor
argument — so it reads as "the message" rather than as a missing dispatch.

Confirmed pre-existing (`stable_linux_amd64/default/pinned` behaves identically),
and NOT a consequence of the 2026-08-09 exception str/repr work: that work only
touched the `PyUserObjStr` fallback, and this case never reaches it.

## Where it goes instead — a THIRD path

`str()` of an exception has at least three routes today:

1. a CAUGHT exception (`except E as e: str(e)`) — returns the message;
2. a CONSTRUCTED one (`str(E("v"))`) — went to the default object-repr
   (address) until 2026-08-09, now returns the message via `PyUserObjStr`;
3. this one, which returns the message WITHOUT consulting `__str__` at all —
   pinned already did so, meaning it never enters `PyUserObjStr` (whose very
   first lookup is `PyFindDunder(cls, '__str__')`).

Route 3 is the bug: something upstream recognises "this is an Exception, print
its Message" and short-circuits before the dunder lookup. A user class that is
NOT an Exception dispatches `__str__` correctly, so it is the exception-specific
shortcut that is wrong.

## Why it matters

Defining `__str__` on an exception is the normal way to format a domain error
(`f"{self.field}: {self.reason}"`). Here the class compiles, the method exists,
and the constructor argument is printed instead — so the formatting silently
never runs.

`__repr__` on an exception subclass should be checked at the same time; the same
shortcut may bypass it.

## Gate

`make test-nilpy` + self-host byte-identical, CPython-diffed over a
`__str__`-defining Exception subclass and a `__repr__`-defining one, each
printed via `str()`, `print()`, `%s`, an f-string, inside a container, when
CONSTRUCTED and when CAUGHT — the three routes above must agree — plus a
non-Exception class with `__str__` as the control that already works.
