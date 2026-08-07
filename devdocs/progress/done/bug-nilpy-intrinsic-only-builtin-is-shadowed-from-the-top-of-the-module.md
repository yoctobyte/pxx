---
track: N
prio: 40
type: bug
summary: "A def shadowing a builtin that has NO pylib proc (ord, chr, …) takes effect from the top of the module — `print(ord('A'))` ABOVE the def prints the user's answer where CPython prints 65. Silent."
status: done
owner: claude-AN
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

## 2026-08-07 — FIXED, and the class was wider than `ord`

### Measured the class first, rather than fixing the reported name

Swept ~50 builtin names with `print(NAME(arg))` above `def NAME(x)`, diffed
against CPython. Two distinct failures fell out, and only the first is this
ticket:

- **intrinsic-only** — `ord`, `chr`, `abs`. Exactly as reported: no proc of that
  name exists, so the user's def is the only candidate and ordinary resolution
  finds it from the top of the module.
- **pylib-backed but same arity** — `set([1,1])` above `def set(x)`. Not
  predicted by the ticket, which recorded the pylib-backed case as correct. It
  is correct for `min` only by accident: `test_nilpy_min_max_variadic`'s def
  takes FIVE parameters, so it loses on arity. `PyUserShadowsProc` answering
  "not bound yet" removes the def's *privilege* (the name-level demote) but
  leaves it in the candidate set, where a matching arity wins on argument fit.

Names that looked broken in the sweep but are not this bug: `callable`, `ascii`,
`hash`, `id`, `iter`, `format`, `dir`, `globals`, `complex`, `slice`, `object`,
`property` — pxx does not implement them at all (`undefined variable` without
the def), so there is no builtin to reach. `float`/`bool` are the OPPOSITE
defect: the user's def never wins, even below its own `def`. Both are separate
tickets' territory, not folded in here.

### The fix — one predicate, three call sites

`PyDefBoundHere(pi)` in `symtab.inc` is now the single answer to "is this NilPy
def bound at the cursor?" — `ProcPyDefTok = 0` (not a NilPy module-level def) or
`CurProc >= 0` (inside a def body the whole module has already run) or
`ProcPyDefTok <= TokPos`. Used from:

1. **`MatchElig`** — a not-yet-bound def is dropped from the candidate set, not
   merely un-privileged. That is the `set` half.
2. **`ParseFactorCore`** — `procIdx` is unbound across the name-keyed intrinsic
   chain, because every one of those guards also tests `procIdx < 0`. That is
   the `ord`/`chr`/`abs` half.
3. **`PyUserNameShadowsHere`** — `set(...)`'s own hook test, which asked the
   same question position-blind.

### Why it is NOT enforced unconditionally, which is what the fix-shape note asked for

The note proposed "a main-program proc whose ProcPyDefTok is after the call site
should not be a candidate at all", and flagged forward references between defs
as the thing to check. Two guards, not one, are needed:

- `CurProc >= 0` covers the forward reference the note worried about (a def body
  runs after the module, so everything module-level is bound there).
- **The call site must also have somewhere else to go.** Unbinding with no
  alternative turns a module-body forward call into a COMPILE error, and CPython
  accepts one that never executes:
  ```python
  if False:
      helper()
  def helper(): return 7
  ```
  NilPy is upward compatible with CPython in one direction only, so refusing a
  program CPython runs is not allowed. `MatchElig` therefore drops the late def
  only when a non-main-program routine of that name exists, and
  `ParseFactorCore` REBINDS `procIdx` once the intrinsic chain has declined the
  name. Both cases are in the test.

### Still wrong, and not fixable by a token-position rule

```python
def uses_ord():
    return ord("B")
print(uses_ord())     # CPython 66      pxx: the user's def
def ord(x):
    return "late"
```
Which `ord` the BODY sees depends on when the body is CALLED, not on where it
stands — CPython answers 66 here and `"late"` for the same body called one line
lower. A compile-time token comparison cannot express that. Pre-existing,
identical on `pinned`, recorded in the test as a NOT-covered note.

The [[bug-nilpy-redefining-a-def-is-ignored-the-first-body-still-runs]] case the
ticket called "probably the same fix" is *not* — it needs two Procs for one
name, which is a registration change, not a visibility one.

### Test

`test/test_nilpy_def_shadows_builtin_positionally.npy`, output byte-identical to
CPython's: the three intrinsic-only names, `set`, the `min` case that must not
regress, a forward reference between two defs, and the never-executed
module-body forward call. Wired into both `test-nilpy` recipes.

## Log
- 2026-08-07 — resolved, commit PENDING-COMMIT.
