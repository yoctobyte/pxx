program test_an_implicit_conversion_operator_is_chosen_without_regard_to_declaration_order;
{$mode objfpc}{$H+}
{ WHICH IMPLICIT CONVERSION A STORE TAKES, AND WHAT AMBIGUITY MEANS.

  `operator :=(const a: TTest): TString80` and the same operator returning
  TString90 were refused as DUPLICATES. fpc 3.2.2 accepts both declarations and
  refuses at the STORE instead, if it refuses at all -- same verdict, different
  reason, and it cost the two rows fpc actually compiles.

  The rule, measured cell by cell against fpc 3.2.2 because every obvious
  reading is wrong in some cell:

    sized80 alone           -> TString80   sized80   a lone sized one is used
    sized80 alone           -> TString90   sized80   so capacity does NOT filter
                              (those two live in the LONE fixture beside this
                               one -- see the oracle note below for why they
                               cannot share a program with these rows)
    sized80 + generic       -> TString80   generic   generic BEATS an exact
                                                     capacity match
    sized80+generic+sized90 -> TString80   generic
    sized80 + sized90       -> TString80   REFUSED   nothing to prefer, so fpc
                                                     does not choose at all

  Row 3 is what rules out "prefer the closest capacity" -- an exact-capacity
  operator LOSES to the generic. Row 5 is what rules out "take the first
  applicable one". So the implementation is a rank plus a TIE TEST, and a tie is
  a refusal rather than a choice.

  `orderA`/`orderB` are the two DECLARATION ORDERS of one operator set, and they
  are why this fixture exists in this shape: the answer must not depend on which
  conversion was written first. They are separate source records because the
  operator table is keyed on the source type, so two orders need two sources.

  EVERY DESTINATION TYPE HERE IS CONVERTED TO BY EXACTLY ONE SOURCE RECORD, and
  that is a constraint on the ORACLE, not a property under test. Measured, and it
  is why this fixture was split in two: with `TLone -> TS80` and `TOther -> TS80`
  both declared, fpc refuses `s80 := lone` (`Incompatible types: got "TLone"
  expected "TString80"`) even though exactly one operator is applicable to a
  TLone. Adding any THIRD record with a ShortString conversion refuses it too.
  fpc appears to resolve an implicit conversion by DESTINATION before it checks
  which source the operator actually takes, so a program with several converting
  records is not one it answers reliably. pxx compiles all of them, and us
  accepting what fpc rejects is not a defect -- but fpc cannot be the oracle for
  a program shaped that way, so neither fixture is shaped that way.

  ONE DELIBERATE DIVERGENCE, MEASURED AND NOT ASSERTED HERE. With all three
  operators declared and the destination a plain ShortString, fpc returns the
  FIRST-DECLARED SIZED one -- `sized80` for one order and `sized90` for the
  other, from the same program. That is declaration order deciding an overload,
  which is not a rule to reproduce; pxx answers the generic for both orders. The
  row is left out rather than pinned to either answer, and the divergence is
  recorded on the ticket. Every row below is one where fpc is order-independent
  and pxx agrees with it.

  Oracle: fpc 3.2.2 -Mobjfpc -Sh.
  bug-p-a-conversion-operators-destination-string-capacity-has-no-carrier }
type
  TS80 = string[80]; TS90 = string[90];
  TS100 = string[100]; TS110 = string[110];
  TA = record v: LongInt; end;
  TB = record v: LongInt; end;

{ order A: sized, generic, sized }
operator := (const a: TA): TS80;         begin Result := 'A-sized80'; end;
operator := (const a: TA): ShortString;  begin Result := 'A-generic'; end;
operator := (const a: TA): TS90;         begin Result := 'A-sized90'; end;

{ order B: the same three shapes, the sized ones written the other way round }
operator := (const a: TB): TS110;        begin Result := 'B-sized110'; end;
operator := (const a: TB): ShortString;  begin Result := 'B-generic'; end;
operator := (const a: TB): TS100;        begin Result := 'B-sized100'; end;

var
  a: TA; b: TB;
  s80: TS80; s90: TS90; s100: TS100; s110: TS110;
begin
  a.v := 1; b.v := 1;
  { the generic wins over an exact capacity match, in BOTH declaration orders }
  s80  := a; WriteLn('orderA-80   ', s80);
  s90  := a; WriteLn('orderA-90   ', s90);
  s100 := b; WriteLn('orderB-100  ', s100);
  s110 := b; WriteLn('orderB-110  ', s110);
end.
