program test_delphi_mode_binds_a_bare_routine_name;
{ THE OTHER SIDE OF THE FLAG, and it must not move. {$mode delphi} binds a bare
  routine name to its ADDRESS -- defs.inc calls this "the one behavioural delta"
  of that mode -- so the two spellings the refusal beside this file rejects are
  CORRECT here and still compile.

  Fixing the default-mode crash by adopting Delphi's binding everywhere would
  also have removed it, and was rejected deliberately: that deletes the delta,
  which is a dialect decision and not something to arrive at while fixing a
  segfault.

  SCOPED TO WHAT DELPHI MODE ACTUALLY BINDS TODAY. A record-field or
  array-element target is NOT in here, because the Delphi arm is keyed on the
  destination SYMBOL and never fired for those -- they SIGSEGV'd on the pin and
  are refused now, which is louder but still not what fpc does. That gap is its
  own ticket rather than a row here, because a test asserting it would be
  asserting a shape nobody has fixed.
  bug-p-a-bare-function-name-assigned-to-a-procedural-variable-segfaults-outside-delphi-mode }
{$mode delphi}
type TF = function: Integer;

function G: Integer;
begin
  G := 7;
end;

procedure Use(h: TF);
begin
  WriteLn('B ', h());
end;

var f: TF;
begin
  f := G;   WriteLn('A ', f());
  Use(G);
  Use(@G);
end.
