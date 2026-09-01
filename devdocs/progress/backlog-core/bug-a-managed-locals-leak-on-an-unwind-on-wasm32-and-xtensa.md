---
track: A
prio: 25
type: bug
blocked-by: []
summary: "WASM32 ONLY NOW -- the xtensa half LANDED in af5d2b534 (Call0; windowed stays false, and that is the ABI condition, not a gap). A proc's managed locals are released by a proc CLEANUP FRAME, and TargetHasProcCleanupFrame today covers x86-64, i386, arm32, aarch64, riscv32 and xtensa-under-Call0 -- wasm32 is the only target left out, so an exception unwinding THROUGH a wasm32 frame still leaks everything that frame owned. Silent by construction: an unwind leak prints nothing and both sides of the native-vs-wasm differential produce identical OUTPUT. The stale source comment this ticket flagged is ALSO already fixed. NOT WIRING (measured 2026-09-01): all three shared hooks are register-shaped -- every arm of EmitProcCleanupFramePatchLanding is Patch32(landPatch, branch-to-CodeLen), assuming a linear code buffer, a two-return setjmp entry and a patchable relative branch. wasm32 has none of the three (its pad is a BASIC BLOCK NUMBER; propagation is a pending global checked after every call), so the hooks have nothing to return or patch there. The wasm32 SEMANTICS do fit -- WasmEmitUnwind already branches to a frame whose fp matches, so a cleanup frame is a handler frame whose pad releases and re-raises. Real job is a design choice: give wasm32 its own path around the shared hooks, or generalise the pad to an opaque token across six backends. Plus three named sub-tasks: reserve a shadow-frame slot (the pre-pass counts IR_EXC_ENTER nodes and a proc frame is not one), materialise the pad as a block and get its number into the frame, and re-raise out of it. Predicate arm still LAST."

status: backlog
owner: unassigned
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

## CORRECTION 2026-09-01 (frankB): "wiring, not new machinery" is wrong about the INTERFACE

Read the three shared hooks before starting and did not start. The claim above
is right that wasm32's *frame* machinery exists and wrong about the part that
sets the size of the job.

**All three shared entry points are register-machine shaped, and the patcher
proves it.** `EmitProcCleanupFramePatchLanding` (`ir_codegen.inc:13022`) has one
arm per target and **every one of them** is

```pascal
Patch32(landPatch, <branch encoded from landPatch to CodeLen>)
```

x86-64, i386, arm32, aarch64, riscv32, xtensa — six arms, one shape. The
interface assumes three things at once:

1. a **linear code buffer with byte addresses** (`CodeLen`, `Patch32`),
2. a **two-return entry** — `EmitProcCleanupFrameEnterForTarget` does
   `setjmp`, `test eax,eax`, `jne landing`, and hands back the position of that
   `jne` for later patching,
3. a **patchable relative branch** to a code address.

**wasm32 has none of the three.** Its own backend comment says it outright:
*"the pad is a BASIC BLOCK NUMBER, not a code address — there are no code
addresses in a wasm module"*. There is no `setjmp`; propagation is a `pending`
global checked after every call (`WasmEmitPostCall` → `WasmEmitExcCheck` →
`WasmEmitUnwind`). A pad is reached by setting `$pc` and `br`ing to the dispatch
loop, not by a patched branch.

So `EmitProcCleanupFrameEnterForTarget(var landPatch: Integer)` has **no
meaningful value to return on wasm32**, and `...PatchLanding` has nothing to
patch.

## What IS true, and it is the good news

The wasm32 semantics are already there and are a close fit. `WasmEmitUnwind`
(`ir_codegen_wasm32.inc:3680`) already tests *"is the innermost handler frame
mine?"* by comparing the frame's `fp` against `$fp`, and branches to that
frame's pad when it matches. **A proc cleanup frame is exactly a handler frame
whose pad releases the managed locals and re-raises**, and an exception
unwinding out of a callee already arrives at that test via the post-call
pending check. Nothing new is needed at the raise site or the propagate site.

## So the actual job, correctly sized

Not "add a seventh arm". One of:

- **(a) Give wasm32 its own path** around the three shared hooks — the frontend
  gate at `pasparser_proc.inc:2571` calls the target hook, so wasm32 needs a
  branch there rather than an arm inside it. Smallest diff, and it is a second
  path for one concept, which `normalise-dont-special-case` says is the one
  that stays broken.
- **(b) Generalise the interface** so the landing pad is an opaque token each
  backend interprets (a code offset for five targets, a block number for
  wasm32). Larger, touches six working backends, and is the version that does
  not leave a second path.

**Both are real work with a design choice in front of them, not wiring.**

Three sub-tasks either way, none of which the "wiring" reading anticipates:
1. **Reserve a shadow-frame slot.** `WasmExcSites` is counted by a pre-pass over
   `IR_EXC_ENTER` nodes; a proc cleanup frame is emitted by the frontend and is
   not an IR node, so today it would index past the end and hit
   `WasmUnsupported('exception frame slot out of range')`.
2. **Materialise the cleanup pad as a basic block** and get its number into the
   frame's `pad` word, which is written in the prologue before that block
   exists — the wasm equivalent of the patch, and it needs its own mechanism.
3. **Re-raise out of the pad**: set `pending`, pop the frame, propagate.

## Why I released it rather than doing it

Verifiable here — wasmtime 48.0.1 and node v22.22.1 are both installed, so the
leak can actually be measured rather than argued about. What stopped me is
scope plus ranking: this is a shared-interface design decision across six
working backends, and it is wasm work, which the owner demoted on 2026-08-30
(*"they simply must not outrank ordinary Track A work"*). This ticket's 75 comes
from `umbrella-managed-memory-is-correct`, not from the wasm umbrella, so its
rank is legitimate — but the *work* is still wasm work, and
[[decide-the-wasm-umbrella-at-70-reinstates-everything-the-owner-demoted-to-25]]
is open on exactly that question. Starting a night of wasm backend work while
holding that filing open would contradict it.

Unclaimed and left accurate. Whoever takes it inherits the (a)/(b) choice
already framed and the three sub-tasks named.

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


---

## 2026-09-01 (frankB) — half of this ticket is already done; retitling the rest

Checked at HEAD rather than taken from the body, because two of this ticket's
three stated obstacles have gone since it was written.

**1. xtensa is IN.** `af5d2b534` ("fix(A+S): xtensa gets the proc exception
cleanup frame, Call0 only"). The predicate now reads:

```pascal
Result := (TargetArch = TARGET_X86_64) or (TargetArch = TARGET_I386) or
          (TargetArch = TARGET_ARM32) or (TargetArch = TARGET_AARCH64) or
          (TargetArch = TARGET_RISCV32) or
          ((TargetArch = TARGET_XTENSA) and (XtensaABI = XTENSA_ABI_CALL0));
```

Windowed stays false, and per frankS's 2026-08-30 note that is the ABI
condition rather than an unfinished half: `IR_EXC_ENTER` and `IR_RAISE` both
refuse under windowed, so there is no unwind to clean up after.

**2. The stale comment is fixed too.** The ticket's closing section says
`ir_codegen.inc` "still asserts *its managed-local arm handles AnsiString
alone*" and defers the fix to a Track S grant. Both halves are obsolete: the
comment now explicitly records that the claim *used to* be made and what
retired it (`e1d7977a2` one kind to six, `3a1c1dc73` the seventh), and the grant
system was cut on 2026-08-30, so no scoping reason remains for anyone to defer
a comment fix in that file. **Nothing to do here — do not go looking for it.**

**3. So the title and the summary were both wrong**, and a reader arriving from
the board would have gone hunting for two targets and a comment, of which one
target remains. Summary corrected in place; the title is left alone because the
slug is cited from `umbrella-managed-memory-is-correct` and elsewhere, and a
rename costs more than the wrong word saves.

### What actually remains

`TargetHasProcCleanupFrame` has no `TARGET_WASM32` arm, confirmed by grep. The
machinery the original fix note points at does exist —
`ir_codegen_wasm32.inc:4924` dispatches `IR_EXC_ENTER` to `WasmEmitExcEnter`,
and the body already tracks `WasmExcSites` and maps each enter to its handler
frame in the shadow frame.

**But do not price the job off "wiring, not new machinery."** That phrase is the
ticket body's own, and frankwasm — who wrote it — states it came from the ticket
rather than from reading the backend: *"a plausible read, not a measurement."*
What I verified is narrower and should be quoted at that width: the dispatch and
the shadow-frame bookkeeping EXIST. Whether they are sufficient as a proc
cleanup frame is unmeasured by anyone. I cited that phrase back at frankwasm as
though it were their confirmation, which it was not, and they corrected it — an
unverified claim travelling beside verified ones is how it picks up credibility
it did not earn.

The ordering warning does hold, and holds harder now that it is the only work
left: **the predicate arm is the LAST line of the change.** Adding
`TARGET_WASM32` to it before implementing the enter/leave arms reaches
`Error('compiler error: no proc exception cleanup frame for this target')` and
breaks every wasm build that owns a managed local.

### UNOWNED — not taken by me, and NOT handed off either

I hold the managed-memory group and this is one of its umbrella's blockers, but
the remaining half is wasm backend work in a lane I have no loaded context for,
and verifying it needs the wasm host oracles rather than a native repro.

**I messaged frankwasm to take it and that did not land. Do not read this ticket
as owned.** frankwasm is stood down and idle by the owner's instruction (2-3
concurrent agents; the slots are held elsewhere), and a peer cannot put an agent
back in rotation — that is the owner's call. So the wasm32 remainder is
**unowned**, which is a different state from parked and should be raised as such
rather than left looking assigned. Recorded here because a handoff nobody
accepted is exactly the residual that goes missing.
