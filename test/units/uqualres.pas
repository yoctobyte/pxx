unit uqualres;
{ A unit whose globals are named EXACTLY like the routines that read them, for
  test_a_unit_qualified_read_of_a_same_named_global.pas. The collision is the
  whole point: `uqualres.BOAT` read inside `function boat` was compiled as boat's
  RESULT variable, because the bare-own-name arm matched on the name alone and
  never asked whether the name carried a qualifier. }
interface

var
  BOAT: Integer = 115;
  Other: Integer = 60;
  DeckName: string = 'teak';

function Hull: Integer;

implementation

function Hull: Integer;
begin
  Hull := 11;
end;

end.
