{ charset: the registry, both lookup doors, the reverse-map build and the binary
  format.

  EVERY EXPECTED VALUE BELOW WAS READ OFF FPC 3.2.2, NOT WRITTEN FROM THE
  SPECIFICATION. The same source compiles under both compilers against their own
  charset units and the 86-line output diffs byte for byte; the numbers here are
  that column. The harness was made to redden first, by flipping
  RemoveDuplicates' tie-break -- which moves rev[1] and three getascii rows --
  before the green was believed.

  THE LOAD-BEARING ROWS ARE THE ONES A STUB WOULD PASS. "getmap returns nil for
  an unknown name" is true of a getmap that always returns nil, so it sits
  beside rows requiring a registered map to be FOUND, by both keys, twice each
  (the second hit comes from the cache, which is a different code path and can
  answer staleley). "reversemaplength = 7" is true of several wrong builds, so
  the reverse table is asserted ENTRY BY ENTRY, including the duplicate whose
  tie-break is the one thing an "equivalent" rewrite gets wrong.

  THE MAPPING FILE GIVES EVERY LINE A TRAILING COMMENT ON PURPOSE. fpc's loader
  scans hex digits past the end of the line, so a line ending in hex reads the
  PREVIOUS line's leftover bytes; a trailing comment terminates the scan inside
  the line. We bound our scans and do not need this -- it is here so that the
  numbers below remain fpc's, which is the only reason to trust them. The
  divergence itself is asserted at the end, where we answer and fpc does not. }
program lib_charset;

uses charset;

var ok, total: Integer;

procedure Chk(cond: Boolean; const what: AnsiString);
begin
  Inc(total);
  if cond then Inc(ok) else WriteLn('FAIL: ', what);
end;

procedure ChkI(got, want: LongInt; const what: AnsiString);
begin
  Inc(total);
  if got = want then Inc(ok)
  else WriteLn('FAIL: ', what, ' -- got ', got, ', fpc says ', want);
end;

var
  m, mb: punicodemap;
  t: Text;
  dir, path: AnsiString;
  r: preversecharmapping;
  s: ShortString;
  i, n: LongInt;
  w: array[0..15] of Word;
  src: array[0..7] of AnsiChar;
  buf: PByte;
  hdr: TSerializedMapHeader;
  totalBytes: LongInt;

begin
  ok := 0; total := 0;
  if ParamCount < 1 then
  begin
    WriteLn('usage: lib_charset <scratch-dir>');
    Halt(1);
  end;
  dir := ParamStr(1);
  path := dir + '/lib_charset_mini.txt';

  Assign(t, path);
  Rewrite(t);
  WriteLn(t, '# a comment line, skipped');
  WriteLn(t, 'not a mapping line either');
  WriteLn(t, '0x00', #9, '0x0000', #9, '#NULL');
  WriteLn(t, '0x41', #9, '0x0041', #9, '#LATIN CAPITAL LETTER A');
  WriteLn(t, '0x42', #9, '0x0042', #9, '#LATIN CAPITAL LETTER B');
  WriteLn(t, '0x80', #9, '0x20AC', #9, '#EURO SIGN');
  WriteLn(t, '0x81', #9, '#UNDEFINED');
  WriteLn(t, '0x8E', #9, '#DBCS LEAD BYTE');
  WriteLn(t, '0xFF', #9, '0x00FF', #9, '#Y WITH DIAERESIS');
  WriteLn(t, '0x8E41', #9, '0x4E00', #9, '#CJK ONE');
  WriteLn(t, '0x8E42', #9, '0x4E01', #9, '#CJK TWO');
  { A second position encoding a character already mapped, so the duplicate
    branch runs and its tie-break is observable. }
  WriteLn(t, '0x8E43', #9, '0x0041', #9, '#DUPLICATE OF A');
  Close(t);

  { ---- the text loader -------------------------------------------------- }
  m := loadunicodemapping('MINI', path, 1234);
  Chk(m <> nil, 'the mapping file loaded at all');
  if m = nil then
  begin
    WriteLn('total ok ', ok, ' / ', total);
    Halt(1);
  end;
  ChkI(m^.cp, 1234, 'the codepage number is carried');
  Chk(m^.cpname = 'MINI', 'the codepage name is carried');
  { 0x8E43 is the highest position mentioned, so lastchar is 36419 -- NOT the
    number of lines and not 255. }
  ChkI(m^.lastchar, 36419, 'lastchar is the highest POSITION, past the 256-entry initial table');
  ChkI(Ord(m^.internalmap), 0, 'a file-loaded map is not an internal one');

  { The flag classification, which is what decides the reverse map's contents. }
  ChkI(Ord(m^.map[$41].flag), 0, 'an ordinary position is umf_noinfo');
  ChkI(Ord(m^.map[$81].flag), 3, 'a position with no unicode column is umf_unused');
  ChkI(Ord(m^.map[$8E].flag), 1, 'a #DBCS LEAD BYTE position is umf_leadbyte');
  ChkI(Ord(m^.map[$99].flag), 3, 'a position the file never mentions is umf_unused');
  ChkI(m^.map[$81].unicode, 65535, 'an undefined position holds $FFFF');
  ChkI(m^.map[$99].unicode, 0, 'a never-mentioned position holds 0');
  { THE ROW THAT CATCHES THE UNBOUNDED SCAN: fpc reads the previous line's
    residue here and registers U+00AD instead. }
  ChkI(m^.map[$8E41].unicode, 19968, 'a two-byte position holds its own character, not the previous line''s residue');
  ChkI(m^.map[$8E42].unicode, 19969, 'and so does the next one');

  { ---- the reverse map, entry by entry ---------------------------------- }
  ChkI(m^.reversemaplength, 7, 'the reverse map has one entry per DISTINCT character');
  r := m^.reversemap;
  if m^.reversemaplength = 7 then
  begin
    ChkI(r[0].unicode, 0, 'rev[0] is U+0000');   ChkI(r[0].char1, 0, 'rev[0] char1');
    ChkI(r[1].unicode, 65, 'rev[1] is U+0041');
    { THE TIE-BREAK. U+0041 is encoded at 0x41 and again at 0x8E43; the SMALLEST
      pair wins, so this is 65/0 and not 142/67. A dedup that keeps whichever
      duplicate the (unstable) sort happened to leave first passes every other
      row in this file and fails here. }
    ChkI(r[1].char1, 65, 'rev[1] keeps the SMALLEST encoding of a duplicated character');
    ChkI(r[1].char2, 0, 'rev[1] char2 -- single byte, so zero');
    ChkI(r[2].unicode, 66, 'rev[2] is U+0042');
    ChkI(r[3].unicode, 255, 'rev[3] is U+00FF');  ChkI(r[3].char1, 255, 'rev[3] char1');
    ChkI(r[4].unicode, 8364, 'rev[4] is the euro sign'); ChkI(r[4].char1, 128, 'rev[4] char1');
    ChkI(r[5].unicode, 19968, 'rev[5] is U+4E00');
    ChkI(r[5].char1, 142, 'rev[5] char1 is the lead byte');
    ChkI(r[5].char2, 65, 'rev[5] char2 is the trail byte');
    ChkI(r[6].unicode, 19969, 'rev[6] is U+4E01');
    { Sorted ascending, which is what makes the binary search in find() valid. }
    Chk((r[0].unicode < r[1].unicode) and (r[1].unicode < r[2].unicode) and
        (r[2].unicode < r[3].unicode) and (r[3].unicode < r[4].unicode) and
        (r[4].unicode < r[5].unicode) and (r[5].unicode < r[6].unicode),
        'the reverse map is sorted ascending, as find() requires');
  end
  else
  begin
    { Branch on the precondition: comparing entries of a table of the wrong
      length would read past it. }
    for i := 1 to 17 do Chk(False, '(reverse-map row not run -- wrong length)');
  end;

  { ---- the registry and both lookup doors ------------------------------- }
  Chk(not mappingavailable('MINI'), 'an unregistered map is NOT available -- registration is what publishes it');
  registermapping(m);
  Chk(mappingavailable('MINI'), 'by name, after registering');
  Chk(mappingavailable('MINI'), 'by name again -- this one comes from the cache');
  Chk(mappingavailable(1234), 'by codepage');
  Chk(mappingavailable(1234), 'by codepage again -- the other cache');
  Chk(not mappingavailable('NOPE'), 'an unknown name is not available');
  Chk(not mappingavailable(9999), 'an unknown codepage is not available');
  Chk(getmap('MINI') = m, 'getmap by name returns the very object registered');
  Chk(getmap(1234) = m, 'getmap by codepage returns the very object registered');
  Chk(getmap('NOPE') = nil, 'getmap of an unknown name is nil');

  { ---- single-character conversion -------------------------------------- }
  ChkI(getunicode('A', m), 65, 'getunicode of an ordinary character');
  ChkI(getunicode(#128, m), 8364, 'getunicode of a high character');
  ChkI(getunicode(#129, m), 65535, 'getunicode of an undefined position');
  ChkI(getunicode(#153, m), 0, 'getunicode of a never-mentioned position');

  { ---- the string form, including a lead byte and a truncated one ------- }
  src[0] := 'A'; src[1] := 'B';
  src[2] := AnsiChar($8E); src[3] := AnsiChar($41);
  src[4] := AnsiChar($FF);
  src[5] := AnsiChar($8E);   { a lead byte at the very END, with no trailer }
  ChkI(getunicode(@src[0], 6, m, nil), 5,
       'the length pass collapses the lead-byte PAIR: 6 bytes are 5 characters');
  for i := 0 to 15 do w[i] := $DEAD;
  n := getunicode(@src[0], 6, m, @w[0]);
  ChkI(n, 5, 'the convert pass agrees with the length pass');
  if n = 5 then
  begin
    ChkI(w[0], 65, 'converted[0]');
    ChkI(w[1], 66, 'converted[1]');
    ChkI(w[2], 19968, 'converted[2] -- the two-byte character');
    ChkI(w[3], 255, 'converted[3]');
    ChkI(w[4], 63, 'converted[4] -- a lead byte with no trailer becomes ?');
    { A conversion that wrote one word too many would still pass every row
      above. }
    ChkI(w[5], $DEAD, 'nothing was written past the reported length');
  end
  else
    for i := 1 to 6 do Chk(False, '(converted row not run -- wrong length)');
  ChkI(getunicode(@src[0], 0, m, nil), 0, 'a zero-length source converts to nothing');
  ChkI(getunicode(nil, 6, m, nil), 0, 'a nil source converts to nothing');

  { ---- getascii, both overloads ----------------------------------------- }
  s := getascii($0041, m);
  ChkI(Length(s), 1, 'getascii of an ASCII character is one byte');
  ChkI(Ord(s[1]), 65, 'and it is the right byte');
  s := getascii($20AC, m);
  ChkI(Length(s), 1, 'getascii of the euro sign is one byte in this codepage');
  ChkI(Ord(s[1]), 128, 'and it is the right byte');
  s := getascii($4E00, m);
  ChkI(Length(s), 2, 'getascii of a two-byte character is two bytes');
  ChkI(Ord(s[1]), 142, 'lead byte');
  ChkI(Ord(s[2]), 65, 'trail byte');
  s := getascii($0500, m);
  ChkI(Length(s), 1, 'getascii of an unrepresentable character is one byte');
  ChkI(Ord(s[1]), 63, 'and that byte is ?');

  ChkI(getascii($0041, m, nil, 0), 1, 'the buffer form with nil asks the LENGTH: one byte');
  ChkI(getascii($4E00, m, nil, 0), 2, 'the buffer form with nil asks the LENGTH: two bytes');
  FillChar(src, SizeOf(src), 0);
  ChkI(getascii($0041, m, @src[0], 8), 1, 'the buffer form writes one byte');
  ChkI(Ord(src[0]), 65, 'and writes the right one');
  FillChar(src, SizeOf(src), 0);
  ChkI(getascii($4E00, m, @src[0], 8), 2, 'the buffer form writes two bytes');
  ChkI(Ord(src[0]), 142, 'lead byte into the buffer');
  ChkI(Ord(src[1]), 65, 'trail byte into the buffer');
  ChkI(getascii($4E00, m, @src[0], 1), -1, 'a buffer too small for a two-byte character is refused');
  ChkI(getascii($0041, m, @src[0], 0), -1, 'a zero-length buffer is refused');
  FillChar(src, SizeOf(src), 0);
  ChkI(getascii($0500, m, @src[0], 8), 1, 'an unrepresentable character writes one byte');
  ChkI(Ord(src[0]), 63, 'and that byte is ?');

  { ---- the binary format ------------------------------------------------ }
  ChkI(SizeOf(tunicodecharmapping), 4, 'the forward record is 4 bytes -- {$PACKENUM 1} is in force');
  ChkI(SizeOf(treversecharmapping), 4, 'the reverse record is 4 bytes');
  ChkI(SizeOf(TSerializedMapHeader), 35, 'the serialised header is 35 bytes');
  hdr.cpName := m^.cpname;
  hdr.cp := m^.cp;
  hdr.mapLength := (m^.lastchar + 1) * SizeOf(tunicodecharmapping);
  hdr.lastChar := m^.lastchar;
  hdr.reverseMapLength := m^.reversemaplength * SizeOf(treversecharmapping);
  totalBytes := SizeOf(hdr) + hdr.mapLength + hdr.reverseMapLength;
  GetMem(buf, totalBytes);
  Move(hdr, buf^, SizeOf(hdr));
  Move(m^.map^, (buf + SizeOf(hdr))^, hdr.mapLength);
  Move(m^.reversemap^, (buf + SizeOf(hdr) + hdr.mapLength)^, hdr.reverseMapLength);
  mb := loadbinaryunicodemapping(buf, totalBytes);
  Chk(mb <> nil, 'a serialised map loads back');
  if mb <> nil then
  begin
    Chk(mb^.cpname = 'MINI', 'the name survives the round trip');
    ChkI(mb^.cp, 1234, 'the codepage survives the round trip');
    ChkI(mb^.lastchar, 36419, 'lastchar survives the round trip');
    ChkI(mb^.reversemaplength, 7, 'the reverse map length survives the round trip');
    { Bytes, not just the derived answers: a loader that rebuilt the tables
      instead of reading them would pass the lookups below and fail this. }
    Chk(CompareByte(m^.map^, mb^.map^, hdr.mapLength) = 0,
        'the forward table came back byte for byte');
    Chk(CompareByte(m^.reversemap^, mb^.reversemap^, hdr.reverseMapLength) = 0,
        'the reverse table came back byte for byte');
    ChkI(getunicode('A', mb), 65, 'the reloaded map converts forwards');
    s := getascii($4E00, mb);
    ChkI(Length(s), 2, 'the reloaded map converts backwards');
    ChkI(Ord(s[1]), 142, 'reloaded lead byte');
    ChkI(Ord(s[2]), 65, 'reloaded trail byte');
  end
  else
    for i := 1 to 10 do Chk(False, '(round-trip row not run)');

  { A short image must be REFUSED, not half-loaded into a map that then answers
    from uninitialised memory. }
  Chk(loadbinaryunicodemapping(buf, SizeOf(hdr) + 4) = nil, 'a truncated image is refused');
  Chk(loadbinaryunicodemapping(buf, 2) = nil, 'an image too short for the header is refused');

  { ---- the absent-file doors -------------------------------------------- }
  Chk(loadunicodemapping('X', dir + '/no_such_file.txt', 1) = nil, 'an absent text file is nil');
  Chk(loadbinaryunicodemapping(dir + '/no_such_file.bcm') = nil, 'an absent binary file is nil');
  Chk(loadbinaryunicodemapping('') = nil, 'an empty file name is nil');
  Chk(not registerbinarymapping(dir, 'no_such_cp'), 'registering an absent binary map fails');
  Chk(not registerbinarymapping('', 'no_such_cp'), 'and so does one with an empty directory');
  { Failing to register must not publish anything either. }
  Chk(not mappingavailable('no_such_cp'), 'a failed registration registered nothing');

  { ---- the two places we deliberately answer where fpc does not --------- }

  { RUN WITH A SECOND ARGUMENT `parity` TO SKIP THIS SECTION. That mode exists
    so the fpc column above stays reproducible by anyone: fpc cannot reach the
    end of this file (the first row below kills it with runtime error 216), and
    a claim that "fpc runs this same file" has to be checkable. Measured
    2026-09-16: `lib_charset <dir> parity` answers 95 / 95 under fpc 3.2.2 and
    95 / 95 under pxx; the full run answers 98 / 98 under pxx and crashes fpc. }
  if ParamStr(2) = 'parity' then
  begin
    WriteLn('total ok ', ok, ' / ', total);
    Halt(0);
  end;

  { fpc SEGVs here: its nil check covers only the representable arm. }
  ChkI(getascii($0500, m, nil, 0), 1,
       'DIVERGENCE: a nil buffer is honoured for an UNREPRESENTABLE character too (fpc SEGVs)');
  { And a file whose last field runs to the line end: fpc reads the previous
    line's bytes, we stop. The expected value is ours, not fpc's, and it is the
    one the file actually asks for. }
  path := dir + '/lib_charset_ragged.txt';
  Assign(t, path);
  Rewrite(t);
  WriteLn(t, '0x8E', #9, '#DBCS LEAD BYTE');
  WriteLn(t, '0x8E41', #9, '0x4E00');      { no trailing comment: ends in hex }
  Close(t);
  m := loadunicodemapping('RAGGED', path, 4321);
  Chk(m <> nil, 'the ragged file loads');
  if m <> nil then
    ChkI(m^.map[$8E41].unicode, 19968,
         'DIVERGENCE: the scan stops at the line end (fpc reads the previous line and answers 173)')
  else
    Chk(False, '(ragged row not run)');

  WriteLn('total ok ', ok, ' / ', total);
end.
