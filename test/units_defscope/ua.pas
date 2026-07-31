unit ua;
{$define LEAKED_FROM_UA}
interface
procedure A;
implementation
procedure A; begin writeln('ua'); end;
end.
