unit unit_end_shapes_a;
{ Every legitimate `end` shape a unit implementation section can present, for
  bug-p-a-stray-end-at-unit-implementation-top-level-is-silently-skipped.

  This is the half that keeps the new diagnostic honest. "A stray `end` is now
  an error" is a claim no test can falsify in the direction that actually
  breaks people -- an over-eager arm rejecting ordinary source -- unless
  something asserts that the ordinary shapes still compile. The tkEnd arm is
  reached once per top-level `end` in the pre-scan loop, so each shape below is
  a distinct opportunity for it to fire wrongly.

  This unit carries the `initialization`/`finalization` pair; its sibling
  carries the classic `begin ... end.` initialization form, because a unit
  cannot have both. }
interface

type
  TCounter = class
    Value: Integer;
    procedure Bump;
    function Describe(k: Integer): AnsiString;
  end;

function ShapesTotal: Integer;

implementation

var
  gTotal: Integer;

{ nested begin/end, an if/else with block arms, and a case -- three `end`s that
  belong to statements, none of them top level }
function ShapesTotal: Integer;
var i, acc: Integer;
begin
  acc := 0;
  for i := 1 to 3 do
  begin
    case i of
      1: acc := acc + 1;
      2: begin acc := acc + 2; end;
    else
      begin
        acc := acc + 3;
      end;
    end;
  end;
  ShapesTotal := acc + gTotal;
end;

{ a method body, and a record-valued local with a with-block }
procedure TCounter.Bump;
begin
  Value := Value + 1;
end;

{ a function whose body ends on a nested end, plus an inline try/finally }
function TCounter.Describe(k: Integer): AnsiString;
var s: AnsiString;
begin
  s := '';
  try
    if k > 0 then
    begin
      s := 'pos';
    end
    else
    begin
      s := 'nonpos';
    end;
  finally
    s := s + '!';
  end;
  Describe := s;
end;

initialization
  gTotal := 10;

finalization
  gTotal := 0;

end.
