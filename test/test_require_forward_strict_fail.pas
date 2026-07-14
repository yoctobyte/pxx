program test_require_forward_strict_fail;
{ NEGATIVE half of feature-require-forward-strict-mode: without the flag this
  compiles (pre-scan auto-forward, the pxx default); the Makefile asserts that
  `--strict` REJECTS it (call before definition, no forward;). }
procedure A;
begin
  B;
end;
procedure B;
begin
  writeln('b');
end;
begin
  A;
end.
