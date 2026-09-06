program TestThreadsafeDynarrayReleasesVariantAndInterfaceElements;
{ Under --threadsafe, a dynamic array of Variants or of COM interfaces must
  release its ELEMENTS, not just its buffer.

  It did not, for a reason that was correct at the time: ManagedElemKindLocked
  degraded element kinds 4 (COM interface) and 6 (Variant) to 0 whenever
  ThreadSafeMode was set, because releasing an interface element runs
  _Release -> Destroy -> FreeMem and FreeMem re-acquired the same NON-REENTRANT
  spinlock the dyn-array paths already held. The program would HANG rather than
  leak, and a hang is worse than a leak. So it leaked the whole array on every
  release, forever, in the build a long-running server uses.

  MEASURED, this file, 1000 trips of each shape, -dPXX_ALLOC_CENSUS:

      pinned (pre-fix)              allocs=13891  frees=5952   live=7939
      HEAD                          allocs=13891  frees=13888  live=3
      HEAD -dPXX_NO_REENTRANT_HEAPLOCK            rc=212, the deadlock

  Same allocation count on the two that finish, so it is the free side alone —
  and the third row is the POSITIVE CONTROL, which is the whole reason this test
  is worth more than its live count. Turning the reentrant heap lock off makes
  this exact program hit Runtime error 212 with the heap-lock diagnosis on
  stderr, so the row cannot pass for a reason unrelated to what it is testing,
  and the reentrancy is demonstrated LOAD-BEARING rather than assumed.
  Check the message, not just the code: 212 arriving for another reason would
  pass this control and prove nothing.

  A VALUE ASSERTION CANNOT OBSERVE THIS. The program printed the right answer
  throughout; tools/assert_no_leak.sh is the instrument, and the Makefile runs
  it under -dPXX_ALLOC_CENSUS with a bound.

  feature-a-make-the-heap-lock-reentrant
  bug-a-threadsafe-builds-leak-every-variant-and-interface-element-of-a-dynamic-array }
{$MODE OBJFPC}{$H+}
uses sysutils, variants;
type
  IThing = interface ['{11111111-2222-3333-4444-555555555555}'] procedure Ping; end;
  TThing = class(TInterfacedObject, IThing) public procedure Ping; end;
procedure TThing.Ping; begin end;
var i, k: Integer;
procedure TripVariant;
var a: array of Variant; j: Integer;
begin
  SetLength(a, 4);
  for j := 0 to 3 do a[j] := 'v' + IntToStr(j);
end;
procedure TripIntf;
var a: array of IThing; j: Integer;
begin
  SetLength(a, 4);
  for j := 0 to 3 do a[j] := TThing.Create;
end;
begin
  for i := 1 to 1000 do begin TripVariant; TripIntf; end;
  k := 0; WriteLn('TSDYN OK ', k);
end.
