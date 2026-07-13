{ SPDX-License-Identifier: Zlib }
unit except_b322_late;
{ b322 helper: declares an exception class the thrower unit never saw. }
interface

procedure RaiseLate;

implementation

uses SysUtils;

type
  ELate = class(Exception);

procedure RaiseLate;
begin
  raise ELate.Create('late class');
end;

end.
