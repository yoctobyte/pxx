---
track: A
prio: 85
type: feature
---

# Promotable int stage 2 — storage, checked arithmetic, Write

Split out of [[feature-a-promotable-int]] once stage 1 landed. Stage 1 is done
and green: the type kinds, the frozen variant tag block, the slot size/align,
the storage discriminator, zero-init, and the reserved Pascal type names.

## State at handoff

Landed (all `--tier quick` GREEN + self-host byte-identical):

- `bf86b54e` — `tyPromoInt32` (27) / `tyPromoInt64` (28); `VT_PROMO_BASE = 8192`
  with a contiguous 8-entry reserved block; `TypeSize` 2 native words;
  `TypeIsPromoInt` / `PromoIntInlineBits` / `PromoIntVarTag` /
  `PromoIntDefaultKind`.
- `f053b2ed` — `PromoInt` / `PromoInt32` / `PromoInt64` named in the Pascal type
  resolver, **currently erroring** with a "not implemented yet" diagnostic.
- `d0f2bed8` — storage class keyed on the target's NATIVE int size (the slot is
  two machine words, so the payload is what the core adds in one instruction);
  `PROMO_TAG_INLINE = 0` / `PROMO_TAG_HEAP = 1`; zero-init so a fresh promo
  variable starts as inline 0 for free.

`AllocVar` needed no change — `TypeSize` already returns the two-word size and
`TypeAlign` derives 8 from it. That was verified, not assumed.

## Why the declaration is still guarded

Probed before deciding: `var a: PromoInt; a := 5` was accepted with **no
diagnostic** until `Writeln(a)` tripped the IR verifier's type-kind bound. So a
promo-typed symbol reaching codegen today is a silent-miscompile window — every
integer path would treat the `{tag, payload}` slot as a machine word and compute
on the tag. The guard in `parser.inc` (`OrdinalNameToTk`'s neighbour, the
`promoint` arm of the main type-name resolver) stays until step 1 below is real.

## Steps, in an order where each one ends green

1. **Slot access.** Lower a promo lvalue as payload-at-offset. Layout is
   `{tag at +0, payload at +wordsize}`; add `PROMO_PAYLOAD_OFFSET`. Remove the
   parser guard as the LAST action of this step, not the first.
2. **Store.** `p := <int expr>` — write the payload word, write
   `PROMO_TAG_INLINE`. Range-check the source against the inline width.
3. **Load.** Promo -> native int where the tag is INLINE. Nothing can produce a
   HEAP tag until stage 3, so the check is cheap to add and should be added
   anyway — it is what makes stage 3 a drop-in.
4. **Checked arithmetic.** `+` `-` `*` and the comparisons, trapping on
   overflow. **Reuse the existing `{$Q+}` machinery** rather than inventing one:
   `AN_BINOP` already carries an `ASTQChk` overflow-check tag (ir.inc ~5219) and
   the backends already emit the check. Lower a promo binop as a native-int
   binop with that flag forced on, then re-box. This is why trapping overflow is
   cheap here — do not hand-roll it.
5. **Write / Str** via the existing integer path while the tag is INLINE.

x86-64 first; the other backends should error explicitly rather than fall
through to integer codegen.

## Guardrails carried over from the umbrella ticket

- Keep it out of the C frontend — C99 `int`/`long` are fixed-width.
- Shared type does NOT mean shared operators: Python `//` floors toward −∞,
  Pascal `div` truncates. Operator semantics stay frontend-selected.
- No silent numeric widening: int->float of a huge value must raise.

## Gate

`--tier quick` + self-host byte-identical, plus a Pascal test that declares,
assigns, reads back and prints a `PromoInt`, and one that asserts overflow
RAISES rather than wrapping.

## Log
- 2026-07-20 — resolved, commit a2b88243.
