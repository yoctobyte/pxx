unit olf_pshadow;
{ A PASCAL unit that redefines an intrinsic spelling. Own-language-first must
  NOT touch this case: both sides are Pascal, so there is no cross-language
  precedence to apply and ordinary unit-shadows-builtin must still win.

  FPC does the same thing, which is why it is the control — a rule that made
  the intrinsic win here would be a dialect divergence, not a fix.
  feature-a-own-language-first-symbol-resolution }
interface
function Exp(x: Double): Double;
implementation
function Exp(x: Double): Double;
begin
  Exp := 77.0;
end;
end.
