# `EmitAsmX64` has no `[base+index-register]` (SIB) form — fails safely, but with an unhelpful error

- **Type:** bug (asmtext.inc — diagnostics/coverage gap, low severity) — Track A
- **Status:** backlog
- **Opened:** 2026-07-01 (found during the ongoing `ir_codegen.inc` →
  `EmitAsmX64` migration, [[feature-asm-structured-ir-library]]; corrected
  same day — see Log)

## What's missing

`EmitAsmX64`'s memory-operand grammar (`compiler/asmtext.inc`, `AsmTextOperand`)
supports `[base]`, `[base+disp]`, `[base-disp]`, `[base+%]` (hole) — a single
base register plus an optional constant/hole displacement. It has **no
support for a second, index register** in the bracket (`[rsi+rcx]`, real
x86-64 SIB addressing with an actual index register, not just a
displacement).

## Corrected understanding (read this first)

This ticket originally claimed the gap was a **silent** miscompile hazard
(`[rsi+rcx]` quietly becoming `[rsi+0]` with no diagnostic). That was wrong —
caught and empirically verified same-day before landing on this description.
`AsmTextParseInt` (`compiler/asmtext.inc`, `~line 84`) already validates every
character of a displacement string and calls the (fatal — `Halt(1)`) `Error`
proc the moment it sees a non-digit, so `[rsi+rcx]` fails immediately:

```
$ EmitAsmX64('cmp byte [rsi+rcx], 0')
ERROR: EmitAsmX64: bad integer literal
```

Verified directly against the real `asmtext.inc`/`x64enc.inc` via the
`test_asm_emit_x64.pas` harness scaffold, not just re-read the source. So
there is **no silent-corruption risk** — the actual issue is smaller: the
error message says "bad integer literal", which doesn't tell the caller
*why* (that they used an index register, a form that isn't supported yet)
— a confusing message for whoever hits it next, not a safety hazard.

## Where it was found

While converting `EmitArgvToStringManaged` (`compiler/ir_codegen.inc`) to
`EmitAsmX64` — its inline strlen loop uses `[rsi+rcx]` for the byte scan,
left as raw `EmitB` (not mechanically convertible) specifically because of
this gap, plus separately because the same loop uses hardcoded
(non-`Patch`-tracked) short jump deltas whose values depend on the loop's
exact byte length.

## Scope

1. **Cheap: a clearer error.** When the displacement-position parse fails
   specifically because a register name appears there (as opposed to
   genuine garbage), raise `Error('EmitAsmX64: [base+index-register] (SIB)
   addressing not supported — write it as raw EmitB')` instead of the
   generic "bad integer literal". Low value, mostly a courtesy.
2. **Fuller (optional, only if a real site needs it): add real
   `[base+index]`/`[base+index*scale]` support.** Needs a second register
   token, an optional `*1/2/4/8` scale suffix, and real SIB-byte encoding
   (mod/base/index/scale) instead of the current base-only path. The one
   known site (`EmitArgvToStringManaged`'s strlen loop) doesn't need this —
   it's staying raw `EmitB` regardless, blocked also by its hardcoded jump
   deltas.

## Acceptance

- (If part 1 done) attempting `[base+index-register]` gives a message that
  names the actual unsupported construct.
- (If part 2 done) `[base+index]`/`[base+index*scale]` encodes correctly,
  verified against `llvm-mc`, with oracle-test coverage in
  `test_asm_emit_x64.pas`.

## Log
- 2026-07-01 — Opened with an incorrect "silent misparse" framing; corrected
  same day after empirically verifying `AsmTextParseInt` already rejects a
  register-name displacement with a fatal error. Rescoped from a safety bug
  to a minor diagnostics/coverage gap. Not blocking anything currently — the
  one site that hit it stays raw `EmitB` either way.
