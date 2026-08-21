---
track: A
prio: 40
type: bug
blocked-by: []
summary: "Only x86-64 releases a local DYNAMIC array at scope exit; the other four backends have no `ArrLen = -1` arm at all, so every local dyn array leaks its block there. Attempted 2026-08-21 and REVERTED: the release is only safe where every dyn-array STORE retains, and on those backends the class/record FIELD store (IR_STORE_DYN is x86-64 only) does not. Fix the retain sites first; the ticket now carries the audit list."
status: done
owner: claude-A
---

# Four backends never release a local dynamic array at scope exit

- **Track A** (`compiler/symtab.inc`, the four per-target `EmitProcEpilog` arms).
- Found 2026-08-21 by running the interface-container family's repro across
  targets after fixing it on x86-64.

## Measured

`grep -n 'ArrLen = -1' compiler/symtab.inc` finds exactly ONE scope-exit release
site, and it is inside x86-64's `EmitManagedLocalCleanup`. The i386, arm32,
aarch64 and riscv32 epilogues have no dynamic-array arm at all — they carry the
COM-interface arm, the static-array arm and the scalar string arm, and stop.

Same program, `LocalDyn` filling a local `array of IFoo` with two objects and
returning:

| target | destroyed at scope exit |
| --- | --- |
| x86-64 | **2** (correct — matches FPC) |
| aarch64 | 0 |
| i386 | 0 |

The interface elements make it *observable*; the underlying leak is not
interface-specific. A local `array of string`, `array of TManagedRec` or a plain
`array of Integer` leaks its block on those four targets just the same, because
nothing releases the allocation.

## Why it stayed invisible

Cross-target tests assert printed OUTPUT, and a leak prints nothing. The x86-64
arm has been there long enough that the shape reads as covered; the divergence
only surfaces when a test makes destruction observable, which is exactly what
`test/test_interface_containers.pas` now does — though it runs native-only
today, so it does not catch this either.

## Shape of the fix

Each of the four epilogues needs the arm x86-64 has:

```pascal
else if Syms[i].IsArray and (Syms[i].ArrLen = -1) then
  <load the slot>; PXXDynArrayRelease(data, desc)
```

with the target's own argument-passing. `GetOrAllocSymRTTI` already builds the
descriptor target-independently, and `PXXDynArrayRelease` is plain Pascal, so
there is nothing new to design — this is four mechanical arms plus the
`ManagedElemKindLocked` question below.

**Note the lock question is NOT the same on those targets.** x86-64 wraps the
call in `EmitAcquireHeapLock`, which is why `ManagedElemKindLocked` refuses
interface elements under `--threadsafe`. The other backends do not use that
codegen spinlock at all, so whether their arm should be locked, softlocked or
unlocked has to be answered rather than copied. If in doubt, mirror x86-64's
gate and file the difference — a leak under an opt-in flag is recoverable, a
deadlock is not.

## The deeper reading

Five hand-written copies of one epilogue is why half of them are missing an arm
each. `refactor-a-the-missing-layer-between-frontends-and-backends` is where
that gets solved properly; this ticket is the interim correctness fix, and
whoever takes the refactor should read the five arms first — the diffs between
them ARE the bug list.

## Gate

The interface-container repro run under each target's emulator destroys the same
counts x86-64 does; self-host fixedpoint; `tools/gate.sh quick`.


## 2026-08-21 — HALF LANDED (Track A), and the other half found its blocker

**arm32 and riscv32: done.** Both grew the arm x86-64 has, emitted UNLOCKED
(neither backend uses the codegen BSS spinlock, so there is nothing to hold and
`ManagedElemKindLocked`'s ThreadSafeMode refusal does not apply to them).
Measured, 200k calls of a routine with a local 8-element `array of string`:

| | before | after |
| --- | --- | --- |
| arm32 | 112 MB | **7.8 MB** |
| riscv32 | 112 MB | **7.7 MB** |

(~7 MB is the emulator's own floor; the shape is flat, not linear.) And
`test/test_interface_containers.pas` now reports `dyn: 2` on both, matching FPC
and x86-64 instead of 0.

**i386 and aarch64: reverted, and the reason is the finding.** Adding the
release to those two turned a silent leak into memory corruption, because
neither backend's `IR_STORE_SYM` has a whole-dynamic-array arm: `b := a`
aliases the handle WITHOUT retaining it, so releasing both at scope exit
double-frees. aarch64 SIGSEGVs on the second call of such a routine; i386
double-decrements a freed refcount word and carries on. On aarch64 there is a
second layer — `IR_STORE_SYM` tests `TypeKind = tyAnsiString` first, and an
array's TypeKind IS its element kind, so `array of string` is routed through the
scalar string store as well.

That is filed as
[[bug-a-i386-and-aarch64-dynamic-array-assignment-has-no-store-arm]] and this
ticket is now `blocked-by:` it. **Order matters**: retain first, release second.
The reverse lands a double free, which is exactly what was measured today.

arm32 and riscv32 were safe precisely because they already grew that store arm
(`bug-a-arm32-dynamic-array-assignment-has-no-store-arm`) — so the split is not
arbitrary, it follows the retain/release pairing, and it was measured per target
rather than assumed.

**Still out of scope: xtensa.** Its epilogue has neither a dyn-array arm nor a
static-array one; it is ESP-class and gets its own pass, not a copy of this one.

## What the five-copy epilogue cost, concretely

This ticket, [[bug-a-local-dynamic-array-of-string-is-released-as-a-string-handle]]
and the one above are all the same shape: five hand-written copies of one
epilogue, each missing a different arm, each divergence invisible because a leak
prints nothing. The audit that finds the rest is to diff the five arm-lists
against each other — the differences ARE the bug list — and
[[refactor-a-the-missing-layer-between-frontends-and-backends]] is where that
stops recurring.


## 2026-08-21 (second pass) — landed, then REVERTED, and this is the finding

The arm was added to arm32 and riscv32, gated green, and **pushed** (4999d2a62).
It regressed `test_dynarray_managed_field_reassign` on both: `1 1 1 1 1 1` became
`1 0 0 0 0 0`. Reverted in the following commit. Recorded rather than tidied
away, because the reason is the whole lesson.

**The rule this ticket got wrong twice.** A scope-exit release is only safe when
EVERY store that can put a handle into that local retains it. There is more than
one such store, and the second one was missed:

| store shape | x86-64 | i386 / arm32 / aarch64 / riscv32 |
| --- | --- | --- |
| `b := a` (symbol) | `IR_STORE_SYM` dyn arm, retains | arm32 + riscv32 retain; **i386 + aarch64 did not** (now fixed) |
| `obj.f := a` (field / nested) | `IR_STORE_DYN`, retains | **NONE — `IR_STORE_DYN` is x86-64 only** |

`defs.inc` says it outright: *"x86-64 only; other targets keep the IR_STORE_MEM
share path."* A share path does not retain. So `Items := tmp` inside a method
copies the handle, and adding the scope-exit release then frees the data the
FIELD now points at — which is exactly what the regression printed.

The first pass caught the symbol half by measuring (aarch64 SIGSEGV) and
concluded arm32/riscv32 were safe *because they had that arm*. True and
insufficient: the table above has two rows, and only one was checked. **Count
the store sites before adding a release, not the ones you happen to hit.**

## The audit this ticket now depends on

Before the arm can land on any non-x86-64 backend, every one of these must
retain on that backend:

1. `IR_STORE_SYM`, whole dyn array — done for all four
   ([[bug-a-i386-and-aarch64-dynamic-array-assignment-has-no-store-arm]] covered
   the last two).
2. **`IR_STORE_DYN` — field / nested-subarray store. Missing on all four.**
   This is the blocker; it wants either a per-backend arm or (better) the
   x86-64 lowering generalised so `ir.inc` stops emitting a different IR shape
   per target — see the note in `ir.inc` where the choice is made.
3. Any other path that publishes a handle into a local slot: function-result
   assignment (the move-semantics carve-out already in the symbol arms),
   `SetLength` publishing through a by-ref param, and open-array parameter
   marshalling. Each needs a yes/no answer per backend, written down here.

Only when 1-3 are all yes for a backend does its release arm go in — and then
the cross sweep below is the gate, not a spot check.

## Gate (revised)

Run the FULL dyn-array + interface test set under `tools/run_target.sh` for the
backend being changed and diff every one against the native answer — not
against `pinned`, which is old enough to fail some of them for unrelated
reasons. The two tests that caught this were
`test_dynarray_managed_field_reassign` and `test_dynarray_of_interfaces_assign`;
neither is in the quick tier, which is why the gate was green and the push was
still wrong.

## Unblocked 2026-08-21 — the retain half has landed

`IR_STORE_DYN` (the ARC-correct whole-dyn-array store into a slot ADDRESS: a
class/record field, a nested target) is now implemented on **i386, arm32,
aarch64 and riscv32**, and `ir.inc` emits it for every target except xtensa —
see `bug-a-named-dynarray-alias-element-crashes-on-every-cross-target`. That was
the sole reason this ticket was reverted the first time: a scope-exit release is
only safe when EVERY store that can put a handle into the local retains it, and
the field store did not.

Re-attempt is now in order, but re-run the audit rather than assuming: xtensa
still takes the non-retaining `IR_STORE_MEM` share path, so it must NOT get the
release arm, and `test_dynarray_managed_field_reassign` (the test that caught
the first attempt, `1 1 1 1 1 1` -> `1 0 0 0 0 0` on arm32/riscv32) is **not in
the quick tier** — run it per target under `tools/run_target.sh` by hand before
pushing.

## RESOLVED 2026-08-21 (third attempt, and this one measured before it landed)

All four backends now release a local dynamic array at scope exit —
i386, arm32, aarch64, riscv32 — unlocked, because `EmitAcquireHeapLock` is the
x86-64 codegen BSS spinlock and does not exist on these targets. **xtensa
deliberately still has no arm**: it is the one target that keeps the
non-retaining `IR_STORE_MEM` share path, so the retain half is genuinely absent
there and a release would double-free.

### The audit, answered rather than assumed

1. `IR_STORE_SYM`, whole dyn array — retains on all four (the last two landed in
   `bug-a-i386-and-aarch64-dynamic-array-assignment-has-no-store-arm`).
2. `IR_STORE_DYN`, field / nested target — **now retains on all four**
   (`bug-a-named-dynarray-alias-element-crashes-on-every-cross-target`). This
   was the blocker that made attempts one and two land a double free.
3. Every other publish path — answered by measurement, not by reading: the
   53-test cross differential below covers function-result assignment
   (`test_dynarray_result`, `test_interface_call_result_move`), `SetLength`
   through a by-ref param (`test_dynarray_params`), open-array marshalling and
   record/class field destinations. Nothing regressed on any of them.

### Gate — a differential, not a spot check

Built every test in the dyn-array + interface family (53 files) for native and
all four cross targets, ran each under `tools/run_target.sh`, and diffed against
the native answer. Baseline captured on the parent commit, re-run after:

```
broke = 0     fixed = 4     otherwise changed = 0
```

The four fixed are `test_interface_containers` on i386 / arm32 / aarch64 /
riscv32 — `dyn: 0` became `dyn: 2`, matching FPC and x86-64. Nothing else in the
family moved in either direction. (The driver is
`xdiff.py` in the session scratchpad; the 44-disagreement baseline it captured
is what the three new tickets below were filed from.)

### Leak, measured

200k calls of a routine with a local 8-element `array of Integer`, peak RSS
(`/usr/bin/time -f %M`; the emulator's own floor is ~7 MB):

| target | pinned | HEAD |
| --- | --- | --- |
| i386 | 137.7 MB | **7.4 MB** |
| arm32 | 146.4 MB | **7.7 MB** |
| aarch64 | 163.9 MB | **8.0 MB** |
| riscv32 | — | **7.4 MB** |

Flat, at the floor.

### One arm loaded by hand, and why

arm32 and riscv32 load the handle with an explicit pointer-width load instead of
`EmitLoadVarArm32` / `EmitLoadVarRISCV32`, because both size the load by
`TypeSize(Syms[].TypeKind)` — and an array's TypeKind is its ELEMENT kind, so
`array of Char` would come back through a byte load with the handle's top three
bytes gone. That is the same truncation `EmitLoadVarA64` carried until today.

### Found while measuring, filed separately

The leak probe used `a[i] := 'element-' + IntToStr(i)` and stayed linear after
the array leak closed. That residual is not an array bug at all:
[[bug-a-a-string-function-result-in-a-concat-leaks-on-every-cross-target]] —
`s := 'lit' + F(x)` leaks ~320 bytes per evaluation on all four cross targets,
flat on x86-64, and neither half leaks alone.

The 53-test baseline also surfaced, all pre-existing:
[[bug-a-a-function-returning-a-dynamic-array-is-refused-on-every-cross-target]]
(three tests unbuildable on all four) and
[[bug-a-ordered-string-comparison-of-a-parameter-compares-handles-on-every-cross-target]]
(a silent wrong answer).

## Log
- 2026-08-21 — resolved, commit PENDING-COMMIT.
