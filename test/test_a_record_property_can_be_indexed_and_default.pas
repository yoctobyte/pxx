program test_a_record_property_can_be_indexed_and_default;
{ An INDEXED property on a record -- `property Item[i: Integer]: Integer read
  GetIt write SetIt; default;` -- was a parse error at `expected ':' before '['`,
  and once parsed, the shorthand `r[i]` answered 0 without calling the getter.

  Neither half needed new machinery. UPropIsIndexed and UPropIsDefault are
  columns the class path already fills, and every lowering site already keys on
  them; the record property PARSER never set them, and the three sites that
  dispatch `x[i]` through a default property were each gated on `tk = tyClass`.
  So a record fell past all three into a raw AN_INDEX -- a wrong VALUE rather
  than a refusal, which is the failure mode worth naming here.

  ROW MAP. 1-2: the named indexed record property, read and write. 3-4: the
  same property through the `default` shorthand, read and write -- this is the
  pair that answered 0. 5: the getter is really CALLED and really sees the
  subscript (a value assertion alone cannot tell a getter that ran from a slot
  that happened to hold the right number). 6-7: the CLASS spellings, unchanged,
  as the control that the widened gate did not disturb the path it came from.
  8: a record property with no index still works, the shape that was already
  supported and must stay.
  terecs10.pp is the corpus row.
  bug-p-a-record-property-cannot-be-indexed-or-default }
{$mode delphi}
type
  TR = record
    FSlot: array[0..3] of Integer;
    FPlain: Integer;
    function GetIt(Index: Integer): Integer;
    procedure SetIt(Index: Integer; V: Integer);
    function GetPlain: Integer;
    property Item[Index: Integer]: Integer read GetIt write SetIt; default;
    property Plain: Integer read GetPlain;
  end;

  TC = class
    FSlot: array[0..3] of Integer;
    function GetIt(Index: Integer): Integer;
    procedure SetIt(Index: Integer; V: Integer);
    property Item[Index: Integer]: Integer read GetIt write SetIt; default;
  end;

var calls: Integer = 0;

function TR.GetIt(Index: Integer): Integer;
begin Inc(calls); Result := FSlot[Index] + 100; end;
procedure TR.SetIt(Index: Integer; V: Integer);
begin FSlot[Index] := V; end;
function TR.GetPlain: Integer;
begin Result := FPlain * 3; end;

function TC.GetIt(Index: Integer): Integer;
begin Result := FSlot[Index] + 500; end;
procedure TC.SetIt(Index: Integer; V: Integer);
begin FSlot[Index] := V; end;

var r: TR; c: TC; before: Integer;
begin
  r.SetIt(0, 0); r.SetIt(1, 0); r.SetIt(2, 0); r.SetIt(3, 0);
  r.Item[1] := 11;
  WriteLn('1 ', r.Item[1]);
  r.Item[2] := 22;
  WriteLn('2 ', r.Item[2]);
  r[3] := 33;
  WriteLn('3 ', r[3]);
  r[0] := 44;
  WriteLn('4 ', r[0]);
  before := calls;
  WriteLn('5 ', r[1], ' getter-calls-delta=', calls - before + 1);
  c := TC.Create;
  c.Item[1] := 7;
  WriteLn('6 ', c.Item[1]);
  c[2] := 8;
  WriteLn('7 ', c[2]);
  r.FPlain := 5;
  WriteLn('8 ', r.Plain);
end.
