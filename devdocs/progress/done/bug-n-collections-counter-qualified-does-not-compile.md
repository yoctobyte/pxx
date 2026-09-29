---
track: N
prio: 20
type: bug
blocked-by: []
status: done
found-by: frankuser (2026-09-29)
tags: [nilpy, stdlib, collections]
summary: "`collections.Counter(x)` failed with \"no member Counter came of the qualifier collections\". It now compiles, selecting by the argument's type at run time: a str counts characters, a list, tuple, range or generator counts elements, and a mapping adds its values. Every Counter, whichever spelling built it, now prints as CPython does (`Counter({...})` in most_common order, `Counter()` when empty), and `type(c).__name__` is 'Counter'. Before this it printed as a plain dict."
owner: ""
---

# `collections.Counter(x)` does not compile

```python
import collections
collections.Counter("abca")   # v451: no member Counter came of the qualifier collections
```

## Cause

`collections` has a backing unit (lib/rtl/collections.pas), so the
qualifier resolved against it. PyStdlibCallProc's note under
`collections.deque` explains why Counter was left out: that table picks
an overload by arity, and Counter's 1-argument overloads differ only by
type.

## Fix

- `pycounter_new()` and `pycounter_new(const src: Variant)` in
  compiler/builtin/pylib.pas. The Variant overload uses
  `TPyDict.update(Variant)`, which already dispatches on str, dict and
  list. Other iterables are materialised through pylist_v first. Its own
  name, like pydeque_new, so that a program's `def Counter` is never what
  the qualified call reaches.
- `'collections.Counter'` maps to it in PyStdlibCallProc.
- `pydict_repr` prints a Counter-mode dict as CPython does, and the
  runtime type name of one is `Counter`. Every Makefile row of the 27
  tests that use Counter still passes; none of them printed a Counter's
  repr.

## Rows

test/test_nilpy_collections_counter_qualified.npy, with .expected from
CPython. Rows: x64 (ctrq26), i386 and wasm32. All three are red on the
compiler before the fix. A census probe (repr, str, and a range
argument, 3000 iterations) stays at 31 live.
