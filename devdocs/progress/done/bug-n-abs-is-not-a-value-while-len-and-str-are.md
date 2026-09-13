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
status: done
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


## RESOLVED 2026-09-13 (frankS) -- seven of the twelve, including the headline

`PyBuiltinValueHelper` maps a Python builtin NAME to its pylib helper for the
names that have no proc under their own spelling:

    abs -> pyabs_v   ascii -> pyascii_v   chr -> pychr_s   hash -> pyhash_v
    id  -> pyid_v    ord   -> pyord_v     round -> pyround1_v

`PyBuiltinValueNameAhead` holds the guard list once and `PyBuiltinIntrinsicValue`
acts on it, wired into BOTH doors into a callable value.

**THE SECOND DOOR IS THE PART THAT NEARLY SHIPPED HALF-DONE.** Wiring only
PyMakeFuncValue (assignment) made `f = abs; map(f, xs)` work while
`map(abs, xs)` -- this ticket's own headline repro -- still said
`undefined variable (abs)`, because an ARGUMENT reaches the NilPy factor chain
instead. PyUnboundStrMethodValue's header already records that both doors are
needed and says why; I read it after wiring the first one. The fixture asserts
both spellings for that reason.

**A DESIGN CONSTRAINT THIS TICKET DID NOT KNOW, AND IT DECIDES THE FIX.** The
obvious answer -- declare `function abs` in pylib -- is explicitly rejected
upstream, and the call side records the measurement: a later `uses` unit SHADOWS
a whole name rather than joining its overload set, so a pylib `format` stopped
existing the moment a program said `import json`, and *a builtin that vanishes
when you add an import is worse than a missing one*. Hence a table, not a
routine.

**AND THE BUG WAS WORSE THAN "A NAME IS MISSING".** Measured at 9393ab277:

    f = abs; print(f(-5))                  undefined variable (abs)  -- loud
    import math; f = abs; print(f(-5))     an EMPTY LINE, exit 0     -- silent
    import math; f = abs; print(f(-5.5))   SIGSEGV

An innocuous import turned the refusal into a wrong value and then a crash --
`abs` bound to lib/rtl/math's `Abs(x: Integer)`, declared first, called through
the Variant ABI. The CALL path has an explicit "own language first, and it
overrules import order" rule; the value path never got it. That is why the table
is consulted BEFORE FindProcExactCase: the ORDER is the fix, not decoration.
Its own fixture (`..._beats_an_rtl_routine`) keeps the FLOAT row, since an
int-only version passes on a build where `abs` still binds to Abs(Integer).

hash and id are asserted as CALL-form == VALUE-form, never against CPython's
numbers: both are implementation-defined in Python and ours legitimately differ
(CPython's `hash(7)` is 7, `id` is an address). Comparing them to CPython was my
first probe and it reported two false failures.

Positive control, both fixtures, under the pin: the first does not compile
(`undefined variable (ord)`), the second SIGSEGVs.

STILL OPEN, deliberately, and filed so it is rankable rather than buried here:
`divmod enumerate filter map zip` --
[[bug-n-the-lazy-builtin-constructors-and-divmod-are-still-not-values]]. The
four lazy constructors have several pylib entry points picked from the argument's
STATIC type, so a bare value has nothing to pick with; divmod looks mechanical
and is not (its user-class exit can alias). `min`/`max` are a different mechanism
again: [[bug-n-min-and-max-as-a-value-bind-to-the-two-argument-arm-in-the-wrong-unit]].

## Log
- 2026-09-13 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
