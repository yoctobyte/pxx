{ SPDX-License-Identifier: MPL-2.0 }
{ asmtext_386.inc — text-assembler for readable i386 (x86-32) codegen emission.

  EmitAsm386 is the 32-bit sibling of EmitAsmX64; it shares the AsmText* string
  helpers in asmtext.inc and the x86 operand model, dropping REX and the
  r8..r15 / RIP-relative forms. }

const
  ASM_386_MAX_LABELS = 64;

var
  Asm386LblName:  array[0..ASM_386_MAX_LABELS - 1] of AnsiString;
  Asm386LblPos:   array[0..ASM_386_MAX_LABELS - 1] of Integer;
  Asm386LblCount: Integer;
  Asm386FwName:   array[0..ASM_386_MAX_LABELS - 1] of AnsiString;
  Asm386FwPatch:  array[0..ASM_386_MAX_LABELS - 1] of Integer;
  Asm386FwShort:  array[0..ASM_386_MAX_LABELS - 1] of Boolean;
  Asm386FwCount:  Integer;

{ segment register number for es cs ss ds fs gs, else -1 }
function Asm386SegReg(const op: AnsiString): Integer;
begin
  if CaseEqual(op, 'es') then Result := 0
  else if CaseEqual(op, 'cs') then Result := 1
  else if CaseEqual(op, 'ss') then Result := 2
  else if CaseEqual(op, 'ds') then Result := 3
  else if CaseEqual(op, 'fs') then Result := 4
  else if CaseEqual(op, 'gs') then Result := 5
  else Result := -1;
end;

procedure AsmTextLine386(const line: AnsiString; const holes: array of Int64; nHoles: Integer);
var
  mnem, rest, op0, op1: AnsiString;
  i, n, holeCur, commaPos: Integer;
  k0, k1, r0, s0, r1, s1, mb0, md0, mb1, md1: Integer;
  ssePfx, sseOp: Integer;
  imm0, imm1: Int64;
  haveOps: Boolean;
begin
  holeCur := 0;
  { EncMemIndex is the shared encoder's index register for the CURRENT memory
    operand. AsmTextOperand sets it on `[base+index*scale]` and nothing in this
    routine clears it, so without this reset an indexed line leaked its index
    into the next memory operand, in this assembler or in any raw x64enc
    encoder call after it (`mov ecx, [ebp+8]` came out as
    `mov ecx, [ebp+ecx+8]`). EmitAsmX64 resets it per line in
    AsmTextLineMemo; Asm386ProcessLineEx resets it after the line too. }
  EncMemIndex := -1;
  n := Length(line);
  { skip leading spaces }
  i := 1;
  while (i <= n) and AsmTextIsSpace(AsmTextCharAt(line, i)) do Inc(i);
  { mnemonic }
  mnem := '';
  while (i <= n) and not AsmTextIsSpace(AsmTextCharAt(line, i)) do begin AppendChar(mnem, AsmTextLower(line[i])); Inc(i); end;
  { rest = operands }
  rest := '';
  while i <= n do begin AppendChar(rest, line[i]); Inc(i); end;
  haveOps := Length(rest) > 0;

  { zero-operand forms }
  if CaseEqual(mnem, 'ret') then begin EncB($C3); Exit; end;
  if CaseEqual(mnem, 'leave') then begin EncB($C9); Exit; end;
  if CaseEqual(mnem, 'nop') then begin EncB($90); Exit; end;
  if CaseEqual(mnem, 'cdq') then begin EncB($99); Exit; end;
  { cpuid: busybox procps/powertop.c reads the CPU model through it, and its
    four outputs ARE eax/ebx/ecx/edx -- which is also why that block needs the
    ebx save/restore pair the C frontend puts around it. }
  if CaseEqual(mnem, 'cpuid') then begin EncB($0F); EncB($A2); Exit; end;
  if CaseEqual(mnem, 'movsb') then begin EncB($A4); Exit; end;
  if CaseEqual(mnem, 'cld') then begin EncB($FC); Exit; end;
  if CaseEqual(mnem, 'std') then begin EncB($FD); Exit; end;
  if CaseEqual(mnem, 'frndint') then begin EncB($D9); EncB($FC); Exit; end;
  if CaseEqual(mnem, 'stosb') then begin EncB($AA); Exit; end;

  { rep prefix: `rep movsb` / `rep stosb` }
  if CaseEqual(mnem, 'rep') then
  begin
    rest := AsmTextTrim(rest);
    if CaseEqual(rest, 'movsb') then begin EncB($F3); EncB($A4); Exit; end;
    if CaseEqual(rest, 'stosb') then begin EncB($F3); EncB($AA); Exit; end;
    Error('EmitAsm386: unsupported rep string op');
  end;

  if not haveOps then Error('EmitAsm386: unknown 0-operand mnemonic');

  { shld / shrd r/m32, r32, cl|imm8 -- the one three-operand shape here (the
    64-bit shift helpers). Split on the LAST comma and encode the r/m, r part
    like any reg,reg pair: 0F A4/AC ib, 0F A5/AD for cl. }
  if CaseEqual(mnem, 'shld') or CaseEqual(mnem, 'shrd') then
  begin
    commaPos := 0;
    for i := 1 to Length(rest) do
      if rest[i] = ',' then commaPos := i;
    if commaPos = 0 then Error('EmitAsm386: shld/shrd needs three operands');
    op1 := AsmTextTrim(AsmTextSlice(rest, commaPos + 1, Length(rest) - commaPos));
    rest := AsmTextSlice(rest, 1, commaPos - 1);
    commaPos := 0;
    for i := 1 to Length(rest) do
      if (rest[i] = ',') and (commaPos = 0) then commaPos := i;
    if commaPos = 0 then Error('EmitAsm386: shld/shrd needs three operands');
    op0 := AsmTextTrim(AsmTextSlice(rest, 1, commaPos - 1));
    rest := AsmTextTrim(AsmTextSlice(rest, commaPos + 1, Length(rest) - commaPos));
    if (AsmTextOperand(op0, holes, holeCur, r0, s0, mb0, md0, imm0) <> 0) or
       (AsmTextOperand(rest, holes, holeCur, r1, s1, mb1, md1, imm1) <> 0) then
      Error('EmitAsm386: shld/shrd expects two registers');
    if CaseEqual(mnem, 'shld') then i := $A4 else i := $AC;
    if CaseEqual(op1, 'cl') then
    begin
      EncB($0F); EncB(i + 1); EncModRMReg(r1, r0);
    end
    else
    begin
      if AsmTextOperand(op1, holes, holeCur, k0, s0, mb0, md0, imm0) <> 1 then
        Error('EmitAsm386: shld/shrd count must be cl or an immediate');
      EncB($0F); EncB(i); EncModRMReg(r1, r0); EncB(Integer(imm0) and $FF);
    end;
    Exit;
  end;

  { split rest into op0 [, op1] on the first comma }
  commaPos := 0;
  for i := 1 to Length(rest) do
    if (rest[i] = ',') and (commaPos = 0) then commaPos := i;
  if commaPos = 0 then
  begin
    op0 := rest; op1 := '';
  end
  else
  begin
    op0 := AsmTextSlice(rest, 1, commaPos - 1);
    op1 := AsmTextSlice(rest, commaPos + 1, Length(rest) - commaPos);
  end;

  { trim op0 and op1 }
  op0 := AsmTextTrim(op0);
  op1 := AsmTextTrim(op1);

  { Single-operand forms }
  if CaseEqual(mnem, 'push') then
  begin
    k0 := AsmTextOperand(op0, holes, holeCur, r0, s0, mb0, md0, imm0);
    if k0 = 1 then
    begin
      { push imm: 6A ib when it fits a signed byte, else 68 id (as GNU as) }
      if (imm0 >= -128) and (imm0 <= 127) then
        begin EncB($6A); EncB(Integer(imm0) and $FF); end
      else
        begin EncB($68); EncI32(imm0); end;
      Exit;
    end;
    if k0 = 2 then
    begin
      { push dword [mem]: FF /6 }
      if (s0 <> 0) and (s0 <> 4) then Error('EmitAsm386: push [mem] is dword only');
      EncB($FF); EncModRMMem(6, mb0, md0, False);
      Exit;
    end;
    if k0 <> 0 then
      Error('EmitAsm386: push expects a register, an immediate or dword [mem]');
    if s0 = 2 then EncB($66);
    EncB($50 + (r0 and 7));
    Exit;
  end;
  if CaseEqual(mnem, 'pop') then
  begin
    if AsmTextOperand(op0, holes, holeCur, r0, s0, mb0, md0, imm0) <> 0 then
      Error('EmitAsm386: pop expects a register');
    if s0 = 2 then EncB($66);
    EncB($58 + (r0 and 7));
    Exit;
  end;
  if CaseEqual(mnem, 'inc') or CaseEqual(mnem, 'dec') then
  begin
    if AsmTextOperand(op0, holes, holeCur, r0, s0, mb0, md0, imm0) <> 0 then
      Error('EmitAsm386: inc/dec expects a register');
    if s0 = 2 then EncB($66);
    if s0 = 1 then
    begin
      EncB($FE);
      if CaseEqual(mnem, 'dec') then EncModRMReg(1, r0) else EncModRMReg(0, r0);
    end
    else
    begin
      if CaseEqual(mnem, 'dec') then EncB($48 + (r0 and 7)) else EncB($40 + (r0 and 7));
    end;
    Exit;
  end;
  if CaseEqual(mnem, 'div') then
  begin
    if AsmTextOperand(op0, holes, holeCur, r0, s0, mb0, md0, imm0) <> 0 then
      Error('EmitAsm386: div expects a register');
    if s0 = 2 then EncB($66);
    if s0 = 1 then EncB($F6) else EncB($F7);
    EncModRMReg(6, r0);
    Exit;
  end;
  if CaseEqual(mnem, 'int') then
  begin
    if AsmTextOperand(op0, holes, holeCur, r0, s0, mb0, md0, imm0) <> 1 then
      Error('EmitAsm386: int expects an immediate');
    { the compiler's own kernel entries (`int 128`) go through the one i386
      emitter, EmitInt80, so a translated --os can redirect them; inline asm
      a user wrote (EncToAsmBuffer) keeps its bytes. }
    if (imm0 = 128) and (not EncToAsmBuffer) then begin EmitInt80; Exit; end;
    EncB($CD);
    EncB(Integer(imm0) and $FF);
    Exit;
  end;

  { unary F6/F7 group: not/neg/mul/idiv, plus one-operand imul (the two-operand
    imul reg,reg is handled below). ext digit per mnemonic. Register or MEMORY
    -- `mull -8(%ebp)` is what busybox's PSTM_X86 MULADD writes, an `"m"`
    operand multiplied straight out of its frame slot, and it is the only form
    that keeps the multiplier off the five-register pool. A memory operand
    carries no width of its own, so the size keyword is required rather than
    guessed: F7 on a byte slot is a silent 4-byte read. }
  if (Length(op1) = 0) and (CaseEqual(mnem, 'not') or CaseEqual(mnem, 'neg') or
     CaseEqual(mnem, 'mul') or CaseEqual(mnem, 'idiv') or CaseEqual(mnem, 'imul')) then
  begin
    k0 := AsmTextOperand(op0, holes, holeCur, r0, s0, mb0, md0, imm0);
    if (k0 <> 0) and (k0 <> 2) then
      Error('EmitAsm386: unary op expects a register or a memory operand');
    if CaseEqual(mnem, 'not') then i := 2
    else if CaseEqual(mnem, 'neg') then i := 3
    else if CaseEqual(mnem, 'mul') then i := 4
    else if CaseEqual(mnem, 'imul') then i := 5
    else i := 7;   { idiv }
    if (k0 = 2) and (s0 = 0) then
      Error('EmitAsm386: unary op on memory needs an explicit size (byte/word/dword)');
    if s0 = 2 then EncB($66);
    if s0 = 1 then EncB($F6) else EncB($F7);
    if k0 = 2 then EncModRMMem(i, mb0, md0, False)
    else EncModRMReg(i, r0);
    Exit;
  end;

  { call reg (indirect, FF /2) }
  if CaseEqual(mnem, 'call') then
  begin
    if AsmTextOperand(op0, holes, holeCur, r0, s0, mb0, md0, imm0) <> 0 then
      Error('EmitAsm386: call expects a register');
    EncB($FF); EncModRMReg(2, r0);
    Exit;
  end;

  { stmxcsr / ldmxcsr [mem]: 0F AE /3 and /2 (the C fenv stubs) }
  if CaseEqual(mnem, 'stmxcsr') or CaseEqual(mnem, 'ldmxcsr') then
  begin
    if AsmTextOperand(op0, holes, holeCur, r0, s0, mb0, md0, imm0) <> 2 then
      Error('EmitAsm386: stmxcsr/ldmxcsr expects a memory operand');
    EncB($0F); EncB($AE);
    if CaseEqual(mnem, 'stmxcsr') then EncModRMMem(3, mb0, md0, False)
    else EncModRMMem(2, mb0, md0, False);
    Exit;
  end;

  { x87 memory operands: the float<->int and rounding-mode helpers. The
    width comes from the size keyword, which is required (as in GNU as Intel
    syntax). opcode/digit per width. }
  if CaseEqual(mnem, 'fld') or CaseEqual(mnem, 'fst') or CaseEqual(mnem, 'fstp') or
     CaseEqual(mnem, 'fild') or CaseEqual(mnem, 'fistp') or CaseEqual(mnem, 'fisttp') or
     CaseEqual(mnem, 'fldcw') or CaseEqual(mnem, 'fnstcw') then
  begin
    if AsmTextOperand(op0, holes, holeCur, r0, s0, mb0, md0, imm0) <> 2 then
      Error('EmitAsm386: x87 op expects a memory operand');
    i := -1; k1 := 0;
    if CaseEqual(mnem, 'fldcw') then begin i := $D9; k1 := 5; end
    else if CaseEqual(mnem, 'fnstcw') then begin i := $D9; k1 := 7; end
    else if s0 = 4 then
    begin
      if CaseEqual(mnem, 'fld') then begin i := $D9; k1 := 0; end
      else if CaseEqual(mnem, 'fst') then begin i := $D9; k1 := 2; end
      else if CaseEqual(mnem, 'fstp') then begin i := $D9; k1 := 3; end
      else if CaseEqual(mnem, 'fild') then begin i := $DB; k1 := 0; end
      else if CaseEqual(mnem, 'fistp') then begin i := $DB; k1 := 3; end
      else begin i := $DB; k1 := 1; end;   { fisttp }
    end
    else if s0 = 8 then
    begin
      if CaseEqual(mnem, 'fld') then begin i := $DD; k1 := 0; end
      else if CaseEqual(mnem, 'fst') then begin i := $DD; k1 := 2; end
      else if CaseEqual(mnem, 'fstp') then begin i := $DD; k1 := 3; end
      else if CaseEqual(mnem, 'fild') then begin i := $DF; k1 := 5; end
      else if CaseEqual(mnem, 'fistp') then begin i := $DF; k1 := 7; end
      else begin i := $DD; k1 := 1; end;   { fisttp }
    end;
    if i < 0 then Error('EmitAsm386: x87 memory operand needs dword or qword');
    EncB(i); EncModRMMem(k1, mb0, md0, False);
    Exit;
  end;

  { setcc reg8 (0F 90+cc, /0): map the cc suffix through the jcc table. }
  if (Length(mnem) >= 4) and (AsmTextCharAt(mnem, 1) = 's') and
     (AsmTextCharAt(mnem, 2) = 'e') and (AsmTextCharAt(mnem, 3) = 't') then
  begin
    rest := 'j' + AsmTextSlice(mnem, 4, Length(mnem) - 3);
    if not AsmTextJccCode(rest, i) then Error('EmitAsm386: unknown setcc');
    if AsmTextOperand(op0, holes, holeCur, r0, s0, mb0, md0, imm0) <> 0 then
      Error('EmitAsm386: setcc expects a register');
    EncB($0F); EncB($90 + (i and 15)); EncModRMReg(0, r0);
    Exit;
  end;

  { Two-operand forms }
  if Length(op1) = 0 then Error('EmitAsm386: instruction needs two operands');

  { Relocations: mov reg, @data / mov reg, @glob }
  if CaseEqual(mnem, 'mov') and (CaseEqual(op1, '@data') or CaseEqual(op1, '@glob')) then
  begin
    if not AsmRegNum(op0, r0, s0) then
      Error('EmitAsm386: reloc mov expects a destination register');
    imm0 := holes[holeCur]; Inc(holeCur);
    if s0 = 2 then EncB($66);
    EncB($B8 + (r0 and 7));
    if CaseEqual(op1, '@data') then EmitDataRef(imm0) else EmitGlobRef(imm0);
    Exit;
  end;

  { mov r32, sreg (8C /r) / mov sreg, r32 (8E /r): the TLS selector dance in
    the i386 thread stubs. es cs ss ds fs gs = 0..5. }
  if CaseEqual(mnem, 'mov') and ((Asm386SegReg(op0) >= 0) or (Asm386SegReg(op1) >= 0)) then
  begin
    if Asm386SegReg(op1) >= 0 then
    begin
      if not AsmRegNum(op0, r0, s0) then Error('EmitAsm386: mov from a segment register needs a register');
      EncB($8C); EncModRMReg(Asm386SegReg(op1), r0);
    end
    else
    begin
      if not AsmRegNum(op1, r1, s1) then Error('EmitAsm386: mov to a segment register needs a register');
      EncB($8E); EncModRMReg(Asm386SegReg(op0), r1);
    end;
    Exit;
  end;

  k0 := AsmTextOperand(op0, holes, holeCur, r0, s0, mb0, md0, imm0);
  k1 := AsmTextOperand(op1, holes, holeCur, r1, s1, mb1, md1, imm1);

  { shifts: shl/sal, shr, sar — reg by imm, by 1, or by cl }
  if CaseEqual(mnem, 'shl') or CaseEqual(mnem, 'sal') or
     CaseEqual(mnem, 'shr') or CaseEqual(mnem, 'sar') or
     CaseEqual(mnem, 'rol') or CaseEqual(mnem, 'ror') or
     CaseEqual(mnem, 'rcl') or CaseEqual(mnem, 'rcr') then
  begin
    if k0 <> 0 then Error('EmitAsm386: shift expects a register dest');
    if CaseEqual(mnem, 'shr') then i := 5
    else if CaseEqual(mnem, 'sar') then i := 7
    else if CaseEqual(mnem, 'rol') then i := 0
    else if CaseEqual(mnem, 'ror') then i := 1
    else if CaseEqual(mnem, 'rcl') then i := 2
    else if CaseEqual(mnem, 'rcr') then i := 3
    else i := 4;   { shl / sal }
    if s0 = 2 then EncB($66);
    if (k1 = 0) and (r1 = 1) then   { ,cl }
    begin
      if s0 = 1 then EncB($D2) else EncB($D3);
      EncModRMReg(i, r0);
    end
    else if (k1 = 1) and (imm1 = 1) then
    begin
      if s0 = 1 then EncB($D0) else EncB($D1);
      EncModRMReg(i, r0);
    end
    else if k1 = 1 then
    begin
      if s0 = 1 then EncB($C0) else EncB($C1);
      EncModRMReg(i, r0); EncB(Integer(imm1) and $FF);
    end
    else Error('EmitAsm386: shift count must be imm or cl');
    Exit;
  end;

  { imul reg, reg (two-operand, 0F AF /r) }
  if CaseEqual(mnem, 'imul') then
  begin
    if (k0 = 0) and (k1 = 0) then
    begin
      if s0 = 2 then EncB($66);
      EncB($0F); EncB($AF); EncModRMReg(r0, r1);
      Exit;
    end;
    if (k0 = 0) and (k1 = 2) then
    begin
      if s0 = 2 then EncB($66);
      EncB($0F); EncB($AF); EncModRMMem(r0, mb1, md1, False);
      Exit;
    end;
    Error('EmitAsm386: unsupported imul form');
  end;

  { xchg: 90+r when one side is eax (as GNU as picks), else 87 /r with the
    register in the reg field. }
  if CaseEqual(mnem, 'xchg') then
  begin
    if (k0 = 0) and (k1 = 0) and (s0 = 4) and (s1 = 4) and ((r0 = 0) or (r1 = 0)) then
    begin
      if r0 = 0 then EncB($90 + (r1 and 7)) else EncB($90 + (r0 and 7));
      Exit;
    end;
    if (k0 = 0) and (k1 = 0) then
    begin
      if s0 = 2 then EncB($66);
      if s0 = 1 then EncB($86) else EncB($87);
      EncModRMReg(r1, r0);
      Exit;
    end;
    if (k0 = 2) and (k1 = 0) then
    begin
      if s1 = 2 then EncB($66);
      if s1 = 1 then EncB($86) else EncB($87);
      EncModRMMem(r1, mb0, md0, False);
      Exit;
    end;
    if (k0 = 0) and (k1 = 2) then
    begin
      if s0 = 2 then EncB($66);
      if s0 = 1 then EncB($86) else EncB($87);
      EncModRMMem(r0, mb1, md1, False);
      Exit;
    end;
    Error('EmitAsm386: unsupported xchg form');
  end;

  { movd xmm, r32 (66 0F 6E) / movd r32, xmm (66 0F 7E); xmm in the reg field }
  if CaseEqual(mnem, 'movd') then
  begin
    if (k0 = 0) and (k1 = 0) and (s0 = 16) and (s1 = 4) then
    begin
      EncB($66); EncB($0F); EncB($6E); EncModRMReg(r0, r1); Exit;
    end;
    if (k0 = 0) and (k1 = 0) and (s0 = 4) and (s1 = 16) then
    begin
      EncB($66); EncB($0F); EncB($7E); EncModRMReg(r1, r0); Exit;
    end;
    Error('EmitAsm386: unsupported movd form');
  end;

  { movzx / movsx reg, reg|mem. srcSize 1 or 2. }
  if CaseEqual(mnem, 'movzx') or CaseEqual(mnem, 'movsx') then
  begin
    if k0 <> 0 then Error('EmitAsm386: movzx/movsx dest must be a register');
    if s0 = 2 then EncB($66);
    EncB($0F);
    if k1 = 0 then
    begin
      if CaseEqual(mnem, 'movsx') then
        begin if s1 = 1 then EncB($BE) else EncB($BF); end
      else begin if s1 = 1 then EncB($B6) else EncB($B7); end;
      EncModRMReg(r0, r1);
    end
    else if k1 = 2 then
    begin
      if s1 = 0 then Error('EmitAsm386: movzx/movsx mem needs an explicit size (byte/word)');
      if CaseEqual(mnem, 'movsx') then
        begin if s1 = 1 then EncB($BE) else EncB($BF); end
      else begin if s1 = 1 then EncB($B6) else EncB($B7); end;
      EncModRMMem(r0, mb1, md1, False);
    end
    else Error('EmitAsm386: unsupported movzx/movsx form');
    Exit;
  end;

  { test: reg,reg | reg,imm | reg,[mem] | [mem],reg | [mem],imm }
  if CaseEqual(mnem, 'test') then
  begin
    if (k0 = 0) and (k1 = 0) then
    begin
      if s0 = 2 then EncB($66);
      if s0 = 1 then EncB($84) else EncB($85);
      EncModRMReg(r1, r0);
    end
    else if (k0 = 0) and (k1 = 1) then
    begin
      if s0 = 2 then EncB($66);
      if r0 = 0 then
      begin
        { al/ax/eax: the accumulator form A8 ib / A9 iw|id, as GNU as picks }
        if s0 = 1 then begin EncB($A8); EncB(Integer(imm1) and $FF); end
        else begin EncB($A9); if s0 = 2 then EncI16(imm1) else EncI32(imm1); end;
      end
      else if s0 = 1 then begin EncB($F6); EncModRMReg(0, r0); EncB(Integer(imm1) and $FF); end
      else begin EncB($F7); EncModRMReg(0, r0);
        if s0 = 2 then EncI16(imm1) else EncI32(imm1); end;
    end
    else if (k0 = 0) and (k1 = 2) then
    begin
      if s0 = 2 then EncB($66);
      if s0 = 1 then EncB($84) else EncB($85);
      EncModRMMem(r0, mb1, md1, False);
    end
    else if (k0 = 2) and (k1 = 0) then
    begin
      if s1 = 2 then EncB($66);
      if s1 = 1 then EncB($84) else EncB($85);
      EncModRMMem(r1, mb0, md0, False);
    end
    else if (k0 = 2) and (k1 = 1) then
    begin
      if s0 = 0 then Error('EmitAsm386: test mem,imm needs an explicit size');
      if s0 = 2 then EncB($66);
      if s0 = 1 then begin EncB($F6); EncModRMMem(0, mb0, md0, False); EncB(Integer(imm1) and $FF); end
      else begin EncB($F7); EncModRMMem(0, mb0, md0, False);
        if s0 = 2 then EncI16(imm1) else EncI32(imm1); end;
    end
    else Error('EmitAsm386: unsupported test form');
    Exit;
  end;

  { SSE scalar (i386 uses SSE2 for float, not x87). [prefix] 0F opcode ModRM,
    no REX. movsd/movss have a store opcode (11) for the [mem],xmm direction;
    cvtsi2sd/cvttsd2si/cvt*2* share the regField=op0 rm=op1 shape. }
  if CaseEqual(mnem, 'movsd') or CaseEqual(mnem, 'movss') or
     CaseEqual(mnem, 'addsd') or CaseEqual(mnem, 'subsd') or
     CaseEqual(mnem, 'mulsd') or CaseEqual(mnem, 'divsd') or
     CaseEqual(mnem, 'addss') or CaseEqual(mnem, 'subss') or
     CaseEqual(mnem, 'mulss') or CaseEqual(mnem, 'divss') or
     CaseEqual(mnem, 'comisd') or CaseEqual(mnem, 'ucomisd') or
     CaseEqual(mnem, 'cvtsi2sd') or CaseEqual(mnem, 'cvttsd2si') or
     CaseEqual(mnem, 'cvtsd2ss') or CaseEqual(mnem, 'cvtss2sd') or
     CaseEqual(mnem, 'xorps') or CaseEqual(mnem, 'xorpd') or CaseEqual(mnem, 'pxor') then
  begin
    if CaseEqual(mnem, 'movss') or CaseEqual(mnem, 'addss') or CaseEqual(mnem, 'subss') or
       CaseEqual(mnem, 'mulss') or CaseEqual(mnem, 'divss') or CaseEqual(mnem, 'cvtss2sd') then
      ssePfx := $F3
    else if CaseEqual(mnem, 'comisd') or CaseEqual(mnem, 'ucomisd') or
            CaseEqual(mnem, 'xorpd') or CaseEqual(mnem, 'pxor') then ssePfx := $66
    else if CaseEqual(mnem, 'xorps') then ssePfx := 0
    else ssePfx := $F2;
    if CaseEqual(mnem, 'movsd') or CaseEqual(mnem, 'movss') then sseOp := $10
    else if CaseEqual(mnem, 'addsd') or CaseEqual(mnem, 'addss') then sseOp := $58
    else if CaseEqual(mnem, 'subsd') or CaseEqual(mnem, 'subss') then sseOp := $5C
    else if CaseEqual(mnem, 'mulsd') or CaseEqual(mnem, 'mulss') then sseOp := $59
    else if CaseEqual(mnem, 'divsd') or CaseEqual(mnem, 'divss') then sseOp := $5E
    else if CaseEqual(mnem, 'comisd') then sseOp := $2F
    else if CaseEqual(mnem, 'ucomisd') then sseOp := $2E
    else if CaseEqual(mnem, 'cvtsi2sd') then sseOp := $2A
    else if CaseEqual(mnem, 'cvttsd2si') then sseOp := $2C
    else if CaseEqual(mnem, 'cvtsd2ss') or CaseEqual(mnem, 'cvtss2sd') then sseOp := $5A
    else if CaseEqual(mnem, 'pxor') then sseOp := $EF
    else sseOp := $57;   { xorps / xorpd }
    if (k0 = 0) and (k1 = 0) then
    begin
      if ssePfx <> 0 then EncB(ssePfx);
      EncB($0F); EncB(sseOp); EncModRMReg(r0, r1);
    end
    else if (k0 = 0) and (k1 = 2) then
    begin
      if ssePfx <> 0 then EncB(ssePfx);
      EncB($0F); EncB(sseOp); EncModRMMem(r0, mb1, md1, False);
    end
    else if (k0 = 2) and (k1 = 0) and (CaseEqual(mnem, 'movsd') or CaseEqual(mnem, 'movss')) then
    begin
      if ssePfx <> 0 then EncB(ssePfx);
      EncB($0F); EncB($11); EncModRMMem(r1, mb0, md0, False);   { store xmm -> [mem] }
    end
    else Error('EmitAsm386: unsupported SSE form');
    Exit;
  end;

  if CaseEqual(mnem, 'mov') then
  begin
    { mov reg, reg }
    if (k0 = 0) and (k1 = 0) then
    begin
      if s0 = 2 then EncB($66);
      if s0 = 1 then EncB($88) else EncB($89);
      EncModRMReg(r1, r0);
      Exit;
    end;
    { mov reg, imm }
    if (k0 = 0) and (k1 = 1) then
    begin
      if s0 = 2 then EncB($66);
      if s0 = 1 then
      begin
        EncB($B0 + (r0 and 7));
        EncB(Integer(imm1) and $FF);
      end
      else if s0 = 2 then
      begin
        EncB($B8 + (r0 and 7));
        EncI16(imm1);
      end
      else
      begin
        EncB($B8 + (r0 and 7));
        EncI32(imm1);
      end;
      Exit;
    end;
    { mov reg, mem }
    if (k0 = 0) and (k1 = 2) then
    begin
      if s0 = 2 then EncB($66);
      if s0 = 1 then EncB($8A) else EncB($8B);
      EncModRMMem(r0, mb1, md1, False);
      Exit;
    end;
    { mov mem, reg }
    if (k0 = 2) and (k1 = 0) then
    begin
      if s1 = 2 then EncB($66);
      if s1 = 1 then EncB($88) else EncB($89);
      EncModRMMem(r1, mb0, md0, False);
      Exit;
    end;
    { mov mem, imm }
    if (k0 = 2) and (k1 = 1) then
    begin
      if s0 = 2 then EncB($66);
      if s0 = 1 then EncB($C6) else EncB($C7);
      EncModRMMem(0, mb0, md0, False);
      if s0 = 1 then EncB(Integer(imm1) and $FF)
      else if s0 = 2 then EncI16(imm1)
      else EncI32(imm1);
      Exit;
    end;
    Error('EmitAsm386: unsupported mov form');
  end;

  if CaseEqual(mnem, 'lea') then
  begin
    if (k0 = 0) and (k1 = 2) then
    begin
      if s0 = 2 then EncB($66);
      EncB($8D);
      EncModRMMem(r0, mb1, md1, False);
      Exit;
    end;
    Error('EmitAsm386: unsupported lea form');
  end;

  { ALU reg, imm or reg, reg }
  if (k0 = 0) and (k1 = 1) then
  begin
    if CaseEqual(mnem, 'add') then i := 0
    else if CaseEqual(mnem, 'or')  then i := 1
    else if CaseEqual(mnem, 'adc') then i := 2
    else if CaseEqual(mnem, 'sbb') then i := 3
    else if CaseEqual(mnem, 'and') then i := 4
    else if CaseEqual(mnem, 'sub') then i := 5
    else if CaseEqual(mnem, 'xor') then i := 6
    else if CaseEqual(mnem, 'cmp') then i := 7
    else begin Error('EmitAsm386: unsupported ALU reg,imm mnemonic'); i := 0; end;

    { a 32-bit operand reads its immediate modulo 2^32, as GNU as does:
      `and eax, 0xfffffff0` IS `and eax, -16` and takes the imm8 form }
    if (s0 = 4) and (imm1 >= $80000000) and (imm1 <= $FFFFFFFF) then
      imm1 := imm1 - $100000000;
    if s0 = 2 then EncB($66);
    { al/ax/eax take the one-byte-shorter accumulator form (04+8*op ib,
      05+8*op iw|id) where GNU as does: always for al, and for ax/eax when the
      immediate does not fit the sign-extended imm8 of 83 /op. }
    if (r0 = 0) and (s0 = 1) then
    begin
      EncB($04 + i * 8); EncB(Integer(imm1) and $FF);
    end
    else if s0 = 1 then
    begin
      EncB($80); EncModRMReg(i, r0); EncB(Integer(imm1) and $FF);
    end
    else if (imm1 >= -128) and (imm1 <= 127) then
    begin
      EncB($83); EncModRMReg(i, r0); EncB(Integer(imm1) and $FF);
    end
    else if r0 = 0 then
    begin
      EncB($05 + i * 8);
      if s0 = 2 then EncI16(imm1) else EncI32(imm1);
    end
    else
    begin
      EncB($81); EncModRMReg(i, r0);
      if s0 = 2 then EncI16(imm1) else EncI32(imm1);
    end;
    Exit;
  end;

  if (k0 = 0) and (k1 = 0) then
  begin
    if CaseEqual(mnem, 'add') then mb0 := $01
    else if CaseEqual(mnem, 'or')  then mb0 := $09
    else if CaseEqual(mnem, 'adc') then mb0 := $11
    else if CaseEqual(mnem, 'sbb') then mb0 := $19
    else if CaseEqual(mnem, 'and') then mb0 := $21
    else if CaseEqual(mnem, 'sub') then mb0 := $29
    else if CaseEqual(mnem, 'xor') then mb0 := $31
    else if CaseEqual(mnem, 'cmp') then mb0 := $39
    else begin Error('EmitAsm386: unsupported ALU reg,reg mnemonic'); mb0 := 0; end;

    if s0 = 2 then EncB($66);
    if s0 = 1 then EncB(mb0 - 1) else EncB(mb0);
    EncModRMReg(r1, r0);
    Exit;
  end;

  { ALU reg,[mem] and [mem],reg. i = even (m,r) opcode; r,m = i+2. }
  if ((k0 = 0) and (k1 = 2)) or ((k0 = 2) and (k1 = 0)) then
  begin
    if CaseEqual(mnem, 'add') then i := $01
    else if CaseEqual(mnem, 'or')  then i := $09
    else if CaseEqual(mnem, 'adc') then i := $11
    else if CaseEqual(mnem, 'sbb') then i := $19
    else if CaseEqual(mnem, 'and') then i := $21
    else if CaseEqual(mnem, 'sub') then i := $29
    else if CaseEqual(mnem, 'xor') then i := $31
    else if CaseEqual(mnem, 'cmp') then i := $39
    else begin Error('EmitAsm386: unsupported reg/mem ALU mnemonic'); i := 0; end;
    if k1 = 2 then   { reg,[mem] — r,m opcode = even+2 }
    begin
      if s0 = 2 then EncB($66);
      if s0 = 1 then EncB(i + 1) else EncB(i + 2);
      EncModRMMem(r0, mb1, md1, False);
    end
    else             { [mem],reg — m,r opcode = even }
    begin
      if s1 = 2 then EncB($66);
      if s1 = 1 then EncB(i - 1) else EncB(i);
      EncModRMMem(r1, mb0, md0, False);
    end;
    Exit;
  end;

  { ALU mem, imm }
  if (k0 = 2) and (k1 = 1) then
  begin
    if s0 = 0 then Error('EmitAsm386: memory ALU needs an explicit size (byte/word/dword)');
    if CaseEqual(mnem, 'add') then i := 0
    else if CaseEqual(mnem, 'or')  then i := 1
    else if CaseEqual(mnem, 'adc') then i := 2
    else if CaseEqual(mnem, 'sbb') then i := 3
    else if CaseEqual(mnem, 'and') then i := 4
    else if CaseEqual(mnem, 'sub') then i := 5
    else if CaseEqual(mnem, 'xor') then i := 6
    else if CaseEqual(mnem, 'cmp') then i := 7
    else begin Error('EmitAsm386: unsupported ALU mem,imm mnemonic'); i := 0; end;

    if s0 = 2 then EncB($66);
    if s0 = 1 then
    begin
      EncB($80); EncModRMMem(i, mb0, md0, False); EncB(Integer(imm1) and $FF);
    end
    else if (imm1 >= -128) and (imm1 <= 127) then
    begin
      EncB($83); EncModRMMem(i, mb0, md0, False); EncB(Integer(imm1) and $FF);
    end
    else
    begin
      EncB($81); EncModRMMem(i, mb0, md0, False);
      if s0 = 2 then EncI16(imm1) else EncI32(imm1);
    end;
    Exit;
  end;

  Error('EmitAsm386: unsupported instruction: ' + mnem);
end;

{ Block-scoped label state around Asm386ProcessLine calls. EmitAsm386 is one
  begin/lines/resolve cycle; the inline-asm IR_ASM replay in
  ir_codegen386.inc is another (labels are scoped to one asm block). }
procedure Asm386BlockBegin;
begin
  Asm386LblCount := 0; Asm386FwCount := 0;
end;

{ Process one already-hole-resolved line: label definition, jmp/jcc to a
  label (recorded for Asm386BlockResolve when forward), or an ordinary
  instruction via AsmTextLine386.

  The jump forms match EmitAsmX64 (asmtext.inc), so raw i386 byte runs convert
  the same way the x86-64 ones did:
  - a dotless label is a SCOPE label when the caller allows it (EmitAsm386
    does; the inline-asm replay does not, since a user's `loop:` must stay
    local to its asm block) and a scope is open (AsmScopeBegin/AsmScopeEnd,
    asmscope.inc). It lives across calls and the Pascal between them.
  - `short` / `near` force rel8 / rel32. Without one a known target takes
    rel8 when it reaches and a forward one takes rel32.
  - `jmp @code` / `jcc @code` / `call @code`: rel32 (or `short`) to the code
    position in the line's first hole.
  - `jcc +5` / `jmp -3`: a constant rel8 field. }
procedure Asm386ProcessLineEx(const line: AnsiString; const holes: array of Int64; nHoles: Integer;
  allowScope: Boolean);
var
  trimmed, mnem, target: AnsiString;
  j, k, cc, targetPos, disp, width: Integer;
  isJmp, isCall, defined, scoped: Boolean;
begin
  trimmed := AsmTextTrim(line);

  { first word = mnemonic }
  mnem := ''; j := 1;
  while (j <= Length(trimmed)) and not AsmTextIsSpace(AsmTextCharAt(trimmed, j)) do
    begin AppendChar(mnem, AsmTextLower(trimmed[j])); Inc(j); end;
  while (j <= Length(trimmed)) and AsmTextIsSpace(AsmTextCharAt(trimmed, j)) do Inc(j);
  target := AsmTextSlice(trimmed, j, Length(trimmed) - j + 1);

  if (Length(trimmed) >= 2) and (AsmTextCharAt(trimmed, Length(trimmed)) = ':') then
  begin
    { label definition: `name:` (a bare line ending in ':') }
    target := AsmTextSlice(trimmed, 1, Length(trimmed) - 1);
    if allowScope and AsmIsScopeLabel(target) then
    begin
      if AsmScopeFind(target, disp) then
        Error('EmitAsm386: scope label defined twice: ' + target);
      if AsmSLblCount >= ASM_SCOPE_MAX_LABELS then Error('EmitAsm386: too many scope labels');
      AsmSLblName[AsmSLblCount] := target;
      AsmSLblPos[AsmSLblCount] := CodeLen;
      Inc(AsmSLblCount);
      Exit;
    end;
    if Asm386LblCount >= ASM_386_MAX_LABELS then Error('EmitAsm386: too many labels');
    Asm386LblName[Asm386LblCount] := target;
    Asm386LblPos[Asm386LblCount] := CodeLen;
    Inc(Asm386LblCount);
    Exit;
  end;

  isJmp := CaseEqual(mnem, 'jmp');
  isCall := CaseEqual(mnem, 'call') and CaseEqual(target, '@code');
  { an indirect jmp (register or memory) is an ordinary instruction }
  if isJmp then
    if (AsmTextCharAt(target, 1) = '[') or (AsmTextSizeKeyword(AsmTextSlice(target, 1, 5)) > 0) or
       AsmRegNum(target, k, disp) then
      isJmp := False;

  if isJmp or isCall or AsmTextJccCode(mnem, cc) then
  begin
    width := 0;
    if (Length(target) > 6) and CaseEqual(AsmTextSlice(target, 1, 6), 'short ') then
    begin
      width := 1; target := AsmTextTrim(AsmTextSlice(target, 7, Length(target) - 6));
    end
    else if (Length(target) > 5) and CaseEqual(AsmTextSlice(target, 1, 5), 'near ') then
    begin
      width := 2; target := AsmTextTrim(AsmTextSlice(target, 6, Length(target) - 5));
    end;

    if CaseEqual(target, '@code') then
    begin
      if nHoles < 1 then Error('EmitAsm386: @code needs an integer code position');
      targetPos := Integer(holes[0]);
      if width = 1 then
      begin
        if isCall then Error('EmitAsm386: there is no short call');
        if isJmp then EncB($EB) else EncB($70 + cc);
        disp := targetPos - (CodeLen + 1);
        CheckRel8(disp, 'asm386 short jump to @code');
        EncB(disp and $FF);
      end
      else
      begin
        if isCall then EncB($E8)
        else if isJmp then EncB($E9)
        else begin EncB($0F); EncB($80 + cc); end;
        EncI32(targetPos - (CodeLen + 4));
      end;
      Exit;
    end;
    if isCall then Error('EmitAsm386: call takes a register or @code');

    if (Length(target) >= 1) and
       ((target[1] = '+') or (target[1] = '-') or ((target[1] >= '0') and (target[1] <= '9'))) then
    begin
      disp := 0; k := 1;
      if (target[1] = '+') or (target[1] = '-') then k := 2;
      if k > Length(target) then Error('EmitAsm386: bad constant jump displacement');
      while k <= Length(target) do
      begin
        if (target[k] < '0') or (target[k] > '9') then
          Error('EmitAsm386: bad constant jump displacement');
        disp := disp * 10 + (Ord(target[k]) - Ord('0'));
        Inc(k);
      end;
      if target[1] = '-' then disp := -disp;
      if (disp < -128) or (disp > 127) then
        Error('EmitAsm386: constant jump displacement out of rel8 range');
      if isJmp then EncB($EB) else EncB($70 + cc);
      EncB(disp and $FF);
      Exit;
    end;

    defined := False; targetPos := 0;
    scoped := allowScope and AsmIsScopeLabel(target);
    if scoped then
      defined := AsmScopeFind(target, targetPos)
    else
      for k := 0 to Asm386LblCount - 1 do
        if Asm386LblName[k] = target then begin defined := True; targetPos := Asm386LblPos[k]; end;

    if defined then
    begin
      { backward (or same-call known) target: short form if it reaches. }
      disp := targetPos - (CodeLen + 2);
      if width = 1 then CheckRel8(disp, 'asm386 short back jump');
      if (width <> 2) and (disp >= -128) and (disp <= 127) then
      begin
        if isJmp then EncB($EB) else EncB($70 + cc);
        EncB(disp and $FF);
      end
      else
      begin
        if isJmp then begin EncB($E9); EncI32(targetPos - (CodeLen + 4)); end
        else begin EncB($0F); EncB($80 + cc); EncI32(targetPos - (CodeLen + 4)); end;
      end;
    end
    else
    begin
      { forward target: rel32, or rel8 under `short`, patched at block or
        scope end. }
      if width = 1 then
      begin
        if isJmp then EncB($EB) else EncB($70 + cc);
      end
      else if isJmp then EncB($E9) else begin EncB($0F); EncB($80 + cc); end;
      if scoped then
      begin
        if AsmSFwCount >= ASM_SCOPE_MAX_LABELS then Error('EmitAsm386: too many scope forward jumps');
        AsmSFwName[AsmSFwCount] := target;
        AsmSFwPatch[AsmSFwCount] := CodeLen;
        AsmSFwShort[AsmSFwCount] := width = 1;
        Inc(AsmSFwCount);
      end
      else
      begin
        if Asm386FwCount >= ASM_386_MAX_LABELS then Error('EmitAsm386: too many forward jumps');
        Asm386FwName[Asm386FwCount] := target;
        Asm386FwPatch[Asm386FwCount] := CodeLen;   { position of the displacement }
        Asm386FwShort[Asm386FwCount] := width = 1;
        Inc(Asm386FwCount);
      end;
      if width = 1 then EncB(0) else EncI32(0);
    end;
    Exit;
  end;

  { ordinary instruction }
  AsmTextLine386(line, holes, nHoles);
  EncMemIndex := -1;
end;

procedure Asm386ProcessLine(const line: AnsiString; const holes: array of Int64; nHoles: Integer);
begin
  Asm386ProcessLineEx(line, holes, nHoles, False);
end;

{ resolve forward jumps now that all labels are placed. }
procedure Asm386BlockResolve;
var j, k, targetPos: Integer;
begin
  for k := 0 to Asm386FwCount - 1 do
  begin
    targetPos := -1;
    for j := 0 to Asm386LblCount - 1 do
      if Asm386LblName[j] = Asm386FwName[k] then targetPos := Asm386LblPos[j];
    if targetPos < 0 then Error('EmitAsm386: undefined label in jump: ' + Asm386FwName[k]);
    AsmPatchFw(Asm386FwPatch[k], targetPos, Asm386FwShort[k]);
  end;
end;

{ Replay one parse-time-captured inline-asm line (AsmParseBodyText386, see
  asmenc.inc). Hole values come from the InlineAsmHoleVal pool, count stored
  explicitly per line (NOT derived from '%' — a @glob operand consumes a
  hole without one). Caller brackets a block with Asm386BlockBegin/Resolve. }
procedure Asm386ProcessInlineLine(idx: Integer);
var
  holes: array[0..ASM_MAX_HOLES - 1] of Int64;
  k: Integer;
begin
  if InlineAsmLineHoleN[idx] > ASM_MAX_HOLES then
    Error('EmitAsm386: too many holes in one line');
  for k := 0 to InlineAsmLineHoleN[idx] - 1 do
    holes[k] := InlineAsmHoleVal[InlineAsmLineHole0[idx] + k];
  Asm386ProcessLine(InlineAsmLine[idx], holes, InlineAsmLineHoleN[idx]);
end;

procedure EmitAsm386(const items: array of const); overload;
var
  i, n, h, nHoles, j: Integer;
  line: AnsiString;
  holes: array[0..ASM_MAX_HOLES - 1] of Int64;
begin
  Asm386BlockBegin;
  n := Length(items);
  i := 0;
  while i < n do
  begin
    if items[i].VType <> vtAnsiString then
      Error('EmitAsm386: expected an instruction string');
    line := AsmTextCStr(items[i].VAnsiString);

    { count `%` markers and bind following int holes }
    nHoles := 0;
    for h := 1 to Length(line) do
      if line[h] = '%' then Inc(nHoles);

    { also count `@data` or `@glob` as hole consumers if present }
    j := 1;
    while j <= Length(line) do
    begin
      if (AsmTextCharAt(line, j) = '@') and
         ((AsmTextSlice(line, j, 5) = '@data') or (AsmTextSlice(line, j, 5) = '@glob') or
          (AsmTextSlice(line, j, 5) = '@code')) then
      begin
        Inc(nHoles);
        j := j + 4;
      end;
      Inc(j);
    end;

    if nHoles > ASM_MAX_HOLES then Error('EmitAsm386: too many holes in one line');
    for h := 0 to nHoles - 1 do
    begin
      if (i + 1 + h >= n) or (items[i + 1 + h].VType <> vtInteger) and (items[i + 1 + h].VType <> vtInt64) then
        Error('EmitAsm386: missing integer hole value');
      if items[i + 1 + h].VType = vtInt64 then holes[h] := PHoleI64(items[i + 1 + h].VInt64)^ else holes[h] := items[i + 1 + h].VInteger;
    end;
    Asm386ProcessLineEx(line, holes, nHoles, True);
    i := i + 1 + nHoles;
  end;
  Asm386BlockResolve;
end;

procedure EmitAsm386(const s: AnsiString); overload;
begin
  EmitAsm386([s]);
end;
