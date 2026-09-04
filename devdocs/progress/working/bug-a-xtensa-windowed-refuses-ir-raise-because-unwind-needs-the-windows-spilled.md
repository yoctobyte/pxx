---
slug: bug-a-xtensa-windowed-refuses-ir-raise-because-unwind-needs-the-windows-spilled
title: "xtensa windowed refuses IR_RAISE because a longjmp-style unwind needs the register windows spilled first"
track: A+S
prio: 45
type: bug
status: working
created: 2026-08-30
found-by: frankS
summary: "Under the xtensa windowed ABI, IR_RAISE and try/except refuse (ir_codegen_xtensa.inc:4873/:4898). CAUSE CORRECTED 2026-09-01: the guard tests XtensaABI and nothing else, so it fires on --platform=posix too, where window handlers demonstrably DO exist (depth-40 windowed recursion runs correctly under qemu) — bare-metal's missing handler explains only half of it. The hosted half is blocked on one missing routine, a windowed setjmp/longjmp; newlib's protocol is disassembled in the ticket. MEASURED 2026-09-04 and it moves BOTH halves of the plan: wsr.windowstart AND rsr.windowbase both SIGILL under qemu-xtensa linux-user, so newlib's longjmp design cannot be ported to the hosted profile at all; the spill SYSCALL the plan called 'two instructions on hosted' is `Unknown syscall 0` under qemu, executing and returning without spilling, so a crash-only probe reports success; and the call-chain spill the plan filed as the bare-metal-only fallback DOES work under qemu, making it the one primitive available on every profile we can run. The hosted/bare split this ticket draws does not survive that. Harness, results and the two instrument failures that made the first three runs answer wrongly: devdocs/dev/xtensa-windowed-spill-probes.md."
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
