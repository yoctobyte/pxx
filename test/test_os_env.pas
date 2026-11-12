{ The process environment, read the way every pxx runtime reads it
  (/proc/self/environ). On --os=freebsd there is no /proc: the in-program
  translator answers that path from sysctl kern.proc.env. Run by
  `make test-freebsd` on both kernels with PXX_TEST_PROBE set; output must match.
  feature-port-freebsd-native }
program test_os_env;
uses SysUtils;
begin
  WriteLn('probe=', GetEnvironmentVariable('PXX_TEST_PROBE'));
  WriteLn('missing=[', GetEnvironmentVariable('PXX_TEST_NO_SUCH_VARIABLE'), ']');
  WriteLn('count>0=', GetEnvironmentVariableCount > 0);
  WriteLn('argv0=', ExtractFileName(ParamStr(0)));
  { FreeBSD's entry rsp sat 8 below argc on about half of all runs
    (ParamCount = -1); test-freebsd runs this 8 times. }
  WriteLn('argc=', ParamCount, ' [', ParamStr(1), '] [', ParamStr(2), ']');
end.
