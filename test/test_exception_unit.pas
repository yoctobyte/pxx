program TestExceptionUnit;
uses exception_helper;
begin
  try
    FailFromUnit;
  except
    writeln(6);
  end;
end.
