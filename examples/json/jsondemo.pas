program JSONDemo;
{ Deterministic oracle for the json unit (Track B).

  Exercises: recursive-descent parse, canonical compact + pretty re-emit,
  roundtrip identity (Parse -> ToString -> Parse re-emits byte-identically),
  typed access, string-escape handling, and parse-error exceptions.

  Output is integer/string-deterministic, so it is byte-identical across all
  targets. Ends with 'ALL OK' iff every check passes -- this line is what
  `make lib-test` asserts. }

uses json, sysutils;

var
  ok: Boolean;

{ Parse src, re-emit compact, parse THAT, re-emit again: the two compact forms
  must be byte-identical (canonical, stable). Returns the canonical form. }
function Canonical(const src: AnsiString): AnsiString;
var a, b: TJSONValue; s1, s2: AnsiString;
begin
  a := JSONParse(src);
  s1 := a.ToString(False);
  b := JSONParse(s1);
  s2 := b.ToString(False);
  if s1 <> s2 then
  begin
    ok := False;
    writeln('  FAIL roundtrip: ', s1, ' <> ', s2);
  end;
  a.FreeTree;
  b.FreeTree;
  Result := s1;
end;

function BoolStr(b: Boolean): AnsiString;
begin
  if b then Result := 'T' else Result := 'F';
end;

procedure Check(const lbl, got, want: AnsiString);
begin
  writeln(lbl, ' = ', got);
  if got <> want then
  begin
    ok := False;
    writeln('  FAIL: want ', want);
  end;
end;

var
  v, c: TJSONValue;
  s, caught: AnsiString;
begin
  ok := True;

  { --- canonical roundtrip on a bundled document set --- }
  Check('arr   ', Canonical('[1, 2, 3,  4]'), '[1,2,3,4]');
  Check('obj   ', Canonical('{ "b": 2 , "a": 1 }'), '{"b":2,"a":1}');
  Check('nest  ', Canonical('{"x":[true,false,null],"y":{"z":-7}}'),
                  '{"x":[true,false,null],"y":{"z":-7}}');
  Check('empty ', Canonical('{"a":[],"b":{}}'), '{"a":[],"b":{}}');
  Check('num   ', Canonical('{"pi":3.14,"e":2e3,"neg":-0.5}'),
                  '{"pi":3.14,"e":2e3,"neg":-0.5}');

  { --- string escaping roundtrip --- }
  Check('esc   ', Canonical('{"s":"a\"b\\c\n\tend"}'),
                  '{"s":"a\"b\\c\n\tend"}');
  Check('unicode', Canonical('{"u":"Aé"}'), '{"u":"Aé"}');

  { --- typed access --- }
  s := '{"name":"frank","age":42,"tags":["x","y"],"active":true}';
  v := JSONParse(s);
  Check('name  ', v.GetValue('name').AsString, 'frank');
  Check('age   ', IntToStr(v.GetValue('age').AsInteger), '42');
  Check('active', BoolStr(v.GetValue('active').AsBoolean), 'T');
  c := v.GetValue('tags');
  Check('tags#', IntToStr(c.Count), '2');
  Check('tag1 ', c.GetItem(1).AsString, 'y');
  Check('miss ', BoolStr(v.HasKey('nope')), 'F');

  { --- pretty form (deterministic) --- }
  writeln('pretty:');
  writeln(v.ToString(True));
  v.FreeTree;

  { --- parse errors raise EJSONError --- }
  caught := '';
  try
    v := JSONParse('{"a":}');
  except
    on e: EJSONError do caught := 'err';
  end;
  Check('badval', caught, 'err');

  caught := '';
  try
    v := JSONParse('[1,2');
  except
    on e: EJSONError do caught := 'err';
  end;
  Check('badarr', caught, 'err');

  caught := '';
  try
    v := JSONParse('{} junk');
  except
    on e: EJSONError do caught := 'err';
  end;
  Check('trail ', caught, 'err');

  writeln;
  if ok then writeln('ALL OK') else writeln('FAILURES');
end.
