---
track: N
prio: 60
type: bug
blocked-by: []
summary: "`def m(self): return self or 1` dies with `TypeError: expected a number, got object` — a top-level short-circuit `or` hands back an OPERAND, and the def-return-type scanner types it from the wrong side. The `and` spelling answers correctly only because its truthy arm happens to be the int."
---

# A short-circuit `or` returning `self` is typed as a number

Found 2026-08-27 while fixing
[[bug-n-an-arithmetic-dunder-on-self-is-pointer-arithmetic]], from a line
written to prove the operator table does NOT claim `and`/`or`. It does not —
this is a different mechanism, and it is **pre-existing**: identical at HEAD and
under `stable_linux_amd64/default/pinned`.

```python
class N:
    def kw_and(self):
        return self and 1
    def kw_or(self):
        return self or 1
n = N()
print(n.kw_and())   # CPython 1                              pxx 1
print(n.kw_or())    # CPython <__main__.N object at 0x...>   pxx TypeError
```

pxx: `Unhandled exception: TypeError: expected a number, got object`.

## Why `and` looks fine and is not evidence

`self and 1` yields the RIGHT operand because `self` is truthy, and that operand
is an int — which is what the scanner guessed anyway. `self or 1` yields the
LEFT operand, an instance, and the guess is wrong. Both go through the same
un-typed path; only one of them is caught by coincidence. Do not read the `and`
row as a working arm.

Outside a method it is already right — `n and 1` / `n or 1` / `1 if n else 0` /
`bool(n)` all match CPython at HEAD and at pinned. It is the def's REGISTERED
RETURN TYPE that is wrong, the same owner as the ticket this came from.

## Shape of the fix

`PyInferExprType` (pyparser.inc) already knows this rule exists — the
true-division arm's comment excludes a top-level `and`/`or` in as many words,
"Python hands back an OPERAND for the first" — but nothing then TYPES that case,
so it falls to the walk below and takes an arithmetic answer.

Python's answer is the JOIN of the two operands: equal kinds keep the kind,
different kinds are a variant. That is the same conclusion the conditional
expression arm a few lines above already reaches for `x if c else y`, and the
same one the reassigned-local rule reaches — so the shape to copy is in the file
(devdocs/dev/normalise-dont-special-case.md: the arm should not be a third
spelling of the join).

Note the enclosing class is now reachable for a bare `self` via `PyInferSelfCi`,
added by the ticket this came from, so an operand that IS `self` can be typed
rather than guessed.

## Gate

The four lines above matching CPython, plus the two `and`/`or` rows that
`test/test_nilpy_arith_dunder_on_self.npy` documents as deliberately NOT
asserted — fold them back in when this closes.
