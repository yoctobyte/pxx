---
track: N
prio: 15
type: bug
blocked-by: []
summary: "`\"a\" < 3` with two LITERALS raises `unsupported operand type(s) for this operator` where CPython names both types. The dynamic shape already matches CPython exactly; only the statically-proven clash — where the compiler knows MORE — reports less."
status: done
owner: agent-AN
---

# A statically clashing operand pair refuses without naming the types

```python
"a" < 3      # CPython: TypeError: '<' not supported between instances of 'str' and 'int'
             # pxx:     TypeError: unsupported operand type(s) for this operator
```

The same comparison through variables is already byte-identical to CPython:

```python
def f(x): return x
f("a") < f(3)   # both: TypeError: '<' not supported between instances of 'str' and 'int'
```

Found 2026-08-15 while resolving
`bug-nilpy-comparing-none-with-a-number-answers-instead-of-raising`, whose test
had to exclude this one row.

## Where

Two literals never reach `pylt_v`/`pyvar_gt`. `IRPyNumStrClash` proves the clash
at compile time and the arm emits `PyUnsupportedOperandError` (pylib), a
procedure that takes no arguments and therefore cannot name anything. The
runtime path answers better than the static one precisely because it can see
the operands.

The mildly funny shape of it: the compiler has MORE information here (both types
are known at compile time, which is why it took this arm at all) and produces a
WORSE message. Ordinary "one concept, two mechanisms" — the informative wording
lives in only one of them.

## Fix sketch

`PyOrdCheck`'s wording is already the one CPython uses; the static arm needs the
two type names passed to a raiser that takes them, e.g.
`PyOperandClashError(op, lname, rname)` with all three as IR string constants
the lowering site already has (it knows the operator token and both `ASTTk`s).
`PyUnsupportedOperandError` stays for the arms that genuinely have no operand
types to name (a missing arithmetic dunder).

Same treatment likely applies to the arithmetic clashes (`"a" + 3` and friends)
that share the raiser — check them together rather than one operator at a time.

## Gate

`"a" < 3`, `3 > "a"`, and the arithmetic siblings diffed against CPython, plus
the dynamic rows of `test_nilpy_none_comparison_raises` unchanged.

## Resolution (2026-08-15)

The odd shape the ticket noticed — the compiler knowing MORE here and reporting
LESS — had a mundane cause: the WARNING at that site already composes CPython's
wording from `IRPyOpSpelling` and `IRPyOperandTypeName`, and the RAISER next to
it took no arguments at all. Both halves were already written; only one was
wired.

`PyOperandClashError(op, lk, rk)` takes three small integer codes.
Deliberately codes and not strings: an IR-built call bypasses the
materialised-managed-argument machinery, so three `IR_CONST_STR` arguments
would have leaked a string per raise (the trap
`IRPromoInitFromLiteral` records). `IRPyOpClashCode` and `IRPyOperandKindCode`
sit beside the two spelling helpers they mirror row for row, because a drift
between them puts the wrong symbol in a user's traceback.

**CPython does not use one shape, which is most of the work.** Measured, not
assumed:

| pair | CPython |
| --- | --- |
| `"a" < 3` | `'<' not supported between instances of 'str' and 'int'` |
| `"a" - 3` | `unsupported operand type(s) for -: 'str' and 'int'` |
| `"a" + 3` | `can only concatenate str (not "int") to str` |
| `"a" * "b"` | `can't multiply sequence by non-int of type 'str'` |

All four are reproduced. The `+` rows needed a second site: `str + number` never
reaches the static arm at all — it routes to `pyadd_v`, which fell through to
`pyvar_to_float` and raised the generic `expected a number, got str`, a message
about a coercion naming neither the operator nor the other operand. `pyadd_v`
knows both runtime tags, so it now raises CPython's two asymmetric messages
directly: `str + x` is a failed CONCATENATION, `x + str` is a failed addition.

`*` also gained its spelling in `IRPyOpSpelling`, which had no `tkStar` row —
`"a" * "b"` warned about operator `'?'`.

### Gate

`test/test_nilpy_operand_clash_messages.npy`, byte-identical to CPython: four
comparison rows, five arithmetic rows, bool and float operands so the type
names are exercised beyond str/int, str's own two shapes, and — the other half
of the claim — fourteen pairs that ARE defined still computing, so the refusal
cannot have grown a false positive. `test_nilpy_operator_dunder_missing_fail`,
`test_nilpy_none_comparison_raises` and `test_nilpy_str_concat` re-run green.

### Not covered

A container against a scalar (`[1] + 3`) still reaches the generic raiser rather
than CPython's `can only concatenate list (not "int") to list`. Same family, one
more arm in `pyadd_v`, left because no row of this ticket asked for it and the
message it gives today is at least about the right operator.

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
