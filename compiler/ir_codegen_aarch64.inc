{ ===== IR -> AArch64 machine code (cross target, minimal and growing) =====

  AArch64 (ARM64) target backend. Operates on fixed-width 32-bit instructions.
  Registers used: x0 for expression results, x1..x7 for arguments/temporaries. }

procedure IREmitNodeAarch64(node: Integer); forward;

procedure EmitLoadDataRefA64(rd, dataOff: Integer);
{ Load a data address (or descriptor sentinel) into x[rd]. Inline literal loaded
  as a 32-bit word, zero-extended — binaries map below 4 GiB. }
begin
  EmitI32($18000040 or rd);  { ldr w[rd], [pc+8] }
  EmitI32($14000002);        { b [pc+8] }
  EmitDataRef(dataOff);
end;

procedure EmitHeapAllocLockedA64;
{ x0 = requested payload bytes. Returns payload pointer in x0. Delegates to the
  Pascal PXXAlloc(size, align=8). Threadsafe locking is x86-64-only. }
var pi: Integer;
begin
  EmitLoadImmA64(1, 8);              { mov x1, #8 (align) }
  pi := FindProc('PXXAlloc');
  if pi < 0 then Error('compiler error: Alloc helper not found in builtin unit');
  EmitCallProc(pi);                 { x0 = pointer }
end;

procedure EmitHeapFreeLockedA64;
{ x0 = payload pointer. Delegates to PXXFree(p). nil ignored inside. }
var pi: Integer;
begin
  pi := FindProc('PXXFree');
  if pi < 0 then Error('compiler error: Free helper not found in builtin unit');
  EmitCallProc(pi);
end;

procedure EmitLoadVarA64(idx: Integer);
var tk: TTypeKind; sz: Integer; sgn: Boolean;
begin
  tk := Syms[idx].TypeKind;
  sz := TypeSize(tk);
  sgn := TypeSigned(tk);

  if Syms[idx].Kind = skGlobal then
  begin
    EmitI32($18000041);  { ldr w1, [pc+8] }
    EmitI32($14000002);  { b [pc+8] }
    EmitGlobRef(Syms[idx].Offset);
    if sz = 1 then
    begin
      if sgn then EmitI32($39C00020) else EmitI32($39400020);
    end
    else if sz = 2 then
    begin
      if sgn then EmitI32($79C00020) else EmitI32($79400020);
    end
    else if sz = 4 then
      EmitI32($B9400020)
    else
      EmitI32($F9400020);
  end
  else
  begin
    EmitLoadImmA64(9, Syms[idx].Offset);
    EmitI32($8B0903A9);  { add x9, x29, x9 }
    if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
    begin
      EmitI32($F9400121);  { ldr x1, [x9] }
      if sz = 1 then
      begin
        if sgn then EmitI32($39C00020) else EmitI32($39400020);
      end
      else if sz = 2 then
      begin
        if sgn then EmitI32($79C00020) else EmitI32($79400020);
      end
      else if sz = 4 then
        EmitI32($B9400020)
      else
        EmitI32($F9400020);
    end
    else
    begin
      if sz = 1 then
      begin
        if sgn then EmitI32($39C00120) else EmitI32($39400120);
      end
      else if sz = 2 then
      begin
        if sgn then EmitI32($79C00120) else EmitI32($79400120);
      end
      else if sz = 4 then
        EmitI32($B9400120)
      else
        EmitI32($F9400120);
    end;
  end;
end;

procedure EmitStoreVarA64(idx: Integer);
var tk: TTypeKind; sz: Integer;
begin
  tk := Syms[idx].TypeKind;
  sz := TypeSize(tk);

  if Syms[idx].Kind = skGlobal then
  begin
    EmitI32($18000041);  { ldr w1, [pc+8] }
    EmitI32($14000002);  { b [pc+8] }
    EmitGlobRef(Syms[idx].Offset);
    if sz = 1 then
      EmitI32($39000020)  { strb w0, [x1] }
    else if sz = 2 then
      EmitI32($79000020)  { strh w0, [x1] }
    else if sz = 4 then
      EmitI32($B9000020)  { str w0, [x1] }
    else
      EmitI32($F9000020); { str x0, [x1] }
  end
  else
  begin
    EmitLoadImmA64(9, Syms[idx].Offset);
    EmitI32($8B0903A9);  { add x9, x29, x9 }
    if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
    begin
      EmitI32($F9400121);  { ldr x1, [x9] }
      if sz = 1 then
        EmitI32($39000020)  { strb w0, [x1] }
      else if sz = 2 then
        EmitI32($79000020)  { strh w0, [x1] }
      else if sz = 4 then
        EmitI32($B9000020)  { str w0, [x1] }
      else
        EmitI32($F9000020); { str x0, [x1] }
    end
    else
    begin
      if sz = 1 then
        EmitI32($39000120)  { strb w0, [x9] }
      else if sz = 2 then
        EmitI32($79000120)  { strh w0, [x9] }
      else if sz = 4 then
        EmitI32($B9000120)  { str w0, [x9] }
      else
        EmitI32($F9000120); { str x0, [x9] }
    end;
  end;
end;

procedure EmitLoadVarAddrA64(idx: Integer);
begin
  if Syms[idx].Kind = skGlobal then
  begin
    EmitI32($18000040);  { ldr w0, [pc+8] }
    EmitI32($14000002);  { b [pc+8] }
    EmitGlobRef(Syms[idx].Offset);
  end
  else if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
  begin
    EmitLoadImmA64(9, Syms[idx].Offset);
    EmitI32($8B0903A9);  { add x9, x29, x9 }
    EmitI32($F9400120);  { ldr x0, [x9] }
  end
  else
  begin
    EmitLoadImmA64(0, Syms[idx].Offset);
    EmitI32($8B0003A0);  { add x0, x29, x0 }
  end;
end;

procedure EmitSetccA64(opTk: Integer);
begin
  if opTk = Ord(tkEq) then EmitI32($9A9F17E0)
  else if opTk = Ord(tkNeq) then EmitI32($9A9F07E0)
  else if opTk = Ord(tkLt) then EmitI32($9A9FA7E0)
  else if opTk = Ord(tkLe) then EmitI32($9A9FC7E0)
  else if opTk = Ord(tkGt) then EmitI32($9A9FD7E0)
  else if opTk = Ord(tkGe) then EmitI32($9A9FB7E0)
  else Error('target aarch64: unsupported compare operator');
end;

procedure IREmitNodeAarch64(node: Integer);
var
  valNode, si, left, right, op, pi, argNode, nArgs, i, sz, wid: Integer;
  sVal: AnsiString;
  tk: TTypeKind;
  sgn: Boolean;
begin
  if node = -1 then Exit;
  case IRKind[node] of
    IR_NOP, IR_BLOCK: ;

    IR_CONST_INT:
      EmitLoadImmA64(0, IRIVal[node]);

    IR_LOAD_SYM:
      EmitLoadVarA64(IRA[node]);

    IR_STORE_SYM:
      begin
        IREmitNodeAarch64(IRB[node]);
        EmitStoreVarA64(IRA[node]);
      end;

    IR_LEA:
      EmitLoadVarAddrA64(IRA[node]);

    IR_BINOP:
      begin
        left := IRA[node];
        right := IRB[node];
        op := IRC[node];
        tk := IntToTypeKind(IRTk[node]);
        if not (TypeIsOrdinal(tk) or (tk = tyBoolean) or (tk = tyUnknown)) then
          Error('target aarch64: non-integer binop not yet supported');
        IREmitNodeAarch64(left);
        EmitI32($F81F0FE0); { str x0, [sp, #-16]! }
        IREmitNodeAarch64(right);
        EmitI32($AA0003E1); { mov x1, x0 }
        EmitI32($F84107E0); { ldr x0, [sp], #16 }

        if op = Ord(tkPlus) then EmitI32($8B010000)        { add x0, x0, x1 }
        else if op = Ord(tkMinus) then EmitI32($CB010000)  { sub x0, x0, x1 }
        else if op = Ord(tkStar) then EmitI32($9B017C00)   { mul x0, x0, x1 }
        else if op = Ord(tkDiv) then EmitI32($9AC10C00)    { sdiv x0, x0, x1 }
        else if op = Ord(tkMod) then
        begin
          EmitI32($9AC10C02);  { sdiv x2, x0, x1 }
          EmitI32($9B018040);  { msub x0, x2, x1, x0 }
        end
        else if op = Ord(tkAnd) then EmitI32($8A010000)    { and x0, x0, x1 }
        else if op = Ord(tkOr) then EmitI32($AA010000)     { orr x0, x0, x1 }
        else if op = Ord(tkShl) then EmitI32($9AC12000)    { lsl x0, x0, x1 }
        else if op = Ord(tkIdent) then EmitI32($9AC12400)  { lsr x0, x0, x1 }
        else if (op = Ord(tkEq)) or (op = Ord(tkNeq)) or (op = Ord(tkLt)) or
                (op = Ord(tkLe)) or (op = Ord(tkGt)) or (op = Ord(tkGe)) then
        begin
          EmitI32($EB01001F); { cmp x0, x1 }
          EmitSetccA64(op);
        end
        else
          Error('target aarch64: binop operator not yet supported');
      end;

    IR_CALL:
      begin
        pi := IRA[node];
        if pi = -Ord(tkGetMem) then
        begin
          si := IRC[node];
          if si >= REC_UCLASS_BASE then
            Error('target aarch64: class instantiation not yet supported');
          argNode := IRB[node];               { size arg }
          IREmitNodeAarch64(IRA[argNode]);    { size -> x0 }
          EmitHeapAllocLockedA64;             { x0 = payload pointer }
          Exit;
        end;
        if pi = -Ord(tkFreeMem) then
        begin
          argNode := IRB[node];               { pointer arg }
          IREmitNodeAarch64(IRA[argNode]);    { p -> x0 }
          EmitHeapFreeLockedA64;
          Exit;
        end;
        if pi < 0 then
          Error('target aarch64: builtin/special call not yet supported');
        if ProcExternal[pi] then
          Error('target aarch64: external calls not yet supported');
        if TypeIsAggregate(Procs[pi].RetType) then
          Error('target aarch64: aggregate-valued results not yet supported');

        argNode := IRB[node];
        nArgs := 0;
        while argNode <> -1 do
        begin
          IREmitNodeAarch64(IRA[argNode]);
          EmitI32($F81F0FE0); { str x0, [sp, #-16]! }
          Inc(nArgs);
          argNode := IRB[argNode];
        end;
        if nArgs <> Procs[pi].ParamCount then
          Error('target aarch64: call argument count mismatch');
        if nArgs > 8 then
          Error('target aarch64: procedures with more than 8 arguments not yet supported');

        for i := nArgs - 1 downto 0 do
          EmitI32($F84107E0 + i); { ldr x[i], [sp], #16 }

        EmitCallProc(pi);
      end;

    IR_CONST_STR:
      begin
        sVal := GetTokenStrFromRaw(IRA[node], IRB[node]);
        si := InternStr(sVal);
        EmitLoadDataRefA64(0, Strs[si].Offset);  { x0 = [len][data] struct addr }
      end;

    IR_FIELD:
      begin
        IREmitNodeAarch64(IRA[node]);            { base address -> x0 }
        if Integer(IRIVal[node]) <> 0 then
        begin
          EmitLoadImmA64(9, IRIVal[node]);       { x9 = offset }
          EmitI32($8B090000);                    { add x0, x0, x9 }
        end;
      end;

    IR_INDEX:
      begin
        { base[index]: addr = base + (index - lo) * elemSize. No COW (managed
          dynamic arrays use the handle loaded by IR_LEA). }
        IREmitNodeAarch64(IRA[node]);            { base -> x0 }
        EmitI32($F81F0FE0);                      { str x0, [sp, #-16]! }
        IREmitNodeAarch64(IRB[node]);            { index -> x0 }
        if IRC[node] <> 0 then
        begin
          EmitLoadImmA64(9, IRC[node]);          { x9 = lo }
          EmitI32($CB090000);                    { sub x0, x0, x9 }
        end;
        if Integer(IRIVal[node]) <> 1 then
        begin
          EmitLoadImmA64(9, IRIVal[node]);       { x9 = elemSize }
          EmitI32($9B097C00);                    { mul x0, x0, x9 }
        end;
        EmitI32($F84107E1);                      { ldr x1, [sp], #16 (base) }
        EmitI32($8B010000);                      { add x0, x0, x1 }
      end;

    IR_LOAD_MEM:
      begin
        IREmitNodeAarch64(IRA[node]); { address -> x0 }
        tk := IntToTypeKind(IRTk[node]);
        if not (TypeIsOrdinal(tk) or (tk = tyBoolean) or (tk = tyPointer) or
                (tk = tyChar) or (tk = tyUnknown) or
                (tk = tyAnsiString) or (tk = tyClass)) then
          Error('target aarch64: load through pointer of this type not yet supported');
        sz := TypeSize(tk);
        sgn := TypeSigned(tk);
        if sz = 1 then
        begin
          if sgn then EmitI32($39C00000) else EmitI32($39400000); { ldrsb/ldrb x0/w0, [x0] }
        end
        else if sz = 2 then
        begin
          if sgn then EmitI32($79C00000) else EmitI32($79400000); { ldrsh/ldrh }
        end
        else if sz = 4 then
        begin
          if sgn then EmitI32($B9800000) else EmitI32($B9400000); { ldrsw/ldr w0 }
        end
        else
          EmitI32($F9400000); { ldr x0, [x0] }
      end;

    IR_STORE_MEM:
      begin
        tk := IntToTypeKind(IRTk[node]);
        if not (TypeIsOrdinal(tk) or (tk = tyBoolean) or (tk = tyPointer) or
                (tk = tyChar) or (tk = tyUnknown)) then
          Error('target aarch64: store through pointer of this type not yet supported');
        IREmitNodeAarch64(IRB[node]); { value -> x0 }
        EmitI32($F81F0FE0);           { str x0, [sp, #-16]! }
        IREmitNodeAarch64(IRA[node]); { address -> x0 }
        EmitI32($F84107E1);           { ldr x1, [sp], #16 (value) }
        sz := TypeSize(tk);
        if sz = 1 then EmitI32($39000001)      { strb w1, [x0] }
        else if sz = 2 then EmitI32($79000001) { strh w1, [x0] }
        else if sz = 4 then EmitI32($B9000001) { str w1, [x0] }
        else EmitI32($F9000001);               { str x1, [x0] }
      end;

    IR_SYSCALL:
      begin
        { Raw syscall: args (nr, a0..a5) pushed left-to-right, then popped
          into x8 (number) and x0..x5. Result stays in x0. }
        argNode := IRA[node]; nArgs := 0;
        while argNode <> -1 do
        begin
          IREmitNodeAarch64(IRA[argNode]);
          EmitI32($F81F0FE0); { str x0, [sp, #-16]! }
          Inc(nArgs);
          argNode := IRB[argNode];
        end;
        for i := nArgs - 1 downto 0 do
          if i = 0 then
            EmitI32($F84107E8)          { ldr x8, [sp], #16 }
          else
            EmitI32($F84107E0 + i - 1); { ldr x[i-1], [sp], #16 }
        EmitI32($D4000001); { svc #0 }
      end;

    IR_NEG:
      begin
        IREmitNodeAarch64(IRA[node]);
        EmitI32($CB0003E0); { neg x0, x0 }
      end;

    IR_NOT:
      begin
        IREmitNodeAarch64(IRA[node]);
        if TypeIsOrdinal(IntToTypeKind(IRTk[node])) and
           (IntToTypeKind(IRTk[node]) <> tyBoolean) then
        begin
          EmitI32($AA2003E0); { mvn x0, x0 }
        end
        else
        begin
          EmitI32($D2400000); { eor x0, x0, #1 }
        end;
      end;

    IR_WRITE:
      begin
        valNode := IRA[node];
        wid  := IRB[node];   { field width, 0 = none }
        if IRKind[valNode] = IR_CONST_STR then
        begin
          sVal := GetTokenStrFromRaw(IRA[valNode], IRB[valNode]);
          si := InternStr(sVal);
          if (wid > 0) and (wid > Strs[si].Len) then
          begin
            EnsureSpaces;
            EmitwriteSyscall(SpacesOffset, wid - Strs[si].Len);
          end;
          if Strs[si].Len > 0 then
            EmitwriteSyscall(Strs[si].Offset + 8, Strs[si].Len);
        end
        else
        begin
          tk := IntToTypeKind(IRTk[node]);
          if tk = tyChar then
          begin
            IREmitNodeAarch64(valNode);
            if wid > 1 then
            begin
              { Save x0 on stack to preserve character value }
              EmitI32($F81F0FE0); { str x0, [sp, #-16]! }
              EnsureSpaces;
              EmitwriteSyscall(SpacesOffset, wid - 1);
              EmitI32($F84107E0); { ldr x0, [sp], #16 }
            end;
            EmitwriteCharA64;
          end
          else if TypeIsOrdinal(tk) then
          begin
            IREmitNodeAarch64(valNode);
            if not TypeSigned(tk) then
            begin
              if wid > 0 then
                EmitwriteUIntWA64(wid)
              else
                EmitwriteUIntA64;
            end
            else
            begin
              if wid > 0 then
                EmitwriteIntWA64(wid)
              else
                EmitwriteIntA64;
            end;
          end
          else
            Error('target aarch64: write of this operand not yet supported');
        end;
      end;

    IR_WRITELN:
      EmitwriteSyscall(NEWLINE_OFFSET, 1);

    IR_TERMINATE:
      begin
        if IRIVal[node] = AN_HALT then
        begin
          if IRA[node] <> -1 then
          begin
            IREmitNodeAarch64(IRA[node]);
            EmitI32($D2800BC8); { movz x8, #94 }
            EmitI32($D4000001); { svc #0 }
          end
          else
            EmitExit(0);
        end
        else
        begin
          if CurProc >= 0 then
            EmitProcEpilog(Procs[CurProc].RetSymIdx)
          else
            EmitExit(0);
        end;
      end;

    else
      Error('target aarch64: IR op not yet supported: ' + IROpName(IRKind[node]));
  end;
end;

procedure IREmitMachineCodeAarch64;
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
          if LabelPositions[lblId] <> -1 then
            EmitI32($14000000 or (((LabelPositions[lblId] - CodeLen) div 4) and $03ffffff))
          else
          begin
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitI32($14000000);
          end;
        end;

      IR_JUMP_IF_FALSE:
        begin
          lblId := IRA[i];
          IREmitNodeAarch64(IRB[i]); { condition -> x0 }
          if LabelPositions[lblId] <> -1 then
            EmitI32($B4000000 or (((LabelPositions[lblId] - CodeLen) div 4) and $7ffff) shl 5)
          else
          begin
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitI32($B4000000);
          end;
        end;

      IR_CALL:
        begin
          if IRIVal[i] = 1 then
            IREmitNodeAarch64(i);
        end;

      IR_STORE_SYM, IR_WRITE, IR_WRITELN:
        IREmitNodeAarch64(i);

      IR_NOP, IR_CONST_STR, IR_CONST_INT, IR_BLOCK,
      IR_LOAD_SYM, IR_BINOP, IR_NEG, IR_NOT, IR_ARG, IR_LEA, IR_SYSCALL,
      IR_FIELD, IR_INDEX, IR_CONST_STR: ;

      else
        IREmitNodeAarch64(i);
    end;
  end;

  for f := 0 to LabelFixupCount - 1 do
  begin
    lblId := LabelFixupTarget[f];
    pos := LabelFixupPos[f];
    targetOffset := LabelPositions[lblId];
    if targetOffset = -1 then Error('Unresolved forward jump in AArch64 IR codegen');
    if Code[pos+3] = $14 then
      Patch32(pos, $14000000 or (((targetOffset - pos) div 4) and $03ffffff))
    else if Code[pos+3] = $B4 then
      Patch32(pos, $B4000000 or (((targetOffset - pos) div 4) and $7ffff) shl 5)
    else
      Error('target aarch64: invalid instruction at label fixup');
  end;
end;
