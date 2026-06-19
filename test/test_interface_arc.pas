program TestInterfaceArc;
{ COM/ARC interfaces ({$interfaces com}): a TInterfacedObject-derived class
  managed purely through interface variables (no manual Free) must be freed
  exactly once, at the last reference drop. }
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
  Freed: Integer;

function TInterfacedObject.QueryInterface(iid: Integer): Integer;
begin
  Result := -1;
end;

function TInterfacedObject._AddRef: Integer;
begin
  Self.FRefCount := Self.FRefCount + 1;
  Result := Self.FRefCount;
end;

function TInterfacedObject._Release: Integer;
begin
  Self.FRefCount := Self.FRefCount - 1;
  Result := Self.FRefCount;
  if Self.FRefCount = 0 then
  begin
    Freed := Freed + 1;
    FreeMem(Pointer(Self));
  end;
end;

procedure TFoo.Hello;
begin
  writeln('hello');
end;

{ A single interface var: create through it, use it, drop at scope exit. }
procedure RunSingle;
var f: IFoo;
begin
  f := TFoo.Create;
  f.Hello;
end;

{ Two interface vars aliasing the same object: it must survive until BOTH drop. }
procedure RunShared;
var a, b: IFoo;
begin
  a := TFoo.Create;   { rc 1 }
  b := a;             { rc 2 }
  a.Hello;
  b.Hello;
end;                  { rc 0 at the second scope-exit release }

{ Reassign to nil mid-scope: frees early, then nothing left at scope exit. }
procedure RunNil;
var f: IFoo;
begin
  f := TFoo.Create;
  f := nil;
end;

begin
  Freed := 0;
  RunSingle;
  RunShared;
  RunNil;
  writeln('freed=', Freed);   { expect 3: one object freed per proc }
end.
