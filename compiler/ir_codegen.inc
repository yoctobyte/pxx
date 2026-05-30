{ ===== Experimental IR Machine Code Generator ===== }

procedure IREmitCodeCall(addr: Integer);
begin
  EmitB($E8);
  EmitI32(addr - (CodeLen + 4));
end;

procedure IREmitLeaveExceptionFrames(count: Integer);
var i: Integer;
begin
  for i := 1 to count do
  begin
    EmitB($48); EmitB($8B); EmitB($04); EmitB($24); { mov rax, [rsp] }
    EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_TOP);
    EmitB($48); EmitB($83); EmitB($C4); EmitB(EXC_FRAME_SIZE);
  end;
end;

procedure IREmitNode(node: Integer);
var left, right, valNode, symIdx, si: Integer;
    op: TTokenKind;
    cmpUnsigned: Boolean;
    sVal: AnsiString;
    tk, lhsTk, rhsTk: TTypeKind;
    size: Integer;
    isSigned: Boolean;
    baseAddr, indexNode, lo, elemSize, offset, addressNode, valueNode: Integer;
    argNode, pathIdx, pi, specialId, classIdx, slot, cpi, i, jbePatch: Integer;
    wid, decs: Integer;
    arg1Node, arg2Node, arg3Node, val1Node, val2Node: Integer;
    itemNode, trueCount, nextJmp, falseJmp: Integer;
    trueJumps: array[0..127] of Integer;
    raiseClass: Integer;
begin
  if node = -1 then Exit;
  
  case IRKind[node] of
    IR_NOP, IR_BLOCK:
      begin end;
      
    IR_CONST_INT:
      begin
        MovRaxImm(IRIVal[node]);
      end;
      
    IR_CONST_STR:
      begin
        { Intern the string literal and load it }
        sVal := GetTokenStrFromRaw(IRA[node], IRB[node]);
        si := InternStr(sVal);
        EmitB($48); EmitB($B8); EmitDataRef(Strs[si].Offset);
      end;

    IR_SET_LIT:
      begin
        EmitB($48); EmitB($B8); EmitDataRef(IRIVal[node]);
      end;
      
    IR_ASM:
      begin
        for i := 0 to IRB[node] - 1 do
        begin
          EmitB(AsmBytes[IRA[node] + i]);
        end;
      end;

    IR_RTTI_REG:
      begin
        EmitB($48); EmitB($B8); EmitDataRef(-100);
      end;
      
    IR_LOAD_SYM:
      begin
        EmitLoadVar(IRA[node]);
        { EmitLoadVar leaves floats in xmm0, but the IR value model carries
          floats as double bits in rax. Bridge xmm0 -> rax. }
        if TypeIsFloat(Syms[IRA[node]].TypeKind) then
          begin EmitB($66); EmitB($48); EmitB($0F); EmitB($7E); EmitB($C0); end; { movq rax, xmm0 }
      end;
      
    IR_STORE_SYM:
      begin
        symIdx := IRA[node];
        if (Syms[symIdx].TypeKind = tyString) and not Syms[symIdx].IsArray then
        begin
          valueNode := IRB[node];
          if (IRKind[valueNode] = IR_CALL) and (IRA[valueNode] = -Ord(tkArgStr)) then
          begin
            argNode := IRB[valueNode];
            IREmitNode(IRA[argNode]); { rax = argv index }
            EmitArgvToString(symIdx);
          end
          else
          begin
            IREmitNode(valueNode); { rax = source string address }
            EmitB($50); { push source }
            if Syms[symIdx].Kind = skGlobal then
            begin
              EmitB($48); EmitB($8D); EmitB($04); EmitB($25); EmitGlobRef(Syms[symIdx].Offset);
            end
            else if Syms[symIdx].Kind = skParam then
            begin
              EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[symIdx].Offset);
            end
            else
            begin
              EmitB($48); EmitB($8D); EmitB($85); EmitI32(Syms[symIdx].Offset);
            end;
            EmitB($48); EmitB($89); EmitB($C7); { mov rdi, rax }
            EmitB($5E);                         { pop rsi }
            EmitB($48); EmitB($8B); EmitB($0E); { mov rcx, [rsi] }
            EmitB($48); EmitB($89); EmitB($0F); { mov [rdi], rcx }
            EmitB($48); EmitB($83); EmitB($C6); EmitB($08);
            EmitB($48); EmitB($83); EmitB($C7); EmitB($08);
            EmitB($F3); EmitB($A4);             { rep movsb }
          end;
        end
        else
        begin
          IREmitNode(IRB[node]);
          { IR carries floats as double bits in rax; EmitStoreVar reads xmm0.
            Bridge rax -> xmm0. }
          if TypeIsFloat(Syms[IRA[node]].TypeKind) then
            begin EmitB($66); EmitB($48); EmitB($0F); EmitB($6E); EmitB($C0); end; { movq xmm0, rax }
          EmitStoreVar(IRA[node]);
        end;
      end;
      
    IR_LEA:
      begin
        symIdx := IRA[node];
        if Syms[symIdx].Kind = skGlobal then
        begin
          { Dynamic array slot holds a heap data pointer; load it (mov), not its
            address (lea), so indexing/Length operate on the heap block. }
          if Syms[symIdx].IsArray and (Syms[symIdx].ArrLen = -1) then
            begin EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(Syms[symIdx].Offset); end
          else
            begin EmitB($48); EmitB($8D); EmitB($04); EmitB($25); EmitGlobRef(Syms[symIdx].Offset); end;
        end
        else
        begin
          if (Syms[symIdx].IsArray and (Syms[symIdx].ArrLen = -1)) or
             ((Syms[symIdx].Kind = skParam) and (Syms[symIdx].IsRef or Syms[symIdx].IsArray or (Syms[symIdx].TypeKind = tyString))) then
          begin
            EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[symIdx].Offset);
          end
          else
          begin
            EmitB($48); EmitB($8D); EmitB($85); EmitI32(Syms[symIdx].Offset);
          end;
        end;
      end;

    IR_INDEX:
      begin
        baseAddr := IRA[node];
        indexNode := IRB[node];
        lo := IRC[node];
        elemSize := Integer(IRIVal[node]);
        
        IREmitNode(baseAddr);
        EmitB($50); { push rax }
        
        IREmitNode(indexNode); { rax = index }
        if lo <> 0 then
        begin
          EmitB($48); EmitB($2D); EmitI32(lo); { sub rax, lo }
        end;
        
        if elemSize = 8 then
        begin
          EmitB($48); EmitB($C1); EmitB($E0); EmitB($03); { shl rax, 3 }
        end
        else if elemSize > 1 then
        begin
          EmitB($48); EmitB($C7); EmitB($C1); EmitI32(elemSize); { mov rcx, elemSize }
          EmitB($48); EmitB($0F); EmitB($AF); EmitB($C1); { imul rax, rcx }
        end;
        
        EmitB($59); { pop rcx -- base address }
        EmitB($48); EmitB($01); EmitB($C8); { add rax, rcx }
      end;

    IR_FIELD:
      begin
        baseAddr := IRA[node];
        offset := Integer(IRIVal[node]);
        
        IREmitNode(baseAddr);
        EmitB($48); EmitB($05); EmitI32(offset); { add rax, offset }
      end;

    IR_LOAD_MEM:
      begin
        addressNode := IRA[node];
        IREmitNode(addressNode);
        
        tk := IntToTypeKind(IRTk[node]);
        size := TypeSize(tk);
        isSigned := TypeSigned(tk);
        
        if size = 1 then
        begin
          if isSigned then
          begin
            EmitB($48); EmitB($0F); EmitB($BE); EmitB($00); { movsx rax, byte ptr [rax] }
          end
          else
          begin
            EmitB($48); EmitB($0F); EmitB($B6); EmitB($00); { movzx rax, byte ptr [rax] }
          end;
        end
        else if size = 2 then
        begin
          if isSigned then
          begin
            EmitB($48); EmitB($0F); EmitB($BF); EmitB($00); { movsx rax, word ptr [rax] }
          end
          else
          begin
            EmitB($48); EmitB($0F); EmitB($B7); EmitB($00); { movzx rax, word ptr [rax] }
          end;
        end
        else if size = 4 then
        begin
          if isSigned then
          begin
            EmitB($48); EmitB($63); EmitB($00); { movsxd rax, dword ptr [rax] }
          end
          else
          begin
            EmitB($8B); EmitB($00); { mov eax, dword ptr [rax] }
          end;
        end
        else
        begin
          EmitB($48); EmitB($8B); EmitB($00); { mov rax, qword ptr [rax] }
        end;
      end;

    IR_STORE_MEM:
      begin
        addressNode := IRA[node];
        valueNode := IRB[node];

        tk := IntToTypeKind(IRTk[node]);
        size := TypeSize(tk);

        if tk = tyString then
        begin
          IREmitNode(valueNode); { rax = source string address }
          EmitB($50); { push source }

          IREmitNode(addressNode); { rax = destination address }

          EmitB($48); EmitB($89); EmitB($C7); { mov rdi, rax }
          EmitB($5E);                         { pop rsi }
          EmitB($48); EmitB($8B); EmitB($0E); { mov rcx, [rsi] }
          EmitB($48); EmitB($89); EmitB($0F); { mov [rdi], rcx }
          EmitB($48); EmitB($83); EmitB($C6); EmitB($08);
          EmitB($48); EmitB($83); EmitB($C7); EmitB($08);
          EmitB($F3); EmitB($A4);             { rep movsb }
        end
        else
        begin
          IREmitNode(valueNode);
          EmitB($50); { push rax -- value }

          IREmitNode(addressNode); { rax = address }

          EmitB($59); { pop rcx -- value }

          if size = 1 then
        begin
          EmitB($88); EmitB($08); { mov byte ptr [rax], cl }
        end
        else if size = 2 then
        begin
          EmitB($66); EmitB($89); EmitB($08); { mov word ptr [rax], cx }
        end
        else if size = 4 then
        begin
          EmitB($89); EmitB($08); { mov dword ptr [rax], ecx }
        end
        else
        begin
          EmitB($48); EmitB($89); EmitB($08); { mov qword ptr [rax], rcx }
        end;
        end;
      end;
      
    IR_BINOP:
      begin
        left := IRA[node];
        right := IRB[node];
        op := IntToTokenKind(IRC[node]);
        
        IREmitNode(left);
        EmitB($50); { push rax }
        
        IREmitNode(right);
        EmitB($48); EmitB($89); EmitB($C1); { mov rcx, rax }
        EmitB($58); { pop rax }
        
        if (IntToTypeKind(IRTk[node]) = tyString) and (op = tkPlus) then
        begin
          lhsTk := IntToTypeKind(IRTk[left]);
          rhsTk := IntToTypeKind(IRTk[right]);

          EmitB($49); EmitB($89); EmitB($CA); { mov r10, rcx }
          EmitB($48); EmitB($81); EmitB($EC); EmitI32(272);
          EmitB($49); EmitB($89); EmitB($E3); { mov r11, rsp }

          if lhsTk = tyString then
          begin
            EmitB($4C); EmitB($8B); EmitB($00);
            EmitB($48); EmitB($8D); EmitB($70); EmitB($08);
            EmitB($49); EmitB($8D); EmitB($7B); EmitB($08);
            EmitB($4C); EmitB($89); EmitB($C1);
            EmitB($48); EmitB($85); EmitB($C9);
            EmitB($74); EmitB(15);
            EmitB($8A); EmitB($16);
            EmitB($88); EmitB($17);
            EmitB($48); EmitB($FF); EmitB($C6);
            EmitB($48); EmitB($FF); EmitB($C7);
            EmitB($48); EmitB($FF); EmitB($C9);
            EmitB($EB); EmitB(Byte(-20));
          end
          else
          begin
            EmitB($49); EmitB($C7); EmitB($C0); EmitI32(1);
            EmitB($41); EmitB($88); EmitB($43); EmitB($08);
          end;

          if rhsTk = tyString then
          begin
            EmitB($4D); EmitB($8B); EmitB($0A);
            EmitB($49); EmitB($8D); EmitB($72); EmitB($08);
            EmitB($49); EmitB($8D); EmitB($7B); EmitB($08);
            EmitB($4C); EmitB($01); EmitB($C7);
            EmitB($4C); EmitB($89); EmitB($CA);
            EmitB($48); EmitB($85); EmitB($D2);
            EmitB($74); EmitB(15);
            EmitB($8A); EmitB($06);
            EmitB($88); EmitB($07);
            EmitB($48); EmitB($FF); EmitB($C6);
            EmitB($48); EmitB($FF); EmitB($C7);
            EmitB($48); EmitB($FF); EmitB($CA);
            EmitB($EB); EmitB(Byte(-20));
          end
          else
          begin
            EmitB($49); EmitB($C7); EmitB($C1); EmitI32(1);
            EmitB($49); EmitB($8D); EmitB($7B); EmitB($08);
            EmitB($4C); EmitB($01); EmitB($C7);
            EmitB($44); EmitB($88); EmitB($17);
          end;

          EmitB($4B); EmitB($8D); EmitB($04); EmitB($08);
          EmitB($48); EmitB($3D); EmitI32(256);
          EmitB($7E); EmitB(7);
          EmitB($48); EmitB($C7); EmitB($C0); EmitI32(256);
          EmitB($49); EmitB($89); EmitB($03);
          EmitB($4C); EmitB($89); EmitB($D8);
        end
        else
        begin
          lhsTk := IntToTypeKind(IRTk[left]);
          rhsTk := IntToTypeKind(IRTk[right]);
          if (lhsTk = tySingle) or (lhsTk = tyDouble) or (lhsTk = tyExtended) or
             (rhsTk = tySingle) or (rhsTk = tyDouble) or (rhsTk = tyExtended) or
             (op = tkSlash) then
          begin
            if not TypeIsFloat(lhsTk) then
              begin EmitB($F2); EmitB($48); EmitB($0F); EmitB($2A); EmitB($C8); end  { cvtsi2sd xmm1, rax }
            else
              begin EmitB($66); EmitB($48); EmitB($0F); EmitB($6E); EmitB($C8); end; { movq xmm1, rax }

            if not TypeIsFloat(rhsTk) then
              begin EmitB($F2); EmitB($48); EmitB($0F); EmitB($2A); EmitB($C1); end  { cvtsi2sd xmm0, rcx }
            else
              begin EmitB($66); EmitB($48); EmitB($0F); EmitB($6E); EmitB($C1); end; { movq xmm0, rcx }

            case op of
              tkPlus:  begin EmitB($F2); EmitB($0F); EmitB($58); EmitB($C1); end; { addsd xmm0, xmm1 }
              tkMinus:
                begin
                  EmitB($F2); EmitB($0F); EmitB($5C); EmitB($C8); { subsd xmm1, xmm0 }
                  EmitB($F2); EmitB($0F); EmitB($10); EmitB($C1); { movsd xmm0, xmm1 }
                end;
              tkStar:  begin EmitB($F2); EmitB($0F); EmitB($59); EmitB($C1); end; { mulsd xmm0, xmm1 }
              tkSlash:
                begin
                  EmitB($F2); EmitB($0F); EmitB($5E); EmitB($C8); { divsd xmm1, xmm0 }
                  EmitB($F2); EmitB($0F); EmitB($10); EmitB($C1); { movsd xmm0, xmm1 }
                end;
              tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe:
                begin
                  EmitB($66); EmitB($0F); EmitB($2E); EmitB($C8); { ucomisd xmm1, xmm0 }
                  case op of
                    tkEq:  begin EmitB($0F); EmitB($94); EmitB($C0); end; { sete al }
                    tkNeq: begin EmitB($0F); EmitB($95); EmitB($C0); end; { setne al }
                    tkLt:  begin EmitB($0F); EmitB($92); EmitB($C0); end; { setb al }
                    tkLe:  begin EmitB($0F); EmitB($96); EmitB($C0); end; { setbe al }
                    tkGt:  begin EmitB($0F); EmitB($97); EmitB($C0); end; { seta al }
                    tkGe:  begin EmitB($0F); EmitB($93); EmitB($C0); end; { setae al }
                  end;
                  EmitB($48); EmitB($0F); EmitB($B6); EmitB($C0); { movzx rax, al }
                end;
            end;

            if not ((op = tkEq) or (op = tkNeq) or (op = tkLt) or (op = tkLe) or (op = tkGt) or (op = tkGe)) then
            begin
              EmitB($66); EmitB($48); EmitB($0F); EmitB($7E); EmitB($C0); { movq rax, xmm0 }
            end;
          end
          else
          begin
            cmpUnsigned := TypeCompareUnsigned(IntToTypeKind(IRTk[left]), IntToTypeKind(IRTk[right]));

          case op of
          tkPlus:  begin EmitB($48); EmitB($01); EmitB($C8); end; { add rax, rcx }
          tkMinus: begin EmitB($48); EmitB($29); EmitB($C8); end; { sub rax, rcx }
          tkStar:  begin EmitB($48); EmitB($0F); EmitB($AF); EmitB($C1); end; { imul rax, rcx }
          
          tkDiv:
            begin
              if TypeDivideUnsigned(IntToTypeKind(IRTk[left])) then
                begin EmitB($48); EmitB($31); EmitB($D2); EmitB($48); EmitB($F7); EmitB($F1); end
              else
                begin EmitB($48); EmitB($99); EmitB($48); EmitB($F7); EmitB($F9); end;
            end;
          tkMod:
            begin
              if TypeDivideUnsigned(IntToTypeKind(IRTk[left])) then
                begin EmitB($48); EmitB($31); EmitB($D2); EmitB($48); EmitB($F7); EmitB($F1); end
              else
                begin EmitB($48); EmitB($99); EmitB($48); EmitB($F7); EmitB($F9); end;
              EmitB($48); EmitB($89); EmitB($D0); { mov rax, rdx }
            end;
          tkAnd:   begin EmitB($48); EmitB($21); EmitB($C8); end; { and rax, rcx }
          tkOr:    begin EmitB($48); EmitB($09); EmitB($C8); end; { or rax, rcx }
          tkIdent: begin EmitB($48); EmitB($D3); EmitB($E8); end; { shr rax, cl }

          tkIn:
            begin
              { rax = element value (LHS), rcx = set address (RHS) }
              EmitB($48); EmitB($3D); EmitI32(255); { cmp rax, 255 }
              EmitB($0F); EmitB($87); nextJmp := CodeLen; EmitI32(0); { ja out_of_range }
              
              EmitB($48); EmitB($89); EmitB($C2); { mov rdx, rax }
              EmitB($48); EmitB($C1); EmitB($EA); EmitB($03); { shr rdx, 3 }
              EmitB($49); EmitB($89); EmitB($C0); { mov r8, rax }
              EmitB($49); EmitB($83); EmitB($E0); EmitB($07); { and r8, 7 }
              
              EmitB($48); EmitB($0F); EmitB($B6); EmitB($14); EmitB($11); { movzx rdx, byte [rcx+rdx] }
              
              MovRaxImm(1);
              EmitB($4C); EmitB($89); EmitB($C1); { mov rcx, r8 }
              EmitB($48); EmitB($D3); EmitB($E0); { shl rax, cl }
              EmitB($48); EmitB($85); EmitB($D0); { test rax, rdx }
              EmitB($0F); EmitB($95); EmitB($C0); { setnz al }
              EmitB($48); EmitB($0F); EmitB($B6); EmitB($C0); { movzx rax, al }
              EmitB($E9); falseJmp := CodeLen; EmitI32(0); { jmp exit }
              
              Patch32(nextJmp, CodeLen - (nextJmp + 4));
              MovRaxImm(0);
              Patch32(falseJmp, CodeLen - (falseJmp + 4));
            end;
          
          tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe:
            begin
              if ((op = tkEq) or (op = tkNeq)) and
                 ((IntToTypeKind(IRTk[left]) = tyString) or
                  (IntToTypeKind(IRTk[right]) = tyString)) then
              begin
                lhsTk := IntToTypeKind(IRTk[left]);
                rhsTk := IntToTypeKind(IRTk[right]);
                if (lhsTk = tyString) and (rhsTk = tyChar) then
                begin
                  { String = Char: rax = string struct, rcx = char ordinal.
                    Equal iff len=1 and the single byte matches. }
                  EmitB($51);                                                  { push rcx }
                  EmitB($48); EmitB($8B); EmitB($08);                          { mov rcx, [rax] }
                  EmitB($48); EmitB($83); EmitB($F9); EmitB($01);              { cmp rcx, 1 }
                  EmitB($0F); EmitB($85); nextJmp := CodeLen; EmitI32(0);      { jne not_equal }
                  EmitB($48); EmitB($0F); EmitB($B6); EmitB($48); EmitB($08);  { movzx rcx, byte [rax+8] }
                  EmitB($58);                                                  { pop rax }
                  EmitB($48); EmitB($39); EmitB($C1);                          { cmp rcx, rax }
                  if op = tkEq then begin EmitB($0F); EmitB($94); EmitB($C0); end
                  else begin EmitB($0F); EmitB($95); EmitB($C0); end;
                  EmitB($48); EmitB($0F); EmitB($B6); EmitB($C0);              { movzx rax, al }
                  EmitB($E9); falseJmp := CodeLen; EmitI32(0);                 { jmp end }
                  Patch32(nextJmp, CodeLen - (nextJmp + 4));
                  EmitB($59);                                                  { pop rcx }
                  if op = tkNeq then MovRaxImm(1) else MovRaxImm(0);
                  Patch32(falseJmp, CodeLen - (falseJmp + 4));
                end
                else if (lhsTk = tyChar) and (rhsTk = tyString) then
                begin
                  { Char = String: rax = char ordinal, rcx = string struct. }
                  EmitB($50);                                                  { push rax }
                  EmitB($48); EmitB($8B); EmitB($01);                          { mov rax, [rcx] }
                  EmitB($48); EmitB($83); EmitB($F8); EmitB($01);              { cmp rax, 1 }
                  EmitB($0F); EmitB($85); nextJmp := CodeLen; EmitI32(0);      { jne not_equal }
                  EmitB($48); EmitB($0F); EmitB($B6); EmitB($41); EmitB($08);  { movzx rax, byte [rcx+8] }
                  EmitB($5A);                                                  { pop rdx }
                  EmitB($48); EmitB($39); EmitB($D0);                          { cmp rax, rdx }
                  if op = tkEq then begin EmitB($0F); EmitB($94); EmitB($C0); end
                  else begin EmitB($0F); EmitB($95); EmitB($C0); end;
                  EmitB($48); EmitB($0F); EmitB($B6); EmitB($C0);              { movzx rax, al }
                  EmitB($E9); falseJmp := CodeLen; EmitI32(0);                 { jmp end }
                  Patch32(nextJmp, CodeLen - (nextJmp + 4));
                  EmitB($5A);                                                  { pop rdx }
                  if op = tkNeq then MovRaxImm(1) else MovRaxImm(0);
                  Patch32(falseJmp, CodeLen - (falseJmp + 4));
                end
                else
                  EmitStrCmpReg(op = tkEq);
              end
              else
              begin
                EmitB($48); EmitB($3B); EmitB($C1); { cmp rax, rcx }
                if cmpUnsigned then
                begin
                  case op of
                    tkEq:  begin EmitB($0F); EmitB($94); EmitB($C0); end;
                    tkNeq: begin EmitB($0F); EmitB($95); EmitB($C0); end;
                    tkLt:  begin EmitB($0F); EmitB($92); EmitB($C0); end;
                    tkLe:  begin EmitB($0F); EmitB($96); EmitB($C0); end;
                    tkGt:  begin EmitB($0F); EmitB($97); EmitB($C0); end;
                    tkGe:  begin EmitB($0F); EmitB($93); EmitB($C0); end;
                  end;
                end
                else
                begin
                  case op of
                    tkEq:  begin EmitB($0F); EmitB($94); EmitB($C0); end;
                    tkNeq: begin EmitB($0F); EmitB($95); EmitB($C0); end;
                    tkLt:  begin EmitB($0F); EmitB($9C); EmitB($C0); end;
                    tkLe:  begin EmitB($0F); EmitB($9E); EmitB($C0); end;
                    tkGt:  begin EmitB($0F); EmitB($9F); EmitB($C0); end;
                    tkGe:  begin EmitB($0F); EmitB($9D); EmitB($C0); end;
                  end;
                end;
                EmitB($48); EmitB($0F); EmitB($B6); EmitB($C0); { movzx rax, al }
              end;
            end;
        else
          Error('Unsupported operator in IR codegen');
        end;
        end;
        end;
      end;
      
    IR_NEG:
      begin
        IREmitNode(IRA[node]);
        if TypeIsFloat(IntToTypeKind(IRTk[node])) then
          { Float value lives as double bits in rax; flip the sign bit. }
          begin EmitB($48); EmitB($0F); EmitB($BA); EmitB($F8); EmitB($3F); end { btc rax, 63 }
        else
          begin EmitB($48); EmitB($F7); EmitB($D8); end; { neg rax }
      end;
      
    IR_NOT:
      begin
        IREmitNode(IRA[node]);
        EmitB($48); EmitB($83); EmitB($F0); EmitB($01); { xor rax, 1 }
      end;

    IR_WRITE:
      begin
        valNode := IRA[node];
        wid  := IRB[node];   { field width, 0 = none }
        decs := IRC[node];   { decimals, -1 = none }
        if TypeIsFloat(IntToTypeKind(IRTk[node])) then
        begin
          IREmitNode(valNode);                                        { double bits -> rax }
          EmitB($66); EmitB($48); EmitB($0F); EmitB($6E); EmitB($C0); { movq xmm0, rax }
          if decs >= 0 then EmitWriteFloatFixed(decs) else EmitWriteFloatSci;
        end
        else if IRKind[valNode] = IR_CONST_STR then
        begin
          sVal := GetTokenStrFromRaw(IRA[valNode], IRB[valNode]);
          si := InternStr(sVal);
          if (wid > 0) and (wid > Strs[si].Len) then
          begin
            EnsureSpaces;
            EmitB($48); EmitB($BE); EmitDataRef(SpacesOffset);
            MovRdxImm(wid - Strs[si].Len);
            MovRaxImm(SYS_WRITE); MovRdiImm(STDOUT); EmitSyscall;
          end;
          if Strs[si].Len > 0 then
            EmitwriteSyscall(Strs[si].Offset + 8, Strs[si].Len);
        end
        else if ((IRKind[valNode] = IR_LOAD_SYM) or (IRKind[valNode] = IR_LEA)) and
                (IntToTypeKind(IRTk[valNode]) = tyString) then
        begin
          symIdx := IRA[valNode];
          if wid > 0 then
          begin
            { Runtime string width: pad with max(0, wid - len) spaces. }
            EnsureSpaces;
            EmitLoadStrLen(symIdx);              { rcx = len }
            MovRaxImm(wid);
            EmitB($48); EmitB($29); EmitB($C8);  { sub rax, rcx }
            EmitB($7E); EmitB(35);               { jle .skip_pad (35 bytes) }
            EmitB($48); EmitB($BE); EmitDataRef(SpacesOffset);
            EmitB($48); EmitB($89); EmitB($C2);  { mov rdx, rax }
            MovRaxImm(SYS_WRITE); MovRdiImm(STDOUT); EmitSyscall;
          end;
          EmitwriteStrVar(symIdx);
        end
        else if IntToTypeKind(IRTk[node]) = tyString then
        begin
          { String-valued expression (e.g. a function returning String):
            the value is the address of a [len][chars] struct in rax. }
          IREmitNode(valNode);
          EmitB($48); EmitB($89); EmitB($C6);              { mov rsi, rax }
          EmitB($48); EmitB($8B); EmitB($10);              { mov rdx, [rax] }
          EmitB($48); EmitB($83); EmitB($C6); EmitB($08);  { add rsi, 8 }
          MovRaxImm(SYS_WRITE); MovRdiImm(STDOUT); EmitSyscall;
        end
        else
        begin
          IREmitNode(valNode);
          if IntToTypeKind(IRTk[node]) = tyChar then
            EmitwriteChar
          else if not TypeSigned(IntToTypeKind(IRTk[node])) then
          begin
            if wid > 0 then EmitwriteUIntW(wid) else EmitwriteUInt;
          end
          else
          begin
            if wid > 0 then EmitwriteIntW(wid) else EmitwriteInt;
          end;
        end;
      end;
      
    IR_CALL:
      begin
        pi := IRA[node];
        if pi >= 0 then
        begin
          { User-defined procedure/function }
          argNode := IRB[node];
          pathIdx := 0;
          while argNode <> -1 do
          begin
            IREmitNode(IRA[argNode]); { evaluates arg -> rax }
            EmitB($50); { push rax }
            argNode := IRB[argNode];
            Inc(pathIdx);
          end;
          for i := Procs[pi].ParamCount - 1 downto 0 do
            case i of
              0: EmitB($5F); { pop rdi }
              1: EmitB($5E); { pop rsi }
              2: EmitB($5A); { pop rdx }
              3: EmitB($59); { pop rcx }
              4: begin EmitB($41); EmitB($58); end; { pop r8 }
              5: begin EmitB($41); EmitB($59); end; { pop r9 }
            end;
          EmitCallProc(pi);
        end
        else if pi = -Ord(tkGetMem) then
        begin
          { Class instantiation }
          argNode := IRB[node]; { size arg }
          IREmitNode(IRA[argNode]); { Evaluate size -> rax }
          
          { Round size up to multiple of 8 for alignment }
          EmitB($48); EmitB($83); EmitB($C0); EmitB($07); { add rax, 7 }
          EmitB($48); EmitB($83); EmitB($E0); EmitB($F8); { and rax, -8 }
          
          { mov rbx, [BSS_HEAP_PTR] }
          EmitB($48); EmitB($8B); EmitB($1C); EmitB($25); EmitGlobRef(BSS_HEAP_PTR);
          
          { add rbx, rax }
          EmitB($48); EmitB($01); EmitB($C3);
          
          { cmp rbx, [BSS_HEAP_END] }
          EmitB($48); EmitB($3B); EmitB($1C); EmitB($25); EmitGlobRef(BSS_HEAP_END);
          
          { jbe skip_brk }
          EmitB($76); jbePatch := CodeLen; EmitB(0);
          
          { push rbx }
          EmitB($53);
          { mov rdi, rbx }
          EmitB($48); EmitB($89); EmitB($DF);
          { mov rax, SYS_BRK }
          MovRaxImm(SYS_BRK);
          { syscall }
          EmitSyscall;
          { pop rbx }
          EmitB($5B);
          { mov [BSS_HEAP_END], rax }
          EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_HEAP_END);
          
          { Patch short jump offset }
          Code[jbePatch] := Byte(CodeLen - (jbePatch + 1));
          
          { mov rax, [BSS_HEAP_PTR] }
          EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_HEAP_PTR);
          
          { mov [BSS_HEAP_PTR], rbx }
          EmitB($48); EmitB($89); EmitB($1C); EmitB($25); EmitGlobRef(BSS_HEAP_PTR);
          
          { Put instance pointer in rdi }
          EmitB($48); EmitB($89); EmitB($C7); { mov rdi, rax }
          
          { Initialize VMT pointer at offset 0 }
          classIdx := IRC[node];
          EmitB($48); EmitB($B8); EmitDataRef(UClsVMTOffset[classIdx - REC_UCLASS_BASE]); { mov rax, VMT_addr }
          EmitB($48); EmitB($89); EmitB($07); { mov [rdi], rax }
          
          { Find constructor 'Create' of this class }
          slot := FindUMeth(classIdx - REC_UCLASS_BASE, 'create');
          if slot >= 0 then
          begin
            cpi := UMthProc_[slot];
            
            { Push Self first }
            EmitB($57); { push rdi }
            
            { Push explicit constructor arguments }
            argNode := IRB[node]; { size arg }
            argNode := IRB[argNode]; { first explicit constructor arg }
            while argNode <> -1 do
            begin
              IREmitNode(IRA[argNode]); { evaluates arg -> rax }
              EmitB($50); { push rax }
              argNode := IRB[argNode];
            end;
            
            { Pop args into SysV ABI registers }
            for i := Procs[cpi].ParamCount-1 downto 0 do
              case i of
                0: EmitB($5F);
                1: EmitB($5E);
                2: EmitB($5A);
                3: EmitB($59);
                4: begin EmitB($41); EmitB($58); end;
                5: begin EmitB($41); EmitB($59); end;
              end;
              
            { Save Self on stack across the call }
            EmitB($57); { push rdi }
            
            EmitCallProc(cpi);
            
            { Restore Self into rax as the result of the constructor call }
            EmitB($58); { pop rax }
          end
          else
          begin
            { No constructor defined, just return the instance pointer in rax }
            EmitB($48); EmitB($89); EmitB($F8); { mov rax, rdi }
          end;
        end
        else
        begin
          { Special/built-in calls }
          specialId := -pi;
          if specialId = Ord(tkLength) then
          begin
            arg1Node := IRB[node];
            val1Node := IRA[arg1Node];
            if (IRKind[val1Node] = IR_LEA) and Syms[IRA[val1Node]].IsArray
               and (Syms[IRA[val1Node]].ArrLen = -1) then
            begin
              { Dynamic array: IR_LEA already loaded the heap data pointer (or 0).
                Length lives at [ptr-8]; a nil array reports 0. }
              IREmitNode(val1Node);                          { rax = data ptr (or 0) }
              EmitB($48); EmitB($85); EmitB($C0);            { test rax, rax }
              EmitB($74); jbePatch := CodeLen; EmitB(0);     { jz done (rax already 0) }
              EmitB($48); EmitB($8B); EmitB($40); EmitB($F8);{ mov rax, [rax-8] }
              Code[jbePatch] := Byte(CodeLen - (jbePatch + 1));
            end
            else
            begin
              IREmitNode(val1Node); { evaluates address -> rax }
              EmitB($48); EmitB($8B); EmitB($00); { mov rax, [rax] }
            end;
          end
          else if (specialId = Ord(tkOrd)) or (specialId = Ord(tkChr)) or
                  (specialId = Ord(tkInteger_T)) or (specialId = Ord(tkLongWord_T)) then
          begin
            arg1Node := IRB[node];
            IREmitNode(IRA[arg1Node]);
          end
          else if specialId = Ord(tkArgCount) then
          begin
            EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
            EmitB($48); EmitB($8B); EmitB($00);
            EmitB($48); EmitB($FF); EmitB($C8);
          end
          else if specialId = 100 then
          begin
            arg1Node := IRB[node];
            arg2Node := IRB[arg1Node];
            val1Node := IRA[arg1Node];
            val2Node := IRA[arg2Node];
            if (IRKind[val1Node] = IR_LEA) and (IRKind[val2Node] = IR_LEA) then
              EmitLoadFile(IRA[val1Node], IRA[val2Node])
            else
              Error('LoadFile expects string variables in IR codegen');
          end
          else if specialId = 101 then
          begin
            arg1Node := IRB[node];
            arg2Node := IRB[arg1Node];
            val1Node := IRA[arg1Node];
            if IRKind[val1Node] = IR_LEA then
            begin
              IREmitNode(IRA[arg2Node]);
              EmitStoreStrLen(IRA[val1Node]);
            end
            else
              Error('SetLength expects a string variable in IR codegen');
          end
          else if specialId = 102 then
          begin
            { Dynamic-array SetLength. Heap layout: [base]=refcount, [base+8]=length,
              [base+16]=data. Store the data pointer into the array variable's slot.
              v1: fresh-allocates; old contents not preserved. }
            arg1Node := IRB[node];
            arg2Node := IRB[arg1Node];
            val1Node := IRA[arg1Node];
            if IRKind[val1Node] <> IR_LEA then
              Error('SetLength expects an array variable in IR codegen');
            symIdx := IRA[val1Node];
            if (Syms[symIdx].ElemType = tyRecord) or (Syms[symIdx].ElemType = tyString) then
              Error('SetLength: dynamic array of record/string not yet supported');
            elemSize := TypeSize(Syms[symIdx].ElemType);

            IREmitNode(IRA[arg2Node]);      { rax = n }
            EmitB($50);                     { push rax -- save n }
            if elemSize = 8 then
              begin EmitB($48); EmitB($C1); EmitB($E0); EmitB($03); end { shl rax, 3 }
            else if elemSize > 1 then
              begin
                EmitB($48); EmitB($C7); EmitB($C1); EmitI32(elemSize); { mov rcx, elemSize }
                EmitB($48); EmitB($0F); EmitB($AF); EmitB($C1);        { imul rax, rcx }
              end;
            EmitB($48); EmitB($83); EmitB($C0); EmitB($10); { add rax, 16 (header) }
            EmitBumpAlloc;                  { rax = base }
            EmitB($59);                     { pop rcx -- n }
            EmitB($48); EmitB($C7); EmitB($00); EmitI32(1);  { mov qword [rax], 1 (refcount) }
            EmitB($48); EmitB($89); EmitB($48); EmitB($08);  { mov [rax+8], rcx (length) }
            EmitB($48); EmitB($83); EmitB($C0); EmitB($10);  { add rax, 16 (data ptr) }
            if Syms[symIdx].Kind = skGlobal then
              begin EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(Syms[symIdx].Offset); end
            else
              begin EmitB($48); EmitB($89); EmitB($85); EmitI32(Syms[symIdx].Offset); end;
          end
          else if specialId = SPECIAL_IN then
          begin
            arg1Node := IRB[node];
            IREmitNode(IRA[arg1Node]);
            EmitB($48); EmitB($89); EmitB($C1); { mov rcx, rax }

            trueCount := 0;
            argNode := IRB[arg1Node];
            while argNode <> -1 do
            begin
              itemNode := IRA[argNode];
              if IRKind[itemNode] = IR_BLOCK then
              begin
                lo := Integer(IRIVal[IRA[itemNode]]);
                elemSize := Integer(IRIVal[IRB[itemNode]]);
                EmitB($48); EmitB($81); EmitB($F9); EmitI32(lo);
                EmitB($0F); EmitB($8C); nextJmp := CodeLen; EmitI32(0);
                EmitB($48); EmitB($81); EmitB($F9); EmitI32(elemSize);
                EmitB($0F); EmitB($8E);
                if trueCount >= 128 then Error('set expression too large');
                trueJumps[trueCount] := CodeLen; Inc(trueCount);
                EmitI32(0);
                Patch32(nextJmp, CodeLen - (nextJmp + 4));
              end
              else
              begin
                lo := Integer(IRIVal[itemNode]);
                EmitB($48); EmitB($81); EmitB($F9); EmitI32(lo);
                EmitB($0F); EmitB($84);
                if trueCount >= 128 then Error('set expression too large');
                trueJumps[trueCount] := CodeLen; Inc(trueCount);
                EmitI32(0);
              end;
              argNode := IRB[argNode];
            end;

            MovRaxImm(0);
            EmitB($E9); falseJmp := CodeLen; EmitI32(0);
            for i := 0 to trueCount - 1 do
              Patch32(trueJumps[i], CodeLen - (trueJumps[i] + 4));
            MovRaxImm(1);
            Patch32(falseJmp, CodeLen - (falseJmp + 4));
          end
          else if specialId = Ord(tkSysOpen) then
          begin
            arg1Node := IRB[node];
            arg2Node := IRB[arg1Node];
            
            val1Node := IRA[arg1Node];
            val2Node := IRA[arg2Node];
            
            if (IRKind[val1Node] = IR_LOAD_SYM) or (IRKind[val1Node] = IR_LEA) then
              symIdx := IRA[val1Node]
            else
              symIdx := -1;
              
            EmitTerminateString(symIdx);
            EmitLeaStrDataRdi(symIdx);
            
            IREmitNode(val2Node); { Evaluates flags -> rax }
            EmitB($48); EmitB($89); EmitB($C6); { mov rsi, rax }
            MovRaxImm(0); EmitB($48); EmitB($89); EmitB($C2);
            MovRaxImm(SYS_OPEN); EmitSyscall;
          end
          else if specialId = Ord(tkSysRead) then
          begin
            arg1Node := IRB[node];
            arg2Node := IRB[arg1Node];
            arg3Node := IRB[arg2Node];
            
            IREmitNode(IRA[arg1Node]);
            EmitB($48); EmitB($89); EmitB($C7); { mov rdi, rax }
            
            IREmitNode(IRA[arg2Node]); { evaluates address -> rax }
            EmitB($48); EmitB($89); EmitB($C6); { mov rsi, rax }
            
            IREmitNode(IRA[arg3Node]);
            EmitB($48); EmitB($89); EmitB($C2); { mov rdx, rax }
            
            MovRaxImm(SYS_READ); EmitSyscall;
          end
          else if specialId = Ord(tkSyswrite) then
          begin
            arg1Node := IRB[node];
            arg2Node := IRB[arg1Node];
            arg3Node := IRB[arg2Node];
            
            IREmitNode(IRA[arg1Node]);
            EmitB($48); EmitB($89); EmitB($C7); { mov rdi, rax }
            
            IREmitNode(IRA[arg2Node]); { evaluates address -> rax }
            EmitB($48); EmitB($89); EmitB($C6); { mov rsi, rax }
            
            IREmitNode(IRA[arg3Node]);
            EmitB($48); EmitB($89); EmitB($C2); { mov rdx, rax }
            
            MovRaxImm(1); EmitSyscall;
          end
          else if specialId = Ord(tkSysClose) then
          begin
            arg1Node := IRB[node];
            IREmitNode(IRA[arg1Node]);
            EmitB($48); EmitB($89); EmitB($C7); { mov rdi, rax }
            MovRaxImm(SYS_CLOSE); EmitSyscall;
          end
          else if specialId = Ord(tkArgStr) then
          begin
            { ArgStr(index, strVar): copy argv[index] into the string variable.
              arg1 = index expr, arg2 = string var (lowers to IR_LEA). }
            arg1Node := IRB[node];
            arg2Node := IRB[arg1Node];
            val2Node := IRA[arg2Node];
            if (IRKind[val2Node] = IR_LEA) or (IRKind[val2Node] = IR_LOAD_SYM) then
              symIdx := IRA[val2Node]
            else
              Error('ArgStr expects a string variable in IR codegen');
            IREmitNode(IRA[arg1Node]);   { rax = index }
            EmitArgvToString(symIdx);
          end
          else if specialId = Ord(tkSysFchmod) then
          begin
            arg1Node := IRB[node];
            arg2Node := IRB[arg1Node];
            IREmitNode(IRA[arg1Node]);
            EmitB($48); EmitB($89); EmitB($C7); { mov rdi, rax }
            IREmitNode(IRA[arg2Node]);
            EmitB($48); EmitB($89); EmitB($C6); { mov rsi, rax }
            MovRaxImm(91); EmitSyscall;
          end;
        end;
      end;
      
    IR_WRITELN:
      begin
        EmitwriteSyscall(NEWLINE_OFFSET, 1);
      end;

    IR_EXC_LEAVE:
      begin
        IREmitLeaveExceptionFrames(IRA[node]);
      end;

    IR_RAISE:
      begin
        if IRA[node] <> -1 then
        begin
          IREmitNode(IRA[node]);
          EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_OBJ);
          raiseClass := Integer(IRIVal[node]);
          MovRaxImm(raiseClass);
          EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_CLS);
        end;
        IREmitCodeCall(ExcRaiseAddr);
      end;

    IR_EXC_STORE:
      begin
        EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_OBJ);
        EmitStoreVar(IRA[node]);
      end;

    IR_EXC_CLEAR:
      begin
        MovRaxImm(0);
        EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_OBJ);
        EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_CLS);
      end;

    IR_TERMINATE:
      begin
        if IRIVal[node] = AN_HALT then
        begin
          if IRA[node] <> -1 then
          begin
            IREmitNode(IRA[node]);
            EmitB($48); EmitB($89); EmitB($C7);
            MovRaxImm(SYS_EXIT);
            EmitSyscall;
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
    IR_VIRTUAL_CALL:
      begin
        { IRA=first arg, IRB=last arg, IRC=proc idx, IRIVal=VMT slot }
        pi := IRC[node];
        slot := Integer(IRIVal[node]);
        argNode := IRA[node];
        pathIdx := 0;
        while argNode <> -1 do
        begin
          IREmitNode(IRA[argNode]); { evaluates arg -> rax }
          EmitB($50); { push rax }
          argNode := IRB[argNode];
          Inc(pathIdx);
        end;
        for i := Procs[pi].ParamCount - 1 downto 0 do
          case i of
            0: EmitB($5F); { pop rdi  (Self) }
            1: EmitB($5E); { pop rsi }
            2: EmitB($5A); { pop rdx }
            3: EmitB($59); { pop rcx }
            4: begin EmitB($41); EmitB($58); end; { pop r8 }
            5: begin EmitB($41); EmitB($59); end; { pop r9 }
          end;
        { Virtual Method Table dispatch }
        EmitB($48); EmitB($8B); EmitB($07); { mov rax, [rdi]   -- load VMT pointer }
        EmitB($FF); EmitB($90); EmitI32(slot * 8); { call [rax + slot*8] }
      end;

  else
  begin
    writeln('Unsupported linear node in IR codegen! Kind=', IRKind[node], ' node=', node,
            ' IRA=', IRA[node], ' IRB=', IRB[node], ' IRC=', IRC[node], ' IRIVal=', IRIVal[node]);
    Error('Unsupported linear node in IR codegen');
  end;
  end;
end;

procedure IREmitMachineCode;
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
          begin
            EmitB($E9);
            EmitI32(LabelPositions[lblId] - (CodeLen + 4));
          end
          else
          begin
            EmitB($E9);
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitI32(0);
          end;
        end;

      IR_JUMP_IF_FALSE:
        begin
          lblId := IRA[i];
          IREmitNode(IRB[i]); { evaluate condition -> rax }
          EmitB($48); EmitB($85); EmitB($C0); { test rax, rax }
          if LabelPositions[lblId] <> -1 then
          begin
            EmitB($0F); EmitB($84); { jz 32-bit rel }
            EmitI32(LabelPositions[lblId] - (CodeLen + 4));
          end
          else
          begin
            EmitB($0F); EmitB($84);
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitI32(0);
          end;
        end;

      IR_EXC_ENTER:
        begin
          lblId := IRA[i];
          EmitB($48); EmitB($83); EmitB($EC); EmitB(EXC_FRAME_SIZE);
          EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_TOP);
          EmitB($48); EmitB($89); EmitB($04); EmitB($24);
          EmitB($48); EmitB($89); EmitB($E0);
          EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_TOP);
          EmitB($48); EmitB($8D); EmitB($7C); EmitB($24); EmitB(EXC_JMP_OFFSET);
          IREmitCodeCall(ExcSetJmpAddr);
          EmitB($85); EmitB($C0);
          if LabelPositions[lblId] <> -1 then
          begin
            EmitB($0F); EmitB($85);
            EmitI32(LabelPositions[lblId] - (CodeLen + 4));
          end
          else
          begin
            EmitB($0F); EmitB($85);
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitI32(0);
          end;
        end;

      IR_EXC_MATCH:
        begin
          lblId := IRA[i];
          EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_CLS);
          EmitB($48); EmitB($3D); EmitI32(Integer(IRIVal[i]));
          if LabelPositions[lblId] <> -1 then
          begin
            EmitB($0F); EmitB($85);
            EmitI32(LabelPositions[lblId] - (CodeLen + 4));
          end
          else
          begin
            EmitB($0F); EmitB($85);
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitI32(0);
          end;
        end;

      IR_CALL:
        begin
          if IRIVal[i] = 1 then
            IREmitNode(i);
        end;

      IR_STORE_SYM, IR_STORE_MEM, IR_WRITE, IR_WRITELN,
      IR_EXC_LEAVE, IR_RAISE, IR_EXC_STORE, IR_EXC_CLEAR, IR_TERMINATE,
      IR_ASM:
        begin
          IREmitNode(i);
        end;
    end;
  end;

  { Patch forward jumps }
  for f := 0 to LabelFixupCount - 1 do
  begin
    lblId := LabelFixupTarget[f];
    pos := LabelFixupPos[f];
    targetOffset := LabelPositions[lblId];
    if targetOffset = -1 then Error('Unresolved forward jump in IR codegen');
    Patch32(pos, targetOffset - (pos + 4));
  end;
end;
