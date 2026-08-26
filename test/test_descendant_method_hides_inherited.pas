program test_descendant_method_hides_inherited;
{ Object Pascal's HIDING rule: a method declared in a descendant hides every
  inherited method of that name, unless it carries `overload` (or `override`,
  which continues the inherited method rather than introducing a new one).

  pxx kept the inherited ones as overload candidates regardless. The directive
  parser said so and stated the assumption that made it look safe -- "overload
  resolution is signature-keyed anyway" -- which holds exactly while no two
  candidates both accept the argument. When they do, the call went silently to
  the parent's method:

    TBase = class function Add(x: Pointer): Integer; end;
    TDer  = class(TBase) function Add(const s: AnsiString): Integer; end;
    d.Add(p)   { p: Pointer -- pxx ran TBase.Add, fpc refuses the call }

  In real code that is `fgl.pp`: TFPSList.Add(Item: Pointer) and
  TFPGList.Add(const Item: T), neither marked `overload`. A class instance IS
  compatible with Pointer, so `l.Add(TFoo.Create(3))` on a TFPGList<IFoo> bound
  the hidden parent, which DEREFERENCES its argument -- the eight bytes stored
  were the object's VMT word, and the next read segfaulted. Six of the seven fgl
  drivers passed the whole time because no Pointer overload competed for their
  argument types, which is what made this look interface-specific.
  bug-p-a-descendant-method-does-not-hide-the-inherited-one

  Every row below is measured against fpc 3.2.2 -Mobjfpc -O1. The rows are the
  SHAPES the rule has to get right, not a list of values -- the risk in a
  name-resolution change is the cases where hiding must NOT happen. }
type
  TA = class
    function F(x: Integer): AnsiString; virtual;
    function G(x: Integer): AnsiString; overload;
    function H(x: Integer): AnsiString;
    constructor Create(x: Integer);
  end;
  TB = class(TA)
    function F(x: Integer): AnsiString; override;           { continues -- must NOT hide }
    function G(const s: AnsiString): AnsiString; overload;   { adds -- must NOT hide }
    function H(const s: AnsiString): AnsiString;             { HIDES TA.H(Integer) }
    constructor Create;                                      { a ctor never hides }
  end;
  TC = class(TB)
    function H(x: Double): AnsiString;                       { HIDES TB.H(AnsiString) }
  end;

  { the original nine-line repro, with the parent's method reached only if
    hiding fails }
  TBase = class
    function Add(x: Pointer): Integer;
  end;
  TDer = class(TBase)
    function Add(const s: AnsiString): Integer;
  end;

var
  fails: Integer;

procedure ChkS(const what, got, want: AnsiString);
begin
  if got <> want then
  begin
    writeln('FAIL ', what, ': got "', got, '" want "', want, '"');
    fails := fails + 1;
  end;
end;

constructor TA.Create(x: Integer); begin end;
constructor TB.Create; begin end;
function TA.F(x: Integer): AnsiString; begin F := 'TA.F'; end;
function TA.G(x: Integer): AnsiString; begin G := 'TA.G int'; end;
function TA.H(x: Integer): AnsiString; begin H := 'TA.H int'; end;
function TB.F(x: Integer): AnsiString; begin F := 'TB.F'; end;
function TB.G(const s: AnsiString): AnsiString; begin G := 'TB.G str'; end;
function TB.H(const s: AnsiString): AnsiString; begin H := 'TB.H str'; end;
function TC.H(x: Double): AnsiString; begin H := 'TC.H dbl'; end;

function TBase.Add(x: Pointer): Integer;
begin
  Add := 1;
end;

function TDer.Add(const s: AnsiString): Integer;
begin
  Add := 2;
end;

var
  a: TA;
  b: TB;
  c: TC;
  d: TDer;
begin
  fails := 0;
  b := TB.Create;
  c := TC.Create;
  d := TDer.Create;
  a := b;

  { hiding must NOT fire }
  ChkS('virtual through base', a.F(1), 'TB.F');
  ChkS('override direct', b.F(1), 'TB.F');
  ChkS('overload keeps inherited', b.G(1), 'TA.G int');
  ChkS('overload own', b.G('s'), 'TB.G str');
  ChkS('constructor does not hide', TA.Create(1).H(2), 'TA.H int');

  { hiding must fire }
  ChkS('hidden name binds own', b.H('s'), 'TB.H str');
  ChkS('hiding through two levels', c.H(1.5), 'TC.H dbl');

  { the fgl shape: a string argument must reach the DESCENDANT even though the
    parent's Pointer parameter would also accept a class instance }
  if d.Add('hello') <> 2 then
  begin
    writeln('FAIL fgl shape: d.Add(''hello'') reached the hidden TBase.Add');
    fails := fails + 1;
  end;

  if fails = 0 then writeln('ALL OK') else writeln(fails, ' FAILURES');
end.
