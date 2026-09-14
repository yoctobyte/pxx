---
slug: bug-n-a-lambda-returning-a-user-class-instance-yields-none
title: a lambda returning a user-class instance yields None
summary: >
  `f = lambda: v` where `v` is an instance of a user-defined class returns
  `None`. A lambda returning a float, a str or a list is correct; a nested `def`
  returning the same instance is correct. It is silent -- the caller gets a
  plausible `None` and carries on. Found while writing a fixture for another
  bug, where it made a passing row read as failing, which is the practical cost:
  a lambda is what a test harness is written with.
track: N
type: bug
prio: 62
owner: unassigned
status: open
---

## How it was reached

Sideways, and it nearly cost a correct diagnosis. Writing the table for
`bug-n-arithmetic-on-a-user-class-fails-when-the-other-operand-is-object-typed`
I wrapped each row in a lambda so one failing row would not abort the rest:

```python
def row(tag, fn):
    try:
        print(tag, "->", fn())
    except TypeError as bad:
        print(tag, "-> TypeError:", bad)

row("v.scale(par.k)", lambda: v.scale(par.k))
```

Three rows came back `None`. Re-running the same three as direct `print`
statements gave the correct `V3`, so the `None` was the lambda and not the
expression. The rows were right and the harness was wrong.

## Repro

One file, no imports. Every row should print a value; three print `None`.

```python
class V3:
    def __init__(self, x=0.0):
        self.x = x

    def __repr__(self):
        return "V3(%.2f)" % self.x


def call(fn):
    return fn()


def d_obj():
    return v


v = V3(7.0)
f_obj = lambda: v
f_new = lambda: V3(9.0)
f_num = lambda: 22.0
f_str = lambda: "hello"
f_lst = lambda: [1, 2]

print("L1 lambda -> obj, called direct  ->", f_obj())
print("L2 lambda -> obj, through param  ->", call(f_obj))
print("L3 lambda -> new obj, thru param ->", call(f_new))
print("L4 lambda -> float, thru param   ->", call(f_num))
print("L5 lambda -> str, thru param     ->", call(f_str))
print("L6 lambda -> list, thru param    ->", call(f_lst))
print("L7 def    -> obj, thru param     ->", call(d_obj))
print("L8 inline lambda, thru param     ->", call(lambda: v))
```

| row | CPython | pxx @ 744d673cf |
| --- | --- | --- |
| L1 lambda -> instance, called directly | `V3(7.00)` | **None** |
| L2 lambda -> instance, called through a parameter | `V3(7.00)` | **None** |
| L3 lambda -> a NEW instance, through a parameter | `V3(9.00)` | **None** |
| L4 lambda -> float | `22.0` | `22.0` |
| L5 lambda -> str | `hello` | `hello` |
| L6 lambda -> list | `[1, 2]` | `[1, 2]` |
| L7 nested `def` -> instance | `V3(7.00)` | `V3(7.00)` |
| L8 inline lambda -> instance | `V3(7.00)` | **None** |

Measured at 744d673cf, compiler binary 2026-09-14 03:42, x86-64 `--threadsafe`.

Three readings:

1. **It is the return type, not the call.** L4/L5/L6 travel the identical call
   path with a float, a str and a list and are all correct. Only a user-class
   instance is lost.
2. **It is the lambda, not the closure.** L7 is a nested `def` with the same
   capture and the same return, through the same parameter, and is correct.
   That also separates this cleanly from
   `bug-n-a-returned-nested-def-reads-zero-for-its-captures-past-arity-three`,
   which is the other lowering and the opposite direction.
3. **Direct call fails too.** L1 never passes the lambda anywhere. So this is
   the lambda's own return marshalling, not the argument-passing ladder.

## Where to look

The lambda body is a single expression, so the lowering presumably builds a
return of that expression's value and has an arm per result kind. A user-class
instance is the arm that drops it -- most likely returning the slot rather than
the reference, or declaring the result `None`/void because the expression's
static type is a class reference rather than a value kind it recognises. The
`def` path (L7) is the one that gets it right and is the obvious thing to
compare against.

## The loudness point, again

This is the third silent-wrong-value on track N this week
(`bug-n-a-returned-nested-def-reads-zero-for-its-captures-past-arity-three` and
`bug-n-adjacent-string-literals-splice-a-plus-so-a-tighter-operator-binds-wrong`
are the others). `None` from a lambda is worse than either, because `None` is
what a Python programmer reads as "the thing was not there" rather than "the
compiler dropped it". If the lowering knows it has no arm for this result kind,
refusing at compile time with a line number would turn this into a build failure
instead of a wrong picture.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` carrying the eight
rows above, expectations from CPython. L4-L7 belong in the same file as the
failing rows: they are what stops a fix from being credited to the call ladder
rather than the lambda.

## Log
- 2026-09-14 -- filed from a fixture harness, not from the demo. Reduction is
  single-file and inline above.

## Provenance

Measured and written by the peer session **lekkerzeilen-c8**, which cannot
commit in this checkout; this file is left untracked for that seat to pick up.
Worth recording how it surfaced: it first appeared as three WRONG rows in
another bug's table, and was only separated out because the rows disagreed with
a direct re-run. A harness written in lambdas is not a safe harness on this
compiler until this is fixed, which is a fact about every fixture either of us
writes from here on.
