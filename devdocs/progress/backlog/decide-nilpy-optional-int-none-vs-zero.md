---
track: U
prio: 60
type: decide
---

# decide: NilPy Optional[int] — None must be distinct from 0

## The fork (root cause of the locals-read failure)

NilPy maps `Optional[int]` to tyInt64 with None represented as the **0
sentinel** (see the header note in pyparser PyAnnTypeAt). So a function
`-> Optional[int]` that returns a real None and one that returns 0 are
indistinguishable, and the ubiquitous Python idiom breaks:

```python
def lookup(name: str) -> Optional[int]:
    return d.get(name)          # returns None on miss, an int (incl. 0) on hit
slot = lookup("A")
if slot is not None:            # slot == 0 (valid) reads as None -> WRONG branch
    ...
```

Verified: with the `-> Optional[int]` annotation the above prints "miss"
(0 read as None); WITHOUT the annotation (return stays variant) it correctly
prints "found slot 0". CPython: "found slot 0".

This is EXACTLY uforth's `_lookup_local_slot(name) -> Optional[int]` returning
`current_local_map.get(name.upper())`: a local at slot 0 is treated as absent,
so `A` in a colon body never compiles to LocalGet — blocking ALL local reads
and `TO` (localstest.fth). Declare-only locals work.

## Options

1. **Optional[int] result stays a VARIANT** (None = VT_EMPTY, 0 = VT_INT), and
   `is None`/`is not None` check the TAG. Correct Python semantics. Cost: every
   Optional[int] value is a 16-byte variant, and the many existing
   0-sentinel consumers must switch to tag checks — but `is None` already
   tag-checks a variant, so most `if x is not None` idioms just work.
2. **A distinct None sentinel for Optional[int]** (e.g. Low(Int64)) instead of
   0. Cheap (stays 8-byte) but wrong for any code that legitimately uses that
   value, and `is None` must special-case the sentinel.
3. **Keep 0-sentinel, document as a known deviation.** Rejected — it silently
   breaks a core Python idiom and blocks uforth locals.

## Recommendation

Option 1 (variant Optional[int]) — it is the only fully-correct choice and
`is None` already does the right thing on a variant. Scope: the Optional[int]
type mapping in PyAnnTypeAt (currently tyInt64) and the return coercion.
Root-causes bug-nilpy-locals-list-pointer-truncated-32bit's local-read half.
