---
track: A
prio: 25
type: bug
blocked-by: []
status: done
summary: "`var v: Variant; v := 1;` does not compile for --target=riscv32: `unsupported node in IR codegen: var_store`. Every other target (x86-64, i386, aarch64, arm32) compiles and runs the same program. Loud, not silent -- and it means any ticket claiming riscv32 'routes through PXXVarBinOpPas' is describing a path nothing can reach."
owner: claude-A-S
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


---

## Resolution (2026-08-27)

Enumerated rather than fixing the one op the error named, as the ticket asked.
`var_store` was the first of **four** missing pieces, not the only one — each
found by re-running the repro after the previous one landed:

| missing | symptom |
| --- | --- |
| `IR_VAR_STORE` | `unsupported node in IR codegen: var_store` — the filed one |
| `IR_LOAD_SYM` for a `tyVariant` symbol | a variant in value position tried to LOAD a 16-byte slot into one register instead of yielding its address |
| the write dispatch | `write of this type not supported (hosted)` on `writeln(v)` |
| `IR_VAR_BOX` / `IR_VAR_BINOP` | reached only once a store compiled |

### What landed

Six helpers plus three arms in `ir_codegen_riscv32.inc`, modelled on **arm32**
— the 32-bit peer with the same 16-byte slot (tag +0, zero word +4, 8-byte
payload +8) — and not on aarch64, whose payload is one register.

The 32-bit-specific hazards, each handled explicitly because each has been a
real bug on a sibling target:

- an **Int64** payload reaches the slot whole via `EmitNode64RISCV32` (the
  i386/arm32 twins stored only the low word once —
  `bug-a-an-int64-assigned-to-a-variant-truncates-to-32-bits-on-i386-and-arm32`);
- the **high word comes from the payload's TYPE, not the tag**: signed 4-byte
  payloads sign-extend, unsigned zero-fill, because `tyNativeInt` maps to
  `VT_INT64`;
- a **float** goes through `EmitFloatOperandRISCV32(_, tyDouble)`, the one
  routine that widens a Single and materialises an integer source on a target
  with no FPU, so `VT_DOUBLE` always gets 8 bytes of real IEEE double bits;
- a **boxed string** skips the retain when the source is already an owned
  concat/call result (`bug-a-runtime-variant-heap-grows-unbounded`);
- **`VT_CALLABLE_TAG`** overrides the type-kind answer, matching x86-64 / i386 /
  aarch64. arm32 does *not* do this — a pre-existing arm32 gap, noted, not
  touched here.

`PXXVarBinOp`'s five arguments all land in `a0`-`a4`: riscv32 pushes call
arguments and then loads `a0..a7` from the block, and five is under the
eight-word spill line, so no stack argument is needed the way arm32 needs one.

### Verification — against qemu, not by inspection

The ticket's own repro runs and prints `1`. Beyond it: `test_cross_variant`
and `test_cross_variant_single` were **SKIPped on riscv32** in the Makefile
with the comment "backend feature gap" — this bug was that gap, and both are
un-skipped and now differential-green against x86-64. The gate's named file,
`test_variant_comparison_coerces_a_stringy_operand.pas`, produces `ALL OK`
under `qemu-riscv32`, which is what proves `PXXVarBinOpPas` is genuinely
*reached* here for the first time.

New: `test/test_cross_variant_payload_widths.pas`, one row per hazard above,
run as a differential so the expectations are a 64-bit target's answers rather
than a hand table. Verified identical on **i386, arm32, aarch64 and riscv32**,
so it guards the whole 32-bit family, not just this fix.

### Filed, not chased

[[bug-a-a-variant-assigned-to-itself-becomes-empty]] — `v := v` EMPTIES the
variant on **every** target (pinned included; FPC leaves the value). riscv32
matched the x86-64 oracle on that row because the oracle is wrong too. Root
cause is pinned down in that ticket: the retain-before-clear guards the
payload's refcount, `PXXVarClear` then `PXXMemZero`s the 16 slot bytes it is
about to be the source of, and the copy copies the zeros. Six backends plus the
runtime, and no business riding along here.

## Log
- 2026-08-27 — resolved, commit 57ba5677a.
