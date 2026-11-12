---
track: A
tags: [O]
prio: 30
type: perf
blocked-by: []
summary: "Xtensa ran every Pascal integer binop on the a2:a3 pair: `z := z + 1` over Integers was a sign-extend-and-carry add, `i * j` was four multiplies (mull, muluh and two cross products), and pointer math written through Int64 was a pair add. riscv32's low-32 demand (d236b0481d, f09ac07a51) is now ported. Remote-thermostat S3 firmware .text 550,758 -> 511,230 B (-7.2%), with .data, .bss and .rodata unchanged. An `Integer * Integer` no longer needs --xtensa-soft-mulhigh to run on stock qemu."
status: done
owner: unassigned
---

# Xtensa kept the pair path where only the low word is kept

## Found

This came out of the 2026-11-12 optimisation inventory. The open ticket is
[[bug-o-every-integer-multiply-emits-four-multiplies-on-the-32-bit-backends-and-one-is-enough]].

A probe at HEAD found these multiply counts:

| target | multiplies |
|---|---|
| riscv32 | 1 (fixed by the October size work) |
| xtensa | 4 |
| i386 | 3 |
| arm32 | 3 |

On hosted xtensa, `q := i * j` still died with SIGILL (`muluh`) unless
`--xtensa-soft-mulhigh` was passed.

## Fix

The fix is the riscv32 design, ported. It has two parts.

**1. Low-32 demand (XtLow32Demand, XtExact32, XtNarrowBinop).** A store to an
integer of at most 4 bytes keeps only a2, and says so. The flag is read and
cleared at the top of IREmitNodeXtensa, so it reaches exactly the next node.
The binop under it then takes the 32-bit arm when that gives the same low
word:

- `+ - * and or xor` always narrow, and pass the demand to their operands.
- `div` and `mod` narrow only when both operands are exact 32-bit values of
  one signedness. Narrow 2 is signed and narrow 3 is unsigned. The 32-bit
  divide arm now takes that verdict instead of re-deriving it from the operand
  types: the case that must not be re-derived is `LongWord div Byte`, which is
  narrow 3.

A binop never narrows under {$Q+} (IRIVal = 1), because the overflow check
reads the high word. That is sound only because the store-side range test is
gated on the same flag. The comment at XtLow32Demand names this coupling.

**2. Addresses (EmitLow32Xtensa, XtWordOperand).** The demand is also set for
everything consumed as one register:

- the address of a load or store through memory;
- a field or index base;
- an index;
- a value stored through memory into at most 4 bytes.

The `+ - * and or xor` arm also accepts pointer and class operands, so
`PByte(Int64(p) + k)^` is one add.

## Measured

Remote-thermostat `src/thermo_esp.pas`, built as `build.sh` builds it for
esp32s3 (-O2, --emit-obj, WITH_METER), output to scratch:

| | .text | .data | .bss | .rodata |
|---|---|---|---|---|
| base (master 0c1d3409d1) | 550,758 | 1,104 | 15,964 | 56,304 |
| + low-32 demand at stores | 527,338 | same | same | same |
| + addresses | 511,230 | same | same | same |

The generated `s := s + 1` line in test-xtensa's xt_fwdjump fell from ~59 to
~31 bytes.

## Checked

- The self-rebuild reaches a fixedpoint at each stage.
- Two tests ran on hosted xtensa (windowed and call0, -O0 and -O2), and every
  run matches the x86-64 oracle:
  - test_rv32_low32_narrowing_keeps_64bit_answers, which covers wrap at the
    store, INT_MIN div/mod -1, negative div/mod, a 64-bit dividend,
    LongWord div Integer, and Int64 and QWord div/mod;
  - test_rv32_pointer_math_through_int64_is_32_bit.
- The low-32 test and test_esp_div_by_zero_yields_zero both match on IDF
  QEMU esp32s3. The test-esp-idf low32 row already uses S3 as its control.
- A mutation test confirms the signedness choice is covered: making narrow 2
  divide unsigned fails INT_MIN div -1 and the negative div/mod rows.
- The xtensa probe `q := i * j; if q = 63 then Halt(3)` used to exit 132
  (SIGILL) without --xtensa-soft-mulhigh. It now exits 3. The `+` control is
  unaffected.
- test-xtensa's xt_fwdjump body fell under 128 KiB, so its relaxation control
  went red, as that control is designed to. The generator now writes 6000
  lines instead of 3000. Both ABIs relax and print s=6000.
- test-xtensa and test-esp-idf: see the commit.

## Left

i386 and arm32 still emit 3 multiplies for `Integer * Integer`. They are not
ESP targets, so they stay with the umbrella ticket.
