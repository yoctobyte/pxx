program test_a_method_pointer_can_be_taken_through_a_chain_of_selectors;
{ A METHOD REFERENCE COULD ONLY BE TAKEN THROUGH EXACTLY ONE DOT.
  `@Form.Button.Click` -- wire an event to a method of a NESTED object, which is
  what every form does -- did not compile:

    @o.Inner.Foo      -> wrong number of parameters in call to TInner.Foo
    @g.Mk.Foo         -> a statement cannot start with '.'
    @TG.Create.Foo    -> @TG.Create: unknown method

  ONE CAUSE, THREE MESSAGES. The `@` arms are written for depth 1; the selector
  walker takes every `.` it can reach, so the final one became a CALL, and the
  text depends only on where the truncated parse happened to stop. The third is
  the class-TYPE arm, which reads one dot and asks FindUMeth -- and a
  CONSTRUCTOR is not in that table.

  ROW 1 IS THE CONTROL THAT ALWAYS WORKED (depth 1) and it is here so a
  regression in the arms this change did NOT touch is visible in the same file.

  ROW 5 IS THE VMT ROW AND IT IS THE ONE THAT CAN FAIL QUIETLY. A method
  reference must capture the code address through the object's VMT, not the
  static address of the class the chain is TYPED as -- `Holder.Item` is declared
  TBase and holds a TDerived, so a reference that dropped the slot would call
  TBase.Speak and print `base`: a plausible answer, not a crash.
  bug-a-method-pointer-virtual-captures-static-address is the depth-1 version of
  exactly that, and this says the chained arm did not reintroduce it. `derived`
  is not any default here -- it is reachable only through the slot.

  There is deliberately NO `TBase(h.Item).Speak` row beside it. A cast then a
  CALL still dispatches virtually, so it prints `derived` under both compilers
  and under a broken one: an instrument that answers the same on every branch,
  which is the shape that reads as corroboration and is not.

  ROW 6 IS THE POSITIVE CONTROL FOR THE FALLBACK. When the name after the last
  dot is NOT a method the answer is an ADDRESS, not a method reference, and the
  walk has to be resumed rather than abandoned. Writing through that pointer and
  reading the field back is what says the address is the field's own.

  Oracle: fpc 3.2.2 prints all six rows exactly as below.
  bug-p-a-method-reference-can-only-be-taken-through-one-selector }
{$mode objfpc}{$H+}
type
  TBase = class
    N: Integer;
    function Speak: AnsiString; virtual;
  end;

  TDerived = class(TBase)
    function Speak: AnsiString; override;
  end;

  TLeaf = class
    X: Integer;
    function Add(const aX: Integer): Integer;
  end;

  TMid = class
    Leaf: TLeaf;
    function Self_: TMid;
  end;

  THolder = class
    Mid: TMid;
    Item: TBase;                 { STATICALLY TBase, dynamically TDerived }
  end;

  TIntFn   = function(const aX: Integer): Integer of object;
  TStrFn   = function: AnsiString of object;

function TBase.Speak: AnsiString;    begin Result := 'base'; end;
function TDerived.Speak: AnsiString; begin Result := 'derived'; end;
function TLeaf.Add(const aX: Integer): Integer; begin Result := aX + X; end;
function TMid.Self_: TMid; begin Result := Self; end;

var
  h: THolder;
  leaf: TLeaf;
  f: TIntFn;
  s: TStrFn;
  p: PInteger;
begin
  leaf := TLeaf.Create; leaf.X := 100;
  h := THolder.Create;
  h.Mid := TMid.Create; h.Mid.Leaf := leaf;
  h.Item := TDerived.Create; h.Item.N := 7;

  f := @leaf.Add;                { 1: depth 1 -- the control                  }
  WriteLn('depth1     = ', f(1));
  f := @h.Mid.Leaf.Add;          { 2: a THREE-deep field chain               }
  WriteLn('field3     = ', f(2));
  f := @h.Mid.Self_.Leaf.Add;    { 3: a CALL in the middle of the chain      }
  WriteLn('callchain  = ', f(3));
  f := @TLeaf.Create.Add;        { 4: class TYPE base, constructor in chain  }
  WriteLn('ctorchain  = ', f(4));

  s := @h.Item.Speak;            { 5: a chained VIRTUAL method               }
  WriteLn('virtual    = ', s());

  p := @h.Mid.Leaf.X;            { 6: NOT a method -- an ADDRESS             }
  p^ := 555;
  WriteLn('fieldaddr  = ', h.Mid.Leaf.X);
end.
