{ A record TYPECAST's array field, read and written, at every index.

  `TLongWordRec(l).b[0]` is FPC's own idiom — cutils.pas:331's
  `reverse_longword` is nothing but four lines of it — and pxx got it wrong in
  two different ways at once:

    - as an ASSIGNMENT TARGET it did not parse. The cast-as-lvalue statement arm
      walked the postfix chain with its own `while CurTok.Kind in [tkCaret,
      tkDot]` loop, which knew `^` and `.field` and not `[`, so it stopped at the
      subscript and demanded `:=`. The RIGHT-hand side of that very same FPC line
      parsed;
    - as an RVALUE it parsed and answered the WRONG VALUE. The expression-side
      cast walker kept plain fields on a hand-rolled builder and then let its own
      `[` arm hard-code the indexed value as `tyRecord` — so a Byte element was
      read at the record's width: FPC prints 4 where pxx printed
      18486690310128388. `x.b[0]` on a variable and `p^.b[0]` through a pointer
      were both right the whole time, because both go through
      ParseClassRecordSelectors.

  Both are now that one shared node-keyed selector walker. Rows:

    a  read every index of the cast's array field
    b  the same values through a VARIABLE and a POINTER — the controls that
       always worked, so a regression cannot hide by breaking all three together
    c  write every index through the cast, then read the underlying LongWord:
       the bytes must land where FPC puts them
    d  a non-array field of a cast, and a nested record field, still work
    e  FPC's `reverse_longword` verbatim, including the cast of the RESULT
       VARIABLE as the assignment target

  Oracled against FPC 3.2.2 -Mobjfpc.
  bug-p-a-record-cast-as-an-assignment-target-cannot-be-indexed }
program test_record_cast_indexed_field;

type
  TLongWordRec = packed record
    b: array[0..3] of Byte;
  end;
  TPair = packed record
    lo: Word;
    hi: Word;
  end;

function ReverseByte(b: Byte): Byte;
const
  Rev4: array[0..15] of Byte = (0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15);
begin
  ReverseByte := (Rev4[b and 15] shl 4) or Rev4[b shr 4];
end;

function ReverseLongWord(l: LongWord): LongWord;
begin
  TLongWordRec(ReverseLongWord).b[0] := ReverseByte(TLongWordRec(l).b[3]);
  TLongWordRec(ReverseLongWord).b[1] := ReverseByte(TLongWordRec(l).b[2]);
  TLongWordRec(ReverseLongWord).b[2] := ReverseByte(TLongWordRec(l).b[1]);
  TLongWordRec(ReverseLongWord).b[3] := ReverseByte(TLongWordRec(l).b[0]);
end;

var
  l, r, w: LongWord;
  v: TLongWordRec;
  p: ^TLongWordRec;
  i: Integer;

begin
  l := $01020304;

  Write('a ');
  for i := 0 to 3 do Write(TLongWordRec(l).b[i], ' ');
  WriteLn;

  v.b[0] := 4; v.b[1] := 3; v.b[2] := 2; v.b[3] := 1;
  p := @l;
  Write('b ');
  for i := 0 to 3 do Write(v.b[i], ' ');
  for i := 0 to 3 do Write(p^.b[i], ' ');
  WriteLn;

  r := 0;
  for i := 0 to 3 do TLongWordRec(r).b[i] := (i + 1) * 16;
  Write('c ');
  for i := 0 to 3 do Write(TLongWordRec(r).b[i], ' ');
  WriteLn('| ', r);

  w := 0;
  TPair(w).lo := 258;
  TPair(w).hi := 772;
  WriteLn('d ', TPair(w).lo, '|', TPair(w).hi, '|', w);

  WriteLn('e ', ReverseLongWord($01020304), '|', ReverseLongWord($FF000000),
          '|', ReverseLongWord(1));
end.
