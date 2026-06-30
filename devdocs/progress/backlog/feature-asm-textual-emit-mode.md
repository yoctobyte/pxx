# Codegen: emit human-readable assembly text instead of raw bytes

- **Type:** feature (codegen / diagnostics) — Track A
- **Status:** backlog
- **Opened:** 2026-06-30 (scope corrected same-day — see Log)
- **Relation:** part of [[feature-assembler-first-class-citizen]]; benefits
  from [[feature-asm-structured-ir-library]] but is more independent than
  first thought (see below); pairs with [[feature-asm-source-frontend]] for
  the round-trip validation below.
- **Owner split (2026-06-30):** once [[feature-asmcore-encoder-library]]
  (Track B) ships a textual printer per target and
  [[feature-asm-structured-ir-library]] (Track A) migrates codegen onto it,
  this mode is mostly "call the printer" — cheaper than the interim
  echo-from-`EmitAsmXxx` approach described below, which is the fallback if
  this mode is needed before the library migration lands.

## Corrected understanding (read this first)

Originally scoped as "pretty-print a new IR" — wrong, because the IR isn't
new (see [[feature-asm-structured-ir-library]]). More useful framing: every
`ir_codegen*.inc` backend that already calls `EmitAsmX64`/`EmitAsm386`/
`EmitAsmA64`/`EmitAsmArm32`/`EmitAsmRv32`/`EmitAsmXtensa` (`compiler/
asmtext*.inc`) is **already being told, in readable mnemonic text, what
instruction to emit** — the text is the literal Pascal string the codegen
author wrote. Capturing it is mostly "echo the line (with `%`/`@glob`/`@data`
holes substituted) to a side buffer when a flag is set" inside those six
`EmitAsmXxx` entry points — not a new pretty-printer.

**The catch:** coverage is uneven (2026-06-30 audit, call sites per backend):
`ir_codegen.inc`(x64) 3, `ir_codegen386.inc` 4, `ir_codegen_aarch64.inc` 10,
`ir_codegen_arm32.inc` 16, `ir_codegen_riscv32.inc` 11,
`ir_codegen_xtensa.inc` 40. xtensa/arm32/aarch64/riscv32 route most of their
instruction emission through the text engine already, so textual dump is
close to "just add the echo" for them. x64/i386 (older backends) mostly call
the typed `x64enc.inc` encoders or raw `EmitB` directly, bypassing the text
layer entirely — for those targets, full-coverage textual emission needs
*either* broadening `EmitAsmX64`/`EmitAsm386` call-site usage (more codegen
ported onto the text engine — real, possibly unwanted churn) *or* a separate
lightweight "describe what I just encoded" hook at the typed-encoder layer
(less invasive, lower fidelity — no source mnemonic to echo, would need to
decode-and-describe instead). Pick one before estimating size.

## Goal

A compiler flag (`-S` / `--emit-asm`, naming TBD) makes a target backend emit
readable assembly text — mnemonics, symbolic labels, comments — instead of
(or alongside) raw object bytes. Accepted cost: a text pass is slower than
direct byte emission, but compile-time cost lives elsewhere in the pipeline,
not the final encode step, so this is cheap relative to the readability win.

## Why this matters beyond readability

Once [[feature-asm-source-frontend]] lands, this mode becomes a correctness
oracle: emit `.s` text for a test program, reassemble it through the new
`.asm` frontend, and diff the resulting bytes against direct binary emission
for the same program. Byte-identical output proves both the textual emitter
and the assembler frontend are faithful to the real encoding.

## Scope

- Start with the high-coverage backends (xtensa, arm32, aarch64, riscv32)
  where the echo-from-`EmitAsmXxx` approach gets near-full textual output
  almost for free.
- Decide and scope the x64/i386 gap (broaden text-engine usage vs. typed-
  encoder decode-and-describe) as an explicit follow-up once the cheap wins
  above are landed and the real effort/value tradeoff is visible.

## Acceptance

- `-S` (or chosen flag) on a representative test program produces readable
  assembly text for at least one high-coverage target (e.g. xtensa or
  arm32) end to end.
- Once [[feature-asm-source-frontend]] lands: round-trip
  (compile → emit text → reassemble) is byte-identical to direct binary
  emission for at least one nontrivial program on that target.
- No change to default (non-`-S`) codegen output or self-host byte-identity.

## Log
- 2026-06-30 — Opened, then corrected same-day after the
  [[feature-asm-structured-ir-library]] audit showed the codegen text engine
  already exists; rescoped from "build a pretty-printer" to "expose what's
  already there, fill the x64/i386 coverage gap." (Track B, filing Track
  A-scope ticket per convention.)
