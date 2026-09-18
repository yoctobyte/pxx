---
slug: bug-a-dce-refuses-every-target-except-x86-64
title: "`--dce` refuses every target except x86-64, so no cross target can strip anything"
track: A
prio: 70
type: bug
status: working
created: 2026-09-18
owner: ""
summary: "FOUR OF SIX TARGETS DONE (2026-09-18, frankB): x86-64 as before, plus **riscv32, i386 and xtensa (both ABIs)**, each verified by RUNNING the binary under qemu, not by linking it. THE PRESCRIBED WORK BELOW WAS WRONG AND IS CORRECTED IN ITS OWN SECTION: no backend needed a branch-patch arm written — `ApplyCallFixups` has been fully architecture-aware all along. The real defects were an x86-64 rel32 written over encoded branch WORDS, ~30 stub calls emitted outside every fixup table on the premise that \"the target is final at emit time\" (true of the target, false of the site), a dropped `CallFixAnchor` column, and — xtensa only — CODE ALIGNMENT: a hole whose size is not a multiple of 4 re-aligns every later body, and CALL0/CALL8 require a 4-aligned target. REMAINING: arm32, aarch64 (each needs only its hand-built `SigInstallAddr` branch recorded; the patcher arms already exist) and wasm32 (genuinely different — function indices, not displacements). Owner directive, 2026-09-17: \"strip code and associated data where possible.\" Measured wins: riscv32 880020B->198572B, i386 456290B->86626B, xtensa call0 694520B->161840B / windowed 613087B->140323B."
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


# CORRECTED 2026-09-18 (frankB) — the work list above sends you to write arms that exist

The section "What it costs" says each backend "needs its own branch-patch arm"
and lists five. **Measured: none of them did.** `ApplyCallFixups`
(`symtab.inc:17963`) is already fully architecture-aware — arm32 `$EB000000`,
aarch64 `$94000000`, xtensa `call8`/`call0` with the literal-pool arm and
`XtensaCallReaches`, riscv32 `RISCVPcrelSplit` + `auipc` + `jalr` across both
words, and `else` = x86-64 rel32. **DCE has been calling it at `dce.inc:589`
the whole time.** A reader who takes that list literally writes a fifth copy of
code that is already there, which is why this correction is at the top rather
than in the history below.

What the gate was actually protecting, and its one-line reason named it exactly
("the reference shapes this pass knows how to re-patch are x86-64's rel32
call/jmp"):

**1. The CodeRef re-patch, not the CallFix one.** `dce.inc` re-aimed every
recorded code->code reference with `Patch32(pos, target - (pos + 4))`. On
riscv32 that slot is a JAL, whose displacement is scattered across the
instruction word; DCE wrote the new offset 32988 as a plain little-endian word
over `5394006f`. The program executed four instructions of the entry stub and
fell into `c.lbu a5,1(s1)` + an illegal instruction — SIGSEGV at `si_addr=0x1`,
before any syscall. Fixed by extracting `PatchCodeRefSlot` out of
`PatchProgramEntryJump`, which already had the full arm set including riscv32.

**2. Stub calls that no fixup table knows about — THIS is the per-target work.**
`EmitRiscv32CallToCode` emitted its call with no CallFix and no CodeRef, on the
stated premise that "the target is final at emit time". That is true of the
TARGET and false of the SITE: DCE deletes bodies and every call site after a
hole slides down. Ten sites. Measured, the main body's SIGINT install ran as
`jal ra,-265220` into unmapped memory at `0x0800f588`.

**The xtensa note at `symtab.inc:17878` predicted this in writing** — *"if DCE
ever grows an xtensa arm, these sites need their own fixup list before it
does"* — and it was right about its sibling target too.

## What each remaining target needs, and it is the same thing

`EmitDefaultSignalInstallForTarget` (`ir_codegen.inc:1486`) is the census: every
target except x86-64 hand-builds its branch to `SigInstallAddr` inline, and
**none of them record it**. x86-64 is the only one that goes through
`IREmitCodeCall`, which records. So:

- **i386** — `EmitB($E8); EmitI32(SigInstallAddr - (CodeLen + 4))`. The slot IS
  rel32, so `PatchCodeRefSlot`'s `else` arm already handles it; **only the
  recording is missing.** Cheapest next target by a distance.
- **arm32** — `EmitI32($EB000000 or ...)`, single branch word. Patcher arm
  exists; needs recording.
- **aarch64** — `EmitI32($94000000 or ...)`, single branch word. Same.
- **xtensa** — `EmitXtensaCallToCode` / `EmitXtensaCall8ToCode`, plus the one
  thing riscv32 did not have: `XtEntryPcAnchor` is a code offset captured
  BEFORE the pass runs and DCE moves code, so the entry jump's long form is a
  delta from a stale anchor. Re-derive it through `DceNewOff` first. See the
  hazard block in `PatchCodeRefSlot`'s header — **and re-measure it rather than
  obeying it**; what retires it is an xtensa binary built with `--dce` that
  runs.
- **wasm32** — genuinely different, and the list above was right about this one:
  function indices, not displacements.

**Enumerate before you flip a gate.** Grep the target's backend for branches to
a `*Addr` global that do not go through a recording helper; on riscv32 that set
was exactly `EmitRiscv32CallToCode`'s ten call sites and nothing else, and
checking took one grep.

## What the riscv32 pass is worth, and what it is not

`test/test_dce_riscv32_stub_calls.pas`, `uses sysutils`, classes + virtual
dispatch + AnsiString concat + try/except + div0: **code 884588B -> 200556B**,
byte-identical output, exit 0. Signal DELIVERY re-checked separately because the
install path is what crashed: SIGTERM gives rc=143 gracefully on both legs.

**`code=` IS PAGE-QUANTISED and it cost me a wrong conclusion for an hour.**
Three unrelated programs (`hello`, `begin end.`, `Write('x')`) all reported
`code=36716B`, which I read as proof the program body was being dropped — the
body is rooted correctly and the liveness genuinely differed underneath (29 / 29
/ 31 bodies live, with different roots each time). Grade on the segment with
trailing zeros stripped until frankh-3f lands the instrument fix; do not diff
`code=` across programs and conclude anything.

This still removes **zero bytes of SRAM** — the note above stands unchanged.


## 2026-09-18 (frankB) — riscv32, i386 and xtensa all land; ALIGNMENT was the one nobody predicted

Three more targets, each verified by RUNNING the binary under qemu rather than
by linking it. What each actually needed, against what this ticket predicted:

| target | predicted | actually needed |
| --- | --- | --- |
| riscv32 | `jal`/`auipc+jalr` arm | CodeRef patched per-target (the arm existed); 10 stub calls recorded |
| i386 | not listed | **only** the recording — 11 hand-built sites that are byte-for-byte `IREmitCodeCall` |
| xtensa | `call0/callx0` + literal pool, "the awkward part" | form carried per slot; the backward long call recorded; **4-byte alignment** |
| arm32 | `bl` 24-bit | (unstarted) its `SigInstallAddr` branch recorded — the arm exists |
| aarch64 | `bl` 26-bit | (unstarted) same |
| wasm32 | function indices | genuinely different; the one row this ticket got right |

**i386 is the sharpest evidence that the prediction was about the wrong thing.**
It has NO encoding difference from x86-64 — its slot is the same rel32 — and it
still failed, in eleven sites that hand-rolled the four bytes `IREmitCodeCall`
already emits and lost the record doing it. A target with nothing
target-specific about its branches cannot be fixed by writing it a branch-patch
arm.

### The alignment invariant, which four targets could not have exposed

Everything after a hole slides down by exactly the hole's size. If that size is
not a multiple of 4, every later body changes alignment — and xtensa's
CALL0/CALL8 encode a WORD offset and require a 4-aligned TARGET.

Xtensa is the only ISA here with 2- and 3-byte instructions, so it is the only
one where a body's EXTENT is an arbitrary number: on riscv32, arm32 and aarch64
every instruction is 4 bytes, and on x86-64/i386 there is no constraint at all.
`DceRun` now rounds each removed span down to `DceCodeAlign`, leaving up to 3
dead bytes per dropped body.

**It cost an hour instead of a day because the encoder REFUSES rather than
truncating** — `call0 target 2462 is not 4-aligned; CALL0/CALL8 encode a WORD
offset and a stray byte is silently truncated away by the div below`. That
message is the whole diagnosis, written by whoever put the assert in front of
the `div`.

### And a parallel-array drop, found while mapping xtensa and fixed before it bit

`dce.inc`'s CallFix compaction remapped `CodePos` and `CallFixTarget` and
silently dropped **`CallFixAnchor`**, which is parallel to it BY INDEX — so every
site that moved would have worn the anchor of whoever previously sat at its new
index. Identical in shape to the GlobFix/GlobFixPCRel bug
`test_dce_threadsafe_heaplock.pas` exists for, in the table next door. Inert at
the time (xtensa was the only anchor user and was still refused), fixed anyway.

`CodeRefAnchor` is now a fourth column on the same table and carries the same
hazard; its declaration in `defs.inc` says so and names this.

### What the rows assert, and on which box

`test/test_dce_riscv32_stub_calls.pas` in **quick**, with legs for riscv32, i386
and xtensa (BOTH ABIs — the ABI decides the call form at a stub site, so one ABI
exercises one of the two arms). Each leg asserts the output AND that the image
shrank, because equal output is also what a pass that dropped nothing produces.
Each SKIPs, never passes, when its qemu is absent.

**`--xtensa-soft-mulhigh` is required for the xtensa legs and is not a
workaround**: qemu-xtensa's CPU model has no MULUH, so an integer `WriteLn` is an
illegal instruction with or without `--dce`. I chased that as a pre-existing
xtensa bug first — the PINNED compiler reproduced it identically, which is
exactly what a pre-existing bug looks like — and it was my own missing flag. No
bug filed, and the flag is explained in the recipe so the next reader does not
repeat it.
