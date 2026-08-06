---
track: N
prio: 75
type: bug
status: done
owner: claude-AN
summary: "NilPy: in [[expr for j in ...] for i in range(n)] the inner comprehension is hoisted OUT of the outer loop and evaluated once with i at its initial value — and the same list object is appended to every row, so mutating one row mutates all"
---

# A nested comprehension over range() runs once, and every row is the same list

- **Type:** bug (silent wrong value + aliasing) — **Track N**
- **Found:** 2026-08-06, bughunting. Surfaced by an ordinary matrix-multiply
  probe returning confident, plausible, wrong numbers — not by a unit-shaped
  test. Pre-existing (identical on `pinned`).
- **Severity:** high. Grid/matrix construction is one of the most common uses of
  a nested comprehension in Python, and both failure modes are silent.

## Measured (before, self-hosted at `d3e8bd796`; identical on `pinned`)

```python
print([[i * 3 + j for j in range(3)] for i in range(3)])
# CPython [[0, 1, 2], [3, 4, 5], [6, 7, 8]]
# pxx     [[0, 1, 2], [0, 1, 2], [0, 1, 2]]

print([[i for j in range(2)] for i in range(3)])
# CPython [[0, 0], [1, 1], [2, 2]]
# pxx     [[0, 0], [0, 0], [0, 0]]
```

The rows are not merely equal, they are the SAME OBJECT:

```python
g = [[i for j in range(2)] for i in range(3)]
g[0][0] = 99
print(g)
# CPython [[99, 0], [1, 1], [2, 2]]
# pxx     [[99, 0], [99, 0], [99, 0]]
```

Cross-tabulating the two iterable kinds localised it exactly — **only the OUTER
one matters**, and the inner one is irrelevant:

| outer | inner | verdict |
| --- | --- | --- |
| `range()` | `range()` | WRONG |
| `range()` | container | WRONG |
| container | `range()` | correct |
| container | container | correct |

A single-level range comprehension (`[i * 10 for i in range(3)]`) was always
correct, which rules out the counted-loop lowering itself.

## Cause

An inner comprehension in the element expression hoists its own build loop onto
`PyHoistHead`. The CONTAINER path (`PyParseForIn`) ends up draining that
per-iteration; the range path drained nothing after parsing its element
expression, so the inner build stayed hoisted to the enclosing **statement** and
was emitted BEFORE the outer loop. It therefore ran exactly once, with the outer
loop variable still at its initial value, and the outer loop appended the
resulting list handle on every iteration — hence both the frozen value and the
aliasing, from one cause.

This is the residual of [[feature-nilpy-nested-comprehension]], whose own notes
identified hoisting as the hazard: *"The inner comprehension's own setup goes
through PyHoistStmt, which pushes statements out to the enclosing STATEMENT, i.e.
in front of the outer loop."* That ticket fixed the `undefined variable` error
the hoist caused on the container path; the range path was left silently wrong,
which is the worse half and is why it outlived the fix.

## Fix

In the range path's comprehension branch (`compiler/pyparser.inc`), after
building the append/store body from the element expression:

```pascal
    bodyNode := PySeqAppend(PyFlushHoist(-1), bodyNode);
```

— drain the pending hoist INTO the loop body, ahead of the append that consumes
its result. One line, mirroring what the container path already achieves.

## Verified

`test/test_nilpy_nested_comprehension_over_range.npy` (new, wired into
`make test-nilpy`) covers: outer-range/inner-range, outer-range/inner-container,
both container-outer controls, the two aliasing cases, single-level range
comprehensions, and a real build/transpose/multiply over a 3x3 matrix. All 14
lines match CPython. The wider probe corpus is unchanged and
`tools/gate.sh quick` is GREEN.

## Log

- 2026-08-06 — found, root-caused by cross-tabulating the iterable kinds, fixed
  and verified in one pass.
