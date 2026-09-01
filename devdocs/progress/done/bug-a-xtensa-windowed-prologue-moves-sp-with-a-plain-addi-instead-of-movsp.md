---
slug: bug-a-xtensa-windowed-prologue-moves-sp-with-a-plain-addi-instead-of-movsp
track: A+S
type: bug
prio: 45
status: done
found: 2026-08-30
found-by: frankS
summary: "FIXED (frankC, 2026-09-01): the windowed arm of EmitXtensaFrameReserve now emits `sub a8,a1,a8` + `movsp a1,a8`, the reference compiler's own dynamic-frame sequence; new xtensa_movsp encoder verified by qemu disassembly. Call0 keeps the plain sub. The ticket's addi/addmi citations were already stale — that path became a patched literal + sub, and the ABI violation survived the rewrite. Never caused a known fault, and still does not."
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

## ORACLE RUN 2026-08-30 (frankS) — `xtensa-esp-elf-gcc` does neither of the things we do

The "Bound" above noted the reference compiler was the obvious oracle and had not
been run. It has now. **`xtensa-esp32-elf-gcc` 15.2.0** (esp-15.2.0_20251204),
`-O2 -S`, default windowed ABI.

### Static frames: gcc puts the WHOLE frame in `entry`'s immediate

```c
int big(int n){ char buf[112];  sink(buf,n); return buf[0]+n; }
int huge(int n){ char buf[4000]; sink(buf,n); return buf[0]+n; }
```

```
entry	sp, 144
entry	sp, 4032
```

**No `addi` on `sp` anywhere, and no `movsp`.** The frame size goes in `entry`,
including at 4032 bytes — `entry`'s immediate reaches 32760, so an ordinary
function never needs to move `sp` at all.

### Dynamic frames: where `sp` genuinely must move, gcc uses `MOVSP`

```c
int dyn(int n){ char *p = __builtin_alloca(n); sink(p,n); return p[0]; }
```

```
entry	sp, 32
sub	a8, sp, a8
movsp	sp, a8
```

It computes the new `sp` into a scratch register and installs it with **`movsp`** —
never plain arithmetic on `sp`.

### What this settles, and what it still does not

The ticket left two readings open. **The second one is now dead:**

> ~~2. It is benign as emitted, because `entry a1, 32` plus a later `addi` happens
> to leave the area where the handler looks, and the ABI rule is stricter than
> this codegen needs.~~

The reference implementation treats the rule as binding in **both** situations —
it avoids the sp move entirely when it can, and uses `MOVSP` when it cannot. Our
`entry a1, 32` + `addi a1, a1, -112` matches neither arm. This is a real
divergence from the reference on its own hardware ABI, not an over-reading of the
spec by this ticket.

**It still does not demonstrate a fault**, and the falsified prediction above
stands unchanged: plain recursion 24 deep passes under both ABIs. So reading 1
(latent) is now the only one standing, and "latent" is still not "live".

The cheapest fix shape is also now visible and is the reference's own: **put the
frame in `entry`'s immediate** rather than emitting `entry` + `addi`. That is a
`symtab.inc` change in shared Track A ground and is not this lane's to make —
noted as a direction, not a proposal, since whoever takes it must check
`entry`'s 32760 ceiling and 8-byte granularity against `size + XtSpillMax`, and
decide what happens above it (gcc's answer there is `movsp`).

## FIXED 2026-09-01 (frankC) — `movsp`, and the ticket's own citations had gone stale first

### The citations were stale, and correcting them is half the value here

The ticket points at `compiler/symtab.inc:10779` / `:10784` emitting
`EncodeXtensaAddi` / `EncodeXtensaAddmi`. **At HEAD that path does not exist.**
It was replaced by `EmitXtensaFrameReserve` (`symtab.inc:11196`), which loads the
frame size from a patchable 32-bit literal — precisely because `addi`/`addmi`
cannot reach a 136448-byte frame. So a reader following the line numbers measures
a function that no longer emits what the ticket says it emits, and both numbers
still resolve to real lines that explain nothing.

The **ABI violation survived the rewrite unchanged**, which is why the ticket was
still right about the thing that matters: `sub a1, a1, a8` is a plain arithmetic
move of `a1` exactly as `addi a1, a1, -112` was.

### The fix

`EmitXtensaFrameReserve`'s windowed arm now computes the new `sp` into the
scratch and installs it with `MOVSP`, and Call0 keeps the plain `sub`:

```
l32r  a8, <literal>
sub   a8, a1, a8
movsp a1, a8
```

That is **the reference compiler's dynamic-frame sequence from the ORACLE RUN
section above, instruction for instruction** — arrived at before re-reading that
section, which is the corroboration this ticket asked for.

New encoder `xtensa_movsp` in `compiler/xtensaenc.inc` (RRR, op0/op1/op2 = 0,
r = 1). **Verified by disassembly, not derived:** `qemu-xtensa -d in_asm` on a
windowed build decodes the emitted bytes as `movsp a1, a8` at five sites. An
encoding argued from a manual and never decoded is the failure mode this file
has already had once.

### What was NOT done, deliberately

gcc's *other* arm — putting the frame in `entry`'s immediate when it fits — is
**not** adopted. `EmitXtensaFrameReserve`'s own header records the ADDMI chain
being reverted for exactly this reason: a second mechanism for a rule the
function already has, capped at an arbitrary bound (`entry` tops out at 32760,
and `DelphiRewriteGenericUses` needs 136448). One mechanism, no cap.

### The ALLOCA risk, and why it is not a new dependency

`MOVSP` raises an **ALLOCA exception** when the caller's `a0-a3` are already
spilled, so the handler can copy the 16 bytes to the new location. That needs a
vector bare metal does not have — but `compiler.pas:1783` **already refuses**
`--esp-profile=bare` with windowed, *"the windowed ABI needs window-overflow
exception handlers + vecbase that bare-metal does not install"*. Every profile
that can run windowed at all ships that vector set, and ALLOCA is one of it
(ESP-IDF's `_xt_alloca_exc`, beside `_WindowOverflow4/8/12`). So this adds no
dependency class that windowed did not already have.

**Honest limit:** I could not observe the ALLOCA path firing. `qemu-xtensa -d int`
logs nothing for window exceptions in linux-user, so "the deep-recursion program
passes" is evidence that windowed still works, and **not** evidence that ALLOCA
was exercised. Real IDF hardware remains unmeasured, as the Bound said.

### Measured

Compiler `3377a7541356`, `converged after 2 round(s)`. `gate.sh quick` GREEN with
the FPC seed canary **PASS, not SKIP** (gated before committing).

Windowed, against the x86-64 oracle — the five canary rows plus managed strings,
all `rc` and value: `test_cross_record`, `test_cross_dynarray`, `test_interfaces`,
`test_cross_sets`, `test_cross_variant`, `test_cross_managed_strings` — 6/6 OK.
Call0 unchanged arm re-checked including the two the scratch-register bug once
broke: `test_const_record_temp`, `test_cross_aggregate_return`, plus four — 6/6 OK.
Deep recursion at depth 40 with 800-byte frames: windowed and call0 both `979900`,
matching x86-64.

**Not claimed: that this fixes an observed fault.** The ticket's falsified
prediction stands — no windowed fault was ever attributed to this, and none was
found now. This closes as an ABI-conformance fix that brings us onto the
reference's own sequence.

## Log
- 2026-09-01 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
