program test_inline_expand;
{ feature-inline-routines v1: pure-expression leaf inline (-O2). Output must be
  identical at -O0 (no inline) and -O2 (inline fires) — the test-opt differential
  gate compares them. Exercises arithmetic, boolean, multi-param, nesting, loops,
  const args (foldable), and an ineligible case that degrades to a normal call. }

function Sqr(x: Integer): Integer; inline;
begin Sqr := x * x; end;

function Half(x: Integer): Integer; inline;
begin Half := x div 2; end;

function IsEven(x: Integer): Boolean; inline;
begin IsEven := (x and 1) = 0; end;

function Blend(a: Integer; b: Integer; w: Integer): Integer; inline;
begin Blend := a * w + b * (10 - w); end;

{ ineligible: has a local + control flow → must degrade to a normal call, still correct }
function Clamp(v: Integer; lo: Integer; hi: Integer): Integer;
var r: Integer;
begin
  r := v;
  if r < lo then r := lo;
  if r > hi then r := hi;
  Clamp := r;
end;

var i, acc: Integer;
begin
  writeln(Sqr(9));                 { 81 }
  writeln(Sqr(3) + Sqr(4));        { 25 }
  writeln(Sqr(Sqr(2)));            { outer=call, inner=inline; 16 }
  writeln(Half(15));               { 7 }
  writeln(IsEven(8));              { TRUE }
  writeln(IsEven(7));              { FALSE }
  writeln(Blend(2, 5, 3));         { 2*3 + 5*7 = 6+35 = 41 }
  writeln(Sqr(5));                 { const arg → 25 }
  writeln(Clamp(42, 1, 9));        { ineligible → 9 }
  acc := 0;
  for i := 1 to 6 do acc := acc + Sqr(i);   { 1+4+9+16+25+36 = 91 }
  writeln(acc);
end.
