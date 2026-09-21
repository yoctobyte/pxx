program test_esp_bare_csr;
{ Bare-metal RISC-V CSR access and a RAW TRAP VECTOR INSTALL, booted under the
  Espressif qemu and diffed against the x86-64 oracle running the same source
  (feature-s-a-csr-write-is-not-expressible-from-pascal-so-no-raw-isr-can-be-
  installed).

  WHAT THIS PROVES, AND WHY IT COULD NOT BE PROVEN BEFORE. Until 2026-09-21 the
  tree's only CSR write was `rv32_csrw_mstatus`, with the CSR address frozen in
  the instruction word, so `mtvec` -- the trap vector base, CSR $305 -- was not
  writable from any source spelling. That made `interrupt;` codegen complete and
  UNREACHABLE: the handler was correct and nothing could install it, so no trap
  had ever entered a PXX handler on any instrument. This fixture is the first
  thing in the tree that takes a trap.

  It exercises four things that all landed together and are only useful
  together: `csrw`/`csrr` with a numeric CSR, `mret`, and the Pascal `$` hex
  spelling for the address. The C spelling `0x305` does NOT work -- the
  inline-asm tokenizer splits it into `0` and the identifier `x305` -- and a
  named `mtvec` does not work either, because an identifier in an asm operand
  is resolved as a SYMBOL before the RISC-V assembler sees the line. `$305` is
  the spelling to write.

  THE HANDLER IS DELIBERATELY *NOT* DECLARED `interrupt;`, AND THAT IS THE
  POINT OF THE SHAPE RATHER THAN AN OVERSIGHT. Taking the address of an
  `interrupt;` routine is still refused (ir.inc), because a raw vector entry
  never reaches the IDF's rtos_int_enter and so runs on the interrupted task's
  stack with no ISR stack and no nesting counter. That refusal is the interlock
  that keeps this landing from shipping an installable-but-unprotected handler,
  and it stays until the stack story lands. So this fixture installs a
  hand-written assembler routine, whose address is ordinary and obtainable.

  DO NOT READ THIS HANDLER AS A TEMPLATE FOR AN ASYNCHRONOUS ONE. It clobbers
  t0-t3 without saving them, which is safe here only because `ecall` is
  SYNCHRONOUS -- it traps at one known instruction in this program, not at an
  arbitrary point in unrelated code. An async handler must save every
  caller-saved register, which is exactly what the `interrupt;` prologue does
  and why that directive exists.

  AND `assembler` IS NOT `naked` -- MEASURED 2026-09-22, AND THIS FIXTURE HAD
  THE BUG IT NOW GUARDS AGAINST. An `assembler` procedure still gets the full
  frame prologue: `addi sp,sp,-16`, save ra and s0, then **`mv s0,sp`**. That
  last one overwrites the INTERRUPTED code's frame pointer, and a bare `mret`
  leaves without restoring any of it -- so the handler both leaks 16 bytes of
  the interrupted stack per trap and hands control back with s0 pointing into
  the handler's own frame. Hence the explicit unwind before `mret` below,
  which is what the prologue's matching epilogue would have done.

  THE ORIGINAL VERSION OF THIS FIXTURE PASSED ANYWAY, FOR THE WRONG REASON:
  every variable it touches after the trap is a GLOBAL, and globals are not
  addressed through s0. A corrupted frame pointer is invisible to this program
  unless something reads a LOCAL across the trap. So the trap is now taken
  inside `TakesTrapWithLocals`, whose three locals live at s0-relative offsets
  and are checked afterwards. Measured both ways: without the unwind they read
  back as 1077416976 / 1077672896 / 1077672896 (stack addresses); with it,
  11 / 22 / 33. The same program with the handler declared `interrupt;`
  instead is correct with no unwind at all, because that directive emits the
  matching epilogue -- which is the clearest available statement of what the
  directive is for.

  Note the handler must also step `mepc` past the trapping instruction. `mret`
  restores PC from `mepc`, which for a synchronous trap addresses the `ecall`
  ITSELF -- so a handler that does not advance it returns to the ecall and
  traps forever. Being able to write that fix is itself a consequence of this
  landing: `mepc` is CSR $341. }

{$ifdef CPU_RISCV32}{$define PXX_CSR_REAL}{$endif}

procedure PutC(code: Integer);
begin
{$ifdef PXX_ESP_BARE}
  PByte(Int64($60000000))^ := Byte(code);
{$else}
  Write(Chr(code));
{$endif}
end;

procedure PutS(const s: AnsiString);
var i: Integer;
begin
  for i := 1 to Length(s) do PutC(Ord(s[i]));
end;

procedure PutInt(n: Integer);
begin
  if n >= 10 then PutInt(n div 10);
  PutC(48 + n mod 10);
end;

var
  hvec    : Pointer;
  trapHits: Integer;
  readback: Integer;
  localsOk: Integer;

{$ifdef PXX_CSR_REAL}
{ Raw trap handler. Increments trapHits, steps mepc past the ecall, mret. }
procedure TrapHandler; assembler;
asm
  la   t2, trapHits
  lw   t3, 0(t2)
  addi t3, t3, 1
  sw   t3, 0(t2)
  csrr t0, $341
  addi t0, t0, 4
  csrw $341, t0
  { unwind the frame `assembler` gave us -- see the header. ra and s0 belong
    to the interrupted code and the prologue's `mv s0,sp` destroyed s0. }
  lw   ra, 12(sp)
  lw   s0, 8(sp)
  addi sp, sp, 16
  mret
end;

{ The trap is taken in here rather than in the main body, because the main
  body's variables are globals and a corrupted frame pointer is invisible to
  those. These three are locals at s0-relative offsets. }
procedure TakesTrapWithLocals;
var la1, lb, lc: Integer;
begin
  la1 := 11; lb := 22; lc := 33;
  asm
    la   t1, hvec
    lw   t0, 0(t1)
    csrw $305, t0
    { read mtvec straight back: proves the write landed, independently of
      whether any trap is ever taken }
    csrr t1, $305
    la   t2, readback
    sw   t1, 0(t2)
    ecall
    ecall
  end;
  localsOk := 0;
  if (la1 = 11) and (lb = 22) and (lc = 33) then localsOk := 1;
end;
{$endif}

begin
  trapHits := 0;
  readback := 0;
  localsOk := 0;

{$ifdef PXX_CSR_REAL}
  hvec := @TrapHandler;
  TakesTrapWithLocals;
  if readback = Integer(hvec) then PutS('mtvec readback ok')
  else PutS('mtvec readback BAD');
{$else}
  { x86-64 oracle: no CSRs, no traps. Prints what a correct bare run prints. }
  trapHits := 2;
  localsOk := 1;
  PutS('mtvec readback ok');
{$endif}
  PutC(10);

  PutS('trap handler ran '); PutInt(trapHits); PutC(10);
  if localsOk = 1 then PutS('locals survived the trap')
  else PutS('THE HANDLER CORRUPTED THE INTERRUPTED FRAME');
  PutC(10);
  if (trapHits = 2) and (localsOk = 1) then PutS('CSR-OK') else PutS('CSR-FAIL');
  PutC(10);
end.
