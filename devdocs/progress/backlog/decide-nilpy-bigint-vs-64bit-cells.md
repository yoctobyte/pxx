---
track: U
prio: 40
type: decide
---

# decide: NilPy integer semantics — arbitrary precision vs 64-bit (uforth needs one)

- **Track:** U. Affected: N (frontend semantics), A (runtime), B (uforth arc).
- **Opened:** 2026-07-19, from [[feature-nilpy-corpus-uforth]].

Python ints are arbitrary precision; NilPy's are machine ints. uforth
exploits bignums: `((ud_hi & M) << 64) | ud_lo` 128-bit composites in the
UM/MOD-family paths (uforth.py:2944, 2986), unmasked intermediates with
selective 64-bit masking after the fact. Under 64-bit NilPy ints these go
SILENTLY wrong.

Measured 2026-07-20, so the "silently" above is not an assumption:

```python
c = 9223372036854775807
print(c + 1)     # CPython 9223372036854775808   pxx -9223372036854775808
```

It WRAPS — no overflow trap, no diagnostic. Everything up to that boundary is
exact, including the 2^31 crossing and large products, so the failure is a
cliff rather than a gradient.

Options:
1. **NilPy bigint type** — a real `int` = arbitrary precision (heap,
   Track A runtime + N lowering). Faithful Python semantics, biggest win
   for every future Python corpus; biggest cost (arith on the variant hot
   path, comparisons, literals, printing). Could tier: fixnum 63-bit
   inline + heap bignum overflow promotion (classic tagged scheme).
2. **128-bit support only** — pxx grows int128 (also unblocks the C
   frontend's `unsigned __int128`, e.g. libbf's 64-bit-limb config the
   quickjs runner had to config around!). Covers uforth's actual uses;
   Python semantics still subtly off (overflow wraps somewhere).
3. **Upstream discipline** — rewrite uforth arithmetic in 64-bit pairs
   (Forth cells ARE 64-bit; bignum use is incidental). Cheapest; bends the
   "uforth runs unmodified" goal and fixes nothing for future corpora.

Recommendation: 1 with the fixnum/bignum tier if the Python story is
strategic; else 2 (dual-use with cfront int128 makes it earn its keep
twice). 3 only as a stopgap to get early milestones green.
