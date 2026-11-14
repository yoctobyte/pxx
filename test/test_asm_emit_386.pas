program test_asm_emit_386;
{$mode objfpc}{$H+}

{ Standalone oracle harness for the i386 text assembler (asmtext_386.inc).
  It runs the SHIPPED parser and encoder: the same environment as
  test_asm_emit_x64.pas (asmregs.inc, x64enc.inc, asmtext.inc) with
  asmtext_386.inc on top, so AsmTextOperand, EncModRMMem and the scope labels
  under test are the ones the compiler runs. Until 2026-11-12 this file carried
  its own copies of the operand parser and ModRM encoder, which had drifted
  (no index register, no accumulator forms) from what the compiler uses.
  Expected bytes are GNU as --32 (Intel syntax). }

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

{ emit.inc's i386 kernel entry, which asmtext_386.inc's `int 128` calls. }
procedure EmitInt80;
begin
  EmitB($CD); EmitB($80);
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
  EmitI32(0);   { i386 data refs are absolute 4-byte }
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

{ The TLS block's segment-override byte (defs.inc). gs ($65) on every target
  this harness models; only --os=openbsd answers fs ($64), and the harness
  never selects a kernel. }
function TlsSegPrefix: Integer;
begin
  Result := $65;
end;

function TlsSegDispBias: Integer;   { 0: no --os=openbsd --rtl-libc in the harness }
begin
  Result := 0;
end;

{ --os=windows reaches the TLS block rip-relative instead of through gs
  (defs.inc); the harness never selects a kernel, so never. }
function TlsSegAbsolute: Boolean;
begin
  Result := False;
end;

const BSS_TLS_MAIN = 0;   { only read when TlsSegAbsolute }

{$include ../compiler/rel8.inc}   { CheckRel8: the assembler's short-jump range check }
{$include ../compiler/x64enc.inc}
{$include ../compiler/asmtext.inc}
{ Mock inline-asm line pool. The real definitions are in compiler/defs.inc; the
  emitter's Asm<arch>ProcessInlineLine REPLAYS a parse-time-captured line from
  this pool, and nothing in this harness captures one — so an empty pool is the
  honest mock, not a stub with fake contents. Added 2026-08-21: the emitter grew
  that entry point after this harness was written, and the harness stopped
  compiling with `undefined variable (InlineAsmLineHoleN)` — silently, because
  no build rule ran it (chore-a-sweep-the-unwired-tests-into-the-suite). }
const
  MOCK_INLINE_ASM_LINES = 4;
  MOCK_INLINE_ASM_HOLES = 8;
var
  InlineAsmLine: array[0..MOCK_INLINE_ASM_LINES-1] of AnsiString;
  InlineAsmLineHole0: array[0..MOCK_INLINE_ASM_LINES-1] of Integer;
  InlineAsmLineHoleN: array[0..MOCK_INLINE_ASM_LINES-1] of Integer;
  InlineAsmHoleVal: array[0..MOCK_INLINE_ASM_HOLES-1] of Int64;

{$include ../compiler/asmtext_386.inc}

{ Resolves x64enc.inc's `AsmRecordGlobalFixup` forward decl (the real body
  lives in compiler/asmenc.inc, not included here) — never reached since
  EncToAsmBuffer stays False in this harness. }
procedure AsmRecordGlobalFixup(bssOff: Integer); begin EmitGlobRef(bssOff); end;

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

  { ===== extended instruction families (oracle: llvm-mc-18 -triple=i386) ===== }

  { test }
  ResetCode; EmitAsm386('test ebx, ebx'); AssertBytes('test ebx,ebx', [$85,$DB]);
  ResetCode; EmitAsm386('test ebx, 1'); AssertBytes('test ebx,1', [$F7,$C3,$01,$00,$00,$00]);
  ResetCode; EmitAsm386('test byte [edi], 1'); AssertBytes('test byte[edi],1', [$F6,$07,$01]);
  ResetCode; EmitAsm386('test ecx, [esi]'); AssertBytes('test ecx,[esi]', [$85,$0E]);

  { unary F6/F7 group }
  ResetCode; EmitAsm386('not eax');  AssertBytes('not eax', [$F7,$D0]);
  ResetCode; EmitAsm386('neg ebx');  AssertBytes('neg ebx', [$F7,$DB]);
  ResetCode; EmitAsm386('mul ecx');  AssertBytes('mul ecx', [$F7,$E1]);
  ResetCode; EmitAsm386('imul ecx'); AssertBytes('imul ecx', [$F7,$E9]);
  ResetCode; EmitAsm386('idiv ecx'); AssertBytes('idiv ecx', [$F7,$F9]);
  ResetCode; EmitAsm386('imul eax, ecx'); AssertBytes('imul eax,ecx', [$0F,$AF,$C1]);

  { shifts }
  ResetCode; EmitAsm386('shl eax, 4');  AssertBytes('shl eax,4', [$C1,$E0,$04]);
  ResetCode; EmitAsm386('shr ebx, 1');  AssertBytes('shr ebx,1', [$D1,$EB]);
  ResetCode; EmitAsm386('sar edx, 31'); AssertBytes('sar edx,31', [$C1,$FA,$1F]);
  ResetCode; EmitAsm386('shl eax, cl'); AssertBytes('shl eax,cl', [$D3,$E0]);

  { movzx / movsx }
  ResetCode; EmitAsm386('movzx eax, bl'); AssertBytes('movzx eax,bl', [$0F,$B6,$C3]);
  ResetCode; EmitAsm386('movzx ecx, byte [ebp - 8]'); AssertBytes('movzx ecx,byte[ebp-8]', [$0F,$B6,$4D,$F8]);
  ResetCode; EmitAsm386('movsx edx, byte [ebp - 4]'); AssertBytes('movsx edx,byte[ebp-4]', [$0F,$BE,$55,$FC]);
  ResetCode; EmitAsm386('movzx eax, word [esi]'); AssertBytes('movzx eax,word[esi]', [$0F,$B7,$06]);

  { setcc }
  ResetCode; EmitAsm386('sete al');  AssertBytes('sete al', [$0F,$94,$C0]);
  ResetCode; EmitAsm386('setne bl'); AssertBytes('setne bl', [$0F,$95,$C3]);
  ResetCode; EmitAsm386('setb cl');  AssertBytes('setb cl', [$0F,$92,$C1]);
  ResetCode; EmitAsm386('setl dl');  AssertBytes('setl dl', [$0F,$9C,$C2]);

  { call reg, cdq, string ops }
  ResetCode; EmitAsm386('call eax'); AssertBytes('call eax', [$FF,$D0]);
  ResetCode; EmitAsm386('cdq');      AssertBytes('cdq', [$99]);
  ResetCode; EmitAsm386('movsb');    AssertBytes('movsb', [$A4]);
  ResetCode; EmitAsm386('stosb');    AssertBytes('stosb', [$AA]);
  ResetCode; EmitAsm386('rep movsb'); AssertBytes('rep movsb', [$F3,$A4]);
  ResetCode; EmitAsm386('rep stosb'); AssertBytes('rep stosb', [$F3,$AA]);

  { ALU reg,[mem] and [mem],reg }
  ResetCode; EmitAsm386('add eax, [ebp - 8]'); AssertBytes('add eax,[ebp-8]', [$03,$45,$F8]);
  ResetCode; EmitAsm386('sub [ebp - 8], ecx'); AssertBytes('sub [ebp-8],ecx', [$29,$4D,$F8]);
  ResetCode; EmitAsm386('cmp eax, [esi]'); AssertBytes('cmp eax,[esi]', [$3B,$06]);
  ResetCode; EmitAsm386('xor [edi], eax'); AssertBytes('xor [edi],eax', [$31,$07]);

  { SSE2 scalar float }
  ResetCode; EmitAsm386('movsd xmm0, xmm1'); AssertBytes('movsd xmm0,xmm1', [$F2,$0F,$10,$C1]);
  ResetCode; EmitAsm386('movss xmm0, xmm1'); AssertBytes('movss xmm0,xmm1', [$F3,$0F,$10,$C1]);
  ResetCode; EmitAsm386('movss xmm0, [ebp - 8]'); AssertBytes('movss xmm0,[ebp-8]', [$F3,$0F,$10,$45,$F8]);
  ResetCode; EmitAsm386('movss [ebp - 8], xmm0'); AssertBytes('movss [ebp-8],xmm0', [$F3,$0F,$11,$45,$F8]);
  ResetCode; EmitAsm386('addsd xmm0, xmm1'); AssertBytes('addsd xmm0,xmm1', [$F2,$0F,$58,$C1]);
  ResetCode; EmitAsm386('cvtsi2sd xmm0, eax'); AssertBytes('cvtsi2sd xmm0,eax', [$F2,$0F,$2A,$C0]);
  ResetCode; EmitAsm386('cvttsd2si eax, xmm0'); AssertBytes('cvttsd2si eax,xmm0', [$F2,$0F,$2C,$C0]);
  ResetCode; EmitAsm386('cvtsd2ss xmm0, xmm1'); AssertBytes('cvtsd2ss xmm0,xmm1', [$F2,$0F,$5A,$C1]);
  ResetCode; EmitAsm386('cvtss2sd xmm0, xmm1'); AssertBytes('cvtss2sd xmm0,xmm1', [$F3,$0F,$5A,$C1]);
  ResetCode; EmitAsm386('comisd xmm0, xmm1'); AssertBytes('comisd xmm0,xmm1', [$66,$0F,$2F,$C1]);
  ResetCode; EmitAsm386('pxor xmm0, xmm0'); AssertBytes('pxor xmm0,xmm0', [$66,$0F,$EF,$C0]);
  ResetCode; EmitAsm386('xorpd xmm0, xmm1'); AssertBytes('xorpd xmm0,xmm1', [$66,$0F,$57,$C1]);

  { adc / sbb }
  ResetCode; EmitAsm386('adc edx, 0'); AssertBytes('adc edx,0', [$83,$D2,$00]);
  ResetCode; EmitAsm386('adc eax, ebx'); AssertBytes('adc eax,ebx', [$11,$D8]);
  ResetCode; EmitAsm386('sbb eax, ebx'); AssertBytes('sbb eax,ebx', [$19,$D8]);
  ResetCode; EmitAsm386('sbb edi, [esp + 4]'); AssertBytes('sbb edi,[esp+4]', [$1B,$7C,$24,$04]);

  { jump forms shared with EmitAsmX64: short/near, constant rel8, @code, and
    scope labels that live across calls (asmscope.inc) }
  ResetCode; EmitAsm386(['jz short l', 'nop', 'l:']); AssertBytes('jz short fwd', [$74,$01,$90]);
  ResetCode; EmitAsm386(['jmp short l', 'l:']); AssertBytes('jmp short fwd', [$EB,$00]);
  ResetCode; EmitAsm386(['jz l', 'l:']); AssertBytes('jz near fwd (default)', [$0F,$84,0,0,0,0]);
  ResetCode; EmitAsm386(['l:', 'nop', 'jmp near l']); AssertBytes('jmp near back', [$90,$E9,$FA,$FF,$FF,$FF]);
  ResetCode; EmitAsm386(['l:', 'nop', 'jnz l']); AssertBytes('jnz back short', [$90,$75,$FD]);
  ResetCode; EmitAsm386('jnz +5'); AssertBytes('jnz +5', [$75,$05]);
  ResetCode; EmitAsm386('jmp -3'); AssertBytes('jmp -3', [$EB,$FD]);
  ResetCode; EmitB($90); EmitAsm386(['jmp @code', 0]); AssertBytes('jmp @code', [$90,$E9,$FA,$FF,$FF,$FF]);
  ResetCode; EmitB($90); EmitAsm386(['call @code', 0]); AssertBytes('call @code', [$90,$E8,$FA,$FF,$FF,$FF]);
  ResetCode; EmitB($90); EmitAsm386(['jc short @code', 0]); AssertBytes('jc short @code', [$90,$72,$FD]);
  ResetCode; AsmScopeBegin; EmitAsm386('jz short done'); EmitB($90); EmitAsm386('done:'); AsmScopeEnd;
  AssertBytes('scope label across calls', [$74,$01,$90]);
  ResetCode; AsmScopeBegin; EmitAsm386('top:'); EmitB($90); EmitAsm386('jmp near top'); AsmScopeEnd;
  AssertBytes('scope back edge', [$90,$E9,$FA,$FF,$FF,$FF]);
  ResetCode; AsmScopeBegin; EmitAsm386('jmp short x'); AsmScopeBegin; EmitAsm386(['jmp short x', 'x:']); AsmScopeEnd;
  EmitB($90); EmitAsm386('x:'); AsmScopeEnd;
  AssertBytes('nested scope', [$EB,$03, $EB,$00, $90]);
  { the inline-asm replay keeps a dotless label local even inside a scope }
  ResetCode; AsmScopeBegin; Asm386BlockBegin; Asm386ProcessLine('jmp short q', [], 0); Asm386ProcessLine('q:', [], 0);
  Asm386BlockResolve; AsmScopeEnd; AssertBytes('inline replay label stays local', [$EB,$00]);


  { 2026-11-12 additions (raw i386 bytes -> EmitAsm386), bytes from GNU as --32:
    push imm, x87 memory forms, cld/std/frndint, imul r,[m], xchg, rotates,
    movd xmm<->r32, shld/shrd, 32-bit immediates read modulo 2^32, index regs }
  ResetCode; EmitAsm386('push 1'); AssertBytes('push 1', [$6A, $01]);
  ResetCode; EmitAsm386('push -1'); AssertBytes('push -1', [$6A, $FF]);
  ResetCode; EmitAsm386('push 0x41f00000'); AssertBytes('push 0x41f00000', [$68, $00, $00, $F0, $41]);
  ResetCode; EmitAsm386('push 200'); AssertBytes('push 200', [$68, $C8, $00, $00, $00]);
  ResetCode; EmitAsm386('fld qword [esp]'); AssertBytes('fld qword [esp]', [$DD, $04, $24]);
  ResetCode; EmitAsm386('fstp qword [esp]'); AssertBytes('fstp qword [esp]', [$DD, $1C, $24]);
  ResetCode; EmitAsm386('fst dword [ebp-8]'); AssertBytes('fst dword [ebp-8]', [$D9, $55, $F8]);
  ResetCode; EmitAsm386('fld dword [eax]'); AssertBytes('fld dword [eax]', [$D9, $00]);
  ResetCode; EmitAsm386('fild qword [esp]'); AssertBytes('fild qword [esp]', [$DF, $2C, $24]);
  ResetCode; EmitAsm386('fild dword [esp+4]'); AssertBytes('fild dword [esp+4]', [$DB, $44, $24, $04]);
  ResetCode; EmitAsm386('fistp qword [esp]'); AssertBytes('fistp qword [esp]', [$DF, $3C, $24]);
  ResetCode; EmitAsm386('fistp dword [esp]'); AssertBytes('fistp dword [esp]', [$DB, $1C, $24]);
  ResetCode; EmitAsm386('fisttp qword [esp]'); AssertBytes('fisttp qword [esp]', [$DD, $0C, $24]);
  ResetCode; EmitAsm386('fisttp dword [esp]'); AssertBytes('fisttp dword [esp]', [$DB, $0C, $24]);
  ResetCode; EmitAsm386('fldcw word [esp+8]'); AssertBytes('fldcw word [esp+8]', [$D9, $6C, $24, $08]);
  ResetCode; EmitAsm386('fnstcw word [esp+10]'); AssertBytes('fnstcw word [esp+10]', [$D9, $7C, $24, $0A]);
  ResetCode; EmitAsm386('frndint'); AssertBytes('frndint', [$D9, $FC]);
  ResetCode; EmitAsm386('cld'); AssertBytes('cld', [$FC]);
  ResetCode; EmitAsm386('std'); AssertBytes('std', [$FD]);
  ResetCode; EmitAsm386('imul eax, [esp+4]'); AssertBytes('imul eax, [esp+4]', [$0F, $AF, $44, $24, $04]);
  ResetCode; EmitAsm386('imul ecx, [esp]'); AssertBytes('imul ecx, [esp]', [$0F, $AF, $0C, $24]);
  ResetCode; EmitAsm386('xchg edx, eax'); AssertBytes('xchg edx, eax', [$92]);
  ResetCode; EmitAsm386('xchg eax, ecx'); AssertBytes('xchg eax, ecx', [$91]);
  ResetCode; EmitAsm386('xchg ebx, ecx'); AssertBytes('xchg ebx, ecx', [$87, $CB]);
  ResetCode; EmitAsm386('xchg [ecx], eax'); AssertBytes('xchg [ecx], eax', [$87, $01]);
  ResetCode; EmitAsm386('xchg eax, [ecx]'); AssertBytes('xchg eax, [ecx]', [$87, $01]);
  ResetCode; EmitAsm386('rcl esi, 1'); AssertBytes('rcl esi, 1', [$D1, $D6]);
  ResetCode; EmitAsm386('rcr edx, cl'); AssertBytes('rcr edx, cl', [$D3, $DA]);
  ResetCode; EmitAsm386('rol eax, 3'); AssertBytes('rol eax, 3', [$C1, $C0, $03]);
  ResetCode; EmitAsm386('ror ebx, 1'); AssertBytes('ror ebx, 1', [$D1, $CB]);
  ResetCode; EmitAsm386('movd xmm0, eax'); AssertBytes('movd xmm0, eax', [$66, $0F, $6E, $C0]);
  ResetCode; EmitAsm386('movd eax, xmm1'); AssertBytes('movd eax, xmm1', [$66, $0F, $7E, $C8]);
  ResetCode; EmitAsm386('shld edx, eax, cl'); AssertBytes('shld edx, eax, cl', [$0F, $A5, $C2]);
  ResetCode; EmitAsm386('shrd eax, edx, cl'); AssertBytes('shrd eax, edx, cl', [$0F, $AD, $D0]);
  ResetCode; EmitAsm386('shld edx, eax, 4'); AssertBytes('shld edx, eax, 4', [$0F, $A4, $C2, $04]);
  ResetCode; EmitAsm386('shrd eax, edx, 31'); AssertBytes('shrd eax, edx, 31', [$0F, $AC, $D0, $1F]);
  ResetCode; EmitAsm386('and eax, 0xfffffff0'); AssertBytes('and eax, 0xfffffff0', [$83, $E0, $F0]);
  ResetCode; EmitAsm386('and esp, 0xfffffff0'); AssertBytes('and esp, 0xfffffff0', [$83, $E4, $F0]);
  ResetCode; EmitAsm386('cmp ecx, 0x80000000'); AssertBytes('cmp ecx, 0x80000000', [$81, $F9, $00, $00, $00, $80]);
  ResetCode; EmitAsm386('cmp byte [esi+ecx], 0'); AssertBytes('cmp byte [esi+ecx], 0', [$80, $3C, $0E, $00]);
  ResetCode; EmitAsm386('movzx edx, byte [ecx+edx]'); AssertBytes('movzx edx, byte [ecx+edx]', [$0F, $B6, $14, $11]);
  { an indexed operand must not leak its index into the next line
    (EncMemIndex was never reset on the i386 path) }
  ResetCode; EmitAsm386(['movzx edx, byte [ecx+edx]', 'mov ecx, [ebp+8]']);
  AssertBytes('index does not leak', [$0F,$B6,$14,$11, $8B,$4D,$08]);
  ResetCode; EmitAsm386('cmp byte [esi+ecx], 0'); EmitAsm386('mov eax, [ebp+8]');
  AssertBytes('index does not leak across calls', [$80,$3C,$0E,$00, $8B,$45,$08]);

  writeln('ALL I386 ASM EMIT TESTS PASSED');

end.
