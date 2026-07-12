program vindaggret;
{ Aggregate / frozen-string results returned through a VIRTUAL and an INDIRECT
  call — the hidden caller-destination ABI on every backend
  (feature-cross-virtual-indirect-hidden-dest). Includes a >4-word / >6-arg
  variant so the stack-argument paths of the 32-bit backends are exercised too. }
type
  TPair = record A, B: Integer; end;
  TWide = record A, B, C, D, E, F, G, H: Integer; end;

  TBase = class
    function Pair(a, b: Integer): TPair; virtual;
    function Name: string; virtual;
    function Wide(a, b, c, d, e, f, g: Integer): TWide; virtual;
  end;

  TDerived = class(TBase)
    function Pair(a, b: Integer): TPair; override;
    function Name: string; override;
    function Wide(a, b, c, d, e, f, g: Integer): TWide; override;
  end;

  TPairFn = function(a, b: Integer): TPair;
  TNameFn = function(n: Integer): string;
  TWideFn = function(a, b, c, d, e, f: Integer): TWide;

function TBase.Pair(a, b: Integer): TPair;
begin
  Result.A := a; Result.B := b;
end;

function TBase.Name: string;
begin
  Result := 'base';
end;

function TBase.Wide(a, b, c, d, e, f, g: Integer): TWide;
begin
  Result.A := a; Result.B := b; Result.C := c; Result.D := d;
  Result.E := e; Result.F := f; Result.G := g; Result.H := 0;
end;

function TDerived.Pair(a, b: Integer): TPair;
begin
  Result.A := a * 10; Result.B := b * 10;
end;

function TDerived.Name: string;
begin
  Result := 'derived';
end;

function TDerived.Wide(a, b, c, d, e, f, g: Integer): TWide;
begin
  Result.A := a + 1; Result.B := b + 1; Result.C := c + 1; Result.D := d + 1;
  Result.E := e + 1; Result.F := f + 1; Result.G := g + 1; Result.H := 0;
end;

function FreePair(a, b: Integer): TPair;
begin
  Result.A := a - b; Result.B := a + b;
end;

function FreeName(n: Integer): string;
begin
  if n = 0 then Result := 'zero' else Result := 'many';
end;

function FreeWide(a, b, c, d, e, f: Integer): TWide;
begin
  { 6 args = the x86-64 indirect-call param ceiling; still >4 words, so the
    32-bit backends take their stack-argument path. }
  Result.A := a; Result.B := b; Result.C := c; Result.D := d;
  Result.E := e; Result.F := f; Result.G := 0; Result.H := 0;
end;

var
  o: TBase;
  p: TPair;
  w: TWide;
  pf: TPairFn;
  nf: TNameFn;
  wf: TWideFn;
begin
  { virtual call, aggregate result }
  o := TBase.Create;
  p := o.Pair(3, 4);
  writeln(p.A, ' ', p.B);
  writeln(o.Name);
  w := o.Wide(1, 2, 3, 4, 5, 6, 7);
  writeln(w.A, ' ', w.D, ' ', w.G);

  o := TDerived.Create;
  p := o.Pair(3, 4);
  writeln(p.A, ' ', p.B);
  writeln(o.Name);
  w := o.Wide(1, 2, 3, 4, 5, 6, 7);
  writeln(w.A, ' ', w.D, ' ', w.G);

  { indirect call through a procedural value, aggregate / string result }
  pf := @FreePair;
  p := pf(9, 4);
  writeln(p.A, ' ', p.B);

  nf := @FreeName;
  writeln(nf(0), ' ', nf(7));

  wf := @FreeWide;
  w := wf(10, 20, 30, 40, 50, 60);
  writeln(w.A, ' ', w.E, ' ', w.F);
end.
