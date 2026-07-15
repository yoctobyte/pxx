program test_io_checks_mimic;
{ --mimic-fpc defaults {$I+} ON (FPC-faithful) — no directive in this file;
  the failed reset must raise under mimic and stay quiet under the pxx-lax
  default (the Makefile compiles it BOTH ways).
  feature-pascal-io-checks-i-plus. }
uses sysutils;
var t: text; caught: Integer;
begin
  caught := 0;
  assign(t, '/nonexistent/dir/f');
  try
    reset(t);
  except
    on einouterror do inc(caught);
  end;
  writeln('caught=', caught);
end.
