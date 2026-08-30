unit builtinwide;
{ UTF-16 runtime: wide allocation, concatenation and both UTF-8 transcoders.

  WHY IT IS ITS OWN UNIT. These four functions lived in builtinheap, which has
  no dead-code elimination -- it arrives whole or not at all
  (bug-a-a-pascal-hello-world-is-63kb-after-emission-size-dce). So 278 lines of
  correct runtime became 13,232 bytes of every bare xtensa image and 15,724 of
  every bare riscv32 one, in programs that could not reach them: a third of the
  flash budget on the target family whose entire campaign is size. A bare-ESP
  {$ifndef} bought that back for ESP and left x86_64 paying 4 KB.

  A UNIT IS THE GRANULARITY THE COMPILER HAS, so make the unit match the
  feature. Pulled on demand by pasparser_prog.inc the way `math` is -- 35 KB of
  numerics that a program without `sqrt` never links -- rather than by an
  {$ifndef} per target, which cannot express "this program does not use
  UTF-16".

  THE SHAPE IS wasibackend.pas's, deliberately: a compiler builtin that `uses
  builtinheap` from its implementation and is pulled behind a needs* predicate.
  That unit is the proof a builtin can depend on another builtin; this one is
  the second instance.

  The block layout is builtinheap's and unchanged -- [kind][rc][len][data], len
  in BYTES for both widths -- which is why every existing retain/release/free
  path works on a wide string with no second arm. Only Length() halves it, and
  that is a frontend lowering off the string's ELEMENT type, not a runtime tag
  lookup. feature-unicodestring-model }

interface

function PXXWideAlloc(units: NativeInt): Pointer;
function PXXWideConcat(bytesA: NativeInt; srcA: Pointer; srcB: Pointer; bytesB: NativeInt): Pointer;
function PXXWideFromUtf8(src: Pointer; byteLen: NativeInt): Pointer;
function PXXUtf8FromWide(src: Pointer; byteLen: NativeInt): Pointer;

implementation

uses builtinheap;

{ Pointer aliases, declared here exactly as builtinheap declares them in ITS
  implementation -- they are not exported, and exporting them would put PWord
  and PByte into every program that uses builtinheap, where a user's own PWord
  would be silently re-typed (the trap CLAUDE.md names). Duplicating a type
  alias is not a second code path; getting PWord wrong is. }
type
  PWord = ^NativeInt;  { pointer-sized machine word -- 8 bytes on 64-bit, 4 on
                         32-bit. MUST NOT be ^Int64: on i386 that writes 8
                         bytes into a 4-byte slot and corrupts its neighbour.
                         Matches builtinheap. }
  PByte = ^Byte;
  PU16  = ^Word;   { 2-byte access for UTF-16 code units. NOT PWord -- that name
                     means ^NativeInt above, which is the single easiest mistake
                     to make in this file. }

{ A fresh wide block of `units` UTF-16 code units, zero-filled, 2-byte NUL
  terminated. Returns nil for an empty result, matching every other managed
  string constructor here (an empty managed string IS the nil handle). }
function PXXWideAlloc(units: NativeInt): Pointer;
var base, d, i, nbytes: Int64;
begin
  if units <= 0 then
  begin
    Result := nil;
    Exit;
  end;
  nbytes := Int64(units) * 2;
  base := Int64(PXXAlloc(nbytes + PXX_HDR_SIZE + 2, 8));   { +2 = wide NUL }
  PWord(base + PXX_HDR_RC)^  := 1;
  PWord(base + PXX_HDR_LEN)^ := nbytes;    { BYTES, as everywhere else }
  d := base + PXX_HDR_SIZE;
  i := 0;
  while i < nbytes do
  begin
    PByte(d + i)^ := 0;
    i := i + 1;
  end;
  PByte(d + nbytes)^ := 0;
  PByte(d + nbytes + 1)^ := 0;
  PWord(base + PXX_HDR_META)^ := PXX_KIND_WIDESTR;
  Result := Pointer(d);
end;

{ Wide concatenation. Byte lengths in, byte lengths out -- this is
  PXXStrConcat with a wider terminator and no ASCII scan, and it is a separate
  function only because those two differ. }
function PXXWideConcat(bytesA: NativeInt; srcA: Pointer; srcB: Pointer; bytesB: NativeInt): Pointer;
var total, base, d: Int64;
begin
  total := Int64(bytesA) + Int64(bytesB);
  if total <= 0 then
  begin
    Result := nil;
    Exit;
  end;
  base := Int64(PXXAlloc(total + PXX_HDR_SIZE + 2, 8));
  PWord(base + PXX_HDR_RC)^  := 1;
  PWord(base + PXX_HDR_LEN)^ := total;
  d := base + PXX_HDR_SIZE;
  PXXBlockCopy(d, Int64(srcA), bytesA);
  PXXBlockCopy(d + bytesA, Int64(srcB), bytesB);
  PByte(d + total)^ := 0;
  PByte(d + total + 1)^ := 0;
  PWord(base + PXX_HDR_META)^ := PXX_KIND_WIDESTR;
  Result := Pointer(d);
end;

{ UTF-8 bytes -> UTF-16 code units. A code point above the BMP becomes a
  SURROGATE PAIR, which is the whole reason this ticket exists: jsonscanner
  builds one by hand and needs the two halves to be a two-unit STRING.

  Malformed input is passed through as U+FFFD rather than rejected. This
  transcoder sits under Utf8Decode and under every wide assignment, so raising
  here would turn a bad byte in a JSON document into a crash in the parser.

  Allocation is worst-case (one unit per input BYTE, which ASCII actually
  reaches) and the length word is patched down afterwards. Two passes over the
  input would cost more than the slack. }
function PXXWideFromUtf8(src: Pointer; byteLen: NativeInt): Pointer;
var
  base, d, s, i, units, cp, b, need, k: Int64;
begin
  if (src = nil) or (byteLen <= 0) then
  begin
    Result := nil;
    Exit;
  end;
  base := Int64(PXXAlloc(Int64(byteLen) * 2 + PXX_HDR_SIZE + 2, 8));
  PWord(base + PXX_HDR_RC)^ := 1;
  d := base + PXX_HDR_SIZE;
  s := Int64(src);
  i := 0;
  units := 0;
  while i < byteLen do
  begin
    b := PByte(s + i)^;
    if b < $80 then
    begin
      cp := b; need := 0;
    end
    else if (b and $E0) = $C0 then
    begin
      cp := b and $1F; need := 1;
    end
    else if (b and $F0) = $E0 then
    begin
      cp := b and $0F; need := 2;
    end
    else if (b and $F8) = $F0 then
    begin
      cp := b and $07; need := 3;
    end
    else
    begin
      cp := $FFFD; need := 0;    { stray continuation or 5/6-byte form }
    end;
    i := i + 1;
    k := 0;
    while k < need do
    begin
      if (i >= byteLen) or ((PByte(s + i)^ and $C0) <> $80) then
      begin
        cp := $FFFD;             { truncated -- stop, do not consume the next lead }
        k := need;
      end
      else
      begin
        cp := (cp shl 6) or (PByte(s + i)^ and $3F);
        i := i + 1;
        k := k + 1;
      end;
    end;
    if cp > $10FFFF then cp := $FFFD;
    if cp < $10000 then
    begin
      PU16(d + units * 2)^ := Word(cp);
      units := units + 1;
    end
    else
    begin
      cp := cp - $10000;
      PU16(d + units * 2)^ := Word($D800 + (cp shr 10));
      PU16(d + units * 2 + 2)^ := Word($DC00 + (cp and $3FF));
      units := units + 2;
    end;
  end;
  if units = 0 then
  begin
    PXXFree(Pointer(base));
    Result := nil;
    Exit;
  end;
  PWord(base + PXX_HDR_LEN)^ := units * 2;
  PByte(d + units * 2)^ := 0;
  PByte(d + units * 2 + 1)^ := 0;
  PWord(base + PXX_HDR_META)^ := PXX_KIND_WIDESTR;
  Result := Pointer(d);
end;

{ UTF-16 code units -> UTF-8 bytes. `byteLen` is the wide string's header
  length, i.e. units * 2. Result is an ordinary BYTESTR-shaped block with a
  1-byte NUL, because that is what every consumer of the result expects.

  An unpaired surrogate becomes U+FFFD, for the same reason as above: this runs
  under Utf8Encode on data that came from a file. Worst case is 3 bytes per
  unit (a BMP code point); a surrogate PAIR is 4 bytes for 2 units, so it is
  never the worst case. }
function PXXUtf8FromWide(src: Pointer; byteLen: NativeInt): Pointer;
var
  base, d, s, i, units, out_, cp, hi, lo: Int64;
begin
  units := Int64(byteLen) div 2;
  if (src = nil) or (units <= 0) then
  begin
    Result := nil;
    Exit;
  end;
  base := Int64(PXXAlloc(units * 3 + PXX_HDR_SIZE + 1, 8));
  PWord(base + PXX_HDR_RC)^ := 1;
  d := base + PXX_HDR_SIZE;
  s := Int64(src);
  i := 0;
  out_ := 0;
  while i < units do
  begin
    hi := PU16(s + i * 2)^;
    i := i + 1;
    if (hi >= $D800) and (hi <= $DBFF) then
    begin
      if i < units then
      begin
        lo := PU16(s + i * 2)^;
        if (lo >= $DC00) and (lo <= $DFFF) then
        begin
          cp := $10000 + ((hi - $D800) shl 10) + (lo - $DC00);
          i := i + 1;
        end
        else
          cp := $FFFD;           { high surrogate not followed by a low one }
      end
      else
        cp := $FFFD;             { high surrogate at end of string }
    end
    else if (hi >= $DC00) and (hi <= $DFFF) then
      cp := $FFFD                { lone low surrogate }
    else
      cp := hi;
    if cp < $80 then
    begin
      PByte(d + out_)^ := Byte(cp);
      out_ := out_ + 1;
    end
    else if cp < $800 then
    begin
      PByte(d + out_)^ := Byte($C0 or (cp shr 6));
      PByte(d + out_ + 1)^ := Byte($80 or (cp and $3F));
      out_ := out_ + 2;
    end
    else if cp < $10000 then
    begin
      PByte(d + out_)^ := Byte($E0 or (cp shr 12));
      PByte(d + out_ + 1)^ := Byte($80 or ((cp shr 6) and $3F));
      PByte(d + out_ + 2)^ := Byte($80 or (cp and $3F));
      out_ := out_ + 3;
    end
    else
    begin
      PByte(d + out_)^ := Byte($F0 or (cp shr 18));
      PByte(d + out_ + 1)^ := Byte($80 or ((cp shr 12) and $3F));
      PByte(d + out_ + 2)^ := Byte($80 or ((cp shr 6) and $3F));
      PByte(d + out_ + 3)^ := Byte($80 or (cp and $3F));
      out_ := out_ + 4;
    end;
  end;
  if out_ = 0 then
  begin
    PXXFree(Pointer(base));
    Result := nil;
    Exit;
  end;
  PWord(base + PXX_HDR_LEN)^ := out_;
  PByte(d + out_)^ := 0;
  PWord(base + PXX_HDR_META)^ := PXX_KIND_BYTESTR;
  Result := Pointer(d);
end;


end.
