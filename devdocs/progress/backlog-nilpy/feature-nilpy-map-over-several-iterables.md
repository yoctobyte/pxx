---
track: N
prio: 40
type: feature
blocked-by: []
summary: "`map(f, xs, ys)` — CPython's N-iterable map — is a PARSE error (\"Expected: )\"). The map arm reads exactly two arguments, and the whole callback path below it (PyCallKey1, pymap_iter_i, pyiter_map_i) is one-argument by construction."
---

# `map` over several iterables

- **Type:** feature — **Track N** (`compiler/parser.inc` map arm,
  `compiler/builtin/pyeval.pas`).
- **Found:** 2026-08-16, by a CPython-differential sweep over builtins.

## Measured

```python
print(list(map(lambda x, y: x + y, [1, 2], [3, 4])))   # CPython: [4, 6]
print(list(map(a, [1, 2], [3, 4])))                    # a plain def, same
```

```
Expected: ), but got:  (Kind: 80, Line: 1)
```

A refusal, not a wrong answer — the diagnostic just does not name the cause.
Single-iterable `map`, `zip` of two lists, and a two-parameter lambda called
directly all work, so only the combination is missing.

## Why it is not a one-liner

The callback path is one-argument **all the way down**: `PyCallKey1(key, a0)`
dispatches the four callable representations, `pyiter_map_i` / `pymap_iter_i`
carry one upstream cursor, and `PyIterCallHook` is typed for that shape. N
iterables need either

1. a `PyCallKey2` beside `PyCallKey1` (each of the four representations gets a
   two-argument arm: bound pair, closure, bound compiled fn, bare code) plus a
   `pymap_iter2_i` carrying two cursors and stopping at the shorter — the
   direct route, and the one that generalises worst past two; or
2. lower `map(f, xs, ys)` to a **zip cursor** plus a splat call, which needs
   one new thing instead (a "call this callable with the elements of this
   tuple" entry, which `PyStarForwardCall` is already the frontend half of) and
   then covers three and four iterables for free.

(2) is the recommendation: one mechanism rather than one per arity, per
`devdocs/dev/normalise-dont-special-case.md`.

## Scope note

Low prio deliberately: `map(f, xs, ys)` is rare in real code next to the
single-iterable form, and the current behaviour is an honest refusal. It is
listed here so the sweep's finding is not lost.

## Gate

A `.npy` test whose `.expected` is CPython's output for two- and
three-iterable `map` with a lambda, a def and a bound method, plus the
short-iterable stop; `make compiler/pascal26` + `tools/gate.sh quick`.
