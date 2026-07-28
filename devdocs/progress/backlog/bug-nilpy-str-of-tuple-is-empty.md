---
track: N
prio: 60
type: bug
---

# `str()` of a tuple/list returns the container's POINTER

Found 2026-07-28 while testing tuple dict keys
([[bug-nilpy-tuple-dict-key-never-matches]]).

```python
t = (1, 2)
print(str(t))        # CPython: (1, 2)   pxx: 128148693843992
print(str([1, 2]))   # CPython: [1, 2]   pxx: 128148693844320
print(t)             # CPython: (1, 2)   pxx: [1, 2]
```

Two distinct defects, both silent:

1. **`str(container)` returns the handle as a number.** `print(container)`
   renders it properly, so the repr code exists — it is `str()` that misses,
   which points at `pystr_of`'s overload set (the arm that takes a variant
   holding an object payload) rather than at the printing path. Inside a
   comprehension the same expression came back as an EMPTY string
   (`[str(k) for k in d.keys()]`), so the wrong arm is picked in more than one
   way.

2. **A tuple prints as a list.** `print((1, 2))` gives `[1, 2]`. Tuples lower
   to `TPyList`, and nothing distinguishes them at render time. Fixing this
   needs a tuple flag on the object (or a distinct VType), which is a bigger
   change than (1) and is the more debatable one — worth splitting if (1) is
   taken first.

Check `repr()` and f-string interpolation with the same repro: one repr, three
entry points, and they should not disagree.

## Neighbour found the same way

`d[()] = 1` — an EMPTY tuple literal — does not parse:

```
error: expected expression
```

Loud rather than silent, so it is a gap and not a defect of this ticket's
class, but it belongs to the same tuple-literal surface and is cheap to take in
the same pass.
