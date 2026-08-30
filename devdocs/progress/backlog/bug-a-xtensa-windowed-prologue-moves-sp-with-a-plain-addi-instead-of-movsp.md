---
slug: bug-a-xtensa-windowed-prologue-moves-sp-with-a-plain-addi-instead-of-movsp
track: A+S
type: bug
prio: 45
status: open
found: 2026-08-30
found-by: frankS
summary: "Every windowed xtensa prologue emits `entry a1, 32` then moves sp again with a plain addi/addmi. The windowed ABI requires MOVSP for that, because the caller's 16-byte register save area sits at [a1-16] and a plain add relocates sp while leaving the area behind. Ten executed entry sites, all immediate 32. NOT known to cause a fault -- the obvious mechanism was tested and falsified."
---

# The windowed xtensa prologue moves `sp` with a plain `addi`, where the ABI requires `MOVSP`

Found while chasing
[[bug-a-xtensa-windowed-abi-faults-on-frozen-strings-copy-and-dynarray-setlength]]
and **deliberately filed separately**: "violates the ABI" and "causes that fault"
are demonstrably different claims here, and only the first is supported. A finding
kept inside a ticket about a different symptom gets closed when that symptom is
fixed.

This is also **not a `Copy` bug**. It is in every windowed frame of every program,
and windowed is the **ESP-IDF ABI — the one real hardware uses**.

## What is emitted

Measured with `qemu-xtensa -d in_asm` on a hosted windowed binary
(`--platform=posix --xtensa-soft-mulhigh`), compiler sha256 `cf30672a934e`:

```
0x080576d8:  entry  a1, 32          <- establishes the window frame, allocates 32 bytes
0x080560e6:  addi   a1, a1, -112    <- then moves sp again, plain arithmetic
```

**Ten `entry` sites executed in one small program, every one with immediate 32**,
each followed by an `addi` or `addmi` of -96 or -112.

Source: `compiler/symtab.inc:10779` / `:10784` — the **windowed** arm of the
frame-size patch, which emits
`EncodeXtensaAddi` / `EncodeXtensaAddmi` on `reg_xtensa_sp` for
`size + XtSpillMax`.

## Why this is an ABI violation

Under the xtensa **windowed** ABI, `a1` may be moved only by

- `entry`'s own immediate, or
- the **`MOVSP`** instruction.

The caller's 16-byte register save area lives at `[a1-16]`. `MOVSP` exists
precisely so that relocating the stack pointer also carries that area with it; a
plain `addi` moves `sp` and **leaves the save area behind**. Window overflow and
underflow read it, and neither faults at the point of the mistake.

The invariant is documented **three times in `ir_codegen_xtensa.inc`** — in the
headers of `XtensaPushA2`, `XtensaSlotOff` and `XtensaDropSlots`:

> *Windowed keeps sp fixed — moving it desyncs the window spill area at `[sp-16]`.*

**Those three helpers honour it correctly.** The violation is in the **prologue**,
which is the one place nobody wrote the rule down.

## What is NOT claimed, and this is the important half

**It is not known to cause a fault.** The obvious mechanism was derived and
tested, and it failed:

> If the plain `sp` move desyncs the save area, and a deep enough call chain wraps
> the register file and reads it, then **any** sufficiently deep chain must fault.

Plain recursion 24 deep — no strings, no helpers, nothing from the `Copy` path —
**passes under both ABIs**:

```
depth-24  call0     rc=0  24
depth-24  windowed  rc=0  24
```

Twenty-four `call8` frames comfortably wrap an 8-window register file, so
overflows and underflows certainly occurred and were handled correctly. So the
violation is real and present in every frame, and is **not sufficient on its own**
to produce a fault.

Two readings remain open and this ticket does not choose between them:

1. It is latent — the save area is reconstructed correctly in practice on this
   qemu core, and the bug is waiting for a case that reads it after an sp change.
2. It is benign as emitted, because `entry a1, 32` plus a later `addi` happens to
   leave the area where the handler looks, and the ABI rule is stricter than this
   codegen needs.

**Deciding between them needs someone who knows the windowed spill machinery**, or
a test that forces an overflow/underflow pair to straddle an sp change. Until then
this is an ABI-conformance finding, not a live defect, and it should not be
described as the cause of anything.

## Why prio 45

Breadth argues up: every windowed frame, and windowed is the ABI that runs on the
S2/S3 hardware. Evidence argues down: no demonstrated failure, and the one
mechanism tested came back negative. 45 sits below the `Copy` fault it was found
next to (p50, a live SIGBUS) and above ordinary cleanup, which is where an
unproven finding of this breadth belongs.

Raise it immediately if anyone reproduces a windowed fault that this explains —
and note that [[bug-a-the-xtensa-windowed-abi-is-compiled-twice-and-executed-never]]
means there is no gated coverage that would have caught it either way.

## Bound

Hosted profile under `qemu-xtensa`, HEAD `f17cd5607`, compiler `cf30672a934e`.
Not checked on real IDF hardware, and not checked against a `MOVSP`-using
reference compiler (`xtensa-esp-elf-gcc` would be the oracle and was not run).
