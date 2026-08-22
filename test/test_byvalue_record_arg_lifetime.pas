program test_byvalue_record_arg_lifetime;
{ A by-VALUE record argument with managed fields is copied into a hidden caller
  temp. Nothing released that temp until the CALLER's epilogue, which in the
  main body is program exit — so an interface field's destructor ran after the
  last statement instead of after the call. FPC finalizes a value parameter in
  the callee. Every row checked against fpc 3.2.2 -Mobjfpc -O1; the counts are
  the point, not the names.
  bug-a-by-value-record-arg-temp-outlives-the-call }
type
  IFoo = interface ['{A1B2C3D4-0001-0002-0003-000000000001}']
    function Name: string;
  end;
  TFoo = class(TInterfacedObject, IFoo)
  private FN: string;
  public
    constructor Create(const n: string);
    destructor Destroy; override;
    function Name: string;
  end;
  TRec = record a: Integer; f: IFoo; s: AnsiString; end;
var destroyed: Integer;
constructor TFoo.Create(const n: string); begin inherited Create; FN := n; end;
destructor TFoo.Destroy; begin Inc(destroyed); inherited Destroy; end;
function TFoo.Name: string; begin Result := FN; end;

procedure ByValue(r: TRec); begin WriteLn(r.f.Name, ' ', r.s); end;
procedure Two(r1, r2: TRec); begin WriteLn(r1.f.Name, r2.f.Name); end;
procedure InProc;
var h: TRec;
begin
  h.f := TFoo.Create('P'); h.s := 'ps';
  ByValue(h);
  h.f := nil;
  WriteLn('inproc ', destroyed);
end;
function Ident(const r: TRec): TRec; begin Result := r; end;

var g, g2: TRec; i: Integer;
begin
  destroyed := 0;
  g.f := TFoo.Create('B'); g.s := 'bs';
  ByValue(g);
  g.f := nil;
  WriteLn('main   ', destroyed);

  destroyed := 0;
  g.f := TFoo.Create('X'); g2.f := TFoo.Create('Y');
  Two(g, g2);
  g.f := nil; g2.f := nil;
  WriteLn('two    ', destroyed);

  destroyed := 0;
  InProc;

  destroyed := 0;
  g.f := TFoo.Create('L');
  for i := 1 to 3 do ByValue(g);
  g.f := nil;
  WriteLn('loop   ', destroyed);

  destroyed := 0;
  g.f := TFoo.Create('N');
  ByValue(Ident(g));
  g.f := nil;
  WriteLn('nested ', destroyed);
end.
