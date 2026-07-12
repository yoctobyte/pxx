program test_freemem;
{ FreeMem returns a block to the free list; GetMem reuses a freed block before
  bump-allocating. Covers reuse, data integrity across reuse, and nil-safe free.

  Reuse is EXACT-FIT, by size class (segregated free lists, feature-opt-heap-size-
  class-allocator): a freed block is only handed back to a request of the SAME
  rounded size. It used to be first-fit over one global list, which walked O(n) and
  would hand a 128-byte freed block to a 64-byte request without splitting it —
  reuse, but at the cost of a walk and permanent internal fragmentation. Exact-fit
  makes alloc O(1) and wastes nothing; the larger block simply waits for a request
  of its own size, which is the steady state of any real workload.

  Blocks above HEAP_BIN_MAX (512) keep the old first-fit list, so a large freed
  block still satisfies a smaller large request. That is checked below too. }
type
  PB = ^Byte;
var
  p, q, r: Pointer;
  a, b, c, d: PB;
  big1, big2: Pointer;
  i: Integer;
begin
  { free then re-request the SAME size -> the freed block comes back }
  p := GetMem(64);
  FreeMem(p);
  q := GetMem(64);
  if q = p then writeln(1) else writeln(0);     { 1: reused }

  { that bin is empty again -> a fresh, distinct block }
  r := GetMem(64);
  if r <> q then writeln(1) else writeln(0);    { 1: distinct }

  { a freed SMALL block must not satisfy a LARGER request }
  a := GetMem(16);
  FreeMem(a);
  b := GetMem(128);
  if b <> a then writeln(1) else writeln(0);    { 1: skipped small }

  { ...and a freed LARGER block does not satisfy a smaller one either: exact fit }
  FreeMem(b);
  c := GetMem(64);
  if c <> b then writeln(1) else writeln(0);    { 1: no size-mismatch reuse }

  { the 128 block is still there for a 128 request, and the bytes survive }
  d := GetMem(128);
  if d = b then writeln(1) else writeln(0);     { 1: exact-fit reuse }
  for i := 0 to 127 do d[i] := i and 255;
  for i := 0 to 127 do if d[i] <> (i and 255) then begin writeln(0); Halt(1); end;
  writeln(1);                                   { 1: data intact }

  { above the bin cap the old first-fit list still serves a smaller request }
  big1 := GetMem(4096);
  FreeMem(big1);
  big2 := GetMem(2048);
  if big2 = big1 then writeln(1) else writeln(0);  { 1: large first-fit }

  FreeMem(nil);                                 { no-op, no crash }
  writeln(1);                                   { 1: nil ok }
end.
