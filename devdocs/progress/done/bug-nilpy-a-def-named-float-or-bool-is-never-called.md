---
track: N
prio: 40
type: bug
status: done
commit: 422334d1c
summary: "NilPy: `def float(x)` / `def bool(x)` were never called — their NilPy arms in ParseFactorCore claimed the name unconditionally, with none of the `not PyUserShadowsProc(name)` guard `int` and `str` beside them carry. Silent, on both sides of the def."
---

# A def named `float` or `bool` is never called

- **Type:** bug (NilPy — silent wrong value) — **Track N**
- **Found:** 2026-08-07, in the builtin-shadowing sweep run for
  [[bug-nilpy-intrinsic-only-builtin-is-shadowed-from-the-top-of-the-module]].
  Pre-existing (identical on `pinned`). Fixed the same day.
- **Family:** the third residue of
  [[bug-nilpy-user-def-does-not-shadow-a-pylib-builtin]], whose sweep probed
  fifteen names and did not include these two — see the 2026-08-07 addendum
  there. Siblings:
  [[bug-nilpy-user-def-len-of-a-container-still-binds-the-builtin]] and
  [[bug-nilpy-user-def-loses-to-pylibs-variant-overload-at-the-same-arity]].

## Measured

```python
print(float("1.5"))
def float(x):
    return "late"
print(float("1.5"))
# CPython 1.5, late
# pxx     1.5, 1.5
```

Same for `bool`. Note this is the MIRROR of the ticket it was found under: there
the def won from too early, here it never wins at all — including below its own
`def` statement, where Python unambiguously means the user's.

## Cause

`ParseFactorCore`'s NilPy conversion arms are a chain of
`else if isNilPy and (name = '<builtin>')`. `int` and `str` each carry
`and (not PyUserShadowsProc(name))`; `float` and `bool` were written without it,
so they claimed the name before resolution ever ran. `list` / `dict` / `tuple` /
`set` reach their lowering by other routes that already ask the question, which
is why the sweep found only these two.

## Fix

Added the same guard to both arms. With no user def of the name
`PyUserShadowsProc` is False and nothing changes; with one, the name falls
through to the ordinary call path exactly as `int` and `str` already do.

## Test

Folded into `test/test_nilpy_def_shadows_builtin_positionally.npy` (both names,
above and below the def), which is byte-identical to CPython's output and wired
into both `test-nilpy` recipes.
