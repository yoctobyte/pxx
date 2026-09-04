{ INTERFACE `uses`: the alias minted for TBox<Integer> is part of what this unit
  publishes, and `TIntBox` names it in the interface. An importer must be able to
  hold one. }
unit ugsectb;
{$MODE DELPHI}

interface

uses ugsecta;

type
  TIntBox = TBox<Integer>;

function MakeB: TIntBox;

implementation

function MakeB: TIntBox;
begin
  Result.V := 101;
  Result.Tag := 1;
end;

end.
