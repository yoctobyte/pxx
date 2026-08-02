---
track: N
prio: 55
type: bug
summary: "A def whose result type was inferred (or annotated) as int TRUNCATES a float it returns: `def g() -> int: v = 1; v = 2.5; return v` gives 2 where CPython gives 2.5. Python annotations are not enforcement. Pinned returned the raw IEEE BITS (4612811918334230528) for the same program — improved to truncation by the widen-binding fix, not resolved by it."
---

# a def's return coerces a float to its inferred int result type

- **Type:** bug (NilPy — silent wrong value) — **Track N**
- **Found:** 2026-08-03, measuring the blast radius of
  [[bug-nilpy-int-prints-as-float-when-the-name-is-widened-later]]. Separate
  defect; that fix improved these two cases without fixing them, which is why
  they are not in its test.

## Measured

```python
def g() -> int:
    v = 1
    v = 2.5
    return v
print(g())              # CPython 2.5   pinned 4612811918334230528   HEAD 2

def k():                # NO annotation
    v = 3
    v = 0.5
    return v + 1
print(k())              # CPython 1.5   pinned 0                     HEAD 1
```

Both are silent. `g`'s pinned answer — `4612811918334230528` — is the IEEE 754
bit pattern of 2.5 read as an integer, which is the same shape as every other
"scalar-loaded through the wrong type" bug in this frontend. HEAD truncates
instead, which is better and still wrong.

The controls that DO agree, so the defect is narrow:

```python
def h():
    v = 3
    v = 0.5
    return v            # 0.5, correct — returning the value itself is fine
z = 2; print(z * 3)     # 6
z = 0.5; print(z * 3)   # 1.5 — arithmetic on the widened binding is fine at
                        #       module level
```

So it is not variant arithmetic in general, and not the widened binding in
general. It is the RETURN: `h` returns the variant unchanged and is right,
while `k` returns an EXPRESSION over it and loses the float.

## Where to look

Two candidates, and they may both be live:

- **the annotation.** `-> int` is being treated as enforcement. In Python an
  annotation is metadata — `def g() -> int` returning 2.5 returns 2.5 — so
  coercing on the way out is wrong regardless of what the body does. That is
  `g`.
- **the inferred result type.** `k` has no annotation, so its result type came
  from inference, and `v + 1` over a variant-typed `v` apparently typed as int
  (probably from the literal `1`, or from `v`'s FIRST binding). That is the
  same "decided from a literal" family as
  [[bug-nilpy-int-promotion-decided-statically-so-computed-overflow-wraps]] and
  [[bug-nilpy-range-negative-runtime-step-yields-empty]] — worth reading both,
  a general answer may cover all three.

## Gate

A `.npy` diffed against CPython: both repros; an annotated `-> int` def
returning a plain float literal (does the annotation coerce on its own?); an
unannotated def returning `float + int`; `h`'s form as the passing control; and
an annotated `-> float` def returning an int (the mirror — CPython returns the
int unchanged, `1`, not `1.0`).
