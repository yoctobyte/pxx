program TestExceptionFinally;

var
  i: Integer;

procedure ReturnEarly;
begin
  try
    writeln(7);
    Exit;
  finally
    writeln(8);
  end;
  writeln(999);
end;

function ReturnValue: Integer;
begin
  try
    Exit(12);
  finally
    writeln(12);
  end;
end;

begin
  try
    writeln(1);
  finally
    writeln(2);
  end;

  try
    try
      raise 10;
    finally
      writeln(3);
    end;
  except
    writeln(4);
  end;

  i := 0;
  while i < 1 do
  begin
    Inc(i);
    try
      break;
    finally
      writeln(5);
    end;
  end;

  i := 0;
  while i < 1 do
  begin
    Inc(i);
    try
      continue;
    finally
      writeln(6);
    end;
  end;

  ReturnEarly;

  try
    try
      raise 11;
    except
      raise;
    end;
  except
    writeln(9);
  end;

  while True do
  begin
    try
      try
        break;
      finally
        writeln(10);
      end;
    finally
      writeln(11);
    end;
  end;

  writeln(ReturnValue);
end.
