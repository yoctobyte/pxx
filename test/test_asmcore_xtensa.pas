program test_asmcore_xtensa;
{ lib/asmcore xtensa (LX6/LX7) encoder coverage test — the sixth and final
  asmcore target. Expected words cross-checked against raw bytes from
  `xtensa-lx106-elf-as --no-transform` (forces the 3-byte base forms, not
  the 2-byte "narrow"/density forms `as` otherwise prefers) +
  `objcopy -O binary` (NOT objdump's disassembly text, which renders the
  instruction as a number, MSB-first in the printed string — the opposite
  of the actual little-endian memory byte order; see asmcore_xtensa.pas's
  header comment). Field formulas are taken from this compiler's own
  existing, ESP-hardware-validated `compiler/xtensaenc.inc`, not
  re-derived from scratch. Also covers AsmPatchBranchXtensa, which —
  unlike aarch64/arm32/riscv32's resolvers — takes a raw byte delta, not a
  word count: xtensa instructions here are 3 bytes, so "divide by 4" isn't
  a meaningful unit. }
uses asmcore_base, asmcore_xtensa;

var
  checks, fails: Integer;

procedure Check(const desc: AnsiString; const instr: TAsmInstr; expected: Int64);
var buf: TAsmByteBuf; patches: TAsmPatchList; got: Int64;
begin
  Inc(checks);
  BufInit(buf); PatchListInit(patches);
  if not AsmEncodeXtensa(instr, buf, patches) then
  begin
    writeln('FAIL ', desc, ': encode error: ', AsmCoreLastErrorXtensa);
    Inc(fails);
    Exit;
  end;
  if buf.Len <> 3 then
  begin
    writeln('FAIL ', desc, ': expected 3 bytes, got ', buf.Len);
    Inc(fails);
    Exit;
  end;
  got := Int64(buf.Bytes[0]) or (Int64(buf.Bytes[1]) shl 8) or (Int64(buf.Bytes[2]) shl 16);
  if got <> expected then
  begin
    writeln('FAIL ', desc, ': got ', got, ' expected ', expected);
    Inc(fails);
  end;
end;

procedure CheckPatch(const desc: AnsiString; const mn: AnsiString; relBytes, expected: Int64; threeOp: Boolean);
var buf: TAsmByteBuf; patches: TAsmPatchList; instr: TAsmInstr; got: Int64;
begin
  Inc(checks);
  BufInit(buf); PatchListInit(patches);
  if threeOp then
  begin
    instr.Mnemonic := mn; instr.OperandCount := 3;
    instr.Operands[0] := RegOp(reg_a2, 4); instr.Operands[1] := RegOp(reg_a3, 4); instr.Operands[2] := PatchOp(3);
  end
  else
  begin
    instr.Mnemonic := mn; instr.OperandCount := 1; instr.Operands[0] := PatchOp(3);
  end;
  if not AsmEncodeXtensa(instr, buf, patches) then
  begin writeln('FAIL ', desc, ': encode error: ', AsmCoreLastErrorXtensa); Inc(fails); Exit; end;
  if not AsmPatchBranchXtensa(buf, patches.Items[0].Offset, mn, relBytes) then
  begin writeln('FAIL ', desc, ': patch error: ', AsmCoreLastErrorXtensa); Inc(fails); Exit; end;
  got := Int64(buf.Bytes[0]) or (Int64(buf.Bytes[1]) shl 8) or (Int64(buf.Bytes[2]) shl 16);
  if got <> expected then
  begin writeln('FAIL ', desc, ': got ', got, ' expected ', expected); Inc(fails); end;
end;

function I3(mn: AnsiString; a, b, c: TAsmOperand): TAsmInstr;
begin
  Result.Mnemonic := mn; Result.OperandCount := 3;
  Result.Operands[0] := a; Result.Operands[1] := b; Result.Operands[2] := c;
end;

function I2(mn: AnsiString; a, b: TAsmOperand): TAsmInstr;
begin
  Result.Mnemonic := mn; Result.OperandCount := 2;
  Result.Operands[0] := a; Result.Operands[1] := b;
end;

function I0(mn: AnsiString): TAsmInstr;
begin
  Result.Mnemonic := mn; Result.OperandCount := 0;
end;

var a1, a2, a3: TAsmOperand;
begin
  checks := 0; fails := 0;
  a1 := RegOp(reg_a1, 4); a2 := RegOp(reg_a2, 4); a3 := RegOp(reg_a3, 4);

  Check('add a1,a2,a3', I3('add', a1, a2, a3), $801230);
  Check('sub a1,a2,a3', I3('sub', a1, a2, a3), $c01230);
  Check('and a1,a2,a3', I3('and', a1, a2, a3), $101230);
  Check('or a1,a2,a3',  I3('or', a1, a2, a3), $201230);
  Check('xor a1,a2,a3', I3('xor', a1, a2, a3), $301230);
  Check('addi a1,a2,5', I3('addi', a1, a2, ImmOp(5)), $05c212);
  Check('movi a3,100',  I2('movi', a3, ImmOp(100)), $64a032);
  Check('movi a1,-5',   I2('movi', a1, ImmOp(-5)), $fbaf12);
  Check('l32i a1,a2,8', I2('l32i', a1, MemOp(reg_a2, 8)), $022212);
  Check('s32i a1,a2,8', I2('s32i', a1, MemOp(reg_a2, 8)), $026212);
  Check('mv a1,a2',     I2('mv', a1, a2), $201220);
  Check('ret',            I0('ret'), $000080);
  Check('nop',             I0('nop'), $0020f0);

  { j @0,target@+12: byteOff=12, relBytes=byteOff-4=8 }
  CheckPatch('j forward 12',   'j',   8, $000206, False);
  { beq @12,target2@+9 from beq: byteOff=9, relBytes=9-4=5 }
  CheckPatch('beq forward 9', 'beq', 5, $051237, True);

  writeln(checks - fails, ' / ', checks, ' xtensa checks passed');
  if fails = 0 then writeln('all asmcore_xtensa checks passed');
end.
