---
track: N
prio: 55
type: bug
---

# A set comprehension over `range()` does not deduplicate

```python
print(sorted({x % 3 for x in range(9)}))
```

```
CPython:  [0, 1, 2]
pxx:      [0, 0, 0, 1, 1, 1, 2, 2, 2]
```

`len()` is wrong too, so this is not a display problem — the object really holds
the duplicates. **Silent:** every value present is a value the comprehension
should produce, so the result looks like a plausible set until something counts
it.

## The boundary — it is the SOURCE, not the element

| comprehension | result |
| --- | --- |
| `{x % 3 for x in range(9)}` | **duplicates kept** |
| `{x // 2 for x in range(6)}` | **duplicates kept** |
| `{0 for x in range(3)}` | **duplicates kept** (`[0, 0, 0]`) |
| `{x % 3 for x in [0,1,2,3,4,5]}` | correct |
| `{x % 2 for x in list(range(6))}` | correct |

So: **any** set comprehension whose source is `range(...)` fails; over a
container it is correct. `list(range(6))` working is the tell — same values,
different lowering.

**A blind control nearly hid it.** `{x for x in range(9)}` passes — but every
value there is distinct, so it cannot observe deduplication at all. Any probe
must use an element expression that COLLIDES.

## Cause — located

Two comprehension-body builders, one per loop lowering:

- `compiler/pyparser.inc:13882` (the CONTAINER path, in `PyParseForIn`) chooses
  `add` when `PyCompIsSet` and `append` otherwise — correct.
- `compiler/pyparser.inc:14697` (the **`range` counted-loop path**) calls
  `'append'` **unconditionally**. It never consults `PyCompIsSet`.

`PyParseSetComp` still stamps the result with `PyMarkAsSet`, so the object
*reports* itself a set (`isinstance`, repr, the set operators) while holding
duplicates — which is why the wrongness surfaces only as a count or a repr of
the contents.

The dict arm above it is fine in both places, so it is exactly the set arm that
is missing from the second copy — the recurring two-homes shape
(`devdocs/dev/normalise-dont-special-case.md`).

## Fix

Give the range path the same two-arm choice as the container path. Better still,
lift the choice into one helper both call, so a third loop lowering cannot
reintroduce it.

## Gate

`make test-nilpy` + self-host byte-identical, with a CPython-diffed test over
set comprehensions whose elements COLLIDE, from a `range` source, a list source,
a `list(range(...))` source and a string source; each asserted with both
`sorted(...)` and `len(...)`; plus dict and list comprehensions over `range` as
controls, and a filtered set comprehension over `range`.

## 2026-08-09 — FIXED

The `range` counted-loop path now makes the same two-arm choice the container
path makes. One line of behaviour; the comment beside it names the symptom and
the blind control so the next person to touch that builder sees both.

`test/test_nilpy_set_comprehension_dedup.npy` asserts **only colliding element
expressions**, and says why: `{x for x in range(9)}` PASSES against the broken
compiler, because those values are already distinct and the test cannot observe
deduplication at all. That case is kept at the end of the file precisely so its
blindness is on the record.

Both `sorted(...)` and `len(...)` are asserted for every case — the repr and the
count came from different places and the count is what exposed it — and the
sources are varied (`range`, list, `list(range(...))`, string, tuple) because
the boundary was the SOURCE, and `list(range(6))` working while `range(6)` did
not is what localised it. Controls check that list and dict comprehensions over
`range` still do NOT deduplicate.

Verified against CPython; `gate.sh quick` GREEN.
