---
track: N
prio: 45
type: bug
status: done
owner: agent-AN
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

## FIXED 2026-08-09 — not one shortcut but THREE copies of one decision

### The ticket's model was one route short, and that mattered

It described "a THIRD path" that short-circuits before the dunder lookup. There
were **three** such paths, each an independent copy of the same
Exception-then-dunder decision with the `.msg` arm FIRST:

| route | site |
| --- | --- |
| `print(e)` | `PyReprContainer` (pyparser.inc) |
| `str(e)` | `parser.inc` ~11190, the `str()` builtin arm |
| f-string / `%s` | `parser.inc` ~10393, the `pystr_of` arm |

Reordering the first one alone was measured and it moved **only** `print(e)` —
`str(e)`, the f-string and `%s` stayed wrong. That is what three mechanisms for
one concept costs, and it is why the fix is a single shared routine
(`PyClassStrNode`) rather than three reorderings:

> `__str__`/`__repr__` if the class declares one; otherwise, and only otherwise,
> an Exception's `.msg`.

`devdocs/dev/normalise-dont-special-case.md` — and the sibling-arm rule in
CLAUDE.md: having fixed one arm, the other two were found by grepping for the
sibling rather than by the next bug report.

### Also answered: `__repr__` was never broken

The ticket asked to check it. `repr()` takes a different route that never had
the Exception shortcut, so it was correct all along — which is exactly what made
this look like a str/repr inconsistency in the object model rather than an
ordering bug in three copies.

### Gate

Extended `test_nilpy_exception_str_constructed.npy` — the file that already
parks this case as "NOT asserted, filed separately" — and replaced that note,
since leaving it would be a stale claim in a live test. Asserted through EVERY
route, because routes disagreeing is what this whole file is about:
`str()`, `print()`, an f-string, `%s`, an INHERITED `__str__` (a subclass of a
`__str__`-defining exception), `repr()` on a `__repr__`-defining one, and the
CAUGHT spelling. Plus the control that matters for the reordering: an exception
declaring NEITHER dunder still renders its message, so the `.msg` fallback the
top half of that file pins is untouched.

Matches CPython byte for byte. Self-host fixedpoint byte-identical.

## Log
- 2026-08-09 — resolved, commit PENDING-COMMIT.
