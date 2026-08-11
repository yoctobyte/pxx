---
track: A
prio: 30
type: bug
blocked-by: []
---

# `--strict-fpc` does not reproduce FPC's shift widths

- **Type:** bug (an advertised strict mode that is not strict) — **Track A**
- **Opened:** 2026-08-11, completing
  [[bug-a-shr-on-a-32-bit-operand-does-not-promote-like-fpc]].

[[decide-shift-operator-promotion-width]] has two halves. The default half —
shifts at NATIVE width, no truncation — landed. The other half did not:

> "**`--strict-fpc`: reproduce FPC exactly**, asymmetry and all — `shr` widens
> the operand to 64, `shl` masks the count to 5 bits at 32-bit width, and the
> constant folder keeps its own 64-bit answer. Explicitly 'copy their bugs'."

Today `--strict-fpc` shifts exactly like the default dialect, so the escape
hatch the decision promised anyone porting FPC bit-twiddling does not exist.

## What it has to reproduce (measured, `fpc 3.2.2 -O1 {$mode objfpc}`)

| row | FPC | pxx default |
| --- | --- | --- |
| `i shr 1`, `i: Integer = -8` | 2147483644 | 9223372036854775804 |
| `i shl 31`, `i: Integer = 1` | -2147483648 | 2147483648 |
| `l shr 9`, `l = -2147483648` | 4194304 | 36028797014769664 |
| `l shl 1`, `l = -2147483648` | 0 | -4294967296 |
| `a shl b` (8 shl 40, both vars) | 2048 (count masked mod 32) | 8796093022208 |
| `1 shl 40` (const fold) | 1099511627776 | 1099511627776 |
| `-8 shr 1` (const fold) | 9223372036854775804 | 9223372036854775804 |

Note the last two: FPC's own constant folder does NOT mask or narrow, so strict
mode must keep the fold at 64 bits while the runtime path narrows — the
asymmetry the decision means by "copy their bugs".

## Where the code is

The width choice is one place now: the shift arm of the binop typing in
`parser.inc` (`op = tkIdent` / `tkShl`) decides the RESULT type, and both
backends' shift emitters obey it — a narrow result narrows, an 8-byte result
does not. So strict mode is that arm keeping `ASTTk[left]`, plus the count-mask
for `shl`, which no backend emits today.

## Gate

Every row above matching `fpc -O1` under `--strict-fpc`, the default dialect
unchanged (`test/test_shr_width.pas`, `test/test_shift_operand_width.pas`), and
self-host byte-identical.
