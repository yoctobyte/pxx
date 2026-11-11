program test_asm_emit_x64;
{$mode objfpc}{$H+}

{ Standalone oracle harness for the shared x86-64 text assembler (asmtext.inc +
  x64enc.inc). Mocks the byte sink and fixup tables, includes the real encoder +
  parser, and asserts each instruction encodes to the exact bytes emitted by
  `llvm-mc-18 -triple=x86_64` (Intel syntax). Mirrors test_asm_emit_386.pas. }

uses SysUtils;

var
  Code: array[0..65535] of Byte;
  { Mocked because the declaration lives in defs.inc, which this harness does
    not include -- EmitGlobRef needs it to know whether the ModRM/SIB bytes it
    is about to rewrite went into Code or into AsmBytes. See
    tools/standalone_inc_harnesses.sh for why this file has to carry it. }
  EncToAsmBuffer: Boolean = False;
  { Same reason as EncToAsmBuffer above: declared in defs.inc, which this
    harness does not include. EncPrefixAndREX reads it to decide whether the
    instruction names a HIGH-byte register (%ah/%ch/%dh/%bh), which must be
    encoded with no REX prefix -- the same numbers 4..7 WITH a prefix are
    spl/bpl/sil/dil. False here matches every non-inline-asm caller.
    bug-a-the-x86-64-encoder-cannot-name-a-high-byte-register }
  AsmHigh8Operand: Boolean = False;
  { Backs the mocked PICRefsAreRipRelative below. A VARIABLE, not a constant
    True: `mov reg, @glob` has two encodings and pinning the mock to one
    would leave the other untested here -- and the absolute arm is the one
    every non-x86-64 target and every inline-asm buffer takes. }
  PICRipMock: Boolean = True;
  CodeLen: Integer = 0;
  Fixups: array[0..1023] of record CodePos, DataOff: Integer; end;
  FixCount: Integer = 0;
  GlobFix: array[0..1023] of record CodePos, BSSoff: Integer; end;
  GlobFixCount: Integer = 0;
  CallFixCount: Integer = 0;      { read by asmtext.inc's whole-call memo guard }
  ProcAddrFixCount: Integer = 0;

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

{ Mocked: the real predicate is in emit.inc and reads TargetArch +
  EncToAsmBuffer, neither of which exists in this harness. asmtext.inc calls
  it to choose between `lea r64,[rip+disp32]` and `mov r32,imm32`. }
function PICRefsAreRipRelative: Boolean;
begin
  Result := PICRipMock;
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

{ the REAL register resolver, not a mock table }
{$include ../compiler/asmregs.inc}

{ --- the environment asmtext.inc reaches into defs.inc for --------------------
  This harness supplies its own environment rather than {$include}ing defs.inc,
  which is the whole reason it stays small enough to maintain. The cost is that
  a NEW reference from asmtext.inc into defs.inc surfaces HERE, as `undefined
  variable`, while the compiler itself builds fine -- so the error names this
  file's configuration, not a defect in the declaration.

  Both symbols below arrived with the a.asmmemo memoisation
  (asmtext.inc:1040-1076) and are mocked, not forwarded.

  MEASURED, because "why here and not elsewhere" is the question that matters:
  asmtext.inc has exactly TWO including configurations -- compiler.pas:113,
  which includes defs.inc, and this file, which does not. That is the entire
  difference. lexer.inc calls PxxDbgWants at four sites and never complains
  because its own standalone harness, test/manual/test_pylexer.pas, includes
  compiler/defs.inc at line 9 before including lexer.inc at line 10. So this is
  not a visibility quirk to be silenced with a forward declaration; it is a
  harness that owns its environment and was missing two pieces of it.
  regression-test-asm-test-asm-emit-x64-2 }

var
  { asmtext.inc's memo poisons an entry when emitting a line moves a counter.
    Nothing in this harness lowers a libc syscall, so this stays 0 and the
    check correctly never fires -- 0 is the honest value here, not a placeholder. }
  LibcSyscallCallCount: Integer = 0;
  MemoRound: Integer;   { loop counter for the whole-call memo test }

{ PXXDBG channel selector. Always False here: this harness asserts exact byte
  sequences, so a debug line on stdout would be noise in the thing being
  measured. }
function AIntToStr(v: Int64): AnsiString;
begin
  Result := IntToStr(v);
end;

function PxxDbgWants(const prefix, name: AnsiString): Boolean;
begin
  Result := False;
end;

{$include ../compiler/rel8.inc}   { CheckRel8: the assembler's short-jump range check }
{$include ../compiler/x64enc.inc}
{$include ../compiler/asmtext.inc}

{ Resolves x64enc.inc's `AsmRecordGlobalFixup` forward decl (the real body
  lives in compiler/asmenc.inc, not included here) — never reached since
  EncToAsmBuffer stays False in this harness. }
procedure AsmRecordGlobalFixup(bssOff: Integer); begin EmitGlobRef(bssOff); end;

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
  { Both arms, because the encoding is chosen at run time and asserting only
    the live one would let the other rot silently. rip form: REX.W 8D, the
    register in ModRM.reg -- so a high register needs REX.R, not REX.B, and
    r10 is here to catch that swap. }
  ResetCode; EmitAsmX64(['mov edx, @glob', 200]);
  AssertBytes('mov edx,@glob (rip)', [$48,$8D,$15,$00,$00,$00,$00]);
  ResetCode; EmitAsmX64(['mov r10, @glob', 200]);
  AssertBytes('mov r10,@glob (rip, REX.R)', [$4C,$8D,$15,$00,$00,$00,$00]);
  PICRipMock := False;
  ResetCode; EmitAsmX64(['mov edx, @glob', 200]);
  AssertBytes('mov edx,@glob (absolute)', [$BA,$00,$00,$00,$00]);
  ResetCode; EmitAsmX64(['mov r10, @glob', 200]);
  AssertBytes('mov r10,@glob (absolute, REX.B)', [$41,$BA,$00,$00,$00,$00]);
  PICRipMock := True;
  if (GlobFixCount <> 1) or (GlobFix[0].BSSoff <> 200) then Error('glob reloc failed');

  { --- [@glob]/[@data] dereference-load (mem->reg, bracketed -- distinct from
    the bracket-less address-load forms above) and lea absolute-address (new
    form added for the ir_codegen.inc EmitAsmX64 migration) --- }
  ResetCode; EmitAsmX64(['mov rdi, [@glob]', 300]);
  AssertBytes('mov rdi,[@glob]', [$48,$8B,$3C,$25,$00,$00,$00,$00]);
  ResetCode; EmitAsmX64(['mov rax, [@glob]', 300]);
  AssertBytes('mov rax,[@glob]', [$48,$8B,$04,$25,$00,$00,$00,$00]);
  ResetCode; EmitAsmX64(['lea rsi, [@glob]', 400]);
  AssertBytes('lea rsi,[@glob]', [$48,$8D,$34,$25,$00,$00,$00,$00]);
  { whole-call memo: the same line with different hole values must re-encode
    (disp8 vs disp32, shift-by-1 vs imm8, register hole into REX.B), and a
    repeat must replay identical bytes. Bytes from GNU as. }
  for MemoRound := 1 to 2 do
  begin
    ResetCode; EmitAsmX64(['mov rax, [rbp-%]', 8]);
    AssertBytes('memo mov rax,[rbp-8]', [$48,$8B,$45,$F8]);
    ResetCode; EmitAsmX64(['mov rax, [rbp-%]', 200]);
    AssertBytes('memo mov rax,[rbp-200]', [$48,$8B,$85,$38,$FF,$FF,$FF]);
    ResetCode; EmitAsmX64(['shl %r64, %', 0, 1]);
    AssertBytes('memo shl rax,1', [$48,$D1,$E0]);
    ResetCode; EmitAsmX64(['shl %r64, %', 9, 1]);
    AssertBytes('memo shl r9,1', [$49,$D1,$E1]);
    ResetCode; EmitAsmX64(['shl %r64, %', 0, 5]);
    AssertBytes('memo shl rax,5', [$48,$C1,$E0,$05]);
  end;
  { byte memory forms: a base of rsp..rdi is NOT a byte register -- no REX. }
  ResetCode; EmitAsmX64(['mov [rdi], cl']);
  AssertBytes('mov [rdi],cl', [$88,$0F]);
  ResetCode; EmitAsmX64(['mov cl, [rsi]']);
  AssertBytes('mov cl,[rsi]', [$8A,$0E]);
  ResetCode; EmitAsmX64(['mov [rdi], sil']);
  AssertBytes('mov [rdi],sil', [$40,$88,$37]);
  ResetCode; EmitAsmX64(['inc byte [rdi]']);
  AssertBytes('inc byte [rdi]', [$FE,$07]);
  ResetCode; EmitAsmX64(['mov rax, [rdi+r9*8]']);
  AssertBytes('mov rax,[rdi+r9*8]', [$4A,$8B,$04,$CF]);
  ResetCode; EmitAsmX64(['lea rax, [rdi+r9*8]']);
  AssertBytes('lea rax,[rdi+r9*8]', [$4A,$8D,$04,$CF]);
  { push / pop a memory operand (FF /6, 8F /0). }
  ResetCode; EmitAsmX64(['push [rax]']);
  AssertBytes('push [rax]', [$FF,$30]);
  ResetCode; EmitAsmX64(['push [rax+%]', 8]);
  AssertBytes('push [rax+8]', [$FF,$70,$08]);
  ResetCode; EmitAsmX64(['pop [rbx]']);
  AssertBytes('pop [rbx]', [$8F,$03]);
  ResetCode; EmitAsmX64(['push [r9]']);
  AssertBytes('push [r9]', [$41,$FF,$31]);
  ResetCode; EmitAsmX64(['push [rbp-%]', 200]);
  AssertBytes('push [rbp-200]', [$FF,$B5,$38,$FF,$FF,$FF]);
  ResetCode; EmitAsmX64(['xor r8d, r8d']);
  AssertBytes('xor r8d,r8d', [$45,$31,$C0]);
  { SSE scalar <-> absolute memory: the SSE prefix precedes REX. }
  ResetCode; EmitAsmX64(['movsd xmm0, [@glob]', 300]);
  AssertBytes('movsd xmm0,[@glob]', [$F2,$0F,$10,$04,$25,$00,$00,$00,$00]);
  ResetCode; EmitAsmX64(['movsd [@glob], xmm0', 300]);
  AssertBytes('movsd [@glob],xmm0', [$F2,$0F,$11,$04,$25,$00,$00,$00,$00]);
  ResetCode; EmitAsmX64(['movss [@glob], xmm9', 300]);
  AssertBytes('movss [@glob],xmm9', [$F3,$44,$0F,$11,$0C,$25,$00,$00,$00,$00]);
  ResetCode; EmitAsmX64(['addsd xmm2, [%]', 16]);
  AssertBytes('addsd xmm2,[16]', [$F2,$0F,$58,$14,$25,$10,$00,$00,$00]);
  ResetCode; EmitAsmX64(['lea rax, [@data]', 500]);
  AssertBytes('lea rax,[@data]', [$48,$8D,$04,$25,$00,$00,$00,$00,$00,$00,$00,$00]);

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

  { --- adc / sbb / movabs --- }
  ResetCode; EmitAsmX64('adc edx, 0'); AssertBytes('adc edx,0', [$83,$D2,$00]);
  ResetCode; EmitAsmX64('adc rax, rcx'); AssertBytes('adc rax,rcx', [$48,$11,$C8]);
  ResetCode; EmitAsmX64('adc eax, ebx'); AssertBytes('adc eax,ebx', [$11,$D8]);
  ResetCode; EmitAsmX64('sbb rax, rcx'); AssertBytes('sbb rax,rcx', [$48,$19,$C8]);
  ResetCode; EmitAsmX64('sbb edi, [rsp + 4]'); AssertBytes('sbb edi,[rsp+4]', [$1B,$7C,$24,$04]);
  ResetCode; EmitAsmX64(['movabs rcx, %', 0]); AssertBytes('movabs rcx,0', [$48,$B9,$00,$00,$00,$00,$00,$00,$00,$00]);

  { --- xchg + absolute [@glob] r/m (atomic mutex slot) --- }
  ResetCode; EmitAsmX64('xchg eax, [rbp - 8]'); AssertBytes('xchg eax,[rbp-8]', [$87,$45,$F8]);
  ResetCode; EmitAsmX64(['lock xchg [@glob], eax', 4096]);
  AssertBytes('lock xchg [@glob],eax', [$F0,$87,$04,$25,$00,$00,$00,$00]);
  if (GlobFixCount <> 1) or (GlobFix[0].BSSoff <> 4096) then Error('lock-xchg glob reloc failed');
  ResetCode; EmitAsmX64(['mov dword [@glob], 0', 4096]);
  AssertBytes('mov dword [@glob],0', [$C7,$04,$25,$00,$00,$00,$00,$00,$00,$00,$00]);
  if (GlobFixCount <> 1) or (GlobFix[0].BSSoff <> 4096) then Error('mov-abs glob reloc failed');

  { --- general ALU reg,[@glob/@data] / [@glob/@data],reg (new form added for
    the ir_codegen.inc EmitAsmX64 migration) --- }
  ResetCode; EmitAsmX64(['sub rax, [@glob]', 4096]);
  AssertBytes('sub rax,[@glob]', [$48,$2B,$04,$25,$00,$00,$00,$00]);
  ResetCode; EmitAsmX64(['add [@glob], rcx', 8192]);
  AssertBytes('add [@glob],rcx', [$48,$01,$0C,$25,$00,$00,$00,$00]);
  ResetCode; EmitAsmX64(['cmp rdx, [@glob]', 12288]);
  AssertBytes('cmp rdx,[@glob]', [$48,$3B,$14,$25,$00,$00,$00,$00]);

  { --- push/pop, all registers (regression for bug-emitasmx64-heap-helpers-
    oom-selfhost: the REX.B-forcing path for r8-r15 was never covered here) ---
    Expected bytes cross-checked against llvm-mc-18 -triple=x86_64 -x86-asm-
    syntax=intel -show-encoding. }
  ResetCode; EmitAsmX64('push rax'); AssertBytes('push rax', [$50]);
  ResetCode; EmitAsmX64('push rsi'); AssertBytes('push rsi', [$56]);
  ResetCode; EmitAsmX64('push rdi'); AssertBytes('push rdi', [$57]);
  ResetCode; EmitAsmX64('push r8');  AssertBytes('push r8', [$41,$50]);
  ResetCode; EmitAsmX64('push r11'); AssertBytes('push r11', [$41,$53]);
  ResetCode; EmitAsmX64('push r15'); AssertBytes('push r15', [$41,$57]);
  ResetCode; EmitAsmX64('pop rax');  AssertBytes('pop rax', [$58]);
  ResetCode; EmitAsmX64('pop rsi');  AssertBytes('pop rsi', [$5E]);
  ResetCode; EmitAsmX64('pop r8');   AssertBytes('pop r8', [$41,$58]);
  ResetCode; EmitAsmX64('pop r11');  AssertBytes('pop r11', [$41,$5B]);
  ResetCode; EmitAsmX64('pop r15');  AssertBytes('pop r15', [$41,$5F]);

  { --- inc/dec [mem] (new form added for the ir_codegen.inc EmitAsmX64
    migration) --- }
  ResetCode; EmitAsmX64('inc qword [rax-16]');
  AssertBytes('inc qword[rax-16]', [$48,$FF,$40,$F0]);
  ResetCode; EmitAsmX64('dec qword [rax-16]');
  AssertBytes('dec qword[rax-16]', [$48,$FF,$48,$F0]);
  ResetCode; EmitAsmX64('lock dec qword [rax-16]');
  AssertBytes('lock dec qword[rax-16]', [$F0,$48,$FF,$48,$F0]);
  ResetCode; EmitAsmX64('inc byte [rax-16]');
  AssertBytes('inc byte[rax-16]', [$FE,$40,$F0]);
  ResetCode; EmitAsmX64('dec dword [rax-16]');
  AssertBytes('dec dword[rax-16]', [$FF,$48,$F0]);
  ResetCode; EmitAsmX64('inc qword [rax+16]');
  AssertBytes('inc qword[rax+16]', [$48,$FF,$40,$10]);
  ResetCode; EmitAsmX64('inc qword [r8-16]');
  AssertBytes('inc qword[r8-16]', [$49,$FF,$40,$F0]);
  ResetCode; EmitAsmX64('inc qword [r12-16]');
  AssertBytes('inc qword[r12-16]', [$49,$FF,$44,$24,$F0]);
  ResetCode; EmitAsmX64('inc qword [rbp-16]');
  AssertBytes('inc qword[rbp-16]', [$48,$FF,$45,$F0]);
  ResetCode; EmitAsmX64(['inc qword [@glob]', 4096]);
  AssertBytes('inc qword[@glob]', [$48,$FF,$04,$25,$00,$00,$00,$00]);
  ResetCode; EmitAsmX64(['dec dword [@glob]', 8192]);
  AssertBytes('dec dword[@glob]', [$FF,$0C,$25,$00,$00,$00,$00]);

  { --- mov [mem], imm (new form added for the EmitVariantClear/Retain
    migration; verified against llvm-mc) --- }
  ResetCode; EmitAsmX64(['mov qword [rax], %', 0]);
  AssertBytes('mov qword[rax],0', [$48,$C7,$00,$00,$00,$00,$00]);
  ResetCode; EmitAsmX64(['mov qword [rax+8], %', 0]);
  AssertBytes('mov qword[rax+8],0', [$48,$C7,$40,$08,$00,$00,$00,$00]);
  ResetCode; EmitAsmX64(['mov qword [rax-16], %', 5]);
  AssertBytes('mov qword[rax-16],5', [$48,$C7,$40,$F0,$05,$00,$00,$00]);
  ResetCode; EmitAsmX64(['mov dword [rbx], %', 5]);
  AssertBytes('mov dword[rbx],5', [$C7,$03,$05,$00,$00,$00]);
  ResetCode; EmitAsmX64(['mov byte [rdi], %', 1]);
  AssertBytes('mov byte[rdi],1', [$C6,$07,$01]);
  ResetCode; EmitAsmX64(['mov qword [r12], %', 0]);
  AssertBytes('mov qword[r12],0', [$49,$C7,$04,$24,$00,$00,$00,$00]);
  ResetCode; EmitAsmX64(['mov qword [r13], %', 0]);
  AssertBytes('mov qword[r13],0', [$49,$C7,$45,$00,$00,$00,$00,$00]);

  { --- mov reg64, imm: compact 0xC7 (sign-extended imm32) when the value
    round-trips, movabs (0xB8+r, full imm64) only when it doesn't -- verified
    against llvm-mc. New selection logic added for the ir_codegen.inc
    EmitAsmX64 migration (avoids a silent size regression vs. the original
    hand-picked-compact-form raw EmitB sequences it replaces). }
  ResetCode; EmitAsmX64(['mov rax, %', 1]);
  AssertBytes('mov rax,1', [$48,$C7,$C0,$01,$00,$00,$00]);
  ResetCode; EmitAsmX64(['mov rsi, %', 8]);
  AssertBytes('mov rsi,8', [$48,$C7,$C6,$08,$00,$00,$00]);
  ResetCode; EmitAsmX64(['mov rcx, %', -1]);
  AssertBytes('mov rcx,-1', [$48,$C7,$C1,$FF,$FF,$FF,$FF]);
  ResetCode; EmitAsmX64(['mov rdx, %', 2147483647]);
  AssertBytes('mov rdx,2147483647', [$48,$C7,$C2,$FF,$FF,$FF,$7F]);
  ResetCode; EmitAsmX64(['mov r8, %', -2147483648]);
  AssertBytes('mov r8,-2147483648', [$49,$C7,$C0,$00,$00,$00,$80]);
  ResetCode; EmitAsmX64(['mov r9, %', Int64(2147483648)]);
  AssertBytes('mov r9,2147483648 (movabs)', [$49,$B9,$00,$00,$00,$80,$00,$00,$00,$00]);
  ResetCode; EmitAsmX64(['mov r10, %', Int64(4294967296)]);
  AssertBytes('mov r10,4294967296 (movabs)', [$49,$BA,$00,$00,$00,$00,$01,$00,$00,$00]);

  { --- forward-label jump (the `.done` idiom used by EmitDynArrayRetainLocked
    etc): EmitAsmX64 always emits the near/rel32 form for a same-call forward
    reference, unlike an optimizing assembler (llvm-mc picks the short rel8
    form here since it resolves sizes in a later pass) -- both are correct,
    just different sizes; pin the near form explicitly so a future change
    doesn't silently flip it. }
  ResetCode; EmitAsmX64(['test rax, rax', 'jz .done', 'inc qword [rax-16]', '.done:']);
  AssertBytes('test/jz .done/inc/.done:',
    [$48,$85,$C0, $0F,$84,$04,$00,$00,$00, $48,$FF,$40,$F0]);

  { --- the 2026-11-11 additions, each pinned against GNU as --- }
  { scope labels: a forward jump in one call, its target in a later one, Pascal
    between them }
  ResetCode;
  AsmScopeBegin;
  EmitAsmX64(['test rax, rax', 'jz skip']);
  EmitAsmX64(['inc rax']);
  EmitAsmX64(['skip:', 'ret']);
  AsmScopeEnd;
  AssertBytes('scope forward jump',
    [$48,$85,$C0, $0F,$84,$03,$00,$00,$00, $48,$FF,$C0, $C3]);
  { short forward, and a back edge across calls }
  ResetCode;
  AsmScopeBegin;
  EmitAsmX64(['top:', 'dec ecx', 'jz short out']);
  EmitAsmX64(['jmp top', 'out:']);
  AsmScopeEnd;
  AssertBytes('scope short fwd + back edge', [$FF,$C9, $74,$02, $EB,$FA]);
  { near forces rel32 on a back edge that would fit rel8 }
  ResetCode;
  AsmScopeBegin;
  EmitAsmX64(['top:', 'jmp near top']);
  AsmScopeEnd;
  AssertBytes('jmp near back', [$E9,$FB,$FF,$FF,$FF]);
  { nested scopes do not see each other's labels }
  ResetCode;
  AsmScopeBegin;
  EmitAsmX64(['jmp short done']);
  AsmScopeBegin; EmitAsmX64(['done:', 'nop']); AsmScopeEnd;
  EmitAsmX64(['done:']);
  AsmScopeEnd;
  AssertBytes('nested scope', [$EB,$01, $90]);
  { @code: rel32 to a known position }
  ResetCode; EmitAsmX64(['nop', 'jmp @code', 0]);
  AssertBytes('jmp @code', [$90, $E9,$FA,$FF,$FF,$FF]);
  ResetCode; EmitAsmX64(['call @code', 0]);
  AssertBytes('call @code', [$E8,$FB,$FF,$FF,$FF]);
  ResetCode; EmitAsmX64(['jne @code', 0]);
  AssertBytes('jne @code', [$0F,$85,$FA,$FF,$FF,$FF]);
  { segment override and absolute disp32 }
  ResetCode; EmitAsmX64(['mov rax, gs:[%]', 16]);
  AssertBytes('mov rax, gs:[16]', [$65,$48,$8B,$04,$25,$10,$00,$00,$00]);
  ResetCode; EmitAsmX64(['mov gs:[%], r12', 8]);
  AssertBytes('mov gs:[8], r12', [$65,$4C,$89,$24,$25,$08,$00,$00,$00]);
  { register holes, as operand and as memory base }
  ResetCode; EmitAsmX64(['shl %r64, %', 9, 3]);
  AssertBytes('shl r9, 3', [$49,$C1,$E1,$03]);
  ResetCode; EmitAsmX64(['mov %r32, [%r64+8]', 2, 13]);
  AssertBytes('mov edx, [r13+8]', [$41,$8B,$55,$08]);
  { [base+index*scale+disp] }
  ResetCode; EmitAsmX64('mov byte [rsi+rdx], 0');
  AssertBytes('mov byte [rsi+rdx], 0', [$C6,$04,$16,$00]);
  ResetCode; EmitAsmX64('mov rax, [rbx+r9*8+16]');
  AssertBytes('mov rax, [rbx+r9*8+16]', [$4A,$8B,$44,$CB,$10]);
  ResetCode; EmitAsmX64('cmp byte [rsi+rcx], 0');
  AssertBytes('cmp byte [rsi+rcx], 0', [$80,$3C,$0E,$00]);
  { the index state does not leak into the next line }
  ResetCode; EmitAsmX64(['lea rax, [rdi+rcx*4]', 'mov rax, [rdi]']);
  AssertBytes('index reset', [$48,$8D,$04,$8F, $48,$8B,$07]);
  { indirect jmp, movsxd, 3-operand imul, imul r,[m], literals }
  ResetCode; EmitAsmX64('jmp qword [rdi+56]');
  AssertBytes('jmp [rdi+56]', [$FF,$67,$38]);
  ResetCode; EmitAsmX64('jmp rax');
  AssertBytes('jmp rax', [$FF,$E0]);
  ResetCode; EmitAsmX64('movsxd rax, esi');
  AssertBytes('movsxd rax, esi', [$48,$63,$C6]);
  ResetCode; EmitAsmX64('movsxd rdx, dword [rcx+12]');
  AssertBytes('movsxd rdx, [rcx+12]', [$48,$63,$51,$0C]);
  ResetCode; EmitAsmX64('imul rbx, rbx, 10');
  AssertBytes('imul rbx, rbx, 10', [$48,$6B,$DB,$0A]);
  ResetCode; EmitAsmX64('imul rcx, rcx, 1000');
  AssertBytes('imul rcx, rcx, 1000', [$48,$69,$C9,$E8,$03,$00,$00]);
  ResetCode; EmitAsmX64('imul rax, [rsi+8]');
  AssertBytes('imul rax, [rsi+8]', [$48,$0F,$AF,$46,$08]);
  ResetCode; EmitAsmX64('and eax, ~0x6000');
  AssertBytes('and eax, ~0x6000', [$25,$FF,$9F,$FF,$FF]);   { eax accumulator form, as GNU as }
  ResetCode; EmitAsmX64('cmp al, ''0''');
  AssertBytes('cmp al, ''0''', [$3C,$30]);   { accumulator form, as GNU as }
  { accumulator forms (bytes from GNU as): rax with an imm32 / al with imm8;
    an imm8 on rax keeps 83 /ext, a non-rax register keeps 81 /ext. }
  ResetCode; EmitAsmX64(['and rax, %', $7FFFFFFF]);
  AssertBytes('and rax,7fffffff', [$48,$25,$FF,$FF,$FF,$7F]);
  ResetCode; EmitAsmX64(['add eax, %', 1000]);
  AssertBytes('add eax,1000', [$05,$E8,$03,$00,$00]);
  ResetCode; EmitAsmX64(['sub rax, %', 5]);
  AssertBytes('sub rax,5', [$48,$83,$E8,$05]);
  ResetCode; EmitAsmX64(['cmp ax, %', 1000]);
  AssertBytes('cmp ax,1000', [$66,$3D,$E8,$03]);
  ResetCode; EmitAsmX64(['xor rax, %', -1000]);
  AssertBytes('xor rax,-1000', [$48,$35,$18,$FC,$FF,$FF]);
  ResetCode; EmitAsmX64(['and rcx, %', $7FFFFFFF]);
  AssertBytes('and rcx,7fffffff', [$48,$81,$E1,$FF,$FF,$FF,$7F]);
  ResetCode; EmitAsmX64(['cld', 'rep stosq', 'rep movsq']);
  AssertBytes('cld/rep stosq/rep movsq', [$FC, $F3,$48,$AB, $F3,$48,$A5]);

  ResetCode; EmitAsmX64(['repe cmpsb', 'repne scasb']);
  AssertBytes('repe cmpsb/repne scasb', [$F3,$A6, $F2,$AE]);
  { a strlen scan with call-local short labels, as it replaced `je +5` /
    `jmp -11` in three places }
  ResetCode; EmitAsmX64(['.scan:', 'cmp byte [rsi+rcx], 0', 'je short .found',
                         'inc rcx', 'jmp short .scan', '.found:']);
  AssertBytes('strlen scan', [$80,$3C,$0E,$00, $74,$05, $48,$FF,$C1, $EB,$F5]);

  writeln('ALL X64 ASM EMIT TESTS PASSED');
end.
