unit Posix.SysSocket;
interface
const
  AF_INET = 2;
function SockTag: Integer;
implementation
function SockTag: Integer;
begin
  SockTag := 42;
end;
end.
