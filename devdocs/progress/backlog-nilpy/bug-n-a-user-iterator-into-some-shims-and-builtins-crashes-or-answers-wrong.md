---
slug: bug-n-a-user-iterator-into-some-shims-and-builtins-crashes-or-answers-wrong
track: N
prio: 45
type: bug
status: new
owner: ""
blocked-by: []
summary: "NARROWED 2026-11-20: what remains is a user class named like a pylib function (Counter) typed as that function's result at a call site seen before the class is registered -- see feature-n-register-every-module-s-classes-before-any-module-s-methods-are-typed. Originally: MEASURED 2026-11-20 on 0ab6ae5f65. A user class with __iter__/__next__ (Counter below) passed to: itertools.islice(c, 3) and itertools.takewhile(pred, c) -> SEGFAULT; collections.Counter(c) -> prints nothing (CPython Counter({1: 1, 2: 1, 3: 1})); bytes(c) / bytearray(c) -> TypeError 'cannot convert this value to bytes without an encoding'. itertools.chain(c, c), set, frozenset, dict.fromkeys, deque, heapq.nlargest are correct."
---

# A user iterator into some shims and builtins crashes or answers wrong

Found while resolving
[[bug-n-pyfixiterableargs-is-inert-its-own-test-passes-with-it-disabled]].

```python
import itertools, collections
class Counter:
    def __init__(self, n):
        self.n = n
        self.i = 0
    def __iter__(self):
        return self
    def __next__(self):
        if self.i >= self.n:
            raise StopIteration
        self.i += 1
        return self.i

print(list(itertools.islice(Counter(9), 3)))                   # segfault; CPython [1, 2, 3]
print(list(itertools.takewhile(lambda x: x < 3, Counter(9))))  # segfault; CPython [1, 2]
print(collections.Counter(Counter(3)))                         # empty line
print(bytes(Counter(3)))                                       # TypeError; CPython b'\x01\x02\x03'
```

## What is known

- **islice/takewhile:** the shim's `iterable` parameter (unannotated, in
  lib/rtl/mimic_itertools.py) reaches PyFixIterableArgs as tyClass with rec
  id 0, so no arm drains it.
  - The same def written in the user's own module works:
    `def g(it): for x in it: yield x` gives `[1, 2, 3]`.
  - `chain`, which iterates the elements of its `*iterables` tuple, works.
  - So the defect is in how a separately compiled shim types an unannotated
    parameter iterated directly, not in generators over user iterators.
- **bytes/bytearray/collections.Counter:** these match a Variant overload,
  whose run-time conversion does not walk a user iterator the way
  list/sorted/sum's already do.

## Progress 2026-11-20

- **bytes/bytearray: fixed.** The Variant overloads in compiler/builtin/pylib.pas
  gained a `PyUserObjIterable` arm that drains through `pyseq_of_obj`. Test:
  test_nilpy_bytes_of_a_user_iterable.py.
- **collections.Counter: correct.** It was a name clash in the probe, not
  iteration: the user class was ALSO named `Counter`. `collections.Counter(Ctr(3))`
  is right. What remains is narrower and still a segfault. On 0ab6ae5f65 and
  earlier:
  ```python
  import collections
  class Counter:            # __init__/__iter__/__next__ as above
      ...
  w = collections.Counter(Counter(3))   # segfault
  ```
  The same line is correct if any earlier statement constructs `Counter(...)`.
  The qualified call does not pass through PyFixIterableArgs.
- **islice/takewhile: still open.** The same generators written in the user's
  module work over a user iterator. So the shim compiled as its own unit is
  what differs: its unannotated `iterable` arrives tyClass with rec 0
  (PyParamTypeFromSites typing it from the user's call site).
- While narrowing takewhile, I found that a parameter or local named `pred`
  answers Pascal's Pred. Filed separately:
  [[bug-n-a-param-or-local-named-like-a-pascal-intrinsic-is-answered-by-the-intrinsic]].

## Narrowed 2026-11-20 (later): every remaining failure is a NAME CLASH

All of them were probed with a user class named `Counter`. Renamed (`Ctr`),
`itertools.islice`, `takewhile` and `chain` over a user iterator match
CPython, and so does `collections.Counter(Ctr(3))`.

With the class named `Counter`, PXXDBG=n.psites shows the shim's parameter
typed from the user's call site as pylib's `Counter()` result:

    PXXDBG n.psites islice.iterable mode=2 sites=1 gaveup=0 tk=6 cls=TPyDict

The shim (mimic_itertools) is typed before the user module's classes are
registered. So at that site `Counter(9)` is not yet the user's class, and the
token-level inference (PyInferExprType's call arm) answers with the only
`Counter` it knows. Then the Ctr object is read through TPyDict's layout:
segfault.

This is an instance of
[[feature-n-register-every-module-s-classes-before-any-module-s-methods-are-typed]]
(prio 75): sites are seen across the closure, classes one module at a time.
What this ticket adds there is the shape: a user class named like a pylib
FUNCTION (Counter, and by the same token any other) typed as that function's
result at a site seen early.

Repro, minimal:

```python
import itertools
class Counter:
    def __init__(self, n):
        self.n = n
        self.i = 0
    def __iter__(self):
        return self
    def __next__(self):
        if self.i >= self.n:
            raise StopIteration
        self.i += 1
        return self.i
print(list(itertools.islice(Counter(9), 3)))   # segfault; CPython [1, 2, 3]
```
