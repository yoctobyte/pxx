program test_generic_class_methods;
{ `class function` / `class procedure` members inside a generic class (fgl's
  `class Function ItemIsManaged : Boolean; override;` shape). The template
  depth scan must not treat the `class` member prefix as a nested class-body
  opener, and a `class function TG.M` impl must keep its prefix when buffered
  for specialization. }

type
  TBase = class
    class function Kind: Integer; virtual;
  end;
  generic TG<T> = class(TBase)
    FVal: T;
    class function Kind: Integer; override;
    class function Tag: Integer;
    class procedure Ping;
    procedure SetVal(v: T);
    function GetVal: T;
  end;
  TGI = specialize TG<Integer>;

var
  total, okc, pings: Integer;

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

class function TBase.Kind: Integer;
begin
  Kind := 1;
end;

class function TG.Kind: Integer;
begin
  Kind := 2;
end;

class function TG.Tag: Integer;
begin
  Tag := 77;
end;

class procedure TG.Ping;
begin
  pings := pings + 1;
end;

procedure TG.SetVal(v: T);
begin
  FVal := v;
end;

function TG.GetVal: T;
begin
  GetVal := FVal;
end;

var
  g: TGI;
begin
  total := 0; okc := 0; pings := 0;
  Check('static-on-generic', TGI.Tag, 77);
  TGI.Ping;
  TGI.Ping;
  Check('class-proc', pings, 2);
  Check('override-on-generic', TGI.Kind, 2);
  Check('base-kind', TBase.Kind, 1);
  g := TGI.Create;
  g.SetVal(42);
  Check('instance-method-still-works', g.GetVal, 42);
  g.Free;
  writeln('total ok ', okc, ' / ', total);
end.
