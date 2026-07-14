{ %FAIL-style negative: a value of one enum type assigned to a variable of another.

  Two enum types are distinct types with no implicit conversion (FPC). pxx used to
  accept this and store the RHS's ORDINAL: `c := banana` put TFruit's 1 into a TColor,
  which reads back as green. A wrong value, silently — and it is what let a
  {$SCOPEDENUMS} program pick up the shadowed member of the *other* enum (tenum4).

  The identity is carried on the symbol (SymEnumId) and, for a member const — which
  folds to a bare ordinal literal and would otherwise lose all trace of its enum — on
  the node (ASTEnumId).

  Positive cases (same-enum assign/compare, Ord(), a cast, a call result) stay legal:
  test/test_enum_identity_ok.pas. }
program test_enum_identity_fail;
type
  TColor = (red, green, blue);
  TFruit = (apple, banana, cherry);
var
  c: TColor;
begin
  c := banana;
  writeln(Ord(c));
end.
