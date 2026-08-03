---
track: N
prio: 45
type: bug
summary: "`def len(x)` shadows the builtin for a STRING argument but not for a list/dict — the container call still reaches pylib's len and prints its answer silently. Residue of bug-nilpy-user-def-does-not-shadow-a-pylib-builtin, which fixed 14 of 15 builtins."
---

# `def len(x)` is still ignored when the argument is a container

- **Type:** bug (NilPy name resolution — silent wrong value) — **Track N**
- **Found:** 2026-08-04, closing
  [[bug-nilpy-user-def-does-not-shadow-a-pylib-builtin]]. That ticket fixed 14
  of the 15 builtins surveyed; this is the one that did not fall out.

## Measured (self-hosted binary at HEAD)

```python
def len(x):
    return "mine-len"
print(len("ab"))      # mine-len   correct
print(len([1, 2]))    # 2          CPython: mine-len
y = [1, 2]
print(len(y))         # 2          CPython: mine-len
```

So the split is by ARGUMENT KIND, not by the name: a string argument reaches
the user's def, a container does not.

## What is already ruled out

- **Not the overload matcher.** `PyUserShadowsProc` demotes every unit overload
  at name level, and it demonstrably works for an exact-match container
  argument on a routine with the same overload shape:
  `def Counter(x)` called as `Counter([1, 2])` returns `mine-counter`, even
  though pylib declares `Counter(TPyList)`.
- **Not the `len` intrinsic in `parser.inc`.** That dispatch is now guarded by
  `PyUserShadowsProc`, and it is what fixed the string case. For a pylib
  CONTAINER class the block used to rewind and take the ordinary overload path
  anyway, so skipping it entirely should land in the same place — and does not.

So there is a THIRD route for `len` of a container that neither guard covers.
Whoever picks this up: find it before changing anything — the two obvious
places are already excluded by measurement above.

## A separate, PRE-EXISTING crash lives in the same corner

```python
def len(x):
    return "mine-len"
for y in [[1, 2]]:
    print(len(y))
print(len(5))
print(len({}))
```

segfaults — and segfaults identically on `pinned`, so it is not a regression
from the shadowing work. `len(5)` has no matching overload at all and the
matcher picks one anyway, which is the same silent-wrong-pick the `len`
intrinsic's own comment describes for an unmatched `tyClass`. Worth fixing in
the same pass, since it is the same missing check.

## Gate

A `.npy` diffed against CPython: `def len(x)` called with a string, a list, a
dict, a variant (a for-in variable) and an int; the unshadowed controls still
correct; and the crash above producing a diagnostic rather than a signal.
