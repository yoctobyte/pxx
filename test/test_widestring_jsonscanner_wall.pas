{ THE ACCEPTANCE TEST for feature-unicodestring-model: the exact line from
  fcl-json's jsonscanner.pp that the campaign exists to make compile.

    S := Utf8Encode(WideString(WideChar(u1) + WideChar(u2)));

  pxx used to reject it, correctly: with one byte-shaped string model, `+` on two
  WideChars was integer ADDITION and `String(...)` of the sum had nothing sensible
  to mean.

  NO {$define PXX_WIDE_PAYLOAD} IN THIS FILE, and that is the point of the test
  rather than an oversight. Real-world FPC source will never carry a pxx define,
  so a wall that falls only under the define is a wall that is still standing for
  jsonscanner. It works in a DEFAULT build because the gate covers the type NAMES
  `widestring`/`unicodestring`, not the WideChar type: `WideChar + WideChar` is a
  genuine two-unit UTF-16 value whatever the define says, and assigning it to an
  AnsiString transcodes. The `WideString(...)` cast and Utf8Encode on top are
  both pass-throughs once that is true -- verified by dropping them and getting
  the same four bytes.

  Both halves of the escape path, because they fail differently:
    BMP pair   E9 + 20AC   -> two independent characters, 5 UTF-8 bytes
    surrogates D83D + DE00 -> ONE character U+1F600, 4 UTF-8 bytes

  The surrogate line is the one with teeth. Transcoding each unit on its own
  yields CESU-8 -- two unpaired surrogates, six bytes -- which is a plausible
  wrong answer that no length check on the BMP line would catch.

  ORACLE: FPC 3.2.2 with `uses cwstring`, which matches byte for byte. Stock FPC
  does NOT: its default widestring manager converts byte-for-byte and no source
  codepage setting changes that. See debugging-playbook.md.
  feature-unicodestring-model }
{$mode objfpc}{$H+}
program JsonScannerWall;
uses sysutils;
var u1, u2: Word; S: AnsiString; i: Integer;
begin
  u1 := $00E9; u2 := $20AC;
  S := Utf8Encode(WideString(WideChar(u1) + WideChar(u2)));
  Write('bmp  bytes=', Length(S), ':');
  for i := 1 to Length(S) do Write(' ', Ord(S[i]));
  WriteLn;
  u1 := $D83D; u2 := $DE00;
  S := Utf8Encode(WideString(WideChar(u1) + WideChar(u2)));
  Write('pair bytes=', Length(S), ':');
  for i := 1 to Length(S) do Write(' ', Ord(S[i]));
  WriteLn;
end.
