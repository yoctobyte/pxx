program test_asm_emit_x64;
{$mode objfpc}{$H+}

{ Standalone oracle harness for the shared x86-64 text assembler (asmtext.inc +
  x64enc.inc). Mocks the byte sink and fixup tables, includes the real encoder +
  parser, and asserts each instruction encodes to the exact bytes emitted by
  `llvm-mc-18 -triple=x86_64` (Intel syntax). Mirrors test_asm_emit_386.pas. }

uses SysUtils;

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

procedure EmitI32(v: Int64);
begin
  EmitB(v and $FF); EmitB((v shr 8) and $FF);
  EmitB((v shr 16) and $FF); EmitB((v shr 24) and $FF);
end;

procedure EmitI64(v: Int64);
begin
  EmitI32(v and $FFFFFFFF); EmitI32((v shr 32) and $FFFFFFFF);
end;

{ Inline-asm-buffer sink — never reached (EncToAsmBuffer stays False) but the
  encoder references them. }
procedure AsmB(b: Byte); begin EmitB(b); end;
procedure AsmI16(v: Int64); begin EmitB(v and $FF); EmitB((v shr 8) and $FF); end;
procedure AsmI32(v: Int64); begin EmitI32(v); end;
procedure AsmI64(v: Int64); begin EmitI64(v); end;

procedure Patch32(pos: Integer; v: Int64);
begin
  Code[pos] := v and $FF; Code[pos+1] := (v shr 8) and $FF;
  Code[pos+2] := (v shr 16) and $FF; Code[pos+3] := (v shr 24) and $FF;
end;

procedure Error(const msg: AnsiString);
begin
  writeln(StdErr, 'ERROR: ', msg); Halt(1);
end;

function CaseEqual(const a, b: AnsiString): Boolean;
begin
  Result := LowerCase(a) = LowerCase(b);
end;

function AppendChar(var s: AnsiString; c: Char): Integer;
begin
  s := s + c; Result := Length(s);
end;

procedure EmitDataRef(dataOff: Integer);
begin
  if FixCount >= 1024 then Error('fixup overflow');
  Fixups[FixCount].CodePos := CodeLen; Fixups[FixCount].DataOff := dataOff;
  Inc(FixCount);
  EmitI64(0);   { x64 data refs are absolute 8-byte }
end;

procedure EmitGlobRef(bssOff: Integer);
begin
  if GlobFixCount >= 1024 then Error('global fixup overflow');
  GlobFix[GlobFixCount].CodePos := CodeLen; GlobFix[GlobFixCount].BSSoff := bssOff;
  Inc(GlobFixCount);
  EmitI32(0);   { BSS is low 4G → 4-byte }
end;

{ Full x86-64 register map: name -> (num, size-in-bytes). }
function AsmRegNum(const nm: AnsiString; var num, size: Integer): Boolean;
  function M(n, s: Integer): Boolean; begin num := n; size := s; M := True; end;
var l: AnsiString;
begin
  l := LowerCase(nm);
  Result := True;
  { 64-bit }
  if l = 'rax' then begin AsmRegNum := M(0,8); Exit; end;
  if l = 'rcx' then begin AsmRegNum := M(1,8); Exit; end;
  if l = 'rdx' then begin AsmRegNum := M(2,8); Exit; end;
  if l = 'rbx' then begin AsmRegNum := M(3,8); Exit; end;
  if l = 'rsp' then begin AsmRegNum := M(4,8); Exit; end;
  if l = 'rbp' then begin AsmRegNum := M(5,8); Exit; end;
  if l = 'rsi' then begin AsmRegNum := M(6,8); Exit; end;
  if l = 'rdi' then begin AsmRegNum := M(7,8); Exit; end;
  if l = 'r8'  then begin AsmRegNum := M(8,8); Exit; end;
  if l = 'r9'  then begin AsmRegNum := M(9,8); Exit; end;
  if l = 'r10' then begin AsmRegNum := M(10,8); Exit; end;
  if l = 'r11' then begin AsmRegNum := M(11,8); Exit; end;
  if l = 'r12' then begin AsmRegNum := M(12,8); Exit; end;
  if l = 'r13' then begin AsmRegNum := M(13,8); Exit; end;
  if l = 'r14' then begin AsmRegNum := M(14,8); Exit; end;
  if l = 'r15' then begin AsmRegNum := M(15,8); Exit; end;
  { 32-bit }
  if l = 'eax' then begin AsmRegNum := M(0,4); Exit; end;
  if l = 'ecx' then begin AsmRegNum := M(1,4); Exit; end;
  if l = 'edx' then begin AsmRegNum := M(2,4); Exit; end;
  if l = 'ebx' then begin AsmRegNum := M(3,4); Exit; end;
  if l = 'esp' then begin AsmRegNum := M(4,4); Exit; end;
  if l = 'ebp' then begin AsmRegNum := M(5,4); Exit; end;
  if l = 'esi' then begin AsmRegNum := M(6,4); Exit; end;
  if l = 'edi' then begin AsmRegNum := M(7,4); Exit; end;
  { 16-bit }
  if l = 'ax' then begin AsmRegNum := M(0,2); Exit; end;
  { 8-bit }
  if l = 'al'  then begin AsmRegNum := M(0,1); Exit; end;
  if l = 'cl'  then begin AsmRegNum := M(1,1); Exit; end;
  if l = 'dl'  then begin AsmRegNum := M(2,1); Exit; end;
  if l = 'bl'  then begin AsmRegNum := M(3,1); Exit; end;
  if l = 'sil' then begin AsmRegNum := M(6,1); Exit; end;
  if l = 'dil' then begin AsmRegNum := M(7,1); Exit; end;
  { xmm0..xmm15 (size 16 marker) }
  if l = 'xmm0' then begin AsmRegNum := M(0,16); Exit; end;
  if l = 'xmm1' then begin AsmRegNum := M(1,16); Exit; end;
  if l = 'xmm2' then begin AsmRegNum := M(2,16); Exit; end;
  if l = 'xmm3' then begin AsmRegNum := M(3,16); Exit; end;
  if l = 'xmm8' then begin AsmRegNum := M(8,16); Exit; end;
  if l = 'xmm9' then begin AsmRegNum := M(9,16); Exit; end;
  Result := False;
end;

{$include ../compiler/x64enc.inc}
{$include ../compiler/asmtext.inc}

procedure ResetCode;
begin
  CodeLen := 0; FixCount := 0; GlobFixCount := 0;
end;

procedure AssertBytes(const name: AnsiString; const expected: array of Byte);
var i: Integer; ok: Boolean;
begin
  ok := CodeLen = Length(expected);
  if ok then
    for i := 0 to Length(expected) - 1 do
      if Code[i] <> expected[i] then ok := False;
  if not ok then
  begin
    write('FAIL ', name, ': got');
    for i := 0 to CodeLen - 1 do write(' ', IntToHex(Code[i], 2));
    write(' expected');
    for i := 0 to Length(expected) - 1 do write(' ', IntToHex(expected[i], 2));
    writeln;
    Halt(1);
  end;
end;

begin
  { --- test --- }
  ResetCode; EmitAsmX64('test rbx, rbx');
  AssertBytes('test rbx,rbx', [$48,$85,$DB]);
  ResetCode; EmitAsmX64('test ecx, edx');
  AssertBytes('test ecx,edx', [$85,$D1]);
  ResetCode; EmitAsmX64('test rbx, 1');
  AssertBytes('test rbx,1', [$48,$F7,$C3,$01,$00,$00,$00]);
  ResetCode; EmitAsmX64('test byte [rdi], 1');
  AssertBytes('test byte [rdi],1', [$F6,$07,$01]);

  { --- unary F6/F7 group --- }
  ResetCode; EmitAsmX64('not rax');  AssertBytes('not rax', [$48,$F7,$D0]);
  ResetCode; EmitAsmX64('neg eax');  AssertBytes('neg eax', [$F7,$D8]);
  ResetCode; EmitAsmX64('mul rcx');  AssertBytes('mul rcx', [$48,$F7,$E1]);
  ResetCode; EmitAsmX64('imul rcx'); AssertBytes('imul rcx', [$48,$F7,$E9]);
  ResetCode; EmitAsmX64('div rcx');  AssertBytes('div rcx', [$48,$F7,$F1]);
  ResetCode; EmitAsmX64('idiv ecx'); AssertBytes('idiv ecx', [$F7,$F9]);
  ResetCode; EmitAsmX64('imul rax, rcx');
  AssertBytes('imul rax,rcx', [$48,$0F,$AF,$C1]);

  { --- shifts --- }
  ResetCode; EmitAsmX64('shl rax, 4');  AssertBytes('shl rax,4', [$48,$C1,$E0,$04]);
  ResetCode; EmitAsmX64('shr eax, 1');  AssertBytes('shr eax,1', [$D1,$E8]);
  ResetCode; EmitAsmX64('sar rdx, 63'); AssertBytes('sar rdx,63', [$48,$C1,$FA,$3F]);
  ResetCode; EmitAsmX64('shl rax, cl'); AssertBytes('shl rax,cl', [$48,$D3,$E0]);

  { --- movzx / movsx --- }
  ResetCode; EmitAsmX64('movzx eax, al');
  AssertBytes('movzx eax,al', [$0F,$B6,$C0]);
  ResetCode; EmitAsmX64('movzx rax, byte [rsi]');
  AssertBytes('movzx rax,byte[rsi]', [$48,$0F,$B6,$06]);
  ResetCode; EmitAsmX64('movzx ecx, byte [rbp - 8]');
  AssertBytes('movzx ecx,byte[rbp-8]', [$0F,$B6,$4D,$F8]);
  ResetCode; EmitAsmX64('movsx edx, byte [rbp - 4]');
  AssertBytes('movsx edx,byte[rbp-4]', [$0F,$BE,$55,$FC]);
  ResetCode; EmitAsmX64('movsx rax, eax');
  AssertBytes('movsx rax,eax', [$48,$63,$C0]);

  { --- setcc --- }
  ResetCode; EmitAsmX64('sete al');   AssertBytes('sete al', [$0F,$94,$C0]);
  ResetCode; EmitAsmX64('setne bl');  AssertBytes('setne bl', [$0F,$95,$C3]);
  ResetCode; EmitAsmX64('setb cl');   AssertBytes('setb cl', [$0F,$92,$C1]);
  ResetCode; EmitAsmX64('seta dl');   AssertBytes('seta dl', [$0F,$97,$C2]);
  ResetCode; EmitAsmX64('setne sil'); AssertBytes('setne sil', [$40,$0F,$95,$C6]);

  { --- call reg --- }
  ResetCode; EmitAsmX64('call rax'); AssertBytes('call rax', [$FF,$D0]);
  ResetCode; EmitAsmX64('call r11'); AssertBytes('call r11', [$41,$FF,$D3]);

  { --- string ops --- }
  ResetCode; EmitAsmX64('movsb');     AssertBytes('movsb', [$A4]);
  ResetCode; EmitAsmX64('stosb');     AssertBytes('stosb', [$AA]);
  ResetCode; EmitAsmX64('rep movsb'); AssertBytes('rep movsb', [$F3,$A4]);
  ResetCode; EmitAsmX64('rep stosb'); AssertBytes('rep stosb', [$F3,$AA]);

  { --- ALU reg,[mem] and [mem],reg --- }
  ResetCode; EmitAsmX64('add rax, [rbp - 8]');
  AssertBytes('add rax,[rbp-8]', [$48,$03,$45,$F8]);
  ResetCode; EmitAsmX64('sub [rbp - 8], rcx');
  AssertBytes('sub [rbp-8],rcx', [$48,$29,$4D,$F8]);
  ResetCode; EmitAsmX64('cmp eax, [rsi]');
  AssertBytes('cmp eax,[rsi]', [$3B,$06]);
  ResetCode; EmitAsmX64('xor [rdi], eax');
  AssertBytes('xor [rdi],eax', [$31,$07]);

  { --- reloc moves --- }
  ResetCode; EmitAsmX64(['mov rax, @data', 100]);
  AssertBytes('mov rax,@data', [$48,$B8,$00,$00,$00,$00,$00,$00,$00,$00]);
  if (FixCount <> 1) or (Fixups[0].DataOff <> 100) then Error('data reloc failed');
  ResetCode; EmitAsmX64(['mov edx, @glob', 200]);
  AssertBytes('mov edx,@glob', [$BA,$00,$00,$00,$00]);
  if (GlobFixCount <> 1) or (GlobFix[0].BSSoff <> 200) then Error('glob reloc failed');

  { --- SSE scalar double --- }
  ResetCode; EmitAsmX64('movsd xmm0, xmm1'); AssertBytes('movsd xmm0,xmm1', [$F2,$0F,$10,$C1]);
  ResetCode; EmitAsmX64('movsd xmm0, [rbp - 8]'); AssertBytes('movsd xmm0,[rbp-8]', [$F2,$0F,$10,$45,$F8]);
  ResetCode; EmitAsmX64('movsd [rbp - 8], xmm0'); AssertBytes('movsd [rbp-8],xmm0', [$F2,$0F,$11,$45,$F8]);
  ResetCode; EmitAsmX64('addsd xmm0, xmm1'); AssertBytes('addsd xmm0,xmm1', [$F2,$0F,$58,$C1]);
  ResetCode; EmitAsmX64('subsd xmm0, xmm1'); AssertBytes('subsd xmm0,xmm1', [$F2,$0F,$5C,$C1]);
  ResetCode; EmitAsmX64('mulsd xmm2, xmm3'); AssertBytes('mulsd xmm2,xmm3', [$F2,$0F,$59,$D3]);
  ResetCode; EmitAsmX64('divsd xmm0, xmm1'); AssertBytes('divsd xmm0,xmm1', [$F2,$0F,$5E,$C1]);
  ResetCode; EmitAsmX64('addsd xmm0, [rbp - 8]'); AssertBytes('addsd xmm0,[rbp-8]', [$F2,$0F,$58,$45,$F8]);
  ResetCode; EmitAsmX64('cvtsi2sd xmm0, rax'); AssertBytes('cvtsi2sd xmm0,rax', [$F2,$48,$0F,$2A,$C0]);
  ResetCode; EmitAsmX64('cvtsi2sd xmm0, eax'); AssertBytes('cvtsi2sd xmm0,eax', [$F2,$0F,$2A,$C0]);
  ResetCode; EmitAsmX64('cvttsd2si rax, xmm0'); AssertBytes('cvttsd2si rax,xmm0', [$F2,$48,$0F,$2C,$C0]);
  ResetCode; EmitAsmX64('cvttsd2si eax, xmm1'); AssertBytes('cvttsd2si eax,xmm1', [$F2,$0F,$2C,$C1]);
  ResetCode; EmitAsmX64('comisd xmm0, xmm1'); AssertBytes('comisd xmm0,xmm1', [$66,$0F,$2F,$C1]);
  ResetCode; EmitAsmX64('ucomisd xmm0, xmm1'); AssertBytes('ucomisd xmm0,xmm1', [$66,$0F,$2E,$C1]);
  ResetCode; EmitAsmX64('xorps xmm0, xmm0'); AssertBytes('xorps xmm0,xmm0', [$0F,$57,$C0]);
  ResetCode; EmitAsmX64('movsd xmm8, xmm9'); AssertBytes('movsd xmm8,xmm9', [$F2,$45,$0F,$10,$C1]);
  ResetCode; EmitAsmX64('cvtsd2ss xmm0, xmm1'); AssertBytes('cvtsd2ss xmm0,xmm1', [$F2,$0F,$5A,$C1]);

  { --- movq (xmm<->gp / xmm<->xmm / xmm<->mem) --- }
  ResetCode; EmitAsmX64('movq xmm0, rax'); AssertBytes('movq xmm0,rax', [$66,$48,$0F,$6E,$C0]);
  ResetCode; EmitAsmX64('movq rax, xmm0'); AssertBytes('movq rax,xmm0', [$66,$48,$0F,$7E,$C0]);
  ResetCode; EmitAsmX64('movq xmm0, xmm1'); AssertBytes('movq xmm0,xmm1', [$F3,$0F,$7E,$C1]);
  ResetCode; EmitAsmX64('movq xmm0, [rbp - 8]'); AssertBytes('movq xmm0,[rbp-8]', [$F3,$0F,$7E,$45,$F8]);
  ResetCode; EmitAsmX64('movq [rbp - 8], xmm0'); AssertBytes('movq [rbp-8],xmm0', [$66,$0F,$D6,$45,$F8]);
  ResetCode; EmitAsmX64('movq xmm0, r10'); AssertBytes('movq xmm0,r10', [$66,$49,$0F,$6E,$C2]);
  ResetCode; EmitAsmX64('movq r11, xmm2'); AssertBytes('movq r11,xmm2', [$66,$49,$0F,$7E,$D3]);

  writeln('ALL X64 ASM EMIT TESTS PASSED');
end.
