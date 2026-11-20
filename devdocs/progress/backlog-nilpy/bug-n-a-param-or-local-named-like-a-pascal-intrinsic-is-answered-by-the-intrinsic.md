---
slug: bug-n-a-param-or-local-named-like-a-pascal-intrinsic-is-answered-by-the-intrinsic
track: N
prio: 70
type: bug
status: new
owner: ""
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
