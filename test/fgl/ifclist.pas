program ifclist;
{ fgl rung: TFPGInterfacedObjectList<T> — refcounted interface container. }
uses fgl;
type
  IFoo = interface ['{11111111-2222-3333-4444-555555555555}']
    function V: Integer;
  end;
  TFoo = class(TInterfacedObject, IFoo)
    n: Integer;
    constructor Create(an: Integer);
    function V: Integer;
  end;
  TFooList = specialize TFPGInterfacedObjectList<IFoo>;

constructor TFoo.Create(an: Integer);
begin
  inherited Create;
  n := an;
end;

function TFoo.V: Integer;
begin
  Result := n;
end;

var
  l: TFooList;
begin
  l := TFooList.Create;
  l.Add(TFoo.Create(3));
  l.Add(TFoo.Create(4));
  writeln('count=', l.Count, ' v0=', l[0].V, ' v1=', l[1].V);
  l.Delete(0);
  writeln('after-del count=', l.Count, ' head=', l[0].V);
  l.Free;
  writeln('freed');
end.
