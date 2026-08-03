---
track: N
prio: 20
type: bug
summary: "A NilPy `def sizeof(...)` is claimed by Pascal's SizeOf intrinsic — 'SizeOf: expected type name'. Loud and exotic, but the guard its sibling intrinsics already have is missing"
---

# A NilPy `def sizeof(x)` is hijacked by Pascal's `SizeOf` intrinsic

- **Type:** bug (frontend collision in the shared parser) — **Track N**
- **Found:** 2026-08-03, auditing for siblings of
  [[bug-nilpy-construction-on-the-right-of-is-does-not-parse]], where a Pascal
  operator intercept with no `PyExprMode` gate claimed NilPy syntax.

## Measured

```python
def sizeof(x: int) -> int:
    return 7


print(sizeof(3))        # CPython: 7     pxx: error: SizeOf: expected type name
```

`ParseFactorCore`'s `if CaseEqual(name, 'sizeof')` (parser.inc) takes the call
before the ordinary user-routine path, and its hand-rolled type dispatch then
rejects the integer argument.

## Why it is only prio 20

It fails **loudly** — a compile error naming SizeOf, not a wrong answer — and
`def sizeof` is not something Python code writes. It is filed because the guard
is one condition and its neighbours already have it: `high`, `low` and `length`
were checked in the same pass and all three honour a NilPy `def` of that name
correctly. `sizeof` is the odd one out, not a deliberate exception.

## Fix direction

Decline the intrinsic under `PyExprMode` when the program declares a routine of
that name — the same shape the `min`/`max`, `enumerate`/`zip` and `set` branches
use (`FindSym`/`FindProc`/`PyAnyProcWithArity`). Gating on `PyExprMode` keeps
Pascal's own `SizeOf` untouched, where it must stay an intrinsic; the self-host
fixedpoint is the check for that.

Worth doing as part of a wider sweep of the shared `ParseExpr`/`ParseFactorCore`
tail rather than alone — the audit that found this covered `is`/`as`, `sizeof`,
`high`/`low`, `ord`/`succ`/`pred`, `chr` and `length`, and only `is` (fixed) and
`sizeof` were wrong, but the tail is long and was not read exhaustively.

## Gate

A `.npy` defining `sizeof` and calling it, diffed against CPython, plus Pascal's
`SizeOf(Integer)` / `SizeOf(TRec)` still folding and the self-host fixedpoint
staying byte-identical.
