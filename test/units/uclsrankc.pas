{ uses uclsrankb, uclsranka -- REVERSED, so uclsranka's CLASS is the later
  clause entry and must win. The control that stops "an alias always beats a
  class" from passing. }
unit uclsrankc; {$mode objfpc}
interface
uses uclsrankb, uclsranka;
function WhichInC: ShortString;
implementation
function WhichInC: ShortString;
var s: TShared;
begin
  s := TShared.Create;
  WhichInC := s.ClassName;
end;
end.
