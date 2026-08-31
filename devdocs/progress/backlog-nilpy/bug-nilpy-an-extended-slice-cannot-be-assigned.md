---
track: N
prio: 30
type: bug
blocked-by: []
summary: "`l[::2] = [7, 8]` is a parse error. The READ form `l[::2]` works, and the plain-slice ASSIGN `l[1:3] = [9]` works; only the strided assignment is missing."
---

# An extended slice cannot be assigned

Found 2026-08-16 by a `tools/pydiff.py` sweep.

```python
l = [1, 2, 3]
l[::2] = [7, 8]      # CPython [7, 2, 8]
                     # pascal26: error (parse)
l[1:3] = [9]         # works
print(l[::2])        # works — the READ side is complete
```

Both halves it needs already exist: `pylist_slice_step` reads a strided slice
and `pylist_setslice` writes a contiguous one. The missing piece is the
lvalue-side parse of a three-part subscript plus a `pylist_setslice_step`
that walks the same index sequence the reader does — and, as CPython does,
raises when the RHS length does not match the number of selected slots (that
check is what makes the strided form different from the contiguous one, which
resizes).

Low priority: strided assignment is rare in real code, and it fails LOUDLY at
compile time, so nothing can be silently wrong.

## Gate

A `.npy` diffed against CPython: forward and negative steps, a length mismatch
raising ValueError, and the contiguous forms unchanged.
