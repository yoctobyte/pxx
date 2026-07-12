program test_varcast_and_dec;
{ FPC variable typecasts as by-ref args + cast-deref/type-keyword Dec targets
  (Pascal Script's ParseToken(..., Cardinal(len), ...) and Dec(Byte(p^),32)). }
procedure Bump(var x: Cardinal);
begin
  x := x + 1;
end;
var n: Integer; b: Byte;
begin
  n := 41;
  Bump(Cardinal(n));       { variable typecast as var arg }
  writeln(n);
  b := Ord('a');
  Dec(Byte(b), 32);        { type-keyword cast as Dec target }
  writeln(b);
end.
