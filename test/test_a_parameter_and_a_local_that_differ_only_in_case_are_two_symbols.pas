program test_a_parameter_and_a_local_that_differ_only_in_case_are_two_symbols;
{ bug-p-a-parameter-and-a-local-that-differ-only-in-case-are-two-symbols

  THIS FILE ASSERTS NOTHING ABOUT WHAT THE PROGRAM SHOULD MEAN. Pascal is
  case-insensitive, so `const N` and `var n` in one routine are ONE identifier
  declared twice and fpc 3.2.2 refuses the file outright with a duplicate
  identifier. pxx registers two symbols and keeps them apart, which is the
  defect the ticket is about -- three routines in lib/rtl/strutils.pas were
  written this way and read the two as different variables until a name
  resolution fix collapsed them.

  It exists to give PXXDBG=a.casedup a POSITIVE CONTROL DRAWN FROM THE
  POPULATION THE TICKET IS ABOUT. The census that decides whether the
  declaration-site check should be an error or a warning has to be run before
  the check is written, and a census instrument with no case it must report is
  not an instrument. Every other case-only pair reachable today is a local
  shadowing an OUTER name, which is ordinary correct shadowing and is the
  samescope=0 arm -- a control from the wrong population.

  So the Makefile row asserts the CHANNEL, not the values below, and the
  program's own output is deliberately independent of which symbol each
  reference binds.

  WHEN THE DIAGNOSTIC LANDS this file must be REFUSED, and the assertion on it
  inverts from "compiles, and a.casedup reports samescope=1" to "does not
  compile, and says why on the declaration line". Do not read a green here as
  the behaviour being endorsed. }

var
  fails: Integer;

procedure Check(const what: AnsiString; g, w: Integer);
begin
  if g <> w then
  begin
    WriteLn('FAIL ', what, ': got ', g, ' want ', w);
    fails := fails + 1;
  end;
end;

{ The strutils.pas shape, reduced: a parameter and a local differing only in
  case. Each reference below uses ONE spelling only, so the routine's result is
  the same under either reading and this file cannot be turned into an accidental
  assertion that the two-symbol reading is right. }
function WordCountish(const N: Integer): Integer;
var
  i, n: Integer;
begin
  n := 0;
  for i := 1 to 3 do n := n + i;
  WordCountish := n;
end;

begin
  fails := 0;
  Check('the routine still computes 1+2+3', WordCountish(9), 6);
  WriteLn('fails=', fails);
  if fails = 0 then WriteLn('CASEDUP FIXTURE OK');
end.
