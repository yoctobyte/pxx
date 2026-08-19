unit test_unit_hint_directive_hu deprecated 'use the newer one instead';
{ FPC and Delphi both accept a hint directive on the UNIT declaration; a
  deprecated unit is exactly the kind a codebase keeps for compatibility, so
  refusing it means the unit cannot be compiled at all (Synapse's
  ssl_openssl.pas ends with one). compat-pascal-unit-deprecated-hint-directive }
interface
function HintTwo: Integer;
implementation
function HintTwo: Integer; begin HintTwo := 2; end;
end.
