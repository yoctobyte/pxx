{ SPDX-License-Identifier: Zlib }
unit io;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Python's `io` for the Nil-Python frontend — the in-memory buffers.

  Named `io` so `from io import BytesIO` needs no frontend change (NilPy maps
  `import X` onto the unit resolver; see devdocs/dev/python-compat-tiers.md).

  THE SUBSET:

    io.BytesIO([initial])  -> write / read / getvalue / seek / tell / close,
                              plus `.closed`
    io.StringIO([initial]) -> the same, over text

  Both are what a program reaches for when a library wants a FILE and it has
  (or wants) bytes in memory — `img.save(buf, format="PNG")` then
  `buf.getvalue()`. NOT here: the real file objects (`io.open`, TextIOWrapper,
  BufferedReader), line iteration, `readline`, and the encoding machinery.

  Bytes are held as an AnsiString, which in this dialect is a length-carrying
  byte string, so a NUL is data like any other byte. }

interface

uses pylib;

type
  BytesIO = class
  public
    buf: AnsiString;
    pos: Integer;                  { 0-based, as Python's tell() reports }
    closed: Boolean;
    { `BytesIO()` or `BytesIO(data)` — the initial contents, positioned at 0. }
    constructor Create(const initial: Variant = 0);
    { Append at the current position and advance it; returns the count written,
      as Python's does. }
    function write(const data: Variant): Integer;
    { The whole buffer regardless of position, which is what getvalue means. }
    function getvalue: AnsiString;
    { `read()` = the rest; `read(n)` = at most n bytes. }
    function read(n: Integer = -1): AnsiString;
    function seek(offset: Integer; whence: Integer = 0): Integer;
    function tell: Integer;
    procedure close;
  end;

  StringIO = class(BytesIO)
  end;

implementation

constructor BytesIO.Create(const initial: Variant);
begin
  if pyvartag(initial) = 0 then buf := '' else buf := pystr_of(initial);
  pos := 0;
  closed := False;
end;

function BytesIO.write(const data: Variant): Integer;
var s: AnsiString;
begin
  s := pystr_of(data);
  { A write past the end extends the buffer; a write in the middle overwrites,
    which is what a seek-then-write means. }
  if pos = Length(buf) then
    buf := buf + s
  else
  begin
    while Length(buf) < pos do buf := buf + #0;
    buf := Copy(buf, 1, pos) + s + Copy(buf, pos + Length(s) + 1, Length(buf));
  end;
  pos := pos + Length(s);
  Result := Length(s);
end;

function BytesIO.getvalue: AnsiString;
begin
  Result := buf;
end;

function BytesIO.read(n: Integer): AnsiString;
var take: Integer;
begin
  take := Length(buf) - pos;
  if (n >= 0) and (n < take) then take := n;
  if take <= 0 then begin Result := ''; Exit; end;
  Result := Copy(buf, pos + 1, take);
  pos := pos + take;
end;

function BytesIO.seek(offset, whence: Integer): Integer;
begin
  case whence of
    1: pos := pos + offset;             { SEEK_CUR }
    2: pos := Length(buf) + offset;     { SEEK_END }
  else
    pos := offset;                      { SEEK_SET }
  end;
  if pos < 0 then pos := 0;
  Result := pos;
end;

function BytesIO.tell: Integer;
begin
  Result := pos;
end;

procedure BytesIO.close;
begin
  closed := True;
end;

end.
