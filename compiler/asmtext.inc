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
  if (i <= n) and (s[i] = '-') then begin neg := True; Inc(i); end;
  if (i + 1 <= n) and (s[i] = '0') and (AsmTextLower(s[i+1]) = 'x') then
    begin hex := True; i := i + 2; end
  else if (i <= n) and (s[i] = '$') then
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

{ Classify one operand text. Returns kind via Result: 0=register, 1=immediate,
  2=memory [base+disp]. Fills the relevant out params. `%` immediates/disps pull
  the next value from holes[] via holeCur. }
function AsmTextOperand(const opIn: AnsiString;
  const holes: array of Int64; var holeCur: Integer;
  var regNum, regSize, memBase, memDisp: Integer; var immVal: Int64): Integer;
var op, inner, baseStr, dispStr: AnsiString;
    i, n, dummySize: Integer; sign: Integer;
begin
  { trim }
  op := '';
  n := Length(opIn);
  i := 1;
  while (i <= n) and AsmTextIsSpace(opIn[i]) do Inc(i);
  while (n >= i) and AsmTextIsSpace(opIn[n]) do Dec(n);
  while i <= n do begin AppendChar(op, opIn[i]); Inc(i); end;

  if Length(op) = 0 then Error('EmitAsmX64: empty operand');

  { memory: [ base (+|-) disp ] }
  if op[1] = '[' then
  begin
    inner := '';
    i := 2;
    while (i <= Length(op)) and (op[i] <> ']') do begin AppendChar(inner, op[i]); Inc(i); end;
    { split on + or - }
    baseStr := ''; dispStr := ''; sign := 1;
    i := 1;
    while (i <= Length(inner)) and (inner[i] <> '+') and (inner[i] <> '-') do
      begin AppendChar(baseStr, inner[i]); Inc(i); end;
    if i <= Length(inner) then
    begin
      if inner[i] = '-' then sign := -1;
      Inc(i);
      while i <= Length(inner) do begin AppendChar(dispStr, inner[i]); Inc(i); end;
    end;
    { trim base }
    while (Length(baseStr) > 0) and AsmTextIsSpace(baseStr[Length(baseStr)]) do
      baseStr := AsmTextSlice(baseStr, 1, Length(baseStr) - 1);
    if not AsmRegNum(baseStr, memBase, dummySize) then
      Error('EmitAsmX64: bad memory base register');
    { trim disp }
    while (Length(dispStr) > 0) and AsmTextIsSpace(dispStr[1]) do
      dispStr := AsmTextSlice(dispStr, 2, Length(dispStr) - 1);
    if Length(dispStr) = 0 then
      memDisp := 0
    else if dispStr[1] = '%' then
    begin
      memDisp := Integer(holes[holeCur]) * sign; Inc(holeCur);
    end
    else
      memDisp := Integer(AsmTextParseInt(dispStr)) * sign;
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
  if op[1] = '%' then
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
  while (i <= n) and AsmTextIsSpace(line[i]) do Inc(i);
  { mnemonic }
  mnem := '';
  while (i <= n) and not AsmTextIsSpace(line[i]) do begin AppendChar(mnem, AsmTextLower(line[i])); Inc(i); end;
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

  Error('EmitAsmX64: unsupported instruction');
end;

procedure EmitAsmX64(const items: array of const);
var
  i, n, h, nHoles: Integer;
  line: AnsiString;
  holes: array[0..ASM_MAX_HOLES - 1] of Int64;
begin
  n := Length(items);
  i := 0;
  while i < n do
  begin
    if items[i].VType <> vtAnsiString then
      Error('EmitAsmX64: expected an instruction string');
    line := AsmTextCStr(items[i].VAnsiString);
    { count `%` markers; consume that many following int holes }
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
