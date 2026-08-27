---
track: N
prio: 70
type: bug
blocked-by: []
summary: "`return lambda x: ...` yields a value that is NOT callable — `TypeError: object is not callable (no __call__)` where CPython calls it. Binding the same lambda to a local first (`g = lambda ...; return g`) works, so the lift is fine and it is the RETURN of the lambda expression that loses the callable tag."
status: done
owner: agent-A
---

# A lambda returned directly is not callable

- **Type:** bug (NilPy frontend) — **Track N** (`compiler/pyparser.inc`).
- **Filed by:** frank2 on Track A, 2026-08-19, while probing
  [[refactor-a-one-signature-record-for-every-callable-carrier]]. Found by a
  probe, not by the ticket; unrelated to that refactor (it reproduces on the
  pinned compiler too).

## Measured at HEAD (9477001a8, self-host converged)

```python
def mk(k):
    return lambda x, y=2: x * 100 + y + k
a = mk(1)
print(a(5))
print(a(5, 9))
```

| | output |
| --- | --- |
| CPython | `503` / `510` |
| pxx | `Unhandled exception: TypeError: object is not callable (no __call__)` |

## The shape that WORKS — same lambda, one local in between

```python
def mk(k):
    g = lambda x, y=k: x * 100 + y
    return g
a = mk(1); b = mk(7)
print(a(5), b(5), a(x=5))     # 501 507 501, matching CPython
```

So the lift, the captures, the per-instance defaults and the keyword path are
all fine. What differs is only that the lambda expression is the operand of
`return` rather than of an assignment — the callable BOXING (`pyvar_of_callable`,
which is what stamps VT_CALLABLE/the bound-fn tag) is presumably applied on the
assignment path and not on the return path, so the caller receives a payload
with a tag that `PyNotCallable`'s allow-list rejects.

## Why it matters

`return lambda ...` is the single most idiomatic way to write a closure factory
in Python, and it fails while its two-line spelling works — a difference no
Python author would predict. It is also a silent-looking failure at the CALL
site, far from the `return` that caused it.

## Suggested first look

`PyBoxCallableValue` / `PyNodeIsCallableValue` (`compiler/pyparser.inc`) decide
where a callable-producing node gets boxed. Check whether the `return`
statement's expression runs through the same box as an assignment's RHS — the
allow-list already carries the whole `pyboundfn_*` chain, so the likely gap is
that the return path never asks.

---

## Resolved 2026-08-27

### The ticket's "suggested first look" was the one place that was NOT wrong

It pointed at `PyBoxCallableValue` and asked whether the `return` path runs the
same box as an assignment's RHS. It does — `pyparser.inc` ~25680, with a comment
naming the sibling ticket it was added for. `PXXDBG=n.bfn` confirms the boxing
happens on both spellings. So the box was never the problem, and reading the
ticket's hypothesis as a diagnosis would have sent the fix to the wrong file.

### What it actually was — one comma, counted by the wrong scanner

`PXXDBG=n.ret`, the same two programs:

```
return lambda x, y=2: ...       tk=6  rec=42     (tyClass, TPyList)
g = lambda x, y=2: ...; return g  tk=22           (tyVariant)
```

The def's inferred RETURN TYPE is a **tuple**. `PyInferDefRetTypeScan` decides
"is this `return a, b`?" by scanning for a comma at bracket depth 0 — and

```python
return lambda x, y=2: x * 100 + y + k
                ^ this comma
```

separates the **lambda's own parameters**, at depth 0, in a scan that knows
nothing about lambdas. So the def was typed `tyClass`/TPyList, the correctly
boxed callable was stored into a class-typed result, and the caller received
something it could not call. The scan's *own* arm for a returned lambda —
`` `return lambda ...` is a CALLABLE VALUE, which travels as a variant `` — sits
**later in the same else-if chain**, so it could never fire for any lambda
declaring more than one parameter.

That is also exactly why the ticket's "works when bound to a local first"
observation is true: no `return`-level comma.

### The fix, and why not the obvious one

Skip from `lambda` to its `:` while scanning for the tuple comma. **Not** by
moving the lambda arm above the tuple test, which was the tempting one-line
change and is wrong: `return lambda x: x, 1` really *is* a tuple whose first
element is a lambda, and CPython reads it that way. Only the PARAMETER list is
exempt; commas in the lambda's BODY still count. A default value containing a
colon (`lambda x, y={1: 2}: ...`) sits inside brackets, so its depth is not 0
and it cannot end the header early. All three are controls in the witness.

### The sibling, found by asking every other position the same question

`self.h = lambda x, y: x + y` in a constructor was **`cannot infer the type of
field self.h - annotate it`** — a compile error on ordinary Python — while the
one-parameter `self.h = lambda x: x + 1` compiled, because its *body* typed the
field and happened to be harmless. Same construct, two answers, decided by
whether the parameter list had a comma in it.

The field pre-pass asks `PyInferExprType`, which had no lambda case at all: a
lambda's body is an expression, so every operator arm in that scan typed the
whole lambda by it — `lambda x, y: x + y` looked like an int addition,
`lambda p: p > 1` like a Boolean, `lambda n: n / 2` like a float. Fixed by
answering tyVariant for an expression that *starts* with `lambda`, placed
**first**, before the paren strip and before every operator scan, since the
keyword governs everything after it. One arm; the dict-value, list-element,
`key=` and argument positions all come along.

### Found while probing, NOT fixed here

`a, b = lambda x: x + 1, lambda x: x + 2` compiles and then raises
`TypeError: object is not callable` — the tuple-UNPACK targets never box the
callable. Identical at HEAD and at pinned v380, i.e. pre-existing. Filed as
[[bug-n-a-tuple-unpacking-assignment-does-not-box-a-callable-value]] (p55); it
would be the fourth position to need `PyBoxCallableValue`, which is an argument
for asking where that decision lives rather than adding a fourth call.

### Gate

`make compiler/pascal26` (fixedpoint `31c875946ff9`), `tools/gate.sh quick`
GREEN, and a witness row `test_nilpy_lambda_returned_directly` in `test-core`:
six closure-factory shapes (zero-arg, one, two, defaulted, `*args`, no capture),
the three tuple controls, the two-line spelling that always worked, and the
field/dict/list/`key=`/argument positions. `.expected` is CPython's own output.
At pinned v380 it does not compile.

No pin needed: `compiler/builtin/**` is untouched.

## Log
- 2026-08-27 — resolved, commit f9b4b061c.
