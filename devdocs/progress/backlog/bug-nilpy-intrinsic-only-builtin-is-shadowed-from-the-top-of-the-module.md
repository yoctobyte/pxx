---
track: N
prio: 40
type: bug
summary: "A def shadowing a builtin that has NO pylib proc (ord, chr, …) takes effect from the top of the module — `print(ord('A'))` ABOVE the def prints the user's answer where CPython prints 65. Silent."
---

# A builtin with no pylib proc is shadowed from the top of the module

- **Type:** bug (NilPy — silent wrong value) — **Track N**
- **Found:** 2026-08-04, measuring the residual edges of
  [[bug-nilpy-user-def-does-not-shadow-a-pylib-builtin]] after it closed.

## Measured

```python
print(ord("A"))        # CPython 65     pxx: "late"
def ord(x):
    return "late"
```

Python rebinds a name when the `def` STATEMENT runs, so a call ABOVE it still
reaches the builtin — and that rule works correctly for every builtin that pylib
declares as a real routine, pinned by `test_nilpy_min_max_variadic`:

```python
print(min(3, 1, 2))                     # 1, the builtin — correct
def min(a, b, c, d, e): return 100
print(min(1, 2, 3, 4, 5))               # 100, the user's — correct
```

## Why `ord` differs

`PyUserShadowsProc` gates on `ProcPyDefTok` — the def's token index — so a call
before the def does not see it. That gate only matters when there is something
ELSE to resolve to. `ord` has no pylib proc of that name (it is lowered as a
name-keyed intrinsic), so once the user's def is registered it is the ONLY proc
called `ord`, and ordinary resolution finds it from anywhere in the module.

The positional rule is therefore enforced by *competition*, not by the gate, and
it silently lapses for exactly the builtins that have no competitor.

## Shape of a fix

The intrinsic guards already call `PyUserShadowsProc`, which already answers the
positional question correctly. What is missing is that when it answers False,
the intrinsic runs — but the ordinary path afterwards still finds the user's
proc by name. So the position has to be enforced at RESOLUTION, not only at the
guard: a main-program proc whose `ProcPyDefTok` is after the call site should not
be a candidate at all under `NilPyUserCode`.

Check first whether that breaks forward references between user defs — `def a()`
calling `def b()` declared later is ordinary Python and must keep working, so
the restriction can only apply where the name ALSO resolves to something else
(a unit proc or an intrinsic). That distinction is the whole design question.

## Related, and probably the same fix

A plain redefinition has the same shape — compile-time single binding versus
Python's runtime rebinding:

```python
def f(): return 1
print(f())      # CPython 1    pxx: 2
def f(): return 2
print(f())      # 2 on both
```

See [[bug-nilpy-redefining-a-def-is-ignored-the-first-body-still-runs]].

## Gate

A `.npy` diffed against CPython: a call above and below a def shadowing an
intrinsic-only builtin (`ord`, `chr`); the same for a pylib-backed one (`min`),
which must not regress; a forward reference between two user defs, which must
keep working; and the redefinition case above.
