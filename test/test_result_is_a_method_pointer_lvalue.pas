program test_result_is_a_method_pointer_lvalue;
{ `Result := <method reference>` inside a function whose return type is a
  method pointer.

  The LHS spelling was a third axis, orthogonal to the receiver spellings that
  bug-p-a-parenless-method-reference-handles-two-of-four-receiver-spellings
  covers: all three receivers (`s.Pick`, `Self.Pick`, bare `Pick`) worked with a
  declared LOCAL on the left and all three were refused with `Result` on the
  left, because the implicit result symbol is minted from the return KIND alone
  and so carried no procedural signature. Every arm that asks "is this lvalue a
  procedural value?" gates on `SymProcSig >= 0` and got -1 for Result.

  So each row here goes through `Result :=` and then CALLS THROUGH the returned
  value -- asserting it is non-nil would pass on a Result that is furnished but
  mis-marshalled. The `ViaLocal` row is the workaround that always worked and is
  kept as the control: if the fix ever regresses to furnishing nothing, that row
  still prints and the other three stop.

  Oracle: fpc 3.2.2 -Mdelphi -O1, byte-identical output.
  bug-p-result-is-not-a-method-pointer-lvalue }
{$mode delphi}
type
  TSel = procedure of object;
  TSvc = class
    procedure Pick;
    function  ViaSelf: TSel;
    function  ViaBare: TSel;
    function  ViaLocal: TSel;
  end;
procedure TSvc.Pick; begin writeln('picked'); end;
function TSvc.ViaSelf: TSel;  begin Result := Self.Pick; end;
function TSvc.ViaBare: TSel;  begin Result := Pick; end;
function TSvc.ViaLocal: TSel; var t: TSel; begin t := Self.Pick; Result := t; end;
function FreeFn(s: TSvc): TSel;
begin
  Result := s.Pick;
end;
var s: TSvc; f: TSel;
begin
  s := TSvc.Create;
  writeln('free');  f := FreeFn(s);  f();
  writeln('self');  f := s.ViaSelf;  f();
  writeln('bare');  f := s.ViaBare;  f();
  writeln('local'); f := s.ViaLocal; f();
end.
