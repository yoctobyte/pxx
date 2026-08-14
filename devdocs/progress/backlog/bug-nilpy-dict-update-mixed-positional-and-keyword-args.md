---
track: N
prio: 35
type: bug
blocked-by: []
summary: "`d.update(other, a=1)` is a clean compile error (`unexpected token c`) — CPython accepts a mapping followed by keywords. The keywords-are-KEYS builder takes over only when the argument list STARTS with a keyword, so a positional first argument leaves the keyword run unhandled. Same for dict(other, a=1)."
---

# `d.update(other, a=1)` — a positional argument before the keyword run

Residual of [[bug-nilpy-dict-update-keyword-args-segfault-on-two-keywords]],
whose two headline symptoms (the two-keyword segfault and the `**` refusal) are
fixed and tested. This is the row of its gate that was never built.

```python
h = {"a": 0}
h.update({"b": 1}, c=2)     # CPython {'a': 0, 'b': 1, 'c': 2}
                            # pxx      error: unexpected token  near: b >>> c
d = dict({"x": 1}, y=2)     # same shape through the other callee
```

**Not a wrong value — a clean refusal.** That is why it is priced below the
segfault it came from.

## Cause

`PyKeywordsAreKeys(mpi) and PyDictKwArgsAhead` is the guard at all five
argument loops, and `PyDictKwArgsAhead` asks whether the CURRENT token starts a
keyword or a `**`. With a positional first argument it is False, so the ordinary
argument path parses that expression and then meets `c=2` with nothing to do
about it.

## Two lowerings, and the choice is not obvious

1. **Seed the builder.** Give `PyBuildKeywordDict` an already-parsed expression
   to `pydict_merge` in before the keyword pairs. One dict argument again, so
   nothing downstream changes, and it is exactly CPython's order (the mapping
   first, keywords winning). The catch: `update` has THREE overloads
   (TPyList / TPyDict / Variant) and only the dict one can be merged this way —
   `d.update([("a", 1)], b=2)` would need the list arm, so the seed has to be
   type-directed or the mixed form restricted to a mapping seed.
2. **Two calls.** `d.update(m, **kw)` IS `d.update(m); d.update(kw)` — hoist the
   first and let the second be the expression. Handles every overload of the
   seed for free, but it puts a second call site into a construct that today is
   one, across five loops, which is the shape
   `devdocs/dev/normalise-dont-special-case.md` warns about.

Option 1 for a mapping seed is the smaller change and the one that keeps a
single call; option 2 is what a list seed would need. Worth measuring how often
the non-mapping seed appears before building the general form.

## Gate

`d.update(other, a=1)`, `dict(other, a=1)`, and the existing rows of
`test_nilpy_dict_update_keywords.npy` unchanged, all diffed against CPython.
