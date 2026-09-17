program test_p_a_conditional_directive_can_test_in_over_a_set_constant;
{ `{$if (cs_opt_use_load_modify_store in supported_optimizerswitches)}` is
  FPC's nld.pas:700, and it needs four things the conditional evaluator did not
  have: a SET on its value stack, set-union folding across named constants, an
  enum MEMBER's ordinal, and the `in` operator itself. pxx answered
  `conditional directive: expected operator` at the `in` -- which describes the
  grammar and not the program: `in` was read as a VALUE in operator position,
  so the guard that fired was the one for two operands in a row.

  EVERY MEMBERSHIP ROW IS PAIRED WITH A NON-MEMBERSHIP ROW, and that pairing is
  the point rather than thoroughness. A set walk that over-approximates -- one
  that returned a FULL mask on any shape it did not understand -- answers `yes`
  to every `in` test and passes a file containing only positive rows. The `no`
  rows are the ones that can fail, so they are what makes this a guard.

  AND THE MEMBER UNDER TEST IS NOT ALWAYS THE FIRST ELEMENT. A folding bug that
  kept only the first term of `A + B`, or only the first element of `[a, b, c]`,
  passes every row whose answer sits at position zero. IN_SECOND_TERM and
  IN_LAST_ELEMENT exist to put the interesting element somewhere a first-wins
  bug cannot rescue.

  WHAT IS DELIBERATELY NOT HERE. An enum with an EXPLICIT value in its body
  (`(a, b := 5, c)`) makes position stop meaning ordinal, and this walk declines
  the whole enum rather than counting commas -- a wrong ordinal in a set test
  does not fail, it takes the other branch. fpc answers that case correctly and
  we refuse it; refusing is the safe direction and a differing diagnostic is
  deferred, not a defect. That control must not compile, so it is asserted by
  the Makefile row beside this one.

  AND SET DIFFERENCE IS PART OF THE SAME FEATURE, NOT A NEIGHBOUR. FPC's
  supported_optimizerswitches (x86_64/cpuinfo.pas:205) is three named constants
  joined with `+` and then `- [cs_opt_level1,cs_opt_level2,cs_opt_level3]`,
  with its own source comment saying why it takes them back out. A walk that
  knows only `+` does not merely decline that shape -- wired naively it would
  OVER-APPROXIMATE it, and an over-approximating set answers `yes` for an
  element the program removed deliberately. The REMOVED_* rows below are the
  ones that can fail; the present-after-difference rows cannot.

  `*` (intersection) is deliberately absent and is REFUSED by the walk rather
  than folded: it binds tighter than `+` and `-`, so a left-to-right fold would
  compute (a + b) * c where the source wrote a + (b * c). Same reason as the
  explicit-value enum above -- a wrong set does not fail, it takes the other
  branch.

  Byte-identical to fpc 3.2.2 on all 14 rows below, measured. }
var fails: Integer;

procedure Check(const nm: AnsiString; got, want: Boolean);
begin
  if got = want then WriteLn(nm, '=', 'yes')
  else begin WriteLn(nm, '=NO'); Inc(fails); end;
end;

type
  sw = (s0, s1, s2, s3, s4, s5, s6);

const
  g1 = [s0, s1];
  g2 = [s3];
  gu = g1 + g2;          { the union shape FPC's cpuinfo.pas:139 has }
  gempty = [];
  grange = [s1..s4];
  glast = [s0, s2, s6];  { the interesting element is LAST }
  gbig = [s0, s1, s2, s3, s4];
  gdrop = [s1, s4];      { s4 is LAST in the subtrahend, s1 is first }
  gdiff = gbig - gdrop;  { the shape cpuinfo.pas:205 has }
  gmix = g1 + grange - gdrop;   { `+` then `-`, left to right }

{ A member of the FIRST union term. }
{$if (s0 in gu)}
  IN_FIRST_TERM = True;
{$else}
  IN_FIRST_TERM = False;
{$endif}
{ ...and of the SECOND, which a fold that kept only the left term would miss. }
{$if (s3 in gu)}
  IN_SECOND_TERM = True;
{$else}
  IN_SECOND_TERM = False;
{$endif}
{ NOT a member of either. This row is the one an over-approximating fold fails. }
{$if (s5 in gu)}
  NOT_IN_UNION = True;
{$else}
  NOT_IN_UNION = False;
{$endif}
{ The empty set contains nothing -- and `[]` is also the value a walk that gave
  up would produce, so the row above is what separates the two readings. }
{$if (s0 in gempty)}
  IN_EMPTY = True;
{$else}
  IN_EMPTY = False;
{$endif}
{ A range interior, and a value beyond its top. }
{$if (s2 in grange)}
  IN_RANGE_MID = True;
{$else}
  IN_RANGE_MID = False;
{$endif}
{$if (s6 in grange)}
  PAST_RANGE_TOP = True;
{$else}
  PAST_RANGE_TOP = False;
{$endif}
{ The LAST element of a literal, and one that is absent from the same literal. }
{$if (s6 in glast)}
  IN_LAST_ELEMENT = True;
{$else}
  IN_LAST_ELEMENT = False;
{$endif}
{$if (s1 in glast)}
  ABSENT_FROM_LAST = True;
{$else}
  ABSENT_FROM_LAST = False;
{$endif}
{ SET DIFFERENCE. A member the subtraction did NOT touch survives... }
{$if (s2 in gdiff)}
  SURVIVES_DIFF = True;
{$else}
  SURVIVES_DIFF = False;
{$endif}
{ ...the FIRST element of the subtrahend is gone... }
{$if (s1 in gdiff)}
  REMOVED_FIRST = True;
{$else}
  REMOVED_FIRST = False;
{$endif}
{ ...and so is its LAST, which a fold keeping only the first term would leave. }
{$if (s4 in gdiff)}
  REMOVED_LAST = True;
{$else}
  REMOVED_LAST = False;
{$endif}
{ `+` and `-` in one expression, applied left to right: g1 = [s0,s1] unioned
  with grange = [s1..s4], then [s1,s4] taken out, leaves s0, s2, s3. }
{$if (s1 in gmix)}
  MIXED_REMOVED = True;
{$else}
  MIXED_REMOVED = False;
{$endif}
{ `in` composes with `and`, at relational precedence: both sides must be
  evaluated as memberships before the `and` sees them. }
{$if (s1 in g1) and (s3 in g2)}
  BOTH_IN = True;
{$else}
  BOTH_IN = False;
{$endif}
{ ...and under `not`, which must negate the membership and not the set. }
{$if not (s5 in gu)}
  NOT_MEMBER = True;
{$else}
  NOT_MEMBER = False;
{$endif}

begin
  fails := 0;
  Check('IN_FIRST_TERM', IN_FIRST_TERM, True);
  Check('IN_SECOND_TERM', IN_SECOND_TERM, True);
  Check('NOT_IN_UNION', NOT_IN_UNION, False);
  Check('IN_EMPTY', IN_EMPTY, False);
  Check('IN_RANGE_MID', IN_RANGE_MID, True);
  Check('PAST_RANGE_TOP', PAST_RANGE_TOP, False);
  Check('IN_LAST_ELEMENT', IN_LAST_ELEMENT, True);
  Check('ABSENT_FROM_LAST', ABSENT_FROM_LAST, False);
  Check('BOTH_IN', BOTH_IN, True);
  Check('NOT_MEMBER', NOT_MEMBER, True);
  Check('SURVIVES_DIFF', SURVIVES_DIFF, True);
  Check('REMOVED_FIRST', REMOVED_FIRST, False);
  Check('REMOVED_LAST', REMOVED_LAST, False);
  Check('MIXED_REMOVED', MIXED_REMOVED, False);
  WriteLn('fails=', fails);
  WriteLn('CONDSET OK');
end.
