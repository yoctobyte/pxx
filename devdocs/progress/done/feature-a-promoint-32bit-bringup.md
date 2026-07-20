---
track: A
prio: 55
type: feature
---

# Promotable int: heap tier faults on 32-bit native targets — FIXED

Split out of [[feature-a-promotable-int]] stage 3. The type is currently
refused on 32-bit natives with a pointed diagnostic rather than shipping
something that segfaults the moment a value gets large — which is precisely
when a user reaches for it.

## State

The INLINE tier works on i386. This runs and prints `479001600`:

```pascal
var a: PromoInt; i: Integer;
begin
  a := 1;
  for i := 1 to 12 do a := a * i;   { 12! fits 32 bits }
  Writeln(a);
end.
```

Adding `for i := 13 to 15 do a := a * i` — the first value that must promote to
the heap bignum — segfaults.

## It is the RUNTIME, not the lowering

Narrowed: `compiler/builtin/promoint.pas` fails on i386 called directly from
source, with no promo-typed variable and no compiler lowering involved:

```pascal
var s1, s3: array[0..1] of NativeInt;
begin
  PXXPromoFromInt(@s1, 4000000000);
  PXXPromoMul(@s3, @s1, @s1);        { must promote }
  Writeln(PXXPromoToStr(@s3));       { segfaults on i386, correct on x86-64 }
end.
```

So the bug is in the unit's own bignum core (base-1e9 limbs in
`array of Int64`) or in what it depends on, not in the promo IR lowering.

## Where to look first

The prime suspect is 64-bit arithmetic under ILP32 — see the existing landmine
that a 64-bit value is a REGISTER PAIR on 32-bit targets and both halves must
be folded. The bignum core does `a.limbs[i] * b.limbs[j]` (products up to
~1e18) and `cur div BIG_BASE` on Int64, which is exactly the emulated-64-bit
path. Check `BMul`, `BMulSmall` and `BDivMod` first, and establish whether this
is a promoint bug or an i386 codegen bug — if the latter it is a `bug-a-*`
ticket in its own right, not a promoint one.

Note the design intent this unblocks: the ticket's per-target default is
`promo32` on ESP/riscv32/xtensa precisely because those are the targets where
16 bytes per int hurts, and **NilPy on ESP is a project subgoal**. So this is
on the path to that, not a nicety.

## Gate

The x86-64 promo tests passing under `--target=i386` (and then the other 32-bit
natives), plus a differential against CPython on i386 like the x86-64 one.


## Resolved 2026-07-20

Root cause was **infinite recursion**, not ILP32 arithmetic (the 64-bit limb
math was measured correct on i386 first). `PXXPromoFromInt` spilled to
`StoreBig` when a value did not fit the NATIVE word; `StoreBig`'s demotion check
asked whether the result fit an **Int64**, which on a 32-bit target it did — so
it called `PXXPromoFromInt` again, which spilled again. It could not happen on
x86-64, where NativeInt is already 8 bytes, which is why it only ever showed up
on i386.

Fix: demote against the native word (`BToNative`) and write the inline payload
DIRECTLY instead of routing back through `PXXPromoFromInt`, so the recursion is
gone by construction. That also dropped a `BToStr` + `Val` decimal round trip
from every stored result.

Two more portability bugs fell out of testing the other targets:

- The variant helpers read a variant slot through `^NativeInt`. A VARIANT slot
  is 8-byte tag + 8-byte payload on EVERY target, unlike a promo slot which is
  two native words — so this worked on x86-64 by coincidence and read the wrong
  halves on i386. Added `PVarWord`/`VarPayloadAddr`.
- `in ['0'..'9']` is a standard builtin the riscv32 bare-metal path cannot
  lower; replaced with an explicit range test.

**Result:** the promo core (arithmetic, wide literals, promotion, demotion,
printing) is byte-identical to x86-64 on **i386, aarch64, arm32 and riscv32**.

Variant INTEROP additionally works on x86-64, i386, aarch64 and arm32. It does
not build on riscv32 or xtensa, on gaps that are **not promo's**: riscv32 has no
`Writeln` of a Variant ("write of this type not supported (hosted)") and xtensa
wants softfloat's `__pxx_d2i`. Filed as
[[feature-a-promoint-variant-esp-targets]].

## Log
- 2026-07-20 — resolved, commit HEAD.
