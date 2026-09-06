program test_a_procedural_type_without_a_default_still_refuses_a_short_call_fail;
{ MUST NOT COMPILE — the control for
  test_a_procedural_types_parameter_carries_its_default_through_every_indirect_call_shape.

  Teaching BuildIndirectCallAST and the statement path's parenless arm to FILL a
  procedural type's declared defaults meant relaxing an arity check that used to
  be an equality. If the relaxation is unconditional rather than gated on
  ProcParamHasDefault, every row of the sibling fixture still passes -- the
  defaults would be filled from a zeroed column and an Integer default of 5
  happens to be the only thing those rows check. THIS file is what fails then:
  `NoDef` declares a parameter with no default at all, and a short call must
  still be refused.

  The parenless spelling is the sharper of the two, because that arm's guard was
  `ParamCount = 0` and is now `ParamCount = 0 or ParamsDefaultedFrom(sig, 0)`.
  Get that wrong and `c;` on a one-parameter proc type compiles and calls with
  an unsupplied argument -- which is the shape that segfaulted at four interface
  arms, not a diagnostic.

  bug-p-a-procedural-types-parameter-cannot-carry-a-default-value }
{$mode objfpc}{$H+}
type TNoDef = procedure(n: Integer);
procedure P(n: Integer); begin WriteLn(n); end;
var c: TNoDef;
begin
  c := @P;
  c;
end.
