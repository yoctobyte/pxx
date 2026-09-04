{ {$FATAL} is the directive whose ENTIRE PURPOSE is to stop the compile, and it
  was a no-op: `{$fatal nope}` compiled clean with exit 0, so a source saying
  "this configuration is unsupported, do not build" got a binary. Found while
  writing lib/rtl/signals.pas, which needed exactly this guard.

  The assertion is on the FAILURE, not on the absence of output -- a compile
  that stopped for any other reason would satisfy "no binary".
  bug-p-fatal-directive-is-silently-ignored }
program test_pascal_fatal_directive;
{$fatal this configuration is unsupported}
begin
  WriteLn('this program must never be built');
end.
