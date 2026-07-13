{ SPDX-License-Identifier: Zlib }
unit except_b322_thrower;
{ b322 helper: compiled BEFORE except_b322_late, so ELate does not exist when
  this unit's `on E: Exception` lowers. }
interface

type
  TRaiser = procedure;

procedure CatchAll(R: TRaiser);

implementation

uses SysUtils;

procedure CatchAll(R: TRaiser);
begin
  try
    R();
    Writeln('no raise');
  except
    on E: Exception do Writeln('caught ', E.ClassName, ': ', E.Message);
  end;
end;

end.
