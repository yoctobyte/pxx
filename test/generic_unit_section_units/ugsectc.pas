{ IMPLEMENTATION `uses`: this unit specializes TBox<Integer> for its own use and
  publishes only an Integer. Nothing about the specialization is part of its
  interface, and an importer specializing the SAME template must get its own
  working type regardless -- the minted alias name is the same string in both
  files. }
unit ugsectc;
{$MODE DELPHI}

interface

function MakeC: Integer;

implementation

uses ugsecta;

function MakeC: Integer;
var b: TBox<Integer>;
begin
  b.V := 202;
  b.Tag := 2;
  Result := b.V;
end;

end.
