{ SPDX-License-Identifier: MPL-2.0 }
{ rv32enc.inc — typed instruction encoders for RISC-V RV32IMC codegen }

const
  reg_zero = 0; reg_ra = 1; reg_sp = 2; reg_gp = 3; reg_tp = 4;
  reg_t0 = 5; reg_t1 = 6; reg_t2 = 7;
  reg_s0 = 8; reg_fp = 8; reg_s1 = 9;
  reg_a0 = 10; reg_a1 = 11; reg_a2 = 12; reg_a3 = 13; reg_a4 = 14; reg_a5 = 15; reg_a6 = 16; reg_a7 = 17;
  reg_s2 = 18; reg_s3 = 19; reg_s4 = 20; reg_s5 = 21; reg_s6 = 22; reg_s7 = 23; reg_s8 = 24; reg_s9 = 25; reg_s10 = 26; reg_s11 = 27;
  reg_t3 = 28; reg_t4 = 29; reg_t5 = 30; reg_t6 = 31;

procedure EmitRType(funct7, rs2, rs1, funct3, rd, opcode: Integer);
begin
  EmitI32((funct7 shl 25) or (rs2 shl 20) or (rs1 shl 15) or (funct3 shl 12) or (rd shl 7) or opcode);
end;

procedure EmitIType(imm, rs1, funct3, rd, opcode: Integer);
begin
  EmitI32(((imm and $FFF) shl 20) or (rs1 shl 15) or (funct3 shl 12) or (rd shl 7) or opcode);
end;

procedure EmitSType(imm, rs2, rs1, funct3, opcode: Integer);
begin
  EmitI32(((imm and $FE0) shl 20) or (rs2 shl 20) or (rs1 shl 15) or (funct3 shl 12) or ((imm and $1F) shl 7) or opcode);
end;

procedure EmitBType(imm, rs2, rs1, funct3, opcode: Integer);
var
  i12, i11, i10_5, i4_1: Integer;
begin
  i12   := (imm shr 12) and 1;
  i11   := (imm shr 11) and 1;
  i10_5 := (imm shr 5) and $3F;
  i4_1  := (imm shr 1) and $F;
  EmitI32((i12 shl 31) or (i10_5 shl 25) or (rs2 shl 20) or (rs1 shl 15) or (funct3 shl 12) or (i4_1 shl 8) or (i11 shl 7) or opcode);
end;

procedure EmitUType(imm, rd, opcode: Integer);
begin
  EmitI32((imm and $FFFFF000) or (rd shl 7) or opcode);
end;

procedure EmitJType(imm, rd, opcode: Integer);
var
  i20, i19_12, i11, i10_1: Integer;
begin
  i20    := (imm shr 20) and 1;
  i19_12 := (imm shr 12) and $FF;
  i11    := (imm shr 11) and 1;
  i10_1  := (imm shr 1) and $3FF;
  EmitI32((i20 shl 31) or (i10_1 shl 21) or (i11 shl 20) or (i19_12 shl 12) or (rd shl 7) or opcode);
end;

function EncodeRISCVJAL(rd: Integer; offset: Integer): Integer;
var
  i20, i19_12, i11, i10_1: Integer;
begin
  i20    := (offset shr 20) and 1;
  i19_12 := (offset shr 12) and $FF;
  i11    := (offset shr 11) and 1;
  i10_1  := (offset shr 1) and $3FF;
  Result := (i20 shl 31) or (i10_1 shl 21) or (i11 shl 20) or (i19_12 shl 12) or (rd shl 7) or $6F;
end;

function EncodeRISCVAddi(rd, rs1, imm: Integer): Integer;
begin
  Result := (((imm and $FFF) shl 20) or (rs1 shl 15) or (rd shl 7) or $13);
end;

procedure rv32_add(rd, rs1, rs2: Integer);  begin EmitRType(0, rs2, rs1, 0, rd, $33); end;
procedure rv32_sub(rd, rs1, rs2: Integer);  begin EmitRType($20, rs2, rs1, 0, rd, $33); end;
procedure rv32_addi(rd, rs1, imm: Integer); begin EmitIType(imm, rs1, 0, rd, $13); end;
procedure rv32_lui(rd, imm: Integer);       begin EmitUType(imm, rd, $37); end;
procedure rv32_auipc(rd, imm20: Integer);   begin EmitUType(imm20, rd, $17); end;
procedure rv32_lb(rd, rs1, imm: Integer);   begin EmitIType(imm, rs1, 0, rd, $03); end;
procedure rv32_lh(rd, rs1, imm: Integer);   begin EmitIType(imm, rs1, 1, rd, $03); end;
procedure rv32_lbu(rd, rs1, imm: Integer);  begin EmitIType(imm, rs1, 4, rd, $03); end;
procedure rv32_lhu(rd, rs1, imm: Integer);  begin EmitIType(imm, rs1, 5, rd, $03); end;
procedure rv32_lw(rd, rs1, imm: Integer);   begin EmitIType(imm, rs1, 2, rd, $03); end;
procedure rv32_sb(rs2, rs1, imm: Integer);  begin EmitSType(imm, rs2, rs1, 0, $23); end;
procedure rv32_sh(rs2, rs1, imm: Integer);  begin EmitSType(imm, rs2, rs1, 1, $23); end;
procedure rv32_sw(rs2, rs1, imm: Integer);  begin EmitSType(imm, rs2, rs1, 2, $23); end;
procedure rv32_xori(rd, rs1, imm: Integer); begin EmitIType(imm, rs1, 4, rd, $13); end;
procedure rv32_ori(rd, rs1, imm: Integer);  begin EmitIType(imm, rs1, 6, rd, $13); end;
procedure rv32_andi(rd, rs1, imm: Integer); begin EmitIType(imm, rs1, 7, rd, $13); end;
procedure rv32_jal(rd, offset: Integer);    begin EmitJType(offset, rd, $6F); end;
procedure rv32_jalr(rd, rs1, imm: Integer); begin EmitIType(imm, rs1, 0, rd, $67); end;
procedure rv32_mul(rd, rs1, rs2: Integer);  begin EmitRType(1, rs2, rs1, 0, rd, $33); end;
procedure rv32_mulhu(rd, rs1, rs2: Integer);begin EmitRType(1, rs2, rs1, 3, rd, $33); end;
procedure rv32_div(rd, rs1, rs2: Integer);  begin EmitRType(1, rs2, rs1, 4, rd, $33); end;
procedure rv32_divu(rd, rs1, rs2: Integer); begin EmitRType(1, rs2, rs1, 5, rd, $33); end;
procedure rv32_rem(rd, rs1, rs2: Integer);  begin EmitRType(1, rs2, rs1, 6, rd, $33); end;
procedure rv32_remu(rd, rs1, rs2: Integer); begin EmitRType(1, rs2, rs1, 7, rd, $33); end;
procedure rv32_and(rd, rs1, rs2: Integer);  begin EmitRType(0, rs2, rs1, 7, rd, $33); end;
procedure rv32_or(rd, rs1, rs2: Integer);   begin EmitRType(0, rs2, rs1, 6, rd, $33); end;
procedure rv32_xor(rd, rs1, rs2: Integer);  begin EmitRType(0, rs2, rs1, 4, rd, $33); end;
procedure rv32_sll(rd, rs1, rs2: Integer);  begin EmitRType(0, rs2, rs1, 1, rd, $33); end;
procedure rv32_srl(rd, rs1, rs2: Integer);  begin EmitRType(0, rs2, rs1, 5, rd, $33); end;
procedure rv32_sra(rd, rs1, rs2: Integer);  begin EmitRType($20, rs2, rs1, 5, rd, $33); end;
procedure rv32_slt(rd, rs1, rs2: Integer);  begin EmitRType(0, rs2, rs1, 2, rd, $33); end;
procedure rv32_sltu(rd, rs1, rs2: Integer); begin EmitRType(0, rs2, rs1, 3, rd, $33); end;
procedure rv32_slti(rd, rs1, imm: Integer); begin EmitIType(imm, rs1, 2, rd, $13); end;
procedure rv32_sltiu(rd, rs1, imm: Integer);begin EmitIType(imm, rs1, 3, rd, $13); end;
procedure rv32_slli(rd, rs1, sh: Integer);  begin EmitIType(sh and $1F, rs1, 1, rd, $13); end;
procedure rv32_srli(rd, rs1, sh: Integer);  begin EmitIType(sh and $1F, rs1, 5, rd, $13); end;
procedure rv32_srai(rd, rs1, sh: Integer);  begin EmitIType((sh and $1F) or $400, rs1, 5, rd, $13); end;

function EncodeRISCVBEQ(rs1, rs2, offset: Integer): Integer;
var i12, i11, i10_5, i4_1: Integer;
begin
  i12   := (offset shr 12) and 1;
  i11   := (offset shr 11) and 1;
  i10_5 := (offset shr 5) and $3F;
  i4_1  := (offset shr 1) and $F;
  Result := (i12 shl 31) or (i10_5 shl 25) or (rs2 shl 20) or (rs1 shl 15) or (0 shl 12) or (i4_1 shl 8) or (i11 shl 7) or $63;
end;

procedure rv32_beq(rs1, rs2, offset: Integer);
begin
  EmitI32(EncodeRISCVBEQ(rs1, rs2, offset));
end;

procedure rv32_nop;
begin
  EmitI32($00000013);
end;

procedure rv32_mret;   { return from machine-mode trap (restores PC from mepc) }
begin
  EmitI32($30200073);
end;




