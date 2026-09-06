unit ugmund;
{$mode delphi}
{ The same shape on the Delphi surface, which never writes the `generic`
  keyword -- both surfaces reach ExpandGenericMethod and both must erase. }
interface
type
  TBoxD = class
    function Tag: Integer;
    function Never<T>(a, b: T): T;
  end;
implementation
function TBoxD.Tag: Integer;
begin Result := 22; end;
function TBoxD.Never<T>(a, b: T): T;
begin Result := a + b; end;
end.
