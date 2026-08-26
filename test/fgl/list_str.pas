program list_str;
{ fgl rung: TFPGList<string> — a string-instantiated generic container. }
uses fgl;
type
  TStrList = specialize TFPGList<string>;
var
  l: TStrList;
  s: string;
begin
  l := TStrList.Create;
  l.Add('gamma'); l.Add('alpha'); l.Add('beta');
  writeln('count=', l.Count);
  writeln('indexof=', l.IndexOf('beta'));
  write('items:');
  for s in l do write(' ', s);
  writeln;
  l.Delete(0);
  writeln('after-del head=', l[0]);
  l.Free;
end.
