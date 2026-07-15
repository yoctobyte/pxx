program test_io_checks_iplus;
{ {$I+} (opt-in — pxx's default stays quiet/IOResult-style pending the user's
  dialect call, see feature-pascal-io-checks-i-plus): a failed Text operation
  inside the region raises catchable EInOutError via the 4th sysutils hook;
  {$I-} keeps today's behavior. Semantics FPC-verified (caught=1, no
  'opened?', IOResult TRUE); FPC 3.2.2 itself drops the 'ioresult=' literal
  after the unwind (its Output buffering artifact), so the golden pins pxx's
  fuller line. }
uses sysutils;
var t: text; caught: Integer;
begin
  caught := 0;
  {$I+}
  assign(t, '/nonexistent/dir/file.txt');
  try
    reset(t);
    writeln('opened?');
  except
    on einouterror do inc(caught);
  end;
  {$I-}
  reset(t);
  writeln('ioresult=', IOResult <> 0, ' caught=', caught);
end.
