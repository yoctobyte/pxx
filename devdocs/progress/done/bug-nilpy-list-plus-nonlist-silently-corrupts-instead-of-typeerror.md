---
track: N
prio: 55
type: bug
blocked-by: []
---

# `[list] + non-list` silently corrupted instead of raising TypeError

Found by proactive CPython-diff sweeping — a genuinely dangerous
silent-wrong-value bug (this repo's known worst failure mode: no crash, no
error, just a plausible-looking wrong answer far from the cause).

```python
a = [1, 2, 3]
print(a + "x")
```
CPython: `TypeError: can only concatenate list (not "str") to list`.
pxx (before this fix): compiled cleanly and printed `x` — the list's contents
were silently dropped and only the string operand survived.

## Root cause

`compiler/parser.inc`'s shared binop-typing chain has a list-concat branch
(`PyNodeIsPyList(left) and PyNodeIsPyList(right)` → `pylist_concat`) that
requires BOTH operands to be lists. When only one side is (as in `a + "x"`),
that branch doesn't match, and the very next branch down —
`(op = tkPlus) and ((ASTTk[left] = Ord(tyString)) or (ASTTk[right] =
Ord(tyString)) or ...)` — only checks that EITHER side is string-typed and
never notices the OTHER side is actually a raw `tyClass` (list) POINTER, not a
string. The node gets typed and lowered as an ordinary string concat, which
reinterprets the list's pointer bits as string data instead of raising.

## Fix

Added a guard directly above the string-concat branch: `PyExprMode and (op =
tkPlus) and (PyNodeIsPyList(left) or PyNodeIsPyList(right))` — since the
list-concat branch immediately above it already accepted the
both-are-lists case, reaching this guard means EXACTLY one side is a list, so
it always errors. NilPy resolves types statically, so this is caught as a
**compile-time** error (`Nil Python: can only concatenate list with another
list (+)`) rather than deferred to a run-time exception — consistent with how
this frontend already treats other statically-decidable type mismatches
(e.g. `PyBitGuard`'s comparison-parenthesization check) as compile errors.

Regression test `test/test_nilpy_list_plus_nonlist_fail.npy` (the
established `_fail.npy` convention: `! $(COMPILER) ... ; grep -q "<message>"`)
gated in `test-nilpy`; confirmed legitimate `list + list`, `list * int`, and
`str * int` are unaffected. `tools/testmgr.py --tier quick` and the full
`test-nilpy` suite green (nothing else relied on the old broken fallthrough).
Self-host confirmed byte-identical via `make pxx-debug`.

## Log
- 2026-07-31 — resolved, commit HEAD.
