---
slug: bug-n-a-param-or-local-named-like-a-pascal-intrinsic-is-answered-by-the-intrinsic
track: N
prio: 70
type: bug
status: done
owner: "claude-pxx"
blocked-by: []
tags: [nilpy, shadowing, silent-wrong-value]
summary: "MEASURED 2026-11-20 on 0ab6ae5f65 (also the 2026-11-11 compiler). `def p(pred, v): return pred(v)` called with a def answers v-1: Pascal's Pred, not the argument. The same for a LOCAL (`pred = f; pred(v)`). 19 names fail, as a parameter and as a local: pred succ lo hi odd trunc round swap length copy pos concat upcase ord frac int sizeof random val. Silent wrong values, a bogus TypeError, or a compile error. `round`, `int` and `ord` are Python builtins that CPython lets a local shadow. The 2026-11-10 fix of the sibling ticket covered module-level globals and the Abs/Sqr block only."
---

# A param or local named like a Pascal intrinsic is answered by the intrinsic

Found 2026-11-20 while narrowing `itertools.takewhile`: a local copy of it took
its predicate as `pred` and filtered every list to `[]`.

```python
def f(x):
    return 'f' + str(x)

def p_n(pred, v):
    return pred(v)          # pxx: 6     CPython: f7

def l_n(v):
    pred = f
    return pred(v)          # pxx: 6     CPython: f7

print(p_n(f, 7), l_n(7))
```

## The sweep (each name substituted for `pred`; CPython prints `f7 f7`)

| name | pxx |
|---|---|
| pred / succ | `6 6` / `8 8` |
| odd | `True True` |
| trunc, round, int, concat | `7 7` |
| frac | `0.0 0.0` |
| sizeof | `8 8` |
| upcase | empty line |
| lo, hi, swap, length, ord, random, val | TypeError: expected a number, got str |
| copy | compile error: one-argument Copy needs a dynamic array |
| pos | compile error: expected ',' before ')' |

Correct today: abs sqr chr sqrt exp ln sin high low inc dec halt exit delete
insert assigned.

## Where to start

[[bug-n-a-local-holding-a-callable-is-shadowed-by-a-pascal-intrinsic-at-the-call]]
(done 2026-11-10) fixed two doors for module-level globals: FindProcNilPyBound's
exact-spelling rule, and the Abs/Sqr block's "a local, param or this-module
global of the exact spelling exists" check. The working names above already go
through some such check. The failing ones reach a case-folded Pascal
routine or intrinsic arm that does not ask. The rule should be one predicate
asked once, before any intrinsic dispatch, not per name.

## Fixed 2026-11-20

Three doors in compiler/pyparser.inc. The trouble came from two predicates:
the name-keyed arms asked "does a user DEF shadow this?" (PyUserShadowsProc)
or "did a proc match?" (procIdx < 0), and never "does a variable bind it?".

1. **The intrinsic block of PyParseFactorCore** (Eof … Copy, ~25 arms) is
   wrapped in one guard, `pyNameBoundHere`: a local, parameter, or this-module
   global under the exact spelling skips every arm, and the name parses as the
   variable. This fixes pred succ odd upcase pos concat copy ord length.
2. **The earlier builtin arms** (len, the conversions, int, float, bool, str,
   open, setattr, trunc/round/frac/int, sizeof, next) now ask `PyShadowedHere`
   = PyUserShadowsProc or the new `PyNameBoundAsVarHere`.
3. **Return/local type inference** (PyInferExprType's bare-call arm): a call
   of a parameter or local of the def being scanned (PyNameBoundInDef) is
   typed Variant, not by case-folded FindProc. This fixes `return lo(v)`,
   `r = hi(v)`, swap, random, val.

Module order unchanged: `round(7.4)` before `round = f` is still the builtin.
Sweep of 52 names (Pascal intrinsics plus Python builtins), as a parameter
and as a local: all match CPython.
Test: test_nilpy_a_param_or_local_named_like_a_pascal_intrinsic_is_that_binding.py
(row shadowlocal26).
