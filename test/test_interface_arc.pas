program TestInterfaceArc;
{ COM/ARC interfaces ({$interfaces com}): a TInterfacedObject-derived class
  managed purely through interface variables (no manual Free) must be freed
  exactly once, at the last reference drop.

  TInterfacedObject/IInterface are the builtinheap RTL pair now (this test used
  to declare its own copies — the reason the missing RTL type went unnoticed,
  bug-pascal-tinterfacedobject-missing-silent-segfault). Frees are counted
  through the virtual-destructor path _Release dispatches at refcount 0. }
{$interfaces com}
type
  IFoo = interface
    procedure Hello;
  end;

  TFoo = class(TInterfacedObject, IFoo)
    destructor Destroy; override;
    procedure Hello;
  end;

var
  Freed: Integer;

destructor TFoo.Destroy;
begin
  Freed := Freed + 1;
  inherited Destroy;
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
