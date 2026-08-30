{ FPC's SysUtils declares `procedure OutOfMemoryError` (sysutilh.inc:243) and
  real code calls it as a bare statement in grow paths rather than raising the
  class itself -- rtl-generics does exactly that five times, and it is where the
  rung-6b corpus probe met `undefined variable (OutOfMemoryError)` once the
  generic body-extent fix let the compiler reach that far.

  EOutOfMemory already existed in lib/rtl/sysutils.pas; only the procedure was
  missing, so this asserts the routine EXISTS, RAISES, and raises the right
  class -- not merely that the name resolves.
  Oracle: FPC 3.2.2 prints the same two lines. }
program test_rtl_outofmemoryerror;
{$mode objfpc}
uses sysutils;
var caught: Boolean;
begin
  caught := False;
  try
    OutOfMemoryError;
    writeln('NOT RAISED');
  except
    on E: EOutOfMemory do
    begin
      caught := True;
      writeln('EOutOfMemory');
    end;
  end;
  if caught then writeln('ok') else writeln('MISSED');
end.
