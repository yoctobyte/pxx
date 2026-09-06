program test_a_bare_routine_name_into_a_procedural_slot_is_refused;
{ NEGATIVE HALF. Outside {$mode delphi} a bare routine name is a CALL -- fpc's
  reading too, hence its `Incompatible types: got "LongInt"` -- so `f := G`
  stored the Integer RESULT into a function-pointer slot and `f()` jumped
  through 7. pxx compiled all four spellings and SIGSEGV'd on each (rc=139),
  identically on pin v404.

  FOUR SPELLINGS, TWO CHECKS, and that split is structural rather than a
  shortcut: three of them funnel through AN_ASSIGN and the fourth is an
  ARGUMENT, which passes through no node the other three do. The first attempt
  at this defect fixed the assignment and left the argument crashing.

  THE FIRST ATTEMPT (4760474da, reverted in 2d6bfadd6) typed the slot tyPointer
  and wrote a POINTER-GENERAL rule, which refused every legal Char-into-PChar
  binding with it -- thirteen rows red, and the self-host could not see the
  shape because compiler.pas never binds a Char to a PChar. So this check does
  not ask the kind at all: it asks SymProcSig / UFldProcSig / SymElemProcSig /
  ProcParamProcSig, the per-entity facts that record "this slot will be
  CALLED", which no TTypeKind can distinguish from "this pointer will be READ".

  All four errors are expected from ONE compile: the check recovers rather than
  halting, so a file reports every one it contains.
  bug-p-a-bare-function-name-assigned-to-a-procedural-variable-segfaults-outside-delphi-mode }
type
  TF = function: Integer;
  TRec = record f: TF; end;

function G: Integer;
begin
  G := 7;
end;

procedure Use(h: TF);
begin
  WriteLn(h());
end;

var
  f: TF;
  r: TRec;
  a: array[0..1] of TF;
begin
  f := G;        { 1: variable }
  r.f := G;      { 2: record field }
  a[0] := G;     { 3: array element }
  Use(G);        { 4: argument -- a different check, by construction }
end.
