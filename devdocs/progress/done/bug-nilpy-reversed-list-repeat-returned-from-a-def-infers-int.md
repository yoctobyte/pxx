---
track: N
prio: 30
type: bug
summary: "SILENT WRONG VALUE: `def f(u): return u * [7]` returns the list HANDLE as an integer — the reversed LIST repeat is built correctly but the def's inferred return type is Integer. `u * bytes(...)` and `[7] * u` are both fine."
status: done
owner: claude-AN
---

# A reversed list repeat returned from a def comes back as an integer

```python
def f(u):
    return u * [7]

print(f(2))        # CPython: [7, 7]        pxx: 127321897959656
```

No error — a heap handle printed as a number. The sibling forms all work:

```python
def g(u): return [7] * u          # OK
def h(u): return u * bytes([1])   # OK   (reversed BYTES is fine)
print(2 * [7])                    # OK   (not inside a def)
```

So it is specific to REVERSED order + LIST + returned from a def, which points
at the def's RETURN-TYPE inference rather than at the repeat lowering: the
repeat node itself carries tyClass and the TPyList record (PyMakeListRepeat sets
both, precisely so the identity survives into a local).

## Likely mechanism

NilPy infers a def's result by re-parsing the body, and the trial pass may see
the parameter before its type is known — `u` as tyUnknown rather than a variant
or an ordinal — so `PyIsRepeatCountTk` says no, the pair reads as arithmetic and
the result infers Integer. The REAL parse then builds the list correctly and
returns it through an Integer-typed result. That the reversed BYTES form escapes
this suggests the two do not share the inference path; find out which before
changing anything (see the trial-AST-typing note in
[[project_nilpy_class_attribute_lowering_matrix]]).

## PRE-EXISTING

Not introduced by
[[bug-nilpy-sequence-repeat-with-a-variant-count-falls-through-to-arithmetic]] —
it fails identically before that change. It was found by that ticket's test
matrix and deliberately left out of its scope rather than half-fixed;
`test/test_nilpy_sequence_repeat_variant_count.npy` says so in a comment.

## Gate

The four forms above oracle-diffed with `tools/pydiff.py`, the reversed-list case
added to `test_nilpy_sequence_repeat_variant_count.npy`, plus the per-fix loop.

## Fixed (2026-08-09, claude-AN)

`def f(u): return u * [7]` returns `[7, 7]`.

### The mechanism, and where the ticket's guess was close but not right

Not the parameter's type being unknown in the trial pass. `PyInferExprType`'s
literal recognisers all key on **what the expression STARTS with** — there is a
`Tokens[startIdx].Kind = tkLBrack` arm, and nothing that looks past a leading
operand. So `[7] * u` was typed a list and the reversed `u * [7]` fell straight
through to the arithmetic default.

The ticket's own observation was the clue: the repeat LOWERING accepts either
order (`PyIsListRepeatPair` tests both sides), which is exactly why the value
was built correctly and only the def's declared return type was wrong. Python's
`*` on a sequence is commutative; the inference now is too.

Added: a scan for the first TOP-LEVEL `*`, inferring the right-hand side and
adopting it when it is a `TPyList` or `TPyBytes`. Bytes is included even though
`u * bytes(...)` already happened to work — fixing the reported case alone would
have left the family half-done, and the test asserts both orders of both types.

### `**` is the trap

`**` is two `tkStar` tokens, so without an explicit guard `2 ** u` finds a
top-level star and recurses on `* u`. Excluded by checking the neighbouring
token on both sides, and `h(3)`/`i(3)` in the test are what catch it.

### Verification

`test/test_nilpy_reversed_sequence_repeat_return.{npy,expected}` (`.expected`
from CPython): both orders of list and bytes repeat, plus controls that carry
the weight here because `*` is a shared token — int, float, str repeat both
ways, tuple repeat, an expression on the left (`(u * 2) * [7]`), a `*` inside a
list literal (`[u * 2, 3]`), a call on the right (`u * len([1,2])`), and `**`
both ways round. Wired into `test-nilpy`.

`test_nilpy_{list_repeat,tuple_pow_builtins,list,bytes_repr}` re-diffed against
CPython: match. (`test_nilpy_str_float` differs from CPython because `trunc` is
a deliberate NilPy extension CPython has no builtin for — identical on the
pinned binary, so pre-existing and unrelated.)

`tools/gate.sh quick` GREEN.

## Log
- 2026-08-09 — resolved, commit 10772d418.
