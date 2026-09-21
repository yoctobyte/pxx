program test_esp_bare_vectorauto;
{ Bare-metal XTENSA: an `interrupt;` handler installed BY THE COMPILER, with no
  vector table built in the program and no VECBASE write anywhere in this
  source (feature-s-the-xtensa-raw-isr-install-has-no-vecbase-write-and-no-isr-
  stack, second landing). Booted under the Espressif qemu and diffed against
  the x86-64 oracle running the same source.

  THE DIFFERENCE FROM test_esp_bare_vector.pas IS EVERYTHING THIS FIXTURE
  ASSERTS. That one builds a 1 KiB-aligned table out of a BSS array, computes a
  `j` stub's 18-bit displacement with shifts and masks, and writes VECBASE from
  inline asm -- about twenty lines a program should not have to contain, and
  which no Pascal programmer would call usable. This one declares a routine
  `interrupt;` and takes a trap. Everything between those two sentences is the
  compiler's job now.

  BOTH FIXTURES STAY, AND THE OLDER ONE IS NOT SUPERSEDED. A program is still
  free to build its own table and point VECBASE at it -- the compiler's install
  is a DEFAULT, not a lock, and it runs at the top of the main body so any
  later write by the program wins. test_esp_bare_vector.pas is what keeps that
  path working; this one is what keeps the default honest. Keeping only one
  would leave the other silently rotting.

  WHAT IS ASSERTED, and "the handler ran" is not the whole of any row:
    1. the handler ran at all -- which here means the compiler emitted a table,
       aligned it, planted the User vector and wrote VECBASE, none of which
       this source mentions.
    2. isr sp ABOVE task sp -- it ran on the dedicated ISR stack.
    3. a call OUT of the handler returned. `interrupt;` implies `iram;`, and
       until 2026-09-22 that made any such call take the cross-section indirect
       path, whose literal only the ET_REL object writer patches -- so on a bare
       ET_EXEC image the handler jumped to address 0.
    4. the locals of the interrupted routine survived.

  THE HANDLER STILL HAS TO STEP EPC1 ITSELF, and that is deliberate rather than
  unfinished. `syscall` leaves EPC1 addressing the syscall, so returning without
  advancing it re-executes it forever -- but by how much is the HANDLER'S
  business and not the compiler's: 3 for a syscall, 0 for an asynchronous
  interrupt that must resume exactly where it was preempted. A compiler that
  guessed would be wrong for one of those two and silent about it. }

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

{$ifdef CPU_XTENSA}
procedure Bump;
{ Ordinary, non-iram, and called only from the handler -- which is the shape
  that used to jump to address 0. }
begin
  callsOk := 1;
end;

procedure MyIsr; interrupt;
begin
  asm
    la   a6, isrSp
    mov  a7, sp
    s32i a7, a6, 0
    { step EPC1 past the 3-byte syscall -- see the header for why the compiler
      does not do this for you }
    rsr  a7, $b1
    addi a7, a7, 3
    wsr  a7, $b1
  end;
  isrHits := isrHits + 1;
  Bump;
end;

procedure TakesTrapWithLocals;
var la1, lb, lc: Integer;
begin
  la1 := 11; lb := 22; lc := 33;
  asm
    la   a6, taskSp
    mov  a7, sp
    s32i a7, a6, 0
    syscall
  end;
  localsOk := 0;
  if (la1 = 11) and (lb = 22) and (lc = 33) then localsOk := 1;
end;
{$endif}

begin
  isrHits := 0; isrSp := 0; taskSp := 0; localsOk := 0; callsOk := 0;

{$ifdef CPU_XTENSA}
  { No table. No VECBASE. No @MyIsr. Declaring it `interrupt;` is the install. }
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
    then PutS('VECTORAUTO-OK') else PutS('VECTORAUTO-FAIL');
  PutC(10);
end.
