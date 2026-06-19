program TestUInt64Ops;
{ 64-bit operator + UInt64 coverage: xor, large shl/shr, UInt64 type alias and
  full-width store/load, and the unsigned writer for values >= 2^63 (top bit
  set). Regression for bug-64bit-shift-xor-literal-gaps. }
var
  a, b: UInt64;
  bo: Boolean;
begin
  a := $853C49E6748FEA9B;
  writeln(a);                 { 9600629759793949339 — UInt64 full width + writer >= 2^63 }
  writeln(a xor a);           { 0 }
  b := a xor $FFFFFFFFFFFFFFFF;
  writeln(b);                 { 8846114313915602276 — bitwise NOT }
  writeln(a shl 8);           { 4344256703880665856 }
  writeln(a shr 60);          { 8 }
  writeln(UInt64(1) shl 40);  { 1099511627776 }
  bo := True xor False; writeln(bo);   { TRUE }
  bo := True xor True;  writeln(bo);   { FALSE }
  writeln(12 xor 10);         { 6 — plain Integer xor }
end.
