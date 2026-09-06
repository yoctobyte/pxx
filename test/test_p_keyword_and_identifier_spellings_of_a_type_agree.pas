program test_p_keyword_and_identifier_spellings_of_a_type_agree;
{ Ten type names lex as KEYWORD tokens (boolean, byte, char, double, extended,
  integer, longword, real, single, string) and get their own cast arms in
  ParseFactorCore. Every other type name is an identifier and goes through the
  shared builtin door ~5000 lines later. Where one type has BOTH spellings, the
  two arms must produce the same value -- they are two mechanisms for one
  concept, and this file's history is one of them being taught while the other
  stayed broken:

    - `AnsiChar(258)` narrowed and `Char(258)` did not.
    - `AnsiString(p)` accepted a PChar and `String(p)` was rejected.
    - `AnsiString(r)[2]` parsed and `t(r)[2]` parsed and `String(r)[2]` did not.

  Each was fixed on the door that was reported. This test varies the SELECTOR --
  which spelling is written -- and holds the value fixed, so it fails whichever
  direction the next divergence faces.

  A pair disagreeing here is self-inconsistent and wrong without an oracle;
  every expected value is nonetheless FPC 3.2.2's, from running this program
  under `fpc -Mobjfpc -Sh`.

  PROBE VALUES EXCEED THE TARGET WIDTH ON PURPOSE (258 into a byte, 2^32+5 into
  a longword). A value that fits both widths cannot tell a truncating door from
  a non-truncating one, and 65 -> 'A' is the row that would pass either way --
  it is here as the readable control, not as the discriminator.

  SOME ROWS ARE NOT PAIRED AND THAT IS DELIBERATE: `Boolean`, `Real` and
  `Single` have no identifier-spelled synonym in the shared table, so no
  comparison exists to make. Their absence is a gap in the population, not an
  omission.

  THE TWO DEFECTS THIS FILE WAS WRITTEN FOR FAIL AT DIFFERENT STAGES, and the
  loud one hides the quiet one. Against the pinned (pre-fix) compiler the
  indexed row at `idx-kw` is a COMPILE refusal -- `expected ')' before '['` --
  so the run never happens and the char->string rows below are never reached.
  Cut to the char rows alone, that same compiler prints `s-kw A 1` and then
  SEGFAULTS on `s-ansi`. Both were verified separately before this test was
  written; a future reader seeing only the parse error should not conclude the
  conversion rows are fine. }
{$mode objfpc}{$H+}
var
  n: Int64; d: Double; c: Char; s: string; p: PChar; r: string;
begin
  { --- ordinal pairs: the keyword arm vs the shared builtin door --- }
  n := 258;
  WriteLn('byte-kw     ', Byte(n));        { 2 }
  WriteLn('byte-id     ', UInt8(n));       { 2 }
  WriteLn('char-kw     ', Ord(Char(n)));   { 2 — the AnsiChar(258) divergence }
  WriteLn('char-id     ', Ord(AnsiChar(n)));

  n := 4294967296 + 5;
  WriteLn('lword-kw    ', LongWord(n));    { 5 }
  WriteLn('lword-id    ', Cardinal(n));
  WriteLn('lword-id2   ', UInt32(n));
  WriteLn('lword-id3   ', DWord(n));

  d := 3.75;
  WriteLn('double-kw   ', Double(d):0:2);  { 3.75 }
  WriteLn('double-id   ', ValReal(d):0:2);

  { --- a CHAR cast to a string type is a CONVERSION, not a reinterpret ---
    The keyword spelling materialised a 1-char string; every identifier
    spelling reinterpreted the character AS a string and SEGFAULTED. }
  c := 'A';
  r := String(c);        WriteLn('s-kw        ', r, ' ', Length(r));
  r := AnsiString(c);    WriteLn('s-ansi      ', r, ' ', Length(r));
  r := UnicodeString(c); WriteLn('s-unicode   ', r, ' ', Length(r));
  r := WideString(c);    WriteLn('s-wide      ', r, ' ', Length(r));
  r := UTF8String(c);    WriteLn('s-utf8      ', r, ' ', Length(r));
  r := RawByteString(c); WriteLn('s-rawbyte   ', r, ' ', Length(r));
  WriteLn('s-concat    ', AnsiString(c) + 'BC');

  { --- the INDEXED string cast, both spellings ---
    `AnsiString(s)[2]` walked the selector and `String(s)[2]` reported
    `expected ')' before '['`: the walk sat on one branch of a four-branch arm
    and served the pointer operand only. }
  s := 'hello';
  p := PChar(s);
  WriteLn('idx-kw      ', String(s)[2]);       { e }
  WriteLn('idx-id      ', AnsiString(s)[2]);   { e }
  WriteLn('idx-kw-p    ', String(p)[2]);       { e — the branch that already worked }
  WriteLn('idx-id-p    ', AnsiString(p)[2]);

  { --- the passthrough and pointer operands, unchanged by any of the above --- }
  WriteLn('pass-kw     ', String(s));
  WriteLn('pass-id     ', AnsiString(s));
  WriteLn('pchar-kw    ', String(p));
  WriteLn('pchar-id    ', AnsiString(p));
end.
