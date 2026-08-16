---
track: N
prio: 50
type: bug
blocked-by: []
summary: "`dict.fromkeys(\"ab\")` SEGFAULTS — the stdlib call site builds the call by NAME and cannot resolve overloads by type, so a str landed in a TPyList parameter and the callee dereferenced a string as an object. The list forms are correct."
---

# `dict.fromkeys` of a str segfaults

Found 2026-08-16 by a `tools/pydiff.py` sweep over the builtin surface.

## Measured

```python
dict.fromkeys("ab", 0)     # CPython {'a': 0, 'b': 0}     pxx SIGSEGV
dict.fromkeys("ab")        # CPython {'a': None, 'b': None} pxx SIGSEGV
dict.fromkeys(["a", "b"])  # correct on both
```

Not exotic: `list(dict.fromkeys(xs))` is the standard order-preserving dedupe,
so deduping the characters of a word lands exactly here.

## Cause — the known population, not a new one

`PyParseStdlibCall` builds `pydict_fromkeys` **by name** and re-targets only by
ARITY. `pydict_fromkeys(l: TPyList)` therefore received a str and dereferenced
it as an object. This is the population
[[project_nilpy_byname_findproc_lowerings_are_the_unchecked_population]] names:
every by-name lowering that lands on a pylib routine with a `TPyList` parameter
is one wrong argument type away from a crash.

## Fix

Both overloads take a **Variant** and go through `pylist_v`, the one bridge that
turns any Python iterable (str, list, tuple, set, dict) into a `TPyList`, and
which already raises a TypeError naming the offending tag for anything else.
The cure is in the callee rather than a check at the call site, because a
call-site check would have to be repeated per site — and the point of the
population note is that there are many sites.

## Gate

`test/test_nilpy_dict_fromkeys_any_iterable.npy` — str, list, tuple, dict and
the deduping idiom, both arities, every value CPython's. The existing
`test_nilpy_dict_fromkeys.npy` is unchanged. `gate.sh quick` green.
