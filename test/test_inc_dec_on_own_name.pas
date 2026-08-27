program test_inc_dec_on_own_name;
{ `Inc(FuncName)` / `Dec(FuncName[i])` — the bare OWN NAME of the enclosing
  function, FPC's synonym for `Result`. The expression-read arm knew the rule;
  the Inc/Dec arm resolved its target with a bare FindSym, which cannot see a
  PROC name, and reported `undefined variable (FuncName)`. FPC's own
  cutils.pas:1429 grows a shortstring with `inc(minilzw_encode[0])`.
  bug-p-inc-dec-does-not-accept-the-enclosing-functions-own-name }
{$mode objfpc}

type
  TRec = record n: Integer; end;

function Counted: Integer;
begin
  Counted := 10;
  Inc(Counted);
  Inc(Counted, 5);
  Dec(Counted, 2);
end;

function Built: shortstring;
begin
  Built := '';
  Inc(Built[0]); Built[Length(Built)] := 'x';
  Inc(Built[0]); Built[Length(Built)] := 'y';
  Inc(Built[0]); Built[Length(Built)] := 'z';
  Dec(Built[0]);
end;

function Boxed: TRec;
begin
  Boxed.n := 1;
  Inc(Boxed.n, 41);
end;

function Shadowed: Integer;
var Shadowed_: Integer;
begin
  Shadowed_ := 0;
  Shadowed := 100;
  Inc(Shadowed_);
  Inc(Shadowed);
  Shadowed := Shadowed + Shadowed_;
end;

{ a local that SHADOWS the function name still wins — Inc must not hijack it }
function Sums(n: Integer): Integer;
var i, acc: Integer;
begin
  acc := 0;
  for i := 1 to n do Inc(acc, i);
  Sums := acc;
  Inc(Sums);
end;

begin
  writeln('a ', Counted);
  writeln('b ', Built, '|', Length(Built));
  writeln('c ', Boxed.n);
  writeln('d ', Shadowed);
  writeln('e ', Sums(4));
  writeln('OK');
end.
