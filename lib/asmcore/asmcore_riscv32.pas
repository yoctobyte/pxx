unit asmcore_riscv32;
{$mode objfpc}{$H+}
{ riscv32 (RV32I) instruction encoder + textual printer — the fifth
  `lib/asmcore` target. Fixed-width 32-bit instructions, but the most
  structurally different patch-resolution problem yet: where aarch64's
  branch immediates are a contiguous bitfield (just shifted) and arm32's are
  a contiguous bitfield offset by one pipeline word, RISC-V's `jal`
  (UJ-type) and branch (SB-type) immediates are BIT-SCRAMBLED — split into
  non-contiguous, non-monotonic pieces (imm[20|10:1|11|19:12] for jal,
  imm[12|10:5] ... imm[4:1|11] for branches), a deliberate hardware-wiring
  optimization in the ISA spec. AsmPatchBranchRiscv32 below has to scatter
  the bits into place, not just shift-and-OR a contiguous field.

  A second difference from every other target here: RISC-V branch/jal
  immediates are relative to the CURRENT instruction's OWN address — no
  "+4 next instruction" (x64/aarch64/i386) and no "+8 pipeline" (arm32)
  adjustment. To keep the frontend-facing contract identical across every
  target this library has (the same `relWords = (target-(patch+4))/4` a
  frontend already computes uniformly), `AsmPatchBranchRiscv32` converts
  internally: `byteOffset = relWords*4 + 4`. Verified against the host
  oracle, 2026-06-30.

  A third structural difference: RISC-V branches compare two registers
  *in the branch instruction itself* (no separate flags-setting `cmp` the
  way x86/ARM work) — so a riscv32 branch's `TAsmInstr` is 3 operands
  (rs1, rs2, the patch site), not the 1-operand `<patch>` every other
  target here uses. `TAsmOperand`/`TAsmInstr` needed no changes to express
  this — confirms the abstraction generalizes a fourth way.

  Coverage:
    add/sub/and/or/xor/slt/sltu        reg,reg,reg
    addi/andi/ori/xori/sltiu             reg,reg,#imm12 (signed, sign-
                                          extended on the ALU op; sltiu
                                          compares unsigned but the field
                                          is still a signed 12-bit pattern)
    mv reg,reg                           (pseudo: addi rd,rs,0)
    li reg,#imm12                        (pseudo: addi rd,zero,imm — single
                                          instruction, -2048..2047 only;
                                          the full 32-bit li (lui+addi pair)
                                          is out of scope this slice, same
                                          "one canonical instruction, not a
                                          synthesized multi-op pseudo"
                                          choice aarch64's movz made)
    lw/sw                                 reg,[reg+#imm12]
    lui                                   reg,#imm20
    jal reg,<patch>                       (UJ-type, scrambled imm21)
    jalr reg,reg,#imm12                   (indirect; not a patch site)
    ret                                   (= jalr x0,x1,0)
    beq/bne/blt/bge/bltu/bgeu reg,reg,<patch>  (SB-type, scrambled imm13)
    nop                                    (= addi x0,x0,0)
  Byte-exact vs `riscv64-linux-gnu-as -march=rv32i`/objdump oracle,
  2026-06-30 (the riscv64 toolchain assembles RV32I cleanly with the right
  -march/-mabi; no separate riscv32-only toolchain was needed).
  Deliberately NOT modeled: the C (compressed) extension, M/A/F/D
  extensions, full 32-bit `li` (lui+addi), AUIPC, fence/ecall/ebreak.
  See devdocs/developer/asmcore-design.md. }

interface

uses asmcore_base;

const
  reg_x0=0; reg_x1=1; reg_x2=2; reg_x3=3; reg_x4=4; reg_x5=5; reg_x6=6; reg_x7=7;
  reg_x8=8; reg_x9=9; reg_x10=10; reg_x11=11; reg_x12=12; reg_x13=13; reg_x14=14; reg_x15=15;
  reg_x16=16; reg_x17=17; reg_x18=18; reg_x19=19; reg_x20=20; reg_x21=21; reg_x22=22; reg_x23=23;
  reg_x24=24; reg_x25=25; reg_x26=26; reg_x27=27; reg_x28=28; reg_x29=29; reg_x30=30; reg_x31=31;
  reg_zero=0; reg_ra=1; reg_sp=2;

function AsmEncodeRiscv32(const instr: TAsmInstr;
                           var buf: TAsmByteBuf;
                           var patches: TAsmPatchList): Boolean;
function AsmPrintRiscv32(const instr: TAsmInstr): AnsiString;
function AsmCoreLastErrorRiscv32: AnsiString;

{ Resolve one riscv32 jal/branch patch site. relWords uses the SAME
  convention every other target's resolver does -- (target-(patch+4))/4,
  what a frontend already computes uniformly -- converted internally to
  the byte offset RISC-V's "relative to this instruction's own address"
  convention needs, then bit-scattered into the UJ-type (jal) or SB-type
  (branch) immediate layout. See the unit header note. }
function AsmPatchBranchRiscv32(var buf: TAsmByteBuf; offset: Integer;
                                const mnemonic: AnsiString; relWords: Int64): Boolean;

implementation

var
  LastError: AnsiString;

function MnemIs(const m: AnsiString; const lit: AnsiString): Boolean;
var i: Integer; c: Char;
begin
  Result := False;
  if Length(m) <> Length(lit) then Exit;
  for i := 1 to Length(m) do
  begin
    c := m[i];
    if (c >= 'A') and (c <= 'Z') then c := Chr(Ord(c) + 32);
    if c <> lit[i] then Exit;
  end;
  Result := True;
end;

function IntToStrAsm(v: Int64): AnsiString;
var neg: Boolean; u: Int64; s: AnsiString; d: Integer;
begin
  if v = 0 then begin Result := '0'; Exit; end;
  neg := v < 0;
  u := v; if neg then u := -u;
  s := '';
  while u > 0 do
  begin
    d := Integer(u mod 10);
    s := Chr(Ord('0') + d) + s;
    u := u div 10;
  end;
  if neg then s := '-' + s;
  Result := s;
end;

function RegName(reg: Integer): AnsiString;
begin
  if (reg >= 0) and (reg <= 31) then Result := 'x' + IntToStrAsm(reg)
  else Result := '?';
end;

procedure BufAppendU32(var buf: TAsmByteBuf; w: Int64);
begin
  BufAppend(buf, Byte(w and $FF));
  BufAppend(buf, Byte((w shr 8) and $FF));
  BufAppend(buf, Byte((w shr 16) and $FF));
  BufAppend(buf, Byte((w shr 24) and $FF));
end;

{ R-type: funct7(7) rs2(5) rs1(5) funct3(3) rd(5) opcode(7)=0110011. }
function EncodeRType(funct7, funct3: Integer; const rd, rs1, rs2: TAsmOperand; var buf: TAsmByteBuf): Boolean;
var w: Int64;
begin
  w := $33 or (Int64(funct3) shl 12) or (Int64(funct7) shl 25)
     or (Int64(rs2.Reg) shl 20) or (Int64(rs1.Reg) shl 15) or (Int64(rd.Reg) shl 7);
  BufAppendU32(buf, w);
  Result := True;
end;

{ I-type ALU: imm12(12) rs1(5) funct3(3) rd(5) opcode(7)=0010011. }
function EncodeIType(opcode, funct3: Integer; imm12: Int64; const rd, rs1: TAsmOperand; var buf: TAsmByteBuf): Boolean;
var w: Int64;
begin
  if (imm12 < -2048) or (imm12 > 2047) then
  begin LastError := 'asmcore_riscv32: immediate must be -2048..2047 (signed 12-bit)'; Result := False; Exit; end;
  w := Int64(opcode) or (Int64(funct3) shl 12) or ((imm12 and $FFF) shl 20)
     or (Int64(rs1.Reg) shl 15) or (Int64(rd.Reg) shl 7);
  BufAppendU32(buf, w);
  Result := True;
end;

{ S-type (store): imm[11:5](7) rs2(5) rs1(5) funct3(3) imm[4:0](5) opcode(7)=0100011.
  rs2 is the VALUE being stored (this library's "reg" operand for str-style
  calls); rs1 is the base address (mem.MemBase). }
function EncodeSType(funct3: Integer; const valueReg: TAsmOperand; const mem: TAsmOperand; var buf: TAsmByteBuf): Boolean;
var w, imm: Int64;
begin
  imm := mem.MemDisp;
  if (imm < -2048) or (imm > 2047) then
  begin LastError := 'asmcore_riscv32: store offset must be -2048..2047'; Result := False; Exit; end;
  w := $23 or (Int64(funct3) shl 12) or (Int64(valueReg.Reg) shl 20) or (Int64(mem.MemBase) shl 15)
     or ((imm and $1F) shl 7) or (((imm shr 5) and $7F) shl 25);
  BufAppendU32(buf, w);
  Result := True;
end;

function AsmEncodeRiscv32(const instr: TAsmInstr;
                           var buf: TAsmByteBuf;
                           var patches: TAsmPatchList): Boolean;
var
  d0, d1, d2: TAsmOperand;
  w: Int64;
  funct3: Integer;
begin
  LastError := '';
  Result := False;

  { ---- zero-operand: nop, ret ---- }
  if (instr.OperandCount = 0) and MnemIs(instr.Mnemonic, 'nop') then
  begin BufAppendU32(buf, $00000013); Result := True; Exit; end;
  if (instr.OperandCount = 0) and MnemIs(instr.Mnemonic, 'ret') then
  begin BufAppendU32(buf, $00008067); Result := True; Exit; end;   { jalr x0,x1,0 }

  { ---- jal rd,<patch> ---- }
  if (instr.OperandCount = 2) and (instr.Operands[0].Kind = opReg)
     and (instr.Operands[1].Kind = opPatch) and MnemIs(instr.Mnemonic, 'jal') then
  begin
    PatchAdd(patches, buf.Len, 4, 1);
    BufAppendU32(buf, $6F or (Int64(instr.Operands[0].Reg) shl 7));
    Result := True; Exit;
  end;

  { ---- jalr rd,rs1,#imm (not a patch site -- indirect) ---- }
  if (instr.OperandCount = 3) and (instr.Operands[0].Kind = opReg) and (instr.Operands[1].Kind = opReg)
     and (instr.Operands[2].Kind = opImm) and MnemIs(instr.Mnemonic, 'jalr') then
  begin Result := EncodeIType($67, 0, instr.Operands[2].Imm, instr.Operands[0], instr.Operands[1], buf); Exit; end;

  { ---- branches: beq/bne/blt/bge/bltu/bgeu rs1,rs2,<patch> ---- }
  if (instr.OperandCount = 3) and (instr.Operands[0].Kind = opReg) and (instr.Operands[1].Kind = opReg)
     and (instr.Operands[2].Kind = opPatch) then
  begin
    funct3 := -1;
    if MnemIs(instr.Mnemonic, 'beq') then funct3 := 0
    else if MnemIs(instr.Mnemonic, 'bne') then funct3 := 1
    else if MnemIs(instr.Mnemonic, 'blt') then funct3 := 4
    else if MnemIs(instr.Mnemonic, 'bge') then funct3 := 5
    else if MnemIs(instr.Mnemonic, 'bltu') then funct3 := 6
    else if MnemIs(instr.Mnemonic, 'bgeu') then funct3 := 7;
    if funct3 < 0 then begin LastError := 'asmcore_riscv32: unrecognized branch mnemonic: ' + instr.Mnemonic; Exit; end;
    d0 := instr.Operands[0]; d1 := instr.Operands[1];
    w := $63 or (Int64(funct3) shl 12) or (Int64(d0.Reg) shl 15) or (Int64(d1.Reg) shl 20);
    PatchAdd(patches, buf.Len, 4, 2);
    BufAppendU32(buf, w);
    Result := True; Exit;
  end;

  { ---- two-operand reg,reg : mv (pseudo addi rd,rs,0) ---- }
  if (instr.OperandCount = 2) and (instr.Operands[0].Kind = opReg) and (instr.Operands[1].Kind = opReg)
     and MnemIs(instr.Mnemonic, 'mv') then
  begin Result := EncodeIType($13, 0, 0, instr.Operands[0], instr.Operands[1], buf); Exit; end;

  { ---- two-operand reg,imm : li (pseudo addi rd,zero,imm) ---- }
  if (instr.OperandCount = 2) and (instr.Operands[0].Kind = opReg) and (instr.Operands[1].Kind = opImm)
     and MnemIs(instr.Mnemonic, 'li') then
  begin d2.Reg := reg_zero; Result := EncodeIType($13, 0, instr.Operands[1].Imm, instr.Operands[0], d2, buf); Exit; end;

  { ---- two-operand reg,imm : lui ---- }
  if (instr.OperandCount = 2) and (instr.Operands[0].Kind = opReg) and (instr.Operands[1].Kind = opImm)
     and MnemIs(instr.Mnemonic, 'lui') then
  begin
    d1 := instr.Operands[1];
    if (d1.Imm < 0) or (d1.Imm > 1048575) then begin LastError := 'asmcore_riscv32: lui immediate must be 0..0xFFFFF'; Exit; end;
    BufAppendU32(buf, $37 or (d1.Imm shl 12) or (Int64(instr.Operands[0].Reg) shl 7));
    Result := True; Exit;
  end;

  { ---- two-operand reg,[mem] : lw / sw ---- }
  if (instr.OperandCount = 2) and (instr.Operands[0].Kind = opReg) and (instr.Operands[1].Kind = opMem) then
  begin
    d0 := instr.Operands[0]; d1 := instr.Operands[1];
    if MnemIs(instr.Mnemonic, 'lw') then
    begin d2.Reg := d1.MemBase; Result := EncodeIType($03, 2, d1.MemDisp, d0, d2, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'sw') then
    begin Result := EncodeSType(2, d0, d1, buf); Exit; end;
  end;

  { ---- three-operand reg,reg,reg : R-type ALU ---- }
  if (instr.OperandCount = 3) and (instr.Operands[0].Kind = opReg)
     and (instr.Operands[1].Kind = opReg) and (instr.Operands[2].Kind = opReg) then
  begin
    d0 := instr.Operands[0]; d1 := instr.Operands[1]; d2 := instr.Operands[2];
    if MnemIs(instr.Mnemonic, 'add') then begin Result := EncodeRType(0, 0, d0, d1, d2, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'sub') then begin Result := EncodeRType($20, 0, d0, d1, d2, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'and') then begin Result := EncodeRType(0, 7, d0, d1, d2, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'or')  then begin Result := EncodeRType(0, 6, d0, d1, d2, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'xor') then begin Result := EncodeRType(0, 4, d0, d1, d2, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'slt') then begin Result := EncodeRType(0, 2, d0, d1, d2, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'sltu') then begin Result := EncodeRType(0, 3, d0, d1, d2, buf); Exit; end;
  end;

  { ---- three-operand reg,reg,imm : I-type ALU ---- }
  if (instr.OperandCount = 3) and (instr.Operands[0].Kind = opReg)
     and (instr.Operands[1].Kind = opReg) and (instr.Operands[2].Kind = opImm) then
  begin
    d0 := instr.Operands[0]; d1 := instr.Operands[1]; d2 := instr.Operands[2];
    if MnemIs(instr.Mnemonic, 'addi') then begin Result := EncodeIType($13, 0, d2.Imm, d0, d1, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'andi') then begin Result := EncodeIType($13, 7, d2.Imm, d0, d1, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'ori')  then begin Result := EncodeIType($13, 6, d2.Imm, d0, d1, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'xori') then begin Result := EncodeIType($13, 4, d2.Imm, d0, d1, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'sltiu') then begin Result := EncodeIType($13, 3, d2.Imm, d0, d1, buf); Exit; end;
  end;

  LastError := 'asmcore_riscv32: unrecognized mnemonic/operand combination: ' + instr.Mnemonic;
  Result := False;
end;

function AsmPatchBranchRiscv32(var buf: TAsmByteBuf; offset: Integer;
                                const mnemonic: AnsiString; relWords: Int64): Boolean;
var w, off: Int64; isJal: Boolean;
begin
  Result := False;
  isJal := MnemIs(mnemonic, 'jal');
  if (not isJal) and (not MnemIs(mnemonic, 'beq')) and (not MnemIs(mnemonic, 'bne'))
     and (not MnemIs(mnemonic, 'blt')) and (not MnemIs(mnemonic, 'bge'))
     and (not MnemIs(mnemonic, 'bltu')) and (not MnemIs(mnemonic, 'bgeu')) then
  begin LastError := 'asmcore_riscv32: not a branch mnemonic: ' + mnemonic; Exit; end;

  off := relWords * 4 + 4;   { uniform convention -> "relative to this instruction" }
  if (off mod 2) <> 0 then
  begin LastError := 'asmcore_riscv32: branch/jal target must be 2-byte aligned'; Exit; end;

  w := Int64(buf.Bytes[offset]) or (Int64(buf.Bytes[offset+1]) shl 8)
     or (Int64(buf.Bytes[offset+2]) shl 16) or (Int64(buf.Bytes[offset+3]) shl 24);

  if isJal then
  begin
    if (off < -1048576) or (off > 1048574) then
    begin LastError := 'asmcore_riscv32: jal target out of imm21 range'; Exit; end;
    w := w or (((off shr 20) and 1) shl 31) or (((off shr 1) and $3FF) shl 21)
       or (((off shr 11) and 1) shl 20) or (((off shr 12) and $FF) shl 12);
  end
  else
  begin
    if (off < -4096) or (off > 4094) then
    begin LastError := 'asmcore_riscv32: branch target out of imm13 range'; Exit; end;
    w := w or (((off shr 12) and 1) shl 31) or (((off shr 5) and $3F) shl 25)
       or (((off shr 1) and $F) shl 8) or (((off shr 11) and 1) shl 7);
  end;

  buf.Bytes[offset]   := Byte(w and $FF);
  buf.Bytes[offset+1] := Byte((w shr 8) and $FF);
  buf.Bytes[offset+2] := Byte((w shr 16) and $FF);
  buf.Bytes[offset+3] := Byte((w shr 24) and $FF);
  Result := True;
end;

{ ---- textual printer ---- }

function MemText(const m: TAsmOperand): AnsiString;
begin
  Result := IntToStrAsm(m.MemDisp) + '(' + RegName(m.MemBase) + ')';
end;

function OperandText(const op: TAsmOperand): AnsiString;
begin
  case op.Kind of
    opReg: Result := RegName(op.Reg);
    opImm: Result := IntToStrAsm(op.Imm);
    opMem: Result := MemText(op);
    opPatch: Result := '<patch>';
  else
    Result := '?';
  end;
end;

function AsmPrintRiscv32(const instr: TAsmInstr): AnsiString;
var i: Integer; s: AnsiString;
begin
  s := instr.Mnemonic;
  if instr.OperandCount > 0 then s := s + ' ';
  for i := 0 to instr.OperandCount - 1 do
  begin
    if i > 0 then s := s + ', ';
    s := s + OperandText(instr.Operands[i]);
  end;
  Result := s;
end;

function AsmCoreLastErrorRiscv32: AnsiString;
begin
  Result := LastError;
end;

end.
