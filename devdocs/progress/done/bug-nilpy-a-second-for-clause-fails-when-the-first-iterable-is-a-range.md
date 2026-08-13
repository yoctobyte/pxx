---
track: N
prio: 50
type: bug
blocked-by: []
summary: "`[x + y for x in range(2) for y in [10]]` is 'undefined variable (y)' — a two-for comprehension works only when the FIRST clause iterates a list; a range() there takes a fast path that never binds the second clause's name. `for x in <list> for y in range(...)` is fine, so it is the first iterable alone that decides"
status: done
owner: claude-AN
---

# A second `for` clause fails when the FIRST iterable is a `range()`

- **Type:** bug (compile error on ordinary code) — **Track N**
- **Found:** 2026-08-12, differential bug hunting against CPython.
- **Related:** [[bug-nilpy-nested-for-comprehension-not-supported]] (done) made
  the two-for comprehension work; this is the arm it did not reach.

```python
print([x + y for x in range(2) for y in [10]])     # error: undefined variable (y)
print([x + y for x in [10] for y in range(2)])     # fine -> [10, 11]
```

## The boundary — the FIRST iterable decides, and only it

| comprehension | result |
| --- | --- |
| `[x + y for x in range(2) for y in [10]]` | **error: undefined variable (y)** |
| `[x + y for x in range(2) for y in range(3)]` | **error: undefined variable (y)** |
| `[(x, y) for x in range(2) for y in range(2)]` | **error: undefined variable (y)** |
| `[[x, y] for x in range(2) for y in range(2)]` | **error: undefined variable (y)** |
| `[x for x in range(2) for y in range(2)]` | **error: unexpected token** |
| `[x + y for x in [10] for y in range(2)]` | ok — `[10, 11]` |
| `[x * 10 + y for x in [1,2] for y in [3,4]]` | ok — `[13, 14, 23, 24]` |
| `[x + y for x in rng for y in rng]` (a NAME holding a list) | ok — `[0, 1, 1, 2]` |
| `[c for r in rows for c in r]` (the flatten idiom) | ok |

So the second clause is parsed and lowered correctly in general; a `range()` in
the FIRST clause routes the comprehension onto a different (counted) path that
consumes the rest of the header without ever binding the second target. The
element expression only changes WHICH error you get — using the second name
gives "undefined variable", not using it gives "unexpected token", which is the
tell that the header, not the element, is what got mis-parsed.

## Why it matters

`for i in range(n) for j in range(m)` is the plainest way to write a nested
iteration in a comprehension — grids, pair tables, index products — and
`range()` is the first iterable anyone reaches for. The workaround (bind the
range to a name first, or use a list) is not discoverable from the message.

## Where to look

The `range()` fast path in the comprehension lowering (pyparser.inc, the
comprehension header parse — the same code the flatten fix in
[[bug-nilpy-nested-for-comprehension-not-supported]] taught about a second
clause). Expect a straight case of one shape's handler predating the multi-
clause support: the fix is to make the counted-range arm loop over the
remaining `for`/`if` clauses exactly as the general arm does, not to special-
case two clauses. Check the `if` filter on the same path while there —
`[x for x in range(4) if x > 1]` works, but `for x in range(2) for y in ... if
...` is worth a row in the test.

## 2026-08-12 — attempted, reverted, and here is exactly where it stops

Nothing landed. The obvious fix was implemented and measured; it does not work,
and the measurement is the useful part.

**What was tried.** The CONTAINER path already handles a second clause by
recursing into `PyParseFor` (`if PyIsIdent('for') then node := PyParseFor`, the
flatten-idiom fix). The counted-range path in `PyParseFor` has no such arm, so
one was added at the same point — after the element-expression rename, before
the `if` filter — plus a rename of the outer loop variable across the WHOLE
remaining header (not just the element expression), since the inner clause's
iterable and filter may mention it (`for y in range(x)`).

**What happens.** The arm IS reached — probed, `CurTok.SVal = 'for'` and
`PyIsIdent('for')` is True at that point, in the real parse, both inside a def
and at module level. But after `bodyNode := PyParseFor` returns, a probe shows
**the cursor is back ON the same `for`**, so the caller
(`PyParseListComp`/`PyParseCompExprValue`) then fails its `Expect(tkRBrack)`
with "Expected: ], but got: for". The recursive call is not consuming its
clause.

That is the whole question for the next session: *why does the recursive
`PyParseFor` leave the cursor where it started, when the identical recursion
from the container path works?* Both enter with `CurTok` on the `for`, and
`PyParseFor` opens with `forTokIdx := TokPos - 1; Next;`. Suspects, in order:
the inner clause's own `compSaved` restore (`TokPos := compSaved; Next`)
computing a different token than expected because the outer range header left
`TokPos` somewhere unusual; and the interaction with `PyCompHiddenLoopName`,
which the range path uses for its counter and the container path does not.

The reverse order — a CONTAINER first clause with a `range()` second — works
today (`[x + y for x in [0,1] for y in range(2)]` is correct), which is the
control that says the recursion mechanism itself is sound and it is the range
path's own bookkeeping that is off.

## Gate

A `.npy` diffed against CPython: every row of the table above, plus a
three-clause comprehension, a filter on each clause, a dict and a set
comprehension with the same header, and the tuple-element form (the shape that
found this).

## 2026-08-13 — FIXED. The 08-12 attempt was right; it was never calling itself

The parked handoff asked one question — *why does the recursive `PyParseFor`
leave the cursor where it started, when the identical recursion from the
container path works?* — and listed `compSaved` bookkeeping and
`PyCompHiddenLoopName` as suspects. Both are innocent.

**There was no recursive call.** `bodyNode := PyParseFor;` INSIDE `PyParseFor`
reads the function's own RESULT variable in this dialect; it does not recurse.
`PyParseFor()`, with the parentheses, does. That is why the cursor never
moved and why nothing was consumed — and it is exactly the trap recorded in
`project_bare_funcname_result_partial`, which the compiler now warns about by
default (the warning is not raised here because this file is compiled by the
PINNED binary during a self-host round, so it never reached the terminal).

The container path's recursion works because it lives in `PyParseForIn` — a
DIFFERENT function — where the bare name really is a call.

Probing beat reading again: the trace showed the inner `PyParseFor` printing no
entry line at all, which is what turned "the recursion returns wrong" into "the
recursion did not happen".

**The second half of the fix is real, though**, and the 08-12 note had it: the
outer loop variable must be renamed over the WHOLE remaining header, not just
the element expression, because the inner clause's iterable may name it
(`for y in range(x)`). `PyParseForIn` renames up to `closerPos` for exactly
this; the range path renamed only the element range and its own filter. Both
now do the same thing.

### One row of the matrix stays red, and it was already red

`[x + y for x in xs if x > 0 for y in ys]` — a filter BETWEEN clauses — fails
on the CONTAINER path too, at the pin, so it is not this bug and not a
regression from this fix. Filed as
[[bug-nilpy-a-filter-between-two-for-clauses-is-not-supported]] with the
measurement, and the row is not in this ticket's test.

### Gate

`test/test_nilpy_two_for_clauses_over_range.npy` + `.expected` from CPython,
wired into `make test-nilpy`: every row of this ticket's table, a three-clause
comprehension, the outer variable used in the inner ITERABLE
(`for y in range(x)`), a trailing filter, dict and set comprehensions with the
same header, the tuple- and list-element forms, and a `sum()` over the result.
`make test-nilpy` green, `gate.sh quick` GREEN.

## Log
- 2026-08-13 — resolved, commit PENDING-COMMIT.
