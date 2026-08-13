---
track: N
prio: 40
type: feature
blocked-by: []
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
