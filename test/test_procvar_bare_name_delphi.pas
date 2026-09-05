{ THE CONTROL FOR THE DELTA. {$mode delphi} relaxes a bare routine name bound to
  a procedural target to take its ADDRESS -- defs.inc calls that the dialect's
  one behavioural delta -- and the refusal added for the default mode must not
  erase it.

  This row matters because the tempting reading of the SIGSEGV is "bind the
  address everywhere, like Delphi", which would also fix the crash, accept
  strictly more programs (and CLAUDE.md is explicit that accepting what FPC
  rejects is not a defect), and quietly delete the one thing {$mode delphi}
  means. That is a dialect decision and not a bug fix, so it was NOT taken; this
  file is what makes the difference observable rather than assumed.

  fpc 3.2.2 -Mdelphi prints 7 for exactly the program the default mode refuses.
  bug-p-a-bare-function-name-assigned-to-a-procedural-variable-segfaults-outside-delphi-mode }
program test_procvar_bare_name_delphi;
{$MODE DELPHI}
type TF = function: Integer;
function G: Integer; begin G := 7; end;
var f: TF;
begin
  f := G;
  WriteLn(f());
end.
