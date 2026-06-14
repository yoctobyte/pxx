program test_asm_emit_rv32;
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
  TargetArch: Integer = 5; { TARGET_RISCV32 }

procedure EmitB(b: Byte);
begin
  Code[CodeLen] := b;
  Inc(CodeLen);
end;

procedure EmitI32(v: Int64);
begin
  EmitB(v and $FF);
  EmitB((v shr 8) and $FF);
  EmitB((v shr 16) and $FF);
  EmitB((v shr 24) and $FF);
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

// Simple implementation for testing hex/dec formats
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
{$include ../compiler/rv32enc.inc}
{$include ../compiler/asmtext_rv32.inc}

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
  { --- R-type instructions --- }
  { Oracle: echo "add a0, a1, a2" | llvm-mc -triple=riscv32 -show-encoding }
  { Expected bytes: [33, 85, c5, 00] }
  ResetCode;
  EmitAsmRv32('add a0, a1, a2');
  AssertBytes('add a0, a1, a2', [$33, $85, $c5, $00]);

  { Oracle: echo "sub a0, a1, a2" | llvm-mc -triple=riscv32 -show-encoding }
  { Expected bytes: [33, 85, c5, 40] }
  ResetCode;
  EmitAsmRv32('sub a0, a1, a2');
  AssertBytes('sub a0, a1, a2', [$33, $85, $c5, $40]);

  { Oracle: echo "mul a0, a1, a2" | llvm-mc -triple=riscv32 -show-encoding }
  { Expected bytes: [33, 85, c5, 02] }
  ResetCode;
  EmitAsmRv32('mul a0, a1, a2');
  AssertBytes('mul a0, a1, a2', [$33, $85, $c5, $02]);

  { --- I-type instructions --- }
  { Oracle: echo "addi a0, a1, 100" | llvm-mc -triple=riscv32 -show-encoding }
  { Expected bytes: [13, 85, 45, 06] }
  ResetCode;
  EmitAsmRv32('addi a0, a1, 100');
  AssertBytes('addi a0, a1, 100', [$13, $85, $45, $06]);

  { Oracle: echo "andi a0, a1, -10" | llvm-mc -triple=riscv32 -show-encoding }
  { Expected bytes: [13, f5, 65, ff] }
  ResetCode;
  EmitAsmRv32('andi a0, a1, -10');
  AssertBytes('andi a0, a1, -10', [$13, $f5, $65, $ff]);

  { --- Load / Store instructions --- }
  { Oracle: echo "lw a0, 8(sp)" | llvm-mc -triple=riscv32 -show-encoding }
  { Expected bytes: [03, 25, 81, 00] }
  ResetCode;
  EmitAsmRv32('lw a0, 8(sp)');
  AssertBytes('lw a0, 8(sp)', [$03, $25, $81, $00]);

  { Oracle: echo "sw a0, -16(sp)" | llvm-mc -triple=riscv32 -show-encoding }
  { Expected bytes: [23, 28, a1, fe] }
  ResetCode;
  EmitAsmRv32('sw a0, -16(sp)');
  AssertBytes('sw a0, -16(sp)', [$23, $28, $a1, $fe]);

  { --- U-type instructions --- }
  { Oracle: echo "lui a0, 0x12" | llvm-mc -triple=riscv32 -show-encoding }
  { Expected bytes: [37, 25, 01, 00] }
  ResetCode;
  EmitAsmRv32('lui a0, 0x12');
  AssertBytes('lui a0, 0x12', [$37, $25, $01, $00]);

  { --- Jumps and Branches (including labels and fixups) --- }
  { Oracle: echo "jal zero, 8" | llvm-mc -triple=riscv32 -show-encoding }
  { Expected bytes: [6f, 00, 80, 00] }
  ResetCode;
  EmitAsmRv32('jal zero, 8');
  AssertBytes('jal zero, 8', [$6f, $00, $80, $00]);

  { Oracle: echo -e "jal zero, .done\nnop\n.done:" | llvm-mc -triple=riscv32 -show-encoding }
  { Expected bytes: [6f, 00, 80, 00, 13, 00, 00, 00] }
  ResetCode;
  EmitAsmRv32([
    'jal zero, .done',
    'nop',
    '.done:'
  ]);
  AssertBytes('jal forward', [$6f, $00, $80, $00, $13, $00, $00, $00]);

  { Oracle: echo -e ".loop:\nnop\nbeq a0, zero, .loop" | llvm-mc -triple=riscv32 -show-encoding }
  { Expected bytes: [13, 00, 00, 00, e3, 0e, 05, fe] }
  ResetCode;
  EmitAsmRv32([
    '.loop:',
    'nop',
    'beq a0, zero, .loop'
  ]);
  AssertBytes('beq backward', [$13, $00, $00, $00, $e3, $0e, $05, $fe]);

  writeln('ALL RISC-V ASM EMIT TESTS PASSED');
end.
