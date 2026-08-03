---
track: N
prio: 20
type: bug
summary: "A NilPy `def sizeof(...)` is claimed by Pascal's SizeOf intrinsic — 'SizeOf: expected type name'. Loud and exotic, but the guard its sibling intrinsics already have is missing"
status: done
owner: agent-AN
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

## Fixed 2026-08-03

One condition, exactly as the fix direction predicted: `ParseFactorCore`'s
`CaseEqual(name, 'sizeof')` now declines under `PyExprMode` when a `(` follows
and `PyAnyProcWithArity(name, CountCallArgsAhead)` says the program declares a
routine of that name and arity — the same `FindSym`/`PyAnyProcWithArity` shape
the `min`/`max` branch already uses.

Gated on `PyExprMode`, so Pascal's `SizeOf` stays an intrinsic. That is not
taken on trust: the compiler itself uses `SizeOf` throughout, and the self-host
fixedpoint rebuilt byte-identical.

`test/test_nilpy_def_shadows_pascal_intrinsic.npy`, matching CPython, pins all
four names together (`sizeof`, `high`, `low`, `length` — the three that already
declined are pinned so they cannot silently regress into the same trap) plus a
`sizeof` METHOD on a user class. Registered at both `test-nilpy` Makefile sites.

Gate: `make compiler/pascal26` (self-host fixedpoint) + `tools/gate.sh quick`
GREEN.

The wider sweep this ticket asks for — auditing every Pascal intercept in the
shared `ParseExpr`/`ParseFactorCore` for a missing `PyExprMode` gate — is NOT
done here and stays worth doing; see
[[project_pascal_operator_intercepts_in_shared_parseexpr_claim_nilpy_syntax]].
The structural answer is a NilPy expression parser that never enters the Pascal
one, which is its own piece of work.

## Log
- 2026-08-03 — resolved, commit a686e8e36.
