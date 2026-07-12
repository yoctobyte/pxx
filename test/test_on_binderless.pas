program test_on_binderless;
{ `on <Class> do` WITHOUT a binder variable (FPC/Delphi form, Synapse synautil
  uses `except on Exception do ;`). Also keeps the named form working. }
uses sysutils;
var hits: Integer;
begin
  hits := 0;
  try
    raise Exception.Create('boom');
  except
    on Exception do
      hits := hits + 1;
  end;
  try
    raise Exception.Create('bang');
  except
    on E: Exception do
      if E.Message = 'bang' then hits := hits + 10;
  end;
  writeln('hits=', hits);
end.
