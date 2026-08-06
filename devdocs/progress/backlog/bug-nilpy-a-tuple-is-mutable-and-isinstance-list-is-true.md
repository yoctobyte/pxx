---
track: N
prio: 50
type: bug
summary: "NilPy: a tuple is a TPyList wearing a tuple name — `t[0] = 9`, `t.append(4)` and `del t[0]` all succeed where CPython raises, and `isinstance(t, list)` is True. Read semantics are all correct; only the immutability contract is missing."
---

# A tuple is mutable, and `isinstance(t, list)` is True

- **Type:** bug (silent semantic divergence) — **Track N**
- **Found:** 2026-08-06, incidentally, while scoping
  [[meta-constant-normalisation]] — the question "are tuples actually immutable
  here?" got measured rather than assumed. They are not.
- Pre-existing (identical on `pinned`), and NOT listed in
  `devdocs/dev/nilpy-semantics-divergences.md`, so it is a bug rather than a
  chosen divergence.

## Measured

```python
t = (1, 2, 3)
```

| expression | CPython | pxx |
| --- | --- | --- |
| `type(t).__name__` | `tuple` | `tuple` — OK |
| `isinstance(t, tuple)` | True | True — OK |
| `isinstance(t, list)` | **False** | **True** |
| `t.append(4)` | `AttributeError` | **succeeds** -> `(1, 2, 3, 4)` |
| `t[0] = 9` | `TypeError` | **succeeds** -> `(9, 2, 3)` |
| `del t[0]` | `TypeError` | **succeeds** |
| `(1,2) == (1,2)` | True | True — OK |
| `(1,2) + (3,)` | `(1, 2, 3)` | `(1, 2, 3)` — OK |
| `d[(1,2)] = "k"` | works | works — OK |

So the VALUE semantics are right and only the immutability contract is missing:
a tuple is built as a `TPyList` (the parser says so — *"A parenthesised TUPLE is
built as a TPyList"*) and nothing marks it read-only.

## Why it matters

It silently accepts programs CPython rejects. Mutating a tuple is a bug in the
author's program; pxx runs it and produces a plausible result, so the mistake
survives to wherever the tuple is next read instead of being reported at the
line that made it.

`isinstance(t, list)` answering True is the other half, and is the one that can
change a correct program's behaviour: an `isinstance(x, list)` branch — the
ordinary way NilPy code narrows an untyped value — takes the list arm for a
tuple.

## Shape of a fix

A read-only flag on the `TPyList` instance, set when it is built as a tuple and
checked by the mutating entry points (`setitem`, `append`, `extend`, `del`,
`pop`, `insert`, `remove`, `sort`, `reverse`), raising `TypeError` with Python's
wording. `isinstance(t, list)` then keys off the same flag.

Cheaper than a separate `TPyTuple` class and keeps every read path — indexing,
slicing, iteration, `len`, comparison, hashing, unpacking — exactly as it is,
which is the part that already agrees with CPython.

Check `pyvar_setitem` and the default-indexed-property setter both honour it:
those are the two arms of the subscript-store double case (see
`devdocs/dev/normalise-dont-special-case.md`), and fixing one and not the other
is the recurring failure this repo keeps hitting.

## Gate

Per-fix loop. A `.npy` test over the table above — every mutating method and
`del`, `isinstance` against both `tuple` and `list`, plus the read paths that
must stay working (index, slice, iterate, `len`, `==`, `+`, dict key,
unpacking) — diffed against CPython with `tools/pydiff.py`.
