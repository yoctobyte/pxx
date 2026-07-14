{ %FAIL-style negative: an abstract method inside a `sealed` class.

  An abstract method has no body and depends on a descendant to supply one. A sealed
  class can never have a descendant, so the method could never be implemented and a
  call would dispatch into nothing (tsealed2). See test_sealed_class_fail.pas. }
program test_sealed_abstract_method_fail;
{$mode objfpc}
type
  TSealedClass = class sealed
  public
    procedure Run; virtual; abstract;
  end;
begin
end.
