{ SPDX-License-Identifier: Zlib }
unit strings;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ FPC-compatible `strings` unit: classic NUL-terminated PChar routines.
  Semantics follow FPC's strings.pp: nil-tolerant where FPC is (StrLen(nil)=0,
  StrPos with a nil argument returns nil); StrCopy/StrCat trust the caller's
  buffer like the originals. }

interface

function StrLen(P: PChar): Integer;
function StrEnd(P: PChar): PChar;
function StrCopy(Dest, Source: PChar): PChar;
function StrLCopy(Dest, Source: PChar; MaxLen: Integer): PChar;
function StrCat(Dest, Source: PChar): PChar;
function StrComp(Str1, Str2: PChar): Integer;
function StrLComp(Str1, Str2: PChar; L: Integer): Integer;
function StrIComp(Str1, Str2: PChar): Integer;
function StrScan(P: PChar; C: Char): PChar;
function StrRScan(P: PChar; C: Char): PChar;
function StrPos(Str1, Str2: PChar): PChar;
function StrPas(P: PChar): AnsiString;

{ ---- the half of the family that was missing ----

  Behaviour below is MEASURED against FPC 3.2.2 (syspch.inc / stringsi.inc plus
  a differential probe), not derived from the names. The traps:

  - StrNew('') and StrNew(nil) both return **nil** — FPC bails before it ever
    allocates, so `if StrNew(s) = nil then` fires on an empty source, not just
    on OOM. A caller that assumes "non-nil on success" is wrong for one input.
  - StrAlloc/StrDispose/StrBufSize are a matched set with a hidden 4-byte
    Cardinal size prefix. StrDispose ONLY works on a pointer from StrAlloc or
    StrNew; handing it a plain GetMem block corrupts the heap. StrBufSize(nil)
    is 0 and StrBufSize after StrAlloc(N) is N (the prefix is subtracted back
    out); after StrNew(p) it is StrLen(p)+1, not the buffer's capacity.
  - StrECopy returns a pointer to the terminating NUL of Dest, NOT Dest — it is
    the "append cursor" form, and the one member of the family whose return
    value differs from every other Str*Copy.
  - StrPLCopy's MaxLen counts CHARACTERS COPIED, not buffer size: it writes
    MaxLen+1 bytes at most, so the buffer must hold one more than MaxLen.
  - StrUpper/StrLower are ASCII-only ('a'..'z' / 'A'..'Z'); FPC does not
    consult a locale here, and neither do we.

  ONE DELIBERATE DIVERGENCE, and it is a safety fix — see
  `decide-stralloc-one-implementation-or-fpcs-two`.
  FPC ships TWO INCOMPATIBLE StrAllocs. Its `strings` unit allocates with a
  bare GetMem and no prefix (and has no StrBufSize at all); its `sysutils`
  allocates with the 4-byte prefix above. Because a later unit in a `uses`
  clause wins, `uses SysUtils, Strings` silently pairs the prefix-FREE
  allocator with the prefix-ASSUMING StrBufSize and StrDispose. Measured on
  fpc 3.2.2: StrBufSize then answers 4294967292, and StrDispose frees four
  bytes before the block — a real heap error that happens not to abort.

  We ship ONE implementation, here, and SysUtils forwards to it. Every program
  that uses only `strings` OR only `sysutils` — which is all of them, in
  practice — sees exactly FPC's behaviour. The only programs that can observe
  the difference are the ones FPC corrupts, and they get a correct answer
  instead. StrBufSize being reachable from `strings` is an addition, never a
  behaviour change. }
function StrECopy(Dest, Source: PChar): PChar;
function StrMove(Dest, Source: PChar; L: Integer): PChar;
function StrUpper(P: PChar): PChar;
function StrLower(P: PChar): PChar;
function StrPCopy(Dest: PChar; const Source: AnsiString): PChar;
function StrPLCopy(Dest: PChar; const Source: AnsiString; MaxLen: Integer): PChar;
function StrAlloc(Size: Integer): PChar;
function StrBufSize(Str: PChar): Integer;
function StrNew(P: PChar): PChar;
procedure StrDispose(Str: PChar);

implementation

function StrLen(P: PChar): Integer;
var n: Integer;
begin
  n := 0;
  if P <> nil then
    while P[n] <> #0 do Inc(n);
  Result := n;
end;

function StrEnd(P: PChar): PChar;
begin
  if P = nil then
    Result := nil
  else
    Result := @P[StrLen(P)];
end;

function StrCopy(Dest, Source: PChar): PChar;
var i: Integer;
begin
  i := 0;
  while Source[i] <> #0 do
  begin
    Dest[i] := Source[i];
    Inc(i);
  end;
  Dest[i] := #0;
  Result := Dest;
end;

function StrLCopy(Dest, Source: PChar; MaxLen: Integer): PChar;
var i: Integer;
begin
  i := 0;
  while (i < MaxLen) and (Source[i] <> #0) do
  begin
    Dest[i] := Source[i];
    Inc(i);
  end;
  Dest[i] := #0;
  Result := Dest;
end;

function StrCat(Dest, Source: PChar): PChar;
begin
  StrCopy(StrEnd(Dest), Source);
  Result := Dest;
end;

function StrComp(Str1, Str2: PChar): Integer;
var i: Integer;
begin
  i := 0;
  while (Str1[i] = Str2[i]) and (Str1[i] <> #0) do Inc(i);
  Result := Ord(Str1[i]) - Ord(Str2[i]);
end;

function StrLComp(Str1, Str2: PChar; L: Integer): Integer;
var i: Integer;
begin
  Result := 0;
  if L = 0 then Exit;
  i := 0;
  while (i < L - 1) and (Str1[i] = Str2[i]) and (Str1[i] <> #0) do Inc(i);
  Result := Ord(Str1[i]) - Ord(Str2[i]);
end;

function StrIComp(Str1, Str2: PChar): Integer;
var i: Integer; c1, c2: Char;
begin
  i := 0;
  repeat
    c1 := UpCase(Str1[i]);
    c2 := UpCase(Str2[i]);
    if (c1 <> c2) or (c1 = #0) then Break;
    Inc(i);
  until False;
  Result := Ord(c1) - Ord(c2);
end;

function StrScan(P: PChar; C: Char): PChar;
var i: Integer;
begin
  Result := nil;
  if P = nil then Exit;
  i := 0;
  repeat
    if P[i] = C then
    begin
      Result := @P[i];
      Exit;
    end;
    if P[i] = #0 then Exit;
    Inc(i);
  until False;
end;

function StrRScan(P: PChar; C: Char): PChar;
var i: Integer;
begin
  Result := nil;
  if P = nil then Exit;
  i := 0;
  repeat
    if P[i] = C then Result := @P[i];
    if P[i] = #0 then Exit;
    Inc(i);
  until False;
end;

function StrPos(Str1, Str2: PChar): PChar;
var i, j: Integer;
begin
  Result := nil;
  if (Str1 = nil) or (Str2 = nil) then Exit;
  if Str2[0] = #0 then
  begin
    Result := Str1;
    Exit;
  end;
  i := 0;
  while Str1[i] <> #0 do
  begin
    j := 0;
    while (Str2[j] <> #0) and (Str1[i + j] = Str2[j]) do Inc(j);
    if Str2[j] = #0 then
    begin
      Result := @Str1[i];
      Exit;
    end;
    Inc(i);
  end;
end;

function StrPas(P: PChar): AnsiString;
var i, n: Integer;
begin
  Result := '';
  if P = nil then Exit;
  n := StrLen(P);
  SetLength(Result, n);
  for i := 0 to n - 1 do
    Result[i + 1] := P[i];
end;

function StrMove(Dest, Source: PChar; L: Integer): PChar;
var i: Integer;
begin
  Result := Dest;
  if (L <= 0) or (Dest = Source) then Exit;
  { FPC's StrMove is System.Move, which is overlap-safe in BOTH directions.
    Copying forward when Dest is inside [Source, Source+L) would smear the
    source over itself, so pick the direction. }
  if PtrUInt(Dest) < PtrUInt(Source) then
    for i := 0 to L - 1 do Dest[i] := Source[i]
  else
    for i := L - 1 downto 0 do Dest[i] := Source[i];
end;

function StrECopy(Dest, Source: PChar): PChar;
var i: Integer;
begin
  i := 0;
  while Source[i] <> #0 do
  begin
    Dest[i] := Source[i];
    Inc(i);
  end;
  Dest[i] := #0;
  { the ONE Str*Copy that does not return Dest: the cursor at the new NUL,
    so `p := StrECopy(p, part)` chains appends without a StrEnd rescan. }
  Result := @Dest[i];
end;

function StrUpper(P: PChar): PChar;
var i: Integer;
begin
  Result := P;
  if P = nil then Exit;
  i := 0;
  while P[i] <> #0 do
  begin
    if (P[i] >= 'a') and (P[i] <= 'z') then
      P[i] := Chr(Ord(P[i]) - 32);
    Inc(i);
  end;
end;

function StrLower(P: PChar): PChar;
var i: Integer;
begin
  Result := P;
  if P = nil then Exit;
  i := 0;
  while P[i] <> #0 do
  begin
    if (P[i] >= 'A') and (P[i] <= 'Z') then
      P[i] := Chr(Ord(P[i]) + 32);
    Inc(i);
  end;
end;

function StrPCopy(Dest: PChar; const Source: AnsiString): PChar;
var i, n: Integer;
begin
  Result := Dest;
  if Dest = nil then Exit;
  n := Length(Source);
  for i := 1 to n do
    Dest[i - 1] := Source[i];
  Dest[n] := #0;
end;

function StrPLCopy(Dest: PChar; const Source: AnsiString; MaxLen: Integer): PChar;
var i, n: Integer;
begin
  Result := Dest;
  if Dest = nil then Exit;
  n := Length(Source);
  if n > MaxLen then n := MaxLen;
  if n < 0 then n := 0;
  for i := 1 to n do
    Dest[i - 1] := Source[i];
  Dest[n] := #0;   { FPC terminates even when it truncated }
end;

{ The size prefix StrAlloc/StrBufSize/StrDispose share. FPC stores a Cardinal
  (4 bytes) holding the TOTAL allocation, prefix included, and hands back the
  pointer just past it. We keep the same 4-byte width so the arithmetic — and
  any code that reasons about StrBufSize — matches FPC on every target. }
const
  StrAllocPrefix = 4;

type
  PStrAllocSize = ^LongWord;

function StrAlloc(Size: Integer): PChar;
var raw: Pointer; total: LongWord;
begin
  if Size < 0 then Size := 0;
  total := LongWord(Size) + StrAllocPrefix;
  raw := GetMem(Integer(total));
  if raw = nil then
  begin
    Result := nil;
    Exit;
  end;
  PStrAllocSize(raw)^ := total;
  Result := PChar(PtrUInt(raw) + StrAllocPrefix);
end;

function StrBufSize(Str: PChar): Integer;
begin
  if Str = nil then
    Result := 0
  else
    Result := Integer(PStrAllocSize(PtrUInt(Str) - StrAllocPrefix)^) - StrAllocPrefix;
end;

procedure StrDispose(Str: PChar);
begin
  { nil-tolerant, like FPC — StrDispose(StrNew('')) must not fault, and
    StrNew('') is nil. }
  if Str <> nil then
    FreeMem(Pointer(PtrUInt(Str) - StrAllocPrefix));
end;

function StrNew(P: PChar): PChar;
var n: Integer;
begin
  Result := nil;
  { FPC's early-out: nil source AND empty source both give nil. Not an
    allocation failure — measured. }
  if (P = nil) or (P[0] = #0) then Exit;
  n := StrLen(P) + 1;
  Result := StrAlloc(n);
  if Result <> nil then
    StrMove(Result, P, n);
end;

end.
