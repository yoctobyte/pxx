---
slug: bug-a-xtensa-windowed-refuses-ir-raise-because-unwind-needs-the-windows-spilled
title: "xtensa windowed refuses IR_RAISE because a longjmp-style unwind needs the register windows spilled first"
track: A+S
prio: 45
type: bug
status: done
created: 2026-08-30
found-by: frankS
summary: "FIXED 2026-09-04. `--xtensa-abi=windowed` compiles and RUNS try/except, try/finally, re-raise and a raise 40 frames deep, verified under qemu-xtensa against the x86-64 oracle and against the Call0 control; the pin refuses the same source. The unwind spills the register windows with a self-recursive call8 chain, rewrites the try frame's TWO save areas and forges an ordinary RETW -- newlib's wsr.windowstart design is unusable here (it SIGILLs in user mode) and the Linux spill syscall is Unknown syscall 0 under qemu. TargetHasProcCleanupFrame now includes windowed. NOT the signal runtime, which is Call0-only for an unrelated reason (the kernel enters the handler with the call4 convention) and still refuses."
owner: frankb-78
---

# The gap

Under `XTENSA_ABI_WINDOWED`, `IR_RAISE` and the unwind path refuse. Call0 is fine —
`af5d2b534` gave xtensa the proc exception cleanup frame, and at HEAD
`TargetHasProcCleanupFrame` (`ir_codegen.inc:11777`) carries
`(TargetArch = TARGET_XTENSA) and (XtensaABI = XTENSA_ABI_CALL0)`, with windowed
deliberately false.

**The cause is a runtime gap, not a codegen or prologue gap.** A longjmp-style unwind on
windowed xtensa must spill the register windows before it can transfer control, and
bare-metal has no handler to do that spill.

## Why this is filed rather than folded into the cdecl work

`bug-a-the-cdecl-soundness-reject-still-has-its-argument-shaped-door-on-four-targets` gives
i386/arm32/aarch64/riscv32 a real C-convention prologue arm. Xtensa is **explicitly out of
that ticket's scope**, and the reason is the trap rather than the tidiness (frankS):

> It would not fall out of frankA's change even if the arm were added — **it would just look
> like it had.**

That is the failure mode the whole day has been about: a change that appears to fix a target
it did not touch produces a green that means nothing. Adding xtensa as a fifth slice there
would have manufactured exactly that.

## Scope

Track S owns it, file-owned by A (`ir_codegen.inc` / `ir_codegen_xtensa.inc`) and B
(`lib/rtl/platform/esp/**`) depending on where the spill lands. **Not urgent** — Call0 is the
working configuration and windowed refusing is honest refusal, not silent wrong behaviour,
which is the deliberate ESP failure mode.

## Gate

Whatever lands must show the refusal is gone **by running a raise under windowed**, not by
observing that `TargetHasProcCleanupFrame` now returns true. And it must name the sha of the
binary the measurement came from.

## 2026-09-01 (frankC) — the reference protocol, disassembled; and the stated cause does not explain the hosted refusal

Picked up after
[[bug-a-xtensa-windowed-prologue-moves-sp-with-a-plain-addi-instead-of-movsp]]
in the same group. **Not implemented — banked.** The write-up below is the
deliverable: this ticket said deciding it "needs someone who knows the windowed
spill machinery", and the machinery is readable rather than arcane, so here it
is with the guesswork taken out.

### First, a correction to the diagnosis

> *"bare-metal has no handler to do that spill"*

True, and it does **not explain the refusal we actually have.** The guard at
`ir_codegen_xtensa.inc:4873` and `:4898` tests `XtensaABI` **and nothing else** —
it fires on `--platform=posix` exactly as on ESP. And the hosted profile
demonstrably *does* have window handlers: a depth-40 recursion with 800-byte
frames, built `--xtensa-abi=windowed --platform=posix`, runs to the right answer
under `qemu-xtensa`, and 40 nested frames cannot fit a 64-register file without
overflow and underflow both being taken and handled correctly.

So there are two situations behind one refusal, and only one of them has the
stated cause:

- **bare metal** — no handlers, and `compiler.pas:1783` already refuses windowed
  outright for `--esp-profile=bare`. This ticket's cause is right here, and here
  it is also *already enforced somewhere else*.
- **hosted (posix/qemu, the profile every xtensa test runs on)** — handlers
  exist. The refusal is not explained by the stated cause, and the real blocker
  is narrower: **we have no windowed `setjmp`/`longjmp`**, because ours saves and
  restores `a0`/`a1` and that is meaningless while a caller's registers are still
  live in the register file.

That distinction is the difference between "blocked on bare-metal runtime work"
(what the ticket says, and what would keep anyone off it) and "blocked on one
routine we can write and can execute today under qemu".

### The protocol, read out of newlib rather than derived

`xtensa-esp-elf` 15.2.0 is on this box. `libc_a-setjmp.o` disassembled with
`xtensa-esp-elf-objdump -d`. The windowed implementation is ~120 bytes and the
trick is worth stating plainly, because it is not the obvious design:

**`longjmp` does not jump.** It rebuilds the memory that the window *underflow*
handler reads, then executes an ordinary `retw` and lets the hardware restore the
target frame for it.

`setjmp`:
```
entry a1, 16
movi.n a2, 0 ; syscall          <- SPILL ALL WINDOWS (Linux/xtensa syscall 0)
addi a5, a1, -16                <- the caller's 16-byte save area
<copy [a5..a5+15] -> buf[0..15]>
extui a3, a0, 30, 2             <- a0's top 2 bits = the CALL SIZE of the return
blti a3, 2, .skip               <-   call4 -> nothing more to save
<copy the caller's EXTENDED save area (call8/call12: 16 or 32 more bytes),
 located at caller_sp - 16*callsize, -> buf[16..47]>
.skip:
<copy this frame's [a1..a1+15] -> buf[48..63]>
s32i a0, a2, 64                 <- the return address, call-size bits included
```

`longjmp`:
```
entry a1, 16
rsr.windowbase a5 ; movi.n a4,1 ; ssl a5 ; sll a4, a4
wsr.windowstart a4 ; rsync       <- declare EXACTLY ONE live window: ours.
                                    every other frame is now "already spilled",
                                    so nothing stale can be underflowed back
l32i a0, a2, 64                  <- restore the saved return address
<write buf[0..15] back to [a1-16], and the extended area back, and
 buf[48..63] to the target frame's own save area>
movi.n a2, 1 ; movnez a2, a3, a3 <- the return value
retw.n                           <- underflow reloads the target frame FROM the
                                    memory just written, and control lands in
                                    setjmp's caller
```

### What we would need that we do not have

Measured against this tree, not assumed:

1. **A spill primitive.** newlib-hosted uses `syscall` with `a2 = 0` — the
   Linux/xtensa `spill_registers` call, which fits our own map exactly (nr -> a2,
   `ir_codegen_xtensa.inc:1491`). `xtensa_syscall` already exists in
   `xtensaenc.inc:154`, so on the hosted profile this costs **two instructions**.
   Bare metal would need `xthal_window_spill`'s call-chain trick instead — a
   nest of `call12`s that walks the window base around the register file. That
   is the part that is genuinely bare-metal-only, and it is why the split above
   matters: the hosted half does not wait on it.
2. **`rsr.windowbase` / `wsr.windowstart`.** No encoders (`grep -i "rsr\|wsr"
   compiler/xtensaenc.inc` -> nothing), and these are **privileged** special
   registers. On ESP everything runs ring 0 so newlib may use them freely; under
   `qemu-xtensa` linux-user on a ringed core they would trap. **UNMEASURED, and
   it is the one fact that decides whether the hosted half is a short job or a
   different design** — whoever takes this should measure it first, before
   writing anything.
3. Encoders for `extui`, `slli`, `ssl`, `sll`, `movnez`, and the `l32i.n`/`s32i.n`
   narrow forms (the wide forms would do).

### Why it stopped here

"Can I fix AND verify this right now" comes back no: item 2 is unmeasured and
there is no Pascal-level route to a raw syscall to measure it with (`asmtext_xtensa.inc`
accepts 30 mnemonics and `syscall` is not among them), so the first step is
itself a compiler change. Banked rather than started, and deliberately not
traded for a microfix elsewhere.

### Gate, restated more cheaply than the ticket has it

The ticket asks for a raise that runs under windowed. Note that this is now
**reachable on the hosted profile under `qemu-xtensa`** — `test_cross_exception`
builds Call0 today and refuses windowed with the error above, so it is already
the ready-made row. It does not need hardware.

### Bound

HEAD `4cac68da5`, compiler `3377a7541356` (`converged after 2 round(s)`).
Newlib disassembly is `xtensa-esp-elf` esp-15.2.0_20251204, big-endian object;
our targets are little-endian, which changes nothing about the instruction
sequence but means the bytes are not copyable.


# 2026-09-04 (frankB, Track A) — the unmeasured fact is measured, and it moves the plan both ways

Full write-up, harness and reproduction:
**`devdocs/dev/xtensa-windowed-spill-probes.md`**. Bound: origin/master
`4b264f3d2`; no compiler change was needed and none was made, so no pxx binary
identity applies — the probes are hand-assembled with `llvm-mc-21` (LLVM 21 has
an Xtensa assembler) inside a hand-written ELF32-LE header, run under
`qemu-xtensa`. Three results:

1. **`rsr a5, windowbase` SIGILLs in user mode**, and so does `wsr.windowstart`.
   That is the fact the previous section named as deciding "whether the hosted
   half is a short job or a different design". **It is a different design** —
   newlib's `longjmp`, which turns on declaring one live window through
   `wsr.windowstart`, cannot be ported here.
2. **The spill syscall is not implemented by qemu.** `qemu-xtensa -strace` prints
   `Unknown syscall 0`. The instructions execute and return, so the "costs two
   instructions on the hosted profile" reading is not wrong about Linux — it is
   wrong about the only hosted runtime we can execute, and a probe that checks
   only for a crash reports it as working.
3. **The call-chain spill works.** 24 nested `call4` frames put an outer frame's
   `a2` into memory under qemu, using nothing but ordinary calls. This section
   had it as the bare-metal-only alternative with the hosted half not waiting on
   it; it is the reverse — it is the ONE primitive available on every profile,
   and it needs no new encoders, no privileged access and no syscall.

## What that leaves, and it is smaller than the plan assumed

No `rsr`/`wsr` encoders are needed at all — items 2 and 3 of the previous
section's list are moot for a call-chain design. What is needed is a Pascal- or
IR-level spill routine (a self-recursive windowed call chain, depth chosen from
the register-file size) and then the save-area rewrite plus `retw` that
`longjmp` already needs. Both halves are ordinary code.

**Not started, and deliberately not traded for a microfix.** This is the
measurement the ticket asked for first, and it is banked rather than acted on
because the design it implies is a different one from the disassembled reference,
and choosing it is not a thing to do at the end of a session.

## A note on how nearly this went the other way

The first three runs of the spill probe reported "not found" and would have been
banked as *the call-chain spill does not work* — the exact opposite of result 3.
Two independent instrument failures, neither of which errored: an out-of-range
`movi` that `llvm-mc` silently turned into an `l32r` reading a literal pool the
probe's own `--only-section=.text` had dropped, and a scan that went upward when
the Xtensa ABI puts a spilled CALLER's registers BELOW the callee's stack
pointer. What caught both was carrying a positive control (store the needle, must
find it) beside the negative one (no spill, must not find it). With only the
negative control the probe was confidently wrong twice.


# 2026-09-04 (frankB, Track A) — FIXED, and the mechanism is the one the measurement implied

`--xtensa-abi=windowed --platform=posix --xtensa-soft-mulhigh` now compiles and
runs `test_cross_exception` (try/except, try/finally, nested, re-raise) and a new
deep-raise row, matching the x86-64 oracle exactly and matching the Call0
control. **Positive control across the whole population: the same two sources on
pin v403 (`c31d03b202da`) give `error: target xtensa: try/except requires the
Call0 ABI`.**

## What landed

- `compiler/exception_emit.inc` — a windowed arm with four stubs: the spill
  chain, `ExcSetJmp`, `ExcLongJmp`, `ExcRaise`. All four are windowed functions
  (`entry` / `retw`) entered by `CALL8`.
- `compiler/symtab.inc` — `EmitXtensaCall8ToCode`. **Deliberately not a windowed
  arm inside `EmitXtensaCallToCode`**, which was the smaller diff and was wrong:
  the signal stubs go through that helper and end in `RET`, so calling them with
  `CALL8` would rotate a window nothing rotates back. The two helpers are named
  for the STUB'S OWN return instruction, which the call site cannot see.
- `compiler/ir_codegen_xtensa.inc` — the two `Error` calls are gone;
  `EmitXtensaExcFramePushW` moves sp with **MOVSP** under windowed, and the pop
  does too. A plain `ADDI` would have left the caller's `a0-a3` save area behind
  at the old `[sp-16]`, which is a wrong value on the next underflow rather than
  a fault.
- `compiler/ir_codegen.inc` — `TargetHasProcCleanupFrame` includes xtensa
  unconditionally; the proc-cleanup frame grew a windowed arm.
- `compiler/defs.inc` — `EXC_FRAME_SIZE_XTW = 64`, an 11-word jmpbuf.

## The mechanism, in one paragraph

`RETW` takes its window increment from the top two bits of `a0` and reloads the
target frame through the window UNDERFLOW handler — but only for a window whose
`windowstart` bit is clear. So: spill everything (which clears those bits and
writes every frame to memory), write the try frame's two save areas back the way
they were when `setjmp` ran, forge `a0` and `a1`, and `RETW`. The hardware does
the transfer. Full protocol and the probe that established it before any
compiler code was written:
`devdocs/dev/xtensa-windowed-spill-probes.md`, section "A windowed longjmp that
uses no privileged instruction", builder
`devdocs/dev/xtensa-windowed-longjmp-probe.py`.

## `test_cross_exception` CANNOT guard half of this, and that is measured

The two save areas are in different places — `a0-a3` at the callee's `[sp-16]`,
`a4-a7` at the frame's own `[caller_sp - 32]` — and this backend keeps the
windowed frame pointer in `a7`. With the SECOND restore deliberately pointed 16
bytes wrong and the compiler rebuilt:

| row | broken compiler |
| --- | --- |
| `test_cross_exception` windowed | **prints 1..9 and PASSES** |
| `test_xtensa_windowed_deep_raise` | `caught`, then `545258032 0 0 0` for `11 22 33 44` |

Half a restore lands, prints the right first line, and is wrong. That is why the
new test exists and why it prints the four locals individually rather than their
sum: a compensating pair cannot hide. It also raises 40 frames down, because
`test_cross_exception` raises ONE frame below its try — shallow enough that it
passes whether or not the unwind spills at all.

## Also removed: a dead riscv32 arm

The park-and-exit stub this replaced was `(TARGET_XTENSA) or (TARGET_RISCV32)`,
and the riscv32 half was already unreachable — the real riscv32 arm above it is
unconditional and takes every riscv32 build, hosted and bare, since
feature-esp-bare-exceptions gave it a runtime. Verified before deleting (no inner
guard, no early Exit), and `test_cross_exception` on riscv32 re-run after.

## What this does NOT change

**The signal runtime is still Call0-only** and its comment used to cite
`TargetHasProcCleanupFrame` as the same fact. It is not: the signal stub is
windowed because the KERNEL enters a handler with the call4 convention, which is
unrelated to the unwind. The stale cross-reference is corrected in place rather
than left to be cited next.

## Gate

`make compiler/pascal26` converged (`62e1b024fa19`); `tools/gate.sh quick` GREEN
with the FPC seed canary RUN (gated before the commit, on a dirty
`compiler/**`); `PXX_ALLOW_FULL_SUITE=1 make test-xtensa` green end to end on
that exact binary — the quick tier does not run `test-xtensa` and every row added
here lives in it.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 2ec3e61c5.


## 2026-09-04, same session — I SHIPPED A CRASH AND THIS IS THE FOLLOW-UP

`2ec3e61c5` was green on every row it wired and **wrong about a shape none of
them had**: a `try` in the MAIN PROGRAM BODY SIGSEGV'd under windowed, where
before the change it had refused to compile. Found within the hour by taking the
next ticket in the same group and running the two managed-unwind programs
(`test_managed_exception_cleanup`, `test_interface_arc_exc`) that the Call0 half
had been proved with — both crashed, and so did a four-line reduction.

**A refusal is a worse product than a working feature and a BETTER one than a
crash**, so the first action was to close `TargetHasProcCleanupFrame` again. That
changed nothing, which is how the first hypothesis died: the proc cleanup frame
had just been enabled in the same commit and was the obvious suspect, and it was
not the cause.

### The cause

Every frame's 16-byte block at `[sp-16]` is written **by its caller** — window
overflow puts the caller's `a0-a3` there. Every frame gets one for free except
one: **the process entry reaches its frame through a bare `entry` from the ROOT
window and was never `CALL8`'d**, so nothing ever fills the block below it. The
word at `[sp-12]` is whatever the kernel left on the stack, and `ExcSetJmp`
reads it to find the frame's caller.

Harmless for as long as nothing walked that chain, which is why it surfaced the
moment the unwind landed and not before.

Fixed in the windowed startup with four stores right after the outermost
`entry`: `a0`, the **pre-`entry` sp**, `a2`, `a3`. The pre-`entry` sp is the
honest value for `[sp-12]` — it is where this frame's caller's stack pointer
would be if it had one, and it makes `[that - 32]` land inside this frame.

### Reproduced outside the compiler first, and that is what named it

`lj8root_yes` (rc 139) and `lj8seed_yes` (rc 50) in
`devdocs/dev/xtensa-windowed-longjmp-probe.py`: 30 instructions, one run, the
right frame. Guessing had already cost one wrong hypothesis and a rebuild.

### What the rows now cover

`test_xtensa_windowed_deep_raise` grew a main-body `try` (the crashing shape),
and `test_managed_exception_cleanup` and `test_interface_arc_exc` — which ran
Call0-only, correctly, because windowed could not compile a raise — are now
windowed rows too. All match the x86-64 oracle on both ABIs.

### The reusable part

**The rows I wired were all about the mechanism I had just built, and the shape
that broke was one the mechanism had never been asked about.** `test_cross_exception`
and the deep-raise test both put their `try` inside a procedure, because that is
what a test that is *about* exceptions looks like. Nothing in either was wrong.
The gap was that "which FRAME is the try in" was not a dimension either of them
varied, and the outermost frame is the one that is different on this ABI.
