program test_managed_block_meta;
{ feature-nilpy-text-string-kind, phase 2 foundation.

  The META word of the shared managed-block header:
    BlockKind(8) | Flags(8) | KindData0(8) | KindData1(8), bits 32-63 RESERVED.

  Pins the one field that carries information today — PXX_FLAG_ASCII — because
  it is what will make NilPy character indexing O(1) on the overwhelmingly
  common string, and because it is computed inside the string constructors'
  existing copy loops where a mistake is invisible.

  Also pins the LOW-32 budget: bits 32-63 must read zero. A future field that
  quietly spends the upper half would foreclose
  feature-a-shrink-managed-header-on-32-bit, where a packed ILP32 header makes
  this word 32 bits wide. }

uses builtinheap;

var failures: Integer;

procedure Check(ok: Boolean; const what: AnsiString);
begin
  if not ok then
  begin
    WriteLn('FAIL ', what);
    failures := failures + 1;
  end;
end;

function IsAscii(const v: AnsiString): Boolean;
begin
  IsAscii := (PXXHdrMeta(Pointer(v)) and PXX_FLAG_ASCII) <> 0;
end;

var
  a, hi, both, grown: AnsiString;
  i: Integer;

begin
  failures := 0;

  { a literal of plain ASCII }
  a := 'plain ascii text';
  Check(IsAscii(a), 'ascii literal flagged');

  { a string carrying a UTF-8 continuation byte must NOT be flagged. Built with
    Chr so the test file itself stays ASCII. }
  hi := 'h' + Chr(195) + Chr(169) + 'llo';    { h, U+00E9 as UTF-8, llo }
  Check(not IsAscii(hi), 'non-ascii not flagged');
  Check(Length(hi) = 6, 'non-ascii byte length still 6');

  { concat propagates: ascii+ascii is ascii, ascii+non-ascii is not }
  both := a + a;
  Check(IsAscii(both), 'ascii concat stays ascii');
  both := a + hi;
  Check(not IsAscii(both), 'concat with non-ascii is not ascii');
  both := hi + a;
  Check(not IsAscii(both), 'concat with non-ascii first is not ascii');

  { growth through the inline resize path must not lose or invent the flag }
  grown := '';
  for i := 1 to 300 do grown := grown + 'x';
  Check(IsAscii(grown), 'grown ascii string stays ascii');
  grown := grown + Chr(200);
  Check(not IsAscii(grown), 'grown string turning non-ascii loses the flag');

  { the RESERVED half must be zero — see the header comment }
  Check((PXXHdrMeta(Pointer(a)) shr 32) = 0, 'reserved bits 32-63 are zero');
  Check((PXXHdrMeta(Pointer(hi)) shr 32) = 0, 'reserved bits zero (non-ascii)');

  { A string built by the x86-64 INLINE allocation path (SetLength lays the
    header down in emitted code) carries NO flag. That is correct and must stay
    correct: absence means "unknown", NOT "non-ascii". A consumer that reads a
    missing flag as "definitely multi-byte" is wrong-but-slow; one that reads it
    as "definitely ascii" is wrong-and-fast, which is the bug this pins. }
  SetLength(both, 5);
  both[1] := 'a'; both[2] := 'b'; both[3] := 'c'; both[4] := 'd'; both[5] := 'e';
  Check(not IsAscii(both), 'inline-allocated string carries no flag (unknown)');
  Check((PXXHdrMeta(Pointer(both)) shr 32) = 0, 'reserved bits zero (inline path)');

  { The mirror of the growth assertion above, and the one a careless fix breaks:
    appending to a string whose ASCII-ness was never established must leave it
    UNKNOWN, not invent ascii from the appended bytes alone. `both` here came
    from the inline SetLength path, so it carries no flag; 'a'..'e' plus 'x' are
    all ascii, yet nothing has scanned the payload. }
  both := both + 'x';
  Check(not IsAscii(both), 'append to an unknown-kind string does not invent ascii');

  { nil handle answers LEGACY rather than faulting }
  a := '';
  Check(PXXHdrMeta(Pointer(a)) = PXX_KIND_LEGACY, 'nil handle reads LEGACY');

  if failures = 0 then WriteLn('managed block meta ok')
  else WriteLn('managed block meta FAILED ', failures);
end.
