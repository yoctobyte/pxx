program test_asmcore_riscv32;
{ lib/asmcore riscv32 (RV32I) encoder coverage test — the fifth asmcore
  target. Expected words cross-checked against host `riscv64-linux-gnu-as
  -march=rv32i -mabi=ilp32`+objdump 2026-06-30. Also covers
  AsmPatchBranchRiscv32, which has the most structurally different
  patch-resolution job in the library: RISC-V's jal (UJ-type) and branch
  (SB-type) immediates are bit-SCRAMBLED (non-contiguous field placement),
  not just packed-and-shifted like aarch64, and are relative to the
  instruction's own address (no +4/+8 adjustment) — see
  asmcore_riscv32.pas's header comment. }
uses asmcore_base, asmcore_riscv32;

var
  checks, fails: Integer;

procedure Check(const desc: AnsiString; const instr: TAsmInstr; expected: Int64);
var buf: TAsmByteBuf; patches: TAsmPatchList; got: Int64;
begin
  Inc(checks);
  BufInit(buf); PatchListInit(patches);
  if not AsmEncodeRiscv32(instr, buf, patches) then
  begin
    writeln('FAIL ', desc, ': encode error: ', AsmCoreLastErrorRiscv32);
    Inc(fails);
    Exit;
  end;
  if buf.Len <> 4 then
  begin
    writeln('FAIL ', desc, ': expected 4 bytes, got ', buf.Len);
    Inc(fails);
    Exit;
  end;
  got := Int64(buf.Bytes[0]) or (Int64(buf.Bytes[1]) shl 8) or (Int64(buf.Bytes[2]) shl 16) or (Int64(buf.Bytes[3]) shl 24);
  if got <> expected then
  begin
    writeln('FAIL ', desc, ': got ', got, ' expected ', expected);
    Inc(fails);
  end;
end;

procedure CheckPatch(const desc: AnsiString; const mn: AnsiString; rd, rs1, rs2: Integer; isJal: Boolean; relWords, expected: Int64);
var buf: TAsmByteBuf; patches: TAsmPatchList; instr: TAsmInstr; got: Int64;
begin
  Inc(checks);
  BufInit(buf); PatchListInit(patches);
  if isJal then
  begin
    instr.Mnemonic := mn; instr.OperandCount := 2;
    instr.Operands[0] := RegOp(rd, 4); instr.Operands[1] := PatchOp(4);
  end
  else
  begin
    instr.Mnemonic := mn; instr.OperandCount := 3;
    instr.Operands[0] := RegOp(rs1, 4); instr.Operands[1] := RegOp(rs2, 4); instr.Operands[2] := PatchOp(4);
  end;
  if not AsmEncodeRiscv32(instr, buf, patches) then
  begin writeln('FAIL ', desc, ': encode error: ', AsmCoreLastErrorRiscv32); Inc(fails); Exit; end;
  if not AsmPatchBranchRiscv32(buf, patches.Items[0].Offset, mn, relWords) then
  begin writeln('FAIL ', desc, ': patch error: ', AsmCoreLastErrorRiscv32); Inc(fails); Exit; end;
  got := Int64(buf.Bytes[0]) or (Int64(buf.Bytes[1]) shl 8) or (Int64(buf.Bytes[2]) shl 16) or (Int64(buf.Bytes[3]) shl 24);
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

var x10, x11, x12: TAsmOperand;
begin
  checks := 0; fails := 0;
  x10 := RegOp(reg_x10, 4); x11 := RegOp(reg_x11, 4); x12 := RegOp(reg_x12, 4);

  Check('addi x10,x11,5',   I3('addi', x10, x11, ImmOp(5)), $00558513);
  Check('add x10,x11,x12',  I3('add', x10, x11, x12), $00c58533);
  Check('sub x10,x11,x12',  I3('sub', x10, x11, x12), $40c58533);
  Check('and x10,x11,x12',  I3('and', x10, x11, x12), $00c5f533);
  Check('or x10,x11,x12',   I3('or', x10, x11, x12), $00c5e533);
  Check('xor x10,x11,x12',  I3('xor', x10, x11, x12), $00c5c533);
  Check('andi x10,x11,5',   I3('andi', x10, x11, ImmOp(5)), $0055f513);
  Check('ori x10,x11,5',    I3('ori', x10, x11, ImmOp(5)), $0055e513);
  Check('xori x10,x11,5',   I3('xori', x10, x11, ImmOp(5)), $0055c513);
  Check('slt x10,x11,x12',  I3('slt', x10, x11, x12), $00c5a533);
  Check('sltu x10,x11,x12', I3('sltu', x10, x11, x12), $00c5b533);
  Check('sltiu x10,x11,5',  I3('sltiu', x10, x11, ImmOp(5)), $0055b513);
  Check('mv x10,x11',       I2('mv', x10, x11), $00058513);
  Check('li x10,5',         I2('li', x10, ImmOp(5)), $00500513);
  Check('lw x10,8(x11)',    I2('lw', x10, MemOp(reg_x11, 8)), $0085a503);
  Check('sw x10,8(x11)',    I2('sw', x10, MemOp(reg_x11, 8)), $00a5a423);
  Check('lui x10,1',        I2('lui', x10, ImmOp(1)), $00001537);
  Check('ret',                I0('ret'), $00008067);
  Check('nop',                 I0('nop'), $00000013);

  CheckPatch('jal ra,target', 'jal', reg_x1, 0, 0, True, 7, $020000ef);
  CheckPatch('beq x10,x11',   'beq', 0, reg_x10, reg_x11, False, 3, $00b50863);
  CheckPatch('bne x10,x11',   'bne', 0, reg_x10, reg_x11, False, 2, $00b51663);
  CheckPatch('blt x10,x11',   'blt', 0, reg_x10, reg_x11, False, 1, $00b54463);
  CheckPatch('bge x10,x11',   'bge', 0, reg_x10, reg_x11, False, 0, $00b55263);

  writeln(checks - fails, ' / ', checks, ' riscv32 checks passed');
  if fails = 0 then writeln('all asmcore_riscv32 checks passed');
end.
