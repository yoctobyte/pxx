{ Statement-level call in an inline body (-O3)
  (feature-opt-inline-bodies-with-a-statement-level-call): the AN_SEQ walker
  accepts a bare procedure-call statement, which blocked 67 distinct functions
  across the example corpus.

  THE ASSERTIONS ARE ABOUT SIDE-EFFECT COUNT AND ORDER, not values. A statement
  call exists to have an effect, so a value check is close to blind here: it
  cannot see an effect that ran twice, ran in the wrong order relative to the
  statements around it, or did not run at all when its result went unused.
  g below is the instrument; every Writeln of a value is secondary to it.

  Output identical at every -O level; the -O0 column is the oracle. }
program test_inline_stmt_call;

var g: Int64;

procedure Bump(n: Int64);
begin
  g := g + n;
end;

procedure Bump2(n: Int64);
begin
  g := g * 2 + n;
end;

{ The shape the slice admits: effect, then Result. }
function EffThenRes(x: Int64): Int64;
begin
  Bump(x);
  EffThenRes := x * 2;
end;

{ ORDER DISCRIMINATOR: Bump and Bump2 do not commute, so a splice that reorders
  them changes g while every returned value stays correct. }
function TwoEffects(x: Int64): Int64;
begin
  Bump(x);
  Bump2(x);
  TwoEffects := x + 1;
end;

{ The effect sits BETWEEN two assignments, so it must not float to either end. }
function Sandwich(x: Int64): Int64;
var t: Int64;
begin
  t := x * 3;
  Bump(t);
  Sandwich := t + 1;
end;

{ POSITIVE CONTROL for the by-ref guard: a `var` parameter lets the callee write
  a caller local, which the retention dataflow does not model. This must NOT
  inline. It is here to fail if the guard is ever dropped -- and it is a real
  behavioural row, not a compile-only one, because a wrong answer here is the
  symptom the guard prevents. }
procedure SetTo(var dst: Int64; v: Int64);
begin
  dst := v;
end;

function UsesVarParam(x: Int64): Int64;
var t: Int64;
begin
  t := 0;
  SetTo(t, x * 5);
  UsesVarParam := t;
end;

var i, a, b, c, d: Int64;
begin
  g := 0; a := 0;
  for i := 1 to 5 do a := a + EffThenRes(i);
  Writeln('EffThenRes ', a, ' g=', g);

  g := 0; b := 0;
  for i := 1 to 4 do b := b + TwoEffects(i);
  Writeln('TwoEffects ', b, ' g=', g);

  g := 0; c := 0;
  for i := 1 to 3 do c := c + Sandwich(i);
  Writeln('Sandwich   ', c, ' g=', g);

  d := 0;
  for i := 1 to 3 do d := d + UsesVarParam(i);
  Writeln('UsesVar    ', d);
end.
