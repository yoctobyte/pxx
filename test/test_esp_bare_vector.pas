program test_esp_bare_vector;
{ Bare-metal XTENSA RAW VECTOR INSTALL and the raw-ISR STACK, booted under the
  Espressif qemu and diffed against the x86-64 oracle running the same source
  (feature-s-the-xtensa-raw-isr-install-has-no-vecbase-write-and-no-isr-stack).

  The xtensa completion of what test_esp_bare_csr.pas did for riscv32, and it
  took three things that had to land together, for the reason that ticket's
  sibling established: an install with no ISR stack is a handler running on the
  interrupted task's stack with no runtime guard, so shipping the install alone
  would only have unlocked the hazard.

  WHY THIS IS NOT ONE INSTRUCTION, WHICH IS THE THING THAT DOES NOT TRANSFER
  FROM riscv32. `mtvec` is a HANDLER address; VECBASE is a TABLE base, with
  each vector at a fixed offset from it (0x180 Level2 ... 0x300 Kernel, 0x340
  User, 0x3C0 Double, 0x400 end). So `wsr a4, $e7` on its own relocates a table
  a bare PXX image does not have. This builds one at runtime, in a 1 KiB-aligned
  window carved out of an over-allocated BSS array, and plants a stub in it.

  THE STUB IS A SINGLE `j`, AND THAT IS WHAT MAKES THE WHOLE THING CHEAP.
  Xtensa's `j` is an 18-bit PC-relative jump -- +/-128 KiB, no register operand,
  no literal pool -- so the table entry hands the handler a COMPLETELY UNTOUCHED
  machine. That matters beyond the stub: it is why the `interrupt;` prologue can
  spend EXCSAVE_1 on its stack switch without first having to give back an a-reg
  the stub borrowed. A stub that materialised a 32-bit address would have needed
  EXCSAVE_1 itself and the two would have had to agree about handing it over.
  The encoding is ((target - pc - 4) shl 6) or $06, verified against
  xtensa-esp32s3-elf-as rather than remembered.

  ONLY THE USER VECTOR IS PLANTED, AND THAT IS AN ASSERTION RATHER THAN AN
  ECONOMY. Routing depends on PS: EXCM=1 sends every exception to the DOUBLE
  vector at 0x3C0 with its PC in DEPC and needing RFDE, while EXCM=0 with UM=1
  sends it to the User vector at 0x340 with its PC in EPC1 and needing RFE --
  which is the one the `interrupt;` epilogue emits. Until 2026-09-22 no bare
  image wrote PS at all, so it ran with the reset value (measured: $1F, EXCM
  SET) and the epilogue was returning from the wrong KIND of exception with the
  wrong register; EPC1 read back as 0 and the RFE jumped to address 0. The
  entry stub now writes PS = $2F, so planting 0x340 ALONE fails loudly if that
  ever regresses, where planting 0x300 and 0x3C0 as well would quietly absorb
  it.

  WHAT THE ASSERTIONS ARE, and none of them is "the handler ran":
    1. isr sp ABOVE task sp -- the handler is on the dedicated ISR stack
       (defs.inc ESP_BARE_ISR_STACK_*, the top 1 KiB of the SRAM stack region),
       not on the interrupted code's. This is the row that reddens if the
       prologue's switch is removed while the handler still runs perfectly.
    2. the interrupted code's LOCALS survive -- the `interrupt;` epilogue
       restores the frame its prologue built. test_esp_bare_csr.pas is the
       cautionary tale here: it asserted only that the handler ran, and passed
       for a year's worth of the wrong reason because every variable it checked
       was a global and globals are not addressed through the frame pointer.
    3. the syscall RETURNED -- EPC1 was stepped past it. `syscall` is 3 bytes
       and the hardware does not advance PC, so a handler that does not add 3
       re-executes it forever. That is +3 here against riscv32's +4, which is
       the other thing a copyist gets wrong.

  EXCSAVE_1 ($D1) is the prologue's scratch. It is architecturally a scratch
  register the hardware never reads, and it is per-LEVEL: this prologue is
  level-1 only, which is not a restriction it invented but the same fact its
  epilogue already commits to by returning via `rfe`. }

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
  { 2 KiB so a 1 KiB-aligned 1 KiB window always fits inside it, whatever the
    linker gave us. VECBASE ignores the low 10 bits, so an unaligned table is
    not a wrong table -- it is a table at a DIFFERENT address, which is worse:
    the stub lands wherever the truncation points and there is no diagnostic. }
  vecRaw  : array[0..2047] of Byte;
  isrHits : Integer;
  isrSp   : Integer;
  taskSp  : Integer;
  excCause: Integer;
  localsOk: Integer;
  jReach  : Integer;
  callsOk : Integer;
  { Declared up here with the rest, not beside its use: an inline-asm `la`
    resolves an ordinary forward-declared symbol, and one declared after the
    procedure that names it is `asm: unknown symbol`. }
  vecBaseSlot: Integer;

{$ifdef CPU_XTENSA}
procedure Bump;
{ An ORDINARY (non-iram) procedure, deliberately: the call from VecHandler to
  this one is what crosses the iram boundary the compiler used to mishandle. }
begin
  callsOk := 1;
end;

procedure VecHandler; interrupt;
begin
  asm
    { sp here is the handler's own frame, inside the ISR region if the
      prologue switched. Recorded rather than compared in asm so the
      comparison itself is ordinary Pascal and readable. }
    la   a6, isrSp
    mov  a7, sp
    s32i a7, a6, 0
    la   a6, excCause
    rsr  a7, $e8              { EXCCAUSE: 1 = SyscallCause }
    s32i a7, a6, 0
    { Step EPC1 past the 3-byte syscall. Without this the rfe in the epilogue
      returns straight to the syscall and the program never leaves the trap. }
    rsr  a7, $b1
    addi a7, a7, 3
    wsr  a7, $b1
  end;
  isrHits := isrHits + 1;
  { A CALL from inside the handler, which is the thing that was broken until
    2026-09-22 and is invisible to every other assertion here. `interrupt;`
    implies `iram;`, so a call out of the handler to an ordinary proc took the
    cross-section indirect path whose literal is patched ONLY by the ET_REL
    object writer -- and a bare image is ET_EXEC with no linker, so the literal
    stayed zero and the handler jumped to address 0. Everything else in this
    fixture passes with that bug present. }
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

procedure InstallVector;
var base, arrBase, slot, off, insn: Integer;
begin
  arrBase := Integer(@vecRaw[0]);
  base := (arrBase + 1023) and (not 1023);
  { ONE slot, written straight rather than in a loop. The entry stub sets
    PS = $2F (EXCM 0, UM 1), so a level-1 exception lands at the User vector
    and nowhere else; see the header for why planting the neighbours would
    weaken this rather than harden it. }
  slot := $340;                      { UserExceptionVector }
  off := (base - arrBase) + slot;
  { j target: imm18 = target - pc - 4, where pc is the stub's own address. }
  insn := ((Integer(@VecHandler) - (base + slot) - 4) shl 6) or $06;
  vecRaw[off]     := insn and $FF;
  vecRaw[off + 1] := (insn shr 8) and $FF;
  vecRaw[off + 2] := (insn shr 16) and $FF;
  { A guard that can fail: `j` reaches +/-128 KiB and the table is in BSS while
    the handler is in the code section. Small images are comfortably inside,
    but "comfortably" is not a range check, and past it the stub jumps to a
    truncated address and the image dies with no output at all. }
  jReach := Integer(@VecHandler) - (base + $340) - 4;
  if (jReach < -131072) or (jReach > 131071) then jReach := 0 else jReach := 1;
  asm
    la   a6, vecBaseSlot
    l32i a4, a6, 0
    wsr  a4, $e7              { VECBASE := the table we just built }
  end;
end;
{$endif}

begin
  isrHits := 0; isrSp := 0; taskSp := 0; excCause := 0;
  localsOk := 0; jReach := 0; callsOk := 0;

{$ifdef CPU_XTENSA}
  vecBaseSlot := (Integer(@vecRaw[0]) + 1023) and (not 1023);
  InstallVector;
  TakesTrapWithLocals;
{$else}
  { x86-64 oracle: no vectors, no traps. Prints what a correct bare run prints. }
  isrHits := 1; localsOk := 1; jReach := 1; callsOk := 1;
  isrSp := 2; taskSp := 1; excCause := 1;
{$endif}

  PutS('j in range '); PutInt(jReach); PutC(10);
  PutS('handler ran '); PutInt(isrHits); PutC(10);
  PutS('exccause '); PutInt(excCause); PutC(10);
  if callsOk = 1 then PutS('a call from the handler returned')
  else PutS('A CALL FROM THE HANDLER DID NOT RUN');
  PutC(10);
  if isrSp > taskSp then PutS('isr sp is ABOVE task sp')
  else PutS('ISR STACK NOT SWITCHED');
  PutC(10);
  if localsOk = 1 then PutS('locals survived the trap')
  else PutS('THE HANDLER CORRUPTED THE INTERRUPTED FRAME');
  PutC(10);
  if (jReach = 1) and (isrHits = 1) and (isrSp > taskSp) and (localsOk = 1)
     and (callsOk = 1)
    then PutS('VECTOR-OK') else PutS('VECTOR-FAIL');
  PutC(10);
end.
