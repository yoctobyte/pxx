---
slug: feature-rv32-constant-64-bit-shifts-and-literal-inline-arguments
track: S
type: feature
prio: 50
status: done
owner: ""
created: 2026-11-01
found-by: claude (remote_thermostat size audit)
blocked-by: []
summary: "riscv32: a 64-bit shift by a constant is now the fixed 3-4 instruction sequence (12 bytes, was the 72-byte variable-count path), and an integer literal argument to an inlined routine stays a literal even beside an impure argument, so `Sar(x * 7, 11)` reaches that path. Fixed on the way: an integer argument substituted into an inlined Double parameter printed 0.0 at -O3 on aarch64/i386/arm32."
---

# rv32 constant 64-bit shifts, and literal inline arguments

Part of feature-code-size-int64-arith-and-string-building (still open).

## What changed

1. **compiler/ir_codegen_riscv32.inc, EmitBinop64RISCV32**: `shl`, `shr`
   and `SarInt64` by a constant count emit the fixed sequence (count >= 32:
   one shift plus a zero/sign fill; count < 32: shift both halves and OR in
   the carried bits). Narrow left operands keep their slot semantics (the
   high word is zero- or sign-filled from the low word). Before, every
   64-bit shift went through the variable-count path with its branches on
   `count >= 32`: 72 bytes against 12.
2. **compiler/ir.inc, IRInlineExpand**: an `AN_INT_LIT` argument is
   substituted directly even when another argument is impure or the body
   calls out. It reads nothing, so no side effect can change it, and a
   retained body never writes a parameter. Before, one impure argument
   captured every argument into a temp, which hid `Sar`'s count from the
   backend: BmpTemp kept 8 variable-shift sequences after change 1.
3. **Same place, a pre-existing bug**: an integer argument (literal or
   pure ident) for a FLOAT parameter is no longer substituted, because the
   body was typed with the parameter as a float and `x + d` is a float add.
   aarch64, i386 and arm32 read the integer node as float bits:
   `AddD(v, 3)` printed 0.0 at -O3 on latest-51fdc7bb8b; x86-64 and
   riscv32 converted per operand and hid it. The temp path converts on the
   store.

## Numbers

remote_thermostat, esp32c3, -O2, `--emit-obj` of src/thermo_esp.pas
(2026-11-10, the app as it is that day; latest-51fdc7bb8b against dev with
this change):

| | latest | this change |
|---|---|---|
| code | 280,930 B | 277,562 B (−3,368) |
| data / bss (RAM) | 62,640 / 15,964 B | unchanged |
| BmpTemp | 1,804 | 1,028 |
| BmpPress | 3,276 | 1,976 |

## Tests

- test/test_rv32_a_constant_64_bit_shift_is_the_fixed_sequence: 8 values
  × counts 0..65, Int64/QWord shl/shr/SarInt64 plus narrow shr; riscv32
  -O2 and -O0 rows. Oracle is FPC (= the old rv32 path); not an x86-64
  oracle, because pxx shifts at native width (owner ruling 2026-08-10).
- test/test_an_inlined_literal_argument_stays_a_literal_beside_an_impure_one:
  -O0 output is the oracle; -O3 rows on x86-64, riscv32, aarch64, i386.
  Positive control: latest fails the `AddD(v, 3)` line on aarch64 and i386.
  Also checked by hand: arm32 -O2/-O3, and FPC gives the same output.
