{ The negative control for test_a_var_may_not_redeclare_any_name_of_its_own_scope:
  a var in an INNER scope may reuse a name an outer scope declared as a string
  const, a set const, a type or a routine. fpc accepts all of these, and the
  inner declaration wins inside its routine only. }
program test_a_var_may_shadow_a_name_of_an_outer_scope;
{$mode objfpc}
type
  TWidth = Integer;
const
  TEL = 'hello';
  Digits = ['0'..'9'];

procedure Probe;
begin
  writeln('probe');
end;

procedure Shadow;
var
  tel: AnsiString;
  digits: Integer;
  TWidth: Integer;
  probe: Integer;
begin
  tel := 'local'; digits := 7; TWidth := 3; probe := 4;
  writeln(tel, ' ', digits, ' ', TWidth, ' ', probe);
end;

procedure Outer;
const Greeting = 'outer';
  procedure Inner;
  var greeting: AnsiString;
  begin
    greeting := 'inner';
    writeln(greeting);
  end;
begin
  Inner;
  writeln(Greeting);
end;

begin
  Shadow;
  Outer;
  Probe;
  writeln(TEL, ' ', '5' in Digits);
end.
