{ `p.field` where p is a POINTER means `p^.field`, and until 2026-09-06 that
  rule had exactly one implementation — ParseLValueAST's, which only a pointer
  VARIABLE reaches. Every other opener of the same value walks its selectors
  through ParseClassRecordSelectors or one of the two hand-rolled cast loops,
  and none of those had the rule, so the field offset was applied to the
  POINTER VALUE and read back garbage with no diagnostic:

    p.a            pointer variable      11        (the one arm that had it)
    pp^.a          ...depth 2            11
    PRec(q).a      pointer-alias cast    4310632
    PRec(q).GetA   ...and a METHOD       4310632
    PPRec(qq)^.a   ...cast, depth 2      4310632
    GetPP^.a       call RESULT, depth 2  4310504  (STILL RED, filed)
    GetP.a         call result, depth 1  IR_UNSUPPORTED (kind 8)

  fpc 3.2.2 prints 11 for all seven; pin v404 fails five of them the same way
  and answers the sixth with an internal error for ordinary source. The
  EXPLICIT spellings — `PRec(q)^.a`, `pp^^.a`, `GetP^.a` — were correct through
  every opener throughout, which is the discriminator: the record identity
  resolves fine and only the address computation is short a level.

  AND THE MEMBER KIND IS A SECOND AXIS THE ROWS BELOW EXIST FOR. The rule's
  guard enumerated field and method and not PROPERTY, so `pp^.PA` printed the
  pointer value and `p.PA` was REFUSED — on the pinned compiler too, and on the
  ONE opener that had the rule. A guard built from a list of member kinds goes
  wrong by the kind nobody listed, so all three are asserted through all eight
  openers rather than one of each.

  The `varexpl` / `castexpl` rows are the negative control: the value there is
  already a record, so the rule must NOT fire and a second deref would read
  through the record's first field.
  Expected output is fpc 3.2.2 -Mdelphi -O1.
  bug-p-a-cast-to-a-pointer-to-pointer-drops-the-implicit-second-deref
  bug-p-an-implicit-deref-over-a-typed-pointer-cast-is-dropped }
program test_an_implicit_deref_through_every_opener;
{$mode delphi}
type
  TRec = record
    a, b: Integer;
    function GetA: Integer;
    property PA: Integer read GetA;
  end;
  PRec   = ^TRec;
  PPRec  = ^PRec;
  PPPRec = ^PPRec;
function TRec.GetA: Integer; begin Result := a; end;
var r: TRec; p: PRec; pp: PPRec; ppp: PPPRec; q, qq, qqq: Pointer;
function GetP: PRec; begin Result := p; end;
function GetPP: PPRec; begin Result := pp; end;
begin
  r.a := 11; r.b := 22;
  p := @r; pp := @p; ppp := @pp;
  q := @r; qq := @p; qqq := @pp;

  WriteLn('var1     ', p.a,             ' ', p.b,             ' ', p.GetA,             ' ', p.PA);
  WriteLn('var2     ', pp^.a,           ' ', pp^.b,           ' ', pp^.GetA,           ' ', pp^.PA);
  WriteLn('var3     ', ppp^^.a,         ' ', ppp^^.b,         ' ', ppp^^.GetA,         ' ', ppp^^.PA);
  WriteLn('cast1    ', PRec(q).a,       ' ', PRec(q).b,       ' ', PRec(q).GetA,       ' ', PRec(q).PA);
  WriteLn('cast2    ', PPRec(qq)^.a,    ' ', PPRec(qq)^.b,    ' ', PPRec(qq)^.GetA,    ' ', PPRec(qq)^.PA);
  WriteLn('cast3    ', PPPRec(qqq)^^.a, ' ', PPPRec(qqq)^^.b, ' ', PPPRec(qqq)^^.GetA, ' ', PPPRec(qqq)^^.PA);
  WriteLn('callres1 ', GetP.a,          ' ', GetP.b,          ' ', GetP.GetA,          ' ', GetP.PA);
  { `GetPP^.a` -- a call result at pointer depth 2, one caret written and one
    implicit -- is deliberately NOT a row here and is the one cell of the census
    still red: it prints 4306192 / 0 against fpc's 11 / 22. `GetPP^^.a` fully
    written out is correct, so the depth is recorded somewhere; where it is lost
    between there and this walk is NOT established. Filed rather than guessed:
    bug-p-a-call-result-at-pointer-depth-2-does-not-take-the-implicit-deref }

  { negative control: the value is already a RECORD, the rule must not fire }
  WriteLn('varexpl  ', p^.a,            ' ', p^.b,            ' ', p^.GetA,            ' ', p^.PA);
  WriteLn('castexpl ', PRec(q)^.a,      ' ', PRec(q)^.b,      ' ', PRec(q)^.GetA,      ' ', PRec(q)^.PA);

  WriteLn('IMPLICIT DEREF OK');
end.
