unit ub;
interface
procedure B;
implementation
procedure B;
begin
{$ifdef LEAKED_FROM_UA}
  writeln('ub SEES ua''s define');
{$else}
  writeln('ub does not see it');
{$endif}
end;
end.
