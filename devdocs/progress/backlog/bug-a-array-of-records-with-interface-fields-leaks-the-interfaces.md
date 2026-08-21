---
track: A
prio: 45
type: bug
blocked-by: []
summary: "An array (static or dynamic) of records holding a COM interface field leaks every interface: the element walk calls PXXRecordRelease, which owns kinds 1-3 only, and nothing runs the unlocked kind-4 pass the scalar record path now has."
status: backlog
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
