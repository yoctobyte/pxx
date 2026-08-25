program test_virtual_class_method_called_as_a_statement;
{ `q.Emit(1);` where `q: TFactoryClass` — a VIRTUAL CLASS METHOD called through a
  metaclass receiver, in STATEMENT position.

  It worked as an EXPRESSION (`k := q.Val(3)`) and was refused as a statement
  with `Expected: :=`, which names the punctuation rather than the gap. The
  cause: "is this statement a call?" was written five times in the statement
  parser, and AN_CLASS_VIRTUAL_CALL appeared in none of the five copies. One
  predicate now (ASTNodeIsCall), so the sixth spelling is added once.

  Both halves are asserted on every receiver spelling that reaches the metaclass
  member parser — a `class of` VARIABLE, a metaclass-typed FIELD, and an ELEMENT
  of an array of them — because the drift this fixes is exactly the kind that
  leaves one spelling working and its neighbour broken. Virtual dispatch is
  asserted too (a descendant overrides), since a non-virtual class method takes a
  different path entirely.

  .expected IS fpc 3.2.2's own output on this source. }
{$mode delphi}
type
  TFactory = class
    class procedure Emit(n: LongInt); virtual;
    class function Val(n: LongInt): LongInt; virtual;
  end;
  TFactoryClass = class of TFactory;
  TDerived = class(TFactory)
    class procedure Emit(n: LongInt); override;
    class function Val(n: LongInt): LongInt; override;
  end;
  THolder = record
    Ref: TFactoryClass;
  end;

class procedure TFactory.Emit(n: LongInt); begin WriteLn('base emit ', n); end;
class function TFactory.Val(n: LongInt): LongInt; begin Result := n * 2; end;
class procedure TDerived.Emit(n: LongInt); begin WriteLn('derived emit ', n); end;
class function TDerived.Val(n: LongInt): LongInt; begin Result := n * 10; end;

var
  q: TFactoryClass;
  h: THolder;
  arr: array[0..1] of TFactoryClass;
  k: LongInt;
begin
  { a class-of VARIABLE }
  q := TFactory;
  k := q.Val(3);  WriteLn('var expr    : ', k);
  q.Emit(1);
  q := TDerived;
  k := q.Val(3);  WriteLn('var expr    : ', k);
  q.Emit(2);

  { a metaclass-typed FIELD }
  h.Ref := TDerived;
  k := h.Ref.Val(4); WriteLn('field expr  : ', k);
  h.Ref.Emit(3);

  { an ELEMENT of an array of them }
  arr[0] := TFactory; arr[1] := TDerived;
  k := arr[1].Val(5); WriteLn('elem expr   : ', k);
  arr[0].Emit(4);
  arr[1].Emit(5);

  { a function RESULT is the fifth spelling; the class NAME itself is the
    compile-time form and never went through this path }
  TFactory.Emit(6);
  TDerived.Emit(7);
end.
