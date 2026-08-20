---
track: A
prio: 45
type: bug
blocked-by: []
summary: "A local dynamic array of interfaces is not released at scope exit — a routine that fills two elements and returns destroys neither. Explicitly nilling every element before returning is a complete workaround, which is why the shape usually looks fine."
status: done
owner: claude-A
---

# A local dynamic array of interfaces is not released at scope exit

- **Track A** (`compiler/symtab.inc` `EmitManagedLocalCleanup` /
  `PXXDynArrayRelease`'s descriptor walk).
- Found 2026-08-20 by an FPC differential probe of interfaces in containers.

## Measured

```pascal
procedure LocalDyn;
var d: array of IFoo;
begin
  SetLength(d, 2);
  d[0] := TFoo.Create('a');
  d[1] := TFoo.Create('b');
end;                          { FPC destroys 2 here.  pxx destroys 0. }
```

Nilling both elements first destroys 2 correctly, on pinned and HEAD alike — so
the element assignment path is fine and only the scope-exit walk is missing.

## Cause

Same shape as the static-array and SetLength-shrink tickets: the dyn-array
release walks elements by a `baseKind` that knows strings (1) and records (3),
and a COM interface element has no kind there.

## Do it with the family

`bug-a-setlength-shrink-does-not-release-dropped-interface-elements`,
`bug-a-a-local-array-of-interfaces-is-never-released-at-scope-exit`,
`bug-a-a-record-copy-does-not-retain-an-interface-field` and
`bug-a-class-managed-fields-not-finalized-on-destroy` are all the same missing
descriptor kind plus the heap-lock blocker. One change closes all five.

## Gate

Track A: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick`.

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
- 2026-08-21 — resolved, commit PENDING-COMMIT.
