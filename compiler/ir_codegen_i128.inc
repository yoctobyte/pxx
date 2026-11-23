{ ir_codegen_i128.inc -- GCC's 128-bit integers on x86-64 (aarch64: ir_codegen_a64_i128.inc).

  `__int128` / `unsigned __int128` (tyInt128 / tyUInt128) are carried in
  rdx:rax, low half in rax, the way the i386 back end carries an Int64 in
  edx:eax (ir_codegen386.inc, EmitBinop64_386). The convention is the SysV
  one for a returned __int128, so a call result needs no shuffling.

  IREmitNode hands a node here when it PRODUCES or CONSUMES a 128-bit value
  (I128Claims). A narrower consumer of a 128-bit value needs nothing: the low
  half is already in rax, which is C's conversion to a narrower integer. A
  128-bit consumer of a narrower value widens it with I128EmitValue, by the
  narrow operand's own signedness (cqo or a zeroed rdx).

  Only rax, rcx and rdx are clobbered, plus the stack for the left operand,
  which is the contract every other binop arm keeps.

  Division and modulo are inline (no libgcc), and so are the conversions to
  and from the floating types (I128ToDouble, I128FromFloat). aarch64 carries
  the same model in x0:x1 (ir_codegen_a64_i128.inc); the 32-bit targets
  refuse the type, as gcc does.
  feature-c-int128-and-attribute-mode,
  feature-c-int128-other-targets-float-and-narrow-modes }

function I128Node(n: Integer): Boolean;
begin
  Result := (n >= 0) and TypeIsInt128(IntToTypeKind(IRTk[n]));
end;

{ A scalar 128-bit variable (a 128-bit ARRAY is reached through IR_INDEX and
  a typed IR_LOAD_MEM, never as a whole). }
function I128Sym(sym: Integer): Boolean;
begin
  Result := (sym >= 0) and TypeIsInt128(Syms[sym].TypeKind) and (not Syms[sym].IsArray);
end;

function I128Claims(node: Integer): Boolean;
begin
  Result := False;
  case IRKind[node] of
    IR_CONST_INT, IR_LOAD_MEM, IR_STORE_MEM:
      Result := I128Node(node);
    IR_LOAD_SYM, IR_STORE_SYM:
      Result := I128Sym(IRA[node]);
    IR_BINOP:
      { an __int128 meeting a float is float arithmetic (or a float compare):
        the float arm converts the integer side (EmitCvtSi2SdOrU64) }
      Result := (I128Node(node) or I128Node(IRA[node]) or I128Node(IRB[node])) and
                not TypeIsFloat(IntToTypeKind(IRTk[node])) and
                not TypeIsFloat(IntToTypeKind(IRTk[IRA[node]])) and
                not TypeIsFloat(IntToTypeKind(IRTk[IRB[node]]));
    IR_NEG, IR_NOT:
      Result := I128Node(node) or I128Node(IRA[node]);
  end;
end;

{ A floating value (its double bits in rax, a Single's included) truncated toward zero
  into rdx:rax, as gcc's __fixdfti / __fixunsdfti. Below 2^63 in magnitude
  cvttsd2si is exact and cqo extends it. Above, the value is its 53-bit
  mantissa shifted left by (exponent - 1075) >= 11, then negated if the sign
  bit was set. Out of range is undefined in C, as in gcc.
  feature-c-int128-other-targets-float-and-narrow-modes }
procedure I128FromFloat(tk: TTypeKind);
begin
  { a Single travels as double bits too (it is narrowed only when stored),
    so tk does not change the sequence }
  AsmScopeBegin;
  EmitAsmX64([
    'mov rcx, rax',
    'shr rcx, 52',
    'and ecx, 2047',                 { biased exponent }
    'cmp ecx, 1086',                 { 1023 + 63: |x| >= 2^63 }
    'jae big',
    'movq xmm0, rax',
    'cvttsd2si rax, xmm0',
    'cqo',
    'jmp done',
  'big:',
    'mov r11, rax',                  { the sign, in bit 63 }
    'mov rdx, -1',
    'shr rdx, 12',
    'and rax, rdx',                  { the 52 stored mantissa bits }
    'mov edx, 1',
    'shl rdx, 52',
    'or rax, rdx',                   { m, with the implicit bit }
    'sub ecx, 1075',                 { m << ecx is the value }
    'xor edx, edx',
    'cmp ecx, 64',
    'jae wide',
    'shld rdx, rax, cl',
    'shl rax, cl',
    'jmp sign',
  'wide:',
    'sub ecx, 64',
    'mov rdx, rax',
    'shl rdx, cl',
    'xor eax, eax',
  'sign:',
    'test r11, r11',
    'jns done',
    'neg rax',
    'adc rdx, 0',
    'neg rdx',
  'done:']);
  AsmScopeEnd;
end;

{ The value in rdx:rax converted to the double in xmm<xmm>, correctly
  rounded, as gcc's __floattidf / __floatuntidf. A value that fits in 63 bits
  is one cvtsi2sd. Otherwise it is shifted right by s (1..65) to 63 bits with
  every bit shifted out OR-ed into bit 0 -- 63 bits hold the 53 kept, a round
  bit and a sticky bit, so cvtsi2sd rounds exactly as the full value would --
  and 2^s is put back by adding s to the exponent field, which is exact. A
  signed value converts its magnitude (2^127 for the most negative is fine
  unsigned) and flips the sign bit. Clobbers rax, rcx, rdx, r11.
  feature-c-int128-other-targets-float-and-narrow-modes }
procedure I128ToDouble(xmm: Integer; signed: Boolean);
begin
  AsmScopeBegin;
  if signed then
    EmitAsmX64([
      'mov r11, rdx',
      'sar r11, 63',
      'xor rax, r11',
      'xor rdx, r11',
      'sub rax, r11',
      'sbb rdx, r11'])               { |v|; r11 = 0 or -1 }
  else
    EmitAsmX64(['xor r11d, r11d']);
  EmitAsmX64([
    'test rdx, rdx',
    'jnz big',
    'test rax, rax',
    'js big',
    'cvtsi2sd %xmm, rax', xmm,
    'jmp sign',
  'big:',
    'push r11',
    'mov ecx, 1',                    { hi = 0, lo >= 2^63: s = 1 }
    'test rdx, rdx',
    'jz haves',
    'bsr rcx, rdx',
    'add ecx, 2',                    { bit length 65 + idx: s = idx + 2 }
  'haves:',
    'push rcx',
    'cmp ecx, 64',
    'jae wide',
    'mov r11, rax',
    'neg ecx',
    'shl r11, cl',                   { the s low bits, at the top: shift 64 - s }
    'neg ecx',
    'shrd rax, rdx, cl',
    'jmp sticky',
  'wide:',
    'sub ecx, 64',                   { 0 or 1 }
    'mov r11, rdx',
    'and r11, rcx',                  { the bit of hi shifted out, if any }
    'or r11, rax',                   { and all of lo }
    'shr rdx, cl',
    'mov rax, rdx',
  'sticky:',
    'test r11, r11',
    'jz exact',
    'or rax, 1',
  'exact:',
    'cvtsi2sd %xmm, rax', xmm,
    'movq rax, %xmm', xmm,
    'pop rcx',
    'shl rcx, 52',
    'add rax, rcx',                  { times 2^s }
    'movq %xmm, rax', xmm,
    'pop r11',
  'sign:',
    'test r11, r11',
    'jz done',
    'movq rax, %xmm', xmm,
    'btc rax, 63',
    'movq %xmm, rax', xmm,
  'done:']);
  AsmScopeEnd;
end;

{ A binop with an __int128 operand and a floating one (arithmetic or a
  compare): C converts the integer to the floating type. }
function I128MixedFloat(node: Integer): Boolean;
var lt, rt: TTypeKind;
begin
  lt := IntToTypeKind(IRTk[IRA[node]]);
  rt := IntToTypeKind(IRTk[IRB[node]]);
  Result := (TypeIsInt128(lt) and TypeIsFloat(rt)) or (TypeIsFloat(lt) and TypeIsInt128(rt));
end;

{ n's value as double bits in rax: an __int128 converted, a float as it is.
  The other operand of a mixed binop is always the float one. }
procedure I128OperandAsDouble(n: Integer);
begin
  IREmitNode(n);
  if TypeIsInt128(IntToTypeKind(IRTk[n])) then
  begin
    I128ToDouble(0, IntToTypeKind(IRTk[n]) = tyInt128);
    EmitAsmX64(['movq rax, xmm0']);
  end;
end;

{ Evaluate n into rdx:rax as a 128-bit value. }
procedure I128EmitValue(n: Integer);
var tk: TTypeKind;
begin
  IREmitNode(n);
  if I128Node(n) then Exit;
  tk := IntToTypeKind(IRTk[n]);
  if TypeIsFloat(tk) then
  begin
    I128FromFloat(tk);
    Exit;
  end;
  { tyUnknown is a synthesized integer, which x86-64 treats as signed }
  if TypeSigned(tk) or (tk = tyUnknown) then
    begin EmitAsmX64(['cqo']); end
  else
    begin EmitAsmX64(['xor edx, edx']); end;
end;

procedure I128SymRefuse(sym: Integer; const what: AnsiString);
begin
  Error('__int128: ' + what + ' of ' + Syms[sym].Name +
        ' is not supported yet (feature-c-int128-and-attribute-mode)');
end;

procedure I128LoadSym(sym: Integer);
begin
  if ResidentRegOf(sym) <> 0 then I128SymRefuse(sym, 'a register-resident copy');
  case Syms[sym].Kind of
    skGlobal:
      begin
        EmitAsmX64(['mov rax, [@glob]', Syms[sym].Offset]);
        EmitAsmX64(['mov rdx, [@glob]', Syms[sym].Offset + 8]);
      end;
    skLocal, skParam:
      if (Syms[sym].Kind = skParam) and Syms[sym].IsRef then
      begin
        EmitAsmX64([
          'mov rcx, [rbp+%]', Syms[sym].Offset,
          'mov rax, [rcx]',
          'mov rdx, [rcx+8]']);
      end
      else
      begin
        EmitAsmX64([
          'mov rax, [rbp+%]', Syms[sym].Offset,
          'mov rdx, [rbp+%]', Syms[sym].Offset + 8]);
      end;
  else
    I128SymRefuse(sym, 'a load');
  end;
end;

{ Store rdx:rax into sym; rdx:rax keep the value. }
procedure I128StoreSym(sym: Integer);
begin
  if ResidentRegOf(sym) <> 0 then I128SymRefuse(sym, 'a register-resident copy');
  case Syms[sym].Kind of
    skGlobal:
      begin
        EmitAsmX64(['mov [@glob], rax', Syms[sym].Offset]);
        EmitAsmX64(['mov [@glob], rdx', Syms[sym].Offset + 8]);
      end;
    skLocal, skParam:
      if (Syms[sym].Kind = skParam) and Syms[sym].IsRef then
      begin
        EmitAsmX64([
          'mov rcx, [rbp+%]', Syms[sym].Offset,
          'mov [rcx], rax',
          'mov [rcx+8], rdx']);
      end
      else
      begin
        EmitAsmX64([
          'mov [rbp+%], rax', Syms[sym].Offset,
          'mov [rbp+%], rdx', Syms[sym].Offset + 8]);
      end;
  else
    I128SymRefuse(sym, 'a store');
  end;
end;

procedure I128EmitShift(node: Integer);
var op: Integer; arith: Boolean;
begin
  op := IRC[node];
  { The C parser already chose: tkShr is arithmetic (a signed left operand),
    tkShrLogical logical. Not the node's type -- a cast between the two
    128-bit kinds retypes the node, so `(unsigned __int128)(s >> 1)` would
    read as unsigned here. }
  arith := op = Ord(tkShr);
  I128EmitValue(IRA[node]);
  EmitAsmX64(['push rdx', 'push rax']);
  IREmitNode(IRB[node]);                       { the count; its low half if 128-bit }
  EmitAsmX64(['mov rcx, rax', 'pop rax', 'pop rdx']);
  if op = Ord(tkShl) then
    EmitAsmX64([
      'shld rdx, rax, cl',
      'shl rax, cl',
      'test cl, 64',
      'jz .done',
      'mov rdx, rax',
      'xor eax, eax',
    '.done:'])
  else if arith then
    EmitAsmX64([
      'shrd rax, rdx, cl',
      'sar rdx, cl',
      'test cl, 64',
      'jz .done',
      'mov rax, rdx',
      'sar rdx, 63',
    '.done:'])
  else
    EmitAsmX64([
      'shrd rax, rdx, cl',
      'shr rdx, cl',
      'test cl, 64',
      'jz .done',
      'mov rax, rdx',
      'xor edx, edx',
    '.done:']);
end;

{ L / R and L % R, no libgcc (pxx-does-not-depend-on-libgcc). The operands
  are on the stack; the frame below is

    [rsp+0]  S0 normalising shift n      [rsp+48] R lo   [rsp+64] L lo
    [rsp+8]  S1 top word of R << n       [rsp+56] R hi   [rsp+72] L hi
    [rsp+16] S2 quotient (high word, or the one-word quotient)
    [rsp+24] S3 quotient sign mask       [rsp+32] S4 remainder sign mask

  A divisor below 2^64 -- every libtommath mp_word / mp_digit -- is two `div`s:
  the high word first, its remainder carried into the low word's divide, so
  neither can overflow. A wider divisor leaves a quotient below 2^64, which one
  `div` of the normalised operands estimates to within one (Hacker's Delight,
  9-5 "divlu" extended to 128/128): q0 = ((L >> 1) / v1) >> (63 - n), less one
  if non-zero, plus one if the remainder still reaches R.

  Signed: divide the magnitudes, then the quotient takes the XOR of the signs
  and the remainder the dividend's (C99 6.5.5: truncation toward zero). A zero
  divisor faults in `div`, the same SIGFPE gcc's code raises. }
procedure I128EmitDivMod(node: Integer; wantMod, signed: Boolean);
begin
  I128EmitValue(IRA[node]);
  EmitAsmX64(['push rdx', 'push rax']);          { L }
  I128EmitValue(IRB[node]);
  EmitAsmX64(['push rdx', 'push rax', 'sub rsp, 48']);   { R, then scratch }
  if signed then
    { take magnitudes: v = (v xor m) - m with m = v's sign word }
    EmitAsmX64([
      'mov rax, [rsp+72]', 'sar rax, 63', 'mov [rsp+32], rax',   { S4 = sign(L) }
      'mov rcx, [rsp+56]', 'sar rcx, 63', 'xor rax, rcx', 'mov [rsp+24], rax',   { S3 = sign(L) xor sign(R) }
      'mov rax, [rsp+64]', 'mov rdx, [rsp+72]', 'mov rcx, [rsp+32]',
      'xor rax, rcx', 'xor rdx, rcx', 'sub rax, rcx', 'sbb rdx, rcx',
      'mov [rsp+64], rax', 'mov [rsp+72], rdx',
      'mov rax, [rsp+48]', 'mov rdx, [rsp+56]', 'mov rcx, rdx', 'sar rcx, 63',
      'xor rax, rcx', 'xor rdx, rcx', 'sub rax, rcx', 'sbb rdx, rcx',
      'mov [rsp+48], rax', 'mov [rsp+56], rdx']);
  { unsigned core, ONE listing per variant (EmitAsmX64 labels are per call):
    the wide-divisor path first, then the two-`div` path for R < 2^64.
    Leaves the quotient or the remainder in rdx:rax. }
  if not wantMod then
    EmitAsmX64([
      'mov rcx, [rsp+56]',
      'test rcx, rcx',
      'jz .narrow',
      'bsr rcx, rcx',
      'xor ecx, 63',                             { n = leading zeros of R hi }
      'mov [rsp], rcx',
      'mov rdx, [rsp+56]',
      'mov rax, [rsp+48]',
      'shld rdx, rax, cl',
      'mov [rsp+8], rdx',                        { v1 = top word of R << n }
      'mov rax, [rsp+64]',
      'mov rdx, [rsp+72]',
      'mov ecx, 1',
      'shrd rax, rdx, cl',
      'shr rdx, 1',                              { L >> 1: its high word is below v1 }
      'mov rcx, [rsp+8]',
      'div rcx',                                 { q1 }
      'mov rcx, [rsp]',
      'xor ecx, 63',
      'shr rax, cl',                             { q0 = q1 >> (63 - n) }
      'test rax, rax',
      'jz .q0',
      'sub rax, 1',
    '.q0:',
      'mov [rsp+16], rax',
      'mov rcx, [rsp+48]',
      'mul rcx',                                 { q0 * R lo }
      'mov rcx, [rsp+16]',
      'imul rcx, [rsp+56]',
      'add rdx, rcx',                            { q0 * R }
      'mov rcx, rax',
      'mov rax, [rsp+64]',
      'sub rax, rcx',
      'mov rcx, rdx',
      'mov rdx, [rsp+72]',
      'sbb rdx, rcx',                            { rem = L - q0 * R }
      'cmp rax, [rsp+48]',
      'mov rcx, rdx',
      'sbb rcx, [rsp+56]',
      'jb .fix',                                 { rem < R: q0 stands }
      'sub rax, [rsp+48]',
      'sbb rdx, [rsp+56]',
      'mov rcx, [rsp+16]',
      'add rcx, 1',
      'mov [rsp+16], rcx',
    '.fix:',
      'mov rax, [rsp+16]',
      'xor edx, edx',
      'jmp .done',
    '.narrow:',
      'mov rcx, [rsp+48]',
      'mov rax, [rsp+72]',
      'xor edx, edx',
      'div rcx',                                 { high quotient word }
      'mov [rsp+16], rax',
      'mov rax, [rsp+64]',
      'div rcx',                                 { low word, high remainder carried }
      'mov rdx, [rsp+16]',
    '.done:'])
  else
    EmitAsmX64([
      'mov rcx, [rsp+56]',
      'test rcx, rcx',
      'jz .narrow',
      'bsr rcx, rcx',
      'xor ecx, 63',                             { n = leading zeros of R hi }
      'mov [rsp], rcx',
      'mov rdx, [rsp+56]',
      'mov rax, [rsp+48]',
      'shld rdx, rax, cl',
      'mov [rsp+8], rdx',                        { v1 = top word of R << n }
      'mov rax, [rsp+64]',
      'mov rdx, [rsp+72]',
      'mov ecx, 1',
      'shrd rax, rdx, cl',
      'shr rdx, 1',                              { L >> 1: its high word is below v1 }
      'mov rcx, [rsp+8]',
      'div rcx',                                 { q1 }
      'mov rcx, [rsp]',
      'xor ecx, 63',
      'shr rax, cl',                             { q0 = q1 >> (63 - n) }
      'test rax, rax',
      'jz .q0',
      'sub rax, 1',
    '.q0:',
      'mov [rsp+16], rax',
      'mov rcx, [rsp+48]',
      'mul rcx',                                 { q0 * R lo }
      'mov rcx, [rsp+16]',
      'imul rcx, [rsp+56]',
      'add rdx, rcx',                            { q0 * R }
      'mov rcx, rax',
      'mov rax, [rsp+64]',
      'sub rax, rcx',
      'mov rcx, rdx',
      'mov rdx, [rsp+72]',
      'sbb rdx, rcx',                            { rem = L - q0 * R }
      'cmp rax, [rsp+48]',
      'mov rcx, rdx',
      'sbb rcx, [rsp+56]',
      'jb .fix',                                 { rem < R: q0 stands }
      'sub rax, [rsp+48]',
      'sbb rdx, [rsp+56]',
      'mov rcx, [rsp+16]',
      'add rcx, 1',
      'mov [rsp+16], rcx',
    '.fix:',
      'jmp .done',
    '.narrow:',
      'mov rcx, [rsp+48]',
      'mov rax, [rsp+72]',
      'xor edx, edx',
      'div rcx',
      'mov rax, [rsp+64]',
      'div rcx',
      'mov rax, rdx',
      'xor edx, edx',
    '.done:']);
  if signed then
  begin
    if wantMod then EmitAsmX64(['mov rcx, [rsp+32]'])
    else EmitAsmX64(['mov rcx, [rsp+24]']);
    EmitAsmX64(['xor rax, rcx', 'xor rdx, rcx', 'sub rax, rcx', 'sbb rdx, rcx']);
  end;
  EmitAsmX64(['add rsp, 80']);
end;

procedure I128EmitBinop(node: Integer);
var op: Integer; uns: Boolean;
begin
  op := IRC[node];
  if (op = Ord(tkShl)) or (op = Ord(tkShr)) or (op = Ord(tkShrLogical)) then
  begin
    I128EmitShift(node);
    Exit;
  end;
  if (op = Ord(tkDiv)) or (op = Ord(tkMod)) then
  begin
    { signed unless an operand is unsigned 128-bit (C's usual conversions:
      a narrower unsigned operand converts to the signed 128-bit type) }
    I128EmitDivMod(node, op = Ord(tkMod),
      (IntToTypeKind(IRTk[IRA[node]]) <> tyUInt128) and (IntToTypeKind(IRTk[IRB[node]]) <> tyUInt128));
    Exit;
  end;
  { left -> [rsp] (lo), [rsp+8] (hi); right -> rdx:rax }
  I128EmitValue(IRA[node]);
  EmitAsmX64(['push rdx', 'push rax']);
  I128EmitValue(IRB[node]);
  uns := (IntToTypeKind(IRTk[IRA[node]]) = tyUInt128) or
         (IntToTypeKind(IRTk[IRB[node]]) = tyUInt128);
  if op = Ord(tkPlus) then
    EmitAsmX64(['add rax, [rsp]', 'adc rdx, [rsp+8]'])
  else if op = Ord(tkMinus) then
    EmitAsmX64([
      'mov rcx, rax',
      'mov rax, [rsp]',
      'sub rax, rcx',                          { CF survives the two movs }
      'mov rcx, rdx',
      'mov rdx, [rsp+8]',
      'sbb rdx, rcx'])
  else if op = Ord(tkAnd) then
    EmitAsmX64(['and rax, [rsp]', 'and rdx, [rsp+8]'])
  else if op = Ord(tkOr) then
    EmitAsmX64(['or rax, [rsp]', 'or rdx, [rsp+8]'])
  else if op = Ord(tkXor) then
    EmitAsmX64(['xor rax, [rsp]', 'xor rdx, [rsp+8]'])
  else if op = Ord(tkStar) then
    { the low 128 bits of L*R: Llo*Rlo in full, plus both cross products'
      low halves into the high word. Lhi*Rhi only reaches bit 128 and up. }
    EmitAsmX64([
      'mov rcx, [rsp+8]',                      { Lhi }
      'imul rcx, rax',                         { Lhi*Rlo }
      'imul rdx, [rsp]',                       { Rhi*Llo }
      'add rcx, rdx',
      'mov rdx, [rsp]',                        { Llo }
      'mul rdx',                               { rdx:rax = Rlo*Llo }
      'add rdx, rcx'])
  else if (op = Ord(tkEq)) or (op = Ord(tkNeq)) then
  begin
    EmitAsmX64(['xor rax, [rsp]', 'xor rdx, [rsp+8]', 'or rax, rdx']);
    if op = Ord(tkEq) then EmitAsmX64(['setz al']) else EmitAsmX64(['setnz al']);
    EmitAsmX64(['movzx eax, al']);
  end
  else if (op = Ord(tkLt)) or (op = Ord(tkGe)) then
  begin
    { flags of L - R }
    EmitAsmX64(['mov rcx, [rsp]', 'cmp rcx, rax', 'mov rcx, [rsp+8]', 'sbb rcx, rdx']);
    if op = Ord(tkLt) then
    begin
      if uns then EmitAsmX64(['setb al']) else EmitAsmX64(['setl al']);
    end
    else
    begin
      if uns then EmitAsmX64(['setae al']) else EmitAsmX64(['setge al']);
    end;
    EmitAsmX64(['movzx eax, al']);
  end
  else if (op = Ord(tkGt)) or (op = Ord(tkLe)) then
  begin
    { flags of R - L: L > R is R < L, L <= R is R >= L }
    EmitAsmX64(['cmp rax, [rsp]', 'mov rcx, rdx', 'sbb rcx, [rsp+8]']);
    if op = Ord(tkGt) then
    begin
      if uns then EmitAsmX64(['setb al']) else EmitAsmX64(['setl al']);
    end
    else
    begin
      if uns then EmitAsmX64(['setae al']) else EmitAsmX64(['setge al']);
    end;
    EmitAsmX64(['movzx eax, al']);
  end
  else
    Error('__int128: operator ' + AIntToStr(op) + ' is not supported yet (feature-c-int128-and-attribute-mode)');
  EmitAsmX64(['add rsp, 16']);
end;

procedure I128EmitNode(node: Integer);
var saved: Boolean;
begin
  case IRKind[node] of
    IR_CONST_INT:
      begin
        { a constant is folded as a 64-bit value: sign-extend it }
        MovRaxImm(IRIVal[node]);
        EmitAsmX64(['cqo']);
      end;
    IR_LOAD_SYM:
      I128LoadSym(IRA[node]);
    IR_STORE_SYM:
      begin
        I128EmitValue(IRB[node]);
        I128StoreSym(IRA[node]);
      end;
    IR_LOAD_MEM:
      begin
        IREmitNode(IRA[node]);
        EmitAsmX64(['mov rdx, [rax+8]', 'mov rax, [rax]']);
      end;
    IR_STORE_MEM:
      begin
        I128EmitValue(IRB[node]);
        EmitAsmX64(['push rdx', 'push rax']);
        saved := InLValueWrite;
        InLValueWrite := True;
        IREmitNode(IRA[node]);
        InLValueWrite := saved;
        EmitAsmX64([
          'pop rcx', 'mov [rax], rcx',
          'pop rcx', 'mov [rax+8], rcx']);
      end;
    IR_BINOP:
      I128EmitBinop(node);
    IR_NEG:
      begin
        I128EmitValue(IRA[node]);
        EmitAsmX64(['neg rax', 'adc rdx, 0', 'neg rdx']);
      end;
    IR_NOT:
      begin
        I128EmitValue(IRA[node]);
        if I128Node(node) then
          EmitAsmX64(['not rax', 'not rdx'])
        else
          EmitAsmX64(['or rax, rdx', 'setz al', 'movzx eax, al']);   { logical ! }
      end;
  end;
end;
