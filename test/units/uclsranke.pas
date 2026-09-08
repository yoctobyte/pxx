{ uses uclsranka, uclsrankb -- the DEFECT's own order: a class row from the
  earlier unit and an alias from the later one. The alias must win. }
unit uclsranke; {$mode objfpc}
interface
uses uclsranka, uclsrankb;
function WhichInE: ShortString;
implementation
function WhichInE: ShortString;
var s: TShared;
begin
  s := TShared.Create;
  WhichInE := s.ClassName;
end;
end.
