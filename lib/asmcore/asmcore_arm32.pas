unit asmcore_arm32;
{$mode objfpc}{$H+}
{ arm32 (AArch32, A32/ARM-mode) instruction encoder + textual printer — the
  fourth `lib/asmcore` target. Fixed-width 32-bit instructions like aarch64,
  but with two of its own wrinkles neither x64 nor aarch64 have:

  1. Every instruction carries a 4-bit condition-code field (bits[31:28]) —
     execution is predicated, not just branches. `AL` (always, 0xE) is what
     an unconditional instruction encodes as; this slice only emits `AL` for
     non-branch instructions (conditional *data processing* — `addeq`,
     `movne`, etc — is real ARM but out of scope here, matching how this
     library has consistently picked one canonical form per instruction
     rather than the full predication matrix).
  2. **Branch PC-relative arithmetic is offset by one word from every other
     target this library covers.** x64's rel32 and aarch64's imm26/imm19 are
     both `target - address_of_next_instruction` (i.e. `patch_offset + 4`).
     ARM32's `B`/`BL`/`Bcc` imm24 is `(target - (patch_offset + 8)) / 4` —
     the classic 3-stage-pipeline artifact where PC reads as two
     instructions ahead, not one, while an instruction executes. Verified
     against the host oracle (`arm-linux-gnueabi-as`/objdump), 2026-06-30.
     `AsmPatchBranchArm32` below takes `relWords` in the SAME convention
     every other target's resolver uses (`(target - (patch_offset+4)) / 4`,
     what a frontend already computes uniformly) and subtracts 1 word
     internally — so the frontend-facing contract stays uniform across
     targets even though the hardware doesn't.

  Coverage (mirrors the aarch64/x64 tier):
    mov   reg,reg | reg,#imm (rotated-imm8, see EncodeArmImm12)
    add/sub/and/orr/eor  reg,reg,reg | reg,reg,#imm (rotated-imm8)
    cmp   reg,reg | reg,#imm (rotated-imm8)
    ldr/str reg,[reg,#imm0-4095]   (P=1,U=1,W=0 — pre-indexed, positive,
                                     no writeback; the common "[base,#imm]")
    bx reg                          (the real A32 "return" idiom: bx lr)
    b/bl/b<cc> <patch>               (imm24, PC-relative /4, see note above)
    nop                              (the classic pre-ARMv6T2 `mov r0,r0`)
  Byte-exact vs `arm-linux-gnueabi-as`+objdump oracle, 2026-06-30 and
  2026-07-01 (rotated-immediate search, EncodeArmImm12). The immediate
  field is the real ARM 8-bit-value-rotated-right-by-an-even-amount
  encoding (not just raw 0-255) — most "round-looking" 32-bit constants
  (0x10000, 0xFF000000, ...) have a valid rotation; constants that need
  more than 8 significant bits spread non-rotation-adjacently (e.g. 258 =
  0x102) don't, and error clearly rather than silently truncating — real
  `as` falls back to the separate MOVW/MOVT pair there (ARMv6T2+), not
  modeled this slice.
  Deliberately NOT modeled: MOVW/MOVT, Thumb/Thumb2, conditional data-
  processing, shifted-register operands, LDM/STM, SIMD/VFP.
  See devdocs/developer/asmcore-design.md. }

interface

uses asmcore_base;

const
  reg_r0=0; reg_r1=1; reg_r2=2; reg_r3=3; reg_r4=4; reg_r5=5; reg_r6=6; reg_r7=7;
  reg_r8=8; reg_r9=9; reg_r10=10; reg_r11=11; reg_r12=12;
  reg_sp=13; reg_lr=14; reg_pc=15;

function AsmEncodeArm32(const instr: TAsmInstr;
                         var buf: TAsmByteBuf;
                         var patches: TAsmPatchList): Boolean;
function AsmPrintArm32(const instr: TAsmInstr): AnsiString;
function AsmCoreLastErrorArm32: AnsiString;

{ Resolve one arm32 branch patch site. relWords uses the SAME convention
  every other target's resolver does -- (target - (patch_offset+4)) / 4,
  what a frontend already computes uniformly -- the -1-word PC+8 pipeline
  adjustment happens internally. See the unit header note. }
function AsmPatchBranchArm32(var buf: TAsmByteBuf; offset: Integer;
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
  case reg of
    13: Result := 'sp'; 14: Result := 'lr'; 15: Result := 'pc';
  else
    if (reg >= 0) and (reg <= 12) then Result := 'r' + IntToStrAsm(reg)
    else Result := '?';
  end;
end;

procedure BufAppendU32(var buf: TAsmByteBuf; w: Int64);
begin
  BufAppend(buf, Byte(w and $FF));
  BufAppend(buf, Byte((w shr 8) and $FF));
  BufAppend(buf, Byte((w shr 16) and $FF));
  BufAppend(buf, Byte((w shr 24) and $FF));
end;

const
  COND_AL = $E0000000;

function RotateLeft32(v: Int64; n: Integer): Int64;
begin
  v := v and $FFFFFFFF;
  n := n and 31;
  if n = 0 then begin Result := v; Exit; end;
  Result := ((v shl n) or (v shr (32 - n))) and $FFFFFFFF;
end;

{ ARM data-processing immediates encode as ROR(imm8, rotate*2) -- an 8-bit
  value rotated right by an even amount, not a plain 0..255 range. Search
  all 16 even rotations for one that reproduces v exactly (v is treated as
  a 32-bit bit pattern; a negative Int64 is masked to its 32-bit pattern
  first, e.g. -1 -> 0xFFFFFFFF, which DOES have a valid rotated-imm8 form).
  Checking rotField=0 first means a plain 0..255 value always gets the
  canonical rotate=0 encoding, matching what `as` picks. Returns the packed
  12-bit imm12 field (rotate<<8 | imm8) on success. Not every 32-bit value
  has a rotated-imm8 encoding at all (e.g. 258/0x102 doesn't -- real `as`
  falls back to the separate MOVW/MOVT instructions there, ARMv6T2+); this
  slice doesn't model that fallback, see unit header note. }
function EncodeArmImm12(v: Int64; var imm12: Integer): Boolean;
var rotField: Integer; uval, candidate: Int64;
begin
  Result := False;
  uval := v and $FFFFFFFF;
  for rotField := 0 to 15 do
  begin
    candidate := RotateLeft32(uval, rotField * 2);
    if (candidate and (not Int64($FF))) = 0 then
    begin
      imm12 := (rotField shl 8) or Integer(candidate and $FF);
      Result := True;
      Exit;
    end;
  end;
end;

{ Data-processing, register shifter_operand form (no shift):
  cond 00 0 opcode S Rn Rd 00000000 Rm. dpOpcode already includes the I=0
  bit position (bits[24:21]). }
function EncodeDpReg(dpOpcode: Int64; const rd, rn, rm: TAsmOperand; var buf: TAsmByteBuf): Boolean;
var w: Int64;
begin
  w := COND_AL or dpOpcode or (Int64(rn.Reg) shl 16) or (Int64(rd.Reg) shl 12) or Int64(rm.Reg);
  BufAppendU32(buf, w);
  Result := True;
end;

{ Data-processing, immediate form: cond 00 1 opcode S Rn Rd imm12, where
  imm12 packs a rotate field and an 8-bit value (ROR(imm8,rotate*2) == v) --
  see EncodeArmImm12. }
function EncodeDpImm(dpOpcodeImm: Int64; v: Int64; const rd, rn: TAsmOperand; var buf: TAsmByteBuf): Boolean;
var w: Int64; imm12: Integer;
begin
  if not EncodeArmImm12(v, imm12) then
  begin LastError := 'asmcore_arm32: ' + IntToStrAsm(v) + ' has no rotated-imm8 encoding (not every 32-bit value does; MOVW/MOVT not modeled this slice)'; Result := False; Exit; end;
  w := COND_AL or dpOpcodeImm or (Int64(rn.Reg) shl 16) or (Int64(rd.Reg) shl 12) or Int64(imm12);
  BufAppendU32(buf, w);
  Result := True;
end;

function EncodeLdrStr(base: Int64; const rt: TAsmOperand; const mem: TAsmOperand; var buf: TAsmByteBuf): Boolean;
var w: Int64;
begin
  if (mem.MemDisp < 0) or (mem.MemDisp > 4095) then
  begin LastError := 'asmcore_arm32: ldr/str offset must be 0..4095 (positive pre-indexed only, this slice)'; Result := False; Exit; end;
  w := base or (Int64(mem.MemBase) shl 16) or (Int64(rt.Reg) shl 12) or mem.MemDisp;
  BufAppendU32(buf, w);
  Result := True;
end;

function AsmCondArm32(const s: AnsiString): Integer;
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
  else if MnemIs(s,'le') then Result := 13;
end;

{ True + sets cond iff mn is `b<cc>` (no dot, e.g. "beq"/"blt" — the real A32
  convention, unlike aarch64's "b.eq"). Must not match "b" or "bl" exactly
  (checked by the caller first) or any cond-less mnemonic. }
function AsmIsBCond(const mn: AnsiString; var cond: Integer): Boolean;
begin
  Result := False; cond := -1;
  if (Length(mn) < 3) or (Length(mn) > 4) or ((mn[1] <> 'b') and (mn[1] <> 'B')) then Exit;
  cond := AsmCondArm32(Copy(mn, 2, Length(mn) - 1));
  Result := cond >= 0;
end;

function AsmEncodeArm32(const instr: TAsmInstr;
                         var buf: TAsmByteBuf;
                         var patches: TAsmPatchList): Boolean;
var
  d0, d1, d2: TAsmOperand;
  cond: Integer;
begin
  LastError := '';
  Result := False;

  { ---- zero-operand: nop ---- }
  if (instr.OperandCount = 0) and MnemIs(instr.Mnemonic, 'nop') then
  begin BufAppendU32(buf, $E1A00000); Result := True; Exit; end;

  { ---- one-operand: bx reg ---- }
  if (instr.OperandCount = 1) and (instr.Operands[0].Kind = opReg) and MnemIs(instr.Mnemonic, 'bx') then
  begin BufAppendU32(buf, $E12FFF10 or Int64(instr.Operands[0].Reg)); Result := True; Exit; end;

  { ---- branches: b / bl / b<cc> <patch> ---- }
  if (instr.OperandCount = 1) and (instr.Operands[0].Kind = opPatch) then
  begin
    if MnemIs(instr.Mnemonic, 'b') then
    begin PatchAdd(patches, buf.Len, 4, 0); BufAppendU32(buf, $EA000000); Result := True; Exit; end;
    if MnemIs(instr.Mnemonic, 'bl') then
    begin PatchAdd(patches, buf.Len, 4, 0); BufAppendU32(buf, $EB000000); Result := True; Exit; end;
    if AsmIsBCond(instr.Mnemonic, cond) then
    begin PatchAdd(patches, buf.Len, 4, 0); BufAppendU32(buf, (Int64(cond) shl 28) or $0A000000); Result := True; Exit; end;
    LastError := 'asmcore_arm32: unrecognized branch mnemonic: ' + instr.Mnemonic;
    Exit;
  end;

  { ---- two-operand reg,reg : mov / cmp ---- }
  if (instr.OperandCount = 2) and (instr.Operands[0].Kind = opReg) and (instr.Operands[1].Kind = opReg) then
  begin
    d0 := instr.Operands[0]; d1 := instr.Operands[1];
    if MnemIs(instr.Mnemonic, 'mov') then
    begin d2.Reg := 0; Result := EncodeDpReg($01A00000, d0, d2, d1, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'cmp') then
    begin d2.Reg := 0; Result := EncodeDpReg($01500000, d2, d0, d1, buf); Exit; end;
  end;

  { ---- two-operand reg,imm : mov / cmp ---- }
  if (instr.OperandCount = 2) and (instr.Operands[0].Kind = opReg) and (instr.Operands[1].Kind = opImm) then
  begin
    d0 := instr.Operands[0]; d1 := instr.Operands[1];
    if MnemIs(instr.Mnemonic, 'mov') then
    begin d2.Reg := 0; Result := EncodeDpImm($03A00000, d1.Imm, d0, d2, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'cmp') then
    begin d2.Reg := 0; Result := EncodeDpImm($03500000, d1.Imm, d2, d0, buf); Exit; end;
  end;

  { ---- two-operand reg,[mem] : ldr / str ---- }
  if (instr.OperandCount = 2) and (instr.Operands[0].Kind = opReg) and (instr.Operands[1].Kind = opMem) then
  begin
    d0 := instr.Operands[0]; d1 := instr.Operands[1];
    if MnemIs(instr.Mnemonic, 'ldr') then begin Result := EncodeLdrStr($E5900000, d0, d1, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'str') then begin Result := EncodeLdrStr($E5800000, d0, d1, buf); Exit; end;
  end;

  { ---- three-operand reg,reg,reg : add/sub/and/orr/eor ---- }
  if (instr.OperandCount = 3) and (instr.Operands[0].Kind = opReg)
     and (instr.Operands[1].Kind = opReg) and (instr.Operands[2].Kind = opReg) then
  begin
    d0 := instr.Operands[0]; d1 := instr.Operands[1]; d2 := instr.Operands[2];
    if MnemIs(instr.Mnemonic, 'add') then begin Result := EncodeDpReg($00800000, d0, d1, d2, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'sub') then begin Result := EncodeDpReg($00400000, d0, d1, d2, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'and') then begin Result := EncodeDpReg($00000000, d0, d1, d2, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'orr') then begin Result := EncodeDpReg($01800000, d0, d1, d2, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'eor') then begin Result := EncodeDpReg($00200000, d0, d1, d2, buf); Exit; end;
  end;

  { ---- three-operand reg,reg,imm : add/sub/and/orr/eor #imm ---- }
  if (instr.OperandCount = 3) and (instr.Operands[0].Kind = opReg)
     and (instr.Operands[1].Kind = opReg) and (instr.Operands[2].Kind = opImm) then
  begin
    d0 := instr.Operands[0]; d1 := instr.Operands[1]; d2 := instr.Operands[2];
    if MnemIs(instr.Mnemonic, 'add') then begin Result := EncodeDpImm($02800000, d2.Imm, d0, d1, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'sub') then begin Result := EncodeDpImm($02400000, d2.Imm, d0, d1, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'and') then begin Result := EncodeDpImm($02000000, d2.Imm, d0, d1, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'orr') then begin Result := EncodeDpImm($03800000, d2.Imm, d0, d1, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'eor') then begin Result := EncodeDpImm($02200000, d2.Imm, d0, d1, buf); Exit; end;
  end;

  LastError := 'asmcore_arm32: unrecognized mnemonic/operand combination: ' + instr.Mnemonic;
  Result := False;
end;

function AsmPatchBranchArm32(var buf: TAsmByteBuf; offset: Integer;
                              const mnemonic: AnsiString; relWords: Int64): Boolean;
var w, armWords: Int64; cond: Integer;
begin
  Result := False;
  if not (MnemIs(mnemonic, 'b') or MnemIs(mnemonic, 'bl') or AsmIsBCond(mnemonic, cond)) then
  begin LastError := 'asmcore_arm32: not a branch mnemonic: ' + mnemonic; Exit; end;
  armWords := relWords - 1;   { PC reads as instr_addr+8, one word past every other target's convention }
  if (armWords < -8388608) or (armWords > 8388607) then
  begin LastError := 'asmcore_arm32: branch target out of imm24 range'; Exit; end;
  w := Int64(buf.Bytes[offset]) or (Int64(buf.Bytes[offset+1]) shl 8)
     or (Int64(buf.Bytes[offset+2]) shl 16) or (Int64(buf.Bytes[offset+3]) shl 24);
  w := w or (armWords and $00FFFFFF);
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
  s := '[' + RegName(m.MemBase);
  if m.MemDisp <> 0 then s := s + ', #' + IntToStrAsm(m.MemDisp);
  Result := s + ']';
end;

function OperandText(const op: TAsmOperand): AnsiString;
begin
  case op.Kind of
    opReg: Result := RegName(op.Reg);
    opImm: Result := '#' + IntToStrAsm(op.Imm);
    opMem: Result := MemText(op);
    opPatch: Result := '<patch>';
  else
    Result := '?';
  end;
end;

function AsmPrintArm32(const instr: TAsmInstr): AnsiString;
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

function AsmCoreLastErrorArm32: AnsiString;
begin
  Result := LastError;
end;

end.
