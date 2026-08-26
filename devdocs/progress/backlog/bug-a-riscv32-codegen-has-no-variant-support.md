---
track: A
prio: 25
type: bug
blocked-by: []
status: backlog
summary: "`var v: Variant; v := 1;` does not compile for --target=riscv32: `unsupported node in IR codegen: var_store`. Every other target (x86-64, i386, aarch64, arm32) compiles and runs the same program. Loud, not silent -- and it means any ticket claiming riscv32 'routes through PXXVarBinOpPas' is describing a path nothing can reach."
---

# riscv32 codegen has no Variant support

Found 2026-08-23 while cross-checking
[[bug-a-a-variant-comparison-does-not-coerce-a-stringy-operand]] across the
targets that share the `PXXVarBinOpPas` helper.

## Repro

```pascal
program tiny; var v: Variant; begin v := 1; writeln(v); end.
```

```
$ ./compiler/pascal26 --target=riscv32 -Fulib/rtl tiny.pas out
pascal26:1: error: target riscv32: unsupported node in IR codegen: var_store
```

x86-64, i386, aarch64 and arm32 all compile it and print `1`. Reproduces with
the PINNED binary as well as HEAD, so it is pre-existing, not a regression.

## Why it is worth a ticket rather than a shrug

Low priority — riscv32 is a bare-metal profile and variants are not what an MCU
program reaches for. But it is worth **recording** because two tickets already
describe riscv32 as one of the four targets whose variant binops "route through
`PXXVarBinOpPas`". They do not route anywhere: the program never gets past
codegen. Any cross-target agreement claim about variants covers **four** targets,
not five, and a session that assumes otherwise will look for a bug that cannot
exist.

`var_store` is likely not the only missing node — it is just the first one a
one-line program hits. Whoever takes this should enumerate the variant IR ops
against `ir_codegen_riscv.inc` rather than fixing the one the error names.

## Gate

Track A's, plus `tiny.pas` above compiling and running under `qemu-riscv32`,
and the variant differential in
`test/test_variant_comparison_coerces_a_stringy_operand.pas` producing `ALL OK`
there as it already does on the other four targets.
