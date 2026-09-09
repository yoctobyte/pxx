program test_a_nested_forward_pointer_does_not_see_another_classes_type_fail;
{$mode objfpc}
{ %FAIL: a nested `type` section is a SCOPE, and widening the forward-pointer
  drain to see nested aliases must not make it see ANOTHER class's.

  This is the control that makes
  bug-p-a-forward-pointer-in-a-class-type-section-is-not-resolved's fix correct
  rather than merely working. The fix replaced FindNestedType with
  ClassDeclaresTypeNamed in the drain, and the easy wrong version is to fall back
  to an unscoped alias scan -- which compiles this file. fpc 3.2.2 refuses it too
  ("Forward type not resolved: PB"), so this is parity and not our own rule.

  The other half of the same guard is a name declared NOWHERE, which the drain
  refused before and after; it is not a separate file because it cannot
  distinguish a scoped fix from an unscoped one. This one can.
  bug-p-a-forward-pointer-in-a-class-type-section-is-not-resolved }
type
  TOther = class
  private type
    PB = ^LongInt;          { declared here... }
  end;

  TFactory = class
  private type
    PA = ^PB;               { ...and must NOT be visible here }
  public
    class function Go: LongInt; static;
  end;

class function TFactory.Go: LongInt; begin Result := 0; end;

begin
  WriteLn(TFactory.Go);
end.
