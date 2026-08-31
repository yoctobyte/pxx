program test_heapdbg_control_stale_string;
{ POSITIVE CONTROL for the -dPXX_HEAP_DEBUG stale-handle check in PXXStrDecRef
  (report kind 8). Not a regression test -- it does not assert an output and it
  passes trivially without the plant. It exists so the INSTRUMENT can be shown
  to speak before any silence from it is believed.

  Build twice for a target whose release path is the Pascal routine (i.e. NOT
  x86-64, which releases through the hand-emitted AnsiStrReleaseAddr blob and
  where this check is structurally unable to fire):

    pascal26 --target=arm32 -dPXX_HEAP_DEBUG -dPLANTDEC  <this> plant
    pascal26 --target=arm32 -dPXX_HEAP_DEBUG             <this> clean

  Expected: `plant` prints exactly one
      pxx-heap: DECREF of a FREED string 0x...  size=0x...
  and exits 0; `clean` prints none and exits 0. A plant arm that exits 204 means
  the check is reaching PXXHdrBase, which Halt(204)s on a poisoned kind byte --
  that is how this check was silent for its whole first life.

  Method: take a RAW copy of the handle (no retain), let the original release
  free the block, then plant that raw handle back into a string variable's slot
  -- again with no retain -- and let the ordinary release path decref it. The
  string must be BUILT, not assigned from a literal: a literal may be a static
  block and never reaches the allocator at all. }
var
  s, q: AnsiString;
  p: Pointer;
  i, j: Integer;
begin
  s := '';
  for j := 1 to 16 do s := s + 'Z';
  p := Pointer(s);        { raw handle, no retain }
  s := '';                { refcount to zero -> freed and poisoned }
{$ifdef PLANTDEC}
  q := '';
  PPointer(@q)^ := p;     { stale handle into q's slot, still no retain }
  q := '';                { the release path decrefs a FREED string }
{$endif}
  for i := 1 to 3000 do
  begin
    s := '';
    for j := 1 to 4 do s := s + 'a';
    s := '';
  end;
  WriteLn('done');
end.
