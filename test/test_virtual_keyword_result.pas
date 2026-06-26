program test_virtual_keyword_result;

{ Bare own-name result of a VIRTUAL method whose name is an intrinsic keyword
  (Read/Write/Readln/Writeln) must return the assigned value, like any other
  function-name-as-Result. Previously miscompiled to garbage (a code address) for
  the keyword-name + virtual combination; rejected by a parser guard until the
  codegen path was confirmed correct. See bug-virtual-keyword-name-result. }

type
  TStream = class
    function Read(var Buffer; Count: Integer): Integer; virtual;
    function Write(var Buffer; Count: Integer): Integer; virtual;
  end;
  TDerived = class(TStream)
    function Read(var Buffer; Count: Integer): Integer; override;
  end;

function TStream.Read(var Buffer; Count: Integer): Integer;
begin Read := Count; end;

function TStream.Write(var Buffer; Count: Integer): Integer;
begin Write := Count + 1; end;

function TDerived.Read(var Buffer; Count: Integer): Integer;
begin Read := Count * 2; end;

var s: TStream; d: TDerived; buf: Integer;
begin
  s := TStream.Create; d := TDerived.Create; buf := 0;
  writeln(s.Read(buf, 5));    { 5 }
  writeln(s.Write(buf, 5));   { 6 }
  writeln(d.Read(buf, 5));    { 10 }
  s := d;
  writeln(s.Read(buf, 5));    { 10 — virtual dispatch }
end.
