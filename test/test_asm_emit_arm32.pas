program test_asm_emit_arm32;
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
  TargetArch: Integer = 3; { TARGET_ARM32 }

procedure EmitB(b: Byte);
begin
  Code[CodeLen] := b;
  Inc(CodeLen);
end;

procedure EmitI32(v: Int64);
begin
  Code[CodeLen] := v and $FF;
  Code[CodeLen+1] := (v shr 8) and $FF;
  Code[CodeLen+2] := (v shr 16) and $FF;
  Code[CodeLen+3] := (v shr 24) and $FF;
  CodeLen := CodeLen + 4;
end;

procedure EmitI64(v: Int64);
begin
  EmitI32(v and $FFFFFFFF);
  EmitI32((v shr 32) and $FFFFFFFF);
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

{ Mock some symbols / types }
type
  TTypeKind = Integer;
const
  tyString = 6;
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

{ Inline helpers normally in compiler/asmtext.inc }
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

{ Mock functions from asmtext.inc for trimmed/reg/int }
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

function AsmRv32IsLabel(const s: AnsiString): Boolean;
var c: Char;
begin
  c := AsmTextCharAt(s, 1);
  Result := (c <> '%') and (c <> '-') and ((c < '0') or (c > '9'));
end;

procedure EmitDataRef(dataOff: Integer);
begin
  if FixCount >= 1024 then Error('fixup overflow');
  Fixups[FixCount].CodePos := CodeLen; Fixups[FixCount].DataOff := dataOff;
  Inc(FixCount);
  EmitI32(0);
end;

procedure EmitGlobRef(bssOff: Integer);
begin
  if GlobFixCount >= 1024 then Error('global fixup overflow');
  GlobFix[GlobFixCount].CodePos := CodeLen;
  GlobFix[GlobFixCount].BSSoff  := bssOff;
  Inc(GlobFixCount);
  EmitI32(0);
end;

{ Include the target encoders and text assemblers }
{$include ../compiler/asmtext_arm32.inc}

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
  { --- Arithmetic & Logical --- }
  ResetCode;
  EmitAsmArm32('add r0, r0, r1');
  AssertBytes('add r0, r0, r1', [$01, $00, $80, $E0]);

  ResetCode;
  EmitAsmArm32('add r0, fp, r0');
  AssertBytes('add r0, fp, r0', [$00, $00, $8B, $E0]);

  ResetCode;
  EmitAsmArm32('sub r1, r2, #100');
  AssertBytes('sub r1, r2, #100', [$64, $10, $42, $E2]);

  ResetCode;
  EmitAsmArm32('orr r4, r5, r6');
  AssertBytes('orr r4, r5, r6', [$06, $40, $85, $E1]);

  ResetCode;
  EmitAsmArm32('cmp r0, #0');
  AssertBytes('cmp r0, #0', [$00, $00, $50, $E3]);

  ResetCode;
  EmitAsmArm32('cmp r1, r2');
  AssertBytes('cmp r1, r2', [$02, $00, $51, $E1]);

  { --- Moves --- }
  ResetCode;
  EmitAsmArm32('mov r0, #0');
  AssertBytes('mov r0, #0', [$00, $00, $A0, $E3]);

  ResetCode;
  EmitAsmArm32('moveq r4, #1');
  AssertBytes('moveq r4, #1', [$01, $40, $A0, $03]);

  { --- Loads and Stores --- }
  ResetCode;
  EmitAsmArm32('ldr r0, [r1]');
  AssertBytes('ldr r0, [r1]', [$00, $00, $91, $E5]);

  ResetCode;
  EmitAsmArm32('strb r0, [r1]');
  AssertBytes('strb r0, [r1]', [$00, $00, $C1, $E5]);

  ResetCode;
  EmitAsmArm32('ldr r2, [sp, #12]');
  AssertBytes('ldr r2, [sp, #12]', [$0C, $20, $9D, $E5]);

  ResetCode;
  EmitAsmArm32('ldrh r0, [r1, #8]');
  AssertBytes('ldrh r0, [r1, #8]', [$B8, $00, $D1, $E1]);

  ResetCode;
  EmitAsmArm32('ldrsb r2, [r3, #-16]');
  AssertBytes('ldrsb r2, [r3, #-16]', [$D0, $21, $53, $E1]);

  { --- Branches --- }
  ResetCode;
  EmitAsmArm32('bx lr');
  AssertBytes('bx lr', [$1E, $FF, $2F, $E1]);

  ResetCode;
  EmitAsmArm32(['beq %', 8]);
  AssertBytes('beq %', [$00, $00, $00, $0A]);

  ResetCode;
  EmitAsmArm32(['bne %', -8]);
  AssertBytes('bne %', [$FC, $FF, $FF, $1A]);

  { --- Labels --- }
  ResetCode;
  EmitAsmArm32([
    'b .done',
    'nop',
    '.done:'
  ]);
  AssertBytes('b forward', [$00, $00, $00, $EA, $00, $F0, $20, $E3]);

  writeln('ALL ARM32 ASM EMIT TESTS PASSED');
end.
