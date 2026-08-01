---
track: N
prio: 60
type: bug
---

# One-line `def` and `class` bodies do not parse

- **Type:** bug (NilPy frontend gap — hard compile error) — **Track N**
- **Found:** 2026-08-01, while verifying
  [[bug-nilpy-bitwise-shift-on-class-operand-segfaults]] — whose repro is
  written this way and therefore could not be run as published.

## Repro

```python
def f(): return 5
print(f())
```

```
pascal26:1: error: unexpected token
  near:  f    >>>
```

Same for a class:

```python
class C: pass
```

## What makes it narrow: every OTHER compound statement supports it

Measured, same binary:

| form | result |
| --- | --- |
| `if True: print("x")` | **OK** |
| `for i in [1,2]: print(i)` | **OK** |
| `while x < 2: x += 1` | **OK** |
| `with open(p) as fh: pass` | **OK** |
| `if True: return 7` *inside* a def | **OK** |
| **`def f(): return 5`** | **FAIL** |
| **`class C: pass`** | **FAIL** |

So the suite parser already handles "`:` then a statement on the same line" —
`def` and `class` are the two that don't use it.

## Likely cause

`PyParseDefHeader` is documented as "leaving the cursor just past the `:`
NEWLINE INDENT that opens the body" — i.e. it hard-requires the indented form.
`PyRegisterDefShells` and `PyRegisterClassMembers` also scan for a body `tkIndent`
to find the span, so a one-line body has no INDENT for them to find either.

**Measure before fixing**: three passes look for that INDENT (the header parse,
the def-shell registration, and the class-member registration), so a fix that
only teaches the header about the one-line form will leave the other two
scanning for a body that isn't there. Check all three.

## Why it matters

`def f(): return x` and `class C: pass` are ordinary Python — `class X: pass` in
particular is the idiomatic empty placeholder and appears constantly in stubs,
exception hierarchies and protocol classes. It is a hard compile error rather
than a miscompile, which is the good case, but it blocks whole files.

## Gate

A `.npy` diffed against CPython covering: one-line `def` with a return, one-line
`def` with a bare call, `class C: pass`, a one-line method inside a normal class
body, an empty exception subclass (`class E(Exception): pass`), and the indented
forms of each still working.
