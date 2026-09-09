---
slug: bug-n-sorted-over-bytes-raises-where-sorted-over-str-works
track: N
prio: 40
type: bug
status: done
owner: ""
created: 2026-09-09
found-by: frankB
tags: [nilpy, bytes, sort, comparison]
blocked-by: []
summary: "`sorted([b\"cd\", b\"ab\"])` raised `TypeError: expected a number, got object` where CPython answers `[b'ab', b'cd']`; `sorted([\"cd\",\"ab\"])` and `sorted([2,1])` both worked. Cause: pyvar_gt has a lexicographic arm for two TPyLists -- which covers list, tuple AND set, because those are one class here -- and none for TPyBytes, so two bytes objects fell through to pyvar_to_int. Fixed 2026-09-09 by adding the TPyBytes arm beside its sibling, comparing UNSIGNED byte values (b'\\xff' > b'\\x01') and shorter-is-smaller on a common prefix, which is CPython's rule. Found while grepping for siblings of the bytes.join gap, not by a report."
---

# sorted() over bytes raises where sorted() over str works

## Repro

```python
print(sorted([b"cd", b"ab"]))   # CPython: [b'ab', b'cd']
                                # before:  TypeError: expected a number, got object
print(sorted(["cd", "ab"]))     # worked
print(sorted([2, 1]))           # worked
```

## Cause

`pyvar_gt` (compiler/builtin/pylib.pas) already carried a lexicographic arm for
two `TPyList`s, added for `sorted([("b",2),("a",1)])`. That arm covers list,
tuple and set together because NilPy backs all three with one `TPyList`.
`TPyBytes` is a different class, so two bytes objects matched neither the
sequence arm nor the user-`__gt__` arm and fell through to `pyvar_to_int`.

One concept — "two sequences compare lexicographically" — and the sibling nobody
extended is the one that stayed broken
(`devdocs/dev/normalise-dont-special-case.md`).

## The part that could have been silently wrong

CPython compares bytes as **unsigned** values 0..255, so `b"\xff" > b"\x01"`.
Reading the bytes as signed inverts every pair with the top bit set — and still
returns a list that is sorted, just in the wrong order. A "does it run" assertion
cannot see that. `test/test_nilpy_bytes_join_and_bytes_n.npy` asserts
`sorted([b"\xff", b"\x01"])` and `sorted([b"\x80", b"\x7f", b"\x00"])` against
CPython's own output for exactly that reason.

Found by grepping for siblings after fixing
`bug-n-str-join-rejects-an-argument-shape-cpython-accepts`; not reached by
lekkerzeilen, so it blocked nothing and was fixed because it was one line from
a defect already in hand.

## Log

- 2026-09-09 — fixed and closed in the same change; the fix and its test row are
  in commit d1efd1dee (the `TPyBytes` lexicographic arm of `pyvar_gt` in
  `compiler/builtin/pylib.pas`, asserted by
  `test/test_nilpy_bytes_join_and_bytes_n.npy`).
