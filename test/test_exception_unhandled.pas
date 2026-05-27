program TestExceptionUnhandled;

procedure ReturnEarly;
begin
  try
    Exit;
  except
    writeln(999);
  end;
end;

begin
  ReturnEarly;
  raise 7;
end.
