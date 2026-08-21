program test_tobject_root_methods;
{ TObject's root virtuals (Equals / GetHashCode / ToString) occupy RESERVED
  leading VMT slots in every class, so a descendant's `override` lands in a slot
  a receiver statically typed TObject can dispatch through.
  feature-a-tobject-root-method-vmt-slots. Output matched against FPC 3.2.2. }
uses sysutils;
type
  TPoint = class(TObject)
    X: Integer;
    constructor Create(ax: Integer);
    function Equals(Obj: TObject): Boolean; override;
    function GetHashCode: PtrInt; override;
    function ToString: AnsiString; override;
  end;

  TQuiet = class            { no overrides: the defaults must still work }
    Y: Integer;
  end;

constructor TPoint.Create(ax: Integer);
begin
  X := ax;
end;

function TPoint.Equals(Obj: TObject): Boolean;
begin
  Result := (Obj is TPoint) and (TPoint(Obj).X = X);
end;

function TPoint.GetHashCode: PtrInt;
begin
  Result := X * 31;
end;

function TPoint.ToString: AnsiString;
begin
  Result := 'TPoint(' + IntToStr(X) + ')';
end;

var
  a, b, c: TPoint;
  q: TQuiet;
  o, p: TObject;
begin
  a := TPoint.Create(3);
  b := TPoint.Create(3);
  c := TPoint.Create(4);

  { static descendant receiver }
  WriteLn('direct ', a.Equals(b), ' ', a.Equals(c));
  WriteLn('directhash ', a.GetHashCode, ' ', c.GetHashCode);
  WriteLn('directstr ', a.ToString);

  { static TObject receiver — the whole point of the reserved slots }
  o := a; p := b;
  WriteLn('static ', o.Equals(p), ' ', o.Equals(c));
  WriteLn('statichash ', o.GetHashCode);
  WriteLn('staticstr ', o.ToString);

  { the inherited defaults: identity, the pointer, the class name }
  q := TQuiet.Create;
  o := q;
  WriteLn('quiet ', o.Equals(q), ' ', o.Equals(a));
  WriteLn('quietstr ', o.ToString, ' ', q.ToString);
  WriteLn('quiethash ', q.GetHashCode = o.GetHashCode);

  o := TObject.Create;
  WriteLn('root ', o.Equals(o), ' ', o.ToString);
end.
