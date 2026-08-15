program quick_canary_uses;
{ Quick-tier canary for NAMESPACE SCOPE. A unit's imports belong to that unit
  and to nothing above it, and this is the positive half: a legitimate chain
  still resolves through three units and both uses sections.

  It exists because gate.sh quick could not see this at all. When `uses` went
  non-transitive the quick tier stayed green while five sources in the corpus
  went red, all of them found HOURS later by Track T's native sweep, because
  nothing in the quick tier imported deeply enough to leak. Broad-not-deep is
  the right shape for the rest of the tier; this one is deep on purpose.

  The negative half is quick_canary_uses_fail.pas, which must NOT compile.
  Both halves matter: a regression that re-opens the leak keeps this file
  green, and one that over-tightens keeps the _fail file red. }
uses udeep1;
begin
  { 42 + 1 + 7 + 1 + 3 + 4 + 122 = 180 }
  writeln('uses depth ok ', Outer);
end.
