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

## It is the INFERRED RETURN TYPE

Two probes pin it:

```python
def mk(d, k) -> list:      # annotated: WORKS
    b = d.get(k, [])
    return b[:6]
```

```python
b = d.get("C", [])         # inline, no function: WORKS
s = b[:6]
print(len(s))              # 2
```

So the slice value itself is right and `len()` on a variant holding a list is
right; what is wrong is the type NilPy infers for a body whose `return` is a
slice of a variant-typed local. The returned value then goes out through the
wrong coercion and reaches the caller as a bare object.

**FIXED** (2026-07-29): `PyInferExprType` now recognises a SLICE — a ':' at
bracket depth 1, via the new `PySliceBracketAt` — and types it as the receiver's
container kind (a str slice is a str; slicing a list or a variant holding one
yields a TPyList). Previously only the string INDEX form was handled, so
`return b[:6]` fell to the Integer default.

Verified against CPython on nine repros, including the app's exact shape
`d.get(k, [])[:6] if w else []` inside a def.

**NOT SUFFICIENT for songformatter** — a SECOND defect is in play, and a
top-down bisect of the real detector (a scratch copy at `/tmp/sfx`, rebuilt each
step) pins it to the METHOD, not the expression:

| `evidence=` in ViolationCountDetector.analyze | field reads back |
| --- | --- |
| `[]` | correct (0) |
| `penalty_evidence.get(winner.label, []) if winner else []` (no slice) | correct (0) |
| `penalty_evidence.get(winner.label, [])[:6] if winner else []` | **garbage** (1751084129) |
| `penalty_evidence.get("C", [])[:6] if winner else []` (literal key) | **garbage** |

So: the slice is the trigger, the key is irrelevant, and the SAME expression in
a small method is fine — every bottom-up repro matches CPython (annotated
`dict[str, list[str]]`, inside a method, Optional winner, a stored EMPTY list
under an existing key, keyword arguments with a trailing `debug=`).

What is different about the real one is its SIZE: `ViolationCountDetector.analyze`
is ~90 lines with many locals, two nested loops over 84 keys, `del` statements
and set literals. Prime suspect is a per-method locals/temporaries cap: the
hidden temp the slice needs lands in a slot past the limit and is written
somewhere else. Next step is to check the locals/temp allocation limits for a
method that big (see [[project_nilpy_variant_container_landmines]], which
records a 255-local truncation), NOT to keep growing the repro.

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
