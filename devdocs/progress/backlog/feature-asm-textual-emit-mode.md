---
prio: 53  # auto
---

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
- **Stale-ref note (2026-07-03):** the [[feature-asm-structured-ir-library]]
  emitter migration was REJECTED by user decision (see that ticket's log and
  [[feedback_no_emitter_migration_asmcore]]) — plan on the echo-from-
  `EmitAsmXxx` fallback as the real path, not "wait for the migration."

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
- 2026-07-01 — **x64 gap closed** (Track A), via a *different* mechanism than
  this ticket originally planned: not an echo-from-`EmitAsmXxx` capture
  (`ir_codegen.inc` only has 3 such call sites for x64, as the audit above
  found — genuinely too few to reach meaningful coverage that way), but a
  standalone **disassembler** (`compiler/asmdisasm_x64.inc`, new file,
  `DisOne`/`DisOneReal`/`DisParseModRM` + `WriteDisassemblyX64`) that decodes
  whatever bytes `ir_codegen.inc` already produced, *after* codegen finishes
  — for any source language (Pascal/C/etc.), not just `.asm`. `-S` writes an
  additional `<outFile>.s` text file alongside the normal binary (additive,
  not a replacement — `gcc -S`-style "instead of" was considered and
  rejected: producing *only* text with no working binary is less useful for
  a debug/diffing tool, and duplicating codegen's patch/relocation
  resolution to make a text-only path correct would have meant real new
  risk to the shared writer paths for no real benefit).
  - **Deliberate, load-bearing design choice over the ticket's original
    plan:** decode-after-the-fact instead of retrofitting `ir_codegen.inc`
    onto a textual intermediate. The rejected alternative would touch the
    single most central, most self-host-critical file in the compiler,
    shared by every source language — high risk for a readability feature.
    This file is 100% new and additive; it changes zero bytes of what any
    existing codegen path produces.
  - **Real x86-64 coverage, not a toy subset:** verified **zero**
    unrecognized-byte fallback lines across every available test category
    (arithmetic, control flow, floats/SSE2 double+single, threads, atomics
    -- lock/cmpxchg/xadd, records, string ops -- rep movsb/stosb/cmpsb,
    file I/O) *and*, as the real stress test, disassembling `-S
    compiler/compiler.pas` itself (~3.5 MB of `Code[]`, ~794,000 decoded
    instruction lines) with **zero** fallback lines and no crash. That
    coverage came from iterating against real `objdump -d` ground truth on
    actual compiled test programs, not from reading an ISA reference cover
    to cover — every opcode added was one this compiler's own backend was
    actually observed emitting.
  - **Explicitly does NOT satisfy this ticket's original round-trip
    acceptance criterion** ("emit `.s`, reassemble through
    [[feature-asm-source-frontend]], byte-identical to direct binary
    emission"). The disassembler's output format is a readable pretty-print
    for humans/diffing (labels resolved to proc names, `loc_<hex>` for
    unnamed targets, `lock`/`rep` prefixes as text) — it is not nasm-
    compatible `.asm` syntax and was never intended to feed back into the
    `.asm` frontend. If a true round-trip oracle is wanted later, it would
    need a *second*, syntax-compatible textual form (or the `.asm`
    frontend's parser widened to accept this format) — out of scope for
    what shipped here, which optimizes purely for "readable output for a
    human, cheaply and safely."
  - **Three real, previously-undiscovered pxx self-host compiler bugs found
    and worked around while building this** (all filed, none blocking):
    1. [[bug-const-open-array-param-stack-copies-caller-frame]] — a `const
       array of T` parameter stack-copies into the *caller's* frame instead
       of passing by reference; passing the compiler's own 8 MB `Code[]`
       array this way caused a genuine SIGSEGV (not just a warning) once
       actually run, caught only by testing the self-hosted binary against
       a real large program, not just checking that FPC/pxx accepted the
       *source*. Worked around by having the disassembler read the global
       `Code[]` directly instead of threading it as a parameter.
    2. [[bug-case-else-multi-statement-parse-error]] — `case ... else
       stmt1; stmt2; end` (an implicit multi-statement else, valid FPC/
       standard Pascal) fails to parse in pxx, which only accepts a single
       statement there. Diagnostically nasty: the reported error line
       pointed at the `case`'s closing `end`, nowhere near the real
       problem. Worked around with explicit `begin...end`.
    3. [[bug-const-array-of-ansistring-literal-too-many-elements]] — `const
       array[0..N-1] of AnsiString = (...)` literals fail "too many array
       constant elements" even with a hand-verified-correct count; no
       existing code in this self-hosting codebase had ever used the
       construct (confirmed by grep), so genuinely untested territory, not
       a usage mistake. Worked around with `case`-statement lookup
       functions instead (proven-safe, used pervasively already).
  - Verified self-hosted `pascal26 -S compiler/compiler.pas` runs cleanly
    (previously segfaulted before fix #1 above). `test/hello.pas` and
    `compiler/compiler.pas` disassembly checks (zero fallback lines) now in
    `make test` (`test-asm`). Full `make test` green; self-host bootstrap
    byte-identical.
  - **Acceptance status:** "produces readable assembly text for x86-64 end
    to end" — met, and exceeded (100% real-world coverage, not just "at
    least one representative program"). Round-trip reassembly acceptance —
    explicitly not met, see above; xtensa/arm32/aarch64/riscv32
    echo-from-`EmitAsmXxx` coverage — still open, unstarted, this session's
    goal was specifically the x64 gap.
