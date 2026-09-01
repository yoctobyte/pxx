{ The --threadsafe heap magazine's correctness contract, on the paths a
  benchmark never touches: sizes straddling both bounds of the cached range,
  blocks reused after being dirtied, and two live blocks of one size class at
  once (the second GetMem MUST miss and reach the global allocator, because the
  magazine is depth one).

  Every check is a VALUE comparison, not a "did not crash". The failure mode
  this guards is a block handed back with stale bytes, which faults nowhere and
  surfaces later as a managed header or a dynarray slot holding garbage.

  POSITIVE CONTROL, run rather than asserted: with the `rep stosb` deleted from
  EmitHeapMagAllocTry and the compiler rebuilt, the 'reused' row reports
  `byte 0 = 171` -- 171 is $AB, the fill byte below, read back out of a block
  the magazine handed over without zeroing. So this test can fail, and it fails
  by naming the exact byte. The zeroing was restored immediately; the point of
  recording it here is that a guard nobody has ever seen go red is not a guard.

  It runs under --threadsafe AND plain (the magazine only exists in the first,
  and the second is the control that the SAME source is correct without it),
  and passes identically both ways.
  feature-a-reentrant-heap-lock-and-per-thread-arenas }
program test_threadsafe_heap_magazine;

var
  bad: Integer;

procedure CheckZeroed(p: PByte; n: Integer; const tag: AnsiString);
var i: Integer;
begin
  for i := 0 to n - 1 do
    if PByte(PtrInt(p) + i)^ <> 0 then
    begin
      WriteLn('FAIL: ', tag, ' byte ', i, ' = ', PByte(PtrInt(p) + i)^, ', want 0');
      bad := bad + 1;
      Exit;
    end;
end;

procedure Fill(p: PByte; n: Integer; v: Byte);
var i: Integer;
begin
  for i := 0 to n - 1 do PByte(PtrInt(p) + i)^ := v;
end;

procedure RoundTrip(n: Integer);
{ Alloc, dirty, free, alloc the same class again -- the second alloc is the one
  that comes out of the magazine, and it must be ZEROED even though the block it
  reuses was full of $AB. This is the check that catches a missing `rep stosb`,
  which nothing else notices until a managed header reads garbage. }
var p, q: PByte;
begin
  GetMem(p, n);
  CheckZeroed(p, n, 'fresh');
  Fill(p, n, $AB);
  FreeMem(p);
  GetMem(q, n);
  CheckZeroed(q, n, 'reused');
  FreeMem(q);
end;

procedure TwoLive(n: Integer);
{ Two blocks of one class alive at once. The magazine holds at most one, so the
  second GetMem must fall through to the locked allocator and hand back a
  DIFFERENT block -- if the fast path ever returned the same pointer twice the
  program would alias them silently. }
var p, q: PByte;
begin
  GetMem(p, n);
  GetMem(q, n);
  if p = q then begin WriteLn('FAIL: two live blocks alias at n=', n); bad := bad + 1; end;
  Fill(p, n, 1);
  Fill(q, n, 2);
  if p^ <> 1 then begin WriteLn('FAIL: first block clobbered at n=', n); bad := bad + 1; end;
  FreeMem(p);
  FreeMem(q);
end;

procedure Sizes;
var n: Integer;
begin
  { every class boundary, plus the two edges of the magazine's range and sizes
    beyond it that must always take the locked path }
  n := 1;
  while n <= 40 do begin RoundTrip(n); TwoLive(n); n := n + 1; end;
  n := 504;
  while n <= 544 do begin RoundTrip(n); TwoLive(n); n := n + 8; end;
  RoundTrip(4096); TwoLive(4096);
  RoundTrip(65536);
end;

procedure Nested;
{ free order reversed relative to alloc order, and a free of nil }
var a, b, c: PByte;
begin
  GetMem(a, 64); GetMem(b, 64); GetMem(c, 64);
  Fill(a, 64, 7); Fill(b, 64, 8); Fill(c, 64, 9);
  if (a^ <> 7) or (b^ <> 8) or (c^ <> 9) then
  begin WriteLn('FAIL: three live 64-byte blocks overlap'); bad := bad + 1; end;
  FreeMem(a); FreeMem(c); FreeMem(b);
  a := nil;
  FreeMem(a);          { nil free takes the fast path's early exit }
end;

var i: Integer;
begin
  bad := 0;
  for i := 1 to 50 do
  begin
    Sizes;
    Nested;
  end;
  if bad = 0 then WriteLn('MAGAZINE OK') else WriteLn('MAGAZINE FAIL: ', bad);
end.
