---
track: A
prio: 40
type: feature
---

# Promotable int in a Variant: riscv32 / xtensa

Split from [[feature-a-promoint-32bit-bringup]]. The promotable int's own
arithmetic works on riscv32 (byte-identical to x86-64); only the VARIANT interop
does not build there, and for reasons that are not promo's.

## What fails

```
--target=riscv32 : error: target riscv32: write of this type not supported (hosted)
--target=xtensa  : error: compiler error: __pxx_d2i not found (uses softfloat?)
```

The riscv32 one is `Writeln` of a Variant — pre-existing, nothing to do with the
promotable int. The xtensa one is a softfloat entry point pulled in by the
variant runtime.

## Note the priority

Deliberately low. The umbrella ticket's reason for caring about these targets is
`promo32` on ESP for NilPy, and the promo CORE already works there — it is the
Variant tier that does not, which matters only once NilPy's soft-typed values
land on ESP. Do not confuse this with the core being broken.

## Gate

`test_promoint.pas` (the full one, including its Variant section) compiling and
matching x86-64 output on riscv32 and xtensa.

## Note 2026-08-02 — the xtensa half is a LINK gap, not a missing helper

`--target=xtensa : compiler error: __pxx_d2i not found (uses softfloat?)` reads
like an unimplemented conversion. It is not:

- `__pxx_d2i` **is implemented**, in `compiler/builtin/softfloat.pas:49`
  (alongside `__pxx_i2d`, `__pxx_d2i64`, `__pxx_d2i64_rne`).
- The xtensa backend **already calls it** —
  `ir_codegen_xtensa.inc:1665-1666` emits `__pxx_d2i` / `__pxx_d2i_rne`
  through `EmitFloatUnaryCallXtensa`.

So both ends exist and the symbol simply is not resolved in this build
configuration: the softfloat unit is not pulled in when Variant interop needs it
on xtensa. That makes this a unit-inclusion question rather than a codegen
feature, and likely much smaller than the error text suggests.

(Recorded while assessing what genuinely blocks xtensa now that the user has
made it the primary ESP target — see
[[feature-xtensa-stack-args-over-6-words]].)
