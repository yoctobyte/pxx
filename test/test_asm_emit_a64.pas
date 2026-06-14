program test_asm_emit_a64;
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
  TargetArch: Integer = 3; { TARGET_AARCH64 }

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

function AsmTextIsLabel(const s: AnsiString): Boolean;
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
  EmitI32(0); { 8-byte reloc value on AArch64 }
end;

procedure EmitGlobRef(bssOff: Integer);
begin
  if GlobFixCount >= 1024 then Error('global fixup overflow');
  GlobFix[GlobFixCount].CodePos := CodeLen;
  GlobFix[GlobFixCount].BSSoff  := bssOff;
  Inc(GlobFixCount);
  EmitI32(0); { 4-byte reloc value }
end;

{ Include the target encoders and text assemblers }
{$include ../compiler/asmtext_a64.inc}

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
  { --- Arithmetic --- }
  { Oracle: echo "add x0, x1, x2" | llvm-mc -triple=aarch64 -show-encoding }
  ResetCode;
  EmitAsmA64('add x0, x1, x2');
  AssertBytes('add x0, x1, x2', [$20, $00, $02, $8B]);

  { Oracle: echo "add x0, x1, #100" | llvm-mc -triple=aarch64 -show-encoding }
  ResetCode;
  EmitAsmA64('add x0, x1, #100');
  AssertBytes('add x0, x1, #100', [$20, $90, $01, $91]);

  { --- Logical --- }
  { Oracle: echo "eor x0, x0, #1" | llvm-mc -triple=aarch64 -show-encoding }
  ResetCode;
  EmitAsmA64('eor x0, x0, #1');
  AssertBytes('eor x0, x0, #1', [$00, $00, $40, $D2]);

  { Oracle: echo "and x0, x0, x1" | llvm-mc -triple=aarch64 -show-encoding }
  ResetCode;
  EmitAsmA64('and x0, x0, x1');
  AssertBytes('and x0, x0, x1', [$00, $00, $01, $8A]);

  { --- Move --- }
  { Oracle: echo "mov x0, x1" | llvm-mc -triple=aarch64 -show-encoding }
  ResetCode;
  EmitAsmA64('mov x0, x1');
  AssertBytes('mov x0, x1', [$E0, $03, $01, $AA]);

  { Oracle: echo "movz x0, #0x1234" | llvm-mc -triple=aarch64 -show-encoding }
  ResetCode;
  EmitAsmA64('movz x0, #0x1234');
  AssertBytes('movz x0, #0x1234', [$80, $46, $82, $D2]);

  { Oracle: echo "movk x0, #0x5678, lsl #16" | llvm-mc -triple=aarch64 -show-encoding }
  ResetCode;
  EmitAsmA64('movk x0, #0x5678, lsl #16');
  AssertBytes('movk x0, #0x5678, lsl #16', [$00, $CF, $AA, $F2]);

  { --- Load / Store --- }
  { Oracle: echo "ldr x0, [x1]" | llvm-mc -triple=aarch64 -show-encoding }
  ResetCode;
  EmitAsmA64('ldr x0, [x1]');
  AssertBytes('ldr x0, [x1]', [$20, $00, $40, $F9]);

  { Oracle: echo "str x0, [x1, #8]" | llvm-mc -triple=aarch64 -show-encoding }
  ResetCode;
  EmitAsmA64('str x0, [x1, #8]');
  AssertBytes('str x0, [x1, #8]', [$20, $04, $00, $F9]);

  { Oracle: echo "str x0, [sp, #-16]!" | llvm-mc -triple=aarch64 -show-encoding }
  ResetCode;
  EmitAsmA64('str x0, [sp, #-16]!');
  AssertBytes('str x0, [sp, #-16]!', [$E0, $0F, $1F, $F8]);

  { Oracle: echo "ldr x0, [sp], #16" | llvm-mc -triple=aarch64 -show-encoding }
  ResetCode;
  EmitAsmA64('ldr x0, [sp], #16');
  AssertBytes('ldr x0, [sp], #16', [$E0, $07, $41, $F8]);

  { Oracle: echo "ldr w1, [pc, #8]" | llvm-mc -triple=aarch64 -show-encoding }
  ResetCode;
  EmitAsmA64('ldr w1, [pc, #8]');
  AssertBytes('ldr w1, [pc, #8]', [$41, $00, $00, $18]);

  { --- Control Flow & Ret/Nop --- }
  { Oracle: echo "nop" | llvm-mc -triple=aarch64 -show-encoding }
  ResetCode;
  EmitAsmA64('nop');
  AssertBytes('nop', [$1F, $20, $03, $D5]);

  { Oracle: echo "ret" | llvm-mc -triple=aarch64 -show-encoding }
  ResetCode;
  EmitAsmA64('ret');
  AssertBytes('ret', [$C0, $03, $5F, $D6]);

  { Oracle: echo "b 8" | llvm-mc -triple=aarch64 -show-encoding }
  ResetCode;
  EmitAsmA64('b 8');
  AssertBytes('b 8', [$02, $00, $00, $14]);

  { Oracle: echo "b.eq 8" | llvm-mc -triple=aarch64 -show-encoding }
  ResetCode;
  EmitAsmA64('b.eq 8');
  AssertBytes('b.eq 8', [$40, $00, $00, $54]);

  { Oracle: echo "cbz x0, 8" | llvm-mc -triple=aarch64 -show-encoding }
  ResetCode;
  EmitAsmA64('cbz x0, 8');
  AssertBytes('cbz x0, 8', [$40, $00, $00, $B4]);

  { Oracle: echo "cset x0, eq" | llvm-mc -triple=aarch64 -show-encoding }
  ResetCode;
  EmitAsmA64('cset x0, eq');
  AssertBytes('cset x0, eq', [$E0, $17, $9F, $9A]);

  { --- Jumps and Forward References --- }
  { Oracle: echo -e "b .done\nnop\n.done:" | llvm-mc -triple=aarch64 -show-encoding }
  ResetCode;
  EmitAsmA64([
    'b .done',
    'nop',
    '.done:'
  ]);
  AssertBytes('b forward', [$02, $00, $00, $14, $1F, $20, $03, $D5]);

  writeln('ALL AARCH64 ASM EMIT TESTS PASSED');
end.
