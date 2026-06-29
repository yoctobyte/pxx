program test_c_packed_aligned;
uses cpackedaligned;
var
  n: NormalStruct;
  p: PackedStruct;
  a: AlignedStruct;
  t: TypeAlignedStruct;
begin
  n.a := 'X';
  n.b := 42;
  writeln(n.a);
  writeln(n.b);
  writeln(SizeOf(NormalStruct));
  writeln(Int64(@n.b) - Int64(@n));

  p.a := 'P';
  p.b := 7;
  writeln(p.a);
  writeln(p.b);
  writeln(SizeOf(PackedStruct));
  writeln(Int64(@p.b) - Int64(@p));

  a.a := 'A';
  a.b := 8;
  writeln(a.a);
  writeln(a.b);
  writeln(SizeOf(AlignedStruct));
  writeln(Int64(@a.b) - Int64(@a));

  t.a := 'T';
  t.b := 16;
  writeln(t.a);
  writeln(t.b);
  writeln(SizeOf(TypeAlignedStruct));
  writeln(Int64(@t.b) - Int64(@t));
end.
