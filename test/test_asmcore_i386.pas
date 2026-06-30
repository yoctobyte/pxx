program test_asmcore_i386;
{ lib/asmcore i386 encoder coverage test — the third asmcore target,
  mechanical per the ticket's sequencing ("i386 is mostly x86-64 with the
  lid off"). Expected bytes cross-checked against host `as --32`/objdump
  (.intel_syntax noprefix) 2026-06-30 — byte-identical to the equivalent
  x64 forms, minus REX. }
uses asmcore_base, asmcore_i386;

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
  if not AsmEncodeI386(instr, buf, patches) then
  begin
    EncHex := 'ERROR:' + AsmCoreLastErrorI386;
    Exit;
  end;
  EncHex := HexOf(buf);
end;

procedure Check(const desc, got, expected: AnsiString);
begin
  if got <> expected then
  begin
    writeln('FAIL ', desc, ': got [', got, '] expected [', expected, ']');
    failed := True;
  end;
end;

function I0(const mn: AnsiString): TAsmInstr;
begin
  Result.Mnemonic := mn; Result.OperandCount := 0;
end;

function I1(const mn: AnsiString; a: TAsmOperand): TAsmInstr;
begin
  Result.Mnemonic := mn; Result.OperandCount := 1; Result.Operands[0] := a;
end;

function I2(const mn: AnsiString; a, b: TAsmOperand): TAsmInstr;
begin
  Result.Mnemonic := mn; Result.OperandCount := 2;
  Result.Operands[0] := a; Result.Operands[1] := b;
end;

var
  eax, ebx, ecx: TAsmOperand;
  patches: TAsmPatchList;
begin
  failed := False;
  eax := RegOp(reg_eax, 4); ebx := RegOp(reg_ebx, 4); ecx := RegOp(reg_ecx, 4);

  Check('mov eax,5',        EncHex(I2('mov', eax, ImmOp(5)), patches), 'b8 05 00 00 00');
  Check('mov eax,ebx',      EncHex(I2('mov', eax, ebx), patches), '89 d8');
  Check('add eax,ebx',      EncHex(I2('add', eax, ebx), patches), '01 d8');
  Check('add eax,5',        EncHex(I2('add', eax, ImmOp(5)), patches), '83 c0 05');
  Check('sub eax,ebx',      EncHex(I2('sub', eax, ebx), patches), '29 d8');
  Check('cmp eax,ebx',      EncHex(I2('cmp', eax, ebx), patches), '39 d8');
  Check('push eax',         EncHex(I1('push', eax), patches), '50');
  Check('pop ebx',          EncHex(I1('pop', ebx), patches), '5b');
  Check('ret',               EncHex(I0('ret'), patches), 'c3');
  Check('nop',               EncHex(I0('nop'), patches), '90');
  Check('mov ecx,0x12345678', EncHex(I2('mov', ecx, ImmOp($12345678)), patches), 'b9 78 56 34 12');
  Check('mov eax,[ecx+8]',  EncHex(I2('mov', eax, MemOp(reg_ecx, 8)), patches), '8b 41 08');
  Check('mov [ecx+8],eax',  EncHex(I2('mov', MemOp(reg_ecx, 8), eax), patches), '89 41 08');
  Check('lea eax,[ecx+8]',  EncHex(I2('lea', eax, MemOp(reg_ecx, 8)), patches), '8d 41 08');
  Check('and eax,ebx',      EncHex(I2('and', eax, ebx), patches), '21 d8');
  Check('or eax,ebx',       EncHex(I2('or', eax, ebx), patches), '09 d8');
  Check('xor eax,ebx',      EncHex(I2('xor', eax, ebx), patches), '31 d8');
  Check('test eax,ebx',     EncHex(I2('test', eax, ebx), patches), '85 d8');
  Check('imul eax,ebx',     EncHex(I2('imul', eax, ebx), patches), '0f af c3');
  Check('inc eax',          EncHex(I1('inc', eax), patches), '40');
  Check('dec eax',          EncHex(I1('dec', eax), patches), '48');
  Check('neg eax',          EncHex(I1('neg', eax), patches), 'f7 d8');
  Check('not eax',          EncHex(I1('not', eax), patches), 'f7 d0');
  Check('leave',             EncHex(I0('leave'), patches), 'c9');
  Check('cdq',                EncHex(I0('cdq'), patches), '99');

  { branches: rel32 patch site, byte-identical opcode shape to x64 }
  Check('jmp <patch>', EncHex(I1('jmp', PatchOp(4)), patches), 'e9 00 00 00 00');
  if (patches.Count <> 1) or (patches.Items[0].Offset <> 1) or (patches.Items[0].Width <> 4) then
  begin writeln('FAIL jmp patch site: count=', patches.Count); failed := True; end;
  Check('call <patch>', EncHex(I1('call', PatchOp(4)), patches), 'e8 00 00 00 00');
  Check('je <patch>',   EncHex(I1('je', PatchOp(4)), patches), '0f 84 00 00 00 00');
  Check('jg <patch>',   EncHex(I1('jg', PatchOp(4)), patches), '0f 8f 00 00 00 00');

  if failed then writeln('asmcore_i386 checks FAILED')
  else writeln('all asmcore_i386 checks passed');
end.
