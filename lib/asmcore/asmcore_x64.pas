unit asmcore_x64;
{ x86-64 instruction encoder + textual printer — first slice.
  Covers: mov reg,imm | add reg,reg | ret. Grows per need.
  See devdocs/developer/asmcore-design.md. }

interface

uses asmcore_base;

const
  reg_rax = 0; reg_rcx = 1; reg_rdx = 2; reg_rbx = 3;
  reg_rsp = 4; reg_rbp = 5; reg_rsi = 6; reg_rdi = 7;
  reg_r8  = 8; reg_r9  = 9; reg_r10 = 10; reg_r11 = 11;
  reg_r12 = 12; reg_r13 = 13; reg_r14 = 14; reg_r15 = 15;

function AsmEncodeX64(const instr: TAsmInstr;
                       var buf: TAsmByteBuf;
                       var patches: TAsmPatchList): Boolean;
function AsmPrintX64(const instr: TAsmInstr): AnsiString;
function AsmCoreLastError: AnsiString;

implementation

var
  LastError: AnsiString;

{ Local mnemonic compare — deliberately not pulling in sysutils' LowerCase
  just to keep asmcore dependency-free (uses asmcore_base only). }
function MnemIs(const m: AnsiString; const lit: AnsiString): Boolean;
var i: Integer; c: Char;
begin
  Result := False;
  if Length(m) <> Length(lit) then Exit;
  for i := 1 to Length(m) do
  begin
    c := m[i];
    if (c >= 'A') and (c <= 'Z') then c := Chr(Ord(c) + 32);
    if c <> lit[i] then Exit;
  end;
  Result := True;
end;

{ Plain if-chain, not a typed const array of AnsiString — that construct is
  broken in the pinned stable compiler for multi-char string elements (see
  devdocs/progress/backlog/bug-typed-const-array-of-string-broken.md, which
  this finding was folded into). }
function RegName(reg, size: Integer): AnsiString;
begin
  if (reg < 0) or (reg > 15) then begin Result := '?'; Exit; end;
  if size = 8 then
  begin
    case reg of
      0: Result := 'rax'; 1: Result := 'rcx'; 2: Result := 'rdx'; 3: Result := 'rbx';
      4: Result := 'rsp'; 5: Result := 'rbp'; 6: Result := 'rsi'; 7: Result := 'rdi';
      8: Result := 'r8';  9: Result := 'r9';  10: Result := 'r10'; 11: Result := 'r11';
      12: Result := 'r12'; 13: Result := 'r13'; 14: Result := 'r14'; 15: Result := 'r15';
    end;
  end
  else
  begin
    case reg of
      0: Result := 'eax'; 1: Result := 'ecx'; 2: Result := 'edx'; 3: Result := 'ebx';
      4: Result := 'esp'; 5: Result := 'ebp'; 6: Result := 'esi'; 7: Result := 'edi';
      8: Result := 'r8d';  9: Result := 'r9d';  10: Result := 'r10d'; 11: Result := 'r11d';
      12: Result := 'r12d'; 13: Result := 'r13d'; 14: Result := 'r14d'; 15: Result := 'r15d';
    end;
  end;
end;

function IntToStrAsm(v: Int64): AnsiString;
var neg: Boolean; u: Int64; s: AnsiString; d: Integer;
begin
  if v = 0 then begin Result := '0'; Exit; end;
  neg := v < 0;
  u := v; if neg then u := -u;
  s := '';
  while u > 0 do
  begin
    d := Integer(u mod 10);
    s := Chr(Ord('0') + d) + s;
    u := u div 10;
  end;
  if neg then s := '-' + s;
  Result := s;
end;

{ REX prefix: 0100WRXB. needB extends the rm/opcode-reg field, needR the
  reg field. Emits nothing if none of W/R/B/X are needed. }
procedure EmitRex(var buf: TAsmByteBuf; w: Boolean; regHi, rmHi: Boolean);
var rex: Integer;
begin
  if not (w or regHi or rmHi) then Exit;
  rex := $40;
  if w then rex := rex or $08;
  if regHi then rex := rex or $04;
  if rmHi then rex := rex or $01;
  BufAppend(buf, Byte(rex));
end;

function EncodeMovRegImm(const dst, src: TAsmOperand; var buf: TAsmByteBuf): Boolean;
begin
  Result := False;
  if dst.Kind <> opReg then begin LastError := 'mov: expected register destination'; Exit; end;
  if src.Kind <> opImm then begin LastError := 'mov: expected immediate source (this slice)'; Exit; end;
  EmitRex(buf, dst.RegSize = 8, False, dst.Reg >= 8);
  BufAppend(buf, Byte($B8 + (dst.Reg and 7)));
  if dst.RegSize = 8 then BufAppendI64(buf, src.Imm) else BufAppendI32(buf, src.Imm);
  Result := True;
end;

function EncodeAddRegReg(const dst, src: TAsmOperand; var buf: TAsmByteBuf): Boolean;
var modrm: Integer;
begin
  Result := False;
  if (dst.Kind <> opReg) or (src.Kind <> opReg) then
  begin LastError := 'add: expected register, register (this slice)'; Exit; end;
  EmitRex(buf, dst.RegSize = 8, src.Reg >= 8, dst.Reg >= 8);
  BufAppend(buf, $01);   { ADD r/m, r }
  modrm := ($03 shl 6) or ((src.Reg and 7) shl 3) or (dst.Reg and 7);
  BufAppend(buf, Byte(modrm));
  Result := True;
end;

function AsmEncodeX64(const instr: TAsmInstr;
                       var buf: TAsmByteBuf;
                       var patches: TAsmPatchList): Boolean;
begin
  LastError := '';
  if MnemIs(instr.Mnemonic, 'mov') and (instr.OperandCount = 2) then
  begin
    Result := EncodeMovRegImm(instr.Operands[0], instr.Operands[1], buf);
    Exit;
  end;
  if MnemIs(instr.Mnemonic, 'add') and (instr.OperandCount = 2) then
  begin
    Result := EncodeAddRegReg(instr.Operands[0], instr.Operands[1], buf);
    Exit;
  end;
  if MnemIs(instr.Mnemonic, 'ret') and (instr.OperandCount = 0) then
  begin
    BufAppend(buf, $C3);
    Result := True;
    Exit;
  end;
  LastError := 'asmcore_x64: unrecognized mnemonic/operand combination: ' + instr.Mnemonic;
  Result := False;
end;

function AsmPrintX64(const instr: TAsmInstr): AnsiString;
var op0, op1: TAsmOperand;
begin
  if MnemIs(instr.Mnemonic, 'ret') and (instr.OperandCount = 0) then
  begin
    Result := 'ret';
    Exit;
  end;
  if instr.OperandCount = 2 then
  begin
    op0 := instr.Operands[0];
    op1 := instr.Operands[1];
    Result := instr.Mnemonic + ' ' + RegName(op0.Reg, op0.RegSize) + ', ';
    if op1.Kind = opImm then
      Result := Result + IntToStrAsm(op1.Imm)
    else
      Result := Result + RegName(op1.Reg, op1.RegSize);
    Exit;
  end;
  Result := instr.Mnemonic + ' ; <unprintable in this slice>';
end;

function AsmCoreLastError: AnsiString;
begin
  Result := LastError;
end;

end.
