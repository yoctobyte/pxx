unit uideriv;
interface
uses uibase;
var DerivInit: Integer;
implementation
{ Dependency ordering: uibase's begin-form init must have run already, so
  BaseInit is 7 here, not the BSS zero. }
begin
  DerivInit := BaseInit + 1;
end.
