program TestInterfaceArcExc;
{ COM/ARC interfaces — result transfer, reassignment, and exception-unwind
  release. The exception-unwind finalisation rides the x86-64 proc cleanup frame,
  so this test is x86-64 only (wired into test-core, not the cross suites). }
{$interfaces com}
type
  IInterface = interface
    function QueryInterface(iid: Integer): Integer;
    function _AddRef: Integer;
    function _Release: Integer;
  end;
  IFoo = interface
    procedure Hello;
  end;
  TInterfacedObject = class
    FRefCount: Integer;
    function QueryInterface(iid: Integer): Integer;
    function _AddRef: Integer;
    function _Release: Integer;
  end;
  TFoo = class(TInterfacedObject, IFoo)
    procedure Hello;
  end;

var
  Freed, Created: Integer;

function TInterfacedObject.QueryInterface(iid: Integer): Integer;
begin Result := -1; end;
function TInterfacedObject._AddRef: Integer;
begin Self.FRefCount := Self.FRefCount + 1; Result := Self.FRefCount; end;
function TInterfacedObject._Release: Integer;
begin
  Self.FRefCount := Self.FRefCount - 1;
  Result := Self.FRefCount;
  if Self.FRefCount = 0 then begin Freed := Freed + 1; FreeMem(Pointer(Self)); end;
end;
procedure TFoo.Hello; begin end;

function MakeFoo: IFoo;
begin
  Result := TFoo.Create;   { result transfer: AddRef here, no release at callee exit }
  Created := Created + 1;
end;

{ Result assigned into an already-populated var: the old reference is released. }
procedure RunReassign;
var f: IFoo;
begin
  f := MakeFoo;            { object A }
  f := MakeFoo;            { object B; A released here }
end;                       { B released at scope exit }

{ Exception unwind: the interface local is released as the frame unwinds. }
procedure RunExc;
var f: IFoo;
begin
  f := TFoo.Create;
  raise 12;
end;

begin
  Freed := 0; Created := 0;
  RunReassign;
  writeln('reassign created=', Created, ' freed=', Freed);   { 2 2 }
  try
    RunExc;
  except
    writeln('caught');
  end;
  writeln('unwind freed=', Freed);                            { 3 }
end.
