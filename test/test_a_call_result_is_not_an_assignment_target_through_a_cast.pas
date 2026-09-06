{ A CALL RESULT IS NOT AN ASSIGNMENT TARGET — INCLUDING THROUGH A CAST.

  `o.GetV := 5` and `pc^.GetV := 5` have always said "cannot assign to the
  result of a function call". The cast spelling `PTC(raw)^.GetV := 5` answered
  `IR_UNSUPPORTED: frontend could not lower AST node (kind 8) — would
  miscompile` instead: an internal message for an ordinary user mistake, on the
  pinned compiler too.

  The single-exit guard tested the RETURNED node for being a call, which is what
  the plain-call and lvalue branches hand back with `:=` still pending. The
  cast-headed branches consume the `:=` themselves and hand back an AN_ASSIGN
  whose left side is the call, so they went straight past it. One construct,
  three spellings, one of them answering with a compiler-internal message.

  This asserts the MESSAGE and not the exit code: every one of these spellings
  fails either way, so a rc-only check cannot tell the real diagnostic from the
  internal one — which is the whole defect.

  refactor-p-one-lvalue-path-for-statements-and-expressions }
program test_a_call_result_is_not_an_assignment_target_through_a_cast;
type
  TC = class
    v: Integer;
    function GetV: Integer;
  end;
  PTC = ^TC;
var o: TC; pc: PTC; raw: Pointer;
function TC.GetV: Integer; begin Result := v; end;
begin
  o := TC.Create; pc := @o; raw := pc;
  PTC(raw)^.GetV := 5;
end.
