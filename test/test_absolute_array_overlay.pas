program test_absolute_array_overlay;
{ `absolute` over a FIXED array: b: array[0..3] of Byte absolute i overlays i's
  storage. This used to be excluded from the overlay silently — the array kept
  its own slot, so it read 0 and swallowed writes. Every row is checked against
  fpc 3.2.2 -Mobjfpc -O1. bug-a-an-absolute-array-overlay-is-silently-ignored }
type TR = record a: Word; b: Word; end;
var g: Int64;
    gb: array[0..7] of Byte absolute g;
    gr: TR absolute g;
    src: array[0..3] of Word;
    view: array[0..7] of Byte absolute src;
    k: Integer;

procedure Locals;
var i: Integer;
    lb: array[0..3] of Byte absolute i;
    lw: array[0..1] of Word absolute i;
begin
  i := $04030201;
  WriteLn('local ', lb[0], ' ', lb[1], ' ', lb[2], ' ', lb[3]);
  WriteLn('words ', lw[0], ' ', lw[1]);
  lb[3] := 255;
  WriteLn('back ', i);
end;

begin
  g := $0807060504030201;
  Write('glob');
  for k := 0 to 7 do Write(' ', gb[k]);
  WriteLn;
  { a record overlay was always allowed — it is here so the array row is not
    the only witness that the overlay itself is right }
  WriteLn('rec ', gr.a, ' ', gr.b);
  gb[0] := 99;
  WriteLn('write ', g);
  src[0] := $0201; src[1] := $0403; src[2] := $0605; src[3] := $0807;
  Write('view');
  for k := 0 to 7 do Write(' ', view[k]);
  WriteLn;
  Locals;
end.
