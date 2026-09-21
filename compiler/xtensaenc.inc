{ SPDX-License-Identifier: MPL-2.0 }
{ xtensaenc.inc — typed instruction encoders for Xtensa LX6/LX7 codegen }

const
  reg_xtensa_a0 = 0; reg_xtensa_a1 = 1; reg_xtensa_sp = 1;
  reg_xtensa_a2 = 2; reg_xtensa_a3 = 3; reg_xtensa_a4 = 4; reg_xtensa_a5 = 5; reg_xtensa_a6 = 6; reg_xtensa_a7 = 7;
  reg_xtensa_a8 = 8; reg_xtensa_a9 = 9; reg_xtensa_a10 = 10; reg_xtensa_a11 = 11; reg_xtensa_a12 = 12; reg_xtensa_a13 = 13; reg_xtensa_a14 = 14; reg_xtensa_a15 = 15;

  { Special registers this compiler names. Only the ones it emits itself are
    here; the inline assembler takes any 8-bit number, which is the capability
    -- a name table must never be the only way to reach an SR, and on this
    target it could not be one anyway (an identifier in an asm operand is
    symbol-resolved by asmenc.inc before the xtensa assembler sees the line,
    so `wsr vecbase, a4` fails upstream with "unknown symbol: vecbase"). }
  SR_SCOMPARE1 = 12;    { the S32C1I comparand }
  SR_ATOMCTL   = 99;    { what S32C1I does per memory class }
  SR_EXCSAVE_1 = $D1;   { 209 — level-1 scratch; $D1..$D7 is the whole file }
  SR_VECBASE   = $E7;   { 231 — base of the VECTOR TABLE, not of a handler }
  SR_PS        = $E6;   { processor state: INTLEVEL[3:0] EXCM[4] UM[5] RING[7:6] WOE[18] }
  SR_CPENABLE  = $E0;   { 224 }
  SR_PRID      = $EB;   { 235 }

procedure XtensaRelCheck(v, lo, hi: Integer; const what: AnsiString);
{ THE range check every PC-relative xtensa field was missing. Each encoder below
  ends in `and $3FFFF` / `and $FF`, and a mask is not a check: an offset past the
  field silently wraps and the instruction targets a DIFFERENT, perfectly valid
  address. There is no fault at encode time and no fault at link time -- the
  program simply jumps somewhere else.

  Measured 2026-08-27, and it is the reason this exists. An ESP-IDF esp32s3
  image whose main body sat 262591 bytes past the entry stub encoded its entry
  `j` as 262581 mod 262144 = 437, i.e. 0x4204ca4b became 0x4200ca4b -- one bit
  of 2^18 dropped, landing MID-INSTRUCTION inside sShiftRightSticky. The chip
  decoded three bytes of a `sub`, then hit an illegal opcode:

    Guru Meditation Error: Core 0 panic'ed (IllegalInstruction)
    PC: 0x4200ca51

  A wrong PC three functions away from the cause, which is exactly the failure
  shape devdocs/dev/debugging-playbook.md opens with. The offset was not close
  to the boundary and no diagnostic mentioned a range, so nothing pointed at the
  encoder; it took a disassembly and the arithmetic 262591-262144=437 to name it.

  Masking is still correct for NEGATIVE offsets (two's complement is what the
  field wants), so this checks the SIGNED range rather than "did the mask change
  the value" -- the latter would reject every backward branch.
  bug-a-xtensa-pc-relative-encoders-silently-truncate-an-out-of-range-offset }
begin
  if (v < lo) or (v > hi) then
    Error('target xtensa: ' + what + ' displacement ' + AIntToStr(v) +
          ' is outside the encodable range ' + AIntToStr(lo) + '..' +
          AIntToStr(hi) + '; the code is too large for this branch form');
end;

function EncodeXtensaJ(offset: Integer): Integer;
var
  imm: Integer;
begin
  { J: target = PC + 4 + imm18; imm18 sits at insn bits [23:6]
    (op0=6 in bits [3:0], n=0 in bits [5:4]). }
  XtensaRelCheck(offset - 4, -131072, 131071, 'j');
  imm := (offset - 4) and $3FFFF;
  Result := (imm shl 6) or 6;
end;

procedure xtensa_j(offset: Integer);
var
  val: Integer;
begin
  val := EncodeXtensaJ(offset);
  EmitB(val and $FF);
  EmitB((val shr 8) and $FF);
  EmitB((val shr 16) and $FF);
end;

function EncodeXtensaAddi(t, s, imm: Integer): Integer;
begin
  { NOT a PC-relative field, and it had the same wrap: `imm and $FF` turned
    `addi a3, sp, 252` into `addi a3, sp, -4`, a valid instruction aimed at the
    wrong slot. Windowed spill-slot addresses reach it past a depth of ~130. }
  XtensaRelCheck(imm, -128, 127, 'addi immediate');
  Result := ((imm and $FF) shl 16) or ((($C shl 4) or s) shl 8) or ((t shl 4) or 2);
end;

function EncodeXtensaAddmi(t, s, imm: Integer): Integer;
{ ADDMI t, s, imm — imm must be a multiple of 256 (encoded as imm8<<8), giving a
  -32768..32512 range. Same RRI8 frame as ADDI but op1 = D. Lets a single
  instruction reserve a frame larger than ADDI's +-128. }
begin
  Result := (((imm div 256) and $FF) shl 16) or ((($D shl 4) or s) shl 8) or ((t shl 4) or 2);
end;

procedure xtensa_addi(t, s, imm: Integer);
var
  val: Integer;
begin
  val := EncodeXtensaAddi(t, s, imm);
  EmitB(val and $FF);
  EmitB((val shr 8) and $FF);
  EmitB((val shr 16) and $FF);
end;

procedure XtensaCheckWordOffset(offset: Integer; const what: AnsiString);
{ l32i/s32i encode offset/4 in eight bits: 0..1020, word-aligned. The mask
  below wrapped anything else to a different valid slot. }
begin
  XtensaRelCheck(offset, 0, 1020, what + ' offset');
  if (offset and 3) <> 0 then
    Error('target xtensa: ' + what + ' offset ' + AIntToStr(offset)
          + ' is not word-aligned');
end;

procedure xtensa_s32i(t, s, offset: Integer);
begin
  XtensaCheckWordOffset(offset, 's32i');
  EmitB((t shl 4) or 2);
  EmitB((6 shl 4) or s);
  EmitB((offset div 4) and $FF);
end;

procedure xtensa_l32i(t, s, offset: Integer);
begin
  XtensaCheckWordOffset(offset, 'l32i');
  EmitB((t shl 4) or 2);
  EmitB((2 shl 4) or s);
  EmitB((offset div 4) and $FF);
end;

{ ---- the atomic primitive: S32C1I + its SCOMPARE1 companion --------------

  `s32c1i at, as, off` is Xtensa's compare-and-swap:

      tmp := MEM[as+off];
      if tmp = SCOMPARE1 then MEM[as+off] := at;
      at  := tmp                       { the ORIGINAL memory word }

  Present on every LX6/LX7 core Espressif ships, single- and dual-core alike,
  so it needs no chip gate. Same RRI8 shape as s32i with r = 14 instead of 6.

  Byte patterns verified against xtensa-esp32s3-elf-as, not derived from the
  manual: `s32c1i a4, a2, 0` = 00 E2 42, `wsr.scompare1 a3` = 13 0C 30,
  `rsr.scompare1 a3` = 03 0C 30.
  bug-a-riscv32-and-xtensa-have-no-atomic-codegen }
procedure xtensa_s32c1i(t, s, offset: Integer);
begin
  EmitB((t shl 4) or 2);
  EmitB((14 shl 4) or s);
  EmitB((offset div 4) and $FF);
end;

{ The general special-register forms, added 2026-09-21 for the raw-ISR work
  (feature-s-the-xtensa-raw-isr-install-has-no-vecbase-write-and-no-isr-stack).
  Until these existed every SR this compiler could touch had its number frozen
  into a hand-written helper, so VECBASE ($E7) and the EXCSAVE_n scratch file
  ($D1..$D7) were unreachable from any source spelling.

  The layout is uniform across every RSR/WSR in the ISA and all four helpers
  below now DERIVE from it rather than restating it -- the same reason the
  riscv32 side stopped spelling $300 into two instruction words:

      byte0 = at shl 4      the AR register
      byte1 = sr            the special register number, 8 bits
      byte2 = $13 WSR / $03 RSR

  Byte patterns verified against xtensa-esp32s3-elf-as via the four call sites
  that already had them: wsr.scompare1 a3 (SR 12), wsr.atomctl a3 (SR 99),
  wsr.cpenable (SR 224), rsr.prid (SR 235). }
procedure xtensa_wsr(sr, at: Integer);
begin
  EmitB((at and $F) shl 4);
  EmitB(sr and $FF);
  EmitB($13);
end;

procedure xtensa_rsr(sr, at: Integer);
begin
  EmitB((at and $F) shl 4);
  EmitB(sr and $FF);
  EmitB($03);
end;

procedure xtensa_wsr_scompare1(t: Integer);
begin
  xtensa_wsr(SR_SCOMPARE1, t);
end;

procedure xtensa_rsr_scompare1(t: Integer);
begin
  xtensa_rsr(SR_SCOMPARE1, t);
end;

{ ATOMCTL (special register 99) selects what S32C1I DOES per memory class:
  bits [1:0] write-back cacheable, [3:2] write-through, [5:4] bypass; each
  0 = raise an exception, 1 = RCW bus transaction, 2 = internal operation.
  Reset value 0 therefore makes every S32C1I trap, which is exactly what an
  esp32s3 image that sets up its own world sees.
  Bytes verified against xtensa-esp32s3-elf-as: `wsr.atomctl a3` = 30 63 13. }
procedure xtensa_wsr_atomctl(t: Integer);
begin
  xtensa_wsr(SR_ATOMCTL, t);
end;

procedure xtensa_memw;
{ full memory barrier — `memw` = C0 20 00 }
begin
  EmitB($C0); EmitB($20); EmitB($00);
end;

procedure xtensa_syscall;
{ `syscall` = 00 50 00. RRR with op0=0 (QRST), op1=0 (RST0), op2=0 (ST0) and
  r=5, s=0, t=0, laid out little-endian as byte0=(t shl 4) or op0,
  byte1=(r shl 4) or s, byte2=(op2 shl 4) or op1.

  Raises the Syscall exception (EXCCAUSE 1). Under qemu-xtensa user mode it is
  the Linux syscall trap.
  feature-a-hosted-xtensa-so-qemu-xtensa-can-be-an-oracle

  THE SENTENCE THAT USED TO BE HERE -- "on a bare or IDF part that is a fault
  with no handler, which is why the ESP profile does not emit this" -- was true
  until 2026-09-22 and is not now. A bare image can install a raw vector table
  and an `interrupt;` handler, so this is reachable from ESP inline asm on
  purpose and is how test/test_esp_bare_vector.pas takes its trap.

  THE HARDWARE DOES NOT ADVANCE THE PC, exactly as RISC-V's ecall does not:
  EPC1 addresses the SYSCALL itself, so a handler that returns via RFE without
  stepping EPC1 past it re-executes it and traps forever. SYSCALL is three
  bytes, so the step is +3 -- NOT the +4 its riscv32 analogue uses. }
begin
  EmitB($00); EmitB($50); EmitB($00);
end;

procedure xtensa_l8ui(t, s, offset: Integer);
begin
  EmitB((t shl 4) or 2);
  EmitB((0 shl 4) or s);
  EmitB(offset and $FF);
end;

procedure xtensa_l16ui(t, s, offset: Integer);
begin
  EmitB((t shl 4) or 2);
  EmitB((1 shl 4) or s);
  EmitB((offset div 2) and $FF);
end;

procedure xtensa_l16si(t, s, offset: Integer);
begin
  EmitB((t shl 4) or 2);
  EmitB((9 shl 4) or s);
  EmitB((offset div 2) and $FF);
end;

procedure xtensa_s8i(t, s, offset: Integer);
begin
  EmitB((t shl 4) or 2);
  EmitB((4 shl 4) or s);
  EmitB(offset and $FF);
end;

procedure xtensa_s16i(t, s, offset: Integer);
begin
  EmitB((t shl 4) or 2);
  EmitB((5 shl 4) or s);
  EmitB((offset div 2) and $FF);
end;

procedure xtensa_l32r(t, imm16: Integer);
begin
  EmitB((t shl 4) or 1);
  EmitB(imm16 and $FF);
  EmitB((imm16 shr 8) and $FF);
end;

procedure xtensa_or(r, s, t: Integer);
begin
  EmitB((t shl 4) or 0);
  EmitB((r shl 4) or s);
  EmitB((2 shl 4) or 0);
end;

procedure xtensa_add(r, s, t: Integer);
begin
  EmitB((t shl 4) or 0);
  EmitB((r shl 4) or s);
  EmitB((8 shl 4) or 0);
end;

procedure xtensa_sub(r, s, t: Integer);
begin
  EmitB((t shl 4) or 0);
  EmitB((r shl 4) or s);
  EmitB((12 shl 4) or 0);
end;

procedure xtensa_movsp(t, s: Integer);
{ MOVSP at, as — the ONLY legal way to move a1 under the windowed ABI, besides
  ENTRY's own immediate.

  Why an instruction exists just for this: the caller's 16-byte register save
  area lives at [a1-16], and window OVERFLOW and UNDERFLOW read it there. A
  plain `sub a1, a1, aN` relocates sp and leaves that area behind, so the
  handlers read whatever now occupies the address. MOVSP carries the area with
  the pointer (raising an ALLOCA exception for the runtime to do the copy when
  the caller's registers are still live in the register file).

  RRR format, and the field layout is the same one every encoder in this file
  uses: byte0 = t<<4 | op0, byte1 = r<<4 | s, byte2 = op2<<4 | op1. MOVSP is
  op0=0, op1=0, op2=0, r=1 — so byte2 is 0 and byte1 carries the r=1 that
  distinguishes it from the other op2=0 forms.

  VERIFIED BY DISASSEMBLY, not derived: qemu-xtensa -d in_asm decodes the bytes
  this emits as `movsp a1, a8` in a real windowed prologue. An encoding argued
  from a manual and never decoded is how this file got
  XtensaRelCheck (see its header) — a field that silently produced a valid
  instruction pointing somewhere else. }
begin
  EmitB((t shl 4) or 0);
  EmitB(($1 shl 4) or s);
  EmitB(0);
end;

procedure xtensa_and(r, s, t: Integer);
begin
  EmitB((t shl 4) or 0);
  EmitB((r shl 4) or s);
  EmitB((1 shl 4) or 0);
end;

procedure xtensa_xor(r, s, t: Integer);
begin
  EmitB((t shl 4) or 0);
  EmitB((r shl 4) or s);
  EmitB((3 shl 4) or 0);
end;

{ ===== Single-precision FPU (FP coprocessor option; ESP32/-S3 have it, -S2 does
  NOT — emit only under --xtensa-fpu). RRR: byte0=(t<<4)|op0, byte1=(r<<4)|s,
  byte2=(op2<<4)|op1. Verified against xtensa-esp32s3-elf-as. ===== }
procedure xtensa_add_s(fr, fs, ft: Integer);   { add.s fr, fs, ft }
begin
  EmitB((ft shl 4) or 0);
  EmitB((fr shl 4) or fs);
  EmitB((0 shl 4) or $A);
end;

procedure xtensa_sub_s(fr, fs, ft: Integer);   { sub.s fr, fs, ft }
begin
  EmitB((ft shl 4) or 0);
  EmitB((fr shl 4) or fs);
  EmitB((1 shl 4) or $A);
end;

procedure xtensa_mul_s(fr, fs, ft: Integer);   { mul.s fr, fs, ft }
begin
  EmitB((ft shl 4) or 0);
  EmitB((fr shl 4) or fs);
  EmitB((2 shl 4) or $A);
end;

procedure xtensa_wfr(fr, ar: Integer);         { wfr fr, ar  (ar bits -> FP reg) }
begin
  EmitB((5 shl 4) or 0);
  EmitB((fr shl 4) or ar);
  EmitB(($F shl 4) or $A);
end;

procedure xtensa_rfr(ar, fr: Integer);         { rfr ar, fr  (FP reg -> ar bits) }
begin
  EmitB((4 shl 4) or 0);
  EmitB((ar shl 4) or fr);
  EmitB(($F shl 4) or $A);
end;

procedure xtensa_wsr_cpenable(ar: Integer);    { wsr.cpenable ar  (SR 224) }
begin
  xtensa_wsr(SR_CPENABLE, ar);
end;

procedure xtensa_rsr_prid(ar: Integer);        { rsr.prid ar  (SR 235) }
begin
  xtensa_rsr(SR_PRID, ar);
end;

procedure xtensa_rsync;                          { rsync }
{ Wait for a WSR to a state register to take effect before any dependent
  instruction issues. Insn word $002010.

  REQUIRED AFTER `wsr ps`, AND ITS ABSENCE IS NOT VISIBLE UNDER qemu -- which
  is the reason to emit it rather than to measure whether it is needed. qemu
  retires the WSR before the next instruction whatever you do, so a missing
  RSYNC costs nothing there and is a real race on silicon. }
begin
  EmitB($10); EmitB($20); EmitB($00);
end;

procedure xtensa_mov(dst, src: Integer);
begin
  xtensa_or(dst, src, src);
end;

procedure xtensa_movi(t, imm12: Integer);
{ MOVI at, imm12 — RRI8 with r=$A; imm12 signed -2048..2047. }
begin
  EmitB((t shl 4) or 2);
  EmitB(($A shl 4) or ((imm12 shr 8) and $F));
  EmitB(imm12 and $FF);
end;

procedure xtensa_mull(r, s, t: Integer);
{ MULL r, s, t — requires the 32-bit integer multiply option (present on
  ESP32 LX6/LX7). op2=8, op1=2. }
begin
  EmitB((t shl 4) or 0);
  EmitB((r shl 4) or s);
  EmitB((8 shl 4) or 2);
end;

procedure xtensa_muluh(r, s, t: Integer);
{ MULUH r, s, t -> r = high 32 of (s * t) unsigned. 32-bit integer multiply
  option (present on ESP32 LX6/LX7). Same RRR layout as MULL; op2=$A, op1=2
  (byte2 = $A2). Verified vs xtensa-esp32s3-elf-as. }
begin
  EmitB((t shl 4) or 0);
  EmitB((r shl 4) or s);
  EmitB(($A shl 4) or 2);
end;

procedure xtensa_quos(r, s, t: Integer);
{ QUOS r, s, t  ->  r = s div t (signed). Requires the 32-bit integer divide
  option, present on ESP32-S2/S3 (LX7) and later, NOT on ESP32 classic (LX6).
  Same RRR layout as MULL; only op2/op1 (byte2 = $D2) differs. Encodings
  taken from xtensa-esp32s3-elf-as (llvm-mc 18 lacks the divide mnemonics). }
begin
  EmitB((t shl 4) or 0);
  EmitB((r shl 4) or s);
  EmitB($D2);
end;

procedure xtensa_quou(r, s, t: Integer);
{ QUOU r, s, t  ->  r = s div t (unsigned). byte2 = $C2. }
begin
  EmitB((t shl 4) or 0);
  EmitB((r shl 4) or s);
  EmitB($C2);
end;

procedure xtensa_rems(r, s, t: Integer);
{ REMS r, s, t  ->  r = s mod t (signed). byte2 = $F2. }
begin
  EmitB((t shl 4) or 0);
  EmitB((r shl 4) or s);
  EmitB($F2);
end;

procedure xtensa_remu(r, s, t: Integer);
{ REMU r, s, t  ->  r = s mod t (unsigned). byte2 = $E2. }
begin
  EmitB((t shl 4) or 0);
  EmitB((r shl 4) or s);
  EmitB($E2);
end;

procedure xtensa_ssl(s: Integer);
{ SSL s -> SAR := 32 - (s & 31), so a following SLL left-shifts by (s & 31). }
begin
  EmitB(0);
  EmitB((1 shl 4) or s);
  EmitB($40);
end;

procedure xtensa_sll(r, s: Integer);
{ SLL r, s -> r := s << (32 - SAR) (value in the s field). op2=A, op1=1. }
begin
  EmitB(0);
  EmitB((r shl 4) or s);
  EmitB($A1);
end;

procedure xtensa_ssr(s: Integer);
{ SSR s -> SAR := s & 31, so a following SRL right-shifts by (s & 31). }
begin
  EmitB(0);
  EmitB(s);
  EmitB($40);
end;

procedure xtensa_srl(r, t: Integer);
{ SRL r, t -> r := t >> SAR (logical; value in the t field, not s). op2=9, op1=1. }
begin
  EmitB((t shl 4) or 0);
  EmitB((r shl 4) or 0);
  EmitB($91);
end;

procedure xtensa_sra(r, t: Integer);
{ SRA r, t -> r := t >>> SAR (arithmetic; value in the t field, not s). Same
  shape as SRL but op2=0xB instead of 9 -- verified byte-for-byte against a
  real xtensa-lx106-elf-as assembly of `sra a2, a3` (bug-c-signed-arith-
  shift-right, the C signed `>>` case; Pascal has no arithmetic-shift
  operator so this is C-only). }
begin
  EmitB((t shl 4) or 0);
  EmitB((r shl 4) or 0);
  EmitB($B1);
end;

procedure xtensa_ret;
begin
  { RET = insn word $000080 (op0=0, t=8: SNM0/JR group), LE bytes 80 00 00. }
  EmitB($80);
  EmitB(0);
  EmitB(0);
end;

procedure xtensa_rfe;
begin
  { RFE = return-from-exception (general level-1): PS.EXCM cleared, PC <- EPC1.
    Insn word $003000, LE bytes 00 30 00. Verified vs xtensa-esp32s3-elf-as
    (llvm-mc 18 lacks the Xtensa exception mnemonics). }
  EmitB($00);
  EmitB($30);
  EmitB($00);
end;

function EncodeXtensaEntry(s, frameSize: Integer): Integer;
var
  imm12: Integer;
begin
  imm12 := (frameSize div 8) and $FFF;
  Result := $36 or ((((imm12 and $F) shl 4) or s) shl 8) or
            ((imm12 shr 4) shl 16);
end;

procedure xtensa_entry(s, frameSize: Integer);
var
  val: Integer;
begin
  val := EncodeXtensaEntry(s, frameSize);
  EmitB(val and $FF);
  EmitB((val shr 8) and $FF);
  EmitB((val shr 16) and $FF);
end;

procedure xtensa_retw;
begin
  { RETW.N = density return from windowed callee, LE bytes 1D F0. }
  EmitB($1D);
  EmitB($F0);
end;

procedure xtensa_nop;
begin
  EmitB($F0);
  EmitB($20);
  EmitB($00);
end;

procedure xtensa_jx(s: Integer);
{ Register-indirect jump: PC := a[s]. The one xtensa branch with UNLIMITED
  reach, which is why it exists here at all -- J is imm18 (+-128 KiB) and
  CALL0/CALL8 imm18 words (+-512 KiB), so a large image cannot be entered
  without it (bug-a-xtensa-entry-jump-cannot-reach-a-main-body-past-128kb).

  Bytes verified against xtensa-esp-elf-as, as everything else in this file is
  -- but verified against `objdump -s` (RAW MEMORY BYTES), not against the hex
  column of `objdump -d`. That column is NOT a byte dump and reading it as one
  emitted this instruction BACKWARDS on the first attempt: 00 08 A0 is a
  perfectly valid RRR encoding with op2=$A, i.e. `addx4 a0, a8, a0`, which
  computes a garbage address and FALLS THROUGH. Control then ran into the next
  routine's `entry`, the window rotated by 8, and the callee received a0 and a2
  from the stub's leftover a8 and a10 -- a StoreProhibited deep inside a runtime
  helper with no hint that a jump was involved. objdump printed `addx4` at that
  address and it was misread as a disassembler desync.

    jx a8  = A0 08 00        jx a10 = A0 0A 00
    (RRR: op0=0, t=$A -> m=2,n=2 = JX; s = the register; op1=op2=0)

  Same shape as xtensa_add's A0 88 80 right above -- t in byte 0, s in byte 1. }
begin
  EmitB($A0);
  EmitB(s);
  EmitB($00);
end;

function EncodeXtensaCall0(pc, target: Integer): Integer;
var
  imm18: Integer;
begin
  { CALL0: target = align4(PC) + 4 + imm18*4, so the target must be
    4-aligned (proc entries are padded to 4 on this target).
    NB: PXX `not` is not a bitwise int op — use div/mul to mask. }
  if (target mod 4) <> 0 then
    Error('target xtensa: call0 target ' + AIntToStr(target) +
          ' is not 4-aligned; CALL0/CALL8 encode a WORD offset and a stray ' +
          'byte is silently truncated away by the div below');
  XtensaRelCheck((target - (pc div 4) * 4 - 4) div 4, -131072, 131071, 'call0');
  imm18 := ((target - (pc div 4) * 4 - 4) div 4) and $3FFFF;
  Result := (imm18 shl 6) or 5;
end;

function EncodeXtensaCall8(pc, target: Integer): Integer;
var
  imm18: Integer;
begin
  if (target mod 4) <> 0 then
    Error('target xtensa: call8 target ' + AIntToStr(target) +
          ' is not 4-aligned; CALL0/CALL8 encode a WORD offset and a stray ' +
          'byte is silently truncated away by the div below');
  XtensaRelCheck((target - (pc div 4) * 4 - 4) div 4, -131072, 131071, 'call8');
  imm18 := ((target - (pc div 4) * 4 - 4) div 4) and $3FFFF;
  Result := (imm18 shl 6) or $25;
end;

procedure xtensa_call0(offset: Integer);
var
  val: Integer;
begin
  val := EncodeXtensaCall0(CodeLen, CodeLen + offset);
  EmitB(val and $FF);
  EmitB((val shr 8) and $FF);
  EmitB((val shr 16) and $FF);
end;

procedure xtensa_call8(offset: Integer);
var
  val: Integer;
begin
  val := EncodeXtensaCall8(CodeLen, CodeLen + offset);
  EmitB(val and $FF);
  EmitB((val shr 8) and $FF);
  EmitB((val shr 16) and $FF);
end;

procedure xtensa_callx0(s: Integer);
begin
  { CALLX0 as = insn word $0000C0 or (s shl 8), LE bytes C0 0s 00. }
  EmitB($C0);
  EmitB(s);
  EmitB(0);
end;

procedure xtensa_callx8(s: Integer);
begin
  { CALLX8 as = insn word $0000E0 or (s shl 8), LE bytes E0 0s 00. }
  EmitB($E0);
  EmitB(s);
  EmitB(0);
end;

function EncodeXtensaBranch(r, s, t, offset: Integer): Integer;
var
  imm8: Integer;
begin
  XtensaRelCheck(offset - 4, -128, 127, 'conditional branch');
  imm8 := (offset - 4) and $FF;
  Result := (imm8 shl 16) or (r shl 12) or (s shl 8) or (t shl 4) or 7;
end;

procedure xtensa_beq(s, t, offset: Integer);
var val: Integer;
begin
  val := EncodeXtensaBranch(1, s, t, offset);
  EmitB(val and $FF);
  EmitB((val shr 8) and $FF);
  EmitB((val shr 16) and $FF);
end;

procedure xtensa_bne(s, t, offset: Integer);
var val: Integer;
begin
  val := EncodeXtensaBranch(9, s, t, offset);
  EmitB(val and $FF);
  EmitB((val shr 8) and $FF);
  EmitB((val shr 16) and $FF);
end;

procedure xtensa_blt(s, t, offset: Integer);
var val: Integer;
begin
  val := EncodeXtensaBranch(2, s, t, offset);
  EmitB(val and $FF);
  EmitB((val shr 8) and $FF);
  EmitB((val shr 16) and $FF);
end;

procedure xtensa_bge(s, t, offset: Integer);
var val: Integer;
begin
  val := EncodeXtensaBranch(10, s, t, offset);
  EmitB(val and $FF);
  EmitB((val shr 8) and $FF);
  EmitB((val shr 16) and $FF);
end;
