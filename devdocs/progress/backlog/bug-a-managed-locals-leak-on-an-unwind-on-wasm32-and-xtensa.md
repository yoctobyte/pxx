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

## Update 2026-08-30 (frankS): ONE OF XTENSA'S TWO BLOCKERS IS GONE

This ticket, and the comment above `TargetHasProcCleanupFrame` that it quotes,
both give two reasons for xtensa's exclusion:

> *xtensa is out because its exception runtime exists only under the Call0 ABI
> **and its managed-local arm handles `AnsiString` alone***

**The second half is no longer true.** `e1d7977a2` took that arm from one
managed kind to six and `3a1c1dc73` added the seventh, so
`EmitManagedLocalCleanupForTarget`'s xtensa block now releases all 7 — COM
interface, static array of managed, scalar `AnsiString`, `Variant`, promo-int,
record-with-managed-fields, and local dynamic array. Verified at HEAD, and both
downstream divergences that work was filed against (`test_managed_local_release_reuse`,
`test_interface_arc`) now MATCH the x86-64 oracle.

So the release SEQUENCE a cleanup frame would need as its landing pad already
exists on xtensa and is complete. What remains is only the first reason: the
exception runtime is Call0-only (`IR_EXC_ENTER` and `IR_RAISE` both `Error` out
under `--xtensa-abi=windowed`). That makes the remaining xtensa work narrower
than this ticket describes — **wire the existing enter/leave under Call0 and
keep the predicate false for windowed**, rather than "ESP-campaign work" of
unstated size.

Not re-priced here; p25's argument (it needs a raise crossing a frame that owns
a managed local) is unaffected by which blocker remains.

### A source comment now states something false

`ir_codegen.inc`, immediately above `TargetHasProcCleanupFrame`, still asserts
*"its managed-local arm handles AnsiString alone"*. That line should go when
someone next holds the file. **Not fixed here:** the Track S grant covering this
area is scoped to the `TargetArch = TARGET_XTENSA` block inside
`EmitManagedLocalCleanupForTarget` and nothing else in `ir_codegen.inc`, and
this comment sits outside it. A one-line comment fix is exactly the size of
edit a grant boundary looks silly around, which is the point of having one.

## Update 2026-08-30 (frankS): THE XTENSA HALF IS DONE. wasm32 remains.

Landed under the narrowed analysis in the update above: `TargetHasProcCleanupFrame`
now answers true for xtensa **under Call0 only**, and the six emitters
(`Enter` / `Leave` / `PatchLanding` / `Skip` / `PatchSkip` / `ReRaise`) have
xtensa arms transcribed from that backend's own `IR_EXC_ENTER` / `IR_EXC_LEAVE`.
Under windowed the predicate stays false and a proc still leaks on an unwind —
`IR_EXC_ENTER` and `IR_RAISE` refuse there outright, so there is nothing to hang
a frame on. The stale comment clause is deleted.

**Keeping the two halves separate, as this ticket instructed.** wasm32 is
untouched and the ticket stays open for it; nothing here changes what that half
needs.

### This ticket's central claim needs one correction

> *"The failure mode is the reason this is worth a ticket rather than a comment:
> an unwind leak prints nothing."*

True of a leak and **false of this corpus**, which already held the proof:

| test | x86-64 | xtensa before |
| --- | --- | --- |
| `test_managed_exception_cleanup` | `1` | **SEGFAULT** |
| `test_interface_arc_exc` | `unwind freed=3` | `unwind freed=2` |

The first raises 9000 times through a frame holding a 64 KiB string and a
dynamic array — roughly 590 MB never released, which is not a quiet refcount but
a crash. The second prints the missing release **as a number**. Both now MATCH.

So the defect was observable all along; what was missing was anything that
looked. **Neither test is in the 129-source cross differential** — that corpus
has no exception-unwind coverage at all, which is why every sweep run against
xtensa this month was green on a target that released nothing on an unwind. Both
are now rows in `test-xtensa` (101 → 103 programs).

That is the reusable part: p25's "not on the path of any current milestone" was
argued from reachability, and reachability was right — but the two programs that
DO reach it were already written, already passing on five backends, and simply
not wired to this target.

### Measured

At the SAME HEAD with and without the change, which is the only baseline worth
quoting in a repo where every lane pushes to master:

- call0 **104 MATCH**, lost=0 gained=0 · windowed **94 MATCH**, lost=0 gained=0
- x86-64 emitted output byte-identical, 6/6
- `gate.sh quick` GREEN, self-host fixedpoint converged

Both sweeps had moved substantially against my *earlier* baselines (call0
103→104, windowed 53→94) and none of that is this change — rebuilding the same
HEAD without the diff reproduces both numbers exactly.
