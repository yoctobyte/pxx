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
