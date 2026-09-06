{ `Fld := nil` ON A DYNAMIC-ARRAY FIELD — two defects stacked, and the first was
  hiding the second.

  1. AssignSideKind typed the field as its ELEMENT (an array's TypeKind IS the
     element's), so for `array of <record>` the assignment check read the
     destination as a record and refused

       error: incompatible types: cannot assign Pointer to record

     Legal Pascal, refused — and that function's own header calls the false
     reject the worse direction. The AN_IDENT arm has bailed on `Syms[si].IsArray`
     from the start; the field/element/deref arm never got the equivalent.

  2. With the refusal gone the program SEGFAULTED, because ASTNodeIsWholeArray
     answered only for the AN_IDENT spelling. A dyn-array FIELD is a whole array
     and it said no, so `Fld := nil` took ir.inc's "record-shaped destination
     := nil" arm and zeroed RecSize(ELEMENT) bytes — four — over the eight-byte
     array HANDLE. The next `Length(Fld)` read a truncated pointer.

  ACCIDENTAL COVER: the type error was a refusal, so nothing ever reached the
  bad lowering. Fixing the false reject is what exposed the miscompile, which is
  why both go in together and why neither is provable alone.

  THE ROWS ARE THE SPELLINGS, and the ones that already worked are here on
  purpose. `IA` (integer element) always compiled — its element kind is scalar,
  so neither defect fired — and a file containing only the record row cannot
  tell "arrays now work" from "records now work". `c.RA` from outside a method
  is the same lvalue reached without implicit Self.

  THE METHOD-POINTER ROW IS THE ONE THAT MUST NOT MOVE. `OnHit := nil` is a
  record-shaped field assigned nil and it MUST keep taking the zero-fill arm —
  that is how an event handler is detached
  (bug-a-assigning-nil-to-a-method-pointer-segfaults). Widening the whole-array
  predicate is exactly the change that could steal it, so it is asserted here
  rather than in the ticket for it. }
{$mode objfpc}
program test_nil_assigned_to_a_dynamic_array_field;
type
  TR = record a: Integer; end;
  TNotify = procedure(x: Integer) of object;
  TC = class
    IA: array of Integer;      { scalar element: always worked }
    RA: array of TR;           { record element: both defects }
    OnHit: TNotify;            { record-SHAPED, and not an array }
    procedure WipeI;
    procedure WipeR;
    procedure Hit(x: Integer);
  end;

var hits: Integer;

procedure TC.WipeI; begin IA := nil; end;
procedure TC.WipeR; begin RA := nil; end;
procedure TC.Hit(x: Integer); begin hits := hits + x; end;

var c: TC;
begin
  hits := 0;
  c := TC.Create;
  SetLength(c.IA, 3); SetLength(c.RA, 3); c.RA[2].a := 5;

  WriteLn('int  before=', Length(c.IA));
  c.WipeI;
  WriteLn('int  after =', Length(c.IA));

  WriteLn('rec  before=', Length(c.RA), ' last=', c.RA[2].a);
  c.WipeR;
  WriteLn('rec  after =', Length(c.RA));

  { the same field, reached from outside the class }
  SetLength(c.RA, 2);
  WriteLn('out  before=', Length(c.RA));
  c.RA := nil;
  WriteLn('out  after =', Length(c.RA));

  { a record-SHAPED field assigned nil must still zero-fill and detach }
  c.OnHit := @c.Hit;
  c.OnHit(4);
  WriteLn('mp   assigned=', Assigned(c.OnHit), ' hits=', hits);
  c.OnHit := nil;
  WriteLn('mp   detached=', not Assigned(c.OnHit), ' hits=', hits);
end.
