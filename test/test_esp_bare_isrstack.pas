program test_esp_bare_isrstack;
{ A REAL `interrupt;` HANDLER, INSTALLED AND ENTERED, RUNNING ON A DEDICATED
  ISR STACK (feature-s-a-csr-write-is-not-expressible-from-pascal-...).

  test_esp_bare_csr.pas proved a raw vector can be installed, but its handler
  was hand-written `assembler` -- it had to be, because taking the address of
  an `interrupt;` routine was refused. This is the other half: the directive's
  own codegen, entered by hardware for the first time.

  WHAT IT ASSERTS, AND WHY THE ASSERTION IS THE POINT RATHER THAN "IT RAN".
  A raw vector entry never reaches the IDF's rtos_int_enter, so before this
  landed a handler ran on the INTERRUPTED code's stack -- 3584 bytes by IDF
  default, no runtime stack guard on either ESP profile, and xPortInIsrContext
  answering 0 while genuinely inside an ISR. "The handler ran" is true in both
  worlds and so cannot distinguish them. The stack pointer can:

    without the switch   handler sp < task sp     (it pushed onto the task stack)
    with the switch      handler sp > task sp     (ISR region, above the task top)

  Stacks grow DOWN, so the failing arrangement necessarily puts the handler's
  sp BELOW the interrupted sp. The two outcomes are on opposite sides of the
  comparison and there is no arrangement of a broken build that lands on the
  passing side -- which is what makes this a guard rather than a decoration.
  defs.inc carves the top 1 KiB of the bare SRAM stack region for the ISR
  stack, so the boundary is ESP_BARE_TASK_STACK_TOP and the handler's sp must
  be above it.

  The handler also steps mepc past the `ecall`. `mret` restores PC from mepc,
  which for a synchronous trap addresses the trapping instruction itself, so a
  handler that does not advance it returns to the ecall and traps forever. Two
  ecalls are taken rather than one: a handler that fails to return correctly
  HANGS here, it does not miscount, and the second trap is what proves the
  round trip rather than just the entry. }

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
  hits    : Integer;
  isrSp   : Int64;
  taskSp  : Int64;
  hvec    : Pointer;

{$ifdef CPU_RISCV32}
procedure MyIsr; interrupt;
begin
  asm
    la   t1, isrSp
    sw   sp, 0(t1)
    { the handler's sp is 32-bit; clear the high word so the Int64 compare
      below is not reading whatever was in that slot }
    sw   zero, 4(t1)
    { step mepc past the 4-byte ecall }
    csrr t0, $341
    addi t0, t0, 4
    csrw $341, t0
  end;
  Inc(hits);
end;
{$endif}

begin
  hits := 0;
  isrSp := 0;
  taskSp := 0;

{$ifdef CPU_RISCV32}
  hvec := @MyIsr;
  asm
    la   t1, taskSp
    sw   sp, 0(t1)
    sw   zero, 4(t1)
    la   t1, hvec
    lw   t0, 0(t1)
    csrw $305, t0
    ecall
    ecall
  end;
{$else}
  { x86-64 oracle: no traps. Prints what a correct bare run prints. }
  hits := 2;
  taskSp := 1;
  isrSp := 2;
{$endif}

  PutS('isr hits '); PutInt(hits); PutC(10);
  if isrSp > taskSp then PutS('isr stack is above the task stack')
  else PutS('ISR RAN ON THE TASK STACK');
  PutC(10);
  if (hits = 2) and (isrSp > taskSp) then PutS('ISRSTACK-OK')
  else PutS('ISRSTACK-FAIL');
  PutC(10);
end.
