program test_overload_pchar_and_pwidechar_are_two_overloads;
{ PChar and PWideChar are both tyPointer, so before 2026-09-05 they were ONE
  overload signature: the second declaration was reported as a "duplicate
  definition", its body was written into the first one's row, and BOTH calls ran
  whichever was declared LAST. A silent wrong dispatch with a warning that names
  the wrong defect.

  Two mechanisms had to be right for this, and each is asserted below:

    1. the `pwidechar` arm of the builtin type-name chain set only the immediate
       pointee and dropped LastTypePointerDepth / LastTypePointerBaseTk, which
       three sibling arms (pchar, ppchar, the builtin P-names) do set. Depth 0
       reads as "not a typed pointer", and the pointee then reads as tyUnknown --
       which is ALSO the untyped-`Pointer` sentinel, so the two spellings were
       indistinguishable rather than merely unrecorded.

    2. FindProcOverloadRec and MatchParamExact compare a typed pointer's
       POINTEE, and only when both sides positively name one, so an untyped
       `Pointer` formal keeps accepting everything it accepted before.

  NO {$define PXX_WIDE_PAYLOAD} HERE, deliberately: this half is live in a
  default build, unlike its managed-string twin (see
  test_overload_widestring_and_ansistring_are_two_overloads, where WideString is
  an ALIAS of AnsiString until that define breaks it).

  DECLARATION ORDER IS THE ASSERTION. With the fix absent, a same-order pair
  answers 5/5 and a reversed pair answers 4/4 -- so a test that declared only
  one order would have half of its rows pass by luck. Both orders are here, and
  the untyped-Pointer row is the control that this narrowed nothing it should
  not have.

  Fails on pin v403 (214500da2): prints `pc 5` for the first pair. }

function f(p: pchar): Integer; overload; begin f := 4; end;
function f(p: pwidechar): Integer; overload; begin f := 5; end;

function g(p: pwidechar): Integer; overload; begin g := 5; end;
function g(p: pchar): Integer; overload; begin g := 4; end;

function h(p: Pointer): Integer; overload; begin h := 9; end;

var pc: pchar; pw: pwidechar; pv: Pointer;
begin
  pc := nil; pw := nil; pv := nil;
  WriteLn('pc ', f(pc));
  WriteLn('pw ', f(pw));
  WriteLn('rc ', g(pc));
  WriteLn('rw ', g(pw));
  WriteLn('untyped ', h(pv));
  { an untyped Pointer ARGUMENT still reaches a PChar formal: the narrowing
    needs BOTH sides to name a pointee, and this one names none }
  WriteLn('any ', f(pv));
end.
