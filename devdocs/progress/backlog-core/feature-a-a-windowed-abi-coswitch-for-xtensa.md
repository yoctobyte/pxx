---
slug: feature-a-a-windowed-abi-coswitch-for-xtensa
track: A
tags: [S]
type: feature
prio: 25
status: open
owner: ""
created: 2026-09-24
found-by: frank (the Call0 half landed; this is the sequenced remainder)
blocked-by: []
summary: "MECHANISM: a stackful context switch assumes callee-saved state lives ON the stack it is swapping, and the xtensa WINDOWED ABI does not put it there -- `call8` rotates the register file and the window's spill area sits at [sp-16], so handing a stack to another context requires spilling the window FIRST and a switch that moves sp invalidates the area it would spill into. That is why it was sequenced away from Call0 rather than bundled with it. NOT A GAP ANYONE HITS BY DEFAULT: XtensaABI defaults to CALL0 and only an explicit --xtensa-abi=windowed moves it (measured -- a flagless xtensa build is byte-identical to --xtensa-abi=call0 and differs from windowed), so every xtensa and esp32s3 build gets working coroutines today. It is reachable, though: the NilPy xtensa rows in test-xtensa build with `--xtensa-abi=windowed --platform=esp`, so an ESP-IDF-shaped build that also wanted async would meet the refusal. IT REFUSES BY NAME, NOT SILENTLY -- coroutine_emit.inc names the ABI, says Call0 is supported and is the default, and a negative-control row in test-xtensa greps for that wording, so the refusal cannot rot into a fall-through. THE CONDITION THAT RETIRES IT: the six test-xtensa coroutine rows pass under --xtensa-abi=windowed as well as Call0, with the negative control replaced rather than deleted, and a raise inside a coroutine still reaching the handler around its driver (the exception chain travels with the stack, so the window spill and BSS_EXC_TOP interact)."
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
