program esp_obj_dead_literals_take_no_room;
{ An ESP object carries only the string literals something still references
  (ObjRoDropDeadStrings). Unused's literal and the external's name must not be
  in the object; every literal the program prints must be, byte for byte,
  including one reached only through a typed-const array and one shared by a
  live and a dead routine. }
{$mode objfpc}
const
  Names: array[0..2] of AnsiString = ('alpha-in-const', 'beta-in-const', 'gamma-in-const');

{$ifdef PXX_PLATFORM_ESP}
function strlen_never_called(p: PChar): LongInt; cdecl; external name 'DEADLIT_EXTERNAL_NAME';

procedure Unused;
begin
  writeln('DEADLIT_UNUSED_ROUTINE_LITERAL');
  writeln('shared-literal');
  writeln(strlen_never_called('DEADLIT_ARG_LITERAL'));
end;
{$endif}

procedure Used(n: Integer);
var s: AnsiString;
begin
  s := 'live-' + Names[n mod 3];
  writeln(s);
  writeln('shared-literal');
end;

var i: Integer;
begin
  for i := 0 to 3 do Used(i);
  writeln('done');
end.
