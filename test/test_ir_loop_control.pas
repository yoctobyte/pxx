program TestIRLoopControl;
var
  I, Sum: Integer;
begin
  { While Loop with Break }
  I := 0;
  Sum := 0;
  while I < 10 do
  begin
    I := I + 1;
    if I = 5 then break;
    Sum := Sum + I;
  end;
  writeln(Sum); { 10 }

  { While Loop with Continue }
  I := 0;
  Sum := 0;
  while I < 5 do
  begin
    I := I + 1;
    if I = 3 then continue;
    Sum := Sum + I;
  end;
  writeln(Sum); { 12 }

  { For Loop with Break }
  Sum := 0;
  for I := 1 to 10 do
  begin
    if I = 6 then break;
    Sum := Sum + I;
  end;
  writeln(Sum); { 15 }

  { For Loop with Continue }
  Sum := 0;
  for I := 1 to 5 do
  begin
    if I = 3 then continue;
    Sum := Sum + I;
  end;
  writeln(Sum); { 12 }

  { Repeat Loop with Break }
  I := 0;
  Sum := 0;
  repeat
    I := I + 1;
    if I = 4 then break;
    Sum := Sum + I;
  until I >= 10;
  writeln(Sum); { 6 }

  { Repeat Loop with Continue }
  I := 0;
  Sum := 0;
  repeat
    I := I + 1;
    if I = 3 then continue;
    Sum := Sum + I;
  until I >= 5;
  writeln(Sum); { 12 }
end.
