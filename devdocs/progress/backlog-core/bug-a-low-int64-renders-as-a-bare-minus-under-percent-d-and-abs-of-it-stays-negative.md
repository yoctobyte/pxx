---
slug: bug-a-low-int64-renders-as-a-bare-minus-under-percent-d-and-abs-of-it-stays-negative
title: "A promotable int at exactly Low(Int64) prints as a bare `-` under `%d`, and `abs()` of it stays negative"
track: A
prio: 40
type: bug
status: backlog
owner: ""
created: 2026-09-22
found-by: franks-5b
blocked-by: []
summary: "MECHANISM: Low(Int64) is the one value whose magnitude does not fit the type that holds it, so any path that renders or negates a promotable int by taking |v| into an Int64 is wrong at that single value and correct at every other. It SPRINGS wherever a promo path negates before it widens. Two live instances, both at exactly -9223372036854775808 and neither at any neighbour: `\"%d\" % v` emits a bare `-` (sign, no digits) where CPython gives -9223372036854775808; and `abs(v)` returns -9223372036854775808 where CPython gives 9223372036854775808. `print(v)` and `\"%s\" % v` are both CORRECT on the same value, so the readout decides whether the defect appears -- which is how it survived: the ordinary spelling works. Neighbours verified clean: -2^62, -2^63+1, +2^63 and -2^64 all render correctly under %d. Found while landing 247260d36 (the promotable-shift inline arm); NOT caused by it -- reproduced with that change stashed and the compiler rebuilt, byte-identical output both ways."
---

# A promotable int at exactly Low(Int64) prints as `-` under `%d`

Two defects, one hazard. `Low(Int64)` = -9223372036854775808 has no positive
counterpart in Int64, so `-v` and `Abs(v)` both overflow for that one value.
`promocore.pas`'s `BFromInt` already carries a hand-written special case for it
and says so in a comment, which is evidence the hazard is known and was handled
in *one* place.

## Repro

```python
a = -9223372036854775808
print(a)            # -9223372036854775808   correct
print("%s" % a)     # -9223372036854775808   correct
print("%d" % a)     # -                      WRONG (bare sign, no digits)
print(abs(a))       # -9223372036854775808   WRONG (CPython: 9223372036854775808)
```

## The neighbours are all clean, which is the useful part

Measured 2026-09-22, same binary, same run:

| expression | pxx | CPython |
| --- | --- | --- |
| `"%d" % -4611686018427387904` (-2^62) | correct | correct |
| `"%d" % -9223372036854775807` (-2^63+1) | correct | correct |
| `"%d" % -9223372036854775808` (-2^63) | **`-`** | -9223372036854775808 |
| `"%d" % 9223372036854775808` (+2^63) | correct | correct |
| `"%d" % -18446744073709551616` (-2^64) | correct | correct |

So it is not "large negatives" and not "values past a machine word". It is
exactly the one value whose magnitude is not representable in the type being
used to hold it, which is the signature of a negate-before-widen.

## Why it has not been seen

**The ordinary spelling is correct.** `print(v)` and `%s` both work. Only `%d`
fails, and only at one value out of 2^64. Any test that prints its numbers the
usual way passes.

It was found because a fixture printed with `"%d" %` for column alignment, and
the value arrived from `-(1 << 63)`. Changing the readout to `print(a, b, c)`
made the same population pass with zero differences — **the readout, not the
value, was the defect**, which is the inverse of the usual trap: here the
instrument manufactured a disagreement out of a correct value.

## Attribution, established rather than assumed

Found while landing `247260d36`. **Not caused by it**: stashed that change,
rebuilt the compiler, re-ran — same 30 differing lines, and the two builds'
fixture output is byte-identical across all 269 rows.

## What would retire this

Both instances answering CPython on the row above, plus one row asserting
`abs(Low(Int64))` widens rather than negates in place. The fix wants to be in
whatever helper takes the magnitude, not in the two call sites, or the third
caller will have it too.
