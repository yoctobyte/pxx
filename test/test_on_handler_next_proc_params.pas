program test_on_handler_next_proc_params;
{ A `try..except on E: ... do` handler binder allocated mid-block used to
  poison the NEXT routine's params: AllocParam left SymBlockId stale from the
  recycled slot, so FindSym filtered the params invisible
  ("undefined variable (Enable)" in blcksock's SetLinger). }
uses sysutils;
procedure Purge;
begin
  try
    writeln('purging');
  except
    on e: Exception do writeln('caught');
  end;
end;
procedure SetLinger(Enable: Boolean; Linger: Integer);
begin
  writeln(Enable, ' ', Linger);
end;
begin
  Purge;
  SetLinger(True, 7);
end.
