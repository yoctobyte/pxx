---
slug: bug-a-dce-refuses-every-target-except-x86-64
title: "`--dce` refuses every target except x86-64, so no cross target can strip anything"
track: A
prio: 70
type: bug
status: new
created: 2026-09-18
owner: ""
summary: "`dce.inc:226`: `if TargetArch <> TARGET_X86_64 then why := 'target is not x86-64'`, with the reason stated in the comment above it — \"the reference shapes this pass knows how to re-patch are x86-64's rel32 call/jmp. Every other target keeps its bodies.\" This is the FIRST gate in the function, so an ESP, aarch64, arm32, riscv32 or wasm32 build never reaches the frontend gate below it and never strips a byte. On x86-64 the pass is worth 44.7% of code (1,347,352 -> 745,240 measured); on xtensa it is worth nothing. Owner directive, 2026-09-17: \"strip code and associated data where possible.\" Cross targets are where stripping actually pays, and they are the ones it is switched off for."
---

# What

    compiler/dce.inc:226
    if TargetArch <> TARGET_X86_64 then why := 'target is not x86-64'

It is the first gate. Everything below it — `--shared`, `-g`, the frontend
check, the `.asm` entry override — is unreachable on a cross target.

The pass reports honestly: `off: target is not x86-64`. Nobody reads it, because
a cross build is usually being checked for correctness, not size.

## What it costs

Measured on x86-64, Pascal hello world: code 1,347,352 -> 745,240, **-44.7%**.
Nothing equivalent is available anywhere else.

The comment names the real work and it is not large: the pass compacts and
re-patches `Fixups`, `GlobFix`, `CallFix`, `ProcAddrFix`, `DynCall`, `CodeRef`
and `Procs[].BodyAddr`. What is x86-64-specific is the *reference shape* — rel32
call/jmp. Each other backend needs its own branch-patch arm:

- **riscv32** — `jal`/`auipc+jalr` pairs, 20-bit and 32-bit forms
- **xtensa** — `call0`/`callx0`, and the literal pool, which is the awkward part
- **aarch64 / arm32** — `bl` with a 26-bit / 24-bit signed displacement
- **wasm32** — not a displacement at all; function indices

## Note on what this does NOT fix

DCE drops unreachable procedure **bodies**. Measured 2026-09-18, it removes
**zero bytes of SRAM**: code 1,347,352 -> 745,240, data 86,084 -> 86,084, bss
66,796 -> 66,796. So porting it to xtensa shrinks flash, not RAM. The RAM half is
[[feature-a-unreferenced-class-rtti-keeps-every-method-alive]] and
[[bug-a-the-signal-alt-stack-is-32768-bytes-of-unconditional-bss]]. Do not file
this as the answer to the ESP SRAM question; it is the answer to the flash one.
