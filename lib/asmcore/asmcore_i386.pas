unit asmcore_i386;
{$mode objfpc}{$H+}
{ i386 instruction encoder + textual printer — the third `lib/asmcore`
  target, mechanical per the ticket's own sequencing ("i386... mostly x86-64
  with the lid off"). Confirmed empirically (host `as --32`/objdump oracle,
  2026-06-30): identical opcode bytes to asmcore_x64.pas for every
  instruction in this slice, just with REX/W stripped — no new bit layouts,
  no new patch contract. Unlike aarch64 (see asmcore_aarch64.pas + the
  design doc's "branch patch resolution is target-specific" section), i386
  branch immediates ARE a separate trailing byte-aligned rel32 field exactly
  like x64's, so the existing generic raw-overwrite patch resolution
  (Patch32, already used by the `.asm` frontend and inline-asm) works
  unchanged — no AsmPatchBranchI386 needed.

  Coverage (mirrors asmcore_x64's current tier, minus anything REX-only):
    mov   reg,imm | reg,reg | reg,[base+disp] | [base+disp],reg
    lea   reg,[base+disp]
    add/sub/and/or/xor/cmp  reg,reg | reg,imm
    test  reg,reg
    imul  reg,reg
    inc/dec/neg/not  reg
    push/pop  reg
    ret | nop | leave | cdq
    jmp/call  <patch>      (rel32 patch site)
    je/jne/jz/jnz/jl/jge/jle/jg/jb/jae/jbe/ja/js/jns  <patch>  (rel32)
  Byte-exact vs `as --32`/objdump (.intel_syntax noprefix) oracle, 2026-06-30.
  One real divergence from the x64 encoder: inc/dec r32 use the 1-byte short
  form (40+r / 48+r), available only in 32-bit mode (those bytes are REX
  prefixes in long mode, so x64 has to use the longer FF /digit form) --
  `as` picks it by default, matched here rather than the also-valid FF form.
  i386 has only 8 GP registers (0-7, no r8-r15, no REX) and one operand
  width that matters here (32-bit; RegOp's `size` field is accepted but only
  4 is exercised/tested this slice — 16-bit via an 0x66 prefix is deferred).
  See devdocs/developer/asmcore-design.md. }

interface

uses asmcore_base;

const
  reg_eax = 0; reg_ecx = 1; reg_edx = 2; reg_ebx = 3;
  reg_esp = 4; reg_ebp = 5; reg_esi = 6; reg_edi = 7;

function AsmEncodeI386(const instr: TAsmInstr;
                        var buf: TAsmByteBuf;
                        var patches: TAsmPatchList): Boolean;
function AsmPrintI386(const instr: TAsmInstr): AnsiString;
function AsmCoreLastErrorI386: AnsiString;

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

function RegName(reg: Integer): AnsiString;
begin
  case reg of
    0: Result := 'eax'; 1: Result := 'ecx'; 2: Result := 'edx'; 3: Result := 'ebx';
    4: Result := 'esp'; 5: Result := 'ebp'; 6: Result := 'esi'; 7: Result := 'edi';
  else
    Result := '?';
  end;
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

function FitsI8(v: Int64): Boolean;
begin
  Result := (v >= -128) and (v <= 127);
end;

{ ModRM + (SIB) + disp for [base+disp] (no index this slice). regField is
  the /r register or /digit opcode-extension, already 0..7 (no REX.R/.X/.B
  ever applies — i386 has nothing past register 7). }
procedure EmitModRMMem(var buf: TAsmByteBuf; regField: Integer; const m: TAsmOperand);
var base, rm, modBits: Integer; needSib, forceDisp8: Boolean;
begin
  base := m.MemBase;
  rm := base and 7;
  needSib := (rm = 4);                          { esp -> SIB with no-index }
  forceDisp8 := (rm = 5) and (m.MemDisp = 0);    { ebp has no disp-less form }

  if (m.MemDisp = 0) and (not forceDisp8) then modBits := 0
  else if FitsI8(m.MemDisp) then modBits := 1
  else modBits := 2;

  BufAppend(buf, Byte((modBits shl 6) or (regField shl 3) or rm));
  if needSib then BufAppend(buf, $24);

  if modBits = 1 then BufAppend(buf, Byte(m.MemDisp and $FF))
  else if modBits = 2 then BufAppendI32(buf, m.MemDisp);
end;

function AluOpcodeRR(const mnem: AnsiString; var op: Integer): Boolean;
begin
  Result := True;
  if MnemIs(mnem, 'add') then op := $01
  else if MnemIs(mnem, 'or')  then op := $09
  else if MnemIs(mnem, 'and') then op := $21
  else if MnemIs(mnem, 'sub') then op := $29
  else if MnemIs(mnem, 'xor') then op := $31
  else if MnemIs(mnem, 'cmp') then op := $39
  else Result := False;
end;

function AluDigit(const mnem: AnsiString; var dig: Integer): Boolean;
begin
  Result := True;
  if MnemIs(mnem, 'add') then dig := 0
  else if MnemIs(mnem, 'or')  then dig := 1
  else if MnemIs(mnem, 'and') then dig := 4
  else if MnemIs(mnem, 'sub') then dig := 5
  else if MnemIs(mnem, 'xor') then dig := 6
  else if MnemIs(mnem, 'cmp') then dig := 7
  else Result := False;
end;

function JccCond(const mnem: AnsiString): Integer;
begin
  if MnemIs(mnem, 'jo')  then JccCond := $0
  else if MnemIs(mnem, 'jno') then JccCond := $1
  else if MnemIs(mnem, 'jb')  or MnemIs(mnem, 'jc')  or MnemIs(mnem, 'jnae') then JccCond := $2
  else if MnemIs(mnem, 'jae') or MnemIs(mnem, 'jnb') or MnemIs(mnem, 'jnc')  then JccCond := $3
  else if MnemIs(mnem, 'je')  or MnemIs(mnem, 'jz')  then JccCond := $4
  else if MnemIs(mnem, 'jne') or MnemIs(mnem, 'jnz') then JccCond := $5
  else if MnemIs(mnem, 'jbe') or MnemIs(mnem, 'jna') then JccCond := $6
  else if MnemIs(mnem, 'ja')  or MnemIs(mnem, 'jnbe') then JccCond := $7
  else if MnemIs(mnem, 'js')  then JccCond := $8
  else if MnemIs(mnem, 'jns') then JccCond := $9
  else if MnemIs(mnem, 'jp')  or MnemIs(mnem, 'jpe') then JccCond := $A
  else if MnemIs(mnem, 'jnp') or MnemIs(mnem, 'jpo') then JccCond := $B
  else if MnemIs(mnem, 'jl')  or MnemIs(mnem, 'jnge') then JccCond := $C
  else if MnemIs(mnem, 'jge') or MnemIs(mnem, 'jnl')  then JccCond := $D
  else if MnemIs(mnem, 'jle') or MnemIs(mnem, 'jng')  then JccCond := $E
  else if MnemIs(mnem, 'jg')  or MnemIs(mnem, 'jnle') then JccCond := $F
  else JccCond := -1;
end;

function EncodeMovRegImm(const dst, src: TAsmOperand; var buf: TAsmByteBuf): Boolean;
begin
  BufAppend(buf, Byte($B8 + (dst.Reg and 7)));
  BufAppendI32(buf, src.Imm);
  Result := True;
end;

function EncodeRMReg(opcode: Integer; const dst, src: TAsmOperand; var buf: TAsmByteBuf): Boolean;
begin
  BufAppend(buf, Byte(opcode));
  BufAppend(buf, Byte(($03 shl 6) or ((src.Reg and 7) shl 3) or (dst.Reg and 7)));
  Result := True;
end;

function EncodeAluRegImm(dig: Integer; const dst, src: TAsmOperand; var buf: TAsmByteBuf): Boolean;
begin
  if FitsI8(src.Imm) then
  begin
    BufAppend(buf, $83);
    BufAppend(buf, Byte(($03 shl 6) or (dig shl 3) or (dst.Reg and 7)));
    BufAppend(buf, Byte(src.Imm and $FF));
  end
  else
  begin
    BufAppend(buf, $81);
    BufAppend(buf, Byte(($03 shl 6) or (dig shl 3) or (dst.Reg and 7)));
    BufAppendI32(buf, src.Imm);
  end;
  Result := True;
end;

function EncodeRegMem(opcode: Integer; const regOp, memOp: TAsmOperand; var buf: TAsmByteBuf): Boolean;
begin
  BufAppend(buf, Byte(opcode));
  EmitModRMMem(buf, regOp.Reg and 7, memOp);
  Result := True;
end;

function EncodeUnary(digit, opByte: Integer; const dst: TAsmOperand; var buf: TAsmByteBuf): Boolean;
begin
  BufAppend(buf, Byte(opByte));
  BufAppend(buf, Byte(($03 shl 6) or (digit shl 3) or (dst.Reg and 7)));
  Result := True;
end;

function EncodePushPop(base: Integer; const r: TAsmOperand; var buf: TAsmByteBuf): Boolean;
begin
  BufAppend(buf, Byte(base + (r.Reg and 7)));
  Result := True;
end;

procedure EncodeRel32(var buf: TAsmByteBuf; var patches: TAsmPatchList; opIndex: Integer);
begin
  PatchAdd(patches, buf.Len, 4, opIndex);
  BufAppendI32(buf, 0);
end;

function AsmEncodeI386(const instr: TAsmInstr;
                        var buf: TAsmByteBuf;
                        var patches: TAsmPatchList): Boolean;
var
  d0, d1: TAsmOperand;
  aluOp, dig, cond: Integer;
begin
  LastError := '';
  Result := False;

  { ---- zero-operand ---- }
  if instr.OperandCount = 0 then
  begin
    if MnemIs(instr.Mnemonic, 'ret') then begin BufAppend(buf, $C3); Result := True; Exit; end;
    if MnemIs(instr.Mnemonic, 'nop') then begin BufAppend(buf, $90); Result := True; Exit; end;
    if MnemIs(instr.Mnemonic, 'leave') then begin BufAppend(buf, $C9); Result := True; Exit; end;
    if MnemIs(instr.Mnemonic, 'cdq') then begin BufAppend(buf, $99); Result := True; Exit; end;
    LastError := 'asmcore_i386: unknown zero-operand mnemonic: ' + instr.Mnemonic;
    Exit;
  end;

  { ---- one-operand ---- }
  if instr.OperandCount = 1 then
  begin
    d0 := instr.Operands[0];
    if d0.Kind = opPatch then
    begin
      if MnemIs(instr.Mnemonic, 'jmp') then
      begin BufAppend(buf, $E9); EncodeRel32(buf, patches, 0); Result := True; Exit; end;
      if MnemIs(instr.Mnemonic, 'call') then
      begin BufAppend(buf, $E8); EncodeRel32(buf, patches, 0); Result := True; Exit; end;
      cond := JccCond(instr.Mnemonic);
      if cond >= 0 then
      begin
        BufAppend(buf, $0F); BufAppend(buf, Byte($80 + cond));
        EncodeRel32(buf, patches, 0); Result := True; Exit;
      end;
      LastError := 'asmcore_i386: mnemonic does not take a branch target: ' + instr.Mnemonic;
      Exit;
    end;
    if d0.Kind = opReg then
    begin
      if MnemIs(instr.Mnemonic, 'push') then begin Result := EncodePushPop($50, d0, buf); Exit; end;
      if MnemIs(instr.Mnemonic, 'pop')  then begin Result := EncodePushPop($58, d0, buf); Exit; end;
      { inc/dec r32 has a 1-byte short form in 32-bit mode (40+r / 48+r) that
        doesn't exist in long mode (those bytes are REX prefixes there) --
        `as` picks it by default; match it rather than the longer FF /digit
        form (also valid, just not idiomatic). }
      if MnemIs(instr.Mnemonic, 'inc') then begin BufAppend(buf, Byte($40 + (d0.Reg and 7))); Result := True; Exit; end;
      if MnemIs(instr.Mnemonic, 'dec') then begin BufAppend(buf, Byte($48 + (d0.Reg and 7))); Result := True; Exit; end;
      if MnemIs(instr.Mnemonic, 'not') then begin Result := EncodeUnary(2, $F7, d0, buf); Exit; end;
      if MnemIs(instr.Mnemonic, 'neg') then begin Result := EncodeUnary(3, $F7, d0, buf); Exit; end;
      if MnemIs(instr.Mnemonic, 'mul') then begin Result := EncodeUnary(4, $F7, d0, buf); Exit; end;
      if MnemIs(instr.Mnemonic, 'imul') then begin Result := EncodeUnary(5, $F7, d0, buf); Exit; end;
      if MnemIs(instr.Mnemonic, 'div') then begin Result := EncodeUnary(6, $F7, d0, buf); Exit; end;
      if MnemIs(instr.Mnemonic, 'idiv') then begin Result := EncodeUnary(7, $F7, d0, buf); Exit; end;
    end;
    LastError := 'asmcore_i386: unsupported one-operand form: ' + instr.Mnemonic;
    Exit;
  end;

  { ---- two-operand ---- }
  if instr.OperandCount = 2 then
  begin
    d0 := instr.Operands[0];
    d1 := instr.Operands[1];

    if MnemIs(instr.Mnemonic, 'mov') then
    begin
      if (d0.Kind = opReg) and (d1.Kind = opImm) then begin Result := EncodeMovRegImm(d0, d1, buf); Exit; end;
      if (d0.Kind = opReg) and (d1.Kind = opReg) then begin Result := EncodeRMReg($89, d0, d1, buf); Exit; end;
      if (d0.Kind = opReg) and (d1.Kind = opMem) then begin Result := EncodeRegMem($8B, d0, d1, buf); Exit; end;
      if (d0.Kind = opMem) and (d1.Kind = opReg) then begin Result := EncodeRegMem($89, d1, d0, buf); Exit; end;
      LastError := 'asmcore_i386: unsupported mov operand combination';
      Exit;
    end;

    if MnemIs(instr.Mnemonic, 'lea') then
    begin
      if (d0.Kind = opReg) and (d1.Kind = opMem) then begin Result := EncodeRegMem($8D, d0, d1, buf); Exit; end;
      LastError := 'asmcore_i386: lea expects reg, [mem]';
      Exit;
    end;

    if MnemIs(instr.Mnemonic, 'test') then
    begin
      if (d0.Kind = opReg) and (d1.Kind = opReg) then begin Result := EncodeRMReg($85, d0, d1, buf); Exit; end;
      LastError := 'asmcore_i386: test expects reg, reg (this slice)';
      Exit;
    end;

    if MnemIs(instr.Mnemonic, 'imul') then
    begin
      if (d0.Kind = opReg) and (d1.Kind = opReg) then
      begin
        BufAppend(buf, $0F); BufAppend(buf, $AF);
        BufAppend(buf, Byte(($03 shl 6) or ((d0.Reg and 7) shl 3) or (d1.Reg and 7)));
        Result := True; Exit;
      end;
      LastError := 'asmcore_i386: imul reg,reg only (this slice)';
      Exit;
    end;

    if AluOpcodeRR(instr.Mnemonic, aluOp) then
    begin
      if (d0.Kind = opReg) and (d1.Kind = opReg) then begin Result := EncodeRMReg(aluOp, d0, d1, buf); Exit; end;
      if (d0.Kind = opReg) and (d1.Kind = opImm) then
      begin
        AluDigit(instr.Mnemonic, dig);
        Result := EncodeAluRegImm(dig, d0, d1, buf);
        Exit;
      end;
      LastError := 'asmcore_i386: unsupported ALU operand combination for ' + instr.Mnemonic;
      Exit;
    end;
  end;

  LastError := 'asmcore_i386: unrecognized mnemonic/operand combination: ' + instr.Mnemonic;
  Result := False;
end;

{ ---- textual printer ---- }

function MemText(const m: TAsmOperand): AnsiString;
var s: AnsiString;
begin
  s := '[' + RegName(m.MemBase);
  if m.MemDisp > 0 then s := s + '+' + IntToStrAsm(m.MemDisp)
  else if m.MemDisp < 0 then s := s + IntToStrAsm(m.MemDisp);
  Result := s + ']';
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

function AsmPrintI386(const instr: TAsmInstr): AnsiString;
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

function AsmCoreLastErrorI386: AnsiString;
begin
  Result := LastError;
end;

end.
