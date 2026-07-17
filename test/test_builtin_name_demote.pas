program test_builtin_name_demote;
{ Regression: bug-pascal-unqualified-call-binds-builtin-over-used-unit.

  A used unit (myrand) declares Random(Integer), shadowing the System builtin
  Random(Int64). Before the fix, both lived in one overload set and the ARGUMENT
  WIDTH silently steered the pick: a literal bound the unit (exact Integer),
  a wider expression bound the builtin (exact Int64) -> two calls to "the same"
  Random routed to two different generators. The fix makes the builtin
  FALLBACK-ONLY: once a non-builtin routine of the name is in scope, every
  unqualified call binds the unit regardless of arg width.

  myrand.Random(n) = n*10, so:
    Random(1000) -> 10000   (was already unit: literal is exact Integer)
    Random(i+1)  -> 60      (was BUILTIN misbind before the fix; now unit)
  An explicit System.Random still reaches the builtin (in [0,6) here). }
uses myrand;
var i, a, b: Integer; sys: Int64;
begin
  RandSeed(1);
  i := 5;
  a := Random(1000);           { literal  -> unit  -> 10000 }
  b := Random(i + 1);          { wide expr -> unit  -> 60    (the fixed misbind) }
  sys := System.Random(i + 1); { qualified -> builtin -> [0,6) }
  writeln(a);
  writeln(b);
  if (sys >= 0) and (sys < 6) then writeln('sys-ok') else writeln('sys-BAD');
end.
