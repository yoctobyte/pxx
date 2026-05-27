program test_loop_control;

var
  i, j, total: Integer;
begin
  i := 0;
  total := 0;
  while i < 6 do
  begin
    Inc(i);
    if i = 2 then continue;
    if i = 5 then break;
    total := total + i;
  end;
  writeln(total);
  writeln(i);

  total := 0;
  for i := 1 to 6 do
  begin
    if i = 2 then continue;
    if i = 5 then break;
    total := total + i;
  end;
  writeln(total);

  i := 0;
  total := 0;
  repeat
    Inc(i);
    if i < 3 then continue;
    total := total + i;
  until i = 4;
  writeln(total);

  total := 0;
  for i := 1 to 3 do
  begin
    for j := 1 to 3 do
    begin
      if j = 2 then break;
      Inc(total);
    end;
  end;
  writeln(total);
end.
