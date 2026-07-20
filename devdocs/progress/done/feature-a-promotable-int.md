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

## Staged plan — RENUMBERED 2026-07-20 (read this, not the old numbering)

**The numbers shifted once and the drift caused confusion.** Splitting storage
+arithmetic into its own ticket inserted a stage, so everything after it moved
up by one. The progress log below already uses the NEW numbers; this section
did not, and listed four items under "stages 3-5". Now they agree. If you see
a stage number anywhere else in the tree, check it against this table.

| # | stage | status |
| --- | --- | --- |
| 1 | Type exists; names/kinds reserved; declaration guarded; overflow traps, never wraps | **DONE** (`f053b2ed`, `bf86b54e`) |
| 2 | Storage, checked arithmetic, `Write` — inline tier only | **DONE** (`a2b88243`, split to [[feature-a-promoint-stage2-storage-arith]]) |
| 3 | Promotion to heap bignum; demotion when it fits again | **DONE** (`2296b874`) |
| 4 | **Check elision** — range/induction analysis strips checks where values are provably bounded | **NEXT — open** |
| 5 | Variant integration (new tag, coercions, `VarClear`/`VarCopy`) + NilPy adoption | open |
| 6 | Pascal dialect exposure — opt-in, explicitly typed, no existing program changes behaviour | open |

**Where the work is now: stage 4.** Every promo op is currently a runtime call
(that is Option A of [[decide-promoint-rvalue-representation]], accepted
deliberately — see below). Stage 4 is what restores native speed for values
that never leave the inline tier. It is not an optimisation afterthought; it is
the other half of the stage-3 bargain.

### The stage-3 representation decision — settled, do not relitigate

[[decide-promoint-rvalue-representation]] resolved as **Option A: a promo
rvalue is the ADDRESS of a 2-word slot**, and every op is a runtime helper
taking slot addresses — the `tyVariant` model already proven in this codebase,
so all six backends work with no backend changes.

The slowdown is known and was accepted on purpose: correctness before
optimisation, and stage 4 was already scheduled to restore the fast path.
Options B (inline payload + guarded fast path) and C (16-byte by-value record)
were rejected as new value models — guessing wrong there means throwing the
work away, whereas A can only be slow, and slow is scheduled to be fixed.

**So: do not re-open the representation question as part of stage 4.** Stage 4
elides *checks* on top of A; it does not replace A.

### Blocked / filed separately (not stage-4 work)

- [[feature-a-promoint-wide-literals]] — a value cannot be WRITTEN past Int64
  yet (the lexer folds the literal first); blocked on
  [[bug-a-integer-literal-out-of-range-wraps-silently]].
- [[bug-a-qplus-misses-32bit-overflow]] — blocks `PromoInt32`, which stays
  declaration-blocked until its own-width trap is possible.

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

### Stage 2 split out

Stage 2 (storage, checked arithmetic, Write) is now its own ticket:
[[feature-a-promoint-stage2-storage-arith]], prio 85. This umbrella stays open
for stages 3-6 — see the renumbered table above, which is authoritative. (This
line originally said "stages 3-5" and then listed four things; that off-by-one
is what the renumbering fixed.)

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


### Stage 3 landed 2026-07-20 — arbitrary precision works

`2296b874`. Heap bignum tier via `compiler/builtin/promoint.pas`. 30! is exact,
values demote back to the inline tier when they fit, and a 60-case randomized
differential against CPython (`+ - * div mod`, negative operands and divisors,
values straddling the Int64 boundary) matches on every case.

Representation follows [[decide-promoint-rvalue-representation]] Option A
(answered): rvalue = slot address, tyVariant model, so all six backends work
with no backend changes. Lifetime rides the managed-AnsiString refcount, as
decided.

DCE gate verified, not assumed: a program that never names the type is 35 KB;
one that declares a `PromoInt` is 92 KB.

**Remaining, filed separately:**
- [[feature-a-promoint-wide-literals]] — a value cannot be WRITTEN past Int64
  yet (the lexer folds the literal first), blocked on
  [[bug-a-integer-literal-out-of-range-wraps-silently]].
- [[bug-a-qplus-misses-32bit-overflow]] — blocks `PromoInt32`, which is
  declaration-blocked until its own-width trap is possible.
- Stage 4 (check elision), stage 5 (variant integration + NilPy adoption) still
  open. Every op is currently a runtime call; stage 4 is what restores native
  speed for values that never leave the inline tier.


### Session close 2026-07-20 — what is done and what is left

**Done and green** (stages 1, 2 and "promotion" of the staged plan):
`bf86b54e`, `f053b2ed`, `d0f2bed8`, `a2b88243`, `2296b874`, `cb119351`,
`0adbb80d`. On 64-bit native targets `PromoInt` is a working arbitrary-precision
integer: declare, assign, `+ - * div mod`, compare, `Write`, wide literals past
Int64, negation, promotion to a heap bignum and demotion back. Verified by a
50-case randomized differential against CPython with literals up to 10^40.

Also fixed on the way, and a real bug for ordinary Pascal: over-range decimal
literals used to WRAP silently (`bug-a-integer-literal-out-of-range-wraps-silently`).

**Left, each with its own ticket:**
- [[feature-a-promoint-variant-integration]] — stage 4. Needed by the NilPy
  adoption. Design and the one per-backend hazard (`EmitVariantClear` only
  releases `VT_STRING`) are written up.
- [[feature-a-promoint-check-elision]] — stage 5, performance. Every promo op is
  a runtime call today.
- [[feature-a-promoint-32bit-bringup]] — the heap tier faults on 32-bit natives;
  the type is refused there rather than shipped faulting.
- NilPy adopting it as its `int` — the original motivation, deliberately after
  the NilPy refactor.


### Variant integration landed 2026-07-20 — `11f8b672`

Stage 4 done. Promo round-trips through a Variant, prints, and does not leak
(200k-iteration boxing loop holds at 264 KB). Inline values box as ordinary
`VT_INT64`; only heap values take `VT_PROMO_INT64` with a managed-AnsiString
decimal payload, which is what keeps `VarClear`/`VarRetain` a range test over
the reserved block instead of a switch in six emitters.

Now works on **aarch64** as well as x86-64, byte-identical output. That needed
dropping `IR_ZERO_SYM` for promo temps (aarch64 rejects it) in favour of a
`PXXPromoInit` runtime call — routing init like every other promo operation, so
the feature stays backend-free.

**Remaining:** [[feature-a-promoint-check-elision]] (perf — every op is still a
runtime call), [[feature-a-promoint-32bit-bringup]], and NilPy adoption after
the NilPy refactor. Variant ARITHMETIC where both operands are runtime-tagged
promos (no static type) is not wired — the compiler routes on static types
today; NilPy will need that and it belongs with the adoption work.

Filed on the way: [[bug-a-aarch64-managed-string-concat-leak]] — ordinary
Pascal, not promo, but it is what a promo bignum loop on aarch64 hits.


## FEATURE COMPLETE 2026-07-20

All five stages of the staged plan are done, plus the 32-bit bring-up.

| stage | state |
| --- | --- |
| 1. Type + trapping overflow | done (`bf86b54e` … `a2b88243`) |
| 2. Promotion (heap bignum) | done (`2296b874`) |
| 3. Check elision | done to 9x-of-Int64 (`b3f703b3`); true range analysis deliberately not attempted, see ticket |
| 4. Variant integration | done (`11f8b672`, `df786485`) |
| 5. Pascal dialect exposure | done — `PromoInt` is opt-in and explicitly typed |

Plus: wide literals past Int64 (`cb119351`), native-width type names
(`0adbb80d`), 32-bit natives (`67239e24`).

**Verified, not assumed:** a 50-case randomized differential against CPython
(`+ - * div mod`, negative operands and divisors, literals to 10^40); byte-identical
output on i386, aarch64 and arm32; the promo core also byte-identical on riscv32;
no leak over 200k variant boxings; and a program that never names the type shows
no size growth (35 KB vs 92 KB).

### Bugs this work found in EXISTING code, all filed separately

- [[bug-a-integer-literal-out-of-range-wraps-silently]] — FIXED. Over-range
  decimal literals wrapped silently, in ordinary Pascal.
- [[bug-a-aarch64-managed-string-concat-leak]] — open. `s := s + lit` in a
  function leaks on aarch64.
- [[bug-a-aarch64-variant-string-compare-always-false]] — open. Comparing two
  string Variants returns FALSE both ways on aarch64.
- [[bug-a-qplus-misses-32bit-overflow]] — open. `{$Q+}` only checks 64-bit ops.

### Left, low priority

- [[feature-a-promoint-variant-esp-targets]] — variant interop does not build on
  riscv32/xtensa (their gaps, not promo's; the promo core works there).
- NilPy adopting it as its `int` — the original motivation, deliberately after
  the NilPy refactor.

## Log
- 2026-07-20 — resolved, commit 933a8764.
