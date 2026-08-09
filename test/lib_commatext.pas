{ TStrings.CommaText / DelimitedText — the quoting rules, which ARE the job.

  Every line below is FPC's own output for the same program, captured from three
  probe runs and pasted in; the test is a diff against that. The ticket
  (feature-b-tstrings-commatext) says to read these off an FPC build case by
  case rather than implement from the description, and it is right — two rules
  were wrong when written from the description and only the adversarial cases
  caught them:

    "a"b   ->  TWO items <a> <b>    the closing quote ENDS the item
    a"b"   ->  ONE item <a"b">      a quote mid-item is a literal character

  A from-the-description implementation gave <ab> for both. Note that BOTH of
  those round-trip cleanly, so the round-trip property the ticket suggests would
  have passed while both directions were wrong in matching ways — which is why
  the literal strings are asserted too.

  Other rules that are not guessable: an empty item writes as nothing (`a,,b`)
  EXCEPT a list of exactly one empty string, which writes as `""` so it stays
  distinguishable from an empty list; and unless StrictDelimiter, WHITESPACE
  ALSO SEPARATES, so `a b,c d` parses to four items. }
program lib_commatext;

uses sysutils, classes;

var
  sl: TStringList;
  failures: Integer;
  log: AnsiString;

procedure Emit(const s: AnsiString);
begin
  log := log + s + Chr(10);
end;

procedure Items(const a: array of string);
var k: Integer;
begin
  sl.Clear;
  for k := 0 to High(a) do sl.Add(a[k]);
end;

procedure Show(const tag: string);
var k: Integer; s: AnsiString;
begin
  s := tag + ' [' + sl.CommaText + ']  items:';
  for k := 0 to sl.Count - 1 do s := s + ' <' + sl[k] + '>';
  Emit(s);
end;

procedure P(const v: string);
var k: Integer; s: AnsiString;
begin
  sl.Clear;
  sl.CommaText := v;
  s := '<' + v + '> ->';
  for k := 0 to sl.Count - 1 do s := s + ' <' + sl[k] + '>';
  Emit(s + ' n=' + IntToStr(sl.Count));
end;

procedure PD(const tag, v: string);
var k: Integer; s: AnsiString;
begin
  sl.Clear;
  sl.DelimitedText := v;
  s := tag + ' <' + v + '> ->';
  for k := 0 to sl.Count - 1 do s := s + ' <' + sl[k] + '>';
  Emit(s + ' n=' + IntToStr(sl.Count));
end;

procedure RT(const a: array of string);
var k: Integer; t: string; s: AnsiString;
begin
  Items(a);
  t := sl.CommaText;
  sl.Clear;
  sl.CommaText := t;
  s := 'rt [' + t + '] ->';
  for k := 0 to sl.Count - 1 do s := s + ' <' + sl[k] + '>';
  Emit(s + ' n=' + IntToStr(sl.Count));
end;

var
  want, got: AnsiString;
  i, n: Integer;
  gl, wl: TStringList;
begin
  failures := 0;
  log := '';
  sl := TStringList.Create;

  { ---- writing: when an item gets quoted ---- }
  Items(['a', 'b', 'c']);                Show('plain   ');
  Items(['a b', 'c']);                   Show('space   ');
  Items(['a,b', 'c']);                   Show('comma   ');
  Items(['say "hi"']);                   Show('quote   ');
  Items(['']);                           Show('empty   ');
  Items(['a', '', 'b']);                 Show('midempty');
  Items(['  lead', 'trail  ']);          Show('ws      ');
  Items(['tab' + Chr(9) + 'x']);         Show('tab     ');
  sl.StrictDelimiter := True;
  Items(['a b', 'c,d', 'e']);            Show('strict  ');
  sl.StrictDelimiter := False;

  { ---- StrictDelimiter, and CommaText ignoring it ---- }
  sl.Clear;
  Emit('emptylist CommaText=[' + sl.CommaText + '] n=' + IntToStr(sl.Count));
  Items(['a b', 'c,d', 'e', '']);
  sl.StrictDelimiter := False;
  Emit('DT strict=F [' + sl.DelimitedText + ']');
  sl.StrictDelimiter := True;
  Emit('DT strict=T [' + sl.DelimitedText + ']');
  Emit('CT while strict=T [' + sl.CommaText + ']');
  PD('strictparse', 'a b,c d');
  PD('strictparse', '  a  ,  b  ');
  sl.StrictDelimiter := False;
  PD('laxparse   ', 'a b,c d');

  { ---- Delimiter / QuoteChar, and CommaText not disturbing them ---- }
  sl.Delimiter := ';';
  Items(['x,y', 'z']);
  Emit('semi DT [' + sl.DelimitedText + ']  CT [' + sl.CommaText + ']');
  Emit('after CT get, delim=<' + sl.Delimiter + '>');
  sl.Delimiter := ',';
  sl.QuoteChar := Chr(39);
  Items(['a b']);
  Emit('apostrophe DT [' + sl.DelimitedText + ']');
  sl.QuoteChar := '"';

  { ---- parsing, including the two rules a description gets wrong ---- }
  P('a,b,c');
  P('a, b, c');
  P('"a,b",c');
  P('"a"b');
  P('a"b"');
  P('"unterminated');
  P(',a');
  P('a,');
  P(',');
  P(',,');
  P('   ');
  P('""');
  P('"",""');
  P('a b');
  P('"a""b"');
  P(Chr(9) + 'a' + Chr(9));
  P('a,"b c",d e');

  { ---- round trips ---- }
  RT(['a', 'b']);
  RT(['a b', 'c,d', 'say "hi"', '']);
  RT(['']);
  RT(['  x  ']);
  RT([',']);
  RT(['"']);
  sl.Free;

  want :=
    'plain    [a,b,c]  items: <a> <b> <c>' + Chr(10) +
    'space    ["a b",c]  items: <a b> <c>' + Chr(10) +
    'comma    ["a,b",c]  items: <a,b> <c>' + Chr(10) +
    'quote    ["say ""hi"""]  items: <say "hi">' + Chr(10) +
    'empty    [""]  items: <>' + Chr(10) +
    'midempty [a,,b]  items: <a> <> <b>' + Chr(10) +
    'ws       ["  lead","trail  "]  items: <  lead> <trail  >' + Chr(10) +
    'tab      ["tab	x"]  items: <tab	x>' + Chr(10) +
    'strict   ["a b","c,d",e]  items: <a b> <c,d> <e>' + Chr(10) +
    'emptylist CommaText=[] n=0' + Chr(10) +
    'DT strict=F ["a b","c,d",e,]' + Chr(10) +
    'DT strict=T [a b,"c,d",e,]' + Chr(10) +
    'CT while strict=T ["a b","c,d",e,]' + Chr(10) +
    'strictparse <a b,c d> -> <a b> <c d> n=2' + Chr(10) +
    'strictparse <  a  ,  b  > -> <  a  > <  b  > n=2' + Chr(10) +
    'laxparse    <a b,c d> -> <a> <b> <c> <d> n=4' + Chr(10) +
    'semi DT [x,y;z]  CT ["x,y",z]' + Chr(10) +
    'after CT get, delim=<;>' + Chr(10) +
    'apostrophe DT [''a b'']' + Chr(10) +
    '<a,b,c> -> <a> <b> <c> n=3' + Chr(10) +
    '<a, b, c> -> <a> <b> <c> n=3' + Chr(10) +
    '<"a,b",c> -> <a,b> <c> n=2' + Chr(10) +
    '<"a"b> -> <a> <b> n=2' + Chr(10) +
    '<a"b"> -> <a"b"> n=1' + Chr(10) +
    '<"unterminated> -> <unterminated> n=1' + Chr(10) +
    '<,a> -> <> <a> n=2' + Chr(10) +
    '<a,> -> <a> <> n=2' + Chr(10) +
    '<,> -> <> <> n=2' + Chr(10) +
    '<,,> -> <> <> <> n=3' + Chr(10) +
    '<   > -> n=0' + Chr(10) +
    '<""> -> <> n=1' + Chr(10) +
    '<"",""> -> <> <> n=2' + Chr(10) +
    '<a b> -> <a> <b> n=2' + Chr(10) +
    '<"a""b"> -> <a"b> n=1' + Chr(10) +
    '<	a	> -> <a> n=1' + Chr(10) +
    '<a,"b c",d e> -> <a> <b c> <d> <e> n=4' + Chr(10) +
    'rt [a,b] -> <a> <b> n=2' + Chr(10) +
    'rt ["a b","c,d","say ""hi""",] -> <a b> <c,d> <say "hi"> <> n=4' + Chr(10) +
    'rt [""] -> <> n=1' + Chr(10) +
    'rt ["  x  "] -> <  x  > n=1' + Chr(10) +
    'rt [","] -> <,> n=1' + Chr(10) +
    'rt [""""] -> <"> n=1' + Chr(10);
  got := log;
  if got <> want then
  begin
    { line-by-line so a failure names the case, not a 40-line blob }
    gl := TStringList.Create; wl := TStringList.Create;
    gl.Text := got; wl.Text := want;
    n := gl.Count; if wl.Count > n then n := wl.Count;
    for i := 0 to n - 1 do
    begin
      if (i >= gl.Count) then writeln('FAIL: missing  want <', wl[i], '>')
      else if (i >= wl.Count) then writeln('FAIL: extra    got  <', gl[i], '>')
      else if gl[i] <> wl[i] then
      begin
        writeln('FAIL: got  <', gl[i], '>');
        writeln('      want <', wl[i], '>');
        failures := failures + 1;
      end;
    end;
    if failures = 0 then failures := 1;
    gl.Free; wl.Free;
  end;

  if failures = 0 then writeln('COMMATEXT OK')
  else writeln('COMMATEXT ', failures, ' FAILURES');
end.
