program test_a_lone_sized_conversion_operator_serves_any_string_destination;
{$mode objfpc}{$H+}
{ CAPACITY NEVER FILTERS AN IMPLICIT CONVERSION -- it only ranks.

  The companion to
  test_an_implicit_conversion_operator_is_chosen_without_regard_to_declaration_order,
  which asserts the RANK (a generic result beats an exact capacity match). This
  one asserts that the rank is not a FILTER: with a single `: string[40]`
  conversion declared and no generic anywhere, fpc 3.2.2 uses it for a
  `string[40]` destination AND for a `string[50]` one.

  That row is what makes the implementation a rank plus a tie test rather than a
  capacity match. Excluding on a capacity mismatch would leave `s50 := lone` with
  no operator, and a store that finds no conversion does not refuse -- it goes
  through RAW, which for a record into a string is a garbage length byte and a
  segfault in WriteLn. The same fall-through cost a segfault once already in this
  family (see OpConvResultCapRank in symtab.inc).

  SEPARATE PROGRAM FROM ITS COMPANION, and the reason is the oracle rather than
  the subject: fpc refuses `s40 := lone` as soon as ANY other record in the
  program also converts to a string, including through a plain ShortString
  operator -- `Incompatible types: got "TLone" expected "TS40"`, with exactly one
  operator applicable to a TLone. It appears to resolve by DESTINATION before
  checking which source the operator takes. pxx compiles those programs and us
  accepting what fpc rejects is not a defect, but fpc cannot be the oracle for
  one, so the two fixtures each hold a single converting record.

  THIS FIXTURE PASSES AT HEAD, DELIBERATELY, and saying so is the point: it is a
  REGRESSION GUARD, not evidence for the change it ships with. Its companion and
  the ambiguity fixture both go red without the fix; this one asserts the
  behaviour that must SURVIVE it. The rank added for the generic-beats-sized rule
  is one edit away from being written as a filter, and a filter is what breaks
  exactly this row -- silently, into a raw store. A guard whose control passes is
  worth having when what it guards is the thing a plausible implementation would
  break; it is only worthless when it could not fail for ANY implementation.

  Oracle: fpc 3.2.2 -Mobjfpc -Sh.
  bug-p-a-conversion-operators-destination-string-capacity-has-no-carrier }
type
  TS40 = string[40];
  TS50 = string[50];
  TLone = record v: LongInt; end;

operator := (const a: TLone): TS40; begin Result := 'lone40'; end;

var lone: TLone; s40: TS40; s50: TS50;
begin
  lone.v := 1;
  s40 := lone; WriteLn('lone-exact  ', s40);
  s50 := lone; WriteLn('lone-other  ', s50);
end.
