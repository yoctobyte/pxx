{ SPDX-License-Identifier: MPL-2.0 }
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
var b: PAsmTextByte; i, n: Integer;
begin
  Result := '';
  if p = nil then Exit;
  b := PAsmTextByte(p);
  { measure, then ONE SetLength + fill. The old loop AppendChar'd every
    character, i.e. one heap realloc per character of every instruction string
    the codegen emits (139,722 of them on an empty .npy). }
  n := 0;
  while b[n] <> 0 do Inc(n);
  if n = 0 then Exit;
  SetLength(Result, n);
  for i := 0 to n - 1 do
    Result[i + 1] := Chr(b[i]);
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
var i, last, count: Integer;
begin
  { copy s[from .. min(from+len-1, Length(s))] in one SetLength + fill (the old
    char-at-a-time AppendChar reallocated per char). Hot: every mnemonic/operand
    split in the asm-text engine goes through here. }
  last := from + len - 1;
  if last > Length(s) then last := Length(s);
  if last < from then begin Result := ''; Exit; end;
  { the whole string: hand it back rather than copy it. Callers slice
    already-tight strings constantly (the mnemonic of a one-word line, an
    operand that is the whole `rest`), and a copy there is a heap allocation
    bought for nothing. }
  if (from = 1) and (last = Length(s)) then begin Result := s; Exit; end;
  count := last - from + 1;
  SetLength(Result, count);
  for i := 0 to count - 1 do
    Result[i + 1] := s[from + i];
end;

{ Lowercase a single ASCII letter. }
function AsmTextLower(c: Char): Char;
begin
  if (c >= 'A') and (c <= 'Z') then Result := Chr(Ord(c) + 32)
  else Result := c;
end;

{ Does s contain an ASCII uppercase letter? Asked before lowercasing, so the
  common case (already-lowercase mnemonics, which is every literal the codegen
  emits) costs no allocation at all. }
function AsmTextHasUpper(const s: AnsiString): Boolean;
var i: Integer;
begin
  Result := False;
  i := 1;
  while i <= Length(s) do
  begin
    if (s[i] >= 'A') and (s[i] <= 'Z') then begin Result := True; Exit; end;
    Inc(i);
  end;
end;

{ Lowercase a whole string into a FRESH one. Never lowercase in place after an
  AsmTextSlice/AsmTextTrim: those hand the argument straight back when there is
  nothing to cut, so an in-place edit would rewrite the CALLER's string. }
function AsmTextLowerStr(const s: AnsiString): AnsiString;
var i: Integer;
begin
  SetLength(Result, Length(s));
  for i := 1 to Length(s) do Result[i] := AsmTextLower(s[i]);
end;

{ Parse a signed integer literal: decimal, or 0x.. / $.. hex. }
function AsmTextParseInt(const s: AnsiString): Int64;
var i, n: Integer; neg: Boolean; v: Int64; c: Char; d: Integer; hex: Boolean;
begin
  v := 0; neg := False; hex := False;
  n := Length(s);
  { bitwise NOT, `~0x6000`, as GNU as and NASM both take it }
  if (n >= 2) and (AsmTextCharAt(s, 1) = '~') then
  begin
    Result := not AsmTextParseInt(AsmTextSlice(s, 2, n - 1));
    Exit;
  end;
  { a character literal, 'c': its code, as in NASM (`cmp al, '0'`) }
  if (n = 3) and (AsmTextCharAt(s, 1) = '''') and (AsmTextCharAt(s, 3) = '''') then
  begin
    Result := Ord(s[2]);
    Exit;
  end;
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
    else Error('EmitAsmX64: bad integer literal ''' + s + '''');
    if hex then v := v * 16 + d else v := v * 10 + d;
    Inc(i);
  end;
  if neg then v := -v;
  Result := v;
end;

{ Size in bytes of an explicit-size keyword (byte/word/dword/qword), else 0.
  The length+first-letter guard is not decoration: this is asked about EVERY
  operand of every emitted instruction (251,900 times on an empty .npy) and the
  answer is almost always "not a size keyword", which used to cost four
  CaseEqual calls. }
function AsmTextSizeKeyword(const w: AnsiString): Integer;
var c: Char;
begin
  Result := 0;
  if (Length(w) < 4) or (Length(w) > 5) then Exit;
  c := AsmTextLower(w[1]);
  if (c <> 'b') and (c <> 'w') and (c <> 'd') and (c <> 'q') then Exit;
  if CaseEqual(w, 'byte') then Result := 1
  else if CaseEqual(w, 'word') then Result := 2
  else if CaseEqual(w, 'dword') then Result := 4
  else if CaseEqual(w, 'qword') then Result := 8
  else Result := 0;
end;

{ Trim leading/trailing whitespace. Shared by all per-target emitters. }
function AsmTextTrim(const s: AnsiString): AnsiString;
var i, n, k, count: Integer;
begin
  n := Length(s);
  i := 1;
  while (i <= n) and AsmTextIsSpace(AsmTextCharAt(s, i)) do Inc(i);
  while (n >= i) and AsmTextIsSpace(AsmTextCharAt(s, n)) do Dec(n);
  count := n - i + 1;
  if count <= 0 then begin Result := ''; Exit; end;
  { nothing to trim: hand the string back instead of copying it. 725,334 calls
    on an empty .npy, and the overwhelming majority are already tight — an
    operand that AsmTextLine trimmed being trimmed again by AsmTextOperand,
    a one-word line, a `[rax]` inner. }
  if (i = 1) and (n = Length(s)) then begin Result := s; Exit; end;
  { one SetLength + fill instead of per-char AppendChar realloc. }
  SetLength(Result, count);
  for k := 0 to count - 1 do
    Result[k + 1] := s[i + k];
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
  { the MEMORY-operand REX rule: a byte op on [rsi] needs no REX (the register
    rule would force one for "sil", which is not an operand here) }
  EncPrefixAndREXMem(size, ext, baseReg, False);
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

{ Position of a `gs:` / `fs:` segment override in an operand list, 0 if none.
  Only a segment name directly followed by ':' counts, so a register such as
  `fs` never appears in this syntax by accident. }
function AsmTextSegAt(const s: AnsiString): Integer;
var i: Integer; c: Char;
begin
  Result := 0;
  for i := 1 to Length(s) - 2 do
    if (s[i + 2] = ':') and ((s[i + 1] = 's') or (s[i + 1] = 'S')) then
    begin
      c := AsmTextLower(s[i]);
      if (c = 'g') or (c = 'f') then
        if (i = 1) or AsmTextIsSpace(s[i - 1]) or (s[i - 1] = ',') then
        begin
          Result := i;
          Exit;
        end;
    end;
end;

{ Absolute-address r/m: ModRM mod=00 rm=100 + SIB=$25 (no base/index, disp32)
  followed by a 4-byte relocation, or for kind 5 by the plain disp32 -- the
  `gs:[8*k]` thread-block slots address memory this way, relative to the
  segment base and with nothing to relocate. kind 3 = glob (BSS), 4 = data. The r/m form
  the atomic mutex slot and zeroing store use ([@glob]). }
var
  AsmSegTls: Boolean;   { this line's operand carries the TLS segment (gs:) }

procedure AsmEncAbsRM(regField, kind, off: Integer);
begin
  EncB(((regField and 7) shl 3) or 4);
  EncB($25);
  if (kind = 5) and AsmSegTls and TlsSegAbsolute then EmitGlobRef(BSS_TLS_MAIN + off)   { --os=windows: the main block itself }
  else if (kind = 5) and AsmSegTls then EncI32(off + TlsSegDispBias)   { fs - span under --os=openbsd --rtl-libc }
  else if kind = 5 then EncI32(off)
  else if kind = 4 then EmitDataRef(off) else EmitGlobRef(off);
end;

{ SSE xmm <-> absolute memory: [prefix] [REX.R] 0F op ModRM(rm=100) SIB=25
  disp32 -- the absolute form AsmEncAbsRM emits, after the SSE prefix (which
  must precede REX). }
procedure AsmEncSseAbs(prefix, opcode, regField, kind, off: Integer);
begin
  if prefix <> 0 then EncB(prefix);
  if regField >= 8 then EncB($44);
  EncB($0F); EncB(opcode and $FF);
  AsmEncAbsRM(regField, kind, off);
end;

{ A register HOLE: `%r64` / `%r32` / `%r16` / `%r8` / `%xmm` stands for the register
  whose number (0..15, the encoder's numbering) is the next int element. For
  codegen that picks its register at compile time -- `shl %r64, %` with the
  register and the count both bound -- which raw code spelled as arithmetic on
  an opcode byte (`EmitB($E0 + reg)`). Result = the size in bytes, 0 if `op` is
  not a register hole. }
function AsmTextRegHoleSize(const op: AnsiString): Integer;
begin
  Result := 0;
  if (Length(op) < 3) or (AsmTextCharAt(op, 1) <> '%') then Exit;
  if CaseEqual(op, '%xmm') then begin Result := 16; Exit; end;   { an xmm register, 0..15 }
  if AsmTextLower(AsmTextCharAt(op, 2)) <> 'r' then Exit;
  if CaseEqual(op, '%r64') then Result := 8
  else if CaseEqual(op, '%r32') then Result := 4
  else if CaseEqual(op, '%r16') then Result := 2
  else if CaseEqual(op, '%r8') then Result := 1;
end;

{ Classify one operand text. Returns kind via Result: 0=register, 1=immediate,
  2=memory [base+disp], 3=absolute [@glob], 4=absolute [@data], 5=absolute
  numeric [disp32] (kinds >= 3 all encode through AsmEncAbsRM). Fills the
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
  op := AsmTextTrim(opIn);

  if Length(op) = 0 then Error('EmitAsmX64: empty operand');

  { strip a leading explicit-size keyword (byte/word/dword/qword) if present }
  p := 1;
  while (p <= Length(op)) and not AsmTextIsSpace(AsmTextCharAt(op, p)) do Inc(p);
  firstWord := AsmTextSlice(op, 1, p - 1);
  if AsmTextHasUpper(firstWord) then firstWord := AsmTextLowerStr(firstWord);
  memSize := AsmTextSizeKeyword(firstWord);
  if memSize > 0 then
  begin
    while (p <= Length(op)) and AsmTextIsSpace(AsmTextCharAt(op, p)) do Inc(p);
    op := AsmTextSlice(op, p, Length(op) - p + 1);
  end;

  { memory: [ base (+|-) disp ] }
  if AsmTextCharAt(op, 1) = '[' then
  begin
    i := 2;
    while (i <= Length(op)) and (AsmTextCharAt(op, i) <> ']') do Inc(i);
    inner := AsmTextTrim(AsmTextSlice(op, 2, i - 2));

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

    { absolute numeric r/m: [%] / [0x10] -- a bare disp32, kind 5. On its own it
      is an absolute address; behind a `gs:` / `fs:` (AsmTextLine strips the
      segment and emits its prefix) it is an offset into the thread block. }
    if (inner = '%') or
       ((AsmTextCharAt(inner, 1) >= '0') and (AsmTextCharAt(inner, 1) <= '9')) then
    begin
      if AsmTextCharAt(inner, 1) = '%' then
      begin
        memDisp := Integer(holes[holeCur]); Inc(holeCur);
      end
      else
        memDisp := Integer(AsmTextParseInt(inner));
      regSize := memSize;
      Result := 5;
      Exit;
    end;

    { split on + or - }
    dispStr := ''; sign := 1;
    i := 1;
    while (i <= Length(inner)) and (AsmTextCharAt(inner, i) <> '+') and (AsmTextCharAt(inner, i) <> '-') do
      Inc(i);
    baseStr := AsmTextSlice(inner, 1, i - 1);
    if i <= Length(inner) then
    begin
      if AsmTextCharAt(inner, i) = '-' then sign := -1;
      Inc(i);
      dispStr := AsmTextSlice(inner, i, Length(inner) - i + 1);
    end;
    { an INDEX term right after the base: `+ index` or `+ index*scale`, then
      the displacement (if any) as before. Hands the index to EncModRMMem
      through EncMemIndex, which AsmTextLineMemo resets after the line. }
    if (sign = 1) and (Length(dispStr) > 0) then
    begin
      p := 1;
      while (p <= Length(dispStr)) and AsmTextIsSpace(AsmTextCharAt(dispStr, p)) do Inc(p);
      i := p;
      while (i <= Length(dispStr)) and (AsmTextCharAt(dispStr, i) <> '+') and
            (AsmTextCharAt(dispStr, i) <> '-') and (AsmTextCharAt(dispStr, i) <> '*') do Inc(i);
      firstWord := AsmTextTrim(AsmTextSlice(dispStr, p, i - p));
      n := -1;
      if AsmTextRegHoleSize(firstWord) = 8 then
      begin
        n := Integer(holes[holeCur]); Inc(holeCur);
      end
      else if not AsmRegNum(firstWord, n, dummySize) then n := -1;
      if n >= 0 then
      begin
        if (n and 15) = 4 then Error('EmitAsmX64: rsp cannot be an index register');
        EncMemIndex := n;
        EncMemScale := 0;
        if AsmTextCharAt(dispStr, i) = '*' then
        begin
          Inc(i);
          case AsmTextCharAt(dispStr, i) of
            '1': EncMemScale := 0;
            '2': EncMemScale := 1;
            '4': EncMemScale := 2;
            '8': EncMemScale := 3;
          else Error('EmitAsmX64: index scale must be 1, 2, 4 or 8');
          end;
          Inc(i);
          while (i <= Length(dispStr)) and AsmTextIsSpace(AsmTextCharAt(dispStr, i)) do Inc(i);
        end;
        { what follows the index is the displacement, with its own sign }
        if i <= Length(dispStr) then
        begin
          if AsmTextCharAt(dispStr, i) = '-' then sign := -1;
          dispStr := AsmTextSlice(dispStr, i + 1, Length(dispStr) - i);
        end
        else
          dispStr := '';
      end;
    end;
    { trim base }
    while AsmTextIsSpace(AsmTextCharAt(baseStr, Length(baseStr))) do
      baseStr := AsmTextSlice(baseStr, 1, Length(baseStr) - 1);
    if AsmTextRegHoleSize(baseStr) = 8 then
    begin
      memBase := Integer(holes[holeCur]); Inc(holeCur);
    end
    else if not AsmRegNum(baseStr, memBase, dummySize) then
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
      Error('EmitAsmX64: a second index register; write [base+index*scale+disp]')
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
  { register hole }
  dummySize := AsmTextRegHoleSize(op);
  if dummySize > 0 then
  begin
    regNum := Integer(holes[holeCur]); Inc(holeCur);
    if (regNum < 0) or (regNum > 15) then Error('EmitAsmX64: register hole out of range');
    regSize := dummySize;
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
  { EmitAsmX64 asks this about EVERY mnemonic it sees, to decide whether the
    line is a jump at all, and the answer is nearly always no — which used to
    walk all 28 CaseEqual calls below. Every jcc spelling starts with 'j' and is
    2..4 chars, so one character settles it. 3.9M of the compile's 18.6M
    CaseEqual calls came from this function's miss path. }
  Result := False;
  if (Length(m) < 2) or (Length(m) > 4) then Exit;
  if AsmTextLower(m[1]) <> 'j' then Exit;
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
  mStart, mLow: Integer;
  imm0, imm1: Int64;
  haveOps: Boolean;
begin
  holeCur := 0;
  EncMemIndex := -1;
  n := Length(line);
  { skip leading spaces }
  i := 1;
  while (i <= n) and AsmTextIsSpace(AsmTextCharAt(line, i)) do Inc(i);
  { mnemonic — one slice, then lowercase in place (was an AppendChar, i.e. a
    heap realloc, per character) }
  mStart := i;
  while (i <= n) and not AsmTextIsSpace(AsmTextCharAt(line, i)) do Inc(i);
  mnem := AsmTextSlice(line, mStart, i - mStart);
  if AsmTextHasUpper(mnem) then mnem := AsmTextLowerStr(mnem);
  { rest = operands, trimmed once here rather than by each arm below }
  rest := AsmTextTrim(AsmTextSlice(line, i, n - i + 1));
  haveOps := Length(rest) > 0;

  { Segment override, written on the memory operand as `gs:[...]` / `fs:[...]`.
    The prefix byte goes out FIRST -- before any 66/REX the encoder writes --
    and the operand is then parsed without it, so every form that takes memory
    takes a segment for free. One per line; the bytes are what `mov rax,
    gs:[%]` has always been by hand: 65 48 8B 04 25 disp32. }
  AsmSegTls := False;
  if haveOps then
  begin
    k0 := AsmTextSegAt(rest);
    if k0 > 0 then
    begin
      AsmSegTls := AsmTextLower(rest[k0]) = 'g';
      if AsmSegTls then
      begin
        if not TlsSegAbsolute then EncB(TlsSegPrefix);   { gs = the TLS block's segment (fs under --os=openbsd) }
      end
      else EncB($64);
      rest := AsmTextSlice(rest, 1, k0 - 1) + AsmTextSlice(rest, k0 + 3, Length(rest) - k0 - 2);
    end;
  end;

  { The zero-operand forms — reachable ONLY when the line carries no operands,
    so the whole chain is skipped for the ~90% of lines that do. It used to run
    16 CaseEqual calls before every `mov`/`lea`/`cmp` in the program. }
  if not haveOps then
  begin
  if CaseEqual(mnem, 'ret') then begin x64_ret; Exit; end;
  if CaseEqual(mnem, 'leave') then begin x64_leave; Exit; end;
  if CaseEqual(mnem, 'syscall') then begin x64_syscall; Exit; end;
  { The opt-out from --rtl-libc's thunk, for the syscalls whose CONTRACT is the
    machine state at the instruction itself. `syscall` above is free to become a
    `call` into the libc thunk; `syscall_raw` never is, on any target or flag.
    Today's only user is rt_sigreturn, and it is not a style preference: it takes
    no arguments and restores the entire context from a signal frame at a FIXED
    offset from rsp, so the thunk's return address and six register pushes make
    the kernel read the frame from the wrong place -- measured as a SIGSEGV on
    signal delivery where the default build exits 143. Anything else that is
    rsp-relative or must not return belongs here too (clone's child-stack stub
    is already raw for the same reason, in thread_emit.inc). }
  if CaseEqual(mnem, 'syscall_raw') then begin EncB($0F); EncB($05); Exit; end;
  if CaseEqual(mnem, 'nop') then begin EncB($90); Exit; end;
  if CaseEqual(mnem, 'pause') then begin EncB($F3); EncB($90); Exit; end;   { F3 90 — the spin-wait hint: on a real core it throttles the loop and drains the store buffer, and on a hyperthread it yields the pipeline to the sibling. Decodes as NOP on anything that predates it, so it is always safe to emit. }
  if CaseEqual(mnem, 'cqo') then begin EncB($48); EncB($99); Exit; end;
  { CPU feature discovery. These gate any RUNTIME ISA dispatch — a program can
    pick a GP, SSE or AVX kernel only if it can ask what the CPU has — so they
    are worth having before a single vector opcode exists.
    cpuid clobbers eax/ebx/ecx/edx; xgetbv reads XCR<ecx> into edx:eax and is
    what distinguishes "the CPU has AVX" from "the OS saves the YMM state",
    which is the check that actually matters. Kept in step with asmenc.inc's
    copy — same instructions, two encoders (feature-inline-asm-xmm-operands). }
  if CaseEqual(mnem, 'cpuid')  then begin EncB($0F); EncB($A2); Exit; end;
  if CaseEqual(mnem, 'xgetbv') then begin EncB($0F); EncB($01); EncB($D0); Exit; end;
  if CaseEqual(mnem, 'xsetbv') then begin EncB($0F); EncB($01); EncB($D1); Exit; end;
  if CaseEqual(mnem, 'rdtsc')  then begin EncB($0F); EncB($31); Exit; end;
  if CaseEqual(mnem, 'cdq') then begin EncB($99); Exit; end;
  if CaseEqual(mnem, 'cdqe') then begin EncB($48); EncB($98); Exit; end;
  if CaseEqual(mnem, 'movsb') then begin x64_movsb; Exit; end;
  if CaseEqual(mnem, 'cld') then begin EncB($FC); Exit; end;
  if CaseEqual(mnem, 'std') then begin EncB($FD); Exit; end;
  if CaseEqual(mnem, 'stosq') then begin EncB($48); EncB($AB); Exit; end;
  if CaseEqual(mnem, 'movsq') then begin EncB($48); EncB($A5); Exit; end;
  if CaseEqual(mnem, 'stosb') then begin x64_stosb; Exit; end;
  Error('EmitAsmX64: unknown 0-operand mnemonic');
  end;

  { rep prefix: `rep movsb` / `rep stosb` (rest holds the string op) }
  { repe/repz/repne/repnz + a string op: F3 / F2, then the op's own bytes }
  if CaseEqual(mnem, 'repe') or CaseEqual(mnem, 'repz') or
     CaseEqual(mnem, 'repne') or CaseEqual(mnem, 'repnz') then
  begin
    if CaseEqual(mnem, 'repe') or CaseEqual(mnem, 'repz') then EncB($F3) else EncB($F2);
    if CaseEqual(rest, 'cmpsb') then begin EncB($A6); Exit; end;
    if CaseEqual(rest, 'scasb') then begin EncB($AE); Exit; end;
    Error('EmitAsmX64: unsupported repe/repne string op: ' + line);
  end;

  if CaseEqual(mnem, 'rep') then
  begin
    if CaseEqual(rest, 'movsb') then begin x64_rep_movsb; Exit; end;
    if CaseEqual(rest, 'stosb') then begin x64_rep_stosb; Exit; end;
    if CaseEqual(rest, 'stosq') then begin EncB($F3); EncB($48); EncB($AB); Exit; end;
    if CaseEqual(rest, 'movsq') then begin EncB($F3); EncB($48); EncB($A5); Exit; end;
    Error('EmitAsmX64: unsupported rep string op: ' + line);
  end;

  { lock prefix: `lock xchg ...` etc — emit F0, then assemble the rest as a
    fresh line (the recursion re-binds holes from holes[0], and lock takes none). }
  if CaseEqual(mnem, 'lock') then
  begin
    EncB($F0);
    AsmTextLine(rest, holes, nHoles);
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
  { trim so marker/keyword compares (e.g. @data) see no leading space;
    AsmTextOperand also trims, so this is harmless for the operand path. }
  op0 := AsmTextTrim(op0);
  op1 := AsmTextTrim(op1);

  { three-operand imul: `imul dst, src, imm` -- 6B /r ib when the immediate
    fits a signed byte, else 69 /r id. The only three-operand form x86-64
    integer code has, so it is split off here rather than in the general
    two-operand parser. }
  if CaseEqual(mnem, 'imul') then
  begin
    commaPos := 0;
    for i := 1 to Length(op1) do
      if (op1[i] = ',') and (commaPos = 0) then commaPos := i;
    if commaPos > 0 then
    begin
      rest := AsmTextTrim(AsmTextSlice(op1, commaPos + 1, Length(op1) - commaPos));
      op1 := AsmTextTrim(AsmTextSlice(op1, 1, commaPos - 1));
      if AsmTextOperand(op0, holes, holeCur, r0, s0, mb0, md0, imm0) <> 0 then
        Error('EmitAsmX64: imul dst must be a register');
      if AsmTextOperand(op1, holes, holeCur, r1, s1, mb1, md1, imm1) <> 0 then
        Error('EmitAsmX64: three-operand imul takes a register source (this slice)');
      if AsmTextOperand(rest, holes, holeCur, k0, k1, mb0, md0, imm0) <> 1 then
        Error('EmitAsmX64: imul third operand must be an immediate');
      EncPrefixAndREX(s0, r0, r1, False);
      if (imm0 >= -128) and (imm0 <= 127) then
      begin
        EncB($6B); EncModRMReg(r0, r1); EncB(Integer(imm0) and $FF);
      end
      else
      begin
        EncB($69); EncModRMReg(r0, r1); EncI32(imm0);
      end;
      Exit;
    end;
  end;

  { single-operand: push / pop }
  { push/pop r64, [mem] (FF /6, 8F /0) or an absolute [@glob]/[@data]/[num] }
  if CaseEqual(mnem, 'push') or CaseEqual(mnem, 'pop') then
  begin
    k0 := AsmTextOperand(op0, holes, holeCur, r0, s0, mb0, md0, imm0);
    if CaseEqual(mnem, 'push') then
    begin
      if k0 = 0 then x64_push_reg(r0)
      else if k0 = 2 then x64_push_mem(mb0, md0, False)
      else if k0 >= 3 then begin EncB($FF); AsmEncAbsRM(6, k0, md0); end
      else Error('EmitAsmX64: push takes a register or a memory operand: ' + line);
    end
    else
    begin
      if k0 = 0 then x64_pop_reg(r0)
      else if k0 = 2 then x64_pop_mem(mb0, md0, False)
      else if k0 >= 3 then begin EncB($8F); AsmEncAbsRM(0, k0, md0); end
      else Error('EmitAsmX64: pop takes a register or a memory operand: ' + line);
    end;
    Exit;
  end;
  { stmxcsr / ldmxcsr [mem] -- 0F AE /3 and /2; a dword in memory, no REX.W. }
  if CaseEqual(mnem, 'stmxcsr') or CaseEqual(mnem, 'ldmxcsr') then
  begin
    k0 := AsmTextOperand(op0, holes, holeCur, r0, s0, mb0, md0, imm0);
    if (k0 <> 2) or (Length(op1) <> 0) then
      Error('EmitAsmX64: ' + mnem + ' takes one memory operand: ' + line);
    if CaseEqual(mnem, 'stmxcsr') then i := 3 else i := 2;
    EncPrefixAndREXMem(4, i, mb0, False);
    EncB($0F); EncB($AE);
    EncModRMMem(i, mb0, md0, False);
    Exit;
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
    else if k0 >= 3 then
    begin
      if s0 = 0 then Error('EmitAsmX64: inc/dec [@glob]/[@data] needs an explicit size (byte/dword/qword)');
      EncPrefixAndREX(s0, i, 0, False);
      if s0 = 1 then EncB($FE) else EncB($FF);
      AsmEncAbsRM(i, k0, md0);
    end
    else Error('EmitAsmX64: unsupported inc/dec form: ' + line);
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

  { rdrand / rdseed reg: 0F C7 /6 and /7. Kept in step with asmenc.inc's copy —
    same instructions, two encoders. CF is the result: set = the destination
    holds entropy, clear = it does not and the destination is zero.
    feature-a-rdrand-cpuid-compiler-builtins }
  if (Length(op1) = 0) and (CaseEqual(mnem, 'rdrand') or CaseEqual(mnem, 'rdseed')) then
  begin
    if AsmTextOperand(op0, holes, holeCur, r0, s0, mb0, md0, imm0) <> 0 then
      Error('EmitAsmX64: ' + mnem + ' expects a register');
    if CaseEqual(mnem, 'rdrand') then i := 6 else i := 7;
    EncPrefixAndREX(s0, i, r0, False);
    EncB($0F); EncB($C7);
    EncModRMReg(i, r0);
    Exit;
  end;

  { jmp reg / jmp qword [base+disp] (FF /4). Reaches here only for those: the
    driver sends label and @code jumps down its own path. }
  if CaseEqual(mnem, 'jmp') then
  begin
    k0 := AsmTextOperand(op0, holes, holeCur, r0, s0, mb0, md0, imm0);
    if k0 = 0 then x64_jmp_reg(r0)
    else if k0 = 2 then
    begin
      EncPrefixAndREXMem(4, 4, mb0, False);   { no REX.W: FF /4 is 64-bit by default }
      EncB($FF);
      EncModRMMem(4, mb0, md0, False);
    end
    else Error('EmitAsmX64: jmp takes a label, @code, a register or [mem]');
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
    else if PICRefsAreRipRelative then
    begin
      { `lea r64, [rip+disp32]` -- 7 bytes where the mov was 5. The old form
        put the address in a 32-bit IMMEDIATE, and no relocation makes an
        immediate position-independent; it was the last thing keeping
        R_X86_64_32S in .text. The register moves from the opcode's low bits
        into ModRM.reg, so what was REX.B becomes REX.R. }
      if r0 >= 8 then EncB($4C) else EncB($48);      { REX.W (+R) }
      EncB($8D);
      EncB(Byte(((r0 and 7) shl 3) or $05));         { mod=00 reg=r0 rm=101 }
      EmitGlobRef(Integer(imm0));
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
    else if (k0 = 0) and (k1 = 2) then
    begin
      EncPrefixAndREXMem(s0, r0, mb1, False);   { imul r, [mem]: 0F AF /r }
      EncB($0F); EncB($AF);
      EncModRMMem(r0, mb1, md1, False);
    end
    else Error('EmitAsmX64: unsupported imul form: ' + line);
    Exit;
  end;

  { movzx / movsx reg, reg|mem }
  { movsxd r64, r32 / dword [mem]: 63 /r with REX.W. A memory source goes
    through the same prefix+ModRM pair as every other r,[m] form. }
  if CaseEqual(mnem, 'movsxd') then
  begin
    if k0 <> 0 then Error('EmitAsmX64: movsxd dest must be a register: ' + line);
    if k1 = 0 then x64_movx_reg_reg(s0, 4, r0, r1, True)
    else if k1 = 2 then
    begin
      EncPrefixAndREXMem(s0, r0, mb1, False);
      EncB($63);
      EncModRMMem(r0, mb1, md1, False);
    end
    else if k1 >= 3 then
    begin
      EncPrefixAndREX(s0, r0, 0, False);
      EncB($63);
      AsmEncAbsRM(r0, k1, md1);                         { r64, dword [@glob] }
    end
    else Error('EmitAsmX64: unsupported movsxd form: ' + line);
    Exit;
  end;

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
    else if k1 >= 3 then
    begin
      { absolute [@glob]/[@data]: [66|REX] 0F B6/B7 (movzx) or BE/BF (movsx) }
      if (s1 <> 1) and (s1 <> 2) then Error('EmitAsmX64: movzx/movsx mem needs an explicit size (byte/word)');
      EncPrefixAndREX(s0, r0, 0, False);
      EncB($0F);
      if CaseEqual(mnem, 'movsx') then i := $BE else i := $B6;
      if s1 = 2 then Inc(i);
      EncB(i);
      AsmEncAbsRM(r0, k1, md1);
    end
    else Error('EmitAsmX64: unsupported movzx/movsx form: ' + line);
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
    else Error('EmitAsmX64: unsupported test form: ' + line);
    Exit;
  end;

  { xadd / cmpxchg r/m, r -- 0F C1 /r and 0F B1 /r, 32 or 64 bit; the source
    register is the ModRM reg field. Usually behind `lock` for an atomic. }
  if CaseEqual(mnem, 'xadd') or CaseEqual(mnem, 'cmpxchg') then
  begin
    if CaseEqual(mnem, 'xadd') then i := $C1 else i := $B1;
    if (k1 <> 0) or ((s1 <> 4) and (s1 <> 8)) then
      Error('EmitAsmX64: unsupported ' + mnem + ' form: ' + line);
    if k0 = 0 then
    begin
      if s0 <> s1 then Error('EmitAsmX64: ' + mnem + ' operand sizes differ: ' + line);
      EncPrefixAndREX(s1, r1, r0, False);
      EncB($0F); EncB(i);
      EncModRMReg(r1, r0);
    end
    else if k0 = 2 then
    begin
      EncPrefixAndREXMem(s1, r1, mb0, False);
      EncB($0F); EncB(i);
      EncModRMMem(r1, mb0, md0, False);
    end
    else Error('EmitAsmX64: unsupported ' + mnem + ' form: ' + line);
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
    else if (k0 >= 3) and (k1 = 0) then
    begin
      EncPrefixAndREX(s1, r1, 0, False);
      if s1 = 1 then EncB($86) else EncB($87);
      AsmEncAbsRM(r1, k0, md0);
    end
    else if (k0 = 0) and (k1 >= 3) then
    begin
      EncPrefixAndREX(s0, r0, 0, False);
      if s0 = 1 then EncB($86) else EncB($87);
      AsmEncAbsRM(r0, k1, md1);
    end
    else Error('EmitAsmX64: unsupported xchg form: ' + line);
    Exit;
  end;

  { movq — five encodings selected by operand kind (xmm flagged size 16):
    xmm,gp (66 [W] 0F 6E) / gp,xmm (66 [W] 0F 7E) / xmm,xmm (F3 0F 7E) /
    xmm,[mem] (F3 0F 7E) / [mem],xmm (66 0F D6). }
  { movd -- the 32-bit twin of movq's GP<->xmm forms: xmm,r32 (66 0F 6E) and
    r32,xmm (66 0F 7E); no REX.W. The same two opcodes take a memory operand:
    xmm,[mem] loads a dword (upper lanes zeroed), [mem],xmm stores one. }
  if CaseEqual(mnem, 'movd') then
  begin
    if (k0 = 0) and (k1 = 0) and (s0 = 16) and (s1 = 4) then
      x64_sse_rr($66, $6E, r0, r1, False)               { xmm, r32 }
    else if (k0 = 0) and (k1 = 0) and (s0 = 4) and (s1 = 16) then
      x64_sse_rr($66, $7E, r1, r0, False)               { r32, xmm }
    else if (k0 = 0) and (k1 = 2) and (s0 = 16) then
      x64_sse_rm($66, $6E, r0, mb1, md1, False, False)  { xmm, [mem] }
    else if (k0 = 2) and (k1 = 0) and (s1 = 16) then
      x64_sse_rm($66, $7E, r1, mb0, md0, False, False)  { [mem], xmm }
    else Error('EmitAsmX64: unsupported movd form: ' + line);
    Exit;
  end;

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
    else Error('EmitAsmX64: unsupported movq form: ' + line);
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
     CaseEqual(mnem, 'xorps') or CaseEqual(mnem, 'xorpd') or CaseEqual(mnem, 'pxor') or
     CaseEqual(mnem, 'movaps') or CaseEqual(mnem, 'movapd') then
  begin
    { prefix }
    if CaseEqual(mnem, 'movss') or CaseEqual(mnem, 'addss') or CaseEqual(mnem, 'subss') or
       CaseEqual(mnem, 'mulss') or CaseEqual(mnem, 'divss') or CaseEqual(mnem, 'cvtss2sd') then
      ssePfx := $F3
    else if CaseEqual(mnem, 'comisd') or CaseEqual(mnem, 'ucomisd') or
            CaseEqual(mnem, 'xorpd') or CaseEqual(mnem, 'pxor') or
            CaseEqual(mnem, 'movapd') then ssePfx := $66
    else if CaseEqual(mnem, 'xorps') or CaseEqual(mnem, 'movaps') then ssePfx := 0
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
    else if CaseEqual(mnem, 'movaps') or CaseEqual(mnem, 'movapd') then sseOp := $28   { load / reg form; no store form here }
    else sseOp := $57;   { xorps / xorpd }
    if (k0 = 0) and (k1 = 0) then x64_sse_rr(ssePfx, sseOp, r0, r1, False)
    else if (k0 = 0) and (k1 = 2) then x64_sse_rm(ssePfx, sseOp, r0, mb1, md1, False, False)
    else if (k0 = 2) and (k1 = 0) and (CaseEqual(mnem, 'movsd') or CaseEqual(mnem, 'movss')) then
      x64_sse_rm(ssePfx, $11, r1, mb0, md0, False, False)   { store xmm -> [mem] }
    else if (k0 = 0) and (k1 >= 3) then
      AsmEncSseAbs(ssePfx, sseOp, r0, k1, md1)               { xmm, [@glob|@data|num] }
    else if (k0 >= 3) and (k1 = 0) and (CaseEqual(mnem, 'movsd') or CaseEqual(mnem, 'movss')) then
      AsmEncSseAbs(ssePfx, $11, r1, k0, md0)                 { store xmm -> absolute }
    else Error('EmitAsmX64: unsupported SSE form: ' + line);
    Exit;
  end;

  { int<->double conversions. cvtsi2sd dest=xmm, src=GP (REX.W if 64-bit src);
    cvttsd2si dest=GP, src=xmm (REX.W if 64-bit dest). }
  if CaseEqual(mnem, 'cvtsi2sd') then
  begin
    if (k0 = 0) and (k1 = 0) then x64_sse_rr($F2, $2A, r0, r1, s1 = 8)
    else if (k0 = 0) and (k1 = 2) then x64_sse_rm($F2, $2A, r0, mb1, md1, s1 = 8, False)
    else Error('EmitAsmX64: unsupported cvtsi2sd form: ' + line);
    Exit;
  end;
  if CaseEqual(mnem, 'cvttsd2si') then
  begin
    if (k0 = 0) and (k1 = 0) then x64_sse_rr($F2, $2C, r0, r1, s0 = 8)
    else if (k0 = 0) and (k1 = 2) then x64_sse_rm($F2, $2C, r0, mb1, md1, s0 = 8, False)
    else Error('EmitAsmX64: unsupported cvttsd2si form: ' + line);
    Exit;
  end;
  { cvtsd2si is cvttsd2si's ROUNDING sibling ($2D vs $2C) — it honours the
    rounding mode where cvttsd2si always truncates. Both are needed together
    wherever a value is split into an integer part and a rounded fraction. }
  if CaseEqual(mnem, 'cvtsd2si') then
  begin
    if (k0 = 0) and (k1 = 0) then x64_sse_rr($F2, $2D, r0, r1, s0 = 8)
    else if (k0 = 0) and (k1 = 2) then x64_sse_rm($F2, $2D, r0, mb1, md1, s0 = 8, False)
    else Error('EmitAsmX64: unsupported cvtsd2si form: ' + line);
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
    else if (k0 >= 3) and (k1 = 1) then
    begin
      if s0 = 0 then Error('EmitAsmX64: mov [@..] needs an explicit size');
      EncPrefixAndREX(s0, 0, 0, False);
      if s0 = 1 then EncB($C6) else EncB($C7);
      AsmEncAbsRM(0, k0, md0);
      if s0 = 1 then EncB(Integer(imm1) and $FF)
      else if s0 = 2 then EncI16(imm1) else EncI32(imm1);
    end
    else if (k0 >= 3) and (k1 = 0) then
    begin
      EncPrefixAndREX(s1, r1, 0, False);
      if s1 = 1 then EncB($88) else EncB($89);
      AsmEncAbsRM(r1, k0, md0);
    end
    else if (k0 = 0) and (k1 >= 3) then
    begin
      EncPrefixAndREX(s0, r0, 0, False);
      if s0 = 1 then EncB($8A) else EncB($8B);
      AsmEncAbsRM(r0, k1, md1);
    end
    else Error('EmitAsmX64: unsupported mov form: ' + line);
    Exit;
  end;
  if CaseEqual(mnem, 'lea') then
  begin
    if (k0 = 0) and (k1 = 2) then x64_lea_reg_mem(s0, r0, mb1, md1, False)
    else if (k0 = 0) and (k1 >= 3) then
    begin
      EncPrefixAndREX(s0, r0, 0, False);
      EncB($8D);
      AsmEncAbsRM(r0, k1, md1);
    end
    else Error('EmitAsmX64: unsupported lea form: ' + line);
    Exit;
  end;

  { bit test with an immediate bit number: 0F BA /4 bt, /5 bts, /6 btr, /7 btc }
  if (k0 = 0) and (k1 = 1) and (CaseEqual(mnem, 'bt') or CaseEqual(mnem, 'bts') or
     CaseEqual(mnem, 'btr') or CaseEqual(mnem, 'btc')) then
  begin
    if CaseEqual(mnem, 'bt') then i := 4
    else if CaseEqual(mnem, 'bts') then i := 5
    else if CaseEqual(mnem, 'btr') then i := 6
    else i := 7;
    EncPrefixAndREX(s0, 0, r0, False);
    EncB($0F); EncB($BA); EncModRMReg(i, r0); EncB(Integer(imm1) and $FF);
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
    else Error('EmitAsmX64: unsupported reg,imm mnemonic: ' + line);
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
    else Error('EmitAsmX64: unsupported reg,reg mnemonic: ' + line);
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
    else begin Error('EmitAsmX64: unsupported reg/mem ALU mnemonic: ' + line); i := 0; end;
    if k1 = 2 then x64_alu_reg_mem(i + 2, s0, r0, mb1, md1, False)   { reg,[mem] }
    else x64_alu_mem_reg(i, s1, mb0, md0, r1, False);               { [mem],reg }
    Exit;
  end;

  { ALU reg,[@glob/@data] and [@glob/@data],reg (absolute-address form). }
  if ((k0 = 0) and (k1 >= 3)) or ((k0 >= 3) and (k1 = 0)) then
  begin
    if CaseEqual(mnem, 'add') then i := $01
    else if CaseEqual(mnem, 'or')  then i := $09
    else if CaseEqual(mnem, 'adc') then i := $11
    else if CaseEqual(mnem, 'sbb') then i := $19
    else if CaseEqual(mnem, 'and') then i := $21
    else if CaseEqual(mnem, 'sub') then i := $29
    else if CaseEqual(mnem, 'xor') then i := $31
    else if CaseEqual(mnem, 'cmp') then i := $39
    else begin Error('EmitAsmX64: unsupported reg/abs ALU mnemonic: ' + line); i := 0; end;
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
    else begin Error('EmitAsmX64: unsupported mem,imm mnemonic: ' + line); i := 0; end;
    AsmEncAluMemImm(i, s0, mb0, md0, imm1);
    Exit;
  end;

  Error('EmitAsmX64: unsupported instruction: ' + line);
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
  AsmFwShort: array[0..ASM_MAX_LABELS - 1] of Boolean;
  AsmFwCount: Integer;

{$include asmscope.inc}

{ ---- fixed-line encode memo -------------------------------------------------

  The runtime blobs are written as EmitAsmX64(['mov rdi, rax', 'push rcx', ...])
  because that reads far better than a wall of EmitB($48); EmitB($89); ..., and
  standing policy protects that readability. What it costs is that the SAME
  fixed strings are re-lexed by AsmTextLine on every emission, of every program:
  the source text cannot change, yet 'push rax' is tokenised character by
  character at each of its call sites, every compile.

  So the ENCODED BYTES are memoised per line. A hit appends them and never
  enters the assembler at all. This changes WHEN bytes are computed, never
  WHICH bytes -- the acceptance condition of feature-opt-emitasmx64-reparses-
  fixed-strings, and what the self-host fixedpoint checks for free.

  WHICH LINES MAY BE CACHED IS DECIDED BY OBSERVATION, NOT BY A LIST.
  A hand-written "these mnemonics are safe" table would be the same construction
  as IRFirstEvaluated: a mirror of another routine's control flow, correct on the
  day it is written and silently wrong the day the authority changes. That cost
  us bug-a-o3-drops-the-first-of-two-chained-qword-multiply-xor-statements, and
  the fix there was to check the prediction WHERE IT IS USED. Same here: the
  first encode of a line is watched, and the line earns its cache entry only if
  encoding it moved nothing but CodeLen.

  Exactly two things can move, and both are counters we can read:

    FixCount             a relocation was recorded; Fixups[] stores CodeLen, so
                         the bytes are tied to where they were emitted.
    LibcSyscallCallCount --rtl-libc lowered `syscall` to a patched call and
                         recorded the site in LibcSyscallCallPos[]. Replaying
                         cached bytes would emit the call and register nothing,
                         so the thunk would never be patched in.

  Either means "not a pure byte-producing line". Such a line is POISONED and
  takes the slow path forever after. Nothing needs to know in advance which
  lines those are, which is the whole point.

  nHoles = 0 is required for the obvious reason -- a `%` line's bytes vary with
  its argument -- and it covers `@data` / `@glob` too, since EmitAsmX64 counts
  those as holes. The remaining guarantee, that a hole-free line's bytes do not
  depend on CodeLen, holds because AsmTextLine never reads CodeLen; the counter
  watch above is what catches it if that ever stops being true.

  Staging mode (EncToAsmBuffer) is excluded outright: there EncB writes to the
  AsmB buffer rather than Code[], so there is no byte range at Code[CodeLen] to
  capture in the first place. }

const
  ASM_MEMO_SLOTS = 512;        { power of two; ~185 distinct fixed lines today }
  ASM_MEMO_POOL_CAP = 8192;    { bytes of encoded output retained }

var
  AsmMemoKey: array[0..ASM_MEMO_SLOTS - 1] of AnsiString;
  AsmMemoOff: array[0..ASM_MEMO_SLOTS - 1] of Integer;
  AsmMemoLen: array[0..ASM_MEMO_SLOTS - 1] of Integer;   { -1 = poisoned }
  AsmMemoPool: array[0..ASM_MEMO_POOL_CAP - 1] of Byte;
  AsmMemoPoolLen: Integer = 0;
  AsmMemoHits: Int64 = 0;
  AsmMemoMisses: Int64 = 0;
  AsmMemoPoison: Int64 = 0;
  AsmMemoNoRoom: Int64 = 0;

{ Masked at every step so the multiply cannot overflow a 32-bit Integer. }
function AsmMemoHash(const line: AnsiString): Integer;
var h, i: Integer;
begin
  h := 0;
  for i := 1 to Length(line) do
    h := ((h * 33) + Ord(line[i])) and $03FFFFFF;
  AsmMemoHash := h and (ASM_MEMO_SLOTS - 1);
end;

{ Result=True: slot holds this line (a cached entry or a poison marker).
  Result=False with slot >= 0: slot is free, fill it. slot < 0: table full. }
function AsmMemoFind(const line: AnsiString; var slot: Integer): Boolean;
var probes: Integer;
begin
  slot := AsmMemoHash(line);
  probes := 0;
  while probes < ASM_MEMO_SLOTS do
  begin
    if Length(AsmMemoKey[slot]) = 0 then begin AsmMemoFind := False; Exit; end;
    if AsmMemoKey[slot] = line then begin AsmMemoFind := True; Exit; end;
    slot := (slot + 1) and (ASM_MEMO_SLOTS - 1);
    Inc(probes);
  end;
  slot := -1;
  AsmMemoFind := False;
end;

{ The memoising front door to AsmTextLine. Every ordinary instruction line in
  EmitAsmX64 goes through here. }
procedure AsmTextLineMemo(const line: AnsiString; const holes: array of Int64; nHoles: Integer);
var
  slot, i, startLen, f0, s0, n: Integer;
begin
  if EncToAsmBuffer or (nHoles > 0) then
  begin
    AsmTextLine(line, holes, nHoles);
    EncMemIndex := -1;
    Exit;
  end;

  if AsmMemoFind(line, slot) then
  begin
    if AsmMemoLen[slot] >= 0 then
    begin
      for i := 0 to AsmMemoLen[slot] - 1 do
        EmitB(AsmMemoPool[AsmMemoOff[slot] + i]);
      AsmMemoHits := AsmMemoHits + 1;
      Exit;
    end;
    AsmTextLine(line, holes, nHoles);       { poisoned — always the slow path }
    EncMemIndex := -1;
    Exit;
  end;

  { First sighting: encode it for real, watching what else moves. }
  startLen := CodeLen;
  f0 := FixCount;
  s0 := LibcSyscallCallCount;
  AsmTextLine(line, holes, nHoles);
  EncMemIndex := -1;
  AsmMemoMisses := AsmMemoMisses + 1;

  if slot < 0 then begin AsmMemoNoRoom := AsmMemoNoRoom + 1; Exit; end;

  if (FixCount <> f0) or (LibcSyscallCallCount <> s0) then
  begin
    AsmMemoKey[slot] := line;
    AsmMemoLen[slot] := -1;
    AsmMemoOff[slot] := 0;
    AsmMemoPoison := AsmMemoPoison + 1;
    if PxxDbgWants('a.asmmemo', '*') then
      WriteLn('PXXDBG a.asmmemo POISON (emitting it moved a counter): ', line);
    Exit;
  end;

  n := CodeLen - startLen;
  if (n < 0) or (AsmMemoPoolLen + n > ASM_MEMO_POOL_CAP) then
  begin
    AsmMemoNoRoom := AsmMemoNoRoom + 1;
    Exit;
  end;
  for i := 0 to n - 1 do
    AsmMemoPool[AsmMemoPoolLen + i] := Code[startLen + i];
  AsmMemoKey[slot] := line;
  AsmMemoOff[slot] := AsmMemoPoolLen;
  AsmMemoLen[slot] := n;
  AsmMemoPoolLen := AsmMemoPoolLen + n;
end;

{ One line under PXXDBG a.asmmemo, at end of compile. The hit:miss ratio is the
  whole measurement this feature is judged on. }
procedure AsmMemoReport;
begin
  if not PxxDbgWants('a.asmmemo', '*') then Exit;
  WriteLn('PXXDBG a.asmmemo hits=', AsmMemoHits, ' misses=', AsmMemoMisses,
          ' poisoned=', AsmMemoPoison, ' no-room=', AsmMemoNoRoom,
          ' pool=', AsmMemoPoolLen, '/', ASM_MEMO_POOL_CAP);
end;

{ ---- whole-call memo, holes included -------------------------------------

  The fixed-line memo above skips any line with a hole, and the converted
  codegen is almost all holes: `mov rax, [rbp-%]`, `cmp rcx, %`, `shl %r64, %`.
  Each of those re-ran the label/jump classification (a trim and three slices,
  all heap strings) and the full lexer on every emission. On lib_charset.pas
  that was +8.5% of all compiler instructions for the 2026-11-11 batch.

  This memo keys on the line TEXT plus the exact hole VALUES, so the bytes are
  determined by the key. It does not have to predict how a value changes the
  encoding: disp8 vs disp32, imm8 vs imm32, shift-by-1 and a register hole's
  REX bits are all part of the key. Lookup reads the literal in place and
  allocates nothing.

  Admission is by observation, as for the fixed-line memo. On a miss the call
  runs normally, and the result is stored only if it was ONE plain instruction
  (no label, jump or call) and moved no fixup or syscall counter and no scope
  label. Lines containing `@` (relocations) or `syscall` (a policy hook) are
  refused outright as well. }

const
  ASM_CM_SLOTS = 4096;          { power of two }
  ASM_CM_POOL_CAP = 65536;      { encoded bytes retained }

var
  AsmCMKey: array[0..ASM_CM_SLOTS - 1] of AnsiString;
  AsmCMPtr: array[0..ASM_CM_SLOTS - 1] of Pointer;   { the literal's address, or nil for a text key }
  AsmCMProbePtr: Pointer = nil;   { what the last probe keyed on: AsmCallMemoStore records it }
  AsmCMNHoles: array[0..ASM_CM_SLOTS - 1] of Integer;
  AsmCMHoles: array[0..ASM_CM_SLOTS * ASM_MAX_HOLES - 1] of Int64;
  AsmCMOff: array[0..ASM_CM_SLOTS - 1] of Integer;
  AsmCMLen: array[0..ASM_CM_SLOTS - 1] of Integer;
  AsmCMPool: array[0..ASM_CM_POOL_CAP - 1] of Byte;
  AsmCMPoolLen: Integer = 0;
  AsmCMUsed: Integer = 0;
  AsmCMHits: Int64 = 0;
  AsmCMMisses: Int64 = 0;
  AsmPlainLines: Int64 = 0;     { plain instructions encoded by EmitAsmX64 }

{ The hole value of items[k], or False if items[k] is not an integer. }
function AsmCMHoleOf(const items: array of const; k: Integer; var v: Int64): Boolean;
begin
  Result := True;
  if items[k].VType = vtInteger then v := items[k].VInteger
  else if items[k].VType = vtInt64 then v := PHoleI64(items[k].VInt64)^
  else Result := False;
end;

{ Probe for items = [line, hole, hole, ...]. True: the cached bytes were
  appended. False with slot >= 0: a free slot to fill if the call qualifies.
  slot < 0: the call cannot be cached (shape, too many holes, table full). }
function AsmCallMemoProbe(const items: array of const; var slot: Integer): Boolean;
var b, kp: PAsmTextByte; n, nh, k, L, i, probes: Integer; h: Int64; v: Int64; same: Boolean;
begin
  Result := False;
  slot := -1;
  n := Length(items);
  nh := n - 1;
  if (nh > ASM_MAX_HOLES) or (items[0].VAnsiString = nil) then Exit;
  b := PAsmTextByte(items[0].VAnsiString);
  { AN IMMORTAL LITERAL IS KEYED BY ITS ADDRESS. Nearly every call passes the
    line as a string literal, whose block is static: it never moves and is
    never freed, so the same address is the same text for the whole compile.
    Hashing and comparing it byte by byte cost ~1,000 instructions a call
    (measured 2026-11-11, lib_charset: 60 M in this function for 58,867
    calls, two per-character loops). The refcount floor test is the one
    PyAttrLkStaticH uses (PXX_STATIC_RC_FLOOR read at half). A heap string can
    reuse an address for other text, so it keeps the text key. An FPC-built
    compiler stores -1 there, which is below the floor, so it simply takes the
    text path. }
  AsmCMProbePtr := nil;
  if PInt64(NativeInt(Pointer(b)) - 16)^ >= $20000000 then
    AsmCMProbePtr := Pointer(b);
  if AsmCMProbePtr <> nil then
  begin
    h := (NativeInt(Pointer(b)) shr 3) and $0FFFFFFF;
    L := -1;
  end
  else
  begin
    h := 5381;
    L := 0;
    while b[L] <> 0 do
    begin
      h := ((h * 33) + b[L]) and $0FFFFFFF;
      Inc(L);
    end;
  end;
  for k := 1 to nh do
  begin
    if not AsmCMHoleOf(items, k, v) then Exit;
    h := ((h * 31) + (v and $FFFFFF) + (v shr 40)) and $0FFFFFFF;
  end;
  slot := Integer(h and (ASM_CM_SLOTS - 1));
  probes := 0;
  while probes < 8 do
  begin
    if Length(AsmCMKey[slot]) = 0 then Exit;      { free: caller may fill it }
    if AsmCMNHoles[slot] = nh then
    begin
      if AsmCMProbePtr <> nil then
        same := AsmCMPtr[slot] = AsmCMProbePtr
      else
      begin
        same := Length(AsmCMKey[slot]) = L;
        kp := PAsmTextByte(Pointer(AsmCMKey[slot]));
        i := 0;
        while same and (i < L) do
        begin
          if kp[i] <> b[i] then same := False;
          Inc(i);
        end;
      end;
      k := 1;
      while same and (k <= nh) do
      begin
        AsmCMHoleOf(items, k, v);
        if AsmCMHoles[slot * ASM_MAX_HOLES + k - 1] <> v then same := False;
        Inc(k);
      end;
      if same then
      begin
        for i := 0 to AsmCMLen[slot] - 1 do
          EmitB(AsmCMPool[AsmCMOff[slot] + i]);
        EncMemIndex := -1;
        AsmCMHits := AsmCMHits + 1;
        Result := True;
        Exit;
      end;
    end;
    slot := (slot + 1) and (ASM_CM_SLOTS - 1);
    Inc(probes);
  end;
  slot := -1;                                       { cluster full: no caching }
end;

{ One line under PXXDBG a.asmmemo: whole-call memo hit/miss at end of compile. }
procedure AsmCallMemoReport;
begin
  if not PxxDbgWants('a.asmmemo', '*') then Exit;
  WriteLn('PXXDBG a.asmmemo call-memo hits=', AsmCMHits, ' stored=', AsmCMMisses,
          ' slots=', AsmCMUsed, '/', ASM_CM_SLOTS, ' pool=', AsmCMPoolLen, '/', ASM_CM_POOL_CAP);
end;

procedure AsmCallMemoStore(slot: Integer; const line: AnsiString;
  const holes: array of Int64; nh, startLen: Integer; litPtr: Pointer);
var i, n: Integer;
begin
  n := CodeLen - startLen;
  if (n <= 0) or (AsmCMPoolLen + n > ASM_CM_POOL_CAP) then Exit;
  if (AsmCMUsed * 4 >= ASM_CM_SLOTS * 3) then Exit;  { keep probe chains short }
  if (Pos('@', line) > 0) or (Pos('syscall', line) > 0) then Exit;
  for i := 0 to n - 1 do
    AsmCMPool[AsmCMPoolLen + i] := Code[startLen + i];
  for i := 0 to nh - 1 do
    AsmCMHoles[slot * ASM_MAX_HOLES + i] := holes[i];
  AsmCMKey[slot] := line;
  AsmCMPtr[slot] := litPtr;   { the probe's own key, carried by the caller }
  AsmCMNHoles[slot] := nh;
  AsmCMOff[slot] := AsmCMPoolLen;
  AsmCMLen[slot] := n;
  AsmCMPoolLen := AsmCMPoolLen + n;
  Inc(AsmCMUsed);
  AsmCMMisses := AsmCMMisses + 1;
end;

procedure EmitAsmX64(const items: array of const); overload;
var
  i, n, h, nHoles, j: Integer;
  line, trimmed, mnem, target: AnsiString;
  holes: array[0..ASM_MAX_HOLES - 1] of Int64;
  cc, k, targetPos, disp, width: Integer;
  isJmp, isCall, defined, scoped: Boolean;
  cmSlot, cmLen0, cmF, cmG, cmC, cmP, cmS, cmSl: Integer;
  cmPtr: Pointer;
  cmPlain: Int64;
begin
  AsmLblCount := 0; AsmFwCount := 0;
  n := Length(items);
  cmSlot := -1;
  if (not EncToAsmBuffer) and (n >= 1) and (items[0].VType = vtAnsiString) then
    if AsmCallMemoProbe(items, cmSlot) then Exit;
  cmPtr := AsmCMProbePtr;   { this call's key; a nested emit may probe again }
  cmLen0 := CodeLen; cmF := FixCount; cmG := GlobFixCount; cmC := CallFixCount;
  cmP := ProcAddrFixCount; cmS := LibcSyscallCallCount;
  cmSl := AsmSLblCount; cmPlain := AsmPlainLines;
  i := 0;
  while i < n do
  begin
    if items[i].VType <> vtAnsiString then
      Error('EmitAsmX64: expected an instruction string');
    line := AsmTextCStr(items[i].VAnsiString);

    { trim for label/jump classification — AsmTextTrim is exactly the
      skip-leading / copy / strip-trailing the three loops here used to spell by
      hand, and it is one SetLength+fill instead of an AppendChar per char. }
    trimmed := AsmTextTrim(line);

    { first word = mnemonic }
    j := 1;
    while (j <= Length(trimmed)) and not AsmTextIsSpace(AsmTextCharAt(trimmed, j)) do Inc(j);
    mnem := AsmTextSlice(trimmed, 1, j - 1);
    if AsmTextHasUpper(mnem) then mnem := AsmTextLowerStr(mnem);

    isJmp := CaseEqual(mnem, 'jmp');
    { the operand text, for the jump/call classification below }
    while (j <= Length(trimmed)) and AsmTextIsSpace(AsmTextCharAt(trimmed, j)) do Inc(j);
    target := AsmTextSlice(trimmed, j, Length(trimmed) - j + 1);
    isCall := CaseEqual(mnem, 'call') and CaseEqual(target, '@code');
    { an INDIRECT jmp (register, register hole or memory) is an ordinary
      instruction, encoded by AsmTextLine }
    if isJmp then
      if (AsmTextCharAt(target, 1) = '[') or (AsmTextCharAt(target, 1) = '%') or
         (AsmTextSizeKeyword(AsmTextSlice(target, 1, 5)) > 0) or AsmRegNum(target, k, disp) then
        isJmp := False;
    if (Length(trimmed) >= 2) and (AsmTextCharAt(trimmed, Length(trimmed)) = ':') then
    begin
      { label definition: `name:` (a bare line ending in ':') }
      target := AsmTextSlice(trimmed, 1, Length(trimmed) - 1);
      if AsmIsScopeLabel(target) then
      begin
        if AsmScopeFind(target, disp) then
          Error('EmitAsmX64: scope label defined twice: ' + target);
        if AsmSLblCount >= ASM_SCOPE_MAX_LABELS then Error('EmitAsmX64: too many scope labels');
        AsmSLblName[AsmSLblCount] := target;
        AsmSLblPos[AsmSLblCount] := CodeLen;
        Inc(AsmSLblCount);
      end
      else
      begin
        if AsmLblCount >= ASM_MAX_LABELS then Error('EmitAsmX64: too many labels');
        AsmLblName[AsmLblCount] := target;
        AsmLblPos[AsmLblCount] := CodeLen;
        Inc(AsmLblCount);
      end;
      Inc(i);
    end
    else if isJmp or isCall or AsmTextJccCode(mnem, cc) then
    begin
      { operand = label name, or a constant byte displacement (`jnz +5`,
        `jmp -3`): bytes to skip relative to the END of the (short-form)
        instruction — i.e. the raw rel8 field. For hops over emission the
        assembler cannot see (an EmitCallProc between two EmitAsmX64 calls,
        whose labels are per-call). Short range only (+-127). }
      { `short` / `near` force the rel8 / rel32 form, as in NASM. Without one a
        known (backward) target takes rel8 when it reaches and a forward one
        takes rel32. Raw-byte code that is converted line for line needs both:
        a hand-written `EB 00` forward placeholder is a short forward jump, and
        a hand-written `E9 rel32` back edge stays rel32 so the bytes match. }
      width := 0;
      if (Length(target) > 6) and CaseEqual(AsmTextSlice(target, 1, 6), 'short ') then
      begin
        width := 1; target := AsmTextTrim(AsmTextSlice(target, 7, Length(target) - 6));
      end
      else if (Length(target) > 5) and CaseEqual(AsmTextSlice(target, 1, 5), 'near ') then
      begin
        width := 2; target := AsmTextTrim(AsmTextSlice(target, 6, Length(target) - 5));
      end;

      { `jmp @code` / `jcc @code` / `call @code`: a known code position, taken
        from the next int element -- a routine emitted earlier (ExcLongJmpAddr,
        a loop head saved in a Pascal variable). Always rel32 unless `short`. }
      if CaseEqual(target, '@code') then
      begin
        if i + 1 >= n then Error('EmitAsmX64: @code needs an integer code position');
        if items[i + 1].VType <> vtInteger then
          Error('EmitAsmX64: @code needs an integer code position');
        targetPos := items[i + 1].VInteger;
        if width = 1 then
        begin
          if isCall then Error('EmitAsmX64: there is no short call');
          if isJmp then EncB($EB) else EncB($70 + cc);
          disp := targetPos - (CodeLen + 1);
          CheckRel8(disp, 'asm short jump to @code');
          EncB(disp and $FF);
        end
        else
        begin
          if isCall then EncB($E8)
          else if isJmp then EncB($E9)
          else begin EncB($0F); EncB($80 + cc); end;
          EncI32(targetPos - (CodeLen + 4));
        end;
        i := i + 2;
        continue;
      end;
      if isCall then Error('EmitAsmX64: call takes a register or @code');

      if (Length(target) >= 1) and
         ((target[1] = '+') or (target[1] = '-') or
          ((target[1] >= '0') and (target[1] <= '9'))) then
      begin
        disp := 0; k := 1;
        if (target[1] = '+') or (target[1] = '-') then k := 2;
        if k > Length(target) then Error('EmitAsmX64: bad constant jump displacement');
        while k <= Length(target) do
        begin
          if (target[k] < '0') or (target[k] > '9') then
            Error('EmitAsmX64: bad constant jump displacement');
          disp := disp * 10 + (Ord(target[k]) - Ord('0'));
          Inc(k);
        end;
        if target[1] = '-' then disp := -disp;
        if (disp < -128) or (disp > 127) then
          Error('EmitAsmX64: constant jump displacement out of rel8 range');
        if isJmp then EncB($EB) else EncB($70 + cc);
        EncB(disp and $FF);
        Inc(i);
        continue;
      end;

      defined := False; targetPos := 0;
      scoped := AsmIsScopeLabel(target);
      if scoped then
        defined := AsmScopeFind(target, targetPos)
      else
        for k := 0 to AsmLblCount - 1 do
          if AsmLblName[k] = target then begin defined := True; targetPos := AsmLblPos[k]; end;

      if defined then
      begin
        { backward (or same-call known) target: short form if it reaches. }
        disp := targetPos - (CodeLen + 2);
        if width = 1 then CheckRel8(disp, 'asm short back jump');
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
        { forward target: the near (rel32) form, or rel8 under `short`, and a
          patch recorded in the call's table or the open scope's. }
        if width = 1 then
        begin
          if isJmp then EncB($EB) else EncB($70 + cc);
        end
        else if isJmp then EncB($E9) else begin EncB($0F); EncB($80 + cc); end;
        if scoped then
        begin
          if AsmSFwCount >= ASM_SCOPE_MAX_LABELS then Error('EmitAsmX64: too many scope forward jumps');
          AsmSFwName[AsmSFwCount] := target;
          AsmSFwPatch[AsmSFwCount] := CodeLen;
          AsmSFwShort[AsmSFwCount] := width = 1;
          Inc(AsmSFwCount);
        end
        else
        begin
          if AsmFwCount >= ASM_MAX_LABELS then Error('EmitAsmX64: too many forward jumps');
          AsmFwName[AsmFwCount] := target;
          AsmFwPatch[AsmFwCount] := CodeLen;   { position of the displacement }
          AsmFwShort[AsmFwCount] := width = 1;
          Inc(AsmFwCount);
        end;
        if width = 1 then EncB(0) else EncI32(0);
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
      AsmTextLineMemo(line, holes, nHoles);
      AsmPlainLines := AsmPlainLines + 1;
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
    AsmPatchFw(AsmFwPatch[k], targetPos, AsmFwShort[k]);
  end;

  { admit the call to the whole-call memo only if it was exactly one plain
    instruction that moved nothing but CodeLen }
  if (cmSlot >= 0) and (AsmPlainLines = cmPlain + 1) and (n = 1 + nHoles) and
     (AsmFwCount = 0) and (AsmLblCount = 0) and (AsmSLblCount = cmSl) and
     (FixCount = cmF) and (GlobFixCount = cmG) and (CallFixCount = cmC) and
     (ProcAddrFixCount = cmP) and
     (LibcSyscallCallCount = cmS) and not EncToAsmBuffer then
    AsmCallMemoStore(cmSlot, line, holes, nHoles, cmLen0, cmPtr);
end;

{ Single-line convenience overload: EmitAsmX64('ret') / EmitAsmX64('mov rax, %', v)
  needs the bracket form; this covers the no-hole trivial case. }
procedure EmitAsmX64(const s: AnsiString); overload;
begin
  EmitAsmX64([s]);
end;

