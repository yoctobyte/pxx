---
track: N
prio: 40
type: feature
blocked-by: []
status: done
owner: claude-A-N
---

# A `set` needs its own runtime tag — two divergences from `list` share this root cause

Found by proactive CPython-diff sweeping. NilPy backs Python's `set` with the
same `TPyList` as `list` (built via `.add()`'s dedup insert instead of
`.append()`), with NO runtime flag distinguishing "this TPyList is really a
set" — unlike tuple-vs-list, which already has exactly this kind of flag
(`FIsTuple` on `TPyList`, set by the frontend when a tuple literal was
written). Two independent, previously-unnoticed correctness gaps trace back
to that missing tag:

**1. Display: a set prints with list brackets, not `{...}`.**
```python
print({1, 2, 3})   # CPython: {1, 2, 3}   pxx: [1, 2, 3]
```
Already noted as an out-of-scope cosmetic aside in
`bug-nilpy-set-and-dict-operators-do-raw-pointer-arithmetic` and
`feature-nilpy-set-methods-issubset-union-etc` — recorded properly here as its
own tracked half of the same fix.

**2. Equality: set equality is POSITIONAL (list rules), not CONTENT-set rules.**
```python
print({1, 2} == {2, 1})   # CPython: True (order-independent)   pxx: False
```
`compiler/ir.inc`'s `==` lowering for two class-typed operands calls
`pylist_eq` (`compiler/builtin/pylib.pas`) unconditionally — correct for two
genuine lists (Python list equality IS positional/ordered), but wrong for two
sets, which CPython compares by membership regardless of order. `pylist_eq`
has no way to tell "these are sets" from "these are lists" today, so it always
applies list rules.

## Fix direction

Add an `FIsSet: Boolean` field to `TPyList` (mirroring `FIsTuple` exactly),
set by the frontend at every point a set is constructed — set literals
(`{1, 2, 3}`), `set(iterable)`, and the result of the set operators/methods
already implemented (`pyset_and`/`_or`/`_sub`/`_xor`,
`union`/`intersection`/`difference`). Then:
- `pylist_repr` (pylib.pas): if `FIsSet`, render with `{`/`}` like `FIsTuple`
  already does for `(`/`)` (and CPython's own `set()` spelling for an empty
  set, since `{}` means an empty DICT in Python).
- The `==` lowering path (`ir.inc`) or `pylist_eq` itself: when either operand
  is `FIsSet`, use a set-equality check (same cardinality, every element of
  one found via `pycontains` in the other) instead of the positional compare.

Not attempted this pass — touches both the frontend's set-construction call
sites (several: literal parsing, `set()`, every set-operator/method result)
and the shared `ir.inc` equality lowering, so it deserves its own dedicated
pass with its own gate rather than a rushed patch appended to a sweep.

## Gate

A `.npy` case with set literals, `set(iterable)`, and results of the set
operators/methods, checking both `print()` output uses `{...}`/`set()` and
that `==` is order-independent — diffed against CPython, gated in
`test-nilpy` + `--tier quick` + self-host byte-identical (`ir.inc` is a
compiler-internal file).

## Re-measured 2026-08-13 — the TAG exists and half 1 is done; half 2 is not

`TPyList.FKind` (PYSEQ_LIST / PYSEQ_TUPLE / PYSEQ_SET) is the runtime tag this
ticket asks for, and it landed with the display half:

```python
print({1, 2, 3})   # {1, 2, 3} — correct, brackets and all
print(str({1}))    # {1}       — correct
```

Half 2 is unchanged and is now the whole ticket:

```python
print({1, 2} == {2, 1})   # CPython True — pxx still False
```

The tag being present is what makes this cheap now: `pylist_eq` can ask
`FKind = PYSEQ_SET` on both sides and compare by membership instead of by
position, with no frontend change. Note it is a `compiler/builtin/**` edit, so
it carries the stabilize+pin obligation.

## DONE 2026-08-13 — half 2 landed; the tag made it a small change after all

`{1, 2} == {2, 1}` is True, and a set is no longer equal to a sequence
(`{1, 2} == [1, 2]` was True, now False, matching CPython both ways round).

`pylist_eq` asks `FKind` when either side is a set and compares by MEMBERSHIP
instead of by position — equal lengths plus "every element of a is in b", which
is sufficient because `add()` dedups, so neither side can hold a repeat. The
positional walk stays exactly as it was for two lists, which is Python's own
rule for lists.

### The second copy is what made it look fixed when it was not

The first cut passed the direct rows and failed `[{1, 2}] == [{2, 1}]` and
`{1, 2} in [{2, 1}]`. `PyVarEq`'s two-objects arm carried its OWN copy of the
positional walk, so the operator agreed with the new rule and every CONTAINER
route — `in`, `.index()`, `.count()`, `.remove()`, a nested compare — still ran
the old one. That arm now calls `pylist_eq`, so there is one comparison in one
place; the duplication is what this repo's `normalise-dont-special-case.md`
keeps warning about, and it was found by testing the sibling route rather than
by reading.

### Left open, on purpose

`(1, 2) == [1, 2]` is still True where CPython says False. Same tag, same
function, one guard away — but the set arm only fires for values explicitly
built as sets, whereas a tuple-vs-list guard fires for everything whose kind was
left at its default, and that surface was not swept. Filed as
[[bug-nilpy-a-tuple-compares-equal-to-a-list]] with the constructors to check.

### Verified

`test/test_nilpy_set_equality_is_membership.{npy,expected}` (`.expected` from
CPython), wired into `test-nilpy`: order-independence, unequal contents at equal
length (which the length check alone cannot catch), differing lengths, empties,
strings and mixed types, `!=`, set-vs-list both ways, set-vs-tuple, the `is`
control that must not have moved, sets built by mutation and by `|=`, the
nested/`in` routes that caught the second copy, and lists keeping the ordered
rule.

`compiler/builtin/**` change, so it carries the stabilize+pin obligation —
pinned in the same commit. Gate: self-host fixedpoint + `gate.sh quick` GREEN.

## Log
- 2026-08-13 — resolved, commit PENDING-COMMIT.
