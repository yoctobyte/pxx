---
track: N
prio: 45
type: bug
blocked-by: []
summary: "`[x + y for x in xs if x > 0 for y in range(2)]` — an `if` BETWEEN two for-clauses — is 'undefined variable (y)' on BOTH comprehension paths (container and range). A filter after the LAST clause is fine, and so are two clauses with no filter; it is only the interleaved position that fails"
status: done
owner: claude-AN
---

# A filter BETWEEN two `for` clauses is not supported

- **Type:** bug (compile error on ordinary code) — **Track N**
- **Found:** 2026-08-13, while fixing
  [[bug-nilpy-a-second-for-clause-fails-when-the-first-iterable-is-a-range]] —
  it is the one row of that ticket's matrix that stayed red, and it was already
  red on the CONTAINER path, so it is a separate defect rather than a piece of
  that one.

```python
print([x + y for x in [0, 1, 2] if x > 0 for y in range(2)])
# CPython [1, 2, 2, 3]
# pxx     error: undefined variable (y)  near: __py_cv6_0  y >>> for __py_cv6_0
```

## The boundary — the POSITION of the filter, on either path

| comprehension | result |
| --- | --- |
| `[x + y for x in xs for y in ys]` (no filter) | fine |
| `[x + y for x in xs for y in ys if y > 1]` (after the LAST clause) | fine |
| `[x for x in xs if x > 1]` (one clause, filtered) | fine |
| `[x + y for x in xs if x > 0 for y in ys]` (BETWEEN) | **error** |
| the same with `range()` in either clause | **error** |

CPython allows a filter after every clause, and the natural reading —
"filter the outer loop before entering the inner one" — is also the efficient
one, which is why the position is used.

## Where to look

Both paths (`PyParseForIn`'s comprehension arm and `PyParseFor`'s counted-range
arm) treat the filter as a suffix: they parse the element expression, then look
for a single trailing `if` and wrap the append in it. A clause-position filter
needs the filter to wrap the REST OF THE HEADER instead — the recursion into
the next clause has to happen INSIDE the AN_IF, not after it.

The two-clause recursion landed in
[[bug-nilpy-a-second-for-clause-fails-when-the-first-iterable-is-a-range]]
(and, for containers, in [[bug-nilpy-nested-for-comprehension-not-supported]]),
so the shape to add is: at the point where the header continues, if the next
token is `if`, parse the condition, then recurse for whatever follows and wrap
the recursion's body in the filter. Both paths need it — fixing one arm of a
double case is what `devdocs/dev/normalise-dont-special-case.md` is about, and
this bug is the second time this pair has diverged.

## Gate

A `.npy` diffed against CPython: the interleaved filter with a container first
clause and with a `range()` first clause, a filter on BOTH clauses, a filter
between three clauses, and the already-working suffix-filter rows as controls.

## 2026-08-13 — FIXED on both paths, same shape on each

A filter between clauses gates the inner LOOP, so it has to WRAP the rest of the
header. Both comprehension paths now recognise it at the point where the header
continues — `PyCompForAfter` answers "is there another depth-0 `for` before the
closer?" — parse the condition there, and recurse for the remainder INSIDE the
`AN_IF`. The trailing-filter arms are untouched and still gate the append.

**The stale CurTok was the one real surprise.** In the container path the
filter's `if` is temporarily rewritten to a fake `:` so the ITER expression
parser stops at it, and restored afterwards — but `CurTok` is a COPY taken when
the token was still the fake colon, so the test had to read `Tokens[TokPos - 1]`
and re-read the token before parsing. Testing `CurTok.Kind = tkIf` silently
never matched, which looked exactly like the arm not being reached.

Both paths were fixed in one pass rather than one-then-the-other: the ticket
already recorded that this pair has diverged twice, and the range path's arm is
five lines once the container path's is written.

### Gate

`test/test_nilpy_filter_between_for_clauses.npy` + `.expected` from CPython,
wired into `make test-nilpy`: the interleaved filter with a container first
clause and with a `range()` first clause, filters on BOTH clauses, a filter
between three clauses, a filter over a nested-list flatten, and the
already-working suffix-filter / no-filter / single-clause forms as controls.
`make test-nilpy` green, `gate.sh quick` GREEN.

## Log
- 2026-08-13 — resolved, commit d168d1fbf.
