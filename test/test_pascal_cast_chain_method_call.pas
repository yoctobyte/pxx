program test_pascal_cast_chain_method_call;
{ A METHOD at the end of a `PRec(q)^.field.Method(...)` chain.

  The cast-deref suffix loops in ParseFactorCore hand-roll their own selector
  walk, and that walk can only build an AN_FIELD. A method name therefore became
  a FIELD of the receiver, and since RecFieldType's miss returns the tyInteger
  default, the expression compiled, ran, and evaluated to the RECEIVER POINTER.
  Nothing crashed -- `v := PRec(q)^.o.F(2)` printed a heap address.

  That is the failure mode this repo's debugging playbook is written around: a
  plausible wrong value far from the cause. Every assertion below is an
  identity: the SAME call reached through a plain pointer variable and through
  the cast must agree, so a silent regression cannot pass by matching itself.

  Two receivers, because they lose the record id in different places:
    - an instance field (`o: TObj`)      -- RecFieldRecId answers the class
    - a metaclass field (`cr: TObjClass`) -- RecFieldRecId answers REC_NONE, the
      class lives in UFldPtrElemRec, which is what NodeMetaclassCi reads
  and both cast spellings: the record NAME (`TRec(p)^`) and a pointer-type
  ALIAS (`PRec(p)^`), which are two separate branches of the same loop.
  bug-pascal-record-cast-chain-drops-method-call }
type
  TObj = class
    n: Integer;
    function F(x: Integer): Integer;
    class function NewN(x: Integer): Integer;
    procedure M(x: Integer);
  end;
  TObjClass = class of TObj;
  TRec = record
    o: TObj;
    cr: TObjClass;
  end;
  PRec = ^TRec;

var
  total, okc, sideEffect: Integer;

function TObj.F(x: Integer): Integer;
begin
  Result := n + x;
end;

procedure TObj.M(x: Integer);
begin
  sideEffect := sideEffect + x;
end;

class function TObj.NewN(x: Integer): Integer;
begin
  Result := x * 10;
end;

procedure Check(const name: AnsiString; ok: Boolean);
begin
  total := total + 1;
  if ok then
  begin
    okc := okc + 1;
    writeln('ok ', name);
  end
  else
    writeln('FAIL ', name);
end;

var
  r: TRec;
  p: PRec;
  q: Pointer;
begin
  total := 0; okc := 0; sideEffect := 0;
  r.o := TObj.Create;
  r.o.n := 2;
  r.cr := TObj;
  p := @r;
  q := @r;

  { the reference value, through a pointer VARIABLE -- this path always worked }
  Check('baseline-var-ptr', p^.o.F(1) = 3);

  { ...and the same call through each cast spelling }
  Check('alias-cast-expr', PRec(q)^.o.F(1) = p^.o.F(1));
  Check('recname-cast-expr', TRec(q^).o.F(1) = p^.o.F(1));

  { a PROCEDURE through the cast, in statement position: the parser used to
    demand `:=` after the opening `(` of a cast-led statement }
  sideEffect := 0;
  PRec(q)^.o.M(5);
  Check('alias-cast-stmt', sideEffect = 5);

  { assignment THROUGH the cast still parses as an assignment, not a call }
  PRec(q)^.o.n := 7;
  Check('alias-cast-assign', p^.o.n = 7);
  r.o.n := 2;

  { a CLASS method through a `class of` field -- the shape rtl-generics needs
    for PPVmt(Self)^.__ClassRef.GetHashList(...) }
  Check('baseline-classref', p^.cr.NewN(3) = 30);
  Check('alias-cast-classref', PRec(q)^.cr.NewN(3) = p^.cr.NewN(3));
  Check('recname-cast-classref', TRec(q^).cr.NewN(3) = 30);

  { a class-reference OPERATION on that field, which takes the other arm }
  Check('classref-op-through-cast', PRec(q)^.cr.ClassName = p^.cr.ClassName);

  r.o.Free;
  writeln('total ok ', okc, ' / ', total);
end.
