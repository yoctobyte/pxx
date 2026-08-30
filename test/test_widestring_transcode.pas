{ The UTF-8 <-> UTF-16 transcoders and wide allocation in builtinheap.pas —
  the RUNTIME half of feature-unicodestring-model.

  This calls PXXWideFromUtf8 / PXXUtf8FromWide / PXXWideAlloc DIRECTLY rather
  than through `WideString`, because at the time it was written the type-system
  half did not exist yet: `var w: WideString` is still an alias for a byte
  string, so there is no source-level way to reach these. That is deliberate,
  not a shortcut — the runtime half was landed first and this is what keeps it
  from sitting unexercised until the frontend catches up. When `tyWideString`
  lands, this file stays as the unit test underneath the language-level ones.

  The emoji row is the whole point. U+1F600 is the case `jsonscanner.pp`'s
  \uXXXX path hits:

      S := Utf8Encode(WideString(WideChar(u1) + WideChar(u2)));

  with u1=$D83D, u2=$DE00 — a surrogate PAIR that must transcode back to the
  four UTF-8 bytes F0 9F 98 80, not to two replacement characters.

  Malformed input maps to U+FFFD in both directions rather than raising. These
  transcoders run under Utf8Decode/Utf8Encode on data that came from a file, so
  a bad byte in a JSON document must not become a crash in the parser.
  feature-unicodestring-model }
program test_widestring_transcode;
uses sysutils;
type
  MyU16 = ^Word;
  MyB   = ^Byte;

{ the managed-block header's length word, which is a BYTE count for both kinds }
function WBytes(w: Pointer): NativeInt;
begin
  if w = nil then WBytes := 0 else WBytes := PWord(Int64(w) - 8)^;
end;

procedure ShowWide(const tag: AnsiString; const src: AnsiString);
var w: Pointer; n, i: NativeInt; line: AnsiString;
begin
  w := PXXWideFromUtf8(PChar(src), Length(src));
  n := WBytes(w) div 2;
  line := ''; i := 0;
  while i < n do
  begin
    line := line + ' ' + IntToHex(MyU16(Int64(w) + i * 2)^, 4);
    i := i + 1;
  end;
  WriteLn(tag, ' units=', n, line);
end;

procedure RoundTrip(const tag: AnsiString; const src: AnsiString);
var w, b: Pointer; n, i: NativeInt; line: AnsiString;
begin
  w := PXXWideFromUtf8(PChar(src), Length(src));
  b := PXXUtf8FromWide(w, WBytes(w));
  n := WBytes(b);
  line := ''; i := 0;
  while i < n do
  begin
    line := line + ' ' + IntToHex(MyB(Int64(b) + i)^, 2);
    i := i + 1;
  end;
  WriteLn(tag, ' bytes=', n, line, ' roundtrips=', (n = Length(src)));
end;

procedure FromUnits(const tag: AnsiString; u1, u2: Word);
var w, b: Pointer; n, i: NativeInt; line: AnsiString;
begin
  w := PXXWideAlloc(2);
  MyU16(Int64(w))^ := u1;
  MyU16(Int64(w) + 2)^ := u2;
  b := PXXUtf8FromWide(w, 4);
  n := WBytes(b);
  line := ''; i := 0;
  while i < n do
  begin
    line := line + ' ' + IntToHex(MyB(Int64(b) + i)^, 2);
    i := i + 1;
  end;
  WriteLn(tag, ' bytes=', n, line);
end;

begin
  { UTF-8 in, UTF-16 out: one unit below the BMP ceiling, a pair above it }
  ShowWide('ascii     ', 'hi');
  ShowWide('eacute    ', #$C3#$A9);          { U+00E9 }
  ShowWide('nihon     ', #$E6#$97#$A5);      { U+65E5 }
  ShowWide('emoji     ', #$F0#$9F#$98#$80);  { U+1F600 -> D83D DE00 }

  { malformed UTF-8 -> U+FFFD, and the byte AFTER the bad one survives:
    a truncated lead must not swallow the next character }
  ShowWide('truncated ', #$E6#$97);
  ShowWide('stray-cont', #$97#$41);
  ShowWide('bad-lead  ', #$FE#$41);
  WriteLn;

  { and back again, byte for byte }
  RoundTrip('ascii     ', 'hi');
  RoundTrip('eacute    ', #$C3#$A9);
  RoundTrip('nihon     ', #$E6#$97#$A5);
  RoundTrip('emoji     ', #$F0#$9F#$98#$80);
  WriteLn;

  { UTF-16 in, UTF-8 out, built from raw code units the way jsonscanner does }
  FromUnits('pair      ', $D83D, $DE00);     { the ticket's wall }
  FromUnits('lone-high ', $D83D, $0041);     { unpaired -> FFFD, 'A' survives }
  FromUnits('lone-low  ', $DE00, $0041);
end.
