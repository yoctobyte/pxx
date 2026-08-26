---
track: N
prio: 70
type: bug
blocked-by: []
summary: "`obj[k] += v` on any class that reaches subscripting through `__getitem__`/`__setitem__` is a named compile-time refusal — `augmented assignment to a __getitem__/__setitem__ subscript is not supported`. Ordinary Python, and the counting idiom (`counts[k] += 1`) is the single most common thing a dict-like class is written for. The default-indexed-property arm beside it already desugars the augmented form; only the dunder arm does not."
---

# An augmented subscript on a `__getitem__` class is refused

- **Type:** bug — **Track N**. **Found:** 2026-08-18 by frank2-7e while landing
  [[bug-n-a-builtin-subclass-subscript-operator-skips-the-override]].
- **Pre-existing**, not introduced by that fix — it is the dunder arm's own
  documented limitation (`compiler/parser.inc`, "Single-key subscript only (no
  `obj[a, b]` tuple key, no `+=` augmented form)"). What changed is its REACH:
  a builtin subclass now takes that arm too, so the refusal is visible to a
  shape that previously compiled (and silently called the base).

## Repro

```python
class Counts(dict):
    def __getitem__(self, k):
        return dict.__getitem__(self, k)
    def __setitem__(self, k, v):
        dict.__setitem__(self, k, v)

c = Counts()
c["a"] = 0
c["a"] += 1        # error: augmented assignment to a __getitem__/__setitem__
                   #        subscript is not supported
```

A plain user class with the same two methods and no base has always had this.

## Why it is a compile error and not a wrong value

Deliberate, and the reason it is filed at 45 rather than higher: the sibling
fix routes an augmented subscript to this arm **when either dunder is
declared**, so the alternative on the table was `c[k] += 1` silently calling
pylib's `store()` while the plain `c[k]` next to it called the override. A
named refusal beats a silent divergence, so the refusal is what landed. This
ticket is to finish the job, not to undo it.

## Shape of the fix

The default-indexed-property arm immediately above already does exactly this
desugar and is the model: `PyEvalOnce` the base and the key (Python evaluates
each once — `e[key()] += 1` calling `key()` twice was
`bug-nilpy-augmented-subscript-evaluates-its-index-twice`), build the read with
`PyCallMeth1(mci, '__getitem__', base, key)`, the binop with `PyAugBinTok` (or
`PyMakePow` for `**=`, which has no binary token — the third shape that keeps
needing its own arm), and the write with `PyCallMeth2(mci, '__setitem__', ...)`.
Requires BOTH members; a class declaring only one should keep a named error
saying which is missing.

While there: the same arm refuses a TUPLE key (`obj[a, b]`). Different feature,
same comment block — decide whether it goes in the same change or gets its own
ticket, but do not let the sibling sit unlooked-at
(`devdocs/dev/normalise-dont-special-case.md`).

## Gate

`make compiler/pascal26` fixedpoint + `tools/gate.sh quick`, plus the repro
above matching CPython, `**=` covered, the index expression evaluated exactly
once, and `test/test_nilpy_builtin_subclass_dunder_dispatch.npy` /
`test/test_nilpy_subclass_a_builtin_type.npy` unchanged.
