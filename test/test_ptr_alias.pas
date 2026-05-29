program test_ptr_alias;
{ Named pointer type aliases (PFoo = ^TFoo) carry their element type, so a var
  of the alias type derefs at the right width. Phase 2 (typed-pointer) step 1. }
type
  PInt64 = ^Int64;
  PInt   = ^Integer;
var
  buf: array[0..3] of Int64;
  ibuf: array[0..3] of Integer;
  p: PInt64;
  q: PInt;
begin
  buf[0] := 777;
  p := @buf[0];
  writeln(p^);
  p^ := 888;
  writeln(buf[0]);

  ibuf[0] := 12;
  q := @ibuf[0];
  writeln(q^);
  q^ := 34;
  writeln(ibuf[0]);
end.
