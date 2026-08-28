{ A METHOD mentioned without its arguments is a compile error, exactly as a FREE
  routine in the same position always was.

  Before this check the four calls below compiled clean and the callee read
  whatever the argument register happened to hold -- a garbage value, no crash,
  no diagnostic. FPC rejects all four. The surplus direction (`c.M(1, 2)`) was
  already checked and is pinned in
  test_bad_arity_and_noncallable_all_report_fail; this file pins the DEFICIT
  direction, which was the hole: too few arguments INSIDE parens was caught by
  Expect(tkComma), so the only unchecked shape was no parentheses at all.

  All four arms are here on purpose -- instance function, instance procedure,
  virtual and class-method -- because AN_CALL, AN_VIRTUAL_CALL and
  AN_CLASS_VIRTUAL_CALL are three separate lowering paths, and an early version
  of the probe that found this bug measured only the first of them and reported
  a clean zero.

  The must-NOT-break direction is pinned separately in
  test_method_parenless_still_valid -- method pointers, parameterless methods
  and all-defaulted methods are all parenless mentions that stay legal.
  bug-p-a-method-call-with-missing-arguments-is-accepted-and-reads-garbage }
program test_method_missing_args_report_fail;
{$MODE DELPHI}{$H+}
type
  TSvc = class
    function IPick(A: LongInt): LongInt;
    procedure IDo(A: LongInt);
    procedure VDo(A: LongInt); virtual;
    class procedure CDo(A: LongInt);
  end;

function TSvc.IPick(A: LongInt): LongInt; begin Result := A * 3; end;
procedure TSvc.IDo(A: LongInt); begin WriteLn('do ', A); end;
procedure TSvc.VDo(A: LongInt); begin WriteLn('vdo ', A); end;
class procedure TSvc.CDo(A: LongInt); begin WriteLn('cdo ', A); end;

var
  s: TSvc;
  n: LongInt;
begin
  s := TSvc.Create;
  n := s.IPick;
  s.IDo;
  s.VDo;
  TSvc.CDo;
  WriteLn(n);
end.
