{ SPDX-License-Identifier: Zlib }
unit strings;
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

end.
