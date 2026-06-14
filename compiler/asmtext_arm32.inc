{ asmtext_arm32.inc — text-assembler for readable ARM32 codegen emission.

  EmitAsmArm32 parses assembly strings and handles register mapping, % holes,
  labels, branches, and relocations for ARM32 (A32). }

function EncodeArm32ImmRot(val: Cardinal; var imm8, rot: Integer): Boolean;
var
  r: Integer;
  rotated: Cardinal;
begin
  Result := False;
  for r := 0 to 15 do
  begin
    { rotate val left by r * 2 }
    if r = 0 then
      rotated := val
    else
      rotated := (val shl (r * 2)) or (val shr (32 - r * 2));
    
    if (rotated and $FF) = rotated then
    begin
      imm8 := Integer(rotated);
      rot := r;
      Result := True;
      Exit;
    end;
  end;
end;

function AsmArm32RegNum(const opIn: AnsiString; var reg: Integer): Boolean;
var
  s: AnsiString;
  i, n, v: Integer;
  c: Char;
begin
  Result := False;
  s := AsmRv32Trim(opIn);
  if CaseEqual(s, 'sp')  then begin reg := 13; Result := True; Exit; end;
  if CaseEqual(s, 'lr')  then begin reg := 14; Result := True; Exit; end;
  if CaseEqual(s, 'pc')  then begin reg := 15; Result := True; Exit; end;
  if CaseEqual(s, 'fp')  then begin reg := 11; Result := True; Exit; end;
  if CaseEqual(s, 'ip')  then begin reg := 12; Result := True; Exit; end;

  if Length(s) < 2 then Exit;
  c := AsmTextLower(AsmTextCharAt(s, 1));
  if c <> 'r' then Exit;

  v := 0; i := 2; n := Length(s);
  while i <= n do
  begin
    c := s[i];
    if (c < '0') or (c > '9') then Exit;
    v := v * 10 + (Ord(c) - Ord('0'));
    Inc(i);
  end;
  if (v >= 0) and (v <= 15) then
  begin
    reg := v;
    Result := True;
  end;
end;

function AsmArm32RegOp(const opIn: AnsiString): Integer;
var
  r: Integer;
begin
  if not AsmArm32RegNum(opIn, r) then
    Error('EmitAsmArm32: expected register');
  Result := r;
end;

function AsmArm32Int(const opIn: AnsiString; const holes: array of Int64; var holeCur: Integer): Int64;
var
  s: AnsiString;
begin
  s := AsmRv32Trim(opIn);
  if AsmTextCharAt(s, 1) = '#' then
    s := AsmRv32Trim(AsmTextSlice(s, 2, Length(s) - 1));
  if AsmTextCharAt(s, 1) = '%' then
  begin
    Result := holes[holeCur]; Inc(holeCur);
  end
  else
    Result := AsmTextParseInt(s);
end;

procedure AsmArm32ParseMem(const opIn: AnsiString; const holes: array of Int64; var holeCur: Integer; var reg: Integer; var disp: Integer; var mode: Integer);
var
  s, baseStr, dispStr: AnsiString;
  pOpen, pClose, pComma, i, n: Integer;
begin
  s := AsmRv32Trim(opIn);
  n := Length(s);
  pOpen := 0; pClose := 0;
  for i := 1 to n do
  begin
    if s[i] = '[' then pOpen := i;
    if s[i] = ']' then pClose := i;
  end;
  if (pOpen = 0) or (pClose = 0) or (pOpen > pClose) then
    Error('EmitAsmArm32: expected memory operand in [base] format');

  { Check if pre-indexed: trailing '!' }
  if (pClose < n) and (s[n] = '!') then
    mode := 2 { Pre-indexed }
  else if pClose < n then
    mode := 1 { Post-indexed }
  else
    mode := 0; { Standard Offset }

  { Parse base register inside [] }
  pComma := 0;
  for i := pOpen + 1 to pClose - 1 do
    if s[i] = ',' then pComma := i;

  if pComma = 0 then
  begin
    baseStr := AsmRv32Trim(AsmTextSlice(s, pOpen + 1, pClose - pOpen - 1));
    disp := 0;
  end
  else
  begin
    baseStr := AsmRv32Trim(AsmTextSlice(s, pOpen + 1, pComma - pOpen - 1));
    dispStr := AsmRv32Trim(AsmTextSlice(s, pComma + 1, pClose - pComma - 1));
    if AsmTextCharAt(dispStr, 1) = '#' then
      dispStr := AsmRv32Trim(AsmTextSlice(dispStr, 2, Length(dispStr) - 1));
    
    if AsmTextCharAt(dispStr, 1) = '%' then
    begin
      disp := Integer(holes[holeCur]); Inc(holeCur);
    end
    else
      disp := Integer(AsmTextParseInt(dispStr));
  end;

  if mode = 1 then
  begin
    { Post-indexed: offset is after the ] }
    dispStr := AsmRv32Trim(AsmTextSlice(s, pClose + 1, n - pClose));
    if AsmTextCharAt(dispStr, 1) = ',' then
      dispStr := AsmRv32Trim(AsmTextSlice(dispStr, 2, Length(dispStr) - 1));
    if AsmTextCharAt(dispStr, 1) = '#' then
      dispStr := AsmRv32Trim(AsmTextSlice(dispStr, 2, Length(dispStr) - 1));
    
    if AsmTextCharAt(dispStr, 1) = '%' then
    begin
      disp := Integer(holes[holeCur]); Inc(holeCur);
    end
    else
      disp := Integer(AsmTextParseInt(dispStr));
  end;

  if not AsmArm32RegNum(baseStr, reg) then
    Error('EmitAsmArm32: invalid base register in memory operand');
end;

function AsmArm32CondCode(const condStr: AnsiString; var cond: Integer): Boolean;
begin
  Result := True;
  if CaseEqual(condStr, 'eq') then cond := 0
  else if CaseEqual(condStr, 'ne') then cond := 1
  else if CaseEqual(condStr, 'cs') or CaseEqual(condStr, 'hs') then cond := 2
  else if CaseEqual(condStr, 'cc') or CaseEqual(condStr, 'lo') then cond := 3
  else if CaseEqual(condStr, 'mi') then cond := 4
  else if CaseEqual(condStr, 'pl') then cond := 5
  else if CaseEqual(condStr, 'vs') then cond := 6
  else if CaseEqual(condStr, 'vc') then cond := 7
  else if CaseEqual(condStr, 'hi') then cond := 8
  else if CaseEqual(condStr, 'ls') then cond := 9
  else if CaseEqual(condStr, 'ge') then cond := 10
  else if CaseEqual(condStr, 'lt') then cond := 11
  else if CaseEqual(condStr, 'gt') then cond := 12
  else if CaseEqual(condStr, 'le') then cond := 13
  else if CaseEqual(condStr, 'al') then cond := 14
  else Result := False;
end;

procedure AsmTextLineArm32(const line: AnsiString; const holes: array of Int64; nHoles: Integer);
var
  mnem, rest, op0, op1, op2: AnsiString;
  i, n, holeCur, partIdx: Integer;
  r0, r1, r2: Integer;
  imm: Int64;
  disp, mode: Integer;
  cond, opcode: Integer;
  sh: Integer;
  imm8, rot: Integer;
  baseMnem: AnsiString;
  isLoad, isByte, hasImmed: Boolean;
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

  { Extract condition suffix if present }
  cond := 14; { AL default }
  baseMnem := mnem;
  if Length(mnem) >= 3 then
  begin
    if AsmArm32CondCode(AsmTextSlice(mnem, Length(mnem) - 1, 2), cond) then
      baseMnem := AsmTextSlice(mnem, 1, Length(mnem) - 2);
  end;

  { zero-operand forms }
  if CaseEqual(baseMnem, 'nop') then begin EmitI32((cond shl 28) or $0320F000); Exit; end;

  { split rest into up to three comma-separated operands }
  op0 := ''; op1 := ''; op2 := ''; partIdx := 0;
  sh := 0; { 0 = normal, 2 = inside memory operand (seen '[') }
  for i := 1 to Length(rest) do
  begin
    if rest[i] = '[' then sh := 2;
    if (rest[i] = ',') and (sh = 0) then Inc(partIdx)
    else if partIdx = 0 then AppendChar(op0, rest[i])
    else if partIdx = 1 then AppendChar(op1, rest[i])
    else AppendChar(op2, rest[i]);
  end;
  op0 := AsmRv32Trim(op0); op1 := AsmRv32Trim(op1); op2 := AsmRv32Trim(op2);

  if CaseEqual(baseMnem, 'bx') then
  begin
    r0 := AsmArm32RegOp(op0);
    EmitI32((cond shl 28) or $12FFF10 or r0);
    Exit;
  end;

  opcode := -1;
  if CaseEqual(baseMnem, 'and') then opcode := 0
  else if CaseEqual(baseMnem, 'eor') then opcode := 1
  else if CaseEqual(baseMnem, 'sub') then opcode := 2
  else if CaseEqual(baseMnem, 'add') then opcode := 4
  else if CaseEqual(baseMnem, 'cmp') then opcode := 10
  else if CaseEqual(baseMnem, 'orr') then opcode := 12
  else if CaseEqual(baseMnem, 'mov') then opcode := 13
  else if CaseEqual(baseMnem, 'mvn') then opcode := 15;

  if opcode <> -1 then
  begin
    if CaseEqual(baseMnem, 'mov') or CaseEqual(baseMnem, 'mvn') then
    begin
      r0 := AsmArm32RegOp(op0);
      hasImmed := (AsmTextCharAt(op1, 1) = '#') or (AsmTextCharAt(op1, 1) = '%') or ((AsmTextCharAt(op1, 1) >= '0') and (AsmTextCharAt(op1, 1) <= '9')) or (AsmTextCharAt(op1, 1) = '-');
      if hasImmed then
      begin
        imm := AsmArm32Int(op1, holes, holeCur);
        if not EncodeArm32ImmRot(Cardinal(imm), imm8, rot) then
          Error('EmitAsmArm32: immediate cannot be represented in ARM32 8-bit-rotated format');
        EmitI32((cond shl 28) or (1 shl 25) or (opcode shl 21) or (r0 shl 12) or (rot shl 8) or imm8);
      end
      else
      begin
        r1 := AsmArm32RegOp(op1);
        EmitI32((cond shl 28) or (opcode shl 21) or (r0 shl 12) or r1);
      end;
      Exit;
    end;

    if CaseEqual(baseMnem, 'cmp') then
    begin
      r0 := AsmArm32RegOp(op0);
      hasImmed := (AsmTextCharAt(op1, 1) = '#') or (AsmTextCharAt(op1, 1) = '%') or ((AsmTextCharAt(op1, 1) >= '0') and (AsmTextCharAt(op1, 1) <= '9')) or (AsmTextCharAt(op1, 1) = '-');
      if hasImmed then
      begin
        imm := AsmArm32Int(op1, holes, holeCur);
        if not EncodeArm32ImmRot(Cardinal(imm), imm8, rot) then
          Error('EmitAsmArm32: immediate cannot be represented in ARM32 8-bit-rotated format');
        EmitI32((cond shl 28) or (1 shl 25) or (opcode shl 21) or (1 shl 20) or (r0 shl 16) or (rot shl 8) or imm8);
      end
      else
      begin
        r1 := AsmArm32RegOp(op1);
        EmitI32((cond shl 28) or (opcode shl 21) or (1 shl 20) or (r0 shl 16) or r1);
      end;
      Exit;
    end;

    { 3-operand forms: add/sub/and/orr/eor }
    if op2 = '' then
    begin
      r0 := AsmArm32RegOp(op0);
      r1 := r0;
      op2 := op1;
    end
    else
    begin
      r0 := AsmArm32RegOp(op0);
      r1 := AsmArm32RegOp(op1);
    end;

    hasImmed := (AsmTextCharAt(op2, 1) = '#') or (AsmTextCharAt(op2, 1) = '%') or ((AsmTextCharAt(op2, 1) >= '0') and (AsmTextCharAt(op2, 1) <= '9')) or (AsmTextCharAt(op2, 1) = '-');
    if hasImmed then
    begin
      imm := AsmArm32Int(op2, holes, holeCur);
      if not EncodeArm32ImmRot(Cardinal(imm), imm8, rot) then
        Error('EmitAsmArm32: immediate cannot be represented in ARM32 8-bit-rotated format');
      EmitI32((cond shl 28) or (1 shl 25) or (opcode shl 21) or (r1 shl 16) or (r0 shl 12) or (rot shl 8) or imm8);
    end
    else
    begin
      r2 := AsmArm32RegOp(op2);
      EmitI32((cond shl 28) or (opcode shl 21) or (r1 shl 16) or (r0 shl 12) or r2);
    end;
    Exit;
  end;

  if CaseEqual(baseMnem, 'ldr') or CaseEqual(baseMnem, 'str') or
     CaseEqual(baseMnem, 'ldrb') or CaseEqual(baseMnem, 'strb') or
     CaseEqual(baseMnem, 'ldrh') or CaseEqual(baseMnem, 'strh') or
     CaseEqual(baseMnem, 'ldrsb') or CaseEqual(baseMnem, 'ldrsh') then
  begin
    { ldr relocations: ldr rd, @data/glob }
    if CaseEqual(baseMnem, 'ldr') and (CaseEqual(op1, '@data') or CaseEqual(op1, '@glob')) then
    begin
      r0 := AsmArm32RegOp(op0);
      imm := AsmArm32Int(op2, holes, holeCur);
      EmitI32((cond shl 28) or $059F0000 or (r0 shl 12)); { ldr rd, [pc] }
      EmitI32((cond shl 28) or $0A000000);                { b 0 (b .+8) }
      if CaseEqual(op1, '@data') then EmitDataRef(imm)
      else EmitGlobRef(imm);
      Exit;
    end;

    r0 := AsmArm32RegOp(op0);
    AsmArm32ParseMem(op1, holes, holeCur, r1, disp, mode);

    if CaseEqual(baseMnem, 'ldrh') or CaseEqual(baseMnem, 'strh') or
       CaseEqual(baseMnem, 'ldrsb') or CaseEqual(baseMnem, 'ldrsh') then
    begin
      if CaseEqual(baseMnem, 'strh') then opcode := 0 else opcode := 1;
      
      if CaseEqual(baseMnem, 'ldrh') or CaseEqual(baseMnem, 'strh') then rot := $B
      else if CaseEqual(baseMnem, 'ldrsb') then rot := $D
      else rot := $F;

      if (disp < -255) or (disp > 255) then
        Error('EmitAsmArm32: halfword/signed byte offset out of range (-255..255)');

      if disp < 0 then imm8 := -disp else imm8 := disp;
      sh := imm8 and $F;
      imm := (imm8 shr 4) and $F;

      i := (cond shl 28) or $00000090 or (1 shl 24) or (1 shl 22) or (opcode shl 20) or (r1 shl 16) or (r0 shl 12) or (imm shl 8) or (rot shl 4) or sh;
      if disp >= 0 then i := i or (1 shl 23);
      EmitI32(i);
      Exit;
    end;

    isLoad := CaseEqual(baseMnem, 'ldr') or CaseEqual(baseMnem, 'ldrb');
    isByte := CaseEqual(baseMnem, 'ldrb') or CaseEqual(baseMnem, 'strb');

    if (disp < -4095) or (disp > 4095) then
      Error('EmitAsmArm32: memory offset out of range (-4095..4095)');

    if disp < 0 then imm8 := -disp else imm8 := disp;

    i := (cond shl 28) or $04000000 or (1 shl 24) or (r1 shl 16) or (r0 shl 12) or imm8;
    if disp >= 0 then i := i or (1 shl 23);
    if isByte then i := i or (1 shl 22);
    if isLoad then i := i or (1 shl 20);
    EmitI32(i);
    Exit;
  end;

  { b / bl }
  if CaseEqual(baseMnem, 'b') or CaseEqual(baseMnem, 'bl') then
  begin
    imm := AsmArm32Int(op0, holes, holeCur);
    disp := (imm div 4) - 2;
    if CaseEqual(baseMnem, 'bl') then
      EmitI32((cond shl 28) or $0B000000 or (disp and $00ffffff))
    else
      EmitI32((cond shl 28) or $0A000000 or (disp and $00ffffff));
    Exit;
  end;

  Error('EmitAsmArm32: unsupported instruction: ' + mnem);
end;

const ASM_ARM32_MAX_LABELS = 64;

var
  AsmArm32LblName:  array[0..ASM_ARM32_MAX_LABELS - 1] of AnsiString;
  AsmArm32LblPos:   array[0..ASM_ARM32_MAX_LABELS - 1] of Integer;
  AsmArm32LblCount: Integer;
  AsmArm32FwName:   array[0..ASM_ARM32_MAX_LABELS - 1] of AnsiString;
  AsmArm32FwPatch:  array[0..ASM_ARM32_MAX_LABELS - 1] of Integer;
  AsmArm32FwType:   array[0..ASM_ARM32_MAX_LABELS - 1] of Integer;
  AsmArm32FwCond:   array[0..ASM_ARM32_MAX_LABELS - 1] of Integer;
  AsmArm32FwCount:  Integer;

procedure EmitAsmArm32(const items: array of const); overload;
var
  i, n, h, nHoles, j, k: Integer;
  line, trimmed, mnem, target: AnsiString;
  holes: array[0..ASM_MAX_HOLES - 1] of Int64;
  rd, branchPos, targetPos, cond: Integer;
  isJ, defined: Boolean;
  baseMnem: AnsiString;
begin
  AsmArm32LblCount := 0; AsmArm32FwCount := 0;
  n := Length(items);
  i := 0;
  while i < n do
  begin
    if items[i].VType <> vtAnsiString then
      Error('EmitAsmArm32: expected an instruction string');
    line := AsmTextCStr(items[i].VAnsiString);
    trimmed := AsmRv32Trim(line);

    mnem := ''; j := 1;
    while (j <= Length(trimmed)) and not AsmTextIsSpace(AsmTextCharAt(trimmed, j)) do
      begin AppendChar(mnem, AsmTextLower(trimmed[j])); Inc(j); end;

    cond := 14;
    baseMnem := mnem;
    if Length(mnem) >= 3 then
    begin
      if AsmArm32CondCode(AsmTextSlice(mnem, Length(mnem) - 1, 2), cond) then
        baseMnem := AsmTextSlice(mnem, 1, Length(mnem) - 2);
    end;

    isJ := CaseEqual(baseMnem, 'b') or CaseEqual(baseMnem, 'bl');

    if (Length(trimmed) >= 2) and (AsmTextCharAt(trimmed, Length(trimmed)) = ':') then
    begin
      if AsmArm32LblCount >= ASM_ARM32_MAX_LABELS then Error('EmitAsmArm32: too many labels');
      AsmArm32LblName[AsmArm32LblCount] := AsmTextSlice(trimmed, 1, Length(trimmed) - 1);
      AsmArm32LblPos[AsmArm32LblCount] := CodeLen;
      Inc(AsmArm32LblCount);
      Inc(i);
    end
    else if isJ then
    begin
      target := AsmRv32Trim(AsmTextSlice(trimmed, j, Length(trimmed) - j + 1));
      if AsmRv32IsLabel(target) then
      begin
        branchPos := CodeLen;
        defined := False; targetPos := 0;
        for k := 0 to AsmArm32LblCount - 1 do
          if AsmArm32LblName[k] = target then begin defined := True; targetPos := AsmArm32LblPos[k]; end;
        if defined then
        begin
          rd := ((targetPos - branchPos) div 4) - 2;
          if CaseEqual(baseMnem, 'bl') then EmitI32((cond shl 28) or $0B000000 or (rd and $00ffffff))
          else EmitI32((cond shl 28) or $0A000000 or (rd and $00ffffff));
        end
        else
        begin
          if AsmArm32FwCount >= ASM_ARM32_MAX_LABELS then Error('EmitAsmArm32: too many forward jumps');
          AsmArm32FwName[AsmArm32FwCount] := target;
          AsmArm32FwPatch[AsmArm32FwCount] := branchPos;
          if CaseEqual(baseMnem, 'bl') then AsmArm32FwType[AsmArm32FwCount] := 1 else AsmArm32FwType[AsmArm32FwCount] := 0;
          AsmArm32FwCond[AsmArm32FwCount] := cond;
          Inc(AsmArm32FwCount);
          if CaseEqual(baseMnem, 'bl') then EmitI32((cond shl 28) or $0B000000) else EmitI32((cond shl 28) or $0A000000);
        end;
        Inc(i);
      end
      else
      begin
        nHoles := 0;
        for h := 1 to Length(line) do
          if line[h] = '%' then Inc(nHoles);
        if nHoles > ASM_MAX_HOLES then Error('EmitAsmArm32: too many holes in one line');
        for h := 0 to nHoles - 1 do
        begin
          if (i + 1 + h >= n) or (items[i + 1 + h].VType <> vtInteger) then
            Error('EmitAsmArm32: missing integer hole value');
          holes[h] := items[i + 1 + h].VInteger;
        end;
        AsmTextLineArm32(line, holes, nHoles);
        i := i + 1 + nHoles;
      end;
    end
    else
    begin
      nHoles := 0;
      for h := 1 to Length(line) do
        if line[h] = '%' then Inc(nHoles);
      if nHoles > ASM_MAX_HOLES then Error('EmitAsmArm32: too many holes in one line');
      for h := 0 to nHoles - 1 do
      begin
        if (i + 1 + h >= n) or (items[i + 1 + h].VType <> vtInteger) then
          Error('EmitAsmArm32: missing integer hole value');
        holes[h] := items[i + 1 + h].VInteger;
      end;
      AsmTextLineArm32(line, holes, nHoles);
      i := i + 1 + nHoles;
    end;
  end;

  for k := 0 to AsmArm32FwCount - 1 do
  begin
    targetPos := -1;
    for j := 0 to AsmArm32LblCount - 1 do
      if AsmArm32LblName[j] = AsmArm32FwName[k] then targetPos := AsmArm32LblPos[j];
    if targetPos < 0 then Error('EmitAsmArm32: undefined label in jump');
    
    branchPos := AsmArm32FwPatch[k];
    rd := ((targetPos - branchPos) div 4) - 2;
    cond := AsmArm32FwCond[k];
    if AsmArm32FwType[k] = 1 then
      Patch32(branchPos, (cond shl 28) or $0B000000 or (rd and $00ffffff))
    else
      Patch32(branchPos, (cond shl 28) or $0A000000 or (rd and $00ffffff));
  end;
end;

procedure EmitAsmArm32(const s: AnsiString); overload;
begin
  EmitAsmArm32([s]);
end;
