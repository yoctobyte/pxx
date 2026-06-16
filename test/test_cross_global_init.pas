program test_cross_global_init;
{ Constant global-var initializers: scalar (Integer/Int64/Boolean) and array.
  Were silently discarded (globals read 0); now emitted before the body.
  Byte-identical on every target. }
var
  k: Integer = 42;
  q: Int64 = 5000000000;
  flag: Boolean = True;
  tab: array[0..4] of Integer = (10, 20, 30, 40, 50);
  lut: array[1..3] of Int64 = (1000000000, 2000000000, 3000000000);
var i, s: Integer; sq: Int64;
begin
  writeln('k=', k, ' q=', q, ' flag=', flag);
  s := 0;
  for i := 0 to 4 do s := s + tab[i];
  writeln('tabsum=', s);
  sq := 0;
  for i := 1 to 3 do sq := sq + lut[i];
  writeln('lutsum=', sq);
end.
