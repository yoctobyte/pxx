unit ugmun;
{$mode objfpc}
{ A unit that declares a generic method NOTHING in the build ever calls. Before
  the zero-uses erase this unit could not be compiled at all -- not by a caller,
  not standalone. }
interface
type
  TBoxU = class
    function Tag: Integer;
    generic function Never<T>(a, b: T): T;
  end;
implementation
function TBoxU.Tag: Integer;
begin Result := 11; end;
generic function TBoxU.Never<T>(a, b: T): T;
begin Result := a + b; end;
end.
