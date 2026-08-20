---
track: A
prio: 45
type: bug
blocked-by: []
summary: "A local `array[0..N] of IFoo` is never released at scope exit — a routine that fills three elements and returns destroys none of them. The same two-arm gap that left the array un-zero-initialised (now fixed) also leaves it un-cleaned: SymNeedsManagedCleanup answers False for it, and EmitManagedLocalCleanup has no per-element interface walk."
status: done
owner: claude-A
---

# A local array of interfaces is never released at scope exit

- **Track A** (`compiler/symtab.inc` — `SymNeedsManagedCleanup`,
  `EmitManagedLocalCleanup`; `compiler/builtin/builtinheap.pas`).
- Split out of `bug-a-a-local-array-of-interfaces-is-not-zero-initialised`, which
  fixed the crashing half (the init) and left this.

## Measured

pxx at `HEAD` with the init fix in place:

```pascal
procedure P;
var i: Integer; keep: array[0..2] of IFoo;
begin
  for i := 0 to 2 do keep[i] := TFoo.Create('r' + IntToStr(i));
end;                      { FPC destroys 3 here.  pxx destroys 0. }
```

Bounded by the array length per call, but a routine called in a loop leaks
linearly. Explicitly nilling every element before returning is a full workaround,
which is why the shape often looks fine in existing tests.

## Cause

Exactly the gap the init fix documented, on the cleanup side:

- `SymNeedsManagedCleanup` keys on `SymIsComInterface`, which answers **False for
  an array** by design, and on `RecordHasManagedFields(ElemRec)`, which is False
  for an interface UCls (no managed *fields*). So the routine is not even flagged
  as needing a cleanup block.
- `EmitManagedLocalCleanup`'s static-array arm calls `PXXArrayReleaseImmediate`,
  which understands `baseKind` 1 (string) and 3 (record + descriptor) only.

## Suggested fix

1. `SymElemIsComInterface` already exists (added by the init fix) — use it in
   `SymNeedsManagedCleanup`.
2. Add a runtime helper `PXXIntfArrayRelease(arrData, len, ifaceId)` to
   builtinheap — a straight loop over `PXXIntfRelease(itemAddr, ifaceId)`, which
   is nil-safe, so a partly-filled array is fine. Register it beside
   `PXXIntfRelease` in `parser.inc`.
3. Emit it from `EmitManagedLocalCleanup`'s array arm when
   `SymElemIsComInterface`. N-D arrays are stored flat, so `ArrLen` is the count
   — same as the existing string/record arms.

Do NOT unroll N release calls instead: `ArrLen` can be large and this is a
prologue/epilogue path.

## Note on scope

While here, check the same question for a **global** array of interfaces at
program exit, and for an interface array FIELD of a record or class — the
finalizer walks fields by kind and interfaces-in-aggregates have been the
recurring gap in this family. If either is also unhandled, fold it in rather
than filing a third ticket.

## Gate

Track A: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick`. Extend
`test/test_interface_local_array_zero_init.pas` with a destroyed-count check
after the owning routine returns.

## Resolution 2026-08-21 (Track A)

Fixed together with its siblings — one absent case, not four bugs.

**Root cause.** The policy "what must a container's element walk do for this
element type" was written out **nine times**: `ir.inc`'s two whole-static-array
copy branches, `ir_codegen.inc`'s two dyn-array descriptor allocators, its
`IR_SETLEN_DYN` retain guard, its `specialId = 102` (depth-1 SetLength) retain
guard, `rtti_emit.inc`'s descriptor writer, and `symtab.inc`'s five per-target
scope-exit arms. Every one of them knew kind 1 (AnsiString) and kind 3 (managed
record). **None** of them knew a COM interface. That is the exact shape
`devdocs/dev/normalise-dont-special-case.md` describes — one missing case
reachable through nine doors, presenting as four separate leaks.

**Fix.** `ManagedElemKind(elemTk, elemRec)` in `compiler/symtab.inc` is now the
single owner of that policy (0 / 1 / 3 / **4 = COM interface**), with
`ManagedElemRef` for the paired argument, and all nine sites ask it. Kind 4
carries the INTERFACE ID in the descriptor word that kind 3 uses for a relative
sub-descriptor offset — the same discriminated slot a CLASS layout descriptor
already uses for its kind-4 members, so this is the existing convention extended
rather than a new one. `builtinheap` gained kind-4 arms in
`PXXArrayReleaseImmediate`, `PXXDynArrayRetainImmediate` and
`PXXDynArrayReleaseDepth`, and the three `baseRecDesc` derivations pass the id
through.

**SetLength shrink falls out of the design rather than needing its own code**:
the resize retains the survivors and then releases the whole old block, so a
survivor nets zero and a dropped element nets exactly one release.

**Measured against FPC**, same program, `fpc -O- -Mobjfpc`:

| | FPC | pxx before | pxx after |
| --- | --- | --- | --- |
| static `array[0..2] of IFoo` at scope exit | 3 | 0 | **3** |
| local `array of IFoo` at scope exit | 2 | 0 | **2** |
| `SetLength(d, 4)` then `SetLength(d, 2)` | 2 | 0 | **2** |
| ...total after `SetLength(d, 0)` | 4 | 0 (then SIGSEGV) | **4** |
| `b := a` on `array[0..1] of IFoo`, then nil `a` | 0, `b` alive | 0, `b` DANGLING | **0, `b` alive** |

The last row was not in any of these tickets: whole-static-array assignment took
the raw byte copy for interface elements, so both arrays held the same counted
references. It is the array-shaped twin of
[[bug-a-a-record-copy-does-not-retain-an-interface-field]] and it is now fixed.

**The heap-lock hazard, handled and NOT guessed at.** Releasing an interface
element runs `_Release -> Destroy -> FreeMem`, and the FreeMem intrinsic
re-acquires the non-reentrant codegen spinlock. Every x86-64 DYNAMIC-array path
holds that lock across the release, so kind 4 there would HANG rather than leak.
`ManagedElemKindLocked` refuses kind 4 whenever `ThreadSafeMode` is on, which
keeps the pre-existing leak under `--threadsafe` — the identical residual, for
the identical reason, that [[bug-a-class-managed-fields-not-finalized-on-destroy]]
recorded for record fields. STATIC arrays are not gated: their walk is emitted
outside any lock, the same shape the scalar-interface arm has shipped with for a
long time. Both are asserted in the Makefile, including that `--threadsafe`
still TERMINATES.

Lifting the residual is [[decide-interface-members-in-aggregates-lock-strategy]]
(Track U) — one decision covering records, classes and containers together.

**Found and fixed alongside** (same function, same "an array's TypeKind IS its
element kind" trap): [[bug-a-local-dynamic-array-of-string-is-released-as-a-string-handle]],
a 112 MB-per-200k-calls leak present on `pinned` too.
**Found and filed, not fixed** (out of scope, four backends):
[[bug-a-no-dyn-array-scope-exit-release-on-four-backends]].

Regression: `test/test_interface_containers.pas`, native + `--threadsafe`, every
count taken from an FPC differential run of that exact program.
Gate: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick` GREEN.

## Log
- 2026-08-21 — resolved, commit bcd8546f9.
