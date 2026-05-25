
procedure ParseExpr; forward;

procedure SkipSelectors;
begin
  while CurTok.Kind in [tkDot, tkLBrack] do
  begin
    if CurTok.Kind = tkDot then
    begin
      Next;
      if CurTok.Kind in [tkEOF, tkSemicolon, tkAssign, tkRBrack, tkRParen] then Error('expected field name');
      Next;
    end
    else
    begin
      Next;
      ParseExpr;
      Expect(tkRBrack, ']');
    end;
  end;
end;

function ParseSetConst: Int64;
var idx: Integer;
begin
  if CurTok.Kind = tkInteger then
  begin
    Result := CurTok.IVal;
    Next;
  end
  else if CurTok.Kind = tkString then
  begin
    if Length(CurTok.SVal) <> 1 then Error('set item must be one character');
    Result := Ord(CurTok.SVal[1]);
    Next;
  end
  else if CurTok.Kind = tkIdent then
  begin
    idx := FindSym(CurTok.SVal);
    if (idx < 0) or (Syms[idx].Kind <> skConst) then Error('set item must be constant');
    Result := Syms[idx].ConstVal;
    Next;
  end
  else Error('expected set item');
end;

procedure ParseSetMembership;
const MAX_SET_JUMPS = 128;
var
  lo, hi: Int64;
  trueJumps: array[0..MAX_SET_JUMPS-1] of Integer;
  trueCount, falseJmp, nextJmp, i: Integer;
  done: Boolean;
begin
  { Left expression is in rax. Keep it in rcx and produce boolean in rax. }
  EmitB($48); EmitB($89); EmitB($C1);       { mov rcx, rax }
  Expect(tkLBrack, '[');
  trueCount := 0;
  if CurTok.Kind <> tkRBrack then
  begin
    done := False;
    while not done do
    begin
      lo := ParseSetConst;
      hi := lo;
      if Eat(tkDotDot) then hi := ParseSetConst;

      if lo = hi then
      begin
        EmitB($48); EmitB($81); EmitB($F9); EmitI32(lo); { cmp rcx, imm32 }
        EmitB($0F); EmitB($84);
        if trueCount >= MAX_SET_JUMPS then Error('set expression too large');
        trueJumps[trueCount] := CodeLen; Inc(trueCount);
        EmitI32(0);
      end
      else
      begin
        EmitB($48); EmitB($81); EmitB($F9); EmitI32(lo); { cmp rcx, lo }
        EmitB($0F); EmitB($8C); nextJmp := CodeLen; EmitI32(0); { jl next }
        EmitB($48); EmitB($81); EmitB($F9); EmitI32(hi); { cmp rcx, hi }
        EmitB($0F); EmitB($8E);
        if trueCount >= MAX_SET_JUMPS then Error('set expression too large');
        trueJumps[trueCount] := CodeLen; Inc(trueCount);
        EmitI32(0);
        Patch32(nextJmp, CodeLen - (nextJmp + 4));
      end;

      if not Eat(tkComma) then done := True;
    end;
  end;
  Expect(tkRBrack, ']');
  MovRaxImm(0);
  EmitB($E9); falseJmp := CodeLen; EmitI32(0);
  for i := 0 to trueCount-1 do
    Patch32(trueJumps[i], CodeLen - (trueJumps[i] + 4));
  MovRaxImm(1);
  Patch32(falseJmp, CodeLen - (falseJmp + 4));
end;

procedure CompileLValueAddressInternal(idx: Integer; var tk: TTypeKind; var recName: Integer); forward;
procedure CompileLValueAddress(const name: AnsiString; var tk: TTypeKind; var recName: Integer); forward;
procedure ParseLValue(const name: AnsiString); forward;
procedure EmitArgvToAddr; forward;

procedure EmitArgvToAddr;
begin
  { On entry: rax = argv index, rdi = destination address. }
  EmitB($57); { push rdi }
  EmitB($48); EmitB($C1); EmitB($E0); EmitB($03);   { shl rax, 3 }
  EmitB($48); EmitB($8B); EmitB($0C); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
  EmitB($48); EmitB($83); EmitB($C1); EmitB($08);   { add rcx, 8 }
  EmitB($48); EmitB($01); EmitB($C8);               { add rax, rcx }
  EmitB($48); EmitB($8B); EmitB($00);               { mov rax, [rax] }
  EmitB($48); EmitB($89); EmitB($C6);               { mov rsi, rax }
  EmitB($48); EmitB($31); EmitB($C9);               { xor rcx, rcx }
  EmitB($80); EmitB($3C); EmitB($0E); EmitB($00);   { cmp byte [rsi+rcx], 0 }
  EmitB($74); EmitB($05);                           { je +5 }
  EmitB($48); EmitB($FF); EmitB($C1);               { inc rcx }
  EmitB($EB); EmitB($F5);                           { jmp -11 }
  EmitB($5F); { pop rdi }
  EmitB($48); EmitB($89); EmitB($0F);               { mov [rdi], rcx }
  EmitB($48); EmitB($83); EmitB($C7); EmitB($08);   { add rdi, 8 }
  EmitB($F3); EmitB($A4);                           { rep movsb }
end;

procedure CompileLValueAddressInternal(idx: Integer; var tk: TTypeKind; var recName: Integer);
var
  curTk: TTypeKind;
  curRec: Integer;
  offset, elemSize, lo: Integer;
  isArr: Boolean;
begin
  if Syms[idx].Kind = skGlobal then
  begin
    { Global variable base address }
    EmitB($48); EmitB($8D); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset);
  end
  else
  begin
    { Local variable or parameter base address }
    if (Syms[idx].Kind = skParam) and (Syms[idx].IsArray or (Syms[idx].TypeKind = tyString)) then
    begin
      { param slot holds pointer P; address of string/array struct = P }
      EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[idx].Offset); { mov rax, [rbp+off] = P }
    end
    else
    begin
      { Local variable or regular parameter address: lea rax, [rbp + Offset] }
      EmitB($48); EmitB($8D); EmitB($85); EmitI32(Syms[idx].Offset);
    end;
  end;
  
  curTk := Syms[idx].TypeKind;
  curRec := Syms[idx].RecName;
  isArr := Syms[idx].IsArray;
  
  while CurTok.Kind in [tkLBrack, tkDot] do
  begin
    if CurTok.Kind = tkLBrack then
    begin
      Next;
      EmitB($50); { push rax -- base address }
      ParseExpr; { rax = index }
      Expect(tkRBrack, ']');
      
      if isArr then
      begin
        elemSize := 1;
        if curTk in [tyInteger, tyBoolean] then elemSize := 8
        else if curTk = tyChar then elemSize := 1
        else if curTk = tyString then
        begin
          if Syms[idx].Kind = skGlobal then elemSize := STRING_CAP + 8
          else elemSize := LOCAL_STR_CAP + 8;
        end
        else if curTk = tyRecord then
        begin
          if curRec = REC_NONE then
            elemSize := RecSize(Syms[idx].ElemRecName)
          else
            elemSize := RecSize(curRec);
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
        
        if curRec = REC_TPARAM then lo := 0
        else lo := Syms[idx].ConstVal;
        
        if lo <> 0 then
        begin
          EmitB($48); EmitB($2D); EmitI32(lo * elemSize); { sub rax, lo*elemSize }
        end;
        
        EmitB($59); { pop rcx -- base address }
        EmitB($48); EmitB($01); EmitB($C8); { add rax, rcx }
        
        isArr := False;
        if curRec = REC_TPARAM then
        begin
          curTk := tyRecord;
          curRec := REC_TPARAM;
        end
        else
        begin
          curTk := Syms[idx].ElemType;
          curRec := Syms[idx].ElemRecName;
        end;
      end
      else if curTk = tyString then
      begin
        { String character access! }
        { rax = index (1-based). We want to compute: base + 8 + (rax - 1) = base + 7 + rax }
        EmitB($48); EmitB($05); EmitI32(7);
        EmitB($59); { pop rcx -- base address }
        EmitB($48); EmitB($01); EmitB($C8); { add rax, rcx }
        
        curTk := tyChar;
        curRec := REC_NONE;
      end
      else
        Error('subscripted value is not an array or string');
    end
    else
    begin
      Next;
      if CurTok.Kind in [tkEOF, tkSemicolon, tkAssign, tkRBrack, tkRParen] then Error('expected field name');
      if VERBOSE then writeln('Dot selector: curRec = ', curRec, ', field = ', CurTok.SVal);
      offset := RecFieldOffset(curRec, CurTok.SVal);
      EmitB($48); EmitB($05); EmitI32(offset); { add rax, offset }
      
      isArr := RecFieldIsArray(curRec, CurTok.SVal);
      
      curTk := RecFieldType(curRec, CurTok.SVal);
      curRec := RecFieldRecId(curRec, CurTok.SVal);
      Next;
    end;
  end;
  tk := curTk;
  recName := curRec;
end;

procedure CompileLValueAddress(const name: AnsiString; var tk: TTypeKind; var recName: Integer);
var idx: Integer;
begin
  idx := FindSym(name);
  if idx < 0 then
  begin
    ErrorIdent := name;
    Error('undefined variable');
  end;
  CompileLValueAddressInternal(idx, tk, recName);
end;

procedure ParseLValue(const name: AnsiString);
var
  idx, si, si2, rhsIdx: Integer;
  isComplex: Boolean;
  tk, rhsTk: TTypeKind;
  recName, rhsRecName: Integer;
  rhsName: AnsiString;
begin
  if VERBOSE then writeln('Parsing LValue: ', name);
  idx := FindSym(name);
  if idx < 0 then
  begin
    ErrorIdent := name;
    Error('undefined variable');
  end;
  
  Next; { consume identifier }
  isComplex := CurTok.Kind in [tkLBrack, tkDot];
  
  if not isComplex then
  begin
    Expect(tkAssign, ':=');
    if Syms[idx].TypeKind = tyString then
    begin
      if CurTok.Kind = tkString then
      begin
        si := InternStr(CurTok.SVal); Next;
        EmitStrAssignLiteral(idx, Strs[si].Offset, Strs[si].Len);
      end
      else if CurTok.Kind = tkArgStr then
      begin
        Next; Expect(tkLParen, '(');
        ParseExpr;
        Expect(tkRParen, ')');
        EmitArgvToString(idx);
      end
      else
      begin
        si2 := FindSym(CurTok.SVal);
        if (si2 >= 0) and (Syms[si2].TypeKind = tyString) then
        begin
          EmitStrAssignVar(idx, si2); Next;
        end
        else if CurTok.Kind = tkIdent then
        begin
          rhsName := CurTok.SVal;
          if CurTok.Kind = tkIdent then
          begin
            Next; { consume RHS identifier before compiling its address }
            CompileLValueAddress(rhsName, rhsTk, rhsRecName);
            if rhsTk <> tyString then
            begin
              if VERBOSE then writeln('rhsTk: ', Ord(rhsTk));
              Error('type mismatch: expected string');
            end;
            EmitLeaStrDataRdi(idx);
            EmitB($48); EmitB($89); EmitB($C6); { mov rsi, rax }
            EmitB($48); EmitB($8B); EmitB($06); { mov rax, [rsi] }
            EmitStoreStrLen(idx);
            EmitB($48); EmitB($89); EmitB($C1); { mov rcx, rax }
            EmitB($48); EmitB($83); EmitB($C6); EmitB($08); { add rsi, 8 }
            EmitB($F3); EmitB($A4); { rep movsb }
          end;
        end
        else Error('string assignment: literal or string LValue required');
      end;
    end
    else
    begin
      ParseExpr;
      EmitStoreVar(idx);
    end;
  end
  else
  begin
    CompileLValueAddressInternal(idx, tk, recName);
    EmitB($50); { push rax -- destination address }
    Expect(tkAssign, ':=');
    
    if tk = tyString then
    begin
      if CurTok.Kind = tkString then
      begin
        si := InternStr(CurTok.SVal); Next;
        EmitB($5F); { pop rdi -- LHS address }
        EmitB($48); EmitB($C7); EmitB($C0); EmitI32(Strs[si].Len);
        EmitB($48); EmitB($89); EmitB($07);
        EmitB($48); EmitB($BE); EmitDataRef(Strs[si].Offset + 8);
        EmitB($48); EmitB($89); EmitB($C1);
        EmitB($48); EmitB($83); EmitB($C7); EmitB($08);
        EmitB($F3); EmitB($A4);
      end
      else if CurTok.Kind = tkArgStr then
      begin
        Next; Expect(tkLParen, '(');
        ParseExpr;
        EmitB($50); { push rax }
        EmitB($5F); { pop rdi -- LHS address }
        EmitB($58); { pop rax -- index }
        EmitArgvToAddr;
      end
      else
      begin
        { RHS is complex string or string var }
        rhsName := CurTok.SVal;
        Next; { consume RHS identifier before compiling its address }
        CompileLValueAddress(rhsName, rhsTk, rhsRecName);
        if rhsTk <> tyString then
        begin
          if VERBOSE then writeln('rhsTk: ', Ord(rhsTk));
          Error('type mismatch: expected string');
        end;
        EmitB($5F); { pop rdi -- LHS address }
        EmitB($48); EmitB($89); EmitB($C6); { mov rsi, rax }
        EmitB($48); EmitB($8B); EmitB($06); { mov rax, [rsi] }
        EmitB($48); EmitB($89); EmitB($07); { mov [rdi], rax }
        EmitB($48); EmitB($89); EmitB($C1); { mov rcx, rax }
        EmitB($48); EmitB($83); EmitB($C6); EmitB($08); { add rsi, 8 }
        EmitB($48); EmitB($83); EmitB($C7); EmitB($08); { add rdi, 8 }
        EmitB($F3); EmitB($A4);
      end;
    end
    else
    begin
      ParseExpr;
      EmitB($59); { pop rcx -- LHS address }
      if tk in [tyInteger, tyBoolean] then
        begin EmitB($48); EmitB($89); EmitB($01); end
      else if tk = tyChar then
        begin EmitB($88); EmitB($01); end;
    end;
  end;
end;

procedure ParseFactor;
var name: AnsiString; recName: Integer; idx, pi, i: Integer; tk: TTypeKind;
begin
  LastExprTk := tyInteger;
  case CurTok.Kind of
    tkInteger: begin MovRaxImm(CurTok.IVal); Next; end;
    tkTrue:    begin MovRaxImm(1); Next; LastExprTk := tyBoolean; end;
    tkFalse:   begin MovRaxImm(0); Next; LastExprTk := tyBoolean; end;
    tkString:
    begin
      { Single-char literal → ordinal value }
      if Length(CurTok.SVal) = 1 then begin MovRaxImm(Ord(CurTok.SVal[1])); Next; LastExprTk := tyChar; end
      else
      begin
        idx := InternStr(CurTok.SVal); Next;
        EmitB($48); EmitB($B8); EmitDataRef(Strs[idx].Offset);
        LastExprTk := tyString;
      end;
    end;
    tkLParen:  begin Next; ParseExpr; Expect(tkRParen, ')'); end;
    tkMinus:
    begin
      Next; ParseFactor;
      EmitB($48); EmitB($F7); EmitB($D8);
    end;
    tkNot:
    begin
      Next; ParseFactor;
      EmitB($48); EmitB($83); EmitB($F0); EmitB($01);
      LastExprTk := tyBoolean;
    end;
    tkOrd, tkChr:
    begin
      Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
      if CurTok.Kind = tkChr then LastExprTk := tyChar else LastExprTk := tyInteger;
    end;
    tkInteger_T, tkLongWord_T:
    begin
      Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
    end;
    tkLength:
    begin
      Next; Expect(tkLParen, '(');
      if CurTok.Kind <> tkIdent then Error('Length: expected string variable');
      idx := FindSym(CurTok.SVal);
      if (idx >= 0) and (Syms[idx].TypeKind = tyString) then
        EmitLoadVar(idx)
      else
        MovRaxImm(0);
      Next;
      SkipSelectors;
      Expect(tkRParen, ')');
    end;
    tkSysOpen:
    begin
      { SysOpen(path_str_var, flags): Integer = fd }
      Next; Expect(tkLParen, '(');
      if CurTok.Kind <> tkIdent then Error('SysOpen: expected string var');
      idx := FindSym(CurTok.SVal);
      if (idx < 0) or (Syms[idx].TypeKind <> tyString) then Error('SysOpen: not a string var');
      { lea rdi, [bss+str.Offset+8] (path data, NUL-terminated) }
      EmitB($48); EmitB($8D); EmitB($3C); EmitB($25); EmitGlobRef(Syms[idx].Offset + 8);
      Next; Expect(tkComma, ',');
      ParseExpr;   { flags → rax }
      EmitB($48); EmitB($89); EmitB($C6);               { mov rsi, rax }
      MovRaxImm(0); EmitB($48); EmitB($89); EmitB($C2); { rdx=0 (mode ignored for open) }
      MovRaxImm(SYS_OPEN); EmitSyscall;
      Expect(tkRParen, ')');
    end;
    tkSysRead:
    begin
      { SysRead(fd, buf_array, maxn): Integer = bytes read }
      Next; Expect(tkLParen, '(');
      ParseExpr; EmitB($48); EmitB($89); EmitB($C7);     { mov rdi, rax (fd) }
      Expect(tkComma, ',');
      if CurTok.Kind <> tkIdent then Error('SysRead: expected array var');
      idx := FindSym(CurTok.SVal);
      if (idx < 0) or not Syms[idx].IsArray then Error('SysRead: not an array var');
      { lea rsi, [bss+arr.Offset] }
      EmitB($48); EmitB($8D); EmitB($34); EmitB($25); EmitGlobRef(Syms[idx].Offset);
      Next; Expect(tkComma, ',');
      ParseExpr; EmitB($48); EmitB($89); EmitB($C2);     { mov rdx, rax (count) }
      MovRaxImm(SYS_READ); EmitSyscall;
      Expect(tkRParen, ')');
    end;
    tkSyswrite:
    begin
      { Syswrite(fd, buf_array, n): Integer = bytes written }
      Next; Expect(tkLParen, '(');
      ParseExpr; EmitB($48); EmitB($89); EmitB($C7);     { mov rdi, rax (fd) }
      Expect(tkComma, ',');
      if CurTok.Kind <> tkIdent then Error('Syswrite: expected array var');
      idx := FindSym(CurTok.SVal);
      if (idx < 0) or not Syms[idx].IsArray then Error('Syswrite: not an array var');
      { lea rsi, [bss+arr.Offset] }
      EmitB($48); EmitB($8D); EmitB($34); EmitB($25); EmitGlobRef(Syms[idx].Offset);
      Next; Expect(tkComma, ',');
      ParseExpr; EmitB($48); EmitB($89); EmitB($C2);     { mov rdx, rax (count) }
      MovRaxImm(1); EmitSyscall;                          { SYS_WRITE=1 }
      Expect(tkRParen, ')');
    end;
    tkArgCount:
    begin
      { ArgCount(): Integer = argc - 1  (Pascal ParamCount semantics) }
      Next;
      if CurTok.Kind = tkLParen then begin Next; Expect(tkRParen, ')'); end;
      EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
      EmitB($48); EmitB($8B); EmitB($00);               { mov rax, [rax] = argc }
      EmitB($48); EmitB($FF); EmitB($C8);               { dec rax → argc-1 }
    end;
    tkIdent:
    begin
      name := CurTok.SVal;
      idx  := FindSym(name);
      pi   := FindProc(name);
      if (idx >= 0) and (Syms[idx].Kind = skConst) then
      begin
        MovRaxImm(Syms[idx].ConstVal); Next;
      end
      else if (pi >= 0) and Procs[pi].IsFunc then
      begin
        { Function call in expression }
        Next;
        { Push args left to right }
        if CurTok.Kind = tkLParen then
        begin
          Next;
          for i := 0 to Procs[pi].ParamCount-1 do
          begin
            ParseExpr; EmitB($50);
            if i < Procs[pi].ParamCount-1 then Expect(tkComma, ',');
          end;
          Expect(tkRParen, ')');
        end;
        { Pop into registers right to left }
        for i := Procs[pi].ParamCount-1 downto 0 do
          case i of
            0: EmitB($5F);
            1: EmitB($5E);
            2: EmitB($5A);
            3: EmitB($59);
            4: begin EmitB($41); EmitB($58); end;
            5: begin EmitB($41); EmitB($59); end;
          end;
        EmitCallProc(pi);
        { rax = return value }
        LastExprTk := Procs[pi].RetType;
      end
      else if idx >= 0 then
      begin
        Next;
        if CurTok.Kind in [tkLBrack, tkDot] then
        begin
          CompileLValueAddressInternal(idx, tk, recName);
          LastExprTk := tk;
          if tk = tyString then
            begin { leave address in rax } end
          else if tk in [tyInteger, tyBoolean] then
            begin EmitB($48); EmitB($8B); EmitB($00); end
          else if tk = tyChar then
            begin EmitB($48); EmitB($0F); EmitB($B6); EmitB($00); end;
        end
        else
        begin
          LastExprTk := Syms[idx].TypeKind;
          if (Syms[idx].TypeKind = tyString) and not Syms[idx].IsArray then
            CompileLValueAddressInternal(idx, tk, recName)
          else
            EmitLoadVar(idx);
        end;
      end
    end;
    else Error('expected expression');
  end;
end;

procedure ParseTerm;
var op: TTokenKind; isShr: Boolean;
begin
  ParseFactor;
  while (CurTok.Kind in [tkStar, tkDiv, tkMod, tkAnd]) or
        ((CurTok.Kind = tkIdent) and (CurTok.SVal = 'shr')) do
  begin
    isShr := (CurTok.Kind = tkIdent) and (CurTok.SVal = 'shr');
    op := CurTok.Kind; Next;
    EmitB($50);
    ParseFactor;
    EmitB($48); EmitB($89); EmitB($C1);
    EmitB($58);
    if isShr then
      begin EmitB($48); EmitB($D3); EmitB($E8); end
    else
      case op of
        tkStar: begin EmitB($48); EmitB($0F); EmitB($AF); EmitB($C1); end;
        tkDiv:  begin EmitB($48); EmitB($99); EmitB($48); EmitB($F7); EmitB($F9); end;
        tkMod:  begin EmitB($48); EmitB($99); EmitB($48); EmitB($F7); EmitB($F9);
                      EmitB($48); EmitB($89); EmitB($D0); end;
        tkAnd:  begin EmitB($48); EmitB($21); EmitB($C8); end;
      end;
  end;
end;

procedure ParseSimpleExpr;
var op: TTokenKind; neg: Boolean;
begin
  neg := CurTok.Kind = tkMinus; Eat(tkMinus); Eat(tkPlus);
  ParseTerm;
  if neg then begin EmitB($48); EmitB($F7); EmitB($D8); end;
  while CurTok.Kind in [tkPlus, tkMinus, tkOr] do
  begin
    op := CurTok.Kind; Next; EmitB($50); ParseTerm;
    EmitB($48); EmitB($89); EmitB($C1); EmitB($58);
    case op of
      tkPlus:  begin EmitB($48); EmitB($01); EmitB($C8); end;
      tkMinus: begin EmitB($48); EmitB($29); EmitB($C8); end;
      tkOr:    begin EmitB($48); EmitB($09); EmitB($C8); end;
    end;
  end;
end;

procedure ParseExpr;
var op: TTokenKind; lhsTk: TTypeKind;
begin
  ParseSimpleExpr;
  lhsTk := LastExprTk;
  if (CurTok.Kind = tkIdent) and ((CurTok.SVal = 'in') or (CurTok.SVal = 'In')) then
  begin
    Next;
    ParseSetMembership;
    Exit;
  end;
  if CurTok.Kind in [tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe] then
  begin
    op := CurTok.Kind; Next; EmitB($50); ParseSimpleExpr;
    if (lhsTk = tyString) or (LastExprTk = tyString) then
    begin
      EmitB($48); EmitB($89); EmitB($C1); EmitB($58);  { mov rcx, rax; pop rax }
      EmitStrCmpReg(op = tkEq);
    end
    else
    begin
      EmitB($48); EmitB($89); EmitB($C1); EmitB($58);
      EmitB($48); EmitB($3B); EmitB($C1);
      case op of
        tkEq:  begin EmitB($0F); EmitB($94); EmitB($C0); end;
        tkNeq: begin EmitB($0F); EmitB($95); EmitB($C0); end;
        tkLt:  begin EmitB($0F); EmitB($9C); EmitB($C0); end;
        tkLe:  begin EmitB($0F); EmitB($9E); EmitB($C0); end;
        tkGt:  begin EmitB($0F); EmitB($9F); EmitB($C0); end;
        tkGe:  begin EmitB($0F); EmitB($9D); EmitB($C0); end;
      end;
      EmitB($48); EmitB($0F); EmitB($B6); EmitB($C0);
    end;
  end;
end;

function ConstEval: Int64;
{ Evaluate a compile-time constant expression (no code emitted) }
var r, v: Int64; idx: Integer; op: TTokenKind;
begin
  r := 0;
  if CurTok.Kind = tkInteger then begin r := CurTok.IVal; Next; end
  else if CurTok.Kind = tkTrue  then begin r := 1; Next; end
  else if CurTok.Kind = tkFalse then begin r := 0; Next; end
  else if CurTok.Kind = tkMinus then begin Next; r := -ConstEval(); end
  else if CurTok.Kind = tkIdent then
  begin
    idx := FindSym(CurTok.SVal);
    if (idx >= 0) and (Syms[idx].Kind = skConst) then
      r := Syms[idx].ConstVal
    else
    begin
      if VERBOSE then writeln('ConstEval error: SVal = ', CurTok.SVal, ' idx = ', idx);
      if VERBOSE and (idx >= 0) then writeln('Sym Kind = ', Ord(Syms[idx].Kind));
      Error('not a constant');
    end;
    Next;
  end
  else if CurTok.Kind = tkLParen then
  begin
    Next; r := ConstEval; Expect(tkRParen, ')');
  end;
  while CurTok.Kind in [tkPlus, tkMinus, tkStar, tkDiv] do
  begin
    op := CurTok.Kind; Next; v := ConstEval();
    case op of
      tkPlus:  r := r + v;
      tkMinus: r := r - v;
      tkStar:  r := r * v;
      tkDiv:   r := r div v;
    end;
  end;
  Result := r;
end;

{ ===== Statement parser ===== }

procedure ParseStatement; forward;

procedure ParsewriteArgs(newline: Boolean);
var si, vidx: Integer; done: Boolean;
begin
  if CurTok.Kind = tkLParen then
  begin
    Next;
    { Skip the predefined diagnostic output descriptor: writeln(StdErr, ...) }
    if CurTok.Kind = tkIdent then
    begin
      vidx := FindSym(CurTok.SVal);
      if (vidx >= 0) and (Syms[vidx].Kind = skConst) and
         (Syms[vidx].TypeKind = tyInteger) and
         (Syms[vidx].Name = 'StdErr') then
      begin
        Next;  { skip fd identifier }
        Eat(tkComma);
      end;
    end;
    done := False;
    while (CurTok.Kind <> tkRParen) and not done do
    begin
      if CurTok.Kind = tkString then
      begin
        si := InternStr(CurTok.SVal); Next;
        if Strs[si].Len > 0 then EmitwriteSyscall(Strs[si].Offset + 8, Strs[si].Len);
      end
      else if CurTok.Kind = tkIdent then
      begin
        vidx := FindSym(CurTok.SVal);
        if (vidx >= 0) and (Syms[vidx].TypeKind = tyString) then
        begin
          EmitwriteStrVar(vidx); Next;
        end
        else if (vidx >= 0) and Syms[vidx].IsArray and (Syms[vidx].ElemType = tyChar) then
        begin
          { char array element: writeln(arr[i]) writes as character }
          ParseExpr;
          EmitwriteChar;
        end
        else begin ParseExpr; EmitwriteInt; end;
      end
      else begin ParseExpr; EmitwriteInt; end;
      if not Eat(tkComma) then done := True;
    end;
    Expect(tkRParen, ')');
  end;
  if newline then EmitwriteSyscall(NEWLINE_OFFSET, 1);
end;

procedure ParseIfStatement;
var elseJmp, thenJmp: Integer;
begin
  ParseExpr;
  EmitB($48); EmitB($85); EmitB($C0);
  EmitB($0F); EmitB($84); thenJmp := CodeLen; EmitI32(0);
  Expect(tkThen, 'then');
  ParseStatement;
  if CurTok.Kind = tkElse then
  begin
    EmitB($E9); elseJmp := CodeLen; EmitI32(0);
    Patch32(thenJmp, CodeLen - (thenJmp + 4));
    Next; ParseStatement;
    Patch32(elseJmp, CodeLen - (elseJmp + 4));
  end
  else
    Patch32(thenJmp, CodeLen - (thenJmp + 4));
end;

procedure ParseWhileStatement;
var loopTop, condJmp: Integer;
begin
  loopTop := CodeLen;
  ParseExpr;
  EmitB($48); EmitB($85); EmitB($C0);
  EmitB($0F); EmitB($84); condJmp := CodeLen; EmitI32(0);
  Expect(tkDo, 'do');
  ParseStatement;
  EmitB($E9); EmitI32(loopTop - (CodeLen + 4));
  Patch32(condJmp, CodeLen - (condJmp + 4));
end;

procedure ParseForStatement;
var varIdx, limitIdx, loopTop, exitJmp: Integer; down: Boolean;
begin
  if CurTok.Kind <> tkIdent then Error('for: expected variable');
  varIdx := FindSym(CurTok.SVal);
  if varIdx < 0 then Error('for: undefined');
  Next;
  Expect(tkAssign, ':=');
  ParseExpr; EmitStoreVar(varIdx);
  down := CurTok.Kind = tkDownto;
  if down then Next else Expect(tkTo, 'to');
  ParseExpr;
  limitIdx := AllocTemp; EmitStoreVar(limitIdx);
  loopTop := CodeLen;
  EmitLoadVar(varIdx);
  EmitCmpRaxVar(limitIdx);
  EmitB($0F); if down then EmitB($8C) else EmitB($8F);
  exitJmp := CodeLen; EmitI32(0);
  Expect(tkDo, 'do');
  ParseStatement;
  EmitLoadVar(varIdx);
  if down then begin EmitB($48); EmitB($FF); EmitB($C8); end
           else begin EmitB($48); EmitB($FF); EmitB($C0); end;
  EmitStoreVar(varIdx);
  EmitB($E9); EmitI32(loopTop - (CodeLen + 4));
  Patch32(exitJmp, CodeLen - (exitJmp + 4));
end;

procedure ParseRepeatStatement;
var loopTop: Integer;
begin
  loopTop := CodeLen;
  while not (CurTok.Kind in [tkUntil, tkEOF]) do
    begin ParseStatement; Eat(tkSemicolon); end;
  Expect(tkUntil, 'until');
  ParseExpr;
  EmitB($48); EmitB($85); EmitB($C0);
  EmitB($0F); EmitB($84); EmitI32(loopTop - (CodeLen + 4));
end;

procedure ParseCaseStatement;
{ case expr of val1,val2: stmt; ... else stmt; end }
const MAX_BRANCHES = 256;
var
  jePositions : array[0..MAX_BRANCHES-1] of Integer;
  jeCount     : Integer;
  jmpPositions: array[0..MAX_BRANCHES-1] of Integer;
  jmpCount    : Integer;
  elseJmp, i, branchJeStart, si: Integer;
  hasElse     : Boolean;
  cv          : Int64;
  nextJmpPositions: array[0..MAX_BRANCHES-1] of Integer;
  nextJmpCount    : Integer;
begin
  { Save expression in rcx (rax gets clobbered by comparisons) }
  ParseExpr;
  EmitB($48); EmitB($89); EmitB($C1);  { mov rcx, rax }

  Expect(tkOf, 'of');
  jeCount  := 0;
  jmpCount := 0;
  hasElse  := False;
  nextJmpCount := 0;

  while (not (CurTok.Kind in [tkEnd, tkEOF])) and not hasElse do
  begin
    if CurTok.Kind = tkElse then
    begin
      hasElse := True;
      Next;
      { Patch the last branch's jump-to-next to point here }
      if nextJmpCount > 0 then
      begin
        Patch32(nextJmpPositions[nextJmpCount-1], CodeLen - (nextJmpPositions[nextJmpCount-1] + 4));
        Dec(nextJmpCount);
      end;
      ParseStatement;
      Eat(tkSemicolon);
    end
    else
    begin
      { Patch the previous branch's jump-to-next to point here }
      if nextJmpCount > 0 then
      begin
        Patch32(nextJmpPositions[nextJmpCount-1], CodeLen - (nextJmpPositions[nextJmpCount-1] + 4));
        Dec(nextJmpCount);
      end;

      { Collect label values and emit comparisons }
      branchJeStart := jeCount;
      repeat
        { Parse label value }
        if CurTok.Kind = tkInteger then cv := CurTok.IVal
        else if CurTok.Kind = tkString then
        begin
          if Length(CurTok.SVal) = 0 then Error('case string label must not be empty');
          cv := Ord(CurTok.SVal[1]);
        end
        else if CurTok.Kind = tkIdent then
        begin
          si := FindSym(CurTok.SVal);
          if (si >= 0) and (Syms[si].Kind = skConst) then cv := Syms[si].ConstVal
          else Error('case label must be constant');
        end
        else Error('expected case label');
        Next;
        { cmp rcx, imm32; je (forward) }
        EmitB($48); EmitB($81); EmitB($F9); EmitI32(cv); { cmp rcx, imm32 }
        EmitB($0F); EmitB($84);
        if jeCount >= MAX_BRANCHES then Error('too many case branches');
        jePositions[jeCount] := CodeLen; Inc(jeCount);
        EmitI32(0);
      until not Eat(tkComma);
      Expect(tkColon, ':');

      { Emit jump to next comparison (if none of this branch's labels match) }
      EmitB($E9);
      if nextJmpCount >= MAX_BRANCHES then Error('too many case branches');
      nextJmpPositions[nextJmpCount] := CodeLen; Inc(nextJmpCount);
      EmitI32(0);

      { This branch's code starts here: patch all its je targets }
      for i := branchJeStart to jeCount-1 do
        Patch32(jePositions[i], CodeLen - (jePositions[i] + 4));

      ParseStatement;
      Eat(tkSemicolon);

      { jmp end_case }
      EmitB($E9);
      if jmpCount >= MAX_BRANCHES then Error('too many case branches');
      jmpPositions[jmpCount] := CodeLen; Inc(jmpCount);
      EmitI32(0);
    end;
  end;

  Expect(tkEnd, 'end');

  { If there was no else, the last branch's jump-to-next jumps here (end of case) }
  if nextJmpCount > 0 then
  begin
    Patch32(nextJmpPositions[nextJmpCount-1], CodeLen - (nextJmpPositions[nextJmpCount-1] + 4));
    Dec(nextJmpCount);
  end;

  { Patch all jmp end_case to here }
  for i := 0 to jmpCount-1 do
    Patch32(jmpPositions[i], CodeLen - (jmpPositions[i] + 4));
end;

procedure ParseBlock;
begin
  while not (CurTok.Kind in [tkEnd, tkEOF, tkUntil]) do
    begin ParseStatement; Eat(tkSemicolon); end;
end;

procedure ParseStatement;
var name: AnsiString; idx, pi, i, si, si2: Integer;
begin
  case CurTok.Kind of
    tkwriteln: begin Next; ParsewriteArgs(True);  end;
    tkwrite:   begin Next; ParsewriteArgs(False); end;

    tkHalt, tkExit:
    begin
      Next;
	    if CurTok.Kind = tkLParen then
	    begin
	      Next;
	      ParseExpr;
	      EmitB($48); EmitB($89); EmitB($C7);   { mov rdi, rax }
	      MovRaxImm(SYS_EXIT);
	      EmitSyscall;
	      Expect(tkRParen, ')');
	    end
      else if CurTok.Kind = tkSemicolon then
      begin
        { exit from function: emit epilogue }
        if CurProc >= 0 then EmitProcEpilog(Procs[CurProc].RetSymIdx)
        else EmitExit(0);
      end
      else EmitExit(0);
    end;

    tkInc, tkDec:
    begin
      if CurTok.Kind = tkInc then name := 'inc' else name := 'dec';
      Next;
      Expect(tkLParen, '(');
      if CurTok.Kind <> tkIdent then Error('expected variable');
      idx := FindSym(CurTok.SVal);
      if idx < 0 then Error('undefined');
      Next;
      EmitLoadVar(idx);
      if Eat(tkComma) then
      begin
        EmitB($50); ParseExpr;
        EmitB($48); EmitB($89); EmitB($C1); EmitB($58);
        if name = 'inc' then begin EmitB($48); EmitB($01); EmitB($C8); end
        else begin EmitB($48); EmitB($29); EmitB($C8); end;
      end
      else
      begin
        if name = 'inc' then begin EmitB($48); EmitB($FF); EmitB($C0); end
        else begin EmitB($48); EmitB($FF); EmitB($C8); end;
      end;
      EmitStoreVar(idx);
      Expect(tkRParen, ')');
    end;

    { ---- File I/O and argv builtins ---- }
    tkSyswrite:
    begin
      { syswrite(fd, buf_array, n) as statement — discard return value }
      Next; Expect(tkLParen, '(');
      ParseExpr; EmitB($48); EmitB($89); EmitB($C7);     { mov rdi, rax (fd) }
      Expect(tkComma, ',');
      if CurTok.Kind <> tkIdent then Error('Syswrite: expected array var');
      idx := FindSym(CurTok.SVal);
      if (idx < 0) or not Syms[idx].IsArray then Error('Syswrite: not an array var');
      EmitB($48); EmitB($8D); EmitB($34); EmitB($25); EmitGlobRef(Syms[idx].Offset);
      Next; Expect(tkComma, ',');
      ParseExpr; EmitB($48); EmitB($89); EmitB($C2);     { mov rdx, rax (count) }
      MovRaxImm(1); EmitSyscall;
      Expect(tkRParen, ')');
    end;
    tkSysClose:
    begin
      { SysClose(fd) }
      Next; Expect(tkLParen, '(');
      ParseExpr;  { fd → rax }
      EmitB($48); EmitB($89); EmitB($C7);   { mov rdi, rax }
	      MovRaxImm(SYS_CLOSE); EmitSyscall;
      Expect(tkRParen, ')');
    end;
    tkSysFchmod:
    begin
      { SysFchmod(fd, mode): SYS_FCHMOD=91 }
      Next; Expect(tkLParen, '(');
      ParseExpr; EmitB($48); EmitB($89); EmitB($C7);   { mov rdi, rax (fd) }
      Expect(tkComma, ',');
      ParseExpr; EmitB($48); EmitB($89); EmitB($C6);   { mov rsi, rax (mode) }
      MovRaxImm(91); EmitSyscall;
      Expect(tkRParen, ')');
    end;
    tkArgStr:
    begin
      { ArgStr(n, s): copy argv[n] bytes into string var s (global) }
      Next; Expect(tkLParen, '(');
      ParseExpr;  { n → rax }
      Expect(tkComma, ',');
      if CurTok.Kind <> tkIdent then Error('ArgStr: expected string var');
      idx := FindSym(CurTok.SVal);
      if (idx < 0) or (Syms[idx].TypeKind <> tyString) then Error('ArgStr: not a string var');
      EmitArgvToString(idx);
      Next;
      Expect(tkRParen, ')');
    end;

    tkIf:     begin Next; ParseIfStatement;    end;
    tkWhile:  begin Next; ParseWhileStatement; end;
    tkFor:    begin Next; ParseForStatement;   end;
    tkRepeat: begin Next; ParseRepeatStatement; end;
    tkCase:   begin Next; ParseCaseStatement;  end;

    tkBegin:  begin Next; ParseBlock; Expect(tkEnd, 'end'); end;

	  tkIdent:
	  begin
	    name := CurTok.SVal;

      if (name = 'LoadFile') or (name = 'loadfile') then
      begin
        Next;
        Expect(tkLParen, '(');
        if CurTok.Kind <> tkIdent then Error('LoadFile: expected path');
        idx := FindSym(CurTok.SVal);
        if (idx < 0) or (Syms[idx].TypeKind <> tyString) then Error('LoadFile: path must be string');
        Next;
        Expect(tkComma, ',');
        if CurTok.Kind <> tkIdent then Error('LoadFile: expected destination');
        si := FindSym(CurTok.SVal);
        if (si < 0) or (Syms[si].TypeKind <> tyString) then Error('LoadFile: destination must be string');
        Next;
        Expect(tkRParen, ')');
        EmitLoadFile(idx, si);
        Exit;
      end;

      if (name = 'SetLength') or (name = 'setlength') then
      begin
        Next;
        Expect(tkLParen, '(');
        if CurTok.Kind <> tkIdent then Error('SetLength: expected string variable');
        idx := FindSym(CurTok.SVal);
        if (idx < 0) or (Syms[idx].TypeKind <> tyString) then Error('SetLength: not a string var');
        Next;
        Expect(tkComma, ',');
        ParseExpr; { new length -> rax }
        EmitStoreStrLen(idx);
        Expect(tkRParen, ')');
        Exit;
      end;

	      { Function return value: FuncName := expr }
      if (CurProc >= 0) and Procs[CurProc].IsFunc and
         (name = Procs[CurProc].Name) then
      begin
        Next; Expect(tkAssign, ':=');
        ParseExpr;
        EmitStoreVar(Procs[CurProc].RetSymIdx);
        Exit;
      end;

      { Procedure call }
      pi := FindProc(name);
      if pi >= 0 then
      begin
        Next;
        if CurTok.Kind = tkLParen then
        begin
          Next;
          for i := 0 to Procs[pi].ParamCount-1 do
          begin
            ParseExpr; EmitB($50);
            if i < Procs[pi].ParamCount-1 then Expect(tkComma, ',');
          end;
          Expect(tkRParen, ')');
        end;
        for i := Procs[pi].ParamCount-1 downto 0 do
          case i of
            0: EmitB($5F);
            1: EmitB($5E);
            2: EmitB($5A);
            3: EmitB($59);
            4: begin EmitB($41); EmitB($58); end;
            5: begin EmitB($41); EmitB($59); end;
          end;
        EmitCallProc(pi);
        Exit;
      end;

      { Variable assignment }
      ParseLValue(name);
    end;

    tkSemicolon, tkEnd, tkElse, tkUntil, tkEOF: ;
    else
      while not (CurTok.Kind in [tkSemicolon,tkEnd,tkElse,tkUntil,tkEOF]) do Next;
  end;
end;

{ ===== Declaration parsing ===== }

function ParseTypeKind: TTypeKind;
var lo: AnsiString;
begin
  LastTypeRecId := REC_NONE;
  case CurTok.Kind of
    tkInteger_T:
    begin
      if (CurTok.SVal = 'byte') or (CurTok.SVal = 'Byte') then
        Result := tyChar
      else
        Result := tyInteger;
    end;
    tkLongWord_T: Result := tyInteger;
    tkBoolean_T: Result := tyBoolean;
    tkChar_T:    Result := tyChar;
    tkString_T:  Result := tyString;
    else
    begin
      lo := CurTok.SVal;
      if (lo = 'ansistring') or (lo = 'AnsiString') then Result := tyString
      else if (lo = 'byte') or (lo = 'Byte') then Result := tyChar
      else
      begin
        LastTypeRecId := IsRecordType(lo);
        if LastTypeRecId <> REC_NONE then
          Result := tyRecord
        else
          Result := tyInteger;
      end;
    end;
  end;
  Next;
end;

procedure ParseVarSection;
var names: array[0..63] of AnsiString; n, i, idx: Integer; tk: TTypeKind;
    isArr: Boolean; arrLo, arrHi: Integer; elemTk: TTypeKind;
begin
  Next;
  while CurTok.Kind = tkIdent do
  begin
    n := 0;
    repeat
      names[n] := CurTok.SVal; Inc(n); Next;
    until not Eat(tkComma);
    Expect(tkColon, ':');
    isArr := False; arrLo := 0; arrHi := 0; elemTk := tyInteger;
    if CurTok.Kind = tkArray then
    begin
      isArr := True; Next;
      if CurTok.Kind = tkLBrack then
      begin
        Next;
        arrLo := ConstEval;
        Expect(tkDotDot, '..');
        arrHi := ConstEval;
        Expect(tkRBrack, ']');
      end;
      Expect(tkOf, 'of');
      elemTk := ParseTypeKind;
      tk := elemTk;
    end
    else
    begin
      { Skip qualifiers like pointer, ^, etc. }
      while not (CurTok.Kind in [tkSemicolon, tkBegin, tkVar, tkConst, tkType,
                 tkProcedure, tkFunction, tkEOF]) do
      begin
        tk := ParseTypeKind;
      end;
    end;
	    if isArr then
	      for i := 0 to n-1 do
	      begin
	        idx := AllocArray(names[i], elemTk, arrLo, arrHi);
	        if elemTk = tyRecord then
	          Syms[idx].ElemRecName := LastTypeRecId;
	      end
	    else
	      for i := 0 to n-1 do
	      begin
	        idx := AllocVar(names[i], tk);
	        if tk = tyRecord then
	          Syms[idx].RecName := LastTypeRecId;
	      end;
	    if Eat(tkEq) then
	    begin
	      while not (CurTok.Kind in [tkSemicolon, tkEOF]) do Next;
	    end;
	    Eat(tkSemicolon);
	  end;
	end;

procedure ParseConstSection;
var name: AnsiString; v: Int64;
begin
  Next;
  while CurTok.Kind = tkIdent do
  begin
    name := CurTok.SVal; Next;
    Expect(tkEq, '=');
    v := ConstEval;
    AddConst(name, tyInteger, v);
    Eat(tkSemicolon);
  end;
end;

procedure ParseTypeSection;
{ Handles enum types: type TFoo = (a, b, c); }
var ordinal: Int64; tname: AnsiString; depth: Integer; done: Boolean;
begin
  Next;
  while CurTok.Kind = tkIdent do
  begin
    tname := CurTok.SVal; Next;
    Expect(tkEq, '=');
    if CurTok.Kind = tkLParen then
    begin
      Next; ordinal := 0;
      done := False;
      while (CurTok.Kind = tkIdent) and not done do
      begin
        AddConst(CurTok.SVal, tyInteger, ordinal);
        Inc(ordinal); Next;
        if not Eat(tkComma) then done := True;
      end;
      Expect(tkRParen, ')');
    end
    else if CurTok.Kind = tkRecord then
    begin
      depth := 1;
      Next;
      while (depth > 0) and (CurTok.Kind <> tkEOF) do
      begin
        if CurTok.Kind = tkRecord then Inc(depth)
        else if CurTok.Kind = tkEnd then Dec(depth);
        Next;
      end;
    end
    else
    begin
      { Skip non-enum type defs }
      while not (CurTok.Kind in [tkSemicolon,tkEOF]) do Next;
    end;
    Eat(tkSemicolon);
  end;
end;

{ ===== Procedure/function parser ===== }

procedure ParseSubroutine;
var
  isFunc   : Boolean;
  name     : AnsiString;
  retType  : TTypeKind;
  tk       : TTypeKind;
  pnames   : array[0..7] of AnsiString;
  ptypes   : array[0..7] of TTypeKind;
  parr     : array[0..7] of Boolean;
  nparams  : Integer;
  pi, i    : Integer;
  savedSC, savedFS, savedCurProc : Integer;
  patchPos : Integer;
  depth    : Integer;
  doneArgs, doneParam, isArr: Boolean;
  startIdx, idx: Integer;
  tokKindOrd: Integer;
begin
  isFunc := CurTok.Kind = tkFunction;
  Next;
  if CurTok.Kind <> tkIdent then Error('expected name');
  name := CurTok.SVal; Next;

  nparams := 0; retType := tyInteger;

  if CurTok.Kind = tkLParen then
  begin
    Next;
    doneArgs := False;
    while (CurTok.Kind <> tkRParen) and not doneArgs do
    begin
      if CurTok.Kind in [tkVar, tkConst] then Next;
      startIdx := nparams;
      doneParam := False;
      while (CurTok.Kind = tkIdent) and not doneParam do
      begin
        pnames[nparams] := CurTok.SVal; Inc(nparams); Next;
        if not Eat(tkComma) then doneParam := True;
        if CurTok.Kind = tkColon then doneParam := True;
      end;
      Expect(tkColon, ':');
      isArr := False;
      tokKindOrd := Ord(CurTok.Kind);
      if VERBOSE then writeln('After colon, CurTok.Kind = ', tokKindOrd, ', CurTok.SVal = ', CurTok.SVal);
      if CurTok.Kind = tkArray then
      begin
        Next;
        Expect(tkOf, 'of');
        tk := ParseTypeKind;
        isArr := True;
      end
      else
        tk := ParseTypeKind;
      for i := startIdx to nparams-1 do
      begin
        ptypes[i] := tk;
        parr[i] := isArr;
      end;
      if not Eat(tkSemicolon) then doneArgs := True;
    end;
    Expect(tkRParen, ')');
  end;

  if isFunc then
  begin
    Expect(tkColon, ':');
    retType := ParseTypeKind;
  end;

  Eat(tkSemicolon);
  while (CurTok.Kind = tkIdent) and ((CurTok.SVal = 'inline') or (CurTok.SVal = 'Inline')) do
  begin
    Next;
    Eat(tkSemicolon);
  end;

  if (name = 'LoadFile') or (name = 'loadfile') then
  begin
    while not (CurTok.Kind in [tkBegin, tkEOF]) do Next;
    if CurTok.Kind = tkBegin then
    begin
      depth := 1;
      Next;
      while (depth > 0) and (CurTok.Kind <> tkEOF) do
      begin
        if CurTok.Kind = tkBegin then Inc(depth)
        else if CurTok.Kind = tkEnd then Dec(depth);
        Next;
      end;
      Eat(tkSemicolon);
    end;
    Exit;
  end;

  { Forward declaration? }
  if CurTok.Kind = tkForward then
  begin
    Next; Eat(tkSemicolon);
    if FindProc(name) < 0 then
      RegisterProc(name, isFunc, retType, nparams, pnames, ptypes, -1);
    Exit;
  end;

  { Register or resolve }
  pi := FindProc(name);
  if pi < 0 then
    pi := RegisterProc(name, isFunc, retType, nparams, pnames, ptypes, CodeLen)
  else
    Procs[pi].BodyAddr := CodeLen;

  { Save scope }
  savedSC := SymCount;
  savedFS := FrameSize;
  FrameSize := 0;
  CurProc := pi;
  Procs[pi].ScopeBase := SymCount;

  { Allocate param slots }
  for i := 0 to nparams-1 do
  begin
    idx := AllocVar(pnames[i], ptypes[i]);
    Procs[pi].Params[i].SymIdx := idx;
    Syms[idx].Kind := skParam;
    if parr[i] then
    begin
      Syms[idx].IsArray := True;
      Syms[idx].ArrLen := 1000;
      Syms[idx].ElemType := ptypes[i];
    end;
  end;

  { Return value slot }
  if isFunc then
  begin
    if retType = tyString then
    begin
      savedCurProc := CurProc;
      CurProc := -1;
      AllocVar('Result', retType);
      CurProc := savedCurProc;
      Procs[pi].RetSymIdx := SymCount - 1;
      Syms[SymCount-1].Kind := skGlobal;
    end
    else
    begin
      AllocVar('Result', retType);
      Procs[pi].RetSymIdx := SymCount - 1;
      Syms[SymCount-1].Kind := skLocal;
    end;
  end;

  { Prologue }
  patchPos := EmitProcPrologue;
  Procs[pi].FramePatch := patchPos;

  { Copy params from registers to stack: mov [rbp+off], rdi/rsi/rdx/rcx/r8/r9 }
  for i := 0 to nparams-1 do
  begin
    if i < 4 then
    begin
      EmitB($48); EmitB($89);
      case i of
        0: EmitB($BD);   { rdi }
        1: EmitB($B5);   { rsi }
        2: EmitB($95);   { rdx }
        3: EmitB($8D);   { rcx }
      end;
      EmitI32(Syms[Procs[pi].Params[i].SymIdx].Offset);
    end
    else if i = 4 then
    begin
      EmitB($4C); EmitB($89); EmitB($85);
      EmitI32(Syms[Procs[pi].Params[i].SymIdx].Offset);
    end
    else if i = 5 then
    begin
      EmitB($4C); EmitB($89); EmitB($8D);
      EmitI32(Syms[Procs[pi].Params[i].SymIdx].Offset);
    end;
  end;

  { Optional var section }
  while CurTok.Kind in [tkVar, tkConst, tkType] do
    case CurTok.Kind of
      tkVar:   ParseVarSection;
      tkConst: ParseConstSection;
      tkType:  ParseTypeSection;
    end;

  { Body }
  Expect(tkBegin, 'begin');
  ParseBlock;
  Expect(tkEnd, 'end');
  Eat(tkSemicolon);

  { Epilogue }
  EmitProcEpilog(Procs[pi].RetSymIdx);

  { Patch frame size }
  PatchProcPrologue(patchPos, FrameSize);

  { Restore scope }
  SymCount  := savedSC;
  FrameSize := savedFS;
  CurProc   := -1;
end;

{ ===== Program ===== }

procedure ParseProgram;
var jmpPatch: Integer; doneUses: Boolean;
begin
  Expect(tkProgram, 'program');
  if CurTok.Kind = tkEOF then Error('expected program name');
  Next;  { program name can be any identifier (even keyword) }
  if CurTok.Kind = tkLParen then
    begin Next; while CurTok.Kind <> tkRParen do Next; Next; end;
  Eat(tkSemicolon);

  { Reserve BSS[0..7] for initial rsp (argv access) }
  BSS_INITIAL_RSP := BSSSize; Inc(BSSSize, 8);

  { Emit entry stub: save rsp then jmp to main body }
  { mov [bss_initial_rsp], rsp: 48 89 24 25 <GlobRef(0)> }
  EmitB($48); EmitB($89); EmitB($24); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
  EmitB($E9); jmpPatch := CodeLen; EmitI32(0);

  while CurTok.Kind in
    [tkUses, tkVar, tkConst, tkType, tkProcedure, tkFunction] do
    case CurTok.Kind of
      tkUses:
      begin
        Next;
        doneUses := False;
        while (CurTok.Kind = tkIdent) and not doneUses do
        begin
          Next;
          if not Eat(tkComma) then doneUses := True;
        end;
        Eat(tkSemicolon);
      end;
      tkVar:      ParseVarSection;
      tkConst:    ParseConstSection;
      tkType:     ParseTypeSection;
      tkProcedure,
      tkFunction: ParseSubroutine;
    end;

  { Patch jmp to point here (start of main body) }
  Patch32(jmpPatch, CodeLen - (jmpPatch + 4));

  Expect(tkBegin, 'begin');
  ParseBlock;
  Expect(tkEnd, 'end');
  Eat(tkDot);

  EmitExit(0);
  ApplyCallFixups;
end;
