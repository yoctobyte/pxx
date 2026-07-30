---
track: N
prio: 35
type: bug
---

# `enumerate`, `zip`, `dict.items` and `most_common` build pairs that print as lists

```python
print(list(enumerate(["a", "b"])))   # CPython: [(0, 'a'), (1, 'b')]   pxx: [[0, 'a'], [1, 'b']]
print(list(zip([1, 2], ["a", "b"]))) # CPython: [(1, 'a'), (2, 'b')]   pxx: [[1, 'a'], [2, 'b']]
d = {"a": 1, "b": 2}
print(d.items())                     # CPython: dict_items([('a', 1), ('b', 2)])
                                     # pxx:     [['a', 1], ['b', 2]]
```

NilPy has ONE sequence representation, so a tuple is a `TPyList` carrying
`FIsTuple` — set by the frontend wherever a tuple DISPLAY was written, and the
only thing that makes `(1, 2)` render with parentheses rather than brackets
(that is what `bug-nilpy-str-of-tuple-is-empty` established). The four pylib
routines that manufacture pairs never set it:

`pylib.pas` — `pyenumerate` (≈2717), `pyzip` (≈2737), `TPyDict.most_common`
(≈2933), `TPyDict.itemlist` (≈2984), each `pair := TPyList.Create;` with no
`pair.FIsTuple := True`.

Iteration and unpacking are unaffected — `for i, x in enumerate(xs)` works —
so this is confined to rendering, which is why it survived: nothing crashes,
the output is merely not Python's.

## Also, separately, the VIEW objects have no repr

`d.keys()` / `d.values()` / `d.items()` print as bare lists rather than
`dict_keys([...])` / `dict_values([...])` / `dict_items([...])`. That is a
different thing from the tuple flag (a missing view type, not a missing flag)
and is worth its own decision about whether NilPy wants view objects at all —
it is recorded here only so the two are not confused when someone diffs
`d.items()` against CPython.

## Shape of a fix

`pair.FIsTuple := True;` at the four sites. Cheap, but check the one place the
flag changes MEANING rather than rendering: `pypercent_format` reads
`FIsTuple` to decide whether the right-hand side is an argument LIST or a
single value, so `"%s" % <pair>` would start unpacking. Grep the corpus for a
`%` whose right side is an enumerate/zip/items element before landing it.

## Gate

`make test-nilpy` + a `.npy` printing `enumerate`, `zip`, `items` and
`most_common` results, expectation taken from CPython's own output.
