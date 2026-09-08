program test_an_ambiguous_implicit_conversion_is_refused_at_the_store;
{$mode objfpc}{$H+}
{ MUST NOT COMPILE -- and the point is WHERE it is refused, not that it is.

  Two sized conversions from one record and no generic between them. Nothing
  ranks one above the other, so fpc 3.2.2 does not choose: it accepts BOTH
  DECLARATIONS and refuses at the STORE, `Incompatible types: got "TTest"
  expected "TString80"`. toperator92 and toperator95 are that program.

  pxx used to refuse the second DECLARATION as a duplicate conversion operator.
  Same verdict, different reason -- and the harness compares only whether a
  refusal happened, so those two rows passed while the compiler was wrong about
  what the program means. It also cost the rows fpc does compile, because a
  declaration check that cannot tell String[80] from String[90] refuses the
  legal pairs too.

  The other two outcomes are both worse than a refusal and both were reachable:
  picking one silently is accepted-invalid, and letting the store fall through
  with no conversion sends a record into a string RAW -- a garbage length byte
  and a segfault in WriteLn.

  Wired on the MESSAGE, not on the exit code, so that a refusal for some other
  reason cannot pass this fixture.
  bug-p-a-conversion-operators-destination-string-capacity-has-no-carrier }
type
  TString80 = string[80];
  TString90 = string[90];
  TTest = record v: LongInt; end;

operator := (const a: TTest): TString80; begin Result := 'eighty'; end;
operator := (const a: TTest): TString90; begin Result := 'ninety'; end;

var t: TTest; s80: TString80;
begin
  t.v := 1;
  s80 := t;
  WriteLn(s80);
end.
