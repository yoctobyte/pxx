program test_setlen_in_parallel_for_body;
{ The shape that motivated bug-a-setlength-on-a-captured-managed-string: a
  `parallel for` body calling SetLength on a captured AnsiString.

  The body is lifted with the string passed BY POINTER, so `SetLength(s, n)`
  inside it is a deref -- and the SetLength classifier only recognised a deref
  whose pointee was a dynamic ARRAY, never a managed string. `s := s + 'x'` in
  the same body compiled fine, which is what made this look like a threading
  problem rather than a lowering one.

  Positive control: `pinned` (992065f21f33) REFUSES this file with
  `SetLength expects a string variable in IR codegen`. Build --threadsafe.

  WHY `n 1` ON THE FIRST LOOP, AND DO NOT REMOVE IT.
  This file used to run that loop across the whole pool and assert total=8000.
  It is a DATA RACE and it failed ~20% of the time (16/20 correct in a plain
  build on `seven`; 3/15 on 4 cores), so it flaked in every sweep and was
  re-triaged by whoever next saw it:
  bug-a-a-parallel-for-body-shares-one-captured-string-across-all-workers.
  Nothing in the compiler was wrong. `s` is ONE enclosing local and
  docs/library/concurrency.md is explicit that captured locals are shared --
  "captured by reference through the frame", "accumulating into one shared
  variable is a data race unless you guard it". Every worker ran `s := ''`
  against another's `SetLength(s, 8)`. There is no `private(...)` clause, so
  the shape cannot be written race-free with a captured scalar; pinning the
  loop to one worker keeps the LOWERING under test -- which is what this file
  is for -- and removes the race. Widen it again and the flake comes back.

  The second loop is the concurrency the first one gives up: disjoint slots of
  a captured dynamic array, which the same docs call safe. It also covers
  SetLength through a deref one level further out (the pointee is an array
  whose ELEMENT is the managed string), a shape that was refused outright until
  bug-a-a-pointer-to-a-dynamic-array-indexes-with-a-4-byte-stride. }
{$mode objfpc}{$H+}
uses palparallel;
type TStrs = array of AnsiString;
var total, slots: Int64;

procedure RunCaptured;
var i: LongInt; s: AnsiString; acc: Int64;
begin
  acc := 0;
  parallel(pdChunked, n 1) for i := 0 to 999 reduction(+: acc) do
  begin
    s := '';
    SetLength(s, 8);
    acc := acc + Length(s);
  end;
  total := acc;
end;

procedure RunDisjoint;
var i: LongInt; arr: TStrs; acc: Int64;
begin
  SetLength(arr, 1000);
  parallel(pdChunked) for i := 0 to 999 do
  begin
    arr[i] := '';
    SetLength(arr[i], 8);
  end;
  acc := 0;
  for i := 0 to 999 do acc := acc + Length(arr[i]);
  slots := acc;
end;

begin
  RunCaptured;
  RunDisjoint;
  WriteLn('PARALLEL SETLEN OK total=', total, ' slots=', slots);
end.
