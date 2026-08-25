program objectlist;
{ fgl rung: TFPGObjectList<T: TObject> — owning container of class instances. }
uses fgl;
type
  TThing = class
    v: Integer;
    constructor Create(av: Integer);
  end;
  TThingList = specialize TFPGObjectList<TThing>;

constructor TThing.Create(av: Integer);
begin
  inherited Create;
  v := av;
end;

var
  l: TThingList;
  t: TThing;
begin
  l := TThingList.Create(True);
  l.Add(TThing.Create(1));
  l.Add(TThing.Create(2));
  l.Add(TThing.Create(3));
  writeln('count=', l.Count, ' v1=', l[1].v);
  write('items:');
  for t in l do write(' ', t.v);
  writeln;
  l.Delete(0);
  writeln('after-del count=', l.Count, ' head=', l[0].v);
  l.Free;
  writeln('freed');
end.
