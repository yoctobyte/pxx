---
summary: "`><` (set symmetric difference) did not lex — every use died with `expected expression`; added as tkSymDiff through the additive level, IR_SET_BINOP and all five backends that implement sets"
type: bug
prio: 40
track: P
---

# `><` (set symmetric difference) was not supported

- **Type:** bug / small feature (Pascal frontend + shared IR + backends).
  Track P for the lexer/parser half; the IR and backend arms are Track A ground
  (held by the same agent, sole-A confirmed).
- **Status:** done
- **Found:** 2026-08-16, Pascal oracle sweep vs `fpc -O- -Mobjfpc` (sets topic).

## Symptom

```pascal
ds := ds >< es;
```
```
pascal26:6: error: expected expression
  near:   ds  ds  >>>  es
```

A refusal only pxx makes — FPC and Delphi both have `><`, and it is the only
set operator we lacked (`+`, `-`, `*`, `=`, `<>`, `<=`, `>=`, `in` were all
there). Loud rather than silent, which is why it survived: nothing miscompiles,
the program just does not build.

## Fix

- `compiler/defs.inc` — `tkSymDiff` **appended at the tail** of the token enum
  (ordinals are frozen by the self-host discipline, same rule as tkPowEq/tkAtEq).
- `compiler/lexer.inc` — `>` followed immediately by `<` lexes as one token. No
  other Pascal construct puts `<` right after `>`: a nested generic closes `>>`,
  and `<` never begins an operand.
- `compiler/parser.inc` — added to the **additive** level (`tkPlus, tkMinus,
  tkOr, tkXor`), which is where FPC puts it. The existing set arm already types
  a binop with a set operand as `tySet`, so nothing else changed, and the
  operands are lowered once each like every other set binop.
- The five backends that implement `IR_SET_BINOP` each got the xor arm beside
  their or/and/bic: `xor rax,rcx` (x86-64), `xor eax,ecx` (i386),
  `eor x4,x4,x5` (aarch64), `eor r4,r4,r5` (arm32), `rv32_xor` (riscv32).
  Xtensa implements no set ops at all — a pre-existing gap, untouched.

## Gate

`make compiler/pascal26` fixedpoint; `tools/gate.sh quick` GREEN;
`test/test_set_symmetric_difference.pas` (commutativity, involution,
`x >< x = []`, precedence against `+`, operands evaluated exactly once, and a
char set exercising the high bytes of the 32-byte payload) matches
`fpc -O- -Mobjfpc` byte for byte — natively **and** under qemu on all four
cross targets (i386, aarch64, arm32, riscv32).
