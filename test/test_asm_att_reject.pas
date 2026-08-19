program AsmAttReject;
{ feature-inline-asm-depth TODO #6 / feature-pascal-asmmode-directive-tolerance:
  inline asm is Intel syntax only. The DIRECTIVE `{$asmMode att}` is accepted as
  of 76b6fb7f1 (FPC sources carry it in units whose asm blocks we never reach);
  the refusal moved to the point where it matters, an actual asm block that
  would be mis-encoded in Intel operand order.

  This program is a compile-time negative test: it must FAIL to compile,
  checked by the Makefile via `! ./$(COMPILER) ...` (test-core doesn't run it
  directly). Before 76b6fb7f1 the bare directive was what failed here; keeping
  that assertion would have re-broken the tolerance the feature added. }
{$asmMode att}
begin
  asm
    movl $1, %eax
  end;
end.
