---
track: N
prio: 40
type: bug
blocked-by: []
---

# Float printing loses the last 1-2 significant digits vs CPython's shortest round-trip repr

Found by proactive CPython-diff sweeping.

```python
print(10 / 3)
print(1 / 3)
```
CPython (Python's `repr`/`str` for float is the SHORTEST decimal string that
round-trips back to the exact same IEEE 754 double):
```
3.3333333333333335
0.3333333333333333
```
pxx:
```
3.333333333333334
0.333333333333333
```

Both are wrong in the same direction: pxx's float-to-string conversion is
truncating/rounding to fewer significant digits than CPython's algorithm
keeps, so the printed value does not round-trip back to the identical double
(a real, if usually cosmetic, divergence — it would matter for anything that
re-parses printed floats, e.g. a round-trip test, a serialized config, or
`float(str(x)) == x` style logic, all of which CPython guarantees and pxx
currently does not).

## Scope note

This is a numerics/formatting question (the float→string conversion routine,
presumably in the RTL or pylib's float-to-str path), not specific to any one
`.npy` construct — every `print`/`str()`/f-string of a float likely goes
through the same routine, so the fix (whatever it is — more significant
digits kept, or a proper shortest-round-trip algorithm like Grisu/Ryu) is a
single shared fix with broad payoff. Not investigated further or attempted
this pass: pinning down exactly which routine renders a float to text needs
its own dedicated look (RTL float-to-string vs a NilPy-specific formatter),
and fixing a numeric-formatting algorithm deserves care and its own precise
verification against many values, not a rushed patch mid-sweep.

## Gate

A `.npy` case with several float values whose shortest round-trip repr needs
16-17 significant digits (as CPython's does), diffed directly against
CPython's own `print()` output, gated in `test-nilpy` + self-host
byte-identical.

## 2026-08-02 — sweep widens this: THREE more divergences in the same routine

Found by `tools/pydiff.py run` over a float-formatting probe. All of them are the
same float→string routine this ticket already scopes, so they are recorded here
rather than filed separately — but the ticket is broader than "loses the last 1-2
digits", and the first one is not a precision issue at all.

### 1. Negative zero loses its sign

```python
print(-0.0)            # CPython: -0.0     pxx: 0.0
print(float("-0.0"))   # CPython: -0.0     pxx: 0.0
```

Not a rounding difference — a dropped sign bit. IEEE 754 distinguishes -0.0 from
0.0, `-0.0 == 0.0` is True in both, and the sign survives arithmetic, so the loss
is purely in the printing. Cheapest of the three to fix and the least ambiguous.

### 2. No scientific-notation threshold

```python
print(1e-5, 1e-4, 1e16, 1e17)
# CPython: 1e-05 0.0001 1e+16 1e+17
# pxx    : 0.00001 0.0001 10000000000000000.0 100000000000000000.0
```

CPython's `repr` switches to exponent form below `1e-4` and at/above `1e16`. pxx
prints plain decimal across that whole range. Note `1e-4` agrees, which pins the
threshold rather than the formatting.

### 3. Extreme exponents ARE printed in exponent form, but inaccurately

```python
print(1e300, 1e-300)
# CPython: 1e+300              1e-300
# pxx    : 1.000000000000001e+300   9.999999999999993e-301
```

So the exponent path exists and is reached eventually; it is the shortest-
round-trip digit generation that is missing — the same root as this ticket's
original `10 / 3` case, just more visible at the extremes. `9.999999999999993e-301`
does not even round-trip to the same double.

### What this means for the fix

Items 1 and 2 are independent of the digit-generation problem and are far
cheaper: a sign check and a threshold. Item 3 is the original ticket. Worth
splitting the work that way if this is picked up — shipping the sign and the
threshold does not require committing to a Grisu/Ryu-class shortest-round-trip
algorithm, which is what item 3 actually needs.
