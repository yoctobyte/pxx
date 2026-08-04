---
track: N
prio: 30
type: bug
summary: "A NilPy `def min(x, y, z)` compiles but is silently NOT called — pylib's all-Variant 3-arg min outranks it, so the program gets the builtin's answer"
status: done
owner: claude-AN
---

# A user `def` loses to a pylib overload of the same arity — silently

- **Type:** bug (NilPy name resolution / overload ranking) — **Track N**
- **Found:** 2026-08-03, while gating
  [[feature-nilpy-min-max-variadic-more-than-two-args]]. Not caused by it:
  that fold cannot fire at arity 3 (pylib declares a 3-argument min, and the
  fold is guarded on no routine of that arity existing), so this call takes
  the ordinary overload path start to finish.

## Measured

```python
def min(x: int, y: int, z: int) -> int:
    return 100


print(min(1, 2, 3))     # CPython: 100     pxx: 1
```

It compiles clean and prints `1` — pylib's `min(const a, b, c: Variant)` was
chosen over the routine the programmer wrote three lines up. In Python a
module-level `def` shadows a builtin outright; here it is merely one more
overload candidate, and it loses.

Shadowing DOES work where pylib has no same-arity candidate:

| shape | pylib candidate at that arity | result |
| --- | --- | --- |
| `def min(x, y)` + `min(1, 2)` | yes (`Int64,Int64` / `Variant,Variant`) | **100 — correct** |
| `def min(x, y, z)` + `min(1, 2, 3)` | yes (all-Variant) | **1 — WRONG** |
| `def min(a..e)` + `min(1, 2, 3, 4, 5)` | none | **100 — correct** |

So the 2-argument case ranks the user's `Integer, Integer` above the Variant
pair and wins, while the 3-argument case has only a Variant candidate on the
pylib side and the user's exact-typed one still loses. That asymmetry is the
thing to explain before fixing — the ranking that gets it right at 2 args
should get it right at 3.

## Why it matters more than the arity it was found at

The wrong answer is SILENT and the shadowed name is a builtin, so the program
reads as if it calls the function on screen. `min`/`max` are the instance
found; nothing here is specific to them — any NilPy `def` whose name collides
with a pylib routine at the same arity is a candidate for the same shape.
Worth checking `sum`, `len`, `abs`, `sorted`, `round` in the same pass.

## Shape of a fix

A NilPy user `def` at module scope should not merely rank against the pylib
builtins, it should SHADOW them — the same "no user shadow" test the
`enumerate`/`zip`/`min`/`max` parser branches already apply via
`FindSym`/`PyAnyProcWithArity` before claiming a call, but applied in the
overload resolver rather than per-branch. Care needed: pylib routines are
ordinary Pascal procs in the same table, so "declared by the NilPy program"
has to be a real predicate (declaring unit / `NilPyUserCode` at declaration
time), not a name list.

## Gate

A `.npy` shadowing `min`, `max` and at least two other pylib builtins at 1, 2,
3 and 5 arguments, each diffed against CPython, plus the existing pylib call
sites still resolving to pylib when NOT shadowed.


## Resolved 2026-08-04 — fixed by the name-level shadowing work

Re-measured at HEAD:

```python
def min(x: int, y: int, z: int) -> int:
    return 100
print(min(1, 2, 3))     # 100 — the user's, matching CPython
```

This ticket's diagnosis was exactly right — "in Python a module-level `def`
shadows a builtin outright; here it is merely one more overload candidate, and
it loses" — and that is the rule
[[bug-nilpy-user-def-does-not-shadow-a-pylib-builtin]] installed in `37ce259f9`:
`PyUserShadowsProc` + `MatchElig`'s `userOnly` demote drop **all** of a unit's
overloads, at name level, as soon as the main program declares the name. Ranking
never gets a chance to prefer pylib's all-Variant 3-argument form.

Two follow-ons were needed before it worked for every builtin, and this ticket
benefits from both: `8a660bce7` (a def whose name exists only in a unit was
never REGISTERED, so the predicate answered False) and `a6754ddf7` (the shadow
applies only from the def's own statement onward, as Python rebinds).

`max` at arity 3 behaves the same. Unshadowed `min`/`max` at every arity are
unchanged.

Worth recording: with the shadow in place, `def min(x, y, z)` followed by
`min(4, 2)` is now a COMPILE ERROR rather than silently reaching pylib's
2-argument overload. That is the right answer — CPython raises
`TypeError: min() missing 1 required positional argument` for the same program —
and it is loud rather than silent, which is the direction this frontend wants.

Covered by `test/test_nilpy_user_def_shadows_builtin.npy` (which shadows `min`
and `max` among fifteen builtins) and by `test_nilpy_min_max_variadic`, which
pins the positional half.

## Log
- 2026-08-04 — resolved (fixed by 37ce259f9 + 8a660bce7 + a6754ddf7).
- 2026-08-04 — resolved, commit PENDING-COMMIT.
