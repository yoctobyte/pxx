{ A method's RETURN-TYPE class id must be recorded at its DECLARATION, not when its body is
  parsed.

  It used to be set only at the body -- so a method called BEFORE its own implementation
  appeared (an ordinary thing inside one unit: fpjson's TJSONData.DumpJSON reads
  `O.Items[I].DumpJSON(S)` long before TJSONObject.GetItem's body) had ProcRetRecId = REC_NONE.
  A selector on its result then could not resolve: `.DumpJSON` silently degraded to a FIELD
  access, and the statement demanded a ':='.

  Below, DumpAll's body deliberately precedes GetItem's. }
program test_decl_order_ret_recid_b291;
type
  TItem = class
    N: Integer;
    procedure Dump(const pre: string);
  end;
  TCont = class
  private
    FList: array[0..2] of TItem;
    function GetItem(i: Integer): TItem;      { declared here... }
  public
    property Items[i: Integer]: TItem read GetItem;
    procedure Fill;
    procedure DumpAll;
  end;

{ DumpAll's BODY comes BEFORE GetItem's body -- ordinary inside one unit }
procedure TCont.DumpAll;
var i: Integer;
begin
  for i := 0 to 2 do
    Items[i].Dump('#');            { a selector on the getter's result }
  writeln;
end;

procedure TItem.Dump(const pre: string);
begin write(pre, N, ' '); end;

function TCont.GetItem(i: Integer): TItem;   { ...implemented AFTER its use }
begin Result := FList[i]; end;

procedure TCont.Fill;
var i: Integer;
begin
  for i := 0 to 2 do begin FList[i] := TItem.Create; FList[i].N := i + 1; end;
end;

var t: TCont;
begin
  t := TCont.Create; t.Fill; t.DumpAll;
end.
