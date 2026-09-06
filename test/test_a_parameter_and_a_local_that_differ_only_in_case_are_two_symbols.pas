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

{ THE ASSERTION INVERTED WHEN THE DIAGNOSTIC LANDED, 2026-09-06, exactly as this
  file's earlier header said it must. It used to RUN and print CASEDUP FIXTURE
  OK, asserting only that the census channel saw the pair; it is now a program
  that MUST NOT COMPILE, and the Makefile asserts the diagnostic text of both
  message arms.

  Row 1 is the strutils.pas shape reduced: a parameter and a local differing
  only in case. Each reference uses ONE spelling only, so the routine's result
  is the same under either reading and this file was never an accidental
  assertion that the two-symbol reading is right.

  Row 2 is the arm that needs the LANGUAGE named rather than the author: a local
  `result` collides with the implicit function result, which is a name nobody
  wrote, so a message pointing only at the declaration points at nothing. It is
  the shape the one real site in this tree had -- lib/rtl/bignum.pas:495, since
  renamed to `acc` -- and without it that arm has no positive control at all.

  The shapes that must KEEP compiling are asserted elsewhere and are deliberately
  not in this file, because a program that must be rejected cannot share one with
  a program that must run: test_case_sensitive.pas ({$CASESENSITIVE ON}, where
  the two names are genuinely two identifiers), any of the test_c_gtk* fixtures
  (340 GDK keysym pairs arriving through a C header import, same reason), and
  test_exception_handler_binder_is_scoped_to_its_handler.pas (`on E: Exception`
  beside an outer `var e`, which fpc accepts with no warning -- a handler is a
  scope, and eight sites in this corpus were misreported as same-scope until
  that was recorded). }
function WordCountish(const N: Integer): Integer;
var
  i, n: Integer;
begin
  n := 0;
  for i := 1 to 3 do n := n + i;
  WordCountish := n;
end;

function Doubled(a: Integer): Integer;
var
  result: Integer;
begin
  result := a * 2;
  Doubled := result;
end;

begin
  fails := 0;
  Check('unreachable: this program must never be built', WordCountish(9), 6);
  Check('unreachable', Doubled(2), 4);
  WriteLn('fails=', fails);
end.
