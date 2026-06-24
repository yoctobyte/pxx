program test_stream_methods;
{ Regression: Read/Write usable as method names (bug-read-write-reserved-as-
  method-names) + untyped var/const params in methods (bug-untyped-params-in-
  methods). The TStream surface that needs both. Result is assigned via `Result`
  (the bare-own-name result form for intrinsic-named methods is a separate
  deliberate error — bug-virtual-keyword-name-result). }
type
  TStream = class
    Pos: Integer;
    Data: array of Byte;
    function Read(var Buffer; Count: Integer): Integer; virtual;
    function Write(const Buffer; Count: Integer): Integer; virtual;
  end;

function TStream.Read(var Buffer; Count: Integer): Integer;
var p: PByte; i: Integer;
begin
  p := PByte(@Buffer);
  for i := 0 to Count - 1 do p[i] := Data[Pos + i];
  Pos := Pos + Count;
  Result := Count;
end;

function TStream.Write(const Buffer; Count: Integer): Integer;
var p: PByte; i: Integer;
begin
  p := PByte(@Buffer);
  for i := 0 to Count - 1 do Data[Pos + i] := p[i];
  Pos := Pos + Count;
  Result := Count;
end;

var
  s: TStream;
  buf: array[0..7] of Byte;
  nw, nr: Integer;
begin
  s := TStream.Create;
  SetLength(s.Data, 16);
  buf[0] := 65; buf[1] := 66; buf[2] := 67;
  s.Pos := 0; nw := s.Write(buf[0], 3);       { virtual Write, untyped const param }
  buf[0] := 0; buf[1] := 0; buf[2] := 0;
  s.Pos := 0; nr := s.Read(buf[0], 3);        { virtual Read, untyped var param }
  writeln(buf[0], ' ', buf[1], ' ', buf[2]);  { 65 66 67 }
  writeln(nw, ' ', nr);                        { 3 3 }
end.
