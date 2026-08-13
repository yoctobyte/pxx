program test_variant_typecast;
{ A typecast of a Variant is the CONVERSION, not a reinterpret of the 16-byte
  variant record. Every spelling: the keyword-token casts (Integer/Byte/
  LongWord/Char/Boolean/Single/Double/String) and the identifier-named ones
  (Int64/QWord/Cardinal/Word/NativeInt/AnsiString). All values diffed against
  an FPC build of this file.
  bug-p-a-typecast-of-a-variant-reinterprets-it-instead-of-converting }
uses variants;
var v: Variant;
begin
  v := 9;
  writeln(Int64(v));       { 9 }
  writeln(Integer(v));     { 9 }
  writeln(Byte(v));        { 9 }
  writeln(Word(v));        { 9 }
  writeln(Cardinal(v));    { 9 }
  writeln(LongWord(v));    { 9 }
  writeln(QWord(v));       { 9 }
  { NativeInt(v) is deliberately NOT here: FPC REFUSES it ("Illegal type
    conversion"), and pxx's dialect is lax by default — it converts. Nothing to
    diff against, so the oracle file leaves it out. }
  writeln(Double(v):0:2);  { 9.00 }
  writeln(Single(v):0:2);  { 9.00 }
  writeln(Boolean(v));     { TRUE }

  v := 2.5;
  writeln(Double(v):0:2);  { 2.50 }
  writeln(Single(v):0:2);  { 2.50 }
  writeln(Int64(v));       { 3 — variant float->int rounds, as `i := v` does }
  writeln(Integer(v));     { 3 }

  v := True;
  writeln(Boolean(v));     { TRUE }
  { 1, where FPC says -1. A DIVERGENCE IN THE CONVERSION ITSELF, not in the
    cast: `i := v` answers 1 here too. Same for Char(65) below, which FPC
    renders via the string ('65' -> '6') and we answer 'A'. Asserted as-is so
    this file keeps proving the property it is about — the cast agrees with the
    assignment — and the conversion's own FPC parity is
    bug-p-variant-to-int-and-char-conversion-diverges-from-fpc. }
  writeln(Int64(v));       { 1  (FPC: -1) }

  v := 'A';
  writeln(Char(v));        { A }

  v := 'text';
  writeln(String(v));      { text }
  writeln(AnsiString(v));  { text }

  v := 65;
  writeln(Char(v));        { A  (FPC: 6 — see the note above) }

  { the cast in EXPRESSION position, not just as the RHS of an assignment —
    the reinterpret used to leak the tag word into arithmetic }
  v := 20;
  writeln(Int64(v) + 1);       { 21 }
  writeln(Double(v) / 8:0:3);  { 2.500 }
end.
