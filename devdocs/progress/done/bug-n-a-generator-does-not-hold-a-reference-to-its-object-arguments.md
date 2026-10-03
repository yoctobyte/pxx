---
slug: bug-n-a-generator-does-not-hold-a-reference-to-its-object-arguments
title: a generator does not hold a reference to its object arguments
summary: >
  A class-typed (list, dict, instance) or str argument was stored in the
  generator instance's slot as a raw word with no reference of its own. When
  the caller's temporary died -- `return _comb(list(it), r)`, a local list of
  the def that returned the generator, `g(a + "!")` -- the generator read a
  freed block: itertools.combinations/product answered [], a str argument
  yielded whatever reused the block. FIXED 2026-10-03 (frankuser): GenSeedArg
  retains (PXXObjRetain / PXXStrIncRef) and SLReleaseLocalsAtDone drops it at
  done or close.
track: N
type: bug
prio: 40
owner: frankuser
status: done
---

## Measured 2026-10-03 (frankuser)

    def g(xs, k):
        for x in xs:
            yield x + k
    def wrap(it):
        return g(list(it), 1)
    def gs(s):
        s = s + "+"
        yield s
    def wrap_str(a):
        return gs(a + "!")
    print(list(wrap((7, 8))))       # pxx: []        CPython: [8, 9]
    print(list(wrap_str("ab")))     # pxx: ['00']    CPython: ['ab!+']

Variant parameters were already safe: they ride a pycell_new cell assigned
through the managed-variant path, and pycell_free_at releases it at done.
Class and str parameters had no equivalent -- the done path walks skLocal
symbols only, so a parameter slot was never released, and nothing retained it.

## Fix

- GenSeedArg (both seeding paths: the for-in desugar and the generator value
  build): in NilPy, a tyClass slot is retained and a tyAnsiString slot
  inc-ref'd after the store.
- SLReleaseLocalsAtDone: the matching release for each non-ref class/str
  parameter. A parameter REASSIGNED in the body (`s = s + "+"`) is released at
  its current value, which the NilPy store already balanced.

Census, -dPXX_ALLOC_CENSUS: a mix of for-in over g(fresh list), break, a
named list, sum(), a wrapper returning the generator, next() on a stepped
generator, a generator never started, and class-instance arguments --
10/100/1000 rounds live 15/12/8. String arguments 10/100/1000 live 26/16/31.
Main's compiler on the same program raises TypeError (it read freed memory).

Test: test/test_nilpy_a_generator_outlives_its_caller_and_its_arguments.npy.

## A third seeding site, found by the HD sweep

PyEmitGeneratorIterCursor (the synthesized `__pxx_gen_iter__` that makes a
class with a generator `__iter__` iterable at run time) stored `self` with a
raw SlSet. Once done/close released class parameters, that store was released
without having been retained: test_nilpy_a_generator_closed_early_or_exhausted_does_not_leak
reported "RELEASE of a FREED object" twice, inside a def only. It now seeds
through GenSeedArg like the other two sites; the test is clean and its census
flat (live 83/85 at 100/1000 passes).
