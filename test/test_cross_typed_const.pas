program test_cross_typed_const;
{ Typed constants with initializers: scalar + ordinal/Int64 arrays (FPC typed
  consts are writable globals with an initial value). Byte-identical everywhere. }
const
  Limit: Integer = 100;
  Big:   Int64 = 9000000000;
  Tab:   array[0..4] of Integer = (3, 1, 4, 1, 5);
  Lut:   array[1..3] of Int64 = (1000000000, 2000000000, 3000000000);
var i, s: Integer; q: Int64;
begin
  writeln('limit=', Limit, ' big=', Big);
  s := 0; for i := 0 to 4 do s := s + Tab[i];
  writeln('tabsum=', s);
  q := 0; for i := 1 to 3 do q := q + Lut[i];
  writeln('lutsum=', q);
  { typed const is writable (FPC semantics) }
  Tab[2] := 40; writeln('tab2=', Tab[2]);
end.
