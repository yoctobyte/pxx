{ A stackless generator called AFTER another stackless generator has been
  declared. The call site found each argument's instance slot through the
  parameter's symbol, and by then H had reused those symbol indices, so G's
  arguments were seeded into the wrong slots: `1 3 0` instead of `1 2 3`,
  silently, on every target -- and a crash when the parameter was a string.
  bug-a-a-stackless-generator-called-after-a-later-generator-seeds-the-wrong-slots }
program test_stackless_generator_called_after_a_later_generator;
uses slgen;

function G(a, b, c: Integer): Integer; generator; stackless;
begin
  yield a; yield b; yield c;
end;

function S(n: Integer; t: AnsiString): Integer; generator; stackless;
begin
  yield n; yield Length(t);
end;

function H(k: Integer): Integer; generator; stackless;
var x: Integer;
begin
  x := k; yield x;
end;

var v: Integer; w: AnsiString;
begin
  for v in G(1, 2, 3) do WriteLn(v);
  w := 'abcde';
  for v in S(7, w) do WriteLn(v);
  for v in H(9) do WriteLn(v);
end.
