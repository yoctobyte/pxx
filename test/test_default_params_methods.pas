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
  { A defaulted MANAGED (Variant) parameter on a constructor. The ctor call
    path used to build its default args with a hand-rolled copy of the shared
    builder, which never retagged the ordinal as tyInteger — so the boxing was
    skipped and the callee dereferenced a bare 0 as a 16-byte variant slot,
    smashing the caller's frame. A plain PROCEDURE was fine, which is what let
    it survive; hence both shapes below.
    bug-p-constructor-with-a-defaulted-variant-param-corrupts-memory }
  { FLOAT literal defaults, at all FOUR parameter parsers (free routine, class
    method, interface method, record method). None of them accepted a float: the
    token matched no arm and fell through to the INTEGER const folder, which
    returned without consuming it — so the error landed on the NEXT parameter as
    a bare "unexpected token" and pointed at innocent code. The four parsers now
    share one ParseParamDefaultValue.
    bug-p-float-literal-default-in-a-parameter-list-fails-to-parse }
  TFRec = record
    procedure RM(d: Double = 1.25);
  end;
  IFDflt = interface
    procedure IM(d: Double = 2.25);
  end;
  TFDflt = class(TInterfacedObject, IFDflt)
    constructor Create(d: Double = 3.25);
    procedure CM(d: Double = 4.25);
    procedure IM(d: Double = 2.25);
  end;
  TVarDflt = class
    FV: Integer;
    constructor Create(const nm: AnsiString; const v: Variant = 7);
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

constructor TVarDflt.Create(const nm: AnsiString; const v: Variant);
begin
  FV := v;
end;

var seenF: Double;
procedure TFRec.RM(d: Double); begin seenF := d; end;
constructor TFDflt.Create(d: Double); begin seenF := d; end;
procedure TFDflt.CM(d: Double); begin seenF := d; end;
procedure TFDflt.IM(d: Double); begin seenF := d; end;
procedure FreeF(d: Double = 5.25); begin seenF := d; end;

{ PAREN-LESS statement call on a routine whose parameters are ALL defaulted.
  `P;` used to fail with "undefined variable (P)" — the name had resolved and
  the ARITY had not, which is why the diagnostic sent readers looking at scope.
  `P()` worked, and so did `b.G` for a METHOD with defaults, so it was the free-
  routine statement path alone that never reached the trailing-defaults fill.
  bug-p-parenless-call-to-an-all-defaulted-routine-is-an-undefined-variable. }
var seenPL: Integer;
procedure PL1(k: Integer = 3); begin seenPL := k; end;
procedure PL2(a: Integer = 4; b: Integer = 5); begin seenPL := a * 10 + b; end;
{ a defaulted STRING parameter too, so the fill is exercised on a managed type }
var seenPLs: AnsiString;
procedure PLs(const s: AnsiString = 'dflt'); begin seenPLs := s; end;
{ ...and the EXPRESSION arm of the same defect — `a := F` beside `P;`. The
  ticket reported statement position only; fixing that left this one still
  saying "undefined variable (F)". FR assigns its own name as the Result, which
  must stay a Result assignment and NOT become a recursive call now that the
  name looks callable — the sibling this widening could have broken. }
function PlSelfRes(k: Integer = 3): Integer; begin PlSelfRes := k * 2; end;
function PlResVar(k: Integer = 5): Integer; begin Result := k + 1; end;
{ a float default into a VARIANT parameter — the boxing arm, cf. the ctor case }
procedure VarF(const v: Variant = 6.25); begin seenF := v; end;

var lastPV: Integer;
{ the same shape as a plain procedure — this arm always worked }
procedure PVarDflt(const nm: AnsiString; const v: Variant = 7);
begin
  lastPV := v;
end;

var
  b: TBase;
  d: TDer;
  vd: TVarDflt;
  fr: TFRec;
  fc: TFDflt;
  fi: IFDflt;
  plA: Integer;      { paren-less call in EXPRESSION position lands here }
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

  PVarDflt('a');
  Check('proc-variant-default', lastPV, 7);
  vd := TVarDflt.Create('a', 9);
  Check('ctor-variant-explicit', vd.FV, 9);
  vd.Free;
  vd := TVarDflt.Create('a');           { used to smash the stack }
  Check('ctor-variant-default', vd.FV, 7);
  vd.Free;

  { float defaults — compared in hundredths so the integer Check harness serves }
  FreeF();            Check('float-free-routine', Round(seenF * 100), 525);
  FreeF(9.5);         Check('float-free-explicit', Round(seenF * 100), 950);
  fr.RM();            Check('float-record-method', Round(seenF * 100), 125);
  fc := TFDflt.Create();  Check('float-ctor', Round(seenF * 100), 325);
  fc.CM();            Check('float-class-method', Round(seenF * 100), 425);
  fi := fc;
  fi.IM();            Check('float-interface-method', Round(seenF * 100), 225);
  VarF();             Check('float-default-into-variant', Round(seenF * 100), 625);

  { paren-less calls on all-defaulted routines, against their parenthesised
    twins — the pair is the point: `P()` always worked, `P;` did not }
  PL1;                Check('parenless-one-default', seenPL, 3);
  PL1(8);             Check('parenless-one-explicit', seenPL, 8);
  PL2;                Check('parenless-two-defaults', seenPL, 45);
  PL2(7);             Check('parenless-two-partial', seenPL, 75);
  PLs;                Check('parenless-string-default', Ord(seenPLs = 'dflt'), 1);
  FreeF;              Check('parenless-float-default', Round(seenF * 100), 525);
  { assigned to a local first, deliberately: bare `FR` in ARGUMENT position is a
    third site and a genuinely ambiguous one — there it could equally be a
    procedural-type reference — so it is left alone rather than guessed at. }
  plA := PlSelfRes;   Check('parenless-expr-selfresult', plA, 6);
  plA := PlResVar;    Check('parenless-expr-result-var', plA, 6);
  plA := PlSelfRes(10); Check('parenless-expr-explicit', plA, 20);

  writeln('total ok ', okc, ' / ', total);
end.
