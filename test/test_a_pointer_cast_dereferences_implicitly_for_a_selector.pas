program test_a_pointer_cast_dereferences_implicitly_for_a_selector;
{ A `.` ON A VALUE THAT IS STILL A POINTER MEANS ONE MORE DEREFERENCE, and the
  SHARED selector walker could not make one.

  ParseLValueAST has had the implicit-deref arm for as long as `p.a` has worked.
  ParseClassRecordSelectors -- the walker the three postfix cast loops delegate
  to -- never did, and its builder makes AN_FIELD and nothing else. So the field
  offset was applied to the POINTER VALUE: `PRec(x).b` answered 0 and
  `PPRec(pp)^.b` answered 0 beside a low half-address for `.a`, where fpc 3.2.2
  answers 22 and 11. Silent, no diagnostic, and one spelling of two -- the
  explicit `PRec(x)^.b` and `PPRec(pp)^^.b` were right throughout, which is what
  says this is the walk and not the alias table.

  TWO TICKETS, ONE ARM, and the depth is what makes them look like two: they are
  the depth-1 and depth-2 faces of the same absent step. The depth-2 face
  survives only through a CAST, because the variable spelling `pp^.f` goes
  through ParseLValueAST's own copy and was repaired there separately.

  .expected is fpc 3.2.2's own output, byte for byte.
  bug-p-a-cast-to-a-pointer-to-pointer-drops-the-implicit-second-deref
  bug-p-an-implicit-deref-over-a-typed-pointer-cast-is-dropped }
{$mode delphi}
type
  TRec = record
    a, b: Integer;
    function Sum: Integer;
  end;
  PRec   = ^TRec;
  PPRec  = ^PRec;
  PPPRec = ^PPRec;

function TRec.Sum: Integer;
begin
  Result := a + b;
end;

var
  r: TRec;
  p: PRec;
  pp: PPRec;
  ppp: PPPRec;
  x: Pointer;
begin
  r.a := 11; r.b := 22;
  p := @r; pp := @p; ppp := @pp; x := @r;
  { A/B: the depth-1 cast with NO caret -- a field and a METHOD. The method row
    matters on its own: the walker reaches its method arm only after the
    receiver has become a record, so a fix that repaired fields alone would
    leave `PRec(x).Sum` calling with a pointer as Self. }
  WriteLn('A ', PRec(x).a, ' ', PRec(x).b);
  WriteLn('B ', PRec(x).Sum);
  { C: the depth-2 cast with ONE caret -- one explicit dereference, one implicit. }
  WriteLn('C ', PPRec(pp)^.a, ' ', PPRec(pp)^.Sum);
  { D: STORE through the same shape. A cast-headed assignment target now reaches
    the expression parser, so the read and the write take one route; this row is
    the guard for that route staying whole. }
  PRec(x).b := 99;
  PPRec(pp)^.a := 77;
  WriteLn('D ', r.a, ' ', r.b);
  r.a := 11; r.b := 22;
  { E..H: CONTROLS, all green before the fix. Every one of them is the SAME
    access spelled with the dereference written out, or off a plain variable --
    so if the new arm ever fires where a dereference already happened, these are
    what catch the double. }
  WriteLn('E ', PRec(x)^.a, ' ', PRec(x)^.b);
  WriteLn('F ', PPRec(pp)^^.a, ' ', PPPRec(ppp)^^^.b);
  WriteLn('G ', p.Sum, ' ', p^.Sum, ' ', p.a, ' ', p^.b);
  WriteLn('H ', pp^.a, ' ', pp^^.b);
end.
