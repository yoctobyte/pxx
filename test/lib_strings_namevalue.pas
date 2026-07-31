{ TStrings' Name=Value surface. A TStrings doubles as a string-keyed map in FPC
  and Delphi, and Synapse's cookie jar is `FCookies.Values[name] := v` and
  nothing else — which is how the gap was found. Every expectation below was
  read off an FPC build of this same file, so it compiles under both. Two of
  them are FPC quirks that would not have been guessed: a line with no
  separator has an empty Name but its WHOLE text as the value, and an empty
  value deletes the line through ValueFromIndex yet keeps `Name=` through
  Values. }
program lib_strings_namevalue;
uses classes, sysutils;

var fails: Integer;

procedure Chk(const what, got, want: AnsiString);
begin
  if got = want then WriteLn(what, '=ok')
  else begin WriteLn(what, ' FAIL got=[', got, '] want=[', want, ']'); fails := fails + 1; end;
end;

var l: TStringList;
begin
  fails := 0;
  l := TStringList.Create;
  l.Add('alpha=one');
  l.Add('Beta=two');
  l.Add('plain');
  Chk('sep',        l.NameValueSeparator,      '=');
  Chk('value',      l.Values['alpha'],         'one');
  { FPC matches a name case-insensitively }
  Chk('nocase',     l.Values['BETA'],          'two');
  Chk('missing',    l.Values['nope'],          '');
  Chk('name',       l.Names[0],                'alpha');
  { a line with no separator has no name, and no value }
  Chk('noname',     l.Names[2],                '');
  { with no name, FPC makes the WHOLE line the value }
  Chk('novalue',    l.ValueFromIndex[2],       'plain');
  Chk('fromindex',  l.ValueFromIndex[1],       'two');
  Chk('indexof',    IntToStr(l.IndexOfName('beta')),  '1');
  Chk('indexofno',  IntToStr(l.IndexOfName('plain')), '-1');
  l.Values['gamma'] := 'three';
  Chk('append',     l[3],                      'gamma=three');
  l.Values['alpha'] := 'ONE';
  Chk('replace',    l[0],                      'alpha=ONE');
  Chk('nogrow',     IntToStr(l.Count),         '4');
  { through the NAME an empty value keeps the entry with an empty value ... }
  l.Values['Beta'] := '';
  Chk('emptykeeps', IntToStr(l.Count),         '4');
  Chk('emptyline',  l[1],                      'Beta=');
  Chk('emptyread',  l.Values['beta'],          '');
  l.ValueFromIndex[0] := 'x';
  Chk('setfromidx', l[0],                      'alpha=x');
  { ... while through the INDEX it deletes the line }
  l.ValueFromIndex[1] := '';
  Chk('idxdeletes', IntToStr(l.Count),         '3');
  { a settable separator, as FPC exposes }
  l.NameValueSeparator := ':';
  l.Clear;
  l.Add('Host: nope');
  l.Add('Host:v');
  Chk('altsep',     l.Values['Host'],          ' nope');
  l.Free;
  if fails = 0 then WriteLn('NAMEVALUE OK')
  else WriteLn('NAMEVALUE FAILED ', fails);
end.
