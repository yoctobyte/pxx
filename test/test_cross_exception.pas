program TestCrossException;

procedure Fail(val: Integer);
begin
  raise val;
  writeln(999);
end;

procedure TestExcept;
begin
  try
    writeln(1);
    Fail(42);
    writeln(999);
  except
    writeln(2);
  end;
end;

procedure TestFinally;
begin
  try
    writeln(3);
    try
      writeln(4);
      Fail(100);
      writeln(999);
    finally
      writeln(5);
    end;
  except
    writeln(6);
  end;
end;

procedure TestReraise;
begin
  try
    try
      Fail(77);
    except
      writeln(7);
      raise;
    end;
  except
    writeln(8);
  end;
end;

begin
  TestExcept;
  TestFinally;
  TestReraise;
  writeln(9);
end.
