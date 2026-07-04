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

{ slice 2b (-O3): straight-line multi-statement body with locals }
function SumSq(a: Integer; b: Integer): Integer; inline;
var t: Integer;
begin
  t := a + b;
  SumSq := t * t;
end;
function Poly(x: Integer): Integer; inline;
var t1: Integer; t2: Integer;
begin
  t1 := x * x;
  t2 := t1 + x;
  Poly := t2 + 1;
end;

{ slice 2a: if-then-else Result one-liner, inlined as a ternary }
function Min(a: Integer; b: Integer): Integer; inline;
begin if a < b then Min := a else Min := b; end;
function Max(a: Integer; b: Integer): Integer; inline;
begin if a > b then Max := a else Max := b; end;

{ ineligible: has a local + multiple if-statements → must degrade to a normal call }
function Clamp(v: Integer; lo: Integer; hi: Integer): Integer;
var r: Integer;
begin
  r := v;
  if r < lo then r := lo;
  if r > hi then r := hi;
  Clamp := r;
end;

var i, acc, g: Integer;

function Bump: Integer;
begin g := g + 100; Bump := g; end;

begin
  writeln(Sqr(9));                 { 81 }
  { slice 3: non-side-effect-free args → evaluated once into a temp }
  g := 5;
  writeln(Sqr(g + 1));             { (5+1)^2 = 36 }
  writeln(Blend(g * 2, g - 1, 4)); { 10*4 + 4*6 = 40+24 = 64 }
  { eval-order: temp-all-when-impure preserves left-to-right }
  g := 5;
  writeln(Blend(g, Bump, 0));      { a=5, b=Bump(105), w=0 -> 5*0 + 105*10 = 1050 }
  g := 5;
  writeln(Blend(Bump, g, 10));     { a=Bump(105), b=g(now 105), w=10 -> 105*10 + 105*0 = 1050 }
  { slice 2a ternary inline }
  writeln(Min(3, 8));              { 3 }
  writeln(Max(3, 8));              { 8 }
  writeln(Max(Min(5, 2), 9));      { 9 }
  g := 5;
  writeln(Min(g, Bump));           { 5 (g read before Bump) }
  { slice 2b (-O3) stmt-body inline (a no-op at -O0/-O1/-O2 -> still same output) }
  writeln(SumSq(2, 3));            { 25 }
  writeln(Poly(3));               { 9+3+1 = 13 }
  writeln(SumSq(Poly(2), 1));      { Poly(2)=7; SumSq(7,1)=64 }
  g := 5;
  writeln(SumSq(g, Bump));         { a=5, b=105 -> 110^2 = 12100 }
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
