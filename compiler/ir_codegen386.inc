{ ===== IR -> i386 machine code (cross target, minimal and growing) =====

  Vertical slices of the target-parameterized backend
  (feature-target-i386). Deliberately NOT a fork of the 4k-line x86-64
  emitter: ops are added one by one as they are needed, and any IR
  construct this walker does not know is a hard compile error — a cross
  target must refuse, never mis-compile. The x86-64 path is untouched;
  IREmitMachineCode dispatches here when TargetArch = TARGET_I386.

  i386 conventions used: int 0x80 syscalls (eax=nr, ebx/ecx/edx args),
  absolute 4-byte data refs (EmitDataRef emits 4 bytes under this target,
  patched by writeELF32). Value model mirrors x86-64: expression results
  in eax; binop = eval left, push, eval right, mov ecx,eax, pop eax.
  Jump and setcc encodings are REX-free and identical to x86-64, so label
  handling and EmitSetcc are shared. }

procedure EmitSetcc(opTk: Integer; signed: Boolean); forward;

procedure IREmitNode386(node: Integer); forward;

procedure EmitwriteInt386;
{ eax = signed 32-bit value -> decimal on stdout. Transcription of
  symtab.inc EmitwriteInt to 32-bit registers and the int 0x80 write. }
var jnsOff, loopStart: Integer;
begin
  EmitB($85); EmitB($C0);                          { test eax, eax }
  EmitB($79); jnsOff := CodeLen; EmitB(0);         { jns .positive }
  EmitB($F7); EmitB($D8);                          { neg eax }
  EmitB($50);                                      { push eax }
  EmitwriteSyscall(MINUS_OFFSET, 1);               { clobbers eax..edx }
  EmitB($58);                                      { pop eax }
  Code[jnsOff] := Byte(CodeLen - (jnsOff + 1));
  EmitB($31); EmitB($C9);                          { xor ecx, ecx  (digit count) }
  EmitB($BB); EmitI32(10);                         { mov ebx, 10 }
  EmitB($BF); EmitDataRef(INTBUF_OFFSET + INTBUF_SIZE); { mov edi, buf end }
  loopStart := CodeLen;
  EmitB($31); EmitB($D2);                          { xor edx, edx }
  EmitB($F7); EmitB($F3);                          { div ebx }
  EmitB($80); EmitB($C2); EmitB($30);              { add dl, '0' }
  EmitB($4F);                                      { dec edi }
  EmitB($88); EmitB($17);                          { mov [edi], dl }
  EmitB($41);                                      { inc ecx }
  EmitB($85); EmitB($C0);                          { test eax, eax }
  EmitB($75); EmitB(Byte(loopStart - (CodeLen + 1))); { jnz .loop }
  { write(1, edi, ecx): eax=4, ebx=1, ecx=buf, edx=len }
  EmitB($89); EmitB($CA);                          { mov edx, ecx }
  EmitB($89); EmitB($F9);                          { mov ecx, edi }
  EmitB($BB); EmitI32(STDOUT);                     { mov ebx, 1 }
  EmitB($B8); EmitI32(4);                          { mov eax, 4 }
  EmitB($CD); EmitB($80);                          { int 0x80 }
end;

procedure IREmit386CheckScalarSym(symIdx: Integer; const what: AnsiString);
{ v1 symbol model: 8-byte BSS slots (parser allocates with 64-bit sizes), of
  which i386 code reads/writes the low 4 bytes. Only zero-initialized global
  scalars are safe under that model; refuse everything else. }
begin
  if (symIdx < 0) or (symIdx >= SymCount) then
    Error('target i386: bad symbol in ' + what);
  if Syms[symIdx].Kind <> skGlobal then
    Error('target i386: only global variables supported yet (' + what + ')');
  if Syms[symIdx].IsArray then
    Error('target i386: arrays not yet supported');
  if not TypeIsOrdinal(Syms[symIdx].TypeKind) then
    Error('target i386: only ordinal variables supported yet');
end;

procedure IREmitNode386(node: Integer);
var
  valNode, si, left, right, op: Integer;
  sVal: AnsiString;
  emsg: AnsiString;
  tk: TTypeKind;
begin
  if node = -1 then Exit;
  case IRKind[node] of
    IR_NOP, IR_BLOCK: ;

    IR_CONST_INT:
      begin
        if (IRIVal[node] > 2147483647) or (IRIVal[node] < -2147483648) then
          Error('target i386: integer constant exceeds 32 bits');
        EmitB($B8); EmitI32(IRIVal[node]);           { mov eax, imm32 }
      end;

    IR_LOAD_SYM:
      begin
        IREmit386CheckScalarSym(IRA[node], 'load');
        EmitB($A1); EmitGlobRef(Syms[IRA[node]].Offset); { mov eax, [abs32] }
      end;

    IR_STORE_SYM:
      begin
        IREmit386CheckScalarSym(IRA[node], 'store');
        IREmitNode386(IRB[node]);
        EmitB($A3); EmitGlobRef(Syms[IRA[node]].Offset); { mov [abs32], eax }
      end;

    IR_BINOP:
      begin
        left := IRA[node];
        right := IRB[node];
        op := IRC[node];
        tk := IntToTypeKind(IRTk[node]);
        if not (TypeIsOrdinal(tk) or (tk = tyBoolean)) then
          Error('target i386: non-integer binop not yet supported');
        IREmitNode386(left);
        EmitB($50);                                  { push eax }
        IREmitNode386(right);
        EmitB($89); EmitB($C1);                      { mov ecx, eax }
        EmitB($58);                                  { pop eax }
        if op = Ord(tkPlus) then begin EmitB($01); EmitB($C8); end       { add eax, ecx }
        else if op = Ord(tkMinus) then begin EmitB($29); EmitB($C8); end { sub eax, ecx }
        else if op = Ord(tkStar) then begin EmitB($0F); EmitB($AF); EmitB($C1); end { imul eax, ecx }
        else if op = Ord(tkDiv) then begin EmitB($99); EmitB($F7); EmitB($F9); end { cdq; idiv ecx }
        else if op = Ord(tkMod) then
        begin
          EmitB($99); EmitB($F7); EmitB($F9);        { cdq; idiv ecx }
          EmitB($89); EmitB($D0);                    { mov eax, edx }
        end
        else if op = Ord(tkAnd) then begin EmitB($21); EmitB($C8); end   { and eax, ecx }
        else if op = Ord(tkOr) then begin EmitB($09); EmitB($C8); end    { or eax, ecx }
        else if op = Ord(tkShl) then begin EmitB($D3); EmitB($E0); end   { shl eax, cl }
        else if op = Ord(tkIdent) then begin EmitB($D3); EmitB($E8); end { 'shr' parses as ident; shr eax, cl }
        else if (op = Ord(tkEq)) or (op = Ord(tkNeq)) or (op = Ord(tkLt)) or
                (op = Ord(tkLe)) or (op = Ord(tkGt)) or (op = Ord(tkGe)) then
        begin
          EmitB($39); EmitB($C8);                    { cmp eax, ecx }
          EmitSetcc(op, True);                       { REX-free; shared with x86-64 }
        end
        else
          Error('target i386: binop operator not yet supported');
      end;

    IR_NEG:
      begin
        IREmitNode386(IRA[node]);
        EmitB($F7); EmitB($D8);                      { neg eax }
      end;

    IR_NOT:
      begin
        IREmitNode386(IRA[node]);
        if TypeIsOrdinal(IntToTypeKind(IRTk[node])) and
           (IntToTypeKind(IRTk[node]) <> tyBoolean) then
        begin
          EmitB($F7); EmitB($D0);                    { not eax }
        end
        else
        begin
          EmitB($83); EmitB($F0); EmitB($01);        { xor eax, 1 }
        end;
      end;

    IR_WRITE:
      begin
        valNode := IRA[node];
        if IRB[node] > 0 then
          Error('target i386: field width in write not yet supported');
        if IRKind[valNode] = IR_CONST_STR then
        begin
          sVal := GetTokenStrFromRaw(IRA[valNode], IRB[valNode]);
          si := InternStr(sVal);
          if Strs[si].Len > 0 then
            EmitwriteSyscall(Strs[si].Offset + 8, Strs[si].Len);
        end
        else
        begin
          tk := IntToTypeKind(IRTk[node]);
          if TypeIsOrdinal(tk) and (tk <> tyBoolean) and (tk <> tyChar) then
          begin
            IREmitNode386(valNode);
            EmitwriteInt386;
          end
          else
            Error('target i386: write of this operand not yet supported');
        end;
      end;

    IR_WRITELN:
      EmitwriteSyscall(NEWLINE_OFFSET, 1);

    else
      begin
        emsg := 'target i386: IR op not yet supported: ';
        emsg := emsg + IROpName(IRKind[node]);
        Error(emsg);
      end;
  end;
end;

procedure IREmitMachineCode386;
var i, lblId, pos, targetOffset, f: Integer;
    LabelPositions: array[0..MAX_IR-1] of Integer;
    LabelFixupPos: array[0..2047] of Integer;
    LabelFixupTarget: array[0..2047] of Integer;
    LabelFixupCount: Integer;
begin
  for i := 0 to MAX_IR - 1 do
    LabelPositions[i] := -1;
  LabelFixupCount := 0;

  for i := 0 to IRCount - 1 do
  begin
    case IRKind[i] of
      IR_LABEL:
        begin
          lblId := Integer(IRIVal[i]);
          if (lblId >= 0) and (lblId < MAX_IR) then
            LabelPositions[lblId] := CodeLen;
        end;

      IR_JUMP:
        begin
          lblId := IRA[i];
          EmitB($E9);
          if LabelPositions[lblId] <> -1 then
            EmitI32(LabelPositions[lblId] - (CodeLen + 4))
          else
          begin
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitI32(0);
          end;
        end;

      IR_JUMP_IF_FALSE:
        begin
          lblId := IRA[i];
          IREmitNode386(IRB[i]);                     { condition -> eax }
          EmitB($85); EmitB($C0);                    { test eax, eax }
          EmitB($0F); EmitB($84);                    { jz rel32 }
          if LabelPositions[lblId] <> -1 then
            EmitI32(LabelPositions[lblId] - (CodeLen + 4))
          else
          begin
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitI32(0);
          end;
        end;

      IR_STORE_SYM, IR_WRITE, IR_WRITELN:
        IREmitNode386(i);

      IR_NOP, IR_CONST_STR, IR_CONST_INT, IR_BLOCK,
      IR_LOAD_SYM, IR_BINOP, IR_NEG, IR_NOT: ;       { operands, emitted by parents }

      else
        IREmitNode386(i); { unknown statement op -> hard error inside }
    end;
  end;

  for f := 0 to LabelFixupCount - 1 do
  begin
    lblId := LabelFixupTarget[f];
    pos := LabelFixupPos[f];
    targetOffset := LabelPositions[lblId];
    if targetOffset = -1 then Error('Unresolved forward jump in i386 IR codegen');
    Patch32(pos, targetOffset - (pos + 4));
  end;
end;
