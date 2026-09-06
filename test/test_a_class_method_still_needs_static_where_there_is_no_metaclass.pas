program test_a_class_method_still_needs_static_where_there_is_no_metaclass;
{ THE POSITIVE CONTROL FOR NARROWING THE RECORD METACLASS RULE, and it did not
  exist before this file: the rule "a class method of a record must be declared
  static" (terecs5) was asserted NOWHERE in the suite, so narrowing it -- or
  deleting it outright -- would have been invisible.

  The rule is correct and stays for every target that genuinely has no
  metaclass. A non-static class method dispatches on the runtime class
  reference, and these three have none:

    ROW A  a plain record
    ROW B  `record helper for <record>`
    ROW C  `type helper for LongInt`

  What was over-broad is that `class helper for <class>` was parsed by the same
  machinery -- a helper lives in the UCls tables with UClsIsRecord set -- and
  its target DOES have a metaclass. That case is now accepted and is asserted in
  test_a_class_helper_can_declare_a_class_method.

  ONE ROW PER COMPILE, SELECTED BY -dROW_x, because the check is an Error() and
  Error() halts: three rows in one file report only the first, and a grep that
  matches once passes whether the other two are refused or silently accepted.

  Refusing here is not an FPC-parity question -- fpc refuses all three too, for
  its own parsing reasons -- it is that a class method without a class reference
  has nothing to dispatch on. Us refusing is the specification.
  bug-p-a-class-helpers-class-method-is-refused-by-the-record-metaclass-rule }
{$mode objfpc}

type
  TR = record
    x: Integer;
{$ifdef ROW_A}
    class function BadA: LongInt;
{$endif}
  end;

{$ifdef ROW_B}
  TRH = record helper for TR
    class function BadB: LongInt;
  end;
{$endif}

{$ifdef ROW_C}
  TIH = type helper for LongInt
    class function BadC: LongInt;
  end;
{$endif}

{$ifdef ROW_A}
class function TR.BadA: LongInt; begin BadA := 1; end;
{$endif}
{$ifdef ROW_B}
class function TRH.BadB: LongInt; begin BadB := 1; end;
{$endif}
{$ifdef ROW_C}
class function TIH.BadC: LongInt; begin BadC := 1; end;
{$endif}

var r: TR;
begin
  r.x := 5;
  WriteLn('plain record still compiles ', r.x);
end.
