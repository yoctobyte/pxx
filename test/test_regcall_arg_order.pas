{ -O3 regcall phase 3 slice 2 (feature-callconv-register-args): Pascal
  left-to-right argument evaluation must hold when deferrable leaf args mix
  with complex, side-effecting siblings. A GLOBAL read before a call that
  mutates it is position-ordered (globals are never deferred); an addr-clean
  LOCAL may be deferred past the call precisely because the call cannot reach
  it. Also covers: deferred args in every register position around a middle
  complex arg, and an addr-taken local (var-param source) staying ordered.
  Output must be identical at every -O level (optdiff sweeps this). }
program test_regcall_arg_order;

var
  g: Int64;
  log: Int64;

function BumpG(step: Int64): Int64;
begin
  g := g + step;
  BumpG := step * 10;
end;

function Probe3(a, b, c: Int64): Int64;
begin
  Probe3 := a * 1000000 + b * 1000 + c;
end;

function Probe6(a, b, c, d, e, f: Int64): Int64;
begin
  Probe6 := a + b * 10 + c * 100 + d * 1000 + e * 10000 + f * 100000;
end;

procedure TakeAddr(var v: Int64);
begin
  v := v + 7;
end;

procedure Run;
var
  loc, aliased: Int64;
begin
  g := 5; loc := 3;

  { g read at position 1 BEFORE BumpG runs (position 2): must see 5, not 6.
    loc (addr-clean) deferred past BumpG legally: BumpG cannot write it. }
  log := Probe3(g, BumpG(1), loc);
  writeln('t1=', log, ' g=', g);

  { complex FIRST, globals after: both globals read AFTER the bump }
  log := Probe3(BumpG(1), g, g);
  writeln('t2=', log, ' g=', g);

  { deferred leaves in every position around a middle complex arg }
  log := Probe6(1, loc, BumpG(2), loc, 4, g);
  writeln('t3=', log, ' g=', g);

  { aliased local: TakeAddr(var) makes it addr-taken -> position-ordered.
    Read at position 1 must precede the mutation inside the position-2 call. }
  aliased := 100;
  TakeAddr(aliased);                       { aliased = 107; also marks addr-taken }
  log := Probe3(aliased, BumpG(3), aliased);
  writeln('t4=', log, ' aliased=', aliased);

  { two complex args: strict left-to-right side-effect order }
  g := 0;
  log := Probe3(BumpG(1), BumpG(10), g);
  writeln('t5=', log, ' g=', g);
end;

begin
  Run;
end.
