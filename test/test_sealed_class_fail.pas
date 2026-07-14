{ %FAIL-style negative: deriving from a `sealed` class.

  `sealed` was parse-and-ignore, so the whole hierarchy below a sealed class was
  silently accepted — the modifier documented an intent the compiler never checked
  (tsealed1). Two sibling rules land with it, each with its own negative test:

    - test_sealed_abstract_method_fail.pas — a sealed class cannot declare an abstract
      method: only a descendant could ever supply the body, and there can be none.
    - test_sealed_abstract_class_fail.pas — `class abstract sealed` is a contradiction
      ("must be derived from" vs "cannot be").

  `class sealed(TParent)` and a plain `class abstract` stay legal:
  test/test_sealed_ok.pas. }
program test_sealed_class_fail;
{$mode objfpc}
type
  TSealedClass = class sealed
  public
  end;

  TDescendant = class(TSealedClass)
  public
  end;

var
  d: TDescendant;
begin
  d := TDescendant.Create;
  writeln(PtrUInt(d));
end.
