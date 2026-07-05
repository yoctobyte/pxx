program test_impl_static_and_pchar_index;
{ Regression: two small parser gaps closed together.
  1. `static;` (and `reintroduce;`) directive on a class-method IMPLEMENTATION
     header — the interface loop already accepted them; the impl loop did not.
  2. PChar(expr)[i] — indexing a built-in pointer-cast result (ASTIVal -2/-1
     adapter, no alias entry). Element is a char, byte stride. }

type
  TFoo = class
    class function Bar: Integer; static;
    class function Baz: Integer; reintroduce; static;
  end;

class function TFoo.Bar: Integer; static;
begin
  Bar := 42;
end;

class function TFoo.Baz: Integer; reintroduce; static;
begin
  Baz := 7;
end;

var
  ok, total: Integer;

procedure Check(cond: Boolean; msg: string);
begin
  total := total + 1;
  if cond then ok := ok + 1
  else writeln('FAIL: ', msg);
end;

var
  s: AnsiString;
  i: Integer;
  acc: string;
begin
  ok := 0; total := 0;

  Check(TFoo.Bar = 42, 'impl-side static; on class function');
  Check(TFoo.Baz = 7, 'impl-side reintroduce; static;');

  s := 'hello';
  Check(PChar(s)[0] = 'h', 'PChar(s)[0]');
  Check(PChar(s)[4] = 'o', 'PChar(s)[4]');

  acc := '';
  for i := 0 to 4 do
    acc := acc + PChar(s)[i];
  Check(acc = 'hello', 'PChar(s)[i] across a loop');

  writeln('total ok ', ok, ' / ', total);
end.
