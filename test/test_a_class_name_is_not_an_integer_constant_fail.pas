program test_a_class_name_is_not_an_integer_constant_fail;
{ The other half of bug-p-a-class-const-is-not-a-constant-when-named-through-its-type:
  the metaclass-typed-const arm tested the destination with `<> tyRecord`, which
  is every slot but one, so a class NAME initialised an Integer and the VMT
  address was stored in it -- pxx printed 4261440 where fpc 3.2.2 refuses with
  `Illegal expression`. A metaclass const is tyPointer; nothing else may take
  this arm. }
{$mode delphi}
type
  TA = class
  end;
const
  V2: Integer = TA;
begin
  WriteLn(V2);
end.
