{ asmtext_rv32.inc — text-assembler for readable RISC-V RV32 codegen emission.

  EmitAsmRv32 is the RISC-V sibling of EmitAsmX64/EmitAsmXtensa. It parses
  assembly strings and handles register mapping, % holes, labels, branches,
  and relocations. Encodings are routed through the typed rv32_* encoders in
  rv32enc.inc. }


function AsmRv32RegNum(const opIn: AnsiString; var reg: Integer): Boolean;
var s: AnsiString; i, n, v: Integer; c: Char;
begin
  Result := False;
  s := AsmTextTrim(opIn);
  if CaseEqual(s, 'zero') then begin reg := 0; Result := True; Exit; end;
  if CaseEqual(s, 'ra') then begin reg := 1; Result := True; Exit; end;
  if CaseEqual(s, 'sp') then begin reg := 2; Result := True; Exit; end;
  if CaseEqual(s, 'gp') then begin reg := 3; Result := True; Exit; end;
  if CaseEqual(s, 'tp') then begin reg := 4; Result := True; Exit; end;
  if CaseEqual(s, 't0') then begin reg := 5; Result := True; Exit; end;
  if CaseEqual(s, 't1') then begin reg := 6; Result := True; Exit; end;
  if CaseEqual(s, 't2') then begin reg := 7; Result := True; Exit; end;
  if CaseEqual(s, 's0') or CaseEqual(s, 'fp') then begin reg := 8; Result := True; Exit; end;
  if CaseEqual(s, 's1') then begin reg := 9; Result := True; Exit; end;
  if CaseEqual(s, 'a0') then begin reg := 10; Result := True; Exit; end;
  if CaseEqual(s, 'a1') then begin reg := 11; Result := True; Exit; end;
  if CaseEqual(s, 'a2') then begin reg := 12; Result := True; Exit; end;
  if CaseEqual(s, 'a3') then begin reg := 13; Result := True; Exit; end;
  if CaseEqual(s, 'a4') then begin reg := 14; Result := True; Exit; end;
  if CaseEqual(s, 'a5') then begin reg := 15; Result := True; Exit; end;
  if CaseEqual(s, 'a6') then begin reg := 16; Result := True; Exit; end;
  if CaseEqual(s, 'a7') then begin reg := 17; Result := True; Exit; end;
  if CaseEqual(s, 's2') then begin reg := 18; Result := True; Exit; end;
  if CaseEqual(s, 's3') then begin reg := 19; Result := True; Exit; end;
  if CaseEqual(s, 's4') then begin reg := 20; Result := True; Exit; end;
  if CaseEqual(s, 's5') then begin reg := 21; Result := True; Exit; end;
  if CaseEqual(s, 's6') then begin reg := 22; Result := True; Exit; end;
  if CaseEqual(s, 's7') then begin reg := 23; Result := True; Exit; end;
  if CaseEqual(s, 's8') then begin reg := 24; Result := True; Exit; end;
  if CaseEqual(s, 's9') then begin reg := 25; Result := True; Exit; end;
  if CaseEqual(s, 's10') then begin reg := 26; Result := True; Exit; end;
  if CaseEqual(s, 's11') then begin reg := 27; Result := True; Exit; end;
  if CaseEqual(s, 't3') then begin reg := 28; Result := True; Exit; end;
  if CaseEqual(s, 't4') then begin reg := 29; Result := True; Exit; end;
  if CaseEqual(s, 't5') then begin reg := 30; Result := True; Exit; end;
  if CaseEqual(s, 't6') then begin reg := 31; Result := True; Exit; end;

  if Length(s) < 2 then Exit;
  if AsmTextLower(AsmTextCharAt(s, 1)) <> 'x' then Exit;
  v := 0; i := 2; n := Length(s);
  while i <= n do
  begin
    c := s[i];
    if (c < '0') or (c > '9') then Exit;
    v := v * 10 + (Ord(c) - Ord('0'));
    Inc(i);
  end;
  if (v >= 0) and (v <= 31) then begin reg := v; Result := True; end;
end;

function AsmRv32RegOp(const opIn: AnsiString): Integer;
var r: Integer;
begin
  if not AsmRv32RegNum(opIn, r) then
    Error('EmitAsmRv32: expected register');
  Result := r;
end;

function AsmRv32Int(const opIn: AnsiString; const holes: array of Int64; var holeCur: Integer): Int64;
var s: AnsiString;
begin
  s := AsmTextTrim(opIn);
  if AsmTextCharAt(s, 1) = '%' then
  begin
    Result := holes[holeCur]; Inc(holeCur);
  end
  else
    Result := AsmTextParseInt(s);
end;

procedure AsmRv32ParseMem(const opIn: AnsiString; const holes: array of Int64; var holeCur: Integer; var reg: Integer; var disp: Integer);
var
  s, dispStr, regStr: AnsiString;
  i, n, p: Integer;
begin
  s := AsmTextTrim(opIn);
  p := 0;
  n := Length(s);
  for i := 1 to n do
    if s[i] = '(' then p := i;
  if p = 0 then
    Error('EmitAsmRv32: expected memory operand format imm(reg)');
  
  dispStr := AsmTextTrim(AsmTextSlice(s, 1, p - 1));
  if Length(dispStr) = 0 then
    disp := 0
  else if AsmTextCharAt(dispStr, 1) = '%' then
  begin
    disp := Integer(holes[holeCur]); Inc(holeCur);
  end
  else
    disp := Integer(AsmTextParseInt(dispStr));

  regStr := '';
  i := p + 1;
  while (i <= n) and (s[i] <> ')') do
  begin
    AppendChar(regStr, s[i]);
    Inc(i);
  end;
  regStr := AsmTextTrim(regStr);
  if not AsmRv32RegNum(regStr, reg) then
    Error('EmitAsmRv32: invalid base register in memory operand');
end;

function AsmRv32BranchCode(const m: AnsiString; var funct3: Integer): Boolean;
begin
  Result := True;
  if CaseEqual(m, 'beq') then funct3 := 0
  else if CaseEqual(m, 'bne') then funct3 := 1
  else if CaseEqual(m, 'blt') then funct3 := 4
  else if CaseEqual(m, 'bge') then funct3 := 5
  else if CaseEqual(m, 'bltu') then funct3 := 6
  else if CaseEqual(m, 'bgeu') then funct3 := 7
  else Result := False;
end;

procedure AsmRv32CheckImm12(val: Int64);
begin
  if (val < -2048) or (val > 2047) then
    Error('EmitAsmRv32: immediate value out of 12-bit signed range (-2048..2047)');
end;

procedure AsmRv32CheckImm20(val: Int64);
begin
  if (val < -524288) or (val > 1048575) then
    Error('EmitAsmRv32: immediate value out of 20-bit range (-524288..1048575)');
end;

procedure AsmRv32CheckBranch(offset: Integer);
begin
  if (offset < -4096) or (offset > 4095) then
    Error('EmitAsmRv32: branch target out of range (+-4095)');
end;

procedure AsmRv32CheckJump(offset: Integer);
begin
  if (offset < -1048576) or (offset > 1048575) then
    Error('EmitAsmRv32: jump target out of range (+-1MB)');
end;

function EncodeRISCVBranch(funct3, rs1, rs2, offset: Integer): Integer;
var
  i12, i11, i10_5, i4_1: Integer;
begin
  i12   := (offset shr 12) and 1;
  i11   := (offset shr 11) and 1;
  i10_5 := (offset shr 5) and $3F;
  i4_1  := (offset shr 1) and $F;
  Result := (i12 shl 31) or (i10_5 shl 25) or (rs2 shl 20) or (rs1 shl 15) or (funct3 shl 12) or (i4_1 shl 8) or (i11 shl 7) or $63;
end;


procedure AsmTextLineRv32(const line: AnsiString; const holes: array of Int64; nHoles: Integer);
var
  mnem, rest, op0, op1, op2: AnsiString;
  i, n, holeCur, partIdx: Integer;
  r0, r1, r2, imm: Integer;
  disp: Integer;
  funct3: Integer;
begin
  holeCur := 0;
  n := Length(line);
  i := 1;
  while (i <= n) and AsmTextIsSpace(AsmTextCharAt(line, i)) do Inc(i);
  mnem := '';
  while (i <= n) and not AsmTextIsSpace(AsmTextCharAt(line, i)) do
    begin AppendChar(mnem, AsmTextLower(line[i])); Inc(i); end;
  rest := '';
  while i <= n do begin AppendChar(rest, line[i]); Inc(i); end;

  { zero-operand forms }
  if CaseEqual(mnem, 'nop') then begin rv32_nop; Exit; end;
  if CaseEqual(mnem, 'ret') then begin rv32_jalr(0, 1, 0); Exit; end;
  if CaseEqual(mnem, 'ecall') then begin EmitI32($00000073); Exit; end;

  { split rest into up to three comma-separated operands }
  op0 := ''; op1 := ''; op2 := ''; partIdx := 0;
  for i := 1 to Length(rest) do
  begin
    if rest[i] = ',' then Inc(partIdx)
    else if partIdx = 0 then AppendChar(op0, rest[i])
    else if partIdx = 1 then AppendChar(op1, rest[i])
    else AppendChar(op2, rest[i]);
  end;
  op0 := AsmTextTrim(op0); op1 := AsmTextTrim(op1); op2 := AsmTextTrim(op2);

  r0 := AsmRv32RegOp(op0);

  if CaseEqual(mnem, 'add') then begin r1 := AsmRv32RegOp(op1); r2 := AsmRv32RegOp(op2); rv32_add(r0, r1, r2); end
  else if CaseEqual(mnem, 'sub') then begin r1 := AsmRv32RegOp(op1); r2 := AsmRv32RegOp(op2); rv32_sub(r0, r1, r2); end
  else if CaseEqual(mnem, 'and') then begin r1 := AsmRv32RegOp(op1); r2 := AsmRv32RegOp(op2); rv32_and(r0, r1, r2); end
  else if CaseEqual(mnem, 'or')  then begin r1 := AsmRv32RegOp(op1); r2 := AsmRv32RegOp(op2); rv32_or(r0, r1, r2); end
  else if CaseEqual(mnem, 'xor') then begin r1 := AsmRv32RegOp(op1); r2 := AsmRv32RegOp(op2); rv32_xor(r0, r1, r2); end
  else if CaseEqual(mnem, 'sll') then begin r1 := AsmRv32RegOp(op1); r2 := AsmRv32RegOp(op2); rv32_sll(r0, r1, r2); end
  else if CaseEqual(mnem, 'srl') then begin r1 := AsmRv32RegOp(op1); r2 := AsmRv32RegOp(op2); rv32_srl(r0, r1, r2); end
  else if CaseEqual(mnem, 'sra') then begin r1 := AsmRv32RegOp(op1); r2 := AsmRv32RegOp(op2); rv32_sra(r0, r1, r2); end
  else if CaseEqual(mnem, 'slt') then begin r1 := AsmRv32RegOp(op1); r2 := AsmRv32RegOp(op2); rv32_slt(r0, r1, r2); end
  else if CaseEqual(mnem, 'sltu') then begin r1 := AsmRv32RegOp(op1); r2 := AsmRv32RegOp(op2); rv32_sltu(r0, r1, r2); end
  else if CaseEqual(mnem, 'mul') then begin r1 := AsmRv32RegOp(op1); r2 := AsmRv32RegOp(op2); rv32_mul(r0, r1, r2); end
  else if CaseEqual(mnem, 'mulhu') then begin r1 := AsmRv32RegOp(op1); r2 := AsmRv32RegOp(op2); rv32_mulhu(r0, r1, r2); end
  else if CaseEqual(mnem, 'div') then begin r1 := AsmRv32RegOp(op1); r2 := AsmRv32RegOp(op2); rv32_div(r0, r1, r2); end
  else if CaseEqual(mnem, 'rem') then begin r1 := AsmRv32RegOp(op1); r2 := AsmRv32RegOp(op2); rv32_rem(r0, r1, r2); end

  else if CaseEqual(mnem, 'addi') then begin r1 := AsmRv32RegOp(op1); imm := Integer(AsmRv32Int(op2, holes, holeCur)); AsmRv32CheckImm12(imm); rv32_addi(r0, r1, imm); end
  else if CaseEqual(mnem, 'xori') then begin r1 := AsmRv32RegOp(op1); imm := Integer(AsmRv32Int(op2, holes, holeCur)); AsmRv32CheckImm12(imm); rv32_xori(r0, r1, imm); end
  else if CaseEqual(mnem, 'ori')  then begin r1 := AsmRv32RegOp(op1); imm := Integer(AsmRv32Int(op2, holes, holeCur)); AsmRv32CheckImm12(imm); rv32_ori(r0, r1, imm); end
  else if CaseEqual(mnem, 'andi') then begin r1 := AsmRv32RegOp(op1); imm := Integer(AsmRv32Int(op2, holes, holeCur)); AsmRv32CheckImm12(imm); rv32_andi(r0, r1, imm); end
  else if CaseEqual(mnem, 'slli') then begin r1 := AsmRv32RegOp(op1); imm := Integer(AsmRv32Int(op2, holes, holeCur)); EmitIType(imm and $1F, r1, 1, r0, $13); end
  else if CaseEqual(mnem, 'srli') then begin r1 := AsmRv32RegOp(op1); imm := Integer(AsmRv32Int(op2, holes, holeCur)); EmitIType(imm and $1F, r1, 5, r0, $13); end
  else if CaseEqual(mnem, 'srai') then begin r1 := AsmRv32RegOp(op1); imm := Integer(AsmRv32Int(op2, holes, holeCur)); EmitIType((imm and $1F) or $400, r1, 5, r0, $13); end

  else if CaseEqual(mnem, 'lui')   then begin imm := Integer(AsmRv32Int(op1, holes, holeCur)); AsmRv32CheckImm20(imm); rv32_lui(r0, imm shl 12); end
  else if CaseEqual(mnem, 'auipc') then begin imm := Integer(AsmRv32Int(op1, holes, holeCur)); AsmRv32CheckImm20(imm); rv32_auipc(r0, imm shl 12); end

  else if CaseEqual(mnem, 'lw')  then begin AsmRv32ParseMem(op1, holes, holeCur, r1, disp); AsmRv32CheckImm12(disp); rv32_lw(r0, r1, disp); end
  else if CaseEqual(mnem, 'lh')  then begin AsmRv32ParseMem(op1, holes, holeCur, r1, disp); AsmRv32CheckImm12(disp); rv32_lh(r0, r1, disp); end
  else if CaseEqual(mnem, 'lb')  then begin AsmRv32ParseMem(op1, holes, holeCur, r1, disp); AsmRv32CheckImm12(disp); rv32_lb(r0, r1, disp); end
  else if CaseEqual(mnem, 'lhu') then begin AsmRv32ParseMem(op1, holes, holeCur, r1, disp); AsmRv32CheckImm12(disp); rv32_lhu(r0, r1, disp); end
  else if CaseEqual(mnem, 'lbu') then begin AsmRv32ParseMem(op1, holes, holeCur, r1, disp); AsmRv32CheckImm12(disp); rv32_lbu(r0, r1, disp); end

  else if CaseEqual(mnem, 'sw')  then begin AsmRv32ParseMem(op1, holes, holeCur, r1, disp); AsmRv32CheckImm12(disp); rv32_sw(r0, r1, disp); end
  else if CaseEqual(mnem, 'sh')  then begin AsmRv32ParseMem(op1, holes, holeCur, r1, disp); AsmRv32CheckImm12(disp); rv32_sh(r0, r1, disp); end
  else if CaseEqual(mnem, 'sb')  then begin AsmRv32ParseMem(op1, holes, holeCur, r1, disp); AsmRv32CheckImm12(disp); rv32_sb(r0, r1, disp); end

  else if CaseEqual(mnem, 'jalr') then
  begin
    AsmRv32ParseMem(op1, holes, holeCur, r1, disp);
    AsmRv32CheckImm12(disp);
    rv32_jalr(r0, r1, disp);
  end

  else if CaseEqual(mnem, 'jal') then
  begin
    if op1 = '' then
    begin
      imm := Integer(AsmRv32Int(op0, holes, holeCur));
      rv32_jal(1, imm);
    end
    else
    begin
      imm := Integer(AsmRv32Int(op1, holes, holeCur));
      rv32_jal(r0, imm);
    end;
  end

  else if AsmRv32BranchCode(mnem, funct3) then
  begin
    r1 := AsmRv32RegOp(op1);
    imm := Integer(AsmRv32Int(op2, holes, holeCur));
    EmitBType(imm, r1, r0, funct3, $63);
  end

  else if CaseEqual(mnem, 'la') then
  begin
    if CaseEqual(op1, '@data') then
    begin
      imm := Integer(holes[holeCur]); Inc(holeCur);
      rv32_auipc(r0, 0);
      rv32_jal(0, 8);
      EmitDataRef(imm);
      rv32_lw(r0, r0, 8);
    end
    else if CaseEqual(op1, '@glob') then
    begin
      imm := Integer(holes[holeCur]); Inc(holeCur);
      rv32_auipc(r0, 0);
      rv32_jal(0, 8);
      EmitGlobRef(imm);
      rv32_lw(r0, r0, 8);
    end
    else
      Error('EmitAsmRv32: expected @data or @glob after la');
  end

  else Error('EmitAsmRv32: unsupported instruction');
end;

const ASM_RV_MAX_LABELS = 32;

var
  AsmRvLblName:  array[0..ASM_RV_MAX_LABELS - 1] of AnsiString;
  AsmRvLblPos:   array[0..ASM_RV_MAX_LABELS - 1] of Integer;
  AsmRvLblCount: Integer;
  AsmRvFwName:   array[0..ASM_RV_MAX_LABELS - 1] of AnsiString;
  AsmRvFwPatch:  array[0..ASM_RV_MAX_LABELS - 1] of Integer;
  AsmRvFwIsJ:    array[0..ASM_RV_MAX_LABELS - 1] of Boolean;
  AsmRvFwRd:     array[0..ASM_RV_MAX_LABELS - 1] of Integer;
  AsmRvFwRs1:    array[0..ASM_RV_MAX_LABELS - 1] of Integer;
  AsmRvFwRs2:    array[0..ASM_RV_MAX_LABELS - 1] of Integer;
  AsmRvFwFunct3: array[0..ASM_RV_MAX_LABELS - 1] of Integer;
  AsmRvFwCount:  Integer;

procedure EmitAsmRv32(const items: array of const); overload;
var
  i, n, h, nHoles, j, k: Integer;
  line, trimmed, mnem, rest, target, op0, op1: AnsiString;
  holes: array[0..ASM_MAX_HOLES - 1] of Int64;
  rd, rs1, rs2, funct3, branchPos, targetPos, partIdx: Integer;
  isJ, isBr, defined: Boolean;
begin
  AsmRvLblCount := 0; AsmRvFwCount := 0;
  n := Length(items);
  i := 0;
  while i < n do
  begin
    if items[i].VType <> vtAnsiString then
      Error('EmitAsmRv32: expected an instruction string');
    line := AsmTextCStr(items[i].VAnsiString);
    trimmed := AsmTextTrim(line);

    { first word = mnemonic }
    mnem := ''; j := 1;
    while (j <= Length(trimmed)) and not AsmTextIsSpace(AsmTextCharAt(trimmed, j)) do
      begin AppendChar(mnem, AsmTextLower(trimmed[j])); Inc(j); end;

    isJ := CaseEqual(mnem, 'j') or CaseEqual(mnem, 'jal');
    isBr := AsmRv32BranchCode(mnem, funct3);

    if (Length(trimmed) >= 2) and (AsmTextCharAt(trimmed, Length(trimmed)) = ':') then
    begin
      { label definition: a bare line ending in ':' }
      if AsmRvLblCount >= ASM_RV_MAX_LABELS then Error('EmitAsmRv32: too many labels');
      AsmRvLblName[AsmRvLblCount] := AsmTextSlice(trimmed, 1, Length(trimmed) - 1);
      AsmRvLblPos[AsmRvLblCount] := CodeLen;
      Inc(AsmRvLblCount);
      Inc(i);
    end
    else if isJ then
    begin
      { jump instruction: jal rd, .label or j .label }
      rest := AsmTextTrim(AsmTextSlice(trimmed, j, Length(trimmed) - j + 1));
      op0 := ''; op1 := ''; partIdx := 0;
      for k := 1 to Length(rest) do
      begin
        if rest[k] = ',' then Inc(partIdx)
        else if partIdx = 0 then AppendChar(op0, rest[k])
        else AppendChar(op1, rest[k]);
      end;
      op0 := AsmTextTrim(op0);
      op1 := AsmTextTrim(op1);

      if partIdx = 0 then
      begin
        { j .label }
        rd := 0;
        target := op0;
      end
      else
      begin
        { jal rd, .label }
        rd := AsmRv32RegOp(op0);
        target := op1;
      end;

      if AsmTextIsLabel(target) then
      begin
        branchPos := CodeLen;
        defined := False; targetPos := 0;
        for k := 0 to AsmRvLblCount - 1 do
          if AsmRvLblName[k] = target then begin defined := True; targetPos := AsmRvLblPos[k]; end;
        if defined then
        begin
          AsmRv32CheckJump(targetPos - branchPos);
          rv32_jal(rd, targetPos - branchPos);
        end
        else
        begin
          if AsmRvFwCount >= ASM_RV_MAX_LABELS then Error('EmitAsmRv32: too many forward jumps');
          AsmRvFwName[AsmRvFwCount] := target;
          AsmRvFwPatch[AsmRvFwCount] := branchPos;
          AsmRvFwIsJ[AsmRvFwCount] := True;
          AsmRvFwRd[AsmRvFwCount] := rd;
          Inc(AsmRvFwCount);
          rv32_jal(rd, 0);   { placeholder, patched below }
        end;
        Inc(i);
      end
      else
      begin
        { Not a label: handle as ordinary instruction }
        nHoles := 0;
        for h := 1 to Length(line) do
          if line[h] = '%' then Inc(nHoles);
        if nHoles > ASM_MAX_HOLES then Error('EmitAsmRv32: too many holes in one line');
        for h := 0 to nHoles - 1 do
        begin
          if (i + 1 + h >= n) or (items[i + 1 + h].VType <> vtInteger) and (items[i + 1 + h].VType <> vtInt64) then
            Error('EmitAsmRv32: missing integer hole value');
          if items[i + 1 + h].VType = vtInt64 then holes[h] := PHoleI64(items[i + 1 + h].VInt64)^ else holes[h] := items[i + 1 + h].VInteger;
        end;
        AsmTextLineRv32(line, holes, nHoles);
        i := i + 1 + nHoles;
      end;
    end
    else if isBr then
    begin
      { conditional branch: `bXX rs1, rs2, .label` }
      rest := AsmTextTrim(AsmTextSlice(trimmed, j, Length(trimmed) - j + 1));
      op0 := ''; op1 := ''; target := ''; partIdx := 0;
      for k := 1 to Length(rest) do
      begin
        if rest[k] = ',' then Inc(partIdx)
        else if partIdx = 0 then AppendChar(op0, rest[k])
        else if partIdx = 1 then AppendChar(op1, rest[k])
        else AppendChar(target, rest[k]);
      end;
      rs1 := AsmRv32RegOp(op0);
      rs2 := AsmRv32RegOp(op1);
      target := AsmTextTrim(target);

      if AsmTextIsLabel(target) then
      begin
        branchPos := CodeLen;
        defined := False; targetPos := 0;
        for k := 0 to AsmRvLblCount - 1 do
          if AsmRvLblName[k] = target then begin defined := True; targetPos := AsmRvLblPos[k]; end;
        if defined then
        begin
          AsmRv32CheckBranch(targetPos - branchPos);
          EmitBType(targetPos - branchPos, rs2, rs1, funct3, $63);
        end
        else
        begin
          if AsmRvFwCount >= ASM_RV_MAX_LABELS then Error('EmitAsmRv32: too many forward jumps');
          AsmRvFwName[AsmRvFwCount] := target;
          AsmRvFwPatch[AsmRvFwCount] := branchPos;
          AsmRvFwIsJ[AsmRvFwCount] := False;
          AsmRvFwRs1[AsmRvFwCount] := rs1;
          AsmRvFwRs2[AsmRvFwCount] := rs2;
          AsmRvFwFunct3[AsmRvFwCount] := funct3;
          Inc(AsmRvFwCount);
          EmitBType(0, rs2, rs1, funct3, $63);   { placeholder, patched below }
        end;
        Inc(i);
      end
      else
      begin
        { Not a label: handle as ordinary instruction }
        nHoles := 0;
        for h := 1 to Length(line) do
          if line[h] = '%' then Inc(nHoles);
        if nHoles > ASM_MAX_HOLES then Error('EmitAsmRv32: too many holes in one line');
        for h := 0 to nHoles - 1 do
        begin
          if (i + 1 + h >= n) or (items[i + 1 + h].VType <> vtInteger) and (items[i + 1 + h].VType <> vtInt64) then
            Error('EmitAsmRv32: missing integer hole value');
          if items[i + 1 + h].VType = vtInt64 then holes[h] := PHoleI64(items[i + 1 + h].VInt64)^ else holes[h] := items[i + 1 + h].VInteger;
        end;
        AsmTextLineRv32(line, holes, nHoles);
        i := i + 1 + nHoles;
      end;
    end
    else
    begin
      { ordinary instruction }
      nHoles := 0;
      for h := 1 to Length(line) do
        if line[h] = '%' then Inc(nHoles);
      if nHoles > ASM_MAX_HOLES then Error('EmitAsmRv32: too many holes in one line');
      for h := 0 to nHoles - 1 do
      begin
        if (i + 1 + h >= n) or (items[i + 1 + h].VType <> vtInteger) and (items[i + 1 + h].VType <> vtInt64) then
          Error('EmitAsmRv32: missing integer hole value');
        if items[i + 1 + h].VType = vtInt64 then holes[h] := PHoleI64(items[i + 1 + h].VInt64)^ else holes[h] := items[i + 1 + h].VInteger;
      end;
      AsmTextLineRv32(line, holes, nHoles);
      i := i + 1 + nHoles;
    end;
  end;

  { resolve forward jumps/branches now that all labels are placed }
  for k := 0 to AsmRvFwCount - 1 do
  begin
    targetPos := -1;
    for j := 0 to AsmRvLblCount - 1 do
      if AsmRvLblName[j] = AsmRvFwName[k] then targetPos := AsmRvLblPos[j];
    if targetPos < 0 then Error('EmitAsmRv32: undefined label in jump');
    if AsmRvFwIsJ[k] then
    begin
      AsmRv32CheckJump(targetPos - AsmRvFwPatch[k]);
      Patch32(AsmRvFwPatch[k], EncodeRISCVJAL(AsmRvFwRd[k], targetPos - AsmRvFwPatch[k]));
    end
    else
    begin
      AsmRv32CheckBranch(targetPos - AsmRvFwPatch[k]);
      Patch32(AsmRvFwPatch[k], EncodeRISCVBranch(AsmRvFwFunct3[k], AsmRvFwRs1[k], AsmRvFwRs2[k], targetPos - AsmRvFwPatch[k]));
    end;
  end;
end;

procedure EmitAsmRv32(const s: AnsiString); overload;
begin
  EmitAsmRv32([s]);
end;
