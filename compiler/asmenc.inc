{ asmenc.inc — rudimentary x86-64 inline-assembler encoder (Intel syntax).

  Encodes a small but real subset of x86-64 into the AsmBytes buffer at
  parse time. Named identifiers resolve to the symbol's frame slot
  ([rbp+disp32]) so inline asm can read/write Pascal locals and params.

  Scope (grows per need):
    - operands: registers (8/16/32/64-bit), immediates, bare var names (mem)
    - ALU: mov add sub and or xor cmp test xchg lea imul
    - shifts: sar shl sal shr (rm,imm8 or rm,cl)
    - unary: inc dec neg not push pop
    - setcc / cmovcc family
    - 0-operand: nop ret leave syscall cdq cqo cdqe ; int imm8
    - raw data: db dw dd dq

  Not yet supported (clear errors): global-var operands (need relocation),
  explicit [reg] memory, labels/branches, AT&T syntax. }

procedure AsmB(b: Integer);
begin
  if AsmBytesCount >= 65536 then Error('asm: out of instruction byte capacity');
  AsmBytes[AsmBytesCount] := Byte(b and $FF);
  Inc(AsmBytesCount);
end;

procedure AsmI16(v: Int64);
begin
  AsmB(Integer(v and $FF));
  AsmB(Integer((v shr 8) and $FF));
end;

procedure AsmI32(v: Int64);
begin
  AsmB(Integer(v and $FF));
  AsmB(Integer((v shr 8) and $FF));
  AsmB(Integer((v shr 16) and $FF));
  AsmB(Integer((v shr 24) and $FF));
end;

{ Record a global-var operand's fixup (the real EmitGlobRef can't run here —
  AsmBytesCount isn't the operand's final code position, only the IR_ASM
  codegen-replay loop in ir_codegen.inc knows that). Writes the same 4-byte
  zero placeholder EmitGlobRef itself would. Real body for the `forward`
  declaration in x64enc.inc — called from EncModRMAbs when EncToAsmBuffer
  is set. }
procedure AsmRecordGlobalFixup(bssOff: Integer);
begin
  if AsmGlobFixCount >= MAX_ASM_GLOBFIX then Error('asm: too many global-var operand references');
  AsmGlobFix[AsmGlobFixCount].AsmOff := AsmBytesCount;
  AsmGlobFix[AsmGlobFixCount].BSSoff := bssOff;
  Inc(AsmGlobFixCount);
  AsmI32(0);
end;

procedure AsmI64(v: Int64);
begin
  AsmI32(v);
  AsmI32(v shr 32);
end;

{ Resolve a register name -> number (0..15) and size (1/2/4/8). }
function AsmRegNum(const nm: AnsiString; var num, size: Integer): Boolean;
var i: Integer; nm8, nm4, nm2, nm1: AnsiString;
begin
  Result := True;
  { 64-bit }
  if CaseEqual(nm,'rax') then begin num:=0; size:=8; Exit; end;
  if CaseEqual(nm,'rcx') then begin num:=1; size:=8; Exit; end;
  if CaseEqual(nm,'rdx') then begin num:=2; size:=8; Exit; end;
  if CaseEqual(nm,'rbx') then begin num:=3; size:=8; Exit; end;
  if CaseEqual(nm,'rsp') then begin num:=4; size:=8; Exit; end;
  if CaseEqual(nm,'rbp') then begin num:=5; size:=8; Exit; end;
  if CaseEqual(nm,'rsi') then begin num:=6; size:=8; Exit; end;
  if CaseEqual(nm,'rdi') then begin num:=7; size:=8; Exit; end;
  { 32-bit }
  if CaseEqual(nm,'eax') then begin num:=0; size:=4; Exit; end;
  if CaseEqual(nm,'ecx') then begin num:=1; size:=4; Exit; end;
  if CaseEqual(nm,'edx') then begin num:=2; size:=4; Exit; end;
  if CaseEqual(nm,'ebx') then begin num:=3; size:=4; Exit; end;
  if CaseEqual(nm,'esp') then begin num:=4; size:=4; Exit; end;
  if CaseEqual(nm,'ebp') then begin num:=5; size:=4; Exit; end;
  if CaseEqual(nm,'esi') then begin num:=6; size:=4; Exit; end;
  if CaseEqual(nm,'edi') then begin num:=7; size:=4; Exit; end;
  { 16-bit }
  if CaseEqual(nm,'ax') then begin num:=0; size:=2; Exit; end;
  if CaseEqual(nm,'cx') then begin num:=1; size:=2; Exit; end;
  if CaseEqual(nm,'dx') then begin num:=2; size:=2; Exit; end;
  if CaseEqual(nm,'bx') then begin num:=3; size:=2; Exit; end;
  if CaseEqual(nm,'sp') then begin num:=4; size:=2; Exit; end;
  if CaseEqual(nm,'bp') then begin num:=5; size:=2; Exit; end;
  if CaseEqual(nm,'si') then begin num:=6; size:=2; Exit; end;
  if CaseEqual(nm,'di') then begin num:=7; size:=2; Exit; end;
  { 8-bit (REX-form low bytes) }
  if CaseEqual(nm,'al') then begin num:=0; size:=1; Exit; end;
  if CaseEqual(nm,'cl') then begin num:=1; size:=1; Exit; end;
  if CaseEqual(nm,'dl') then begin num:=2; size:=1; Exit; end;
  if CaseEqual(nm,'bl') then begin num:=3; size:=1; Exit; end;
  if CaseEqual(nm,'spl') then begin num:=4; size:=1; Exit; end;
  if CaseEqual(nm,'bpl') then begin num:=5; size:=1; Exit; end;
  if CaseEqual(nm,'sil') then begin num:=6; size:=1; Exit; end;
  if CaseEqual(nm,'dil') then begin num:=7; size:=1; Exit; end;
  { r8..r15 in all four sizes (built with AppendChar — string '+' is unreliable
    when this compiler compiles itself) }
  for i := 8 to 15 do
  begin
    nm8 := '';
    AppendChar(nm8, 'r');                          { r }
    if i < 10 then AppendChar(nm8, Chr(Ord('0') + i))
    else begin AppendChar(nm8, '1'); AppendChar(nm8, Chr(Ord('0') + (i - 10))); end;
    nm4 := nm8; AppendChar(nm4, 'd');              { r8d }
    nm2 := nm8; AppendChar(nm2, 'w');              { r8w }
    nm1 := nm8; AppendChar(nm1, 'b');              { r8b }
    if CaseEqual(nm, nm8) then begin num:=i; size:=8; Exit; end;
    if CaseEqual(nm, nm4) then begin num:=i; size:=4; Exit; end;
    if CaseEqual(nm, nm2) then begin num:=i; size:=2; Exit; end;
    if CaseEqual(nm, nm1) then begin num:=i; size:=1; Exit; end;
  end;
  { xmm0..xmm15 — SSE registers, flagged with size 16 (built by append; string
    '+' is unreliable when this compiler self-compiles). }
  for i := 0 to 15 do
  begin
    nm8 := '';
    AppendChar(nm8, 'x'); AppendChar(nm8, 'm'); AppendChar(nm8, 'm');
    if i < 10 then AppendChar(nm8, Chr(Ord('0') + i))
    else begin AppendChar(nm8, '1'); AppendChar(nm8, Chr(Ord('0') + (i - 10))); end;
    if CaseEqual(nm, nm8) then begin num := i; size := 16; Exit; end;
  end;
  Result := False;
end;

{ Emit a REX prefix. w/r/x/b are 0/1. force = emit 0x40 even when all clear
  (needed to address spl/bpl/sil/dil). }
procedure AsmREX(w, r, x, b, force: Integer);
var v: Integer;
begin
  if (w = 0) and (r = 0) and (x = 0) and (b = 0) and (force = 0) then Exit;
  v := $40;
  if w <> 0 then v := v or $08;
  if r <> 0 then v := v or $04;
  if x <> 0 then v := v or $02;
  if b <> 0 then v := v or $01;
  AsmB(v);
end;

{ Does this 8-bit register require a REX prefix (spl/bpl/sil/dil, or r8b..)? }
function AsmReg8NeedsREX(num: Integer): Boolean;
begin
  Result := (num >= 4);
end;

{ Emit operand-size prefix + REX for an instruction whose register field is
  regField (an actual register, or an opcode-extension digit with regHigh=0)
  and whose r/m is the operand in AsmOp[rmSlot]. opSize selects 1/2/4/8.
  AOP_MEMR (explicit [reg+reg*scale+disp]) needs its own path: it's the only
  r/m kind that can need REX.X (an index register >=8), which
  EncPrefixAndREX's signature has no parameter for at all -- so this one
  case bypasses it and calls AsmREX (which does support X) directly. The
  $66 16-bit prefix is handled here too, same as EncPrefixAndREX's own
  rule. }
procedure AsmPrefixAndREX(opSize, regField, regHigh, rmSlot: Integer);
var
  rmReg, wBit, rBit, xBit, bBit: Integer;
begin
  if AsmOpKind[rmSlot] = AOP_MEMR then
  begin
    if opSize = 2 then AsmB($66);
    wBit := 0; if opSize = 8 then wBit := 1;
    rBit := 0; if regHigh <> 0 then rBit := 1;
    bBit := 0; if AsmOpReg[rmSlot] >= 8 then bBit := 1;
    xBit := 0; if AsmOpIndex[rmSlot] >= 8 then xBit := 1;
    AsmREX(wBit, rBit, xBit, bBit, 0);
    Exit;
  end;

  rmReg := 0;
  if AsmOpKind[rmSlot] = AOP_REG then rmReg := AsmOpReg[rmSlot]
  else if AsmOpKind[rmSlot] = AOP_MEM then rmReg := rRBP;

  EncToAsmBuffer := True;
  EncPrefixAndREX(opSize, (regHigh shl 3) or regField, rmReg, False);
  EncToAsmBuffer := False;
end;

{ Emit ModRM (+disp) where modrm.reg = regField and r/m = AsmOp[rmSlot]. }
procedure AsmModRM(regField, rmSlot: Integer);
var sibBuf: TAsmByteBuf; sibOp: TAsmOperand; k: Integer;
begin
  EncToAsmBuffer := True;
  if AsmOpKind[rmSlot] = AOP_REG then
  begin
    EncModRMReg(regField, AsmOpReg[rmSlot]);
  end
  else if AsmOpKind[rmSlot] = AOP_MEM then
  begin
    EncModRMMem(regField, rRBP, AsmOpVal[rmSlot], True);
  end
  else if AsmOpKind[rmSlot] = AOP_GLOBAL then
  begin
    EncModRMAbs(regField, Integer(AsmOpVal[rmSlot]));
  end
  else if AsmOpKind[rmSlot] = AOP_MEMR then
  begin
    { Reuse lib/asmcore's SIB-capable EmitModRMMem (exported for exactly
      this) rather than re-deriving SIB encoding a second time here --
      "library work first, dial it into the compiler." Bridges through a
      throwaway TAsmByteBuf since asmcore's buffer type isn't AsmBytes. }
    EncToAsmBuffer := False;
    sibOp := MemOpIndexed(AsmOpReg[rmSlot], AsmOpIndex[rmSlot], AsmOpScale[rmSlot], AsmOpVal[rmSlot]);
    BufInit(sibBuf);
    if not EmitModRMMem(sibBuf, regField, sibOp) then
      Error('asm: ' + AsmCoreLastError);
    for k := 0 to sibBuf.Len - 1 do AsmB(sibBuf.Bytes[k]);
  end
  else
    Error('asm: bad r/m operand');
  EncToAsmBuffer := False;
end;

{ Parse one operand into slot (0 or 1). Reads CurTok. }
{ Parse an explicit memory operand: [reg] | [reg+disp] | [reg-disp] |
  [reg+reg*scale] | [reg+reg*scale+disp] | [reg+reg*scale-disp]. The base
  register is mandatory and always first; an index*scale term and a
  displacement term are each optional, in either order, introduced by + or
  -. No size keyword this slice (TODO #4, devdocs/developer/inline-asm.md)
  -- AsmOpSize is left 0 and AsmOpSizeOf's final dword default applies when
  no register operand in the same instruction disambiguates the width. }
procedure AsmParseMemROperand(slot: Integer);
var baseReg, baseSize, idxReg, idxSize, scale, sign: Integer; disp: Int64;
    sawIndex, sawDisp: Boolean;
begin
  Next;   { consume '[' }
  if CurTok.Kind <> tkIdent then Error('asm: expected a register after [');
  if not AsmRegNum(CurTok.SVal, baseReg, baseSize) then
    Error('asm: [..] base must be a register: ' + CurTok.SVal);
  Next;
  idxReg := -1; scale := 1; disp := 0; sawIndex := False; sawDisp := False;

  while (CurTok.Kind = tkPlus) or (CurTok.Kind = tkMinus) do
  begin
    if CurTok.Kind = tkPlus then sign := 1 else sign := -1;
    Next;
    if CurTok.Kind = tkInteger then
    begin
      if sawDisp then Error('asm: [..] has more than one displacement term');
      disp := Int64(sign) * CurTok.IVal;
      sawDisp := True;
      Next;
    end
    else if CurTok.Kind = tkIdent then
    begin
      if sign < 0 then Error('asm: [..] index register cannot be negated');
      if sawIndex then Error('asm: [..] has more than one index term');
      if not AsmRegNum(CurTok.SVal, idxReg, idxSize) then
        Error('asm: [..] expected a register or integer: ' + CurTok.SVal);
      Next;
      if CurTok.Kind = tkStar then
      begin
        Next;
        if CurTok.Kind <> tkInteger then Error('asm: [..] expected scale 1/2/4/8 after *');
        scale := Integer(CurTok.IVal);
        if (scale <> 1) and (scale <> 2) and (scale <> 4) and (scale <> 8) then
          Error('asm: [..] scale must be 1, 2, 4, or 8');
        Next;
      end;
      sawIndex := True;
    end
    else
      Error('asm: [..] expected a register or integer after + or -');
  end;

  if CurTok.Kind <> tkRBrack then Error('asm: expected ] to close memory operand');
  Next;

  AsmOpKind[slot] := AOP_MEMR;
  AsmOpReg[slot] := baseReg;
  AsmOpIndex[slot] := idxReg;
  AsmOpScale[slot] := scale;
  AsmOpVal[slot] := disp;
  AsmOpSize[slot] := 0;
end;

procedure AsmParseOperand(slot: Integer);
var num, size, idx: Integer;
begin
  AsmOpKind[slot] := AOP_NONE;
  AsmOpReg[slot] := 0; AsmOpSize[slot] := 0; AsmOpVal[slot] := 0;
  AsmOpIndex[slot] := -1; AsmOpScale[slot] := 1;

  if CurTok.Kind = tkLBrack then
  begin
    AsmParseMemROperand(slot);
    Exit;
  end;

  if CurTok.Kind = tkMinus then
  begin
    Next;
    if CurTok.Kind <> tkInteger then Error('asm: expected integer after -');
    AsmOpKind[slot] := AOP_IMM;
    AsmOpVal[slot] := -CurTok.IVal;
    Next;
    Exit;
  end;

  if CurTok.Kind = tkInteger then
  begin
    AsmOpKind[slot] := AOP_IMM;
    AsmOpVal[slot] := CurTok.IVal;
    Next;
    Exit;
  end;

  if CurTok.Kind = tkIdent then
  begin
    if AsmRegNum(CurTok.SVal, num, size) then
    begin
      AsmOpKind[slot] := AOP_REG;
      AsmOpReg[slot] := num;
      AsmOpSize[slot] := size;
      Next;
      Exit;
    end;
    { Named variable -> memory operand [rbp+off], or an absolute [disp32]
      for a global (Offset is BSS-relative for skGlobal symbols). }
    idx := FindSym(CurTok.SVal);
    if idx < 0 then Error('asm: unknown symbol: ' + CurTok.SVal);
    if Syms[idx].Kind = skGlobal then
    begin
      AsmOpKind[slot] := AOP_GLOBAL;
      AsmOpVal[slot] := Syms[idx].Offset;
      AsmOpSize[slot] := TypeSize(Syms[idx].TypeKind);
      Next;
      Exit;
    end;
    if (Syms[idx].Kind <> skLocal) and (Syms[idx].Kind <> skParam) then
      Error('asm: operand must be a local, param, global, or register: ' + CurTok.SVal);
    AsmOpKind[slot] := AOP_MEM;
    AsmOpVal[slot] := Syms[idx].Offset;
    AsmOpSize[slot] := TypeSize(Syms[idx].TypeKind);
    Next;
    Exit;
  end;

  Error('asm: unexpected operand token');
end;

{ Determine the instruction operand size from parsed operands. A register
  operand fixes the size; otherwise fall back to a memory operand's size,
  else 4 (dword). }
function AsmOpSizeOf(nops: Integer): Integer;
begin
  if (nops >= 1) and (AsmOpKind[0] = AOP_REG) then begin Result := AsmOpSize[0]; Exit; end;
  if (nops >= 2) and (AsmOpKind[1] = AOP_REG) then begin Result := AsmOpSize[1]; Exit; end;
  if (nops >= 1) and ((AsmOpKind[0] = AOP_MEM) or (AsmOpKind[0] = AOP_GLOBAL)) then begin Result := AsmOpSize[0]; Exit; end;
  if (nops >= 2) and ((AsmOpKind[1] = AOP_MEM) or (AsmOpKind[1] = AOP_GLOBAL)) then begin Result := AsmOpSize[1]; Exit; end;
  Result := 4;
end;

{ Map a condition-code suffix to its 4-bit cc number, or -1. }
function AsmCC(const s: AnsiString): Integer;
begin
  Result := -1;
  if CaseEqual(s,'o')  then Result := 0;
  if CaseEqual(s,'no') then Result := 1;
  if CaseEqual(s,'b')  or CaseEqual(s,'c') or CaseEqual(s,'nae') then Result := 2;
  if CaseEqual(s,'ae') or CaseEqual(s,'nb') or CaseEqual(s,'nc') then Result := 3;
  if CaseEqual(s,'e')  or CaseEqual(s,'z') then Result := 4;
  if CaseEqual(s,'ne') or CaseEqual(s,'nz') then Result := 5;
  if CaseEqual(s,'be') or CaseEqual(s,'na') then Result := 6;
  if CaseEqual(s,'a')  or CaseEqual(s,'nbe') then Result := 7;
  if CaseEqual(s,'s')  then Result := 8;
  if CaseEqual(s,'ns') then Result := 9;
  if CaseEqual(s,'p')  or CaseEqual(s,'pe') then Result := 10;
  if CaseEqual(s,'np') or CaseEqual(s,'po') then Result := 11;
  if CaseEqual(s,'l')  or CaseEqual(s,'nge') then Result := 12;
  if CaseEqual(s,'ge') or CaseEqual(s,'nl') then Result := 13;
  if CaseEqual(s,'le') or CaseEqual(s,'ng') then Result := 14;
  if CaseEqual(s,'g')  or CaseEqual(s,'nle') then Result := 15;
end;

{ Returns the tail of s after a known prefix (prefixLen chars), e.g. 'setnz'
  with prefixLen 3 -> 'nz'. }
function AsmTail(const s: AnsiString; prefixLen: Integer): AnsiString;
var i: Integer; r: AnsiString;
begin
  r := '';
  for i := prefixLen + 1 to Length(s) do AppendChar(r, s[i]);
  Result := r;
end;

function AsmStartsWith(const s, pre: AnsiString): Boolean;
var i: Integer;
begin
  Result := False;
  if Length(s) < Length(pre) then Exit;
  for i := 1 to Length(pre) do
    if (s[i] <> pre[i]) and (Chr(Ord(s[i]) or 32) <> Chr(Ord(pre[i]) or 32)) then Exit;
  Result := True;
end;

{ Encode a two-operand ALU instruction sharing the standard /r encoding.
  rmReg = base opcode for "r/m, reg" form (e.g. mov=$89, add=$01);
  regRm = base opcode for "reg, r/m" form (e.g. mov=$8B, add=$03);
  immExt = /digit for the 81 imm form, or -1 if imm form unsupported. }
procedure AsmEncodeALU(rmReg, regRm, immExt: Integer);
var opSize, rf, rh, r2: Integer;
begin
  { dest=reg, src=reg : use rm,reg form (reg field = src, rm = dest) }
  if (AsmOpKind[0] = AOP_REG) and (AsmOpKind[1] = AOP_REG) then
  begin
    opSize := AsmOpSizeOf(2);
    rf := AsmOpReg[1]; rh := 0; if rf >= 8 then rh := 1;
    AsmPrefixAndREX(opSize, rf, rh, 0);
    if opSize = 1 then AsmB(rmReg - 1) else AsmB(rmReg);
    AsmB($C0 or ((rf and 7) * 8) or (AsmOpReg[0] and 7));
    Exit;
  end;
  { dest=reg, src=mem/global/memr : reg,r/m form (reg field = dest reg, rm = mem) }
  if (AsmOpKind[0] = AOP_REG) and ((AsmOpKind[1] = AOP_MEM) or (AsmOpKind[1] = AOP_GLOBAL) or (AsmOpKind[1] = AOP_MEMR)) then
  begin
    opSize := AsmOpSize[0];
    rf := AsmOpReg[0]; rh := 0; if rf >= 8 then rh := 1;
    AsmPrefixAndREX(opSize, rf, rh, 1);
    if opSize = 1 then AsmB(regRm - 1) else AsmB(regRm);
    AsmModRM(rf, 1);
    Exit;
  end;
  { dest=mem/global/memr, src=reg : rm,reg form }
  if ((AsmOpKind[0] = AOP_MEM) or (AsmOpKind[0] = AOP_GLOBAL) or (AsmOpKind[0] = AOP_MEMR)) and (AsmOpKind[1] = AOP_REG) then
  begin
    opSize := AsmOpSize[1];
    rf := AsmOpReg[1]; rh := 0; if rf >= 8 then rh := 1;
    AsmPrefixAndREX(opSize, rf, rh, 0);
    if opSize = 1 then AsmB(rmReg - 1) else AsmB(rmReg);
    AsmModRM(rf, 0);
    Exit;
  end;
  { dest=reg/mem/global/memr, src=imm : 81 /ext id (or C7 /0 handled by caller for mov) }
  if ((AsmOpKind[0] = AOP_REG) or (AsmOpKind[0] = AOP_MEM) or (AsmOpKind[0] = AOP_GLOBAL) or (AsmOpKind[0] = AOP_MEMR)) and (AsmOpKind[1] = AOP_IMM) then
  begin
    if immExt < 0 then Error('asm: immediate form not supported for this mnemonic');
    opSize := AsmOpSizeOf(1);
    AsmPrefixAndREX(opSize, immExt, 0, 0);
    if opSize = 1 then AsmB($80) else AsmB($81);
    AsmModRM(immExt, 0);
    if opSize = 1 then AsmB(Integer(AsmOpVal[1] and $FF))
    else if opSize = 2 then AsmI16(AsmOpVal[1])
    else AsmI32(AsmOpVal[1]);
    Exit;
  end;
  Error('asm: unsupported operand combination');
end;

{ mov has its own opcodes (88/89 store, 8A/8B load, C7 /0 imm, B8+r imm64). }
procedure AsmEncodeMov;
var opSize, rf, rh: Integer;
begin
  if (AsmOpKind[0] = AOP_REG) and (AsmOpKind[1] = AOP_IMM) then
  begin
    EncToAsmBuffer := True;
    x64_mov_reg_imm(AsmOpSize[0], AsmOpReg[0], AsmOpVal[1]);
    EncToAsmBuffer := False;
    Exit;
  end;
  if (AsmOpKind[0] = AOP_MEM) and (AsmOpKind[1] = AOP_IMM) then
  begin
    EncToAsmBuffer := True;
    x64_mov_mem_imm(AsmOpSizeOf(1), rRBP, AsmOpVal[0], AsmOpVal[1], True);
    EncToAsmBuffer := False;
    Exit;
  end;
  if (AsmOpKind[0] = AOP_MEMR) and (AsmOpKind[1] = AOP_IMM) then
  begin
    { C6 /0 imm8 (1-byte) or C7 /0 imm32. Goes through the generic
      AsmModRM/AsmPrefixAndREX (which both now handle AOP_MEMR) instead of
      x64_mov_mem_imm, which hardcodes an [rbp+disp] base. }
    opSize := AsmOpSizeOf(1);
    AsmPrefixAndREX(opSize, 0, 0, 0);
    if opSize = 1 then AsmB($C6) else AsmB($C7);
    AsmModRM(0, 0);
    if opSize = 1 then AsmB(Integer(AsmOpVal[1] and $FF))
    else if opSize = 2 then AsmI16(AsmOpVal[1])
    else AsmI32(AsmOpVal[1]);
    Exit;
  end;
  if (AsmOpKind[0] = AOP_GLOBAL) and (AsmOpKind[1] = AOP_IMM) then
    Error('asm: mov global,imm not yet supported (x64_mov_mem_imm assumes an [rbp+disp] base) -- load the value into a register first');
  AsmEncodeALU($89, $8B, -1);
end;

{ Forward decls for the per-instruction dispatcher. }
function AsmEncodeOneNamed(const mn: AnsiString; mnLine: Integer): Boolean; forward;

{ Encode a single instruction whose mnemonic is in mn and whose operands have
  already been parsed into AsmOp[0..nops-1]. Returns False if mnemonic unknown. }
function AsmDispatch(const mn: AnsiString; nops: Integer): Boolean;
var opSize, rf, rh, ext, cc: Integer; tail: AnsiString;
begin
  Result := True;

  { ---- 0-operand ---- }
  if CaseEqual(mn,'nop')     then begin AsmB($90); Exit; end;
  if CaseEqual(mn,'ret')     then begin AsmB($C3); Exit; end;
  if CaseEqual(mn,'leave')   then begin AsmB($C9); Exit; end;
  if CaseEqual(mn,'syscall') then begin AsmB($0F); AsmB($05); Exit; end;
  if CaseEqual(mn,'cdq')     then begin AsmB($99); Exit; end;
  if CaseEqual(mn,'cqo')     then begin AsmB($48); AsmB($99); Exit; end;
  if CaseEqual(mn,'cdqe')    then begin AsmB($48); AsmB($98); Exit; end;
  if CaseEqual(mn,'cwde')    then begin AsmB($98); Exit; end;

  if CaseEqual(mn,'int') then
  begin
    if (nops <> 1) or (AsmOpKind[0] <> AOP_IMM) then Error('asm: int needs imm8');
    AsmB($CD); AsmB(Integer(AsmOpVal[0] and $FF)); Exit;
  end;

  { ---- two-operand ALU ---- }
  if CaseEqual(mn,'mov') then begin AsmEncodeMov; Exit; end;
  if CaseEqual(mn,'add') then begin AsmEncodeALU($01,$03,0); Exit; end;
  if CaseEqual(mn,'or')  then begin AsmEncodeALU($09,$0B,1); Exit; end;
  if CaseEqual(mn,'and') then begin AsmEncodeALU($21,$23,4); Exit; end;
  if CaseEqual(mn,'sub') then begin AsmEncodeALU($29,$2B,5); Exit; end;
  if CaseEqual(mn,'xor') then begin AsmEncodeALU($31,$33,6); Exit; end;
  if CaseEqual(mn,'cmp') then begin AsmEncodeALU($39,$3B,7); Exit; end;

  { test: only r/m,reg (85). }
  if CaseEqual(mn,'test') then
  begin
    if (AsmOpKind[1] <> AOP_REG) then Error('asm: test needs a register source');
    opSize := AsmOpSize[1];
    rf := AsmOpReg[1]; rh := 0; if rf >= 8 then rh := 1;
    AsmPrefixAndREX(opSize, rf, rh, 0);
    if opSize = 1 then AsmB($84) else AsmB($85);
    AsmModRM(rf, 0);
    Exit;
  end;

  { xchg: 87 r/m,reg (one operand must be a register). }
  if CaseEqual(mn,'xchg') then
  begin
    if (AsmOpKind[0] = AOP_REG) then
    begin
      opSize := AsmOpSize[0];
      rf := AsmOpReg[0]; rh := 0; if rf >= 8 then rh := 1;
      AsmPrefixAndREX(opSize, rf, rh, 1);
      if opSize = 1 then AsmB($86) else AsmB($87);
      AsmModRM(rf, 1);
      Exit;
    end
    else if (AsmOpKind[1] = AOP_REG) then
    begin
      opSize := AsmOpSize[1];
      rf := AsmOpReg[1]; rh := 0; if rf >= 8 then rh := 1;
      AsmPrefixAndREX(opSize, rf, rh, 0);
      if opSize = 1 then AsmB($86) else AsmB($87);
      AsmModRM(rf, 0);
      Exit;
    end;
    Error('asm: xchg needs a register operand');
  end;

  { lea reg, mem/global/memr }
  if CaseEqual(mn,'lea') then
  begin
    if (AsmOpKind[0] <> AOP_REG) or ((AsmOpKind[1] <> AOP_MEM) and (AsmOpKind[1] <> AOP_GLOBAL) and (AsmOpKind[1] <> AOP_MEMR)) then
      Error('asm: lea needs reg, mem');
    opSize := AsmOpSize[0];
    rf := AsmOpReg[0]; rh := 0; if rf >= 8 then rh := 1;
    AsmPrefixAndREX(opSize, rf, rh, 1);
    AsmB($8D);
    AsmModRM(rf, 1);
    Exit;
  end;

  { imul reg, r/m  (0F AF) }
  if CaseEqual(mn,'imul') and (nops = 2) then
  begin
    if AsmOpKind[0] <> AOP_REG then Error('asm: imul dest must be register');
    opSize := AsmOpSize[0];
    rf := AsmOpReg[0]; rh := 0; if rf >= 8 then rh := 1;
    AsmPrefixAndREX(opSize, rf, rh, 1);
    AsmB($0F); AsmB($AF);
    AsmModRM(rf, 1);
    Exit;
  end;

  { ---- shifts: rm, imm8 (C1 /ext) or rm, cl (D3 /ext) ---- }
  ext := -1;
  if CaseEqual(mn,'rol') then ext := 0;
  if CaseEqual(mn,'ror') then ext := 1;
  if CaseEqual(mn,'shl') or CaseEqual(mn,'sal') then ext := 4;
  if CaseEqual(mn,'shr') then ext := 5;
  if CaseEqual(mn,'sar') then ext := 7;
  if ext >= 0 then
  begin
    opSize := AsmOpSizeOf(1);
    if (AsmOpKind[1] = AOP_REG) and (AsmOpReg[1] = 1) then
    begin
      AsmPrefixAndREX(opSize, ext, 0, 0);
      if opSize = 1 then AsmB($D2) else AsmB($D3);
      AsmModRM(ext, 0);
    end
    else if AsmOpKind[1] = AOP_IMM then
    begin
      AsmPrefixAndREX(opSize, ext, 0, 0);
      if opSize = 1 then AsmB($C0) else AsmB($C1);
      AsmModRM(ext, 0);
      AsmB(Integer(AsmOpVal[1] and $FF));
    end
    else
      Error('asm: shift count must be cl or an immediate');
    Exit;
  end;

  { ---- unary: rm ---- }
  ext := -1;
  if CaseEqual(mn,'not') then ext := 2;
  if CaseEqual(mn,'neg') then ext := 3;
  if CaseEqual(mn,'mul') then ext := 4;
  if CaseEqual(mn,'idiv') then ext := 7;
  if CaseEqual(mn,'div') then ext := 6;
  if ext >= 0 then
  begin
    opSize := AsmOpSizeOf(1);
    AsmPrefixAndREX(opSize, ext, 0, 0);
    if opSize = 1 then AsmB($F6) else AsmB($F7);
    AsmModRM(ext, 0);
    Exit;
  end;
  if CaseEqual(mn,'inc') or CaseEqual(mn,'dec') then
  begin
    ext := 0; if CaseEqual(mn,'dec') then ext := 1;
    opSize := AsmOpSizeOf(1);
    AsmPrefixAndREX(opSize, ext, 0, 0);
    if opSize = 1 then AsmB($FE) else AsmB($FF);
    AsmModRM(ext, 0);
    Exit;
  end;

  { ---- push / pop ---- }
  if CaseEqual(mn,'push') then
  begin
    if AsmOpKind[0] = AOP_MEMR then
    begin
      { push r/m64 = FF /6. No REX.W (push/pop default to 64-bit operand
        size already; verified vs host `as` -- 0xFF 0x70 0x10 for
        "push qword [rax+0x10]", no 48 prefix). opSize=0 is an inert
        sentinel here: not 2 (no $66) and not 8 (no REX.W). }
      AsmPrefixAndREX(0, 6, 0, 0);
      AsmB($FF);
      AsmModRM(6, 0);
      Exit;
    end;
    EncToAsmBuffer := True;
    if AsmOpKind[0] = AOP_REG then
      x64_push_reg(AsmOpReg[0])
    else if AsmOpKind[0] = AOP_IMM then
      x64_push_imm(AsmOpVal[0])
    else if AsmOpKind[0] = AOP_GLOBAL then
      Error('asm: push global not yet supported (x64_push_mem assumes an [rbp+disp] base)')
    else
      x64_push_mem(rRBP, AsmOpVal[0], True);
    EncToAsmBuffer := False;
    Exit;
  end;
  if CaseEqual(mn,'pop') then
  begin
    if AsmOpKind[0] = AOP_MEMR then
    begin
      { pop r/m64 = 8F /0. Same no-REX.W note as push above. }
      AsmPrefixAndREX(0, 0, 0, 0);
      AsmB($8F);
      AsmModRM(0, 0);
      Exit;
    end;
    EncToAsmBuffer := True;
    if AsmOpKind[0] = AOP_REG then
      x64_pop_reg(AsmOpReg[0])
    else if AsmOpKind[0] = AOP_GLOBAL then
      Error('asm: pop global not yet supported (x64_pop_mem assumes an [rbp+disp] base)')
    else
      x64_pop_mem(rRBP, AsmOpVal[0], True);
    EncToAsmBuffer := False;
    Exit;
  end;

  { ---- setcc r/m8 ---- }
  if AsmStartsWith(mn, 'set') then
  begin
    tail := AsmTail(mn, 3);
    cc := AsmCC(tail);
    if cc >= 0 then
    begin
      AsmPrefixAndREX(1, 0, 0, 0);  { 8-bit r/m, force REX if spl.. }
      AsmB($0F); AsmB($90 + cc);
      AsmModRM(0, 0);
      Exit;
    end;
  end;

  { ---- cmovcc reg, r/m ---- }
  if AsmStartsWith(mn, 'cmov') then
  begin
    tail := AsmTail(mn, 4);
    cc := AsmCC(tail);
    if (cc >= 0) and (AsmOpKind[0] = AOP_REG) then
    begin
      opSize := AsmOpSize[0];
      rf := AsmOpReg[0]; rh := 0; if rf >= 8 then rh := 1;
      AsmPrefixAndREX(opSize, rf, rh, 1);
      AsmB($0F); AsmB($40 + cc);
      AsmModRM(rf, 1);
      Exit;
    end;
  end;

  Result := False;
end;

{ True for a token that can lead an asm statement (mnemonic or label name).
  Mostly tkIdent, but `and`/`or`/`xor`/`not`/`div`/`mod`/`shl`/`inc`/`dec` are
  valid x86 mnemonics that collide with Pascal keywords and lex to their own
  token kinds (bug-asm-keyword-mnemonic-collision) — CurTok.SVal still holds
  their text, so the fix is just widening this gate, not touching SVal. }
function AsmTokIsWordLike(k: TTokenKind): Boolean;
begin
  Result := (k = tkIdent) or (k = tkAnd) or (k = tkOr) or (k = tkXor)
    or (k = tkNot) or (k = tkDiv) or (k = tkMod) or (k = tkShl)
    or (k = tkInc) or (k = tkDec);
end;

{ True if mn is a control-transfer mnemonic taking a single label target
  (jmp/call/jcc) — built on the existing AsmCC condition-code table, so the
  jcc set never needs to be enumerated twice. }
function AsmIsBranchMnem(const mn: AnsiString): Boolean;
begin
  Result := CaseEqual(mn, 'jmp') or CaseEqual(mn, 'call')
    or (AsmStartsWith(mn, 'j') and (AsmCC(AsmTail(mn, 1)) >= 0));
end;

{ Parse + encode one instruction's operands. mn/mnLine are the already-
  consumed mnemonic (CurTok is sitting on the first operand, or past the
  instruction if it had none). Operand list ends at the next source line or
  at 'end'. Returns False if the mnemonic is unknown (caller reports it). }
function AsmEncodeOneNamed(const mn: AnsiString; mnLine: Integer): Boolean;
var nops: Integer;
begin
  nops := 0;
  { Operands continue while still on the mnemonic's source line. }
  while (CurTok.Kind <> tkEnd) and (CurTok.Line = mnLine) and (CurTok.Kind <> tkEOF) do
  begin
    if nops >= 2 then Error('asm: more than 2 operands not supported: ' + mn);
    AsmParseOperand(nops);
    Inc(nops);
    if (CurTok.Kind = tkComma) and (CurTok.Line = mnLine) then Next
    else mnLine := -2;  { force loop exit: next token belongs to next instr }
  end;
  Result := AsmDispatch(mn, nops);
end;

const
  ASM_MAX_LOCAL_LABELS = 256;
  ASM_MAX_LOCAL_FIXUPS = 512;

{ Parse a full asm block body (after the 'asm' keyword) up to 'end', encoding
  into AsmBytes. Handles raw data directives db/dw/dd/dq, `name:` labels, and
  jmp/call/jcc <label> branches (rel32, forward + backward — see
  devdocs/developer/inline-asm.md TODO #1). Branches are encoded via
  lib/asmcore's AsmEncodeX64 (PatchOp(4)) the same way the standalone `.asm`
  frontend (compiler/asmfront.inc) resolves its own labels: record a fixup at
  the patch site, resolve target-(patch+4) once every label is known.
  startOff is set to the buffer offset where this block's bytes begin; len is
  the byte count. Also consumes the optional clobber list:
  end ['eax', ...] ;  (parsed, ignored — this codegen keeps nothing live in
  registers across statements). }
procedure AsmParseBody(var startOff, len: Integer);
var
  dir, branchTarget: AnsiString;
  v, rel: Int64;
  dirLine, dummyNum, dummySize, baseOff, k, tgt, li: Integer;
  found: Boolean;
  instr: TAsmInstr;
  buf: TAsmByteBuf;
  patches: TAsmPatchList;
  lblName: array[0..ASM_MAX_LOCAL_LABELS-1] of AnsiString;
  lblOff:  array[0..ASM_MAX_LOCAL_LABELS-1] of Integer;
  lblCount: Integer;
  fixPos:  array[0..ASM_MAX_LOCAL_FIXUPS-1] of Integer;
  fixName: array[0..ASM_MAX_LOCAL_FIXUPS-1] of AnsiString;
  fixCount: Integer;
begin
  { The encoder below emits x86-64 bytes only; encoding them into a
    cross-target ELF would be silently wrong. }
  if TargetArch <> TARGET_X86_64 then
    Error('inline asm is x86-64 only; not supported for this target');
  startOff := AsmBytesCount;
  lblCount := 0;
  fixCount := 0;

  while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
  begin
    if not AsmTokIsWordLike(CurTok.Kind) then
    begin
      Next;  { skip stray punctuation defensively }
      Continue;
    end;

    dir := CurTok.SVal;
    dirLine := CurTok.Line;
    Next;   { tentatively consume the identifier to check for a trailing ':' }

    if CurTok.Kind = tkColon then
    begin
      if lblCount >= ASM_MAX_LOCAL_LABELS then Error('asm: too many labels');
      lblName[lblCount] := dir;
      lblOff[lblCount] := AsmBytesCount;
      Inc(lblCount);
      Next;   { consume ':' — a label may stand alone or prefix an instruction }
      Continue;
    end;

    if CaseEqual(dir,'db') or CaseEqual(dir,'dw') or CaseEqual(dir,'dd') or CaseEqual(dir,'dq') then
    begin
      repeat
        if CurTok.Kind <> tkInteger then Error('asm: expected integer constant');
        v := CurTok.IVal;
        Next;
        if CaseEqual(dir,'db') then AsmB(Integer(v and $FF))
        else if CaseEqual(dir,'dw') then AsmI16(v)
        else if CaseEqual(dir,'dd') then AsmI32(v)
        else AsmI64(v);
      until not Eat(tkComma);
    end
    else if AsmIsBranchMnem(dir) then
    begin
      if CurTok.Kind <> tkIdent then Error('asm: "' + dir + '" needs a label target');
      if AsmRegNum(CurTok.SVal, dummyNum, dummySize) then
        Error('asm: "' + dir + '" target must be a label, not a register');
      branchTarget := CurTok.SVal;
      Next;
      instr.Mnemonic := dir;
      instr.OperandCount := 1;
      instr.Operands[0] := PatchOp(4);
      baseOff := AsmBytesCount;
      BufInit(buf);
      PatchListInit(patches);
      if not AsmEncodeX64(instr, buf, patches) then
        Error('asm: ' + AsmCoreLastError);
      for k := 0 to buf.Len - 1 do AsmB(buf.Bytes[k]);
      if patches.Count <> 1 then
        Error('asm: internal: branch "' + dir + '" produced an unexpected number of patch sites');
      if fixCount >= ASM_MAX_LOCAL_FIXUPS then Error('asm: too many branch fixups');
      fixPos[fixCount] := baseOff + patches.Items[0].Offset;
      fixName[fixCount] := branchTarget;
      Inc(fixCount);
    end
    else
    begin
      if not AsmEncodeOneNamed(dir, dirLine) then Error('asm: unknown instruction: ' + dir);
    end;
  end;

  { resolve branch fixups: rel32 = target - (patchPos + 4) }
  for k := 0 to fixCount - 1 do
  begin
    found := False; tgt := 0;
    for li := 0 to lblCount - 1 do
      if CaseEqual(lblName[li], fixName[k]) then begin tgt := lblOff[li]; found := True; end;
    if not found then Error('asm: undefined label "' + fixName[k] + '"');
    rel := tgt - (fixPos[k] + 4);
    AsmBytes[fixPos[k]]   := Byte(rel and $FF);
    AsmBytes[fixPos[k]+1] := Byte((rel shr 8) and $FF);
    AsmBytes[fixPos[k]+2] := Byte((rel shr 16) and $FF);
    AsmBytes[fixPos[k]+3] := Byte((rel shr 24) and $FF);
  end;

  Expect(tkEnd, 'end');

  { Optional clobber list: ['reg', ...] — parsed and discarded. }
  if CurTok.Kind = tkLBrack then
  begin
    Next;
    while (CurTok.Kind <> tkRBrack) and (CurTok.Kind <> tkEOF) do Next;
    Expect(tkRBrack, ']');
  end;
  Eat(tkSemicolon);

  len := AsmBytesCount - startOff;
end;
