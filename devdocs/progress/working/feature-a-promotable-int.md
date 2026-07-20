---
track: A
prio: 85
type: feature
---

# Promotable int — a new arbitrary-precision integer type (fixnum + heap bignum)

- **Track:** A (new type, IR, runtime, variant integration). Affected: N (NilPy
  uses it as its `int`), P (opt-in dialect type), B (bigint library entry
  points).
- **Opened:** 2026-07-20, out of [[decide-nilpy-bigint-vs-64bit-cells]] and
  [[decide-nilpy-and-or-return-operand-or-bool]].
- **Blocking:** further NilPy work. Python's `int` IS arbitrary precision;
  building more of the frontend on a type that silently wraps at 2^63 means
  redoing it. Land this first.

## What

A new, distinct integer type — "promotable int" — that is statically an integer
but whose runtime storage promotes from an inline machine value to a heap
bignum on overflow. Classic fixnum/bignum tier.

It is a **new type**, not a change to any existing one:

- Pascal's `Integer`/`Int64` and variant's `varInteger`/`varInt64` keep their
  exact current semantics and cost. FPC compatibility is not touched.
- **New variant tags are appended** — one per storage class (`promo32`,
  `promo64`); see Representation. Never renumber existing tags: Pascal code
  compares `VarType()` against documented constants, and there is serialization
  to consider. Pick values in a clearly pxx-specific range so a future FPC
  `varXxx` addition cannot collide.
- Pascal and C code that never names the type pays **nothing**.

## Why it must be in variant too

Python is soft-typed; a value's type is not always known statically, so the
promotable int has to be representable inside a variant. That is what forces the
new tag. But note the separation of concerns:

- **promotable int** = width fallback (known to be an int, may not fit a word)
- **variant** = type fallback (don't know the type at all)

NilPy escalates: **native int64 → promotable int → variant**, only as far as it
must. Loop induction variables, indices and `len()` results stay native int64
with no checks at all.

## Representation — DECIDED: explicit `{tag, payload}`, no pointer tagging

**One semantic type, two storage classes.** The semantics (arbitrary precision)
are defined once; the storage class only says how wide the inline value is
before it spills to the heap:

| storage class | inline payload | struct size |
| --- | --- | --- |
| `promo32` | `int32` | 8 bytes |
| `promo64` | `int64` | 16 bytes (12 packed) |

Both get a variant tag. Coercion rules, conformance tests and the operator
semantics below are written **once** against "promotable int" and parameterised
by width — do not fork the semantics per class.

**Why the width is safe to vary:** it is semantically *unobservable*. A
promotable int is arbitrary precision by definition, so whether it spills at
2^31 or 2^63 changes performance only, never a result. That matters here because
cross-targets are validated by differential-testing against x86-64 — differing
promotion boundaries cannot produce differing output.

**Selection is per target AND per value:**

- Per target — 64-bit hosts default to `promo64`; ESP/riscv32/xtensa default to
  `promo32`, because int64 on those cores is multi-instruction emulation and
  16 bytes per int is expensive in scarce SRAM. **NilPy on ESP is a project
  subgoal**, so this is not a hypothetical.
- Per value — a 32-bit target may still select `promo64` where range analysis
  proves the value needs it but stays inside int64; a 64-bit host may select
  `promo32` for provably small values.

### Fast path

The tag check is a predictable branch; on the native side the payload is a
**plain machine int**. No shifting, no masking, negatives free, full range of
the storage class. Only the tagged-bigint state touches the heap — and in that
state the struct has spare room for metadata (sign, limb count, or a small
inline bignum) instead of forcing a second dereference.

### Reserved naming — leave room for the bit-hacking family

Pointer tagging is rejected *for now* (below), but it may return as an opt-in
compiler-flag choice for memory-tight builds. That would double the storage
classes, which is mostly a **naming** problem — so fix the taxonomy now, while it
is free.

Convention: **the number in the name is the actual usable inline width.** The
tagged form genuinely loses a bit to the tag, so it names itself honestly and no
"tagged"/"packed" suffix is needed:

| name | encoding | inline payload | struct |
| --- | --- | --- | --- |
| `promoint32` | explicit `{tag, payload}` | 32-bit | 8 B |
| `promoint64` | explicit `{tag, payload}` | 64-bit | 16 B |
| `promoint31` | pointer-tagged *(reserved)* | 31-bit | 4 B |
| `promoint63` | pointer-tagged *(reserved)* | 63-bit | 8 B |

Extends cleanly: a 2-bit tag would be `promoint62`, a wider inline `promoint128`.
All classes share the single semantic definition; only the storage table grows,
and the promotion boundary stays unobservable in every case.

**Reserve now, even though only two are implemented:**

- a **contiguous block of ~8 variant tag numbers** in the pxx-specific range —
  tags can never be renumbered, so claiming a block now is what keeps the tagged
  family adjacent instead of scattered into whatever gaps exist later;
- the matching **IR type codes**, same argument.

**ABI hazard to settle before any flag ships:** the storage class must be a
**whole-program** property, or be encoded in the type's mangling. A variant
crossing unit boundaries is safe (the tag travels with the data), but a *bare*
promotable-int field in a record shared between units built with different
settings is a silent layout mismatch. Whatever the flag ends up being called
(`--int-storage=explicit|tagged` or similar), it needs a link-time/use-time
consistency check, not per-unit freedom.

### Rejected: pointer tagging (low-bit / NaN-boxing)

Considered and dropped. It would have saved 8 bytes but **not the branch** — the
tag still has to be tested — while taxing *every* arithmetic op with
shift/mask/sign fixups. Density only pays off for large int arrays, which is not
a case worth optimising for now.

For the record, since it came up: low-bit tagging would have been *correct* under
ASLR — it keys off allocation **alignment** (malloc guarantees 8/16-byte, and pxx
ships its own allocator anyway), not address range, and ASLR only randomises
page-aligned bases, so a valid pointer can never be odd. It was rejected on cost,
not safety. High-bit/NaN-boxing is separately unsafe and stays rejected: it bets
on 47-bit addresses and breaks under 5-level paging (LA57).

## Lifetime

- **Inside a variant:** rides the existing `VarClear`/`VarCopy` machinery. Solved
  for free.
- **Standalone:** needs a policy. Cheapest correct route is to reuse the managed
  string refcount path (already exists, already `--threadsafe`-aware) rather than
  invent one. "Bigints are rare" is true of *creation*, not of lifetime — a
  factorial or crypto loop churns them and will leak without reclamation.

## Code size / pulling in the bigint library

Pascal and C must not grow. Keep the slow path behind a **narrow external
interface** — roughly `add/sub/mul/divmod/cmp/from_str/to_str/free` — and have
overflow handlers call into it:

- No promotable ints in a program → no references → reachability-gated DCE
  ([[feature-emission-size-dce]]) drops the whole library. Automatic; no opt-in
  ceremony required for Pascal/C.
- Same posture as `uses softfloat` on ESP: keep entry points few and coarse so
  DCE can actually cut. **Do not scatter inline bignum calls through codegen.**

## Embedded posture

NilPy on ESP is a subgoal, so the `promo32` default there is deliberate: keep
ints 8 bytes and keep arithmetic on the core's natural word.

But note the honest division of labour — **for hot numeric work on an ESP, Pascal
or C is the right tool**, and pxx makes mixing them trivial by design (shared IR,
same binary, wrapperless C header import). NilPy earns its place there for glue,
control flow and orchestration; the inner loops can live in a Pascal or C unit
alongside it. That combination is a feature to document, not a limitation to
apologise for — and it means `promo32` never has to be fast enough to win a
benchmark it shouldn't be entered in.

## Guardrails (the AST is shared — these will bite otherwise)

1. **Keep it out of the C frontend.** C99 `int`/`long` are fixed-width; the type
   must never be inferred for C code.
2. **Shared type does NOT mean shared operators.** Python `//` floors toward −∞
   and `%` takes the divisor's sign; Pascal `div`/`mod` truncate toward zero.
   `-7 // 2` is `-4` in Python and `-3` in Pascal. Operator semantics stay
   **frontend-selected**. Same for `**` (float result for negative exponents).
3. **No silent numeric widening.** int→float conversion of a huge value must
   raise (CPython raises `OverflowError`), not quietly lose precision.

## Coercion matrix (define explicitly)

| expression | result |
| --- | --- |
| promo ∘ `varInt64` | promo (never lose) |
| promo ∘ `varDouble` | double; raise if the int is too big to convert |
| promo → Pascal `Integer`/`Int64` | range check, raise on overflow |
| promo → string | exact decimal, both directions |

Pascal-only expressions keep current semantics untouched; only expressions
*touching the new tag* use the new rules.

## Staged plan

1. **Type + trapping overflow.** Promotable int exists, arithmetic is checked,
   overflow raises a clear error (never silent wrap). Fast, honest, ships early;
   fixes the current correctness cliff immediately.
2. **Promotion.** Overflow allocates and promotes to the heap bignum via the
   narrow interface. Semantics now Python-correct.
3. **Check elision.** Range/induction analysis strips checks where values are
   provably bounded — restores full native speed in ordinary loops.
4. **Variant integration** (new tag, coercions, `VarClear`/`VarCopy`).
5. **Pascal dialect exposure** — opt-in, explicitly typed, so no existing Pascal
   program changes behaviour. Genuinely attractive on its own: real bigints
   without external-library ceremony.

## Testing

CPython is the oracle — this is the same differential pattern as pasmith-vs-FPC
and csmith-vs-gcc. Wire into [[feature-t-nilpy-cpython-differential-fuzzer]].

Seed boundary set: `2^63-1`, `2^63`, `-2^63`, `2^62` (tagging boundary),
`factorial(30)`, negative `//` and `%` combinations, `**` with large exponents,
int→float overflow, `str(bigint)` round-trips, and uforth's
`((ud_hi & M) << 64) | ud_lo` composites.

Also assert the negative: a Pascal/C program that never uses the type must show
**no size growth** and no reference to the bignum entry points.

---

## Progress log

### Landed 2026-07-20

- `bf86b54e` — type kinds `tyPromoInt32` (27) / `tyPromoInt64` (28) appended to
  `TTypeKind`; contiguous 8-entry variant tag block at `VT_PROMO_BASE = 8192`;
  `TypeSize` (8 / 16); `TypeIsPromoInt`, `PromoIntInlineBits`, `PromoIntVarTag`,
  `PromoIntDefaultKind`. The freeze-forever decisions are now in the tree.
  Deliberately absent from `TypeIsOrdinal` / `TypeSigned` so no existing integer
  path can pick the type up.
- `f053b2ed` — `PromoInt` / `PromoInt32` / `PromoInt64` reserved in the Pascal
  type resolver, currently erroring with a "not implemented yet" diagnostic.

### MEASURED: the current cliff is at 2^31, not 2^63

The ticket's framing ("silently wraps at 2^63") is optimistic — measured against
CPython before touching anything:

```python
def fact(n: int) -> int:
    r = 1
    i = 1
    while i <= n:
        r = r * i
        i = i + 1
    return r
print(fact(13))
```

pxx prints `1932053504`, CPython prints `6227020800`. NilPy's `int` annotation
maps to `tyInteger` (pyparser.inc:138, :227), which is **4-byte signed**, so an
explicitly annotated `-> int` function wraps at 2^31. A loop-carried
accumulator inferred from `z = 1` does the same: `z * 100000` three times gives
`-1530494976` instead of `10^15`.

It is also inconsistent — `w = 2147483647; w = w + 1` DOES widen (the AST-typing
pre-pass widens on a literal that does not fit), while arithmetic growth does
not. So today the width a NilPy int gets depends on whether the big value
appears as a literal.

This strengthens "land this first": the cliff is shallow enough to hit in
ordinary programs, not just in bignum-flavoured ones.

### Next step — stage 2

Storage and arithmetic. Order that keeps every increment green:

1. `{tag, payload}` slot allocation + zero-init for a promo-typed local/global.
2. Store: integer expr -> promo, with a range check against the inline width.
3. Load: promo -> Int64 where the tag says inline; raise on the spilled tag
   (which stage 2 cannot produce yet).
4. Checked `+` / `-` / `*` and the comparisons, trapping on overflow.
5. `Write`/`Str` via the existing integer path while inline.

x86-64 first, other backends erroring explicitly rather than falling through.
Removing the stage-1 declaration guard in parser.inc is the last step of (1),
not the first — nothing should be declarable until the slot is real.
