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

procedure xtensa_ret;
begin
  { RET = insn word $000080 (op0=0, t=8: SNM0/JR group), LE bytes 80 00 00. }
  EmitB($80);
  EmitB(0);
  EmitB(0);
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
