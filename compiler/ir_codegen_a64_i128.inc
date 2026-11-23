{ ir_codegen_a64_i128.inc -- GCC's 128-bit integers on aarch64.

  The x86-64 model (ir_codegen_i128.inc) moved to this ISA: an `__int128`
  value is carried in x0 (low) : x1 (high), which is also where AAPCS64
  returns one, so a call result needs no shuffling. A narrower consumer reads
  x0, which is C's conversion to the narrower type. A binop evaluates the left
  operand, parks it on the stack, evaluates the right into x0:x1 and takes the
  left back into x2:x3. Scratch is x2..x7 and x9..x14; x8 and the resident
  x19..x24 are not touched.

  The fixed sequences below are generated: their assembly source is
  tools/a64_i128/snippets.s and tools/a64_i128/gen.py encodes it with clang
  (the comment on each word is its source line). Their branches stay inside
  the sequence. Edit the .s and regenerate rather than editing a word.
  feature-c-int128-other-targets-float-and-narrow-modes }

procedure A64I128Add;
begin
  EmitI32($AB000040);  { adds x0, x2, x0 }
  EmitI32($9A010061);  { adc x1, x3, x1 }
end;

procedure A64I128Sub;
begin
  EmitI32($EB000040);  { subs x0, x2, x0 }
  EmitI32($DA010061);  { sbc x1, x3, x1 }
end;

procedure A64I128And;
begin
  EmitI32($8A000040);  { and x0, x2, x0 }
  EmitI32($8A010061);  { and x1, x3, x1 }
end;

procedure A64I128Or;
begin
  EmitI32($AA000040);  { orr x0, x2, x0 }
  EmitI32($AA010061);  { orr x1, x3, x1 }
end;

procedure A64I128Xor;
begin
  EmitI32($CA000040);  { eor x0, x2, x0 }
  EmitI32($CA010061);  { eor x1, x3, x1 }
end;

procedure A64I128Mul;
begin
  EmitI32($9B007C44);  { mul x4, x2, x0 }
  EmitI32($9BC07C45);  { umulh x5, x2, x0 }
  EmitI32($9B011445);  { madd x5, x2, x1, x5 }
  EmitI32($9B001461);  { madd x1, x3, x0, x5 }
  EmitI32($AA0403E0);  { mov x0, x4 }
end;

procedure A64I128CmpEqNe;
begin
  EmitI32($CA000044);  { eor x4, x2, x0 }
  EmitI32($CA010065);  { eor x5, x3, x1 }
  EmitI32($AA050080);  { orr x0, x4, x5 }
  EmitI32($F100001F);  { cmp x0, #0 }
end;

procedure A64I128CmpLR;
begin
  EmitI32($EB00005F);  { cmp x2, x0 }
  EmitI32($FA01007F);  { sbcs xzr, x3, x1 }
end;

procedure A64I128CmpRL;
begin
  EmitI32($EB02001F);  { cmp x0, x2 }
  EmitI32($FA03003F);  { sbcs xzr, x1, x3 }
end;

procedure A64I128Shl;
begin
  EmitI32($92401804);  { and x4, x0, #127 }
  EmitI32($37300104);  { tbnz x4, #6, big }
  EmitI32($9AC42061);  { lsl x1, x3, x4 }
  EmitI32($D341FC45);  { lsr x5, x2, #1 }
  EmitI32($AA2403E6);  { mvn x6, x4 }
  EmitI32($9AC624A5);  { lsr x5, x5, x6 }
  EmitI32($AA050021);  { orr x1, x1, x5 }
  EmitI32($9AC42040);  { lsl x0, x2, x4 }
  EmitI32($14000003);  { b done }
  EmitI32($9AC42041);  { big: lsl x1, x2, x4 }
  EmitI32($AA1F03E0);  { mov x0, xzr }
end;

procedure A64I128Shr;
begin
  EmitI32($92401804);  { and x4, x0, #127 }
  EmitI32($37300104);  { tbnz x4, #6, big }
  EmitI32($9AC42440);  { lsr x0, x2, x4 }
  EmitI32($D37FF865);  { lsl x5, x3, #1 }
  EmitI32($AA2403E6);  { mvn x6, x4 }
  EmitI32($9AC620A5);  { lsl x5, x5, x6 }
  EmitI32($AA050000);  { orr x0, x0, x5 }
  EmitI32($9AC42461);  { lsr x1, x3, x4 }
  EmitI32($14000003);  { b done }
  EmitI32($9AC42460);  { big: lsr x0, x3, x4 }
  EmitI32($AA1F03E1);  { mov x1, xzr }
end;

procedure A64I128Sar;
begin
  EmitI32($92401804);  { and x4, x0, #127 }
  EmitI32($37300104);  { tbnz x4, #6, big }
  EmitI32($9AC42440);  { lsr x0, x2, x4 }
  EmitI32($D37FF865);  { lsl x5, x3, #1 }
  EmitI32($AA2403E6);  { mvn x6, x4 }
  EmitI32($9AC620A5);  { lsl x5, x5, x6 }
  EmitI32($AA050000);  { orr x0, x0, x5 }
  EmitI32($9AC42861);  { asr x1, x3, x4 }
  EmitI32($14000003);  { b done }
  EmitI32($9AC42860);  { big: asr x0, x3, x4 }
  EmitI32($937FFC61);  { asr x1, x3, #63 }
end;

procedure A64I128Neg;
begin
  EmitI32($EB0003E0);  { negs x0, x0 }
  EmitI32($DA0103E1);  { ngc x1, x1 }
end;

procedure A64I128Not;
begin
  EmitI32($AA2003E0);  { mvn x0, x0 }
  EmitI32($AA2103E1);  { mvn x1, x1 }
end;

procedure A64I128LogNot;
begin
  EmitI32($AA010000);  { orr x0, x0, x1 }
  EmitI32($F100001F);  { cmp x0, #0 }
  EmitI32($9A9F17E0);  { cset x0, eq }
end;

procedure A64I128SignsSigned;
begin
  EmitI32($937FFC6C);  { asr x12, x3, #63 }
  EmitI32($937FFC2D);  { asr x13, x1, #63 }
  EmitI32($CA0C0042);  { eor x2, x2, x12 }
  EmitI32($CA0C0063);  { eor x3, x3, x12 }
  EmitI32($EB0C0042);  { subs x2, x2, x12 }
  EmitI32($DA0C0063);  { sbc x3, x3, x12 }
  EmitI32($CA0D0000);  { eor x0, x0, x13 }
  EmitI32($CA0D0021);  { eor x1, x1, x13 }
  EmitI32($EB0D0000);  { subs x0, x0, x13 }
  EmitI32($DA0D0021);  { sbc x1, x1, x13 }
end;

procedure A64I128SignsUnsigned;
begin
  EmitI32($AA1F03EC);  { mov x12, xzr }
  EmitI32($AA1F03ED);  { mov x13, xzr }
end;

procedure A64I128DivCore;
begin
  EmitI32($AA1F03E6);  { mov x6, xzr }
  EmitI32($AA1F03E7);  { mov x7, xzr }
  EmitI32($D2801009);  { mov x9, #128 }
  EmitI32($93C6FCE7);  { loop: extr x7, x7, x6, #63 }
  EmitI32($93C3FCC6);  { extr x6, x6, x3, #63 }
  EmitI32($93C2FC63);  { extr x3, x3, x2, #63 }
  EmitI32($D37FF842);  { lsl x2, x2, #1 }
  EmitI32($EB0000CA);  { subs x10, x6, x0 }
  EmitI32($FA0100EB);  { sbcs x11, x7, x1 }
  EmitI32($54000083);  { b.lo skip }
  EmitI32($AA0A03E6);  { mov x6, x10 }
  EmitI32($AA0B03E7);  { mov x7, x11 }
  EmitI32($B2400042);  { orr x2, x2, #1 }
  EmitI32($F1000529);  { skip: subs x9, x9, #1 }
  EmitI32($54FFFEA1);  { b.ne loop }
end;

procedure A64I128TakeQuot;
begin
  EmitI32($CA0D018C);  { eor x12, x12, x13 }
  EmitI32($AA0203E0);  { mov x0, x2 }
  EmitI32($AA0303E1);  { mov x1, x3 }
  EmitI32($CA0C0000);  { eor x0, x0, x12 }
  EmitI32($CA0C0021);  { eor x1, x1, x12 }
  EmitI32($EB0C0000);  { subs x0, x0, x12 }
  EmitI32($DA0C0021);  { sbc x1, x1, x12 }
end;

procedure A64I128TakeRem;
begin
  EmitI32($AA0603E0);  { mov x0, x6 }
  EmitI32($AA0703E1);  { mov x1, x7 }
  EmitI32($CA0C0000);  { eor x0, x0, x12 }
  EmitI32($CA0C0021);  { eor x1, x1, x12 }
  EmitI32($EB0C0000);  { subs x0, x0, x12 }
  EmitI32($DA0C0021);  { sbc x1, x1, x12 }
end;

procedure A64I128ToDoubleSigned;
begin
  EmitI32($937FFC29);  { asr x9, x1, #63 }
  EmitI32($CA090000);  { eor x0, x0, x9 }
  EmitI32($CA090021);  { eor x1, x1, x9 }
  EmitI32($EB090000);  { subs x0, x0, x9 }
  EmitI32($DA090021);  { sbc x1, x1, x9 }
end;

procedure A64I128ToDoubleCore;
begin
  EmitI32($B5000081);  { cbnz x1, big }
  EmitI32($9E630000);  { ucvtf d0, x0 }
  EmitI32($9E660000);  { fmov x0, d0 }
  EmitI32($14000013);  { b sign }
  EmitI32($DAC0102A);  { big: clz x10, x1 }
  EmitI32($D280080B);  { mov x11, #64 }
  EmitI32($CB0A016B);  { sub x11, x11, x10 }
  EmitI32($F101017F);  { cmp x11, #64 }
  EmitI32($540000C0);  { b.eq s64 }
  EmitI32($9ACA200D);  { lsl x13, x0, x10 }
  EmitI32($9ACB2400);  { lsr x0, x0, x11 }
  EmitI32($9ACA202E);  { lsl x14, x1, x10 }
  EmitI32($AA0E0000);  { orr x0, x0, x14 }
  EmitI32($14000003);  { b stick }
  EmitI32($AA0003ED);  { s64: mov x13, x0 }
  EmitI32($AA0103E0);  { mov x0, x1 }
  EmitI32($F10001BF);  { stick: cmp x13, #0 }
  EmitI32($9A9F07EE);  { cset x14, ne }
  EmitI32($AA0E0000);  { orr x0, x0, x14 }
  EmitI32($9E630000);  { ucvtf d0, x0 }
  EmitI32($9E660000);  { fmov x0, d0 }
  EmitI32($8B0BD000);  { add x0, x0, x11, lsl #52 }
  EmitI32($92410129);  { sign: and x9, x9, #0x8000000000000000 }
  EmitI32($CA090000);  { eor x0, x0, x9 }
end;

procedure A64I128FromDouble;
begin
  EmitI32($AA0003EC);  { mov x12, x0 }
  EmitI32($D374F809);  { ubfx x9, x0, #52, #11 }
  EmitI32($F110F93F);  { cmp x9, #1086 }
  EmitI32($540000A2);  { b.hs big }
  EmitI32($9E670000);  { fmov d0, x0 }
  EmitI32($9E780000);  { fcvtzs x0, d0 }
  EmitI32($937FFC01);  { asr x1, x0, #63 }
  EmitI32($14000011);  { b done }
  EmitI32($D340CC0A);  { big: ubfx x10, x0, #0, #52 }
  EmitI32($B24C014A);  { orr x10, x10, #0x10000000000000 }
  EmitI32($D110CD29);  { sub x9, x9, #1075 }
  EmitI32($F101013F);  { cmp x9, #64 }
  EmitI32($540000C2);  { b.hs wide }
  EmitI32($D280080B);  { mov x11, #64 }
  EmitI32($CB09016B);  { sub x11, x11, x9 }
  EmitI32($9ACB2541);  { lsr x1, x10, x11 }
  EmitI32($9AC92140);  { lsl x0, x10, x9 }
  EmitI32($14000004);  { b sign }
  EmitI32($D1010129);  { wide: sub x9, x9, #64 }
  EmitI32($9AC92141);  { lsl x1, x10, x9 }
  EmitI32($AA1F03E0);  { mov x0, xzr }
  EmitI32($B6F8006C);  { sign: tbz x12, #63, done }
  EmitI32($EB0003E0);  { negs x0, x0 }
  EmitI32($DA0103E1);  { ngc x1, x1 }
end;

function A64I128Node(n: Integer): Boolean;
begin
  Result := (n >= 0) and TypeIsInt128(IntToTypeKind(IRTk[n]));
end;

function A64I128Sym(sym: Integer): Boolean;
begin
  Result := (sym >= 0) and TypeIsInt128(Syms[sym].TypeKind) and (not Syms[sym].IsArray);
end;

{ The same claim as I128Claims on x86-64: a node that produces or consumes a
  128-bit value, except a binop that meets a float, which is float arithmetic
  (A64I128MixedFloat). }
function A64I128Claims(node: Integer): Boolean;
begin
  Result := False;
  case IRKind[node] of
    IR_CONST_INT, IR_LOAD_MEM, IR_STORE_MEM:
      Result := A64I128Node(node);
    IR_LOAD_SYM, IR_STORE_SYM:
      Result := A64I128Sym(IRA[node]);
    IR_BINOP:
      Result := (A64I128Node(node) or A64I128Node(IRA[node]) or A64I128Node(IRB[node])) and
                not TypeIsFloat(IntToTypeKind(IRTk[node])) and
                not TypeIsFloat(IntToTypeKind(IRTk[IRA[node]])) and
                not TypeIsFloat(IntToTypeKind(IRTk[IRB[node]]));
    IR_NEG, IR_NOT:
      Result := A64I128Node(node) or A64I128Node(IRA[node]);
  end;
end;

function A64I128MixedFloat(node: Integer): Boolean;
var lt, rt: TTypeKind;
begin
  lt := IntToTypeKind(IRTk[IRA[node]]);
  rt := IntToTypeKind(IRTk[IRB[node]]);
  Result := (TypeIsInt128(lt) and TypeIsFloat(rt)) or (TypeIsFloat(lt) and TypeIsInt128(rt));
end;

procedure A64I128Push;
begin
  EmitI32($A9BF07E0);    { stp x0, x1, [sp, #-16]! }
end;

procedure A64I128PopLeft;
begin
  EmitI32($A8C10FE2);    { ldp x2, x3, [sp], #16 }
end;

{ The value in x0:x1 converted to double bits in x0, correctly rounded
  (__floattidf): ucvtf when the high word is zero, else shifted to 64 bits
  with a sticky bit and the shift added to the exponent. }
procedure A64I128ToDouble(signed: Boolean);
begin
  if signed then A64I128ToDoubleSigned
  else EmitI32($AA1F03E9);   { mov x9, xzr (no sign) }
  A64I128ToDoubleCore;
end;

{ Widen x0, a value of kind tk, to 128 bits in x0:x1 by its own signedness. }
procedure A64I128Widen(tk: TTypeKind);
var sz: Integer;
begin
  if TypeIsFloat(tk) then
  begin
    A64I128FromDouble;
    Exit;
  end;
  sz := TypeSlotSize(tk);
  if TypeSigned(tk) or (tk = tyUnknown) then
  begin
    if sz = 4 then EmitI32($93407C00)        { sxtw x0, w0 }
    else if sz = 2 then EmitI32($93403C00)   { sxth x0, w0 }
    else if sz = 1 then EmitI32($93401C00);  { sxtb x0, w0 }
    EmitI32($937FFC01);                      { asr x1, x0, #63 }
  end
  else
  begin
    if sz = 4 then EmitI32($2A0003E0)        { mov w0, w0 }
    else if sz = 2 then EmitI32($53003C00)   { uxth w0, w0 }
    else if sz = 1 then EmitI32($53001C00);  { uxtb w0, w0 }
    EmitI32($AA1F03E1);                      { mov x1, xzr }
  end;
end;

{ Evaluate n into x0:x1 as a 128-bit value. }
procedure A64I128EmitValue(n: Integer);
begin
  IREmitNodeAarch64(n);
  if not A64I128Node(n) then A64I128Widen(IntToTypeKind(IRTk[n]));
end;

procedure A64I128SymRefuse(sym: Integer; const what: AnsiString);
begin
  Error('__int128: ' + what + ' of ' + Syms[sym].Name +
        ' is not supported yet on aarch64 (feature-c-int128-other-targets-float-and-narrow-modes)');
end;

procedure A64I128LoadSym(sym: Integer);
begin
  if ResidentRegOf(sym) <> 0 then A64I128SymRefuse(sym, 'a register-resident copy');
  if not (Syms[sym].Kind in [skGlobal, skLocal, skParam]) then A64I128SymRefuse(sym, 'a load');
  EmitLoadVarAddrA64(sym);                   { x0 = its address }
  EmitI32($A9400400);                        { ldp x0, x1, [x0] }
end;

{ Store x0:x1 into sym; x0:x1 keep the value. }
procedure A64I128StoreSym(sym: Integer);
begin
  if ResidentRegOf(sym) <> 0 then A64I128SymRefuse(sym, 'a register-resident copy');
  if not (Syms[sym].Kind in [skGlobal, skLocal, skParam]) then A64I128SymRefuse(sym, 'a store');
  EmitI32($AA0003E2);                        { mov x2, x0 }
  EmitI32($AA0103E3);                        { mov x3, x1 }
  EmitLoadVarAddrA64(sym);                   { x0 = its address (x9 clobbered) }
  EmitI32($A9000C02);                        { stp x2, x3, [x0] }
  EmitI32($AA0203E0);                        { mov x0, x2 }
  EmitI32($AA0303E1);                        { mov x1, x3 }
end;

procedure A64I128EmitBinop(node: Integer);
var op: Integer; uns, signed: Boolean;
begin
  op := IRC[node];
  uns := (IntToTypeKind(IRTk[IRA[node]]) = tyUInt128) or
         (IntToTypeKind(IRTk[IRB[node]]) = tyUInt128);
  if (op = Ord(tkShl)) or (op = Ord(tkShr)) or (op = Ord(tkShrLogical)) then
  begin
    { tkShr is arithmetic (the C parser chose, from the left operand) }
    A64I128EmitValue(IRA[node]);
    A64I128Push;
    IREmitNodeAarch64(IRB[node]);            { the count; its low word if 128-bit }
    A64I128PopLeft;
    if op = Ord(tkShl) then A64I128Shl
    else if op = Ord(tkShr) then A64I128Sar
    else A64I128Shr;
    Exit;
  end;
  A64I128EmitValue(IRA[node]);
  A64I128Push;
  A64I128EmitValue(IRB[node]);
  A64I128PopLeft;                            { left x2:x3, right x0:x1 }
  if (op = Ord(tkDiv)) or (op = Ord(tkMod)) then
  begin
    { signed unless an operand is unsigned 128-bit, as on x86-64 }
    signed := not uns;
    if signed then A64I128SignsSigned else A64I128SignsUnsigned;
    A64I128DivCore;
    if op = Ord(tkDiv) then A64I128TakeQuot else A64I128TakeRem;
  end
  else if op = Ord(tkPlus) then A64I128Add
  else if op = Ord(tkMinus) then A64I128Sub
  else if op = Ord(tkAnd) then A64I128And
  else if op = Ord(tkOr) then A64I128Or
  else if op = Ord(tkXor) then A64I128Xor
  else if op = Ord(tkStar) then A64I128Mul
  else if (op = Ord(tkEq)) or (op = Ord(tkNeq)) then
  begin
    A64I128CmpEqNe;
    if op = Ord(tkEq) then EmitI32($9A9F17E0)    { cset x0, eq }
    else EmitI32($9A9F07E0);                     { cset x0, ne }
  end
  else if (op = Ord(tkLt)) or (op = Ord(tkGe)) then
  begin
    A64I128CmpLR;                                { flags of L - R }
    if op = Ord(tkLt) then
    begin
      if uns then EmitI32($9A9F27E0) else EmitI32($9A9FA7E0);   { cset x0, lo / lt }
    end
    else
    begin
      if uns then EmitI32($9A9F37E0) else EmitI32($9A9FB7E0);   { cset x0, hs / ge }
    end;
  end
  else if (op = Ord(tkGt)) or (op = Ord(tkLe)) then
  begin
    A64I128CmpRL;                                { flags of R - L }
    if op = Ord(tkGt) then
    begin
      if uns then EmitI32($9A9F27E0) else EmitI32($9A9FA7E0);   { cset x0, lo / lt }
    end
    else
    begin
      if uns then EmitI32($9A9F37E0) else EmitI32($9A9FB7E0);   { cset x0, hs / ge }
    end;
  end
  else
    Error('__int128: operator ' + AIntToStr(op) +
          ' is not supported yet on aarch64 (feature-c-int128-other-targets-float-and-narrow-modes)');
end;

procedure A64I128EmitNode(node: Integer);
var saved: Boolean;
begin
  case IRKind[node] of
    IR_CONST_INT:
      begin
        { a constant is folded as a 64-bit value: sign-extend it, as x86-64 }
        EmitLoadImmA64(0, IRIVal[node]);
        EmitI32($937FFC01);                      { asr x1, x0, #63 }
      end;
    IR_LOAD_SYM:
      A64I128LoadSym(IRA[node]);
    IR_STORE_SYM:
      begin
        A64I128EmitValue(IRB[node]);
        A64I128StoreSym(IRA[node]);
      end;
    IR_LOAD_MEM:
      begin
        IREmitNodeAarch64(IRA[node]);            { address }
        EmitI32($A9400400);                      { ldp x0, x1, [x0] }
      end;
    IR_STORE_MEM:
      begin
        A64I128EmitValue(IRB[node]);
        A64I128Push;
        saved := InLValueWrite;
        InLValueWrite := True;
        IREmitNodeAarch64(IRA[node]);            { address }
        InLValueWrite := saved;
        A64I128PopLeft;
        EmitI32($A9000C02);                      { stp x2, x3, [x0] }
        EmitI32($AA0203E0);                      { mov x0, x2 }
        EmitI32($AA0303E1);                      { mov x1, x3 }
      end;
    IR_BINOP:
      A64I128EmitBinop(node);
    IR_NEG:
      begin
        A64I128EmitValue(IRA[node]);
        A64I128Neg;
      end;
    IR_NOT:
      begin
        A64I128EmitValue(IRA[node]);
        if A64I128Node(node) then A64I128Not else A64I128LogNot;
      end;
  end;
end;

{ x9 := a C-call argument whose 16-byte temp is at [sp, #sz]: the word in it
  (a scalar, or an aggregate's address), or for an __int128, whose two words
  ARE the temp, the temp's address, which the aggregate loaders read both
  halves from. }
procedure A64ArgTempToX9(inTemp: Boolean; sz: Integer);
begin
  if inTemp then
  begin
    if sz > 4095 then
      Error('__int128: an argument temp past add''s 4095-byte reach on aarch64 (feature-c-int128-other-targets-float-and-narrow-modes)');
    EmitI32($910003E9 or (sz shl 10));             { add x9, sp, #sz }
  end
  else
    EmitI32($F94003E9 or ((sz div 8) shl 10));     { ldr x9, [sp, #sz] }
end;

{ n's value as double bits in x0: an __int128 converted while x0:x1 hold it,
  anything else exactly as IREmitNodeAarch64 leaves it. }
procedure A64I128OperandAsDouble(n: Integer);
begin
  IREmitNodeAarch64(n);
  if A64I128Node(n) then
    A64I128ToDouble(IntToTypeKind(IRTk[n]) = tyInt128);
end;
