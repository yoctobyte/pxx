program fpcv;
{$mode objfpc}{$H+}
uses SysUtils, Variants;
var v: Variant; i: Integer; b: Boolean; d: Double;
begin
  v := '42';
  try i := v; writeln('int of ''42''  = ', i); except on e: Exception do writeln('int of ''42''  EXC: ', e.ClassName); end;
  v := 'abc';
  try i := v; writeln('int of ''abc'' = ', i); except on e: Exception do writeln('int of ''abc'' EXC: ', e.ClassName); end;
  v := '2.5';
  try d := v; writeln('dbl of ''2.5'' = ', d:0:2); except on e: Exception do writeln('dbl of ''2.5'' EXC: ', e.ClassName); end;
  v := '';
  try b := v; writeln('bool of ''''    = ', b); except on e: Exception do writeln('bool of ''''    EXC: ', e.ClassName); end;
  v := 0.0;
  try b := v; writeln('bool of 0.0   = ', b); except on e: Exception do writeln('bool of 0.0   EXC: ', e.ClassName); end;
end.
