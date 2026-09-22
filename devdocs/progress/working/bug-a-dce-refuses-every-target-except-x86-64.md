---
slug: bug-a-dce-refuses-every-target-except-x86-64
title: "`--dce` refuses every target except x86-64, so no cross target can strip anything"
track: A
prio: 70
type: bug
status: working
created: 2026-09-18
owner: frankb-8e
summary: "FIVE OF SIX TARGETS DONE, and arm32/aarch64 needed NO WORK -- the REMAINING list below was stale when it was written (re-measured 2026-09-19, frankS). x86-64, riscv32, i386 and xtensa (both ABIs) as before, plus **arm32 and aarch64**: dce.inc's refusal gate never mentioned either of them -- it refuses wasm32, --shared, -g, a non-wired frontend and an .asm entry override, and nothing else -- so `--dce` was already running on both. What the list asked for ("each needs only its hand-built `SigInstallAddr` branch recorded") had ALREADY LANDED as the 2026-09-18 linkReg work in PatchCodeRefSlot, whose own comment records the exact failure: arm32 `hello` installing SIGINT and then taking SIGSEGV at si_addr=NULL because B was patched where BL was meant. VERIFIED BY RUNNING, which is the standard this ticket sets for itself: five fixtures per target, stdout and exit code identical with and without the pass (arm32 246072->37176 on hello, -85%; aarch64 200968->69896, -65%), plus lib_signals_fpc -- which INSTALLS a handler, RAISES SIGUSR1/SIGUSR2 and dispatches through the trampoline, so the signal path the list named is the one actually exercised rather than merely linked. REMAINING: wasm32 alone (genuinely different -- function indices, not displacements). ALSO CORRECTED: dce.inc's own comment said \"Xtensa is the one still refused\" three lines above a refusal list that does not contain xtensa -- stale prose against correct code, fixed here. AND A SEPARATE DEFECT FELL OUT OF THE VERIFICATION, fixed and not merely filed: the xtensa signal stub never stored BSS_SIG_NUM (five backends did, xtensa did not), so __pxxSigNum answered 0, 0 failed the trampoline's bounds check, and every delivery was dropped SILENTLY -- see the logbook entry for 2026-09-19. Owner directive, 2026-09-17: \"strip code and associated data where possible.\" Measured wins: riscv32 880020B->198572B, i386 456290B->86626B, xtensa call0 694520B->161840B / windowed 613087B->140323B."
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

### RE-MEASURED 2026-09-19 (frankS) — arm32 AND aarch64 WERE NEVER REFUSED

Taken as a lead to check rather than as a conclusion, and two of the three
things it said turned out not to match the tree.

**The refusal gate does not mention arm32 or aarch64, and never did.**
`dce.inc` refuses `wasm32`, `--shared`, `-g`, a frontend that is not
Pascal/C/NilPy, and an `.asm` entry override. There is no architecture arm
below wasm32. Both targets ran the pass on first asking:

| target | bodies | live | dead | code |
| --- | --- | --- | --- | --- |
| arm32 | 174 | 27 (28544B) | 146 (209892B) | 239108B -> 29216B |
| aarch64 | 138 | 27 (26440B) | 110 (137244B) | 164308B -> 27064B |

**What the REMAINING list asked for had already landed.** It said each target
"needs only its hand-built `SigInstallAddr` branch recorded". That is the
2026-09-18 `linkReg` work in `PatchCodeRefSlot`, whose comment records the
failure it fixed in the same words this ticket uses — arm32 `hello` installed
SIGINT and then took SIGSEGV at `si_addr=NULL`, because B was being patched
where BL was meant, eleven basic blocks from the patch site.

**Verified by RUNNING, which is the standard this ticket sets for itself.**
Five fixtures per target, stdout and exit status compared with and without the
pass: `hello`, the packed-record fixture, the variant-record fixture, the
open-array leak fixture, and `lib_signals_fpc`. All SAME.

    h/arm32               SAME rc=0  246072 -> 37176
    h/aarch64             SAME rc=0  200968 -> 69896
    test_pkfld/arm32      SAME rc=0  255576 -> 75352
    test_pkfld/aarch64    SAME rc=0  202264 -> 71192

**`lib_signals_fpc` is in that list on purpose, and it is the row with teeth.**
Every other fixture runs to exit 0 without a signal ever being delivered, so a
mis-patched `SigInstallAddr` would not show: the binary installs a handler it
never uses. That fixture installs two handlers, sends itself SIGUSR1 and
SIGUSR2 through the PAL, and asserts per-signal dispatch through the
trampoline — so it takes the route the REMAINING list named, rather than merely
linking it. `--dce` and plain agree on i386, arm32, aarch64, riscv32 and
x86-64.

**Isolation was not the guard here — the ROUTE was.** The first pass of this
verification ran four fixtures per target, got SAME on all of them, and would
have closed arm32/aarch64 on evidence that could not have failed for the defect
the ticket names.

## REMAINING after this: wasm32 only.


## 2026-09-22 (frankb-8e) — wasm32: THE GATE'S STATED REASON IS TRUE AND IS NOT THE BLOCKER

Taken from frankh-c0, who holds the emitted-size/DCE group and is not working
this member. Measured before writing any compiler code, which is why this
section exists before a fix does.

**The refusal says `wasm32 references functions by INDEX, not by displacement`.
That is a true sentence about wasm and it is not what stops the pass.** The
index problem is *already solved*, by this backend's own design and for an
unrelated reason:

- `WasmIndexOfSlot` (`wasmenc.inc:441`) is **the single** slot->index
  conversion in the compiler. It has four call sites: the call patcher, the
  element segment, the export section and the asm-text writer. Nothing else
  turns a slot into an index.
- A call to a defined function is **never written at emission time**. It goes
  out as a fixed-width 5-byte LEB placeholder plus a relocation
  (`WasmCallRelPos`/`WasmCallRelSlot`), and `WasmPatchCalls` fills every one in
  once the index space closes. The header says why, and it is not DCE: an
  import is registered the first time a call to an external routine is lowered,
  so `WasmImpFuncCount` is not final while bodies are being emitted.
- `WasmCall` does not ACCEPT a function index, only a slot — *"the wrong form is
  not merely avoided here, it is unspellable."*

**So wasm32 already has, for free, the late-bound indirection that every ELF
target had to grow displacement-patching machinery to fake.** Renumbering is a
map lookup in one function. A reader who takes the refusal literally goes and
writes an index-patching pass that the backend makes unnecessary — the same
error this ticket already recorded once, when its own "What it costs" list sent
a reader to write five branch-patch arms that `ApplyCallFixups` already had.

### What ACTUALLY blocks it, measured

`ir_codegen_wasm32.inc:7743`, in the code, in its own words:

> *"Every routine is exported for now. A later phase narrows this to what the
> host profile actually needs; until then an exported function is how the test
> harness reaches a body at all."*

**Every defined function is exported, so every function is a root, so DCE would
drop nothing.** Counted on a Pascal hello world: **141 defined functions, 141 of
them exported** (142 export entries; one function is exported twice). The root
set is total. A DCE pass wired in today would run correctly, walk the whole
module, and report zero dead bodies — a green, honest, worthless result.

### The prize, measured from OUTSIDE the compiler

`wasmreach.py` (scratch, not committed yet) computes reachability from wabt's
own decoder rather than from pxx's tables, so it and any future in-compiler
pass would agree from two decoders instead of one. Roots are the REAL entry
points — the `_start` export plus every element-segment entry, which is every
address-taken function and therefore every `call_indirect` target — and
explicitly NOT the blanket per-routine export.

| program | defined | code section | LIVE | DEAD | dead share |
| --- | --- | --- | --- | --- | --- |
| `hello` (WriteLn only) | 141 | 68,540B | 33 | 108 | **82.6%** |
| classes + virtual + exceptions + IntToStr | 880 | 374,116B | 107 | 773 | **79.8%** |

The code section is ~90% of the module (68,547B of 75,996B on `hello`), so this
is roughly a **-75% module**, not a -75% of some minor part.

**CORROBORATION FROM A PIPELINE WITH NOTHING IN COMMON:** `--dce` on x86-64 for
the identical `hello` source reports `bodies 138  live 47  dead 90`, code
`67486B -> 18790B`. Two backends, two liveness implementations, two decoders:
34% live there against 23% live here. Not equal — the backends emit different
helper sets and the wasm root set is smaller — but the same order, which is
what makes the wasm number believable rather than merely large.

**WHAT WOULD RETIRE THESE ROWS, and it is not a re-run.** They are STATIC
estimates from wabt's disassembly. Neither has been validated by building a
DCE'd module and running it. A missing root category would show up as a smaller
live set here and a trap under `wasmtime` there, and this instrument cannot
tell those apart. The numbers are a claim about the GRAPH, not about a program
that works. Population: the two sources above at HEAD `319ccdade`, wabt
`wasm-objdump`, module built with `--target=wasm32` and no other flags.

### The design this points at, and why it needs no "later phase"

The export-narrowing the backend comment defers is **not a prerequisite**.
`--dce` is opt-in, and on wasm32 it is currently refused outright, so the
default path is untouched either way. The whole thing collapses to one rule:

> under `--dce`, the blanket per-routine export is **not a root**; roots are
> `_start`/`main`, the element segment, and the usual graph-level roots
> (`MethodFixups`, init/fini, `interrupt`, `EntryRootProc`). Exports for bodies
> that do not survive are dropped with them.

That keeps the harness's reach-by-export for every body that survives, and a
body that does not survive is one the program cannot reach anyway. **It also
means the deferred "later phase" is this work, arriving opt-in first.**

One consequence worth stating for whoever promotes `--dce` to `-O2`: on wasm32
the harness reaches bodies THROUGH exports, so a test that calls a routine by
export name and nothing else would lose it. That is correct `--dce` behaviour
and not a defect, but it is a reason wasm32 should not inherit a `-O2` default
on the same day it gains the pass.

### What the port needs, against dce.inc as it stands

The graph core is keyed on **proc indices** and is backend-neutral: `DceMark`,
the counting-sort edge build, the two-kind fixpoint, and roots for
`MethodFixups`, init/fini, `interrupt` and `EntryRootProc` all carry over
untouched. The single adapter is that `DceCallOwner[]`/`DceProcAddrOwner[]` are
derived on ELF targets by `DceOwnerOf(CodePos)`, a binary search over byte
ranges — and **wasm can supply the owner by construction**, because every call
site is inside a function. `WasmProcSlot[p]` already maps proc -> slot.

A note that cuts the right way: the pass's two documented approximation
channels both exist because a call site can fall OUTSIDE every body's byte
range (`DCE_WHY_FREECODE`, and the merged unowned-code node in the report). On
wasm there is no unowned code, so **the wasm graph is strictly more precise
than the native one**, and that machinery has nothing to do.

Everything from `dce.inc`'s removable-range loop to the end — hole removal,
`DceNewOff`, the eight compaction loops, `DceCodeAlign`, `ApplyCallFixups`,
`PatchCodeRefSlot` — is byte-layout work with **no wasm analogue at all**. It is
replaced by: mark dead slots, compact the slot numbering, and let
`WasmIndexOfSlot` and the section writers honour it.
