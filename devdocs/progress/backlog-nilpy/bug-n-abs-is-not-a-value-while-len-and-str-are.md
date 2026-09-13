---
slug: bug-n-abs-is-not-a-value-while-len-and-str-are
title: abs is not a value while len and str are
summary: >
  `map(abs, xs)`, `f = abs` and any other use of `abs` as a FUNCTION VALUE are
  refused with `undefined variable (abs)`. `len` and `str` in the same position
  both work, so this is one name missing from whatever makes a builtin
  addressable rather than a design gap. `abs(x)` as a CALL is fine -- the
  frontend intercepts it by name and routes to pylib's pyabs_v, and a name-keyed
  intrinsic has no symbol for a bare mention to find.
track: N
type: bug
prio: 35
owner: unassigned
status: open
---

## Measured

    print(list(map(len, ["aa", "b"])))   # [2, 1]        ok
    print(list(map(str, [1, 2])))        # ['1', '2']    ok
    print(list(map(abs, [-5, 2])))       # undefined variable (abs)

2026-09-13, at HEAD. Found while writing the `default=` rows of
`test/test_nilpy_minmax_default.npy`, which wanted a lengthless iterable and
reached for `map(abs, ...)` first; the fixture uses `map(len, ...)` instead and
says why.

## What the fix has to decide

`abs` is not one function. pylib carries `pyabs_v(const v: Variant)` plus the
static integer and double spellings, so a bare `abs` has to name ONE of them —
presumably the variant one, which is what the dynamic call path would want
anyway. That choice is the whole ticket; it is not obviously a one-liner, which
is why this is filed rather than fixed beside the min/max work it was found in.

Worth checking at the same time whether any other name-keyed intrinsic has the
same hole — `round`, `ord`, `chr`, `sorted`, `sum` are the neighbours.
