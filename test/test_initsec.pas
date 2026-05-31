program test_initsec;
uses initsec_a, initsec_b;
begin
  { A.init runs first (dependency), then B.init appends 'B'. finalization skipped. }
  writeln(Log);
end.
