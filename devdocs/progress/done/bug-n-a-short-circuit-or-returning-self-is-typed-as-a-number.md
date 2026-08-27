---
track: N
prio: 60
type: bug
blocked-by: []
summary: "`def m(self): return self or 1` dies with `TypeError: expected a number, got object` — a top-level short-circuit `or` hands back an OPERAND, and the def-return-type scanner types it from the wrong side. The `and` spelling answers correctly only because its truthy arm happens to be the int."
status: done
owner: frank1-AN
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

## Resolution — 2026-08-27

Fixedpoint `68e7d2d154fc`, `tools/gate.sh quick` GREEN.
Test: `test/test_nilpy_bool_op_return_type.npy` + `.expected`, registered in the
Makefile — and the two deferred rows in
`test/test_nilpy_arith_dunder_on_self.npy` are **folded back in**, as the Gate
section asked, with its comment rewritten to say why `kw_and` is not evidence.

Implemented as the ticket described, including the warning it ends with.

**The join is now spelled ONCE.** The ticket said the new arm "should not be a
third spelling of the join", so the conditional expression's inline copy was
extracted into `PyJoinInferTk(ta, ca, tb, cb, var ciOut)` and the ternary arm
became its first caller before the `and`/`or` arm became its second. The
extraction is behaviour-preserving — same unknown/same-class/widen ladder, with
`ciOut` carrying the class identity that `ASTTk` equality cannot (the reason
`bytearray() if flag else [1, 2]` once registered TPyBytes).

**Precedence, not just presence.** `or` is scanned at depth 0 first and `and`
only if no top-level `or` exists, because `a and b or c` is `(a and b) or c` —
the `or` is what decides the whole expression. Splitting at the FIRST operator
and recursing right handles chains (`a or b or c` joins `a` with `b or c`).
Depth-tracked, so an operator inside a call or a subscript does not claim the
enclosing expression.

**The `and` row is asserted everywhere in the new test, on purpose.** The
ticket's own warning — "do not read the `and` row as a working arm" — is a
property of the test suite too: `self and 1` yields the right operand because
self is truthy, and that operand is the int the old walk guessed anyway. A test
that asserted only `and` would have passed before this change.

**Canaries, all green, named individually:** `mixed_type_bool_op`,
`membership_bool_return`, `call_return_infer`, `def_return_type`,
`quick_canary_nilpy`, `lambda_returned_from_def`, `one_line_def_suite`,
`empty_tuple`, `kwarg_overload`, `nonlocal_escaping_closure`,
`def_returning_a_big_int`, `arith_dunder_on_self`, `return_type_inference`,
`infer_return`, `conditional_expression_none`, `variant_method_call`,
`a_rebound_parameter_widens`, `numeric_widen`, `container_kind_tag`,
`is_none_typed`, `lib_mimic_xml_etree_elementtree`. The ternary ones matter most
— that arm was rewritten, not just added beside.

## Log
- 2026-08-27 — resolved, commit 9678afd7f.
