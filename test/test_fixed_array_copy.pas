program test_fixed_array_copy;
{ Regression: whole static-array assignment `b := a` must copy all elements
  by value, for element widths Byte / Integer / Int64, with no aliasing.
  bug-fixed-array-assignment-no-copy. }
type
  TB = array[0..3] of Byte;
  TI = array[0..2] of Integer;
  TQ = array[0..1] of Int64;
var
  ab, bb: TB;
  ai, bi: TI;
  aq, bq: TQ;
  i: Integer;
begin
  for i := 0 to 3 do ab[i] := i + 1;   { 1 2 3 4 }
  bb := ab;
  ab[0] := 99;                         { must not disturb bb }
  writeln(bb[0], ' ', bb[3]);          { 1 4 }

  ai[0] := 10; ai[1] := 20; ai[2] := 30;
  bi := ai;
  ai[1] := 999;
  writeln(bi[0], ' ', bi[1], ' ', bi[2]);   { 10 20 30 }

  aq[0] := Int64(5000000000); aq[1] := Int64(7000000000);
  bq := aq;
  aq[0] := 1;
  writeln(bq[0], ' ', bq[1]);          { 5000000000 7000000000 }
  writeln('OK');
end.
