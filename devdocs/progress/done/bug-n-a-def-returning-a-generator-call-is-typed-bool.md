---
slug: bug-n-a-def-returning-a-generator-call-is-typed-bool
title: a def returning a generator call is typed bool
summary: >
  `def w(x): return g(x)` where g is a generator was typed BOOL: return-type
  inference read the generator proc's own RetType, which is the step routine's
  "produced one more" Boolean. The cursor came back as False, so `list(w(xs))`
  was [] and `type(w(xs))` said bool. Every itertools wrapper that hands its
  argument tuple to a private generator hit it. FIXED 2026-10-03 (frankuser):
  PyInferExprType answers TPyIter for a call of a stackless generator.
track: N
type: bug
prio: 40
owner: frankuser
status: done
---

## Measured 2026-10-03 (frankuser)

    def g(it):
        for e in it:
            yield e
    def w(x):
        return g(x)
    print(list(w([5, 6])))   # pxx at pin v452: []   CPython: [5, 6]
    print(type(w([5, 6])))   # pxx: <class 'bool'>

Same answer on main's compiler, so it predates this session's work. The AST
showed w's Result as tyBoolean initialised to 0.

## Fix

The call arm of PyInferExprType: a call whose proc is a stackless generator
answers tyClass with PyInferLastCi = TPyIter, ahead of the RetType read.

Test: test/test_nilpy_a_generator_outlives_its_caller_and_its_arguments.npy.

## Not fixed here

`type(g())` prints `<class '__main__.TPyIter'>` where CPython prints
`<class 'generator'>` -- the same on main before this, for map() too.
