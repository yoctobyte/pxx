unit ugspecnon;
{ The NON-generic TTest, same name as ugspecgen's template. }
{$mode objfpc}
interface

type
  TTest = class
  public
    function Tag: Integer;
  end;

implementation

function TTest.Tag: Integer;
begin
  Tag := 7;
end;

end.
