program test_a_soft_keyword_statement_still_works;
{$mode objfpc}
{ The unshadowed half of test_a_soft_keyword_name_can_be_a_function_result.pas,
  in its own file because it has to be: once `break` / `continue` / `exit` /
  `halt` are declared as functions, shadowing is TOTAL and the statement forms
  are unreachable — pxx and fpc 3.2.2 agree on that, to the line
  (`Wrong number of parameters specified for call to "continue"`). So a control
  for the statements cannot live beside the declarations, and a file that
  declared them and then claimed to test the statements would be testing the
  user routines under the statements' names.

  Nothing here is new behaviour. It is the row that must not move. }
var
  i: Integer;

function counted: Integer;
begin
  Result := 0;
  for i := 1 to 10 do
  begin
    if i = 3 then continue;
    if i = 7 then break;
    Inc(Result);
  end;
end;

procedure early;
begin
  writeln('early   in');
  exit;
  writeln('NOT REACHED');
end;

begin
  writeln('counted ', counted);
  early;
  writeln('bye');
  halt(5);
  writeln('NOT REACHED EITHER');
end.
