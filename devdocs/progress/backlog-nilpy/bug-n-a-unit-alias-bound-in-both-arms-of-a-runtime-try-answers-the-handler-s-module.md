---
prio: 35
track: N
summary: "`try: ... except E: from pkg import a as impl / else: from pkg import b as impl` -- a unit alias is a COMPILE-TIME first-wins table and the branch is a RUNTIME one, so `impl` answers the handler's module whichever arm actually runs. Silent wrong value, exit 0. Measured 2026-09-11, identical on `785b25831252` and `8b0839edde8f`, so it is untouched by the guarded-import arm work and is NOT the guarded case, which is fixed. No fix proposed: the two representations disagree about when the choice is made."
---

# bug: a unit alias bound in both arms of a RUNTIME try answers the handler's module

- **Type:** bug (silent wrong value — compiles, runs, exit 0, no diagnostic).
- **Found:** 2026-09-11, frankZ, as the one non-matching row in the regression
  set for `bug-n-try-except-else-does-not-parse-when-the-try-body-is-an-import`.
- **Not that bug, and measured so:** identical output on the pre-fix compiler
  `785b25831252` and the post-fix `8b0839edde8f`.

## Measured

```python
try:
    x = 1                      # no import here -- an ORDINARY runtime try
except ValueError:
    import armone as impl
    print("handler", impl.WHO)
else:
    import armtwo as impl
    print("else", impl.WHO)
```

| | |
| --- | --- |
| CPython | `else two` |
| pxx | **`else one`** |

The control flow is right — pxx takes the `else` arm and says so — and the
alias is wrong. `armone` is the module the program did not import.

## Why, and why it is not the guarded-import bug

A unit alias lives in a compile-time table, and `FindUnitOrAlias` scans from
index 0 and takes the **first** row for a name
(`bug-n-a-unit-alias-rebind-is-silently-ignored`). Both arms register `impl`;
the handler is lexically first; the handler wins.

For a GUARDED import try the frontend knows which arm is dead — it decided the
branch itself at the import — and as of `8b0839edde8f` both layers that resolve
imports skip the dead one, so that whole family is correct. **Here there is
nothing to know.** `x = 1` raises or does not raise at run time; no compile-time
question has an answer, and a first-wins table has no way to hold "whichever of
these two runs".

## Why prio 35 rather than higher, stated as a population and not as a feeling

The shape needs an ordinary runtime try to select a MODULE and bind it under one
name in more than one arm. The overwhelmingly common spelling of module
selection is the guarded-import idiom, which is the fixed family. This is real
Python and it does appear — a `try: import fast_json as json / except
ImportError: import json` is guarded, but `try: cfg = load() / except OSError:
import defaults as cfg_mod / else: import user as cfg_mod` is not — and it is
rarer than the guarded form by a wide margin.

**It is ranked on rarity and not on harm.** The harm is the expensive kind: a
plausible wrong value far from the cause, with the control flow visibly correct
beside it, which is exactly the shape that survives review.

## Direction — NOT chosen, and the fork is real

A compile-time alias cannot answer a runtime question, so any fix changes the
representation of one of the two:

1. **Refuse it.** Diagnose a second registration of an alias name in a sibling
   arm of a runtime try. Cheap, loud, upward-compatible with CPython in the
   direction NilPy already allows (we may reject what CPython accepts is NOT
   allowed — N is upward compatible one way — so this would be a real
   divergence and needs stating as one).
2. **Make the binding a runtime value** where the arms disagree — the module
   object as a value rather than a namespace, which is
   `bug-n-a-module-bound-by-an-import-is-not-a-value` and is the same wall that
   ticket is about.

Option 2 is where this actually belongs; it is listed here so the next reader
does not build option 1 without noticing that the general fix subsumes it.
`blocked-by` that ticket rather than duplicating its analysis.

## Reproducing

Two one-line packages (`armone/__init__.py` = `WHO = "one"`, `armtwo` the same
with `"two"`) and the file above. Under pxx the answer does not change if the
arms are swapped in source order — whichever is lexically first wins, which is
the confirmation that it is the alias table and not the branch.
