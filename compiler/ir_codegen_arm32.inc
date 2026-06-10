{ ===== IR -> ARM32 machine code (cross target, minimal and growing) =====

  ARM32 (ARMv7-A) target backend. Operates on fixed-width 32-bit instructions.
  Registers used: r0 for expression results, r1..r3 for arguments/temporaries. }

procedure EmitLoadVarArm32(idx: Integer);
var tk: TTypeKind; sz: Integer; sgn: Boolean;
begin
  tk := Syms[idx].TypeKind;
  sz := TypeSize(tk);
  sgn := TypeSigned(tk);

  if Syms[idx].Kind = skGlobal then
  begin
    EmitI32($E59F1000);  { ldr r1, [pc] }
    EmitI32($EA000000);  { b .+8 }
    EmitGlobRef(Syms[idx].Offset);
    if sz = 1 then
    begin
      if sgn then EmitI32($E1D100D0) else EmitI32($E5D10000);
    end
    else if sz = 2 then
    begin
      if sgn then EmitI32($E1D100F0) else EmitI32($E1D100B0);
    end
    else
      EmitI32($E5910000);
  end
  else
  begin
    EmitLoadImmArm32(9, Syms[idx].Offset);
    EmitI32($E08B9009);  { add r9, fp, r9 }
    if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
    begin
      EmitI32($E5991000);  { ldr r1, [r9] }
      if sz = 1 then
      begin
        if sgn then EmitI32($E1D100D0) else EmitI32($E5D10000);
      end
      else if sz = 2 then
      begin
        if sgn then EmitI32($E1D100F0) else EmitI32($E1D100B0);
      end
      else
        EmitI32($E5910000);
    end
    else
    begin
      if sz = 1 then
      begin
        if sgn then EmitI32($E1D900D0) else EmitI32($E5D90000);
      end
      else if sz = 2 then
      begin
        if sgn then EmitI32($E1D900F0) else EmitI32($E1D900B0);
      end
      else
        EmitI32($E5990000);
    end;
  end;
end;

procedure EmitStoreVarArm32(idx: Integer);
var tk: TTypeKind; sz: Integer;
begin
  tk := Syms[idx].TypeKind;
  sz := TypeSize(tk);

  if Syms[idx].Kind = skGlobal then
  begin
    EmitI32($E59F1000);  { ldr r1, [pc] }
    EmitI32($EA000000);  { b .+8 }
    EmitGlobRef(Syms[idx].Offset);
    if sz = 1 then
      EmitI32($E5C10000)  { strb r0, [r1] }
    else if sz = 2 then
      EmitI32($E1C100B0)  { strh r0, [r1] }
    else
      EmitI32($E5810000); { str r0, [r1] }
  end
  else
  begin
    EmitLoadImmArm32(9, Syms[idx].Offset);
    EmitI32($E08B9009);  { add r9, fp, r9 }
    if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
    begin
      EmitI32($E5991000);  { ldr r1, [r9] }
      if sz = 1 then
        EmitI32($E5C10000)  { strb r0, [r1] }
      else if sz = 2 then
        EmitI32($E1C100B0)  { strh r0, [r1] }
      else
        EmitI32($E5810000); { str r0, [r1] }
    end
    else
    begin
      if sz = 1 then
        EmitI32($E5C90000)  { strb r0, [r9] }
      else if sz = 2 then
        EmitI32($E1C900B0)  { strh r0, [r9] }
      else
        EmitI32($E5890000); { str r0, [r9] }
    end;
  end;
end;

procedure EmitLoadVarAddrArm32(idx: Integer);
begin
  if Syms[idx].Kind = skGlobal then
  begin
    EmitI32($E59F0000);  { ldr r0, [pc] }
    EmitI32($EA000000);  { b .+8 }
    EmitGlobRef(Syms[idx].Offset);
  end
  else if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
  begin
    EmitLoadImmArm32(9, Syms[idx].Offset);
    EmitI32($E08B9009);  { add r9, fp, r9 }
    EmitI32($E5990000);  { ldr r0, [r9] }
  end
  else
  begin
    EmitLoadImmArm32(0, Syms[idx].Offset);
    EmitI32($E08B0000);  { add r0, fp, r0 }
  end;
end;

procedure EmitSetccArm32(opTk: Integer);
begin
  EmitI32($E3A00000);  { mov r0, #0 }
  if opTk = Ord(tkEq) then EmitI32($03A00001)
  else if opTk = Ord(tkNeq) then EmitI32($13A00001)
  else if opTk = Ord(tkLt) then EmitI32($B3A00001)
  else if opTk = Ord(tkLe) then EmitI32($D3A00001)
  else if opTk = Ord(tkGt) then EmitI32($C3A00001)
  else if opTk = Ord(tkGe) then EmitI32($A3A00001)
  else Error('target arm32: unsupported compare operator');
end;

procedure IREmitNodeArm32(node: Integer);
var
  valNode, si, left, right, op, pi, argNode, nArgs, i, wid: Integer;
  sVal: AnsiString;
  tk: TTypeKind;
begin
  if node = -1 then Exit;
  case IRKind[node] of
    IR_NOP, IR_BLOCK: ;

    IR_CONST_INT:
      EmitLoadImmArm32(0, IRIVal[node]);

    IR_LOAD_SYM:
      EmitLoadVarArm32(IRA[node]);

    IR_STORE_SYM:
      begin
        IREmitNodeArm32(IRB[node]);
        EmitStoreVarArm32(IRA[node]);
      end;

    IR_LEA:
      EmitLoadVarAddrArm32(IRA[node]);

    IR_BINOP:
      begin
        left := IRA[node];
        right := IRB[node];
        op := IRC[node];
        tk := IntToTypeKind(IRTk[node]);
        if not (TypeIsOrdinal(tk) or (tk = tyBoolean) or (tk = tyUnknown)) then
          Error('target arm32: non-integer binop not yet supported');
        IREmitNodeArm32(left);
        EmitI32($E92D0001); { push {r0} }
        IREmitNodeArm32(right);
        EmitI32($E1A01000); { mov r1, r0 }
        EmitI32($E8BD0001); { pop {r0} }

        if op = Ord(tkPlus) then EmitI32($E0800001)        { add r0, r0, r1 }
        else if op = Ord(tkMinus) then EmitI32($E0400001)  { sub r0, r0, r1 }
        else if op = Ord(tkStar) then EmitI32($E0000091)   { mul r0, r1, r0 }
        else if op = Ord(tkDiv) then EmitI32($E710F110)    { sdiv r0, r0, r1 }
        else if op = Ord(tkMod) then
        begin
          EmitI32($E712F110);  { sdiv r2, r0, r1 }
          EmitI32($E0020192);  { mul r2, r2, r1 }
          EmitI32($E0400002);  { sub r0, r0, r2 }
        end
        else if op = Ord(tkAnd) then EmitI32($E0000001)    { and r0, r0, r1 }
        else if op = Ord(tkOr) then EmitI32($E1800001)     { orr r0, r0, r1 }
        else if op = Ord(tkShl) then EmitI32($E1A00110)    { lsl r0, r0, r1 }
        else if op = Ord(tkIdent) then EmitI32($E1A00130)  { lsr r0, r0, r1 }
        else if (op = Ord(tkEq)) or (op = Ord(tkNeq)) or (op = Ord(tkLt)) or
                (op = Ord(tkLe)) or (op = Ord(tkGt)) or (op = Ord(tkGe)) then
        begin
          EmitI32($E1500001); { cmp r0, r1 }
          EmitSetccArm32(op);
        end
        else
          Error('target arm32: binop operator not yet supported');
      end;

    IR_CALL:
      begin
        pi := IRA[node];
        if pi < 0 then
          Error('target arm32: builtin/special call not yet supported');
        if ProcExternal[pi] then
          Error('target arm32: external calls not yet supported');
        if TypeIsAggregate(Procs[pi].RetType) then
          Error('target arm32: aggregate-valued results not yet supported');

        argNode := IRB[node];
        nArgs := 0;
        while argNode <> -1 do
        begin
          IREmitNodeArm32(IRA[argNode]);
          EmitI32($E92D0001); { push {r0} }
          Inc(nArgs);
          argNode := IRB[argNode];
        end;
        if nArgs <> Procs[pi].ParamCount then
          Error('target arm32: call argument count mismatch');
        if nArgs > 4 then
          Error('target arm32: procedures with more than 4 arguments not yet supported');

        for i := nArgs - 1 downto 0 do
          EmitI32($E8BD0000 or (1 shl i)); { pop {r[i]} }

        EmitCallProc(pi);
      end;

    IR_NEG:
      begin
        IREmitNodeArm32(IRA[node]);
        EmitI32($E2600000); { rsb r0, r0, #0 }
      end;

    IR_NOT:
      begin
        IREmitNodeArm32(IRA[node]);
        if TypeIsOrdinal(IntToTypeKind(IRTk[node])) and
           (IntToTypeKind(IRTk[node]) <> tyBoolean) then
        begin
          EmitI32($E1E00000); { mvn r0, r0 }
        end
        else
        begin
          EmitI32($E2200001); { eor r0, r0, #1 }
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
            IREmitNodeArm32(valNode);
            if wid > 1 then
            begin
              { Save r0 on stack to preserve character value }
              EmitI32($E92D0001); { push {r0} }
              EnsureSpaces;
              EmitwriteSyscall(SpacesOffset, wid - 1);
              EmitI32($E8BD0001); { pop {r0} }
            end;
            EmitwriteCharArm32;
          end
          else if TypeIsOrdinal(tk) then
          begin
            IREmitNodeArm32(valNode);
            if not TypeSigned(tk) then
            begin
              if wid > 0 then
                EmitwriteUIntWArm32(wid)
              else
                EmitwriteUIntArm32;
            end
            else
            begin
              if wid > 0 then
                EmitwriteIntWArm32(wid)
              else
                EmitwriteIntArm32;
            end;
          end
          else
            Error('target arm32: write of this operand not yet supported');
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
            IREmitNodeArm32(IRA[node]);
            EmitI32($E3A07001); { mov r7, #1 }
            EmitI32($EF000000); { svc #0 }
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
      Error('target arm32: IR op not yet supported: ' + IROpName(IRKind[node]));
  end;
end;

procedure IREmitMachineCodeArm32;
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
            EmitI32($EA000000 or ((((LabelPositions[lblId] - CodeLen) div 4) - 2) and $00ffffff))
          else
          begin
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitI32($EA000000);
          end;
        end;

      IR_JUMP_IF_FALSE:
        begin
          lblId := IRA[i];
          IREmitNodeArm32(IRB[i]); { condition -> r0 }
          EmitI32($E3500000);      { cmp r0, #0 }
          if LabelPositions[lblId] <> -1 then
            EmitI32($0A000000 or ((((LabelPositions[lblId] - CodeLen) div 4) - 2) and $00ffffff))
          else
          begin
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitI32($0A000000);
          end;
        end;

      IR_CALL:
        begin
          if IRIVal[i] = 1 then
            IREmitNodeArm32(i);
        end;

      IR_STORE_SYM, IR_WRITE, IR_WRITELN:
        IREmitNodeArm32(i);

      IR_NOP, IR_CONST_STR, IR_CONST_INT, IR_BLOCK,
      IR_LOAD_SYM, IR_BINOP, IR_NEG, IR_NOT, IR_ARG, IR_LEA: ;

      else
        IREmitNodeArm32(i);
    end;
  end;

  for f := 0 to LabelFixupCount - 1 do
  begin
    lblId := LabelFixupTarget[f];
    pos := LabelFixupPos[f];
    targetOffset := LabelPositions[lblId];
    if targetOffset = -1 then Error('Unresolved forward jump in ARM32 IR codegen');
    if Code[pos+3] = $EA then
      Patch32(pos, $EA000000 or ((((targetOffset - pos) div 4) - 2) and $00ffffff))
    else if Code[pos+3] = $0A then
      Patch32(pos, $0A000000 or ((((targetOffset - pos) div 4) - 2) and $00ffffff))
    else
      Error('target arm32: invalid instruction at label fixup');
  end;
end;
