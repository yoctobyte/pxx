---
track: N
prio: 60
type: bug
---

# Arithmetic on mismatched operand types silently does POINTER math

```python
print(3 - "ab")       # CPython: TypeError    pxx: -5271260
print(3 * {"k": 1})   # CPython: TypeError    pxx: 372863378918136
print(3 < [1, 2])     # CPython: TypeError    pxx: True
print(3 - None)       # CPython: TypeError    pxx: 3
```

The second operand's HANDLE is used as a number, so the result is an address
difference — a different value on every run, silently. No error, no warning,
and the number is plausible enough to flow onwards. This is precisely the
failure mode the debugging playbook is built around: a wrong value far from its
cause.

Found by sweeping every binary operator against every operand-type pair and
diffing against CPython. It affects `-`, `*`, `/`, `//`, `%`, `<`, `<=`, `>`,
`>=` — the whole arithmetic and ordering family. `+` is correct (it dispatches
on the operand types already), and `and`/`or` are correct, which shows the
machinery to do this exists and is simply not reached by the other operators.

`None` deserves its own mention: `3 - None` yields `3`, i.e. None is silently
read as 0, so a missing value propagates as a legitimate-looking number rather
than failing.

## What to do — needs a decision (Track U)

NilPy has no exceptions-on-type-error story, and a fully dynamic check on every
arithmetic op has a cost. Three options, roughly:

1. **Compile-time error when both operand types are statically known** and the
   pair is meaningless. Cheap, catches the literal cases above and most real
   ones, no runtime cost. Does not catch variant-typed operands.
2. **Runtime ZeroDivisionError-style raise** from the variant arithmetic
   helpers when the tags do not admit the operator. Complete, costs a tag check
   per dynamic op (the helpers already switch on the tag, so the check is
   nearly free where it matters).
3. Leave as-is and document the divergence. Rejected as written here — a value
   derived from a heap address is not a documentable semantic.

Recommendation: 1 and 2 together — 1 is a small change with immediate value,
2 closes the dynamic hole. Filed as
[[decide-nilpy-mixed-type-operand-policy]] because it sets NilPy's stance on
type errors generally, not just for these operators.

## Gate

`make test-nilpy` + self-host byte-identical, plus the operator × operand-type
table from the sweep, diffed against CPython.

## Policy settled 2026-07-30 — see [[decide-nilpy-mixed-type-operand-policy]]

1. `PyTypeError` raises instead of halting (the mechanism already works; only
   these call sites were never converted).
2. The operator arms reach the type dispatch `+` and `and`/`or` already use.
3. Statically provable mismatches WARN — they do not abort. Warning text should
   say it is provable, and name both operand types.

`-Werror` is deliberately not the opt-in for step 3; see the decide ticket.
