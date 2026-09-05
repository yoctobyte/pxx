program test_operator_delphi_names_and_unary;
{$mode delphi}
{ Track P — the Delphi `class operator` NAME spellings, the unary operators, and
  the one shape that made a wrong VALUE rather than a diagnostic.

  Three separate claims, in one file because they share a record:

  1. THE NAMES. `Add`/`Subtract`/`Multiply`/`Modulus`/`LogicalAnd`/`BitwiseAnd`/
     `LogicalNot`/`Negative`/`Positive`/`In` ... declare the same operators the
     symbols do; only the lexeme differs, exactly as `Implicit` and `:=` already
     did. A partial table is the arm that stays broken, so the whole table is
     asserted here rather than the rows one corpus row happened to need.

  2. THE UNARY OPERATORS IN AN ADDRESS POSITION. `b := -a` and `(-a).F` are the
     same expression in two positions, and they used to differ: the overload was
     TAGGED onto AN_NEG/AN_NOT for ir.inc to re-resolve, and an AN_NEG is not one
     of the kinds IRLowerAddress can take an address of, so the field selection
     died with `IR_UNSUPPORTED ... (kind 6)`. The parser builds a CALL now.
     Both spellings of each are asserted, which is the point.

  3. `LogicalAnd` RETURNING Boolean. The parser tags the AN_BINOP with the
     overload's result type, so a pair of RECORD operands reached ir.inc's
     short-circuit and/or arm wearing tyBoolean and was evaluated as two flags --
     each record lowering to its own address, never nil. `a and b` answered TRUE
     without calling the operator. THE EXPECTED VALUE HERE IS FALSE, and False is
     the answer only a real call can produce: 1 and 2 is 0. A row expecting True
     could not have failed. }

type
  TFoo = record
    F: Integer;
    class operator Add(a, b: TFoo): Integer;
    class operator Subtract(a, b: TFoo): Integer;
    class operator Multiply(a, b: TFoo): Integer;
    class operator IntDivide(a, b: TFoo): Integer;
    class operator Modulus(a, b: TFoo): Integer;
    class operator LeftShift(a, b: TFoo): Integer;
    class operator RightShift(a, b: TFoo): Integer;
    class operator Equal(a, b: TFoo): Boolean;
    class operator NotEqual(a, b: TFoo): Boolean;
    class operator GreaterThan(a, b: TFoo): Boolean;
    class operator LessThan(a, b: TFoo): Boolean;
    class operator LogicalAnd(a, b: TFoo): Boolean;
    class operator LogicalOr(a, b: TFoo): Boolean;
    class operator In(a, b: TFoo): Boolean;
    class operator LogicalNot(a: TFoo): TFoo;
    class operator Negative(a: TFoo): TFoo;
    class operator Positive(a: TFoo): TFoo;
  end;

class operator TFoo.Add(a, b: TFoo): Integer;        begin Result := a.F + b.F; end;
class operator TFoo.Subtract(a, b: TFoo): Integer;   begin Result := a.F - b.F; end;
class operator TFoo.Multiply(a, b: TFoo): Integer;   begin Result := a.F * b.F; end;
class operator TFoo.IntDivide(a, b: TFoo): Integer;  begin Result := a.F div b.F; end;
class operator TFoo.Modulus(a, b: TFoo): Integer;    begin Result := a.F mod b.F; end;
class operator TFoo.LeftShift(a, b: TFoo): Integer;  begin Result := a.F shl b.F; end;
class operator TFoo.RightShift(a, b: TFoo): Integer; begin Result := a.F shr b.F; end;
class operator TFoo.Equal(a, b: TFoo): Boolean;      begin Result := a.F = b.F; end;
class operator TFoo.NotEqual(a, b: TFoo): Boolean;   begin Result := a.F <> b.F; end;
class operator TFoo.GreaterThan(a, b: TFoo): Boolean;begin Result := a.F > b.F; end;
class operator TFoo.LessThan(a, b: TFoo): Boolean;   begin Result := a.F < b.F; end;
class operator TFoo.LogicalAnd(a, b: TFoo): Boolean; begin Result := (a.F and b.F) <> 0; end;
class operator TFoo.LogicalOr(a, b: TFoo): Boolean;  begin Result := (a.F or b.F) <> 0; end;
class operator TFoo.In(a, b: TFoo): Boolean;         begin Result := a.F < b.F; end;
class operator TFoo.LogicalNot(a: TFoo): TFoo;       begin Result.F := not a.F; end;
class operator TFoo.Negative(a: TFoo): TFoo;         begin Result.F := -a.F; end;
{ NOT identity: a `Positive` body that returned its argument unchanged would
  pass whether or not the operator was ever called. }
class operator TFoo.Positive(a: TFoo): TFoo;         begin Result.F := a.F + 1; end;

var a, b, r: TFoo;
begin
  a.F := 1; b.F := 2;
  WriteLn('add ', a + b);          { 3 }
  WriteLn('sub ', a - b);          { -1 }
  WriteLn('mul ', a * b);          { 2 }
  WriteLn('idiv ', b div a);       { 2 }
  WriteLn('mod ', a mod b);        { 1 }
  WriteLn('shl ', a shl b);        { 4 }
  WriteLn('shr ', b shr a);        { 1 }
  WriteLn('eq ', a = b);           { FALSE }
  WriteLn('ne ', a <> b);          { TRUE }
  WriteLn('gt ', a > b);           { FALSE }
  WriteLn('lt ', a < b);           { TRUE }
  WriteLn('and ', a and b);        { FALSE -- 1 and 2 is 0; see (3) above }
  WriteLn('or ', a or b);          { TRUE }
  WriteLn('in ', a in b);          { TRUE }

  { the unary three, each in BOTH positions }
  r := not a;  WriteLn('not stmt ', r.F);     { -2 }
  WriteLn('not fld ', (not a).F);             { -2 }
  r := -b;     WriteLn('neg stmt ', r.F);     { -2 }
  WriteLn('neg fld ', (-b).F);                { -2 }
  r := +a;     WriteLn('pos stmt ', r.F);     { 2 }
  WriteLn('pos fld ', (+a).F);                { 2 }

  { a built-in operand is untouched by any of it }
  WriteLn('int ', +7, ' ', -7, ' ', not 7);   { 7 -7 -8 }
end.
