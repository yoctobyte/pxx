unit uspec;
{ The unit the diagnostic must NAME. It specializes two generics, which splices
  thousands of tokens into the middle of the stream, and it `uses` uhelper,
  whose tokens are appended after this unit's. Before the fix, the splice moved
  every later token without moving the token->file boundaries with them, so the
  error on line 24 below was reported `in: ...uhelper.pas`. }
{$mode objfpc}
interface
uses uhelper;
type
  generic TBox<T> = class
  public
    V: T;
    function Get: T;
  end;
  TIntBox = specialize TBox<Integer>;
  TStrBox = specialize TBox<string>;
function Run: Integer;
implementation
function TBox.Get: T;
begin
  Result := V;
end;
function Run: Integer;
var b: TIntBox;
begin
  b := TIntBox.Create;
  Result := b.Get + Helper + NoSuchName;   { the deliberate error }
  b.Free;
end;
end.
