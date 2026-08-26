program test_result_by_function_name_converts;
{ `F := expr` and `Result := expr` are the same statement, so they must apply
  the same conversion.

  They did not. The function-NAME spelling took a shortcut in the statement
  parser: it hand-built `AN_IDENT(RetSymIdx)` and stamped no ASTTk on it, so
  everything downstream that reads the assignment target's TYPE had nothing to
  read and the right-hand side's conversion was never applied. With a Variant
  source that meant the variant SLOT ADDRESS was stored instead of the value:

    function ByName(v: Variant): Int64;   begin ByName := v; end;    { 4350216 }
    function ByResult(v: Variant): Int64; begin Result := v; end;    { 5000000000 }

  Two spellings of one line, one right and one silently wrong, in the older and
  more common of the two -- the caller receives a plausible number and nothing
  reports anything. An Int64, a Double and an AnsiString result were all wrong;
  Boolean agreed by luck, a non-zero address being truthy, which is exactly the
  accidental agreement that kept it hidden.

  The fix deleted the shortcut rather than teaching it about Variants: both
  shapes now go through ParseLValueAST, which is what the `Result` spelling
  already reached through the ordinary identifier path.
  bug-p-a-variant-assigned-to-the-result-by-function-name-is-not-converted

  Every row matches fpc 3.2.2 -Mobjfpc -O1, and the shapes are varied rather
  than the values: the two spellings, a global vs a parameter source, six
  result types, a NESTED function, `Exit(v)`, and the `.field` / `[i]` forms of
  the same name-as-Result synonym, which never took the shortcut and are here
  so the normalisation cannot regress them. }
uses variants;
type
  TP = record x, y: Int64; end;
  TDyn = array of Int64;
var
  g: Variant;
  fails: Integer;

procedure ChkI(const what: AnsiString; got, want: Int64);
begin
  if got <> want then
  begin
    writeln('FAIL ', what, ': got ', got, ' want ', want);
    fails := fails + 1;
  end;
end;

procedure ChkS(const what: AnsiString; const got, want: AnsiString);
begin
  if got <> want then
  begin
    writeln('FAIL ', what, ': got "', got, '" want "', want, '"');
    fails := fails + 1;
  end;
end;

{ the two spellings, side by side }
function ByName(v: Variant): Int64;   begin ByName := v; end;
function ByResult(v: Variant): Int64; begin Result := v; end;

{ a GLOBAL variant as the source, not a parameter }
function FromGlobal: Int64;           begin FromGlobal := g; end;

{ the other result types the missing conversion reached }
function AsDouble(v: Variant): Double;      begin AsDouble := v; end;
function AsAnsi(v: Variant): AnsiString;    begin AsAnsi := v; end;
function AsShort(v: Variant): string;       begin AsShort := v; end;
function AsChar(v: Variant): Char;          begin AsChar := v; end;
function AsBool(v: Variant): Boolean;       begin AsBool := v; end;

{ a NESTED function assigning its own result by name }
function Outer: Int64;
  function Inner: Int64;
  begin
    Inner := g;
  end;
begin
  Outer := Inner;
end;

{ Exit(v) with a Variant operand and an ordinal result }
function ExitForm(v: Variant): Int64;
begin
  Exit(v);
end;

{ the name-as-Result synonym through a selector — these already worked }
function RecResult: TP;
begin
  RecResult.x := 7;
  RecResult.y := 9;
end;

function DynResult: TDyn;
begin
  SetLength(DynResult, 2);
  DynResult[0] := 4;
  DynResult[1] := 5;
end;

var
  r: TP;
  d: TDyn;
  dbl: Double;
begin
  fails := 0;
  g := 5000000000;

  ChkI('name spelling', ByName(g), 5000000000);
  ChkI('Result spelling', ByResult(g), 5000000000);
  ChkI('global source', FromGlobal, 5000000000);
  ChkI('nested function', Outer, 5000000000);
  ChkI('Exit form', ExitForm(g), 5000000000);

  g := 2.5;
  dbl := AsDouble(g);
  if (dbl < 2.4999) or (dbl > 2.5001) then
  begin
    writeln('FAIL double result: got ', dbl:0:4, ' want 2.5000');
    fails := fails + 1;
  end;

  g := 'hey';
  ChkS('ansistring result', AsAnsi(g), 'hey');
  ChkS('shortstring result', AsShort(g), 'hey');

  g := 'q';
  if AsChar(g) <> 'q' then
  begin
    writeln('FAIL char result: got ', AsChar(g), ' want q');
    fails := fails + 1;
  end;

  g := True;
  if not AsBool(g) then
  begin
    writeln('FAIL boolean result: got FALSE want TRUE');
    fails := fails + 1;
  end;

  r := RecResult;
  ChkI('record field by name', r.x * 100 + r.y, 709);
  d := DynResult;
  ChkI('dynarray element by name', d[0] * 100 + d[1], 405);

  if fails = 0 then writeln('ALL OK') else writeln(fails, ' FAILURES');
end.
