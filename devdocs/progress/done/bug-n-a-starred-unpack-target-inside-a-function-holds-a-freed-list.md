---
slug: bug-n-a-starred-unpack-target-inside-a-function-holds-a-freed-list
title: a starred unpack target inside a function holds a freed list
summary: >
  Every `a, *rest = xs` (and `*init, last`, `a, *mid, z`) inside a def stored
  a FREED list in the starred name: "RETAIN of a FREED object" under
  -dPXX_HEAP_DEBUG, silent heap corruption without it; module level was
  unaffected. The target was built as mark_list(slice(xs, ..)) -- the slice a
  fresh argument the call site releases after the call, and mark_list handing
  the same object back. FIXED 2026-10-03 (frankuser): pylist_slice_aslist /
  pyvar_slice_aslist mint the list in one call.
track: N
type: bug
prio: 85
owner: frankuser
status: done
---

## Measured 2026-10-03 (frankuser)

Found while adding str unpacking: `def f(w): first, *rest = w` failed under
HEAP_DEBUG, and so did the same shape over a list parameter, a list literal,
a tuple and a call result -- eight of eight shapes inside a def, none at
module level. Present at pin v452 and at 79b1a0bca7.

The mechanism is general, so it is worth stating for the next reader: an
argument that is a FRESH call result is released by the call site after the
call, on the assumption that the callee only read it. A pylib routine that
RETURNS ITS ARGUMENT (the mark_* family: pylist_mark_list/tuple/set/
frozenset, pyvar_mark_list) therefore hands back an object the caller is
about to free, whenever its argument is fresh. The set comprehension met the
same family earlier (bug-n-a-set-comprehension-over-releases-its-own-list).
The other mark_* consumers were checked by measurement, inside a def with
fresh arguments: set()/frozenset()/tuple() of a call result, of a generator
and of a range, set and tuple literals, frozenset of a set literal, list of a
set -- byte-identical to CPython under HEAP_DEBUG and flat under the census
(25 vs 8 live at 300/3000). The starred unpack was the one site that wrapped
a fresh slice.

The variant-source arm now also lists a str, range, deque or user iterable
before slicing (a slice of a str is a str, and a range had no slice), and
pylen_v answers a range and a deque, which `len(x)` on an unannotated
parameter and the unpack's count both use.

Test: test/test_nilpy_a_starred_unpack_target_inside_a_function_is_not_freed.npy
-- byte-identical to CPython under HEAP_DEBUG; census: 56 live after 3000
passes, keep control trips.
