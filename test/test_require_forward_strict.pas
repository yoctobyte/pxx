program test_require_forward_strict;
{ --strict / {$STRICT ON} / --require-forward (feature-require-forward-strict-mode):
  FPC-parity routine visibility — a routine header must be ABOVE the call (full
  definition, `forward;`, an interface section, or a class method); the pre-scan's
  auto-forward is disabled. This POSITIVE test compiles under {$STRICT ON}: the
  explicit forward + mutual recursion + builtins/unit calls must all still bind.
  The NEGATIVE shapes (call-before-define without forward errors at the right
  line) are asserted by the Makefile with ! ./$(COMPILER) --strict runs. }
{$STRICT ON}
uses sysutils;

function OddN(n: Integer): Boolean; forward;

function EvenN(n: Integer): Boolean;
begin
  if n = 0 then EvenN := True else EvenN := OddN(n - 1);
end;

function OddN(n: Integer): Boolean;
begin
  if n = 0 then OddN := False else OddN := EvenN(n - 1);
end;

procedure Above;
begin
  writeln('above');
end;

procedure Caller;
begin
  Above;                       { defined above: fine }
  writeln(IntToStr(42));       { unit routine: always visible }
  writeln(Length('xy'));       { builtin: always visible }
end;

begin
  writeln(EvenN(10));          { TRUE }
  writeln(OddN(7));            { TRUE }
  Caller;
end.
