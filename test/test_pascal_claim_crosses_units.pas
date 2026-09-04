{ feature-p-defineglobal-a-define-that-crosses-unit-boundaries — {$CLAIM X}
  outlives the unit that set it, {$DEFINE X} still does not, and {$UNDEF} cannot
  take a claim back.

  Five of these eight rows discriminate against a no-op: if {$CLAIM} were an
  ignored directive, `b` would claim too, `undef` would report the claim gone,
  and both include rows would report it lost. Two rows cannot fail on their own
  and are here to pin the SHAPE of the answer, not to catch a regression:

  - `early` — "no claim yet" is also what a no-op prints. It says the claim is
    not RETROACTIVE: a unit compiled before the claimer sees nothing.
  - `program` — likewise. pxx lexes a source file WHOLE (LexAll) before parsing
    it, so every conditional in the main program is resolved before its `uses`
    clause has compiled a single unit. The program is, in scan order, the first
    thing compiled, so a unit's later claim is not retroactive to it either —
    the same rule, not a second one, and the same reason a unit's plain
    {$DEFINE} has never reached the program. A program that wants the name takes
    the claim itself, above its own `uses`. }
program test_pascal_claim_crosses_units;
uses uclaim_early, uclaim_a, uclaim_b, uclaim_undef, uclaim_c, uclaim_d;
begin
  EarlyWho;
  AWho;
  BWho;
  UndefWho;
  IncWho;
  IncLater;
{$IFDEF UCLAIM_A_PLAIN}
  writeln('program: plain define LEAKED');
{$ELSE}
  writeln('program: plain define stayed in the unit');
{$ENDIF}
{$IFDEF PXX_TEST_CAP}
  writeln('program: sees the claim');
{$ELSE}
  writeln('program: scanned before its units, no claim');
{$ENDIF}
end.
