program test_default_params_methods;
{ Default parameter values on class methods, constructors, and interface
  methods (previously free routines only). A call omitting trailing defaulted
  args gets the declared constants; supplying them overrides. Covers direct,
  virtual-through-base, class-static, and paren-less call forms, plus a
  sizeof(...) default (FPC fgl's TFPSList.Create shape). }

type
  TBase = class
    FSz: Integer;
    constructor Create(sz: Integer = sizeof(Pointer));
    procedure M(a: Integer; b: Integer = 5; c: Integer = 100);
    function G(x: Integer = 3): Integer;
    function V(a: Integer; b: Integer = 11): Integer; virtual;
    class function CF(k: Integer = 21): Integer;
  end;
  TDer = class(TBase)
    function V(a: Integer; b: Integer = 11): Integer; override;
  end;

var
  total, okc: Integer;
  lastM: Integer;

procedure Check(name: string; got, want: Integer);
begin
  total := total + 1;
  if got = want then
  begin
    okc := okc + 1;
    writeln('ok ', name);
  end
  else
    writeln('FAIL ', name, ' got=', got, ' want=', want);
end;

constructor TBase.Create(sz: Integer);
begin
  FSz := sz;
end;

{ impl repeats params WITHOUT the defaults (FPC style) — must not clear them }
procedure TBase.M(a: Integer; b: Integer; c: Integer);
begin
  lastM := a * 10000 + b * 100 + c;
end;

function TBase.G(x: Integer): Integer;
begin
  G := x * 10;
end;

function TBase.V(a: Integer; b: Integer): Integer;
begin
  V := a + b;
end;

function TDer.V(a: Integer; b: Integer): Integer;
begin
  V := a * b;
end;

class function TBase.CF(k: Integer): Integer;
begin
  CF := k + 1;
end;

var
  b: TBase;
  d: TDer;
begin
  total := 0; okc := 0;

  b := TBase.Create;                    { ctor: default = sizeof(Pointer) }
  Check('ctor-default-sizeof', b.FSz, 8);
  b.Free;

  b := TBase.Create(16);                { ctor: explicit overrides }
  Check('ctor-explicit', b.FSz, 16);

  b.M(1);                               { fill both trailing defaults }
  Check('method-fill-2', lastM, 10600);
  b.M(1, 2);                            { fill last only }
  Check('method-fill-1', lastM, 10300);
  b.M(1, 2, 3);                         { all explicit }
  Check('method-fill-0', lastM, 10203);

  Check('parenless-default', b.G, 30);  { f.G with no parens }
  Check('explicit-over-default', b.G(4), 40);

  Check('virtual-direct', b.V(2), 13);
  d := TDer.Create(1);
  b.Free;
  b := d;
  Check('virtual-through-base', b.V(3), 33);   { TDer.V: 3*11 }
  Check('virtual-explicit', b.V(3, 4), 12);
  d.Free;

  Check('class-static-default', TBase.CF, 22);
  Check('class-static-explicit', TBase.CF(5), 6);

  writeln('total ok ', okc, ' / ', total);
end.
