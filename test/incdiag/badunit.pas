unit badunit;
{ The globtype.pas shape that produced the ticket: a unit that includes a
  file near its top and has an error far below. The reported line has to
  resolve in THIS file (not in the include, and not past this file's end),
  and the message has to name this file — the program that `uses` it does
  not name it anywhere. bug-a-a-parse-error-in-a-used-unit-reports-a-line-in-no-file }
interface
{$I pad.inc}
procedure Foo;
implementation
procedure Foo;
begin
  if then;
end;
end.
