{ `for i := 0 to ParamCount do` — the ParamCount node must carry a TYPE.

  Left untyped it defaulted to tyUnknown, and the hidden for-loop LIMIT temp
  copied that. x86-64, aarch64, arm32 and riscv32 never inspect it and happened
  to work; i386 checks every symbol it touches, so it refused — which meant
  `uses pylib` could not be built for i386 at all, since pylib's own pysys_argv
  is exactly this loop. That took base64, http and examples/net/httpdemo.pas
  with it (the test-i386 httpdemo red), and every NilPy program besides.

  Hoisting the limit into a variable worked, and a USER function as the limit
  worked — the pair is what localised it to the ParamCount node rather than to
  the for-loop lowering. Output below is FPC's, minus argv[0], which differs by
  path.
  bug-a-paramcount-node-has-no-type-so-i386-refuses-any-pylib-user }
program test_paramcount_for_limit;
var i, n: Integer;
begin
  n := 0;
  { argv[0] is the binary path — counted, never printed, so the expectation
    holds wherever the test binary is written. }
  for i := 0 to ParamCount do n := n + 1;
  writeln('iters=', n);
  writeln('count=', ParamCount);
  for i := 1 to ParamCount do writeln(i, ':', ParamStr(i));
end.
