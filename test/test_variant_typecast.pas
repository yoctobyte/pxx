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
  { -1, matching FPC: a boolean variant is OLE's VARIANT_TRUE. Adopted
    2026-08-13; scoped to the VARIANT conversion, so Ord(True) and
    Integer(someBooleanVar) are still 1. }
  writeln(Int64(v));       { -1 }
  writeln(Byte(v));        { 255 — the same -1 through the narrowing mask }
  writeln(Double(v):0:1);  { -1.0 }
  writeln(String(v));      { True — VariantToStr knows VT_BOOL as of the same
                             change; it used to answer '' }

  v := 'A';
  writeln(Char(v));        { A }

  v := 'text';
  writeln(String(v));      { text }
  writeln(AnsiString(v));  { text }

  { Char is the one row that deliberately does NOT track FPC: FPC renders the
    variant and takes character 1 ('65' -> '6'), which is inherited OLE history
    and contradicts its own numeric Byte/Word/Int64 conversions of the same
    value. The default dialect answers Chr(n); FPC's rule lives behind
    --strict-fpc and is covered by test_variant_typecast_strict.pas. }
  v := 65;
  writeln(Char(v));        { A  (FPC, and --strict-fpc: 6) }

  { the cast in EXPRESSION position, not just as the RHS of an assignment —
    the reinterpret used to leak the tag word into arithmetic }
  v := 20;
  writeln(Int64(v) + 1);       { 21 }
  writeln(Double(v) / 8:0:3);  { 2.500 }
end.
