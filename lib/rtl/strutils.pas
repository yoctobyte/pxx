{ SPDX-License-Identifier: Zlib }
unit strutils;
{ Minimal FPC-compatible StrUtils shim (feature-synapse-compile-check —
  ftpsend pulls it). Grown on demand. }

interface

uses sysutils;

function LeftStr(const S: AnsiString; Count: Integer): AnsiString;
function RightStr(const S: AnsiString; Count: Integer): AnsiString;
function MidStr(const S: AnsiString; Start, Count: Integer): AnsiString;
function DupeString(const S: AnsiString; Count: Integer): AnsiString;
function PosEx(const SubStr, S: AnsiString; Offset: Integer): Integer;
function ReverseString(const S: AnsiString): AnsiString;
function IfThen(Cond: Boolean; const ATrue, AFalse: AnsiString): AnsiString;

{ ---- the Ansi* predicate family (FPC/Delphi StrUtils) ----

  Thin wrappers over Pos / CompareText / Copy / StringReplace, but the CONTRACTS
  are not guessable and are measured against FPC 3.2.2 rather than derived:

  - ARGUMENT ORDER on Starts/Ends is (NEEDLE, haystack) — the opposite of the
    reading order most people assume, and the opposite of Contains, which is
    (haystack, needle). Getting it backwards type-checks and silently answers
    the wrong question.
  - AnsiContainsStr(s, '') is **FALSE**, because FPC's Pos('', s) is 0 — where
    AnsiStartsStr('', s) and AnsiEndsStr('', s) are both **TRUE**. So the empty
    needle is not handled uniformly across the family, and it is not an
    oversight to be smoothed over: it is what real code sees.
  - AnsiIndexStr returns **-1** when absent, not 0 — it is an array index, not
    a Pos.
  - AddChar/AddCharR do NOT truncate: a string already longer than the target
    width comes back unchanged.
  - Every ...Str is case-SENSITIVE and its ...Text twin is case-INSENSITIVE.
    ([[feature-lib-strutils-ansi-predicate-family]]) }
function AnsiContainsStr(const AText, ASubText: AnsiString): Boolean;
function AnsiContainsText(const AText, ASubText: AnsiString): Boolean;
function AnsiStartsStr(const ASubText, AText: AnsiString): Boolean;
function AnsiStartsText(const ASubText, AText: AnsiString): Boolean;
function AnsiEndsStr(const ASubText, AText: AnsiString): Boolean;
function AnsiEndsText(const ASubText, AText: AnsiString): Boolean;
function AnsiIndexStr(const AText: AnsiString; const AValues: array of AnsiString): Integer;
function AnsiIndexText(const AText: AnsiString; const AValues: array of AnsiString): Integer;
function AnsiReplaceStr(const AText, AFromText, AToText: AnsiString): AnsiString;
function AnsiReplaceText(const AText, AFromText, AToText: AnsiString): AnsiString;
function AddChar(AChar: Char; const S: AnsiString; N: Integer): AnsiString;
function AddCharR(AChar: Char; const S: AnsiString; N: Integer): AnsiString;

implementation

function LeftStr(const S: AnsiString; Count: Integer): AnsiString;
begin
  if Count < 0 then Count := 0;
  if Count > Length(S) then Count := Length(S);
  Result := Copy(S, 1, Count);
end;

function RightStr(const S: AnsiString; Count: Integer): AnsiString;
begin
  if Count < 0 then Count := 0;
  if Count > Length(S) then Count := Length(S);
  Result := Copy(S, Length(S) - Count + 1, Count);
end;

function MidStr(const S: AnsiString; Start, Count: Integer): AnsiString;
begin
  Result := Copy(S, Start, Count);
end;

function DupeString(const S: AnsiString; Count: Integer): AnsiString;
var i: Integer;
begin
  Result := '';
  for i := 1 to Count do
    Result := Result + S;
end;

function PosEx(const SubStr, S: AnsiString; Offset: Integer): Integer;
var i, j: Integer; ok: Boolean;
begin
  Result := 0;
  if (Length(SubStr) = 0) or (Offset < 1) then Exit;
  for i := Offset to Length(S) - Length(SubStr) + 1 do
  begin
    ok := True;
    for j := 1 to Length(SubStr) do
      if S[i + j - 1] <> SubStr[j] then
      begin
        ok := False;
        Break;
      end;
    if ok then
    begin
      Result := i;
      Exit;
    end;
  end;
end;

function ReverseString(const S: AnsiString): AnsiString;
var i: Integer;
begin
  SetLength(Result, Length(S));
  for i := 1 to Length(S) do
    Result[i] := S[Length(S) - i + 1];
end;

function AnsiContainsStr(const AText, ASubText: AnsiString): Boolean;
begin
  { Pos('', s) is 0 in FPC, so the empty needle is FALSE here — deliberately
    unlike Starts/Ends below. Measured, not chosen. }
  Result := Pos(ASubText, AText) > 0;
end;

function AnsiContainsText(const AText, ASubText: AnsiString): Boolean;
begin
  Result := Pos(UpperCase(ASubText), UpperCase(AText)) > 0;
end;

function AnsiStartsStr(const ASubText, AText: AnsiString): Boolean;
begin
  { needle first — see the interface note }
  Result := (Length(ASubText) <= Length(AText)) and
            (Copy(AText, 1, Length(ASubText)) = ASubText);
end;

function AnsiStartsText(const ASubText, AText: AnsiString): Boolean;
begin
  Result := (Length(ASubText) <= Length(AText)) and
            (CompareText(Copy(AText, 1, Length(ASubText)), ASubText) = 0);
end;

function AnsiEndsStr(const ASubText, AText: AnsiString): Boolean;
begin
  Result := (Length(ASubText) <= Length(AText)) and
            (Copy(AText, Length(AText) - Length(ASubText) + 1,
                  Length(ASubText)) = ASubText);
end;

function AnsiEndsText(const ASubText, AText: AnsiString): Boolean;
begin
  Result := (Length(ASubText) <= Length(AText)) and
            (CompareText(Copy(AText, Length(AText) - Length(ASubText) + 1,
                              Length(ASubText)), ASubText) = 0);
end;

function AnsiIndexStr(const AText: AnsiString; const AValues: array of AnsiString): Integer;
var i: Integer;
begin
  for i := 0 to High(AValues) do
    if AValues[i] = AText then begin Result := i; Exit; end;
  Result := -1;      { an array index, so absent is -1 and not 0 }
end;

function AnsiIndexText(const AText: AnsiString; const AValues: array of AnsiString): Integer;
var i: Integer;
begin
  for i := 0 to High(AValues) do
    if CompareText(AValues[i], AText) = 0 then begin Result := i; Exit; end;
  Result := -1;
end;

function AnsiReplaceStr(const AText, AFromText, AToText: AnsiString): AnsiString;
begin
  Result := StringReplace(AText, AFromText, AToText, [rfReplaceAll]);
end;

function AnsiReplaceText(const AText, AFromText, AToText: AnsiString): AnsiString;
begin
  Result := StringReplace(AText, AFromText, AToText, [rfReplaceAll, rfIgnoreCase]);
end;

function AddChar(AChar: Char; const S: AnsiString; N: Integer): AnsiString;
begin
  { pads on the LEFT to width N, and never truncates }
  Result := S;
  while Length(Result) < N do Result := AChar + Result;
end;

function AddCharR(AChar: Char; const S: AnsiString; N: Integer): AnsiString;
begin
  Result := S;
  while Length(Result) < N do Result := Result + AChar;
end;

function IfThen(Cond: Boolean; const ATrue, AFalse: AnsiString): AnsiString;
begin
  if Cond then Result := ATrue else Result := AFalse;
end;

end.
