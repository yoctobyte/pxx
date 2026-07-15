program test_io_checks_mimic;
{ {$I+} is the DEFAULT (user dialect call 2026-07-15: code expects FPC's
  behavior; {$I-} opts out) — no directive in this file; the failed reset
  raises in BOTH default and --mimic-fpc compiles (Makefile runs both).
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
