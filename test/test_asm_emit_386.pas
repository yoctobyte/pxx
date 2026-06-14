program test_asm_emit_386;
{$mode objfpc}{$H+}

uses SysUtils;

{ Mock environment to satisfy the includes for tests }
var
  Code: array[0..65535] of Byte;
  CodeLen: Integer = 0;
  Fixups: array[0..1023] of record CodePos, DataOff: Integer; end;
  FixCount: Integer = 0;
  GlobFix: array[0..1023] of record CodePos, BSSoff: Integer; end;
  GlobFixCount: Integer = 0;

procedure EmitB(b: Byte);
begin
  Code[CodeLen] := b;
  Inc(CodeLen);
end;

procedure EncB(b: Byte);
begin
  EmitB(b);
end;

procedure EncI16(v: Int64);
begin
  EmitB(v and $FF);
  EmitB((v shr 8) and $FF);
end;

procedure EncI32(v: Int64);
begin
  EmitB(v and $FF);
  EmitB((v shr 8) and $FF);
  EmitB((v shr 16) and $FF);
  EmitB((v shr 24) and $FF);
end;

procedure EncI64(v: Int64);
begin
  EncI32(v and $FFFFFFFF);
  EncI32((v shr 32) and $FFFFFFFF);
end;

procedure Patch32(pos: Integer; v: Int64);
begin
  Code[pos] := v and $FF;
  Code[pos+1] := (v shr 8) and $FF;
  Code[pos+2] := (v shr 16) and $FF;
  Code[pos+3] := (v shr 24) and $FF;
end;

procedure Error(const msg: AnsiString);
begin
  writeln(StdErr, 'ERROR: ', msg);
  Halt(1);
end;

const
  ASM_MAX_HOLES = 8;

{ Mock CaseEqual }
function CaseEqual(const a, b: AnsiString): Boolean;
begin
  Result := LowerCase(a) = LowerCase(b);
end;

function AppendChar(var s: AnsiString; c: Char): Integer;
begin
  s := s + c;
  Result := Length(s);
end;

function AsmTextCStr(p: Pointer): AnsiString;
begin
  if p = nil then Result := '' else Result := PChar(p);
end;

function AsmTextIsSpace(c: Char): Boolean;
begin
  Result := (c = ' ') or (c = #9) or (c = #10) or (c = #13);
end;

function AsmTextCharAt(const s: AnsiString; idx: Integer): Char;
begin
  if (idx < 1) or (idx > Length(s)) then
    Result := #0
  else
    Result := s[idx];
end;

function AsmTextLower(c: Char): Char;
begin
  if (c >= 'A') and (c <= 'Z') then
    Result := Char(Ord(c) + 32)
  else
    Result := c;
end;

function AsmTextSlice(const s: AnsiString; from, len: Integer): AnsiString;
var
  i: Integer;
begin
  Result := '';
  for i := from to from + len - 1 do
    if (i >= 1) and (i <= Length(s)) then
      Result := Result + s[i];
end;

function AsmTextParseInt(const s: AnsiString): Int64;
var
  val: Int64;
  i: Integer;
  neg: Boolean;
begin
  val := 0;
  i := 1;
  neg := False;
  if AsmTextCharAt(s, i) = '-' then
  begin
    neg := True;
    Inc(i);
  end
  else if AsmTextCharAt(s, i) = '+' then
  begin
    Inc(i);
  end;
  
  if (AsmTextCharAt(s, i) = '$') then
  begin
    Inc(i);
    while i <= Length(s) do
    begin
      if (s[i] >= '0') and (s[i] <= '9') then
        val := val * 16 + (Ord(s[i]) - Ord('0'))
      else if (LowerCase(s[i]) >= 'a') and (LowerCase(s[i]) <= 'f') then
        val := val * 16 + (Ord(LowerCase(s[i])) - Ord('a') + 10)
      else
        break;
      Inc(i);
    end;
  end
  else if (AsmTextCharAt(s, i) = '0') and (AsmTextCharAt(s, i+1) = 'x') then
  begin
    i := i + 2;
    while i <= Length(s) do
    begin
      if (s[i] >= '0') and (s[i] <= '9') then
        val := val * 16 + (Ord(s[i]) - Ord('0'))
      else if (LowerCase(s[i]) >= 'a') and (LowerCase(s[i]) <= 'f') then
        val := val * 16 + (Ord(LowerCase(s[i])) - Ord('a') + 10)
      else
        break;
      Inc(i);
    end;
  end
  else
  begin
    while i <= Length(s) do
    begin
      if (s[i] >= '0') and (s[i] <= '9') then
        val := val * 10 + (Ord(s[i]) - Ord('0'))
      else
        break;
      Inc(i);
    end;
  end;
  if neg then val := -val;
  Result := val;
end;

procedure EmitDataRef(dataOff: Integer);
begin
  if FixCount >= 1024 then Error('fixup overflow');
  Fixups[FixCount].CodePos := CodeLen; Fixups[FixCount].DataOff := dataOff;
  Inc(FixCount);
  EncI32(0);
end;

procedure EmitGlobRef(bssOff: Integer);
begin
  if GlobFixCount >= 1024 then Error('global fixup overflow');
  GlobFix[GlobFixCount].CodePos := CodeLen;
  GlobFix[GlobFixCount].BSSoff  := bssOff;
  Inc(GlobFixCount);
  EncI32(0);
end;

{ Mock functions from compiler/asmenc.inc & compiler/x64enc.inc }
function AsmRegNum(const nm: AnsiString; var num, size: Integer): Boolean;
begin
  Result := True;
  if CaseEqual(nm,'eax') then begin num:=0; size:=4; Exit; end;
  if CaseEqual(nm,'ecx') then begin num:=1; size:=4; Exit; end;
  if CaseEqual(nm,'edx') then begin num:=2; size:=4; Exit; end;
  if CaseEqual(nm,'ebx') then begin num:=3; size:=4; Exit; end;
  if CaseEqual(nm,'esp') then begin num:=4; size:=4; Exit; end;
  if CaseEqual(nm,'ebp') then begin num:=5; size:=4; Exit; end;
  if CaseEqual(nm,'esi') then begin num:=6; size:=4; Exit; end;
  if CaseEqual(nm,'edi') then begin num:=7; size:=4; Exit; end;
  if CaseEqual(nm,'ax')  then begin num:=0; size:=2; Exit; end;
  if CaseEqual(nm,'cx')  then begin num:=1; size:=2; Exit; end;
  if CaseEqual(nm,'dx')  then begin num:=2; size:=2; Exit; end;
  if CaseEqual(nm,'bx')  then begin num:=3; size:=2; Exit; end;
  if CaseEqual(nm,'sp')  then begin num:=4; size:=2; Exit; end;
  if CaseEqual(nm,'bp')  then begin num:=5; size:=2; Exit; end;
  if CaseEqual(nm,'si')  then begin num:=6; size:=2; Exit; end;
  if CaseEqual(nm,'di')  then begin num:=7; size:=2; Exit; end;
  if CaseEqual(nm,'al')  then begin num:=0; size:=1; Exit; end;
  if CaseEqual(nm,'cl')  then begin num:=1; size:=1; Exit; end;
  if CaseEqual(nm,'dl')  then begin num:=2; size:=1; Exit; end;
  if CaseEqual(nm,'bl')  then begin num:=3; size:=1; Exit; end;
  Result := False;
end;

procedure EncModRMReg(regField, rmReg: Integer);
begin
  EncB($C0 or ((regField and 7) shl 3) or (rmReg and 7));
end;

procedure EncModRMMem(regField: Integer; baseReg: Integer; disp: Integer; force32: Boolean);
var
  modVal, rmVal, sibVal: Integer;
  needsSIB: Boolean;
begin
  needsSIB := (baseReg and 7) = 4;
  if needsSIB then
  begin
    rmVal := 4;
    sibVal := $24;
  end
  else
  begin
    rmVal := baseReg and 7;
    sibVal := -1;
  end;

  if force32 then
  begin
    modVal := 2;
    EncB((modVal shl 6) or ((regField and 7) shl 3) or rmVal);
    if needsSIB then EncB(sibVal);
    EncI32(disp);
  end
  else
  begin
    if (disp = 0) and ((baseReg and 7) <> 5) then
    begin
      modVal := 0;
      EncB((modVal shl 6) or ((regField and 7) shl 3) or rmVal);
      if needsSIB then EncB(sibVal);
    end
    else if (disp >= -128) and (disp <= 127) then
    begin
      modVal := 1;
      EncB((modVal shl 6) or ((regField and 7) shl 3) or rmVal);
      if needsSIB then EncB(sibVal);
      EncB(disp and $FF);
    end
    else
    begin
      modVal := 2;
      EncB((modVal shl 6) or ((regField and 7) shl 3) or rmVal);
      if needsSIB then EncB(sibVal);
      EncI32(disp);
    end;
  end;
end;

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

function AsmTextSizeKeyword(const w: AnsiString): Integer;
begin
  if CaseEqual(w, 'byte') then Result := 1
  else if CaseEqual(w, 'word') then Result := 2
  else if CaseEqual(w, 'dword') then Result := 4
  else Result := 0;
end;

function AsmTextOperand(const opIn: AnsiString;
  const holes: array of Int64; var holeCur: Integer;
  var regNum, regSize, memBase, memDisp: Integer; var immVal: Int64): Integer;
var op, inner, baseStr, dispStr, firstWord: AnsiString;
    i, n, dummySize, memSize, p: Integer; sign: Integer;
begin
  op := '';
  n := Length(opIn);
  i := 1;
  while (i <= n) and AsmTextIsSpace(AsmTextCharAt(opIn, i)) do Inc(i);
  while (n >= i) and AsmTextIsSpace(AsmTextCharAt(opIn, n)) do Dec(n);
  while i <= n do begin AppendChar(op, opIn[i]); Inc(i); end;

  if Length(op) = 0 then Error('EmitAsmX64: empty operand');

  firstWord := ''; p := 1;
  while (p <= Length(op)) and not AsmTextIsSpace(AsmTextCharAt(op, p)) do
    begin AppendChar(firstWord, AsmTextLower(op[p])); Inc(p); end;
  memSize := AsmTextSizeKeyword(firstWord);
  if memSize > 0 then
  begin
    while (p <= Length(op)) and AsmTextIsSpace(AsmTextCharAt(op, p)) do Inc(p);
    op := AsmTextSlice(op, p, Length(op) - p + 1);
  end;

  if AsmTextCharAt(op, 1) = '[' then
  begin
    inner := '';
    i := 2;
    while (i <= Length(op)) and (AsmTextCharAt(op, i) <> ']') do begin AppendChar(inner, op[i]); Inc(i); end;
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
    while AsmTextIsSpace(AsmTextCharAt(baseStr, Length(baseStr))) do
      baseStr := AsmTextSlice(baseStr, 1, Length(baseStr) - 1);
    if not AsmRegNum(baseStr, memBase, dummySize) then
      Error('EmitAsmX64: bad memory base register');
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
    regSize := memSize;
    Result := 2;
    Exit;
  end;

  if AsmRegNum(op, regNum, regSize) then
  begin
    Result := 0;
    Exit;
  end;

  if AsmTextCharAt(op, 1) = '%' then
  begin
    immVal := holes[holeCur]; Inc(holeCur);
  end
  else
    immVal := AsmTextParseInt(op);
  Result := 1;
end;

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

{ Copy the actual EmitAsm386 implementation from our asmtext.inc }
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
  i := 1;
  while (i <= n) and AsmTextIsSpace(AsmTextCharAt(line, i)) do Inc(i);
  mnem := '';
  while (i <= n) and not AsmTextIsSpace(AsmTextCharAt(line, i)) do begin AppendChar(mnem, AsmTextLower(line[i])); Inc(i); end;
  rest := '';
  while i <= n do begin AppendChar(rest, line[i]); Inc(i); end;
  haveOps := Length(rest) > 0;

  if CaseEqual(mnem, 'ret') then begin EncB($C3); Exit; end;
  if CaseEqual(mnem, 'leave') then begin EncB($C9); Exit; end;
  if CaseEqual(mnem, 'nop') then begin EncB($90); Exit; end;

  if not haveOps then Error('EmitAsm386: unknown 0-operand mnemonic');

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

  op0 := AsmRv32Trim(op0);
  op1 := AsmRv32Trim(op1);

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

  if Length(op1) = 0 then Error('EmitAsm386: instruction needs two operands');

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
    if (k0 = 0) and (k1 = 0) then
    begin
      if s0 = 2 then EncB($66);
      if s0 = 1 then EncB($88) else EncB($89);
      EncModRMReg(r1, r0);
      Exit;
    end;
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
    if (k0 = 0) and (k1 = 2) then
    begin
      if s0 = 2 then EncB($66);
      if s0 = 1 then EncB($8A) else EncB($8B);
      EncModRMMem(r0, mb1, md1, False);
      Exit;
    end;
    if (k0 = 2) and (k1 = 0) then
    begin
      if s1 = 2 then EncB($66);
      if s1 = 1 then EncB($88) else EncB($89);
      EncModRMMem(r1, mb0, md0, False);
      Exit;
    end;
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
    trimmed := AsmRv32Trim(line);

    mnem := ''; j := 1;
    while (j <= Length(trimmed)) and not AsmTextIsSpace(AsmTextCharAt(trimmed, j)) do
      begin AppendChar(mnem, AsmTextLower(trimmed[j])); Inc(j); end;

    isJmp := CaseEqual(mnem, 'jmp');
    if (Length(trimmed) >= 2) and (AsmTextCharAt(trimmed, Length(trimmed)) = ':') then
    begin
      if Asm386LblCount >= ASM_386_MAX_LABELS then Error('EmitAsm386: too many labels');
      Asm386LblName[Asm386LblCount] := AsmTextSlice(trimmed, 1, Length(trimmed) - 1);
      Asm386LblPos[Asm386LblCount] := CodeLen;
      Inc(Asm386LblCount);
      Inc(i);
    end
    else if isJmp or AsmTextJccCode(mnem, cc) then
    begin
      while (j <= Length(trimmed)) and AsmTextIsSpace(AsmTextCharAt(trimmed, j)) do Inc(j);
      target := '';
      while j <= Length(trimmed) do begin AppendChar(target, trimmed[j]); Inc(j); end;

      defined := False; targetPos := 0;
      for k := 0 to Asm386LblCount - 1 do
        if Asm386LblName[k] = target then begin defined := True; targetPos := Asm386LblPos[k]; end;

      if defined then
      begin
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
        if isJmp then EncB($E9) else begin EncB($0F); EncB($80 + cc); end;
        if Asm386FwCount >= ASM_386_MAX_LABELS then Error('EmitAsm386: too many forward jumps');
        Asm386FwName[Asm386FwCount] := target;
        Asm386FwPatch[Asm386FwCount] := CodeLen;
        Inc(Asm386FwCount);
        EncI32(0);
      end;
      Inc(i);
    end
    else
    begin
      nHoles := 0;
      for h := 1 to Length(line) do
        if line[h] = '%' then Inc(nHoles);
      
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

{ Test runner }
procedure AssertBytes(const name: AnsiString; const expected: array of Byte);
var
  i: Integer;
  failed: Boolean;
begin
  failed := False;
  if CodeLen <> Length(expected) then
    failed := True
  else
  begin
    for i := 0 to CodeLen - 1 do
      if Code[i] <> expected[i] then
        failed := True;
  end;
  
  if failed then
  begin
    write('FAIL: ', name, '. Expected ');
    for i := 0 to Length(expected) - 1 do
      write(IntToHex(expected[i], 2), ' ');
    writeln;
    write('Got: ');
    for i := 0 to CodeLen - 1 do
      write(IntToHex(Code[i], 2), ' ');
    writeln;
    Halt(1);
  end
  else
    writeln('PASS: ', name);
end;

procedure ResetCode;
begin
  CodeLen := 0;
  FixCount := 0;
  GlobFixCount := 0;
end;

begin
  { Oracle: echo "mov ebx, eax" | llvm-mc -triple=i386 -show-encoding }
  { Expected: [0x89, 0xc3] }
  ResetCode;
  EmitAsm386('mov ebx, eax');
  AssertBytes('mov ebx, eax', [$89, $C3]);

  { Oracle: echo "mov eax, [ebp - 8]" | llvm-mc -triple=i386 -show-encoding }
  { Expected: [0x8b, 0x45, 0xf8] }
  ResetCode;
  EmitAsm386('mov eax, [ebp - 8]');
  AssertBytes('mov eax, [ebp - 8]', [$8B, $45, $F8]);

  { Oracle: echo "mov eax, [ebp - 512]" | llvm-mc -triple=i386 -show-encoding }
  { Expected: [0x8b, 0x85, 0x00, 0xfe, 0xff, 0xff] }
  ResetCode;
  EmitAsm386('mov eax, [ebp - 512]');
  AssertBytes('mov eax, [ebp - 512]', [$8B, $85, $00, $FE, $FF, $FF]);

  { Oracle: echo "xor edx, edx" | llvm-mc -triple=i386 -show-encoding }
  { Expected: [0x31, 0xd2] }
  ResetCode;
  EmitAsm386('xor edx, edx');
  AssertBytes('xor edx, edx', [$31, $D2]);

  { Oracle: echo "mov ecx, 10" | llvm-mc -triple=i386 -show-encoding }
  { Expected: [0xb9, 0x0a, 0x00, 0x00, 0x00] }
  ResetCode;
  EmitAsm386('mov ecx, 10');
  AssertBytes('mov ecx, 10', [$B9, $0A, $00, $00, $00]);

  { Oracle: echo "div ecx" | llvm-mc -triple=i386 -show-encoding }
  { Expected: [0xf7, 0xf1] }
  ResetCode;
  EmitAsm386('div ecx');
  AssertBytes('div ecx', [$F7, $F1]);

  { Oracle: echo "add dl, 0x30" | llvm-mc -triple=i386 -show-encoding }
  { Expected: [0x80, 0xc2, 0x30] }
  ResetCode;
  EmitAsm386('add dl, 0x30');
  AssertBytes('add dl, 0x30', [$80, $C2, $30]);

  { Oracle: echo "dec edi" | llvm-mc -triple=i386 -show-encoding }
  { Expected: [0x4f] }
  ResetCode;
  EmitAsm386('dec edi');
  AssertBytes('dec edi', [$4F]);

  { Oracle: echo "mov [edi], dl" | llvm-mc -triple=i386 -show-encoding }
  { Expected: [0x88, 0x17] }
  ResetCode;
  EmitAsm386('mov [edi], dl');
  AssertBytes('mov [edi], dl', [$88, $17]);

  { Oracle: echo "or eax, ebx" | llvm-mc -triple=i386 -show-encoding }
  { Expected: [0x09, 0xd8] }
  ResetCode;
  EmitAsm386('or eax, ebx');
  AssertBytes('or eax, ebx', [$09, $D8]);

  { Oracle: echo "int 0x80" | llvm-mc -triple=i386 -show-encoding }
  { Expected: [0xcd, 0x80] }
  ResetCode;
  EmitAsm386('int 0x80');
  AssertBytes('int 0x80', [$CD, $80]);

  { Reloc load tests }
  ResetCode;
  EmitAsm386(['mov edi, @data', 100]);
  AssertBytes('mov edi, @data', [$BF, $00, $00, $00, $00]);
  if (FixCount <> 1) or (Fixups[0].DataOff <> 100) then Error('Data reloc fixup failed');

  ResetCode;
  EmitAsm386(['mov edx, @glob', 200]);
  AssertBytes('mov edx, @glob', [$BA, $00, $00, $00, $00]);
  if (GlobFixCount <> 1) or (GlobFix[0].BSSoff <> 200) then Error('Glob reloc fixup failed');

  { Oracle: echo -e "jmp .done\nnop\n.done:" | llvm-mc -triple=i386 -show-encoding }
  { Expected: [0xe9, 0x01, 0x00, 0x00, 0x00, 0x90] }
  ResetCode;
  EmitAsm386([
    'jmp .done',
    'nop',
    '.done:'
  ]);
  AssertBytes('jmp forward', [$E9, $01, $00, $00, $00, $90]);

  { Oracle: echo -e ".loop:\nnop\njnz .loop" | llvm-mc -triple=i386 -show-encoding }
  { Expected: [0x90, 0x75, 0xfd] }
  ResetCode;
  EmitAsm386([
    '.loop:',
    'nop',
    'jnz .loop'
  ]);
  AssertBytes('jnz backward', [$90, $75, $FD]);

  { Oracle: echo "lea eax, [ebp - 8]" | llvm-mc -triple=i386 -show-encoding }
  { Expected: [0x8d, 0x45, 0xf8] }
  ResetCode;
  EmitAsm386('lea eax, [ebp - 8]');
  AssertBytes('lea eax, [ebp - 8]', [$8D, $45, $F8]);

  writeln('ALL I386 ASM EMIT TESTS PASSED');
end.
