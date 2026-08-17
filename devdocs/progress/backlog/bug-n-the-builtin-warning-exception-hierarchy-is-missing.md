---
track: N
prio: 40
type: bug
blocked-by: []
summary: "`Warning`, `UserWarning` and `DeprecationWarning` do not exist in NilPy, so `class DataLossWarning(UserWarning)` will not compile. They are BUILTINS, named bare by calling code, so no mimic_warnings shim can supply them — this blocks the warnings shim and 16 non-test html5lib call sites."
---

# The builtin `Warning` exception hierarchy is missing

- **Type:** bug (missing builtin) — **Track N**. Likely `compiler/builtin/**`,
  which means it **needs a pin** and is coordinator-scheduled.
- **Found:** 2026-08-17 by frank3 (Track B), measuring the premises of
  [[feature-nilpy-six-and-warnings-shims]] before writing that shim.
- **Measured against:** `pinned` **v344**. Not re-checked at HEAD — Track B
  cannot rebuild the compiler. Re-measure before working it.

## Repro

```python
print(Warning, UserWarning, DeprecationWarning)
```

```
pxx:     pascal26: error, near: print  Warning >>>  UserWarning
CPython: <class 'Warning'> <class 'UserWarning'> <class 'DeprecationWarning'>
```

## Why a shim cannot paper over it

These are **builtins**, not members of `warnings` — calling code names them
bare, and subclasses them:

```python
# html5lib/constants.py:2940
class DataLossWarning(UserWarning):
    pass
```

So `mimic_warnings` cannot supply them however it is written, and a
`mimic_warnings` shipped without them would resolve `import warnings` and then
fail one line later at the first category argument. That is worse than the
honest missing module and violates the T1 rule in
`devdocs/dev/python-compat-tiers.md` (a shim states its subset and fails loudly
rather than approximating).

## Blast radius, measured not estimated

Every `warnings.warn` call in non-test html5lib code passes a category:

| category | sites |
| --- | --- |
| `DataLossWarning` | 14 |
| `DeprecationWarning` | 2 |

The 14 are indirect — they need `UserWarning` only so that `DataLossWarning` can
be *declared* — so all 16 sit behind this one gap.

## Note on scope

The full CPython warning tree is large (`SyntaxWarning`, `RuntimeWarning`,
`BytesWarning`, …). What is measured as load-bearing here is three names:
`Warning`, `UserWarning`, `DeprecationWarning`. Whether to add the three or the
whole tree is a judgement for whoever owns the builtin exception table — the
rest are cheap once the base exists, and a partial tree that silently misses a
name is the failure mode worth avoiding.

## Gate

`class D(UserWarning): pass` compiles, `warnings.warn(msg, D)` accepts it, and
the three names print as classes like CPython.
