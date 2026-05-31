program test_reallocmem;
{ ReallocMem(p, n): resize preserving min(oldsize, newsize) bytes, free the old
  block, write the new pointer back to p. Covers grow (content preserved + grown
  region usable), shrink (prefix preserved), realloc(nil) = GetMem, and that the
  freed old block is recycled. }
type PB = ^Byte;
var p, old, q: PB; i: Integer;
begin
  p := GetMem(8);
  for i := 0 to 7 do p[i] := i + 1;
  old := p;

  ReallocMem(p, 64);                 { grow }
  for i := 0 to 7 do if p[i] <> i + 1 then begin writeln(0); Halt(1); end;
  writeln(1);                        { 1: grow preserved content }
  for i := 8 to 63 do p[i] := 50;
  writeln(p[63]);                    { 50: grown region usable }

  q := GetMem(8);                    { reuse the freed 8-byte block }
  if q = old then writeln(1) else writeln(0);   { 1: recycled }

  ReallocMem(p, 4);                  { shrink }
  for i := 0 to 3 do if p[i] <> i + 1 then begin writeln(0); Halt(1); end;
  writeln(1);                        { 1: shrink preserved prefix }

  q := nil;
  ReallocMem(q, 16);                 { realloc(nil) = GetMem }
  if q = nil then writeln(0) else writeln(1);    { 1: allocated }
  q[0] := 77;
  writeln(q[0]);                     { 77 }
end.
