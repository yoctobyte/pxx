{ FreeAndNil must (a) take an UNTYPED var parameter, as FPC does, and (b) actually run the
  DESTRUCTOR.

  The old one did neither: it was declared `var Obj: TObject` -- so any other class-typed
  variable failed to match -- and its body called FreeMem(Pointer(Obj)) directly, which
  releases the memory WITHOUT dispatching Destroy. Every destructor of every object freed
  through it was silently skipped: no `inherited`, no child cleanup, no handle release. It
  looked like it worked, because the memory really was freed.

  It also nils AFTER taking the reference but BEFORE freeing, which is FPC's order and the
  point of the routine: a re-entrant destructor sees nil, not a dangling pointer. }
program test_freeandnil_destructor_b300;
uses sysutils;

var
  destroyed: Integer;

type
  TChild = class
    destructor Destroy; override;
  end;

  TParent = class
    Kid: TChild;
    constructor Create;
    destructor Destroy; override;
  end;

destructor TChild.Destroy;
begin
  Inc(destroyed);
  writeln('  TChild.Destroy');
  inherited Destroy;
end;

constructor TParent.Create;
begin
  Kid := TChild.Create;
end;

destructor TParent.Destroy;
begin
  writeln('  TParent.Destroy');
  Kid.Free;                    { the child is only released if THIS runs }
  inherited Destroy;
end;

var
  p: TParent;
  c: TChild;
begin
  destroyed := 0;

  { an UNTYPED var param takes any class-typed variable, no cast }
  p := TParent.Create;
  writeln('freeing parent:');
  FreeAndNil(p);
  writeln('parent nil : ', p = nil);
  writeln('destructors: ', destroyed, ' (1 = the child, via TParent.Destroy)');

  c := TChild.Create;
  writeln('freeing child:');
  FreeAndNil(c);
  writeln('child nil  : ', c = nil);
  writeln('destructors: ', destroyed, ' (2)');
end.
