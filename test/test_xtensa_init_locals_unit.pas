unit test_xtensa_init_locals_unit;
interface
var G: LongInt; GS: string;
implementation
uses SysUtils;
initialization
var i, acc: LongInt; s: string; q: Int64;
begin
  acc := 0; s := '';
  for i := 1 to 5 do begin acc := acc * 3 + i; s := s + Chr(Ord('a') + i); end;
  q := Int64(acc) shl 33;
  G := acc + LongInt(q shr 33); GS := s + '/' + IntToStr(acc);
end;
finalization
  writeln('fini ', G);
end.
