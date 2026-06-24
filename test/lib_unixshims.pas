program lib_unixshims;
{ Smoke for the FPC-compat unix shims (feature-synapse-compile-check):
  baseunix.fpgettimeofday (real CLOCK_REALTIME syscall), unix.Tzseconds,
  unixutil presence. Asserts the surface Synapse's synautil consumes. }
uses baseunix, unix, unixutil;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

var
  tv: TTimeVal;
  rc: cint;
begin
  rc := fpgettimeofday(@tv, nil);
  SayBool('gettimeofday', rc = 0);
  { Wall clock must be well past 2020-01-01 (epoch 1577836800) and before a far
    future bound — proves the syscall filled real seconds, not zero/garbage. }
  SayBool('tv_sec-sane', (tv.tv_sec > 1577836800) and (tv.tv_sec < 4102444800));
  SayBool('tv_usec-range', (tv.tv_usec >= 0) and (tv.tv_usec < 1000000));
  { nil tp is rejected, not crashed. }
  SayBool('nil-tp', fpgettimeofday(nil, nil) = -1);
  { Tzseconds exists and is the documented UTC default. }
  SayBool('tzseconds', Tzseconds = 0);
end.
