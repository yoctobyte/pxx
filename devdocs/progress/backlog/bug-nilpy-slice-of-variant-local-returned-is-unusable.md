---
track: N
prio: 75
type: bug
---

# Returning a SLICE of a variant local gives the caller an unusable value

```python
def mk(d, k):
    b = d.get(k, [])
    return b[:6]

d = {"C": ["a", "b"]}
print(len(mk(d, "C")))     # TypeError: expected a number, got object
```

CPython prints `2`. Returning the `.get()` result **without** the slice is fine:

```python
def mk(d, k):
    return d.get(k, [])    # len(mk(d, "C")) == 2, correct
```

So it is the slice of a **variant-typed local** that produces the bad value: the
result reaches the caller as something `len()` then coerces through
`pyvar_to_int` ("expected a number, got object") instead of a list.

## Why it matters

This is the wall songformatter's key analysis dies on, and it is worth noting
how it presents there, because the visible symptom is nowhere near the cause:

```python
evidence=penalty_evidence.get(winner.label, [])[:6] if winner else []
```

The value is a correct (empty) list when it is passed — an instrumented copy of
the app prints `DBG slice n= 0` right before the constructor — and by the time
`DetectorResult.to_text` reads `self.evidence` back, `len()` answers
**1751084129** (ASCII bytes read as an integer) and the join walks off into a
segfault. Only that one detector of eight is affected; every other one builds
its evidence list inline.

## Repro / gate

The snippet at the top, matching CPython. Then songformatter's
`DetectorResult.to_text(verbose=True)` rendering all eight detectors — see
[[bug-nilpy-songformatter-first-render-walls]], whose remaining failure this is.

Instrumented copy still at `/tmp/sfx` (a `cp -r` of `~/songformatter` with
prints in `key_analysis.py`); rebuild it with
`pascal26 SongFormatter.py <out>` and run under `DISPLAY=:99`.
