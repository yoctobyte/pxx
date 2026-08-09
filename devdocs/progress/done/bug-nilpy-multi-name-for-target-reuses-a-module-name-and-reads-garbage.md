---
prio: 55
track: N
type: bug
blocked-by: []
status: done
---

# A MULTI-NAME for target at module scope reuses an existing name's slot

- **Type:** bug (NilPy; valid CPython silently wrong, then SIGSEGV) — **Track N**
- **Found:** 2026-08-09, realistic-program sweep (a meeting scheduler that
  builds `conflicts` in a nested loop and then unpacks it).

```python
a = ["p"]
for k, a in [("t", ["x", "y"])]:
    print("in loop", a)        # CPython: ['x', 'y'];  pxx: empty, then SIGSEGV
```

Every prior binding kind reproduces, including a binding of the **same** type:

| prior binding | pxx |
| --- | --- |
| `a = 3` | `TypeError: expected a number, got object` |
| `a = "hello"` | empty value, then SIGSEGV |
| `a = ["p"]` | empty value, then SIGSEGV |
| `a = set(["q"])` | `TypeError: sequence item 0: expected str instance` |
| name never bound before | correct |

**Module scope only** — the identical code inside a `def` is correct, because a
def body's locals are pre-seeded from the converged `PyLocals` table.

The realistic shape it was found in: build a list of tuples in one loop, then
`for a, b, shared in conflicts:` with the same names the build loop used. The
first divergence is a silent wrong value; the crash comes later and elsewhere.

## Cause

`PyCollectModuleLocalsAST`'s `for` arm folds a loop TARGET's element type into
the whole-program widening table — but **single-name targets only**. That
narrowing is stated outright in its comment ("a two-name target … is rarer for
this specific conflict and stays unhandled rather than guessed at"), and this
ticket is that gap: nothing notes `a`, so the name keeps the type its earlier
ordinary assignment gave it, and `PyParseForIn`'s `symIdx := PyProgSym(name)`
binds the unpacked element — always a variant — into that fixed slot.

It is the exact sibling of
`bug-nilpy-for-variable-reused-after-a-non-string-binding-iterates-garbage`
(single-name) and of
`bug-nilpy-tuple-unpacked-name-undefined-in-a-later-assignment` (the `a, b =`
statement form, which grew its own arm in the same pre-pass).

## Fix

The `for` arm now scans a whole comma-separated target list. A multi-name
target's elements are **variants whatever the iterable is** — that is a property
of unpacking, not of the container — so unlike the single-name arm this needs no
look at the iterable and stays a pure token peek. `enumerate(...)` is the one
exception: its first name is the index, noted `tyInt64` so an arithmetic loop
counter is not widened to a variant.

Single-name behaviour is unchanged: the new `PyForTargetRun` answers count 1 and
the same `in` position the old `Tokens[i+2] = tkIn` test required.

## Verified

- `test/test_nilpy_for_multiname_target_reuses_name.npy` (all five prior-binding
  kinds above, plus `enumerate` and `.items()` over reused names).
- The scheduler program that found it now matches CPython line for line.
- `make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN.

## Log
- 2026-08-09 — resolved, commit PENDING-COMMIT.
