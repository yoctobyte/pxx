{ The advanced-record ctor / `static` method call arm — the THIRD hand-rolled
  argument loop in the frontend, and the last one.

  It was `while CurTok.Kind <> tkRParen do ParseExpr` with a bare
  `Expect(tkRParen)` for a tail: no bracket door, no bare-method-name door, no
  arity pre-check, and no ExpectCallRParen. Measured 2026-09-09 before the fix:

      TR.One(1, 2, 3)   -> 3    the arguments shifted one slot
      TR.One()          -> 12   uninitialised memory, exit 0, no diagnostic

  fpc 3.2.2 refuses both. Every ACCEPTED row below is byte-identical to
  fpc -Mobjfpc.

  WHY THIS ARM NEEDED MORE THAN A CALL TO THE SHARED ROUTINE, and it is what
  the rows guard: a `static` method has NO Self, so `Params[0]` is a REAL
  parameter and there is no head AN_ARG to hang the chain off. Three shapes
  reach this arm and they disagree about both — no Self at all, a dummy Self
  slot for a static that still has one, and a lifted record temp for a
  constructor. `Opt()` and `Opt(9)` are the rows that catch a selfBase off by
  one: with the method-flavoured 1, a one-parameter static reads as requiring
  none, and `Opt()` would silently take the default instead of the argument
  slot it was given.

  AND THIS FILE CANNOT FAIL FOR THE DEFECT IT IS NAMED AFTER. Say it plainly
  rather than let a green here read as coverage: it is BYTE-IDENTICAL on the
  pinned pre-fix compiler, because the broken loop got the GOOD calls right —
  it appended whatever it parsed, and for a call whose arity already matched
  that is the same tree. Every row here is a must-not-break control, for
  selfBase above all. The rows that can only pass on a fixed compiler live in
  test_p_a_record_static_call_arity_fail.pas, which the pin compiles clean.

  bug-p-the-record-static-call-arm-is-a-third-hand-rolled-argument-loop }
{$mode objfpc}{$modeswitch advancedrecords}
program test_p_a_record_static_call_is_checked_like_every_other_call;
type
  TR = record
    x, y: Integer;
    class function One(a: Integer): Integer; static;
    class function Opt(a: Integer = 5): Integer; static;
    class function None: Integer; static;
    constructor Create(ax, ay: Integer);
    function Sum: Integer;
  end;

class function TR.One(a: Integer): Integer; begin One := a; end;
class function TR.Opt(a: Integer = 5): Integer; begin Opt := a; end;
class function TR.None: Integer; begin None := 42; end;
constructor TR.Create(ax, ay: Integer); begin x := ax; y := ay; end;
function TR.Sum: Integer; begin Sum := x + y; end;

var r: TR;
begin
  { a static with a required parameter — the shape that returned the LAST
    argument when the loop was unbounded }
  WriteLn('one-1     ', TR.One(7));

  { a static whose only parameter is defaulted, in all three spellings }
  WriteLn('opt-()    ', TR.Opt());
  WriteLn('opt-bare  ', TR.Opt);
  WriteLn('opt-1     ', TR.Opt(9));

  { a static with no parameters at all, with and without parens }
  WriteLn('none      ', TR.None);
  WriteLn('none-()   ', TR.None());

  { the constructor, whose Self is a lifted record temp rather than absent }
  r := TR.Create(3, 4);
  WriteLn('ctor      ', r.Sum);

  { ...and chained off the ctor result, which is the arm's other shape }
  WriteLn('chain     ', TR.Create(7, 8).Sum);
end.
