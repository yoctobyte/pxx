program TestExceptions;

procedure Fail;
begin
  raise 42;
  writeln(999);
end;

begin
  try
    writeln(1);
    Fail;
    writeln(999);
  except
    writeln(2);
  end;

  try
    try
      raise 3;
    except
      raise 4;
    end;
  except
  else
    writeln(4);
  end;

  writeln(5);
end.
