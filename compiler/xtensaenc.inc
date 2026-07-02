{ xtensaenc.inc — typed instruction encoders for Xtensa LX6/LX7 codegen }

const
  reg_xtensa_a0 = 0; reg_xtensa_a1 = 1; reg_xtensa_sp = 1;
  reg_xtensa_a2 = 2; reg_xtensa_a3 = 3; reg_xtensa_a4 = 4; reg_xtensa_a5 = 5; reg_xtensa_a6 = 6; reg_xtensa_a7 = 7;
  reg_xtensa_a8 = 8; reg_xtensa_a9 = 9; reg_xtensa_a10 = 10; reg_xtensa_a11 = 11; reg_xtensa_a12 = 12; reg_xtensa_a13 = 13; reg_xtensa_a14 = 14; reg_xtensa_a15 = 15;

function EncodeXtensaJ(offset: Integer): Integer;
var
  imm: Integer;
begin
  { J: target = PC + 4 + imm18; imm18 sits at insn bits [23:6]
    (op0=6 in bits [3:0], n=0 in bits [5:4]). }
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

procedure xtensa_s32i(t, s, offset: Integer);
begin
  EmitB((t shl 4) or 2);
  EmitB((6 shl 4) or s);
  EmitB((offset div 4) and $FF);
end;

procedure xtensa_l32i(t, s, offset: Integer);
begin
  EmitB((t shl 4) or 2);
  EmitB((2 shl 4) or s);
  EmitB((offset div 4) and $FF);
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
  EmitB((ar shl 4) or 0);
  EmitB($E0);
  EmitB($13);
end;

procedure xtensa_rsync;                          { rsync }
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

function EncodeXtensaCall0(pc, target: Integer): Integer;
var
  imm18: Integer;
begin
  { CALL0: target = align4(PC) + 4 + imm18*4, so the target must be
    4-aligned (proc entries are padded to 4 on this target).
    NB: PXX `not` is not a bitwise int op — use div/mul to mask. }
  imm18 := ((target - (pc div 4) * 4 - 4) div 4) and $3FFFF;
  Result := (imm18 shl 6) or 5;
end;

function EncodeXtensaCall8(pc, target: Integer): Integer;
var
  imm18: Integer;
begin
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
