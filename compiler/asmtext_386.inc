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
  Asm386FwCount:  Integer;

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
  if CaseEqual(mnem, 'movsb') then begin EncB($A4); Exit; end;
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
    if AsmTextOperand(op0, holes, holeCur, r0, s0, mb0, md0, imm0) <> 0 then
      Error('EmitAsm386: push expects a register');
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
    EncB($CD);
    EncB(Integer(imm0) and $FF);
    Exit;
  end;

  { unary F6/F7 group on a register: not/neg/mul/idiv, plus one-operand imul
    (the two-operand imul reg,reg is handled below). ext digit per mnemonic. }
  if (Length(op1) = 0) and (CaseEqual(mnem, 'not') or CaseEqual(mnem, 'neg') or
     CaseEqual(mnem, 'mul') or CaseEqual(mnem, 'idiv') or CaseEqual(mnem, 'imul')) then
  begin
    if AsmTextOperand(op0, holes, holeCur, r0, s0, mb0, md0, imm0) <> 0 then
      Error('EmitAsm386: unary op expects a register');
    if CaseEqual(mnem, 'not') then i := 2
    else if CaseEqual(mnem, 'neg') then i := 3
    else if CaseEqual(mnem, 'mul') then i := 4
    else if CaseEqual(mnem, 'imul') then i := 5
    else i := 7;   { idiv }
    if s0 = 2 then EncB($66);
    if s0 = 1 then EncB($F6) else EncB($F7);
    EncModRMReg(i, r0);
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

  k0 := AsmTextOperand(op0, holes, holeCur, r0, s0, mb0, md0, imm0);
  k1 := AsmTextOperand(op1, holes, holeCur, r1, s1, mb1, md1, imm1);

  { shifts: shl/sal, shr, sar — reg by imm, by 1, or by cl }
  if CaseEqual(mnem, 'shl') or CaseEqual(mnem, 'sal') or
     CaseEqual(mnem, 'shr') or CaseEqual(mnem, 'sar') then
  begin
    if k0 <> 0 then Error('EmitAsm386: shift expects a register dest');
    if CaseEqual(mnem, 'shr') then i := 5
    else if CaseEqual(mnem, 'sar') then i := 7
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
    Error('EmitAsm386: unsupported imul form');
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
      if s0 = 1 then begin EncB($F6); EncModRMReg(0, r0); EncB(Integer(imm1) and $FF); end
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
    else if CaseEqual(mnem, 'and') then i := 4
    else if CaseEqual(mnem, 'sub') then i := 5
    else if CaseEqual(mnem, 'xor') then i := 6
    else if CaseEqual(mnem, 'cmp') then i := 7
    else begin Error('EmitAsm386: unsupported ALU reg,imm mnemonic'); i := 0; end;
    
    if s0 = 2 then EncB($66);
    if s0 = 1 then
    begin
      EncB($80); EncModRMReg(i, r0); EncB(Integer(imm1) and $FF);
    end
    else if (imm1 >= -128) and (imm1 <= 127) then
    begin
      EncB($83); EncModRMReg(i, r0); EncB(Integer(imm1) and $FF);
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

procedure EmitAsm386(const items: array of const); overload;
var
  i, n, h, nHoles, j, k: Integer;
  line, trimmed, mnem, target: AnsiString;
  holes: array[0..ASM_MAX_HOLES - 1] of Int64;
  cc, targetPos, disp: Integer;
  isJmp, defined: Boolean;
begin
  Asm386LblCount := 0; Asm386FwCount := 0;
  n := Length(items);
  i := 0;
  while i < n do
  begin
    if items[i].VType <> vtAnsiString then
      Error('EmitAsm386: expected an instruction string');
    line := AsmTextCStr(items[i].VAnsiString);

    { trim for label/jump classification }
    trimmed := AsmTextTrim(line);

    { first word = mnemonic }
    mnem := ''; j := 1;
    while (j <= Length(trimmed)) and not AsmTextIsSpace(AsmTextCharAt(trimmed, j)) do
      begin AppendChar(mnem, AsmTextLower(trimmed[j])); Inc(j); end;

    isJmp := CaseEqual(mnem, 'jmp');
    if (Length(trimmed) >= 2) and (AsmTextCharAt(trimmed, Length(trimmed)) = ':') then
    begin
      { label definition: `name:` (a bare line ending in ':') }
      if Asm386LblCount >= ASM_386_MAX_LABELS then Error('EmitAsm386: too many labels');
      Asm386LblName[Asm386LblCount] := AsmTextSlice(trimmed, 1, Length(trimmed) - 1);
      Asm386LblPos[Asm386LblCount] := CodeLen;
      Inc(Asm386LblCount);
      Inc(i);
    end
    else if isJmp or AsmTextJccCode(mnem, cc) then
    begin
      { operand = label name }
      while (j <= Length(trimmed)) and AsmTextIsSpace(AsmTextCharAt(trimmed, j)) do Inc(j);
      target := '';
      while j <= Length(trimmed) do begin AppendChar(target, trimmed[j]); Inc(j); end;

      defined := False; targetPos := 0;
      for k := 0 to Asm386LblCount - 1 do
        if Asm386LblName[k] = target then begin defined := True; targetPos := Asm386LblPos[k]; end;

      if defined then
      begin
        { backward (or same-call known) target: short form if it reaches. }
        disp := targetPos - (CodeLen + 2);
        if (disp >= -128) and (disp <= 127) then
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
        { forward target: emit the near (rel32) form and record a patch. }
        if isJmp then EncB($E9) else begin EncB($0F); EncB($80 + cc); end;
        if Asm386FwCount >= ASM_386_MAX_LABELS then Error('EmitAsm386: too many forward jumps');
        Asm386FwName[Asm386FwCount] := target;
        Asm386FwPatch[Asm386FwCount] := CodeLen;   { position of the rel32 displacement }
        Inc(Asm386FwCount);
        EncI32(0);
      end;
      Inc(i);
    end
    else
    begin
      { ordinary instruction: count `%` markers and bind following int holes }
      nHoles := 0;
      for h := 1 to Length(line) do
        if line[h] = '%' then Inc(nHoles);
      
      { also count `@data` or `@glob` as hole consumers if present }
      j := 1;
      while j <= Length(line) do
      begin
        if (AsmTextCharAt(line, j) = '@') and
           ((AsmTextSlice(line, j, 5) = '@data') or (AsmTextSlice(line, j, 5) = '@glob')) then
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
      AsmTextLine386(line, holes, nHoles);
      i := i + 1 + nHoles;
    end;
  end;

  { resolve forward jumps now that all labels are placed. }
  for k := 0 to Asm386FwCount - 1 do
  begin
    targetPos := -1;
    for j := 0 to Asm386LblCount - 1 do
      if Asm386LblName[j] = Asm386FwName[k] then targetPos := Asm386LblPos[j];
    if targetPos < 0 then Error('EmitAsm386: undefined label in jump');
    Patch32(Asm386FwPatch[k], targetPos - (Asm386FwPatch[k] + 4));
  end;
end;

procedure EmitAsm386(const s: AnsiString); overload;
begin
  EmitAsm386([s]);
end;
