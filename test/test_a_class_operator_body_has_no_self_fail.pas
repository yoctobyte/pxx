program test_a_class_operator_body_has_no_self_fail;
{$MODE DELPHI}
{ THE NEGATIVE CONTROL for test_a_class_operator_body_sees_its_own_record.pas,
  and the reason that fix sets CurMethClass and NOT CurSelfClass.

  A class operator is STATIC. Its body is a member of the record for the purpose
  of NAMES -- class vars, class consts, nested types -- and it has no instance,
  so a bare FIELD name must stay unresolved. The only object in scope is the
  operator's own `var` parameter.

  Setting CurSelfClass instead of (or as well as) CurMethClass is the tempting
  one-word version of that fix, and it would compile this file. fpc 3.2.2
  refuses it too, with `Pointer to object expected` -- a different wording for
  the same rule, which is deferred, not a defect.

  Kept as a %FAIL fixture because the passing test cannot express it: a file
  that compiles cannot assert that something does not. }
type
  TF = record
    I: Integer;
    class operator Initialize(var a: TF);
  end;

class operator TF.Initialize(var a: TF);
begin
  I := 5;        { no Self here -- must NOT resolve to the field }
end;

var
  f: TF;
begin
  writeln(f.I);
end.
