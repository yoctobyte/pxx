program test_rv32_pointer_math_through_int64_is_32_bit;
{ The RTL writes pointer arithmetic through Int64 -- `PByte(Int64(p) + k)^`,
  `PMachineWord(Int64(d) - 8)^` -- and riscv32 used to compute the whole pair
  sum and then keep its low word. An address, a field or index base, an index,
  and a value stored into at most 4 bytes now demand only the low word, and a
  `+`/`-` of a constant there is one addi (none for 0). Values only, never
  addresses, so x86-64 is the oracle. The constants sit on both sides of the
  12-bit immediate range, -2048 included on the minus side, whose negation
  does not fit. }
{$mode objfpc}
type
  PLongWord = ^LongWord;
  TRec = record a, b: LongInt; c: array[0..3] of Byte; end;
  PRec = ^TRec;
var
  big: array[0..4095] of Byte;
  words: array[0..15] of LongWord;
  recs: array[0..3] of TRec;
  p: Pointer;
  pc: PChar;
  s: AnsiString;
  i, n: LongInt;
  k: Int64;
  w: LongWord;
  sm: SmallInt;
  b: Byte;
  sum: Int64;

function ByteAt(base: Pointer; off: Int64): Byte;
begin
  Result := PByte(Int64(base) + off)^;
end;

function WordBefore(d: Pointer): LongWord;
begin
  Result := PLongWord(Int64(d) - 8)^;
end;

procedure Poke(base: Pointer; off: LongInt; v: Byte);
begin
  PByte(Int64(base) + off)^ := v;
end;

begin
  for i := 0 to High(big) do big[i] := Byte(i * 7 + i shr 8);
  for i := 0 to High(words) do words[i] := LongWord(i) * 1000003;
  p := @big[2048];
  { constant offsets around the addi range, both signs }
  writeln(ByteAt(p, 0), ' ', PByte(Int64(p) + 2047)^, ' ', PByte(Int64(p) - 2048)^, ' ',
    PByte(Int64(p) + 1)^, ' ', PByte(Int64(p) - 1)^);
  writeln(PByte(Int64(p) + 2046)^, ' ', PByte(Int64(p) - 2047)^);
  p := @big[100];
  writeln(PByte(Int64(p) + 2048)^, ' ', PByte(Int64(p) + 3000)^);
  p := @big[4000];
  writeln(PByte(Int64(p) - 2049)^, ' ', PByte(Int64(p) - 3999)^);
  { variable and computed Int64 offsets }
  p := @big[0];
  sum := 0;
  for i := 0 to 400 do
  begin
    k := Int64(i) * 5 + 3;          { k * 2 - i stays below 4096 }
    sum := sum + ByteAt(p, k) + PByte(Int64(p) + k * 2 - i)^;
  end;
  writeln(sum);
  { the word before a pointer, as the string header reads it }
  writeln(WordBefore(@words[5]), ' ', WordBefore(@words[15]));
  { stores through Int64-computed addresses }
  for i := 0 to 9 do Poke(@big[500], i * 3 - 4, Byte(200 + i));
  for i := 496 to 528 do write(big[i], ' ');
  writeln;
  { field and index bases from Int64 arithmetic }
  for i := 0 to High(recs) do
  begin
    recs[i].a := i * 11; recs[i].b := -i * 13;
    recs[i].c[0] := i; recs[i].c[3] := 100 + i;
  end;
  for i := 0 to High(recs) do
    writeln(PRec(Int64(@recs[0]) + Int64(i) * SizeOf(TRec))^.b, ' ',
      PRec(Int64(@recs[0]) + Int64(i) * SizeOf(TRec))^.c[3]);
  k := 7;
  writeln(words[k - 2], ' ', words[k * 2 + 1], ' ', big[k * 300 - 1]);
  { an Int64 expression stored into narrow integers keeps its low bits }
  k := $123456789A;
  w := k + 5;  n := k - 3;  sm := k * 3;  b := k + 300;
  writeln(w, ' ', n, ' ', sm, ' ', b);
  k := -5;
  w := k - 1;  n := k * 1000000;  sm := k - 40000;  b := k xor 255;
  writeln(w, ' ', n, ' ', sm, ' ', b);
  { PChar arithmetic }
  s := 'abcdefghijklmnopqrstuvwxyz';
  pc := PChar(s);
  writeln((pc + 3)^, (pc + 25)^, PChar(Int64(pc) + 10)^, (pc + 26 - 1)^);
  writeln('done');
end.
