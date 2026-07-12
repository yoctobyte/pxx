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

function IfThen(Cond: Boolean; const ATrue, AFalse: AnsiString): AnsiString;
begin
  if Cond then Result := ATrue else Result := AFalse;
end;

end.
