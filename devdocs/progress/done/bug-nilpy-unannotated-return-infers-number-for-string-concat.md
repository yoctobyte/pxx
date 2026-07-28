---
summary: "nilpy: an unannotated def returning `variant + str` infers a NUMERIC return and prints garbage"
type: bug
track: N
prio: 70
---

# nilpy: unannotated `return <variant> + <str>` infers a number

- **Type:** bug (Nil-Python frontend, return inference) — **Track N**
- **Opened:** 2026-07-27. PRE-EXISTING: reproduces on the pinned stable.
- **Severity:** silent wrong output, the class this project treats as worst.

## Repro

```python
def mk(k, t, reason="r"):        # no return annotation
    return k + reason

print(mk("a", 9, reason="X"))    # pxx: a large integer (or TypeError at run time)
                                 # CPython: aX
```

Add `-> str` and it is correct. The parameter `k` is unannotated, so it is Any
(a variant); `reason` is a defaulted str. `k + reason` is therefore a
variant+string concatenation, but `PyInferDefRetType` types the def's result as a
number, and the caller then reads the returned string handle as an integer.

Two shapes were seen from the same cause, depending on what the value met next:
printing it gave a garbage integer, and using it in another concatenation raised
`TypeError: expected a number, got str` at run time.

## Where

`PyInferDefRetType` (pyparser.inc) walks the body's `return` expressions. For a
binary `+` it needs the same rule the expression parser already applies: if
either operand is string-ish the result is a string, and if the operands are a
variant and a string the honest answer is a string too (concatenation is what
`pyadd_v` does at run time). When it cannot decide, tyVariant is the safe answer
— boxing costs a little, guessing costs correctness.

## Why it matters

Unannotated helpers are ordinary Python, and this is the most common shape there
is: build a label from a couple of values and return it. songformatter's
key_analysis.py is full of them.

## Gate

`make test-nilpy` green with a `.npy` case covering an unannotated def returning
a variant+str concatenation, the result printed AND fed into another
concatenation, diffed against CPython, + `tools/gate.sh quick`.

## Log
- 2026-07-28 — resolved, commit dcbca98c1.

## Resolution

Fixed by dcbca98c1 ("fix(nilpy): return inference must agree between passes"),
which is the same PyInferDefRetType work that closed
[[bug-nilpy-comparison-return-type-from-operands]]. The ticket was left in
`backlog/` by that commit.

Re-verified 2026-07-28: this ticket's repro prints `aX`, matching CPython.
