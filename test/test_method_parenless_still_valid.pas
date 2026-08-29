{ The constructs a parenless-method-call ARITY CHECK must not break.

  `s.IPick;` on a method that requires arguments is now rejected
  (test_method_missing_args_report_fail). Every shape below is ALSO a method
  mentioned without parentheses, and every one of them is legitimate — which is
  why the check is narrow rather than "no parens means error":

    - a method POINTER takes the method's address, and is not a call at all.
      This is the construct with the real regression risk: it is the basis of
      bug-p-a-class-method-cast-to-a-method-pointer-inline-segfaults, and a
      check that fired here would break it while fixing the other case.
    - a PARAMETERLESS method has nothing missing.
    - an ALL-DEFAULTED method supplies the rest itself
      (bug-p-a-parenless-call-to-an-all-defaulted-virtual-method-segfaults),
      on the instance, virtual and class-method paths alike.

  Both directions are pinned deliberately: the rejection test alone would pass
  just as well if the check were far too strict.
  bug-p-a-method-call-with-missing-arguments-is-accepted-and-reads-garbage }
program test_method_parenless_still_valid;
{$MODE DELPHI}{$H+}
type
  TIntFn = function(A: LongInt): LongInt of object;
  TProcN = procedure(A: LongInt) of object;

  TSvc = class
    function Pick(A: LongInt): LongInt;
    procedure Act(A: LongInt);
    function NoArgs: LongInt;
    procedure Defaulted(A: LongInt = 3); virtual;
    function DefFn(A: LongInt = 5): LongInt;
    class procedure ClsDef(A: LongInt = 7);
  end;

function TSvc.Pick(A: LongInt): LongInt; begin Result := A * 3; end;
procedure TSvc.Act(A: LongInt); begin WriteLn('act ', A); end;
function TSvc.NoArgs: LongInt; begin Result := 7; end;
procedure TSvc.Defaulted(A: LongInt); begin WriteLn('def ', A); end;
function TSvc.DefFn(A: LongInt): LongInt; begin Result := A * 100; end;
class procedure TSvc.ClsDef(A: LongInt); begin WriteLn('cls ', A); end;

var
  s: TSvc;
  f: TIntFn;
  p: TProcN;
  n: LongInt;
begin
  s := TSvc.Create;

  f := s.Pick;            { method pointer -- an ADDRESS, not a call }
  p := s.Act;
  WriteLn(f(5));
  p(9);

  n := s.NoArgs;          { parameterless -- nothing is missing }
  WriteLn(n);

  s.Defaulted;            { all-defaulted, parenless, virtual }
  WriteLn(s.DefFn);       { all-defaulted, parenless, in an expression }
  TSvc.ClsDef;            { all-defaulted, parenless, class method }

  WriteLn(s.Pick(4));     { the ordinary correct-arity call }
end.
