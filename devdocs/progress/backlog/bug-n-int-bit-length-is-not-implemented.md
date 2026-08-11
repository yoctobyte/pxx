---
track: N
prio: 30
type: bug
blocked-by: []
---

# `int.bit_length()` is not implemented

- **Type:** bug (missing method — a compile error, so loud) — **Track N**
- **Found:** 2026-08-11, checking the sibling intrinsics for
  [[bug-nilpy-method-chained-on-open-result-fails-to-parse]]. The chain PARSES;
  the method simply does not exist.

```python
print(int("42").bit_length())
print((255).bit_length(), (0).bit_length(), (-8).bit_length())
```

```
pascal26: error: Nil Python: no class declares a method or callable field .bit_length()
```

CPython prints `6` / `8 0 4`. The diagnostic is honest and names the method, so
this is a gap rather than a trap.

## Semantics to match

`n.bit_length()` is the number of bits needed to represent `abs(n)` in binary,
excluding sign and leading zeros — so `(0).bit_length()` is **0**, and negative
values answer the same as their absolute value. Do not implement it as
"position of the highest set bit + 1" without handling 0 separately.

Worth doing in the same pass, since they are the same family and the same
place: `bit_count()` (CPython 3.10+), and `to_bytes`/`from_bytes` already exist
(`PyParseToBytes`) so the intercept pattern is right there.

## Gate

The values above matching CPython via `tools/pydiff.py run`, including 0 and a
negative, plus a promotable-int (bignum) receiver — `(2**70).bit_length()` is
71, and the machine-int path would answer wrongly for it.
`make test-nilpy` + self-host byte-identical.
