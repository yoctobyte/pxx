program test_esp_interrupt_direct_call_fail;
{ POSITIVE CONTROL for the AN_CALL arm of the `interrupt;` refusal (ir.inc).
  MUST BE REFUSED. A routine declared `interrupt;` returns via a trap-return
  (riscv32 `mret`, xtensa `rfe`), so a normal call into it restores a
  caller-saved set this caller never saved and returns through mepc / EPC
  instead of the return address -- with no diagnostic at link or at run time.
  `@MyIsr` has been refused since d305e1afa; the direct call is the same fault
  by another spelling and was accepted until 2026-09-23.

  THE CALL IS BEHIND AN ALWAYS-FALSE GUARD ON PURPOSE. That is the exact shape
  test_esp_interrupt.pas used to carry, and the shape a structural probe reaches
  for, so it is the one that most needs refusing: a refusal that only caught an
  unguarded call would miss every real instance. The guard makes no difference
  -- this is refused at IR lowering, not by reachability.
  bug-s-a-direct-call-to-an-interrupt-routine-is-the-same-trap-return-fault-by-another-spelling }
var
  counter: Integer;

procedure MyIsr; interrupt;
begin
  counter := counter + 1;
end;

begin
  counter := 0;
  if counter < 0 then MyIsr;
end.
