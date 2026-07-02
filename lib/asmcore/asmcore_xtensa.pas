{ SPDX-License-Identifier: Zlib }
unit asmcore_xtensa;
{$mode objfpc}{$H+}
{ xtensa (LX6/LX7, ESP32 family) instruction encoder + textual printer — the
  sixth and final `lib/asmcore` target. Structurally different from every
  prior target in a new way: the base (non-"narrow"/code-density) ISA is
  **24-bit (3-byte), not 32-bit** — this slice deliberately covers only the
  3-byte base forms (real assembly distinguishes them from the 2-byte
  density forms by mnemonic, e.g. `add` vs `add.n`; an assembler doesn't
  silently substitute one for the other, so excluding `.n` forms is a scope
  choice, not an approximation). TAsmByteBuf/TAsmPatchSite needed no changes
  to support a 3-byte instruction width — Width is caller bookkeeping, not
  enforced by asmcore_base, so this target just uses 3 throughout instead
  of 4. Confirms the abstraction generalizes a fifth way.

  Field formulas are taken directly from `compiler/xtensaenc.inc` (this
  compiler's own existing, ESP-hardware-validated typed encoder for xtensa
  codegen — see `make test-esp-bare`), not re-derived from scratch, and
  cross-checked against raw bytes from `xtensa-lx106-elf-as --no-transform`
  (NOTE: `objdump`'s disassembly text shows the instruction as a number,
  MSB-first in the printed string — NOT the literal little-endian memory
  byte order; verified the true byte order via `objcopy -O binary` +
  `xxd`, 2026-06-30 — a real trap for hand-deriving xtensa encodings from
  objdump output alone).

  Branch/jump immediates (J, branches) are relative to the instruction's
  OWN address (`target = PC + 4 + imm`, where PC = this instruction's
  address — no "next instruction" or pipeline-ahead adjustment, the
  simplest of the four PC-relative conventions this library has met:
  x64/aarch64/i386 use next-instruction, arm32 uses +8 pipeline, riscv32
  and xtensa both use "this instruction, +4"). **Unlike** aarch64/arm32/
  riscv32's resolvers (which take a word count pre-divided by 4 — a fit for
  those, since their instructions are uniformly 4-byte and every valid
  branch target lands on a multiple of 4), `AsmPatchBranchXtensa` takes a
  raw **byte** delta (`relBytes = target-(patch+4)`) — xtensa instructions
  here are 3 bytes, so "divide by 4" isn't a meaningful unit and would
  silently go fractional. `relBytes` is exactly what the `.asm` frontend's
  existing generic `Patch32` already computes for x64 — this resolver's
  contract is, if anything, the more natural fit, not a special case.

  Coverage:
    add/sub/and/or/xor    r,s,t        (RRR; r=dest, s/t=operands)
    addi                  t,s,#imm8    (RRI8, signed -128..127)
    movi                  t,#imm12     (RRI8, signed -2048..2047)
    mv                    dst,src       (pseudo: or dst,src,src)
    l32i/s32i              t,[s+#imm]   (RRI8, imm scaled /4, 0..1020)
    j <patch>                            (imm18, byte-relative)
    beq/bne/blt/bge s,t,<patch>          (RRI8-shaped branch, imm8 range)
    ret | nop
  Deliberately NOT modeled: the 2-byte density ("narrow", `.n`-suffixed)
  forms, CALL0/CALL8/CALLX/ENTRY/RETW (windowed-register-ABI specific),
  L8UI/L16UI/L16SI/S8I/S16I (sub-word memory ops — same RRI8 shape as
  L32I/S32I, trivial to add later), FPU/MAC16/integer-mul-div options.
  See devdocs/developer/asmcore-design.md. }

interface

uses asmcore_base;

const
  reg_a0=0; reg_a1=1; reg_a2=2; reg_a3=3; reg_a4=4; reg_a5=5; reg_a6=6; reg_a7=7;
  reg_a8=8; reg_a9=9; reg_a10=10; reg_a11=11; reg_a12=12; reg_a13=13; reg_a14=14; reg_a15=15;
  reg_sp = 1;

function AsmEncodeXtensa(const instr: TAsmInstr;
                          var buf: TAsmByteBuf;
                          var patches: TAsmPatchList): Boolean;
function AsmPrintXtensa(const instr: TAsmInstr): AnsiString;
function AsmCoreLastErrorXtensa: AnsiString;

{ Resolve one xtensa j/branch patch site (a 3-byte instruction, not 4 --
  reads/writes exactly buf.Bytes[offset..offset+2]). Unlike aarch64/arm32/
  riscv32's resolvers, this one takes a raw BYTE delta (relBytes =
  target - (patch_offset+4)), not a word count divided by 4 -- xtensa
  instructions here are 3 bytes, so "divide by 4" isn't a meaningful unit at
  all (a sequence of 3-byte instructions lands on multiples of 3, not 4;
  forcing the word-based convention the 4-byte-fixed-width targets share
  would silently produce fractional/wrong values here). relBytes is exactly
  what the existing `.asm` frontend's generic Patch32 already computes for
  x64 (`target - (patch_offset+4)`) -- this resolver fits that contract
  *more* naturally than the word-based ones do, not less. Converted
  internally to the byte offset xtensa's "PC+4+imm" convention needs. See
  the unit header note. }
function AsmPatchBranchXtensa(var buf: TAsmByteBuf; offset: Integer;
                               const mnemonic: AnsiString; relBytes: Int64): Boolean;

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
  if (reg >= 0) and (reg <= 15) then Result := 'a' + IntToStrAsm(reg)
  else Result := '?';
end;

procedure BufAppendU24(var buf: TAsmByteBuf; w: Int64);
begin
  BufAppend(buf, Byte(w and $FF));
  BufAppend(buf, Byte((w shr 8) and $FF));
  BufAppend(buf, Byte((w shr 16) and $FF));
end;

{ RRR: byte0=(t<<4)|0, byte1=(r<<4)|s, byte2=(op2<<4)|op1. }
function EncodeRRR(op2, op1: Integer; const r, s, t: TAsmOperand; var buf: TAsmByteBuf): Boolean;
var w: Int64;
begin
  w := (Int64(t.Reg) shl 4) or (Int64(r.Reg) shl 12) or (Int64(s.Reg) shl 8) or (Int64(op2) shl 20) or (Int64(op1) shl 16);
  BufAppendU24(buf, w);
  Result := True;
end;

{ RRI8 immediate ALU (addi): byte0=(t<<4)|2, byte1=(0xC<<4)|s, byte2=imm8. }
function EncodeAddi(const t, s: TAsmOperand; imm8: Int64; var buf: TAsmByteBuf): Boolean;
var w: Int64;
begin
  if (imm8 < -128) or (imm8 > 127) then
  begin LastError := 'asmcore_xtensa: addi immediate must be -128..127'; Result := False; Exit; end;
  w := (Int64(t.Reg) shl 4) or 2 or (($C shl 4) shl 8) or (Int64(s.Reg) shl 8) or ((imm8 and $FF) shl 16);
  BufAppendU24(buf, w);
  Result := True;
end;

{ RRI8 movi (12-bit signed split): byte0=(t<<4)|2, byte1=(0xA<<4)|((imm12>>8)&0xF), byte2=imm12&0xFF. }
function EncodeMovi(const t: TAsmOperand; imm12: Int64; var buf: TAsmByteBuf): Boolean;
var w: Int64;
begin
  if (imm12 < -2048) or (imm12 > 2047) then
  begin LastError := 'asmcore_xtensa: movi immediate must be -2048..2047'; Result := False; Exit; end;
  w := (Int64(t.Reg) shl 4) or 2 or ((($A shl 4) or ((imm12 shr 8) and $F)) shl 8) or ((imm12 and $FF) shl 16);
  BufAppendU24(buf, w);
  Result := True;
end;

{ RRI8 memory (l32i/s32i): byte0=(t<<4)|2, byte1=(opMarker<<4)|s, byte2=(offset div 4)&0xFF.
  opMarker: 2=l32i, 6=s32i. }
function EncodeMem32(opMarker: Integer; const t: TAsmOperand; const mem: TAsmOperand; var buf: TAsmByteBuf): Boolean;
var w, scaled: Int64;
begin
  if (mem.MemDisp < 0) or (mem.MemDisp > 1020) or ((mem.MemDisp mod 4) <> 0) then
  begin LastError := 'asmcore_xtensa: l32i/s32i offset must be 0..1020, a multiple of 4'; Result := False; Exit; end;
  scaled := mem.MemDisp div 4;
  w := (Int64(t.Reg) shl 4) or 2 or ((Int64(opMarker) shl 4) shl 8) or (Int64(mem.MemBase) shl 8) or (scaled shl 16);
  BufAppendU24(buf, w);
  Result := True;
end;

function AsmEncodeXtensa(const instr: TAsmInstr;
                          var buf: TAsmByteBuf;
                          var patches: TAsmPatchList): Boolean;
var
  d0, d1, d2: TAsmOperand;
  cond: Integer;
  w: Int64;
begin
  LastError := '';
  Result := False;

  { ---- zero-operand: ret, nop ---- }
  if (instr.OperandCount = 0) and MnemIs(instr.Mnemonic, 'ret') then
  begin BufAppendU24(buf, $000080); Result := True; Exit; end;
  if (instr.OperandCount = 0) and MnemIs(instr.Mnemonic, 'nop') then
  begin BufAppendU24(buf, $0020F0); Result := True; Exit; end;

  { ---- j <patch> ---- }
  if (instr.OperandCount = 1) and (instr.Operands[0].Kind = opPatch) and MnemIs(instr.Mnemonic, 'j') then
  begin PatchAdd(patches, buf.Len, 3, 0); BufAppendU24(buf, 6); Result := True; Exit; end;

  { ---- branches: beq/bne/blt/bge s,t,<patch> ---- }
  if (instr.OperandCount = 3) and (instr.Operands[0].Kind = opReg) and (instr.Operands[1].Kind = opReg)
     and (instr.Operands[2].Kind = opPatch) then
  begin
    cond := -1;
    if MnemIs(instr.Mnemonic, 'beq') then cond := 1
    else if MnemIs(instr.Mnemonic, 'bne') then cond := 9
    else if MnemIs(instr.Mnemonic, 'blt') then cond := 2
    else if MnemIs(instr.Mnemonic, 'bge') then cond := 10;
    if cond < 0 then begin LastError := 'asmcore_xtensa: unrecognized branch mnemonic: ' + instr.Mnemonic; Exit; end;
    d0 := instr.Operands[0]; d1 := instr.Operands[1];
    w := (Int64(cond) shl 12) or (Int64(d0.Reg) shl 8) or (Int64(d1.Reg) shl 4) or 7;
    PatchAdd(patches, buf.Len, 3, 2);
    BufAppendU24(buf, w);
    Result := True; Exit;
  end;

  { ---- mv dst,src (pseudo: or dst,src,src) ---- }
  if (instr.OperandCount = 2) and (instr.Operands[0].Kind = opReg) and (instr.Operands[1].Kind = opReg)
     and MnemIs(instr.Mnemonic, 'mv') then
  begin Result := EncodeRRR(2, 0, instr.Operands[0], instr.Operands[1], instr.Operands[1], buf); Exit; end;

  { ---- movi t,#imm12 ---- }
  if (instr.OperandCount = 2) and (instr.Operands[0].Kind = opReg) and (instr.Operands[1].Kind = opImm)
     and MnemIs(instr.Mnemonic, 'movi') then
  begin Result := EncodeMovi(instr.Operands[0], instr.Operands[1].Imm, buf); Exit; end;

  { ---- l32i/s32i t,[s+#imm] ---- }
  if (instr.OperandCount = 2) and (instr.Operands[0].Kind = opReg) and (instr.Operands[1].Kind = opMem) then
  begin
    d0 := instr.Operands[0]; d1 := instr.Operands[1];
    if MnemIs(instr.Mnemonic, 'l32i') then begin Result := EncodeMem32(2, d0, d1, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 's32i') then begin Result := EncodeMem32(6, d0, d1, buf); Exit; end;
  end;

  { ---- three-operand reg,reg,reg : add/sub/and/or/xor ---- }
  if (instr.OperandCount = 3) and (instr.Operands[0].Kind = opReg)
     and (instr.Operands[1].Kind = opReg) and (instr.Operands[2].Kind = opReg) then
  begin
    d0 := instr.Operands[0]; d1 := instr.Operands[1]; d2 := instr.Operands[2];
    if MnemIs(instr.Mnemonic, 'add') then begin Result := EncodeRRR(8, 0, d0, d1, d2, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'sub') then begin Result := EncodeRRR(12, 0, d0, d1, d2, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'and') then begin Result := EncodeRRR(1, 0, d0, d1, d2, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'or')  then begin Result := EncodeRRR(2, 0, d0, d1, d2, buf); Exit; end;
    if MnemIs(instr.Mnemonic, 'xor') then begin Result := EncodeRRR(3, 0, d0, d1, d2, buf); Exit; end;
  end;

  { ---- three-operand reg,reg,imm : addi ---- }
  if (instr.OperandCount = 3) and (instr.Operands[0].Kind = opReg)
     and (instr.Operands[1].Kind = opReg) and (instr.Operands[2].Kind = opImm)
     and MnemIs(instr.Mnemonic, 'addi') then
  begin Result := EncodeAddi(instr.Operands[0], instr.Operands[1], instr.Operands[2].Imm, buf); Exit; end;

  LastError := 'asmcore_xtensa: unrecognized mnemonic/operand combination: ' + instr.Mnemonic;
  Result := False;
end;

function AsmPatchBranchXtensa(var buf: TAsmByteBuf; offset: Integer;
                               const mnemonic: AnsiString; relBytes: Int64): Boolean;
var w, byteOff, imm: Int64; isJ: Boolean;
begin
  Result := False;
  isJ := MnemIs(mnemonic, 'j');
  if (not isJ) and (not MnemIs(mnemonic, 'beq')) and (not MnemIs(mnemonic, 'bne'))
     and (not MnemIs(mnemonic, 'blt')) and (not MnemIs(mnemonic, 'bge')) then
  begin LastError := 'asmcore_xtensa: not a branch mnemonic: ' + mnemonic; Exit; end;

  byteOff := relBytes + 4;   { undo the generic "target-(patch+4)" frontend convention -> "relative to this instruction" }
  w := Int64(buf.Bytes[offset]) or (Int64(buf.Bytes[offset+1]) shl 8) or (Int64(buf.Bytes[offset+2]) shl 16);

  if isJ then
  begin
    imm := (byteOff - 4);
    if (imm < -131072) or (imm > 131071) then
    begin LastError := 'asmcore_xtensa: j target out of imm18 range'; Exit; end;
    w := w or ((imm and $3FFFF) shl 6);
  end
  else
  begin
    imm := (byteOff - 4);
    if (imm < -128) or (imm > 127) then
    begin LastError := 'asmcore_xtensa: branch target out of imm8 range'; Exit; end;
    w := w or ((imm and $FF) shl 16);
  end;

  buf.Bytes[offset]   := Byte(w and $FF);
  buf.Bytes[offset+1] := Byte((w shr 8) and $FF);
  buf.Bytes[offset+2] := Byte((w shr 16) and $FF);
  Result := True;
end;

{ ---- textual printer ---- }

function MemText(const m: TAsmOperand): AnsiString;
begin
  Result := RegName(m.MemBase) + ', ' + IntToStrAsm(m.MemDisp);
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

function AsmPrintXtensa(const instr: TAsmInstr): AnsiString;
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

function AsmCoreLastErrorXtensa: AnsiString;
begin
  Result := LastError;
end;

end.
