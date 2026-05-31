program test_freemem;
{ FreeMem returns a block to the free list; GetMem reuses a fitting freed
  block (first-fit, no split) before bump-allocating. Covers reuse, the
  too-small skip, data integrity across reuse, and nil-safe free. }
type
  PB = ^Byte;
var
  p, q, r: Pointer;
  a, b, c: PB;
  i: Integer;
begin
  { free then re-request same size -> the freed block comes back }
  p := GetMem(64);
  FreeMem(p);
  q := GetMem(64);
  if q = p then writeln(1) else writeln(0);     { 1: reused }

  { free list now empty -> a fresh, distinct block }
  r := GetMem(64);
  if r <> q then writeln(1) else writeln(0);     { 1: distinct }

  { a freed small block must not satisfy a larger request }
  a := GetMem(16);
  FreeMem(a);
  b := GetMem(128);
  if b <> a then writeln(1) else writeln(0);     { 1: skipped small }

  { a request that fits a freed block reuses it, and the bytes survive }
  FreeMem(b);
  c := GetMem(64);
  if c = b then writeln(1) else writeln(0);      { 1: fit }
  for i := 0 to 63 do c[i] := i;
  for i := 0 to 63 do if c[i] <> i then begin writeln(0); Halt(1); end;
  writeln(1);                                    { 1: data intact }

  FreeMem(nil);                                  { no-op, no crash }
  writeln(1);                                    { 1: nil ok }
end.
