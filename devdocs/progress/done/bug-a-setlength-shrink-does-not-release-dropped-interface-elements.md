---
track: A
prio: 45
type: bug
blocked-by: []
summary: "SetLength shrinking a dynamic array of interfaces drops the tail elements without releasing them — shrinking 4→2 destroys 0 objects where FPC destroys 2. A leak, not a crash; the surviving elements and a later re-grow are all correct."
status: done
owner: claude-A
---

# SetLength shrink does not release dropped interface elements

- **Track A** (`PXXDynSetLen` in `compiler/builtin/builtinheap.pas` and the
  descriptor it walks).
- Found 2026-08-20 by an FPC differential probe of interfaces in containers.

## Measured

```pascal
var d: array of IFoo; i: Integer;
SetLength(d, 4);
for i := 0 to 3 do d[i] := TFoo.Create('s');
SetLength(d, 2);
writeln(destroyed);          { FPC: 2    pxx: 0 }
```

Everything else about the operation is right: the two survivors keep their
values, re-growing to 4 leaves `d[2]` nil, and the final tally is 2 of 4 rather
than a crash. Purely the dropped tail that leaks.

## Cause

`PXXDynSetLen` releases the dropped elements through the array's element
descriptor, which knows strings and managed records — the same `baseKind` set as
`PXXArrayReleaseImmediate` (1 = string, 3 = record + descriptor). A COM interface
element has no kind there, so the tail is simply forgotten.

## Relation to the other interface-container tickets

This is one of a family found the same day, all of them the element/member kind
being invisible to a container-level walk:

- `bug-a-a-local-array-of-interfaces-is-never-released-at-scope-exit` (static array)
- this one (dynamic array, shrink)
- `bug-a-a-record-copy-does-not-retain-an-interface-field` (record copy)
- `bug-a-class-managed-fields-not-finalized-on-destroy` (the original, and the
  one holding the deadlock blocker)

They want ONE fix, not four: an interface member kind in the descriptor plus a
release path that runs outside the non-reentrant heap spinlock. Do them together.

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
- 2026-08-21 — resolved, commit bcd8546f9.
