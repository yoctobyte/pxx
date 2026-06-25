program test_dynlib;
{ feature-real-dynlib-loader: dynlibs LoadLibrary/GetProcedureAddress/UnloadLibrary.
  Default build is the libc-free stub (LoadLibrary -> NilHandle -> "no loader").
  Built with -dPXX_DYNLIB_LIBC it wraps libc dlopen/dlsym/dlclose: loads
  libc.so.6, resolves strlen, calls it through a proc var. }
uses dynlibs;
type
  TStrLen = function(s: PChar): Integer;
var
  h: TLibHandle;
  fn: TStrLen;
  buf: array[0..5] of Char;
begin
  buf[0] := 'h'; buf[1] := 'e'; buf[2] := 'l'; buf[3] := 'l'; buf[4] := 'o'; buf[5] := #0;
  h := LoadLibrary('libc.so.6');
  if h = NilHandle then
    writeln('no loader')
  else
  begin
    fn := TStrLen(GetProcedureAddress(h, 'strlen'));
    writeln('strlen: ', fn(@buf[0]));
    writeln('unloaded: ', UnloadLibrary(h));
  end;
end.
