program test_widestring_surrogate_pair;
{ feature-unicodestring-model -- the wall the whole ticket exists for.

  `WideChar(u1) + WideChar(u2)` must be a two-unit STRING. jsonscanner builds a
  non-BMP code point exactly that way, from two \uXXXX escapes, and before the
  7c lowering there was no value in the language that could hold the pair: the
  two units went in as UTF-8 and came back out as one byte each.

  NOT AN FPC ORACLE, and exactly which lines diverge is worth stating rather
  than summarising. Measured against FPC 3.2.2, four of the six lines ARE its
  answer byte for byte: `units=2`, both `u` lines (55357 and 56832), and
  `doubled units=4`. The two UTF-8 lines are not. Converting a WideString to an
  AnsiString, FPC goes through DefaultSystemCodePage, which cannot represent
  U+1F600: it answers `utf8: 63 63` and `doubled utf8 bytes=4` -- four question
  marks. pxx's AnsiString is UTF-8 by construction, which is what
  PXXWideFromUtf8 reads and what PXXUtf8FromWide writes, so the round trip is
  lossless here and lossy there.

  So the UNICODE half of this test is FPC-verified and the ENCODING half is
  deliberately ours. Compat's own table settles which that is: a form pxx
  handles and FPC mishandles is a divergence to record, not a defect to fix. }
{$define PXX_WIDE_PAYLOAD}
var
  w: WideString;
  s: AnsiString;
  i: Integer;
begin
  { U+1F600 GRINNING FACE = surrogate pair D83D DE00. }
  w := WideChar($D83D) + WideChar($DE00);
  writeln('units=', Length(w));
  for i := 1 to Length(w) do
    writeln('  u', i, '=', Ord(w[i]));
  { ...and back out as UTF-8: F0 9F 98 80, the four bytes of one code point. }
  s := w;
  write('utf8:');
  for i := 1 to Length(s) do write(' ', Ord(s[i]));
  writeln;
  { A surrogate pair survives a concat without being split or re-decoded. }
  w := w + w;
  writeln('doubled units=', Length(w));
  s := w;
  writeln('doubled utf8 bytes=', Length(s));
end.
