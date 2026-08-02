---
track: N
prio: 30
type: bug
summary: "The `else` clause on a for/while loop does not parse — `for ... else:` fails with 'expected expression' at the else"
---

# `for ... else:` / `while ... else:` do not parse

- **Type:** bug / missing language feature (NilPy) — **Track N**
- **Found:** 2026-08-02, sweeping control-flow constructs vs CPython (the sweep
  that produced [[bug-nilpy-assert-statement-not-supported]], now fixed).
- **Loud**: `error: expected expression` at the `else`.

```python
for i in [1, 2]:
    pass
else:
    print("for-else")        # CPython prints it

n = 0
while n < 2:
    n += 1
else:
    print("while-else")      # CPython prints it
```

Both fail. `global` and `nonlocal`, swept at the same time, work correctly.

## Semantics, since they are the part people get wrong

The `else` runs when the loop finished **without executing a `break`** — it is
not "if the loop body never ran". So:

```python
for i in [1, 2, 3]:
    if i == 2:
        break
else:
    print("not reached")     # break happened, else SKIPPED

for i in []:
    pass
else:
    print("reached")         # empty loop still runs else
```

Getting this backwards would be a silent wrong answer, which is the argument for
implementing it deliberately rather than approximating it as "run after the
loop".

## Why prio 30

It fails loudly, and loop-else is genuinely rare and widely considered
confusing — plenty of Python style guides discourage it. Filed because it is
cheap next to the machinery already present, and because a corpus file that uses
it currently cannot compile at all.

## Shape of the fix

The desugar is a flag: a hidden boolean set before the loop, cleared by any
`break` in that loop's own body, tested after it.

```
__py_broke := False
<loop>                       # each `break` in THIS loop sets __py_broke := True
if not __py_broke then <else body>
```

The care points:

- a `break` in a NESTED loop must not clear the outer loop's flag, so the flag
  has to be bound to the loop the break belongs to
- `PyParseFor` already desugars to an AN_SEQ containing an AN_WHILE, and sets
  `PyStmtAteBlock`; the else body is a second suite after that sequence, so the
  block-consumed bookkeeping needs to cover both suites
- a `return` out of the loop skips the else, which falls out of the flag
  approach for free

## Gate

A `.npy` diffed against CPython: for-else and while-else with and without a
break, an empty iterable (else still runs), a break in a nested inner loop (the
outer else still runs), and a `return` from inside the loop.
