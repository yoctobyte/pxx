{ Two INDEPENDENT unresolved names, and a third mention of the first one.

  Expected: the compiler reports the first two once each and exits 1 without
  writing an output file. It used to report `alpha` and halt, so a file with ten
  typos cost ten compile cycles.

  `alpha` appears twice on purpose: recovery registers the failed name, so the
  second mention resolves against the stand-in and stays quiet. One line per
  MISTAKE, not per occurrence.
  feature-a-error-does-not-halt-so-a-parse-can-be-speculative }
program test_two_undefined_names_both_report_fail;
var ok: Integer;
begin
  ok := 1;
  alpha := ok + 1;
  writeln(beta);
  writeln(alpha);
  writeln(ok);
end.
