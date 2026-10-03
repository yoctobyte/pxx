---
slug: feature-n-collections-defaultdict-and-ordereddict
title: collections.defaultdict and collections.OrderedDict
summary: >
  Neither existed: `from collections import defaultdict` and
  `collections.OrderedDict()` were "undefined variable" / "no member ... came
  of the qualifier collections". DONE 2026-10-03 (frankuser): both are TPyDict
  MODES, the way Counter already is, reached by every spelling (qualified,
  from-import, aliased). Writing them closed three adjacent defects: an
  aliased compiler-provided member with a capital letter bound nothing, a
  builtin type held as a value leaked what it built, and `f = dict; f(d)`
  aliased d instead of copying it.
track: N
type: feature
prio: 40
owner: frankuser
status: done
---

## What is there

- `defaultdict(factory[, mapping])`: a missing key on a subscript READ calls
  the factory, stores and answers the value. get(), `in`, pop() and
  setdefault() do not call it, as in CPython (only `__getitem__` consults
  `__missing__`). Any callable value works -- `int`, `list`, `set`, `str`,
  `dict`, a def, a lambda, a class -- through a new zero-argument hook
  (PyCall0Hook = pyeval's pyvar_callv0). `defaultdict()` / `defaultdict(None)`
  raise KeyError like a dict. copy() keeps the factory; dict(d) does not.
  repr is CPython's `defaultdict(<class 'list'>, {...})`; type name
  `defaultdict`; isinstance(d, dict) is True.
- `OrderedDict([src])`: a dict already keeps insertion order, so the mode
  changes the type name and repr (`OrderedDict({...})`, 3.12+ format) and adds
  `move_to_end(key, last=True)` and `popitem(last=True)`, which are dict
  methods and harmless on any dict. move_to_end(last=False) is O(n), where
  CPython's linked list is O(1); an LRU moves to the END, the cheap direction.
- Equality with a plain dict is order-insensitive, as CPython's
  `OrderedDict == dict` is. OrderedDict-vs-OrderedDict order-SENSITIVE
  equality is NOT implemented (it compares as dicts).

## Adjacent defects closed

1. **An aliased compiler-provided member with a capital letter bound
   nothing.** `from collections import Counter as C` -> `undefined variable
   (C)`, while `deque as dq` worked. PyStdAliasRecord stored the member
   LOWERCASED and the call table is matched as spelled, so
   `collections.counter` resolved nothing. Stored as spelled now; the two
   value-table readers (PyIsSysStreamAhead, PyParseSysStream) fold it
   themselves, keeping `from os import SEEK_SET` working.
2. **A builtin type held as a value leaked what it built.** pybtype_call0
   (`f = list; f()`) and pybtype_call1 (`f("ab")`, `f([1, 2])`) boxed the new
   object with PyObjAsVar, which takes its own reference, and never dropped
   the construction's: 1.8 blocks per call for list/set, 3.8 for dict,
   -dPXX_ALLOC_CENSUS 1000 rounds. Flat now (live 6-10).
3. **`f = dict; f(d)` returned d itself**, not a copy (pydict_v hands back
   the argument's own dict). It copies now, and drops Counter/defaultdict/
   OrderedDict modes as `dict(x)` does.
4. `set()`, `tuple()`, `frozenset()` through a type held as a value raised
   "not supported yet"; they build the empty value now.

## Measured

Census, -dPXX_ALLOC_CENSUS, the full defaultdict exercise in a loop:
100/1000/3000 rounds live 109/134/133. The OrderedDict exercise including an
LRU loop: 19/16/48. A discarded `d.popitem(last=False)` first leaked two
blocks per call because the overload forwarded to popitem() and so was not
classified as returning what it minted (ClassifyProcResultFresh); it builds
its own tuple now, live 10.

Test: test/test_nilpy_collections_defaultdict_and_ordereddict.npy, byte-
identical to CPython 3.14 under -dPXX_HEAP_DEBUG and on i386.
