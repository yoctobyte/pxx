{ SPDX-License-Identifier: MPL-2.0 }
{ rv32enc.inc — typed instruction encoders for RISC-V RV32IMC codegen }

const
  reg_zero = 0; reg_ra = 1; reg_sp = 2; reg_gp = 3; reg_tp = 4;
  reg_t0 = 5; reg_t1 = 6; reg_t2 = 7;
  reg_s0 = 8; reg_fp = 8; reg_s1 = 9;
  reg_a0 = 10; reg_a1 = 11; reg_a2 = 12; reg_a3 = 13; reg_a4 = 14; reg_a5 = 15; reg_a6 = 16; reg_a7 = 17;
  reg_s2 = 18; reg_s3 = 19; reg_s4 = 20; reg_s5 = 21; reg_s6 = 22; reg_s7 = 23; reg_s8 = 24; reg_s9 = 25; reg_s10 = 26; reg_s11 = 27;
  reg_t3 = 28; reg_t4 = 29; reg_t5 = 30; reg_t6 = 31;

  { Machine-mode CSR addresses. Only the ones the compiler itself emits are
    named here; the inline assembler takes any 12-bit number, which is the
    capability -- a name table is a convenience and must never be the only
    way to reach a CSR. }
  CSR_MSTATUS = $300;   { MIE lives at bit 3 }
  CSR_MTVEC   = $305;   { trap vector base + mode; THE raw-ISR install target }
  CSR_MSCRATCH= $340;   { machine scratch. Free on BARE (no FreeRTOS); the IDF
                          port uses it, which is why the ISR-stack switch that
                          depends on it is gated on EspBareBoot. }

{ --- range checks for the PC-relative forms -----------------------------------
  RISC-V branch and jump immediates are cut into pieces and OR'd into the
  instruction word, and every one of those pieces is masked. A target out of
  reach therefore does not fail -- it loses its high bits and produces a
  perfectly well-formed instruction that jumps somewhere else. This backend has
  already paid for that twice over, both times by working around the CALL SITE
  and leaving the encoder sharp:

    - `IR_JUMP_IF_FALSE` in ir_codegen_riscv32.inc emits bne-skip + jal rather
      than a bare beq, because a large routine truncated the B-type offset and
      "branches landed inside unrelated code (chess perft counted 164)".
    - xtensa hit the same class and it "took a disassembly and the arithmetic
      262591-262144=437 to name it" -- which is what produced XtensaRelCheck in
      xtensaenc.inc, the template this mirrors. That fix stopped at its own
      backend; this is the sibling it did not sweep.

  MASKING IS CORRECT FOR NEGATIVE OFFSETS -- two's complement is exactly what
  the field wants -- so this checks the SIGNED RANGE rather than asking whether
  the mask changed the value. The naive form would reject every backward branch.
  xtensaenc.inc states this and it is repeated here because it is the one way
  this check is easy to write wrongly.

  The ALIGNMENT check is not decoration: J- and B-type immediates encode bits
  [20:1] and [12:1], so bit 0 is dropped rather than rejected, and an odd offset
  silently becomes an even one -- a jump into the middle of an instruction, on a
  target where every instruction this backend emits is 4 bytes and an odd offset
  can therefore only be a bug in the caller.
  bug-a-riscv32-pc-relative-encoders-silently-truncate-xtensa-already-guards }
procedure RISCVRelCheck(v, lo, hi: Integer; const what: AnsiString);
begin
  if (v < lo) or (v > hi) then
    Error('target riscv32: ' + what + ' displacement ' + AIntToStr(v) +
          ' is outside the encodable range ' + AIntToStr(lo) + '..' +
          AIntToStr(hi) + '; the code is too large for this branch form');
  if (v mod 2) <> 0 then
    Error('target riscv32: ' + what + ' displacement ' + AIntToStr(v) +
          ' is odd; this form encodes a 2-byte-aligned offset and would drop '
          + 'the low bit, jumping into the middle of an instruction');
end;

{ --- RV32C: the compressed forms ---------------------------------------------
  --rv32-rvc turns RvcOn on (the default on --platform=esp; --no-rv32-rvc off). The rv32_* wrappers below then emit the 16-bit
  form of an ALU/load/store instruction when one exists (about half the
  instructions this backend writes have one). Branches, jal, auipc and
  every jalr but `ret` stay 32-bit: they are the words other code patches,
  relocates or measures, so their size must be fixed when they are emitted.

  Two holds keep compression away from code whose SIZE something else has
  already counted:
    RvcHoldUntil  -- a branch or jal with a constant forward offset (a skip
                    over N bytes, or a loop's exit) holds every instruction
                    until the code reaches its target. Set by the branch
                    wrappers themselves, so no call site has to know.
    RvcHoldDepth  -- >0 while a caller emits words that are patched or
                    relocated later (the prologue's frame reserve, a hi/lo
                    pair) or written by a user (inline asm).
  RvInsn* is a ring of the last instructions the wrappers emitted (start,
  length), so a peephole that reads code backwards can tell where an
  instruction starts -- with mixed lengths the bytes alone cannot. }
var
  RvcOn: Boolean;
  RvcOptRequested: Boolean;   { --rv32-rvc / the esp default; RvcOn once the target is riscv32 }
  RvcOptExplicit: Boolean;    { --rv32-rvc or --no-rv32-rvc was given }
  RvcHoldUntil, RvcHoldDepth: Integer;
  RvInsnStart, RvInsnLen: array[0..7] of Integer;
  RvInsnCount: Integer;
  RvLastAuipcEnd: Integer;   { CodeLen just after the last rv32_auipc }

function RvcMay: Boolean;
begin
  Result := RvcOn and (RvcHoldDepth = 0) and (CodeLen >= RvcHoldUntil);
end;

procedure RvNoteInsn(len: Integer);
begin
  RvInsnStart[RvInsnCount and 7] := CodeLen;
  RvInsnLen[RvInsnCount and 7] := len;
  Inc(RvInsnCount);
end;

{ The k-th most recent wrapper-emitted instruction (0 = last), or False when
  the ring does not reach back that far or something emitted after it
  without going through a wrapper (its end would not be the next start). }
function RvRecentInsn(k: Integer; var start, len: Integer): Boolean;
var i, e: Integer;
begin
  Result := False;
  if (k < 0) or (k >= 8) or (k >= RvInsnCount) then Exit;
  e := CodeLen;
  for i := 0 to k do
  begin
    start := RvInsnStart[(RvInsnCount - 1 - i) and 7];
    len := RvInsnLen[(RvInsnCount - 1 - i) and 7];
    if start + len <> e then Exit;
    e := start;
  end;
  Result := True;
end;

{ After a peephole drops bytes: forget instructions at or past the new end. }
procedure RvForgetFrom(pos: Integer);
begin
  while (RvInsnCount > 0) and (RvInsnStart[(RvInsnCount - 1) and 7] >= pos) do
    Dec(RvInsnCount);
end;

procedure EmitC16(h: Integer);
begin
  RvNoteInsn(2);
  EmitB(Byte(h and $FF));
  EmitB(Byte((h shr 8) and $FF));
end;

{ A constant forward branch/jal offset: no compression until its target. }
procedure RvcHoldSkip(offset: Integer);
begin
  if RvcOn and (offset > 0) and (CodeLen + offset > RvcHoldUntil) then
    RvcHoldUntil := CodeLen + offset;
end;

{ Before `auipc rd,0; jal x0,8; .word; lw rd,8(rd)`: the word must be
  4-aligned for the lw (the C3 does not do misaligned loads), so the auipc
  must be. Pads with c.nop. Inside a counted skip the pad would move code
  someone measured, so that is an internal error instead. }
procedure RvAlignLiteral;
begin
  if not RvcOn then Exit;
  if (CodeLen mod 4) = 0 then Exit;
  if CodeLen < RvcHoldUntil then
    Error('internal: riscv32 --rv32-rvc: an inline literal is misaligned inside a counted skip');
  EmitC16($0001);   { c.nop }
end;

procedure EmitRType(funct7, rs2, rs1, funct3, rd, opcode: Integer);
begin
  RvNoteInsn(4);
  EmitI32((funct7 shl 25) or (rs2 shl 20) or (rs1 shl 15) or (funct3 shl 12) or (rd shl 7) or opcode);
end;

procedure EmitIType(imm, rs1, funct3, rd, opcode: Integer);
begin
  RvNoteInsn(4);
  EmitI32(((imm and $FFF) shl 20) or (rs1 shl 15) or (funct3 shl 12) or (rd shl 7) or opcode);
end;

procedure EmitSType(imm, rs2, rs1, funct3, opcode: Integer);
begin
  RvNoteInsn(4);
  EmitI32(((imm and $FE0) shl 20) or (rs2 shl 20) or (rs1 shl 15) or (funct3 shl 12) or ((imm and $1F) shl 7) or opcode);
end;

procedure EmitBType(imm, rs2, rs1, funct3, opcode: Integer);
var
  i12, i11, i10_5, i4_1: Integer;
begin
  RISCVRelCheck(imm, -4096, 4094, 'conditional branch');
  i12   := (imm shr 12) and 1;
  i11   := (imm shr 11) and 1;
  i10_5 := (imm shr 5) and $3F;
  i4_1  := (imm shr 1) and $F;
  RvNoteInsn(4);
  EmitI32((i12 shl 31) or (i10_5 shl 25) or (rs2 shl 20) or (rs1 shl 15) or (funct3 shl 12) or (i4_1 shl 8) or (i11 shl 7) or opcode);
end;

procedure EmitUType(imm, rd, opcode: Integer);
begin
  RvNoteInsn(4);
  EmitI32((imm and $FFFFF000) or (rd shl 7) or opcode);
end;

procedure EmitJType(imm, rd, opcode: Integer);
var
  i20, i19_12, i11, i10_1: Integer;
begin
  RISCVRelCheck(imm, -1048576, 1048574, 'jal');
  i20    := (imm shr 20) and 1;
  i19_12 := (imm shr 12) and $FF;
  i11    := (imm shr 11) and 1;
  i10_1  := (imm shr 1) and $3FF;
  RvNoteInsn(4);
  EmitI32((i20 shl 31) or (i10_1 shl 21) or (i11 shl 20) or (i19_12 shl 12) or (rd shl 7) or opcode);
end;

function EncodeRISCVJAL(rd: Integer; offset: Integer): Integer;
var
  i20, i19_12, i11, i10_1: Integer;
begin
  RISCVRelCheck(offset, -1048576, 1048574, 'jal');
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

{ auipc rd, hi  (hi already a multiple of 4096 = the upper-20-bit immediate) and
  jalr rd, rs1, lo  — the two halves of a PC-relative long call (auipc+jalr spans
  the full 32-bit range, unlike JAL's +/-1MB). Split a call offset via
  RISCVPcrelSplit. }
function EncodeRISCVAuipc(rd, hi: Integer): Integer;
begin
  Result := (hi and Integer($FFFFF000)) or (rd shl 7) or $17;
end;
function EncodeRISCVLui(rd, hi: Integer): Integer;
begin
  Result := (hi and Integer($FFFFF000)) or (rd shl 7) or $37;
end;
function EncodeRISCVSub(rd, rs1, rs2: Integer): Integer;
begin
  Result := ($20 shl 25) or (rs2 shl 20) or (rs1 shl 15) or (rd shl 7) or $33;
end;
function EncodeRISCVJalr(rd, rs1, imm: Integer): Integer;
begin
  Result := (((imm and $FFF) shl 20) or (rs1 shl 15) or (rd shl 7) or $67);
end;
{ Split a PC-relative offset (target - auipc_pos) into the auipc upper immediate
  (multiple of 4096) and the sign-extended jalr low-12; auipc adds hi, jalr adds
  sign-extended lo, so hi+lo = off exactly. }
procedure RISCVPcrelSplit(off: Integer; var hi: Integer; var lo: Integer);
begin
  lo := off and $FFF;
  if (lo and $800) <> 0 then lo := lo - $1000;   { sign-extend to [-2048, 2047] }
  hi := off - lo;                                { multiple of 4096 }
end;

{ ---- CSR access, for the interrupt-masked critical section ---------------

  The ESP32-C3/C2 core is RV32IMC — no `A` extension, so there is no AMO and no
  LR/SC to build an atomic from. What it does have is machine-mode CSR access,
  and those parts are SINGLE-CORE, so masking interrupts around a
  read-modify-write makes it atomic with respect to everything that can observe
  it. This is what ESP-IDF does on the C3 for the same reason.

  Encodings verified against riscv32-esp-elf-as (-march=rv32imc_zicsr):
    csrrci t0, mstatus, 8   = 0x300472F3   { clear MIE, old mstatus -> t0 }
    csrrw  zero, mstatus, t0 = 0x30029073  { restore it }
  bug-a-riscv32-and-xtensa-have-no-atomic-codegen }
{ The general forms. These were added 2026-09-21 for the raw-ISR vector install
  (feature-s-a-csr-write-is-not-expressible-from-pascal-...): mtvec is CSR $305,
  and until these existed the tree's ONLY CSR write was the mstatus one below,
  with the address frozen in the instruction word.

  The two mstatus helpers are now DERIVED from these rather than restating the
  encoding. That is not tidiness: $300 appeared in two instruction words that
  no test relates to each other, which is the shape CLAUDE.md's "where two
  constants share a name-shape" rule is about. Deriving them means a future
  edit to the CSR field cannot fix one spelling and miss the other.

  Field layout is identical for all six Zicsr instructions -- csr[11:0] in
  31:20, rs1-or-uimm5 in 19:15, funct3 in 14:12, rd in 11:7, opcode $73:
    funct3 1 = csrrw   2 = csrrs   3 = csrrc
           5 = csrrwi  6 = csrrsi  7 = csrrci   (rs1 field is a 5-bit immediate)
  Verified against riscv32-esp-elf-as (-march=rv32imc_zicsr):
    csrrci t0, mstatus, 8    = 0x300472F3
    csrrw  zero, mstatus, t0 = 0x30029073
    csrw   mtvec, t0         = 0x30529073 }
procedure rv32_csr(rd, csr, rs1, funct3: Integer);
begin
  RvNoteInsn(4);
  EmitI32(((csr and $FFF) shl 20) or ((rs1 and $1F) shl 15)
          or ((funct3 and 7) shl 12) or ((rd and $1F) shl 7) or $73);
end;

procedure rv32_csrrw(rd, csr, rs1: Integer);   { rd := csr; csr := rs1 }
begin rv32_csr(rd, csr, rs1, 1); end;

procedure rv32_csrrs(rd, csr, rs1: Integer);   { rd := csr; csr := csr or rs1 }
begin rv32_csr(rd, csr, rs1, 2); end;

procedure rv32_csrrc(rd, csr, rs1: Integer);   { rd := csr; csr := csr and not rs1 }
begin rv32_csr(rd, csr, rs1, 3); end;

procedure rv32_csrrci(rd, csr, uimm: Integer); { rd := csr; csr := csr and not uimm }
begin rv32_csr(rd, csr, uimm, 7); end;

procedure rv32_csrrci_mstatus_mie(rd: Integer);
{ rd := mstatus; mstatus.MIE := 0 }
begin
  rv32_csrrci(rd, CSR_MSTATUS, 8);
end;

procedure rv32_csrw_mstatus(rs1: Integer);
{ mstatus := rs1 }
begin
  rv32_csrrw(0, CSR_MSTATUS, rs1);
end;

procedure rv32_add(rd, rs1, rs2: Integer);
begin
  if RvcMay and (rd <> 0) then
  begin
    if (rs1 = 0) and (rs2 <> 0) then begin EmitC16($8002 or (rd shl 7) or (rs2 shl 2)); Exit; end;   { c.mv }
    if (rs2 = 0) and (rs1 <> 0) then begin EmitC16($8002 or (rd shl 7) or (rs1 shl 2)); Exit; end;
    if (rd = rs1) and (rs2 <> 0) then begin EmitC16($9002 or (rd shl 7) or (rs2 shl 2)); Exit; end;  { c.add }
    if (rd = rs2) and (rs1 <> 0) then begin EmitC16($9002 or (rd shl 7) or (rs1 shl 2)); Exit; end;
  end;
  EmitRType(0, rs2, rs1, 0, rd, $33);
end;
{ c.sub/c.xor/c.or/c.and: rd = rs1, both in x8..x15. }
function RvcTryCA(rd, rs1, rs2, f2: Integer; commutes: Boolean): Boolean;
begin
  Result := False;
  if not RvcMay then Exit;
  if (rd < 8) or (rd > 15) then Exit;
  if (rd <> rs1) and commutes and (rd = rs2) then begin rs2 := rs1; rs1 := rd; end;
  if (rd <> rs1) or (rs2 < 8) or (rs2 > 15) then Exit;
  EmitC16($8C01 or ((rd - 8) shl 7) or (f2 shl 5) or ((rs2 - 8) shl 2));
  Result := True;
end;

procedure rv32_sub(rd, rs1, rs2: Integer);
begin
  if RvcTryCA(rd, rs1, rs2, 0, False) then Exit;
  EmitRType($20, rs2, rs1, 0, rd, $33);
end;
procedure rv32_addi(rd, rs1, imm: Integer);
begin
  if RvcMay and (rd <> 0) then
  begin
    if (rs1 = 0) and (imm >= -32) and (imm < 32) then                                 { c.li }
    begin EmitC16($4001 or (((imm shr 5) and 1) shl 12) or (rd shl 7) or ((imm and $1F) shl 2)); Exit; end;
    if (rd = rs1) and (imm <> 0) and (imm >= -32) and (imm < 32) then                 { c.addi }
    begin EmitC16($0001 or (((imm shr 5) and 1) shl 12) or (rd shl 7) or ((imm and $1F) shl 2)); Exit; end;
    if (rd = 2) and (rs1 = 2) and (imm <> 0) and ((imm and 15) = 0) and
       (imm >= -512) and (imm < 512) then                                              { c.addi16sp }
    begin
      EmitC16($6101 or (((imm shr 9) and 1) shl 12) or (((imm shr 4) and 1) shl 6) or
              (((imm shr 6) and 1) shl 5) or (((imm shr 7) and 3) shl 3) or (((imm shr 5) and 1) shl 2));
      Exit;
    end;
    if (imm = 0) and (rs1 <> 0) and (rd <> rs1) then                                  { c.mv }
    begin EmitC16($8002 or (rd shl 7) or (rs1 shl 2)); Exit; end;
    if (rs1 = 2) and (rd >= 8) and (rd <= 15) and (imm > 0) and ((imm and 3) = 0) and
       (imm < 1024) then                                                               { c.addi4spn }
    begin
      EmitC16((((imm shr 4) and 3) shl 11) or (((imm shr 6) and 15) shl 7) or
              (((imm shr 2) and 1) shl 6) or (((imm shr 3) and 1) shl 5) or ((rd - 8) shl 2));
      Exit;
    end;
  end;
  EmitIType(imm, rs1, 0, rd, $13);
end;
procedure rv32_lui(rd, imm: Integer);
var v: Integer;
begin
  { imm is the value with its low 12 bits clear; c.lui carries bits 17:12 }
  v := imm div 4096;
  if RvcMay and (rd <> 0) and (rd <> 2) and ((imm and $FFF) = 0) and (v <> 0) and
     (v >= -32) and (v < 32) then
  begin
    EmitC16($6001 or (((v shr 5) and 1) shl 12) or (rd shl 7) or ((v and $1F) shl 2));
    Exit;
  end;
  EmitUType(imm, rd, $37);
end;
procedure rv32_auipc(rd, imm20: Integer);   begin EmitUType(imm20, rd, $17); RvLastAuipcEnd := CodeLen; end;
procedure rv32_lb(rd, rs1, imm: Integer);   begin EmitIType(imm, rs1, 0, rd, $03); end;
procedure rv32_lh(rd, rs1, imm: Integer);   begin EmitIType(imm, rs1, 1, rd, $03); end;
procedure rv32_lbu(rd, rs1, imm: Integer);  begin EmitIType(imm, rs1, 4, rd, $03); end;
procedure rv32_lhu(rd, rs1, imm: Integer);  begin EmitIType(imm, rs1, 5, rd, $03); end;
procedure rv32_lw(rd, rs1, imm: Integer);
begin
  if RvcMay and (rd <> 0) and (imm >= 0) and ((imm and 3) = 0) then
  begin
    if (rs1 = 2) and (imm < 256) then                                                 { c.lwsp }
    begin
      EmitC16($4002 or (((imm shr 5) and 1) shl 12) or (rd shl 7) or
              (((imm shr 2) and 7) shl 4) or (((imm shr 6) and 3) shl 2));
      Exit;
    end;
    if (rs1 >= 8) and (rs1 <= 15) and (rd >= 8) and (rd <= 15) and (imm < 128) then   { c.lw }
    begin
      EmitC16($4000 or (((imm shr 3) and 7) shl 10) or ((rs1 - 8) shl 7) or
              (((imm shr 2) and 1) shl 6) or (((imm shr 6) and 1) shl 5) or ((rd - 8) shl 2));
      Exit;
    end;
  end;
  EmitIType(imm, rs1, 2, rd, $03);
end;
procedure rv32_sb(rs2, rs1, imm: Integer);  begin EmitSType(imm, rs2, rs1, 0, $23); end;
procedure rv32_sh(rs2, rs1, imm: Integer);  begin EmitSType(imm, rs2, rs1, 1, $23); end;
procedure rv32_sw(rs2, rs1, imm: Integer);
begin
  if RvcMay and (imm >= 0) and ((imm and 3) = 0) then
  begin
    if (rs1 = 2) and (imm < 256) then                                                 { c.swsp }
    begin
      EmitC16($C002 or (((imm shr 2) and 15) shl 9) or (((imm shr 6) and 3) shl 7) or (rs2 shl 2));
      Exit;
    end;
    if (rs1 >= 8) and (rs1 <= 15) and (rs2 >= 8) and (rs2 <= 15) and (imm < 128) then { c.sw }
    begin
      EmitC16($C000 or (((imm shr 3) and 7) shl 10) or ((rs1 - 8) shl 7) or
              (((imm shr 2) and 1) shl 6) or (((imm shr 6) and 1) shl 5) or ((rs2 - 8) shl 2));
      Exit;
    end;
  end;
  EmitSType(imm, rs2, rs1, 2, $23);
end;
procedure rv32_xori(rd, rs1, imm: Integer); begin EmitIType(imm, rs1, 4, rd, $13); end;
procedure rv32_ori(rd, rs1, imm: Integer);  begin EmitIType(imm, rs1, 6, rd, $13); end;
procedure rv32_andi(rd, rs1, imm: Integer);
begin
  if RvcMay and (rd = rs1) and (rd >= 8) and (rd <= 15) and (imm >= -32) and (imm < 32) then
  begin
    EmitC16($8801 or (((imm shr 5) and 1) shl 12) or ((rd - 8) shl 7) or ((imm and $1F) shl 2));
    Exit;
  end;
  EmitIType(imm, rs1, 7, rd, $13);
end;
procedure rv32_jal(rd, offset: Integer);
begin
  RvcHoldSkip(offset);
  { `jal x0, 8` steps over an inline literal word, which must be 4-aligned. }
  if RvcOn and (rd = 0) and (offset = 8) and (RvLastAuipcEnd = CodeLen) and ((CodeLen mod 4) <> 0) then
    Error('internal: riscv32 --rv32-rvc: inline literal after a misaligned jal (no RvAlignLiteral before its auipc)');
  EmitJType(offset, rd, $6F);
end;
procedure rv32_jalr(rd, rs1, imm: Integer);
begin
  { only `ret`: every other jalr may be the second word of an auipc pair
    that is patched or relocated as a unit }
  if RvcMay and (rd = 0) and (rs1 = reg_ra) and (imm = 0) then
  begin
    EmitC16($8082);   { c.jr ra }
    Exit;
  end;
  EmitIType(imm, rs1, 0, rd, $67);
end;

{ ---- the A extension: AMO, LR and SC -------------------------------------
  R-type on opcode $2F with funct3 = 010 (word width), and funct7 carries the
  operation in its top five bits plus the two ordering bits:
  funct7 = (funct5 shl 2) or (aq shl 1) or rl. Both ordering bits are set on
  every emission here -- sequential consistency is what __pxxatomic_* promises,
  and the weaker orderings have no spelling in that interface to ask for.

  These are deliberately NOT reachable on the ESP parts. The refusal in
  ir_codegen_riscv32.inc's IR_ATOMIC asks the per-CHIP capability table first:
  the ESP32-C3/C2 are RV32IMC and would take an ILLEGAL INSTRUCTION on any of
  these, which is why that arm masks interrupts instead. What these encoders
  add is the HOSTED case, where the core is qemu's rv32gc and has them.
  feature-a-a-stackful-coroutine-is-four-targets-only-so-examples-net-httpdemo-cannot-cross }
procedure rv32_amo_w(funct5, rd, rs2, rs1: Integer);
begin EmitRType((funct5 shl 2) or 3, rs2, rs1, 2, rd, $2F); end;
procedure rv32_amoswap_w(rd, rs2, rs1: Integer); begin rv32_amo_w($01, rd, rs2, rs1); end;
procedure rv32_amoadd_w(rd, rs2, rs1: Integer);  begin rv32_amo_w($00, rd, rs2, rs1); end;
procedure rv32_lr_w(rd, rs1: Integer);           begin rv32_amo_w($02, rd, 0, rs1); end;
procedure rv32_sc_w(rd, rs2, rs1: Integer);      begin rv32_amo_w($03, rd, rs2, rs1); end;

procedure rv32_mul(rd, rs1, rs2: Integer);  begin EmitRType(1, rs2, rs1, 0, rd, $33); end;
procedure rv32_mulhu(rd, rs1, rs2: Integer);begin EmitRType(1, rs2, rs1, 3, rd, $33); end;
procedure rv32_mulh(rd, rs1, rs2: Integer); begin EmitRType(1, rs2, rs1, 1, rd, $33); end;
procedure rv32_div(rd, rs1, rs2: Integer);  begin EmitRType(1, rs2, rs1, 4, rd, $33); end;
procedure rv32_divu(rd, rs1, rs2: Integer); begin EmitRType(1, rs2, rs1, 5, rd, $33); end;
procedure rv32_rem(rd, rs1, rs2: Integer);  begin EmitRType(1, rs2, rs1, 6, rd, $33); end;
procedure rv32_remu(rd, rs1, rs2: Integer); begin EmitRType(1, rs2, rs1, 7, rd, $33); end;
procedure rv32_and(rd, rs1, rs2: Integer);  begin if RvcTryCA(rd, rs1, rs2, 3, True) then Exit; EmitRType(0, rs2, rs1, 7, rd, $33); end;
procedure rv32_or(rd, rs1, rs2: Integer);   begin if RvcTryCA(rd, rs1, rs2, 2, True) then Exit; EmitRType(0, rs2, rs1, 6, rd, $33); end;
procedure rv32_xor(rd, rs1, rs2: Integer);  begin if RvcTryCA(rd, rs1, rs2, 1, True) then Exit; EmitRType(0, rs2, rs1, 4, rd, $33); end;
procedure rv32_sll(rd, rs1, rs2: Integer);  begin EmitRType(0, rs2, rs1, 1, rd, $33); end;
procedure rv32_srl(rd, rs1, rs2: Integer);  begin EmitRType(0, rs2, rs1, 5, rd, $33); end;
procedure rv32_sra(rd, rs1, rs2: Integer);  begin EmitRType($20, rs2, rs1, 5, rd, $33); end;
procedure rv32_slt(rd, rs1, rs2: Integer);  begin EmitRType(0, rs2, rs1, 2, rd, $33); end;
procedure rv32_sltu(rd, rs1, rs2: Integer); begin EmitRType(0, rs2, rs1, 3, rd, $33); end;
procedure rv32_slti(rd, rs1, imm: Integer); begin EmitIType(imm, rs1, 2, rd, $13); end;
procedure rv32_sltiu(rd, rs1, imm: Integer);begin EmitIType(imm, rs1, 3, rd, $13); end;
procedure rv32_slli(rd, rs1, sh: Integer);
begin
  if RvcMay and (rd = rs1) and (rd <> 0) and ((sh and $1F) <> 0) then
  begin EmitC16($0002 or (rd shl 7) or ((sh and $1F) shl 2)); Exit; end;     { c.slli }
  EmitIType(sh and $1F, rs1, 1, rd, $13);
end;
procedure rv32_srli(rd, rs1, sh: Integer);
begin
  if RvcMay and (rd = rs1) and (rd >= 8) and (rd <= 15) and ((sh and $1F) <> 0) then
  begin EmitC16($8001 or ((rd - 8) shl 7) or ((sh and $1F) shl 2)); Exit; end;     { c.srli }
  EmitIType(sh and $1F, rs1, 5, rd, $13);
end;
procedure rv32_srai(rd, rs1, sh: Integer);
begin
  if RvcMay and (rd = rs1) and (rd >= 8) and (rd <= 15) and ((sh and $1F) <> 0) then
  begin EmitC16($8401 or ((rd - 8) shl 7) or ((sh and $1F) shl 2)); Exit; end;     { c.srai }
  EmitIType((sh and $1F) or $400, rs1, 5, rd, $13);
end;

function EncodeRISCVBEQ(rs1, rs2, offset: Integer): Integer;
var i12, i11, i10_5, i4_1: Integer;
begin
  RISCVRelCheck(offset, -4096, 4094, 'conditional branch');
  i12   := (offset shr 12) and 1;
  i11   := (offset shr 11) and 1;
  i10_5 := (offset shr 5) and $3F;
  i4_1  := (offset shr 1) and $F;
  Result := (i12 shl 31) or (i10_5 shl 25) or (rs2 shl 20) or (rs1 shl 15) or (0 shl 12) or (i4_1 shl 8) or (i11 shl 7) or $63;
end;

procedure rv32_beq(rs1, rs2, offset: Integer);
begin
  RvcHoldSkip(offset);
  RvcHoldSkip(offset);
  RvNoteInsn(4);
  EmitI32(EncodeRISCVBEQ(rs1, rs2, offset));
end;

function EncodeRISCVBNE(rs1, rs2, offset: Integer): Integer;
{ B-type, funct3 = 001. Same shape as BEQ; the branch offset is relative to the
  BRANCH itself, as RISC-V defines it. }
var i12, i11, i10_5, i4_1: Integer;
begin
  RISCVRelCheck(offset, -4096, 4094, 'conditional branch');
  i12   := (offset shr 12) and 1;
  i11   := (offset shr 11) and 1;
  i10_5 := (offset shr 5) and $3F;
  i4_1  := (offset shr 1) and $F;
  Result := (i12 shl 31) or (i10_5 shl 25) or (rs2 shl 20) or (rs1 shl 15) or
            (1 shl 12) or (i4_1 shl 8) or (i11 shl 7) or $63;
end;

procedure rv32_bne(rs1, rs2, offset: Integer);
begin
  RvcHoldSkip(offset);
  RvcHoldSkip(offset);
  RvNoteInsn(4);
  EmitI32(EncodeRISCVBNE(rs1, rs2, offset));
end;

function EncodeRISCVBranch(funct3, rs1, rs2, offset: Integer): Integer;
{ Any B-type branch: BEQ/BNE above are this with funct3 0/1; BLT=4, BGE=5,
  BLTU=6, BGEU=7. }
var i12, i11, i10_5, i4_1: Integer;
begin
  RISCVRelCheck(offset, -4096, 4094, 'conditional branch');
  i12   := (offset shr 12) and 1;
  i11   := (offset shr 11) and 1;
  i10_5 := (offset shr 5) and $3F;
  i4_1  := (offset shr 1) and $F;
  Result := (i12 shl 31) or (i10_5 shl 25) or (rs2 shl 20) or (rs1 shl 15) or
            (funct3 shl 12) or (i4_1 shl 8) or (i11 shl 7) or $63;
end;

procedure rv32_blt(rs1, rs2, offset: Integer);  begin RvcHoldSkip(offset); RvNoteInsn(4); EmitI32(EncodeRISCVBranch(4, rs1, rs2, offset)); end;
procedure rv32_bge(rs1, rs2, offset: Integer);  begin RvcHoldSkip(offset); RvNoteInsn(4); EmitI32(EncodeRISCVBranch(5, rs1, rs2, offset)); end;
procedure rv32_bltu(rs1, rs2, offset: Integer); begin RvcHoldSkip(offset); RvNoteInsn(4); EmitI32(EncodeRISCVBranch(6, rs1, rs2, offset)); end;
procedure rv32_bgeu(rs1, rs2, offset: Integer); begin RvcHoldSkip(offset); RvNoteInsn(4); EmitI32(EncodeRISCVBranch(7, rs1, rs2, offset)); end;

procedure rv32_nop;
begin
  RvNoteInsn(4);
  EmitI32($00000013);
end;

procedure rv32_mret;   { return from machine-mode trap (restores PC from mepc) }
begin
  RvNoteInsn(4);
  EmitI32($30200073);
end;




