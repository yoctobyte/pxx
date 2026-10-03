---
slug: bug-n-a-for-over-a-variant-drains-a-generator-before-the-first-iteration
title: a for over a variant drains a generator before the first iteration
summary: >
  `def take(it, k): for v in it: ... break` called with an infinite generator
  hung: the for-in over an untyped (variant) container unboxed it through
  pylist_v, which DRAINS whatever the variant holds. FIXED 2026-10-03
  (frankuser): the variant arm walks a cursor (pyiter_v), which iterates a list
  or str in place and hands an iterator back as itself.
track: N
type: bug
prio: 40
owner: frankuser
status: done
---

## Measured 2026-10-03 (frankuser)

    def naturals():
        n = 0
        while True:
            yield n
            n += 1
    def take(it, k):
        out = []
        for v in it:
            out.append(v)
            if len(out) >= k:
                break
        return out
    print(take(naturals(), 3))      # pxx at pin v452: hangs. CPython: [0, 1, 2]

The AST showed the loop's container as a call returning TPyList over the
variant parameter: pylist_v -> pyseq_of_obj, i.e. list(it). A finite generator
"worked" only because draining it first happens to give the same values.

## Fix

PyParseForIn's variant/unknown arm now builds `pyiter_v(<container>)` and
takes the cursor (has/take) protocol the map()/generator loops already use.
pylist_v stays as the fallback only when TPyIter is not loaded.

Checked against CPython on 23 shapes through an untyped parameter: list,
tuple, str, dict (keys), set, range, bytes, a user `__iter__` class, a
generator, a map cursor, an empty list, two-name unpack, `.items()`,
enumerate over a list and over a generator, nested loops over the same list
and over the same generator, a list appended to during the loop, early
`return` from inside the loop, a TypeError on an int, and a generator
resumed across three consumers. Census over 10/100/1000 rounds: live
118/109/113, flat.

Test: test/test_nilpy_a_generator_outlives_its_caller_and_its_arguments.npy.

## The two kind chains, found by the HD sweep

pylist_v reaches pyseq_of_obj, which knows a DEQUE; pyiter_v did not, so a
deque returned from a def and walked with `for x in d` became "TypeError:
expected an iterable, got object" (test_nilpy_a_deque_releases_its_old_buffer_and_indexes_through_a_variant).
pyiter_v now ends with a fallback to pyseq_of_obj, adopting the fresh list,
so a kind added to that chain is iterable by both routes.
