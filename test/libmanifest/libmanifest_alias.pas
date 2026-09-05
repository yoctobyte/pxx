unit libmanifest_alias;
{ The TARGET of a `unitalias` row. Nothing here is about aliasing — the unit is
  deliberately dull, because what is under test is that a `uses Scoped.Alias`
  written one directory down reaches THIS file. }
interface
function AliasSees: AnsiString;
implementation
function AliasSees: AnsiString;
begin
  AliasSees := 'alias-ok';
end;
end.
