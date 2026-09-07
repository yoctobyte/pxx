program test_unnamed_managed_temps_are_released;
{ THE SCOPE-EXIT SWEEP MUST RELEASE UNNAMED COMPILER TEMPS, NOT JUST DECLARED
  LOCALS -- and this test exists because the tree contains a comment that reads
  like permission to skip them.

  `ir_codegen.inc:13838` says an unnamed temp "does not outlive the statement
  that minted it". That is TRUE and it is a claim about the temp's VALUE, which
  is what entitles the ZERO-INIT pass to re-scan: re-zeroing something dead is
  harmless. The release loop needs a different claim -- that OWNERSHIP of what
  the temp REFERENCES was transferred or dropped inside that statement. The two
  are not the same and one does not imply the other.

  Measured 2026-09-07 by building exactly that change (unnamed locals excluded
  from SymSkipScopeExitRelease) and running this program under the census:

      20000 iterations   live=75189    (against live=5 unmodified)
      80000 iterations   live=309011   -- 4.11x for 4x the work

  Proportional to iterations, which is the signature of a per-call leak. ~3.8 of
  the ~19 temps this body mints per iteration hold the ONLY reference at scope
  exit. In `ParseFactorCore` 609 of 619 managed slots are unnamed (frank-subcoord,
  91d33e053), so the sweep is ~98% temps and ~98% of it is load-bearing.

  WHY THIS TEST AND NOT AN OUTPUT ASSERTION: a leak does not corrupt. Every
  WriteLn below is correct with the releases removed, so `expect_same` alone
  certifies the leak as fine. Only the census can see it.

  The body declares TWO names and mints everything else, so a guard that only
  covered declared locals would pass while this failed. }
function Tag(n: Integer): AnsiString;
begin
  Tag := 'x' + Chr(65 + n mod 26) + 'y';
end;
function Wrap(const a, b: AnsiString): AnsiString;
begin
  Wrap := '<' + a + '|' + b + '>';
end;
procedure Churn(n: Integer);
var s: AnsiString;
begin
  { every operand below is a temp the programmer never named }
  s := Wrap(Tag(n) + Tag(n + 1), Tag(n + 2) + Wrap(Tag(n), Tag(n + 3)));
  if Length(s) = 0 then WriteLn('impossible');
end;
var k: Integer;
begin
  for k := 1 to 20000 do Churn(k);
  WriteLn('MINT OK');
end.
