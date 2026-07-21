---
track: A
prio: 55
type: bug
---

# NilPy: wide int literals + the `& 0xFFFF...` unsigned-mask idiom don't promote to bignum

- **Track:** A (shared integer semantics / runtime; [[feature-a-promotable-int]]
  extension). Consumer: [[feature-nilpy-corpus-uforth]]. Oracle: CPython.
- **Found:** 2026-07-21, driving uforth's conformance suite. This is the
  DO/LOOP blocker — it hangs the whole prelim suite past Pass #21.

## Symptom

uforth's DO/LOOP boundary test (`_loop_crossed`, uforth.py:2101) computes
`(idx - limit) & 0xFFFFFFFFFFFFFFFF` for both the old and new index and compares
them UNSIGNED. Python's arbitrary precision makes the masked values positive
bignums, so the unsigned comparison is correct. Under NilPy's 64-bit ints the
mask is a no-op and the comparison runs SIGNED, so a normal incrementing loop
never crosses its boundary → **infinite loop**. `: T 0 5 0 DO 1+ LOOP ; T`
hangs. Almost every Forth-2012 test uses DO/LOOP, so the suite hangs at the
first one (prelimtest Pass #22 region; it runs and matches CPython exactly
through Pass #21).

## Root cause — three uncovered promotion entry points

[[feature-a-promotable-int]] (done, stages 1-3) promotes some runtime overflow,
but these paths still silently wrap to 64-bit:

```python
print(0xFFFFFFFFFFFFFFFF)        # NilPy -1        CPython 18446744073709551615
print(18446744073709551615)      # NilPy -1        CPython 18446744073709551615
print(1 << 64)                   # NilPy 0         CPython 18446744073709551616
c = 9223372036854775807
print(c + c + 1)                 # NilPy -1        CPython 18446744073709551615
print((c + c + 1) > 0)           # NilPy False     CPython True
```

So: (1) a **wide integer literal** (hex/decimal) that overflows Int64 is emitted
as the wrapped Int64 with no promo text — pylexer.inc ~634 (`0x`/`0o`/`0b`) and
~649 (decimal) both `n := n*base + digit` into an Int64 and `PyEmitToken(tkInteger,
n, '')`; contrast the Pascal lexer (lexer.inc ~2071) which carries the digit TEXT
in SVal when it exceeds Int64 for the promo lowering. (2) `1 << 64` doesn't
promote. (3) `c + c` past 2^63 doesn't promote to a positive bignum — it wraps.
And even a correctly-masked value would need an **unsigned** `>`; today `>` is
signed.

## Fix scope

Extend promotable-int to cover: wide integer literals (carry the value for the
promo lowering, like the decimal Pascal path), shift-left overflow, and additive
overflow into the 2^63..2^64 range; and make `&` with an all-ones mask yield the
unsigned value (positive bignum) so the subsequent compare is unsigned — matching
CPython. This is squarely the promotable-int / bignum runtime, not a frontend
patch. Gate: CPython-differential on the snippets above, then
`: T 0 5 0 DO 1+ LOOP ; T .` = 5 and the prelim suite runs to completion
(`cd ~/projects/uforth && /tmp/uforth tests/prelimtest.fth` matches
`python3 uforth.py tests/prelimtest.fth`: 0/57 failed).

## What already works (2026-07-21)

uforth compiles unmodified, STD.UFO fully loads, VARIABLE/CONSTANT/memory words
run (`VARIABLE Q 42 Q ! Q @ .`=42, `100 8192 ! 5 8192 +! 8192 @ .`=105, `BL .`=32),
and the prelim suite executes and matches the CPython oracle byte-for-byte through
Pass #21. Only the unsigned-cell arithmetic above is missing.
