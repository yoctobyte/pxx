---
track: N
prio: 50
type: feature
status: working
owner: claude-AN
---

# Starred and NESTED unpacking targets

- **Type:** feature (NilPy frontend gap — loud) — **Track N**
- **Found:** 2026-08-02, by a differential sweep against the CPython oracle.
- Extends [[feature-nilpy-tuple-unpack]], which landed the two-name forms and is
  done. These are the shapes it did not cover.

## Measured

```python
first, *rest = [1, 2, 3]        # error: undefined variable (first)
```

```python
nested = [(1, ("a", "b"))]
for n, (p, q) in nested:        # error: Nil Python: expected a second loop variable
    ...
```

Both are hard compile errors, so they are the good case.

## What already works (measured in the same sweep)

Worth stating, so this is scoped as an extension and not re-investigated from
scratch:

```python
for k, v in pairs: ...            # list of 2-tuples
for k, v in sorted(d.items()): ...
for a, b in zip(xs, ys): ...
for a, b in [[1, 2], [3, 4]]: ... # list of lists
head, tail = [9, 8]
a, b = b, a
```

All correct. So the machinery for a flat two-name target exists; what is missing
is (a) a STAR in the target list and (b) a target that is itself a target list.

## Shape

- **Starred**: `a, *b = xs` and `*a, b = xs`. The starred name takes a LIST of
  the surplus, so it needs a count computed at run time (`len(xs) - fixed`), not
  a compile-time slot count. Python allows exactly one star per target list —
  refuse two loudly rather than picking one.
- **Nested**: `for n, (p, q) in ...`. The target is a TREE, so the existing
  "expected a second loop variable" scan needs to recurse instead of assuming a
  flat name list. Same for the assignment form `a, (b, c) = ...`.

The two are independent; either can land alone.

## Gate

A `.npy` diffed against CPython covering: `a, *b`, `*a, b`, a star that captures
zero elements, nested targets one and two levels deep, nested inside a `for`,
the mixed form `a, (b, c) = ...`, and a too-few-values case (CPython raises
ValueError).

## 2026-08-04 — the DIAGNOSTIC half landed; the feature itself is untouched

Both forms are still unsupported. What changed is that they now say so, because
the old messages accused the user's own code:

| form | before | now |
| --- | --- | --- |
| `first, *rest = [1,2,3]` | `undefined variable (first)` | `a STARRED assignment target ... is not supported yet — assign the sequence and slice it (rest = xs[1:])` |
| `*init, last = [1,2,3]` | `expected expression` | same STARRED message |
| `a, (b, c) = ...` | `undefined variable (a)` | `a NESTED assignment target ... — unpack the outer level first, then the inner` |
| `for n, (p, q) in xs:` | `expected a second loop variable` | `a NESTED loop target ... — loop over the outer level and unpack the inner in the body` |

The first three pointed at a name that is perfectly fine, indistinguishable from
a typo; the fourth claimed a variable was MISSING while the user is looking
straight at one that is merely parenthesised. That is the shape this repo treats
as worse than the gap itself.

`PyUnpackTargetAhead` requires every target element to be a plain name, so these
fall through to the ordinary expression statement — which is why the failure
surfaced on the first NAME rather than on the construct. A new
`PyUnsupportedUnpackTargetAhead` recognises the two shapes just after it, and the
for-target gets its own check at the `tkLParen` / `tkStar` it currently rejects.

Deliberately narrow, since a false positive would REJECT VALID CODE: the
statement must open the target, there must be a depth-0 `=` before the end of the
logical line, and the star or `(` must sit where a target element begins. One bug
found while testing exactly that — the end-of-line exit returned the accumulated
result instead of clearing it, so `for n, (p, q) in xs:` (which has no `=`
anywhere) was reported as a nested ASSIGNMENT target and stole the loop's own
message. Twelve valid shapes are checked against CPython as controls, including
`a, b = b, a`, `for k, v in d.items()`, `def f(*args, **kw)`, slices, f-strings
and comprehensions.

Pinned by four `*_fail.npy` tests wired into `make test-nilpy`, each grepping for
its own message so the two shapes cannot collapse into one.

**Unchanged:** the Shape and Gate sections above still describe the real work.
Starred needs a run-time surplus count; nested needs the target to become a TREE,
and the for-target is a flat name list (`name`/`name2`/`PyForExtraName[]`) that
the whole lowering is keyed on, so that is a bigger change than "make the scan
recurse" suggests. A cheaper route worth weighing first: DESUGAR a nested target
into a temp plus an inner unpack (`for n, __t in xs:` + `p, q = __t`), which
reuses the flat machinery and the existing two-name assignment.

## 2026-08-09 — the STARRED half is IMPLEMENTED; NESTED still open

`a, *rest = xs`, `*init, last = xs` and `p, *mid, q = xs` all work and match
CPython. The two halves were independent as the ticket said, and only the
starred one is done.

### How

The fixed targets are counted from each END and the starred one takes the slice
between — `a, *rest = xs` is `a = xs[0]; rest = xs[1:len(xs)]`, and
`*init, last` is `init = xs[0:len(xs)-1]; last = xs[len(xs)-1]`. The high bound
is a RUNTIME expression, which is exactly why a star cannot be a compile-time
slot count the way the flat form is.

### Three things the first attempt got wrong, now pinned

- **The starred target is always a LIST**, even from a tuple source:
  `a, *b = (1,2,3)` gives `b == [2, 3]`, not `(2, 3)`. The slice that builds it
  copies the source's kind — correct for an ordinary slice, where a slice of a
  tuple IS a tuple — so it is re-marked. The VALUES look identical either way,
  so the test asserts `type(v).__name__`.
- **Too few values raise ValueError**, naming the count. The indexed stores
  alone raise IndexError, a different type, so `except ValueError` around the
  unpack would not catch it. A length check is emitted once per starred unpack.
- **The star may capture ZERO**, at either end. The from-the-end arithmetic is
  what breaks first there.

### The negative tests it retired — and the trap that nearly shipped

`test_nilpy_starred_target_fail` and `test_nilpy_leading_star_target_fail`
asserted the OLD refusal message. With the feature implemented they compile, so
their `! $(COMPILER) ...` recipes would have FAILED `make test-nilpy` — and
`gate.sh quick` does **not** run that target, so the per-fix gate was green with
a broken suite waiting for Track T. Both are retired with their recipes; the
diagnostic reasoning they recorded lives in this ticket, and
`test_nilpy_starred_unpack.npy` covers the behaviour.

The nested pair (`nested_assign_target_fail`, `nested_for_target_fail`) is
UNCHANGED and still exercised — those forms are still unsupported and must still
name themselves.

**Lesson worth carrying: implementing a feature can break its own `{%FAIL}`
tests, and the quick gate cannot see it.** Grep for `_fail` tests naming the
feature before landing one.

### Verified
`test/test_nilpy_starred_unpack.{npy,expected}` (`.expected` from CPython): all
three star positions, zero-capture at both ends, tuple/list/call/variant
sources, the mutability of the starred list, and the ValueError. Whole-suite
HEAD-vs-pinned sweep: **zero regressions**, 74 -> 45 differing. `make test-nilpy`
run to 1647 lines with no failure (cut short by a local timeout, not an error),
confirming the retired recipes are gone and the nested ones still run.
`gate.sh quick` GREEN.

### Still open
The NESTED half — `a, (b, c) = ...` and `for n, (p, q) in xs:` — is untouched.
Its shape is a target TREE, so the flat name-list scan has to recurse. Both
still refuse themselves by name.
