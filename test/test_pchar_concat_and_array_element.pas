program test_pchar_concat_and_array_element;
{ PChar -> managed string in the two contexts that had NO conversion at all:
  a `+` operand, and an element of an array of PChar.

  Both were silent wrong VALUES, not errors, and both are FPC-verified line by
  line (fpc 3.2.2 on this same source prints exactly what is asserted below).

  The `+` half went wrong in two unrelated ways depending on the OTHER operand:
    'xy' + p   typed as a string concat, but the concat read the POINTER as
               string data and appended one garbage byte
    'x'  + p   a one-char literal is an ORDINAL, so `ordinal + pointer` claimed
               it and the whole expression became pointer arithmetic — the
               pointer was offset by 120 and the result was ''
  while `p + 1` must STAY pointer arithmetic, which is the line this test
  draws: the other operand being a char/string means concat, an integer means
  arithmetic. That is FPC's rule too, measured rather than assumed.

  The array half was one unrecognised SHAPE breaking every context at once:
  cast, assign, concat and compare all produced '', Length answered 0, and
  WriteLn printed the pointer as a number.

  refactor-centralize-managed-string-pchar-conversion }

var Buf: array[0..7] of Char;

function GetP: PChar;
begin
  GetP := @Buf[0];
end;

procedure Show(const t: AnsiString);
begin
  WriteLn(t);
end;

var
  s: AnsiString;
  c: Char;
  i: Integer;
  fixed: array[0..1] of PChar;
  dyn: array of PChar;
begin
  Buf[0] := 'a'; Buf[1] := 'b'; Buf[2] := 'c'; Buf[3] := 'd'; Buf[4] := 'e';
  Buf[5] := #0;

  { ---- concat: the PChar is a string operand, whichever side it is on ---- }
  s := 'xy' + GetP;    WriteLn(s);              { xyabcde }
  s := 'x' + GetP;     WriteLn(s);              { xabcde  — one-char literal }
  s := GetP + 'tail';  WriteLn(s);              { abcdetail }
  c := 'Q';
  s := c + GetP;       WriteLn(s);              { Qabcde  — char VARIABLE }
  s := GetP + c;       WriteLn(s);              { abcdeQ }
  s := 'z';
  s := s + GetP;       WriteLn(s);              { zabcde  — AnsiString var }

  { ---- ...but an INTEGER operand is still pointer arithmetic ---- }
  i := 1;
  s := AnsiString(GetP + i);  WriteLn(s);       { bcde }
  s := AnsiString(GetP + 2);  WriteLn(s);       { cde }

  { ---- an element of an array of PChar, in every context ---- }
  fixed[0] := @Buf[0];
  fixed[1] := @Buf[2];
  s := AnsiString(fixed[0]);  WriteLn(s);       { abcde }
  s := fixed[1];              WriteLn(s);       { cde }
  s := 'p' + fixed[0];        WriteLn(s);       { pabcde }
  WriteLn(Length(AnsiString(fixed[0])));        { 5 }
  if AnsiString(fixed[0]) = 'abcde' then WriteLn('eq') else WriteLn('ne');
  WriteLn(fixed[0]);                            { abcde — not the pointer }
  Show(fixed[1]);                               { cde   — const AnsiString param }

  SetLength(dyn, 2);
  dyn[0] := @Buf[1];
  dyn[1] := @Buf[4];
  s := AnsiString(dyn[0]);  WriteLn(s);         { bcde }
  s := 'q' + dyn[1];        WriteLn(s);         { qe }
  Show(dyn[0]);                                 { bcde }
end.
