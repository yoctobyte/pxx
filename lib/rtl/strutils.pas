{ SPDX-License-Identifier: Zlib }
unit strutils;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
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

{ ---- the word / delimiter family (FPC StrUtils) ----

  TWO DIFFERENT SPLITTING MODELS live here, and picking the wrong one is the
  trap — they disagree on exactly the input real code has:

  - The WORD functions (WordCount / WordPosition / ExtractWord) treat a RUN of
    delimiters as one separator and skip leading/trailing ones. So
    WordCount('  a  b  ', [' ']) is 2, and there are no empty words, ever.
    This is the "split a command line" model.
  - ExtractDelimited counts FIELDS: every delimiter starts a new one, so
    ExtractDelimited(3, 'a,b,,c', [',']) is the EMPTY string and field 4 is
    'c'. This is the "parse a CSV row" model.

  Reaching for ExtractWord on CSV silently renumbers every field after the
  first empty one. Both measured against FPC 3.2.2.

  Index base: all of these are 1-based, and N=0 is not an error — it returns
  0 / '' (measured). ExtractWord past the end is '' too, not an exception. }
function WordCount(const S: AnsiString; const WordDelims: TSysCharSet): Integer;
function WordPosition(const N: Integer; const S: AnsiString; const WordDelims: TSysCharSet): Integer;
function ExtractWord(N: Integer; const S: AnsiString; const WordDelims: TSysCharSet): AnsiString;
function ExtractWordPos(N: Integer; const S: AnsiString; const WordDelims: TSysCharSet; var Pos: Integer): AnsiString;
function ExtractDelimited(N: Integer; const S: AnsiString; const Delims: TSysCharSet): AnsiString;
function ExtractSubstr(const S: AnsiString; var Pos: Integer; const Delims: TSysCharSet): AnsiString;

{ FPC's SplitString — the `'a,b,,c'.Split(',')` idiom under its function name.
  Field semantics, NOT word semantics: EVERY character of Delimiters is a
  separator, empty fields are KEPT, and the result therefore has
  (number of delimiters found + 1) entries. Measured against FPC 3.2.2:

    SplitString('a,b,,c', ',')  ->  4 items: 'a' 'b' '' 'c'
    SplitString(',a,',     ',')  ->  3 items: ''  'a' ''
    SplitString('',        ',')  ->  1 item : ''            <- not zero
    SplitString('abc',     '')   ->  1 item : 'abc'
    SplitString('a1b2c',   '12') ->  1 item : 'a1b2c'       <- see below

  The last two are the ones that catch people. The second argument is a SET of
  single-character delimiters, so '12' means "split on '1' or on '2'" — but FPC
  3.2.2's SplitString routes through TStringHelper.Split(array of string),
  which treats the argument as ONE multi-character separator, so 'a1b2c' split
  on '12' comes back whole. We reproduce FPC's observed behaviour rather than
  the documented intent, because agreeing with the oracle is the contract; a
  caller who wants per-character splitting has ExtractDelimited. }
function SplitString(const S, Delimiters: AnsiString): TStringArray;

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

{ ---- word family: a RUN of delimiters is one separator ---- }

function WordCount(const S: AnsiString; const WordDelims: TSysCharSet): Integer;
var i, n: Integer;
begin
  Result := 0;
  n := Length(S);
  i := 1;
  while i <= n do
  begin
    while (i <= n) and (S[i] in WordDelims) do Inc(i);
    if i <= n then Inc(Result);
    while (i <= n) and not (S[i] in WordDelims) do Inc(i);
  end;
end;

function WordPosition(const N: Integer; const S: AnsiString; const WordDelims: TSysCharSet): Integer;
var i, n, count: Integer;
begin
  Result := 0;
  count := 0;
  n := Length(S);
  i := 1;
  { N <= 0 never matches, so the loop exits with 0 — FPC's answer, not an error }
  while (i <= n) and (count <> N) do
  begin
    while (i <= n) and (S[i] in WordDelims) do Inc(i);
    if i <= n then Inc(count);
    if count <> N then
      while (i <= n) and not (S[i] in WordDelims) do Inc(i)
    else
      Result := i;
  end;
end;

function ExtractWordPos(N: Integer; const S: AnsiString; const WordDelims: TSysCharSet; var Pos: Integer): AnsiString;
var i, j, n: Integer;
begin
  j := 0;
  i := WordPosition(N, S, WordDelims);
  Pos := i;
  if i <> 0 then
  begin
    j := i;
    n := Length(S);
    while (j <= n) and not (S[j] in WordDelims) do Inc(j);
  end;
  { i = 0 leaves j = 0 too, so the length is 0 and the result is '' }
  Result := Copy(S, i, j - i);
end;

function ExtractWord(N: Integer; const S: AnsiString; const WordDelims: TSysCharSet): AnsiString;
var p: Integer;
begin
  Result := ExtractWordPos(N, S, WordDelims, p);
end;

{ ---- delimiter family: every delimiter starts a new FIELD ---- }

function ExtractDelimited(N: Integer; const S: AnsiString; const Delims: TSysCharSet): AnsiString;
var w, i, n: Integer;
begin
  Result := '';
  w := 0;
  i := 1;
  n := Length(S);
  while (i <= n) and (w <> N) do
  begin
    if S[i] in Delims then
      Inc(w)
    else if (N - 1) = w then
      Result := Result + S[i];
    Inc(i);
  end;
end;

function ExtractSubstr(const S: AnsiString; var Pos: Integer; const Delims: TSysCharSet): AnsiString;
var i, n: Integer;
begin
  n := Length(S);
  i := Pos;
  while (i <= n) and not (S[i] in Delims) do Inc(i);
  Result := Copy(S, Pos, i - Pos);
  { WORD semantics on the advance, not field semantics — measured: FPC skips the
    whole RUN of delimiters, so 'a,b,,c' walked with this yields a, b, c, ''
    and never the empty field between the two commas. Naming it "Substr" while
    ExtractDelimited over the same string yields a, b, '', c is exactly the
    kind of near-miss that reads as a typo and is not one. }
  while (i <= n) and (S[i] in Delims) do Inc(i);
  Pos := i;
end;

function SplitString(const S, Delimiters: AnsiString): TStringArray;
var
  count, start, hit, dlen: Integer;
begin
  dlen := Length(Delimiters);
  if (dlen = 0) or (Length(S) = 0) then
  begin
    { both degenerate cases give ONE element — the whole (possibly empty)
      string — not zero. Measured; a caller that loops `for i := 0 to High(r)`
      sees one pass, which is what makes `SplitString('', ',')` safe. }
    SetLength(Result, 1);
    Result[0] := S;
    Exit;
  end;
  { Delimiters is one MULTI-CHARACTER separator here, not a character set —
    see the interface note; this mirrors FPC 3.2.2's TStringHelper.Split. }
  count := 0;
  SetLength(Result, 0);
  start := 1;
  repeat
    hit := PosEx(Delimiters, S, start);
    if hit = 0 then Break;
    Inc(count);
    SetLength(Result, count);
    Result[count - 1] := Copy(S, start, hit - start);
    start := hit + dlen;
  until False;
  Inc(count);
  SetLength(Result, count);
  Result[count - 1] := Copy(S, start, Length(S) - start + 1);
end;

end.
