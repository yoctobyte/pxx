program test_operator_unary_address_and_boolean_and;
{ Track P — two operator-overload defects that the DELPHI-NAME test cannot reach,
  written in the objfpc symbol spelling on purpose so an older compiler gets past
  the declarations and fails on the thing under test instead of on the lexeme.
  Both were reachable in source pxx already claimed to support.

  1. A UNARY OVERLOAD IN AN ADDRESS POSITION. `b := -a` and `(-a).F` are one
     expression in two positions. The overload used to be TAGGED onto AN_NEG /
     AN_NOT for ir.inc to re-resolve, and neither is one of the kinds
     ASTNodeIsCall names, so IRLowerAddress had no arm and the field selection
     died with `IR_UNSUPPORTED ... (kind 6)` / `(kind 7)`. Measured on pin
     v-current: it refuses this file at the `(-a).F` line.

  2. AN OVERLOADED `and` THAT RETURNS Boolean. This one printed a WRONG VALUE,
     which is why it needs its own row rather than a compile check: the parser
     tags the AN_BINOP with the overload's result type, so two RECORD operands
     reached ir.inc's short-circuit and/or arm wearing tyBoolean and were
     evaluated as two flags — each record lowering to its own address, never
     nil — so `a and b` answered True and the operator was never called.
     Measured on pin v-current: prints TRUE. fpc 3.2.2 prints FALSE.

     THE EXPECTED VALUE IS FALSE AND THAT IS THE WHOLE ASSERTION. 1 and 2 is 0,
     so False is an answer only a real call can produce; a row whose operands
     ANDed to something non-zero would have printed True either way and could
     not have failed. }

type
  TFoo = record F: Integer; end;

operator -   (a: TFoo) r: TFoo;    begin r.F := -a.F; end;
operator not (a: TFoo) r: TFoo;    begin r.F := not a.F; end;
operator and (a, b: TFoo) r: Boolean; begin r := (a.F and b.F) <> 0; end;
operator or  (a, b: TFoo) r: Boolean; begin r := (a.F or b.F) <> 0; end;

var a, b, c: TFoo;
begin
  a.F := 1; b.F := 2;
  c := -a;      WriteLn('neg stmt ', c.F);   { -1 }
  WriteLn('neg fld ', (-a).F);               { -1 }
  c := not a;   WriteLn('not stmt ', c.F);   { -2 }
  WriteLn('not fld ', (not a).F);            { -2 }
  WriteLn('and ', a and b);                  { FALSE — see (2) }
  WriteLn('or ', a or b);                    { TRUE }
end.
