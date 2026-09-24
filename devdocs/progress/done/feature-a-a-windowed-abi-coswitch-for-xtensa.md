---
slug: feature-a-a-windowed-abi-coswitch-for-xtensa
track: A
tags: [S]
type: feature
prio: 25
status: done
owner: ""
created: 2026-09-24
found-by: frank (the Call0 half landed; this is the sequenced remainder)
blocked-by: []
summary: "DONE 2026-09-24. xtensa coroutines work on the WINDOWED ABI as well as Call0. The stub (coroutine_emit.inc) spills every caller window with a CALL8 chain, saves exc_top and a0 in a 48-byte frame, swaps a1 and RETWs, and the window underflow handler reloads the other context from its own stack; a fresh context (saved a0 = 0) is CALLX8'd into its entry on the new stack. scheduler.pas primes ONE layout for both ABIs. Retire condition met: the six test-xtensa coroutine rows pass under --xtensa-abi=windowed, the negative control was REPLACED by ABI relation rows, and a raise inside a coroutine reaches its handler (scheduler_exc, plus the new deep-call-chain row)."
---

# A windowed-ABI CoSwitch for xtensa

The sequenced remainder of
[[feature-a-coswitch-for-xtensa-and-riscv32-the-scheduler-has-no-context-switch-there]],
whose body asked for exactly this split: *"a windowed `CoSwitch` is a materially
harder problem than a Call0 one, and the two should be sequenced, not bundled."*
Call0 landed 2026-09-24 with all three of that ticket's parts.

## Why it is harder, stated as the thing that breaks

The switch that works on every other target is: push the callee-saved set plus
`BSS_EXC_TOP` onto the current stack, store `sp` into `[pfrom]`, load `sp` from
`[pto]`, restore, return. It assumes **callee-saved state is on the stack being
swapped.**

Under the windowed ABI it is not. `call8` rotates the register file, so a
routine's callee-saved values live in **physical registers belonging to a window
the callee cannot see**, and they reach memory only when the window is spilled.
Two consequences, and the second is the awkward one:

1. The window must be spilled before another context can own the stack, or the
   values are still in the register file when the other context starts using it.
2. The windowed spill area is at **`[sp-16]`**, so a switch that moves `sp`
   invalidates the region it would have to spill into. `ir_codegen_xtensa.inc`
   already records this in a different context — its note that windowed keeps
   `sp` CONSTANT because moving it desyncs the window spill area.

So this is not "write the Call0 arm with different register numbers".

## What the Call0 work leaves in place for whoever takes this

- **The stub site**: `compiler/coroutine_emit.inc`, whose xtensa arm is gated on
  `XtensaABI = XTENSA_ABI_CALL0` with a windowed arm immediately after it that
  refuses **by name**.
- **The lowering**: `ir_codegen_xtensa.inc`'s `IR_COSWITCH` needs **no ABI
  guard** and deliberately has none — it is reachable only when a stub was
  emitted, because `EmitCoroutineRuntime` errors on every xtensa configuration it
  does not implement. **If you add a windowed stub, that property still holds;
  if you add a windowed stub with a different frame, the RTL priming must move in
  the same commit.**
- **The priming**: `lib/rtl/scheduler.pas`'s xtensa arm writes a 16-byte frame
  (exc_top, a15, a0, pad). A windowed switch will almost certainly want a
  different one, which means an ABI-conditional priming block — and the RTL
  cannot see `--xtensa-abi`, so **how the RTL learns which ABI it is being
  compiled for is a real sub-problem and should be answered before any codegen.**
  That is the first thing to look at, not the window spill.
- **The authority on the callee-saved set**: `compiler/exception_emit.inc`. Its
  Call0 jmpbuf saves `(a15, sp, a0)`; its windowed arm is separate. Whatever the
  windowed jmpbuf saves is what a windowed CoSwitch should save, for the same
  reason the Call0 pair agree — a switch that preserves more than the exception
  runtime does is claiming a guarantee nothing else makes.

## The negative control that exists today, and what to do with it

`test-xtensa` carries:

```
! ./pascal26 --target=xtensa --platform=posix --xtensa-abi=windowed --emit-obj \
      test/lib_asyncnet6.pas ... >...out 2>&1
grep -q "xtensa WINDOWED ABI" ...out
```

**Replace it, do not delete it.** It is what stops the refusal quietly becoming
a fall-through, and a fall-through here calls `CoSwitchAddr = 0` — offset 0 of
`.text`, the program entry, from inside user code, which hangs or re-enters
rather than diagnosing. When windowed works, this row should become the six
coroutine rows run a second time under `--xtensa-abi=windowed`.

(Note for whoever edits it: the redirect is `>` and not `2>` because **pascal26
writes diagnostics to stdout**. The `2>/dev/null` spelling on neighbouring
refusal rows works only because those rows assert a nonzero exit and never read
the text.)

## Positive control for whoever fixes this

Three rows, because "it switched" and "it switched correctly" and "exceptions
still work" are different claims:

1. **The six coroutine rows under `--xtensa-abi=windowed`**, asserted against the
   **x86-64 build of the same source** as the Call0 rows are — so no per-target
   constant is baked in and neither ABI can encode its own wrong answer.
2. **A perturbation control.** The Call0 arm was validated by moving `@CoStart`
   one slot in the RTL priming and confirming `test_scheduler` and
   `test_asyncecho` **segfault**. Do the same for whatever frame windowed uses:
   if a one-slot error still passes, the rows are not exercising the switch.
3. **`test_scheduler_exc`**, which is the row that matters most here.
   `BSS_EXC_TOP` travels with the stack so each coroutine owns its exception
   chain, and the window spill interacts with that — a windowed switch that gets
   registers right and the chain wrong passes rows 1 and 2.

## Why the priority is 25 and not higher

Call0 is the default on every xtensa target including `esp32s3`, so coroutines
and async work there today and nothing is blocked. This is reachable only by an
explicit flag, it refuses loudly when reached, and the refusal is guarded. Rank
it up if a real ESP-IDF build wants async — the NilPy xtensa rows show that
`--xtensa-abi=windowed --platform=esp` is a combination this tree already
builds, so that is not hypothetical, just not currently asked for.

# Umbrella

[[meta-a-pxx-produces-linkable-code]]


## Resolution (2026-09-24, frankH)

**Mechanism.** This is the windowed longjmp's trick (exception_emit.inc, the
part measured under QEMU), aimed at a different frame. The switch needs no
jmpbuf-style copy of the [sp-16] save area, because a SUSPENDED context's
stack is not written by anyone while it is parked.

**The one number that is easy to get wrong: `entry a1, 48`, not 32.**
- With 32 bytes, the ABI claims every byte of the frame: [sp+0,+16) is this
  window's own a4-a7 save area, and [sp+16,+32) is the caller's caller's base
  save area.
- The three slots therefore live in the 16 bytes that 48 adds: exc_top at
  sp+0, a0 at sp+4, fresh-entry at sp+8.

**A fresh context is CALLED, not returned into,** because CoStart begins with
ENTRY. The stub:
1. moves its own window onto the new stack at P-32;
2. records P at [a1-12], so a later overflow of that window writes its a4-a7
   into [P-32,P-16) and nowhere else;
3. CALLX8s the entry.

**The priming layout is shared with Call0.** It is [0] exc_top = 0,
[4] = 0 (Call0 reads it as a15; windowed reads it as "never ran"), and
[8] = @CoStart.

**Verified:**
- **Rows vs the x86-64 oracle, windowed:** scheduler, scheduler_exc, channel,
  timer, reactor and asyncecho, plus the new
  test_scheduler_yields_deep_in_a_call_chain on both ABIs. That test yields
  with 20 frames live, far more than the 64-register file holds.
- **httpdemo:** examples/net/httpdemo runs on xtensa under both ABIs.
- **Positive control:** writing 0 to the CoStart slot makes test_scheduler
  SEGFAULT on both ABIs, so the rows do reach the stub.
- **The board:** the deep test passed on an ESP32-S3.
- **gate.sh quick:** GREEN.

**Found beside it, not fixed:**
- On ESP-IDF, the scheduler's default 192 KB coroutine stack (CO_STK) does
  not fit three times in the S3's internal RAM. Unmodified test_scheduler
  aborts with "pxx: out of memory"; SpawnSized works.
- That is a sizing default for the ESP profile, not an ABI defect, and it is
  filed as its own ticket.

## Log
- 2026-09-24 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
