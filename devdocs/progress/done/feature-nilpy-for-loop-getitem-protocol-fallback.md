---
track: N
prio: 25
type: feature
blocked-by: []
status: done
commit: PENDING-COMMIT
---

# `for x in obj:` doesn't fall back to `__getitem__`/`__len__` for a custom container

Found by proactive CPython-diff sweeping.

```python
class Box:
    def __init__(self, items):
        self.items = items
    def __getitem__(self, idx):
        return self.items[idx]
    def __setitem__(self, idx, val):
        self.items[idx] = val
    def __len__(self):
        return len(self.items)

b = Box([1,2,3])
print(b[0])       # works: 1
b[0] = 99         # works
print(len(b))     # works: 3
for x in b:       # fails
    print(x)
```
`b[idx]`/`b[idx] = v`/`len(b)` (via `__getitem__`/`__setitem__`/`__len__`)
already all work correctly. Only iterating a custom container with `for`
fails:
```
pascal26:16: error: Nil Python: pylib (count) not loaded
```
CPython supports iterating ANY object that implements `__getitem__`
(starting from index 0, stopping on `IndexError`) even without a full
`__iter__`/`__next__` — the "old-style iteration protocol" fallback. NilPy's
`for` desugars to a counted loop assuming a known container type
(list/dict/str/etc.) and has no path for a bare user class, even one that
otherwise fully implements the item-access protocol.

## Scope note

Likely related to the broader, already-tracked generator/iterator-protocol
gap (`feature-generators-yield`, `feature-nilpy-yield-outside-a-for-loop`,
and the full `__iter__`/`__next__` STOP-iteration protocol, which is a much
bigger feature) — but this specific fallback (iterate via `__getitem__`
alone, no explicit iterator object) is narrower and could plausibly land
independently of the general generator/iterator machinery: it's "counted
loop calling `obj[i]` until `__getitem__` would raise `IndexError`," which is
close in shape to how NilPy already desugars `for x in some_list:`.

Not attempted this pass — needs its own investigation into whether it's
cheap to add as a special `for` desugar case (detect a class with
`__getitem__` but no static list/dict/str type) versus properly belonging
to the larger iterator-protocol feature.

## Gate

A `.npy` case iterating a class that implements only `__getitem__`/`__len__`
(no `__iter__`), diffed against CPython, gated in `test-nilpy` + `--tier
quick` + self-host byte-identical.


---

## RESOLVED 2026-08-19

Reproduced at HEAD exactly as filed.

### Root cause

`for x in obj` over a non-string, non-cursor receiver lowers to an INDEX LOOP,
and that loop asked the receiver's class for pylib's spellings — `count` for the
length and `at` for the element. A user container spells them `__len__` and
`__getitem__`, so the length lookup found nothing and the compile died with
`pylib (count) not loaded` — an error naming a pylib routine, raised for a
program that never mentions pylib, about a class whose `b[0]`, `b[0] = v` and
`len(b)` all already worked. Only the ITERATION spelling was missing.

### Fix

Two small helpers, `PySeqLenMethod` / `PySeqAtMethod`, that answer which
spelling class `ci` uses, and the index loop calls those. Deliberately not
folded into `PyMethNameFor`: that maps a PYTHON name onto a class's spelling,
and here we hold the pylib name and want the Python one — the opposite
direction.

**Applied at BOTH index-loop sites.** There are two (the length snapshot and the
loop condition) and fixing one would have left `for` working and the loop test
broken. Grepping for the sibling before closing is the repo's own rule and it
paid here.

### The `__getitem__`-only case, and its diagnostic

CPython iterates a class with `__getitem__` alone by walking 0.. until
`IndexError`. That is still unsupported — but it now says so:

```
Nil Python: `for` over this object needs `__len__` as well as `__getitem__`
— iterating by __getitem__ alone (stopping on IndexError) is not supported yet
```

instead of `pylib (count) not loaded`. The message names the method the reader
would add, not pylib's internal spelling.

### Verified against CPython

| shape | before | after |
| --- | --- | --- |
| `for x in b` over `__getitem__`+`__len__` | compile error | 1 2 3 |
| `[x*2 for x in b]` | compile error | `[2, 4, 6]` |
| `b[0]`, `b[0] = v`, `len(b)` | worked | still work |
| list / dict / str iteration | worked | still work |
| `__getitem__` with no `__len__` | confusing error | clear, actionable error |

### Sibling consumers — filed, not silently left

Fixing the `for` lowering moved comprehensions (same lowering) and nothing else.
`list(b)`, `sum(b)`, `2 in b` and `p, q, r = b` each test for a container their
own way and all still refuse a `__getitem__` container — **and `list(b)` answers
`[]` silently**, which is worse than the errors. All confirmed pre-existing on
pinned, none caused by this change, and all filed as
[[bug-n-the-old-style-iteration-protocol-reaches-only-the-for-loop]] with the
silent one called out as the reason it is a bug ticket.

### Test

`test/test_nilpy_for_getitem_protocol.npy` + `.expected` (CPython-generated),
covering iteration, the comprehension, the three shapes that already worked, and
ordinary containers as controls. **Wired** into the Makefile; wiring verified by
running the wired lines verbatim plus `make -n compiler/pascal26`.

### Gate

`make compiler/pascal26` (self-host fixedpoint, 1 round) + `tools/gate.sh quick`.

## Log
- 2026-08-19 — resolved, commit 6905d6fd0.
