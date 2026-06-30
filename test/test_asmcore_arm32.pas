program test_asmcore_arm32;
{ lib/asmcore arm32 (A32) encoder coverage test — the fourth asmcore target.
  Expected words cross-checked against host `arm-linux-gnueabi-as`+objdump
  2026-06-30. Also covers AsmPatchBranchArm32, which has its own pipeline-
  driven adjustment (PC reads as instr_addr+8 in A32, not +4 like every
  other target here) on top of the read-modify-write pattern aarch64
  established — see asmcore_arm32.pas's header comment. }
uses asmcore_base, asmcore_arm32;

var
  checks, fails: Integer;

procedure Check(const desc: AnsiString; const instr: TAsmInstr; expected: Int64);
var buf: TAsmByteBuf; patches: TAsmPatchList; got: Int64;
begin
  Inc(checks);
  BufInit(buf); PatchListInit(patches);
  if not AsmEncodeArm32(instr, buf, patches) then
  begin
    writeln('FAIL ', desc, ': encode error: ', AsmCoreLastErrorArm32);
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
  if not AsmEncodeArm32(instr, buf, patches) then
  begin writeln('FAIL ', desc, ': encode error: ', AsmCoreLastErrorArm32); Inc(fails); Exit; end;
  if not AsmPatchBranchArm32(buf, patches.Items[0].Offset, mn, relWords) then
  begin writeln('FAIL ', desc, ': patch error: ', AsmCoreLastErrorArm32); Inc(fails); Exit; end;
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

var r0, r1, r2, lr: TAsmOperand; buf: TAsmByteBuf; patches: TAsmPatchList;
begin
  checks := 0; fails := 0;
  r0 := RegOp(reg_r0, 4); r1 := RegOp(reg_r1, 4); r2 := RegOp(reg_r2, 4); lr := RegOp(reg_lr, 4);

  Check('mov r0,r1',      I2('mov', r0, r1), $e1a00001);
  Check('mov r0,#5',      I2('mov', r0, ImmOp(5)), $e3a00005);
  Check('add r0,r1,r2',   I3('add', r0, r1, r2), $e0810002);
  Check('add r0,r1,#5',   I3('add', r0, r1, ImmOp(5)), $e2810005);
  Check('sub r0,r1,r2',   I3('sub', r0, r1, r2), $e0410002);
  Check('sub r0,r1,#5',   I3('sub', r0, r1, ImmOp(5)), $e2410005);
  Check('and r0,r1,r2',   I3('and', r0, r1, r2), $e0010002);
  Check('orr r0,r1,r2',   I3('orr', r0, r1, r2), $e1810002);
  Check('eor r0,r1,r2',   I3('eor', r0, r1, r2), $e0210002);
  Check('cmp r0,r1',      I2('cmp', r0, r1), $e1500001);
  Check('cmp r0,#5',      I2('cmp', r0, ImmOp(5)), $e3500005);
  Check('ldr r0,[r1,#8]', I2('ldr', r0, MemOp(reg_r1, 8)), $e5910008);
  Check('str r0,[r1,#8]', I2('str', r0, MemOp(reg_r1, 8)), $e5810008);
  Check('bx lr',           I1('bx', lr), $e12fff1e);
  Check('mov pc,lr',       I2('mov', RegOp(reg_pc, 4), lr), $e1a0f00e);
  Check('nop',              I0('nop'), $e1a00000);

  CheckPatch('b forward 3',   'b',   3, $ea000002);
  CheckPatch('bl forward 2',  'bl',  2, $eb000001);
  CheckPatch('beq forward 1', 'beq', 1, $0a000000);
  CheckPatch('blt forward 0', 'blt', 0, $baffffff);

  { ---- rotated-immediate (ROR(imm8,rotate*2)), not just plain 0..255 ----
    Byte-exact vs `arm-linux-gnueabi-as`+objdump, 2026-07-01. }
  Check('mov r0,#0x10000',    I2('mov', r0, ImmOp($10000)), $e3a00801);
  Check('mov r0,#0xFF000000', I2('mov', r0, ImmOp($FF000000)), $e3a004ff);
  Check('mov r0,#0x3FC',      I2('mov', r0, ImmOp($3FC)), $e3a00fff);
  Check('add r0,r1,#0x10000', I3('add', r0, r1, ImmOp($10000)), $e2810801);
  Check('mov r0,#256',        I2('mov', r0, ImmOp(256)), $e3a00c01);
  { 258 has no rotated-imm8 encoding at all -- must error, not miscompile }
  Inc(checks);
  BufInit(buf); PatchListInit(patches);
  if AsmEncodeArm32(I2('mov', r0, ImmOp(258)), buf, patches) then
  begin writeln('FAIL: mov r0,#258 should have been rejected'); Inc(fails); end;

  writeln(checks - fails, ' / ', checks, ' arm32 checks passed');
  if fails = 0 then writeln('all asmcore_arm32 checks passed');
end.
