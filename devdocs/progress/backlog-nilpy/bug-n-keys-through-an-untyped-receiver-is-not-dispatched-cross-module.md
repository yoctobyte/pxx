---
slug: bug-n-keys-through-an-untyped-receiver-is-not-dispatched-cross-module
track: N
prio: 55
type: bug
status: backlog
blocked-by: []
summary: "`other.keys()` on an untyped parameter is not dispatched on the receiver when the call sits in an IMPORTED module: it either falls through to the dict-view builtin or binds to a `keys()` the callee's module declares, and a foreign object reaching a self-iterating `keys()` segfaults. Reopens bug-n-a-user-classs-keys-items-values-is-dispatched-as-a-dict-view, which was closed on the single-module case. Found by Track B reverting a workaround the closed ticket had unblocked."
---

# `keys()` through an untyped receiver is not dispatched, across a module edge

- **Track N** (Nil-Python frontend — the method-dispatch path for
  `keys`/`items`/`values` on a dynamically-typed receiver).
- Found 2026-08-27 by Track B (frankB) while reverting the
  `mimic_collections_abc.update()` workaround that
  [[bug-n-hasattr-through-an-untyped-parameter-is-always-false]] had unblocked.
  Verified against pin **v389** (`325b4479070a`).

## This REOPENS a closed ticket

[[bug-n-a-user-classs-keys-items-values-is-dispatched-as-a-dict-view]] is in
`done/`, and every probe in this session confirms it is fixed **within one
compilation unit**. It is not fixed when the call and the class are separated by
a module edge. The closing evidence was single-module, which is why it read as
green.

## Repro — two files, 22 lines

`helper.py`:

```python
class Mapping:
    def __iter__(self):
        raise NotImplementedError('abstract')
    def __getitem__(self, key):
        raise KeyError(key)
    def keys(self):              # a self-iterating keys(), as an ABC's mixin is
        out = []
        for k in self:
            out.append(k)
        return out

class Caller:
    def take_keys(self, other):  # `other` is untyped
        out = []
        for k in other.keys():
            out.append(k)
        return out
```

`main.npy`:

```python
from helper import Caller

class Duck:
    def keys(self):
        return ["d1"]

print(Caller().take_keys(Duck()))   # CPython: ['d1']   pxx: SIGSEGV
```

```
$ pxx -Fu. main.npy x && ./x
Segmentation fault (core dumped)
$ python3 main.npy
['d1']
```

## Two distinct wrong outcomes, one cause

The call is resolved statically at the call site instead of dispatching on the
receiver. What that produces depends on what the *callee's* module can see:

| the calling module declares | result |
| --- | --- |
| no class with `keys()` | **SIGSEGV** — falls through to the dict-view builtin, which reads a non-dict |
| a `keys()` that iterates `self` (an ABC mixin's shape) | **SIGSEGV** — the foreign object reaches that body and `for k in self` faults on an object with no `__iter__` |
| a `keys()` that returns a plain list | **correct** — dispatches to the receiver's own |

The third row is why isolated probes pass: give the module any simple `keys()`
and the bug hides. Adding an unrelated, never-instantiated class with a
one-line `keys()` to `helper.py` above makes the repro print `['d1']`.

`items()` and `values()` are named in the original ticket and are presumably the
same path; only `keys()` was measured here.

No spelling of the call escapes it — `ks = other.keys()`, `list(other.keys())`
all segfault identically, and `getattr(other, 'keys')()` fails differently
(`TypeError: expected a str, a list or a dict, got int`), which is its own
evidence that the receiver is not reaching the resolver.

## Why it matters beyond the repro

It is the sole remaining blocker on `MutableMapping.update()` accepting a
duck-typed mapping, which is CPython's documented contract for it:

```python
elif hasattr(other, "keys"):      # hasattr is FIXED as of v389
    for k in other.keys():        # this line is the one that faults
        self[k] = other[k]
```

`hasattr(other, "keys")` now answers correctly through an untyped parameter, so
the discrimination CPython uses is available and the branch it selects is not.
Track B has therefore **kept** its `isinstance(other, dict) or isinstance(other,
Mapping)` workaround — safe only because both of its branches iterate `other`
directly and neither calls `keys()` — and re-pointed the registry entry in
`devdocs/dev/track-b-workarounds.md` at this ticket.

## Gate

The two-file repro prints `['d1']`, and `mimic_collections_abc.update()` reverts
to CPython's three-branch form (`isinstance` → `hasattr` → pairs) with
`test/lib_mimic_collections_abc.npy` gaining a duck-typed `update()` row.
