unit asmcore_aarch64;
{$mode objfpc}{$H+}
{ aarch64 (AArch64/ARMv8-A) instruction encoder + textual printer — the
  second `lib/asmcore` target (feature-asmcore-encoder-library), chosen as
  the deliberate "structurally different" pressure test for the operand
  model proved out by asmcore_x64: fixed-width 32-bit instructions, no
  ModRM/SIB, no REX, 3-address ALU (add Xd,Xn,Xm, not x64's 2-address
  add Rd,Rm), and — the real finding — branch immediates are NOT a separate
  trailing byte-aligned field like x86's rel32. They're bit-packed inside
  the same 32-bit word as the opcode (imm26 at bits[25:0] for b/bl, imm19 at
  bits[23:5] for b.cond), so a generic "overwrite N raw bytes at Offset"
  patch (x64's Patch32) would clobber the opcode. See AsmPatchBranchAArch64
  below — TAsmPatchSite's (Offset, Width, OperandIndex) contract still holds
  unchanged (asmcore_base needed zero changes), but resolving an aarch64
  branch patch needs a read-modify-write helper that knows the per-mnemonic
  bit layout, not a blind byte overwrite. That helper is target-specific by
  necessity and is exported here, not generalized into asmcore_base.

  Coverage (this slice — same scope tier x64 had after its first session):
    mov   reg,reg                          (alias: orr Xd, XZR, Xm)
    add/sub/and/orr/eor  reg,reg,reg        (shifted-register, shift #0)
    add/sub              reg,reg,#imm12     (unsigned 12-bit immediate)
    cmp   reg,reg | reg,#imm12              (alias: subs xzr/wzr, ...)
    ldr/str reg,[reg]  | reg,[reg,#imm]     (unsigned offset, scaled by size)
    movz/movk/movn reg,#imm16[,#imm-shift]  (shift in 0/16/32/48)
    b/bl/b.cond <patch>                     (imm26 / imm19, PC-relative /4)
    ret  | ret reg  | nop
  Byte-exact vs `aarch64-linux-gnu-as`+objdump oracle, 2026-06-30.
  Deliberately NOT modeled this slice: SP as a distinct register from XZR
  (reg 31 is always treated as the zero register here — SP-relative forms
  need a context flag this slice doesn't carry), logical-immediate ALU
  (AND/ORR/EOR with an immediate — the bitmask-immediate encoding is its own
  can of worms), shifted/extended-register addressing, signed/unscaled
  (LDUR/STUR) loads, paired loads/stores, SIMD/FP.
  See devdocs/developer/asmcore-design.md.

  All bit-packing is done in Int64 (not Cardinal/LongWord — untested under
  this dialect's two compilers; Int64 is proven both under FPC and PXX
  self-host elsewhere in this library) and truncated to 4 bytes on append. }

interface

uses asmcore_base;

const
  reg_x0=0; reg_x1=1; reg_x2=2; reg_x3=3; reg_x4=4; reg_x5=5; reg_x6=6; reg_x7=7;
  reg_x8=8; reg_x9=9; reg_x10=10; reg_x11=11; reg_x12=12; reg_x13=13; reg_x14=14; reg_x15=15;
  reg_x16=16; reg_x17=17; reg_x18=18; reg_x19=19; reg_x20=20; reg_x21=21; reg_x22=22; reg_x23=23;
  reg_x24=24; reg_x25=25; reg_x26=26; reg_x27=27; reg_x28=28; reg_x29=29; reg_x30=30;
  reg_xzr = 31;   { also encodes SP in the few contexts that allow it — not modeled here }

function AsmEncodeAArch64(const instr: TAsmInstr;
                           var buf: TAsmByteBuf;
                           var patches: TAsmPatchList): Boolean;
function AsmPrintAArch64(const instr: TAsmInstr): AnsiString;
function AsmCoreLastErrorAArch64: AnsiString;

{ Resolve one aarch64 branch patch site: relWords is the already-computed
  (target - patch_instr_addr) DIVIDED BY 4 (instructions are 4-byte aligned;
  the frontend computes the byte delta the same way it does for x64 and
  passes the word count here). Read-modify-writes buf.Bytes[offset..+3] —
  must NOT be treated as a raw byte overwrite (unlike x64's Patch32). }
function AsmPatchBranchAArch64(var buf: TAsmByteBuf; offset: Integer;
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

function RegName(reg, size: Integer): AnsiString;
var pfx: AnsiString;
begin
  if (reg < 0) or (reg > 31) then begin Result := '?'; Exit; end;
  if size = 8 then pfx := 'x' else pfx := 'w';
  if reg = 31 then begin Result := pfx + 'zr'; Exit; end;
  Result := pfx + IntToStrAsm(reg);
end;

procedure BufAppendU32(var buf: TAsmByteBuf; w: Int64);
begin
  BufAppend(buf, Byte(w and $FF));
  BufAppend(buf, Byte((w shr 8) and $FF));
  BufAppend(buf, Byte((w shr 16) and $FF));
  BufAppend(buf, Byte((w shr 24) and $FF));
end;

{ ALU shifted-register family (AND/ORR/EOR/ADD/SUB), base64 is the fully-
  formed 64-bit-register opcode word (sf bit set); sf8=False clears bit31
  for the 32-bit (w-register) form — true for every instruction in this
  family, since sf always occupies bit31 alone. }
function EncodeLogicalShiftedReg(base64: Int64; sf8: Boolean;
                                  const rd, rn, rm: TAsmOperand; var buf: TAsmByteBuf): Boolean;
var w: Int64;
begin
  w := base64;
  if not sf8 then w := w and not Int64($80000000);
  w := w or (Int64(rm.Reg) shl 16) or (Int64(rn.Reg) shl 5) or Int64(rd.Reg);
  BufAppendU32(buf, w);
  Result := True;
end;

function EncodeAddSubImm(base64: Int64; sf8: Boolean; imm12: Int64;
                          const rd, rn: TAsmOperand; var buf: TAsmByteBuf): Boolean;
var w: Int64;
begin
  if (imm12 < 0) or (imm12 > 4095) then
  begin LastError := 'asmcore_aarch64: add/sub/cmp immediate must be 0..4095 (unscaled this slice)'; Result := False; Exit; end;
  w := base64;
  if not sf8 then w := w and not Int64($80000000);
  w := w or (imm12 shl 10) or (Int64(rn.Reg) shl 5) or Int64(rd.Reg);
  BufAppendU32(buf, w);
  Result := True;
end;

function EncodeLdrStr(base64: Int64; sf8: Boolean; const rt: TAsmOperand;
                       const mem: TAsmOperand; var buf: TAsmByteBuf): Boolean;
var unitSize: Int64; imm12: Int64; w: Int64;
begin
  unitSize := 4; if sf8 then unitSize := 8;
  if (mem.MemDisp < 0) or ((mem.MemDisp mod unitSize) <> 0) then
  begin LastError := 'asmcore_aarch64: ldr/str offset must be a non-negative multiple of the access size (unsigned-offset form only, this slice)'; Result := False; Exit; end;
  imm12 := mem.MemDisp div unitSize;
  if imm12 > 4095 then
  begin LastError := 'asmcore_aarch64: ldr/str scaled offset out of range'; Result := False; Exit; end;
  { base64 already carries the correct size(2) field for this width — no
    sf-style bit to clear here, the 32-/64-bit bases are independent consts. }
  w := base64 or (imm12 shl 10) or (Int64(mem.MemBase) shl 5) or Int64(rt.Reg);
  BufAppendU32(buf, w);
  Result := True;
end;

function AsmCondAArch64(const s: AnsiString): Integer;
begin
  Result := -1;
  if MnemIs(s,'eq') then Result := 0
  else if MnemIs(s,'ne') then Result := 1
  else if MnemIs(s,'cs') or MnemIs(s,'hs') then Result := 2
  else if MnemIs(s,'cc') or MnemIs(s,'lo') then Result := 3
  else if MnemIs(s,'mi') then Result := 4
  else if MnemIs(s,'pl') then Result := 5
  else if MnemIs(s,'vs') then Result := 6
  else if MnemIs(s,'vc') then Result := 7
  else if MnemIs(s,'hi') then Result := 8
  else if MnemIs(s,'ls') then Result := 9
  else if MnemIs(s,'ge') then Result := 10
  else if MnemIs(s,'lt') then Result := 11
  else if MnemIs(s,'gt') then Result := 12
  else if MnemIs(s,'le') then Result := 13
  else if MnemIs(s,'al') then Result := 14;
end;

{ True + sets cond iff mn is `b.<cc>` (a single dotted token, as produced by
  a frontend that read "b.eq" as one mnemonic — mirrors `as` syntax). }
function AsmIsBCond(const mn: AnsiString; var cond: Integer): Boolean;
begin
  Result := False; cond := -1;
  if (Length(mn) < 3) or ((mn[1] <> 'b') and (mn[1] <> 'B')) or (mn[2] <> '.') then Exit;
  cond := AsmCondAArch64(Copy(mn, 3, Length(mn) - 2));
  Result := cond >= 0;
end;

function AsmEncodeAArch64(const instr: TAsmInstr;
                           var buf: TAsmByteBuf;
                           var patches: TAsmPatchList): Boolean;
var
  d0, d1, d2, zr: TAsmOperand;
  sf8: Boolean;
  cond, hw: Integer;
  shiftVal: Int64;
begin
  LastError := '';
  Result := False;
  zr := RegOp(reg_xzr, 8);

  { ---- zero/one-operand: ret, nop ---- }
  if (instr.OperandCount = 0) and MnemIs(instr.Mnemonic, 'nop') then
  begin BufAppendU32(buf, $D503201F); Result := True; Exit; end;
  if (instr.OperandCount = 0) and MnemIs(instr.Mnemonic, 'ret') then
  begin BufAppendU32(buf, $D65F0000 or (Int64(reg_x30) shl 5)); Result := True; Exit; end;
  if (instr.OperandCount = 1) and MnemIs(instr.Mnemonic, 'ret') then
  begin
    d0 := instr.Operands[0];
    if d0.Kind <> opReg then begin LastError := 'asmcore_aarch64: ret expects a register'; Exit; end;
    BufAppendU32(buf, $D65F0000 or (Int64(d0.Reg) shl 5));
    Result := True; Exit;
  end;

  { ---- branches: b / bl / b.cond <patch> ---- }
  if (instr.OperandCount = 1) and (instr.Operands[0].Kind = opPatch) then
  begin
    if MnemIs(instr.Mnemonic, 'b') then
    begin PatchAdd(patches, buf.Len, 4, 0); BufAppendU32(buf, $14000000); Result := True; Exit; end;
    if MnemIs(instr.Mnemonic, 'bl') then
    begin PatchAdd(patches, buf.Len, 4, 0); BufAppendU32(buf, $94000000); Result := True; Exit; end;
    if AsmIsBCond(instr.Mnemonic, cond) then
    begin PatchAdd(patches, buf.Len, 4, 0); BufAppendU32(buf, $54000000 or Int64(cond)); Result := True; Exit; end;
    LastError := 'asmcore_aarch64: unrecognized branch mnemonic: ' + instr.Mnemonic;
    Exit;
  end;

  { ---- two-operand reg,reg : mov (alias orr Xd,XZR,Xm) / cmp (alias subs zr,Xn,Xm) ---- }
  if (instr.OperandCount = 2) and (instr.Operands[0].Kind = opReg) and (instr.Operands[1].Kind = opReg) then
  begin
    d0 := instr.Operands[0]; d1 := instr.Operands[1];
    sf8 := d0.RegSize = 8;
    if MnemIs(instr.Mnemonic, 'mov') then
    begin Result := EncodeLogicalShiftedReg($AA000000, sf8, d0, zr, d1, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'cmp') then
    begin
      { SUBS (shifted register), Rd = XZR: sf 1 1 01011 shift(2)=00 0 Rm imm6=0 Rn Rd }
      Result := EncodeLogicalShiftedReg($EB000000, sf8, zr, d0, d1, buf); Exit;
    end;
  end;

  { ---- two-operand reg,imm : cmp #imm12 / movz / movn / movk (hw=0) ---- }
  if (instr.OperandCount = 2) and (instr.Operands[0].Kind = opReg) and (instr.Operands[1].Kind = opImm) then
  begin
    d0 := instr.Operands[0]; d1 := instr.Operands[1];
    sf8 := d0.RegSize = 8;
    if MnemIs(instr.Mnemonic, 'cmp') then
    begin Result := EncodeAddSubImm($F1000000, sf8, d1.Imm, zr, d0, buf); Exit; end;
    if (d1.Imm < 0) or (d1.Imm > 65535) then
    begin
      if MnemIs(instr.Mnemonic, 'movz') or MnemIs(instr.Mnemonic, 'movn') or MnemIs(instr.Mnemonic, 'movk') then
      begin LastError := 'asmcore_aarch64: move-wide imm16 out of range'; Exit; end;
    end
    else
    begin
      if MnemIs(instr.Mnemonic, 'movz') then
      begin if sf8 then BufAppendU32(buf, $D2800000 or (d1.Imm shl 5) or Int64(d0.Reg)) else BufAppendU32(buf, $52800000 or (d1.Imm shl 5) or Int64(d0.Reg)); Result := True; Exit; end;
      if MnemIs(instr.Mnemonic, 'movn') then
      begin if sf8 then BufAppendU32(buf, $92800000 or (d1.Imm shl 5) or Int64(d0.Reg)) else BufAppendU32(buf, $12800000 or (d1.Imm shl 5) or Int64(d0.Reg)); Result := True; Exit; end;
      if MnemIs(instr.Mnemonic, 'movk') then
      begin if sf8 then BufAppendU32(buf, $F2800000 or (d1.Imm shl 5) or Int64(d0.Reg)) else BufAppendU32(buf, $72800000 or (d1.Imm shl 5) or Int64(d0.Reg)); Result := True; Exit; end;
    end;
  end;

  { ---- two-operand reg,[mem] : ldr / str (unsigned-offset) ---- }
  if (instr.OperandCount = 2) and (instr.Operands[0].Kind = opReg) and (instr.Operands[1].Kind = opMem) then
  begin
    d0 := instr.Operands[0]; d1 := instr.Operands[1];
    sf8 := d0.RegSize = 8;
    if MnemIs(instr.Mnemonic, 'ldr') then
    begin if sf8 then Result := EncodeLdrStr($F9400000, True, d0, d1, buf) else Result := EncodeLdrStr($B9400000, False, d0, d1, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'str') then
    begin if sf8 then Result := EncodeLdrStr($F9000000, True, d0, d1, buf) else Result := EncodeLdrStr($B9000000, False, d0, d1, buf); Exit; end;
  end;

  { ---- three-operand reg,reg,reg : add/sub/and/orr/eor (shifted-register) ---- }
  if (instr.OperandCount = 3) and (instr.Operands[0].Kind = opReg)
     and (instr.Operands[1].Kind = opReg) and (instr.Operands[2].Kind = opReg) then
  begin
    d0 := instr.Operands[0]; d1 := instr.Operands[1]; d2 := instr.Operands[2];
    sf8 := d0.RegSize = 8;
    if MnemIs(instr.Mnemonic, 'add') then begin Result := EncodeLogicalShiftedReg($8B000000, sf8, d0, d1, d2, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'sub') then begin Result := EncodeLogicalShiftedReg($CB000000, sf8, d0, d1, d2, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'and') then begin Result := EncodeLogicalShiftedReg($8A000000, sf8, d0, d1, d2, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'orr') then begin Result := EncodeLogicalShiftedReg($AA000000, sf8, d0, d1, d2, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'eor') then begin Result := EncodeLogicalShiftedReg($CA000000, sf8, d0, d1, d2, buf); Exit; end;
  end;

  { ---- three-operand reg,reg,imm : add/sub #imm12 ---- }
  if (instr.OperandCount = 3) and (instr.Operands[0].Kind = opReg)
     and (instr.Operands[1].Kind = opReg) and (instr.Operands[2].Kind = opImm) then
  begin
    d0 := instr.Operands[0]; d1 := instr.Operands[1]; d2 := instr.Operands[2];
    sf8 := d0.RegSize = 8;
    if MnemIs(instr.Mnemonic, 'add') then begin Result := EncodeAddSubImm($91000000, sf8, d2.Imm, d0, d1, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'sub') then begin Result := EncodeAddSubImm($D1000000, sf8, d2.Imm, d0, d1, buf); Exit; end;
  end;

  { ---- three-operand reg,imm,imm : movz/movk/movn reg,#imm16,#shift ---- }
  if (instr.OperandCount = 3) and (instr.Operands[0].Kind = opReg)
     and (instr.Operands[1].Kind = opImm) and (instr.Operands[2].Kind = opImm) then
  begin
    d0 := instr.Operands[0]; d1 := instr.Operands[1]; d2 := instr.Operands[2];
    sf8 := d0.RegSize = 8;
    shiftVal := d2.Imm;
    if (shiftVal <> 0) and (shiftVal <> 16) and (shiftVal <> 32) and (shiftVal <> 48) then
    begin LastError := 'asmcore_aarch64: move-wide shift must be 0/16/32/48'; Exit; end;
    if (not sf8) and (shiftVal > 16) then
    begin LastError := 'asmcore_aarch64: move-wide shift must be 0/16 for a 32-bit register'; Exit; end;
    if (d1.Imm < 0) or (d1.Imm > 65535) then begin LastError := 'asmcore_aarch64: move-wide imm16 out of range'; Exit; end;
    hw := shiftVal div 16;
    if MnemIs(instr.Mnemonic, 'movz') then
    begin
      if sf8 then BufAppendU32(buf, $D2800000 or (Int64(hw) shl 21) or (d1.Imm shl 5) or Int64(d0.Reg))
      else BufAppendU32(buf, $52800000 or (Int64(hw) shl 21) or (d1.Imm shl 5) or Int64(d0.Reg));
      Result := True; Exit;
    end;
    if MnemIs(instr.Mnemonic, 'movk') then
    begin
      if sf8 then BufAppendU32(buf, $F2800000 or (Int64(hw) shl 21) or (d1.Imm shl 5) or Int64(d0.Reg))
      else BufAppendU32(buf, $72800000 or (Int64(hw) shl 21) or (d1.Imm shl 5) or Int64(d0.Reg));
      Result := True; Exit;
    end;
    if MnemIs(instr.Mnemonic, 'movn') then
    begin
      if sf8 then BufAppendU32(buf, $92800000 or (Int64(hw) shl 21) or (d1.Imm shl 5) or Int64(d0.Reg))
      else BufAppendU32(buf, $12800000 or (Int64(hw) shl 21) or (d1.Imm shl 5) or Int64(d0.Reg));
      Result := True; Exit;
    end;
  end;

  LastError := 'asmcore_aarch64: unrecognized mnemonic/operand combination: ' + instr.Mnemonic;
  Result := False;
end;

function AsmPatchBranchAArch64(var buf: TAsmByteBuf; offset: Integer;
                                const mnemonic: AnsiString; relWords: Int64): Boolean;
var w: Int64; cond: Integer;
begin
  Result := False;
  w := Int64(buf.Bytes[offset]) or (Int64(buf.Bytes[offset+1]) shl 8)
     or (Int64(buf.Bytes[offset+2]) shl 16) or (Int64(buf.Bytes[offset+3]) shl 24);
  if MnemIs(mnemonic, 'b') or MnemIs(mnemonic, 'bl') then
  begin
    if (relWords < -33554432) or (relWords > 33554431) then
    begin LastError := 'asmcore_aarch64: b/bl target out of imm26 range'; Exit; end;
    w := w or (relWords and $03FFFFFF);
  end
  else if AsmIsBCond(mnemonic, cond) then
  begin
    if (relWords < -262144) or (relWords > 262143) then
    begin LastError := 'asmcore_aarch64: b.cond target out of imm19 range'; Exit; end;
    w := w or ((relWords and $0007FFFF) shl 5);
  end
  else
  begin LastError := 'asmcore_aarch64: not a branch mnemonic: ' + mnemonic; Exit; end;
  buf.Bytes[offset]   := Byte(w and $FF);
  buf.Bytes[offset+1] := Byte((w shr 8) and $FF);
  buf.Bytes[offset+2] := Byte((w shr 16) and $FF);
  buf.Bytes[offset+3] := Byte((w shr 24) and $FF);
  Result := True;
end;

{ ---- textual printer ---- }

function MemText(const m: TAsmOperand): AnsiString;
var s: AnsiString;
begin
  s := '[' + RegName(m.MemBase, 8);
  if m.MemDisp <> 0 then s := s + ', #' + IntToStrAsm(m.MemDisp);
  Result := s + ']';
end;

function OperandText(const op: TAsmOperand): AnsiString;
begin
  case op.Kind of
    opReg: Result := RegName(op.Reg, op.RegSize);
    opImm: Result := '#' + IntToStrAsm(op.Imm);
    opMem: Result := MemText(op);
    opPatch: Result := '<patch>';
  else
    Result := '?';
  end;
end;

function AsmPrintAArch64(const instr: TAsmInstr): AnsiString;
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

function AsmCoreLastErrorAArch64: AnsiString;
begin
  Result := LastError;
end;

end.
