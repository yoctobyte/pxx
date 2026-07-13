{ A SELECTOR after an indexed-property read: `Self.Items[I].Clone` (fpjson's TJSONArray.Clone).

  A property getter's result is an ordinary value, so a selector may follow it. The
  ParseLValueAST getter path Exited as soon as it had built the getter call, leaving the
  `.Clone` unconsumed.

  What made that survive: an ASSIGNMENT tolerated it (`x := obj.Items[i].Method` -- the
  statement ended there anyway, so nobody noticed the leftover token), while an ARGUMENT LIST
  did not ("expected comma or close parenthesis"). So the obvious way to write the thing
  worked, and only `Take(obj.Items[i].Method)` failed. Both are asserted below. }
program test_selector_after_property_b289;
type
  TItem = class
    N: Integer;
    function Clone: TItem;
  end;
  TCont = class
  private
    FList: array[0..3] of TItem;
    function GetItem(i: Integer): TItem;
  public
    property Items[i: Integer]: TItem read GetItem;
    procedure Fill;
    procedure CopyTo(A: TCont);
  end;
function TItem.Clone: TItem;
begin Result := TItem.Create; Result.N := N * 100; end;
function TCont.GetItem(i: Integer): TItem;
begin Result := FList[i]; end;
procedure TCont.Fill;
var i: Integer;
begin
  for i := 0 to 3 do begin FList[i] := TItem.Create; FList[i].N := i + 1; end;
end;
procedure Take(x: TItem);
begin writeln('took ', x.N); end;
procedure TCont.CopyTo(A: TCont);
var i: Integer;
begin
  for i := 0 to 3 do
    Take(Self.Items[i].Clone);       { fpjson: A.Add(Self.Items[I].Clone) }
end;
var t: TCont;
begin
  t := TCont.Create; t.Fill;
  t.CopyTo(t);
  writeln('chained: ', t.Items[1].Clone.N);   { the deeper chain }
end.
