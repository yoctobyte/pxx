---
track: N
prio: 45
type: bug
summary: "`def len(x)` shadows the builtin for a STRING argument but not for a list/dict — the container call still reaches pylib's len and prints its answer silently. Residue of bug-nilpy-user-def-does-not-shadow-a-pylib-builtin, which fixed 14 of 15 builtins."
status: done
owner: claude-AN
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


## Resolved 2026-08-04 — the cause was UPSTREAM of both excluded candidates

Both exclusions in this ticket were correct and both were beside the point. The
`PXXDBG=n.shadow` probe added while chasing this says it in one line:

```
PXXDBG n.shadow sorted user=TRUE  nilpyuser=TRUE curunit=-1
PXXDBG n.shadow len    user=FALSE nilpyuser=TRUE curunit=-1
```

In the SAME program. `PyUserShadowsProc('len')` answered **False** — so the
overload demote never fired and the `len` intrinsic's guard never engaged.
Everything downstream was behaving correctly on a wrong premise.

### Why: `def len` was never registered at all

`PyRegisterDefShells` registered a module-level def only `if FindProc(name) < 0`
— and `FindProc` sees **unit** procs, so pylib's `len` made the user's shell be
skipped entirely.

`def sorted(x)` worked only by accident of **registration order**: pylib (which
declares `len`) is registered before that pre-pass and pyeval (which declares
`sorted`) after it, so `FindProc('sorted')` missed and the shell went in. That
accident is exactly why `len` was the one straggler of the fifteen builtins the
shadowing ticket surveyed — and it is the same "probe with an argument the
builtin matches exactly, or the test is blind" trap in a new dress.

Fixed by asking the right question: `FindProcInUnit(name, -1) < 0` — *has the
MAIN PROGRAM already declared this name*. Registering the shell is what Python
semantics want; `MatchProcCall`'s `userOnly` demote then drops the unit's
overloads by name, as it already did for the other fourteen.

### Two follow-on repairs the shell exposed

1. **`unresolved forward: len`.** `PyParseDef` reused a shell via `FindProc`,
   which returns the OLDEST registration of a name — pylib's — so it registered
   a second proc and left the shell bodyless. It now looks in the main program
   first.
2. **A THIRD name-keyed surface**, in `ir.inc`: the `len(v)` → `pylen_v` rewrite
   for a VARIANT argument is keyed on `Procs[cpi].Name = 'len'`, so a user def
   that had correctly won resolution was still rewritten to pylib's helper and
   never ran (`for y in [[1,2]]: print(len(y))` printed an empty line). Guarded
   on `ProcUnitIdx[cpi] <> -1`. That is the third surface after the parser
   intrinsics and the overload demote — the ticket predicted there was one.

### The pre-existing segfault is gone too

`len(5)` with no matching overload segfaulted (and did so on `pinned`). It now
raises a catchable `TypeError: expected a str, list, dict or bytes, got int`,
because the shadow question is answered correctly and the call no longer reaches
a mismatched overload.

### Verified

`test/test_nilpy_user_def_shadows_builtin.npy` gained `len` over a string, a
list, a dict, an int and a for-in VARIANT; all fifteen builtins in the original
survey shadow correctly, and the unshadowed control program is unchanged —
both diffed against CPython. `tools/gate.sh quick` GREEN, self-host
byte-identical.

`PXXDBG=n.shadow` is kept: this predicate gates the demote AND every intrinsic
guard, so "did the predicate even say so" is the first question worth answering,
and reasoning about it from the call sites is what burned an hour here.

## Log
- 2026-08-04 — resolved.
- 2026-08-04 — resolved, commit PENDING-COMMIT.
