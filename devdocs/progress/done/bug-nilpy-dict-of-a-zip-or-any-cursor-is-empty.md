---
track: N
prio: 40
type: bug
blocked-by: []
commit: PENDING-COMMIT
summary: "`dict(zip(names, values))` — the commonest way to build a dict — answered {} silently: zip hands back a cursor, the call boxed it, and dict's only variant arm asked 'is it a TPyDict'. Every non-dict iterable of pairs answered empty."
---

# `dict(zip(...))` is empty

```python
print(dict(zip("ab", [1, 2])))       # CPython {'a': 1, 'b': 2}   pxx {}
print(dict(zip(["a","b"], [1, 2])))  # CPython {'a': 1, 'b': 2}   pxx {}
```

Silent. `list(zip("ab", [1,2]))` is correct, `dict([("a",1),("b",2)])` is
correct, and the `for k, v in zip(...)` loop is correct — so the pairs exist and
the constructor is the only thing that loses them.

Found 2026-08-15 by a CPython differential sweep (`tools/pydiff.py`), one probe
after [[bug-nilpy-builtins-over-a-user-iterable-answer-empty]] — the same
defect one container over, which is exactly what that ticket's "one concept, N
copies" note predicts.

## Cause

`dict(const v: Variant)` had ONE arm:

```pascal
if o is TPyDict then begin Result := dict(TPyDict(o)); Exit; end;
...
Result := TPyDict.Create;   { None / non-mapping }
```

Python's `dict()` takes either a mapping OR an iterable of (key, value) pairs.
`zip` answers a cursor (`TPyIter`), there was no overload for one, so the call
boxed it into a variant, reached the arm above, matched nothing and fell into
the empty-dict fallback. The pair walk itself already existed —
`dict(TPyList)` is `TPyDict.update`.

## Fix

The variant arm now routes any non-dict object through `pyseq_of_obj` (pylib's
one object-to-sequence chain, introduced by the ticket above) and hands the
result to `dict(TPyList)`. A `dict(it: TPyIter)` overload was added beside it so
a statically-typed cursor never has to be boxed to find its meaning.

That covers `zip`, `map`, `filter`, `enumerate`, `iter(...)`, a range, and a
user class with `__iter__`, because it is the same chain every other container
constructor now uses.

Not changed: `dict(5)` still answers `{}` where CPython raises TypeError. That
fallback predates this and is its own (unfiled) divergence — worth a ticket if
the empty answer ever hides something, but widening it here would have been an
unrelated behaviour change in the same commit.

## Gate

`test/test_nilpy_dict_over_any_iterable.npy` (+`.expected`, in the Makefile),
byte-identical to CPython: `dict(zip(...))` in three spellings, `map`, `filter`,
`enumerate`, an explicit `iter(...)`, a user iterable, a list of pairs, a list
of two-element lists, `dict(**kwargs)`, `dict(<dict>)`, and the empty cases.
`gate.sh quick` GREEN. Pinned (the change is in `compiler/builtin/**`).
