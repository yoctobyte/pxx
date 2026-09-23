program test_esp_interrupt;
{ `interrupt;` directive (riscv32 / esp32c3 and xtensa Call0 / esp32s3): the
  handler compiles as a raw hardware trap routine — its prologue saves the
  interrupted caller-saved context (riscv: t0-t6, a0-a7; xtensa Call0: a2-a8,
  a10-a13 — plus ra/s0 resp. a0/a15 via the normal frame), the body runs, the
  epilogue restores that context and returns via the hardware exception-return
  insn (riscv `mret`, xtensa `rfe`). The code lands in .iram1.text (interrupt
  routines must be IRAM-resident so a trap during a flash-cache stall doesn't
  re-fault). Installing the handler in the vector table + triggering a real trap
  needs CSR / vecbase setup not yet expressible in PXX, so this is a STRUCTURAL
  probe: the handler is emitted with NOTHING referencing it, so the .iram1.text
  section + the mret/rfe epilogue can be verified by disassembly.

  NOTHING REFERENCES MyIsr AND THAT IS THE POINT. Until 2026-09-23 this file
  carried `if counter < 0 then MyIsr;` — a call behind an always-false guard —
  believed to be the only way to force the body to be emitted. It was not, and a
  direct call to an `interrupt;` routine is now REFUSED (ir.inc, AN_CALL): it is
  the same trap-return-out-of-a-normal-call fault as `@MyIsr`, which has been
  refused since d305e1afa. An `interrupt;` body is an unconditional DCE root of
  its own (dce.inc, DCE_WHY_VECTOR — `--dce-why=MyIsr` prints `MyIsr <-
  [interrupt; -- entered by hardware]`), and it has been one since 57af7aa10,
  which added the root for bare xtensa's vector table. So the guard was dead
  weight that also demonstrated the very mistake the compiler now rejects.

  DO NOT "FIX" A FUTURE DCE REGRESSION BY CALLING THE HANDLER AGAIN. If MyIsr
  ever stops appearing in .iram1.text, the root is what broke; the Makefile rows
  for this file assert its presence and its section for exactly that reason. }
{$ifdef CPU_RISCV32}{$define PXX_ESP}{$endif}
{$ifdef CPU_XTENSA}{$define PXX_ESP}{$endif}

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
  { MyIsr is deliberately not named here — see the header. }
  PutC(69); PutC(10);          { 'E' }
end.
