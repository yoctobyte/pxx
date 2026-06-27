{ ===== C Parser ===== }

function ParseCBlockAST: Integer; forward;
function ParseCStatementAST: Integer; forward;
procedure SkipBraceBlock; forward;
procedure ParseCSubroutine; forward;
function ParseCExpr: Integer; forward;
function ParseCCommaExpr: Integer; forward;
function CEvalConstExpr: Int64; forward;
procedure ParseCTypedef; forward;
procedure ParseCEnumDecl; forward;
procedure ParseCStructDecl; forward;
function IsBareStructDecl: Boolean; forward;
function IsCTypeTok: Boolean; forward;
function ParseCDeclType: TTypeKind; forward;
function ParseCCommaStmt: Integer; forward;
function ParseCCommaExpr: Integer; forward;
function ParseCSwitchAST: Integer; forward;
function CNodeIsPointer(node: Integer): Boolean; forward;
{ CNodeDecaysToPointer forward moved to forwards.inc (must sit above ir.inc:901,
  which calls it; this spot is below that use — too late for the FPC seed). }
function CNodePtrElemRec(node: Integer): Integer; forward;
procedure ParseCStructInto(ci: Integer; isUnion: Boolean); forward;

{ ===== C expression compiler (Slice B) =====
  A real recursive-descent C expression parser at C precedence, replacing the
  earlier Pascal-ParseExpr borrow. Emits the shared AST nodes (AN_BINOP, AN_NEG,
  AN_NOT, AN_INT_LIT, AN_IDENT, AN_CALL, AN_ASSIGN, AN_STR_LIT) so the existing
  IR lowering and all backends apply unchanged.

  Operator-token mapping into AN_BINOP.IVal: the IR's binop validator accepts
  ops with ordinal <= Ord(tkShl) plus tkXor, and encodes shift-right as the
  *tkIdent* operator (shift-left = tkShl). So the distinct C lexer tokens from
  Slice A are translated here to the operator tokens the IR understands:
    C `&`(tkAmp)->tkAnd bitwise, `|`(tkPipe)->tkOr bitwise, `^`->tkXor,
    `<<`->tkShl, `>>`->tkIdent(shr), `/`->tkDiv (integer division),
    `&&`->tkAnd / `||`->tkOr but tagged tyBoolean for the short-circuit path. }

{ Result type of a binary node: comparisons/logical -> Boolean; otherwise widen
  to Int64 if either operand is Int64, else Integer. }
function CBinResultTk(opTok, l, r: Integer): Integer;
begin
  if (opTok = Ord(tkEq)) or (opTok = Ord(tkNeq)) or (opTok = Ord(tkLt)) or
     (opTok = Ord(tkLe)) or (opTok = Ord(tkGt)) or (opTok = Ord(tkGe)) or
     (opTok = Ord(tkAnd)) or (opTok = Ord(tkOr)) then
    Result := Ord(tyBoolean)
  else if TypeIsFloat(IntToTypeKind(ASTTk[l])) or TypeIsFloat(IntToTypeKind(ASTTk[r])) then
  begin
    { Float arithmetic (`d+1`, `a*b`, …): the result is float, NOT integer —
      otherwise the BINOP was tagged tyInteger and the backend INTEGER-added the
      two IEEE bit patterns, producing a garbage near-infinity double. Promote to
      the wider operand type (Extended > Double > Single). }
    if (IntToTypeKind(ASTTk[l]) = tyExtended) or (IntToTypeKind(ASTTk[r]) = tyExtended) then
      Result := Ord(tyExtended)
    else if (IntToTypeKind(ASTTk[l]) = tyDouble) or (IntToTypeKind(ASTTk[r]) = tyDouble) then
      Result := Ord(tyDouble)
    else
      Result := Ord(tySingle);
  end
  { Integer usual-arithmetic-conversion result, preserving SIGNEDNESS so the IR
    lowering picks signed vs unsigned compares/division/shifts correctly. C
    promotes unsigned char/short to signed int, so only unsigned int (tyUInt32)
    and unsigned long/long-long (tyUInt64) keep an unsigned result. Rank order:
    unsigned 64 > signed 64 > unsigned 32 > signed 32. Without this an inline
    `i - 1u` (unsigned) was tagged signed, so `(i - 1u) < asize` compiled to a
    SIGNED compare (lua `findindex` looped forever in `pairs`). }
  else if (IntToTypeKind(ASTTk[l]) = tyUInt64) or (IntToTypeKind(ASTTk[r]) = tyUInt64) then
    Result := Ord(tyUInt64)
  else if (IntToTypeKind(ASTTk[l]) = tyInt64) or (IntToTypeKind(ASTTk[r]) = tyInt64) then
    Result := Ord(tyInt64)
  else if (IntToTypeKind(ASTTk[l]) = tyUInt32) or (IntToTypeKind(ASTTk[r]) = tyUInt32) or
          (IntToTypeKind(ASTTk[l]) = tyNativeUInt) or (IntToTypeKind(ASTTk[r]) = tyNativeUInt) then
    Result := Ord(tyUInt32)
  else
    Result := Ord(tyInteger);
end;

function CIntegerPromoteTk(tk: TTypeKind): TTypeKind;
begin
  Result := tk;
  if TypeIsOrdinal(tk) and (TypeSize(tk) < TypeSize(tyInteger)) then
    Result := tyInteger;
end;

function CTernaryResultTk(thenE, elseE: Integer): Integer;
var tTk, eTk: TTypeKind;
begin
  tTk := IntToTypeKind(ASTTk[thenE]);
  eTk := IntToTypeKind(ASTTk[elseE]);
  if TypeIsFloat(tTk) or TypeIsFloat(eTk) then
  begin
    if (tTk = tyExtended) or (eTk = tyExtended) then Result := Ord(tyExtended)
    else if (tTk = tyDouble) or (eTk = tyDouble) then Result := Ord(tyDouble)
    else Result := Ord(tySingle);
  end
  else if TypeIsOrdinal(tTk) and TypeIsOrdinal(eTk) then
  begin
    tTk := CIntegerPromoteTk(tTk);
    eTk := CIntegerPromoteTk(eTk);
    if tTk = eTk then Result := Ord(tTk)
    else if (tTk = tyUInt64) or (eTk = tyUInt64) then Result := Ord(tyUInt64)
    else if (tTk = tyInt64) or (eTk = tyInt64) then Result := Ord(tyInt64)
    else Result := Ord(tyInteger);
  end
  else
    Result := ASTTk[thenE];
end;

{ Build an AN_BINOP from a C operator token and two operand nodes. cTok is the
  raw C lexer token kind (CurTok.Kind ordinal). }
{ Wrap an expression in `(e != 0)` so a logical operand becomes a true 0/1
  boolean. C `&&`/`||` must yield exactly 0/1, and the short-circuit IR stores
  the operand value into a 1-byte boolean temp — a raw `2` would read back as 2.
  Normalising both operands here keeps the result canonical. }
function CMakeTruthy(e: Integer): Integer;
var node, zero: Integer;
begin
  zero := AllocNode(AN_INT_LIT);
  ASTIVal[zero] := 0;
  ASTTk[zero] := Ord(tyInteger);
  node := AllocNode(AN_BINOP);
  ASTIVal[node] := Ord(tkNeq);
  ASTLeft[node] := e;
  ASTRight[node] := zero;
  ASTTk[node] := Ord(tyBoolean);
  Result := node;
end;

function CMakeBinop(cTok, l, r: Integer): Integer;
var node, ivalOp: Integer;
begin
  ivalOp := cTok;
  if cTok = Ord(tkSlash) then
  begin
    { C `/` is integer division on ints (-> tkDiv) but REAL division on floats.
      The backend's float arithmetic path keys on tkSlash (divsd); keep tkSlash
      when either operand is float, else `0.5/scale` integer-divided the IEEE bit
      patterns into garbage. }
    if TypeIsFloat(IntToTypeKind(ASTTk[l])) or TypeIsFloat(IntToTypeKind(ASTTk[r])) then
      ivalOp := Ord(tkSlash)
    else
      ivalOp := Ord(tkDiv);
  end
  else if cTok = Ord(tkShr) then ivalOp := Ord(tkIdent)   { shr encoded as tkIdent }
  else if cTok = Ord(tkAmp) then ivalOp := Ord(tkAnd)     { bitwise AND }
  else if cTok = Ord(tkPipe) then ivalOp := Ord(tkOr);    { bitwise OR }
  { tkPlus/tkMinus/tkStar/tkMod/tkShl/tkXor/tkAnd(&&)/tkOr(||)/comparisons map
    straight through. }
  if (cTok = Ord(tkAnd)) or (cTok = Ord(tkOr)) then       { logical && / || }
  begin
    l := CMakeTruthy(l);
    r := CMakeTruthy(r);
  end;
  node := AllocNode(AN_BINOP);
  ASTIVal[node] := ivalOp;
  ASTLeft[node] := l;
  ASTRight[node] := r;
  ASTTk[node] := CBinResultTk(cTok, l, r);
  { Pointer arithmetic `ptr +/- int` (or `int + ptr`) stays a pointer, carrying
    the element record on ASTSOffset so `(p+i)->field` / `(p+i)[j]` resolve (the
    IR already scales the offset by element size). }
  if (cTok = Ord(tkPlus)) or (cTok = Ord(tkMinus)) then
  begin
    if CNodeDecaysToPointer(l) then
    begin ASTTk[node] := Ord(tyPointer); ASTSOffset[node] := CNodePtrElemRec(l); end
    else if (cTok = Ord(tkPlus)) and CNodeDecaysToPointer(r) then
    begin ASTTk[node] := Ord(tyPointer); ASTSOffset[node] := CNodePtrElemRec(r); end;
  end;
  Result := node;
end;

{ Binary-operator precedence (higher binds tighter); -1 = not a binary op.
  Note `&`=tkAmp(bitwise, 8) is distinct from `&&`=tkAnd(logical, 4), and
  `|`=tkPipe(bitwise, 6) from `||`=tkOr(logical, 3) since Slice A. }
function CBinPrec(k: TTokenKind): Integer;
begin
  case k of
    tkStar, tkSlash, tkMod:        Result := 11;
    tkPlus, tkMinus:               Result := 10;
    tkShl, tkShr:                  Result := 9;
    tkLt, tkLe, tkGt, tkGe:        Result := 8;
    tkEq, tkNeq:                   Result := 7;
    tkAmp:                         Result := 6;   { bitwise & }
    tkXor:                         Result := 5;   { bitwise ^ }
    tkPipe:                        Result := 4;   { bitwise | }
    tkAnd:                         Result := 3;   { logical && }
    tkOr:                          Result := 2;   { logical || }
    else                           Result := -1;
  end;
end;

function ParseCUnary: Integer; forward;
function ParseCPostfix: Integer; forward;

{ Build the shared-IR AN_INCDEC value node (master shape): Left = the lvalue
  (address computed once at lowering), ASTIVal = +1/-1 (the lowering scales by
  element size for a pointer), ASTSOffset = 1 for postfix (yield OLD value) / 0
  for prefix (yield NEW). The pointed-at record for `(p++)->field` is derived from
  the lvalue (Left) by CNodePtrElemRec, not carried on the node. }
function CMakeIncDec(lv: Integer; isInc, isPre: Boolean): Integer;
var node: Integer;
begin
  node := AllocNode(AN_INCDEC);
  ASTLeft[node] := lv;
  if isInc then ASTIVal[node] := 1 else ASTIVal[node] := -1;
  if isPre then ASTSOffset[node] := 0 else ASTSOffset[node] := 1;
  ASTTk[node] := ASTTk[lv];
  Result := node;
end;

{ Precedence-climbing binary-expression parser (left-associative). }
function ParseCBinExpr(minPrec: Integer): Integer;
var left, right, cTok, prec: Integer;
begin
  left := ParseCUnary;
  while True do
  begin
    prec := CBinPrec(CurTok.Kind);
    if prec < minPrec then Break;
    cTok := Ord(CurTok.Kind);
    Next;
    right := ParseCBinExpr(prec + 1);   { left-assoc: strictly-higher on the right }
    left := CMakeBinop(cTok, left, right);
  end;
  Result := left;
end;

{ The pointer to a va_list's control block, for the __pxx_va_* helpers. va_list
  is `__pxx_va_elem[1]`, so a LOCAL va_list is an array — take its address (&ap[0]).
  A va_list PARAMETER decayed to a pointer at the call site, so the identifier
  already IS the control-block pointer — pass it as-is. }
function CVaListAddr(apNode: Integer): Integer;
begin
  Result := AllocNode(AN_ADDR);
  ASTLeft[Result] := apNode;
  ASTIVal[Result] := ResolveNodeRec(apNode);
  ASTTk[Result] := Ord(tyPointer);
end;

{ A primary: integer/char/string literal, parenthesised expr, identifier
  (constant -> folded literal; variable -> AN_IDENT; name followed by `(` ->
  call with an AN_ARG chain). }
function ParseCPrimary: Integer;
var node, idx, procIdx, argHead, argTail, argNode, valNode, calleeNode: Integer;
    apNode, addrNode, callNode, helper, a2, a3, a4: Integer;
    vt: TTypeKind;
    name: AnsiString;
begin
  Result := -1;
  case CurTok.Kind of
    tkInteger:
    begin
      node := AllocNode(AN_INT_LIT);
      ASTIVal[node] := CurTok.IVal;
      if (CurTok.IVal > 2147483647) or (CurTok.IVal < -2147483648) then
        ASTTk[node] := Ord(tyInt64)
      else
        ASTTk[node] := Ord(tyInteger);
      Next;
      Result := node;
    end;
    tkFloat:
    begin
      { float literal — IVal carries the IEEE-754 double bit pattern (clexer) }
      node := AllocNode(AN_FLOAT_LIT);
      ASTIVal[node] := CurTok.IVal;
      ASTTk[node] := Ord(tyDouble);
      Next;
      Result := node;
    end;
    tkString:
    begin
      node := AllocNode(AN_STR_LIT);
      ASTSOffset[node] := Tokens[TokPos - 1].SOffset;
      ASTSLen[node] := Tokens[TokPos - 1].SLen;
      ASTTk[node] := Ord(tyString);
      Next;
      { Adjacent string literals concatenate (C: `"a" "b"` == `"ab"`; lua's
        `lua_pushliteral` expands to `"" s`). The decoded chars of consecutive
        string tokens are contiguous in TokChars, so just extend the length. }
      while CurTok.Kind = tkString do
      begin
        ASTSLen[node] := ASTSLen[node] + Tokens[TokPos - 1].SLen;
        Next;
      end;
      Result := node;
    end;
    tkLParen:
    begin
      Next;
      Result := ParseCExpr;
      { Parenthesized comma EXPRESSION `(a, b, c)` — evaluate each for side
        effects, yield the last. lua uses `((void)l, expr)` pervasively (api_check
        / lua_lock expand to it). Build left-nested AN_COMMA nodes. }
      while CurTok.Kind = tkComma do
      begin
        Next;
        valNode := ParseCExpr;
        node := AllocNode(AN_COMMA);
        ASTLeft[node] := Result;       { evaluated, discarded }
        ASTRight[node] := valNode;     { yields the value }
        ASTTk[node] := ASTTk[valNode];
        Result := node;
      end;
      Expect(tkRParen, ')');
    end;
    tkIdent:
    begin
      name := CurTok.SVal;
      Next;
      { varargs builtins, desugared over stdarg.h's va_list struct + the pure-C
        __pxx_va_* helpers (so the only special codegen is the variadic prologue). }
      if (name = '__builtin_va_arg') and (CurTok.Kind = tkLParen) then
      begin
        { __builtin_va_arg(ap, type) -> *(type*)__pxx_va_arg_{gp|fp}(&ap) }
        Next;
        apNode := ParseCExpr; Eat(tkComma);
        vt := ParseCDeclType;
        if CTypePtrDepth > 0 then vt := tyPointer;
        Expect(tkRParen, ')');
        addrNode := CVaListAddr(apNode);
        { SysV AMD64 variadic ABI: integer/pointer args arrive in the GP regs and
          floats in the XMM regs; the variadic prologue saves both classes into
          __va_save (GP at +0, XMM/FP at +48). va_arg(double) therefore reads the
          FP save area, va_arg(int/ptr) the GP area. (An earlier model pushed every
          arg through GP and read floats from gp too; that mismatched the actual
          SysV call+prologue and made %f/%g render 0 — bug-c-double-vararg.) }
        if TypeIsFloat(vt) then
          helper := FindProc('__pxx_va_arg_fp')
        else
          helper := FindProc('__pxx_va_arg_gp');
        argNode := AllocNode(AN_ARG); ASTLeft[argNode] := addrNode; ASTRight[argNode] := -1;
        callNode := AllocNode(AN_CALL); ASTIVal[callNode] := helper;
        ASTTk[callNode] := Ord(tyPointer); ASTLeft[callNode] := argNode;
        node := AllocNode(AN_DEREF); ASTLeft[node] := callNode; ASTTk[node] := Ord(vt);
        Result := node; Exit;
      end
      else if (name = '__builtin_va_start') and (CurTok.Kind = tkLParen) then
      begin
        { __builtin_va_start(ap, last) -> __pxx_va_start_impl(&ap, &__va_save, NGP, __va_overflow) }
        Next;
        apNode := ParseCExpr; Eat(tkComma);
        valNode := ParseCExpr;   { `last` named param — discarded }
        Expect(tkRParen, ')');
        addrNode := CVaListAddr(apNode);
        idx := FindSym('__va_save');
        a2 := AllocNode(AN_IDENT); ASTIVal[a2] := idx; ASTTk[a2] := Ord(tyRecord);
        node := AllocNode(AN_ADDR); ASTLeft[node] := a2; ASTTk[node] := Ord(tyPointer);
        a3 := AllocNode(AN_INT_LIT);
        if CurProc >= 0 then ASTIVal[a3] := ProcNamedGP[CurProc] else ASTIVal[a3] := 0;
        ASTTk[a3] := Ord(tyInteger);
        idx := FindSym('__va_overflow');
        a4 := AllocNode(AN_IDENT); ASTIVal[a4] := idx; ASTTk[a4] := Ord(tyPointer);
        helper := FindProc('__pxx_va_start_impl');
        argNode := AllocNode(AN_ARG); ASTLeft[argNode] := addrNode;
        calleeNode := AllocNode(AN_ARG); ASTLeft[calleeNode] := node; ASTRight[argNode] := calleeNode;
        valNode := AllocNode(AN_ARG); ASTLeft[valNode] := a3; ASTRight[calleeNode] := valNode;
        apNode := AllocNode(AN_ARG); ASTLeft[apNode] := a4; ASTRight[valNode] := apNode; ASTRight[apNode] := -1;
        callNode := AllocNode(AN_CALL); ASTIVal[callNode] := helper;
        ASTTk[callNode] := Ord(tyPointer); ASTLeft[callNode] := argNode;
        Result := callNode; Exit;
      end
      else if (name = '__builtin_va_end') and (CurTok.Kind = tkLParen) then
      begin
        Next; apNode := ParseCExpr; Expect(tkRParen, ')');
        node := AllocNode(AN_INT_LIT); ASTIVal[node] := 0; ASTTk[node] := Ord(tyInteger);
        Result := node; Exit;
      end;
      if CurTok.Kind = tkLParen then
      begin
        { call — direct (named function) or indirect (fn-pointer variable) }
        Next;
        argHead := -1; argTail := -1;
        if CurTok.Kind <> tkRParen then
        begin
          while True do
          begin
            valNode := ParseCExpr;
            argNode := AllocNode(AN_ARG);
            ASTLeft[argNode] := valNode;
            ASTRight[argNode] := -1;
            if argHead = -1 then argHead := argNode
            else ASTRight[argTail] := argNode;
            argTail := argNode;
            if CurTok.Kind = tkComma then begin Next; Continue; end;
            Break;
          end;
        end;
        Expect(tkRParen, ')');
        { gcc builtin `__builtin_expect(x, c)` is a branch-prediction hint that
          evaluates to its first argument — lua uses it pervasively via
          l_likely/l_unlikely. Reduce it to that argument's value. }
        if (name = '__builtin_expect') and (argHead >= 0) then
        begin
          Result := ASTLeft[argHead];
          Exit;
        end;
        procIdx := FindProc(name);
        if procIdx >= 0 then
        begin
          node := AllocNode(AN_CALL);
          ASTIVal[node] := procIdx;
          ASTTk[node] := Ord(Procs[procIdx].RetType);
          ASTLeft[node] := argHead;
        end
        else
        begin
          idx := FindSym(name);
          if (idx >= 0) and (SymProcSig[idx] >= 0) then
          begin
            { `f(args)` where f is a fn-pointer variable -> indirect call.
              ASTRight = the callee value (the variable), ASTIVal = the
              signature Procs[] index (marshalling + return type). }
            calleeNode := AllocNode(AN_IDENT);
            ASTIVal[calleeNode] := idx;
            ASTTk[calleeNode] := Ord(tyPointer);
            node := AllocNode(AN_CALL_IND);
            ASTLeft[node]  := argHead;
            ASTRight[node] := calleeNode;
            ASTIVal[node]  := SymProcSig[idx];
            ASTTk[node]    := Ord(Procs[SymProcSig[idx]].RetType);
            ASTSLen[node]  := 0;
          end
          else
            Error('call to undeclared function: ' + name);
        end;
        Result := node;
      end
      else
      begin
        idx := FindSym(name);
        if idx < 0 then
        begin
          { A bare function name decays to its address (a fn-pointer value),
            e.g. `BinOp f = add;`. Otherwise an unresolved identifier (a token
            left by a self-referential / unmodelled macro) degrades to a 0
            literal — best-effort frontend, matching the old skip leniency. }
          procIdx := FindProc(name);
          if procIdx >= 0 then
          begin
            node := AllocNode(AN_PROCADDR);
            ASTIVal[node] := procIdx;
            ASTTk[node] := Ord(tyPointer);
          end
          else
          begin
            node := AllocNode(AN_INT_LIT);
            ASTIVal[node] := 0;
            ASTTk[node] := Ord(tyInteger);
          end;
        end
        else if Syms[idx].Kind = skConst then
        begin
          node := AllocNode(AN_INT_LIT);
          ASTIVal[node] := Syms[idx].ConstVal;
          ASTTk[node] := Ord(Syms[idx].TypeKind);
        end
        else
        begin
          node := AllocNode(AN_IDENT);
          ASTIVal[node] := idx;
          ASTTk[node] := Ord(Syms[idx].TypeKind);
        end;
        Result := node;
      end;
    end;
    else
      Error('expected C expression');
  end;
end;

function CNodePtrDepth(node: Integer): Integer;
begin
  Result := 0;
  if node < 0 then Exit;
  if ASTKind[node] = AN_IDENT then
  begin
    if Syms[ASTIVal[node]].IsArray then
      Result := SymPtrDepth[ASTIVal[node]]
    else if Syms[ASTIVal[node]].TypeKind = tyPointer then
    begin
      Result := SymPtrDepth[ASTIVal[node]];
      if Result = 0 then Result := 1;
    end;
  end
  else if ASTKind[node] = AN_INDEX then
  begin
    if IntToTypeKind(ASTTk[node]) = tyPointer then
    begin
      if (ASTKind[ASTLeft[node]] = AN_IDENT) and Syms[ASTIVal[ASTLeft[node]]].IsArray then
        Result := SymPtrDepth[ASTIVal[ASTLeft[node]]]
      else
      begin
        Result := CNodePtrDepth(ASTLeft[node]) - 1;
        if Result < 1 then Result := 1;
      end;
    end;
  end
  else if ASTKind[node] = AN_DEREF then
  begin
    if IntToTypeKind(ASTTk[node]) = tyPointer then
    begin
      Result := CNodePtrDepth(ASTLeft[node]) - 1;
      if Result < 1 then Result := 1;
    end;
  end
  else if ASTKind[node] = AN_BINOP then
  begin
    if CNodeIsPointer(ASTLeft[node]) then Result := CNodePtrDepth(ASTLeft[node])
    else if CNodeIsPointer(ASTRight[node]) then Result := CNodePtrDepth(ASTRight[node]);
  end
  else if ASTKind[node] = AN_TERNARY then
  begin
    if (ASTRight[node] >= 0) and CNodeDecaysToPointer(ASTLeft[ASTRight[node]]) then
      Result := CNodePtrDepth(ASTLeft[ASTRight[node]])
    else if (ASTRight[node] >= 0) and CNodeDecaysToPointer(ASTRight[ASTRight[node]]) then
      Result := CNodePtrDepth(ASTRight[ASTRight[node]]);
  end
  else if ASTKind[node] = AN_INCDEC then
    Result := CNodePtrDepth(ASTLeft[node])
  else if ASTKind[node] = AN_ASSIGN then
    Result := CNodePtrDepth(ASTLeft[node]);
end;

function CNodePtrBaseTk(node: Integer): Integer;
var baseNode: Integer;
begin
  Result := Ord(tyUnknown);
  if node < 0 then Exit;
  if ASTKind[node] = AN_IDENT then
    Result := SymPtrBaseTk[ASTIVal[node]]
  else if ASTKind[node] = AN_INDEX then
  begin
    baseNode := ASTLeft[node];
    Result := CNodePtrBaseTk(baseNode);
  end
  else if ASTKind[node] = AN_DEREF then
    Result := CNodePtrBaseTk(ASTLeft[node])
  else if ASTKind[node] = AN_BINOP then
  begin
    if CNodeIsPointer(ASTLeft[node]) then Result := CNodePtrBaseTk(ASTLeft[node])
    else if CNodeIsPointer(ASTRight[node]) then Result := CNodePtrBaseTk(ASTRight[node]);
  end
  else if ASTKind[node] = AN_TERNARY then
  begin
    if (ASTRight[node] >= 0) and CNodeDecaysToPointer(ASTLeft[ASTRight[node]]) then
      Result := CNodePtrBaseTk(ASTLeft[ASTRight[node]])
    else if (ASTRight[node] >= 0) and CNodeDecaysToPointer(ASTRight[ASTRight[node]]) then
      Result := CNodePtrBaseTk(ASTRight[ASTRight[node]]);
  end
  else if ASTKind[node] = AN_INCDEC then
    Result := CNodePtrBaseTk(ASTLeft[node])
  else if ASTKind[node] = AN_ASSIGN then
    Result := CNodePtrBaseTk(ASTLeft[node]);
end;

{ Pointed-at / element TTypeKind ordinal of a pointer or array node, used to tag
  AN_DEREF / AN_INDEX results. Defaults to Integer for shapes not yet modelled. }
function CNodePointeeTk(node: Integer): Integer;
var recId, inner, depth, baseTk: Integer; fieldName: AnsiString;
begin
  Result := Ord(tyInteger);
  if node < 0 then Exit;
  if ASTKind[node] = AN_ADDR then
  begin
    { `*(&x)` — the deref of an address-of yields x's own type. Without this the
      pointee defaulted to tyInteger and a `*(&d) = expr` store of an 8-byte
      double (lua's `tonumber` macro: `*(n) = fltvalue(o)` with n = &local)
      truncated to a 4-byte store, dropping the high 32 bits of every float. }
    inner := ASTLeft[node];
    if inner < 0 then
      Result := Ord(tyInteger)
    else if (ASTKind[inner] = AN_IDENT) and not Syms[ASTIVal[inner]].IsArray then
      Result := Ord(Syms[ASTIVal[inner]].TypeKind)
    else if ASTKind[inner] = AN_FIELD then
    begin
      recId := ResolveNodeRec(ASTLeft[inner]);
      fieldName := GetASTIdentName(inner);
      if not RecFieldIsArray(recId, fieldName) then
        Result := Ord(RecFieldType(recId, fieldName))
      else
        Result := ASTTk[inner];
    end
    else
      Result := ASTTk[inner];
    Exit;
  end;
  if ASTKind[node] = AN_IDENT then
  begin
    if Syms[ASTIVal[node]].IsArray then
      Result := Ord(Syms[ASTIVal[node]].ElemType)
    else if Syms[ASTIVal[node]].TypeKind = tyPointer then
    begin
      depth := SymPtrDepth[ASTIVal[node]];
      if depth >= 2 then
        Result := Ord(tyPointer)
      else
        Result := Ord(Syms[ASTIVal[node]].PtrElemTk);
    end;
  end
  else if ASTKind[node] = AN_FIELD then
  begin
    recId := ResolveNodeRec(ASTLeft[node]);
    fieldName := GetASTIdentName(node);
    if RecFieldIsArray(recId, fieldName) then
      Result := Ord(RecFieldType(recId, fieldName))
    else if RecFieldType(recId, fieldName) = tyPointer then
      Result := Ord(RecFieldPtrElemTk(recId, fieldName));
  end
  else if ASTKind[node] = AN_CALL then
  begin
    if (ASTIVal[node] >= 0) and
       (Procs[ASTIVal[node]].RetType = tyPointer) then
      Result := ProcRetPtrElemTk[ASTIVal[node]];
  end
  else if ASTKind[node] = AN_PTR_CAST then
  begin
    { `*(T*)expr`: the cast carries the pointed-at type in its type-alias slot
      (castDepth>0 -> ASTIVal = alias idx, AliasElemTk = T). Without this the
      deref defaulted to tyInteger and a `*(long*)&d` / `*(double*)p` load read
      only 4 bytes — narrowing every 8-byte double moved through a pointer cast. }
    if (IntToTypeKind(ASTTk[node]) = tyPointer) and (ASTIVal[node] >= 0) then
      Result := AliasElemTk[ASTIVal[node]];
  end
  else if ASTKind[node] = AN_INDEX then
  begin
    if IntToTypeKind(ASTTk[node]) = tyPointer then
    begin
      depth := CNodePtrDepth(node);
      baseTk := CNodePtrBaseTk(node);
      if depth >= 2 then
        Result := Ord(tyPointer)
      else if baseTk <> Ord(tyUnknown) then
        Result := baseTk
      else if ASTKind[ASTLeft[node]] = AN_IDENT then
        Result := Ord(Syms[ASTIVal[ASTLeft[node]]].PtrElemTk)
      else
        Result := ASTTk[node];
    end
    else
      Result := ASTTk[node];
  end
  else if ASTKind[node] = AN_DEREF then
  begin
    if IntToTypeKind(ASTTk[node]) = tyPointer then
    begin
      depth := CNodePtrDepth(node);
      baseTk := CNodePtrBaseTk(node);
      if depth >= 2 then
        Result := Ord(tyPointer)
      else if baseTk <> Ord(tyUnknown) then
        Result := baseTk
      else
        Result := ASTTk[node];
    end
    else
      Result := ASTTk[node];
  end
  else if ASTKind[node] = AN_BINOP then
  begin
    if CNodeIsPointer(ASTLeft[node]) then
      Result := CNodePointeeTk(ASTLeft[node])
    else if CNodeIsPointer(ASTRight[node]) then
      Result := CNodePointeeTk(ASTRight[node]);
  end
  else if ASTKind[node] = AN_TERNARY then
  begin
    if (ASTRight[node] >= 0) and CNodeDecaysToPointer(ASTLeft[ASTRight[node]]) then
      Result := CNodePointeeTk(ASTLeft[ASTRight[node]])
    else if (ASTRight[node] >= 0) and CNodeDecaysToPointer(ASTRight[ASTRight[node]]) then
      Result := CNodePointeeTk(ASTRight[ASTRight[node]]);
  end
  else if ASTKind[node] = AN_INCDEC then
    Result := CNodePointeeTk(ASTLeft[node])
  else if ASTKind[node] = AN_ASSIGN then
    Result := CNodePointeeTk(ASTLeft[node]);
end;

{ True when a node denotes a pointer value, so `.`/`->` (both lex to tkDot in C)
  on it means C `->` (deref then field) rather than direct field access. }
function CNodeIsPointer(node: Integer): Boolean;
begin
  Result := False;
  if node < 0 then Exit;
  if ASTKind[node] = AN_IDENT then
    Result := (Syms[ASTIVal[node]].TypeKind = tyPointer) and not Syms[ASTIVal[node]].IsArray
  else if ASTKind[node] = AN_FIELD then
    Result := RecFieldType(ResolveNodeRec(ASTLeft[node]), GetASTIdentName(node)) = tyPointer
  else if ASTKind[node] = AN_INDEX then
    Result := IntToTypeKind(ASTTk[node]) = tyPointer
  else if ASTKind[node] = AN_DEREF then
    { `*p` where p is `T**`: the deref is itself a pointer value, so `(*p)->f`
      is a real C `->` (deref then field), not a `.` on an embedded record.
      ParseCUnary tags AN_DEREF with the pointee type (CNodePointeeTk). Without
      this, `(*p)->f` mis-lowered to a field of the slot holding `*p` (it read /
      addressed `p`'s own storage instead of `*p`'s target). }
    Result := IntToTypeKind(ASTTk[node]) = tyPointer
  else if (ASTKind[node] = AN_BINOP) or (ASTKind[node] = AN_INCDEC) then
    { pointer arithmetic / `p++` keeps a pointer type (CMakeBinop / CMakeIncDec) }
    Result := IntToTypeKind(ASTTk[node]) = tyPointer
  else if ASTKind[node] = AN_CALL then
    { a function returning a pointer — `f()->field` must deref the result }
    Result := IntToTypeKind(ASTTk[node]) = tyPointer
  else if ASTKind[node] = AN_TERNARY then
    Result := IntToTypeKind(ASTTk[node]) = tyPointer
  else if ASTKind[node] = AN_ADDR then
    Result := True
  else if ASTKind[node] = AN_ASSIGN then
    { `(p = x)->field`: the assignment yields the (pointer) LHS value }
    Result := CNodeIsPointer(ASTLeft[node]);
end;

function CNodeDecaysToPointer(node: Integer): Boolean;
var recId: Integer; fieldName: AnsiString;
begin
  Result := CNodeIsPointer(node);
  if Result or (node < 0) then Exit;
  if ASTKind[node] = AN_IDENT then
    Result := Syms[ASTIVal[node]].IsArray and (Syms[ASTIVal[node]].ArrLen <> -1)
  else if ASTKind[node] = AN_FIELD then
  begin
    recId := ResolveNodeRec(ASTLeft[node]);
    fieldName := GetASTIdentName(node);
    Result := RecFieldIsArray(recId, fieldName) and
              (RecFieldDynDepth(recId, fieldName) = 0);
  end;
end;

{ Pointed-at record id of a pointer-valued node, for `(p+i)->field` resolution.
  Pointer-arithmetic binops / `p++` carry it on ASTSOffset. }
function CNodePtrElemRec(node: Integer): Integer;
var baseNode, recId: Integer; fieldName: AnsiString;
begin
  Result := REC_NONE;
  if node < 0 then Exit;
  if ASTKind[node] = AN_IDENT then
  begin
    if Syms[ASTIVal[node]].IsArray then
      Result := Syms[ASTIVal[node]].ElemRecName
    else
      Result := Syms[ASTIVal[node]].PtrElemRec;
  end
  else if ASTKind[node] = AN_FIELD then
  begin
    recId := ResolveNodeRec(ASTLeft[node]);
    fieldName := GetASTIdentName(node);
    if RecFieldIsArray(recId, fieldName) then
      Result := ResolveNodeRec(node)
    else
      Result := RecFieldPtrElemRec(recId, fieldName);
  end
  else if ASTKind[node] = AN_ADDR then
  begin
    if ASTIVal[node] > 0 then
      Result := ASTIVal[node]
    else
      Result := ResolveNodeRec(ASTLeft[node]);
  end
  else if ASTKind[node] = AN_INDEX then
  begin
    baseNode := ASTLeft[node];
    if ASTKind[baseNode] = AN_IDENT then
      Result := Syms[ASTIVal[baseNode]].PtrElemRec
    else if ASTKind[baseNode] = AN_FIELD then
    begin
      recId := ResolveNodeRec(ASTLeft[baseNode]);
      fieldName := GetASTIdentName(baseNode);
      Result := RecFieldPtrElemRec(recId, fieldName);
    end;
  end
  else if ASTKind[node] = AN_BINOP then
    Result := ASTSOffset[node]      { pointer-arith binop carries the elem rec }
  else if ASTKind[node] = AN_TERNARY then
    Result := ASTSOffset[node]
  else if ASTKind[node] = AN_CALL then
  begin
    if (ASTIVal[node] >= 0) and
       (Procs[ASTIVal[node]].RetType = tyPointer) then
      Result := ProcRetPtrElemRec[ASTIVal[node]];
  end
  else if ASTKind[node] = AN_INCDEC then
    Result := CNodePtrElemRec(ASTLeft[node])   { `p++`: elem rec from the lvalue }
  else if ASTKind[node] = AN_DEREF then
    { `*p` where p is `T**`: *p is a `T*` whose pointed-at record is the same
      base record recorded on p. Needed so `(*p)->field` resolves non-zero field
      offsets (without it the record was unknown and every field landed at 0). }
    Result := CNodePtrElemRec(ASTLeft[node])
  else if ASTKind[node] = AN_ASSIGN then
    Result := CNodePtrElemRec(ASTLeft[node]);
end;

{ Size in bytes of the type just consumed by ParseCDeclType (globals CType*). }
function CTypeSizeBytes(tk: TTypeKind): Integer;
begin
  if CTypePtrDepth > 0 then Result := TARGET_PTR_SIZE
  else if tk = tyRecord then Result := RecSize(CTypeBaseRec)
  else Result := TypeSize(tk);
end;

{ `sizeof(type)`, `sizeof(expr)`, or `sizeof expr` -> a compile-time integer.
  CurTok is the `sizeof` identifier. Folds a type operand to its size; an
  identifier operand to its symbol's size; otherwise a conservative pointer
  size (full expression-type sizing arrives with the type system). }
function ParseCSizeof: Integer;
var node, sz, si, depth: Integer; tk: TTypeKind;
begin
  Next; { sizeof }
  sz := TARGET_PTR_SIZE;
  if CurTok.Kind = tkLParen then
  begin
    Next;
    if IsCTypeTok then
    begin
      tk := ParseCDeclType;
      sz := CTypeSizeBytes(tk);
    end
    else if CurTok.Kind = tkStar then
    begin
      { `sizeof(*p)` -> size of the pointed-at type, not the pointer. Without
        this the operand fell through to the default pointer size, so e.g. lua's
        `memcpy(ra+4, ra, 3*sizeof(*ra))` (ra a StackValue*) copied 3*8 instead
        of 3*16 bytes and dropped the generic-for state/control values. }
      Next;  { consume '*' }
      if CurTok.Kind = tkIdent then
      begin
        si := FindSym(CurTok.SVal);
        if (si >= 0) and (Syms[si].TypeKind = tyPointer) then
        begin
          if Syms[si].PtrElemTk = tyRecord then sz := RecSize(Syms[si].PtrElemRec)
          else sz := TypeSize(Syms[si].PtrElemTk);
        end;
      end;
    end
    else if CurTok.Kind = tkString then
    begin
      { `sizeof("lit")` is the char-array size = decoded byte length + 1 (NUL),
        NOT the default pointer size. lua's `new_localvarliteral(ls,v)` registers
        a hidden local of length `sizeof(v)-1`; with the pointer-size default,
        `sizeof("self")-1` was 7 not 4, so the colon-method `self` parameter was
        registered under a 7-char garbage name and every `self` reference inside
        the body resolved to a nil global. The string token carries its decoded
        length in SLen (escapes already folded). }
      sz := Tokens[TokPos - 1].SLen + 1;
    end
    else if CurTok.Kind = tkIdent then
    begin
      si := FindSym(CurTok.SVal);
      if si >= 0 then
      begin
        if Tokens[TokPos].Kind = tkLBrack then
        begin
          { `sizeof(arr[i])` / `sizeof(p[i])` — the size of ONE element, not the
            whole array. Without this, the ubiquitous `ArraySize(x)` idiom
            `sizeof(x)/sizeof(x[0])` folded to 1 (whole/whole), so e.g. sqlite's
            built-in-extension loop ran a single iteration. }
          if Syms[si].IsArray then
          begin
            if Syms[si].ElemType = tyRecord then sz := RecSize(Syms[si].ElemRecName)
            else sz := TypeSize(Syms[si].ElemType);
          end
          else if Syms[si].TypeKind = tyPointer then
          begin
            if Syms[si].PtrElemTk = tyRecord then sz := RecSize(Syms[si].PtrElemRec)
            else sz := TypeSize(Syms[si].PtrElemTk);
          end
          else sz := TypeSize(Syms[si].TypeKind);
        end
        else if Syms[si].IsArray then sz := Syms[si].ArrLen * TypeSize(Syms[si].ElemType)
        else if Syms[si].TypeKind = tyRecord then sz := RecSize(Syms[si].RecName)
        else sz := TypeSize(Syms[si].TypeKind);
      end;
    end;
    { Skip the rest of the operand to the MATCHING `)` — balanced parens, so
      `sizeof((l)[0])` / `sizeof(a[i])` don't stop at an inner `)`. }
    depth := 1;
    while CurTok.Kind <> tkEOF do
    begin
      if CurTok.Kind = tkLParen then Inc(depth)
      else if CurTok.Kind = tkRParen then
      begin
        Dec(depth);
        if depth = 0 then Break;
      end;
      Next;
    end;
    Expect(tkRParen, ')');
  end
  else if CurTok.Kind = tkIdent then
  begin
    si := FindSym(CurTok.SVal);
    if si >= 0 then sz := TypeSize(Syms[si].TypeKind);
    Next;
  end;
  node := AllocNode(AN_INT_LIT);
  ASTIVal[node] := sz;
  ASTTk[node] := Ord(tyInteger);
  Result := node;
end;

{ Peek: is the `(` at CurTok the start of a cast `(type)…`? Rewinds. }
function CIsCastAhead: Boolean;
var savedPos: Integer;
begin
  savedPos := TokPos - 1;          { index of the '(' }
  Next;                            { CurTok = first token inside the parens }
  Result := IsCTypeTok;
  TokPos := savedPos; Next;        { rewind to '(' }
end;

{ Unary prefix: `- + ! ~ * &`, sizeof, and casts `(type)expr`. }
function ParseCUnary: Integer;
var node, operand, castElemTk, castElemRec, castDepth, argSeq, castProcSig: Integer;
    castTk, opTk: TTypeKind; isVoidCast: Boolean;
begin
  { sizeof }
  if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'sizeof') then
  begin
    Result := ParseCSizeof();
    Exit;
  end;
  { cast: (type) unary -> reinterpret/retag the operand to the target type }
  if (CurTok.Kind = tkLParen) and CIsCastAhead then
  begin
    Next; { ( }
    castTk := ParseCDeclType;
    castDepth := CTypePtrDepth;
    castElemTk := CTypeElemTk;
    castElemRec := CTypeElemRec;
    castProcSig := CTypeProcSig;   { fn-pointer cast `(ret(*)(params))e`: callable value }
    isVoidCast := CTypeIsVoid and (CTypePtrDepth = 0);
    Expect(tkRParen, ')');
    operand := ParseCUnary();   { recurses — clobbers the CType* globals, so castProcSig was captured above }
    { `(void)expr` evaluates expr for its side effects and discards the value.
      Return the operand unwrapped so a void-cast call statement (e.g. the lua
      API macro `lua_pushglobaltable` = `((void)lua_rawgeti(...))`) keeps its
      call and is not pruned as a dead retag node. A `void *` cast (depth > 0)
      is a real pointer cast and stays on the retag path below. }
    if isVoidCast then begin Result := operand; Exit; end;
    { A NUMERIC float<->int cast must CONVERT, not bit-reinterpret: `(int)1.5`==1,
      `(double)i`==(double)i. AN_PTR_CAST only retags, so it left the IEEE bits
      and read them as an integer (-> 0). Route through the existing cross-target
      float intrinsics: -203 Trunc (float->int, toward zero = C cast semantics)
      and -206 Int (int->float, cvtsi2sd). Pointer casts, same-class and
      float<->float casts keep the reinterpret/retag path below. }
    opTk := IntToTypeKind(ASTTk[operand]);
    if (castDepth = 0) and (not TypeIsFloat(castTk)) and TypeIsOrdinal(castTk)
       and TypeIsFloat(opTk) then
    begin
      node := AllocNode(AN_CALL); ASTIVal[node] := -203;   { Trunc: float -> int }
      argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := operand;
      ASTLeft[node] := argSeq; ASTTk[node] := Ord(castTk);
      Result := node; Exit;
    end
    else if (castDepth = 0) and TypeIsFloat(castTk)
            and TypeIsOrdinal(opTk) and (not TypeIsFloat(opTk)) then
    begin
      node := AllocNode(AN_CALL); ASTIVal[node] := -206;   { Int: int -> float }
      argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := operand;
      ASTLeft[node] := argSeq; ASTTk[node] := Ord(castTk);
      Result := node; Exit;
    end;
    node := AllocNode(AN_PTR_CAST);
    ASTLeft[node] := operand;
    ASTIVal[node] := -1;            { numeric / pointer reinterpret-retag }
    ASTRight[node] := castProcSig;  { >=0 iff cast to a fn-pointer type: callee sig for CNodeProcSig }
    if castDepth > 0 then
    begin
      RegisterPtrAlias(0, 0, castElemTk, castElemRec, 0, 0);
      ASTIVal[node] := AliasCount - 1;
      ASTTk[node] := Ord(tyPointer);
    end
    else ASTTk[node] := Ord(castTk);
    Result := node;
    Exit;
  end;
  case CurTok.Kind of
    tkStar:   { *p dereference }
    begin
      Next;
      operand := ParseCUnary();
      node := AllocNode(AN_DEREF);
      ASTLeft[node] := operand;
      ASTTk[node] := CNodePointeeTk(operand);
      if CNodePtrElemRec(operand) > 0 then
        ASTIVal[node] := CNodePtrElemRec(operand);
      Result := node;
    end;
    tkAmp:    { &x address-of }
    begin
      Next;
      operand := ParseCUnary();
      node := AllocNode(AN_ADDR);
      ASTLeft[node] := operand;
      ASTIVal[node] := ResolveNodeRec(operand);
      ASTTk[node] := Ord(tyPointer);
      Result := node;
    end;
    tkMinus:
    begin
      Next;
      operand := ParseCUnary();
      node := AllocNode(AN_NEG);
      ASTLeft[node] := operand;
      ASTTk[node] := ASTTk[operand];
      Result := node;
    end;
    tkPlus:
    begin
      Next;
      Result := ParseCUnary();
    end;
    tkNot:   { `~` bitwise NOT }
    begin
      Next;
      operand := ParseCUnary();
      node := AllocNode(AN_NOT);
      ASTLeft[node] := operand;
      ASTTk[node] := Ord(tyInteger);
      Result := node;
    end;
    tkLogNot:   { `!` logical NOT -> (operand == 0), a 0/1 boolean }
    begin
      Next;
      operand := ParseCUnary();
      node := AllocNode(AN_BINOP);
      ASTIVal[node] := Ord(tkEq);
      ASTLeft[node] := operand;
      ASTRight[node] := AllocNode(AN_INT_LIT);
      ASTIVal[ASTRight[node]] := 0;
      ASTTk[ASTRight[node]] := Ord(tyInteger);
      ASTTk[node] := Ord(tyBoolean);
      Result := node;
    end;
    tkPlusPlus:   { prefix ++lv }
    begin
      Next;
      operand := ParseCUnary();
      Result := CMakeIncDec(operand, True, True);
    end;
    tkMinusMinus: { prefix --lv }
    begin
      Next;
      operand := ParseCUnary();
      Result := CMakeIncDec(operand, False, True);
    end;
    else
      Result := ParseCPostfix();
  end;
end;

{ Procedural-call signature of a node that yields a function-pointer value, or -1.
  Unwraps `*fnptr` (dereferencing a function pointer yields the same callee) and
  resolves the signature of a fn-pointer variable or record field. `callee`
  returns the node whose value is the function address (the var/field itself,
  never the deref) so `(*p->cb)(args)` calls through `p->cb`. }
function CNodeProcSig(node: Integer; var callee: Integer): Integer;
var inner, recId: Integer; fname: AnsiString;
begin
  Result := -1; callee := node;
  if node < 0 then Exit;
  inner := node;
  while ASTKind[inner] = AN_DEREF do inner := ASTLeft[inner];
  callee := inner;
  if ASTKind[inner] = AN_IDENT then
    Result := SymProcSig[ASTIVal[inner]]
  else if (ASTKind[inner] = AN_INDEX) and (ASTKind[ASTLeft[inner]] = AN_IDENT) then
    { `arr[i](args)` — call through an element of a function-pointer array; the
      array sym carries the per-element call signature in SymElemProcSig. }
    Result := SymElemProcSig[ASTIVal[ASTLeft[inner]]]
  else if ASTKind[inner] = AN_PTR_CAST then
    Result := ASTRight[inner]   { cast to a fn-pointer type carries its callee sig (>=0), else -1 }
  else if ASTKind[inner] = AN_FIELD then
  begin
    recId := ResolveNodeRec(ASTLeft[inner]);
    if recId <> REC_NONE then
    begin
      fname := GetTokenStrFromRaw(ASTSOffset[inner], ASTSLen[inner]);
      Result := RecFieldProcSig(recId, fname);
    end;
  end;
end;

{ Postfix layer: a primary optionally followed by `++`/`--`. Array/field/call
  postfix (`[] . -> ()`) arrive with the lvalue increment. }
function ParseCPostfix: Integer;
var node, idxExpr, inode, dnode, fnode, baseFld, recId, fldOff, fldLen: Integer;
    argHead, argTail, argNode, valNode, sig, calleeNode2: Integer;
    rowStride, strideLit, mulNode: Integer;
    ndimsF, flatNode, spanD, ndi, nIdx: Integer;
    done: Boolean; fieldName: AnsiString;
begin
  node := ParseCPrimary;
  done := False;
  while not done do
  begin
    if CurTok.Kind = tkLBrack then        { subscript a[i] / p[i] }
    begin
      Next;
      idxExpr := ParseCExpr;
      Expect(tkRBrack, ']');
      if (ASTKind[node] = AN_IDENT) and NodeArrNDInfo(node) and
         (CurTok.Kind = tkLBrack) then
      begin
        { Local/global multidimensional C array `a[i][j]`: flatten the chained
          subscripts to one AN_INDEX over the row-major storage. }
        NDIdxNode[0] := idxExpr;
        nIdx := 1;
        while (CurTok.Kind = tkLBrack) and (nIdx < NDInfoNDims) do
        begin
          Next;
          NDIdxNode[nIdx] := ParseCExpr;
          Inc(nIdx);
          Expect(tkRBrack, ']');
        end;
        if nIdx <> NDInfoNDims then Error('wrong number of array subscripts');
        inode := AllocNode(AN_INDEX);
        ASTLeft[inode] := node;
        ASTRight[inode] := BuildFlatNDIndex(nIdx);
        ASTTk[inode] := Ord(Syms[ASTIVal[node]].ElemType);
        node := inode;
      end
      else if (ASTKind[node] = AN_FIELD) and
         (RecFieldArrNDims(ResolveNodeRec(ASTLeft[node]), GetASTIdentName(node)) >= 2) then
      begin
        { Multidim array struct field `T m[A][B]..`. The generic per-subscript
          AN_INDEX path mis-strides the outer index (CNodePointeeTk(AN_FIELD)
          defaults to Integer -> 4-byte outer stride), so handle the whole
          subscript run here:
          - FULL index `m[i][j]..` (one subscript per dimension): flatten to a
            single AN_INDEX(field, Horner(i,j,..)) — the field-base AN_INDEX
            strides by the real element size, so the address is correct.
          - PARTIAL index `m[i]` (fewer subscripts than dims): C array decay to
            the ROW ADDRESS `&field + i*rowStride` as a raw pointer value, so
            `T** p = m[i]` gets the row and a later `p[j]` indexes it. }
        ndimsF := RecFieldArrNDims(ResolveNodeRec(ASTLeft[node]), GetASTIdentName(node));
        baseFld := node;            { remember the AN_FIELD for stride/row queries }
        flatNode := idxExpr; ndi := 1;
        while (CurTok.Kind = tkLBrack) and (ndi < ndimsF) do
        begin
          Next;
          { flat := flat*span[ndi] + nextIdx  (Horner, element units) }
          spanD := RecFieldArrDimSpanAt(ResolveNodeRec(ASTLeft[baseFld]), GetASTIdentName(baseFld), ndi);
          strideLit := AllocNode(AN_INT_LIT); ASTIVal[strideLit] := spanD; ASTTk[strideLit] := Ord(tyInteger);
          mulNode := AllocNode(AN_BINOP); ASTIVal[mulNode] := Ord(tkStar);
          ASTLeft[mulNode] := flatNode; ASTRight[mulNode] := strideLit; ASTTk[mulNode] := Ord(tyInteger);
          idxExpr := ParseCExpr;
          Expect(tkRBrack, ']');
          inode := AllocNode(AN_BINOP); ASTIVal[inode] := Ord(tkPlus);
          ASTLeft[inode] := mulNode; ASTRight[inode] := idxExpr; ASTTk[inode] := Ord(tyInteger);
          flatNode := inode;
          Inc(ndi);
        end;
        if ndi >= ndimsF then
        begin
          { full index: one flat AN_INDEX, element stride from the field type }
          inode := AllocNode(AN_INDEX);
          ASTLeft[inode] := baseFld;
          ASTRight[inode] := flatNode;
          ASTTk[inode] := Ord(RecFieldType(ResolveNodeRec(ASTLeft[baseFld]), GetASTIdentName(baseFld)));
          node := inode;
        end
        else
        begin
          { partial index -> row pointer. rowStride = product(remaining spans)*elem.
            Tag operands tyInt64 so the add is raw 64-bit (no pointer-stride scale);
            the AN_FIELD value decays to its address as the base. }
          rowStride := RecFieldRowStride(ResolveNodeRec(ASTLeft[baseFld]), GetASTIdentName(baseFld));
          ASTTk[baseFld] := Ord(tyInt64);
          strideLit := AllocNode(AN_INT_LIT); ASTIVal[strideLit] := rowStride; ASTTk[strideLit] := Ord(tyInt64);
          mulNode := AllocNode(AN_BINOP); ASTIVal[mulNode] := Ord(tkStar);
          ASTLeft[mulNode] := flatNode; ASTRight[mulNode] := strideLit; ASTTk[mulNode] := Ord(tyInt64);
          inode := AllocNode(AN_BINOP); ASTIVal[inode] := Ord(tkPlus);
          ASTLeft[inode] := baseFld; ASTRight[inode] := mulNode; ASTTk[inode] := Ord(tyPointer);
          node := inode;
        end;
      end
      else
      begin
        inode := AllocNode(AN_INDEX);
        ASTLeft[inode] := node;
        ASTRight[inode] := idxExpr;
        ASTTk[inode] := CNodePointeeTk(node);
        node := inode;
      end;
    end
    else if CurTok.Kind = tkDot then      { `.` field, or `->` (also tkDot) }
    begin
      Next;
      if CurTok.Kind <> tkIdent then Error('field name expected after .');
      fldOff := Tokens[TokPos - 1].SOffset;
      fldLen := Tokens[TokPos - 1].SLen;
      fieldName := CurTok.SVal;
      { On a pointer base this is C `->`: dereference, then take the field. }
      baseFld := node;
      if CNodeIsPointer(node) then
      begin
        dnode := AllocNode(AN_DEREF);
        ASTLeft[dnode] := node;
        ASTTk[dnode] := Ord(tyRecord);
        { A computed pointer (e.g. `(p+i)->f`, `(p++)->f`) has no symbol/field for
          ResolveNodeRec to walk, so carry the element record on the deref
          (ResolveNodeRec honours ASTIVal[AN_DEREF] > 0). }
        if CNodePtrElemRec(node) > 0 then
          ASTIVal[dnode] := CNodePtrElemRec(node);
        baseFld := dnode;
      end;
      recId := ResolveNodeRec(baseFld);
      fnode := AllocNode(AN_FIELD);
      ASTLeft[fnode] := baseFld;
      ASTSOffset[fnode] := fldOff;
      ASTSLen[fnode] := fldLen;
      if recId <> REC_NONE then
        ASTTk[fnode] := Ord(RecFieldType(recId, fieldName))
      else
        ASTTk[fnode] := Ord(tyInteger);
      Next;   { consume field name }
      { fn-pointer field call: `rec.field(args)` / `p->field(args)` lowers to an
        indirect call through the field value (callee = AN_FIELD node). }
      if (CurTok.Kind = tkLParen) and (recId <> REC_NONE) and
         (RecFieldProcSig(recId, fieldName) >= 0) then
      begin
        sig := RecFieldProcSig(recId, fieldName);
        Next;                                 { consume '(' }
        argHead := -1; argTail := -1;
        if CurTok.Kind <> tkRParen then
          while True do
          begin
            valNode := ParseCExpr;
            argNode := AllocNode(AN_ARG);
            ASTLeft[argNode] := valNode; ASTRight[argNode] := -1;
            if argHead = -1 then argHead := argNode
            else ASTRight[argTail] := argNode;
            argTail := argNode;
            if CurTok.Kind = tkComma then begin Next; Continue; end;
            Break;
          end;
        Expect(tkRParen, ')');
        inode := AllocNode(AN_CALL_IND);
        ASTLeft[inode]  := argHead;
        ASTRight[inode] := fnode;             { callee value = the fn-pointer field }
        ASTIVal[inode]  := sig;
        ASTTk[inode]    := Ord(Procs[sig].RetType);
        ASTSLen[inode]  := 0;
        node := inode;
      end
      else
        node := fnode;
    end
    else if (CurTok.Kind = tkLParen) and (CNodeProcSig(node, calleeNode2) >= 0) then
    begin
      { indirect call through a parenthesized/dereferenced fn-pointer value, e.g.
        `(*g->frealloc)(g->ud, ...)` — lua's allocator idiom. }
      sig := CNodeProcSig(node, calleeNode2);
      Next;                                  { consume '(' }
      argHead := -1; argTail := -1;
      if CurTok.Kind <> tkRParen then
        while True do
        begin
          valNode := ParseCExpr;
          argNode := AllocNode(AN_ARG);
          ASTLeft[argNode] := valNode; ASTRight[argNode] := -1;
          if argHead = -1 then argHead := argNode
          else ASTRight[argTail] := argNode;
          argTail := argNode;
          if CurTok.Kind = tkComma then begin Next; Continue; end;
          Break;
        end;
      Expect(tkRParen, ')');
      inode := AllocNode(AN_CALL_IND);
      ASTLeft[inode]  := argHead;
      ASTRight[inode] := calleeNode2;
      ASTIVal[inode]  := sig;
      ASTTk[inode]    := Ord(Procs[sig].RetType);
      ASTSLen[inode]  := 0;
      node := inode;
    end
    else if (CurTok.Kind = tkPlusPlus) or (CurTok.Kind = tkMinusMinus) then
    begin
      if CurTok.Kind = tkPlusPlus then node := CMakeIncDec(node, True, False)
      else node := CMakeIncDec(node, False, False);
      Next;
    end
    else
      done := True;
  end;
  Result := node;
end;

{ Top-level C expression: assignment (right-assoc), incl. compound-assign and the
  conditional `?:` operator. The comma operator is handled at statement level. }
function ParseCExpr: Integer;
var left, rhs, node, cTok, baseOp, thenE, elseE, pair: Integer;
begin
  left := ParseCBinExpr(1);
  { conditional `cond ? a : b` — sits between logical-or and assignment, and is
    right-associative (`a ? b : c ? d : e` = `a ? b : (c ? d : e)`). Only the
    taken branch is evaluated (lowered via a hidden temp in ir.inc). }
  if CurTok.Kind = tkQuestion then
  begin
    Next;
    thenE := ParseCCommaExpr();   { middle: C `expression`, so comma is allowed }
    Expect(tkColon, ':');
    elseE := ParseCExpr();        { else: right-associative }
    pair := AllocNode(AN_PAIR);
    ASTLeft[pair] := thenE;
    ASTRight[pair] := elseE;
    node := AllocNode(AN_TERNARY);
    ASTLeft[node] := left;        { condition }
    ASTRight[node] := pair;
    ASTTk[node] := CTernaryResultTk(thenE, elseE);
    if CProgramMode and (CNodeDecaysToPointer(thenE) or CNodeDecaysToPointer(elseE)) then
    begin
      ASTTk[node] := Ord(tyPointer);
      if CNodeDecaysToPointer(thenE) then
        ASTSOffset[node] := CNodePtrElemRec(thenE)
      else
        ASTSOffset[node] := CNodePtrElemRec(elseE);
    end;
    left := node;
  end;
  case CurTok.Kind of
    tkAssign, tkPlusEq, tkMinusEq, tkStarEq, tkSlashEq, tkModEq,
    tkAmpEq, tkPipeEq, tkXorEq, tkShlEq, tkShrEq:
    begin
      cTok := Ord(CurTok.Kind);
      Next;
      rhs := ParseCExpr();   { right-associative }
      if cTok <> Ord(tkAssign) then
      begin
        { x OP= y  ==>  x = x OP y. The left operand node is reused as the
          binop's left; since it is a pure lvalue read this is safe. }
        baseOp := Ord(tkPlus);
        if cTok = Ord(tkMinusEq) then baseOp := Ord(tkMinus)
        else if cTok = Ord(tkStarEq) then baseOp := Ord(tkStar)
        else if cTok = Ord(tkSlashEq) then baseOp := Ord(tkSlash)
        else if cTok = Ord(tkModEq) then baseOp := Ord(tkMod)
        else if cTok = Ord(tkAmpEq) then baseOp := Ord(tkAmp)
        else if cTok = Ord(tkPipeEq) then baseOp := Ord(tkPipe)
        else if cTok = Ord(tkXorEq) then baseOp := Ord(tkXor)
        else if cTok = Ord(tkShlEq) then baseOp := Ord(tkShl)
        else if cTok = Ord(tkShrEq) then baseOp := Ord(tkShr);
        rhs := CMakeBinop(baseOp, left, rhs);
      end;
      node := AllocNode(AN_ASSIGN);
      ASTLeft[node] := left;
      ASTRight[node] := rhs;
      ASTTk[node] := ASTTk[left];
      Result := node;
    end;
    else
      Result := left;
  end;
end;

function CTypedefHashKey(const name: AnsiString): Integer;
var i, h: Integer;
begin
  h := 5381;                  { djb2; small literals to stay self-host safe }
  for i := 1 to Length(name) do
    h := ((h * 33) + Ord(name[i])) and 1073741823;  { mask to 30 bits }
  Result := h and 16383;      { table size - 1 }
end;

function CTypedefNameMatches(idx: Integer; const name: AnsiString): Boolean;
var j: Integer;
begin
  Result := False;
  if CTypedefNameLen[idx] <> Length(name) then Exit;
  for j := 0 to CTypedefNameLen[idx] - 1 do
    if CTypedefChars[CTypedefNameOff[idx] + j] <> name[j + 1] then Exit;
  Result := True;
end;

{ O(1) average lookup via the open-addressed hash. Slots hold idx+1; 0 = empty. }
function FindCTypedef(const name: AnsiString): Integer;
var slot, stored: Integer;
begin
  slot := CTypedefHashKey(name);
  while True do
  begin
    stored := CTypedefHash[slot];
    if stored = 0 then begin Result := -1; Exit; end;
    if CTypedefNameMatches(stored - 1, name) then begin Result := stored - 1; Exit; end;
    slot := (slot + 1) and 16383;
  end;
end;

procedure CTypedefHashInsert(idx: Integer; const name: AnsiString);
var slot: Integer;
begin
  slot := CTypedefHashKey(name);
  while CTypedefHash[slot] <> 0 do slot := (slot + 1) and 16383;
  CTypedefHash[slot] := idx + 1;
end;

{ Index of a struct/union tag in the tag table, or -1. O(1) via CTagHash. }
function CTagNameMatches(idx: Integer; const name: AnsiString): Boolean;
var j: Integer;
begin
  Result := False;
  if CTagNameLen[idx] <> Length(name) then Exit;
  for j := 0 to CTagNameLen[idx] - 1 do
    if CTagChars[CTagNameOff[idx] + j] <> name[j + 1] then Exit;
  Result := True;
end;

function FindCTagIdx(const name: AnsiString): Integer;
var slot, stored: Integer;
begin
  slot := CTypedefHashKey(name);
  while True do
  begin
    stored := CTagHash[slot];
    if stored = 0 then begin Result := -1; Exit; end;
    if CTagNameMatches(stored - 1, name) then begin Result := stored - 1; Exit; end;
    slot := (slot + 1) and 16383;
  end;
end;

{ Struct/union tag lookup. Returns the record id (REC_UCLASS_BASE+ci) or -1. }
function FindCTag(const name: AnsiString): Integer;
var idx: Integer;
begin
  idx := FindCTagIdx(name);
  if idx >= 0 then Result := CTagRec[idx] else Result := -1;
end;

procedure AddCTag(const name: AnsiString; recId: Integer);
var idx, i: Integer;
begin
  idx := FindCTagIdx(name);
  if idx >= 0 then begin CTagRec[idx] := recId; Exit; end;  { update (forward -> defined) }
  if CTagCount >= MAX_CTYPEDEF then Error('C tag table overflow');
  if CTagCharLen + Length(name) >= 524288 then Error('C tag chars pool overflow');
  CTagNameOff[CTagCount] := CTagCharLen;
  CTagNameLen[CTagCount] := Length(name);
  for i := 1 to Length(name) do begin CTagChars[CTagCharLen] := name[i]; Inc(CTagCharLen); end;
  CTagRec[CTagCount] := recId;
  i := CTypedefHashKey(name);
  while CTagHash[i] <> 0 do i := (i + 1) and 16383;
  CTagHash[i] := CTagCount + 1;
  Inc(CTagCount);
end;

{ Resolve a struct/union tag to its record id, creating a forward (empty)
  record if the tag has not been seen — so `struct Node *next;` inside Node and
  forward declarations resolve. }
function FindOrForwardCTag(const name: AnsiString): Integer;
var rec, ci: Integer;
begin
  rec := FindCTag(name);
  if rec >= 0 then begin Result := rec; Exit; end;
  { Out of record-table headroom (e.g. GTK's thousands of tags): resolve the tag
    as opaque (REC_NONE) instead of allocating a UClass, so a macro-soup header
    degrades gracefully rather than overflowing MAX_UCLASS. }
  if UClsCount >= MAX_UCLASS - 1 then begin Result := REC_NONE; Exit; end;
  ci := AddUClass(0, 0);
  UClsIsRecord[ci] := True;
  rec := REC_UCLASS_BASE + ci;
  AddCTag(name, rec);
  Result := rec;
end;

{ Lay out an inline struct/union body `{ ... }` (CurTok at the brace) into a
  record, used for `struct|union [tag] { ... }` in a TYPE position. `rec` is the
  tag's record (>= REC_UCLASS_BASE) or REC_NONE for an anonymous body; on return
  it holds the laid-out record id. }
procedure CParseInlineAggBody(var rec: Integer; isUnion: Boolean);
var d: Integer;
begin
  if (rec < REC_UCLASS_BASE) and (UClsCount < MAX_UCLASS - 1) then
  begin
    rec := REC_UCLASS_BASE + AddUClass(0, 0);
    UClsIsRecord[rec - REC_UCLASS_BASE] := True;
  end;
  if rec >= REC_UCLASS_BASE then
    ParseCStructInto(rec - REC_UCLASS_BASE, isUnion)
  else
  begin
    d := 0;   { no record headroom: skip the body with balanced braces }
    repeat
      if CurTok.Kind = tkBegin then Inc(d)
      else if CurTok.Kind = tkEnd then Dec(d);
      Next;
    until (d = 0) or (CurTok.Kind = tkEOF);
  end;
end;

procedure AddCTypedefEx(const name: AnsiString; tk: TTypeKind; elemTk, rec: Integer);
var idx, i: Integer;
begin
  idx := FindCTypedef(name);
  if idx >= 0 then
  begin
    CTypedefTk[idx] := Ord(tk);
    CTypedefElemTk[idx] := elemTk;
    CTypedefRec[idx] := rec;
    CTypedefProcSig[idx] := -1;
    Exit;
  end;
  if CTypedefCount >= MAX_CTYPEDEF then Error('C typedef table overflow');
  if CTypedefCharLen + Length(name) >= 524288 then Error('C typedef chars pool overflow');

  CTypedefNameOff[CTypedefCount] := CTypedefCharLen;
  CTypedefNameLen[CTypedefCount] := Length(name);
  for i := 1 to Length(name) do
  begin
    CTypedefChars[CTypedefCharLen] := name[i];
    Inc(CTypedefCharLen);
  end;

  CTypedefTk[CTypedefCount] := Ord(tk);
  CTypedefElemTk[CTypedefCount] := elemTk;
  CTypedefRec[CTypedefCount] := rec;
  CTypedefProcSig[CTypedefCount] := -1;
  CTypedefHashInsert(CTypedefCount, name);
  Inc(CTypedefCount);
end;

procedure AddCTypedef(const name: AnsiString; tk: TTypeKind);
begin
  AddCTypedefEx(name, tk, Ord(tyUnknown), REC_NONE);
end;

{ Register a function-pointer typedef: `Name` resolves to a pointer value, but
  carries `sigPi` (a signature Procs[] entry, BodyAddr=-1, ProcCdecl) so a var of
  this type is callable through AN_CALL_IND with proper marshalling. }
procedure AddCTypedefFnPtr(const name: AnsiString; sigPi: Integer);
var idx: Integer;
begin
  AddCTypedef(name, tyPointer);
  idx := FindCTypedef(name);
  if idx >= 0 then CTypedefProcSig[idx] := sigPi;
end;

function IsCTypeTok: Boolean;
begin
  Result := CurTok.Kind in [tkInteger_T, tkChar_T, tkCVoid, tkCShort,
    tkCLong, tkCSigned, tkCUnsigned, tkCFloat, tkCDouble, tkCBool, tkConst,
    tkRecord { 'struct' }];
  if (not Result) and (CurTok.Kind = tkIdent) then
    Result := (CurTok.SVal = 'union') or (CurTok.SVal = 'enum') or
              (FindCTypedef(CurTok.SVal) >= 0);
end;

function CUnsignedOf(tk: TTypeKind): TTypeKind;
begin
  Result := tk;
  if tk = tyInt16 then Result := tyUInt16
  else if tk = tyInt32 then Result := tyUInt32
  else if tk = tyInt64 then Result := tyUInt64;
end;

{ Consume a C declaration-specifier sequence (const, signed/unsigned,
  short/long[/long], int/char/void/float/double/_Bool) followed by any
  pointer suffix, and return the mapped Pascal/ABI TTypeKind. Sets the
  global CTypeIsVoid when the result is bare `void` (no pointer). Width and
  signedness are preserved: long/long long -> 8-byte on LP64, short -> 2,
  any pointer -> untyped Pointer (8). }
function ParseCDeclType: TTypeKind;
var
  isUnsigned, isSigned, isFloatTy, isVoid, loop, sawBase, isTypedef, isAggBase: Boolean;
  shortCount, longCount, tdIdx, depth, baseRec, tdElemTk, tdElemRec: Integer;
  base, fpRet, fpPType: TTypeKind;
  fpName: AnsiString;
  fpNameOff, fpNameLen: Integer;   { name token off/len, kept local — a recursive ParseCDeclType (params) resets the globals }
  fpArrLen: Integer;               { array dimension of `(*name[N])` — kept local, restored after the param recursion resets the global }
  fpNParams, fpSig, fnRetNParams, pi: Integer;
  fpPTypes: array[0..15] of TTypeKind;
  fpPNames: array[0..15] of AnsiString;
  fnRetPTypes: array[0..15] of TTypeKind;
  fnRetPNames: array[0..15] of AnsiString;
  fnRetPDepths, fnRetPBaseTk, fnRetPBaseRec, fnRetPElemTk, fnRetPElemRec: array[0..15] of Integer;
  fnRetPRecId, fnRetPProcSig: array[0..15] of Integer;
  fnRetIsFunc: Boolean;
begin
  isUnsigned := False; isSigned := False; isFloatTy := False; isVoid := False;
  sawBase := False; isTypedef := False; isAggBase := False;
  shortCount := 0; longCount := 0; base := tyInt32; baseRec := REC_NONE;
  tdElemTk := Ord(tyUnknown); tdElemRec := REC_NONE;
  CTypeProcSig := -1;
  CTypeFnPtrName := '';
  CTypeFnPtrNameOff := 0; CTypeFnPtrNameLen := 0;
  CTypeFnPtrArrLen := -2;
  CTypeFnRetIsFunc := False;
  CTypeFnRetParamCount := 0;
  loop := True;
  while loop do
  begin
    case CurTok.Kind of
      tkConst:     Next;
      tkCSigned:   begin isSigned := True; sawBase := True; Next; end;
      tkCUnsigned: begin isUnsigned := True; sawBase := True; Next; end;
      tkCShort:    begin Inc(shortCount); sawBase := True; Next; end;
      tkCLong:     begin Inc(longCount); sawBase := True; Next; end;
      tkInteger_T: begin base := tyInt32; sawBase := True; Next; end;
      tkChar_T:    begin base := tyChar; sawBase := True; Next; end;
      tkCVoid:     begin isVoid := True; sawBase := True; Next; end;
      tkCFloat:    begin base := tySingle; isFloatTy := True; sawBase := True; Next; end;
      tkCDouble:   begin base := tyDouble; isFloatTy := True; sawBase := True; Next; end;
      tkCBool:     begin base := tyUInt8; sawBase := True; Next; end;
      tkRecord:    { 'struct' [tag] [inline body] in type position }
        begin
          Next;
          base := tyRecord; isAggBase := True; sawBase := True;
          if CurTok.Kind = tkIdent then begin baseRec := FindOrForwardCTag(CurTok.SVal); Next; end;
          if CurTok.Kind = tkBegin then CParseInlineAggBody(baseRec, False);
        end;
      tkIdent:
        begin
          { A typedef name is a type only in type position (before any base
            type is seen); otherwise it is the declarator name — stop.
            `union`/`enum` keywords are idents in this lexer. }
          if (not sawBase) and (CurTok.SVal = 'union') then
          begin
            Next;
            base := tyRecord; isAggBase := True; sawBase := True;
            if CurTok.Kind = tkIdent then begin baseRec := FindOrForwardCTag(CurTok.SVal); Next; end;
            if CurTok.Kind = tkBegin then CParseInlineAggBody(baseRec, True);
          end
          else if (not sawBase) and (CurTok.SVal = 'enum') then
          begin
            Next;
            if CurTok.Kind = tkIdent then Next;   { tag — enum value is just an int }
            base := tyInt32; sawBase := True;
          end
          else
          begin
            tdIdx := -1;
            if not sawBase then tdIdx := FindCTypedef(CurTok.SVal);
            if tdIdx >= 0 then
            begin
              base := IntToTypeKind(CTypedefTk[tdIdx]);
              baseRec := CTypedefRec[tdIdx];
              tdElemTk := CTypedefElemTk[tdIdx];
              tdElemRec := CTypedefRec[tdIdx];
              CTypeProcSig := CTypedefProcSig[tdIdx]; { fn-pointer typedef carries a call signature }
              sawBase := True; isTypedef := True;
              Next;
            end
            else loop := False;
          end;
        end;
      else loop := False;
    end;
  end;

  CTypeIsVoid := isVoid;

  if isVoid then
    Result := tyInteger          { placeholder; pointer suffix overrides below }
  else if isAggBase then
    Result := tyRecord           { struct/union tag reference }
  else if isTypedef then
    Result := base               { typedef carries its own resolved kind }
  else if isFloatTy then
    Result := base
  else if base = tyChar then
  begin
    if isSigned then base := tyInt8
    else if isUnsigned then base := tyUInt8;
    Result := base;              { plain char stays tyChar }
  end
  else
  begin
    if shortCount > 0 then base := tyInt16
    else if longCount > 0 then base := tyInt64
    else base := tyInt32;
    if isUnsigned then base := CUnsignedOf(base);
    Result := base;
  end;

  { Pointer suffix. Every star is still an 8-byte Pointer at the value level,
    but we now record the pointed-at type (depth 1) and the depth, so a typed
    handle can deref/index/field correctly and a struct pointer knows its
    record. Depth >= 2 reports the element as Pointer (a `T**` derefs to a
    `T*`). The base (Result) before the stars is the element kind. }
  CTypePtrDepth := 0;
  CTypeElemTk := Ord(tyUnknown);
  CTypeElemRec := REC_NONE;
  CTypePtrBaseTk := Ord(tyUnknown);
  CTypePtrBaseRec := REC_NONE;
  CTypeBaseRec := baseRec;
  if isTypedef and (Result = tyPointer) then
  begin
    CTypeElemTk := tdElemTk;
    CTypeElemRec := tdElemRec;
  end;
  if CurTok.Kind = tkStar then
  begin
    CTypeProcSig := -1;           { `FnPtrTypedef *` = pointer-to-fn-ptr, not directly callable }
    CTypeElemTk := Ord(Result);   { the pointed-at scalar/typedef kind at depth 1 }
    CTypeElemRec := baseRec;      { ...and its record id, if it is a struct }
    CTypePtrBaseTk := Ord(Result);
    CTypePtrBaseRec := baseRec;
    while CurTok.Kind = tkStar do
    begin
      Inc(CTypePtrDepth);
      Next;
      { skip a pointer-level `const`/`volatile` qualifier: `char *const p`,
        `T * const * p` — without this the declarator name is never reached and
        the variable goes undeclared (read as 0). }
      while CurTok.Kind = tkConst do Next;
    end;
    if CTypePtrDepth >= 2 then
    begin
      { Pointer-to-pointer: the immediate element is itself a pointer (stride =
        pointer size), but KEEP the base record so `T** p; p[i]->field` resolves
        — ResolveNodeRec consults PtrElemRec at the AN_DEREF(AN_INDEX) (two-level)
        point. Was REC_NONE, which dropped the struct (lua's
        `TString **p = G(L)->strcache[i]; getstr(p[j])`). }
      CTypeElemTk := Ord(tyPointer);
      CTypeElemRec := baseRec;
    end;
    Result := tyPointer;
    CTypeIsVoid := False;
  end;

  { Function-pointer declarator: ret (*name)(params) — e.g. sqlite3_exec's
    callback. Without this the base type (int) leaks through as the param
    type, so a Pointer/nil argument fails overload and would truncate to 4
    bytes. Detect `(` immediately followed by `*`, collapse to Pointer, and
    skip both the `(*name)` declarator group and the trailing `(params)`
    group so the caller's parameter loop resyncs on the next `,`/`)`. }
  if (CurTok.Kind = tkLParen) and (Tokens[TokPos].Kind = tkStar) then
  begin
    fpRet := Result;                  { return type parsed above (before the '(') }
    if isVoid then fpRet := tyInteger;
    Result := tyPointer;
    CTypeIsVoid := False;
    fpName := '';
    fpArrLen := -2;
    fnRetIsFunc := False;
    fnRetNParams := 0;
    { first group `(*name)` — collapse to Pointer, capturing the declarator name }
    depth := 0;
    repeat
      if CurTok.Kind = tkLParen then Inc(depth)
      else if CurTok.Kind = tkRParen then Dec(depth)
      else if (CurTok.Kind = tkIdent) and (fpName = '') then
      begin
        fpName := CurTok.SVal;
        { CurTok.SOffset/SLen are NOT maintained by Next (it only fills
          Kind/IVal/Line/SVal) — read the live token-char ref from Tokens[]. The
          name is the current token, i.e. Tokens[TokPos-1] (Next pre-increments).
          Keep in locals: the recursive ParseCDeclType for the params resets the
          CTypeFnPtrName* globals. }
        fpNameOff := Tokens[TokPos-1].SOffset; fpNameLen := Tokens[TokPos-1].SLen;
        if Tokens[TokPos].Kind = tkLParen then
        begin
          { Function returning a function pointer: `ret (*Name(params))(...)`.
            The params inside the first group belong to the real function Name,
            not to the returned function pointer. Capture them for
            ParseCSubroutine, then let the outer group consume its closing `)`. }
          fnRetIsFunc := True;
          Next;                         { consume name -> CurTok is '(' }
          Next;                         { consume function param-list '(' }
          while (CurTok.Kind <> tkRParen) and (CurTok.Kind <> tkEOF) do
          begin
            if CurTok.Kind = tkDot then
            begin
              { variadic marker; ParseCSubroutine does not need it for sqlite's
                fn-returning-fnptr shape, so just consume it. }
              Next;
            end
            else if IsCTypeTok then
            begin
              fpPType := ParseCDeclType();
              if CTypeIsVoid then
              begin
                { `(void)` empty parameter list }
              end
              else if fnRetNParams <= 15 then
              begin
                fnRetPTypes[fnRetNParams] := fpPType;
                fnRetPDepths[fnRetNParams] := CTypePtrDepth;
                fnRetPBaseTk[fnRetNParams] := CTypePtrBaseTk;
                fnRetPBaseRec[fnRetNParams] := CTypePtrBaseRec;
                fnRetPElemTk[fnRetNParams] := CTypeElemTk;
                fnRetPElemRec[fnRetNParams] := CTypeElemRec;
                fnRetPRecId[fnRetNParams] := CTypeBaseRec;
                fnRetPProcSig[fnRetNParams] := CTypeProcSig;
                if CTypeFnPtrName <> '' then
                  fnRetPNames[fnRetNParams] := CTypeFnPtrName
                else if CurTok.Kind = tkIdent then
                begin
                  fnRetPNames[fnRetNParams] := CurTok.SVal;
                  Next;
                end
                else
                begin
                  fnRetPNames[fnRetNParams] := 'arg0';
                  fnRetPNames[fnRetNParams][4] := Chr(Ord('0') + fnRetNParams);
                end;
                Inc(fnRetNParams);
              end;
            end
            else
              Next;
            Eat(tkComma);
          end;
          Eat(tkRParen);
          Continue;
        end;
      end
      else if (CurTok.Kind = tkLBrack) and (fpName <> '') then
      begin
        { Array-of-function-pointer declarator `ret (*name[N])(params)` — capture
          the dimension so the var/global is registered as an ARRAY of callable
          pointers (sqlite's sqlite3BuiltinExtensions[]). `[]` = unbounded (sized
          from its initializer); `[N]` = fixed. The trailing Next below consumes
          the closing ']'. }
        Next;                          { consume '[' }
        if CurTok.Kind = tkRBrack then fpArrLen := -1
        else fpArrLen := CEvalConstExpr;
      end;
      Next;
    until (depth = 0) or (CurTok.Kind = tkEOF);
    { second group `(params)` — capture param types to build a call signature }
    fpNParams := 0;
    if CurTok.Kind = tkLParen then
    begin
      Next;                           { consume the parameter-list '(' }
      while (CurTok.Kind <> tkRParen) and (CurTok.Kind <> tkEOF) do
      begin
        if IsCTypeTok then
        begin
          { NB parens REQUIRED: bare `ParseCDeclType` would read this function's
            own Result (pxx bare-funcname rule), not recurse -> infinite loop. }
          fpPType := ParseCDeclType();
          if CTypeIsVoid then
          begin
            { (void) — no parameter }
          end
          else if fpNParams <= 15 then
          begin
            fpPTypes[fpNParams] := fpPType;
            fpPNames[fpNParams] := 'a';
            Inc(fpNParams);
          end;
          if CurTok.Kind = tkIdent then Next;  { optional parameter name }
        end
        else
          Next;                       { e.g. `...` varargs marker }
        Eat(tkComma);
      end;
      Eat(tkRParen);
    end;
    { Register the call signature whether or not the declarator carried a name.
      A NAMED form `ret (*name)(params)` threads CTypeFnPtrName onto the
      typedef/var/field/param; an ABSTRACT form `ret (*)(params)` has no name but
      still needs CTypeProcSig set so a cast to a function-pointer type
      (`((int(*)(const char*,int,int))p)(args)` — sqlite's osOpen syscall-table
      idiom) yields a callable value. }
    fpSig := RegisterProc('$cfnptr', True, fpRet, fpNParams, fpPNames, fpPTypes);
    Procs[fpSig].BodyAddr := -1;
    ProcCdecl[fpSig] := True;          { C ABI (System V) for the indirect call }
    CTypeProcSig := fpSig;             { caller threads this onto the typedef/var/field/cast }
    if fpName <> '' then
    begin
      CTypeFnPtrName := fpName;
      CTypeFnPtrNameOff := fpNameOff;  { assign AFTER the param recursion that reset the globals }
      CTypeFnPtrNameLen := fpNameLen;
      CTypeFnPtrArrLen := fpArrLen;    { ditto: `(*name[N])` dimension, clobbered by the param recursion }
      if fnRetIsFunc then
      begin
        CTypeFnRetIsFunc := True;
        CTypeFnRetParamCount := fnRetNParams;
        for pi := 0 to fnRetNParams - 1 do
        begin
          CTypeFnRetPTypes[pi] := fnRetPTypes[pi];
          CTypeFnRetPNames[pi] := fnRetPNames[pi];
          CTypeFnRetPDepths[pi] := fnRetPDepths[pi];
          CTypeFnRetPBaseTk[pi] := fnRetPBaseTk[pi];
          CTypeFnRetPBaseRec[pi] := fnRetPBaseRec[pi];
          CTypeFnRetPElemTk[pi] := fnRetPElemTk[pi];
          CTypeFnRetPElemRec[pi] := fnRetPElemRec[pi];
          CTypeFnRetPRecId[pi] := fnRetPRecId[pi];
          CTypeFnRetPProcSig[pi] := fnRetPProcSig[pi];
        end;
      end;
    end;
  end;
end;

function ParseCPrintfAST: Integer;
var node, argNode, strNode: Integer;
begin
  Next; { skip 'printf' }
  Expect(tkLParen, '(');
  node := AllocNode(AN_WRITE);
  if CurTok.Kind = tkString then
  begin
    strNode := AllocNode(AN_STR_LIT);
    ASTSOffset[strNode] := Tokens[TokPos - 1].SOffset;
    ASTSLen[strNode] := Tokens[TokPos - 1].SLen;
    ASTTk[strNode] := Ord(tyString);
    Next;
    argNode := AllocNode(AN_ARG);
    ASTLeft[argNode] := strNode;
    ASTLeft[node] := argNode;
  end;
  { skip any remaining args }
  while (CurTok.Kind <> tkRParen) and (CurTok.Kind <> tkEOF) do Next;
  Expect(tkRParen, ')');
  Eat(tkSemicolon);
  Result := node;
end;

{ A local declaration line: <type> name [= init] (, name [= init])* ;
  Each name is allocated (a global slot in a top-level main where CurProc<0, a
  stack local inside a function) so subsequent statements resolve it; returns an
  AN_BLOCK whose AN_SEQ chain holds the initialiser assignments (an empty block
  when there are no initialisers). Increment-1 scope: scalar declarators; array
  and per-declarator pointer-depth handling come later. }
function ParseCLocalDeclAST: Integer;
var baseTk, declTk, scalarTk: TTypeKind;
    head, tail, seq, asn, idn, initExpr, blk, idx: Integer;
    elemTkOrd, elemRec, arrLen, procSig: Integer;
    ptrDepth, ptrBaseTk, ptrBaseRec: Integer;
    declElemTk, declElemRec, declProcSig, declPtr, scalarRec: Integer;
    declPtrDepth, declBaseTk, declBaseRec: Integer;
    hadStar: Boolean;
    name: AnsiString;
    inode, idxLit, ei, nArrElems, brDepth: Integer;
    dimCount, dimVal, flatLen, di: Integer;
    arrElems: array[0..255] of Integer;
    dimSpan: array[0..MAX_ARR_DIMS-1] of Integer;
begin
  baseTk := ParseCDeclType;   { specifiers + first declarator's pointer suffix }
  { Capture the pointer element type/record now — ParseCExpr below must not
    clobber the CType* globals (it does not run ParseCDeclType). }
  elemTkOrd := CTypeElemTk;
  elemRec := CTypeElemRec;
  ptrDepth := CTypePtrDepth;
  ptrBaseTk := CTypePtrBaseTk;
  ptrBaseRec := CTypePtrBaseRec;
  procSig := CTypeProcSig;    { fn-pointer typedef signature, if any }
  if CTypeFnPtrName <> '' then
  begin
    { Inline function-pointer local `RET (*name)(params) [= init];` —
      ParseCDeclType consumed the whole declarator and captured the name + call
      signature. The name-reading loop below would Break (the name token is
      already consumed), so allocate the local here as an 8-byte callable
      pointer and parse the optional initializer. Mirrors the ParseCStructInto
      inline fn-ptr member branch. (Capture the name now: a cast inside the
      initializer expression re-runs ParseCDeclType and resets the global.) }
    name := CTypeFnPtrName;
    idx := AllocVar(name, tyPointer);
    Syms[idx].PtrElemTk := tyUnknown;
    Syms[idx].PtrElemRec := REC_NONE;
    SymPtrDepth[idx] := 1;
    SymPtrBaseTk[idx] := Ord(tyUnknown);
    SymPtrBaseRec[idx] := REC_NONE;
    if procSig >= 0 then SymProcSig[idx] := procSig;
    head := -1; tail := -1;
    if CurTok.Kind = tkAssign then
    begin
      Next;
      initExpr := ParseCExpr;
      idn := AllocNode(AN_IDENT); ASTIVal[idn] := idx; ASTTk[idn] := Ord(tyPointer);
      asn := AllocNode(AN_ASSIGN); ASTLeft[asn] := idn; ASTRight[asn] := initExpr;
      ASTTk[asn] := Ord(tyPointer);
      seq := AllocNode(AN_SEQ); ASTLeft[seq] := asn; ASTRight[seq] := -1;
      head := seq; tail := seq;
    end;
    Eat(tkSemicolon);
    blk := AllocNode(AN_BLOCK);
    ASTLeft[blk] := head;
    Result := blk;
    Exit;
  end;
  { Multi-declarator support `T *a, b, *c;`: the `*` binds to each declarator, not
    the base. ParseCDeclType folded the FIRST declarator's star into baseTk, so
    recover the pre-star scalar base; each later declarator gets its own stars.
    A pointer from a *literal* star (elemTk known) is redistributable; a pointer
    from a typedef (no star) is the whole type and applies to every sibling. }
  hadStar := (baseTk = tyPointer) and (CTypePtrDepth > 0);
  if hadStar then begin scalarTk := IntToTypeKind(ptrBaseTk); scalarRec := ptrBaseRec; end
  else begin scalarTk := baseTk; scalarRec := CTypeBaseRec; end;
  declTk := baseTk; declElemTk := elemTkOrd; declElemRec := elemRec; declProcSig := procSig;
  declPtrDepth := ptrDepth; declBaseTk := ptrBaseTk; declBaseRec := ptrBaseRec;
  head := -1; tail := -1;
  while True do
  begin
    if CurTok.Kind <> tkIdent then Break;
    name := CurTok.SVal; Next;
    if CurTok.Kind = tkLBrack then
    begin
      { fixed array  T name[N][M]...  — dimensions are constant expressions.
        Storage is flattened row-major for >=2 dimensions and tagged with
        SymArrNDims so chained indexing can rebuild the flat element index. An
        unsized 1-D `[]` (arrLen=-1) is sized from the initializer below. }
      dimCount := 0;
      flatLen := 1;
      while CurTok.Kind = tkLBrack do
      begin
        Next;
        if CurTok.Kind = tkRBrack then dimVal := -1
        else dimVal := CEvalConstExpr;
        Expect(tkRBrack, ']');
        if dimCount >= MAX_ARR_DIMS then Error('too many C array dimensions');
        dimSpan[dimCount] := dimVal;
        Inc(dimCount);
      end;
      if dimCount = 1 then
        arrLen := dimSpan[0]
      else
      begin
        flatLen := 1;
        for di := 0 to dimCount - 1 do
        begin
          if dimSpan[di] < 1 then dimSpan[di] := 1;
          flatLen := flatLen * dimSpan[di];
        end;
        arrLen := flatLen;
      end;
      { An array of structs needs the element record id so AllocArray sizes the
        slot by RecSize, not a default — `struct V a[N]; a[i].f` was using the
        wrong stride. }
      if declTk = tyRecord then LastTypeRecId := scalarRec;
      { Array brace-initializer for scalar/pointer element arrays: parse each
        element expression up front (so an unsized open-bracket array is sized
        from the count) and generate arr-index-k := ek assignments at the
        declaration point. Reuses the C expr lowering, so string-literal / addr /
        cast elements all materialise correctly (this is how lua's
        luaT_eventname char-pointer table gets real data instead of stack
        garbage). Record-element arrays (each element a nested brace group) and
        over-long lists fall back to the balanced-brace skip below. }
      nArrElems := 0;
      if (CurTok.Kind = tkAssign) and (declTk <> tyRecord) and
         (Tokens[TokPos].Kind = tkBegin) and (dimCount >= 2) and
         (declTk <> tyPointer) and TypeIsOrdinal(declTk) then
      begin
        Next; Next;   { consume the assign then the open brace }
        brDepth := 1;
        while (brDepth > 0) and (CurTok.Kind <> tkEOF) do
        begin
          if CurTok.Kind = tkBegin then
          begin
            Inc(brDepth);
            Next;
          end
          else if CurTok.Kind = tkEnd then
          begin
            Dec(brDepth);
            Next;
          end
          else if CurTok.Kind = tkComma then
            Next
          else
          begin
            if nArrElems > 255 then Error('too many C array initializer elements');
            arrElems[nArrElems] := ParseCExpr;
            Inc(nArrElems);
          end;
        end;
      end
      else if (CurTok.Kind = tkAssign) and (declTk <> tyRecord) and
         (Tokens[TokPos].Kind = tkBegin) and (dimCount <= 1) then
      begin
        Next; Next;   { consume the assign then the open brace }
        while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
        begin
          if nArrElems > 255 then begin nArrElems := -1; Break; end;
          arrElems[nArrElems] := ParseCExpr;
          Inc(nArrElems);
          if CurTok.Kind = tkComma then begin Next; Continue; end;
          Break;
        end;
        if nArrElems >= 0 then Expect(tkEnd, '}')
        else begin
          { oversize: finish the balanced-brace skip from wherever we stopped }
          brDepth := 1;
          while (brDepth > 0) and (CurTok.Kind <> tkEOF) do
          begin
            if CurTok.Kind = tkBegin then Inc(brDepth)
            else if CurTok.Kind = tkEnd then Dec(brDepth);
            Next;
          end;
          nArrElems := 0;
        end;
      end;
      if arrLen < 1 then
      begin
        if nArrElems > 0 then arrLen := nArrElems else arrLen := 1;
      end
      else if (dimCount <= 1) and (nArrElems > arrLen) then arrLen := nArrElems;
      idx := AllocArray(name, declTk, 0, arrLen - 1);
      if dimCount >= 2 then
      begin
        SymArrNDims[idx] := dimCount;
        for di := 0 to dimCount - 1 do
        begin
          SymArrDimLo[idx * MAX_ARR_DIMS + di] := 0;
          SymArrDimSpan[idx * MAX_ARR_DIMS + di] := dimSpan[di];
        end;
      end;
      if declTk = tyPointer then
      begin
        Syms[idx].PtrElemTk := IntToTypeKind(declElemTk);
        Syms[idx].PtrElemRec := declElemRec;
        SymPtrDepth[idx] := declPtrDepth;
        SymPtrBaseTk[idx] := declBaseTk;
        SymPtrBaseRec[idx] := declBaseRec;
      end;
      for ei := 0 to nArrElems - 1 do
      begin
        idn := AllocNode(AN_IDENT); ASTIVal[idn] := idx; ASTTk[idn] := Ord(declTk);
        idxLit := AllocNode(AN_INT_LIT); ASTIVal[idxLit] := ei; ASTTk[idxLit] := Ord(tyInteger);
        inode := AllocNode(AN_INDEX); ASTLeft[inode] := idn; ASTRight[inode] := idxLit;
        ASTTk[inode] := Ord(declTk);
        asn := AllocNode(AN_ASSIGN); ASTLeft[asn] := inode; ASTRight[asn] := arrElems[ei];
        ASTTk[asn] := Ord(declTk);
        seq := AllocNode(AN_SEQ); ASTLeft[seq] := asn; ASTRight[seq] := -1;
        if head = -1 then head := seq else ASTRight[tail] := seq;
        tail := seq;
      end;
      { Unconsumed initializer (record-element array, or non-brace): balanced skip. }
      if CurTok.Kind = tkAssign then
      begin
        Next;
        if CurTok.Kind = tkBegin then
        begin
          brDepth := 0;
          repeat
            if CurTok.Kind = tkBegin then Inc(brDepth)
            else if CurTok.Kind = tkEnd then Dec(brDepth);
            Next;
          until (brDepth = 0) or (CurTok.Kind = tkEOF);
        end
        else
          while (CurTok.Kind <> tkComma) and (CurTok.Kind <> tkSemicolon) and
                (CurTok.Kind <> tkEOF) do Next;
      end;
    end
    else
    begin
      { A struct-by-value local needs its record id so field access resolves and
        AllocVar reserves RecSize bytes. }
      if declTk = tyRecord then LastTypeRecId := scalarRec;
      idx := AllocVar(name, declTk);
      if declTk = tyPointer then
      begin
        Syms[idx].PtrElemTk := IntToTypeKind(declElemTk);
        Syms[idx].PtrElemRec := declElemRec;
        SymPtrDepth[idx] := declPtrDepth;
        SymPtrBaseTk[idx] := declBaseTk;
        SymPtrBaseRec[idx] := declBaseRec;
        if declProcSig >= 0 then SymProcSig[idx] := declProcSig;  { fn-pointer var: callable }
      end;
      initExpr := -1;
      if CurTok.Kind = tkAssign then
      begin
        Next;
        if CurTok.Kind = tkBegin then
        begin
          { Aggregate initializer `= { ... }` on a non-array local (e.g.
            `static const expdesc ef = {VKINT, {0}, ...}`): not yet materialised,
            balanced-brace skip so inner commas/braces don't end it early. }
          arrLen := 0;   { reuse as brace depth }
          repeat
            if CurTok.Kind = tkBegin then Inc(arrLen)
            else if CurTok.Kind = tkEnd then Dec(arrLen);
            Next;
          until (arrLen = 0) or (CurTok.Kind = tkEOF);
        end
        else
          initExpr := ParseCExpr;
      end;
      if initExpr >= 0 then
      begin
        idn := AllocNode(AN_IDENT); ASTIVal[idn] := idx; ASTTk[idn] := Ord(declTk);
        asn := AllocNode(AN_ASSIGN); ASTLeft[asn] := idn; ASTRight[asn] := initExpr;
        ASTTk[asn] := Ord(declTk);
        seq := AllocNode(AN_SEQ); ASTLeft[seq] := asn; ASTRight[seq] := -1;
        if head = -1 then head := seq else ASTRight[tail] := seq;
        tail := seq;
      end;
    end;
    if CurTok.Kind = tkComma then
    begin
      Next;
      { next declarator's own pointer level (`*c` in `T *a, b, *c`) }
      declPtr := 0;
      while CurTok.Kind = tkStar do begin Inc(declPtr); Next; end;
      if declPtr > 0 then
      begin
        declTk := tyPointer;
        declPtrDepth := declPtr;
        declBaseTk := Ord(scalarTk);
        declBaseRec := scalarRec;
        if declPtr = 1 then begin declElemTk := Ord(scalarTk); declElemRec := scalarRec; end
        else begin declElemTk := Ord(tyPointer); declElemRec := REC_NONE; end;
        declProcSig := -1;
      end
      else if hadStar then
      begin
        { sibling with no star, base had a redistributable star: plain scalar }
        declTk := scalarTk; declElemTk := Ord(tyUnknown); declElemRec := scalarRec;
        declPtrDepth := 0; declBaseTk := Ord(tyUnknown); declBaseRec := REC_NONE;
        declProcSig := -1;
      end
      else
      begin
        { base carries no redistributable star (plain/typedef): siblings get the
          same full base type + metadata }
        declTk := baseTk; declElemTk := elemTkOrd; declElemRec := elemRec;
        declPtrDepth := ptrDepth; declBaseTk := ptrBaseTk; declBaseRec := ptrBaseRec;
        declProcSig := procSig;
      end;
      Continue;
    end;
    Break;
  end;
  Eat(tkSemicolon);
  blk := AllocNode(AN_BLOCK);
  ASTLeft[blk] := head;   { -1 = empty block, emits nothing }
  Result := blk;
end;

{ A full C expression INCLUDING the top-level comma operator `a, b` — yields an
  AN_COMMA (evaluate left for side effects, value is the right). Used where C
  allows a comma expression: if/while/for conditions. (Function arguments and
  initializer lists keep using ParseCExpr, which stops at a comma separator.) }
function ParseCCommaExpr: Integer;
var node: Integer;
begin
  Result := ParseCExpr;
  while CurTok.Kind = tkComma do
  begin
    Next;
    node := AllocNode(AN_COMMA);
    ASTLeft[node] := Result;
    ASTRight[node] := ParseCExpr;
    ASTTk[node] := ASTTk[ASTRight[node]];
    Result := node;
  end;
end;

function ParseCIfAST: Integer;
var cond, thenS, elseS, node, pair: Integer;
begin
  Next; { if }
  Expect(tkLParen, '(');
  cond := ParseCCommaExpr;
  Expect(tkRParen, ')');
  thenS := ParseCStatementAST;
  elseS := -1;
  if CurTok.Kind = tkElse then begin Next; elseS := ParseCStatementAST; end;
  node := AllocNode(AN_IF);
  ASTLeft[node] := cond;
  pair := AllocNode(AN_PAIR);
  ASTLeft[pair] := thenS;
  ASTRight[pair] := elseS;
  ASTRight[node] := pair;
  Result := node;
end;

function ParseCWhileAST: Integer;
var cond, body, node: Integer;
begin
  Next; { while }
  Expect(tkLParen, '(');
  cond := ParseCCommaExpr;
  Expect(tkRParen, ')');
  body := ParseCStatementAST;
  node := AllocNode(AN_WHILE);
  ASTLeft[node] := cond;
  ASTRight[node] := body;
  Result := node;
end;

{ Build `(e == 0)` as a tyBoolean node — logical negation / `!e`. }
function CMakeIsZero(e: Integer): Integer;
var node, zero: Integer;
begin
  zero := AllocNode(AN_INT_LIT); ASTIVal[zero] := 0; ASTTk[zero] := Ord(tyInteger);
  node := AllocNode(AN_BINOP);
  ASTIVal[node] := Ord(tkEq);
  ASTLeft[node] := e; ASTRight[node] := zero;
  ASTTk[node] := Ord(tyBoolean);
  Result := node;
end;

{ Append `stmt` as a new AN_SEQ node onto a chain; returns the new tail.
  `*head` is set on the first append. }
function CSeqAppend(stmt: Integer; var head, tail: Integer): Integer;
var seq: Integer;
begin
  seq := AllocNode(AN_SEQ); ASTLeft[seq] := stmt; ASTRight[seq] := -1;
  if head = -1 then head := seq else ASTRight[tail] := seq;
  tail := seq;
  Result := seq;
end;

{ `for (init; cond; post) body`.
  - No post: desugars to `init; while (cond) body` (continue->cond is correct).
  - With post: a `continue` must still run `post`, but the loop machinery's
    continue target is the while condition. So we desugar to a constant-true
    loop that runs `post` at the TOP (guarded by a first-iteration flag) before
    re-checking the condition:
        init; first = 1;
        while (1) { if (!first) post; first = 0; if (!cond) break; body; }
    A continue jumps to the while head, runs post, re-checks cond — exactly C
    semantics. An empty cond is constant-true. }
function ParseCForAST: Integer;
var initNode, cond, post, body, loop, whileBody, outer, trueCond: Integer;
    oHead, oTail, bHead, bTail, flagVar, flagSet, flagClr, ifPost, ifBrk, brk: Integer;
    idn1, idn2: Integer;
begin
  Next; { for }
  Expect(tkLParen, '(');

  initNode := -1;
  if CurTok.Kind = tkSemicolon then
    Next
  else if IsCTypeTok then
    initNode := ParseCLocalDeclAST
  else
  begin
    initNode := ParseCCommaStmt;
    Eat(tkSemicolon);
  end;

  if CurTok.Kind = tkSemicolon then
  begin
    cond := AllocNode(AN_INT_LIT); ASTIVal[cond] := 1; ASTTk[cond] := Ord(tyBoolean);
  end
  else
    cond := ParseCCommaExpr;
  Expect(tkSemicolon, ';');

  post := -1;
  if CurTok.Kind <> tkRParen then post := ParseCCommaStmt;
  Expect(tkRParen, ')');

  body := ParseCStatementAST;

  oHead := -1; oTail := -1;
  if initNode >= 0 then CSeqAppend(initNode, oHead, oTail);

  if post < 0 then
  begin
    { simple: while (cond) body }
    loop := AllocNode(AN_WHILE);
    ASTLeft[loop] := cond;
    ASTRight[loop] := body;
    CSeqAppend(loop, oHead, oTail);
  end
  else
  begin
    flagVar := AllocVar('', tyBoolean);

    { first = 1 }
    idn1 := AllocNode(AN_IDENT); ASTIVal[idn1] := flagVar; ASTTk[idn1] := Ord(tyBoolean);
    flagSet := AllocNode(AN_ASSIGN); ASTLeft[flagSet] := idn1;
    ASTRight[flagSet] := AllocNode(AN_INT_LIT); ASTIVal[ASTRight[flagSet]] := 1;
    ASTTk[ASTRight[flagSet]] := Ord(tyInteger); ASTTk[flagSet] := Ord(tyBoolean);
    CSeqAppend(flagSet, oHead, oTail);

    bHead := -1; bTail := -1;

    { if (!first) post  ->  if (first == 0) post }
    idn2 := AllocNode(AN_IDENT); ASTIVal[idn2] := flagVar; ASTTk[idn2] := Ord(tyBoolean);
    ifPost := AllocNode(AN_IF);
    ASTLeft[ifPost] := CMakeIsZero(idn2);
    ASTRight[ifPost] := AllocNode(AN_PAIR);
    ASTLeft[ASTRight[ifPost]] := post;
    ASTRight[ASTRight[ifPost]] := -1;
    CSeqAppend(ifPost, bHead, bTail);

    { first = 0 }
    idn1 := AllocNode(AN_IDENT); ASTIVal[idn1] := flagVar; ASTTk[idn1] := Ord(tyBoolean);
    flagClr := AllocNode(AN_ASSIGN); ASTLeft[flagClr] := idn1;
    ASTRight[flagClr] := AllocNode(AN_INT_LIT); ASTIVal[ASTRight[flagClr]] := 0;
    ASTTk[ASTRight[flagClr]] := Ord(tyInteger); ASTTk[flagClr] := Ord(tyBoolean);
    CSeqAppend(flagClr, bHead, bTail);

    { if (!cond) break }
    ifBrk := AllocNode(AN_IF);
    ASTLeft[ifBrk] := CMakeIsZero(cond);
    brk := AllocNode(AN_BREAK);
    ASTRight[ifBrk] := AllocNode(AN_PAIR);
    ASTLeft[ASTRight[ifBrk]] := brk;
    ASTRight[ASTRight[ifBrk]] := -1;
    CSeqAppend(ifBrk, bHead, bTail);

    { body }
    CSeqAppend(body, bHead, bTail);

    whileBody := AllocNode(AN_BLOCK); ASTLeft[whileBody] := bHead;
    trueCond := AllocNode(AN_INT_LIT); ASTIVal[trueCond] := 1; ASTTk[trueCond] := Ord(tyBoolean);
    loop := AllocNode(AN_WHILE);
    ASTLeft[loop] := trueCond;
    ASTRight[loop] := whileBody;
    CSeqAppend(loop, oHead, oTail);
  end;

  outer := AllocNode(AN_BLOCK);
  ASTLeft[outer] := oHead;
  Result := outer;
end;

{ `do body while (cond);` — body runs once, then repeats while cond. Desugared
  with a first-iteration flag to a constant-checked while so break/continue keep
  C semantics: `flag=1; while (flag || cond) { flag=0; body }`. A continue jumps
  to the while head, where flag is 0, so cond is re-checked (correct). }
function ParseCDoWhileAST: Integer;
var body, cond, flagVar, loop, whileBody, outer: Integer;
    oHead, oTail, bHead, bTail, flagSet, flagClr, orCond, idn1, idn2: Integer;
begin
  Next; { do }
  body := ParseCStatementAST;
  if CurTok.Kind = tkWhile then Next else Error('while expected after do');
  Expect(tkLParen, '(');
  cond := ParseCExpr;
  Expect(tkRParen, ')');
  Eat(tkSemicolon);

  flagVar := AllocVar('', tyBoolean);
  oHead := -1; oTail := -1;

  idn1 := AllocNode(AN_IDENT); ASTIVal[idn1] := flagVar; ASTTk[idn1] := Ord(tyBoolean);
  flagSet := AllocNode(AN_ASSIGN); ASTLeft[flagSet] := idn1;
  ASTRight[flagSet] := AllocNode(AN_INT_LIT); ASTIVal[ASTRight[flagSet]] := 1;
  ASTTk[ASTRight[flagSet]] := Ord(tyInteger); ASTTk[flagSet] := Ord(tyBoolean);
  CSeqAppend(flagSet, oHead, oTail);

  bHead := -1; bTail := -1;
  idn2 := AllocNode(AN_IDENT); ASTIVal[idn2] := flagVar; ASTTk[idn2] := Ord(tyBoolean);
  flagClr := AllocNode(AN_ASSIGN); ASTLeft[flagClr] := idn2;
  ASTRight[flagClr] := AllocNode(AN_INT_LIT); ASTIVal[ASTRight[flagClr]] := 0;
  ASTTk[ASTRight[flagClr]] := Ord(tyInteger); ASTTk[flagClr] := Ord(tyBoolean);
  CSeqAppend(flagClr, bHead, bTail);
  CSeqAppend(body, bHead, bTail);
  whileBody := AllocNode(AN_BLOCK); ASTLeft[whileBody] := bHead;

  idn1 := AllocNode(AN_IDENT); ASTIVal[idn1] := flagVar; ASTTk[idn1] := Ord(tyBoolean);
  orCond := CMakeBinop(Ord(tkOr), idn1, cond);
  loop := AllocNode(AN_WHILE); ASTLeft[loop] := orCond; ASTRight[loop] := whileBody;
  CSeqAppend(loop, oHead, oTail);

  outer := AllocNode(AN_BLOCK); ASTLeft[outer] := oHead;
  Result := outer;
end;

{ A comma-separated expression sequence in statement position (expression
  statement, for-init, for-post): each expression runs for its side effects with
  the value discarded, so it lowers to a block of the expressions as statements.
  A single expression (no comma) returns just that node. }
function ParseCCommaStmt: Integer;
var head, tail, blk: Integer;
begin
  Result := ParseCExpr;
  if CurTok.Kind <> tkComma then Exit;
  head := -1; tail := -1;
  CSeqAppend(Result, head, tail);
  while CurTok.Kind = tkComma do
  begin
    Next;
    CSeqAppend(ParseCExpr, head, tail);
  end;
  blk := AllocNode(AN_BLOCK); ASTLeft[blk] := head;
  Result := blk;
end;

function ParseCStatementAST: Integer;
var node, exprNode: Integer;
begin
  Result := -1;
  if CurTok.Kind = tkEOF then Exit;

  { empty statement }
  if CurTok.Kind = tkSemicolon then
  begin
    Next;
    node := AllocNode(AN_BLOCK); ASTLeft[node] := -1;
    Result := node;
    Exit;
  end;

  { block-scope typedef declaration. C typedefs are compile-time only; register
    the alias and emit an empty statement node. }
  if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'typedef') then
  begin
    ParseCTypedef;
    node := AllocNode(AN_BLOCK);
    ASTLeft[node] := -1;
    Result := node;
    Exit;
  end;

  { local variable declaration }
  if IsCTypeTok then
  begin
    Result := ParseCLocalDeclAST;
    Exit;
  end;

  { return [expr]; — the expression is optional for void functions }
  if CurTok.Kind = tkExit then
  begin
    Next;
    node := AllocNode(AN_EXIT);
    if CurTok.Kind <> tkSemicolon then
      ASTLeft[node] := ParseCExpr
    else
      ASTLeft[node] := -1;
    Eat(tkSemicolon);
    Result := node;
    Exit;
  end;

  if CurTok.Kind = tkIf then begin Result := ParseCIfAST; Exit; end;
  if CurTok.Kind = tkWhile then begin Result := ParseCWhileAST; Exit; end;
  if CurTok.Kind = tkFor then begin Result := ParseCForAST; Exit; end;
  if CurTok.Kind = tkDo then begin Result := ParseCDoWhileAST; Exit; end;
  if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'switch') then
  begin Result := ParseCSwitchAST; Exit; end;

  { `case CONST:` / `default:` labels inside a switch body — emitted as marker
    nodes that the switch lowering turns into dispatch targets. }
  if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'case') then
  begin
    Next;
    node := AllocNode(AN_CASE);
    ASTIVal[node] := CEvalConstExpr;
    Expect(tkColon, ':');
    Result := node;
    Exit;
  end;
  if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'default') then
  begin
    Next;
    Expect(tkColon, ':');
    Result := AllocNode(AN_DEFAULT);
    Exit;
  end;

  { `goto label;` }
  if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'goto') then
  begin
    Next;
    if CurTok.Kind <> tkIdent then Error('expected label name after goto');
    node := AllocNode(AN_GOTO);
    ASTSOffset[node] := Tokens[TokPos - 1].SOffset;
    ASTSLen[node] := Tokens[TokPos - 1].SLen;
    Next;
    Eat(tkSemicolon);
    Result := node;
    Exit;
  end;

  { `label:` — a goto target as a statement (after case/default, which are above) }
  if (CurTok.Kind = tkIdent) and (Tokens[TokPos].Kind = tkColon) then
  begin
    { Register the label name so AN_LABEL/AN_GOTO resolve it (C labels are not
      pre-declared; the table is reset per function in ParseCSubroutine). }
    if GotoLabelCount >= MAX_GOTO_LABELS then Error('too many labels');
    GotoLabelNOff[GotoLabelCount] := Tokens[TokPos - 1].SOffset;
    GotoLabelNLen[GotoLabelCount] := Tokens[TokPos - 1].SLen;
    GotoLabelCodePos[GotoLabelCount] := -1;
    Inc(GotoLabelCount);
    node := AllocNode(AN_LABEL);
    ASTSOffset[node] := Tokens[TokPos - 1].SOffset;
    ASTSLen[node] := Tokens[TokPos - 1].SLen;
    Next; Next;    { consume ident and colon }
    Result := node;
    Exit;
  end;

  if CurTok.Kind = tkBreak then
  begin
    Next; Eat(tkSemicolon);
    Result := AllocNode(AN_BREAK);
    Exit;
  end;
  if CurTok.Kind = tkContinue then
  begin
    Next; Eat(tkSemicolon);
    Result := AllocNode(AN_CONTINUE);
    Exit;
  end;

  { printf(...) as a statement. Prefer a REAL printf if one is linked (the crtl
    stdio veneer over the PAL byte sink — full format engine); only when no
    printf proc is defined does the literal-only AN_WRITE stub apply (a bare C
    program with no crtl: at least the format string still prints). Letting it
    fall through to the expression path makes `name(args)` resolve via FindProc
    to the veneer. }
  if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'printf') and (FindProc('printf') < 0) then
  begin
    Result := ParseCPrintfAST;
    Exit;
  end;

  { nested block }
  if CurTok.Kind = tkBegin then
  begin
    Result := ParseCBlockAST;
    Exit;
  end;

  { expression statement (assignment, call, ++/--, comma sequence) }
  exprNode := ParseCCommaStmt;
  Eat(tkSemicolon);
  Result := exprNode;
end;

function ParseCBlockAST: Integer;
var blockNode, seqNode, stmtNode, lastSeq: Integer;
begin
  Expect(tkBegin, '{');
  blockNode := AllocNode(AN_BLOCK);
  lastSeq := -1;
  while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
  begin
    stmtNode := ParseCStatementAST;
    if stmtNode <> -1 then
    begin
      seqNode := AllocNode(AN_SEQ);
      ASTLeft[seqNode] := stmtNode;
      if lastSeq = -1 then
        ASTLeft[blockNode] := seqNode
      else
        ASTRight[lastSeq] := seqNode;
      lastSeq := seqNode;
    end;
  end;
  Expect(tkEnd, '}');
  Result := blockNode;
end;

{ C `switch (sel) { ... case CONST: ... default: ... }`. The body is parsed like
  a brace block; `case`/`default` arrive as AN_CASE/AN_DEFAULT marker nodes in the
  statement sequence (fallthrough is implicit — bodies run on into the next).
  AN_SWITCH lowering (ir.inc) turns the markers into dispatch targets + a break
  scope. }
function ParseCSwitchAST: Integer;
var node, selNode, bodyNode, seqNode, stmtNode, lastSeq: Integer;
begin
  Next;                          { consume 'switch' }
  Expect(tkLParen, '(');
  selNode := ParseCExpr;
  Expect(tkRParen, ')');
  Expect(tkBegin, '{');
  bodyNode := AllocNode(AN_BLOCK);
  lastSeq := -1;
  while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
  begin
    stmtNode := ParseCStatementAST;
    if stmtNode <> -1 then
    begin
      seqNode := AllocNode(AN_SEQ);
      ASTLeft[seqNode] := stmtNode;
      if lastSeq = -1 then ASTLeft[bodyNode] := seqNode
      else ASTRight[lastSeq] := seqNode;
      lastSeq := seqNode;
    end;
  end;
  Expect(tkEnd, '}');
  node := AllocNode(AN_SWITCH);
  ASTLeft[node] := selNode;
  ASTRight[node] := bodyNode;
  Result := node;
end;

{ True iff the brace initializer at CurTok (the open brace) holds ONLY a flat list
  of integer literals + commas — no nested braces, no identifiers/macros/strings.
  The per-field PendingInit materialiser walks fields positionally and stops at the
  first close brace; a nested union/struct init (lua Node/TValue, whose body opens
  with another brace) would desync the walk on the inner brace, record wrong field
  offsets, and end at the inner close brace — leaving the outer decl misparsed (a
  pre-main crash). So only a flat all-integer struct is materialised; anything
  richer zero-inits + balanced skips. Non-consuming (scans Tokens from the inner
  token). }
function CBraceFlatIntInitCountAt(openIdx: Integer): Integer;
var j, depth: Integer; sawValue: Boolean;
begin
  Result := 0;
  depth := 1;
  sawValue := False;
  j := openIdx + 1;
  while (depth > 0) and (j < TokCount) do
  begin
    case Tokens[j].Kind of
      tkBegin: begin Result := -1; Exit; end;   { nested aggregate -> not flat }
      tkEnd:
        begin
          if (depth = 1) and sawValue then Inc(Result);
          Dec(depth);
        end;
      tkComma:
        begin
          if depth = 1 then
          begin
            if sawValue then Inc(Result);
            sawValue := False;
          end;
        end;
      tkInteger, tkMinus, tkPlus, tkStar, tkSlash, tkMod, tkShl, tkShr, tkAmp,
      tkXor, tkPipe, tkLParen, tkRParen, tkNot, tkIdent:
        { Allowed flat constant-expression tokens. An element may be a full
          integer constant expression — parens, shifts, bitwise ops, and
          identifiers that name enum/macro constants (e.g. lua's
          `luaP_opmodes[] = { opmode(...), ... }`, which expands to
          `(((0)<<7)|...|(iABC))`). The materializer folds each element with
          CEvalConstExpr, so anything it can fold is fine here; tkBegin (nested
          aggregate) and tkString (pointer-array) still bail to their own paths. }
        if depth = 1 then sawValue := True;
      tkString: begin Result := -1; Exit; end;     { string init -> pointer path }
    else
      begin Result := -1; Exit; end;
    end;
    Inc(j);
  end;
  if depth <> 0 then Result := -1;
end;

function CBraceIsFlatIntInit: Boolean;
begin
  Result := CBraceFlatIntInitCountAt(TokPos - 1) >= 0;
end;

function CBraceTopLevelInitCountAt(openIdx: Integer): Integer;
var j, depth: Integer; sawValue: Boolean;
begin
  Result := 0;
  depth := 1;
  sawValue := False;
  j := openIdx + 1;
  while (depth > 0) and (j < TokCount) do
  begin
    case Tokens[j].Kind of
      tkBegin:
        begin
          if depth = 1 then sawValue := True;
          Inc(depth);
        end;
      tkEnd:
        begin
          if depth = 1 then
          begin
            if sawValue then Inc(Result);
            Dec(depth);
          end
          else
            Dec(depth);
        end;
      tkComma:
        if depth = 1 then
        begin
          if sawValue then Inc(Result);
          sawValue := False;
        end;
    else
      if depth = 1 then sawValue := True;
    end;
    Inc(j);
  end;
  if depth <> 0 then Result := -1;
end;

function CConsumeCastProcInit(var procIdx: Integer): Boolean;
{ Consume a global aggregate initializer element of the form
  `(fn_pointer_type)function_name`. File-scope struct-array initializers use the
  lightweight PendingInit recorder rather than the expression parser, so this
  recognizes the cast wrapper and reuses the existing proc-address PendingInit
  kind used by bare function names. }
var openIdx, j, depth, procTok, afterTok: Integer;
begin
  Result := False;
  procIdx := -1;
  if CurTok.Kind <> tkLParen then Exit;

  openIdx := TokPos - 1;
  j := openIdx + 1;
  depth := 1;
  while (j < TokCount) and (depth > 0) do
  begin
    if Tokens[j].Kind = tkLParen then Inc(depth)
    else if Tokens[j].Kind = tkRParen then Dec(depth);
    Inc(j);
  end;
  if depth <> 0 then Exit;

  procTok := j;       { first token after the cast's closing ')' }
  afterTok := j + 1;
  if (procTok >= TokCount) or (Tokens[procTok].Kind <> tkIdent) then Exit;
  if (afterTok < TokCount) and not (Tokens[afterTok].Kind in [tkComma, tkEnd]) then Exit;

  procIdx := FindProc(GetTokenStr(procTok));
  if procIdx < 0 then Exit;

  TokPos := afterTok;
  Next;               { CurTok now points at the delimiter after the function name }
  Result := True;
end;

procedure CSkipCInitElement;
var depth: Integer;
begin
  depth := 0;
  while (CurTok.Kind <> tkEOF) do
  begin
    if (depth = 0) and ((CurTok.Kind = tkComma) or (CurTok.Kind = tkEnd)) then Exit;
    if CurTok.Kind = tkBegin then
      Inc(depth)
    else if CurTok.Kind = tkEnd then
    begin
      if depth = 0 then Exit;
      Dec(depth);
      Next;
      if depth = 0 then Exit;
      Continue;
    end;
    Next;
  end;
end;

{ A top-level global variable definition: <type> name (, name)* ;
  Allocated as zero-initialised BSS (CurProc<0 => skGlobal). Increment-1 scope:
  the slot is reserved and any initialiser is skipped (C zero-inits globals; a
  non-zero constant/runtime initialiser is a follow-up). Re-running across the
  two driver passes is idempotent — a name already present is not re-allocated. }
procedure ParseCGlobalVarDecl;
var baseTk: TTypeKind; name: AnsiString; depth, idx, recBase, fldI, fOff, fTk, fSz: Integer;
    recId, initSymIdx, procIdx: Integer; wasArr: Boolean; initV: Int64;
    negFloat: Boolean; signMask: Int64;
    arrLen, dimCount, nArrElems, flatInitCount, ei: Integer;
    arrOffs, arrLens, arrKind, arrSym: array[0..255] of Integer;
begin
  baseTk := ParseCDeclType;
  recId := CTypeBaseRec;
  { Inline function-pointer (array) global `ret (*name[N])(params) [= {..}];`
    (sqlite's sqlite3BuiltinExtensions[]). ParseCDeclType already consumed the
    whole declarator — the name into CTypeFnPtrName and any `[..]` into
    CTypeFnPtrArrLen — so the name-reading loop below would Break on the `=`/`;`
    and never register the global, leaving every `name[i]` reference folding to a
    bare 0. Register it here (array of callable pointers when bracketed, else a
    scalar callable pointer) and materialise the brace initializer as
    per-element proc-address PendingInits. }
  if (CTypeFnPtrName <> '') and (baseTk = tyPointer) then
  begin
    { Guard on baseTk = tyPointer: a real inline fn-ptr declarator collapses to a
      pointer, whereas a struct/union global whose LAST member is a fn pointer
      (`struct { void (*f)(void); } g;`) leaves CTypeFnPtrName set as leftover but
      yields baseTk = tyRecord — that must fall through to the normal var loop. }
    name := CTypeFnPtrName;
    procIdx := CTypeProcSig;             { the fn-ptr call signature }
    wasArr := (CTypeFnPtrArrLen >= -1);
    nArrElems := 0;
    if (CurTok.Kind = tkAssign) and (Tokens[TokPos].Kind = tkBegin) then
    begin
      Next; Next;                        { consume assign and opening brace }
      while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
      begin
        if nArrElems > 255 then begin nArrElems := -1; Break; end;
        if (CurTok.Kind = tkIdent) and (FindProc(CurTok.SVal) >= 0) then
        begin
          arrKind[nArrElems] := 3;       { proc address }
          arrSym[nArrElems] := FindProc(CurTok.SVal);
          Next;
        end
        else if CConsumeCastProcInit(idx) then
        begin
          arrKind[nArrElems] := 3;       { (cast)proc — same proc-address form }
          arrSym[nArrElems] := idx;
        end
        else if CurTok.Kind = tkIdent then
        begin
          { NULL or another resolvable global pointer; otherwise a null slot. }
          idx := FindSym(CurTok.SVal);
          if (idx >= 0) and (CurTok.SVal <> 'NULL') then
          begin arrKind[nArrElems] := 2; arrSym[nArrElems] := idx; end
          else begin arrKind[nArrElems] := 1; arrSym[nArrElems] := 0; end;
          Next;
        end
        else if CurTok.Kind = tkInteger then
        begin
          arrKind[nArrElems] := 1; arrSym[nArrElems] := CurTok.IVal; Next;
        end
        else
        begin
          arrKind[nArrElems] := 1; arrSym[nArrElems] := 0;
          CSkipCInitElement;
        end;
        Inc(nArrElems);
        if CurTok.Kind = tkComma then begin Next; Continue; end;
        Break;
      end;
      if nArrElems >= 0 then Eat(tkEnd)
      else
      begin
        depth := 1;
        while (depth > 0) and (CurTok.Kind <> tkEOF) do
        begin
          if CurTok.Kind = tkBegin then Inc(depth)
          else if CurTok.Kind = tkEnd then Dec(depth);
          Next;
        end;
        nArrElems := 0;
      end;
    end
    else if CurTok.Kind = tkAssign then
    begin
      { scalar initializer `= expr;` — record a single proc address if it is a
        bare function name, else skip to the terminator (zero default). }
      Next;
      if (CurTok.Kind = tkIdent) and (FindProc(CurTok.SVal) >= 0) then
      begin
        arrKind[0] := 3; arrSym[0] := FindProc(CurTok.SVal); nArrElems := 1; Next;
      end
      else
        while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
    end;
    arrLen := CTypeFnPtrArrLen;
    if wasArr then
    begin
      if arrLen < 1 then
      begin
        if nArrElems > 0 then arrLen := nArrElems else arrLen := 1;
      end
      else if nArrElems > arrLen then arrLen := nArrElems;
    end;
    idx := FindSym(name);
    if (idx >= 0) and (Syms[idx].Kind = skConst) then idx := -1;
    if idx < 0 then
    begin
      if wasArr then idx := AllocArray(name, tyPointer, 0, arrLen - 1)
      else idx := AllocVar(name, tyPointer);
    end;
    if idx >= 0 then
    begin
      { An ARRAY of callable pointers carries its ELEMENT signature in
        SymElemProcSig (the `arr[i](args)` channel) — NOT SymProcSig, which would
        mark the array variable itself as a proc value and make codegen resolve
        `arr` to a code address (corrupt indexing). A SCALAR fn pointer is itself
        callable, so it takes SymProcSig plus the scalar pointee metadata. }
      if wasArr then
      begin
        if procIdx >= 0 then SymElemProcSig[idx] := procIdx;
      end
      else
      begin
        if procIdx >= 0 then SymProcSig[idx] := procIdx;
        Syms[idx].PtrElemTk := tyUnknown;
        Syms[idx].PtrElemRec := REC_NONE;
        SymPtrDepth[idx] := 1;
      end;
    end;
    for ei := 0 to nArrElems - 1 do
    begin
      if (idx >= 0) and (PendingInitCount < MAX_PENDING_INITS) then
      begin
        PendingInitSym[PendingInitCount]  := idx;
        if wasArr then PendingInitElem[PendingInitCount] := ei
        else PendingInitElem[PendingInitCount] := -1;
        PendingInitFLen[PendingInitCount] := 0;
        PendingInitTk[PendingInitCount]   := Ord(tyPointer);
        if arrKind[ei] = 3 then
        begin
          PendingInitFOff[PendingInitCount] := -1;
          PendingInitKind[PendingInitCount] := 2;          { proc address -> AN_PROCADDR }
          PendingInitVal[PendingInitCount]  := arrSym[ei];
        end
        else if arrKind[ei] = 2 then
        begin
          PendingInitFOff[PendingInitCount] := -4;          { address of named global }
          PendingInitKind[PendingInitCount] := 0;
          PendingInitVal[PendingInitCount]  := arrSym[ei];
        end
        else
        begin
          PendingInitFOff[PendingInitCount] := -1;          { NULL / integer literal }
          PendingInitKind[PendingInitCount] := 0;
          PendingInitVal[PendingInitCount]  := arrSym[ei];
        end;
        Inc(PendingInitCount);
      end;
    end;
    Eat(tkSemicolon);
    Exit;
  end;
  while True do
  begin
    if CurTok.Kind <> tkIdent then Break;
    name := CurTok.SVal; Next;
    { Global array dimension(s). Pointer arrays with string-literal initializers
      are materialized below; other arrays still mostly serve as parse/layout
      anchors for now. }
    wasArr := False;
    arrLen := 0;
    dimCount := 0;
    while CurTok.Kind = tkLBrack do
    begin
      wasArr := True;
      Inc(dimCount);
      Next;
      if dimCount = 1 then
      begin
        if CurTok.Kind = tkRBrack then arrLen := -1
        else arrLen := CEvalConstExpr;
        Expect(tkRBrack, ']');
      end
      else
      begin
        depth := 1;
        while (depth > 0) and (CurTok.Kind <> tkEOF) do
        begin
          if CurTok.Kind = tkLBrack then Inc(depth)
          else if CurTok.Kind = tkRBrack then Dec(depth);
          Next;
        end;
      end;
    end;
    nArrElems := 0;
    if (CurTok.Kind = tkAssign) and wasArr and (baseTk = tyPointer) and
       (Tokens[TokPos].Kind = tkBegin) then
    begin
      Next; Next;  { consume assignment and opening initializer token }
      while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
      begin
        if nArrElems > 255 then begin nArrElems := -1; Break; end;
        if CurTok.Kind = tkString then
        begin
          { string-literal element (kind 0): record the token span }
          arrKind[nArrElems] := 0;
          arrOffs[nArrElems] := Tokens[TokPos - 1].SOffset;
          arrLens[nArrElems] := Tokens[TokPos - 1].SLen;
          Next;
          while CurTok.Kind = tkString do
          begin
            arrLens[nArrElems] := arrLens[nArrElems] + Tokens[TokPos - 1].SLen;
            Next;
          end;
        end
        else if CurTok.Kind = tkIdent then
        begin
          { identifier element: `NULL` -> null pointer (kind 1); otherwise the
            name of a global (a `char[]` array decaying to `char*`, or another
            pointer) -> store its address (kind 2). A name we cannot resolve
            falls back to the whole-array skip path. }
          if CurTok.SVal = 'NULL' then
          begin
            arrKind[nArrElems] := 1;
            arrSym[nArrElems] := 0;
          end
          else
          begin
            arrSym[nArrElems] := FindSym(CurTok.SVal);
            if arrSym[nArrElems] < 0 then begin nArrElems := -1; Break; end;
            arrKind[nArrElems] := 2;
          end;
          Next;
        end
        else if CurTok.Kind = tkInteger then
        begin
          { integer-literal element (kind 1): typically `0`/NULL terminator in a
            `char *[]` table. Store the literal value as the pointer bits. }
          arrKind[nArrElems] := 1;
          arrSym[nArrElems] := CurTok.IVal;
          Next;
        end
        else
        begin
          nArrElems := -1;
          Break;
        end;
        Inc(nArrElems);
        if CurTok.Kind = tkComma then begin Next; Continue; end;
        Break;
      end;
      if nArrElems >= 0 then
        Expect(tkEnd, '}')
      else
      begin
        depth := 1;
        while (depth > 0) and (CurTok.Kind <> tkEOF) do
        begin
          if CurTok.Kind = tkBegin then Inc(depth)
          else if CurTok.Kind = tkEnd then Dec(depth);
          Next;
        end;
        nArrElems := 0;
      end;
    end;
    if wasArr then
    begin
      if arrLen < 1 then
      begin
        if nArrElems > 0 then arrLen := nArrElems
        else if (CurTok.Kind = tkAssign) and (Tokens[TokPos].Kind = tkBegin) and
                (baseTk <> tyRecord) and (baseTk <> tyPointer) and
                TypeIsOrdinal(baseTk) then
        begin
          flatInitCount := CBraceFlatIntInitCountAt(TokPos);
          if flatInitCount > 0 then arrLen := flatInitCount else arrLen := 1;
        end
        else if (CurTok.Kind = tkAssign) and (Tokens[TokPos].Kind = tkBegin) and
                (baseTk = tyRecord) then
        begin
          flatInitCount := CBraceTopLevelInitCountAt(TokPos);
          if flatInitCount > 0 then arrLen := flatInitCount else arrLen := 1;
        end
        else arrLen := 1;
      end
      else if nArrElems > arrLen then arrLen := nArrElems;
    end;
    { A struct-typed global needs its record id recorded (AllocVar reads the
      global LastTypeRecId for tyRecord) so field access `gg.f` resolves the
      offset — without this the field always landed at offset 0. }
    if baseTk = tyRecord then LastTypeRecId := recId;
    idx := FindSym(name);
    { A C global must not bind to a Pascal predefined const that only matches
      case-insensitively (e.g. C `stderr` vs the builtin `StdErr` = fd 2):
      assigning its initializer would hit "cannot assign to constant", and C
      names are case-sensitive anyway. Shadow it with a fresh exact-case global
      (the exact-case FindSym pass then resolves uses to the variable). }
    if (idx >= 0) and (Syms[idx].Kind = skConst) then idx := -1;
    if idx < 0 then
    begin
      if wasArr then
        idx := AllocArray(name, baseTk, 0, arrLen - 1)
      else
        idx := AllocVar(name, baseTk);
    end;
    if (idx >= 0) and (baseTk = tyPointer) then
    begin
      Syms[idx].PtrElemTk := IntToTypeKind(CTypeElemTk);
      Syms[idx].PtrElemRec := CTypeElemRec;
      SymPtrDepth[idx] := CTypePtrDepth;
      SymPtrBaseTk[idx] := CTypePtrBaseTk;
      SymPtrBaseRec[idx] := CTypePtrBaseRec;
    end;
    for ei := 0 to nArrElems - 1 do
    begin
      if PendingInitCount < MAX_PENDING_INITS then
      begin
        PendingInitSym[PendingInitCount]  := idx;
        PendingInitElem[PendingInitCount] := ei;
        PendingInitTk[PendingInitCount]   := Ord(tyPointer);
        PendingInitKind[PendingInitCount] := 0;
        if arrKind[ei] = 0 then
        begin
          PendingInitFOff[PendingInitCount] := -3;  { string literal span }
          PendingInitFLen[PendingInitCount] := arrLens[ei];
          PendingInitVal[PendingInitCount]  := arrOffs[ei];
        end
        else if arrKind[ei] = 2 then
        begin
          PendingInitFOff[PendingInitCount] := -4;  { address of named global }
          PendingInitFLen[PendingInitCount] := 0;
          PendingInitVal[PendingInitCount]  := arrSym[ei];
        end
        else
        begin
          PendingInitFOff[PendingInitCount] := -1;  { NULL / integer literal }
          PendingInitFLen[PendingInitCount] := 0;
          PendingInitVal[PendingInitCount]  := arrSym[ei];
        end;
        Inc(PendingInitCount);
      end;
    end;
    if CurTok.Kind = tkAssign then
    begin
      Next;
      { Materialise a non-array struct/union global brace-initializer as per-field
        PendingInit writes (constant values only) — so e.g. lstrlib's nativeendian
        union and small struct globals read correctly at runtime instead of zero.
        Arrays and non-constant inits fall through to the skip path. The PendingInit
        emission resolves a field by NAME, so FOff/FLen carry the field's NAME
        reference (UFldNOff/UFldNLen), which name-resolves to the correct byte
        offset for every field (unions: all at offset 0; structs: each distinct). }
      recBase := -1;
      if (recId >= REC_UCLASS_BASE) and UClsIsRecord[recId - REC_UCLASS_BASE] then
        recBase := UClsFBase[recId - REC_UCLASS_BASE];
      if (CurTok.Kind = tkBegin) and wasArr and (baseTk <> tyRecord) and
         (baseTk <> tyPointer) and TypeIsOrdinal(baseTk) and
         (idx >= 0) and CBraceIsFlatIntInit then
      begin
        Next;   { consume the opening brace }
        ei := 0;
        while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
        begin
          initV := CEvalConstExpr;
          if (ei < arrLen) and (PendingInitCount < MAX_PENDING_INITS) then
          begin
            PendingInitSym[PendingInitCount]  := idx;
            PendingInitElem[PendingInitCount] := ei;
            PendingInitFOff[PendingInitCount] := -1;
            PendingInitFLen[PendingInitCount] := 0;
            PendingInitVal[PendingInitCount]  := initV;
            PendingInitTk[PendingInitCount]   := Ord(baseTk);
            Inc(PendingInitCount);
          end;
          Inc(ei);
          Eat(tkComma);
        end;
        Eat(tkEnd);
      end
      else if (CurTok.Kind = tkBegin) and wasArr and (baseTk = tyRecord) and
         (idx >= 0) and (recBase >= 0) and
         (UClsFCount[recId - REC_UCLASS_BASE] >= 1) then
      begin
        Next;   { consume the outer opening brace }
        ei := 0;
        while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
        begin
          if CurTok.Kind = tkBegin then
          begin
            Next;   { consume element opening brace }
            fldI := 0;
            while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
            begin
              if (ei < arrLen) and (fldI < UClsFCount[recId - REC_UCLASS_BASE]) then
              begin
                fTk := UFldTk[recBase + fldI];
                if (fTk = Ord(tyPointer)) and (CurTok.Kind = tkString) and
                   (PendingInitCount < MAX_PENDING_INITS) then
                begin
                  PendingInitSym[PendingInitCount]  := idx;
                  PendingInitElem[PendingInitCount] := ei;
                  PendingInitFOff[PendingInitCount] := UFldNOff[recBase + fldI];
                  PendingInitFLen[PendingInitCount] := UFldNLen[recBase + fldI];
                  PendingInitVal[PendingInitCount]  := Tokens[TokPos - 1].SOffset;
                  PendingInitValAux[PendingInitCount] := Tokens[TokPos - 1].SLen;
                  PendingInitTk[PendingInitCount]   := fTk;
                  PendingInitKind[PendingInitCount] := 1;
                  Inc(PendingInitCount);
                  Next;
                  while CurTok.Kind = tkString do
                  begin
                    PendingInitValAux[PendingInitCount - 1] :=
                      PendingInitValAux[PendingInitCount - 1] + Tokens[TokPos - 1].SLen;
                    Next;
                  end;
                end
                else if (fTk = Ord(tyPointer)) and (CurTok.Kind = tkIdent) then
                begin
                  procIdx := FindProc(CurTok.SVal);
                  if (procIdx >= 0) and (PendingInitCount < MAX_PENDING_INITS) then
                  begin
                    PendingInitSym[PendingInitCount]  := idx;
                    PendingInitElem[PendingInitCount] := ei;
                    PendingInitFOff[PendingInitCount] := UFldNOff[recBase + fldI];
                    PendingInitFLen[PendingInitCount] := UFldNLen[recBase + fldI];
                    PendingInitVal[PendingInitCount]  := procIdx;
                    PendingInitValAux[PendingInitCount] := 0;
                    PendingInitTk[PendingInitCount]   := fTk;
                    PendingInitKind[PendingInitCount] := 2;
                    Inc(PendingInitCount);
                    Next;
                  end
                  else
                    CSkipCInitElement;
                end
                else if (fTk = Ord(tyPointer)) and CConsumeCastProcInit(procIdx) then
                begin
                  if PendingInitCount < MAX_PENDING_INITS then
                  begin
                    PendingInitSym[PendingInitCount]  := idx;
                    PendingInitElem[PendingInitCount] := ei;
                    PendingInitFOff[PendingInitCount] := UFldNOff[recBase + fldI];
                    PendingInitFLen[PendingInitCount] := UFldNLen[recBase + fldI];
                    PendingInitVal[PendingInitCount]  := procIdx;
                    PendingInitValAux[PendingInitCount] := 0;
                    PendingInitTk[PendingInitCount]   := fTk;
                    PendingInitKind[PendingInitCount] := 2;
                    Inc(PendingInitCount);
                  end;
                end
                else if TypeIsOrdinal(IntToTypeKind(fTk)) and (CurTok.Kind <> tkBegin) then
                begin
                  initV := CEvalConstExpr;
                  if (CurTok.Kind in [tkComma, tkEnd]) and (PendingInitCount < MAX_PENDING_INITS) then
                  begin
                    PendingInitSym[PendingInitCount]  := idx;
                    PendingInitElem[PendingInitCount] := ei;
                    PendingInitFOff[PendingInitCount] := UFldNOff[recBase + fldI];
                    PendingInitFLen[PendingInitCount] := UFldNLen[recBase + fldI];
                    PendingInitVal[PendingInitCount]  := initV;
                    PendingInitValAux[PendingInitCount] := 0;
                    PendingInitTk[PendingInitCount]   := fTk;
                    PendingInitKind[PendingInitCount] := 0;
                    Inc(PendingInitCount);
                  end
                  else
                    CSkipCInitElement;
                end
                else
                  CSkipCInitElement;
              end
              else
                CSkipCInitElement;
              Inc(fldI);
              Eat(tkComma);
            end;
            Eat(tkEnd);
          end
          else
            CSkipCInitElement;
          Inc(ei);
          Eat(tkComma);
        end;
        Eat(tkEnd);
      end
      else if (CurTok.Kind = tkBegin) and (baseTk = tyRecord) and (not wasArr) and
         (idx >= 0) and (recBase >= 0) and
         (UClsFCount[recId - REC_UCLASS_BASE] >= 1) then
      begin
        Next;   { consume the opening brace }
        fldI := 0;
        while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
        begin
          if fldI < UClsFCount[recId - REC_UCLASS_BASE] then
          begin
            fTk := UFldTk[recBase + fldI];
            if CurTok.Kind = tkBegin then
              CSkipCInitElement
            else if TypeIsOrdinal(IntToTypeKind(fTk)) then
            begin
              initV := CEvalConstExpr;
              if (CurTok.Kind in [tkComma, tkEnd]) and (PendingInitCount < MAX_PENDING_INITS) then
              begin
                PendingInitSym[PendingInitCount]  := idx;
                PendingInitElem[PendingInitCount] := -1;
                PendingInitFOff[PendingInitCount] := UFldNOff[recBase + fldI];  { field NAME ref }
                PendingInitFLen[PendingInitCount] := UFldNLen[recBase + fldI];
                PendingInitVal[PendingInitCount]  := initV;
                PendingInitTk[PendingInitCount]   := fTk;
                Inc(PendingInitCount);
              end
              else
                CSkipCInitElement;
            end
            else
              CSkipCInitElement;
          end
          else
            CSkipCInitElement;   { overflow field: skip without materialising }
          Inc(fldI);
          Eat(tkComma);
        end;
        Eat(tkEnd);
      end
      else if CurTok.Kind = tkBegin then
      begin
        { `= { ... }` aggregate initializer: skip with BALANCED braces so inner
          commas (`{{"a",f},{"b",g}}`) don't end it early. }
        depth := 0;
        repeat
          if CurTok.Kind = tkBegin then Inc(depth)
          else if CurTok.Kind = tkEnd then Dec(depth);
          Next;
        until (depth = 0) or (CurTok.Kind = tkEOF);
      end
      else if (not wasArr) and (idx >= 0) and (baseTk <> tyRecord) and
              (baseTk <> tyPointer) and TypeIsOrdinal(baseTk) and
              (CurTok.Kind = tkInteger) and (Tokens[TokPos].Kind in [tkComma, tkSemicolon]) and
              (PendingInitCount < MAX_PENDING_INITS) then
      begin
        { Scalar ordinal global `T x = <int literal>;` -> a direct PendingInit
          assign (no field offset, so the by-name emission path is unaffected),
          run at the start of main. Anything more complex falls through to skip. }
        PendingInitSym[PendingInitCount]  := idx;
        PendingInitElem[PendingInitCount] := -1;
        PendingInitFOff[PendingInitCount] := -1;
        PendingInitFLen[PendingInitCount] := 0;
        PendingInitVal[PendingInitCount]  := CurTok.IVal;
        PendingInitTk[PendingInitCount]   := Ord(baseTk);
        Inc(PendingInitCount);
        Next;
      end
      else if (not wasArr) and (idx >= 0) and TypeIsFloat(baseTk) and
              ((CurTok.Kind = tkFloat) or
               ((CurTok.Kind = tkMinus) and (Tokens[TokPos].Kind = tkFloat)) or
               ((CurTok.Kind = tkPlus) and (Tokens[TokPos].Kind = tkFloat))) and
              (PendingInitCount < MAX_PENDING_INITS) then
      begin
        { Scalar float global `double x = 3.14;` / `float y = -1.5;`.
          Float tokens carry IEEE-754 double bits; replay as AN_FLOAT_LIT at
          main-entry init so normal assignment lowering narrows tySingle slots. }
        negFloat := False;
        if CurTok.Kind = tkMinus then begin negFloat := True; Next; end
        else if CurTok.Kind = tkPlus then Next;
        if Tokens[TokPos].Kind in [tkComma, tkSemicolon] then
        begin
          initV := CurTok.IVal;
          if negFloat then
          begin
            signMask := 1; signMask := signMask shl 63;
            initV := initV xor signMask;
          end;
          PendingInitSym[PendingInitCount]  := idx;
          PendingInitElem[PendingInitCount] := -1;
          PendingInitFOff[PendingInitCount] := -1;
          PendingInitFLen[PendingInitCount] := 0;
          PendingInitVal[PendingInitCount]  := initV;
          PendingInitTk[PendingInitCount]   := Ord(baseTk);
          PendingInitKind[PendingInitCount] := 3;
          Inc(PendingInitCount);
          Next;
        end
        else
          while (CurTok.Kind <> tkComma) and (CurTok.Kind <> tkSemicolon) and
                (CurTok.Kind <> tkEOF) do Next;
      end
      else if (not wasArr) and (idx >= 0) and (baseTk = tyPointer) and
              (CurTok.Kind = tkString) and
              (PendingInitCount < MAX_PENDING_INITS) then
      begin
        { Scalar `char *p = "literal";` (e.g. lua's `const char *const CLIBS =
          "_CLIBS"`). Store the string-literal address into p at main entry
          (FOff = -3 string-span sentinel, Elem = -1 scalar). The assignment
          lowering applies the C string-literal +8 char-pointer adjustment. }
        PendingInitSym[PendingInitCount]  := idx;
        PendingInitElem[PendingInitCount] := -1;
        PendingInitFOff[PendingInitCount] := -3;
        PendingInitFLen[PendingInitCount] := Tokens[TokPos - 1].SLen;
        PendingInitVal[PendingInitCount]  := Tokens[TokPos - 1].SOffset;
        PendingInitTk[PendingInitCount]   := Ord(tyPointer);
        PendingInitKind[PendingInitCount] := 0;
        Inc(PendingInitCount);
        Next;
        while CurTok.Kind = tkString do
        begin
          PendingInitFLen[PendingInitCount - 1] :=
            PendingInitFLen[PendingInitCount - 1] + Tokens[TokPos - 1].SLen;
          Next;
        end;
      end
      else if (not wasArr) and (idx >= 0) and (baseTk = tyPointer) and
              (CurTok.Kind = tkAmp) and (Tokens[TokPos].Kind = tkIdent) and
              (PendingInitCount < MAX_PENDING_INITS) then
      begin
        { Pointer global initialised to the address of another global:
          `T *p = &g;` — the C frontend's std-stream `FILE *stdout =
          &__crtl_stdout` pattern. Record a PendingInit that stores @g into p at
          main entry (Elem = -2 sentinel = address-of-sym; target sym index in
          Val). Only when g is an already-known global and the init is exactly
          `&g` (the token after the name ends the declarator); anything else
          skips, as before. }
        Next;                       { consume '&' -> CurTok = target ident }
        initSymIdx := FindSym(CurTok.SVal);
        if (initSymIdx >= 0) and (Tokens[TokPos].Kind in [tkComma, tkSemicolon]) then
        begin
          PendingInitSym[PendingInitCount]  := idx;
          PendingInitElem[PendingInitCount] := -2;     { address-of-sym sentinel }
          PendingInitFOff[PendingInitCount] := -1;
          PendingInitFLen[PendingInitCount] := 0;
          PendingInitVal[PendingInitCount]  := initSymIdx;
          PendingInitTk[PendingInitCount]   := Ord(tyPointer);
          Inc(PendingInitCount);
          Next;                     { consume target ident }
        end
        else
          while (CurTok.Kind <> tkComma) and (CurTok.Kind <> tkSemicolon) and
                (CurTok.Kind <> tkEOF) do Next;
      end
      else
        while (CurTok.Kind <> tkComma) and (CurTok.Kind <> tkSemicolon) and
              (CurTok.Kind <> tkEOF) do Next;
    end;
    if CurTok.Kind = tkComma then begin Next; Continue; end;
    Break;
  end;
  Eat(tkSemicolon);
end;

{ Classify the top-level item starting at the current token as a function
  (definition or prototype) vs a global variable, WITHOUT consuming it: peek
  the declaration-specifiers + declarator name and test for a following `(`,
  then rewind the token cursor. }
function CTopLevelIsFunc: Boolean;
var savedPos: Integer;
begin
  savedPos := TokPos - 1;          { index of the current token }
  ParseCDeclType;
  if CTypeFnRetIsFunc then
    Result := True
  else
  begin
    if CurTok.Kind = tkIdent then Next;
    Result := (CurTok.Kind = tkLParen);
  end;
  TokPos := savedPos; Next;        { rewind }
end;

{ True when the current top-level token starts a TYPE declaration
  (`typedef …`, `enum …`, or a bare `struct/union [Tag] { … } ;` / forward),
  as opposed to a function or a global variable typed by a struct. }
function CIsTopLevelTypeDecl: Boolean;
begin
  Result := ((CurTok.Kind = tkIdent) and (CurTok.SVal = 'typedef')) or
            ((CurTok.Kind = tkIdent) and (CurTok.SVal = 'enum')) or
            (((CurTok.Kind = tkRecord) or
              ((CurTok.Kind = tkIdent) and (CurTok.SVal = 'union'))) and IsBareStructDecl);
end;

{ Consume a top-level declaration up to and including its terminating `;`,
  balancing any `{ }` (struct body / brace initialiser). Used in pass 2 to skip
  type declarations and globals already processed in pass 1. }
procedure SkipCDeclToSemi;
var depth: Integer;
begin
  depth := 0;
  while CurTok.Kind <> tkEOF do
  begin
    if CurTok.Kind = tkBegin then Inc(depth)
    else if CurTok.Kind = tkEnd then Dec(depth)
    else if (CurTok.Kind = tkSemicolon) and (depth <= 0) then begin Next; Exit; end;
    Next;
  end;
end;

{ C program driver (Slice D): compile EVERY function (not just main) plus
  top-level globals, with forward inter-function calls resolved. Two passes over
  the one token stream:
    pass 1 (CHeaderMode) — register every function signature and reserve every
            global, skipping bodies, so any call resolves regardless of order;
    pass 2 — compile each function body (ParseCSubroutine) and reserve globals
            (idempotent).
  Entry stub (x86-64, matching the pre-existing convention): save rsp, `call
  main`, then exit_group(eax) so main's int return becomes the process code. }
{ Emit the C setjmp/longjmp primitives as raw machine-code stubs and register
  them as __pxx_setjmp/__pxx_longjmp (BodyAddr = stub). lua's error model rides
  setjmp/longjmp; libc's crash here (the jmp_buf arrives NULL through the import),
  so provide them directly. jmp_buf is `long[16]` in setjmp.h, so the C arg decays
  to the buffer ADDRESS in rdi. Layout: [0]=rbx [8]=rbp [16]=r12 [24]=r13 [32]=r14
  [40]=r15 [48]=caller-rsp [56]=return-addr. setjmp returns 0 the first time and
  the longjmp value when jumped to; longjmp restores and resumes the setjmp call
  site. x86-64 only (the desktop lua/sqlite path). }
procedure EmitCSetjmpStubs;
var sjIdx, ljIdx: Integer;
    pn: array[0..1] of AnsiString; pt: array[0..1] of TTypeKind;
begin
  if TargetArch <> TARGET_X86_64 then Exit;
  pn[0] := 'env'; pt[0] := tyPointer;
  sjIdx := RegisterProc('__pxx_setjmp', True, tyInteger, 1, pn, pt);
  Procs[sjIdx].BodyAddr := CodeLen;
  EmitB($48); EmitB($89); EmitB($5F); EmitB($00);              { mov [rdi+0], rbx }
  EmitB($48); EmitB($89); EmitB($6F); EmitB($08);              { mov [rdi+8], rbp }
  EmitB($4C); EmitB($89); EmitB($67); EmitB($10);              { mov [rdi+16], r12 }
  EmitB($4C); EmitB($89); EmitB($6F); EmitB($18);              { mov [rdi+24], r13 }
  EmitB($4C); EmitB($89); EmitB($77); EmitB($20);              { mov [rdi+32], r14 }
  EmitB($4C); EmitB($89); EmitB($7F); EmitB($28);              { mov [rdi+40], r15 }
  EmitB($48); EmitB($8D); EmitB($44); EmitB($24); EmitB($08);  { lea rax, [rsp+8] }
  EmitB($48); EmitB($89); EmitB($47); EmitB($30);              { mov [rdi+48], rax }
  EmitB($48); EmitB($8B); EmitB($04); EmitB($24);              { mov rax, [rsp] }
  EmitB($48); EmitB($89); EmitB($47); EmitB($38);              { mov [rdi+56], rax }
  EmitB($31); EmitB($C0);                                      { xor eax, eax }
  EmitB($C3);                                                  { ret }

  pn[0] := 'env'; pt[0] := tyPointer; pn[1] := 'val'; pt[1] := tyInteger;
  ljIdx := RegisterProc('__pxx_longjmp', False, tyInteger, 2, pn, pt);
  Procs[ljIdx].BodyAddr := CodeLen;
  EmitB($48); EmitB($8B); EmitB($5F); EmitB($00);              { mov rbx, [rdi+0] }
  EmitB($48); EmitB($8B); EmitB($6F); EmitB($08);              { mov rbp, [rdi+8] }
  EmitB($4C); EmitB($8B); EmitB($67); EmitB($10);              { mov r12, [rdi+16] }
  EmitB($4C); EmitB($8B); EmitB($6F); EmitB($18);              { mov r13, [rdi+24] }
  EmitB($4C); EmitB($8B); EmitB($77); EmitB($20);              { mov r14, [rdi+32] }
  EmitB($4C); EmitB($8B); EmitB($7F); EmitB($28);              { mov r15, [rdi+40] }
  EmitB($48); EmitB($8B); EmitB($67); EmitB($30);              { mov rsp, [rdi+48] }
  EmitB($48); EmitB($8B); EmitB($4F); EmitB($38);              { mov rcx, [rdi+56] }
  EmitB($89); EmitB($F0);                                      { mov eax, esi  (val) }
  EmitB($85); EmitB($C0);                                      { test eax, eax }
  EmitB($75); EmitB($02);                                      { jnz +2 }
  EmitB($FF); EmitB($C0);                                      { inc eax  (0 -> 1) }
  EmitB($FF); EmitB($E1);                                      { jmp rcx }
end;

procedure ParseCProgram;
var firstIdx, callPatch, mainIdx: Integer;
begin
  BSS_INITIAL_RSP := BSSSize; Inc(BSSSize, 8);

  { mov [BSS_INITIAL_RSP], rsp }
  EmitB($48); EmitB($89); EmitB($24); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
  { seed C main(argc, argv) from the Linux initial stack: [argc][argv0]... }
  EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP); { mov rax, [BSS_INITIAL_RSP] }
  EmitB($8B); EmitB($38);                                                       { mov edi, [rax] }
  EmitB($48); EmitB($8D); EmitB($70); EmitB($08);                               { lea rsi, [rax+8] }
  { call main (rel32, patched once main's body address is known) }
  EmitB($E8); callPatch := CodeLen; EmitI32(0);
  { mov edi, eax ; mov eax, 231 (exit_group) ; syscall }
  EmitB($89); EmitB($C7);
  EmitB($B8); EmitI32(231);
  EmitB($0F); EmitB($05);

  { Auto-pull the C IO bridge (pxxcio) so the stdio veneer's
    `extern __pxx_write`/`__pxx_read` resolve to bodied Pascal procs over the
    cross-platform PAL — libc-free, one shared IO path with Pascal. Emitted AFTER
    the entry stub (which is the ELF entry at code offset 0 and never falls
    through — it exit_group's), so the unit bodies sit after it, reached only via
    call. Guarded like the Pascal default-RTL pull: skip on bare-metal ESP and
    when default RTL is opted out. }
  if (not NoDefaultRtl) and
     (TargetArch <> TARGET_XTENSA) and (TargetArch <> TARGET_RISCV32) then
    ParseUsesUnit('pxxcio');

  { setjmp/longjmp primitives (lua's error model). After the entry stub, before
    any C body, so __pxx_setjmp/__pxx_longjmp resolve as bodied procs. }
  EmitCSetjmpStubs;

  firstIdx := TokPos - 1;
  CProgramMode := True;

  { pass 1: lay out types, register every function signature, reserve globals }
  CHeaderMode := True;
  while CurTok.Kind <> tkEOF do
  begin
    if CIsTopLevelTypeDecl then
    begin
      if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'typedef') then ParseCTypedef
      else if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'enum') then ParseCEnumDecl
      else ParseCStructDecl;
    end
    else if IsCTypeTok then
    begin
      if CTopLevelIsFunc then ParseCSubroutine
      else ParseCGlobalVarDecl;
    end
    else
      Next;
  end;
  CHeaderMode := False;

  { pass 2: compile function bodies; types/globals already done in pass 1 }
  TokPos := firstIdx; Next;
  while CurTok.Kind <> tkEOF do
  begin
    if CIsTopLevelTypeDecl then
      SkipCDeclToSemi
    else if IsCTypeTok then
    begin
      if CTopLevelIsFunc then ParseCSubroutine
      else SkipCDeclToSemi;
    end
    else
      Next;
  end;

  CProgramMode := False;
  ApplyCallFixups;

  mainIdx := FindProc('main');
  if mainIdx < 0 then Error('main function not found');
  Patch32(callPatch, Procs[mainIdx].BodyAddr - (callPatch + 4));
end;

procedure ParseCSubroutine;
var
  retType, ptype: TTypeKind;
  name, extLib: AnsiString;
  isFunc: Boolean;
  nparams, procIdx, i, idx, patchPos, sz, gli: Integer;
  intIdx, sseIdx, stackOff: Integer;
  retPtrElemTk, retPtrElemRec, retRecId: Integer;
  ptypes: array[0..15] of TTypeKind;
  pnames: array[0..15] of AnsiString;
  pdepths: array[0..15] of Integer;
  pbasetk: array[0..15] of Integer;
  pbaserec: array[0..15] of Integer;
  pelemtk: array[0..15] of Integer;   { pointed-at TTypeKind ordinal per pointer param }
  pelemrec: array[0..15] of Integer;
  precid: array[0..15] of Integer;    { record id per tyRecord param (for isRef field access) }
  pprocsig: array[0..15] of Integer;  { fn-pointer signature Procs[] index per param, else -1 }
  savedSC, savedFS, node, savedCurProc: Integer;
  vaSaveSym, vaSaveRec, vaOverflowSym: Integer;
  parenName, isVariadic, wasNewProc, fnRetIsFunc: Boolean;
begin
  { Default DT_NEEDED soname for an external with no explicit library: math
    functions are in libm.so.6 on glibc, everything else in libc.so.6. }
  extLib := 'libc.so.6';
  retType := ParseCDeclType;
  { Capture the return type's pointed-at type so `f()^`, `f()^.field`, `f()[i]`
    on a typed-pointer result resolve the element. }
  retPtrElemTk := Ord(tyUnknown);
  retPtrElemRec := REC_NONE;
  if (retType = tyPointer) and
     ((CTypePtrDepth > 0) or (CTypeElemTk <> Ord(tyUnknown))) then
  begin
    retPtrElemTk := CTypeElemTk;
    retPtrElemRec := CTypeElemRec;
  end;
  { An aggregate return type (`struct S f(...)`) carries its record id in
    CTypeBaseRec; capture it before param parsing overwrites CTypeBaseRec, so the
    proc records ProcRetRecId and the hidden Result slot is sized to the record
    (without it the slot was 0/garbage-sized and a by-value struct/union return —
    e.g. lua's `union { double n; long i; }` setobj path — segfaulted). }
  retRecId := REC_NONE;
  if retType = tyRecord then retRecId := CTypeBaseRec;
  if CTypeIsVoid then retType := tyInteger; { void return: value slot unused }
  fnRetIsFunc := CTypeFnRetIsFunc;
  if fnRetIsFunc then
  begin
    name := CTypeFnPtrName;
    nparams := CTypeFnRetParamCount;
    isVariadic := False;
    for i := 0 to nparams - 1 do
    begin
      ptypes[i] := CTypeFnRetPTypes[i];
      pnames[i] := CTypeFnRetPNames[i];
      pdepths[i] := CTypeFnRetPDepths[i];
      pbasetk[i] := CTypeFnRetPBaseTk[i];
      pbaserec[i] := CTypeFnRetPBaseRec[i];
      pelemtk[i] := CTypeFnRetPElemTk[i];
      pelemrec[i] := CTypeFnRetPElemRec[i];
      precid[i] := CTypeFnRetPRecId[i];
      pprocsig[i] := CTypeFnRetPProcSig[i];
    end;
  end;

  { A parenthesized declarator name `(name)(params)` — lua.h declares its whole
    API this way (`LUA_API int (lua_gettop) (lua_State *L);`). Unwrap the redundant
    parens so the name + param list parse normally. Distinct from `(*name)(...)`
    (a function pointer), which ParseCDeclType already consumes. }
  parenName := False;
  if (not fnRetIsFunc) and (CurTok.Kind = tkLParen) and
     (Tokens[TokPos].Kind = tkIdent) and (Tokens[TokPos+1].Kind = tkRParen) then
  begin
    parenName := True;
    Next;   { consume '(' — CurTok is now the name }
  end;

  if (not fnRetIsFunc) and (CurTok.Kind <> tkIdent) then
  begin
    while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
    Eat(tkSemicolon);
    Exit;
  end;
  if not fnRetIsFunc then
  begin
    name := CurTok.SVal;
    Next;
  end;
  extLib := 'libc.so.6';
  if (name = 'pow') or (name = 'sqrt') or (name = 'fmod') or (name = 'floor') or
     (name = 'ceil') or (name = 'fabs') or (name = 'sin') or (name = 'cos') or
     (name = 'tan') or (name = 'asin') or (name = 'acos') or (name = 'atan') or
     (name = 'atan2') or (name = 'exp') or (name = 'log') or (name = 'frexp') or
     (name = 'ldexp') or (name = 'sinh') or (name = 'cosh') or (name = 'tanh') then
    extLib := 'libm.so.6';
  if (not fnRetIsFunc) and parenName then Eat(tkRParen);   { consume the ')' wrapping the name }

  if (not fnRetIsFunc) and (CurTok.Kind <> tkLParen) then
  begin
    while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
    Eat(tkSemicolon);
    Exit;
  end;
  if not fnRetIsFunc then
  begin
    Expect(tkLParen, '(');
    nparams := 0;
    isVariadic := False;
    while (CurTok.Kind <> tkRParen) and (CurTok.Kind <> tkEOF) do
    begin
      if CurTok.Kind = tkDot then isVariadic := True;   { `...` lexes to three tkDot }
      if IsCTypeTok then
      begin
        ptype := ParseCDeclType;
        if CTypeIsVoid then
        begin
          { `(void)` empty parameter list — no actual parameter }
        end
        else if nparams <= 15 then
        begin
          ptypes[nparams] := ptype;
          pdepths[nparams] := CTypePtrDepth;
          pbasetk[nparams] := CTypePtrBaseTk;
          pbaserec[nparams] := CTypePtrBaseRec;
          pelemtk[nparams] := CTypeElemTk;
          pelemrec[nparams] := CTypeElemRec;
          precid[nparams] := CTypeBaseRec;     { record id for a tyRecord param }
          pprocsig[nparams] := CTypeProcSig;   { fn-pointer param: callable in the body }
          if CTypeFnPtrName <> '' then
          begin
            { Inline function-pointer parameter `RET (*name)(params)` — ParseCDeclType
              consumed the whole declarator and captured the name, so the ident-read
              below would miss it and the param would be registered as `argN`, leaving
              a body reference to `name` undeclared (sqlite3ThreadCreate's xTask).
              ParseCDeclType folds the fn-ptr into tyPointer with CTypeProcSig set. }
            pnames[nparams] := CTypeFnPtrName;
          end
          else if CurTok.Kind = tkIdent then
          begin
            pnames[nparams] := CurTok.SVal;
            Next;
          end
          else
          begin
            pnames[nparams] := 'arg0';
            pnames[nparams][4] := Chr(Ord('0') + nparams);
          end;
          { C array parameter `T name[...]` decays to a pointer `T *name` (lua
            ltable `computesizes(unsigned int nums[], ...)`). Consume the bracket
            dimension(s) and retype the param as pointer-to-element. }
          if CurTok.Kind = tkLBrack then
          begin
            while CurTok.Kind = tkLBrack do
            begin
              sz := 0;   { reuse as bracket depth }
              repeat
                if CurTok.Kind = tkLBrack then Inc(sz)
                else if CurTok.Kind = tkRBrack then Dec(sz);
                Next;
              until (sz = 0) or (CurTok.Kind = tkEOF);
            end;
            if pdepths[nparams] = 0 then
            begin
              pelemtk[nparams] := Ord(ptypes[nparams]);
              pelemrec[nparams] := CTypeBaseRec;
              pbasetk[nparams] := Ord(ptypes[nparams]);
              pbaserec[nparams] := CTypeBaseRec;
              pdepths[nparams] := 1;
            end
            else
            begin
              pelemtk[nparams] := Ord(tyPointer);   { `T *name[]` -> pointer-to-pointer }
              Inc(pdepths[nparams]);
            end;
            ptypes[nparams] := tyPointer;
          end;
          Inc(nparams);
        end;
      end
      else
        Next;
      Eat(tkComma);
    end;
    Expect(tkRParen, ')');
  end;
  
  isFunc := True; { In C, everything is a function }
  
  { Register or locate Proc }
  procIdx := FindProc(name);
  wasNewProc := procIdx < 0;
  if wasNewProc then
    procIdx := RegisterProc(name, isFunc, retType, nparams, pnames, ptypes);
  { A C extern can bind by name to an existing PASCAL proc (case-insensitive
    FindProc): lua's <math.h> `sqrt`/`exp`/`sin`/... resolve to the RTL math
    routines. Such a proc keeps its Pascal internal calling convention — marking
    it cdecl here would route the call through the SysV path (floats in XMM) while
    the Pascal prologue reads its params from GP registers, so every double arg
    arrived garbage (sqrt(16)->0, ln(2)->junk). Only a genuinely new C-declared
    proc is cdecl. }
  if wasNewProc then
  begin
    ProcVariadic[procIdx] := isVariadic;
    ProcCdecl[procIdx] := True;
    ProcNamedGP[procIdx] := nparams;   { variadic C fns take only GP named params (L, fmt) }
  end;
  for i := 0 to nparams - 1 do
    ProcParamPtrDepth[procIdx * 16 + i] := pdepths[i];
  ProcRetPtrElemTk[procIdx] := retPtrElemTk;
  ProcRetPtrElemRec[procIdx] := retPtrElemRec;
  if retType = tyRecord then ProcRetRecId[procIdx] := retRecId;

  { If it is just a declaration (ends with ';'), we are done! }
  while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkBegin) and
        (CurTok.Kind <> tkEOF) do Next;
  if CurTok.Kind = tkSemicolon then
  begin
    { Pure declaration (prototype). Mark external EXCEPT in a C-program pass 2,
      where pass 1 already settled linkage (a prototype + a later local
      definition => internal); re-marking here, before that definition is
      recompiled, would make an intervening caller emit an external call. Also
      EXCEPT when the name already resolves to a bodied proc (BodyAddr>=0): an
      auto-pulled Pascal unit (pxxcio's __pxx_write/__pxx_read) supplied the
      definition, so the C `extern` is just a forward view of it — keep it
      internal, not a dynamic libc import. }
    if (not (CProgramMode and not CHeaderMode)) and (Procs[procIdx].BodyAddr < 0) then
    begin
      ProcExternal[procIdx] := True;
      if CurrentCLibrary <> '' then ProcLibrary[procIdx] := InternStr(CurrentCLibrary)
      else ProcLibrary[procIdx] := InternStr(extLib);   { libm for math, else libc }
    end;
    Next;
    Exit;
  end;

  if CHeaderMode then
  begin
    { A bodied function in a C program is a local definition compiled in pass 2;
      mark it internal now so a caller compiled earlier emits a fixup (internal)
      call, not an external one. In true header-import mode bodies stay external. }
    if CProgramMode then
      ProcExternal[procIdx] := False
    else
    begin
      ProcExternal[procIdx] := True;
      if CurrentCLibrary <> '' then ProcLibrary[procIdx] := InternStr(CurrentCLibrary)
      else ProcLibrary[procIdx] := InternStr(extLib);
    end;
    SkipBraceBlock;
    Exit;
  end;
  
  { Otherwise, it has a body! }
  ProcExternal[procIdx] := False;
  Procs[procIdx].BodyAddr := CodeLen;
  
  { Save scope }
  savedSC := SymCount;
  savedFS := FrameSize;
  FrameSize := 0;
  CurProc := procIdx;
  { Reset the goto-label table per function (C labels are registered inline as
    `label:` is parsed; names are function-scoped). }
  GotoLabelCount := 0;
  GotoFixupCount := 0;
  for gli := 0 to MAX_GOTO_LABELS - 1 do GotoLabelIRId[gli] := -1;
  Procs[procIdx].ScopeBase := SymCount;
  
  { Allocate parameter slots }
  for i := 0 to nparams-1 do
  begin
    { A C record param is by-value but passed via the by-ref ABI (an 8-byte
      pointer slot the callee derefs); the caller copies the record to a temp and
      passes &temp (IRLowerCallArg), giving true by-value with correct field
      access for records of ANY size (the inline 8-byte slot could not hold >8B). }
    if ptypes[i] = tyRecord then
    begin
      LastTypeRecId := precid[i];
      idx := AllocParam(pnames[i], ptypes[i], True, False);
    end
    else
      idx := AllocParam(pnames[i], ptypes[i], False, False);
    Procs[procIdx].Params[i].SymIdx := idx;
    { Thread a pointer parameter's pointed-at type so `*p`, `p[i]`, and pointer
      arithmetic inside the body know the element stride/width. }
    if ptypes[i] = tyPointer then
    begin
      Syms[idx].PtrElemTk := IntToTypeKind(pelemtk[i]);
      Syms[idx].PtrElemRec := pelemrec[i];
      SymPtrDepth[idx] := pdepths[i];
      SymPtrBaseTk[idx] := pbasetk[i];
      SymPtrBaseRec[idx] := pbaserec[i];
      if pprocsig[i] >= 0 then SymProcSig[idx] := pprocsig[i];  { fn-pointer param: callable }
    end;
  end;
  
  { Return value slot }
  if retType = tyRecord then LastTypeRecId := retRecId;
  AllocVar('Result', retType);
  Procs[procIdx].RetSymIdx := SymCount - 1;
  Syms[SymCount-1].Kind := skLocal;

  { Aggregate (struct/union by value) return: allocate the hidden destination
    pointer local, exactly like a Pascal record-returning routine. The prologue
    stashes the caller's dest pointer here (EmitAggregateDestStash) and the
    epilogue copies Result into it; the caller's cdecl call path loads it into
    the indirect-result register. Without this a by-value struct/union return
    (lua's TValue union) wrote Result to a garbage pointer and segfaulted. }
  if TypeIsAggregate(retType) then
    ProcAggregateDestSym[procIdx] := AllocVar('', tyPointer);

  { Variadic: reserve a 176-byte register-save area as a hidden local `__va_save`
    plus `__va_overflow`, the caller stack overflow pointer. The prologue stores
    incoming GP+XMM arg registers in __va_save and rbp+16 in __va_overflow. }
  vaSaveSym := -1;
  vaOverflowSym := -1;
  if ProcVariadic[procIdx] then
  begin
    vaSaveRec := FindCTag('__pxx_va_save');
    if vaSaveRec >= 0 then
    begin
      LastTypeRecId := vaSaveRec;
      vaSaveSym := AllocVar('__va_save', tyRecord);
      vaOverflowSym := AllocVar('__va_overflow', tyPointer);
    end;
  end;

  { Prologue }
  patchPos := EmitProcPrologue;
  Procs[procIdx].FramePatch := patchPos;
  EmitAggregateDestStash(procIdx);

  { Variadic register-save prologue (System V): store the 6 GP + 8 XMM arg
    registers into __va_save so va_arg can read the variadic args. Registers are
    still pristine here (the param copy below only reads them). Additive + gated
    to variadic functions, so non-variadic / Pascal codegen is unchanged. }
  if vaSaveSym >= 0 then
  begin
    EmitB($48); EmitB($8D); EmitB($85); EmitI32(16);                          { lea rax, [rbp+16] }
    EmitB($48); EmitB($89); EmitB($85); EmitI32(Syms[vaOverflowSym].Offset);   { mov [rbp+o], rax }
    EmitB($48); EmitB($89); EmitB($BD); EmitI32(Syms[vaSaveSym].Offset + 0);    { mov [rbp+o], rdi }
    EmitB($48); EmitB($89); EmitB($B5); EmitI32(Syms[vaSaveSym].Offset + 8);    { rsi }
    EmitB($48); EmitB($89); EmitB($95); EmitI32(Syms[vaSaveSym].Offset + 16);   { rdx }
    EmitB($48); EmitB($89); EmitB($8D); EmitI32(Syms[vaSaveSym].Offset + 24);   { rcx }
    EmitB($4C); EmitB($89); EmitB($85); EmitI32(Syms[vaSaveSym].Offset + 32);   { r8 }
    EmitB($4C); EmitB($89); EmitB($8D); EmitI32(Syms[vaSaveSym].Offset + 40);   { r9 }
    EmitB($F2); EmitB($0F); EmitB($11); EmitB($85); EmitI32(Syms[vaSaveSym].Offset + 48);   { movsd [rbp+o], xmm0 }
    EmitB($F2); EmitB($0F); EmitB($11); EmitB($8D); EmitI32(Syms[vaSaveSym].Offset + 64);   { xmm1 }
    EmitB($F2); EmitB($0F); EmitB($11); EmitB($95); EmitI32(Syms[vaSaveSym].Offset + 80);   { xmm2 }
    EmitB($F2); EmitB($0F); EmitB($11); EmitB($9D); EmitI32(Syms[vaSaveSym].Offset + 96);   { xmm3 }
    EmitB($F2); EmitB($0F); EmitB($11); EmitB($A5); EmitI32(Syms[vaSaveSym].Offset + 112);  { xmm4 }
    EmitB($F2); EmitB($0F); EmitB($11); EmitB($AD); EmitI32(Syms[vaSaveSym].Offset + 128);  { xmm5 }
    EmitB($F2); EmitB($0F); EmitB($11); EmitB($B5); EmitI32(Syms[vaSaveSym].Offset + 144);  { xmm6 }
    EmitB($F2); EmitB($0F); EmitB($11); EmitB($BD); EmitI32(Syms[vaSaveSym].Offset + 160);  { xmm7 }
  end;

  { Copy SysV argument locations to local parameter slots. Integer and SSE
    classes have independent register counts; overflow args are 8-byte stack
    slots starting at [rbp+16]. }
  intIdx := 0;
  sseIdx := 0;
  stackOff := 16;
  for i := 0 to nparams-1 do
  begin
    idx := Procs[procIdx].Params[i].SymIdx;
    sz := ParamSize(idx);
    if TypeIsFloat(ptypes[i]) and (not Syms[idx].IsRef) and (not Syms[idx].IsArray) then
    begin
      if sseIdx < 8 then
      begin
        if ptypes[i] = tySingle then EmitB($F3) else EmitB($F2);
        EmitB($0F); EmitB($11);
        case sseIdx of
          0: EmitB($85);
          1: EmitB($8D);
          2: EmitB($95);
          3: EmitB($9D);
          4: EmitB($A5);
          5: EmitB($AD);
          6: EmitB($B5);
          7: EmitB($BD);
        end;
        EmitI32(Syms[idx].Offset);
        Inc(sseIdx);
        Continue;
      end
      else
      begin
        EmitB($48); EmitB($8B); EmitB($85); EmitI32(stackOff); { mov rax, [rbp+stackOff] }
        Inc(stackOff, 8);
        if ptypes[i] = tySingle then
        begin
          EmitB($66); EmitB($48); EmitB($0F); EmitB($6E); EmitB($C0); { movq xmm0, rax }
          EmitB($F2); EmitB($0F); EmitB($5A); EmitB($C0);             { cvtsd2ss xmm0, xmm0 }
          EmitB($F3); EmitB($0F); EmitB($11); EmitB($85); EmitI32(Syms[idx].Offset); { movss [rbp+off], xmm0 }
          Continue;
        end;
      end;
    end
    else if intIdx >= 6 then
    begin
      EmitB($48); EmitB($8B); EmitB($85); EmitI32(stackOff); { mov rax, [rbp+stackOff] }
      Inc(stackOff, 8);
      if sz = 1 then
      begin
        EmitB($88); EmitB($85);                   { mov [rbp+off], al }
      end
      else if sz = 2 then
      begin
        EmitB($66); EmitB($89); EmitB($85);       { mov [rbp+off], ax }
      end
      else if sz = 4 then
      begin
        EmitB($89); EmitB($85);                   { mov [rbp+off], eax }
      end
      else
      begin
        EmitB($48); EmitB($89); EmitB($85);       { mov [rbp+off], rax }
      end;
      EmitI32(Syms[idx].Offset);
      Continue;
    end;

    if intIdx < 4 then
    begin
      if sz = 1 then
      begin
        if (intIdx = 0) or (intIdx = 1) then EmitB($40); { REX prefix for dil, sil }
        EmitB($88);
      end
      else if sz = 2 then
      begin
        EmitB($66); EmitB($89);
      end
      else if sz = 4 then
      begin
        EmitB($89);
      end
      else
      begin
        EmitB($48); EmitB($89);
      end;

      case intIdx of
        0: EmitB($BD);   { rdi }
        1: EmitB($B5);   { rsi }
        2: EmitB($95);   { rdx }
        3: EmitB($8D);   { rcx }
      end;
      EmitI32(Syms[idx].Offset);
    end
    else if intIdx = 4 then
    begin
      if sz = 1 then
      begin
        EmitB($44); EmitB($88); EmitB($85);
      end
      else if sz = 2 then
      begin
        EmitB($66); EmitB($44); EmitB($89); EmitB($85);
      end
      else if sz = 4 then
      begin
        EmitB($44); EmitB($89); EmitB($85);
      end
      else
      begin
        EmitB($4C); EmitB($89); EmitB($85);
      end;
      EmitI32(Syms[idx].Offset);
    end
    else if intIdx = 5 then
    begin
      if sz = 1 then
      begin
        EmitB($44); EmitB($88); EmitB($8D);
      end
      else if sz = 2 then
      begin
        EmitB($66); EmitB($44); EmitB($89); EmitB($8D);
      end
      else if sz = 4 then
      begin
        EmitB($44); EmitB($89); EmitB($8D);
      end
      else
      begin
        EmitB($4C); EmitB($89); EmitB($8D);
      end;
      EmitI32(Syms[idx].Offset);
    end;
    Inc(intIdx);
  end;
  
  { Constant global initializers (struct/union brace inits recorded as PendingInit
    during pass 1) run once at the start of `main`, before user code — the C
    analogue of the Pascal program's pre-body CompilePendingGlobalInits. }
  if name = 'main' then CompilePendingGlobalInits;

  { Parse & Compile Body }
  node := ParseCBlockAST;
  CompileAST(node);

  { Epilogue }
  EmitProcEpilog(Procs[procIdx].RetSymIdx);
  PatchProcPrologue(patchPos, FrameSize);
  
  { Restore scope }
  SymCount := savedSC;
  FrameSize := savedFS;
  CurProc := -1;
end;

{ Consume a balanced brace-delimited block. CurTok must be at the opening
  tkBegin; on return CurTok is just past the matching closing brace. }
procedure SkipBraceBlock;
var depth: Integer;
begin
  depth := 0;
  repeat
    if CurTok.Kind = tkBegin then Inc(depth)
    else if CurTok.Kind = tkEnd then Dec(depth);
    Next;
  until (depth = 0) or (CurTok.Kind = tkEOF);
end;

{ Integer constant-expression evaluator for enum values. Operates on the live
  C token stream. Since Slice A the C lexer emits distinct operator tokens:
  `<<`=tkShl, `>>`=tkShr, `|`=tkPipe, `^`=tkXor, `&`=tkAmp.
  Precedence, low to high: | , ^ , & , << >> , + - , * , unary , primary.
  Unknown/unsupported tokens evaluate to 0 rather than derailing.
  (CEvalConstExpr is forward-declared at the top of the C parser.) }

function CEvalConstOffsetofAddress: Int64;
var parenDepth, recId: Integer;
    fieldName, savedFnPtrName: AnsiString;
    savedIsVoid, savedFnRetIsFunc: Boolean;
    savedPtrDepth, savedElemTk, savedElemRec, savedPtrBaseTk, savedPtrBaseRec: Integer;
    savedBaseRec, savedProcSig, savedFnPtrNameOff, savedFnPtrNameLen: Integer;
    savedFnRetParamCount: Integer;
begin
  Result := 0;
  recId := REC_NONE;
  parenDepth := 0;
  while CurTok.Kind <> tkEOF do
  begin
    if CurTok.Kind = tkLParen then
    begin
      Next;
      Inc(parenDepth);
      if IsCTypeTok then
      begin
        savedIsVoid := CTypeIsVoid;
        savedPtrDepth := CTypePtrDepth;
        savedElemTk := CTypeElemTk;
        savedElemRec := CTypeElemRec;
        savedPtrBaseTk := CTypePtrBaseTk;
        savedPtrBaseRec := CTypePtrBaseRec;
        savedBaseRec := CTypeBaseRec;
        savedProcSig := CTypeProcSig;
        savedFnPtrName := CTypeFnPtrName;
        savedFnPtrNameOff := CTypeFnPtrNameOff;
        savedFnPtrNameLen := CTypeFnPtrNameLen;
        savedFnRetIsFunc := CTypeFnRetIsFunc;
        savedFnRetParamCount := CTypeFnRetParamCount;
        ParseCDeclType;
        recId := CTypeBaseRec;
        CTypeIsVoid := savedIsVoid;
        CTypePtrDepth := savedPtrDepth;
        CTypeElemTk := savedElemTk;
        CTypeElemRec := savedElemRec;
        CTypePtrBaseTk := savedPtrBaseTk;
        CTypePtrBaseRec := savedPtrBaseRec;
        CTypeBaseRec := savedBaseRec;
        CTypeProcSig := savedProcSig;
        CTypeFnPtrName := savedFnPtrName;
        CTypeFnPtrNameOff := savedFnPtrNameOff;
        CTypeFnPtrNameLen := savedFnPtrNameLen;
        CTypeFnRetIsFunc := savedFnRetIsFunc;
        CTypeFnRetParamCount := savedFnRetParamCount;
        if CurTok.Kind = tkRParen then
        begin
          Next;
          Dec(parenDepth);
        end;
      end;
    end
    else if CurTok.Kind = tkRParen then
    begin
      if parenDepth > 0 then Dec(parenDepth);
      Next;
    end
    else if CurTok.Kind = tkDot then
    begin
      Next;
      if CurTok.Kind = tkIdent then
      begin
        fieldName := CurTok.SVal;
        if recId <> REC_NONE then Result := RecFieldOffset(recId, fieldName);
        Next;
      end;
      while (parenDepth > 0) and (CurTok.Kind = tkRParen) do
      begin
        Dec(parenDepth);
        Next;
      end;
      Exit;
    end
    else
      Next;
  end;
end;

function CEvalConstPrimary: Int64;
var idx: Integer;
begin
  Result := 0;
  if CurTok.Kind = tkLParen then
  begin
    Next;
    if IsCTypeTok then
    begin
      { cast `(type)expr` in a constant expression — the integer value is
        unchanged for const-folding (lua's cast_int(...) = ((int)(...))). Skip the
        cast type tokens to the matching `)`, then fold the operand. NOTE the `()`
        on the recursive call: bare `CEvalConstPrimary` would read this function's
        own Result, not recurse. }
      while (CurTok.Kind <> tkRParen) and (CurTok.Kind <> tkEOF) do Next;
      if CurTok.Kind = tkRParen then Next;
      Result := CEvalConstPrimary();
    end
    else
    begin
      Result := CEvalConstExpr;
      if CurTok.Kind = tkRParen then Next;
    end;
  end
  else if CurTok.Kind = tkMinus then begin Next; Result := -CEvalConstPrimary(); end
  else if CurTok.Kind = tkPlus then begin Next; Result := CEvalConstPrimary(); end
  else if CurTok.Kind = tkNot then begin Next; Result := CEvalConstPrimary() xor (-1); end  { ~ : bitwise NOT (xor -1 sidesteps the `not <call>`=boolean typing quirk) }
  else if CurTok.Kind = tkAmp then begin Next; Result := CEvalConstOffsetofAddress(); end
  else if CurTok.Kind = tkInteger then begin Result := CurTok.IVal; Next; end
  else if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'sizeof') then
    { `sizeof(type|expr)` in a constant expression (e.g. array dimension
      `char b[3 * sizeof(size_t)]`). Reuse the value-form folder. }
    Result := ASTIVal[ParseCSizeof]
  else if CurTok.Kind = tkIdent then
  begin
    idx := FindSym(CurTok.SVal);
    if (idx >= 0) and (Syms[idx].Kind = skConst) then Result := Syms[idx].ConstVal;
    Next;
  end;
end;

function CEvalConstMul: Int64;
var rhs: Int64;
begin
  Result := CEvalConstPrimary;
  while (CurTok.Kind = tkStar) or (CurTok.Kind = tkSlash) or (CurTok.Kind = tkMod) do
  begin
    if CurTok.Kind = tkStar then begin Next; Result := Result * CEvalConstPrimary; end
    else if CurTok.Kind = tkSlash then
    begin
      Next; rhs := CEvalConstPrimary;
      if rhs <> 0 then Result := Result div rhs else Result := 0;   { e.g. sizeof(a)/sizeof(a[0]) }
    end
    else
    begin
      Next; rhs := CEvalConstPrimary;
      if rhs <> 0 then Result := Result mod rhs else Result := 0;
    end;
  end;
end;

function CEvalConstAdd: Int64;
begin
  Result := CEvalConstMul;
  while (CurTok.Kind = tkPlus) or (CurTok.Kind = tkMinus) do
  begin
    if CurTok.Kind = tkPlus then begin Next; Result := Result + CEvalConstMul; end
    else begin Next; Result := Result - CEvalConstMul; end;
  end;
end;

function CEvalConstShift: Int64;
begin
  Result := CEvalConstAdd;
  while (CurTok.Kind = tkShl) or (CurTok.Kind = tkShr) do
  begin
    if CurTok.Kind = tkShl then begin Next; Result := Result shl CEvalConstAdd; end
    else begin Next; Result := Result shr CEvalConstAdd; end;
  end;
end;

function CEvalConstAnd: Int64;
begin
  Result := CEvalConstShift;
  while CurTok.Kind = tkAmp do begin Next; Result := Result and CEvalConstShift; end;
end;

function CEvalConstXor: Int64;
begin
  Result := CEvalConstAnd;
  while CurTok.Kind = tkXor do begin Next; Result := Result xor CEvalConstAnd; end;
end;

function CEvalConstExpr: Int64;
begin
  Result := CEvalConstXor;
  while CurTok.Kind = tkPipe do begin Next; Result := Result or CEvalConstXor; end;
end;

{ Parse an enumerator list. CurTok must be at the opening tkBegin (the brace).
  Registers each enumerator as an Int32 constant (auto-incrementing from 0,
  or from the last explicit value + 1). Leaves CurTok after the closing brace. }
procedure ParseCEnumBody;
var nextVal, val: Int64; nm: AnsiString;
begin
  Next; { consume the opening brace }
  nextVal := 0;
  while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
  begin
    if CurTok.Kind = tkIdent then
    begin
      nm := CurTok.SVal; Next;
      if CurTok.Kind = tkAssign then { an = introduces an explicit value }
      begin
        Next;
        val := CEvalConstExpr;
      end
      else
        val := nextVal;
      AddConst(nm, tyInt32, val);
      nextVal := val + 1;
      if CurTok.Kind = tkComma then Next;
    end
    else
      Next;
  end;
  if CurTok.Kind = tkEnd then Next; { consume the closing brace }
end;

{ Build an AnsiString from a span of the C preprocessor character pool. }
function CMacroPoolText(off, len: Integer): AnsiString;
var i: Integer;
begin
  Result := '';
  for i := 0 to len - 1 do AppendChar(Result, CPrepChars[off + i]);
end;

{ Surface object-like integer #define macros as Pascal constants, so a C
  header's `#define SQLITE_ROW 100` is usable by name instead of being a magic
  number hardcoded in every binding. Function-like macros, string/float/empty
  bodies, and bodies that are not a pure integer constant expression are
  skipped. The macro value text is lexed into the token stream and evaluated
  with the same CEvalConstExpr used for enum values; an identifier in the body
  is accepted only when it already resolves to a registered constant (so chains
  like `#define B (A+1)` work in definition order). Must run after ParseCUnit,
  while the C header's case-sensitive mode and unit index are still in effect,
  so the constants match the exact C spelling. }
procedure RegisterCMacroConsts;
var mi, vStart, vEnd, t, savedPos: Integer;
    name, valText: AnsiString;
    firstCh: Char; ok: Boolean; v: Int64; si: Integer;
begin
  mi := 0;
  while mi < CPMCount do
  begin
    if CPMFunction[mi] or (CPMNameLen[mi] <= 0) or (CPMValueLen[mi] <= 0) then
    begin
      Inc(mi);
      Continue;
    end;
    { Cheap text prefilter: a pure integer expression starts with a digit, an
      open paren, or a unary +/-. Rejects string/identifier bodies without
      lexing them, keeping the token stream from bloating on system headers. }
    firstCh := CPrepChars[CPMValueOff[mi]];
    if not ((firstCh in ['0'..'9']) or (firstCh = '(') or
            (firstCh = '+') or (firstCh = '-')) then
    begin
      Inc(mi);
      Continue;
    end;
    name := CMacroPoolText(CPMNameOff[mi], CPMNameLen[mi]);
    if FindSym(name) >= 0 then begin Inc(mi); Continue; end;  { don't clobber }

    valText := CMacroPoolText(CPMValueOff[mi], CPMValueLen[mi]);
    vStart := CLexAppend(valText);
    vEnd := vStart;
    while (vEnd < TokCount) and (Tokens[vEnd].Kind <> tkEOF) do Inc(vEnd);

    { Guard: every token must belong to a pure integer constant expression. }
    ok := vEnd > vStart;
    t := vStart;
    while t < vEnd do
    begin
      if (Tokens[t].Kind = tkInteger) or (Tokens[t].Kind = tkLParen) or
         (Tokens[t].Kind = tkRParen) or (Tokens[t].Kind = tkPlus) or
         (Tokens[t].Kind = tkMinus) or (Tokens[t].Kind = tkStar) or
         (Tokens[t].Kind = tkShl) or (Tokens[t].Kind = tkShr) or
         (Tokens[t].Kind = tkPipe) or (Tokens[t].Kind = tkAmp) or
         (Tokens[t].Kind = tkXor) or (Tokens[t].Kind = tkNot) then
        { allowed }
      else if Tokens[t].Kind = tkIdent then
      begin
        si := FindSym(GetTokenStr(t));
        if (si < 0) or (Syms[si].Kind <> skConst) then ok := False;
      end
      else
        ok := False;
      Inc(t);
    end;

    if ok then
    begin
      savedPos := TokPos;
      TokPos := vStart;
      Next;
      v := CEvalConstExpr;
      AddConst(name, tyInt32, v);
      TokPos := savedPos;
    end;
    Inc(mi);
  end;
end;

{ Conservatively decide whether a C struct/union body is laid out as a record.
  startIdx is the opening brace (tkBegin) token index. Returns False — meaning
  fall back to an opaque pointer — for any construct ParseCStructInto cannot lay
  out correctly, so it never produces silently-wrong field offsets:
    - bitfields (`name : n`): wrong offsets for following fields,
    - nested/anonymous struct or union bodies (a second brace),
    - struct/union/enum-tag-typed fields (`struct Foo bar;`): the field would be
      dropped, shifting offsets.
  Plain POD (scalars, pointers, fixed arrays, typedef-named-type fields incl.
  nested-struct-by-value) returns True. }
function CStructBodyIsSimple(startIdx: Integer): Boolean;
var i, depth, declStart: Integer;
begin
  Result := True;
  
  { Find the preceding struct/union/typedef keyword to start scanning for attributes }
  declStart := startIdx;
  while declStart > 0 do
  begin
    if Tokens[declStart].Kind = tkRecord then Break;
    if Tokens[declStart].Kind = tkIdent then
    begin
      if (GetTokenStrFromRaw(Tokens[declStart].SOffset, Tokens[declStart].SLen) = 'union') or
         (GetTokenStrFromRaw(Tokens[declStart].SOffset, Tokens[declStart].SLen) = 'typedef') then
        Break;
    end;
    Dec(declStart);
  end;

  { Scan from declStart to startIdx (the opening brace) for attributes }
  for i := declStart to startIdx - 1 do
  begin
    if (CAttrFlags[i] and 3) <> 0 then
    begin
      Result := False;
      Exit;
    end;
  end;

  depth := 0;
  i := startIdx;
  while i < TokCount do
  begin
    { Check if token inside the body has attribute }
    if (CAttrFlags[i] and 3) <> 0 then
    begin
      Result := False;
      Exit;
    end;

    if Tokens[i].Kind = tkBegin then
      Inc(depth)   { nested aggregate bodies are now laid out as sub-records }
    else if Tokens[i].Kind = tkEnd then
    begin
      Dec(depth);
      if depth <= 0 then
      begin
        { We reached the end of the body. Now scan past the body up to the terminating semicolon }
        Inc(i);
        while (i < TokCount) and (Tokens[i].Kind <> tkEOF) do
        begin
          if (CAttrFlags[i] and 3) <> 0 then
          begin
            Result := False;
            Exit;
          end;
          if Tokens[i].Kind = tkSemicolon then
            Break;
          Inc(i);
        end;
        Exit;
      end;
    end
    else if depth >= 1 then
    begin
      { Named bit-fields `name : width` are now laid out (as a full storage unit
        per field — see ParseCStructInto), so they no longer force the opaque
        fallback. An ANONYMOUS bit-field (`T : width`, padding / `:0` alignment)
        has no name token before the colon and ParseCStructInto cannot model it,
        so still reject those. struct/union/enum keywords are OK as field types
        (`struct Tag *next`, `enum E e`) because ParseCDeclType resolves a tag
        reference; an INLINE anonymous aggregate body is rejected via the
        nested-brace check above. }
      if (Tokens[i].Kind = tkColon) and (Tokens[i-1].Kind <> tkIdent) then
        begin Result := False; Exit; end;
    end;
    Inc(i);
  end;
end;

{ Record alignment of a record id (struct field by value). }
function CRecAlign(rec: Integer): Integer;
begin
  if rec >= REC_UCLASS_BASE then Result := UClsAlign[rec - REC_UCLASS_BASE]
  else Result := TARGET_PTR_SIZE;
  if Result < 1 then Result := 1;
end;

{ Parse a C struct/union body into the user record `ci`. CurTok must be at the
  opening brace (tkBegin). Fills fields with C natural alignment (each field on
  its own alignment; struct align = max member align; size rounded up to that),
  and leaves CurTok past the closing brace (tkEnd). Unions lay every field at
  offset 0 with size = the largest member. Supported field shapes: scalars,
  pointers (any depth -> Pointer, element type/record recorded for deref),
  fixed arrays `T x[N]`, and nested struct-by-value. Bitfields (`x : n`) and
  inline anonymous struct definitions are skipped, not laid out. }
procedure ParseCStructInto(ci: Integer; isUnion: Boolean);
const MAX_BF = 256;
var
  curOff, maxAlign, fnOff, fnLen, arrLen, declStars, sz, al, totalSz, thisOff: Integer;
  baseScalarTk, baseElemTk, baseElemRec, baseRecId, declTk, declElemTk, declElemRec, declRec: Integer;
  fldProcSig, subci, subRecSz, subAl, sdepth, bfCount, k: Integer;
  fTk: TTypeKind;
  isArr, firstDecl, subIsUnion: Boolean;
  { The parent's fields are BUFFERED during the walk and appended to the shared
    UFld pool only AFTER the body (and any nested sub-records) are laid out, so the
    parent's fields stay contiguous — FindUField scans [base, base+count). Without
    this, a nested-aggregate member's sub-record fields would be inserted between
    the parent's fields and break the contiguous range. }
  bfNOff, bfNLen, bfOff, bfTk, bfRec, bfElemTk, bfElemRec, bfProcSig, bfArrLen: array[0..MAX_BF-1] of Integer;
  bfIsArr: array[0..MAX_BF-1] of Boolean;
  bfNDims: array[0..MAX_BF-1] of Integer;
  bfDimSpan: array[0..MAX_BF*MAX_ARR_DIMS-1] of Integer;
  fldNDims, dimVal, ndi: Integer;
begin
  Next; { consume the opening brace }
  curOff := 0;
  maxAlign := 1;
  bfCount := 0;
  while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
  begin
    { Nested inline aggregate member: struct or union with an inline body followed
      by member name(s). Lay the body out as a sub-record (recursively) and buffer
      the member(s) as record-typed fields, so outer.name.member resolves (lua
      CallInfo / GCUnion). Detected by an opening brace right after the keyword,
      optionally past a tag. }
    if ((CurTok.Kind = tkRecord) or ((CurTok.Kind = tkIdent) and (CurTok.SVal = 'union'))) and
       ((Tokens[TokPos].Kind = tkBegin) or
        ((Tokens[TokPos].Kind = tkIdent) and (Tokens[TokPos + 1].Kind = tkBegin))) then
    begin
      subIsUnion := (CurTok.Kind = tkIdent) and (CurTok.SVal = 'union');
      Next;  { consume struct/union keyword }
      if (CurTok.Kind = tkIdent) and (Tokens[TokPos].Kind = tkBegin) then
      begin
        subci := FindOrForwardCTag(CurTok.SVal) - REC_UCLASS_BASE;  { inline-tagged }
        Next;
      end
      else if UClsCount < MAX_UCLASS - 1 then
      begin subci := AddUClass(0, 0); UClsIsRecord[subci] := True; end
      else
        subci := -1;
      if subci >= 0 then
        ParseCStructInto(subci, subIsUnion)
      else
      begin
        sdepth := 0;
        repeat
          if CurTok.Kind = tkBegin then Inc(sdepth)
          else if CurTok.Kind = tkEnd then Dec(sdepth);
          Next;
        until (sdepth = 0) or (CurTok.Kind = tkEOF);
      end;
      if subci >= 0 then begin subRecSz := UClsSize_[subci]; subAl := UClsAlign[subci]; end
      else begin subRecSz := TARGET_PTR_SIZE; subAl := TARGET_PTR_SIZE; end;
      if subAl < 1 then subAl := 1;
      repeat
        if CurTok.Kind <> tkIdent then Break;
        fnOff := Tokens[TokPos - 1].SOffset; fnLen := Tokens[TokPos - 1].SLen; Next;
        while CurTok.Kind = tkLBrack do
        begin Next; while (CurTok.Kind <> tkRBrack) and (CurTok.Kind <> tkEOF) do Next; Eat(tkRBrack); end;
        if isUnion then thisOff := 0 else thisOff := AlignTo(curOff, subAl);
        if (subci >= 0) and (bfCount < MAX_BF) then
        begin
          bfNOff[bfCount] := fnOff; bfNLen[bfCount] := fnLen; bfOff[bfCount] := thisOff;
          bfTk[bfCount] := Ord(tyRecord); bfRec[bfCount] := REC_UCLASS_BASE + subci;
          bfElemTk[bfCount] := Ord(tyUnknown); bfElemRec[bfCount] := REC_NONE;
          bfIsArr[bfCount] := False; bfArrLen[bfCount] := 1; bfProcSig[bfCount] := -1;
          Inc(bfCount);
        end;
        if isUnion then begin if subRecSz > curOff then curOff := subRecSz; end
        else curOff := thisOff + subRecSz;
        if subAl > maxAlign then maxAlign := subAl;
      until not Eat(tkComma);
      Eat(tkSemicolon);
    end
    else if IsCTypeTok then
    begin
      fTk := ParseCDeclType;
      fldProcSig := CTypeProcSig;   { fn-pointer typedef field signature, if any }
      if CTypeFnPtrName <> '' then
      begin
        { Inline function-pointer member `RET (*name)(params);` — ParseCDeclType
          consumed the whole declarator and captured the name + call signature.
          Register it as an 8-byte pointer field; the normal name-reading loop
          below would Break (the name token is already consumed). }
        if isUnion then thisOff := 0 else thisOff := AlignTo(curOff, TARGET_PTR_SIZE);
        if bfCount < MAX_BF then
        begin
          bfNOff[bfCount] := CTypeFnPtrNameOff; bfNLen[bfCount] := CTypeFnPtrNameLen;
          bfOff[bfCount] := thisOff;
          bfTk[bfCount] := Ord(tyPointer); bfRec[bfCount] := REC_NONE;
          bfElemTk[bfCount] := Ord(tyUnknown); bfElemRec[bfCount] := REC_NONE;
          bfIsArr[bfCount] := False; bfArrLen[bfCount] := 1; bfNDims[bfCount] := 0;
          bfProcSig[bfCount] := fldProcSig;
          Inc(bfCount);
        end;
        if isUnion then begin if TARGET_PTR_SIZE > curOff then curOff := TARGET_PTR_SIZE; end
        else curOff := thisOff + TARGET_PTR_SIZE;
        if TARGET_PTR_SIZE > maxAlign then maxAlign := TARGET_PTR_SIZE;
        Eat(tkSemicolon);
      end
      else
      begin
      { Recover the base scalar/struct before pointer folding, so comma
        declarators with differing pointer levels (`int *a, b`) are correct. }
      if CTypePtrDepth > 0 then
      begin
        baseScalarTk := CTypeElemTk;
        baseElemRec := CTypeElemRec;
        baseElemTk := baseScalarTk;
      end
      else
      begin
        baseScalarTk := Ord(fTk);
        if fTk = tyPointer then
        begin
          baseElemTk := CTypeElemTk;
          baseElemRec := CTypeElemRec;
        end
        else
        begin
          baseElemTk := Ord(tyUnknown);
          baseElemRec := REC_NONE;
        end;
      end;
      baseRecId := CTypeBaseRec;

      firstDecl := True;
      repeat
        { stars for this declarator: the first one's stars were consumed by
          ParseCDeclType (CTypePtrDepth); later ones carry their own. }
        if firstDecl then
          declStars := CTypePtrDepth
        else
        begin
          declStars := 0;
          while CurTok.Kind = tkStar do begin Inc(declStars); Next; end;
        end;
        if CurTok.Kind <> tkIdent then Break;
        fnOff := Tokens[TokPos-1].SOffset;
        fnLen := Tokens[TokPos-1].SLen;
        Next;

        { Named bit-field `T name : width` — bit-packing is not modelled; the
          field is laid out as a full storage unit of its base type. That gives
          offsets that differ from the C ABI but are self-consistent for
          pxx-compiled C (which only ever accesses a bit-field by name, never by
          reinterpreting its storage), and — crucially — it keeps the enclosing
          struct laid out as a record instead of an opaque pointer, so sibling
          fn-pointer members (sqlite3.xProgress, reached via the nested
          bit-field struct `init`) stay registered and callable. Discard width.
          A bit-field is never an array, so the bracket loop below is skipped. }
        if CurTok.Kind = tkColon then
        begin
          Next;
          CEvalConstExpr;
        end;

        isArr := False; arrLen := 1; fldNDims := 0;
        while CurTok.Kind = tkLBrack do
        begin
          Next;
          dimVal := 1;
          if CurTok.Kind <> tkRBrack then
            dimVal := CEvalConstExpr;
          arrLen := arrLen * dimVal;
          Eat(tkRBrack);
          isArr := True;
          { record per-dim span so a multidim field supports partial-index row
            decay (`field[i]` -> row address) in the C frontend. }
          if fldNDims < MAX_ARR_DIMS then
          begin
            bfDimSpan[bfCount * MAX_ARR_DIMS + fldNDims] := dimVal;
            Inc(fldNDims);
          end;
        end;

        if declStars > 0 then
        begin
          declTk := Ord(tyPointer); declRec := REC_NONE;
          declElemTk := baseElemTk; declElemRec := baseElemRec;
          if declStars >= 2 then begin declElemTk := Ord(tyPointer); declElemRec := REC_NONE; end;
          sz := TARGET_PTR_SIZE; al := TARGET_PTR_SIZE;
        end
        else if (IntToTypeKind(baseScalarTk) = tyRecord) and (baseRecId >= REC_UCLASS_BASE) then
        begin
          declTk := Ord(tyRecord); declRec := baseRecId;
          declElemTk := Ord(tyUnknown); declElemRec := REC_NONE;
          sz := RecSize(baseRecId); al := CRecAlign(baseRecId);
        end
        else
        begin
          declTk := baseScalarTk; declRec := REC_NONE;
          if IntToTypeKind(baseScalarTk) = tyPointer then
          begin
            declElemTk := baseElemTk;
            declElemRec := baseElemRec;
          end
          else
          begin
            declElemTk := Ord(tyUnknown);
            declElemRec := REC_NONE;
          end;
          sz := TypeSize(IntToTypeKind(baseScalarTk));
          al := TypeAlign(IntToTypeKind(baseScalarTk));
        end;
        if al < 1 then al := 1;

        if isUnion then thisOff := 0
        else thisOff := AlignTo(curOff, al);

        if bfCount < MAX_BF then
        begin
          bfNOff[bfCount] := fnOff; bfNLen[bfCount] := fnLen; bfOff[bfCount] := thisOff;
          bfTk[bfCount] := declTk; bfRec[bfCount] := declRec;
          bfElemTk[bfCount] := declElemTk; bfElemRec[bfCount] := declElemRec;
          bfIsArr[bfCount] := isArr; bfArrLen[bfCount] := arrLen;
          bfNDims[bfCount] := fldNDims;
          if (declStars = 0) then bfProcSig[bfCount] := fldProcSig else bfProcSig[bfCount] := -1;
          Inc(bfCount);
        end;

        totalSz := sz;
        if isArr then totalSz := sz * arrLen;
        if isUnion then
        begin
          if totalSz > curOff then curOff := totalSz;
        end
        else
          curOff := thisOff + totalSz;
        if al > maxAlign then maxAlign := al;

        firstDecl := False;
      until not Eat(tkComma);
      Eat(tkSemicolon);
      end;  { close the non-fn-pointer-member else }
    end
    else
      Next;  { skip attributes / unknown tokens }
  end;
  Eat(tkEnd); { consume the closing brace }
  { Append the parent's buffered fields contiguously, NOW (after sub-records), and
    anchor the record's field base here. }
  UClsFBase[ci] := UFldCount;
  for k := 0 to bfCount - 1 do
  begin
    if UFldCount >= MAX_UFIELD - 1 then Break;   { pool nearly full: drop the rest }
    LastTypePointerElemTk := IntToTypeKind(bfElemTk[k]);
    LastTypePointerElemRec := bfElemRec[k];
    AddUField(ci, bfNOff[k], bfNLen[k], bfOff[k], bfTk[k], bfRec[k]);
    UFldIsArray[UFldCount-1] := bfIsArr[k];
    UFldArrLen[UFldCount-1] := bfArrLen[k];
    if bfProcSig[k] >= 0 then UFldProcSig[UFldCount-1] := bfProcSig[k];
    if bfNDims[k] >= 2 then
    begin
      UFldArrNDims[UFldCount-1] := bfNDims[k];
      for ndi := 0 to bfNDims[k] - 1 do
      begin
        UFldArrDimLo[(UFldCount-1) * MAX_ARR_DIMS + ndi]   := 0;
        UFldArrDimSpan[(UFldCount-1) * MAX_ARR_DIMS + ndi] := bfDimSpan[k * MAX_ARR_DIMS + ndi];
      end;
    end;
  end;
  UClsSize_[ci] := AlignTo(curOff, maxAlign);
  UClsAlign[ci] := maxAlign;
end;

{ Parse a top-level `typedef ...;` and register the new type name.
  - struct/union [tag] [body] Name   -> opaque, mapped to Pointer
  - enum [tag] body Name             -> Int32, enumerators become constants
  - <decl-specifiers> Name           -> the mapped scalar/pointer type
  Function-pointer typedefs `ret (*Name)(args)` are registered as Pointer AND
  carry a signature Procs[] entry (CTypedefProcSig) so a value of the type is
  callable through AN_CALL_IND with C-ABI marshalling. }
procedure ParseCTypedef;
var tk: TTypeKind; nm, tagName: AnsiString;
    isAggregate, isUnion, hasTag: Boolean;
    ci, ptrStars, nmOff, nmLen: Integer;
begin
  Next; { consume 'typedef' }

  isAggregate := (CurTok.Kind = tkRecord) or
                 ((CurTok.Kind = tkIdent) and (CurTok.SVal = 'union'));
  if isAggregate then
  begin
    isUnion := (CurTok.Kind = tkIdent) and (CurTok.SVal = 'union');
    Next; { 'struct' / 'union' }
    hasTag := False;
    if CurTok.Kind = tkIdent then              { optional tag — capture it }
    begin
      tagName := CurTok.SVal; hasTag := True; Next;
    end;
    if (CurTok.Kind = tkBegin) and
       ((UClsCount >= MAX_UCLASS - 1) or (UFldCount >= MAX_UFIELD - 128) or
        (not CStructBodyIsSimple(TokPos - 1))) then
    begin
      { Fall back to an opaque pointer when either (a) record-table headroom is
        low (C structs share the MAX_UCLASS/MAX_UFIELD tables with Pascal), or
        (b) the body uses a construct we cannot lay out without silently-wrong
        offsets (bitfields, nested/anonymous aggregates, struct/union/enum-tag
        fields). Plain POD bodies take the record path below. }
      SkipBraceBlock;
      while CurTok.Kind = tkStar do Next;
      if CurTok.Kind = tkIdent then
      begin
        nm := CurTok.SVal; Next;
        AddCTypedef(nm, tyPointer);
      end;
      while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
      Eat(tkSemicolon);
      Exit;
    end;
    if CurTok.Kind = tkBegin then
    begin
      { Body present: lay it out as a real record so fields are addressable.
        The typedef Name follows the body. When the struct has a tag, register
        (or reuse a forward) record for that tag BEFORE parsing the body, so a
        self-reference `struct Tag *next;` inside resolves to this same record. }
      if hasTag then
        ci := FindOrForwardCTag(tagName) - REC_UCLASS_BASE
      else
        ci := AddUClass(0, 0);
      UClsIsRecord[ci] := True;
      ParseCStructInto(ci, isUnion);
      ptrStars := 0;
      while CurTok.Kind = tkStar do begin Inc(ptrStars); Next; end;
      if CurTok.Kind = tkIdent then
      begin
        nmOff := Tokens[TokPos-1].SOffset;
        nmLen := Tokens[TokPos-1].SLen;
        nm := CurTok.SVal; Next;
        if ptrStars > 0 then
        begin
          { typedef struct {..} *Name; — the record stays anonymous, Name is a
            pointer to it (both for the C parser and as a Pascal pointer type). }
          AddCTypedefEx(nm, tyPointer, Ord(tyRecord), REC_UCLASS_BASE + ci);
          RegisterPtrAlias(nmOff, nmLen, Ord(tyRecord), REC_UCLASS_BASE + ci, 0, 0);
        end
        else
        begin
          { typedef struct {..} Name; — Name *is* the record. }
          UClsNOff[ci] := nmOff;
          UClsNLen[ci] := nmLen;
          AddCTypedefEx(nm, tyRecord, Ord(tyUnknown), REC_UCLASS_BASE + ci);
        end;
      end;
      while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
      Eat(tkSemicolon);
      Exit;
    end;
    { No body present (forward / separately-defined struct). With a tag, the
      typedef ALIASES that struct's (possibly forward) record — `typedef struct
      Zio ZIO;` makes `ZIO` the record and `ZIO *` a pointer to it, so a later
      `struct Zio { ... }` body fills the same record and `z->field` resolves.
      `typedef struct T *Ref;` is a pointer to it. A tagless no-body typedef
      stays an opaque pointer handle. }
    ptrStars := 0;
    while CurTok.Kind = tkStar do begin Inc(ptrStars); Next; end;
    if CurTok.Kind = tkIdent then
    begin
      nmOff := Tokens[TokPos-1].SOffset;
      nmLen := Tokens[TokPos-1].SLen;
      nm := CurTok.SVal; Next;
      if hasTag then
      begin
        ci := FindOrForwardCTag(tagName) - REC_UCLASS_BASE;
        if ptrStars > 0 then
        begin
          AddCTypedefEx(nm, tyPointer, Ord(tyRecord), REC_UCLASS_BASE + ci);
          RegisterPtrAlias(nmOff, nmLen, Ord(tyRecord), REC_UCLASS_BASE + ci, 0, 0);
        end
        else
          AddCTypedefEx(nm, tyRecord, Ord(tyUnknown), REC_UCLASS_BASE + ci);
      end
      else
        AddCTypedef(nm, tyPointer); { tagless opaque aggregate: pointer-only }
    end;
    while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
    Eat(tkSemicolon);
    Exit;
  end;

  if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'enum') then
  begin
    Next; { 'enum' }
    if CurTok.Kind = tkIdent then Next;      { optional tag }
    if CurTok.Kind = tkBegin then ParseCEnumBody; { enumerators -> constants }
    if CurTok.Kind = tkIdent then
    begin
      nm := CurTok.SVal; Next;
      AddCTypedef(nm, tyInt32);
    end;
    while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
    Eat(tkSemicolon);
    Exit;
  end;

  { scalar / pointer typedef }
  tk := ParseCDeclType;
  { Function-pointer typedef `ret (*Name)(params)`: ParseCDeclType collapses the
    declarator to Pointer and (now) captures the name + a call signature in
    CTypeFnPtrName / CTypeProcSig. Register Name as a pointer typedef that carries
    the signature, so a value of the type is callable through AN_CALL_IND. }
  if (CTypeFnPtrName <> '') and (CTypeProcSig >= 0) then
  begin
    AddCTypedefFnPtr(CTypeFnPtrName, CTypeProcSig);
    while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
    Eat(tkSemicolon);
    Exit;
  end;
  if CurTok.Kind = tkIdent then
  begin
    nmOff := Tokens[TokPos-1].SOffset;
    nmLen := Tokens[TokPos-1].SLen;
    nm := CurTok.SVal; Next;
    { Preserve metadata when aliasing typedefs. `typedef S Stream;` must keep the
      record id from S, otherwise `Stream *p; p->field` resolves as REC_NONE and
      all field offsets collapse to 0. Pointer aliases likewise keep their
      pointed-at type even when aliasing an existing pointer typedef rather than
      spelling a fresh `*` here. }
    if (tk = tyRecord) then
      AddCTypedefEx(nm, tk, Ord(tyUnknown), CTypeBaseRec)
    else if tk = tyPointer then
    begin
      AddCTypedefEx(nm, tk, CTypeElemTk, CTypeElemRec);
      if CTypeProcSig >= 0 then CTypedefProcSig[FindCTypedef(nm)] := CTypeProcSig;
      if (CTypePtrDepth > 0) or (CTypeElemTk <> Ord(tyUnknown)) then
        RegisterPtrAlias(nmOff, nmLen, CTypeElemTk, CTypeElemRec, 0, 0);
    end
    else
      AddCTypedef(nm, tk);
  end;
  while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
  Eat(tkSemicolon);
end;

{ Bare top-level `enum [tag] body ;` — register the enumerators as
  constants (no new type name). }
procedure ParseCEnumDecl;
begin
  Next; { consume 'enum' }
  if CurTok.Kind = tkIdent then Next;        { optional tag }
  if CurTok.Kind = tkBegin then ParseCEnumBody;
  while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
  Eat(tkSemicolon);
end;

{ True when the upcoming `struct`/`union` tokens are a bare struct/union
  declaration or definition (`struct Tag { ... };` or `struct Tag;`) rather than
  a function/variable typed by the struct (`struct Tag *get();`). CurTok is the
  struct/union keyword, so Tokens[TokPos] is the token after it. }
function IsBareStructDecl: Boolean;
var i, depth: Integer;
begin
  i := TokPos;
  if (i < TokCount) and (Tokens[i].Kind = tkIdent) then Inc(i);  { skip tag }
  if i >= TokCount then begin Result := False; Exit; end;
  if Tokens[i].Kind = tkSemicolon then begin Result := True; Exit; end;  { `struct Tag;` forward }
  if Tokens[i].Kind <> tkBegin then begin Result := False; Exit; end;    { `struct Tag x` etc. }
  { Scan past the balanced body; a `;` right after it is a bare type definition,
    but an identifier (a variable) means this is a struct-typed GLOBAL/var decl
    (`struct { ... } g;`) that must route to ParseCGlobalVarDecl, not ParseCStructDecl. }
  depth := 0;
  while i < TokCount do
  begin
    if Tokens[i].Kind = tkBegin then Inc(depth)
    else if Tokens[i].Kind = tkEnd then
    begin Dec(depth); if depth = 0 then begin Inc(i); Break; end; end;
    Inc(i);
  end;
  Result := (i < TokCount) and (Tokens[i].Kind = tkSemicolon);
end;

{ Bare `struct/union [Tag] { body };` (definition) or `struct Tag;` (forward).
  A tagged definition lays the body out as a record under the tag, so other C
  declarations can use `struct Tag` by name. }
procedure ParseCStructDecl;
var isUnion, hasTag: Boolean; tagName: AnsiString; ci, tagOff, tagLen, tagRec: Integer;
begin
  isUnion := (CurTok.Kind = tkIdent) and (CurTok.SVal = 'union');
  Next; { struct / union }
  hasTag := False; tagOff := 0; tagLen := 0;
  if CurTok.Kind = tkIdent then
  begin
    tagName := CurTok.SVal;
    tagOff := Tokens[TokPos-1].SOffset; tagLen := Tokens[TokPos-1].SLen;
    hasTag := True; Next;
  end;
  if CurTok.Kind = tkBegin then
  begin
    ci := -1;
    if hasTag then
    begin
      tagRec := FindOrForwardCTag(tagName);          { may be REC_NONE if table full }
      if tagRec >= REC_UCLASS_BASE then ci := tagRec - REC_UCLASS_BASE;
    end
    else if UClsCount < MAX_UCLASS - 1 then
      ci := AddUClass(0, 0);
    if ci < 0 then
      SkipBraceBlock                                  { no headroom: opaque }
    else
    begin
      UClsIsRecord[ci] := True;
      if hasTag and (UClsNLen[ci] = 0) then
      begin
        UClsNOff[ci] := tagOff; UClsNLen[ci] := tagLen;  { name the record by its tag }
      end;
      if (UFldCount < MAX_UFIELD - 128) and CStructBodyIsSimple(TokPos - 1) then
        ParseCStructInto(ci, isUnion)
      else
        SkipBraceBlock;   { opaque: keep the tag, drop the layout }
    end;
  end
  else if hasTag then
    FindOrForwardCTag(tagName);  { forward `struct Tag;` }
  while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
  Eat(tkSemicolon);
end;

procedure ParseCUnit;
begin
  while CurTok.Kind <> tkEOF do
  begin
    if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'typedef') then
      ParseCTypedef
    else if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'enum') then
      ParseCEnumDecl
    else if ((CurTok.Kind = tkRecord) or
             ((CurTok.Kind = tkIdent) and (CurTok.SVal = 'union'))) and
            IsBareStructDecl then
      ParseCStructDecl
    else if IsCTypeTok then
      ParseCSubroutine
    else
      Next;
  end;
end;
