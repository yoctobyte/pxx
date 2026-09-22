program test_esp_bare_vectorauto_rv;
{ Bare-metal RISCV32: an `interrupt;` handler installed BY THE COMPILER, with
  no mtvec write anywhere in this source (feature-s-the-xtensa-raw-isr-install-
  has-no-vecbase-write-and-no-isr-stack, third landing). Booted under the
  Espressif qemu on esp32c3 and diffed against the x86-64 oracle.

  THE XTENSA TWIN IS test_esp_bare_vectorauto.pas AND THE TWO ARE NOT
  DUPLICATES. They assert the same PROMISE -- declaring a routine `interrupt;`
  installs it -- through two mechanisms that share no code: VECBASE points at a
  1 KiB TABLE whose User slot holds a `j`, while mtvec holds the handler's
  ADDRESS directly. Nothing about one landing predicts the other, which is the
  whole reason this file exists rather than a `{$ifdef}` arm in that one.

  WHAT IS ASSERTED, and "the handler ran" is again not the whole of any row:
    1. the handler ran at all -- which here means the compiler emitted an
       mtvec write against an address this source never takes.
    2. isr sp ABOVE task sp -- it ran on the dedicated ISR stack.
    3. a call OUT of the handler returned. `interrupt;` implies `iram;` and on
       a bare ET_EXEC image that used to jump to address 0, on BOTH ISAs.
    4. the locals of the interrupted routine survived. This is the row that
       caught `assembler` not being `naked` on this chip -- a handler that
       corrupts the interrupted frame pointer is invisible to a program whose
       state is all globals.

  THE HANDLER STEPS mepc ITSELF, for the reason its xtensa twin steps EPC1: the
  right step is 4 for an `ecall` and 0 for an asynchronous interrupt that must
  resume where it was preempted, and a compiler that guessed would be wrong for
  one of the two and silent about it. Note the step differs from xtensa's 3 --
  `syscall` and `ecall` are not the same width, which is exactly the kind of
  detail that does not survive being carried across by analogy. }

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
  if n < 0 then begin PutC(45); n := -n; end;
  if n >= 10 then PutInt(n div 10);
  PutC(48 + n mod 10);
end;

var
  isrHits : Integer;
  isrSp   : Integer;
  taskSp  : Integer;
  localsOk: Integer;
  callsOk : Integer;

{$ifdef CPU_RISCV32}
procedure Bump;
{ Ordinary, non-iram, called only from the handler -- the shape that used to
  jump to address 0 on a bare ET_EXEC image. }
begin
  callsOk := 1;
end;

procedure MyIsr; interrupt;
begin
  asm
    la   t0, isrSp
    sw   sp, 0(t0)
    { step mepc past the 4-byte ecall -- see the header for why the compiler
      does not do this for you }
    csrr t0, $341
    addi t0, t0, 4
    csrw $341, t0
  end;
  isrHits := isrHits + 1;
  Bump;
end;

procedure TakesTrapWithLocals;
var la1, lb, lc: Integer;
begin
  la1 := 11; lb := 22; lc := 33;
  asm
    la   t0, taskSp
    sw   sp, 0(t0)
    ecall
  end;
  localsOk := 0;
  if (la1 = 11) and (lb = 22) and (lc = 33) then localsOk := 1;
end;
{$endif}

begin
  isrHits := 0; isrSp := 0; taskSp := 0; localsOk := 0; callsOk := 0;

{$ifdef CPU_RISCV32}
  { No mtvec write. No @MyIsr. Declaring it `interrupt;` is the install. }
  TakesTrapWithLocals;
{$else}
  { x86-64 oracle: no vectors, no traps. Prints what a correct bare run prints. }
  isrHits := 1; localsOk := 1; callsOk := 1;
  isrSp := 2; taskSp := 1;
{$endif}

  PutS('handler ran '); PutInt(isrHits); PutC(10);
  if callsOk = 1 then PutS('a call from the handler returned')
  else PutS('A CALL FROM THE HANDLER DID NOT RUN');
  PutC(10);
  if isrSp > taskSp then PutS('isr sp is ABOVE task sp')
  else PutS('ISR STACK NOT SWITCHED');
  PutC(10);
  if localsOk = 1 then PutS('locals survived the trap')
  else PutS('THE HANDLER CORRUPTED THE INTERRUPTED FRAME');
  PutC(10);
  if (isrHits = 1) and (callsOk = 1) and (isrSp > taskSp) and (localsOk = 1)
    then PutS('VECTORAUTORV-OK') else PutS('VECTORAUTORV-FAIL');
  PutC(10);
end.
