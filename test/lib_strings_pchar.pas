{ The `strings` PChar family — the half that was missing until
  feature-b-rtl-gap-inventory-22-sysutils-strutils-symbols.

  EVERY expectation here was MEASURED against fpc 3.2.2 by running the same
  program under both compilers and diffing, not reasoned about from the names.
  The four that a plausible implementation gets wrong:

  - StrNew('') and StrNew(nil) are **nil**, not an empty allocated buffer.
  - StrECopy returns the cursor at the terminating NUL, not Dest — it is the
    only Str*Copy whose return value is not the destination.
  - StrBufSize after StrAlloc(20) is 20 (the hidden 4-byte prefix is subtracted
    back out), but after StrNew('abc') it is 4 — the string length plus the
    NUL, not any rounded capacity.
  - StrPLCopy's MaxLen counts characters COPIED: with MaxLen 0 it still writes
    the terminator, so buf[0] is #0 and not left untouched.

  Reached through `sysutils`, which is how FPC code actually spells it — that
  is the gap this closed: real code writes `uses SysUtils` and calls StrPCopy
  without ever naming the `strings` unit, and half the family used to stop
  there. SysUtils' arms are one-line forwards into lib/rtl/strings.pas, so this
  exercises that unit's implementation too.

  NOTE this file deliberately does NOT say `uses strings`: unit resolution
  searches the source file's own directory first, and `test/strings.pas` is a
  PROGRAM named Strings, so any test in test/ naming that unit fails to parse.
  Same collision the Makefile already works around for `tk` (Makefile:379). }
program lib_strings_pchar;

uses sysutils;

var
  failures: Integer;

procedure Check(ok: Boolean; const what: string);
begin
  if not ok then
  begin
    Writeln('FAIL: ', what);
    failures := failures + 1;
  end;
end;

procedure CheckStr(const got, want, what: string);
begin
  if got <> want then
  begin
    Writeln('FAIL: ', what, ' got [', got, '] want [', want, ']');
    failures := failures + 1;
  end;
end;

procedure CheckInt(got, want: Integer; const what: string);
begin
  if got <> want then
  begin
    Writeln('FAIL: ', what, ' got ', got, ' want ', want);
    failures := failures + 1;
  end;
end;

var
  buf: array[0..63] of Char;
  buf2: array[0..63] of Char;
  p: PChar;
  i: Integer;

begin
  failures := 0;

  { ---- StrPCopy: pascal string -> buffer, returns Dest, always terminates ---- }
  for i := 0 to 63 do buf[i] := '#';
  p := StrPCopy(@buf[0], 'hello');
  Check(p = @buf[0], 'StrPCopy returns Dest');
  CheckStr(StrPas(@buf[0]), 'hello', 'StrPCopy copies');
  CheckInt(Ord(buf[5]), 0, 'StrPCopy terminates');
  for i := 0 to 63 do buf[i] := '#';
  StrPCopy(@buf[0], '');
  CheckInt(Ord(buf[0]), 0, 'StrPCopy of the empty string writes just the NUL');

  { ---- StrPLCopy: MaxLen is CHARACTERS COPIED, terminator always written ---- }
  for i := 0 to 63 do buf[i] := '#';
  p := StrPLCopy(@buf[0], 'hello', 3);
  Check(p = @buf[0], 'StrPLCopy returns Dest');
  CheckStr(StrPas(@buf[0]), 'hel', 'StrPLCopy truncates to MaxLen');
  for i := 0 to 63 do buf[i] := '#';
  StrPLCopy(@buf[0], 'hi', 10);
  CheckStr(StrPas(@buf[0]), 'hi', 'StrPLCopy with room to spare copies it all');
  for i := 0 to 63 do buf[i] := '#';
  StrPLCopy(@buf[0], 'hello', 0);
  CheckInt(Ord(buf[0]), 0, 'StrPLCopy with MaxLen 0 still terminates');

  { ---- StrAlloc / StrBufSize / StrDispose ---- }
  p := StrAlloc(20);
  Check(p <> nil, 'StrAlloc returns a buffer');
  CheckInt(StrBufSize(p), 20, 'StrBufSize reports the REQUESTED size, prefix removed');
  StrCopy(p, 'usable');
  CheckStr(StrPas(p), 'usable', 'the StrAlloc buffer is writable');
  StrDispose(p);
  CheckInt(StrBufSize(nil), 0, 'StrBufSize(nil) is 0, not a fault');
  StrDispose(nil);
  Check(True, 'StrDispose(nil) is a no-op');

  { ---- StrNew: nil for BOTH nil and empty sources ---- }
  p := StrNew('abc');
  Check(p <> nil, 'StrNew of a non-empty string allocates');
  CheckStr(StrPas(p), 'abc', 'StrNew copies');
  CheckInt(StrBufSize(p), 4, 'StrNew sizes to StrLen+1, not to a capacity');
  StrDispose(p);
  Check(StrNew('') = nil, 'StrNew of the EMPTY string is nil');
  Check(StrNew(nil) = nil, 'StrNew(nil) is nil');

  { ---- StrECopy: returns the END cursor, not Dest ---- }
  for i := 0 to 63 do buf[i] := '#';
  StrCopy(@buf[0], 'abc');
  p := StrECopy(@buf[0], 'xy');
  CheckStr(StrPas(@buf[0]), 'xy', 'StrECopy overwrites from the start');
  { PtrUInt rather than the plain PChar difference: `p - @buf[0]` computes the
    right value but segfaults when printed un-assigned —
    bug-pchar-difference-in-writeln-arg-segfaults. Revert this cast when that
    is fixed. }
  CheckInt(Integer(PtrUInt(p) - PtrUInt(@buf[0])), 2,
           'StrECopy returns the cursor at the terminating NUL');
  { the reason it exists: chained appends with no StrEnd rescan.
    The separator is '--' and not '-' only because a ONE-character literal
    passed to a PChar parameter segfaults on pxx today —
    bug-single-char-literal-as-pchar-argument-segfaults, which is a pre-existing
    frontend bug that hits StrCopy/StrCat the same way. Restore the single
    character when that lands. }
  for i := 0 to 63 do buf[i] := '#';
  p := @buf[0];
  p := StrECopy(p, 'one');
  p := StrECopy(p, '--');
  StrECopy(p, 'two');
  CheckStr(StrPas(@buf[0]), 'one--two', 'StrECopy chains');

  { ---- StrUpper / StrLower: ASCII only, in place, return the same pointer ---- }
  StrCopy(@buf[0], 'aBc9Z');
  p := StrUpper(@buf[0]);
  CheckStr(StrPas(@buf[0]), 'ABC9Z', 'StrUpper uppercases in place, digits untouched');
  Check(p = @buf[0], 'StrUpper returns its argument');
  StrCopy(@buf[0], 'aBc9Z');
  StrLower(@buf[0]);
  CheckStr(StrPas(@buf[0]), 'abc9z', 'StrLower lowercases in place');

  { ---- StrMove: exactly L bytes, no terminator of its own ---- }
  StrCopy(@buf[0], 'abcdef');
  p := StrMove(@buf[0], PChar('XY'), 2);
  CheckStr(StrPas(@buf[0]), 'XYcdef', 'StrMove copies L bytes and no terminator');
  Check(p = @buf[0], 'StrMove returns Dest');
  { overlapping, forward — the case a naive byte loop smears }
  StrCopy(@buf[0], 'abcdef');
  StrMove(@buf[2], @buf[0], 4);
  CheckStr(StrPas(@buf[0]), 'ababcd', 'StrMove handles a forward overlap');
  StrCopy(@buf[0], 'abcdef');
  StrMove(@buf[0], @buf[2], 4);
  CheckStr(StrPas(@buf[0]), 'cdefef', 'StrMove handles a backward overlap');

  { ---- the already-present half still reachable from the same unit: the whole
         point of the ticket was that a program could call StrScan and then hit
         a wall on StrPCopy two lines later ---- }
  for i := 0 to 63 do buf2[i] := '#';
  StrPCopy(@buf2[0], 'one/two');
  CheckStr(StrPas(StrScan(@buf2[0], '/')), '/two', 'StrScan from SysUtils');
  CheckStr(StrPas(StrEnd(@buf2[0])), '', 'StrEnd from SysUtils');
  CheckInt(StrComp(@buf2[0], @buf2[0]), 0, 'StrComp from SysUtils');
  CheckStr(StrPas(StrPos(@buf2[0], PChar('two'))), 'two', 'StrPos from SysUtils');

  if failures = 0 then Writeln('STRINGSPCHAR OK')
  else Writeln('STRINGSPCHAR ', failures, ' FAILURES');
end.
