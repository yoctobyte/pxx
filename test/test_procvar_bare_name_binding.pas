{ The POSITIVE half of the bare-function-name-to-a-procedural-slot rule.

  Outside {$mode delphi} a bare routine name bound to a procedural target is
  read as a CALL -- which is also FPC's reading; its diagnostic says
  got "LongInt" -- so the result lands in a slot that is later called as a code
  address. pxx compiled that clean and SIGSEGV'd, on FOUR paths: a variable, a
  record field, an array element and an argument. The first three funnel through
  the single AN_ASSIGN check; the fourth is TypesCompatible and needed its own
  rule.

  THE REFUSALS ARE ASSERTED SEPARATELY, one fixture per path
  (procvar_bare_name_{var,field,elem,arg}.pas), and each asserts the SPECIFIC
  diagnostic rather than a non-zero exit -- a refusal test that only checks
  "the compiler failed" passes when the fixture has a typo in it. They are
  separate files because the argument arm is diagnosed at PARSE time and aborts
  the compile before the assignment arms are ever lowered, so one file cannot
  show all four.

  THIS file is the other half and the one that would catch an over-broad fix.
  Every legal way to fill a procedural slot has to keep working, and the rule
  landed is deliberately asymmetric -- only the pointer SINK is refused -- so
  the pointer-to-integer direction is asserted here too and must NOT be refused.

  {$mode delphi} is asserted UNCHANGED, in its own file
  (test_procvar_bare_name_delphi.pas) because a program has one mode: it relaxes
  the bare name to take its address, defs.inc calls that the dialect's one
  behavioural delta, and a fix that quietly erased the delta -- by binding the
  address everywhere, which also fixes the crash -- would pass every row in
  THIS file.

  Verified against fpc 3.2.2 (-Mobjfpc for the default rows, -Mdelphi for the
  last one), which prints this file's .expected.
  bug-p-a-bare-function-name-assigned-to-a-procedural-variable-segfaults-outside-delphi-mode }
program test_procvar_bare_name_binding;
type
  TF = function: Integer;
  TR = record f: TF; end;
function G: Integer; begin G := 7; end;
function H: Integer; begin H := 9; end;
procedure TakesIt(p: TF); begin WriteLn('arg    ', p()); end;
var
  f, g2: TF;
  r: TR;
  a: array[0..1] of TF;
  p: Pointer;
  i: PtrInt;
begin
  f := @G;            WriteLn('var    ', f());
  f := nil;           if f = nil then WriteLn('nil    ok');
  f := @G; g2 := f;   WriteLn('copy   ', g2());
  r.f := @H;          WriteLn('field  ', r.f());
  a[0] := @G;
  a[1] := @H;         WriteLn('elem   ', a[0](), ' ', a[1]());
  TakesIt(@G);
  p := @G;            if p <> nil then WriteLn('ptr    ok');
  p := nil;           if p = nil then WriteLn('ptrnil ok');
  { the ASYMMETRY: a pointer READ into an integer is left alone on purpose --
    it is how NativeInt round-trips are spelled and it is not the direction
    that turns a value into an instruction pointer. This row must COMPILE. }
  p := @G; i := PtrInt(p);
  if i <> 0 then WriteLn('round  ok');
end.
