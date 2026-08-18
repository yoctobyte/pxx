---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`c[k]` / `c[k] = v` on a subclass of `dict`/`list` goes straight to pylib's fetch/store and NEVER calls the subclass's `__getitem__` / `__setitem__`. The METHOD spelling (`c.__getitem__(k)`) dispatches correctly, and a plain user class declaring `__getitem__` dispatches correctly — it is only the builtin-subclass + operator combination. Silent wrong behaviour: the override runs zero times and nothing says so."
---

# A builtin subclass's subscript override is skipped by the operator form

- **Type:** bug — **Track N**. **Found:** 2026-08-18 by frank2-7e while landing
  [[bug-n-a-builtin-types-method-cannot-be-called-unbound]].
- **Measured at:** HEAD + that fix, self-host fixedpoint build. Differential
  against CPython 3.12.

## Repro

```python
class C(dict):
    def __getitem__(self, k):
        print("GET")
        return dict.__getitem__(self, k)
    def __setitem__(self, k, v):
        print("SET")
        dict.__setitem__(self, k, v)

c = C()
c["a"] = 1            # CPython: SET     — NilPy: (nothing)
print(c["a"])         # CPython: GET / 1 — NilPy: 1
c.__setitem__("b", 2) # CPython: SET     — NilPy: SET      <- the method spelling is fine
print(c.__getitem__("b"))
```

| | CPython | NilPy (HEAD) |
| --- | --- | --- |
| `c["a"] = 1` | `SET` | *silent* |
| `c["a"]` | `GET`, `1` | `1` |
| `c.__setitem__(...)` | `SET` | `SET` |

So the dispatch machinery works; the OPERATOR does not reach it.

## Why it is this shape

Same family as the feature that created it. Before
[[feature-nilpy-subclass-a-builtin-type]] a `dict` subclass was not a container
to the frontend at all, so the subscript went down the user-class arm — which
DOES look for `__getitem__` (`parser.inc`, the `FindUMeth(ci, '__getitem__')`
sites around the chained-base and subscript paths). Widening "is this a
container?" from identity to kind was correct and is what made `len`/`in`/slice
work, but it also handed these instances to the CONTAINER subscript path, which
lowers straight to pylib's `fetch`/`store` (dict) and `at`/`put` (list) and
never asks whether the receiver's class overrides the protocol.

This is the failure mode the ticket family keeps producing: **two mechanisms
serve one concept** (a user-class subscript arm that consults `__getitem__`, a
container arm that does not), so a value that is BOTH gets whichever arm is
tested first. `devdocs/dev/normalise-dont-special-case.md`.

## Shape of the fix

The container subscript arm should, when the static class of the receiver is a
USER subclass of a pylib container (not the container itself), look for an
override with `FindUMeth(ci, '__getitem__' / '__setitem__')` and call it,
falling through to the direct fetch/store otherwise. The base class itself must
keep the direct lowering — that is the whole point of `dict.__getitem__` being
aliased to `fetch` and is what stops an override from recursing into itself.
Grep the sibling before closing: `__delitem__`, `__len__`, `__contains__` and
`__iter__` are the same question and probably the same answer.

## Priority note

Filed at the same prio as its sibling rather than higher despite being a
silent-wrong-value bug, because the shapes that hit it are exactly the shapes
that could not COMPILE until today — so no working program has been getting a
wrong answer from it. That changes the moment a builtin subclass with an
overridden subscript lands in a real corpus (html5lib's `MethodDispatcher` is
precisely one), which is when this should be re-rated.

## Gate

`make compiler/pascal26` fixedpoint + `tools/gate.sh quick`, plus the repro
above matching CPython line for line, and
`test/test_nilpy_subclass_a_builtin_type.npy` /
`test/test_nilpy_unbound_builtin_method.npy` unchanged.
