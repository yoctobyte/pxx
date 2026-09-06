program test_a_class_property_cannot_be_streamed;
{ `published` AND `stored` ARE TWO SPELLINGS OF ONE RULE, and we implemented one.

  A class property has no instance, so nothing about streaming applies to it.
  fpc refuses both spellings, and the two fpc-testsuite %FAIL rows say it in one
  sentence written twice by the same author:

    tclass14a  "class properties are not for sreaming therefore 'stored' is not
                supported"
    tclass14b  "class properties are not for sreaming therefore publishing them
                is not supported"

  pxx has refused the `published` half for some time (`a class property cannot
  be published`). The `stored` half was not a divergence anyone chose -- it was
  unreachable, because `stored` was refused on EVERY property, so the question
  was never asked. Adding `stored` support made it askable, and the answer had
  to be the same one. BOTH ROWS ARE HERE BECAUSE ONE ROW CANNOT SHOW THAT THEY
  ARE ONE RULE: a file asserting only `stored` passes just as well against a
  tree where the two arms have drifted apart again.

  THE ARGUMENT IS INTERNAL CONSISTENCY, NOT FPC PARITY. Us accepting what fpc
  rejects is not a defect on its own, and without the sibling arm already in the
  tree this would have been a divergence we chose and recorded. It is the
  sibling that makes it normalise-dont-special-case instead.

  ROW C IS THE POSITIVE CONTROL AND IT IS THE ENTIRE RISK: a class property with
  NO streaming clause is legal and common, and a refusal written one token too
  wide takes it with them. It is asserted by COMPILING, below.

  ONE ROW PER COMPILE, SELECTED BY -dROW_x, because the check is an Error() and
  Error() halts: two rows in one file report only the first, and the second
  assertion could not fail.
  feature-p-a-property-stored-clause-is-not-supported }
{$mode delphi}

type
  TC = class
  private
    FF: Integer;
  public
{$ifdef ROW_A}
    published class property CP: Integer read FF write FF;      { the publish half }
{$endif}
{$ifdef ROW_B}
    class property CS: Integer read FF write FF stored False;   { the stored half }
{$endif}
    { ROW C, always compiled: a class property with no streaming clause at all }
    class property CPlain: Integer read FF write FF;
  end;

var
  t: TC;
begin
  t := TC.Create;
  WriteLn(t.CPlain);
end.
