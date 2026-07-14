program shl32;
var l: longint; c: cardinal; n: longint;
begin
  l := 1; n := 31;
  writeln(int64(l shl n));         { FPC: -2147483648 }
  c := 1;
  writeln(int64(c shl n));         { FPC: 2147483648 }
  l := -2147483648;
  writeln(int64(l shr 9));         { 4194304 }
  writeln(int64(l shl 1));         { 0 }
end.
