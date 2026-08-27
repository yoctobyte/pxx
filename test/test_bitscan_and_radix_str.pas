program test_bitscan_and_radix_str;
{ FPC's System bit scan (Bsf/Bsr, one name per width) and the OctStr/BinStr
  siblings of HexStr. All absent — `undefined variable (BsfQWord)` — which is
  where FPC's own cutils.pas stopped (line 960, `ispowerof2`, and line 1092,
  `octal_quote`).

  The zero case is the point: Bsf/Bsr answer 255, a SENTINEL and not an index,
  so these cannot be a log2. Measured against FPC 3.2.2.
  bug-p-the-system-bit-scan-and-radix-string-surface-is-missing }
{$mode objfpc}

{ FPC's own ispowerof2, verbatim from cutils.pas:953 — the call site this came
  from, kept as a row so the surface is tested the way it is used. }
function IsPowerOf2(value: Int64; out power: LongInt): Boolean;
begin
  if (value <= 0) or (value and (value - 1) <> 0) then
  begin
    IsPowerOf2 := False;
    Exit;
  end;
  power := BsfQWord(value);
  IsPowerOf2 := True;
end;

var
  p: LongInt;
begin
  writeln('a ', BsfQWord(QWord(0)), '|', BsfQWord(QWord(1)), '|', BsfQWord(QWord(12)), '|', BsfQWord(QWord($8000000000000000)));
  writeln('b ', BsrQWord(QWord(0)), '|', BsrQWord(QWord(1)), '|', BsrQWord(QWord(12)), '|', BsrQWord(QWord($8000000000000000)));
  writeln('c ', BsfDWord(DWord(0)), '|', BsfDWord(DWord(12)), '|', BsrDWord(DWord(12)), '|', BsrDWord(DWord($80000000)));
  writeln('d ', BsfWord(Word(0)), '|', BsfWord(Word(12)), '|', BsrWord(Word(12)), '|', BsrWord(Word($8000)));
  writeln('e ', BsfByte(Byte(0)), '|', BsfByte(Byte(12)), '|', BsrByte(Byte(12)), '|', BsrByte(Byte($80)));
  writeln('f ', OctStr(8, 3), '|', OctStr(255, 4), '|', OctStr(255, 2), '|', OctStr(0, 1));
  writeln('g ', BinStr(5, 4), '|', BinStr(255, 4), '|', BinStr(0, 0));
  p := -1;
  writeln('h ', IsPowerOf2(64, p), '|', p);
  p := -1;
  writeln('i ', IsPowerOf2(63, p), '|', p);
  p := -1;
  writeln('j ', IsPowerOf2(0, p), '|', p);
  writeln('OK');
end.
