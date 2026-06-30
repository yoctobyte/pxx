program test_uses_alias;
{ `uses <name> as <alias>` — the alias is a valid-identifier handle for qualified
  access to a unit's symbols (feature-uses-alias-as). Covers an unquoted name and
  a quoted name; qualified function + qualified type via the alias; and that
  unqualified access still works. }

uses
  sysutils as su,
  'classes' as cl;

var
  L: cl.TStringList;
begin
  writeln(su.IntToStr(42));        { qualified function via alias -> 42 }
  writeln(IntToStr(7));            { unqualified still works -> 7 }

  L := cl.TStringList.Create;      { qualified type + ctor via quoted-name alias }
  L.Add('a');
  L.Add('b');
  writeln(L.Count);                { 2 }
  L.Free;
end.
