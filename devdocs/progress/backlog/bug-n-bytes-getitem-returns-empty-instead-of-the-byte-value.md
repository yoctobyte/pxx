---
track: N
prio: 60
type: bug
blocked-by: []
summary: "`b'abc'.__getitem__(0)` prints nothing where CPython prints 97 — a silent wrong value, not a diagnostic. `b'abc'.__len__()` on the same receiver is correct, and `str.__len__` / `str.__getitem__` raise AttributeError for methods CPython has."
---

# `bytes.__getitem__` returns empty instead of the byte value

Filed 2026-08-26 while resolving
[[bug-n-hasattr-through-an-untyped-parameter-is-always-false]] — found by asking
whether `hasattr` could honestly answer True for the subscript dunders, which is
answered by whether the CALL works. For bytes it half works, and the half that
does not is silent.

## Measured (self-hosted at the fix's sha; the receiver is an untyped parameter)

```python
def c(x):
    return x.__getitem__(0)
def n(x):
    return x.__len__()
print(n(b'abc'), c(b'abc'))       # CPython: 3 97      pxx: 3 <empty>
print(n('abc'),  c('abc'))        # CPython: 3 a       pxx: AttributeError
```

| | CPython | pxx |
| --- | --- | --- |
| `b'abc'.__len__()` | 3 | 3 |
| `b'abc'.__getitem__(0)` | 97 | **(empty — silent wrong value)** |
| `'abc'.__len__()` | 3 | raises `'str' object has no attribute '__len__'` |
| `'abc'.__getitem__(0)` | `a` | raises `'str' object has no attribute '__getitem__'` |
| `[7,8].__getitem__(0)` | 7 | 7 |
| `{'a':1}.__len__()` | 1 | 1 |

## Two defects, one probe

1. **`bytes.__getitem__` is a silent wrong value.** `PyPylibMethodAlias` maps the
   subscript protocol onto pylib's spellings for **TPyDict** (`fetch`/`store`/
   `remove`/`count`) and **TPyList** (`at`/`put`/`pop_at`/`count`) and has **no
   TPyBytes arm** — yet `TPyBytes` declares the very same `count` and
   `at(i): Integer`. So the call resolves through some other route and comes back
   empty rather than declining. Find out which route before adding the table row;
   a missing alias should produce "no such method", and this produces a value.
2. **str has no dunder methods at all.** `'abc'.__len__()` / `.__getitem__(0)`
   raise, so `len('abc')` and `'abc'[0]` work while their method spellings do
   not — the same one-capability-two-spellings shape
   [[bug-n-a-builtin-types-method-cannot-be-called-unbound]] recorded for dict.
   `PyStrMethodInfo` has no rows for them.

## Why it is filed and not folded in

`hasattr(b'ab', '__len__')` and `hasattr('s', '__len__')` are False today, and
that is the *honest* answer while the call cannot be honoured for one of them and
is wrong for the other — the same rule
[[bug-nilpy-hasattr-on-a-builtin-container-or-str-answers-false]] applied to
float methods ("answering True would be a claim the call cannot honour").
`hasattr` becomes correct for both **for free** when this lands, because the
predicate reads those same tables. Adding the alias rows first, on top of a call
path that already returns the wrong value for `bytes.__getitem__`, would build on
the bug.

## Gate

The table above, diffed against CPython, plus `b'abc'[0]` and `'abc'[0]` (the
operator spellings, which must keep working) and the `hasattr` rows for the four
dunders once the calls are right.
