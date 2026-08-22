---
slug: bug-a-strict-fpc-shr-by-zero-drops-the-sign
track: A
prio: 30
status: done
commit: 708e2e1e6
---

# `--strict-fpc`: a narrow `shr` by zero loses the operand's sign

```pascal
var i: Integer;
begin i := -16; WriteLn(i shr 0); end.
```

| | result |
| --- | --- |
| fpc 3.2.2 | `-16` |
| pxx, default dialect | `-16` |
| **pxx `--strict-fpc`** | **`4294967280`** |

A shift by nothing changed the value. Every count >= 1 was already correct
(`i shr 1` = 2147483640, matching FPC exactly), which is what kept this hidden.

## Cause

`--strict-fpc` reproduces FPC's shift widths: a narrow operand shifts at its
declared 32-bit width rather than at native width
(`decide-shift-operator-promotion-width`). The x86-64 emitter does that by
zero-extending the operand into `rax` (`mov eax, eax`) and shifting there.

But FPC's `shr` result **keeps the operand's type** — `LongInt shr n` is a
`LongInt`, signed. So the 32-bit answer has to be read back as signed. pxx left
it zero-extended, so the value was correct as a bit pattern and wrong as a
number.

Only a count of zero can expose that: `shr` by 1 or more always clears bit 31,
so the sign-extend that was missing would have been a no-op anyway. The bug was
one value wide.

## Fix

Three lines in `ir_codegen.inc`'s Pascal `shr` arm — after `shr rax, cl`, when
the operand *and* the result are narrow and the operand is signed, `cdqe` to
re-interpret the low 32 bits as signed. Costs one instruction on the strict path
only; the default dialect already takes the sign-extend branch before the shift
and never reaches it.

## Verification

`test/test_strict_fpc_shr_keeps_the_sign.pas`, wired into `test-core` and
**compiled twice**, once per dialect, because the two must disagree:

- `c0 v0 l0 s0 b0 q0 p0` — count zero via a literal and via a variable, on
  `Integer`, `SmallInt`, `ShortInt` and `Int64`, plus a positive operand. These
  agree in both dialects and with FPC: a shift by nothing is identity, whatever
  width it notionally happens at.
- `d1 d4 d31 d33` — counts >= 1, where the dialects **must** differ (default:
  native width, `-16 shr 1` = 9223372036854775800; strict: FPC's declared width,
  2147483640). Pinning only one mode would have let the other rot.

The strict-mode output is byte-identical to fpc 3.2.2 across all eleven rows.
`make compiler/pascal26` fixedpoint converged in 1 round; `tools/gate.sh quick`
green.

## Found by

A 34-program integer-arithmetic differential (div/mod with negative operands and
divisors, shifts across the full count range, wraparound at every width,
mixed-signedness comparison, `Int64`/`QWord` boundaries, `Hi`/`Lo`/`Swap`,
constant folding). Four rows diverged from FPC in the default dialect and all
four are the *decided* native-width behaviour — `decide-shift-operator-promotion-width`,
resolved 2026-08-10. Re-running those four under `--strict-fpc`, which that
decision says must reproduce FPC exactly, left two: this one, and a QWord
rendering bug that turned out not to be about shifts at all
(`bug-b-inttostr-of-a-qword-above-2-63-renders-negative`).

Everything else in the family matched: signed division truncating toward zero on
both operands' signs, all four wraparound widths, `Round`'s banker's rounding,
`not` on each unsigned width, `Abs(Low(Int64)+1)`, and 3037000500^2.
