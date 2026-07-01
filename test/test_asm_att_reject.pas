program AsmAttReject;
{ feature-inline-asm-depth TODO #6: inline asm is Intel syntax only --
  {$asmMode att} used to be silently accepted and ignored (would mis-encode,
  AT&T operand order), now errors cleanly. This program is a compile-time
  negative test: it must FAIL to compile, checked by the Makefile via
  `! ./$(COMPILER) ...` (test-core doesn't run it directly). }
{$asmMode att}
begin
end.
