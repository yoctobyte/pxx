program lib_zlib_emit;
{ Dumps DeflateZlib output as hex for test/lib_zlib_cpython.py to check.

  WHY A SECOND PROGRAM RATHER THAN MORE ROWS IN lib_zlib.pas: the rows there
  round-trip our encoder through OUR inflater, and two halves of one unit can
  share a misreading of RFC 1951 and agree with each other all the way. CPython's
  zlib is an independently written decoder, so it fails differently -- which is
  the only property that makes a second reading worth anything (CLAUDE.md, "a
  second source only counts if it FAILS DIFFERENTLY").

  One line per case: <name> <level> <rawhex> <enchex>. Inputs stay small because
  the whole thing goes through stdout as hex; they are chosen for coverage of the
  encoder's branches, not for size. }

uses hashing, zlib;
{ NOT sysutils -- its TByteArray is a STATIC array and shadows hashing's dynamic
  one, which makes SetLength refuse. Same trap the unit header warns about for
  Adler32. }

var src, enc: TByteArray;

function HexOf(const a: TByteArray): AnsiString;
const D: AnsiString = '0123456789abcdef';
var i: Integer; s: AnsiString;
begin
  s := '';
  for i := 0 to Length(a) - 1 do
    s := s + D[(a[i] shr 4) + 1] + D[(a[i] and 15) + 1];
  if s = '' then s := '-';
  Result := s;
end;

procedure Emit(const name: AnsiString; level: Integer);
var lv: AnsiString;
begin
  DeflateZlib(src, enc, level);
  if level < 0 then lv := '-1' else lv := Chr(48 + level);
  writeln(name, ' ', lv, ' ', HexOf(src), ' ', HexOf(enc));
end;

var i, st: Integer;
begin
  { empty, and the three lengths below the 3-byte minimum match }
  SetLength(src, 0);              Emit('empty', 6);
  SetLength(src, 1); src[0] := 7; Emit('one', 6);
  SetLength(src, 2); src[0] := 1; src[1] := 2; Emit('two', 6);

  { every fixed-Huffman code length: 0..143 are 8 bits, 144..255 are 9 }
  SetLength(src, 256);
  for i := 0 to 255 do src[i] := Byte(i);
  Emit('bytes256', 6);

  { one long run -- exercises the 258 length cap and distance 1 }
  SetLength(src, 2000);
  for i := 0 to 1999 do src[i] := 65;
  Emit('same2000', -1);
  for i := 0 to 9 do Emit('same2000', i);

  { text: literals and matches interleaved }
  SetLength(src, 1024);
  for i := 0 to 1023 do src[i] := Byte(Ord('a') + (i mod 7) + ((i div 64) mod 3));
  Emit('texty', 6);

  { no matches at all -- the stored fallback }
  SetLength(src, 1500);
  st := 12345;
  for i := 0 to 1499 do
  begin
    st := (st * 1103515245 + 12345) and $3FFFFFFF;
    src[i] := Byte((st shr 16) and $FF);
  end;
  Emit('random1500', 6);

  { short matches at scattered distances -- where the level knobs bite }
  SetLength(src, 3000);
  st := 999;
  for i := 0 to 2999 do
  begin
    st := (st * 1103515245 + 12345) and $3FFFFFFF;
    src[i] := Byte((st shr 16) and 15);
  end;
  for i := 1 to 9 do Emit('chainy', i);
end.
