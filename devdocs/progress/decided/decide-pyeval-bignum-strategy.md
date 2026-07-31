---
track: U
prio: 40
type: decision
---

# decide: how should pyeval handle arbitrary-precision (bignum) integers?

pyeval (feature-lib-pyexec) models Python ints as **Int64**. That is correct for
almost the whole uforth corpus, but a specific group — the **double-cell MATH.UFO
words** (UM*, M*/, D+, D<, DNEGATE, T*, …) — computes 128-bit intermediate
results the CPython way, e.g.:

```python
M = 0x10000000000000000            # 2**64  — OVERFLOWS Int64 to 0
p = n1 * n2                         # 128-bit product
lo = p & 0xFFFFFFFFFFFFFFFF
hi = (p >> 64) & 0xFFFFFFFFFFFFFFFF
```

With Int64, `2**64` wraps to 0 and the products/shifts lose the high half, so
these ~13 blocks RUN (since `def`/compound landed) but return WRONG values.
`x & 0xFFFFFFFFFFFFFFFF` also can't produce Python's unsigned 2^64-1 (U<, U>).

## The fork

- **A. Integrate pxx's promotable-int / bignum path** (VT_PROMO_*, promoint.pas)
  so a pyeval int auto-promotes on overflow, matching Python's arbitrary
  precision. Cleanest semantically; largest effort (thread promotion through
  every pyadd_v/pymul_v/pyshl_v used by pyeval, plus the `&`/`>>` unsigned mask).
- **B. Targeted 128-bit path**: detect the double-cell idiom (2^64 modulus) and
  compute lo/hi with a 64x64->128 helper. Narrow, unlocks exactly the MATH
  words, no general bignum.
- **C. Accept the limitation.** Double-cell MATH words stay wrong/unsupported;
  everything else (the vast majority of uforth) is correct. Ship, revisit if a
  real workload needs D-arithmetic.

## Recommendation

**C for now, B when a workload needs it.** The double-cell words are a small,
self-contained corner; the interpreter is correct everywhere else. Full bignum
(A) is a large Track A investment better justified by a broader need than these
~13 words. Flagging for the user to rank.

## RESOLVED 2026-07-21 — B′ implemented (user agreed)

User confirmed the fork and the reasoning that bignum here is a TRANSIENT
intermediate (never on the Forth stack — the double-cell words mask/split back to
two 64-bit cells before push), so doing it well is worth it and overhead is a
non-issue (the tree-walker dominates; promo engages only on overflow).

Implemented B′ (commit on master): pyeval integers auto-promote to promoint.pas
on Int64 overflow and demote back when they fit; `& (2^k-1)` / `>>k` / `<<k`
reduce to mod/div/mul by powers of two; big literals tokenize to promo; push()
coerces a promo back to a 64-bit cell. General bignum bitwise-and with a
non-power-of-2 mask is unsupported (not used by the corpus) and errors clearly.
Hand-checked: 10^10*10^10 = 10^20 -> hi=5, lo=7766279631452241920. Done.

## Log
- 2026-07-21 — resolved, commit 0e05946d.
