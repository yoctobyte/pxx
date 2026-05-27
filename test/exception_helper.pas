unit exception_helper;
interface
procedure FailFromUnit;
implementation
procedure FailFromUnit;
begin
  raise 12;
end;
end.
