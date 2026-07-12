program test_tobject_methodaddress_b256;
{ FPC's TObject.MethodAddress(name) / TObject.MethodName(addr), available with NO
  `uses` — FPC declares them on TObject in System, and fcl-fpcunit discovers its
  tests with `Self.MethodAddress(FName)`.

  They rewrite to __pxxMethodAddress / __pxxMethodName in the builtin unit (pulled by
  the token pre-scan), which walk the published-method table in the class RTTI blob.
  The instance reaches that blob through the backlink reserved one word before the
  VMT. See feature-rtti-method-reflection.

  A class with its OWN method of that name must still shadow the builtin — the last
  case pins that down. }
type
  TBase = class
  published
    procedure TestInherited;
  end;

  TCase = class(TBase)
  private
    procedure Helper;              { unpublished — must NOT be found }
  published
    procedure TestAlpha;
  end;

  { a class that defines its own MethodAddress: the user's wins }
  TShadow = class
    function MethodAddress(const s: string): Pointer;
  end;

  TRunner = procedure of object;
  PPtr = ^Pointer;

procedure TBase.TestInherited; begin writeln('ran TestInherited'); end;
procedure TCase.Helper;        begin writeln('ran Helper'); end;
procedure TCase.TestAlpha;     begin writeln('ran TestAlpha'); end;

function TShadow.MethodAddress(const s: string): Pointer;
begin
  writeln('shadowed=', s);
  MethodAddress := nil;
end;

var
  c: TCase;
  sh: TShadow;
  p: Pointer;
  m: TRunner;
  base: PtrUInt;
begin
  c := TCase.Create;

  p := c.MethodAddress('TestAlpha');
  writeln('found-alpha=', p <> nil);
  writeln('name-of-it=', c.MethodName(p));
  writeln('case-insensitive=', c.MethodAddress('testalpha') <> nil);
  writeln('found-inherited=', c.MethodAddress('TestInherited') <> nil);
  writeln('found-private=', c.MethodAddress('Helper') <> nil);
  writeln('found-missing=', c.MethodAddress('Nope') <> nil);
  writeln('name-of-nil=[', c.MethodName(nil), ']');

  { the payoff: bind the discovered address to the instance and RUN it }
  base := PtrUInt(@m);
  PPtr(base)^ := p;
  PPtr(base + 8)^ := Pointer(c);
  m();

  c.Free;

  sh := TShadow.Create;
  p := sh.MethodAddress('zzz');     { the USER's method runs, not the builtin }
  writeln('shadow-nil=', p = nil);
  sh.Free;
end.
