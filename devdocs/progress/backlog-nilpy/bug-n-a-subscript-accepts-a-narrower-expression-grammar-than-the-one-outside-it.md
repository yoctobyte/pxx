---
slug: bug-n-a-subscript-accepts-a-narrower-expression-grammar-than-the-one-outside-it
track: N
type: bug
prio: 70
status: backlog
owner: ""
created: 2026-09-19
found-by: frankuser
tags: [nilpy, parser, tsp, demo]
blocked-by: []
summary: "Inside `[...]` the NilPy parser accepts a NARROWER expression grammar than the one it uses everywhere else: `d[unit or \"s\"]` is `expected ']' before 'or'` and `d[\"a\" if f else \"b\"]` is `expected ']' before 'if'`, while the IDENTICAL expression one line earlier (`k = unit or \"s\"`) compiles and runs. Two expression parsers, one of them wired into the subscript. Measured on That Space Program 2026-09-19: this is the FIRST wall in 15 of 59 modules, the single largest — but READ THE CAVEAT: a count of modules blocked is NOT a count of work, and in this repo clearing the largest wall has moved units-compiling by ZERO four times."
---

# `or` and a conditional expression are refused inside a subscript and accepted outside it

Found by a per-module sweep of **That Space Program** (`~/tuxspaceprogram`,
official name *That Space Program*, not the folder name), 2026-09-19, compiler
`28067ea1d2f3`.

## Minimal, with the control beside it

```python
d = {"s": 1, "m": 60}
unit = ""
k = unit or "s"      # OK, compiles and prints s
print(d[unit or "s"])  # pascal26:3: error: expected ']' before 'or'
print(d["a" if f else "b"])  # pascal26:3: error: expected ']' before 'if'
```

**The control is the point:** the same `or` expression bound to a name one line
earlier compiles and runs. So this is not "we do not support `or`" — it is the
subscript using a different, narrower expression parser.

## Real site

`tsp/timebase.py:195` — `total += float(num) * _DURATION_UNITS[unit or "s"]`.
The `x or default` subscript is ordinary Python and appears throughout the
corpus.

## What this is NOT evidence for

**Fifteen modules hit this FIRST. That is not fifteen modules' worth of work
unblocked.** The census is first-failure, so every wall behind this one is
invisible, and this repo has four dated cases where clearing the largest wall
moved the compiling count by zero. **Record what you expect BEFORE re-running
the sweep**, or the result is uninterpretable either way.

## Likely shape, not verified

The grep to run first is for the OTHER spelling's handler: find where a
subscript parses its index and compare it against the general expression entry
point, rather than grepping for `or`. Same shape as the `$cfnptr`/`$cfntype`
and `ParseConstSection`/`ParseVarSection` pairs — two doors, one wired.
