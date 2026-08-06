---
track: N
prio: 80
type: bug
status: done
owner: claude-AN
summary: "NilPy: a hoisting sub-expression (a string method call) in a `while` condition was flushed OUTSIDE the loop and evaluated ONCE, so the condition went stale — `while s.startswith('a')` spun and `while j < len(s) and s[j].isdigit()` never stopped. Silent."
---

# A method call in a `while` condition is evaluated once, before the loop

- **Type:** bug (silent wrong value / non-termination) — **Track N**
- **Found:** 2026-08-06, bughunting. Surfaced by a hand-written **tokenizer**
  that returned its entire input as a single token. Pre-existing (identical on
  `pinned`).
- **Severity:** high. This is the ordinary scanner idiom, and nothing raises.

## Measured (before, self-hosted at `7c503da50`)

```python
def strip_as(s):
    n = 0
    while s.startswith("a"):
        s = s[1:]
        n += 1
        if n > 9: break
    return n
print(strip_as("aaab"))     # CPython 3     pxx 10 (only the break stopped it)

def scan(s, i):
    j = i
    while j < len(s) and s[j].isdigit():
        j += 1
    return j
print(scan("12 34", 0))     # CPython 2     pxx 5 (ran past the space)
```

What bounded it: an ordinary comparison as the right operand
(`while j < len(s) and s[j] != " "`) was **correct**; the same `and` expression
in an ASSIGNMENT (`b = j < len(s) and s[j].isdigit()`) was **correct**; a free
function as the right operand (`isd(s[j])`) was **correct**. Only a hoisting
sub-expression — a string METHOD call — inside a `while` condition was wrong,
and `and` was a red herring: a sole `while s.startswith("a")` fails on its own.

## Cause

`PyParseWhile` stashed the condition's hoisted setup and left it for the
ENCLOSING statement's flush, i.e. emitted it BEFORE the loop. Its own comment
records the reasoning and the assumption that made it wrong:

> *"NOTE a literal in a while CONDITION is built once, before the loop — CPython
> rebuilds it per test; acceptable divergence, the pattern is
> `while x in ("a","b")` membership against constants."*

True for a constant literal, which is loop-invariant. A string method call
hoists through the same mechanism and is **not** invariant, so the condition was
computed once and every later test read the stale result.

## Fix — and the wrong fix it went through first, which is the point

Folding the setup into the whole CONDITION (a comma chain in front of it) makes
the value fresh, and **breaks short-circuit**: the right operand of `and` then
runs unconditionally, so `while j < len(s) and s[j].isdigit()` evaluated `s[j]`
at `j == len(s)` and raised IndexError. Measured, not reasoned — the corpus
caught it immediately.

The correct place is the **operand**, not the condition. `PyFoldHoistSince` folds
the setup a sub-expression added into THAT sub-expression, and `PyParseBoolAnd`
/ `PyParseBoolExpr` call it for each right operand. Both properties then hold:
the value is recomputed per test, and only on the path that actually reaches it.
`PyParseWhile` keeps the same fold for the condition's own top-level setup,
which covers a sole method call with no `and`/`or` around it.

`and`/`or` were verified to short-circuit correctly first — that is what makes
attaching setup to an operand safe.

## Verified

`test/test_nilpy_while_condition_hoist.npy` (new, wired into `make test-nilpy`):
sole method-call condition, method as the right operand of `and` and of `or`,
method FIRST with a comparison second, the short-circuit guard at
`j == len(s)` (must not evaluate `s[j]`), a condition-mutating loop body, both
container-literal conditions, explicit short-circuit side-effect counting, the
plain/else/break/nested `while` shapes, and the tokenizer that found it. All
lines match CPython. `tools/gate.sh quick` GREEN; the probe corpus shows no
regressions.

## Follow-up: a constant container in the condition is rebuilt per test

Noted by the user while this was being fixed: for a genuinely CONSTANT list or
dict, hoisting it to a variable once is what a person would write by hand, and
it avoids the per-iteration build. That is now the only case paying for the fix
(`while x in ("a","b")` rebuilds the tuple each test). It is correct — CPython
rebuilds it too — but needlessly so.

Not done here, because the predicate ("is this hoisted chain provably constant?")
has to be conservative in the safe direction or it silently reinstates this exact
bug. Filed with the design as
[[feature-nilpy-hoist-constant-container-literals-out-of-a-loop-condition]].

## Log

- 2026-08-06 — found behind
  [[bug-nilpy-a-nested-defs-own-local-is-recorded-as-a-capture]] (the same
  parser program hit both), root-caused, mis-fixed once at the wrong level,
  re-fixed at the operand level, verified.
