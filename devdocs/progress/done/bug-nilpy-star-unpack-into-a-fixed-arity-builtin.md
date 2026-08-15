---
track: N
prio: 30
type: bug
blocked-by: []
commit: PENDING-COMMIT
summary: "`zip(*rows)` — the transpose idiom — did not parse, `zip` of five streams was refused outright, and `max(*xs)` compiled and then raised at run time. One cause: the arity was settled while PARSING. pyiter_zip_n over a LIST of iterables replaces the fixed chain and deletes the four-stream ceiling with it. `sum(*xs)` re-filed."
status: done
---

# `*xs` into a fixed-arity builtin

```python
m = [[1, 2], [3, 4]]
print(list(zip(*m)))          # CPython [(1, 3), (2, 4)]
                              # was: error: expected expression

print(list(zip(a, b, c, d, e)))
                              # was: zip() of more than four iterables is not supported yet

xs = [1, 2, 3]
print(max(*xs))               # CPython 3
                              # was: compiles, then raises "forwarded call got 3
                              #      arguments, expected 2 to 2"
```

`zip(*rows)` is THE transpose idiom — how a matrix is flipped, how columns are
named, how `dict(zip(*pairs))` is written — and it is more common in real Python
than the general `f(*args)` forwarding that already worked. Split out of
[[bug-nilpy-star-unpack-into-a-builtin-or-a-bound-method-is-refused]] and
measured 2026-08-15.

## Fix — one run-time entry instead of a taller fixed chain

`zip` was lowered by counting its streams while parsing: `pyiter_zip_ii` /
`_iii` / `_iiii`, one pylib entry per arity, four `FUp` fields on the cursor,
and a diagnostic where the chain ran out. A star has no count at parse time, so
it fell into the expression parser, where `*` is not an expression.

`PYITER_ZIPN` holds its streams in `FSrc` as a LIST of cursors and walks them,
so the count is a run-time fact: `pyiter_zip_n(items: TPyList)` converts each
element with `pyiter_v` — the one iterable-to-cursor conversion — which is why a
row may be a list, a str, a range, a dict, a cursor or a user iterable without
an arm per shape. The same entry takes zip past four, so **the ceiling is gone
rather than raised**: a mechanism deleted, not a fifth field added
(`devdocs/dev/root-cause-over-microfix.md`). Shortest-wins and left-to-right
consumption are unchanged, and the two/three/four-way lowering is untouched — a
pair still yields a PAIR.

**Three frontend sites, because zip has three:** the value form
(`list(zip(*m))`), the >4 collection, and the STATEMENT for-header desugar
(`for a, b in zip(*m):`, which walks two named containers by index and cannot
serve a starred one — it now falls through to the pair-unpack path over the
expression, exactly as the comprehension form already did). The third was found
by the test, not by reading: the first two passed while the loop did not.

`max`/`min` are the two names for which CPython's `f(*xs)` and `f(xs)` are the
same call, so a starred call lowers to the ITERABLE form and ordinary overload
matching picks `max(TPyList)`. A two-entry list, deliberately not a rule —
`sum(*xs)` and `sorted(*xs)` do not have that property.

## Not fixed: `sum(*[xs])`

Still refused, loudly: "cannot forward *args into sum — parameter l has a type
no runtime argument can be coerced to". It is the run-time forwarder's
parameter-coercion check, not the zip mechanism, and `sum(*...)` is rare enough
not to justify widening that check in this commit. Re-filed as
[[bug-nilpy-star-forwarder-refuses-a-container-typed-parameter]].

## Gate

`test/test_nilpy_zip_star_and_n_way.npy` (+`.expected`, in the Makefile),
byte-identical to CPython: transpose of two and three rows, transposed twice,
`dict(zip(*pairs))`, rows that are strs / ranges / mixed shapes, uneven rows,
an empty row, no rows at all, a single row; five and six written-out streams;
the two/three/four-way controls; a starred zip in a for LOOP and in a
comprehension; the operand as a slice, a call and a variant; and
`max`/`min` starred against their iterable and two-argument forms.
`gate.sh quick` GREEN, pinned v328 (the change touches `compiler/builtin/**`).

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
