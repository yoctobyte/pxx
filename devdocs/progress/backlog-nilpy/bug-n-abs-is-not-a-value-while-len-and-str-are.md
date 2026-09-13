---
slug: bug-n-abs-is-not-a-value-while-len-and-str-are
title: abs is not a value while len and str are
summary: >
  `map(abs, xs)`, `f = abs` and any other use of `abs` as a FUNCTION VALUE are
  refused with `undefined variable (abs)`. `abs(x)` as a CALL is fine -- the
  frontend intercepts it by name and routes to pylib's pyabs_v, and a name-keyed
  intrinsic has no symbol for a bare mention to find. TWELVE names share this,
  censused 2026-09-13: abs ascii chr divmod enumerate filter hash id map ord
  round zip. `len` is the counter-example the fix should copy (it is a real proc
  under its own Python name); `str` is NOT -- `map(str, xs)` works through a
  hardcoded conversion arm in the map() intercept, not through the callable-value
  mechanism, and `f = str; map(f, xs)` raises "calling str() through a type held
  as a value is not supported yet".
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


## The census, 2026-09-13 (frankS, at 34a9a7609)

One isolated fixture per name (`f = <name>`, own file, own compile) so no name's
success could resolve another -- 35 builtin names. TWELVE refuse:

    abs  ascii  chr  divmod  enumerate  filter  hash  id  map  ord  round  zip

and the rest bind. The split is exactly "is there a Pascal proc registered under
the PYTHON spelling": pylib declares `len`, `sum`, `sorted`, `hex`, `bin`, `oct`
under their own names, and declares `pyabs_v`, `pyround_v`, `pyround1_v`,
`pyround_int` for the refused ones. So this is one mechanism, not twelve bugs,
and it is the mechanism this ticket already named.

`str` is worth correcting in the original framing, because it reads as evidence
that the callable-value path already works for a builtin and only `abs` is
missing. It is not. Three shapes, measured separately:

    f = str; f(1)                  ok
    list(map(str, [1, 2]))         ok   -- the map() intercept's CONVERSION arm
                                          (mapConv, pyiter_map_conv_*), which
                                          special-cases the literal tokens
                                          int/str/float followed by a comma
    f = str; list(map(f, [1, 2]))  TypeError: calling str() through a type held
                                          as a value is not supported yet

So `str` in argument position never reaches the mechanism `abs` is missing from.
`len` does, and is the honest model for a fix.

## What the fix still has to decide, unchanged

`abs` is not one function -- pyabs_v plus static integer and double spellings --
so a bare mention has to name ONE. That choice is still the whole ticket. The
neighbours this ticket asked about ARE part of it (`round`, `ord`, `chr` all
refuse; `sorted` and `sum` do not), so it is one group.

## NOT part of this ticket, split out 2026-09-13

`min` and `max` bind but answer wrongly -- a DIFFERENT mechanism (the bare name
reaches pylib's two-argument scalar arm while the one-argument iterable arm is
in pyeval, and the overload search is deliberately unit-scoped). Filed as
[[bug-n-min-and-max-as-a-value-bind-to-the-two-argument-arm-in-the-wrong-unit]].

The defaulted-tail half of this area -- `f = sorted; f(xs)` answering `[]` or
segfaulting -- was a separate bug again and is FIXED (see that ticket's
resolution); it is named here only so a reader who measures `sorted` today and
finds it working does not conclude this ticket is stale.
