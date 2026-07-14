{ SPDX-License-Identifier: Zlib }
unit except_b339_base;
{ b339 helper: compiled BEFORE except_b339_derived, so EDerived does not exist
  when this unit's `on E: EMyBase` lowers. The target is NOT the root Exception,
  so the b322 root-catch-all shortcut does not cover it — only the runtime
  parent-chain walk does. }
interface

uses SysUtils;

type
  EMyBase = class(Exception);
  EOther  = class(Exception);

type
  TRaiser = procedure;

{ Returns what the handler saw: 'base' (matched on E: EMyBase), 'other'
  (fell through to the second handler), or 'none'. }
function CatchMyBase(R: TRaiser): AnsiString;

implementation

function CatchMyBase(R: TRaiser): AnsiString;
begin
  Result := 'none';
  try
    R();
  except
    on E: EMyBase do Result := 'base:' + E.ClassName;
    on E: EOther do Result := 'other:' + E.ClassName;
  end;
end;

end.
