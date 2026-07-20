---
track: A
prio: 60
type: feature
---

# Promotable int inside a Variant

Stage 4 of [[feature-a-promotable-int]]'s staged plan. Stages 1-3 landed; the
type works fully in Pascal on 64-bit natives. This is the piece the NilPy
adoption will need, because Python is soft-typed and a value's type is not
always known statically.

The variant tag block is already reserved and frozen: `VT_PROMO_INT32` = 8192,
`VT_PROMO_INT64` = 8193, 8194-8199 held for the tagged family.

## Design (recon done, not yet built)

Keep the stage-3 posture: **route through runtime helpers, not per-backend
codegen.** That is what let stage 3 land on all six backends with zero backend
changes.

- `v := p` -> `PXXPromoToVariant(vAddr, pAddr)`. If the promo is INLINE, write
  an ordinary `VT_INT64` variant — nothing downstream needs to change for the
  common case. Only a HEAP promo writes `VT_PROMO_INT64`, with the payload
  being the same managed AnsiString the promo slot holds.
- `p := v` -> `PXXPromoFromVariant(pAddr, vAddr)`.
- Variant arithmetic, comparison and `VariantToStr` learn the new tag. Those
  live in `compiler/builtin/builtin.pas`, i.e. ordinary Pascal — no backend
  work.

## The one thing that DOES need per-backend work

`EmitVariantClear` (`ir_codegen.inc:812`, plus its siblings in the 386 /
aarch64 / arm32 / riscv32 / xtensa backends) releases the payload only when the
tag is exactly `VT_STRING`:

```
cmp qword [rax], VT_STRING
jne done
mov rax, [rax+8]
call AnsiStrRelease
```

A `VT_PROMO_INT64` variant carries an AnsiString payload, so as written it
would LEAK. Recommended fix: widen that equality to "is this tag
string-payloaded" — `VT_STRING`, or `>= VT_PROMO_BASE`. That is deliberately
why the promo tags were given a contiguous block: the test stays a range check,
not a growing switch, in six hand-written emitters.

Check `VarCopy`/retain for the mirror of the same hole before building.

## Gate

A `.pas` case putting a bignum-valued promo through a Variant and back, printing
it, and doing variant arithmetic on it; a leak check (the same value in a loop
must not grow RSS); `--tier quick` + self-host byte-identical + cross.
