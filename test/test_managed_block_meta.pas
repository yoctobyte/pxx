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

{ ASKED, as opposed to ANSWERED. Every assertion below that only reads IsAscii
  conflates "scanned, has high bytes" with "nobody looked" — both answer False —
  so it passes whichever of the two the code produces. That is not a hypothetical
  weakness: the inline-path assertion further down passed for two months against
  a block that was in fact stamped KNOWN and non-ASCII, which is a different
  claim from the one its own comment makes
  (regression-test-core-test-nilpy-str-ascii-cache). }
function IsAsciiKnown(const v: AnsiString): Boolean;
begin
  IsAsciiKnown := (PXXHdrMeta(Pointer(v)) and PXX_FLAG_ASCII_KNOWN) <> 0;
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
  Check(not IsAsciiKnown(both), 'inline-allocated string is UNKNOWN, not known-non-ascii');
  Check((PXXHdrMeta(Pointer(both)) shr 32) = 0, 'reserved bits zero (inline path)');

  { The mirror of the growth assertion above, and the one a careless fix breaks:
    appending to a string whose ASCII-ness was never established must leave it
    UNKNOWN, not invent ascii from the appended bytes alone. `both` here came
    from the inline SetLength path, so it carries no flag; 'a'..'e' plus 'x' are
    all ascii, yet nothing has scanned the payload. }
  both := both + 'x';
  Check(not IsAscii(both), 'append to an unknown-kind string does not invent ascii');

  { MUTATION FORGETS. The two assertions below are the ones x86-64 failed, and
    they fail in the dangerous direction — a block still advertising ASCII while
    holding a byte >= $80, so a consumer indexes a multi-byte string at BYTE
    offsets and returns a broken character with no error anywhere.

    x86-64 is the only target that can fail them, because it is the only one
    that does not CALL the two Pascal helpers that keep the cache sound: it
    inlines PXXStrUnique (whose own comment calls it "the single choke point for
    byte mutation") and it inlines the symbol-target SetLength (whose helper's
    comment says it "always allocates a fresh block", true of the helper and not
    of the inline path). Both comments describe an invariant this target routes
    around, so both are asserted here rather than trusted. }

  { (1) a bare indexed store, no SetLength anywhere near it }
  a := 'abc';
  Check(IsAscii(a) and IsAsciiKnown(a), 'ascii literal is known-ascii');
  a[1] := Chr(200);
  Check(not IsAscii(a), 'indexed store clears the ASCII verdict');
  Check(not IsAsciiKnown(a), 'indexed store clears KNOWN too, not just ASCII');

  { (2) an IN-PLACE SetLength grow — the request has to fit the block's existing
    capacity or the alloc arm runs instead and the flag is fresh for a different
    reason. A 3-byte literal grown to 5 stays inside its 32-byte payload. }
  a := 'abc';
  SetLength(a, 5);
  a[4] := Chr(200); a[5] := Chr(200);
  Check(not IsAscii(a), 'in-place SetLength grow does not keep a stale ascii yes');
  Check(not IsAsciiKnown(a), 'in-place SetLength grow leaves the answer unknown');

  { nil handle answers LEGACY rather than faulting }
  a := '';
  Check(PXXHdrMeta(Pointer(a)) = PXX_KIND_LEGACY, 'nil handle reads LEGACY');

  if failures = 0 then WriteLn('managed block meta ok')
  else WriteLn('managed block meta FAILED ', failures);
end.
