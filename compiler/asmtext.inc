{ asmtext.inc — text-assembler for readable codegen emission.

  EmitAsmX64 takes an interleaved `array of const`: each string is one x86-64
  instruction (Intel syntax, one per line), and the integers that follow a
  string are that line's `%` hole values, in order. Instructions are encoded to
  the code buffer through the typed x64_* encoders in x64enc.inc, so ModRM/REX
  is computed once and correctly. Readable alternative to long EmitB runs.

  Example: a push/mov pair with one immediate hole is written as the list
  'push rbp', 'mov rbp, rsp', 'sub rsp, %', frameSize.

  Markers / forms supported in this slice:
    - registers: 8/16/32/64-bit (rax..r15 and sub-registers)
    - `%`        value hole; the next int element is the immediate/displacement,
                 width inferred from the instruction
    - immediates: decimal or 0x-hex literals
    - memory:    [base], [base+disp], [base-disp], [base+%]
    - mnemonics: ret leave syscall nop cqo cdq; push pop; mov; lea;
                 add sub and or xor cmp (reg,imm | reg,reg)

  Anything else raises a clear error — grow the table per need. Shares the
  encoder core with the typed codegen and (later) inline asm. }

type
  PAsmTextByte = ^Byte;

const
  ASM_MAX_HOLES = 8;

{ Rebuild a Pascal string from a NUL-terminated char-data pointer (a TVarRec
  VAnsiString element holds one). }
function AsmTextCStr(p: Pointer): AnsiString;
var b: PAsmTextByte; i: Integer;
begin
  Result := '';
  if p = nil then Exit;
  b := PAsmTextByte(p);
  i := 0;
  while b[i] <> 0 do
  begin
    AppendChar(Result, Chr(b[i]));
    Inc(i);
  end;
end;

function AsmTextIsSpace(c: Char): Boolean;
begin
  Result := (c = ' ') or (c = Chr(9));
end;

{ Safe character access: Chr(0) when idx is out of range. The dialect evaluates
  `and`/`or` fully (no short-circuit) and indexing an EMPTY AnsiString derefs a
  nil data pointer, so a guard like `(Length(s)>0) and (s[1]=..)` still touches
  s[1]; route every conditional char read through here instead. }
function AsmTextCharAt(const s: AnsiString; idx: Integer): Char;
begin
  if (idx >= 1) and (idx <= Length(s)) then Result := s[idx]
  else Result := Chr(0);
end;

{ Substring s[from..from+len-1] (1-based), built by char append — the dialect
  has no Copy. }
function AsmTextSlice(const s: AnsiString; from, len: Integer): AnsiString;
var i: Integer;
begin
  Result := '';
  i := from;
  while (i < from + len) and (i <= Length(s)) do
  begin
    AppendChar(Result, s[i]);
    Inc(i);
  end;
end;

{ Lowercase a single ASCII letter. }
function AsmTextLower(c: Char): Char;
begin
  if (c >= 'A') and (c <= 'Z') then Result := Chr(Ord(c) + 32)
  else Result := c;
end;

{ Parse a signed integer literal: decimal, or 0x.. / $.. hex. }
function AsmTextParseInt(const s: AnsiString): Int64;
var i, n: Integer; neg: Boolean; v: Int64; c: Char; d: Integer; hex: Boolean;
begin
  v := 0; neg := False; hex := False;
  n := Length(s);
  i := 1;
  if (i <= n) and (AsmTextCharAt(s, i) = '-') then begin neg := True; Inc(i); end;
  if (i + 1 <= n) and (AsmTextCharAt(s, i) = '0') and (AsmTextLower(AsmTextCharAt(s, i+1)) = 'x') then
    begin hex := True; i := i + 2; end
  else if (i <= n) and (AsmTextCharAt(s, i) = '$') then
    begin hex := True; Inc(i); end;
  while i <= n do
  begin
    c := AsmTextLower(s[i]);
    d := -1;
    if (c >= '0') and (c <= '9') then d := Ord(c) - Ord('0')
    else if hex and (c >= 'a') and (c <= 'f') then d := 10 + Ord(c) - Ord('a')
    else Error('EmitAsmX64: bad integer literal');
    if hex then v := v * 16 + d else v := v * 10 + d;
    Inc(i);
  end;
  if neg then v := -v;
  Result := v;
end;

{ Size in bytes of an explicit-size keyword (byte/word/dword/qword), else 0. }
function AsmTextSizeKeyword(const w: AnsiString): Integer;
begin
  if CaseEqual(w, 'byte') then Result := 1
  else if CaseEqual(w, 'word') then Result := 2
  else if CaseEqual(w, 'dword') then Result := 4
  else if CaseEqual(w, 'qword') then Result := 8
  else Result := 0;
end;

{ ALU r/m,imm where r/m is memory [base+disp]. ext is the opcode digit
  (add0 or1 adc2 sbb3 and4 sub5 xor6 cmp7). }
procedure AsmEncAluMemImm(ext, size, baseReg, disp: Integer; imm: Int64);
begin
  EncPrefixAndREX(size, ext, baseReg, False);
  if size = 1 then
  begin
    EncB($80); EncModRMMem(ext, baseReg, disp, False); EncB(Integer(imm) and $FF);
  end
  else if (imm >= -128) and (imm <= 127) then
  begin
    EncB($83); EncModRMMem(ext, baseReg, disp, False); EncB(Integer(imm) and $FF);
  end
  else
  begin
    EncB($81); EncModRMMem(ext, baseReg, disp, False); EncI32(imm);
  end;
end;

{ Classify one operand text. Returns kind via Result: 0=register, 1=immediate,
  2=memory [base+disp]. Fills the relevant out params (regSize doubles as the
  explicit memory-operand size for kind 2, 0 if unspecified). `%` immediates/
  disps pull the next value from holes[] via holeCur. }
function AsmTextOperand(const opIn: AnsiString;
  const holes: array of Int64; var holeCur: Integer;
  var regNum, regSize, memBase, memDisp: Integer; var immVal: Int64): Integer;
var op, inner, baseStr, dispStr, firstWord: AnsiString;
    i, n, dummySize, memSize, p: Integer; sign: Integer;
begin
  { trim }
  op := '';
  n := Length(opIn);
  i := 1;
  while (i <= n) and AsmTextIsSpace(AsmTextCharAt(opIn, i)) do Inc(i);
  while (n >= i) and AsmTextIsSpace(AsmTextCharAt(opIn, n)) do Dec(n);
  while i <= n do begin AppendChar(op, opIn[i]); Inc(i); end;

  if Length(op) = 0 then Error('EmitAsmX64: empty operand');

  { strip a leading explicit-size keyword (byte/word/dword/qword) if present }
  firstWord := ''; p := 1;
  while (p <= Length(op)) and not AsmTextIsSpace(AsmTextCharAt(op, p)) do
    begin AppendChar(firstWord, AsmTextLower(op[p])); Inc(p); end;
  memSize := AsmTextSizeKeyword(firstWord);
  if memSize > 0 then
  begin
    while (p <= Length(op)) and AsmTextIsSpace(AsmTextCharAt(op, p)) do Inc(p);
    op := AsmTextSlice(op, p, Length(op) - p + 1);
  end;

  { memory: [ base (+|-) disp ] }
  if AsmTextCharAt(op, 1) = '[' then
  begin
    inner := '';
    i := 2;
    while (i <= Length(op)) and (AsmTextCharAt(op, i) <> ']') do begin AppendChar(inner, op[i]); Inc(i); end;
    { split on + or - }
    baseStr := ''; dispStr := ''; sign := 1;
    i := 1;
    while (i <= Length(inner)) and (AsmTextCharAt(inner, i) <> '+') and (AsmTextCharAt(inner, i) <> '-') do
      begin AppendChar(baseStr, inner[i]); Inc(i); end;
    if i <= Length(inner) then
    begin
      if AsmTextCharAt(inner, i) = '-' then sign := -1;
      Inc(i);
      while i <= Length(inner) do begin AppendChar(dispStr, inner[i]); Inc(i); end;
    end;
    { trim base }
    while AsmTextIsSpace(AsmTextCharAt(baseStr, Length(baseStr))) do
      baseStr := AsmTextSlice(baseStr, 1, Length(baseStr) - 1);
    if not AsmRegNum(baseStr, memBase, dummySize) then
      Error('EmitAsmX64: bad memory base register');
    { trim disp }
    while AsmTextIsSpace(AsmTextCharAt(dispStr, 1)) do
      dispStr := AsmTextSlice(dispStr, 2, Length(dispStr) - 1);
    if Length(dispStr) = 0 then
      memDisp := 0
    else if AsmTextCharAt(dispStr, 1) = '%' then
    begin
      memDisp := Integer(holes[holeCur]) * sign; Inc(holeCur);
    end
    else
      memDisp := Integer(AsmTextParseInt(dispStr)) * sign;
    regSize := memSize;   { explicit operand size, 0 if unspecified }
    Result := 2;
    Exit;
  end;

  { register }
  if AsmRegNum(op, regNum, regSize) then
  begin
    Result := 0;
    Exit;
  end;

  { immediate: % hole or literal }
  if AsmTextCharAt(op, 1) = '%' then
  begin
    immVal := holes[holeCur]; Inc(holeCur);
  end
  else
    immVal := AsmTextParseInt(op);
  Result := 1;
end;

{ Assemble one instruction line, binding its `%` holes from holes[0..nHoles-1]. }
procedure AsmTextLine(const line: AnsiString; const holes: array of Int64; nHoles: Integer);
var
  mnem, rest, op0, op1: AnsiString;
  i, n, holeCur, commaPos: Integer;
  k0, k1, r0, s0, r1, s1, mb0, md0, mb1, md1: Integer;
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
  if CaseEqual(mnem, 'ret') then begin x64_ret; Exit; end;
  if CaseEqual(mnem, 'leave') then begin x64_leave; Exit; end;
  if CaseEqual(mnem, 'syscall') then begin x64_syscall; Exit; end;
  if CaseEqual(mnem, 'nop') then begin EncB($90); Exit; end;
  if CaseEqual(mnem, 'cqo') then begin EncB($48); EncB($99); Exit; end;
  if CaseEqual(mnem, 'cdq') then begin EncB($99); Exit; end;

  if not haveOps then Error('EmitAsmX64: unknown 0-operand mnemonic');

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

  { single-operand: push / pop }
  if CaseEqual(mnem, 'push') then
  begin
    if AsmTextOperand(op0, holes, holeCur, r0, s0, mb0, md0, imm0) <> 0 then
      Error('EmitAsmX64: push expects a register');
    x64_push_reg(r0); Exit;
  end;
  if CaseEqual(mnem, 'pop') then
  begin
    if AsmTextOperand(op0, holes, holeCur, r0, s0, mb0, md0, imm0) <> 0 then
      Error('EmitAsmX64: pop expects a register');
    x64_pop_reg(r0); Exit;
  end;
  if CaseEqual(mnem, 'inc') or CaseEqual(mnem, 'dec') then
  begin
    if AsmTextOperand(op0, holes, holeCur, r0, s0, mb0, md0, imm0) <> 0 then
      Error('EmitAsmX64: inc/dec expects a register (this slice)');
    if CaseEqual(mnem, 'dec') then i := 1 else i := 0;   { FF /0 = inc, /1 = dec }
    EncPrefixAndREX(s0, i, r0, False);
    if s0 = 1 then EncB($FE) else EncB($FF);
    EncModRMReg(i, r0);
    Exit;
  end;

  { two-operand forms }
  if Length(op1) = 0 then Error('EmitAsmX64: instruction needs two operands');
  k0 := AsmTextOperand(op0, holes, holeCur, r0, s0, mb0, md0, imm0);
  k1 := AsmTextOperand(op1, holes, holeCur, r1, s1, mb1, md1, imm1);

  if CaseEqual(mnem, 'mov') then
  begin
    if (k0 = 0) and (k1 = 0) then x64_mov_reg_reg(s0, r0, r1)
    else if (k0 = 0) and (k1 = 1) then x64_mov_reg_imm(s0, r0, imm1)
    else if (k0 = 0) and (k1 = 2) then x64_mov_reg_mem(s0, r0, mb1, md1, False)
    else if (k0 = 2) and (k1 = 0) then x64_mov_mem_reg(s1, mb0, md0, r1, False)
    else Error('EmitAsmX64: unsupported mov form');
    Exit;
  end;
  if CaseEqual(mnem, 'lea') then
  begin
    if (k0 = 0) and (k1 = 2) then x64_lea_reg_mem(s0, r0, mb1, md1, False)
    else Error('EmitAsmX64: unsupported lea form');
    Exit;
  end;

  { ALU reg,imm or reg,reg }
  if (k0 = 0) and (k1 = 1) then
  begin
    if CaseEqual(mnem, 'add') then x64_add_reg_imm(s0, r0, imm1)
    else if CaseEqual(mnem, 'sub') then x64_sub_reg_imm(s0, r0, imm1)
    else if CaseEqual(mnem, 'and') then x64_and_reg_imm(s0, r0, imm1)
    else if CaseEqual(mnem, 'or')  then x64_or_reg_imm(s0, r0, imm1)
    else if CaseEqual(mnem, 'xor') then x64_xor_reg_imm(s0, r0, imm1)
    else if CaseEqual(mnem, 'cmp') then x64_cmp_reg_imm(s0, r0, imm1)
    else Error('EmitAsmX64: unsupported reg,imm mnemonic');
    Exit;
  end;
  if (k0 = 0) and (k1 = 0) then
  begin
    if CaseEqual(mnem, 'add') then x64_add_reg_reg(s0, r0, r1)
    else if CaseEqual(mnem, 'sub') then x64_sub_reg_reg(s0, r0, r1)
    else if CaseEqual(mnem, 'and') then x64_and_reg_reg(s0, r0, r1)
    else if CaseEqual(mnem, 'or')  then x64_or_reg_reg(s0, r0, r1)
    else if CaseEqual(mnem, 'xor') then x64_xor_reg_reg(s0, r0, r1)
    else if CaseEqual(mnem, 'cmp') then x64_cmp_reg_reg(s0, r0, r1)
    else Error('EmitAsmX64: unsupported reg,reg mnemonic');
    Exit;
  end;

  { ALU r/m(mem),imm — needs an explicit operand size (e.g. cmp byte [rdx], 0). }
  if (k0 = 2) and (k1 = 1) then
  begin
    if s0 = 0 then Error('EmitAsmX64: memory ALU needs an explicit size (byte/dword/qword)');
    if CaseEqual(mnem, 'add') then i := 0
    else if CaseEqual(mnem, 'or')  then i := 1
    else if CaseEqual(mnem, 'and') then i := 4
    else if CaseEqual(mnem, 'sub') then i := 5
    else if CaseEqual(mnem, 'xor') then i := 6
    else if CaseEqual(mnem, 'cmp') then i := 7
    else begin Error('EmitAsmX64: unsupported mem,imm mnemonic'); i := 0; end;
    AsmEncAluMemImm(i, s0, mb0, md0, imm1);
    Exit;
  end;

  Error('EmitAsmX64: unsupported instruction');
end;

{ Map a jump mnemonic to its condition-code nibble; -1 via Result=False for an
  unconditional jmp; False with cc untouched for a non-jump. }
function AsmTextJccCode(const m: AnsiString; var cc: Integer): Boolean;
begin
  Result := True;
  if CaseEqual(m, 'jo') then cc := 0
  else if CaseEqual(m, 'jno') then cc := 1
  else if CaseEqual(m, 'jb') or CaseEqual(m, 'jc') or CaseEqual(m, 'jnae') then cc := 2
  else if CaseEqual(m, 'jae') or CaseEqual(m, 'jnb') or CaseEqual(m, 'jnc') then cc := 3
  else if CaseEqual(m, 'je') or CaseEqual(m, 'jz') then cc := 4
  else if CaseEqual(m, 'jne') or CaseEqual(m, 'jnz') then cc := 5
  else if CaseEqual(m, 'jbe') or CaseEqual(m, 'jna') then cc := 6
  else if CaseEqual(m, 'ja') or CaseEqual(m, 'jnbe') then cc := 7
  else if CaseEqual(m, 'js') then cc := 8
  else if CaseEqual(m, 'jns') then cc := 9
  else if CaseEqual(m, 'jp') then cc := 10
  else if CaseEqual(m, 'jnp') then cc := 11
  else if CaseEqual(m, 'jl') or CaseEqual(m, 'jnge') then cc := 12
  else if CaseEqual(m, 'jge') or CaseEqual(m, 'jnl') then cc := 13
  else if CaseEqual(m, 'jle') or CaseEqual(m, 'jng') then cc := 14
  else if CaseEqual(m, 'jg') or CaseEqual(m, 'jnle') then cc := 15
  else Result := False;
end;

const ASM_MAX_LABELS = 32;

{ Label / forward-jump bookkeeping for one EmitAsmX64 call. Module-level (not
  locals) because the dialect's local arrays-of-AnsiString are a self-host
  landmine — the compiler keeps such tables global, like GotoLabel*. Codegen is
  single-threaded, so a shared scratch table is safe. }
var
  AsmLblName: array[0..ASM_MAX_LABELS - 1] of AnsiString;
  AsmLblPos:  array[0..ASM_MAX_LABELS - 1] of Integer;
  AsmLblCount: Integer;
  AsmFwName:  array[0..ASM_MAX_LABELS - 1] of AnsiString;
  AsmFwPatch: array[0..ASM_MAX_LABELS - 1] of Integer;
  AsmFwCount: Integer;

procedure EmitAsmX64(const items: array of const);
var
  i, n, h, nHoles, j: Integer;
  line, trimmed, mnem, target: AnsiString;
  holes: array[0..ASM_MAX_HOLES - 1] of Int64;
  cc, k, targetPos, disp: Integer;
  isJmp, defined: Boolean;
begin
  AsmLblCount := 0; AsmFwCount := 0;
  n := Length(items);
  i := 0;
  while i < n do
  begin
    if items[i].VType <> vtAnsiString then
      Error('EmitAsmX64: expected an instruction string');
    line := AsmTextCStr(items[i].VAnsiString);

    { trim for label/jump classification }
    trimmed := '';
    j := 1;
    while (j <= Length(line)) and AsmTextIsSpace(AsmTextCharAt(line, j)) do Inc(j);
    while j <= Length(line) do begin AppendChar(trimmed, line[j]); Inc(j); end;
    while AsmTextIsSpace(AsmTextCharAt(trimmed, Length(trimmed))) do
      trimmed := AsmTextSlice(trimmed, 1, Length(trimmed) - 1);

    { first word = mnemonic }
    mnem := ''; j := 1;
    while (j <= Length(trimmed)) and not AsmTextIsSpace(AsmTextCharAt(trimmed, j)) do
      begin AppendChar(mnem, AsmTextLower(trimmed[j])); Inc(j); end;

    isJmp := CaseEqual(mnem, 'jmp');
    if (Length(trimmed) >= 2) and (AsmTextCharAt(trimmed, Length(trimmed)) = ':') then
    begin
      { label definition: `name:` (a bare line ending in ':') }
      if AsmLblCount >= ASM_MAX_LABELS then Error('EmitAsmX64: too many labels');
      AsmLblName[AsmLblCount] := AsmTextSlice(trimmed, 1, Length(trimmed) - 1);
      AsmLblPos[AsmLblCount] := CodeLen;
      Inc(AsmLblCount);
      Inc(i);
    end
    else if isJmp or AsmTextJccCode(mnem, cc) then
    begin
      { operand = label name }
      while (j <= Length(trimmed)) and AsmTextIsSpace(AsmTextCharAt(trimmed, j)) do Inc(j);
      target := '';
      while j <= Length(trimmed) do begin AppendChar(target, trimmed[j]); Inc(j); end;

      defined := False; targetPos := 0;
      for k := 0 to AsmLblCount - 1 do
        if AsmLblName[k] = target then begin defined := True; targetPos := AsmLblPos[k]; end;

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
        if AsmFwCount >= ASM_MAX_LABELS then Error('EmitAsmX64: too many forward jumps');
        AsmFwName[AsmFwCount] := target;
        AsmFwPatch[AsmFwCount] := CodeLen;   { position of the rel32 displacement }
        Inc(AsmFwCount);
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
      if nHoles > ASM_MAX_HOLES then Error('EmitAsmX64: too many holes in one line');
      for h := 0 to nHoles - 1 do
      begin
        if (i + 1 + h >= n) or (items[i + 1 + h].VType <> vtInteger) then
          Error('EmitAsmX64: missing integer hole value');
        holes[h] := items[i + 1 + h].VInteger;
      end;
      AsmTextLine(line, holes, nHoles);
      i := i + 1 + nHoles;
    end;
  end;

  { resolve forward jumps now that all labels are placed. }
  for k := 0 to AsmFwCount - 1 do
  begin
    targetPos := -1;
    for j := 0 to AsmLblCount - 1 do
      if AsmLblName[j] = AsmFwName[k] then targetPos := AsmLblPos[j];
    if targetPos < 0 then Error('EmitAsmX64: undefined label in jump');
    Patch32(AsmFwPatch[k], targetPos - (AsmFwPatch[k] + 4));
  end;
end;

{ asmtext_rv32.inc — text-assembler for readable RISC-V RV32 codegen emission. }

function AsmRv32Trim(const s: AnsiString): AnsiString;
var i, n: Integer;
begin
  Result := '';
  n := Length(s);
  i := 1;
  while (i <= n) and AsmTextIsSpace(AsmTextCharAt(s, i)) do Inc(i);
  while (n >= i) and AsmTextIsSpace(AsmTextCharAt(s, n)) do Dec(n);
  while i <= n do begin AppendChar(Result, s[i]); Inc(i); end;
end;

function AsmRv32RegNum(const opIn: AnsiString; var reg: Integer): Boolean;
var s: AnsiString; i, n, v: Integer; c: Char;
begin
  Result := False;
  s := AsmRv32Trim(opIn);
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
  s := AsmRv32Trim(opIn);
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
  s := AsmRv32Trim(opIn);
  p := 0;
  n := Length(s);
  for i := 1 to n do
    if s[i] = '(' then p := i;
  if p = 0 then
    Error('EmitAsmRv32: expected memory operand format imm(reg)');
  
  dispStr := AsmRv32Trim(AsmTextSlice(s, 1, p - 1));
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
  regStr := AsmRv32Trim(regStr);
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

function AsmRv32IsLabel(const s: AnsiString): Boolean;
var c: Char;
begin
  c := AsmTextCharAt(s, 1);
  Result := (c <> '%') and (c <> '-') and ((c < '0') or (c > '9'));
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
  op0 := AsmRv32Trim(op0); op1 := AsmRv32Trim(op1); op2 := AsmRv32Trim(op2);

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
    trimmed := AsmRv32Trim(line);

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
      rest := AsmRv32Trim(AsmTextSlice(trimmed, j, Length(trimmed) - j + 1));
      op0 := ''; op1 := ''; partIdx := 0;
      for k := 1 to Length(rest) do
      begin
        if rest[k] = ',' then Inc(partIdx)
        else if partIdx = 0 then AppendChar(op0, rest[k])
        else AppendChar(op1, rest[k]);
      end;
      op0 := AsmRv32Trim(op0);
      op1 := AsmRv32Trim(op1);

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

      if AsmRv32IsLabel(target) then
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
          if (i + 1 + h >= n) or (items[i + 1 + h].VType <> vtInteger) then
            Error('EmitAsmRv32: missing integer hole value');
          holes[h] := items[i + 1 + h].VInteger;
        end;
        AsmTextLineRv32(line, holes, nHoles);
        i := i + 1 + nHoles;
      end;
    end
    else if isBr then
    begin
      { conditional branch: `bXX rs1, rs2, .label` }
      rest := AsmRv32Trim(AsmTextSlice(trimmed, j, Length(trimmed) - j + 1));
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
      target := AsmRv32Trim(target);

      if AsmRv32IsLabel(target) then
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
          if (i + 1 + h >= n) or (items[i + 1 + h].VType <> vtInteger) then
            Error('EmitAsmRv32: missing integer hole value');
          holes[h] := items[i + 1 + h].VInteger;
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
        if (i + 1 + h >= n) or (items[i + 1 + h].VType <> vtInteger) then
          Error('EmitAsmRv32: missing integer hole value');
        holes[h] := items[i + 1 + h].VInteger;
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

{ --- AArch64 Emitter --- }

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

{ --- ARM32 Emitter --- }

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

{ --- i386 text-assembler (EmitAsm386) --- }

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
  op0 := AsmRv32Trim(op0);
  op1 := AsmRv32Trim(op1);

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
    trimmed := AsmRv32Trim(line);

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
        if (i + 1 + h >= n) or (items[i + 1 + h].VType <> vtInteger) then
          Error('EmitAsm386: missing integer hole value');
        holes[h] := items[i + 1 + h].VInteger;
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
