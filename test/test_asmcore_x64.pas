program test_asmcore_x64;
{ lib/asmcore x86-64 encoder coverage test.

  Expected bytes cross-checked against host `as`+`objdump`
  (.intel_syntax noprefix) 2026-06-30. Where asmcore deliberately picks a
  different-but-valid encoding than GNU as, the comment says so:
    - mov r64, imm  -> the universal B8+rd imm64 form (what `movabs` forces),
      NOT as's c7 /0 imm32-sign-extend shortcut.
    - ALU r64, imm  -> 83 /digit imm8 when it fits a signed byte (matches as),
      else 81 /digit imm32; the AL/AX-special short opcodes (05/25/2D...) are
      never used (general /digit form is equally valid, keeps it uniform).

  Hex-string comparison (not const-array Check) sidesteps the array-constructor-
  as-statement-arg compiler bug noted in the old version of this file. }
uses asmcore_base, asmcore_x64;

var
  failed: Boolean;

function Hex2(b: Integer): AnsiString;
const hx: AnsiString = '0123456789abcdef';
begin
  Hex2 := hx[((b shr 4) and 15) + 1] + hx[(b and 15) + 1];
end;

function HexOf(const buf: TAsmByteBuf): AnsiString;
var i: Integer; s: AnsiString;
begin
  s := '';
  for i := 0 to buf.Len - 1 do
  begin
    if i > 0 then s := s + ' ';
    s := s + Hex2(buf.Bytes[i]);
  end;
  HexOf := s;
end;

function EncHex(const instr: TAsmInstr; var patches: TAsmPatchList): AnsiString;
var buf: TAsmByteBuf;
begin
  BufInit(buf);
  PatchListInit(patches);
  if not AsmEncodeX64(instr, buf, patches) then
    EncHex := 'ENC-ERR:' + AsmCoreLastError
  else
    EncHex := HexOf(buf);
end;

function I0(const m: AnsiString): TAsmInstr;
begin I0.Mnemonic := m; I0.OperandCount := 0; end;

function I1(const m: AnsiString; const a: TAsmOperand): TAsmInstr;
begin I1.Mnemonic := m; I1.Operands[0] := a; I1.OperandCount := 1; end;

function I2(const m: AnsiString; const a, b: TAsmOperand): TAsmInstr;
begin I2.Mnemonic := m; I2.Operands[0] := a; I2.Operands[1] := b; I2.OperandCount := 2; end;

procedure Check(const name, got, want: AnsiString);
begin
  if got = want then
    writeln('OK: ', name, '  [', got, ']')
  else
  begin
    writeln('FAIL: ', name, '  got [', got, '] want [', want, ']');
    failed := True;
  end;
end;

var
  p: TAsmPatchList;
begin
  failed := False;

  { ---- mov ---- }
  Check('mov eax,5',     EncHex(I2('mov', RegOp(reg_rax, 4), ImmOp(5)), p), 'b8 05 00 00 00');
  Check('mov rax,5',     EncHex(I2('mov', RegOp(reg_rax, 8), ImmOp(5)), p), '48 b8 05 00 00 00 00 00 00 00');
  Check('mov rcx,rdx',   EncHex(I2('mov', RegOp(reg_rcx, 8), RegOp(reg_rdx, 8)), p), '48 89 d1');
  Check('mov eax,ebx',   EncHex(I2('mov', RegOp(reg_rax, 4), RegOp(reg_rbx, 4)), p), '89 d8');
  Check('mov r8,r9',     EncHex(I2('mov', RegOp(reg_r8, 8), RegOp(reg_r9, 8)), p), '4d 89 c8');
  Check('mov rax,r15',   EncHex(I2('mov', RegOp(reg_rax, 8), RegOp(reg_r15, 8)), p), '4c 89 f8');

  { ---- alu reg,reg ---- }
  Check('add rax,rbx',   EncHex(I2('add', RegOp(reg_rax, 8), RegOp(reg_rbx, 8)), p), '48 01 d8');
  Check('sub rcx,rdx',   EncHex(I2('sub', RegOp(reg_rcx, 8), RegOp(reg_rdx, 8)), p), '48 29 d1');
  Check('and rax,rbx',   EncHex(I2('and', RegOp(reg_rax, 8), RegOp(reg_rbx, 8)), p), '48 21 d8');
  Check('or rax,rbx',    EncHex(I2('or',  RegOp(reg_rax, 8), RegOp(reg_rbx, 8)), p), '48 09 d8');
  Check('xor rax,rax',   EncHex(I2('xor', RegOp(reg_rax, 8), RegOp(reg_rax, 8)), p), '48 31 c0');
  Check('cmp rdi,rsi',   EncHex(I2('cmp', RegOp(reg_rdi, 8), RegOp(reg_rsi, 8)), p), '48 39 f7');
  Check('add eax,ebx',   EncHex(I2('add', RegOp(reg_rax, 4), RegOp(reg_rbx, 4)), p), '01 d8');
  Check('xor r8,r8',     EncHex(I2('xor', RegOp(reg_r8, 8), RegOp(reg_r8, 8)), p), '4d 31 c0');

  { ---- alu reg,imm (83 imm8 small / 81 imm32 large) ---- }
  Check('add rax,100',   EncHex(I2('add', RegOp(reg_rax, 8), ImmOp(100)), p), '48 83 c0 64');
  Check('sub rsp,16',    EncHex(I2('sub', RegOp(reg_rsp, 8), ImmOp(16)), p), '48 83 ec 10');
  Check('cmp rax,5',     EncHex(I2('cmp', RegOp(reg_rax, 8), ImmOp(5)), p), '48 83 f8 05');
  Check('and rax,255',   EncHex(I2('and', RegOp(reg_rax, 8), ImmOp(255)), p), '48 81 e0 ff 00 00 00');
  Check('add eax,100',   EncHex(I2('add', RegOp(reg_rax, 4), ImmOp(100)), p), '83 c0 64');

  { ---- test / imul ---- }
  Check('test rax,rax',  EncHex(I2('test', RegOp(reg_rax, 8), RegOp(reg_rax, 8)), p), '48 85 c0');
  Check('imul rax,rcx',  EncHex(I2('imul', RegOp(reg_rax, 8), RegOp(reg_rcx, 8)), p), '48 0f af c1');
  Check('imul eax,ebx',  EncHex(I2('imul', RegOp(reg_rax, 4), RegOp(reg_rbx, 4)), p), '0f af c3');

  { ---- unary ---- }
  Check('inc rax',       EncHex(I1('inc', RegOp(reg_rax, 8)), p), '48 ff c0');
  Check('dec rcx',       EncHex(I1('dec', RegOp(reg_rcx, 8)), p), '48 ff c9');
  Check('neg rax',       EncHex(I1('neg', RegOp(reg_rax, 8)), p), '48 f7 d8');
  Check('not rbx',       EncHex(I1('not', RegOp(reg_rbx, 8)), p), '48 f7 d3');
  Check('inc r8',        EncHex(I1('inc', RegOp(reg_r8, 8)), p), '49 ff c0');

  { ---- push/pop ---- }
  Check('push rax',      EncHex(I1('push', RegOp(reg_rax, 8)), p), '50');
  Check('pop rcx',       EncHex(I1('pop',  RegOp(reg_rcx, 8)), p), '59');
  Check('push r12',      EncHex(I1('push', RegOp(reg_r12, 8)), p), '41 54');
  Check('pop rbp',       EncHex(I1('pop',  RegOp(reg_rbp, 8)), p), '5d');
  Check('push rbp',      EncHex(I1('push', RegOp(reg_rbp, 8)), p), '55');

  { ---- zero-operand ---- }
  Check('ret',           EncHex(I0('ret'), p), 'c3');
  Check('syscall',       EncHex(I0('syscall'), p), '0f 05');
  Check('nop',           EncHex(I0('nop'), p), '90');
  Check('leave',         EncHex(I0('leave'), p), 'c9');
  Check('cqo',           EncHex(I0('cqo'), p), '48 99');

  { ---- memory [base+disp] ---- }
  Check('mov rax,[rbx]',     EncHex(I2('mov', RegOp(reg_rax, 8), MemOp(reg_rbx, 0)), p), '48 8b 03');
  Check('mov rax,[rbx+8]',   EncHex(I2('mov', RegOp(reg_rax, 8), MemOp(reg_rbx, 8)), p), '48 8b 43 08');
  Check('mov rax,[rbx+200]', EncHex(I2('mov', RegOp(reg_rax, 8), MemOp(reg_rbx, 200)), p), '48 8b 83 c8 00 00 00');
  Check('mov [rbp-8],rax',   EncHex(I2('mov', MemOp(reg_rbp, -8), RegOp(reg_rax, 8)), p), '48 89 45 f8');
  Check('mov rax,[rsp]',     EncHex(I2('mov', RegOp(reg_rax, 8), MemOp(reg_rsp, 0)), p), '48 8b 04 24');
  Check('mov rax,[rsp+16]',  EncHex(I2('mov', RegOp(reg_rax, 8), MemOp(reg_rsp, 16)), p), '48 8b 44 24 10');
  Check('mov rax,[rbp]',     EncHex(I2('mov', RegOp(reg_rax, 8), MemOp(reg_rbp, 0)), p), '48 8b 45 00');
  Check('mov rcx,[r12+4]',   EncHex(I2('mov', RegOp(reg_rcx, 8), MemOp(reg_r12, 4)), p), '49 8b 4c 24 04');
  Check('mov [r13+0],rax',   EncHex(I2('mov', MemOp(reg_r13, 0), RegOp(reg_rax, 8)), p), '49 89 45 00');
  Check('lea rax,[rbx+16]',  EncHex(I2('lea', RegOp(reg_rax, 8), MemOp(reg_rbx, 16)), p), '48 8d 43 10');
  Check('lea rdi,[rsp+8]',   EncHex(I2('lea', RegOp(reg_rdi, 8), MemOp(reg_rsp, 8)), p), '48 8d 7c 24 08');
  Check('mov [rdi-4],ecx',   EncHex(I2('mov', MemOp(reg_rdi, -4), RegOp(reg_rcx, 4)), p), '89 4f fc');
  Check('mov ecx,[rdi+12]',  EncHex(I2('mov', RegOp(reg_rcx, 4), MemOp(reg_rdi, 12)), p), '8b 4f 0c');

  { ---- branches (rel32 patch sites): opcode + 4 zero bytes ---- }
  Check('jmp <patch>',  EncHex(I1('jmp',  PatchOp(4)), p), 'e9 00 00 00 00');
  Check('call <patch>', EncHex(I1('call', PatchOp(4)), p), 'e8 00 00 00 00');
  Check('je <patch>',   EncHex(I1('je',   PatchOp(4)), p), '0f 84 00 00 00 00');
  Check('jne <patch>',  EncHex(I1('jne',  PatchOp(4)), p), '0f 85 00 00 00 00');
  Check('jl <patch>',   EncHex(I1('jl',   PatchOp(4)), p), '0f 8c 00 00 00 00');
  Check('jge <patch>',  EncHex(I1('jge',  PatchOp(4)), p), '0f 8d 00 00 00 00');
  Check('jg <patch>',   EncHex(I1('jg',   PatchOp(4)), p), '0f 8f 00 00 00 00');

  { patch-site bookkeeping: jmp records one 4-byte site at offset 1 }
  EncHex(I1('jmp', PatchOp(4)), p);
  if (p.Count = 1) and (p.Items[0].Offset = 1) and (p.Items[0].Width = 4) then
    writeln('OK: jmp patch site (offset=1 width=4)')
  else
  begin
    writeln('FAIL: jmp patch site count=', p.Count);
    failed := True;
  end;

  { jcc records its site at offset 2 (after the 0F 8x prefix) }
  EncHex(I1('jg', PatchOp(4)), p);
  if (p.Count = 1) and (p.Items[0].Offset = 2) and (p.Items[0].Width = 4) then
    writeln('OK: jcc patch site (offset=2 width=4)')
  else
  begin
    writeln('FAIL: jcc patch site offset=', p.Items[0].Offset);
    failed := True;
  end;

  { ---- textual printer round-trip sanity ---- }
  writeln('print mov: ', AsmPrintX64(I2('mov', RegOp(reg_rax, 4), ImmOp(5))));
  writeln('print mem: ', AsmPrintX64(I2('mov', RegOp(reg_rax, 8), MemOp(reg_rbp, -8))));
  writeln('print jmp: ', AsmPrintX64(I1('jmp', PatchOp(4))));

  if failed then Halt(1);
  writeln('all asmcore_x64 checks passed');
end.
