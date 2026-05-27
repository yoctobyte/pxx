program TestExceptionControlFlow;
var
  i: Integer;
begin
  { Loop outside try: break leaves its handler frame. }
  while True do
  begin
    try
      break;
    except
      writeln(900);
    end;
  end;

  try
    raise 1;
  except
    writeln(1);
  end;

  { Loop outside try: continue leaves its handler frame each iteration. }
  i := 0;
  while i < 2 do
  begin
    Inc(i);
    try
      continue;
    except
      writeln(901);
    end;
  end;
  writeln(i);

  { Try outside loop: break stays protected. }
  try
    while True do
      break;
    raise 3;
  except
    writeln(3);
  end;

  { Try outside loop: continue stays protected. }
  i := 0;
  try
    while i < 2 do
    begin
      Inc(i);
      continue;
    end;
    raise 4;
  except
    writeln(4);
  end;

  { A jump may leave multiple nested protected bodies at once. }
  while True do
  begin
    try
      try
        break;
      except
        writeln(902);
      end;
    except
      writeln(903);
    end;
  end;
  try
    raise 5;
  except
    writeln(5);
  end;

  { For break uses the for-loop exit target. }
  for i := 1 to 2 do
  begin
    try
      break;
    except
      writeln(904);
    end;
  end;
  try
    raise 6;
  except
    writeln(6);
  end;

  { Repeat continue uses the until-condition target. }
  i := 0;
  repeat
    Inc(i);
    try
      continue;
    except
      writeln(905);
    end;
  until i = 2;
  try
    raise 7;
  except
    writeln(7);
  end;
end.
