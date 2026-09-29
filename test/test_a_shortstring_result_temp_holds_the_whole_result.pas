program test_a_shortstring_result_temp_holds_the_whole_result;
{ The caller's hidden temp for a ShortString result must hold all 256 bytes the
  callee copies out, whatever string[N] type the parser saw last.
  bug-a-a-frozen-string-call-result-temp-takes-a-stale-capacity }
{$mode objfpc}
{$modeswitch advancedrecords}

type
  TTest = record
    class operator :=(const aArg: TTest): ShortString;
  end;
  TString10 = String[10];

class operator TTest.:=(const aArg: TTest): ShortString;
var i: Integer;
begin
  Result := '';
  for i := 1 to 200 do Result := Result + 'x';
end;

function Plain(n: Integer): ShortString;
var i: Integer;
begin
  Result := '';
  for i := 1 to n do Result := Result + 'y';
end;

procedure Run;
var
  canary: array[0..299] of Byte;
  i, bad: Integer;
  t: TTest;
  s10: TString10;   { last: the stale capacity the temp used to take }
begin
  for i := 0 to 299 do canary[i] := 7;
  s10 := t;
  writeln(s10);
  s10 := Plain(250);
  writeln(s10);
  bad := 0;
  for i := 0 to 299 do
    if canary[i] <> 7 then Inc(bad);
  writeln('canary damage: ', bad);
end;

begin
  Run;
end.
