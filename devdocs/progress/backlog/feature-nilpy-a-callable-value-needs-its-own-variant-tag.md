---
track: N
prio: 50
type: feature
---

# A callable value needs its own variant tag

Splits out the part of `bug-nilpy-calling-a-non-callable-segfaults` that the
guard landed there could not close, with the measurement that proves it.

## The residual hole

`PyNotCallable` now refuses every tag that nothing callable ever wears — 1
(VT_INT), 3, 4, 5, 6, the promotable-int block, and 7 without a `__call__`.
**Tag 2 (VT_INT64) is left permitted**, and that is a real hole:

```python
def get(w):
    if w == 1: return 3 + 4
    return "x"
get(1)(3)          # still SEGFAULTS
```

`5` boxes as VT_INT (1) and is caught. `3 + 4`, `2**40` and `int("99")` box as
VT_INT64 (2) — the **same tag a plain compiled def's code address rides as**.
1-vs-2 is an integer WIDTH distinction; it carries no information about whether
the payload is code. Refusing tag 2 would break every ordinary call through a
def value.

## The measurement, so this is not re-derived

Probing every callee that reaches the guard across the whole `.npy` corpus:

| tag | samples | what it is |
| --- | --- | --- |
| 10 | 245 | lifted bound-fn |
| 2 | 106 | **plain def code address** |
| 9 | 12 | pyeval closure |
| 0 | 2 | None (already raised) |

Tags 1/3/4/5/6/7 appeared **zero** times — which is what made refusing them
safe. Tag 2's 106 samples are what make refusing it impossible.

## The fix

Give a callable value its own tag (12), stamped wherever a def's code address
is boxed as a variant, so the guard becomes an allow-list on {8,9,10,11,12}
and the int case closes with everything else. Same shape as VT_CLASSREF (11),
which was added for exactly this reason — an untagged RTTI blob address was
indistinguishable from a code address, and `cls(3)` jumped into the blob.

This is the third representation-collision in
`project_nilpy_callable_has_three_representations`; the tag is what ends the
family rather than adding a fourth guard.

## Gate

`make test-nilpy` + self-host byte-identical. The existing
`test_nilpy_calling_a_non_callable.npy` documents the uncovered case in a
comment — when this lands, move `3 + 4` into the test body and delete the note.
