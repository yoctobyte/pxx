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
  PHoleI64 = ^Int64;   { deref a boxed vtInt64 `array of const` hole value }

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

{ Trim leading/trailing whitespace. Shared by all per-target emitters. }
function AsmTextTrim(const s: AnsiString): AnsiString;
var i, n: Integer;
begin
  Result := '';
  n := Length(s);
  i := 1;
  while (i <= n) and AsmTextIsSpace(AsmTextCharAt(s, i)) do Inc(i);
  while (n >= i) and AsmTextIsSpace(AsmTextCharAt(s, n)) do Dec(n);
  while i <= n do begin AppendChar(Result, s[i]); Inc(i); end;
end;

{ True when an operand token reads as a label reference (not %, not a signed
  number). Shared by the per-target emitters. }
function AsmTextIsLabel(const s: AnsiString): Boolean;
var c: Char;
begin
  c := AsmTextCharAt(s, 1);
  Result := (c <> '%') and (c <> '-') and ((c < '0') or (c > '9'));
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

{ Absolute-address r/m: ModRM mod=00 rm=100 + SIB=$25 (no base/index, disp32)
  followed by a 4-byte relocation. kind 3 = glob (BSS), 4 = data. The r/m form
  the atomic mutex slot and zeroing store use ([@glob]). }
procedure AsmEncAbsRM(regField, kind, off: Integer);
begin
  EncB(((regField and 7) shl 3) or 4);
  EncB($25);
  if kind = 4 then EmitDataRef(off) else EmitGlobRef(off);
end;

{ Classify one operand text. Returns kind via Result: 0=register, 1=immediate,
  2=memory [base+disp], 3=absolute [@glob], 4=absolute [@data]. Fills the
  relevant out params (regSize doubles as the
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
    inner := AsmTextTrim(inner);

    { absolute-address r/m: [@glob] / [@data] — the disp32 is a reloc hole, no
      base register. Kind 3 = glob (BSS), kind 4 = data; offset returned in
      memDisp (consumes one hole). Used by the atomic mutex slot. }
    if AsmTextCharAt(inner, 1) = '@' then
    begin
      memDisp := Integer(holes[holeCur]); Inc(holeCur);
      regSize := memSize;
      if CaseEqual(inner, '@glob') then Result := 3
      else if CaseEqual(inner, '@data') then Result := 4
      else begin Error('EmitAsmX64: bad absolute memory operand'); Result := 3; end;
      Exit;
    end;

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
    else if AsmRegNum(dispStr, dummySize, dummySize) then
      Error('EmitAsmX64: [base+index-register] (SIB) addressing not supported — write it as raw EmitB')
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

{ Map a jump mnemonic to its condition-code nibble; Result=False for a
  non-jump. Shared by the label-jump path and setcc decoding. }
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

{ Assemble one instruction line, binding its `%` holes from holes[0..nHoles-1]. }
procedure AsmTextLine(const line: AnsiString; const holes: array of Int64; nHoles: Integer);
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
  if CaseEqual(mnem, 'ret') then begin x64_ret; Exit; end;
  if CaseEqual(mnem, 'leave') then begin x64_leave; Exit; end;
  if CaseEqual(mnem, 'syscall') then begin x64_syscall; Exit; end;
  if CaseEqual(mnem, 'nop') then begin EncB($90); Exit; end;
  if CaseEqual(mnem, 'cqo') then begin EncB($48); EncB($99); Exit; end;
  if CaseEqual(mnem, 'cdq') then begin EncB($99); Exit; end;
  if CaseEqual(mnem, 'movsb') then begin x64_movsb; Exit; end;
  if CaseEqual(mnem, 'stosb') then begin x64_stosb; Exit; end;

  { rep prefix: `rep movsb` / `rep stosb` (rest holds the string op) }
  if CaseEqual(mnem, 'rep') then
  begin
    rest := AsmTextTrim(rest);
    if CaseEqual(rest, 'movsb') then begin x64_rep_movsb; Exit; end;
    if CaseEqual(rest, 'stosb') then begin x64_rep_stosb; Exit; end;
    Error('EmitAsmX64: unsupported rep string op');
  end;

  { lock prefix: `lock xchg ...` etc — emit F0, then assemble the rest as a
    fresh line (the recursion re-binds holes from holes[0], and lock takes none). }
  if CaseEqual(mnem, 'lock') then
  begin
    EncB($F0);
    AsmTextLine(AsmTextTrim(rest), holes, nHoles);
    Exit;
  end;

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
  { trim so marker/keyword compares (e.g. @data) see no leading space;
    AsmTextOperand also trims, so this is harmless for the operand path. }
  op0 := AsmTextTrim(op0);
  op1 := AsmTextTrim(op1);

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
    k0 := AsmTextOperand(op0, holes, holeCur, r0, s0, mb0, md0, imm0);
    if CaseEqual(mnem, 'dec') then i := 1 else i := 0;   { FF /0 = inc, /1 = dec }
    if k0 = 0 then
    begin
      EncPrefixAndREX(s0, i, r0, False);
      if s0 = 1 then EncB($FE) else EncB($FF);
      EncModRMReg(i, r0);
    end
    else if k0 = 2 then
    begin
      if s0 = 0 then Error('EmitAsmX64: inc/dec mem needs an explicit size (byte/dword/qword)');
      EncPrefixAndREXMem(s0, i, mb0, s0 = 1);
      if s0 = 1 then EncB($FE) else EncB($FF);
      EncModRMMem(i, mb0, md0, False);
    end
    else if (k0 = 3) or (k0 = 4) then
    begin
      if s0 = 0 then Error('EmitAsmX64: inc/dec [@glob]/[@data] needs an explicit size (byte/dword/qword)');
      EncPrefixAndREX(s0, i, 0, False);
      if s0 = 1 then EncB($FE) else EncB($FF);
      AsmEncAbsRM(i, k0, md0);
    end
    else Error('EmitAsmX64: unsupported inc/dec form');
    Exit;
  end;

  { unary F6/F7 group (single register operand): not/neg/mul/div/idiv, and the
    one-operand imul (full-width result). ext digit per mnemonic. }
  if (Length(op1) = 0) and (CaseEqual(mnem, 'not') or CaseEqual(mnem, 'neg') or
     CaseEqual(mnem, 'mul') or CaseEqual(mnem, 'div') or
     CaseEqual(mnem, 'idiv') or CaseEqual(mnem, 'imul')) then
  begin
    if AsmTextOperand(op0, holes, holeCur, r0, s0, mb0, md0, imm0) <> 0 then
      Error('EmitAsmX64: unary op expects a register (this slice)');
    if CaseEqual(mnem, 'not') then i := 2
    else if CaseEqual(mnem, 'neg') then i := 3
    else if CaseEqual(mnem, 'mul') then i := 4
    else if CaseEqual(mnem, 'imul') then i := 5
    else if CaseEqual(mnem, 'div') then i := 6
    else i := 7;   { idiv }
    x64_unary_reg(s0, i, r0);
    Exit;
  end;

  { call reg (indirect) }
  if CaseEqual(mnem, 'call') then
  begin
    if AsmTextOperand(op0, holes, holeCur, r0, s0, mb0, md0, imm0) <> 0 then
      Error('EmitAsmX64: call expects a register (this slice)');
    x64_call_reg(r0);
    Exit;
  end;

  { setcc reg8: map the cc suffix through the jcc table (set<cc> -> j<cc>). }
  if (Length(mnem) >= 4) and (AsmTextCharAt(mnem, 1) = 's') and
     (AsmTextCharAt(mnem, 2) = 'e') and (AsmTextCharAt(mnem, 3) = 't') then
  begin
    rest := 'j' + AsmTextSlice(mnem, 4, Length(mnem) - 3);
    if not AsmTextJccCode(rest, i) then
      Error('EmitAsmX64: unknown setcc');
    if AsmTextOperand(op0, holes, holeCur, r0, s0, mb0, md0, imm0) <> 0 then
      Error('EmitAsmX64: setcc expects a register');
    x64_setcc_reg(i, r0);
    Exit;
  end;

  { two-operand forms }
  if Length(op1) = 0 then Error('EmitAsmX64: instruction needs two operands');

  { Relocations: mov reg, @data (abs 8-byte) / mov reg, @glob (abs 4-byte).
    @data follows the target pointer size via EmitDataRef; @glob is BSS, low 4G,
    encoded as a 32-bit mov (B8+r) so the high half zero-extends. }
  if CaseEqual(mnem, 'mov') and (CaseEqual(op1, '@data') or CaseEqual(op1, '@glob')) then
  begin
    if not AsmRegNum(op0, r0, s0) then
      Error('EmitAsmX64: reloc mov expects a destination register');
    imm0 := holes[holeCur]; Inc(holeCur);
    if CaseEqual(op1, '@data') then
    begin
      EncPrefixAndREX(8, 0, r0, False);   { REX.W for the imm64 form }
      EncB($B8 + (r0 and 7));
      EmitDataRef(Integer(imm0));
    end
    else
    begin
      if r0 >= 8 then EncB($41);   { REX.B only; 32-bit mov zero-extends }
      EncB($B8 + (r0 and 7));
      EmitGlobRef(Integer(imm0));
    end;
    Exit;
  end;

  k0 := AsmTextOperand(op0, holes, holeCur, r0, s0, mb0, md0, imm0);
  k1 := AsmTextOperand(op1, holes, holeCur, r1, s1, mb1, md1, imm1);

  { shifts: shl/sal, shr, sar — reg by imm or by cl }
  if CaseEqual(mnem, 'shl') or CaseEqual(mnem, 'sal') or
     CaseEqual(mnem, 'shr') or CaseEqual(mnem, 'sar') then
  begin
    if k0 <> 0 then Error('EmitAsmX64: shift expects a register dest (this slice)');
    if CaseEqual(mnem, 'shr') then i := 5
    else if CaseEqual(mnem, 'sar') then i := 7
    else i := 4;   { shl / sal }
    if (k1 = 0) and (r1 = 1) then x64_shift_reg_cl(s0, i, r0)   { ,cl (reg 1) }
    else if k1 = 1 then x64_shift_reg_imm(s0, i, r0, Integer(imm1))
    else Error('EmitAsmX64: shift count must be imm or cl');
    Exit;
  end;

  { imul reg, reg (two-operand signed multiply) }
  if CaseEqual(mnem, 'imul') then
  begin
    if (k0 = 0) and (k1 = 0) then x64_imul_reg_reg(s0, r0, r1)
    else Error('EmitAsmX64: unsupported imul form');
    Exit;
  end;

  { movzx / movsx reg, reg|mem }
  if CaseEqual(mnem, 'movzx') or CaseEqual(mnem, 'movsx') then
  begin
    if k0 <> 0 then Error('EmitAsmX64: movzx/movsx dest must be a register');
    if k1 = 0 then
      x64_movx_reg_reg(s0, s1, r0, r1, CaseEqual(mnem, 'movsx'))
    else if k1 = 2 then
    begin
      if s1 = 0 then Error('EmitAsmX64: movzx/movsx mem needs an explicit size (byte/word)');
      x64_movx_reg_mem(s0, s1, r0, mb1, md1, CaseEqual(mnem, 'movsx'), False);
    end
    else Error('EmitAsmX64: unsupported movzx/movsx form');
    Exit;
  end;

  { test: reg,reg | reg,imm | reg,[mem] | [mem],imm }
  if CaseEqual(mnem, 'test') then
  begin
    if (k0 = 0) and (k1 = 0) then x64_test_reg_reg(s0, r0, r1)
    else if (k0 = 0) and (k1 = 1) then x64_test_reg_imm(s0, r0, imm1)
    else if (k0 = 0) and (k1 = 2) then x64_test_reg_mem(s0, r0, mb1, md1, False)
    else if (k0 = 2) and (k1 = 0) then x64_test_reg_mem(s1, r1, mb0, md0, False)
    else if (k0 = 2) and (k1 = 1) then
    begin
      if s0 = 0 then Error('EmitAsmX64: test mem,imm needs an explicit size');
      x64_test_mem_imm(s0, mb0, md0, imm1, False);
    end
    else Error('EmitAsmX64: unsupported test form');
    Exit;
  end;

  { xchg (87 /r; 86 for byte). Supports reg,reg | reg,[mem] | [mem],reg and the
    absolute [@glob]/[@data] r/m used by the atomic mutex slot. The operand size
    comes from the register operand. }
  if CaseEqual(mnem, 'xchg') then
  begin
    if (k0 = 0) and (k1 = 0) then
    begin
      EncPrefixAndREX(s0, r0, r1, False);
      if s0 = 1 then EncB($86) else EncB($87);
      EncModRMReg(r0, r1);
    end
    else if (k0 = 0) and (k1 = 2) then
    begin
      EncPrefixAndREXMem(s0, r0, mb1, s0 = 1);
      if s0 = 1 then EncB($86) else EncB($87);
      EncModRMMem(r0, mb1, md1, False);
    end
    else if (k0 = 2) and (k1 = 0) then
    begin
      EncPrefixAndREXMem(s1, r1, mb0, s1 = 1);
      if s1 = 1 then EncB($86) else EncB($87);
      EncModRMMem(r1, mb0, md0, False);
    end
    else if ((k0 = 3) or (k0 = 4)) and (k1 = 0) then
    begin
      EncPrefixAndREX(s1, r1, 0, False);
      if s1 = 1 then EncB($86) else EncB($87);
      AsmEncAbsRM(r1, k0, md0);
    end
    else if (k0 = 0) and ((k1 = 3) or (k1 = 4)) then
    begin
      EncPrefixAndREX(s0, r0, 0, False);
      if s0 = 1 then EncB($86) else EncB($87);
      AsmEncAbsRM(r0, k1, md1);
    end
    else Error('EmitAsmX64: unsupported xchg form');
    Exit;
  end;

  { movq — five encodings selected by operand kind (xmm flagged size 16):
    xmm,gp (66 [W] 0F 6E) / gp,xmm (66 [W] 0F 7E) / xmm,xmm (F3 0F 7E) /
    xmm,[mem] (F3 0F 7E) / [mem],xmm (66 0F D6). }
  if CaseEqual(mnem, 'movq') then
  begin
    if (k0 = 0) and (k1 = 0) and (s0 = 16) and (s1 = 16) then
      x64_sse_rr($F3, $7E, r0, r1, False)               { xmm, xmm }
    else if (k0 = 0) and (k1 = 0) and (s0 = 16) then
      x64_sse_rr($66, $6E, r0, r1, s1 = 8)              { xmm, gp }
    else if (k0 = 0) and (k1 = 0) and (s1 = 16) then
      x64_sse_rr($66, $7E, r1, r0, s0 = 8)              { gp, xmm }
    else if (k0 = 0) and (k1 = 2) and (s0 = 16) then
      x64_sse_rm($F3, $7E, r0, mb1, md1, False, False)  { xmm, [mem] }
    else if (k0 = 2) and (k1 = 0) and (s1 = 16) then
      x64_sse_rm($66, $D6, r1, mb0, md0, False, False)  { [mem], xmm }
    else Error('EmitAsmX64: unsupported movq form');
    Exit;
  end;

  { SSE scalar arithmetic / move / compare / convert / packed-logical.
    Prefix: F2 (double *sd), F3 (single *ss), 66 (packed-double / pxor), or
    none (xorps). move ops have a distinct store opcode (11/D6) for [mem],xmm. }
  if CaseEqual(mnem, 'movsd') or CaseEqual(mnem, 'movss') or
     CaseEqual(mnem, 'addsd') or CaseEqual(mnem, 'subsd') or
     CaseEqual(mnem, 'mulsd') or CaseEqual(mnem, 'divsd') or
     CaseEqual(mnem, 'addss') or CaseEqual(mnem, 'subss') or
     CaseEqual(mnem, 'mulss') or CaseEqual(mnem, 'divss') or
     CaseEqual(mnem, 'comisd') or CaseEqual(mnem, 'ucomisd') or
     CaseEqual(mnem, 'cvtsd2ss') or CaseEqual(mnem, 'cvtss2sd') or
     CaseEqual(mnem, 'xorps') or CaseEqual(mnem, 'xorpd') or CaseEqual(mnem, 'pxor') then
  begin
    { prefix }
    if CaseEqual(mnem, 'movss') or CaseEqual(mnem, 'addss') or CaseEqual(mnem, 'subss') or
       CaseEqual(mnem, 'mulss') or CaseEqual(mnem, 'divss') or CaseEqual(mnem, 'cvtss2sd') then
      ssePfx := $F3
    else if CaseEqual(mnem, 'comisd') or CaseEqual(mnem, 'ucomisd') or
            CaseEqual(mnem, 'xorpd') or CaseEqual(mnem, 'pxor') then ssePfx := $66
    else if CaseEqual(mnem, 'xorps') then ssePfx := 0
    else ssePfx := $F2;
    { opcode }
    if CaseEqual(mnem, 'movsd') or CaseEqual(mnem, 'movss') then sseOp := $10
    else if CaseEqual(mnem, 'addsd') or CaseEqual(mnem, 'addss') then sseOp := $58
    else if CaseEqual(mnem, 'subsd') or CaseEqual(mnem, 'subss') then sseOp := $5C
    else if CaseEqual(mnem, 'mulsd') or CaseEqual(mnem, 'mulss') then sseOp := $59
    else if CaseEqual(mnem, 'divsd') or CaseEqual(mnem, 'divss') then sseOp := $5E
    else if CaseEqual(mnem, 'comisd') then sseOp := $2F
    else if CaseEqual(mnem, 'ucomisd') then sseOp := $2E
    else if CaseEqual(mnem, 'cvtsd2ss') or CaseEqual(mnem, 'cvtss2sd') then sseOp := $5A
    else if CaseEqual(mnem, 'pxor') then sseOp := $EF
    else sseOp := $57;   { xorps / xorpd }
    if (k0 = 0) and (k1 = 0) then x64_sse_rr(ssePfx, sseOp, r0, r1, False)
    else if (k0 = 0) and (k1 = 2) then x64_sse_rm(ssePfx, sseOp, r0, mb1, md1, False, False)
    else if (k0 = 2) and (k1 = 0) and (CaseEqual(mnem, 'movsd') or CaseEqual(mnem, 'movss')) then
      x64_sse_rm(ssePfx, $11, r1, mb0, md0, False, False)   { store xmm -> [mem] }
    else Error('EmitAsmX64: unsupported SSE form');
    Exit;
  end;

  { int<->double conversions. cvtsi2sd dest=xmm, src=GP (REX.W if 64-bit src);
    cvttsd2si dest=GP, src=xmm (REX.W if 64-bit dest). }
  if CaseEqual(mnem, 'cvtsi2sd') then
  begin
    if (k0 = 0) and (k1 = 0) then x64_sse_rr($F2, $2A, r0, r1, s1 = 8)
    else if (k0 = 0) and (k1 = 2) then x64_sse_rm($F2, $2A, r0, mb1, md1, s1 = 8, False)
    else Error('EmitAsmX64: unsupported cvtsi2sd form');
    Exit;
  end;
  if CaseEqual(mnem, 'cvttsd2si') then
  begin
    if (k0 = 0) and (k1 = 0) then x64_sse_rr($F2, $2C, r0, r1, s0 = 8)
    else if (k0 = 0) and (k1 = 2) then x64_sse_rm($F2, $2C, r0, mb1, md1, s0 = 8, False)
    else Error('EmitAsmX64: unsupported cvttsd2si form');
    Exit;
  end;

  { movabs reg, imm64 — the explicit 10-byte REX.W B8+r imm64 form. }
  if CaseEqual(mnem, 'movabs') then
  begin
    if k0 <> 0 then Error('EmitAsmX64: movabs expects a register dest');
    if k1 <> 1 then Error('EmitAsmX64: movabs expects an immediate');
    EncPrefixAndREX(8, 0, r0, False);
    EncB($B8 + (r0 and 7));
    EncI64(imm1);
    Exit;
  end;

  if CaseEqual(mnem, 'mov') then
  begin
    if (k0 = 0) and (k1 = 0) then x64_mov_reg_reg(s0, r0, r1)
    else if (k0 = 0) and (k1 = 1) then x64_mov_reg_imm(s0, r0, imm1)
    else if (k0 = 0) and (k1 = 2) then x64_mov_reg_mem(s0, r0, mb1, md1, False)
    else if (k0 = 2) and (k1 = 0) then x64_mov_mem_reg(s1, mb0, md0, r1, False)
    else if (k0 = 2) and (k1 = 1) then
    begin
      if s0 = 0 then Error('EmitAsmX64: mov [mem],imm needs an explicit size (byte/word/dword/qword)');
      x64_mov_mem_imm(s0, mb0, md0, imm1, False);
    end
    { absolute [@glob]/[@data] r/m forms }
    else if ((k0 = 3) or (k0 = 4)) and (k1 = 1) then
    begin
      if s0 = 0 then Error('EmitAsmX64: mov [@..] needs an explicit size');
      EncPrefixAndREX(s0, 0, 0, False);
      if s0 = 1 then EncB($C6) else EncB($C7);
      AsmEncAbsRM(0, k0, md0);
      if s0 = 1 then EncB(Integer(imm1) and $FF)
      else if s0 = 2 then EncI16(imm1) else EncI32(imm1);
    end
    else if ((k0 = 3) or (k0 = 4)) and (k1 = 0) then
    begin
      EncPrefixAndREX(s1, r1, 0, False);
      if s1 = 1 then EncB($88) else EncB($89);
      AsmEncAbsRM(r1, k0, md0);
    end
    else if (k0 = 0) and ((k1 = 3) or (k1 = 4)) then
    begin
      EncPrefixAndREX(s0, r0, 0, False);
      if s0 = 1 then EncB($8A) else EncB($8B);
      AsmEncAbsRM(r0, k1, md1);
    end
    else Error('EmitAsmX64: unsupported mov form');
    Exit;
  end;
  if CaseEqual(mnem, 'lea') then
  begin
    if (k0 = 0) and (k1 = 2) then x64_lea_reg_mem(s0, r0, mb1, md1, False)
    else if (k0 = 0) and ((k1 = 3) or (k1 = 4)) then
    begin
      EncPrefixAndREX(s0, r0, 0, False);
      EncB($8D);
      AsmEncAbsRM(r0, k1, md1);
    end
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
    else if CaseEqual(mnem, 'adc') then EncALUImm(s0, r0, imm1, 2)
    else if CaseEqual(mnem, 'sbb') then EncALUImm(s0, r0, imm1, 3)
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
    else if CaseEqual(mnem, 'adc') then EncALURegReg($11, $13, s0, r0, r1)
    else if CaseEqual(mnem, 'sbb') then EncALURegReg($19, $1B, s0, r0, r1)
    else Error('EmitAsmX64: unsupported reg,reg mnemonic');
    Exit;
  end;

  { ALU reg,[mem] and [mem],reg. opMR = even (m,r) opcode; r,m = opMR+2. }
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
    else begin Error('EmitAsmX64: unsupported reg/mem ALU mnemonic'); i := 0; end;
    if k1 = 2 then x64_alu_reg_mem(i + 2, s0, r0, mb1, md1, False)   { reg,[mem] }
    else x64_alu_mem_reg(i, s1, mb0, md0, r1, False);               { [mem],reg }
    Exit;
  end;

  { ALU reg,[@glob/@data] and [@glob/@data],reg (absolute-address form). }
  if ((k0 = 0) and ((k1 = 3) or (k1 = 4))) or (((k0 = 3) or (k0 = 4)) and (k1 = 0)) then
  begin
    if CaseEqual(mnem, 'add') then i := $01
    else if CaseEqual(mnem, 'or')  then i := $09
    else if CaseEqual(mnem, 'adc') then i := $11
    else if CaseEqual(mnem, 'sbb') then i := $19
    else if CaseEqual(mnem, 'and') then i := $21
    else if CaseEqual(mnem, 'sub') then i := $29
    else if CaseEqual(mnem, 'xor') then i := $31
    else if CaseEqual(mnem, 'cmp') then i := $39
    else begin Error('EmitAsmX64: unsupported reg/abs ALU mnemonic'); i := 0; end;
    if k0 = 0 then
    begin
      EncPrefixAndREX(s0, r0, 0, False);
      EncB(i + 2);
      AsmEncAbsRM(r0, k1, md1);
    end
    else
    begin
      EncPrefixAndREX(s1, r1, 0, False);
      EncB(i);
      AsmEncAbsRM(r1, k0, md0);
    end;
    Exit;
  end;

  { ALU r/m(mem),imm — needs an explicit operand size (e.g. cmp byte [rdx], 0). }
  if (k0 = 2) and (k1 = 1) then
  begin
    if s0 = 0 then Error('EmitAsmX64: memory ALU needs an explicit size (byte/dword/qword)');
    if CaseEqual(mnem, 'add') then i := 0
    else if CaseEqual(mnem, 'or')  then i := 1
    else if CaseEqual(mnem, 'adc') then i := 2
    else if CaseEqual(mnem, 'sbb') then i := 3
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

procedure EmitAsmX64(const items: array of const); overload;
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
      { ordinary instruction: count `%` markers and bind following int holes.
        `@data` / `@glob` also each consume one int (the offset). }
      nHoles := 0;
      for h := 1 to Length(line) do
        if line[h] = '%' then Inc(nHoles);
      for h := 1 to Length(line) - 4 do
        if (line[h] = '@') and
           ((AsmTextSlice(line, h, 5) = '@data') or (AsmTextSlice(line, h, 5) = '@glob')) then
          Inc(nHoles);
      if nHoles > ASM_MAX_HOLES then Error('EmitAsmX64: too many holes in one line');
      for h := 0 to nHoles - 1 do
      begin
        if (i + 1 + h >= n) or (items[i + 1 + h].VType <> vtInteger) and (items[i + 1 + h].VType <> vtInt64) then
          Error('EmitAsmX64: missing integer hole value');
        if items[i + 1 + h].VType = vtInt64 then holes[h] := PHoleI64(items[i + 1 + h].VInt64)^ else holes[h] := items[i + 1 + h].VInteger;
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

{ Single-line convenience overload: EmitAsmX64('ret') / EmitAsmX64('mov rax, %', v)
  needs the bracket form; this covers the no-hole trivial case. }
procedure EmitAsmX64(const s: AnsiString); overload;
begin
  EmitAsmX64([s]);
end;

