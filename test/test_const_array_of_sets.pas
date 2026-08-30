program test_const_array_of_sets;
{ A `const` array whose ELEMENTS are sets — fcl-xml's W3C naming tables
  (`namingBitmap: array[0..$0C] of TSetOfByte`) and the ordinary way a lexer
  writes a table of character classes.

  It was rejected as `too many array constant elements` with the position on the
  FIRST element, which reads as a size complaint about a correct size. The array
  -constant element loop's fallback arm calls ParseInitVal, which does not
  consume a `[`, so the loop spun on the same token and counted it once per
  declared slot. That is the third instance of one shape — the multi-character
  string literal and the PChar element above it in that loop failed the same way
  — so the rows below cover the boundary rather than one example: an EMPTY set
  (the shape that spun first), a FULL one, a range, and a named set constant as
  an element, in both a global and a routine-local const array. The local one
  goes through a different emitter (LocalInit, not PendingInit) which is exactly
  where a second encoding would drift.

  ORACLE, and the claim is deliberately split. The `tbl`/`loc` rows are
  FPC-parity: with the `ext` section below deleted, FPC (-Mdelphi) compiles this
  file and prints those seven lines identically. FPC REJECTS both of the `ext`
  forms — a named set constant as an element and a set EXPRESSION as an element
  — as "Illegal expression". Accepting a form FPC rejects is not a defect
  (CLAUDE.md's compat ceiling), so they are kept and covered here rather than
  removed: they reach BakeSetConst through FindSetConst and through its
  `+`/`-` folding, which the literal rows never exercise. Their expected values
  are derived from the set algebra, not from FPC. }
type
  TSetOfByte = set of Byte;
const
  ns_A: TSetOfByte = [$41..$5A];              { 'A'..'Z' }
  { FPC-parity rows: literal set constructors only. }
  tbl: array[0..3] of TSetOfByte =
    ([], [0..255], [$30..$39], [$41..$5A]);
  { Beyond FPC, and covering the two paths the literal rows do not: a NAMED set
    constant as an element, and a set EXPRESSION folded at declaration time. }
  ext: array[0..1] of TSetOfByte =
    (ns_A, ns_A + [$30..$39] - [$41]);

function Code(const s: TSetOfByte): Integer;
{ 1 = holds 'A', 2 = holds '0', 4 = holds #0 — one number per element so a
  wrong 32-byte blob cannot look right by matching on one probe bit. }
begin
  Result := 0;
  if $41 in s then Result := Result + 1;
  if $30 in s then Result := Result + 2;
  if 0 in s then Result := Result + 4;
end;

procedure Local;
const
  loc: array[0..2] of TSetOfByte = ([], [$41..$5A, $30..$39], [$42..$5A]);
var i: Integer;
begin
  for i := 0 to 2 do WriteLn('loc', i, ' ', Code(loc[i]));
end;

var i: Integer;
begin
  for i := 0 to 3 do WriteLn('tbl', i, ' ', Code(tbl[i]));
  Local;
  for i := 0 to 1 do WriteLn('ext', i, ' ', Code(ext[i]));
end.
