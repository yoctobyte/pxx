{ Every pair below is one identifier declared twice in ONE scope, and fpc
  refuses each with "Duplicate identifier". pxx accepted all of them and let the
  later var win: remote_thermostat's 600-byte `const TEL` read as '' because a
  later `var tel: AnsiString` replaced it.
  bug-p-a-var-may-redeclare-a-string-const-type-or-routine-of-the-same-name
  MUST NOT COMPILE; the Makefile row asserts each message by text and that all
  seven are reported from one compile. Legal shadowing across scopes is
  test_a_var_may_shadow_a_name_of_an_outer_scope. }
program test_a_var_may_not_redeclare_any_name_of_its_own_scope;
{$mode objfpc}
type
  TSet = set of Char;
  TWidth = Integer;
const
  TEL = 'hello';
  Vowels: TSet = ['a', 'e'];
  Digits = ['0'..'9'];
var
  same: Integer;

procedure Probe;
begin
end;

var
  same: AnsiString;        { 1: a var twice, same spelling }
  tel: AnsiString;         { 2: a string const }
  digits: Integer;         { 3: a set const }
  TWidth: Integer;         { 4: a type }
  probe: Integer;          { 5: a routine }

procedure Local;
const Greeting = 'hi';
var greeting: AnsiString;  { 6: a string const of the same routine }
  procedure Inner;
  begin
  end;
var inner: Integer;        { 7: a nested routine of the same routine }
begin
end;

begin
end.
