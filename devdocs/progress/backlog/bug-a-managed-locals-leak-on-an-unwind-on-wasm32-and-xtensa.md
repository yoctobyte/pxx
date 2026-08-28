---
track: A
prio: 25
type: bug
blocked-by: []
summary: "A proc's managed locals (AnsiString, interfaces, dynamic arrays) are released by a proc CLEANUP FRAME that five targets have and two do not. wasm32 and xtensa both fall outside TargetHasProcCleanupFrame, so an exception unwinding THROUGH a frame leaks everything that frame owned. Silent by construction: an unwind leak prints nothing."
---

# Managed locals leak on an unwind on wasm32 and xtensa

Filed 2026-08-28 by the wasm lane while landing Phase 7 (exceptions), as a
**known limitation disclosed rather than discovered**. Nothing here is a
regression: wasm32 is arriving at the same position xtensa has held
deliberately, and this ticket exists so that position is a record instead of a
sentence in someone's message.

## What the mechanism is

`ir_codegen.inc` gives every proc that owns managed locals a **cleanup frame**:
the same exception frame a `try` block uses, with the proc's own release
sequence as its landing pad. An exception unwinding through the proc lands
there, releases the managed locals, and re-raises outward. The gate is one
predicate:

```pascal
function TargetHasProcCleanupFrame: Boolean;
begin
  Result := (TargetArch = TARGET_X86_64) or (TargetArch = TARGET_I386) or
            (TargetArch = TARGET_ARM32) or (TargetArch = TARGET_AARCH64) or
            (TargetArch = TARGET_RISCV32);
end;
```

Five targets in, two out. xtensa is out because its exception runtime exists
only under the Call0 ABI and its managed-local arm handles `AnsiString` alone —
that is ESP-campaign work and is stated in the comment above the function.
wasm32 is out because it was never added.

## What it costs

An exception that unwinds THROUGH a frame — not one caught inside it — leaks
every managed local that frame owned: `AnsiString` handles, interface
references, dynamic arrays. The refcount is never dropped, so the block is
never freed.

**The failure mode is the reason this is worth a ticket rather than a comment:
an unwind leak prints nothing.** No wrong value, no crash, no diagnostic. It
is invisible to the native-vs-wasm differential the lane gates on, because both
sides produce identical OUTPUT; only the heap differs. A program has to run the
unwinding path many times before the leak is even measurable.

## Why it is prio 25 and not higher

It needs an exception to unwind through a frame that owns a managed local.
Every `try` that CATCHES is unaffected — the handler runs in the frame that
still owns its locals, and normal scope exit releases them. So the reachable
surface today is: a raise crossing a frame boundary, in a program that also
holds managed values across that frame. Real, but not on the path of any
current milestone.

It is also NOT on the critical path for the wasm exception lowering: the
lowering is correct without it, and adding the cleanup frame later changes no
IR and no shared rule — it is one arm in `TargetHasProcCleanupFrame` plus a
target implementation of enter/leave.

## The fix, for whoever takes it

Two targets, one mechanism. For **wasm32** the cleanup frame is the same
handler frame the lowering already builds for `try`: three words in the shadow
frame (`prev`, `pad`, owning `$fp`), pushed in the prologue with the release
sequence as the pad, popped in the epilogue. The pieces exist —
`ir_codegen_wasm32.inc`'s `IR_EXC_ENTER` / `IR_EXC_LEAVE` emitters are the same
code — so this is wiring, not new machinery, exactly as the comment above
`TargetHasProcCleanupFrame` says ("a `try` frame and a proc cleanup frame are
the same frame with different landing pads").

For **xtensa** it stays ESP-campaign work and is tracked with that campaign;
do not treat the two halves as one job just because they share this ticket.

## Do not "fix" this by widening the predicate

Adding `TARGET_WASM32` to `TargetHasProcCleanupFrame` without implementing
`EmitProcCleanupFrameEnterForTarget` / `...LeaveForTarget` for it reaches the
`else Error('compiler error: no proc exception cleanup frame for this target')`
arm and breaks every wasm build that owns a managed local. The predicate is the
last line of the change, not the first.
