program test_c_packed_aligned;
uses cpackedaligned;
var
  n: NormalStruct;
  p: PackedStruct;
  a: AlignedStruct;
begin
  n.a := 'X';
  n.b := 42;
  writeln(n.a);
  writeln(n.b);

  { Since PackedStruct and AlignedStruct fall back to opaque pointers,
    they are imported as pointer types. We can assign nil to them. }
  p := nil;
  a := nil;
  if p = nil then writeln('PackedStruct is opaque');
  if a = nil then writeln('AlignedStruct is opaque');
end.
