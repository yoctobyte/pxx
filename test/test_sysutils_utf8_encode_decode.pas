program test_sysutils_utf8_encode_decode;
{ sysutils UTF8Decode/UTF8Encode are REAL now, and the bodies did not change to
  make them real -- the whole conversion is in the two signatures. `Result := s`
  across a width boundary lowers to the runtime transcoders (7c), so there is
  one transcoder in this compiler and it lives in the runtime, not in the RTL.

  Both directions are checked with a NON-ASCII code point on purpose. On ASCII
  a UTF-8 byte count and a UTF-16 unit count are the same number, so an
  identity would pass an ASCII test -- which is exactly what these two were
  before this change, and exactly what an ASCII test would not have caught.

  The .expected is an ORACLE: FPC 3.2.2 produces it byte for byte. The literal
  is built from explicit #$C3 #$A9 byte escapes rather than a source-encoded
  `é`, so both compilers read the same five bytes and the comparison is about
  the CONVERSION rather than about either one's source codepage. }
{$define PXX_WIDE_PAYLOAD}
uses sysutils;
var
  s, back: AnsiString;
  w: UnicodeString;
  i: Integer;
begin
  s := 'caf' + #$C3 + #$A9;          { 'café' as 5 UTF-8 bytes }
  writeln('utf8 bytes=', Length(s));
  w := UTF8Decode(s);
  writeln('decoded units=', Length(w));
  write('units:');
  for i := 1 to Length(w) do write(' ', Ord(w[i]));
  writeln;
  back := UTF8Encode(w);
  writeln('re-encoded bytes=', Length(back), ' out=', back);
  writeln('round trip intact=', back = s);
  { The identity that used to be here would have made every line above agree
    with itself while disagreeing with FPC. This one cannot: an ASCII string
    has equal counts, so it pins that the conversion is a no-op where it should
    be rather than everywhere. }
  s := 'plain';
  w := UTF8Decode(s);
  writeln('ascii units=', Length(w), ' bytes=', Length(UTF8Encode(w)));
end.
