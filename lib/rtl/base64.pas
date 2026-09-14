{ SPDX-License-Identifier: Zlib }
unit base64;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Standard RFC 4648 Base64 (alphabet A-Za-z0-9+/, '=' padding).

  Encode/decode over raw bytes (TByteArray) plus AnsiString convenience wrappers.
  Decode is lenient about ASCII whitespace (skipped) and rejects other invalid
  characters. Used by the net lib for HTTP Basic auth, data URIs, etc. }

interface

{ pylib for the Python spellings below: `base64.b64encode(b)` takes BYTES, and
  reading a TPyBytes needs the NilPy runtime. Ruled in by
  decide-pcl-may-use-pylib — a shim's job is to accept what the application
  already writes. Pascal callers of Base64Encode never touch it.
  pymarshal carries the bytes<->TByteArray pair that used to be open-coded here. }
uses hashing, pylib, pymarshal;   { TByteArray }

function Base64Encode(const data: TByteArray): AnsiString;
function Base64EncodeStr(const s: AnsiString): AnsiString;
function Base64Decode(const s: AnsiString; var data: TByteArray): Boolean;
function Base64DecodeStr(const s: AnsiString): AnsiString;

{ Python's `base64` module surface, so `import base64` resolves to this unit and
  `base64.b64encode(data)` is the call an application writes.

  BOTH RETURN `bytes`, AS CPython DOES. They returned AnsiString until
  2026-09-14, with a comment here arguing that the value "is invariably handed
  straight to something that wants text". That was true of the two callers in
  this tree and false of Python as it is written: `b64encode(raw).decode()` and
  `b"Basic " + b64encode(cred)` are the idiomatic spellings and both failed,
  the first with no `decode` on a str and the second on str + bytes.

  NO EXISTING CALLER CHANGES BEHAVIOUR — measured before the flip, not assumed:
  a grep of every .py/.npy/.pas/.inc in the tree found no consumer of either
  name outside this unit, so the "produce the list first" the ticket asked for
  is an empty list.

  WHY NO TEST CAUGHT IT, because it is the cheapest instance of the
  assertion-class rule in CLAUDE.md: the bytes were already identical and only
  the `repr` differed, so every value comparison, every round trip through this
  module and every print agreed with CPython. The instrument that sees it is a
  diff of the two runtimes' repr.

  The Pascal surface above is untouched: Base64Encode/Base64EncodeStr keep
  returning AnsiString, which is what a Pascal caller wants.
  bug-b-base64-b64encode-returns-a-string-where-cpython-returns-bytes }
function b64encode(const data: Variant): TPyBytes;
function b64decode(const data: Variant): TPyBytes;

implementation

function b64encode(const data: Variant): TPyBytes;
var raw: TByteArray;
begin
  { THE INBOUND TEST MOVED AND GOT SAFER. It read `pyvartag(data) = 7` and then
    cast unconditionally, so a caller passing a list would have had a length
    read off a TPyList; pymarshal.PyToBytes asks `is TPyBytes` and falls through
    to the string path otherwise. Same accepted spellings, one fewer way to be
    wrong, and zlib.pas's copy of this is now the same code. }
  raw := PyToBytes(data);
  b64encode := StrToPy(Base64Encode(raw));
end;

function b64decode(const data: Variant): TPyBytes;
begin
  { PyToText and not pystr_of. CPython's b64decode accepts str AND bytes, and
    the bytes arm was broken here in a way no caller could reach until
    b64encode above started returning bytes: pystr_of on a TPyBytes does not
    render the bytes as characters, so the decoder saw no alphabet at all and
    returned empty rather than wrong. The round-trip idiom
    `b64decode(b64encode(x)) == x` was False against CPython's True and is the
    row that found it. }
  b64decode := StrToPy(Base64DecodeStr(PyToText(data)));
end;

const
  ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function Base64Encode(const data: TByteArray): AnsiString;
var i, n, b0, b1, b2: Integer; enc: AnsiString;
begin
  enc := '';
  n := Length(data);
  i := 0;
  while i + 3 <= n do
  begin
    b0 := data[i]; b1 := data[i + 1]; b2 := data[i + 2];
    enc := enc + ALPHABET[(b0 shr 2) + 1]
               + ALPHABET[(((b0 and 3) shl 4) or (b1 shr 4)) + 1]
               + ALPHABET[(((b1 and 15) shl 2) or (b2 shr 6)) + 1]
               + ALPHABET[(b2 and 63) + 1];
    i := i + 3;
  end;
  if n - i = 1 then
  begin
    b0 := data[i];
    enc := enc + ALPHABET[(b0 shr 2) + 1]
               + ALPHABET[((b0 and 3) shl 4) + 1] + '==';
  end
  else if n - i = 2 then
  begin
    b0 := data[i]; b1 := data[i + 1];
    enc := enc + ALPHABET[(b0 shr 2) + 1]
               + ALPHABET[(((b0 and 3) shl 4) or (b1 shr 4)) + 1]
               + ALPHABET[((b1 and 15) shl 2) + 1] + '=';
  end;
  Result := enc;
end;

function Base64EncodeStr(const s: AnsiString): AnsiString;
var data: TByteArray; i: Integer;
begin
  SetLength(data, Length(s));
  for i := 1 to Length(s) do data[i - 1] := Byte(s[i]);
  Result := Base64Encode(data);
end;

{ Map a base64 char to its 0..63 value, -1 if invalid, -2 if skippable space. }
function B64Val(c: AnsiChar): Integer;
begin
  if (c >= 'A') and (c <= 'Z') then Result := Ord(c) - Ord('A')
  else if (c >= 'a') and (c <= 'z') then Result := Ord(c) - Ord('a') + 26
  else if (c >= '0') and (c <= '9') then Result := Ord(c) - Ord('0') + 52
  else if c = '+' then Result := 62
  else if c = '/' then Result := 63
  else if (c = ' ') or (c = #9) or (c = #10) or (c = #13) then Result := -2
  else Result := -1;
end;

function Base64Decode(const s: AnsiString; var data: TByteArray): Boolean;
var i, v, bits, acc, outLen: Integer; pad: Integer;
begin
  Result := False;
  SetLength(data, (Length(s) div 4 + 1) * 3);   { upper bound }
  outLen := 0; bits := 0; acc := 0; pad := 0;
  for i := 1 to Length(s) do
  begin
    if s[i] = '=' then
      Inc(pad)
    else
    begin
      v := B64Val(s[i]);
      if v = -1 then begin SetLength(data, 0); Exit; end;   { invalid char }
      if v >= 0 then                                        { v = -2 → skip space }
      begin
        if pad > 0 then begin SetLength(data, 0); Exit; end; { data after padding }
        acc := (acc shl 6) or v;
        bits := bits + 6;
        if bits >= 8 then
        begin
          bits := bits - 8;
          data[outLen] := Byte((acc shr bits) and $FF);
          Inc(outLen);
        end;
      end;
    end;
  end;
  if (pad > 2) then begin SetLength(data, 0); Exit; end;
  SetLength(data, outLen);
  Result := True;
end;

function Base64DecodeStr(const s: AnsiString): AnsiString;
var data: TByteArray; i: Integer;
begin
  Result := '';
  if not Base64Decode(s, data) then Exit;
  SetLength(Result, Length(data));
  for i := 0 to Length(data) - 1 do Result[i + 1] := AnsiChar(data[i]);
end;

end.
