---
track: N
prio: 65
type: bug
summary: "`f(*range(2))` passes ZERO arguments and `f(*b\"ab\")` passes empty ones, silently. The star-operand normaliser converts a str and a user iterable and returns every other object untouched, so a TPyRange / TPyBytes is stored into a TPyList-typed slot and read as a list header. The same hole in PyMakeIterOf makes `zip(b\"ab\", ...)` yield empties."
---

# A static star operand over a non-list iterable passes nothing

```python
def c(*a):
    return a

print(c(*[1, 2]))     # (1, 2)      CPython (1, 2)     ok
print(c(*(1, 2)))     # (1, 2)      CPython (1, 2)     ok
print(c(*"ab"))       # ('a', 'b')  CPython ('a','b')  ok
print(c(*{"k":1,"j":2}))  # ('k','j')                  ok
print(c(*{1, 2}))     # (1, 2)                         ok
print(c(*range(2)))   # ()          CPython (0, 1)     WRONG
print(c(*b"ab"))      # (, )        CPython (97, 98)   WRONG
```

and the arity check sees the same nothing, so the failure can also be a
refusal rather than a wrong value:

```python
def two(a, b):
    return a + b
print(two(*range(2)))
# TypeError: forwarded call got 0 arguments, expected 2 to 2
# CPython: 1
```

## Why it is only the STATIC spelling

A star operand whose static type is a **variant** goes through
`pystar_as_list`, which converts on `pyiter_v`'s rules and handles every
iterable correctly. That is why `def fwd(args): return two(*args)` called with
a `range` works, and why the whole `test_nilpy_star_operand_in_a_variant`
suite passes: it exercises the variant path end to end and never writes
`f(*range(n))` directly.

The statically-typed spelling goes through `PyStarOperandAsList`
(`compiler/pyparser.inc`), which calls `PyIterArgAsList` and then, for a
non-variant node, **returns it untouched** and assigns it into a hidden local
declared `tyClass` / `TPyList`. `PyIterArgAsList` converts exactly two things —
a str (`pystr_charlist`) and a user class implementing `__iter__`
(`pyiter_drain` of `pyiter_of_userobj`). Everything else falls through. A
`TPyRange` or `TPyBytes` object therefore lands in a TPyList-typed slot and is
read as a list header: `count` reads as 0 for a range (hence the empty tuple)
and as garbage variants for bytes.

Lists, tuples and dicts survive only because they ARE `TPyList`-shaped
(a tuple is a marked TPyList; a dict's arm hands over its `keylist`).

## The sibling — same hole, different consumer

`PyMakeIterOf` (the general "wrap any iterable in a cursor" normaliser) has
arms for str, range, user-iterable and "any other tyClass -> `pyiter_of_list`".
That last arm swallows **TPyBytes**:

```python
print(list(zip(b"ab", "ab")))   # [(, 'a'), (None, 'b')]   CPython [(97,'a'),(98,'b')]
print(list(zip(range(2), "ab")))  # correct
```

So `bytes` is wrong through BOTH normalisers, and `range` through only the
star one. Fix them together or the next consumer inherits whichever half was
left.

## Shape of the fix

`normalise-dont-special-case`: neither normaliser should carry a list of
kinds. `PyIterArgAsList` already has the general answer sitting next to it —
`pyiter_drain(PyMakeIterOf(n))` converts anything. The rule becomes "a node
statically typed as `TPyList` is handed back; everything else is drained",
which subsumes the str and user-iterable arms rather than adding a third and
a fourth. `PyMakeIterOf` needs a real `TPyBytes` arm (its byte elements are
ints, which `pyiter_of_list` cannot produce from a byte buffer) before it can
be the single answer.

Check `pystar_iterable`, `PyMakeZip`, `pyiter_v` and the `for`-loop lowering
for the same list-of-kinds shape before closing — `pyiter_v` already has the
full set and is the model.

## Provenance

Found while resolving
`regression-test-nilpy-test-nilpy-star-operand-in-a-variant` — measured, not
inferred, at self-host fixedpoint `1dbc94c691aa`. Unrelated to that
regression's cause (a compiler zero-init hole); it is a separate defect the
same test file walks past.
