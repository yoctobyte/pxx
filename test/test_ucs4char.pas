program test_ucs4char;
{ feature-nilpy-text-string-kind — tyUCS4Char, a Unicode CODE POINT.

  FPC PARITY, verified against FPC 3.2.2 directly:
    - the type exists and is spelled UCS4Char (FPC system unit:
      UCS4Char = type LongWord)
    - SizeOf is 4
    - Ord() yields the code point
  pxx matches on all three.

  PXX EXTENSION, deliberately laxer than FPC: converting one to a string
  yields its UTF-8 ENCODING. FPC REJECTS `'h' + c` outright, because its
  UCS4Char is an integer type. That divergence is intentional — pxx's dialect
  is lax by default and FPC-parity strictness lives behind --strict-* flags —
  and it is the whole reason tyUCS4Char is its own kind rather than an alias
  for tyUInt32: same storage, different conversion, exactly the argument the
  C99 _Bool kind already makes in defs.inc.

  The encodings are the point of the file. A code point crosses four width
  boundaries on its way to UTF-8, and getting one wrong is a silently corrupt
  byte rather than a crash. }

var failures: Integer;

procedure Check(ok: Boolean; const what: AnsiString);
begin
  if not ok then
  begin
    WriteLn('FAIL ', what);
    failures := failures + 1;
  end;
end;

var
  c: UCS4Char;
  s: AnsiString;

begin
  failures := 0;

  { --- FPC-parity surface --- }
  c := UCS4Char(233);
  Check(SizeOf(c) = 4, 'SizeOf is 4');
  Check(Ord(c) = 233, 'Ord yields the code point');
  c := UCS4Char(128512);
  Check(Ord(c) = 128512, 'holds a code point past the BMP');

  { --- UTF-8 conversion, one case per encoding width --- }
  c := UCS4Char(65);            { 'A' }
  s := '' + c;
  Check(Length(s) = 1, '1-byte encoding length');
  Check(s = 'A', '1-byte encoding value');

  c := UCS4Char($E9);           { 'e' acute }
  s := '' + c;
  Check(Length(s) = 2, '2-byte encoding length');
  Check((Ord(s[1]) = $C3) and (Ord(s[2]) = $A9), '2-byte encoding bytes');

  c := UCS4Char($65E5);         { CJK }
  s := '' + c;
  Check(Length(s) = 3, '3-byte encoding length');
  Check((Ord(s[1]) = $E6) and (Ord(s[2]) = $97) and (Ord(s[3]) = $A5),
        '3-byte encoding bytes');

  c := UCS4Char($1F600);        { emoji, 4-byte }
  s := '' + c;
  Check(Length(s) = 4, '4-byte encoding length');
  Check((Ord(s[1]) = $F0) and (Ord(s[2]) = $9F) and (Ord(s[3]) = $98) and
        (Ord(s[4]) = $80), '4-byte encoding bytes');

  { not code points: a lone surrogate and an out-of-range value encode to
    nothing, which is what FPC's conversion does with an unpaired surrogate }
  c := UCS4Char($D800);
  s := '' + c;
  Check(Length(s) = 0, 'lone surrogate encodes to nothing');
  c := UCS4Char($110000);
  s := '' + c;
  Check(Length(s) = 0, 'past U+10FFFF encodes to nothing');

  { --- the arithmetic trap this kind exists to avoid --- }
  { A ONE-character literal is spelled tyChar, so both sides are ordinals and
    `'h' + c` took the ARITHMETIC path before this kind existed: Chr(104+233),
    one wrong byte, silently. Both operands must become strings. }
  c := UCS4Char($E9);
  s := 'h' + c + 'llo';
  Check(Length(s) = 6, 'char + codepoint concatenates, not adds');
  Check(s[1] = 'h', 'char+codepoint keeps the leading char');
  Check((Ord(s[2]) = $C3) and (Ord(s[3]) = $A9), 'char+codepoint encodes the middle');

  { the same with a multi-character literal, which is tyString not tyChar }
  s := 'ab' + c;
  Check(Length(s) = 4, 'string + codepoint concatenates');

  if failures = 0 then WriteLn('ucs4char ok')
  else WriteLn('ucs4char FAILED ', failures);
end.
