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

## 2026-07-21 (session 5f): promo BITWISE landed; NilPy adoption is all-or-nothing

**Landed (commit 90b95e47): promoint bitwise ops** — PXXPromoAnd/Or/Xor/Shl/Shr
with Python two's-complement semantics (AND/OR/XOR via a fixed-width
two's-complement byte view, SHL = ×2^k, SHR = floor ÷2^k). Routed through
PromoOpHelper. Verified in Pascal: `(4-5) and 2^64-1` = 2^64-1, unsigned compare
crosses, `1 shl 64` = 2^64. This is the arithmetic the mask idiom needs, and it
is correct and self-host-green.

**Wiring it into NilPy for uforth was attempted and REVERTED** — it works for the
isolated idiom but poisons uforth's whole stack, because of one line:

```python
def push(self, value):                 # uforth.py:417 — called for EVERY push
    if isinstance(value, int) ...:
        value = value & 0xFFFFFFFFFFFFFFFF     # -> promo
        if value >= 0x8000000000000000:
            value -= 0x10000000000000000       # sign-convert back to int64
    self.stack.append(value)
```

Findings from the attempt (all real, all needed for a correct full adoption):
1. **Nested-def params are typed concrete, not variant.** uforth's `_loop_crossed`
   is nested, so `(old-lim) & mask` is a SCALAR binop; a variant-only promo path
   never fires. Both scalar and variant binop lowering must promote on a wide-lit
   operand.
2. **`push()` masks EVERY value**, so a partial promo makes every stack cell a
   promo. That is fine ONLY if the value demotes back to inline int64 — which the
   sign-conversion does... except `0x10000000000000000` (2^64) exceeds UInt64 and
   was gated OUT of promo, so `value -= 2^64` subtracted 0 and left a HEAP promo on
   the stack. Heap promos then (a) don't round-trip through a TPyList slot (managed
   AnsiString payload, container-slot landmine) and (b) hard-fail
   `VariantToInt64` at every int boundary (address, count).
3. So the wide-literal-as-promo rule cannot be capped at UInt64 — it must cover
   ANY size (the whole point of arbitrary precision), and the range check at
   ir.inc:3701 must let a promo-typed literal through instead of erroring.
4. `PyWiden` needed promo rules (promo+variant→variant since promo boxes into a
   variant; promo+int→promo) — that part was correct and is the model to keep.

**Conclusion: this is the DECIDED full promotable-int adoption, not a surgical
patch.** For uforth to run, a masked cell must promote AND demote cleanly through
`push`/containers/int-boundaries — i.e. NilPy ints become tier-2 promotable by
default (the decision doc's model), with promo values that survive a container
slot and coerce at int boundaries. That is a large Track A change (blast radius:
shared binop typing, IRLowerAST of a promo literal, container promo storage,
VariantToInt64 demotion). The bitwise runtime is now in place for it.

## What already works (2026-07-21)

uforth compiles unmodified, STD.UFO fully loads, VARIABLE/CONSTANT/memory words
run (`VARIABLE Q 42 Q ! Q @ .`=42, `100 8192 ! 5 8192 +! 8192 @ .`=105, `BL .`=32),
and the prelim suite executes and matches the CPython oracle byte-for-byte through
Pass #21. Only the unsigned-cell arithmetic above is missing.

## RESOLVED 2026-07-21 (session 5g) — full adoption landed, gate met

Commits f058b95b (adoption) + e2eb2ade (Low(Int64) family + pyeval bignum).
Design as decided: a wide literal (any size) is a promo-typed literal
(pylexer digit text -> parser tyPromoInt64 under PyExprMode); PyWiden carries
promo infectiously (promo+int -> promo, promo+variant -> variant); shifts of
machine ints always type promo (1<<64, arithmetic >>); the variant binop maps
bitwise ops 6-10 into PXXPromoVarArithTry (shl/shr fire even on two inline
operands, NilPy-only); promo narrows mod 2^64 at concrete-int boundaries
(PXXPromoToInt64Wrap — assignment, call args, pyvar_to_int, PyToI64), which
is exactly what makes the mask-and-sign-convert idiom an identity.

Gate: mask snippets CPython-identical; push_norm round-trips demote to inline
VT_INT64 through TPyList; `: T 0 5 0 DO 1+ LOOP ; T .` = 5; prelim suite
byte-identical to CPython (0/57); core.fr arithmetic 0 INCORRECT to line 639.
Self-host byte-identical, quick 11/11, test-nilpy/test-uforth/promoint green.

Follow-on (not this ticket): tick/EXECUTE xt wall in core.fr:640 — see
[[feature-nilpy-corpus-uforth]]. Residual known narrowings (documented, not
bugs): compiled-NilPy scalar `//` of Low//-1 still idiv-traps (pylib
pyfloordiv_v, no promoint dep); additive int64+int64 overflow does not
promote unless a wide literal infects the expression (uforth's mask
discipline makes this invisible; CPython-differential print(c+c+1) still
wraps).

## Log
- 2026-07-21 — resolved, commit e2eb2ade.
