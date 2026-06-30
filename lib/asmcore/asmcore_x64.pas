unit asmcore_x64;
{$mode objfpc}{$H+}
{ x86-64 instruction encoder + textual printer.
  Coverage (Intel syntax, dst-first):
    mov   reg,imm | reg,reg | reg,[mem] | [mem],reg
    lea   reg,[mem]
    add/sub/and/or/xor/cmp  reg,reg | reg,imm
    test  reg,reg
    imul  reg,reg
    inc/dec/neg/not  reg
    push/pop  reg
    ret | syscall | nop | leave | cqo | cdq
    jmp/call  <patch>      (rel32 patch site)
    je/jne/jz/jnz/jl/jge/jle/jg/jb/jae/jbe/ja/js/jns  <patch>  (rel32 patch site)
  [mem] = MemOp(base,disp) `[base+disp]` or MemOpIndexed(base,index,scale,disp)
  full SIB `[base+index*scale+disp]` (scale 1/2/4/8; base=-1 for the
  base-less `[index*scale+disp]` form; rsp can't be an index — that bit
  pattern means "no index", so it's rejected rather than silently dropped).
  REG_RIP (asmcore's rip-relative sentinel, base=-2) cannot carry an index.
  Byte-exact vs host `as`+objdump, 2026-07-01.
  Branch targets are PatchOp(4): asmcore emits opcode + 4 zero bytes and records
  a patch site at the rel32 offset; layer 2 (the .asm frontend / structured-ir
  library) resolves the label to (target - instr_end) and fills it.
  See devdocs/developer/asmcore-design.md. }

interface

uses asmcore_base;

const
  reg_rax = 0; reg_rcx = 1; reg_rdx = 2; reg_rbx = 3;
  reg_rsp = 4; reg_rbp = 5; reg_rsi = 6; reg_rdi = 7;
  reg_r8  = 8; reg_r9  = 9; reg_r10 = 10; reg_r11 = 11;
  reg_r12 = 12; reg_r13 = 13; reg_r14 = 14; reg_r15 = 15;
  { MemOp(REG_RIP, 0) means "rip-relative, disp32 is a patch site" — the
    layer-1 opaque-patch-marker the design doc calls for, not a label name;
    layer 2 (the .asm frontend) resolves the disp the same way it resolves
    branch targets: target - (patch_offset + 4). }
  REG_RIP = -2;

function AsmEncodeX64(const instr: TAsmInstr;
                       var buf: TAsmByteBuf;
                       var patches: TAsmPatchList): Boolean;
function AsmPrintX64(const instr: TAsmInstr): AnsiString;
function AsmCoreLastError: AnsiString;

implementation

var
  LastError: AnsiString;

{ Local mnemonic compare — deliberately not pulling in sysutils' LowerCase
  just to keep asmcore dependency-free (uses asmcore_base only). }
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

{ Plain if-chain, not a typed const array of AnsiString — that construct is
  broken in the pinned stable compiler for multi-char string elements (see
  devdocs/progress/backlog/bug-typed-const-array-of-string-broken.md). }
function RegName(reg, size: Integer): AnsiString;
begin
  if (reg < 0) or (reg > 15) then begin Result := '?'; Exit; end;
  if size = 8 then
  begin
    case reg of
      0: Result := 'rax'; 1: Result := 'rcx'; 2: Result := 'rdx'; 3: Result := 'rbx';
      4: Result := 'rsp'; 5: Result := 'rbp'; 6: Result := 'rsi'; 7: Result := 'rdi';
      8: Result := 'r8';  9: Result := 'r9';  10: Result := 'r10'; 11: Result := 'r11';
      12: Result := 'r12'; 13: Result := 'r13'; 14: Result := 'r14'; 15: Result := 'r15';
    end;
  end
  else
  begin
    case reg of
      0: Result := 'eax'; 1: Result := 'ecx'; 2: Result := 'edx'; 3: Result := 'ebx';
      4: Result := 'esp'; 5: Result := 'ebp'; 6: Result := 'esi'; 7: Result := 'edi';
      8: Result := 'r8d';  9: Result := 'r9d';  10: Result := 'r10d'; 11: Result := 'r11d';
      12: Result := 'r12d'; 13: Result := 'r13d'; 14: Result := 'r14d'; 15: Result := 'r15d';
    end;
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

{ REX prefix: 0100WRXB. Emits nothing if none of W/R/X/B are needed. }
procedure EmitRex(var buf: TAsmByteBuf; w, r, x, b: Boolean);
var rex: Integer;
begin
  if not (w or r or x or b) then Exit;
  rex := $40;
  if w then rex := rex or $08;
  if r then rex := rex or $04;
  if x then rex := rex or $02;
  if b then rex := rex or $01;
  BufAppend(buf, Byte(rex));
end;

function FitsI8(v: Int64): Boolean;
begin
  Result := (v >= -128) and (v <= 127);
end;

{ ModRM + (SIB) + disp for a memory operand: plain [base+disp], SIB
  [base+index*scale+disp] when MemIndex<>-1, or the base-less SIB form
  [index*scale+disp] when MemBase=-1 (base field forced to 101, mod=00,
  disp32 mandatory — the dedicated "no base register" encoding, distinct
  from rbp/r13's "no disp-less form" special case below). regField is the
  /r register or /digit opcode extension already masked to 0..7. Caller has
  already emitted any REX (incl. REX.X for the index register, where
  applicable — see EncodeRegMem). }
procedure EmitModRMMem(var buf: TAsmByteBuf; regField: Integer; const m: TAsmOperand);
var rmField, modBits, scaleBits, sibIndex, sibBase: Integer; needSib, noBase, forceDisp8: Boolean;
begin
  noBase := (m.MemBase = -1) and (m.MemIndex <> -1);
  needSib := noBase or (m.MemIndex <> -1) or ((m.MemBase and 7) = 4);  { index present, or rsp/r12 base }

  if needSib then rmField := 4 else rmField := m.MemBase and 7;

  if noBase then
    modBits := 0   { base=101 + mod=00 is the dedicated no-base SIB form; disp32 is mandatory }
  else
  begin
    forceDisp8 := ((m.MemBase and 7) = 5) and (m.MemDisp = 0);  { rbp/r13 (SIB or not) has no disp-less form }
    if (m.MemDisp = 0) and (not forceDisp8) then modBits := 0
    else if FitsI8(m.MemDisp) then modBits := 1
    else modBits := 2;
  end;

  BufAppend(buf, Byte((modBits shl 6) or (regField shl 3) or rmField));

  if needSib then
  begin
    case m.MemScale of
      2: scaleBits := 1;
      4: scaleBits := 2;
      8: scaleBits := 3;
    else
      scaleBits := 0;
    end;
    if m.MemIndex = -1 then sibIndex := 4 else sibIndex := m.MemIndex and 7;  { 100 = no index }
    if noBase then sibBase := 5 else sibBase := m.MemBase and 7;
    BufAppend(buf, Byte((scaleBits shl 6) or (sibIndex shl 3) or sibBase));
  end;

  if modBits = 1 then BufAppend(buf, Byte(m.MemDisp and $FF))
  else if (modBits = 2) or noBase then BufAppendI32(buf, m.MemDisp);
end;

{ ALU "op r/m, r" primary opcode (32/64-bit form, dst=r/m src=reg). }
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

{ ALU "op r/m, imm32" /digit extension for the 81 /digit form. }
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

{ jcc tttn condition nibble for the 0F 8x rel32 form (returns -1 if not a jcc). }
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

{ ---- per-family encoders ---- }

function EncodeMovRegImm(const dst, src: TAsmOperand; var buf: TAsmByteBuf): Boolean;
begin
  Result := False;
  EmitRex(buf, dst.RegSize = 8, False, False, dst.Reg >= 8);
  BufAppend(buf, Byte($B8 + (dst.Reg and 7)));
  if dst.RegSize = 8 then BufAppendI64(buf, src.Imm) else BufAppendI32(buf, src.Imm);
  Result := True;
end;

{ op r/m, r  (dst=r/m, src=reg). Used by ALU reg,reg, mov reg,reg, test. }
function EncodeRMReg(opcode: Integer; w: Boolean;
                     const dst, src: TAsmOperand; var buf: TAsmByteBuf): Boolean;
begin
  EmitRex(buf, w, src.Reg >= 8, False, dst.Reg >= 8);
  BufAppend(buf, Byte(opcode));
  BufAppend(buf, Byte(($03 shl 6) or ((src.Reg and 7) shl 3) or (dst.Reg and 7)));
  Result := True;
end;

{ ALU reg,imm: prefer the compact 83 /digit imm8 form when the immediate fits a
  signed byte (what `as` picks too); else 81 /digit imm32. The AL/AX/EAX/RAX
  short special-case opcodes (05/2D/25/...) are deliberately not used — the
  general /digit form is equally valid and keeps the encoder uniform. }
function EncodeAluRegImm(dig: Integer; const dst, src: TAsmOperand; var buf: TAsmByteBuf): Boolean;
begin
  EmitRex(buf, dst.RegSize = 8, False, False, dst.Reg >= 8);
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

{ mov/lea between a register and [base+disp] or [base+index*scale+disp].
  memIsDst selects direction for mov; lea is always reg<-mem. opcode is the
  base (89 mov r/m,r ; 8B mov r,r/m ; 8D lea r,m). The reg operand supplies
  REX.W/R; the mem base supplies REX.B; the mem index (when present)
  supplies REX.X. rsp (4) can't be a SIB index — that bit pattern is the
  dedicated "no index" encoding, so passing it would silently produce a
  plain [base+disp] instead of erroring on the caller's actual mistake. }
function EncodeRegMem(opcode: Integer; const regOp, memOp: TAsmOperand;
                      var buf: TAsmByteBuf): Boolean;
begin
  Result := False;
  if (memOp.Kind = opMem) and (memOp.MemIndex = 4) then
  begin LastError := 'asmcore_x64: rsp cannot be a SIB index register'; Exit; end;
  EmitRex(buf, regOp.RegSize = 8, regOp.Reg >= 8, memOp.MemIndex >= 8, memOp.MemBase >= 8);
  BufAppend(buf, Byte(opcode));
  EmitModRMMem(buf, regOp.Reg and 7, memOp);
  Result := True;
end;

{ mov/lea reg, [rip+disp32] — a rip-relative patch site (REG_RIP sentinel).
  No base register is encoded (ModRM rm=101 with mod=00 means RIP-relative,
  not "no base"); REX.B is never set for this form. }
function EncodeRegMemPatch(opcode: Integer; const regOp, memOp: TAsmOperand;
                            var buf: TAsmByteBuf; var patches: TAsmPatchList;
                            opIndex: Integer): Boolean;
begin
  Result := False;
  if (memOp.MemBase = REG_RIP) and (memOp.MemIndex <> -1) then
  begin LastError := 'asmcore_x64: rip-relative addressing cannot carry a SIB index'; Exit; end;
  if memOp.MemBase = REG_RIP then
  begin
    EmitRex(buf, regOp.RegSize = 8, regOp.Reg >= 8, False, False);
    BufAppend(buf, Byte(opcode));
    BufAppend(buf, Byte((0 shl 6) or ((regOp.Reg and 7) shl 3) or 5));
    PatchAdd(patches, buf.Len, 4, opIndex);
    BufAppendI32(buf, 0);
    Result := True;
    Exit;
  end;
  Result := EncodeRegMem(opcode, regOp, memOp, buf);
end;

function EncodeUnary(digit: Integer; opByte: Integer; const dst: TAsmOperand; var buf: TAsmByteBuf): Boolean;
begin
  EmitRex(buf, dst.RegSize = 8, False, False, dst.Reg >= 8);
  BufAppend(buf, Byte(opByte));
  BufAppend(buf, Byte(($03 shl 6) or (digit shl 3) or (dst.Reg and 7)));
  Result := True;
end;

function EncodePushPop(base: Integer; const r: TAsmOperand; var buf: TAsmByteBuf): Boolean;
begin
  EmitRex(buf, False, False, False, r.Reg >= 8);   { 64-bit default; only REX.B }
  BufAppend(buf, Byte(base + (r.Reg and 7)));
  Result := True;
end;

{ Branch with a rel32 patch site. Emits prefix opcode bytes, then 4 zero bytes,
  recording the patch at the rel32 byte offset (layer 2 fills target-instr_end). }
procedure EncodeRel32(var buf: TAsmByteBuf; var patches: TAsmPatchList; opIndex: Integer);
begin
  PatchAdd(patches, buf.Len, 4, opIndex);
  BufAppendI32(buf, 0);
end;

function AsmEncodeX64(const instr: TAsmInstr;
                       var buf: TAsmByteBuf;
                       var patches: TAsmPatchList): Boolean;
var
  d0, d1: TAsmOperand;
  aluOp, dig, cond: Integer;
  w: Boolean;
begin
  LastError := '';
  Result := False;

  { ---- zero-operand ---- }
  if instr.OperandCount = 0 then
  begin
    if MnemIs(instr.Mnemonic, 'ret') then begin BufAppend(buf, $C3); Result := True; Exit; end;
    if MnemIs(instr.Mnemonic, 'syscall') then begin BufAppend(buf, $0F); BufAppend(buf, $05); Result := True; Exit; end;
    if MnemIs(instr.Mnemonic, 'nop') then begin BufAppend(buf, $90); Result := True; Exit; end;
    if MnemIs(instr.Mnemonic, 'leave') then begin BufAppend(buf, $C9); Result := True; Exit; end;
    if MnemIs(instr.Mnemonic, 'cqo') then begin BufAppend(buf, $48); BufAppend(buf, $99); Result := True; Exit; end;
    if MnemIs(instr.Mnemonic, 'cdq') then begin BufAppend(buf, $99); Result := True; Exit; end;
    LastError := 'asmcore_x64: unknown zero-operand mnemonic: ' + instr.Mnemonic;
    Exit;
  end;

  { ---- one-operand ---- }
  if instr.OperandCount = 1 then
  begin
    d0 := instr.Operands[0];
    { branches: jmp/call/jcc with a patch operand (rel32) }
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
      LastError := 'asmcore_x64: mnemonic does not take a branch target: ' + instr.Mnemonic;
      Exit;
    end;
    if d0.Kind = opReg then
    begin
      if MnemIs(instr.Mnemonic, 'push') then begin Result := EncodePushPop($50, d0, buf); Exit; end;
      if MnemIs(instr.Mnemonic, 'pop')  then begin Result := EncodePushPop($58, d0, buf); Exit; end;
      if MnemIs(instr.Mnemonic, 'inc') then begin Result := EncodeUnary(0, $FF, d0, buf); Exit; end;
      if MnemIs(instr.Mnemonic, 'dec') then begin Result := EncodeUnary(1, $FF, d0, buf); Exit; end;
      if MnemIs(instr.Mnemonic, 'not') then begin Result := EncodeUnary(2, $F7, d0, buf); Exit; end;
      if MnemIs(instr.Mnemonic, 'neg') then begin Result := EncodeUnary(3, $F7, d0, buf); Exit; end;
      if MnemIs(instr.Mnemonic, 'mul') then begin Result := EncodeUnary(4, $F7, d0, buf); Exit; end;
      if MnemIs(instr.Mnemonic, 'imul') then begin Result := EncodeUnary(5, $F7, d0, buf); Exit; end;
      if MnemIs(instr.Mnemonic, 'div') then begin Result := EncodeUnary(6, $F7, d0, buf); Exit; end;
      if MnemIs(instr.Mnemonic, 'idiv') then begin Result := EncodeUnary(7, $F7, d0, buf); Exit; end;
    end;
    LastError := 'asmcore_x64: unsupported one-operand form: ' + instr.Mnemonic;
    Exit;
  end;

  { ---- two-operand ---- }
  if instr.OperandCount = 2 then
  begin
    d0 := instr.Operands[0];
    d1 := instr.Operands[1];
    w := (d0.RegSize = 8) or (d1.RegSize = 8);

    if MnemIs(instr.Mnemonic, 'mov') then
    begin
      if (d0.Kind = opReg) and (d1.Kind = opImm) then begin Result := EncodeMovRegImm(d0, d1, buf); Exit; end;
      if (d0.Kind = opReg) and (d1.Kind = opReg) then begin Result := EncodeRMReg($89, w, d0, d1, buf); Exit; end;
      if (d0.Kind = opReg) and (d1.Kind = opMem) then begin Result := EncodeRegMemPatch($8B, d0, d1, buf, patches, 1); Exit; end;
      if (d0.Kind = opMem) and (d1.Kind = opReg) then begin Result := EncodeRegMem($89, d1, d0, buf); Exit; end;
      LastError := 'asmcore_x64: unsupported mov operand combination';
      Exit;
    end;

    if MnemIs(instr.Mnemonic, 'lea') then
    begin
      if (d0.Kind = opReg) and (d1.Kind = opMem) then begin Result := EncodeRegMemPatch($8D, d0, d1, buf, patches, 1); Exit; end;
      LastError := 'asmcore_x64: lea expects reg, [mem]';
      Exit;
    end;

    if MnemIs(instr.Mnemonic, 'test') then
    begin
      if (d0.Kind = opReg) and (d1.Kind = opReg) then begin Result := EncodeRMReg($85, w, d0, d1, buf); Exit; end;
      LastError := 'asmcore_x64: test expects reg, reg (this slice)';
      Exit;
    end;

    if MnemIs(instr.Mnemonic, 'imul') then
    begin
      if (d0.Kind = opReg) and (d1.Kind = opReg) then
      begin
        EmitRex(buf, w, d0.Reg >= 8, False, d1.Reg >= 8);
        BufAppend(buf, $0F); BufAppend(buf, $AF);
        BufAppend(buf, Byte(($03 shl 6) or ((d0.Reg and 7) shl 3) or (d1.Reg and 7)));
        Result := True; Exit;
      end;
      LastError := 'asmcore_x64: imul reg,reg only (this slice)';
      Exit;
    end;

    if AluOpcodeRR(instr.Mnemonic, aluOp) then
    begin
      if (d0.Kind = opReg) and (d1.Kind = opReg) then begin Result := EncodeRMReg(aluOp, w, d0, d1, buf); Exit; end;
      if (d0.Kind = opReg) and (d1.Kind = opImm) then
      begin
        AluDigit(instr.Mnemonic, dig);
        Result := EncodeAluRegImm(dig, d0, d1, buf);
        Exit;
      end;
      LastError := 'asmcore_x64: unsupported ALU operand combination for ' + instr.Mnemonic;
      Exit;
    end;
  end;

  LastError := 'asmcore_x64: unrecognized mnemonic/operand combination: ' + instr.Mnemonic;
  Result := False;
end;

{ ---- textual printer ---- }

function MemText(const m: TAsmOperand): AnsiString;
var s: AnsiString; wroteBase: Boolean;
begin
  if m.MemBase = REG_RIP then begin Result := '[rip+<patch>]'; Exit; end;
  s := '[';
  wroteBase := False;
  if m.MemBase >= 0 then begin s := s + RegName(m.MemBase, 8); wroteBase := True; end;
  if m.MemIndex >= 0 then
  begin
    if wroteBase then s := s + '+';
    s := s + RegName(m.MemIndex, 8) + '*' + IntToStrAsm(m.MemScale);
  end;
  if m.MemDisp > 0 then s := s + '+' + IntToStrAsm(m.MemDisp)
  else if m.MemDisp < 0 then s := s + IntToStrAsm(m.MemDisp);
  Result := s + ']';
end;

function OperandText(const op: TAsmOperand): AnsiString;
begin
  case op.Kind of
    opReg: Result := RegName(op.Reg, op.RegSize);
    opImm: Result := IntToStrAsm(op.Imm);
    opMem: Result := MemText(op);
    opPatch: Result := '<patch>';
  else
    Result := '?';
  end;
end;

function AsmPrintX64(const instr: TAsmInstr): AnsiString;
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

function AsmCoreLastError: AnsiString;
begin
  Result := LastError;
end;

end.
