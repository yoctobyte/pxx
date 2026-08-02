---
track: N
prio: 55
type: bug
summary: "`def f(x): return x + 1` on ONE line fails with 'unexpected token'. The compound-statement header requires a newline + INDENT suite; the inline form Python allows on the same line is not accepted for def (or class)"
---

# A one-line `def` suite does not parse

- **Type:** bug / missing syntax (NilPy) — **Track N**
- **Found:** 2026-08-02 by a differential sweep against the CPython oracle.
- **Loud**: `error: unexpected token`.

## Measured

```python
def f(x): return x + 1
print(f(1))
```

```
pascal26:1: error: unexpected token
  near:  f  x   >>>  x
```

Same for a method:

```python
class A:
    def who(self): return "A"
```

```
pascal26:2: error: unexpected token
  near:  who  self   >>>  A
```

The multi-line spelling of both compiles and runs correctly, so this is purely
the inline suite.

## What DOES work — the gap is narrower than "no inline suites"

Inline suites are accepted for the simple compound statements:

```python
for i in range(3):
    if i == 5: break        # ok
while n < 3: n += 1         # ok
```

Both appear in probes that compile today. So the suite parser handles
`<header>: <simple_stmt>` in the loop/conditional path; it is `def` (and, by the
class example, the class-body member path) that requires a newline and an
INDENT block.

## Why it matters

`def f(x): return x` is one of the most common shapes in small Python — helper
predicates, key functions, stubs, and nearly every `class Foo: pass` or
`def method(self): ...` placeholder. A corpus file that uses it cannot compile
at all, so this blocks third-party source rather than degrading it.

It is also the shape a reader is most likely to write when reducing a program
for a bug report, which makes it a repeated tax on this project's own sweeps —
it is why the two-user-class probe for
[[bug-nilpy-and-or-of-two-different-classes-reinterprets-one-as-the-other]] had
to be rewritten multi-line before it could measure anything.

## Shape of the fix

Python's grammar is `funcdef: 'def' NAME parameters ':' suite`, and `suite` is
either `NEWLINE INDENT stmt+ DEDENT` **or** `simple_stmt` (one or more
semicolon-separated simple statements on the same line). Wherever `PyParseDef`
consumes the `:` and then demands a newline, it needs the same two-way branch
the loop/if path already has — so the fix is most likely to be *reusing* that
existing suite helper rather than writing a new one. Check whether that helper
exists as a callable routine or is inlined into the `if`/`while` paths; if
inlined, factoring it out is the change.

`class A: pass` should be covered at the same time — same grammar rule, and the
class-body member path failed in the measurement above.

Note the interaction with `PyStmtAteBlock` bookkeeping, which the for/while
desugar already depends on: an inline suite consumes no INDENT/DEDENT, so
whatever records "a block was consumed" has to agree for both spellings.

## Related

[[bug-nilpy-chained-assign-power-assign-and-semicolon-statements]] covers
semicolon-separated statements, which is the *other* half of Python's
`simple_stmt` suite (`def f(): a = 1; return a`). The two should probably be
gated together even if fixed separately.

## Gate

A `.npy` diffed against CPython covering: a one-line `def` returning an
expression; a one-line `def` whose body is a call with a side effect; a one-line
method in a class; `class A: pass`; a one-line `def` immediately followed by
another top-level statement at column 0 (the DEDENT bookkeeping); a one-line
`def` nested inside a multi-line `def`; and the multi-line spellings of each as
regression controls.
