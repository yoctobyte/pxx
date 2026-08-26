{ The const evaluator carries an Int64, so `High(QWord)` -- 2^64-1 -- used to be
  REFUSED outright rather than folded ("undefined variable (QWord)"), and the
  refusal was deliberate: the bit pattern fits, but reading it back as -1 would
  make `High(QWord) div 2` answer 0 instead of 2^63-1. An honest refusal beat a
  silent wrong value.

  What was missing was not a table row but the TYPE travelling with the value.
  It now rides the CEOrdTk channel from TryConstHighLowValue through every fold
  level, and only the seven operations where two's-complement actually differs
  branch on it: div, mod, shr, and the four ORDERED relationals. *, +, -, and,
  or, xor, shl, = and <> are bit-identical and are untouched, so every signed
  constant in the tree folds byte-for-byte as before -- the last four rows here
  are the control.

  An 8-byte unsigned CAST is the other way in (`qword(high(int64))`, which is
  how FPC's own constexp.pas:329 spells it), and a named const keeps its kind
  so `const A = High(QWord); B = A > 5` is TRUE rather than FALSE.

  Every row is `fpc -O- -Mobjfpc` 3.2.2's.
  feature-p-const-evaluator-carries-unsigned-64-bit }
program test_const_unsigned_64bit_fold;

const
  HQ   = High(QWord);
  HN   = High(NativeUInt);
  LQ   = Low(QWord);
  D2   = High(QWord) div 2;
  M3   = High(QWord) mod 3;
  S1   = High(QWord) shr 1;
  S63  = High(QWord) shr 63;
  GT   = High(QWord) > 5;
  LT   = High(QWord) < 5;
  SUB  = High(QWord) - 1;
  SGT  = SUB > 5;                 { a named unsigned const, read back }
  CAST = QWord(High(Int64));      { the cast route in }
  CGT  = QWord(High(Int64)) > 5;
  NOTQ = not QWord(0);
  { the signed control: none of these may move }
  SD   = High(Int64) div 2;
  SS   = High(Int64) shr 1;
  SN   = -7 div 2;
  SM   = -7 mod 2;
  SLT  = -1 < 5;

begin
  writeln(High(QWord));
  writeln(High(UInt64));
  writeln(High(NativeUInt));
  writeln(High(PtrUInt));
  writeln(Low(QWord));
  writeln(HQ);   writeln(HN);   writeln(LQ);
  writeln(D2);   writeln(M3);   writeln(S1);  writeln(S63);
  writeln(GT);   writeln(LT);
  writeln(SUB);  writeln(SGT);
  writeln(CAST); writeln(CGT);  writeln(NOTQ);
  writeln(SD, ' ', SS, ' ', SN, ' ', SM, ' ', SLT);
end.
