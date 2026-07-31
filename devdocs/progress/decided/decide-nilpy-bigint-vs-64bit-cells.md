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

## DECIDED 2026-07-20: option 1, via a NEW distinct "promotable int" type

Arbitrary precision is not optional — this is Python, and the current silent
wrap at 2^63 is a correctness cliff. Implemented as the classic fixnum/bignum
tier, but as a **new, distinct type** rather than by changing any existing one.
Spec + work item: [[feature-a-promotable-int]] (urgent; land before further
NilPy work).

### Why a new type instead of making variant ints promotable

Pascal's `varInteger`/`varInt64` have specified, FPC-compatible semantics.
Making them promotable would be both **inaccurate** (changes documented Pascal
behaviour) and **unnecessary overhead** for Pascal and C code that never asked
for bigints. Since the AST/IR is shared across frontends, the type system —
not the frontend — has to carry the distinction.

So: a new type, and a **new appended variant tag**. Standard Pascal never sees
it; existing tags keep their numbers and their exact semantics.

### The three tiers (this is the important separation)

Bigint is a **width** fallback, variant is a **type** fallback. Never conflate:

1. **native int64** — where provably safe (loop induction vars, indices,
   `len()` results). Zero overhead, no checks. This is what keeps ordinary
   loops fast.
2. **promotable int** — statically still an int, may not fit a register.
   Overflow-checked, promotes to heap bignum.
3. **variant** — the *type* itself is unknown.

NilPy uses tier 1 when it can prove safety, tier 2 otherwise, tier 3 only for
genuinely dynamic values. Falling back to variant for every int would be a real
and unnecessary cost; a promoting int is a well-predicted `jo` on the fast path.

### Notes

- **Option 2 (int128) is not superseded.** It remains independently worth doing
  for the C frontend's `unsigned __int128` (libbf / quickjs). Orthogonal.
- uforth's 128-bit composites fall out for free once ints promote — the
  `((ud_hi & M) << 64) | ud_lo` paths stop being a cliff.
- CPython is the oracle for the semantics; see
  [[feature-t-nilpy-cpython-differential-fuzzer]].

## Log
- 2026-07-20 — resolved, commit bc9134e7.
