---
slug: bug-n-next-on-an-untyped-value-binds-the-old-counter-overload
title: next() on an untyped value binds the old counter overload
summary: >
  `d = {"a": fin(3)}; next(d["a"])` answered 11, as did `K.ctr = gen(5);
  next(K.ctr)` and `next(self.c)`. An untyped argument went to overload
  resolution and bound pylib's `next(c: TPyCounter)` -- the old itertools.count
  advance -- reading a generator cursor as a counter. FIXED 2026-10-03
  (frankuser): PyNextOverListAhead routes every argument not statically a
  cursor/counter name or a direct generator call to the run-time pynext_v.
track: N
type: bug
prio: 40
owner: frankuser
status: done
---

## Measured 2026-10-03 (frankuser)

    def fin(a):
        yield a
        yield a + 1
    d = {"a": fin(3)}
    print(next(d["a"]))        # pxx at pin v452: 11    CPython: 3
    class K:
        ctr = None
    K.ctr = fin(5)
    print(next(K.ctr))         # 11
    g = [fin(3)]
    print(next(g[0]))          # 3 -- a list subscript happened to work

Same on main before this session. `list(d["a"])` was right; only next().

## Fix

PyNextOverListAhead (the token-level gate of the `next` arm) now claims every
argument except a NAME already typed TPyIter/TPyCounter and a direct call of
a stackless generator, which keep the TPyIter overload. pynext_v dispatches
on the run-time value (cursor, list, user __next__).

Census over subscript, attribute, default, list element, iter(list), a user
__next__ class, a fresh generator, a named one, iter(str): 3000/10000/30000
rounds live 28/42/42, flat. test_nilpy_classvar_counter (a dataclass field
factory calling next() on a ClassVar counter) is the existing fixture that
caught it once `count` became a generator.
