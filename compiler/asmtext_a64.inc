{ asmtext_a64.inc — text-assembler for readable AArch64 codegen emission.

  EmitAsmA64 parses assembly strings and handles register mapping, % holes,
  labels, branches, and relocations for AArch64 (ARM64). }

function AsmA64RegNum(const opIn: AnsiString; var reg: Integer; var is64: Boolean): Boolean;
var
  s: AnsiString;
  i, n, v: Integer;
  c: Char;
begin
  Result := False;
  s := AsmRv32Trim(opIn);
  if CaseEqual(s, 'xzr') then begin reg := 31; is64 := True; Result := True; Exit; end;
  if CaseEqual(s, 'wzr') then begin reg := 31; is64 := False; Result := True; Exit; end;
  if CaseEqual(s, 'sp')  then begin reg := 31; is64 := True; Result := True; Exit; end;
  if CaseEqual(s, 'pc')  then begin reg := 32; is64 := True; Result := True; Exit; end;

  if Length(s) < 2 then Exit;
  c := AsmTextLower(AsmTextCharAt(s, 1));
  if (c <> 'x') and (c <> 'w') then Exit;

  v := 0; i := 2; n := Length(s);
  while i <= n do
  begin
    c := s[i];
    if (c < '0') or (c > '9') then Exit;
    v := v * 10 + (Ord(c) - Ord('0'));
    Inc(i);
  end;
  if (v >= 0) and (v <= 30) then
  begin
    reg := v;
    is64 := (AsmTextLower(s[1]) = 'x');
    Result := True;
  end;
end;

function AsmA64RegOp(const opIn: AnsiString): Integer;
var
  r: Integer;
  is64: Boolean;
begin
  if not AsmA64RegNum(opIn, r, is64) then
    Error('EmitAsmA64: expected register');
  Result := r;
end;

function AsmA64Int(const opIn: AnsiString; const holes: array of Int64; var holeCur: Integer): Int64;
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

procedure AsmA64ParseMem(const opIn: AnsiString; const holes: array of Int64; var holeCur: Integer; var reg: Integer; var disp: Integer; var mode: Integer);
var
  s, baseStr, dispStr: AnsiString;
  pOpen, pClose, pComma, i, n: Integer;
  is64: Boolean;
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
    Error('EmitAsmA64: expected memory operand in [base] format');

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

  if not AsmA64RegNum(baseStr, reg, is64) then
    Error('EmitAsmA64: invalid base register in memory operand');
end;

function AsmA64CondCode(const condStr: AnsiString; var cond: Integer): Boolean;
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

function A64EncodeLogicalImm(val: Int64; sf: Integer; var N, immr, imms: Integer): Boolean;
var
  S, R: Integer;
  mask, rotated: QWord;
begin
  Result := False;
  if sf = 1 then
  begin
    { 64-bit logical immediate }
    for S := 1 to 63 do
    begin
      mask := (QWord(1) shl S) - 1;
      for R := 0 to 63 do
      begin
        if R = 0 then rotated := mask
        else rotated := (mask shr R) or (mask shl (64 - R));
        if Int64(rotated) = val then
        begin
          N := 1;
          immr := R;
          imms := S - 1;
          Result := True;
          Exit;
        end;
      end;
    end;
  end
  else
  begin
    { 32-bit logical immediate }
    for S := 1 to 31 do
    begin
      mask := (QWord(1) shl S) - 1;
      for R := 0 to 31 do
      begin
        if R = 0 then rotated := mask
        else rotated := ((mask shr R) or (mask shl (32 - R))) and $FFFFFFFF;
        if (rotated and $FFFFFFFF) = (QWord(val) and $FFFFFFFF) then
        begin
          N := 0;
          immr := R;
          imms := S - 1;
          Result := True;
          Exit;
        end;
      end;
    end;
  end;
end;

procedure AsmTextLineA64(const line: AnsiString; const holes: array of Int64; nHoles: Integer);
var
  mnem, rest, op0, op1, op2: AnsiString;
  i, n, holeCur, partIdx: Integer;
  r0, r1, r2: Integer;
  is64_0, is64_1, is64_2: Boolean;
  imm: Int64;
  disp, mode: Integer;
  cond: Integer;
  N_bit, immr, imms: Integer;
  sh: Integer;
  dispStr: AnsiString;
  sz: Integer;
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
  if CaseEqual(mnem, 'nop') then begin EmitI32($D503201F); Exit; end;

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

  { ret has optional operand }
  if CaseEqual(mnem, 'ret') then
  begin
    if op0 = '' then r0 := 30
    else r0 := AsmA64RegOp(op0);
    EmitI32($D65F0000 or (r0 shl 5));
    Exit;
  end;

  { b.cond or conditional branches }
  if (Length(mnem) > 2) and (AsmTextSlice(mnem, 1, 2) = 'b.') then
  begin
    if not AsmA64CondCode(AsmTextSlice(mnem, 3, Length(mnem) - 2), cond) then
      Error('EmitAsmA64: unknown condition: ' + mnem);
    imm := AsmA64Int(op0, holes, holeCur);
    EmitI32($54000000 or (((imm div 4) and $7ffff) shl 5) or cond);
    Exit;
  end;

  { also support direct beq, bne conditional branches without dot }
  if (Length(mnem) = 3) and (AsmTextCharAt(mnem, 1) = 'b') and AsmA64CondCode(AsmTextSlice(mnem, 2, 2), cond) then
  begin
    imm := AsmA64Int(op0, holes, holeCur);
    EmitI32($54000000 or (((imm div 4) and $7ffff) shl 5) or cond);
    Exit;
  end;

  { unconditional branch }
  if CaseEqual(mnem, 'b') then
  begin
    imm := AsmA64Int(op0, holes, holeCur);
    EmitI32($14000000 or (((imm div 4) and $03ffffff)));
    Exit;
  end;

  if CaseEqual(mnem, 'bl') then
  begin
    imm := AsmA64Int(op0, holes, holeCur);
    EmitI32($94000000 or (((imm div 4) and $03ffffff)));
    Exit;
  end;

  { compare and branch }
  if CaseEqual(mnem, 'cbz') or CaseEqual(mnem, 'cbnz') then
  begin
    if not AsmA64RegNum(op0, r0, is64_0) then
      Error('EmitAsmA64: expected register in cbz/cbnz');
    imm := AsmA64Int(op1, holes, holeCur);
    if CaseEqual(mnem, 'cbz') then
    begin
      if is64_0 then EmitI32($B4000000 or (((imm div 4) and $7ffff) shl 5) or r0)
      else EmitI32($34000000 or (((imm div 4) and $7ffff) shl 5) or r0);
    end
    else
    begin
      if is64_0 then EmitI32($B5000000 or (((imm div 4) and $7ffff) shl 5) or r0)
      else EmitI32($35000000 or (((imm div 4) and $7ffff) shl 5) or r0);
    end;
    Exit;
  end;

  { cset }
  if CaseEqual(mnem, 'cset') then
  begin
    if not AsmA64RegNum(op0, r0, is64_0) then Error('EmitAsmA64: expected register in cset');
    if not AsmA64CondCode(op1, cond) then Error('EmitAsmA64: expected condition in cset');
    if (cond mod 2) = 0 then cond := cond + 1 else cond := cond - 1;
    if is64_0 then EmitI32($9A9F07E0 or (cond shl 12) or r0)
    else EmitI32($1A9F07E0 or (cond shl 12) or r0);
    Exit;
  end;

  { ldr relocations }
  if CaseEqual(mnem, 'ldr') and CaseEqual(op1, '@data') then
  begin
    if not AsmA64RegNum(op0, r0, is64_0) then Error('EmitAsmA64: expected register');
    imm := AsmA64Int(op2, holes, holeCur);
    EmitI32($58000040 or r0);
    EmitI32($14000003);
    EmitDataRef(imm);
    Exit;
  end;
  if CaseEqual(mnem, 'ldr') and CaseEqual(op1, '@glob') then
  begin
    if not AsmA64RegNum(op0, r0, is64_0) then Error('EmitAsmA64: expected register');
    imm := AsmA64Int(op2, holes, holeCur);
    EmitI32($18000040 or r0);
    EmitI32($14000002);
    EmitGlobRef(imm);
    Exit;
  end;

  { Load literal PC-relative (e.g. ldr x0, label) }
  if CaseEqual(mnem, 'ldr') and (AsmTextCharAt(op1, 1) <> '[') and not AsmA64RegNum(op1, r1, is64_1) then
  begin
    if not AsmA64RegNum(op0, r0, is64_0) then Error('EmitAsmA64: expected register');
    imm := AsmA64Int(op1, holes, holeCur);
    if is64_0 then EmitI32($58000000 or (((imm div 4) and $7ffff) shl 5) or r0)
    else EmitI32($18000000 or (((imm div 4) and $7ffff) shl 5) or r0);
    Exit;
  end;

  { mov / movz / movk }
  if CaseEqual(mnem, 'mov') or CaseEqual(mnem, 'movz') or CaseEqual(mnem, 'movk') then
  begin
    if not AsmA64RegNum(op0, r0, is64_0) then Error('EmitAsmA64: expected destination register');
    { check if second operand is register or immediate }
    if AsmA64RegNum(op1, r1, is64_1) then
    begin
      if not CaseEqual(mnem, 'mov') then Error('EmitAsmA64: movz/movk require immediate operand');
      if is64_0 then EmitI32($AA0003E0 or (r1 shl 16) or r0)
      else EmitI32($2A0003E0 or (r1 shl 16) or r0);
    end
    else
    begin
      { immediate mov/movz/movk }
      imm := AsmA64Int(op1, holes, holeCur);
      { check for shift: op2 can be "lsl #shift" or similar }
      sh := 0;
      if op2 <> '' then
      begin
        if CaseEqual(AsmTextSlice(op2, 1, 3), 'lsl') then
        begin
          dispStr := AsmRv32Trim(AsmTextSlice(op2, 4, Length(op2) - 3));
          if AsmTextCharAt(dispStr, 1) = '#' then dispStr := AsmRv32Trim(AsmTextSlice(dispStr, 2, Length(dispStr)-1));
          sh := Integer(AsmTextParseInt(dispStr));
        end
        else
          Error('EmitAsmA64: expected lsl shift');
      end;
      if (sh <> 0) and (sh <> 16) and (sh <> 32) and (sh <> 48) then
        Error('EmitAsmA64: shift must be 0, 16, 32, or 48');
      
      if CaseEqual(mnem, 'movk') then
      begin
        if is64_0 then EmitI32($F2800000 or ((sh div 16) shl 21) or ((imm and $FFFF) shl 5) or r0)
        else EmitI32($72800000 or ((sh div 16) shl 21) or ((imm and $FFFF) shl 5) or r0);
      end
      else
      begin
        { mov/movz }
        if is64_0 then EmitI32($D2800000 or ((sh div 16) shl 21) or ((imm and $FFFF) shl 5) or r0)
        else EmitI32($52800000 or ((sh div 16) shl 21) or ((imm and $FFFF) shl 5) or r0);
      end;
    end;
    Exit;
  end;

  { add / sub }
  if CaseEqual(mnem, 'add') or CaseEqual(mnem, 'sub') then
  begin
    if not AsmA64RegNum(op0, r0, is64_0) then Error('EmitAsmA64: expected destination register');
    if not AsmA64RegNum(op1, r1, is64_1) then Error('EmitAsmA64: expected source register');
    if AsmA64RegNum(op2, r2, is64_2) then
    begin
      { register form }
      if CaseEqual(mnem, 'add') then
      begin
        if is64_0 then EmitI32($8B000000 or (r2 shl 16) or (r1 shl 5) or r0)
        else EmitI32($0B000000 or (r2 shl 16) or (r1 shl 5) or r0);
      end
      else
      begin
        if is64_0 then EmitI32($CB000000 or (r2 shl 16) or (r1 shl 5) or r0)
        else EmitI32($4B000000 or (r2 shl 16) or (r1 shl 5) or r0);
      end;
    end
    else
    begin
      { immediate form }
      imm := AsmA64Int(op2, holes, holeCur);
      if (imm < 0) or (imm > 4095) then Error('EmitAsmA64: immediate out of range (0..4095)');
      if CaseEqual(mnem, 'add') then
      begin
        if is64_0 then EmitI32($91000000 or (imm shl 10) or (r1 shl 5) or r0)
        else EmitI32($11000000 or (imm shl 10) or (r1 shl 5) or r0);
      end
      else
      begin
        if is64_0 then EmitI32($D1000000 or (imm shl 10) or (r1 shl 5) or r0)
        else EmitI32($51000000 or (imm shl 10) or (r1 shl 5) or r0);
      end;
    end;
    Exit;
  end;

  { cmp }
  if CaseEqual(mnem, 'cmp') then
  begin
    if not AsmA64RegNum(op0, r0, is64_0) then Error('EmitAsmA64: expected register in cmp');
    if AsmA64RegNum(op1, r1, is64_1) then
    begin
      { register form }
      if is64_0 then EmitI32($EB000000 or (r1 shl 16) or (r0 shl 5) or 31)
      else EmitI32($6B000000 or (r1 shl 16) or (r0 shl 5) or 31);
    end
    else
    begin
      { immediate form }
      imm := AsmA64Int(op1, holes, holeCur);
      if (imm < 0) or (imm > 4095) then Error('EmitAsmA64: immediate out of range (0..4095)');
      if is64_0 then EmitI32($F1000000 or (imm shl 10) or (r0 shl 5) or 31)
      else EmitI32($71000000 or (imm shl 10) or (r0 shl 5) or 31);
    end;
    Exit;
  end;

  { and / orr / eor }
  if CaseEqual(mnem, 'and') or CaseEqual(mnem, 'orr') or CaseEqual(mnem, 'eor') then
  begin
    if not AsmA64RegNum(op0, r0, is64_0) then Error('EmitAsmA64: expected destination register');
    if not AsmA64RegNum(op1, r1, is64_1) then Error('EmitAsmA64: expected source register');
    if AsmA64RegNum(op2, r2, is64_2) then
    begin
      { register form }
      if CaseEqual(mnem, 'and') then
      begin
        if is64_0 then EmitI32($8A000000 or (r2 shl 16) or (r1 shl 5) or r0)
        else EmitI32($0A000000 or (r2 shl 16) or (r1 shl 5) or r0);
      end
      else if CaseEqual(mnem, 'orr') then
      begin
        if is64_0 then EmitI32($AA000000 or (r2 shl 16) or (r1 shl 5) or r0)
        else EmitI32($2A000000 or (r2 shl 16) or (r1 shl 5) or r0);
      end
      else
      begin
        if is64_0 then EmitI32($CA000000 or (r2 shl 16) or (r1 shl 5) or r0)
        else EmitI32($4A000000 or (r2 shl 16) or (r1 shl 5) or r0);
      end;
    end
    else
    begin
      { immediate form }
      imm := AsmA64Int(op2, holes, holeCur);
      if is64_0 then
      begin
        if not A64EncodeLogicalImm(imm, 1, N_bit, immr, imms) then
          Error('EmitAsmA64: unencodable logical immediate');
        if CaseEqual(mnem, 'and') then EmitI32($92000000 or (N_bit shl 22) or (immr shl 16) or (imms shl 10) or (r1 shl 5) or r0)
        else if CaseEqual(mnem, 'orr') then EmitI32($B2000000 or (N_bit shl 22) or (immr shl 16) or (imms shl 10) or (r1 shl 5) or r0)
        else EmitI32($D2000000 or (N_bit shl 22) or (immr shl 16) or (imms shl 10) or (r1 shl 5) or r0);
      end
      else
      begin
        if not A64EncodeLogicalImm(imm, 0, N_bit, immr, imms) then
          Error('EmitAsmA64: unencodable logical immediate');
        if CaseEqual(mnem, 'and') then EmitI32($12000000 or (N_bit shl 22) or (immr shl 16) or (imms shl 10) or (r1 shl 5) or r0)
        else if CaseEqual(mnem, 'orr') then EmitI32($32000000 or (N_bit shl 22) or (immr shl 16) or (imms shl 10) or (r1 shl 5) or r0)
        else EmitI32($52000000 or (N_bit shl 22) or (immr shl 16) or (imms shl 10) or (r1 shl 5) or r0);
      end;
    end;
    Exit;
  end;

  { ldr / str / ldrb / strb / ldrh / strh }
  if CaseEqual(mnem, 'ldr') or CaseEqual(mnem, 'str') or
     CaseEqual(mnem, 'ldrb') or CaseEqual(mnem, 'strb') or
     CaseEqual(mnem, 'ldrh') or CaseEqual(mnem, 'strh') then
  begin
    if not AsmA64RegNum(op0, r0, is64_0) then Error('EmitAsmA64: expected register');
    AsmA64ParseMem(op1, holes, holeCur, r1, disp, mode);
    
    if (mode = 0) and (r1 = 32) then
    begin
      { PC-relative load literal }
      if not CaseEqual(mnem, 'ldr') then Error('EmitAsmA64: pc-relative store or other access is not supported');
      if is64_0 then EmitI32($58000000 or (((disp div 4) and $7ffff) shl 5) or r0)
      else EmitI32($18000000 or (((disp div 4) and $7ffff) shl 5) or r0);
    end
    else if mode = 0 then
    begin
      { offset mode: unsigned offset or unscaled }
      { determine access size }
      sz := 4;
      if is64_0 then sz := 8;
      if CaseEqual(mnem, 'ldrb') or CaseEqual(mnem, 'strb') then sz := 1;
      if CaseEqual(mnem, 'ldrh') or CaseEqual(mnem, 'strh') then sz := 2;

      if (disp >= 0) and (disp <= 4095 * sz) and (disp mod sz = 0) then
      begin
        { unsigned offset }
        imm := disp div sz;
        if CaseEqual(mnem, 'ldr') then
        begin
          if is64_0 then EmitI32($F9400000 or (imm shl 10) or (r1 shl 5) or r0)
          else EmitI32($B9400000 or (imm shl 10) or (r1 shl 5) or r0);
        end
        else if CaseEqual(mnem, 'str') then
        begin
          if is64_0 then EmitI32($F9000000 or (imm shl 10) or (r1 shl 5) or r0)
          else EmitI32($B9000000 or (imm shl 10) or (r1 shl 5) or r0);
        end
        else if CaseEqual(mnem, 'ldrb') then EmitI32($39400000 or (imm shl 10) or (r1 shl 5) or r0)
        else if CaseEqual(mnem, 'strb') then EmitI32($39000000 or (imm shl 10) or (r1 shl 5) or r0)
        else if CaseEqual(mnem, 'ldrh') then EmitI32($79400000 or (imm shl 10) or (r1 shl 5) or r0)
        else if CaseEqual(mnem, 'strh') then EmitI32($79000000 or (imm shl 10) or (r1 shl 5) or r0);
      end
      else
      begin
        { unscaled offset }
        if (disp < -256) or (disp > 255) then Error('EmitAsmA64: memory offset out of range');
        imm := disp and $1FF;
        if CaseEqual(mnem, 'ldr') then
        begin
          if is64_0 then EmitI32($F8400800 or (imm shl 12) or (r1 shl 5) or r0)
          else EmitI32($B8400800 or (imm shl 12) or (r1 shl 5) or r0);
        end
        else if CaseEqual(mnem, 'str') then
        begin
          if is64_0 then EmitI32($F8000800 or (imm shl 12) or (r1 shl 5) or r0)
          else EmitI32($B8000800 or (imm shl 12) or (r1 shl 5) or r0);
        end
        else if CaseEqual(mnem, 'ldrb') then EmitI32($38400800 or (imm shl 12) or (r1 shl 5) or r0)
        else if CaseEqual(mnem, 'strb') then EmitI32($38000800 or (imm shl 12) or (r1 shl 5) or r0)
        else if CaseEqual(mnem, 'ldrh') then EmitI32($78400800 or (imm shl 12) or (r1 shl 5) or r0)
        else if CaseEqual(mnem, 'strh') then EmitI32($78000800 or (imm shl 12) or (r1 shl 5) or r0);
      end;
    end
    else
    begin
      { pre-indexed or post-indexed }
      if (disp < -256) or (disp > 255) then Error('EmitAsmA64: memory offset out of range');
      imm := disp and $1FF;
      if mode = 2 then sh := 3 else sh := 1; { pre-indexed = 3, post-indexed = 1 }
      if CaseEqual(mnem, 'ldr') then
      begin
        if is64_0 then EmitI32($F8400000 or (imm shl 12) or (sh shl 10) or (r1 shl 5) or r0)
        else EmitI32($B8400000 or (imm shl 12) or (sh shl 10) or (r1 shl 5) or r0);
      end
      else if CaseEqual(mnem, 'str') then
      begin
        if is64_0 then EmitI32($F8000000 or (imm shl 12) or (sh shl 10) or (r1 shl 5) or r0)
        else EmitI32($B8000000 or (imm shl 12) or (sh shl 10) or (r1 shl 5) or r0);
      end
      else if CaseEqual(mnem, 'ldrb') then EmitI32($38400000 or (imm shl 12) or (sh shl 10) or (r1 shl 5) or r0)
      else if CaseEqual(mnem, 'strb') then EmitI32($38000000 or (imm shl 12) or (sh shl 10) or (r1 shl 5) or r0)
      else if CaseEqual(mnem, 'ldrh') then EmitI32($78400000 or (imm shl 12) or (sh shl 10) or (r1 shl 5) or r0)
      else if CaseEqual(mnem, 'strh') then EmitI32($78000000 or (imm shl 12) or (sh shl 10) or (r1 shl 5) or r0);
    end;
    Exit;
  end;

  Error('EmitAsmA64: unsupported instruction: ' + mnem);
end;

const ASM_A64_MAX_LABELS = 64;

var
  AsmA64LblName:  array[0..ASM_A64_MAX_LABELS - 1] of AnsiString;
  AsmA64LblPos:   array[0..ASM_A64_MAX_LABELS - 1] of Integer;
  AsmA64LblCount: Integer;
  AsmA64FwName:   array[0..ASM_A64_MAX_LABELS - 1] of AnsiString;
  AsmA64FwPatch:  array[0..ASM_A64_MAX_LABELS - 1] of Integer;
  AsmA64FwType:   array[0..ASM_A64_MAX_LABELS - 1] of Integer; { 0=B, 1=BL, 2=B.cond, 3=CBZ, 4=CBNZ, 5=LDR literal }
  AsmA64FwRt:     array[0..ASM_A64_MAX_LABELS - 1] of Integer;
  AsmA64FwCond:   array[0..ASM_A64_MAX_LABELS - 1] of Integer;
  AsmA64FwCount:  Integer;

procedure EmitAsmA64(const items: array of const); overload;
var
  i, n, h, nHoles, j, k: Integer;
  line, trimmed, mnem, rest, target, op0, op1: AnsiString;
  holes: array[0..ASM_MAX_HOLES - 1] of Int64;
  rd, branchPos, targetPos, partIdx, condCode: Integer;
  isJ, isBr, isLdr, defined: Boolean;
  is64: Boolean;
begin
  AsmA64LblCount := 0; AsmA64FwCount := 0;
  n := Length(items);
  i := 0;
  while i < n do
  begin
    if items[i].VType <> vtAnsiString then
      Error('EmitAsmA64: expected an instruction string');
    line := AsmTextCStr(items[i].VAnsiString);
    trimmed := AsmRv32Trim(line);

    { first word = mnemonic }
    mnem := ''; j := 1;
    while (j <= Length(trimmed)) and not AsmTextIsSpace(AsmTextCharAt(trimmed, j)) do
      begin AppendChar(mnem, AsmTextLower(trimmed[j])); Inc(j); end;

    { check instruction type for jumps/branches/literals }
    isJ := CaseEqual(mnem, 'b') or CaseEqual(mnem, 'bl');
    isBr := CaseEqual(mnem, 'cbz') or CaseEqual(mnem, 'cbnz') or
            ((Length(mnem) > 2) and (AsmTextSlice(mnem, 1, 2) = 'b.')) or
            ((Length(mnem) = 3) and (AsmTextCharAt(mnem, 1) = 'b') and AsmA64CondCode(AsmTextSlice(mnem, 2, 2), condCode));
    isLdr := CaseEqual(mnem, 'ldr');

    if (Length(trimmed) >= 2) and (AsmTextCharAt(trimmed, Length(trimmed)) = ':') then
    begin
      { label definition: a bare line ending in ':' }
      if AsmA64LblCount >= ASM_A64_MAX_LABELS then Error('EmitAsmA64: too many labels');
      AsmA64LblName[AsmA64LblCount] := AsmTextSlice(trimmed, 1, Length(trimmed) - 1);
      AsmA64LblPos[AsmA64LblCount] := CodeLen;
      Inc(AsmA64LblCount);
      Inc(i);
    end
    else if isJ then
    begin
      { unconditional branch: b/bl label }
      target := AsmRv32Trim(AsmTextSlice(trimmed, j, Length(trimmed) - j + 1));
      if AsmRv32IsLabel(target) then
      begin
        branchPos := CodeLen;
        defined := False; targetPos := 0;
        for k := 0 to AsmA64LblCount - 1 do
          if AsmA64LblName[k] = target then begin defined := True; targetPos := AsmA64LblPos[k]; end;
        if defined then
        begin
          if CaseEqual(mnem, 'bl') then EmitI32($94000000 or (((targetPos - branchPos) div 4) and $03ffffff))
          else EmitI32($14000000 or (((targetPos - branchPos) div 4) and $03ffffff));
        end
        else
        begin
          if AsmA64FwCount >= ASM_A64_MAX_LABELS then Error('EmitAsmA64: too many forward jumps');
          AsmA64FwName[AsmA64FwCount] := target;
          AsmA64FwPatch[AsmA64FwCount] := branchPos;
          if CaseEqual(mnem, 'bl') then AsmA64FwType[AsmA64FwCount] := 1 else AsmA64FwType[AsmA64FwCount] := 0;
          Inc(AsmA64FwCount);
          if CaseEqual(mnem, 'bl') then EmitI32($94000000) else EmitI32($14000000);
        end;
        Inc(i);
      end
      else
      begin
        { ordinary instruction }
        nHoles := 0;
        for h := 1 to Length(line) do
          if line[h] = '%' then Inc(nHoles);
        if nHoles > ASM_MAX_HOLES then Error('EmitAsmA64: too many holes in one line');
        for h := 0 to nHoles - 1 do
        begin
          if (i + 1 + h >= n) or (items[i + 1 + h].VType <> vtInteger) then
            Error('EmitAsmA64: missing integer hole value');
          holes[h] := items[i + 1 + h].VInteger;
        end;
        AsmTextLineA64(line, holes, nHoles);
        i := i + 1 + nHoles;
      end;
    end
    else if isBr then
    begin
      { conditional branch: b.cond label, or cbz/cbnz rd, label }
      rest := AsmRv32Trim(AsmTextSlice(trimmed, j, Length(trimmed) - j + 1));
      if CaseEqual(mnem, 'cbz') or CaseEqual(mnem, 'cbnz') then
      begin
        op0 := ''; target := ''; partIdx := 0;
        for k := 1 to Length(rest) do
        begin
          if rest[k] = ',' then Inc(partIdx)
          else if partIdx = 0 then AppendChar(op0, rest[k])
          else AppendChar(target, rest[k]);
        end;
        op0 := AsmRv32Trim(op0);
        target := AsmRv32Trim(target);
        if not AsmA64RegNum(op0, rd, is64) then Error('EmitAsmA64: expected register');
      end
      else
      begin
        target := rest;
        if (Length(mnem) > 2) and (AsmTextSlice(mnem, 1, 2) = 'b.') then
        begin
          if not AsmA64CondCode(AsmTextSlice(mnem, 3, Length(mnem) - 2), condCode) then
            Error('EmitAsmA64: invalid condition');
        end
        else
        begin
          if not AsmA64CondCode(AsmTextSlice(mnem, 2, 2), condCode) then
            Error('EmitAsmA64: invalid condition');
        end;
      end;

      if AsmRv32IsLabel(target) then
      begin
        branchPos := CodeLen;
        defined := False; targetPos := 0;
        for k := 0 to AsmA64LblCount - 1 do
          if AsmA64LblName[k] = target then begin defined := True; targetPos := AsmA64LblPos[k]; end;
        if defined then
        begin
          if CaseEqual(mnem, 'cbz') then
          begin
            if is64 then EmitI32($B4000000 or ((((targetPos - branchPos) div 4) and $7ffff) shl 5) or rd)
            else EmitI32($34000000 or ((((targetPos - branchPos) div 4) and $7ffff) shl 5) or rd);
          end
          else if CaseEqual(mnem, 'cbnz') then
          begin
            if is64 then EmitI32($B5000000 or ((((targetPos - branchPos) div 4) and $7ffff) shl 5) or rd)
            else EmitI32($35000000 or ((((targetPos - branchPos) div 4) and $7ffff) shl 5) or rd);
          end
          else
            EmitI32($54000000 or ((((targetPos - branchPos) div 4) and $7ffff) shl 5) or condCode);
        end
        else
        begin
          if AsmA64FwCount >= ASM_A64_MAX_LABELS then Error('EmitAsmA64: too many forward jumps');
          AsmA64FwName[AsmA64FwCount] := target;
          AsmA64FwPatch[AsmA64FwCount] := branchPos;
          if CaseEqual(mnem, 'cbz') then
          begin
            AsmA64FwType[AsmA64FwCount] := 3;
            AsmA64FwRt[AsmA64FwCount] := rd;
            if is64 then EmitI32($B4000000 or rd) else EmitI32($34000000 or rd);
          end
          else if CaseEqual(mnem, 'cbnz') then
          begin
            AsmA64FwType[AsmA64FwCount] := 4;
            AsmA64FwRt[AsmA64FwCount] := rd;
            if is64 then EmitI32($B5000000 or rd) else EmitI32($35000000 or rd);
          end
          else
          begin
            AsmA64FwType[AsmA64FwCount] := 2;
            AsmA64FwCond[AsmA64FwCount] := condCode;
            EmitI32($54000000 or condCode);
          end;
          Inc(AsmA64FwCount);
        end;
        Inc(i);
      end
      else
      begin
        { ordinary instruction }
        nHoles := 0;
        for h := 1 to Length(line) do
          if line[h] = '%' then Inc(nHoles);
        if nHoles > ASM_MAX_HOLES then Error('EmitAsmA64: too many holes in one line');
        for h := 0 to nHoles - 1 do
        begin
          if (i + 1 + h >= n) or (items[i + 1 + h].VType <> vtInteger) then
            Error('EmitAsmA64: missing integer hole value');
          holes[h] := items[i + 1 + h].VInteger;
        end;
        AsmTextLineA64(line, holes, nHoles);
        i := i + 1 + nHoles;
      end;
    end
    else if isLdr then
    begin
      { check if PC-relative literal: ldr rd, label }
      rest := AsmRv32Trim(AsmTextSlice(trimmed, j, Length(trimmed) - j + 1));
      op0 := ''; target := ''; partIdx := 0;
      condCode := 0; { 0 = normal, 2 = inside memory operand (seen '[') }
      for k := 1 to Length(rest) do
      begin
        if rest[k] = '[' then condCode := 2;
        if (rest[k] = ',') and (condCode = 0) then Inc(partIdx)
        else if partIdx = 0 then AppendChar(op0, rest[k])
        else AppendChar(target, rest[k]);
      end;
      op0 := AsmRv32Trim(op0);
      target := AsmRv32Trim(target);

      if AsmA64RegNum(op0, rd, is64) and (AsmTextCharAt(target, 1) <> '[') and AsmRv32IsLabel(target) and
         not CaseEqual(target, '@data') and not CaseEqual(target, '@glob') then
      begin
        branchPos := CodeLen;
        defined := False; targetPos := 0;
        for k := 0 to AsmA64LblCount - 1 do
          if AsmA64LblName[k] = target then begin defined := True; targetPos := AsmA64LblPos[k]; end;
        if defined then
        begin
          if is64 then EmitI32($58000000 or ((((targetPos - branchPos) div 4) and $7ffff) shl 5) or rd)
          else EmitI32($18000000 or ((((targetPos - branchPos) div 4) and $7ffff) shl 5) or rd);
        end
        else
        begin
          if AsmA64FwCount >= ASM_A64_MAX_LABELS then Error('EmitAsmA64: too many forward jumps');
          AsmA64FwName[AsmA64FwCount] := target;
          AsmA64FwPatch[AsmA64FwCount] := branchPos;
          AsmA64FwType[AsmA64FwCount] := 5;
          AsmA64FwRt[AsmA64FwCount] := rd;
          if is64 then AsmA64FwCond[AsmA64FwCount] := 1 else AsmA64FwCond[AsmA64FwCount] := 0;
          Inc(AsmA64FwCount);
          if is64 then EmitI32($58000000 or rd) else EmitI32($18000000 or rd);
        end;
        Inc(i);
      end
      else
      begin
        { ordinary instruction }
        nHoles := 0;
        for h := 1 to Length(line) do
          if line[h] = '%' then Inc(nHoles);
        if nHoles > ASM_MAX_HOLES then Error('EmitAsmA64: too many holes in one line');
        for h := 0 to nHoles - 1 do
        begin
          if (i + 1 + h >= n) or (items[i + 1 + h].VType <> vtInteger) then
            Error('EmitAsmA64: missing integer hole value');
          holes[h] := items[i + 1 + h].VInteger;
        end;
        AsmTextLineA64(line, holes, nHoles);
        i := i + 1 + nHoles;
      end;
    end
    else
    begin
      { ordinary instruction }
      nHoles := 0;
      for h := 1 to Length(line) do
        if line[h] = '%' then Inc(nHoles);
      if nHoles > ASM_MAX_HOLES then Error('EmitAsmA64: too many holes in one line');
      for h := 0 to nHoles - 1 do
      begin
        if (i + 1 + h >= n) or (items[i + 1 + h].VType <> vtInteger) then
          Error('EmitAsmA64: missing integer hole value');
        holes[h] := items[i + 1 + h].VInteger;
      end;
      AsmTextLineA64(line, holes, nHoles);
      i := i + 1 + nHoles;
    end;
  end;

  { resolve forward jumps/branches now that all labels are placed }
  for k := 0 to AsmA64FwCount - 1 do
  begin
    targetPos := -1;
    for j := 0 to AsmA64LblCount - 1 do
      if AsmA64LblName[j] = AsmA64FwName[k] then targetPos := AsmA64LblPos[j];
    if targetPos < 0 then Error('EmitAsmA64: undefined label in jump');
    
    branchPos := AsmA64FwPatch[k];
    case AsmA64FwType[k] of
      0: { B }
        Patch32(branchPos, $14000000 or (((targetPos - branchPos) div 4) and $03ffffff));
      1: { BL }
        Patch32(branchPos, $94000000 or (((targetPos - branchPos) div 4) and $03ffffff));
      2: { B.cond }
        Patch32(branchPos, $54000000 or ((((targetPos - branchPos) div 4) and $7ffff) shl 5) or AsmA64FwCond[k]);
      3: { CBZ }
        begin
          rd := AsmA64FwRt[k];
          if (Code[branchPos+3] and $80) <> 0 then
            Patch32(branchPos, $B4000000 or ((((targetPos - branchPos) div 4) and $7ffff) shl 5) or rd)
          else
            Patch32(branchPos, $34000000 or ((((targetPos - branchPos) div 4) and $7ffff) shl 5) or rd);
        end;
      4: { CBNZ }
        begin
          rd := AsmA64FwRt[k];
          if (Code[branchPos+3] and $80) <> 0 then
            Patch32(branchPos, $B5000000 or ((((targetPos - branchPos) div 4) and $7ffff) shl 5) or rd)
          else
            Patch32(branchPos, $35000000 or ((((targetPos - branchPos) div 4) and $7ffff) shl 5) or rd);
        end;
      5: { LDR literal }
        begin
          rd := AsmA64FwRt[k];
          if AsmA64FwCond[k] = 1 then
            Patch32(branchPos, $58000000 or ((((targetPos - branchPos) div 4) and $7ffff) shl 5) or rd)
          else
            Patch32(branchPos, $18000000 or ((((targetPos - branchPos) div 4) and $7ffff) shl 5) or rd);
        end;
    end;
  end;
end;

procedure EmitAsmA64(const s: AnsiString); overload;
begin
  EmitAsmA64([s]);
end;
