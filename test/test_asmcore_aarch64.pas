program test_asmcore_aarch64;
{ lib/asmcore aarch64 encoder coverage test — the second asmcore target
  (feature-asmcore-encoder-library), the deliberate "structurally different"
  pressure test for the operand model (fixed-width, no ModRM/SIB, 3-address
  ALU, bit-packed branch immediates instead of a trailing rel32 field).

  Expected words cross-checked against host `aarch64-linux-gnu-as`+objdump
  2026-06-30. Also covers AsmPatchBranchAArch64, the read-modify-write
  branch-patch resolver this target needs in place of x64's raw-byte
  Patch32 — see asmcore_aarch64.pas's header comment for why. }
uses asmcore_base, asmcore_aarch64;

var
  checks, fails: Integer;

procedure Check(const desc: AnsiString; const instr: TAsmInstr; expected: Int64);
var buf: TAsmByteBuf; patches: TAsmPatchList; got: Int64;
begin
  Inc(checks);
  BufInit(buf); PatchListInit(patches);
  if not AsmEncodeAArch64(instr, buf, patches) then
  begin
    writeln('FAIL ', desc, ': encode error: ', AsmCoreLastErrorAArch64);
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

procedure CheckPatch(const desc: AnsiString; const mn: AnsiString; relWords, expected: Int64);
var buf: TAsmByteBuf; patches: TAsmPatchList; instr: TAsmInstr; got: Int64;
begin
  Inc(checks);
  BufInit(buf); PatchListInit(patches);
  instr.Mnemonic := mn; instr.OperandCount := 1; instr.Operands[0] := PatchOp(4);
  if not AsmEncodeAArch64(instr, buf, patches) then
  begin writeln('FAIL ', desc, ': encode error: ', AsmCoreLastErrorAArch64); Inc(fails); Exit; end;
  if not AsmPatchBranchAArch64(buf, patches.Items[0].Offset, mn, relWords) then
  begin writeln('FAIL ', desc, ': patch error: ', AsmCoreLastErrorAArch64); Inc(fails); Exit; end;
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

function I1(mn: AnsiString; a: TAsmOperand): TAsmInstr;
begin
  Result.Mnemonic := mn; Result.OperandCount := 1;
  Result.Operands[0] := a;
end;

function I0(mn: AnsiString): TAsmInstr;
begin
  Result.Mnemonic := mn; Result.OperandCount := 0;
end;

var x0, x1, x2, w0, w2, w3, w4, w5: TAsmOperand;
begin
  checks := 0; fails := 0;
  x0 := RegOp(reg_x0, 8); x1 := RegOp(reg_x1, 8); x2 := RegOp(reg_x2, 8);
  w0 := RegOp(reg_x0, 4); w2 := RegOp(reg_x2, 4); w3 := RegOp(reg_x3, 4);
  w4 := RegOp(reg_x4, 4); w5 := RegOp(reg_x5, 4);

  Check('mov x0,x1',       I2('mov', x0, x1), $aa0103e0);
  Check('mov w0,w1',       I2('mov', w0, RegOp(reg_x1,4)), $2a0103e0);
  Check('add x0,x1,x2',    I3('add', x0, x1, x2), $8b020020);
  Check('add x0,x1,#5',    I3('add', x0, x1, ImmOp(5)), $91001420);
  Check('add w3,w4,#100',  I3('add', w3, w4, ImmOp(100)), $11019083);
  Check('sub w3,w4,w5',    I3('sub', w3, w4, w5), $4b050083);
  Check('sub x0,x1,#1',    I3('sub', x0, x1, ImmOp(1)), $d1000420);
  Check('cmp x0,x1',       I2('cmp', x0, x1), $eb01001f);
  Check('cmp w0,#10',      I2('cmp', w0, ImmOp(10)), $7100281f);
  Check('and x0,x1,x2',    I3('and', x0, x1, x2), $8a020020);
  Check('orr x0,x1,x2',    I3('orr', x0, x1, x2), $aa020020);
  Check('eor x0,x1,x2',    I3('eor', x0, x1, x2), $ca020020);
  Check('ldr x0,[x1,#16]', I2('ldr', x0, MemOp(reg_x1, 16)), $f9400820);
  Check('ldr w2,[x3]',     I2('ldr', w2, MemOp(reg_x3, 0)), $b9400062);
  Check('str w2,[x3]',     I2('str', w2, MemOp(reg_x3, 0)), $b9000062);
  Check('str x0,[x1,#8]',  I2('str', x0, MemOp(reg_x1, 8)), $f9000420);
  Check('ret',              I0('ret'), $d65f03c0);
  Check('ret x5',           I1('ret', RegOp(reg_x5, 8)), $d65f00a0);
  Check('nop',               I0('nop'), $d503201f);
  Check('movz x0,#100',     I2('movz', x0, ImmOp(100)), $d2800c80);
  Check('movk x0,#5,#16',   I3('movk', x0, ImmOp(5), ImmOp(16)), $f2a000a0);
  Check('movn x0,#0',       I2('movn', x0, ImmOp(0)), $92800000);

  CheckPatch('b forward 4',    'b',    4, $14000004);
  CheckPatch('bl forward 2',   'bl',   2, $94000002);
  CheckPatch('b.lt forward 3', 'b.lt', 3, $5400006b);
  CheckPatch('b backward -2',  'b',   -2, $17fffffe);

  writeln(checks - fails, ' / ', checks, ' aarch64 checks passed');
  if fails = 0 then writeln('all asmcore_aarch64 checks passed');
end.
