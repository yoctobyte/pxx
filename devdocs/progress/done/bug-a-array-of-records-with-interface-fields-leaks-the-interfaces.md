---
track: A
prio: 45
type: bug
blocked-by: []
summary: "An array (static or dynamic) of records holding a COM interface field leaks every interface: the element walk calls PXXRecordRelease, which owns kinds 1-3 only, and nothing runs the unlocked kind-4 pass the scalar record path now has."
status: done
owner: agent-A
---

# An array of records-with-interface-fields leaks the interfaces

Found while resolving
[[bug-a-a-record-copy-does-not-retain-an-interface-field]], which fixed the same
gap one level in (a plain record local/copy).

## Shape

```pascal
type TRec = record a: Integer; f: IFoo; end;
var arr: array[0..2] of TRec;   { or: array of TRec }
begin
  for i := 0 to 2 do arr[i].f := TFoo.Create('e');
end;   { FPC destroys 3 here. pxx destroys 0. }
```

## Cause

Element kind 3 (record with managed fields) routes the element walk through
`PXXRecordRelease`, and that helper owns kinds 1-3 **by design**: it runs with
the codegen heap lock held on x86-64 `--threadsafe`, where releasing an interface
would re-enter the non-reentrant spinlock. The interface half lives in
`PXXRecordReleaseIntf`, which the scalar record paths now call BEFORE the lock —
`PXXArrayReleaseImmediate` / `PXXDynArrayReleaseDepth` / `PXXDynSetLen` do not
call it at all.

Note the array's own element retain on whole-array copy has the mirror hole.

## Fix

Give the three element walks in `compiler/builtin/builtinheap.pas` a kind-3 arm
that calls `PXXRecordReleaseIntf` (respectively `PXXRecordRetainIntf`) alongside
`PXXRecordRelease`/`Retain` — the descriptor already carries the kind-4 members,
so nothing new has to be emitted. The lock question is the one to answer first:
the dynamic-array walks run under the codegen lock on x86-64 `--threadsafe`
(which is why `ManagedElemKindLocked` refuses kind-4 ELEMENTS there), so the
interface sub-pass has to be hoisted out of the locked region the same way, or
refused under `--threadsafe` and left as today's leak.

## Gate

`make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick`, plus a case in
`test/test_interface_containers.pas` with FPC-matched destroyed counts, native
and `--threadsafe` (must TERMINATE), and one cross target under qemu.

## Resolution 2026-08-21 (Track A)

Fixed the same day it was filed, immediately after its scalar twin
[[bug-a-a-record-copy-does-not-retain-an-interface-field]] — the machinery that
ticket added (`PXXRecordRetainIntf` / `PXXRecordReleaseIntf`, kind-4 members in
the record descriptor) is exactly what the element walks needed.

**It was not only a leak.** The ticket said "leaks the interfaces"; measured, a
whole-static-array copy `b := a` also DANGLED — the element retain never saw the
interface member, so nilling `a` destroyed the objects `b` still pointed at and
the next read segfaulted. Same array-shaped twin the scalar case had.

**Three runtime walks** in `compiler/builtin/builtinheap.pas` gained the
interface sub-pass beside their kind-3 arm: `PXXDynArrayRetainImmediate`
(unguarded — AddRef frees nothing), `PXXDynArrayReleaseDepth` and
`PXXArrayReleaseImmediate` (both `{$ifndef PXX_TS_HARDLOCK}`).

**Plus two x86-64 codegen sites that would otherwise OVER-release.** x86-64 does
not use `PXXDynSetLen`; SetLength is inlined, and its survivor retain called
`EmitManagedRecordRetain` (kinds 1-3) while the blanket release of the old block
now walks interfaces too. Measured before fixing: a shrink from 4 to 2 destroyed
**all four** and then dangled. Both arms — `IR_SETLEN_DYN` and the depth-1
`specialId` sibling — now emit `PXXRecordRetainIntf` first. This is the one part
that was not a copy of the scalar fix, and it is the part a "just add the arm to
the runtime" reading would have shipped broken.

**Measured against FPC 3.2.2**, `test/test_interface_containers.pas` extended
with the four record-element shapes:

| shape | FPC | pxx before | pxx after |
| --- | --- | --- | --- |
| `array[0..2] of TRec` at scope exit | 3 | 0 | **3** |
| `array of TRec` at scope exit | 3 | 0 | **3** |
| `SetLength(d,4)` → `SetLength(d,2)` | 2 | 0 | **2** |
| ...total after `SetLength(d,0)` | 4 | 0 | **4** |
| `b := a`, then nil `a`, read `b[0].f.Name` | `cc` | **SIGSEGV** | `cc` |
| destroyed after that copy's scope | 2 | 2 (both dead early) | **2** |

Identical output under qemu on **aarch64 / arm32 / i386 / riscv32**.

**Residual under `--threadsafe` on x86-64**, deliberate and asserted: the release
sub-pass is compiled out (`PXX_TS_HARDLOCK`), because `IR_SETLEN_DYN` and
`IR_DYNUNIQUE` hold the codegen spinlock across the walk and `_Release` re-enters
it through `FreeMem`. The identical residual, for the identical reason,
`ManagedElemKindLocked` already keeps for kind-4 ELEMENTS. The retain still runs,
so it is a LEAK and never a dangle, and the Makefile asserts the program
TERMINATES with those zero counts. Lifting it is
[[feature-a-reentrant-heap-lock-and-per-thread-arenas]].

Gate: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick` GREEN.

## Log
- 2026-08-21 — resolved, commit 7a9450ea8.
