{ A `property` declared in a TYPE HELPER is dispatched, not only its methods.

  bug-p-a-type-helper-cannot-declare-a-property. `s.Len` used to be refused with
  "a string has no members here" while `s.GetLen` -- the identical accessor, same
  helper, same receiver -- worked, because the helper guard in pasparser_lval.inc
  asked FindUMeth and never FindUProp. The property arm of the selector machinery
  was never missing; it was merely never reached.

  This matters beyond one member: FPC declares TStringHelper.Length as a property
  over a private GetLength, so the most-used member of Delphi's string surface was
  the one that did not work while every sibling did.

  THE RECORD ROW IS THE CONTROL AND MUST STAY. Properties on a plain record always
  worked, so the defect was the intersection of two working features, and this file
  keeps both arms in view -- that is what stops the fix being rewritten as a special
  case for helpers. Same reason as normalise-dont-special-case.md: when a construct
  is reachable by two shapes, test both or the second one rots. }
program test_type_helper_property;
type
  { the arm that always worked }
  TRec = record
    F: Integer;
    function GetD: Integer;
    property D: Integer read GetD;
  end;

  { the arm that did not }
  TIntHelper = type helper for Integer
    function GetTwice: Integer;
    property Twice: Integer read GetTwice;
  end;

function TRec.GetD: Integer; begin GetD := F * 2; end;
function TIntHelper.GetTwice: Integer; begin GetTwice := Self * 2; end;

var
  r: TRec;
  i: Integer;
begin
  r.F := 21;
  writeln('record-property=', r.D);
  i := 21;
  writeln('helper-property=', i.Twice);
  writeln('helper-method=', i.GetTwice);
end.
