program test_a_cast_of_an_untyped_deref_reads_at_the_casts_width;
{$mode objfpc}
{ A value cast of an UNTYPED memory reference -- p^ over a bare Pointer, or an
  untyped const/var parameter -- reinterprets the memory at the CAST's width.
  bug-p-a-cast-of-an-untyped-deref-reads-at-native-width }
type
  TColor = (cRed, cGreen, cBlue);
var
  p: Pointer;
  b: array[0..1] of Int64;
  s: Single;
  d: Double;
  w: Word;
  c: TColor;
  x: Int64;

procedure ShowConst(const v);
begin
  WriteLn('const Int64 ', Int64(v));
  WriteLn('const QWord ', QWord(v));
end;

procedure ShowDouble(const v);
begin
  WriteLn('const Double ', Double(v):0:3);
end;

procedure Bump(var v);
begin
  Int64(v) := Int64(v) + 1;
end;

begin
  b[0] := 5000000000; b[1] := -2;
  p := @b;
  WriteLn('Int64 ', Int64(p^));
  WriteLn('QWord ', QWord(p^));
  WriteLn('LongInt ', LongInt(p^));
  WriteLn('Word ', Word(p^));
  WriteLn('Byte ', Byte(p^));
  WriteLn('Int64+1 ', Int64(p^) + 1);
  WriteLn('second ', Int64((PByte(p) + 8)^ ));
  x := Int64(p^);
  WriteLn('assigned ', x);
  Int64(p^) := 6000000000;
  WriteLn('stored ', b[0]);
  if Int64(p^) > 5500000000 then WriteLn('compared high') else WriteLn('compared low');
  d := 1.5; p := @d;
  WriteLn('Double ', Double(p^):0:3);
  s := 2.25; p := @s;
  WriteLn('Single ', Single(p^):0:3);
  w := 7; p := @w;
  WriteLn('Word7 ', Word(p^));
  c := cBlue; p := @c;
  WriteLn('enum ', Ord(TColor(p^)));
  ShowConst(b[0]);
  ShowDouble(d);
  Bump(b[0]);
  WriteLn('bumped ', b[0]);
end.
