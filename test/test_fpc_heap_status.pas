{ System.GetFPCHeapStatus / TFPCHeapStatus / ErrorAddr.

  These exist for FPC's own testsuite helper `erroru.pp`, which is the unit
  behind five conformance skip rows. The rows' recorded blocker list was
  ExitCode + ErrorAddr + TFPCHeapStatus + GetFPCHeapStatus; ExitCode turned out
  to have been present for a while (the skip prose was stale) and the other
  three landed together.

  EVERY ROW HERE ASSERTS A RELATION, NEVER A BYTE COUNT. The absolute numbers
  are allocator- and target-dependent by construction -- a per-target constant
  would pin this file to x86-64's arena behaviour and fail correctly-different
  numbers everywhere else. `size >= used` and `free = size - used` hold on any
  allocator; `used=137216` holds on one.

  THE LEAK ROW IS THE POSITIVE CONTROL AND IT IS THE POINT OF THE FILE. A live
  counter that is never decremented passes `used > 0`, passes `size >= used`,
  and passes every other row here. Only a deliberate leak proves the counter can
  MOVE, and only the churn row proves it moves BACK -- one without the other is
  a guard that cannot fail in one direction.

  WHY THE LEAK ROW ASSERTS `>= 64000` AND NOT `= 64000`. Measured 2026-09-05 for
  1000 blocks of 64 bytes: pxx reports 64000, fpc 3.2.2 reports 96000. Neither
  is wrong and this is not a divergence to fix -- our CurrHeapUsed counts PAYLOAD
  bytes (8-rounded, header excluded), fpc's counts its own block accounting, and
  each is a true statement about its own allocator's representation. It is the
  same class as SizeOf answering 8 where fpc answers 4: introspection reporting
  a real implementation choice faithfully. Recorded as CHOSEN, not tolerated.
  `>= 64000` is the claim both allocators must satisfy -- you cannot leak 1000
  64-byte blocks and account for less than the payload -- so this whole file
  is diffed against fpc and matches, which a `= 64000` row would have cost. }
program test_fpc_heap_status;
var
  h0, h1, h2: TFPCHeapStatus;
  p: Pointer;
  i: Integer;
  leaked: NativeUInt;
begin
  { ErrorAddr is writable — that is the whole of what erroru.pp asks of it. }
  ErrorAddr := nil;
  WriteLn('erroraddr writable : ', ErrorAddr = nil);

  h0 := GetFPCHeapStatus;
  WriteLn('size >= used       : ', h0.CurrHeapSize >= h0.CurrHeapUsed);
  WriteLn('free = size - used : ', h0.CurrHeapFree = h0.CurrHeapSize - h0.CurrHeapUsed);
  WriteLn('peak >= used       : ', h0.MaxHeapUsed >= h0.CurrHeapUsed);
  WriteLn('maxsize >= size    : ', h0.MaxHeapSize >= h0.CurrHeapSize);

  { A big block must show up, and must go away again. }
  p := GetMem(100000);
  h1 := GetFPCHeapStatus;
  WriteLn('alloc is visible   : ', h1.CurrHeapUsed - h0.CurrHeapUsed >= 100000);
  FreeMem(p);
  h2 := GetFPCHeapStatus;
  WriteLn('free is visible    : ', h2.CurrHeapUsed = h0.CurrHeapUsed);
  WriteLn('peak kept the max  : ', h2.MaxHeapUsed >= h1.CurrHeapUsed);

  { Churn must not drift: this is what catches an add/subtract that are not
    the same quantity (a rounded size in, an unrounded size out). }
  for i := 1 to 2000 do begin p := GetMem(64); FreeMem(p); end;
  WriteLn('no drift over 2000 : ', GetFPCHeapStatus.CurrHeapUsed = h2.CurrHeapUsed);

  { POSITIVE CONTROL: the counter must be able to report a leak. }
  h0 := GetFPCHeapStatus;
  for i := 1 to 1000 do p := GetMem(64);
  leaked := GetFPCHeapStatus.CurrHeapUsed - h0.CurrHeapUsed;
  WriteLn('leak >= payload    : ', leaked >= 64000);
  if p = nil then WriteLn('unreachable');
end.
