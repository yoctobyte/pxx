program test_esp_interrupt;
{ `interrupt;` directive (riscv32 / esp32c3): the handler compiles as a raw
  hardware trap routine — its prologue saves the interrupted caller-saved context
  (t0-t6, a0-a7; ra/s0 via the normal frame), the body runs, the epilogue restores
  that context and returns via `mret`. The code lands in .iram1.text (interrupt
  routines must be IRAM-resident so a trap during a flash-cache stall doesn't
  re-fault). Installing the handler in mtvec + triggering a real trap needs a
  vector-table / CSR setup not yet expressible in PXX, so this is a STRUCTURAL
  probe: it forces the handler to be emitted (referenced behind a runtime-false
  guard, never executed — calling an ISR directly would mret into nowhere) so the
  .iram1.text section + the mret epilogue can be verified by disassembly. }
{$ifdef CPU_RISCV32}{$define PXX_ESP}{$endif}

{$ifdef PXX_ESP}
procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure PutC(code: Integer); begin esp_rom_printf('%c', code); end;
{$else}
procedure PutC(code: Integer);
var b: Byte; r: Int64;
begin
  b := code;
  r := __pxxrawsyscall(1, 1, Int64(@b), 1);
end;
{$endif}

var
  counter: Integer;

procedure MyIsr; interrupt;
begin
  counter := counter + 1;
  PutC(73);          { 'I' — proves the body emits + can cross-call into flash }
end;

begin
  counter := 0;
  PutC(83); PutC(10);          { 'S' }
  { Reference the ISR so it is emitted, but never run it (mret would fault here):
    counter is 0, so the guard is always false at runtime, yet the compiler still
    emits MyIsr and the cross-section call to it. }
  if counter < 0 then MyIsr;
  PutC(69); PutC(10);          { 'E' }
end.
