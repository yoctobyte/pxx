program test_x64enc;
{$mode objfpc}{$H+}

uses SysUtils;

var
  MockBuffer: array[0..1023] of Byte;
  MockLen: Integer = 0;
  LastGlobRef: Integer = -1;

procedure EmitB(b: Byte);
begin
  MockBuffer[MockLen] := b;
  Inc(MockLen);
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

procedure EmitGlobRef(bssOff: Integer);
begin
  LastGlobRef := bssOff;
  EmitI32(0); { mock displacement placeholder }
end;

procedure AsmB(b: Integer);
begin
  MockBuffer[MockLen] := Byte(b and $FF);
  Inc(MockLen);
end;

procedure AsmI16(v: Int64);
begin
  AsmB(v and $FF); AsmB((v shr 8) and $FF);
end;

procedure AsmI32(v: Int64);
begin
  AsmB(v and $FF); AsmB((v shr 8) and $FF); AsmB((v shr 16) and $FF); AsmB((v shr 24) and $FF);
end;

procedure AsmI64(v: Int64);
begin
  AsmI32(v); AsmI32(v shr 32);
end;

procedure Error(const msg: string);
begin
  writeln(StdErr, 'ERROR: ', msg);
  Halt(1);
end;

{$include ../compiler/x64enc.inc}

{ Test helpers }
procedure ClearMock;
begin
  MockLen := 0;
  LastGlobRef := -1;
end;

procedure AssertBytes(const name: string; const expected: array of Byte);
var
  i: Integer;
  failed: Boolean;
begin
  failed := False;
  if MockLen <> Length(expected) then
    failed := True
  else
  begin
    for i := 0 to MockLen - 1 do
      if MockBuffer[i] <> expected[i] then
        failed := True;
  end;
  
  if failed then
  begin
    write('FAIL: ', name, '. Expected ');
    for i := 0 to Length(expected) - 1 do
      write(IntToHex(expected[i], 2), ' ');
    writeln;
    write('Got: ');
    for i := 0 to MockLen - 1 do
      write(IntToHex(MockBuffer[i], 2), ' ');
    writeln;
    Halt(1);
  end
  else
    writeln('PASS: ', name);
end;

begin
  { --- 0-operand --- }
  ClearMock;
  x64_nop;
  AssertBytes('nop', [$90]);

  ClearMock;
  x64_ret;
  AssertBytes('ret', [$C3]);

  ClearMock;
  x64_leave;
  AssertBytes('leave', [$C9]);

  ClearMock;
  x64_syscall;
  AssertBytes('syscall', [$0F, $05]);

  { --- mov reg, reg --- }
  ClearMock;
  x64_mov_reg_reg(8, rRDI, rRAX);
  AssertBytes('mov rdi, rax', [$48, $89, $C7]);

  ClearMock;
  x64_mov_reg_reg(4, rRDI, rRAX);
  AssertBytes('mov edi, eax', [$89, $C7]);

  { --- mov reg, imm --- }
  ClearMock;
  x64_mov_reg_imm(4, rRAX, 1);
  AssertBytes('mov eax, 1', [$B8, $01, $00, $00, $00]);

  ClearMock;
  x64_mov_reg_imm(8, rRAX, $1122334455667788);
  AssertBytes('mov rax, imm64', [$48, $B8, $88, $77, $66, $55, $44, $33, $22, $11]);

  { --- mov reg, mem --- }
  ClearMock;
  { force32 = True }
  x64_mov_reg_mem(8, rRDI, rRBP, -16, True);
  AssertBytes('mov rdi, [rbp-16] force32', [$48, $8B, $BD, $F0, $FF, $FF, $FF]);

  ClearMock;
  { force32 = False, fits in 8 bits }
  x64_mov_reg_mem(8, rRDI, rRBP, -16, False);
  AssertBytes('mov rdi, [rbp-16] 8-bit disp', [$48, $8B, $7D, $F0]);

  ClearMock;
  { base=RSP/rRSP, needs SIB, force32=True }
  x64_mov_reg_mem(8, rRAX, rRSP, 8, True);
  AssertBytes('mov rax, [rsp+8] force32', [$48, $8B, $84, $24, $08, $00, $00, $00]);

  ClearMock;
  { base=RSP/rRSP, needs SIB, force32=False }
  x64_mov_reg_mem(8, rRAX, rRSP, 8, False);
  AssertBytes('mov rax, [rsp+8] 8-bit disp', [$48, $8B, $44, $24, $08]);

  { --- mov mem, reg --- }
  ClearMock;
  x64_mov_mem_reg(8, rRBP, -24, rRBX, True);
  AssertBytes('mov [rbp-24], rbx force32', [$48, $89, $9D, $E8, $FF, $FF, $FF]);

  ClearMock;
  x64_mov_mem_reg(8, rRBP, -24, rRBX, False);
  AssertBytes('mov [rbp-24], rbx 8-bit disp', [$48, $89, $5D, $E8]);

  { --- mov mem, imm --- }
  ClearMock;
  x64_mov_mem_imm(4, rRBP, -8, 0, True);
  AssertBytes('mov dword [rbp-8], 0 force32', [$C7, $85, $F8, $FF, $FF, $FF, $00, $00, $00, $00]);

  ClearMock;
  x64_mov_mem_imm(4, rRBP, -8, 0, False);
  AssertBytes('mov dword [rbp-8], 0 8-bit disp', [$C7, $45, $F8, $00, $00, $00, $00]);

  { --- mov glob --- }
  ClearMock;
  x64_mov_glob_reg(8, 123, rRAX);
  AssertBytes('mov [glob], rax', [$48, $89, $04, $25, $00, $00, $00, $00]);
  if LastGlobRef <> 123 then begin writeln('GlobRef mismatch'); Halt(1); end;

  ClearMock;
  x64_mov_reg_glob(8, rRAX, 123);
  AssertBytes('mov rax, [glob]', [$48, $8B, $04, $25, $00, $00, $00, $00]);
  if LastGlobRef <> 123 then begin writeln('GlobRef mismatch'); Halt(1); end;

  { --- lea --- }
  ClearMock;
  x64_lea_reg_mem(8, rRBX, rRBP, -32, True);
  AssertBytes('lea rbx, [rbp-32] force32', [$48, $8D, $9D, $E0, $FF, $FF, $FF]);

  ClearMock;
  x64_lea_reg_mem(8, rRBX, rRBP, -32, False);
  AssertBytes('lea rbx, [rbp-32] 8-bit disp', [$48, $8D, $5D, $E0]);

  { --- push / pop --- }
  ClearMock;
  x64_push_reg(rRBX);
  AssertBytes('push rbx', [$53]);

  ClearMock;
  x64_pop_reg(rRBX);
  AssertBytes('pop rbx', [$5B]);

  ClearMock;
  x64_push_imm(42);
  AssertBytes('push 42', [$68, $2A, $00, $00, $00]);

  { --- ALU --- }
  ClearMock;
  x64_add_reg_imm(8, rRSP, 24);
  AssertBytes('add rsp, 24 (compact)', [$48, $83, $C4, $18]);

  ClearMock;
  x64_sub_reg_imm(8, rRSP, 8);
  AssertBytes('sub rsp, 8 (compact)', [$48, $83, $EC, $08]);

  ClearMock;
  x64_test_reg_reg(4, rRAX, rRAX);
  AssertBytes('test eax, eax', [$85, $C0]);

  ClearMock;
  x64_test_reg_imm(4, rRAX, 1);
  AssertBytes('test eax, 1', [$F7, $C0, $01, $00, $00, $00]);

  { --- inc / dec --- }
  ClearMock;
  x64_inc_mem(8, rRAX, -16, False);
  AssertBytes('inc qword [rax-16]', [$48, $FF, $40, $F0]);

  { --- jump / call --- }
  ClearMock;
  x64_jmp_rel32(500);
  AssertBytes('jmp rel32', [$E9, $F4, $01, $00, $00]);

  ClearMock;
  x64_jcc_rel8(5, -10); { jnz -10 }
  AssertBytes('jnz rel8', [$75, $F6]);

  writeln('ALL ENCODER TESTS PASSED.');
end.
