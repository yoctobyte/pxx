---
track: N
prio: 30
type: bug
blocked-by: []
status: done
owner: claude-AN
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

## Fixed 2026-08-03

`PyBitGuard` now fires only on a **bare (unparenthesized) comparison AN_BINOP**
— keyed on the node's KIND and operator token, not on its type. Keying it on
"any tyBoolean operand" was rejecting two legitimate shapes:

- `a & b` on real booleans (CPython computes it — `bool` subclasses `int`);
- `(x > y) & (y > x)` — the parenthesized form the diagnostic's own message
  asks the user to write, which was ALSO refused. So the error was
  unactionable: neither spelling compiled.

The paren case needed a marker, since the AST keeps no record of grouping:
`PY_BINOP_PARENED = 4` (defs.inc), stamped in `ParseFactor`'s `tkLParen` arm
under `PyExprMode`, and only onto a node whose `ASTSLen` marker slot is still
0 — `PY_BINOP_IDENTITY`/`PY_BINOP_AUGADD` share that field and outrank it, so
`(a is b) & c` is the one residual shape still refused (rare enough not to
chase; `is` already yields a bool you can bind first).

### A second bug fell out, which is why this is not a one-line diff

With the guard lifted, `True & 1` **SEGFAULTED** — the same shape
`PyBitDunder` was written for. `PyWiden(tyBoolean, tyInteger)` hits neither
the numeric rule (`PyNumeric` excludes Boolean) nor a string rule, so it fell
through to the box-them-both rule and returned `tyVariant` — a raw Boolean and
a raw Integer typed as a variant, dereferenced as a variant record. The guard
had been masking it.

Fixed with `PyBitTk`/`PyBitWiden` (pyparser.inc): a bitwise operand
contributes `tyInteger` where it is `tyBoolean`, so bool widens WITH the ints;
`bool ⊕ bool` stays `tyBoolean`, which is a real Pascal bitwise op and was
already correct. All four sites (`&`, `|`, `^`, and the shift layer) route
through it.

### Verified

`test/test_nilpy_bitwise_on_booleans.npy` (new, registered in both `test-nilpy`
Makefile sites): `&`/`|`/`^` on booleans, parenthesized comparisons on both
sides of a bitwise op, bool⊕int mixes, and `<<`/`>>` with a bool operand — all
diffed byte-identical against CPython. `x & 1 == 1` still errors, i.e. the
precedence typo the guard exists for is still caught. Set `&`/`|`/`^` and dict
`|` re-checked and unchanged. `tools/gate.sh quick` GREEN (self-host
fixedpoint + `--tier quick` + FPC seed canary).

## Log
- 2026-08-03 — resolved, commit PENDING-COMMIT.
