---
track: N
prio: 40
type: bug
summary: "Three statement-level forms don't parse: chained assignment `a = b = 5`, `**=`, and semicolon-separated statements on one line — all loud"
---

# `a = b = 5`, `x **= 2`, and `a; b` on one line do not parse

- **Type:** bug / missing statement forms (NilPy) — **Track N**
- **Found:** 2026-08-02, sweeping assignment forms vs CPython (the sweep that
  found [[bug-nilpy-module-level-true-divide-assign-keeps-an-int-slot]]).
- All three **loud**; grouped because they are small and share a discovery.

## 1. Chained assignment

```python
a = b = 5          # error: undefined variable (b)
```

Python binds RIGHT to left, one evaluation of the RHS shared by every target:
`a = b = f()` calls `f` once. That single-evaluation rule is the part worth
getting right — desugaring to `b = f(); a = f()` would call it twice, and
desugaring to `b = f(); a = b` is correct only because `b` is a plain name (it
is NOT correct for `d[k] = d2[k2] = f()`, where the targets have side effects of
their own).

The diagnostic is also misleading: it names `b` as undefined rather than the
unsupported form.

## 2. `**=`

```python
p = 2
p **= 3            # error: expected expression
```

`PyAugBinTok` maps `tkPlusEq`/`tkMinusEq`/`tkStarEq`/`tkSlashEq`/`tkTrueDivEq`/
`tkModEq`/`tkAmpEq`/`tkPipeEq`/`tkXorEq`/`tkShlEq`/`tkShrEq` — there is no
`tkPowEq` entry, and possibly no such token. `**` itself works, so this is the
augmented spelling only.

Note the typing subtlety if it is added: `2 ** -1` is a FLOAT in Python, so
`p **= -1` must widen the target the way `/=` does — exactly the bug just fixed
one scope over. Do not copy the generic "preserve the target type" arm.

## 3. Semicolon-separated statements

```python
i += 1; i -= 1     # error: expected expression
```

Python allows several simple statements on one line separated by `;`. The lexer
already has `tkSemicolon` (the module-level collector's statement-boundary test
lists it), so this is a statement-loop gap rather than a lexical one.

## Priority note

All three fail at compile time, so nothing is silently wrong — which is why this
is 40 rather than higher. Chained assignment is by far the most common of the
three in real code; `**=` and `;` are rare.

## Gate

A `.npy` diffed against CPython per form: chained assignment to two and three
names including a shared call RHS evaluated ONCE, `**=` on int and on a negative
exponent (float result), and two/three simple statements on one line.
