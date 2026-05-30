unit streams;

{ Minimal read-only byte stream over an in-memory buffer. Part of the Phase 3
  streaming runtime: TReader walks a TPF0 binary form via one of these.
  Dialect notes: no `shl` (use *256 for little-endian assembly); strings are
  built with SetLength + indexed assignment, not `+`/AppendChar. }

interface

uses typinfo; { PUInt8 }

type
  TByteStream = class
  private
    FData: PUInt8;
    FSize: Integer;
    FPos:  Integer;
  public
    procedure Init(data: Pointer; size: Integer);
    function Eos: Boolean;
    function Position: Integer;
    function ReadByte: Integer;     { unsigned 0..255, advances }
    function ReadInt8: Integer;     { signed -128..127 }
    function ReadInt16: Integer;    { signed, little-endian }
    function ReadInt32: Integer;    { signed, little-endian }
    function ReadInt64: Int64;      { little-endian }
    function ReadStrLen(n: Integer): string; { n bytes as a string }
    function ReadShortStr: string;  { 1-byte length prefix + bytes }
    function ReadLStr: string;       { 4-byte (little-endian) length prefix + bytes }
  end;

implementation

procedure TByteStream.Init(data: Pointer; size: Integer);
begin
  FData := PUInt8(data);
  FSize := size;
  FPos  := 0;
end;

{ NOTE: methods assign Result, never the function name. Using the method name
  as the result variable (e.g. `ReadByte := ...`) currently miscompiles in a
  class method (the name resolves toward a self-call). Plain functions are fine. }

function TByteStream.Eos: Boolean;
begin
  Result := FPos >= FSize;
end;

function TByteStream.Position: Integer;
begin
  Result := FPos;
end;

function TByteStream.ReadByte: Integer;
var p: PUInt8;
begin
  { Copy the pointer field to a local before indexing: indexing a pointer-typed
    *class field* directly (FData[FPos]) currently miscompiles; a local pointer
    var indexes correctly. }
  p := FData;
  Result := p[FPos];
  FPos := FPos + 1;
end;

function TByteStream.ReadInt8: Integer;
var b: Integer;
begin
  b := ReadByte;
  if b >= 128 then b := b - 256;
  Result := b;
end;

function TByteStream.ReadInt16: Integer;
var b0, b1, v: Integer;
begin
  b0 := ReadByte;
  b1 := ReadByte;
  v := b0 + b1 * 256;
  if v >= 32768 then v := v - 65536;
  Result := v;
end;

function TByteStream.ReadInt32: Integer;
var b0, b1, b2, b3, v: Integer;
begin
  b0 := ReadByte;
  b1 := ReadByte;
  b2 := ReadByte;
  b3 := ReadByte;
  v := b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
  Result := v;
end;

function TByteStream.ReadInt64: Int64;
var lo, hi: Int64;
begin
  { Read two little-endian 32-bit halves; combine as unsigned low + high*2^32.
    ReadInt32 sign-extends, so mask the low half back to 32 bits. }
  lo := ReadInt32;
  lo := lo and $FFFFFFFF;
  hi := ReadInt32;
  Result := lo + hi * 4294967296;
end;

function TByteStream.ReadStrLen(n: Integer): string;
var i: Integer; s: string;
begin
  s := '';
  SetLength(s, n);
  for i := 1 to n do
    s[i] := Chr(ReadByte);
  Result := s;
end;

function TByteStream.ReadShortStr: string;
var n: Integer;
begin
  n := ReadByte;
  Result := ReadStrLen(n);
end;

function TByteStream.ReadLStr: string;
var n: Integer;
begin
  n := ReadInt32;
  Result := ReadStrLen(n);
end;

end.
