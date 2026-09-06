{ A CLASS CONST IS A CONSTANT IN THE CLASS BODY, INCLUDING IN A FIELD'S ARRAY
  BOUND — and that last position was the one with no class context at all:

    TC = class
      const RingSize = 32;
      FRing: array[0..RingSize - 1] of TRec;   { error: not a constant }
    end;

  The const evaluator recovers a class const from two places, and between them
  is a gap: `ParsingClassConstCi` is live only while a `const` SECTION is being
  parsed, and `CurMethClass` only inside a METHOD BODY. A field declaration is
  neither, so the name fell through to `not a constant` — a diagnostic about the
  EXPRESSION for a defect in SCOPE, which points at the bound and not at the
  lookup. `ParsingClassBodyCi` already spans exactly the missing region.

  fcl-passrc's pparser.pp:286 is the live case:
  `FTokenRing: array[0..FTokenRingSize-1] of TTokenRec`, with
  `const FTokenRingSize = 32` twenty-eight lines above it.

  THE ROWS ARE THE THREE CONTEXTS AND EACH ASSERTS A LENGTH, not that it
  compiled. A bound that folded to the wrong number still compiles — an array of
  some other size, with every index in range — so `Length` is the only thing
  that separates "the const was read" from "something was read".

    bound     the field array bound: the position that had no context
    sibling   a class const defined from another (ParsingClassConstCi)
    method    a class const in a method body (CurMethClass)
    global    a UNIT const in the same bound position — the control that the
              new fallback did not capture names that were already resolving

  THE `global` ROW IS THE ONE THAT CAN BREAK. The fix adds a third fallback to
  a chain, and a fallback consulted too eagerly would shadow the ordinary
  lookup; this row is a plain global const in the same syntactic slot, and it
  must keep resolving to 4. }
{$mode objfpc}
program test_a_class_const_bounds_a_field_array;
const GlobalN = 4;
type
  TC = class
  private
    const RingSize = 3;
    const RingSizePlus = RingSize + 2;   { sibling: const-section context }
    var
      Ring:  array[0..RingSize - 1] of Integer;
      Wide:  array[0..RingSizePlus - 1] of Integer;
      G:     array[0..GlobalN - 1] of Integer;
  public
    procedure Fill;
    function InMethod: Integer;
  end;

procedure TC.Fill;
var i: Integer;
begin
  for i := 0 to RingSize - 1 do Ring[i] := i + 1;
  for i := 0 to RingSizePlus - 1 do Wide[i] := 100;
  for i := 0 to GlobalN - 1 do G[i] := 10;
end;

function TC.InMethod: Integer;
var i, s: Integer;
begin
  s := 0;
  for i := 0 to RingSize - 1 do s := s + Ring[i];   { method-body context }
  InMethod := s;
end;

var c: TC;
begin
  c := TC.Create;
  c.Fill;
  WriteLn('bound   = ', Length(c.Ring));
  WriteLn('sibling = ', Length(c.Wide));
  WriteLn('method  = ', c.InMethod);
  WriteLn('global  = ', Length(c.G), ' ', c.G[3]);
end.
