---
track: N
prio: 55
type: bug
summary: "set() returns a TPyList: elements are NOT deduplicated and it prints with list syntax, so set([1,2,2,3]) gives [1, 2, 2, 3] instead of {1, 2, 3} — silently wrong"
---

# `set()` is a list wearing the name

- **Type:** bug / missing type (NilPy) — **Track N**
- **Found:** 2026-08-02, sweeping iterable builtins vs CPython (the sweep that
  also found [[bug-nilpy-str-iterable-builtins-segfault-on-a-string-handle]]).
- **SILENT**, which is what makes this prio 55 rather than 30.

```python
print(set([1, 2, 2, 3]))    # CPython {1, 2, 3}   pxx [1, 2, 2, 3]
print(set("cab"))           # CPython {'c','b','a'}  pxx ['c', 'a', 'b']
```

`set` is mapped to the same `TPyList` construction as `list()` (see the type
inference arm in pyparser.inc that lumps `list`/`sorted`/`set`/`zip`/
`enumerate` together as TPyList). So it:

- does **not** deduplicate — the defining property of a set
- prints with `[...]` instead of `{...}`
- reports `type(x).__name__` as `list`
- has no `add` / `discard` / `|` / `&` / `-` / `<=`

Every one of those is a plausible wrong answer rather than a refusal. A program
that uses `set()` to dedupe — the single most common reason to reach for it —
gets silently wrong output.

## Why it is not just "add a dedupe"

Making `set()` dedupe on construction would fix the headline case and leave the
rest wrong (printing, type name, the operators, mutation via `.add`). That is
the trap: it converts a loud-ish oddity into a subtler one. `set` needs to be a
real type, the same conclusion item 5 of
[[bug-nilpy-sweep-gaps-pow-thousands-sep-stepped-slice]] reaches for `range`.

Sketch, following TPyDict rather than TPyList — a set is a dict without values,
and TPyDict already has the hashing and key comparison this needs:

- `TPySet` wrapping the dict's key machinery; `add`, `discard`, `remove`,
  `__contains__`, `__len__`
- printing as `{a, b, c}`, and `set()` (empty) as `set()`, which is what CPython
  prints — NOT `{}`, which is an empty dict
- the operators `|` `&` `-` `^` and the comparisons `<=` `>=`
- `set(iterable)` from a list, str, tuple or dict

Note CPython's set iteration order is unspecified but deterministic per build;
the tests should sort before printing rather than pinning an order.

## Interim option

If the full type is not being taken on now, the honest stopgap is to make
`set()` a **loud refusal** ("set() is not implemented; use a list or a dict"),
matching how other unimplemented constructs behave here. That is strictly
better than returning a list that is silently not a set — but it would break
any existing code calling `set()` for its list-ish behaviour, so check the
corpus first.

## Gate

A `.npy` diffed against CPython: dedupe from a list/str/tuple, membership,
`add`/`discard`, the four operators, subset comparisons, empty-set printing,
and `type(s).__name__`.
