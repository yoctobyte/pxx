program test_warn_self_result;

function Count: Integer;
begin
  Count := 1;
  Count := Count + 1;
end;

begin
  writeln(Count());
end.
