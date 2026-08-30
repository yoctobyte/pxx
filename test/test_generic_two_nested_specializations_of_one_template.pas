{ Two DIFFERENT specializations of the SAME inner template, from inside ONE
  enclosing generic: `specialize TCmp<T>.Size * 100 + specialize TCmp<U>.Size`.

  The sibling test (test_generic_nested_specialize_in_method_body) covers a
  nested specialization that appears only in a method body, and deliberately
  excluded this shape because it still failed when that one landed --
  `SizeOf: unknown type or variable`, pointing at the INNER template's own body,
  a line that is correct and compiles fine when only one of the two
  specializations is present. A diagnostic naming a line that is not wrong is
  the signature of a substitution still being loaded from the previous
  specialization, which is what the shape was suspected of.

  It is fixed. Not by a change aimed at it: it was already correct on pin v394
  (`53800fbeb0b66e11`), so one of the ordering fixes that landed around wall 6
  closed it as well, and nothing recorded which. That is exactly why this file
  exists -- an incidental fix has nothing guarding it, and the next change to
  the prerequisite scan has no way to know this shape was ever hard.

  Rows, all verified against FPC (-Mobjfpc), which prints the same:

    Get   -> 8       one nested specialization, one method (the easy row)
    Both  -> 804     SizeOf(Int64)*100 + SizeOf(LongInt) = 800 + 4
    TB    -> 401     a SECOND outer specialization of the same enclosing
                     template: SizeOf(LongInt)*100 + SizeOf(Byte) = 400 + 1

  The third row is the one that would catch a fix binding the FIRST outer
  specialization's arguments everywhere: that failure prints 804 twice, and the
  expected file distinguishes it. Both operands also differ in both rows
  (Int64/LongInt vs LongInt/Byte), so a result that is right for the wrong
  reason -- one operand contaminated, the other not -- lands on neither 804 nor
  401 rather than coinciding with a correct row.

  bug-p-two-different-nested-specializations-of-one-template-collide }
program test_generic_two_nested_specializations_of_one_template;
{$mode objfpc}{$H+}
type
  generic TCmp<T> = class
    class function Size: LongInt; static;
  end;
  generic TOrd<T, U> = class
    class function Get: LongInt; static;
    class function Both: LongInt; static;
  end;

class function TCmp.Size: LongInt; begin Result := SizeOf(T); end;

class function TOrd.Get: LongInt;
begin Result := specialize TCmp<T>.Size; end;

class function TOrd.Both: LongInt;
begin Result := specialize TCmp<T>.Size * 100 + specialize TCmp<U>.Size; end;

type
  TA = specialize TOrd<Int64, LongInt>;
  TB = specialize TOrd<LongInt, Byte>;

begin
  WriteLn(TA.Get);
  WriteLn(TA.Both);
  WriteLn(TB.Both);
end.
