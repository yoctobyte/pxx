---
track: N
prio: 55
type: bug
summary: "set() returns a TPyList: elements are NOT deduplicated and it prints with list syntax, so set([1,2,2,3]) gives [1, 2, 2, 3] instead of {1, 2, 3} — silently wrong"
blocked-by: [decide-nilpy-set-as-a-distinct-type-or-a-list]
status: done
owner: claude-N
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

## 2026-08-08 — RE-MEASURED: the summary is STALE, and most of this is FIXED

The kind tag from
[[bug-nilpy-list-tuple-and-set-are-indistinguishable-to-isinstance]] landed and
closed most of this ticket. Measured at HEAD:

    set([1, 2, 2, 3])        -> {1, 2, 3}     correct, DEDUPLICATED
    len / sorted / {1,2,2,3} -> correct
    type(s).__name__         -> 'set'         correct
    isinstance(s, set)       -> True          correct

So *"elements are NOT deduplicated and it prints with list syntax"* — the
summary — is no longer true and should not be trusted by whoever picks this up.

**What is actually left:** the kind does not survive set OPERATORS.

    {1, 2, 3} - {2}    pxx [1, 3]      CPython {1, 3}

The elements are right; the RESULT row is created without the set kind, so it
displays as a list. Look at whatever builds the difference result and have it
mark the row with `pylist_mark_set` the way the three creation sites already do.
Check `|`, `&` and `^` at the same time — if the result-construction path is
shared they are all wrong together, and that is the thing to fix rather than
`-` alone.

Its sibling residue, `[1] - [2]` computing instead of raising, is
[[bug-nilpy-same-kind-undefined-operators-still-compute]] — now decidable from
the kinds.

## RESOLVED 2026-08-08 — closed with its sibling

The set operators built a bare `TPyList`, which is a LIST by default, so
`{1,2,3} - {2}` computed the right elements and printed `[1, 3]`. They now stamp
`PYSEQ_SET`, and a set COMPREHENSION — a third producer that never carried the
tag either — goes through the same new `PyMarkAsSet` helper as `set()` and the
`{a, b}` literal.

Done as part of [[bug-nilpy-same-kind-undefined-operators-still-compute]]: the
same four functions are where both the missing tag and the missing operand check
live, and fixing one without the other would have left a set that prints right
but still accepts a list.

Covered in `test/test_nilpy_set_ops.npy` (repr, `type().__name__`,
`isinstance(x, set)`, and all three producing forms).

## Log
- 2026-08-08 — resolved, commit PENDING-COMMIT.
