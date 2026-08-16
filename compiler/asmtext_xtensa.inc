{ SPDX-License-Identifier: MPL-2.0 }
{ asmtext_xtensa.inc — text-assembler for readable Xtensa codegen emission.

  EmitAsmXtensa is the Xtensa sibling of EmitAsmX64 (asmtext.inc): it takes an
  interleaved `array of const` where each string is one Xtensa instruction and
  the integers that follow a string are that line's `%` hole values, in order.
  Lines are encoded through the typed xtensa_* / EncodeXtensa* layer in
  xtensaenc.inc, so the ISA's sharp edges (J imm18 at bits[23:6], branch imm8,
  RET=80 00 00) are computed once and correctly.

  Operand model (simpler than x86 — no ModRM/brackets): flat registers a0..a15
  (`sp` = a1); `mnem dst, src, imm` comma-separated; loads/stores are
  `l32i at, as, off` (base register + immediate offset, not bracketed). `%` is a
  value hole bound from the next int element. `.name:` defines a label; `j .name`
  and `bXX as, at, .name` resolve a target-relative offset (back and forward).

  Covered this slice: add sub and or xor mull, mov movi addi, l32i l16ui l16si
  l8ui s32i s16i s8i, nop ret, branches beq bne blt bge, and j. Grow per need.

  Deferred (see feature-xtensa-asm-emitter ticket): L32R literal-pool sugar,
  16-bit narrow encodings, windowed-ABI entry/call8 sugar.

  Shares the AsmText* helpers (AsmTextCStr/IsSpace/CharAt/Slice/Lower/ParseInt)
  with asmtext.inc, which is included before this file. }

{ Trim leading/trailing whitespace. Conditional char reads go through
  AsmTextCharAt — the dialect does not short-circuit and an empty AnsiString
  index is a nil deref. }
function AsmXtensaTrim(const s: AnsiString): AnsiString;
var i, n: Integer;
begin
  Result := '';
  n := Length(s);
  i := 1;
  while (i <= n) and AsmTextIsSpace(AsmTextCharAt(s, i)) do Inc(i);
  while (n >= i) and AsmTextIsSpace(AsmTextCharAt(s, n)) do Dec(n);
  while i <= n do begin AppendChar(Result, s[i]); Inc(i); end;
end;

{ Parse a register name (a0..a15 or sp) into 0..15. Result=False if not one. }
function AsmXtensaRegNum(const opIn: AnsiString; var reg: Integer): Boolean;
var s: AnsiString; i, n, v: Integer; c: Char;
begin
  Result := False;
  s := AsmXtensaTrim(opIn);
  if CaseEqual(s, 'sp') then begin reg := reg_xtensa_sp; Result := True; Exit; end;
  if Length(s) < 2 then Exit;
  if AsmTextLower(AsmTextCharAt(s, 1)) <> 'a' then Exit;
  v := 0; i := 2; n := Length(s);
  while i <= n do
  begin
    c := s[i];
    if (c < '0') or (c > '9') then Exit;
    v := v * 10 + (Ord(c) - Ord('0'));
    Inc(i);
  end;
  if (v >= 0) and (v <= 15) then begin reg := v; Result := True; end;
end;

{ Register operand or error. }
function AsmXtensaRegOp(const opIn: AnsiString): Integer;
var r: Integer;
begin
  if not AsmXtensaRegNum(opIn, r) then
    Error('EmitAsmXtensa: expected register');
  Result := r;
end;

{ Immediate/offset operand: `%` pulls the next hole, else a literal. }
function AsmXtensaInt(const opIn: AnsiString; const holes: array of Int64; var holeCur: Integer): Int64;
var s: AnsiString;
begin
  s := AsmXtensaTrim(opIn);
  if AsmTextCharAt(s, 1) = '%' then
  begin
    Result := holes[holeCur]; Inc(holeCur);
  end
  else
    Result := AsmTextParseInt(s);
end;

{ Map a branch mnemonic to its EncodeXtensaBranch r-code (beq=1 bne=9 blt=2
  bltu=3 bge=10 bgeu=11). Result=False for a non-branch. }
function AsmXtensaBranchCode(const m: AnsiString; var r: Integer): Boolean;
begin
  Result := True;
  if CaseEqual(m, 'beq') then r := 1
  else if CaseEqual(m, 'bne') then r := 9
  else if CaseEqual(m, 'blt') then r := 2
  else if CaseEqual(m, 'bltu') then r := 3
  else if CaseEqual(m, 'bge') then r := 10
  else if CaseEqual(m, 'bgeu') then r := 11
  else Result := False;
end;

{ Emit a 3-byte branch word (r,s,t,offset) through the shared encoder. }
procedure AsmXtensaEmitBranch(r, s, t, offset: Integer);
var val: Integer;
begin
  val := EncodeXtensaBranch(r, s, t, offset);
  EmitB(val and $FF);
  EmitB((val shr 8) and $FF);
  EmitB((val shr 16) and $FF);
end;

{ The base+offset memory forms, as one table: `mnem rt, rs, off`. Split out of
  the mnemonic chain below because the variable-operand path emits the SAME
  instruction against a materialized address, and two spellings of one table is
  how the second one stays wrong (normalise-dont-special-case). }
function AsmXtensaIsLoadStore(const mnem: AnsiString): Boolean;
begin
  Result := CaseEqual(mnem, 'l32i') or CaseEqual(mnem, 'l16ui')
    or CaseEqual(mnem, 'l16si') or CaseEqual(mnem, 'l8ui')
    or CaseEqual(mnem, 's32i') or CaseEqual(mnem, 's16i')
    or CaseEqual(mnem, 's8i');
end;

procedure AsmXtensaEmitLoadStore(const mnem: AnsiString; rt, rs, off: Integer);
begin
  if CaseEqual(mnem, 'l32i') then xtensa_l32i(rt, rs, off)
  else if CaseEqual(mnem, 'l16ui') then xtensa_l16ui(rt, rs, off)
  else if CaseEqual(mnem, 'l16si') then xtensa_l16si(rt, rs, off)
  else if CaseEqual(mnem, 'l8ui') then xtensa_l8ui(rt, rs, off)
  else if CaseEqual(mnem, 's32i') then xtensa_s32i(rt, rs, off)
  else if CaseEqual(mnem, 's16i') then xtensa_s16i(rt, rs, off)
  else if CaseEqual(mnem, 's8i') then xtensa_s8i(rt, rs, off)
  else Error('EmitAsmXtensa: not a load/store: ' + mnem);
end;

{ Assemble one ordinary (non-label, non-jump/branch) instruction line, binding
  its `%` holes from holes[0..nHoles-1]. }
procedure AsmTextLineXtensa(const line: AnsiString; const holes: array of Int64; nHoles: Integer);
var
  mnem, rest, op0, op1, op2: AnsiString;
  i, n, holeCur, partIdx: Integer;
  r0, r1, r2, imm: Integer;
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
  if CaseEqual(mnem, 'nop') then begin xtensa_nop; Exit; end;
  if CaseEqual(mnem, 'ret') then begin xtensa_ret; Exit; end;

  { split rest into up to three comma-separated operands }
  op0 := ''; op1 := ''; op2 := ''; partIdx := 0;
  for i := 1 to Length(rest) do
  begin
    if rest[i] = ',' then Inc(partIdx)
    else if partIdx = 0 then AppendChar(op0, rest[i])
    else if partIdx = 1 then AppendChar(op1, rest[i])
    else AppendChar(op2, rest[i]);
  end;
  op0 := AsmXtensaTrim(op0); op1 := AsmXtensaTrim(op1); op2 := AsmXtensaTrim(op2);

  { Resolve operands into locals first. The dialect mis-evaluates several nested
    function-call arguments in one call, so never pass AsmXtensaRegOp/Int results
    directly as encoder arguments — bind them here. r0 is always a register. }
  r0 := AsmXtensaRegOp(op0);

  { A Pascal variable as the MEMORY operand of a load or store: `l32i a2, x`,
    captured as `l32i a2,@fp` + an offset hole. Xtensa cannot encode it the way
    every other target's capture does — l32i's offset is an UNSIGNED imm8*4
    (0..1020) and frame offsets are NEGATIVE, so there is no `<off>(fp)` form to
    substitute into. The address is materialized into a8, the backend's own
    address scratch, and the access becomes offset 0; hence a8 is refused as the
    value register, where a store would otherwise overwrite its own address. }
  if AsmXtensaIsLoadStore(mnem)
     and (CaseEqual(op1, '@fp') or CaseEqual(op1, '@glob') or CaseEqual(op1, '@data')) then
  begin
    if r0 = reg_xtensa_a8 then
      Error('EmitAsmXtensa: a8 holds the address of a variable operand — use another register');
    imm := Integer(AsmXtensaInt('%', holes, holeCur));
    if CaseEqual(op1, '@fp') then EmitFrameAddrXtensa(reg_xtensa_a8, imm)
    else if CaseEqual(op1, '@glob') then EmitLoadGlobAddrXtensa(reg_xtensa_a8, imm)
    else EmitLoadDataRefXtensa(reg_xtensa_a8, imm);
    AsmXtensaEmitLoadStore(mnem, r0, reg_xtensa_a8, 0);
    Exit;
  end;

  { three-register ALU: r, s, t }
  if CaseEqual(mnem, 'add') then begin r1 := AsmXtensaRegOp(op1); r2 := AsmXtensaRegOp(op2); xtensa_add(r0, r1, r2); end
  else if CaseEqual(mnem, 'sub') then begin r1 := AsmXtensaRegOp(op1); r2 := AsmXtensaRegOp(op2); xtensa_sub(r0, r1, r2); end
  else if CaseEqual(mnem, 'and') then begin r1 := AsmXtensaRegOp(op1); r2 := AsmXtensaRegOp(op2); xtensa_and(r0, r1, r2); end
  else if CaseEqual(mnem, 'or')  then begin r1 := AsmXtensaRegOp(op1); r2 := AsmXtensaRegOp(op2); xtensa_or(r0, r1, r2); end
  else if CaseEqual(mnem, 'xor') then begin r1 := AsmXtensaRegOp(op1); r2 := AsmXtensaRegOp(op2); xtensa_xor(r0, r1, r2); end
  else if CaseEqual(mnem, 'mull') then begin r1 := AsmXtensaRegOp(op1); r2 := AsmXtensaRegOp(op2); xtensa_mull(r0, r1, r2); end
  else if CaseEqual(mnem, 'muluh') then begin r1 := AsmXtensaRegOp(op1); r2 := AsmXtensaRegOp(op2); xtensa_muluh(r0, r1, r2); end
  { Variable shifts route through SAR: `ssl as` / `ssr as` set the shift amount,
    then `sll ar, as` / `srl ar, at` apply it. (r0 above is the first operand:
    the shift-amount reg for ssl/ssr, the destination for sll/srl.) }
  else if CaseEqual(mnem, 'ssl') then xtensa_ssl(r0)
  else if CaseEqual(mnem, 'ssr') then xtensa_ssr(r0)
  else if CaseEqual(mnem, 'sll') then begin r1 := AsmXtensaRegOp(op1); xtensa_sll(r0, r1); end
  else if CaseEqual(mnem, 'srl') then begin r1 := AsmXtensaRegOp(op1); xtensa_srl(r0, r1); end
  else if CaseEqual(mnem, 'mov') then begin r1 := AsmXtensaRegOp(op1); xtensa_mov(r0, r1); end
  else if CaseEqual(mnem, 'movi') then begin imm := Integer(AsmXtensaInt(op1, holes, holeCur)); xtensa_movi(r0, imm); end
  else if CaseEqual(mnem, 'addi') then begin r1 := AsmXtensaRegOp(op1); imm := Integer(AsmXtensaInt(op2, holes, holeCur)); xtensa_addi(r0, r1, imm); end
  else if AsmXtensaIsLoadStore(mnem) then
    begin r1 := AsmXtensaRegOp(op1); imm := Integer(AsmXtensaInt(op2, holes, holeCur)); AsmXtensaEmitLoadStore(mnem, r0, r1, imm); end

  { ---- address materialization: `la <reg>, @fp|@glob|@data` + one hole ----
    The inline-asm capture (AsmParseBodyTextXtensa, asmenc.inc) resolves a
    Pascal name at PARSE time and leaves the kind as a marker plus an offset
    hole; the address itself is built HERE, at codegen, where CodeLen is final
    so EmitGlobRef/EmitDataRef relocations and the L32R literal pool land
    correctly. @fp goes through the backend's own EmitFrameAddrXtensa, which
    is what knows the frame pointer is a7 under the windowed ABI and a15 under
    Call0, and what falls back to the literal pool past addi's +-128. }
  else if CaseEqual(mnem, 'la') then
  begin
    imm := Integer(AsmXtensaInt('%', holes, holeCur));
    if CaseEqual(op1, '@fp') then EmitFrameAddrXtensa(r0, imm)
    else if CaseEqual(op1, '@glob') then EmitLoadGlobAddrXtensa(r0, imm)
    else if CaseEqual(op1, '@data') then EmitLoadDataRefXtensa(r0, imm)
    else Error('EmitAsmXtensa: expected @fp, @glob or @data after la');
  end
  else Error('EmitAsmXtensa: unsupported instruction');
end;

const ASM_XT_MAX_LABELS = 32;

{ Label / forward-branch bookkeeping for one EmitAsmXtensa call. Module-level,
  not locals: the dialect's local arrays-of-AnsiString are a self-host landmine
  (as EmitAsmX64 keeps its tables global). Codegen is single-threaded, so a
  shared scratch table is safe. }
var
  AsmXtLblName:  array[0..ASM_XT_MAX_LABELS - 1] of AnsiString;
  AsmXtLblPos:   array[0..ASM_XT_MAX_LABELS - 1] of Integer;
  AsmXtLblCount: Integer;
  AsmXtFwName:   array[0..ASM_XT_MAX_LABELS - 1] of AnsiString;
  AsmXtFwPatch:  array[0..ASM_XT_MAX_LABELS - 1] of Integer;
  AsmXtFwIsJ:    array[0..ASM_XT_MAX_LABELS - 1] of Boolean;
  AsmXtFwR:      array[0..ASM_XT_MAX_LABELS - 1] of Integer;
  AsmXtFwS:      array[0..ASM_XT_MAX_LABELS - 1] of Integer;
  AsmXtFwT:      array[0..ASM_XT_MAX_LABELS - 1] of Integer;
  AsmXtFwCount:  Integer;

{ Branch reach is imm8 (offset-4 in -128..127). Error early on overflow. }
procedure AsmXtensaCheckBranch(offset: Integer);
begin
  if (offset - 4 < -128) or (offset - 4 > 127) then
    Error('EmitAsmXtensa: branch target out of range (+-127)');
end;

{ Block-scoped label state around AsmXtensaProcessLine calls. EmitAsmXtensa is
  one begin/lines/resolve cycle; the inline-asm IR_ASM replay in
  ir_codegen_xtensa.inc is another (labels are scoped to one asm block). }
procedure AsmXtensaBlockBegin;
begin
  AsmXtLblCount := 0; AsmXtFwCount := 0;
end;

{ Process one already-hole-resolved line: label definition, `j .label`, a
  conditional branch to a label (recorded for AsmXtensaBlockResolve when
  forward), or an ordinary instruction via AsmTextLineXtensa. }
procedure AsmXtensaProcessLine(const line: AnsiString; const holes: array of Int64; nHoles: Integer);
var
  trimmed, mnem, rest, target, op0, op1: AnsiString;
  j, k, r, s, t, branchPos, targetPos, partIdx: Integer;
  isJ, isBr, defined: Boolean;
begin
  trimmed := AsmXtensaTrim(line);

  { first word = mnemonic }
  mnem := ''; j := 1;
  while (j <= Length(trimmed)) and not AsmTextIsSpace(AsmTextCharAt(trimmed, j)) do
    begin AppendChar(mnem, AsmTextLower(trimmed[j])); Inc(j); end;

  isJ := CaseEqual(mnem, 'j');
  isBr := AsmXtensaBranchCode(mnem, r);

  if (Length(trimmed) >= 2) and (AsmTextCharAt(trimmed, Length(trimmed)) = ':') then
  begin
    { label definition: a bare line ending in ':' }
    if AsmXtLblCount >= ASM_XT_MAX_LABELS then Error('EmitAsmXtensa: too many labels');
    AsmXtLblName[AsmXtLblCount] := AsmTextSlice(trimmed, 1, Length(trimmed) - 1);
    AsmXtLblPos[AsmXtLblCount] := CodeLen;
    Inc(AsmXtLblCount);
    Exit;
  end;

  if isJ then
  begin
    { unconditional jump: sole operand is a label name }
    target := AsmXtensaTrim(AsmTextSlice(trimmed, j, Length(trimmed) - j + 1));
    branchPos := CodeLen;
    defined := False; targetPos := 0;
    for k := 0 to AsmXtLblCount - 1 do
      if AsmXtLblName[k] = target then begin defined := True; targetPos := AsmXtLblPos[k]; end;
    if defined then
      xtensa_j(targetPos - branchPos)
    else
    begin
      if AsmXtFwCount >= ASM_XT_MAX_LABELS then Error('EmitAsmXtensa: too many forward jumps');
      AsmXtFwName[AsmXtFwCount] := target;
      AsmXtFwPatch[AsmXtFwCount] := branchPos;
      AsmXtFwIsJ[AsmXtFwCount] := True;
      Inc(AsmXtFwCount);
      xtensa_j(4);   { placeholder, patched in AsmXtensaBlockResolve }
    end;
    Exit;
  end;

  if isBr then
  begin
    { conditional branch: `bXX as, at, .label` }
    rest := AsmXtensaTrim(AsmTextSlice(trimmed, j, Length(trimmed) - j + 1));
    op0 := ''; op1 := ''; target := ''; partIdx := 0;
    for k := 1 to Length(rest) do
    begin
      if rest[k] = ',' then Inc(partIdx)
      else if partIdx = 0 then AppendChar(op0, rest[k])
      else if partIdx = 1 then AppendChar(op1, rest[k])
      else AppendChar(target, rest[k]);
    end;
    s := AsmXtensaRegOp(op0);
    t := AsmXtensaRegOp(op1);
    target := AsmXtensaTrim(target);
    branchPos := CodeLen;
    defined := False; targetPos := 0;
    for k := 0 to AsmXtLblCount - 1 do
      if AsmXtLblName[k] = target then begin defined := True; targetPos := AsmXtLblPos[k]; end;
    if defined then
    begin
      AsmXtensaCheckBranch(targetPos - branchPos);
      AsmXtensaEmitBranch(r, s, t, targetPos - branchPos);
    end
    else
    begin
      if AsmXtFwCount >= ASM_XT_MAX_LABELS then Error('EmitAsmXtensa: too many forward jumps');
      AsmXtFwName[AsmXtFwCount] := target;
      AsmXtFwPatch[AsmXtFwCount] := branchPos;
      AsmXtFwIsJ[AsmXtFwCount] := False;
      AsmXtFwR[AsmXtFwCount] := r;
      AsmXtFwS[AsmXtFwCount] := s;
      AsmXtFwT[AsmXtFwCount] := t;
      Inc(AsmXtFwCount);
      AsmXtensaEmitBranch(r, s, t, 4);   { placeholder, patched in AsmXtensaBlockResolve }
    end;
    Exit;
  end;

  { ordinary instruction }
  AsmTextLineXtensa(line, holes, nHoles);
end;

{ resolve forward jumps/branches now that all labels are placed }
procedure AsmXtensaBlockResolve;
var j, k, targetPos: Integer;
begin
  for k := 0 to AsmXtFwCount - 1 do
  begin
    targetPos := -1;
    for j := 0 to AsmXtLblCount - 1 do
      if AsmXtLblName[j] = AsmXtFwName[k] then targetPos := AsmXtLblPos[j];
    if targetPos < 0 then Error('EmitAsmXtensa: undefined label in jump');
    if AsmXtFwIsJ[k] then
      Patch24(AsmXtFwPatch[k], EncodeXtensaJ(targetPos - AsmXtFwPatch[k]))
    else
    begin
      AsmXtensaCheckBranch(targetPos - AsmXtFwPatch[k]);
      Patch24(AsmXtFwPatch[k], EncodeXtensaBranch(AsmXtFwR[k], AsmXtFwS[k], AsmXtFwT[k], targetPos - AsmXtFwPatch[k]));
    end;
  end;
end;

{ Replay one parse-time-captured inline-asm line (see AsmParseBodyTextXtensa,
  asmenc.inc). Hole values come from the InlineAsmHoleVal pool, count stored
  explicitly per line (NOT derived from '%' — an @fp/@glob operand consumes a
  hole without one). Caller brackets a block with AsmXtensaBlockBegin/Resolve. }
procedure AsmXtensaProcessInlineLine(idx: Integer);
var
  holes: array[0..ASM_MAX_HOLES - 1] of Int64;
  k: Integer;
begin
  if InlineAsmLineHoleN[idx] > ASM_MAX_HOLES then
    Error('EmitAsmXtensa: too many holes in one line');
  for k := 0 to InlineAsmLineHoleN[idx] - 1 do
    holes[k] := InlineAsmHoleVal[InlineAsmLineHole0[idx] + k];
  AsmXtensaProcessLine(InlineAsmLine[idx], holes, InlineAsmLineHoleN[idx]);
end;

procedure EmitAsmXtensa(const items: array of const);
var
  i, n, h, nHoles: Integer;
  line: AnsiString;
  holes: array[0..ASM_MAX_HOLES - 1] of Int64;
begin
  AsmXtensaBlockBegin;
  n := Length(items);
  i := 0;
  while i < n do
  begin
    if items[i].VType <> vtAnsiString then
      Error('EmitAsmXtensa: expected an instruction string');
    line := AsmTextCStr(items[i].VAnsiString);

    nHoles := 0;
    for h := 1 to Length(line) do
      if line[h] = '%' then Inc(nHoles);
    if nHoles > ASM_MAX_HOLES then Error('EmitAsmXtensa: too many holes in one line');
    for h := 0 to nHoles - 1 do
    begin
      if (i + 1 + h >= n) or (items[i + 1 + h].VType <> vtInteger) and (items[i + 1 + h].VType <> vtInt64) then
        Error('EmitAsmXtensa: missing integer hole value');
      if items[i + 1 + h].VType = vtInt64 then holes[h] := PHoleI64(items[i + 1 + h].VInt64)^ else holes[h] := items[i + 1 + h].VInteger;
    end;
    AsmXtensaProcessLine(line, holes, nHoles);
    i := i + 1 + nHoles;
  end;
  AsmXtensaBlockResolve;
end;
