program TestExceptionControlError;
begin
  while True do
  begin
    try
      break;
    except
      writeln(0);
    end;
  end;
end.
