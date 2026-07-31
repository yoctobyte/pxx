---
track: N
prio: 30
type: bug
blocked-by: []
---

# `&`/`|`/`^` on boolean-typed operands unconditionally rejected by PyBitGuard

`PyBitGuard` (`compiler/pyparser.inc`) errors on ANY `tyBoolean`-typed operand of
a bitwise operator, intending to catch the common Python typo of writing `a & b
== c` instead of `(a & b) == c` (a comparison mistakenly chained with a bitwise
op). But it's applied unconditionally, so it also rejects Python code that
deliberately uses `&`/`|`/`^` as *logical* and/or/xor on real booleans — which
CPython supports fine (`bool` is an `int` subclass):

```python
a = True
b = False
print(a & b)
```

fails to compile with:
```
pascal26:3: error: Nil Python: parenthesize the comparison next to a bitwise operator
```

Confirmed pre-existing (not introduced by the concurrent set/dict-operator fix,
bug-nilpy-set-and-dict-operators-do-raw-pointer-arithmetic) by reproducing
against a stashed pre-fix binary — identical failure.

## Fix direction

`PyBitGuard` needs to distinguish "operand is itself the result of a comparison
expression" (the real typo case) from "operand is a boolean value/variable used
deliberately" — e.g. only fire when the immediate operand AST node is a
comparison-operator node (`<`, `>`, `==`, etc.), not for any `tyBoolean`-typed
node in general (a bare variable/literal of type Boolean should pass through to
plain `AN_BINOP` bitwise codegen, matching CPython's bool-is-int semantics).

Not yet investigated further — filed for a dedicated session since it's a
distinct correctness/ergonomics call, not a crash, and un-gates real (if
uncommon) Python code that boolean-combines with `&`/`|`/`^` rather than
`and`/`or`.
