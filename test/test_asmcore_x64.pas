program test_asmcore_x64;
{ lib/asmcore first-slice smoke test: mov reg,imm / add reg,reg / ret.
  Expected bytes cross-checked against host `as`+`objdump`
  (.intel_syntax noprefix) 2026-06-30:
    mov eax, 5      -> b8 05 00 00 00
    add eax, ebx    -> 01 d8
    movabs rax, 5   -> 48 b8 05 00 00 00 00 00 00 00   (NOT plain `mov rax,5`,
      which GNU as shortens to the c7 /0 imm32-sign-extend form instead —
      asmcore implements the universal B8+rd imm64 form, which is what
      `movabs` forces; both are valid, only one is what this encoder emits)
    ret             -> c3

  Workaround note: `Check(name, buf, [bytes...])` with an inline array
  constructor as the 3rd (statement-level) arg hit a real compiler bug —
  `error: too many array constant elements ()` — not the already-filed
  bug-open-array-ctor-statement-call (that one's symptom is "by-reference
  argument must be a variable ()"; this is a different code path, likely
  triggered because the preceding `const buf: TAsmByteBuf` param itself
  contains a dynamic-array field). Filed as
  devdocs/progress/backlog/bug-array-ctor-statement-arg-after-dynarray-record-param.md.
  Worked around below by binding each expected-byte literal to a local
  typed const array first, then passing the named const — sidesteps the
  array-constructor-as-statement-arg path entirely. }
uses asmcore_base, asmcore_x64;

var
  failed: Boolean;

procedure Check(const name: AnsiString; const buf: TAsmByteBuf; const expect: array of Byte);
var i: Integer; ok: Boolean;
begin
  ok := buf.Len = Length(expect);
  if ok then
    for i := 0 to buf.Len - 1 do
      if buf.Bytes[i] <> expect[i] then ok := False;
  if ok then
    writeln('OK: ', name)
  else
  begin
    writeln('FAIL: ', name);
    failed := True;
  end;
end;

const
  expectMovEax5: array[0..4] of Byte = ($B8, $05, $00, $00, $00);
  expectAddEaxEbx: array[0..1] of Byte = ($01, $D8);
  expectMovRax5: array[0..9] of Byte = ($48, $B8, $05, $00, $00, $00, $00, $00, $00, $00);
  expectRet: array[0..0] of Byte = ($C3);

var
  buf: TAsmByteBuf;
  patches: TAsmPatchList;
  instr: TAsmInstr;
begin
  failed := False;

  { mov eax, 5 }
  BufInit(buf); PatchListInit(patches);
  instr.Mnemonic := 'mov';
  instr.Operands[0] := RegOp(reg_rax, 4);
  instr.Operands[1] := ImmOp(5);
  instr.OperandCount := 2;
  if not AsmEncodeX64(instr, buf, patches) then writeln('encode error: ', AsmCoreLastError);
  Check('mov eax, 5', buf, expectMovEax5);

  { add eax, ebx }
  BufInit(buf); PatchListInit(patches);
  instr.Mnemonic := 'add';
  instr.Operands[0] := RegOp(reg_rax, 4);
  instr.Operands[1] := RegOp(reg_rbx, 4);
  instr.OperandCount := 2;
  if not AsmEncodeX64(instr, buf, patches) then writeln('encode error: ', AsmCoreLastError);
  Check('add eax, ebx', buf, expectAddEaxEbx);

  { mov rax, 5 -- the imm64 B8+rd form (movabs's encoding, see header) }
  BufInit(buf); PatchListInit(patches);
  instr.Mnemonic := 'mov';
  instr.Operands[0] := RegOp(reg_rax, 8);
  instr.Operands[1] := ImmOp(5);
  instr.OperandCount := 2;
  if not AsmEncodeX64(instr, buf, patches) then writeln('encode error: ', AsmCoreLastError);
  Check('mov rax, 5 (imm64)', buf, expectMovRax5);

  { ret }
  BufInit(buf); PatchListInit(patches);
  instr.Mnemonic := 'ret';
  instr.OperandCount := 0;
  if not AsmEncodeX64(instr, buf, patches) then writeln('encode error: ', AsmCoreLastError);
  Check('ret', buf, expectRet);

  { textual printer round-trip sanity (not byte-exact, just non-empty/plausible) }
  instr.Mnemonic := 'mov';
  instr.Operands[0] := RegOp(reg_rax, 4);
  instr.Operands[1] := ImmOp(5);
  instr.OperandCount := 2;
  writeln('print: ', AsmPrintX64(instr));

  if failed then Halt(1);
  writeln('all asmcore_x64 checks passed');
end.
