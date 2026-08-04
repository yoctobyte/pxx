---
track: N
prio: 40
type: bug
summary: "list.append/extend/sort/reverse return Self, so `x = l.sort()` yields the LIST where Python yields None — silent, and the return is load-bearing for the comprehension desugar"
status: done
owner: claude-AN
---

# `list.append`/`extend`/`sort`/`reverse` return the list, not None

- **Type:** bug / divergence (NilPy) — **Track N**
- **Found:** 2026-08-02, in the mutator sweep that produced
  [[bug-nilpy-inplace-mutators-do-not-return-none]] (the GARBAGE half, fixed in
  `c063cddb3`).

```python
l = [3, 1, 2]
print(l.sort())       # CPython None    pxx [1, 2, 3]
print(l.reverse())    # CPython None    pxx [2, 1, 3]
print(l.extend([7]))  # CPython None    pxx [3, 1, 2, 7]
print(l.append(9))    # CPython None    pxx the list
```

These are declared `function append(...): TPyList` etc. and return Self. Unlike
the procedures that were just fixed, this is a **defined** value, not garbage —
which is why it is prio 40 and was split out rather than fixed in the same pass.

## Why it matters anyway

`sorted_l = l.sort()` is one of the most common Python mistakes there is. In
CPython it fails loudly and immediately (`None` has no methods, prints as None);
here it **silently appears to work**, so the program behaves differently on the
two implementations and the NilPy run is the one that looks correct. Code
written and tested against NilPy would then break under CPython — the wrong
direction for a dialect that is trying to be a Python.

The falsiness difference is the sharper edge: `if l.append(x):` is True here and
False in CPython.

## Why it is not a one-line change

**The return value is load-bearing.** The comprehension desugar builds
`target.append(EXPR)` and the statement lowering uses the resulting node; the
`reverse` declaration says outright it "returns Self so the statement lowering
can use it as a value". So flipping these to `Variant`/None the way the
procedures were flipped will break those paths.

The shape of the fix is to separate the two audiences:

1. keep an internal Self-returning entry point for the desugars
   (`pylist_append_self` or similar, not exposed under the Python name), and
2. give the PYTHON-visible method the None result.

Check every frontend site that builds one of these calls and uses the node as a
value before changing the signature — `grep` for `'append'` in pyparser.inc is
the starting point, and the comprehension path is the one that matters.

## Gate

A `.npy` diffed against CPython asserting `l.sort() is None` and friends (via
`is None`, not printing), that the mutation still happens in statement position,
and that list comprehensions, nested comprehensions and dict comprehensions —
which all go through the append desugar — are unchanged.


## Resolved 2026-08-04 — the split the ticket described, at one name

The ticket's instruction was right: keep a Self-returning entry point for the
desugars and give the Python-visible method the None result. What the survey it
asked for showed is that **only ONE of the four needed the split.**

`grep` for the frontend sites, as the ticket suggested:

| site | uses the result as |
| --- | --- |
| list LITERAL desugar (2 sites) | **a chained VALUE** — `Create.append(a).append(b)…` |
| comprehension / dict-comprehension body | a statement |
| `*` unpack into a literal (`extend`) | a hoisted statement |
| `+=` on a list (`extend`, 3 sites) | the statement node |

So `sort`, `reverse` and `extend` simply return `pynone` now — nothing needed
their Self result. Only `append` is split: the Self-returning body is renamed
`append_self` and the two literal-desugar sites call that, while the
Python-visible `append` delegates and returns None.

Verified there is no chained use inside the runtime either — the `:=` hits in
`pylib`/`pyeval` are all `for … do X.append(…)` loop headers, not assignments of
the result.

### Verified

`test/test_nilpy_list_mutators_return_none.npy`, wired into `make test-nilpy`:
all four asserted with **`is None`** rather than by printing (so the test cannot
pass on a coincidence of how None renders), the mutation still visible after
each, `if l.append(x):` taking the FALSE branch — the falsiness edge the ticket
called the sharper one — and list literals, a comprehension, a nested
comprehension, a dict comprehension, `+=` and `sorted()` all unchanged. Diffed
against CPython, identical. `tools/gate.sh quick` GREEN, self-host
byte-identical.

## Log
- 2026-08-04 — resolved.
- 2026-08-04 — resolved, commit PENDING-COMMIT.
