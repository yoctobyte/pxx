---
track: N
prio: 40
type: bug
summary: "Three statement-level forms don't parse: chained assignment `a = b = 5`, `**=`, and semicolon-separated statements on one line — all loud"
status: done
owner: claude-AN
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


## Resolved 2026-08-04 — two of three; the third had already fixed itself

Re-measured all three first. **Item 3, semicolon-separated statements, already
works** (`i += 1; i -= 2` runs) — fixed by other work since 2026-08-02, and now
pinned by the test so it stays fixed.

### 1. Chained assignment

`a = b = RHS` desugars through a hidden temp: the RHS is evaluated ONCE into it,
then stored to each target left to right (CPython's order). The single-evaluation
rule the ticket flagged as the part worth getting right is pinned by a row —
`p = q = f()` where `f` appends to a list, and the list has length 1 afterwards.

**Plain NAME targets only.** `d[k] = d2[k2] = f()` is refused by name rather
than half-lowered: the temp would be right for it too, but the STORE path for a
subscript target is a different lowering, and quietly getting it half-right is
the failure mode this frontend keeps trying to avoid. The misleading
"undefined variable (b)" is gone either way.

### 2. `**=`

`**` is not a binop TOKEN — it lowers through `pypow_v` and the
`__pow__`/`__rpow__` dunders — so this needed three things:

- **`tkPowEq`**, APPENDED at the tail of the token enum (never inserted; the
  ordinals are frozen by the self-host discipline) and lexed before the plain
  `*=` so the longer spelling wins;
- **`PyMakePow`**, the `**` lowering factored out of `ParseFactor` so both
  spellings produce the IDENTICAL node. A second hand-built `pypow_v` call
  would have compiled fine and silently dropped the dunder dispatch — this
  repo's recurring failure mode, two readers of one construct that disagree;
- **the widening the ticket warned about.** `2 ** 3` is an int and `2 ** -1` is
  a float, so the target must not keep its type. Inside a def the trial parse
  notes that from the lowered node; at MODULE scope it needed a token-shape arm
  beside the one `/=` already had — measured, not assumed: `q **= -1` printed
  `0` at module scope while the identical code in a def printed `0.5`.

The ticket's advice — "do not copy the generic preserve-the-target-type arm" —
is exactly what the module-scope measurement caught.

### Verified

`test/test_nilpy_chained_assign_powassign.npy`, wired into `make test-nilpy`:
two- and three-target chains, the single-evaluation check, a chain inside a def,
shared-object aliasing, a chain whose RHS reads its own target, `**=` at module
and def scope with int/negative/float exponents, and the semicolon form. Diffed
against CPython, identical. `tools/gate.sh quick` GREEN, self-host
byte-identical; Pascal is untouched (the new token is lexed only by pylexer).

## Log
- 2026-08-04 — resolved.
- 2026-08-04 — resolved, commit cd948253b.
