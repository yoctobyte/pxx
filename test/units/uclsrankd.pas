{ Declares its OWN alias of TShared, which must beat both used units. The
  control that stops a used unit's alias from outranking the current scope. }
unit uclsrankd; {$mode objfpc}
interface
uses uclsranka, uclsrankb;
type
  TOwnAlt = class R: LongInt; end;
  TShared = TOwnAlt;
function WhichInD: ShortString;
implementation
function WhichInD: ShortString;
var s: TShared;
begin
  s := TShared.Create;
  WhichInD := s.ClassName;
end;
end.
