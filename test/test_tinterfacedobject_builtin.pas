program test_tinterfacedobject_builtin;
{ The builtinheap TInterfacedObject/IInterface pair: the stock FPC idiom
  `TFoo = class(TInterfacedObject, IFoo)` with NO local declarations must
  compile, refcount, run the overridden destructor exactly once at the last
  reference drop, and survive scope exit — it used to compile silently as a
  parentless class and SIGSEGV when ARC dispatched _Release through a garbage
  IMT slot (bug-pascal-tinterfacedobject-missing-silent-segfault). }
{$mode objfpc}{$interfaces com}
type
  IFoo = interface
    procedure Go;
  end;

  TFoo = class(TInterfacedObject, IFoo)
    destructor Destroy; override;
    procedure Go;
  end;

var
  Destroyed: Integer;

destructor TFoo.Destroy;
begin
  Destroyed := Destroyed + 1;
  inherited Destroy;
end;

procedure TFoo.Go;
begin
  writeln('go');
end;

{ The ticket's original repro: create through an interface var, use it, let the
  scope-exit release free it. }
procedure Use;
var f: IFoo;
begin
  f := TFoo.Create;
  f.Go;
end;

{ Two references: the destructor must wait for the LAST drop. }
procedure UseShared;
var a, b: IFoo;
begin
  a := TFoo.Create;
  b := a;
  if Destroyed <> 1 then writeln('FAIL: early destroy');
end;

begin
  Destroyed := 0;
  Use;
  writeln('destroyed=', Destroyed);    { 1 }
  UseShared;
  writeln('destroyed=', Destroyed);    { 2 }
  writeln('survived scope exit');
end.
