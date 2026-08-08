---
track: N
prio: 30
type: bug
summary: "SILENT WRONG VALUE: `def f(u): return u * [7]` returns the list HANDLE as an integer — the reversed LIST repeat is built correctly but the def's inferred return type is Integer. `u * bytes(...)` and `[7] * u` are both fine."
---

# A reversed list repeat returned from a def comes back as an integer

```python
def f(u):
    return u * [7]

print(f(2))        # CPython: [7, 7]        pxx: 127321897959656
```

No error — a heap handle printed as a number. The sibling forms all work:

```python
def g(u): return [7] * u          # OK
def h(u): return u * bytes([1])   # OK   (reversed BYTES is fine)
print(2 * [7])                    # OK   (not inside a def)
```

So it is specific to REVERSED order + LIST + returned from a def, which points
at the def's RETURN-TYPE inference rather than at the repeat lowering: the
repeat node itself carries tyClass and the TPyList record (PyMakeListRepeat sets
both, precisely so the identity survives into a local).

## Likely mechanism

NilPy infers a def's result by re-parsing the body, and the trial pass may see
the parameter before its type is known — `u` as tyUnknown rather than a variant
or an ordinal — so `PyIsRepeatCountTk` says no, the pair reads as arithmetic and
the result infers Integer. The REAL parse then builds the list correctly and
returns it through an Integer-typed result. That the reversed BYTES form escapes
this suggests the two do not share the inference path; find out which before
changing anything (see the trial-AST-typing note in
[[project_nilpy_class_attribute_lowering_matrix]]).

## PRE-EXISTING

Not introduced by
[[bug-nilpy-sequence-repeat-with-a-variant-count-falls-through-to-arithmetic]] —
it fails identically before that change. It was found by that ticket's test
matrix and deliberately left out of its scope rather than half-fixed;
`test/test_nilpy_sequence_repeat_variant_count.npy` says so in a comment.

## Gate

The four forms above oracle-diffed with `tools/pydiff.py`, the reversed-list case
added to `test_nilpy_sequence_repeat_variant_count.npy`, plus the per-fix loop.
