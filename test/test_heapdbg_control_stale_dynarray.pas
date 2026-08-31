program test_heapdbg_control_stale_dynarray;
{ POSITIVE CONTROL for the -dPXX_HEAP_DEBUG stale-handle checks in
  PXXDynArrayIncRef / PXXDynArrayReleaseDepth (report kinds 10/11), and for the
  "is the size word a plausible block size" branch of the report. Not a
  regression test -- it asserts no output and passes trivially unplanted. It
  exists so the INSTRUMENT can be shown to speak before a silence is believed.

    -dPLANTDYN   a real stale handle       -> size=0x<a real class>
    -dPLANTDYN2  a fabricated pointer      -> size=0x????????
    (neither)    no plant                  -> no reports

  All three arms must exit 0. Same method as
  test_heapdbg_control_stale_string.pas: raw copy of the handle with no retain,
  let the original release free the block, plant it back, let the ordinary
  release path reach it. Build for a target that calls the Pascal routines. }
var
  a, b: array of AnsiString;
  p: Pointer;
  i, j: Integer;
  s: AnsiString;
begin
  SetLength(a, 4);
  for j := 0 to 3 do a[j] := 'q';
  p := Pointer(a);        { raw handle, no retain }
  a := nil;               { refcount to zero -> freed and poisoned }
{$ifdef PLANTDYN2}
  { Positive control for the "not a block" branch of the size field: a handle
    that points into the MIDDLE of the freed region, so the refcount slot still
    reads as poison (the check fires) but the word below the notional base is
    poison too, which is not a plausible size. This is the shape the arm32
    defect actually produced -- a fabricated pointer, not a real stale handle. }
  b := nil;
  PPointer(@b)^ := Pointer(Int64(p) + 64);
  b := nil;
{$endif}
{$ifdef PLANTDYN}
  b := nil;
  PPointer(@b)^ := p;     { stale handle into b's slot, still no retain }
  b := nil;               { the release path decrefs a FREED dynarray }
{$endif}
  for i := 1 to 500 do
  begin
    s := '';
    for j := 1 to 4 do s := s + 'a';
    s := '';
  end;
  WriteLn('done');
end.
