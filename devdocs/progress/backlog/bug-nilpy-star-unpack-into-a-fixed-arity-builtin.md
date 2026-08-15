---
track: N
prio: 30
type: bug
blocked-by: []
summary: "`zip(*rows)` — the transpose idiom — is refused, `sum(*xs)` is refused, and `max(*xs)` COMPILES and then raises \"forwarded call got 3 arguments, expected 2 to 2\". One mechanism: each builtin is lowered at an arity fixed at compile time, so a run-time count has nowhere to go."
---

# `*xs` into a fixed-arity builtin

```python
m = [[1, 2], [3, 4]]
print(list(zip(*m)))          # CPython [(1, 3), (2, 4)]
                              # pascal26: error: expected expression

print(sum(*[[1, 2]]))         # CPython 3
                              # pascal26: cannot forward *args into sum — parameter l
                              #           has a type no runtime argument can be coerced to

xs = [1, 2, 3]
print(max(*xs))               # CPython 3
                              # pxx: compiles, then raises at run time:
                              #      "forwarded call got 3 arguments, expected 2 to 2"
```

Measured 2026-08-15, splitting out of
[[bug-nilpy-star-unpack-into-a-builtin-or-a-bound-method-is-refused]] once the
star-position half was fixed and the rest re-measured. `max` is the one that
matters most: it is the only shape here that reaches run time before failing.

## Why it is worth more than the arity sounds

`zip(*rows)` is THE transpose idiom — how a matrix is flipped, how columns are
named, how `dict(zip(*pairs))` is written. It is more common in real Python than
the general `f(*args)` forwarding that already works.

## One cause, three faces

Each of these is lowered by a path that settles its arity when the call is
PARSED:

- `zip` builds `pyiter_zip_ii` / `_iii` / `_iiii` by counting the arguments in
  the header — hence also the standing "zip() of more than four iterables is not
  supported yet". A star has no count at parse time, and the arm that would
  expand one is not on this path.
- `sum` is a pylib proc taking a `TPyList`; the run-time forwarder refuses it
  because a forwarded variant argument has no coercion to that parameter.
- `max`/`min` have 2-argument overloads only, so the forwarder's arity dispatch
  finds no arm for three and the guard fires at run time. CPython's `max(*xs)`
  equals `max(xs)`, which pxx already implements.

## The shape a fix probably takes

A `pyiter_zip_n(items: TPyList)` cursor over a LIST of iterables would take
`zip(*m)` and retire the four-way ceiling in the same change — one runtime entry
replacing three, which is a mechanism DELETED rather than a fourth added. For
`max`/`min`, a single-star call with no other arguments IS the iterable form and
can lower to it directly. `sum` wants the forwarder to box a variant into the
`TPyList` parameter.

## Gate

`.npy` diffed against CPython: `zip(*m)` for two, three and five rows;
`dict(zip(*pairs))`; `zip(*m)` where m is a tuple, a variant and a comprehension
result; `sum(*[xs])`; `max(*xs)` / `min(*xs)` for two and three elements and
against the iterable form; and controls that the fixed-arity spellings still
work.
