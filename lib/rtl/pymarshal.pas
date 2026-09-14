{ SPDX-License-Identifier: Zlib }
unit pymarshal;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ The one conversion between a NilPy value and hashing.TByteArray.

  WHY THIS UNIT EXISTS, AND IT IS THE THIRD-COPY RULE RATHER THAN TIDINESS.
  A lib/rtl unit that carries a Python surface beside its Pascal one has to
  cross the same boundary every time: a Python caller hands over `bytes` (or,
  because NilPy is upward compatible, a str), the Pascal side wants a
  TByteArray, and the result has to go back as real `bytes`. zlib.pas wrote
  that pair privately, base64.pas open-coded the inbound half inline in
  b64encode, and pil.pas would have been the third. normalise-dont-special-case
  says the second is a smell and the third is a design flaw, and the arithmetic
  is the kind that goes subtly wrong per copy -- base64's inline version read
  `pyvartag(data) = 7` where zlib's used `pyvar_is_objtag` plus an `is TPyBytes`
  check, and only the second is safe when the caller passes a list.

  Pascal-only consumers must NOT use this unit: it pulls in pylib, and hashing
  is under the crypto/TLS stack where that dependency would be wrong. That is
  also why the pair does not live in hashing.pas beside TByteArray itself. }

interface

uses hashing, pylib;   { TByteArray; TPyBytes/Variant }

{ A NilPy `bytes`, `bytearray` or `str` as bytes.

  ACCEPTING A str IS DELIBERATE AND CPython REFUSES IT. NilPy is upward
  compatible with CPython in one direction only, and accepting what CPython
  rejects is a feature, not laxity (nilpy-semantics-divergences.md).

  The object test is `is TPyBytes` and not an unchecked cast of anything
  obj-tagged, which is what makes `zlib.crc32(some_list)` fall through to the
  string path instead of reading a length off a TPyList. }
function PyToBytes(const data: Variant): TByteArray;

{ Back the other way, as real `bytes` rather than an AnsiString.

  THE RETURN TYPE IS THE WHOLE POINT. A surface that hands back AnsiString
  where CPython hands back bytes passes every value assertion and every print,
  and breaks the first program that writes the idiomatic `.decode()` or
  concatenates the result with other bytes -- the type is wrong where every
  byte is right, which no expect_same row can see.
  bug-b-base64-b64encode-returns-a-string-where-cpython-returns-bytes }
function BytesToPy(const a: TByteArray): TPyBytes;

{ A NilPy `bytes`, `bytearray` or `str` as TEXT -- the mirror of PyToBytes for a
  Pascal half that takes an AnsiString.

  NOT pystr_of, WHICH IS WHAT MAKES THIS WORTH A FUNCTION. pystr_of on a
  TPyBytes does not hand back the bytes as characters, and the failure is
  silent and total rather than partial: measured 2026-09-14,
  `base64.b64decode(base64.b64encode(b"hi"))` answered `b''` against CPython's
  `b'hi'`, because b64decode fed pystr_of's rendering to a decoder that found
  no alphabet characters in it and returned empty. A str argument through the
  same path was correct throughout, which is why the bug was invisible: every
  caller in the tree passed a str, and nothing in the tree produced bytes to
  pass until b64encode started returning them. }
function PyToText(const data: Variant): AnsiString;

{ An AnsiString as `bytes`, for a surface whose Pascal half already produces
  text. Same contract as BytesToPy; saves the caller a TByteArray it does not
  otherwise want. }
function StrToPy(const s: AnsiString): TPyBytes;

{ CPython's "argument omitted" for a `const x: Variant = <default>` parameter.

  LOAD-BEARING, NOT DEFENSIVE: measured, the declared default is not applied on
  the NilPy call path -- an omitted argument arrives as pynone (pyvartag 0,
  pyvar_to_int 0) and NOT as the declared value. The declaration keeps its
  default anyway, because that is the correct Pascal signature and this test is
  harmless once the frontend honours it.
  bug-n-a-variant-default-parameter-arrives-as-none-from-nilpy-while-typed-defaults-apply

  AND A DEFAULT OF ZERO CANNOT SEE THE BUG, which is why this is worth a named
  function rather than an inline `if`: zlib.crc32's CPython default is 0, the
  exact value an unsupplied argument already reads as, so all four crc32 rows
  matched the oracle while the mechanism was broken. adler32's default of 1 is
  what exposed it. Route every such parameter through here, including the ones
  whose default is 0, so the next one added does not depend on its default
  happening to differ from the failure value. }
function PyArgInt(const value: Variant; whenAbsent: Int64): Int64;

implementation

function PyToBytes(const data: Variant): TByteArray;
var o: TObject; by: TPyBytes; raw: AnsiString; i: Integer;
begin
  o := nil;
  if pyvar_is_objtag(data) then o := TObject(pyvarobj(data));
  if (o <> nil) and (o is TPyBytes) then
  begin
    by := TPyBytes(o);
    SetLength(Result, by.count);
    for i := 0 to by.count - 1 do
      Result[i] := by.at(i);
    Exit;
  end;
  raw := pystr_of(data);
  SetLength(Result, Length(raw));
  for i := 1 to Length(raw) do
    Result[i - 1] := Byte(raw[i]);
end;

function BytesToPy(const a: TByteArray): TPyBytes;
var i: Integer;
begin
  Result := TPyBytes.Create(Length(a));
  for i := 0 to Length(a) - 1 do
    Result.put(i, a[i]);
end;

function PyToText(const data: Variant): AnsiString;
var b: TByteArray; i: Integer;
begin
  b := PyToBytes(data);
  SetLength(Result, Length(b));
  for i := 0 to Length(b) - 1 do
    Result[i + 1] := Chr(b[i]);
end;

function StrToPy(const s: AnsiString): TPyBytes;
var i: Integer;
begin
  Result := TPyBytes.Create(Length(s));
  for i := 1 to Length(s) do
    Result.put(i - 1, Byte(s[i]));
end;

function PyArgInt(const value: Variant; whenAbsent: Int64): Int64;
begin
  if value = pynone then
    Result := whenAbsent
  else
    Result := pyvar_to_int(value);
end;

end.
