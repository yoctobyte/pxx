---
track: A
prio: 60
type: regression
summary: "the -S disassembler had no comisd or xorpd, so the Trunc/Round saturation sequence printed `db 66 / db 0f / db 2f` and test-asm's no-undecoded-bytes check went red on hello.pas and compiler.pas"
commit: 2e267df1a
---

# `-S` could not decode the saturation sequence

- **Type:** regression (Track A), self-inflicted and self-fixed
- **Found:** 2026-08-15, from Track T's tstate — two open regressions,
  `test-asm#src:test/hello.pas` and `test-asm#src:compiler/compiler.pas`,
  bisected to a 5-commit range containing
  [[bug-a-trunc-of-a-huge-float-returns-int64-min]]'s fix.

`make test-asm` ends with two `-S` (built-in disassembler) checks that assert
the output contains **no `db ` lines** — i.e. that every byte the compiler
emits, the compiler can also read back. `EmitF2ISaturateX64` introduced two
instructions the disassembler had never been shown:

| bytes | instruction | why it appeared |
| --- | --- | --- |
| `66 0F 2F` | `comisd` | picks the saturation direction |
| `66 0F 57` | `xorpd` | makes the zero xmm to compare against |

`ucomisd` (`66 0F 2E`) was decoded; its ordered twin was not, which is exactly
the sibling-case smell `normalise-dont-special-case` warns about — one arm of a
two-arm opcode pair.

## Fix

Both added to `compiler/asmdisasm_x64.inc`, with `comisd` folded into the
existing `ucomisd` arm rather than given its own (they differ only in whether a
quiet NaN raises, and the decode is identical). `hello.pas` and
`compiler/compiler.pas` both disassemble with **zero** `db ` lines again, and
the `-S` output now names the instructions.

The saturation behaviour is unchanged —
`test/test_cross_trunc_round_saturate.pas` still passes.

## Why this was invisible to the per-fix loop

`test-asm` is not in `--tier quick`, by design: breadth is Track T's job. This
is that split working — T bisected it to a 5-commit range and named the two
jobs, which is what made the cause obvious on sight. The lesson is not "widen
the gate"; it is that a new EMITTED instruction should be checked against the
disassembler, since the compiler is its own oracle there.

## Gate

`compiler/pascal26 -S test/hello.pas` and `-S compiler/compiler.pas` producing
no `db ` lines (the two assertions test-asm makes), the saturation test
unchanged, `tools/gate.sh quick` GREEN and self-host byte-identical.
