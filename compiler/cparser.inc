{ ===== C Parser ===== }

function ParseCBlockAST: Integer; forward;
function ParseCStatementAST: Integer; forward;
procedure SkipBraceBlock; forward;
procedure ParseCSubroutine; forward;
function ParseCExpr: Integer; forward;
function CEvalConstExpr: Int64; forward;
procedure ParseCTypedef; forward;
procedure ParseCEnumDecl; forward;
procedure ParseCStructDecl; forward;
function IsBareStructDecl: Boolean; forward;

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
  else if (IntToTypeKind(ASTTk[l]) = tyInt64) or (IntToTypeKind(ASTTk[r]) = tyInt64) then
    Result := Ord(tyInt64)
  else
    Result := Ord(tyInteger);
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
  if cTok = Ord(tkSlash) then ivalOp := Ord(tkDiv)        { C `/` on ints = div }
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

{ Build `lv = lv (+|-) 1` as an AN_ASSIGN. The read side is a clone of the
  lvalue so the assignment's lvalue and rvalue nodes do not alias. Used for
  both prefix and postfix `++`/`--`; in statement / for-post context the
  pre-vs-post value distinction is irrelevant, so both lower identically. }
function CMakeIncDec(lv: Integer; isInc: Boolean): Integer;
var one, binop, node, rd: Integer;
begin
  rd := CloneAST(lv);
  one := AllocNode(AN_INT_LIT);
  ASTIVal[one] := 1;
  ASTTk[one] := Ord(tyInteger);
  binop := AllocNode(AN_BINOP);
  if isInc then ASTIVal[binop] := Ord(tkPlus) else ASTIVal[binop] := Ord(tkMinus);
  ASTLeft[binop] := rd;
  ASTRight[binop] := one;
  ASTTk[binop] := ASTTk[lv];
  node := AllocNode(AN_ASSIGN);
  ASTLeft[node] := lv;
  ASTRight[node] := binop;
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

{ A primary: integer/char/string literal, parenthesised expr, identifier
  (constant -> folded literal; variable -> AN_IDENT; name followed by `(` ->
  call with an AN_ARG chain). }
function ParseCPrimary: Integer;
var node, idx, procIdx, argHead, argTail, argNode, valNode: Integer;
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
    tkString:
    begin
      node := AllocNode(AN_STR_LIT);
      ASTSOffset[node] := Tokens[TokPos - 1].SOffset;
      ASTSLen[node] := Tokens[TokPos - 1].SLen;
      ASTTk[node] := Ord(tyString);
      Next;
      Result := node;
    end;
    tkLParen:
    begin
      Next;
      Result := ParseCExpr;
      Expect(tkRParen, ')');
    end;
    tkIdent:
    begin
      name := CurTok.SVal;
      Next;
      if CurTok.Kind = tkLParen then
      begin
        { function call }
        Next;
        procIdx := FindProc(name);
        node := AllocNode(AN_CALL);
        ASTIVal[node] := procIdx;
        if procIdx >= 0 then ASTTk[node] := Ord(Procs[procIdx].RetType)
        else ASTTk[node] := Ord(tyInteger);
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
        ASTLeft[node] := argHead;
        Expect(tkRParen, ')');
        if procIdx < 0 then Error('call to undeclared function');
        Result := node;
      end
      else
      begin
        idx := FindSym(name);
        if idx < 0 then
        begin
          { Best-effort C frontend: an unresolved identifier (e.g. a token left
            behind by a self-referential / unmodelled macro) degrades to a 0
            literal instead of failing the whole translation unit — matching the
            old skip-the-statement leniency. Undeclared *calls* still error. }
          node := AllocNode(AN_INT_LIT);
          ASTIVal[node] := 0;
          ASTTk[node] := Ord(tyInteger);
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

{ Pointed-at / element TTypeKind ordinal of a pointer or array node, used to tag
  AN_DEREF / AN_INDEX results. Defaults to Integer for shapes not yet modelled. }
function CNodePointeeTk(node: Integer): Integer;
begin
  Result := Ord(tyInteger);
  if node < 0 then Exit;
  if ASTKind[node] = AN_IDENT then
  begin
    if Syms[ASTIVal[node]].IsArray then
      Result := Ord(Syms[ASTIVal[node]].ElemType)
    else if Syms[ASTIVal[node]].TypeKind = tyPointer then
      Result := Ord(Syms[ASTIVal[node]].PtrElemTk);
  end
  else if ASTKind[node] = AN_INDEX then
    Result := ASTTk[node];
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
    Result := IntToTypeKind(ASTTk[node]) = tyPointer;
end;

{ Unary prefix: `- + ! ~ * &`. sizeof and casts arrive later. }
function ParseCUnary: Integer;
var node, operand: Integer;
begin
  case CurTok.Kind of
    tkStar:   { *p dereference }
    begin
      Next;
      operand := ParseCUnary();
      node := AllocNode(AN_DEREF);
      ASTLeft[node] := operand;
      ASTTk[node] := CNodePointeeTk(operand);
      Result := node;
    end;
    tkAmp:    { &x address-of }
    begin
      Next;
      operand := ParseCUnary();
      node := AllocNode(AN_ADDR);
      ASTLeft[node] := operand;
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
      Result := CMakeIncDec(operand, True);
    end;
    tkMinusMinus: { prefix --lv }
    begin
      Next;
      operand := ParseCUnary();
      Result := CMakeIncDec(operand, False);
    end;
    else
      Result := ParseCPostfix();
  end;
end;

{ Postfix layer: a primary optionally followed by `++`/`--`. Array/field/call
  postfix (`[] . -> ()`) arrive with the lvalue increment. }
function ParseCPostfix: Integer;
var node, idxExpr, inode, dnode, fnode, baseFld, recId, fldOff, fldLen: Integer;
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
      inode := AllocNode(AN_INDEX);
      ASTLeft[inode] := node;
      ASTRight[inode] := idxExpr;
      ASTTk[inode] := CNodePointeeTk(node);
      node := inode;
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
      node := fnode;
    end
    else if (CurTok.Kind = tkPlusPlus) or (CurTok.Kind = tkMinusMinus) then
    begin
      if CurTok.Kind = tkPlusPlus then node := CMakeIncDec(node, True)
      else node := CMakeIncDec(node, False);
      Next;
    end
    else
      done := True;
  end;
  Result := node;
end;

{ Top-level C expression: assignment (right-assoc), incl. compound-assign.
  Ternary `?:` and the comma operator arrive in a later increment. }
function ParseCExpr: Integer;
var left, rhs, node, cTok, baseOp: Integer;
begin
  left := ParseCBinExpr(1);
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

procedure AddCTypedefEx(const name: AnsiString; tk: TTypeKind; elemTk, rec: Integer);
var idx, i: Integer;
begin
  idx := FindCTypedef(name);
  if idx >= 0 then
  begin
    CTypedefTk[idx] := Ord(tk);
    CTypedefElemTk[idx] := elemTk;
    CTypedefRec[idx] := rec;
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
  CTypedefHashInsert(CTypedefCount, name);
  Inc(CTypedefCount);
end;

procedure AddCTypedef(const name: AnsiString; tk: TTypeKind);
begin
  AddCTypedefEx(name, tk, Ord(tyUnknown), REC_NONE);
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
  shortCount, longCount, tdIdx, depth, baseRec: Integer;
  base: TTypeKind;
begin
  isUnsigned := False; isSigned := False; isFloatTy := False; isVoid := False;
  sawBase := False; isTypedef := False; isAggBase := False;
  shortCount := 0; longCount := 0; base := tyInt32; baseRec := REC_NONE;
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
      tkRecord:    { 'struct' [tag] — tag reference in type position }
        begin
          Next;
          if CurTok.Kind = tkIdent then
          begin
            base := tyRecord; baseRec := FindOrForwardCTag(CurTok.SVal);
            isAggBase := True; sawBase := True; Next;
          end
          else begin base := tyRecord; isAggBase := True; sawBase := True; end;
        end;
      tkIdent:
        begin
          { A typedef name is a type only in type position (before any base
            type is seen); otherwise it is the declarator name — stop.
            `union`/`enum` keywords are idents in this lexer. }
          if (not sawBase) and (CurTok.SVal = 'union') then
          begin
            Next;
            if CurTok.Kind = tkIdent then
            begin
              base := tyRecord; baseRec := FindOrForwardCTag(CurTok.SVal); Next;
            end
            else base := tyRecord;
            isAggBase := True; sawBase := True;
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
  CTypeBaseRec := baseRec;
  if CurTok.Kind = tkStar then
  begin
    CTypeElemTk := Ord(Result);   { the pointed-at scalar/typedef kind at depth 1 }
    CTypeElemRec := baseRec;      { ...and its record id, if it is a struct }
    while CurTok.Kind = tkStar do
    begin
      Inc(CTypePtrDepth);
      Next;
    end;
    if CTypePtrDepth >= 2 then
    begin
      CTypeElemTk := Ord(tyPointer);
      CTypeElemRec := REC_NONE;
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
    Result := tyPointer;
    CTypeIsVoid := False;
    depth := 0;
    repeat
      if CurTok.Kind = tkLParen then Inc(depth)
      else if CurTok.Kind = tkRParen then Dec(depth);
      Next;
    until (depth = 0) or (CurTok.Kind = tkEOF);
    if CurTok.Kind = tkLParen then
    begin
      depth := 0;
      repeat
        if CurTok.Kind = tkLParen then Inc(depth)
        else if CurTok.Kind = tkRParen then Dec(depth);
        Next;
      until (depth = 0) or (CurTok.Kind = tkEOF);
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
var baseTk: TTypeKind; head, tail, seq, asn, idn, initExpr, blk, idx: Integer;
    elemTkOrd, elemRec, arrLen: Integer;
    name: AnsiString;
begin
  baseTk := ParseCDeclType;   { specifiers + first declarator's pointer suffix }
  { Capture the pointer element type/record now — ParseCExpr below must not
    clobber the CType* globals (it does not run ParseCDeclType). }
  elemTkOrd := CTypeElemTk;
  elemRec := CTypeElemRec;
  head := -1; tail := -1;
  while True do
  begin
    if CurTok.Kind <> tkIdent then Break;
    name := CurTok.SVal; Next;
    if CurTok.Kind = tkLBrack then
    begin
      { fixed array  T name[N]  — N is a constant expression (literal/enum/macro) }
      Next;
      arrLen := CEvalConstExpr;
      Expect(tkRBrack, ']');
      if arrLen < 1 then arrLen := 1;
      idx := AllocArray(name, baseTk, 0, arrLen - 1);
      { array initialisers `= { ... }` not yet supported — skip if present }
      if CurTok.Kind = tkAssign then
      begin
        Next;
        while (CurTok.Kind <> tkComma) and (CurTok.Kind <> tkSemicolon) and
              (CurTok.Kind <> tkEOF) do Next;
      end;
    end
    else
    begin
      { A struct-by-value local needs its record id so field access resolves and
        AllocVar reserves RecSize bytes. }
      if baseTk = tyRecord then LastTypeRecId := CTypeBaseRec;
      idx := AllocVar(name, baseTk);
      if baseTk = tyPointer then
      begin
        Syms[idx].PtrElemTk := IntToTypeKind(elemTkOrd);
        Syms[idx].PtrElemRec := elemRec;
      end;
      initExpr := -1;
      if CurTok.Kind = tkAssign then
      begin
        Next;
        initExpr := ParseCExpr;
      end;
      if initExpr >= 0 then
      begin
        idn := AllocNode(AN_IDENT); ASTIVal[idn] := idx; ASTTk[idn] := Ord(baseTk);
        asn := AllocNode(AN_ASSIGN); ASTLeft[asn] := idn; ASTRight[asn] := initExpr;
        ASTTk[asn] := Ord(baseTk);
        seq := AllocNode(AN_SEQ); ASTLeft[seq] := asn; ASTRight[seq] := -1;
        if head = -1 then head := seq else ASTRight[tail] := seq;
        tail := seq;
      end;
    end;
    if CurTok.Kind = tkComma then begin Next; Continue; end;
    Break;
  end;
  Eat(tkSemicolon);
  blk := AllocNode(AN_BLOCK);
  ASTLeft[blk] := head;   { -1 = empty block, emits nothing }
  Result := blk;
end;

function ParseCIfAST: Integer;
var cond, thenS, elseS, node, pair: Integer;
begin
  Next; { if }
  Expect(tkLParen, '(');
  cond := ParseCExpr;
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
  cond := ParseCExpr;
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
    initNode := ParseCExpr;
    Eat(tkSemicolon);
  end;

  if CurTok.Kind = tkSemicolon then
  begin
    cond := AllocNode(AN_INT_LIT); ASTIVal[cond] := 1; ASTTk[cond] := Ord(tyBoolean);
  end
  else
    cond := ParseCExpr;
  Expect(tkSemicolon, ';');

  post := -1;
  if CurTok.Kind <> tkRParen then post := ParseCExpr;
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

  { printf(...) — args still ignored beyond the format string (libc work). }
  if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'printf') then
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

  { expression statement (assignment, call, ++/--) }
  exprNode := ParseCExpr;
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

{ A top-level global variable definition: <type> name (, name)* ;
  Allocated as zero-initialised BSS (CurProc<0 => skGlobal). Increment-1 scope:
  the slot is reserved and any initialiser is skipped (C zero-inits globals; a
  non-zero constant/runtime initialiser is a follow-up). Re-running across the
  two driver passes is idempotent — a name already present is not re-allocated. }
procedure ParseCGlobalVarDecl;
var baseTk: TTypeKind; name: AnsiString;
begin
  baseTk := ParseCDeclType;
  while True do
  begin
    if CurTok.Kind <> tkIdent then Break;
    name := CurTok.SVal; Next;
    if FindSym(name) < 0 then AllocVar(name, baseTk);
    if CurTok.Kind = tkAssign then
    begin
      Next;
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
  if CurTok.Kind = tkIdent then Next;
  Result := (CurTok.Kind = tkLParen);
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
procedure ParseCProgram;
var firstIdx, callPatch, mainIdx: Integer;
begin
  BSS_INITIAL_RSP := BSSSize; Inc(BSSSize, 8);

  { mov [BSS_INITIAL_RSP], rsp }
  EmitB($48); EmitB($89); EmitB($24); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
  { call main (rel32, patched once main's body address is known) }
  EmitB($E8); callPatch := CodeLen; EmitI32(0);
  { mov edi, eax ; mov eax, 231 (exit_group) ; syscall }
  EmitB($89); EmitB($C7);
  EmitB($B8); EmitI32(231);
  EmitB($0F); EmitB($05);

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
  name: AnsiString;
  isFunc: Boolean;
  nparams, procIdx, i, idx, patchPos, sz: Integer;
  retPtrElemTk, retPtrElemRec: Integer;
  ptypes: array[0..15] of TTypeKind;
  pnames: array[0..15] of AnsiString;
  pdepths: array[0..15] of Integer;
  pelemtk: array[0..15] of Integer;   { pointed-at TTypeKind ordinal per pointer param }
  pelemrec: array[0..15] of Integer;
  savedSC, savedFS, node, savedCurProc: Integer;
begin
  retType := ParseCDeclType;
  { Capture the return type's pointed-at type so `f()^`, `f()^.field`, `f()[i]`
    on a typed-pointer result resolve the element. }
  retPtrElemTk := Ord(tyUnknown);
  retPtrElemRec := REC_NONE;
  if (retType = tyPointer) and (CTypePtrDepth > 0) then
  begin
    retPtrElemTk := CTypeElemTk;
    retPtrElemRec := CTypeElemRec;
  end;
  if CTypeIsVoid then retType := tyInteger; { void return: value slot unused }

  if CurTok.Kind <> tkIdent then
  begin
    while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
    Eat(tkSemicolon);
    Exit;
  end;
  name := CurTok.SVal;
  Next;

  if CurTok.Kind <> tkLParen then
  begin
    while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
    Eat(tkSemicolon);
    Exit;
  end;
  Expect(tkLParen, '(');
  nparams := 0;
  while (CurTok.Kind <> tkRParen) and (CurTok.Kind <> tkEOF) do
  begin
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
        pelemtk[nparams] := CTypeElemTk;
        pelemrec[nparams] := CTypeElemRec;
        if CurTok.Kind = tkIdent then
        begin
          pnames[nparams] := CurTok.SVal;
          Next;
        end
        else
        begin
          pnames[nparams] := 'arg0';
          pnames[nparams][4] := Chr(Ord('0') + nparams);
        end;
        Inc(nparams);
      end;
    end
    else
      Next;
    Eat(tkComma);
  end;
  Expect(tkRParen, ')');
  
  isFunc := True; { In C, everything is a function }
  
  { Register or locate Proc }
  procIdx := FindProc(name);
  if procIdx < 0 then
    procIdx := RegisterProc(name, isFunc, retType, nparams, pnames, ptypes);
  for i := 0 to nparams - 1 do
    ProcParamPtrDepth[procIdx * 16 + i] := pdepths[i];
  ProcRetPtrElemTk[procIdx] := retPtrElemTk;
  ProcRetPtrElemRec[procIdx] := retPtrElemRec;

  { If it is just a declaration (ends with ';'), we are done! }
  while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkBegin) and
        (CurTok.Kind <> tkEOF) do Next;
  if CurTok.Kind = tkSemicolon then
  begin
    { Pure declaration (prototype). Mark external EXCEPT in a C-program pass 2,
      where pass 1 already settled linkage (a prototype + a later local
      definition => internal); re-marking here, before that definition is
      recompiled, would make an intervening caller emit an external call. }
    if not (CProgramMode and not CHeaderMode) then
    begin
      ProcExternal[procIdx] := True;
      ProcLibrary[procIdx] := InternStr(CurrentCLibrary);
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
      ProcLibrary[procIdx] := InternStr(CurrentCLibrary);
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
  Procs[procIdx].ScopeBase := SymCount;
  
  { Allocate parameter slots }
  for i := 0 to nparams-1 do
  begin
    idx := AllocParam(pnames[i], ptypes[i], False, False);
    Procs[procIdx].Params[i].SymIdx := idx;
    { Thread a pointer parameter's pointed-at type so `*p`, `p[i]`, and pointer
      arithmetic inside the body know the element stride/width. }
    if ptypes[i] = tyPointer then
    begin
      Syms[idx].PtrElemTk := IntToTypeKind(pelemtk[i]);
      Syms[idx].PtrElemRec := pelemrec[i];
    end;
  end;
  
  { Return value slot }
  AllocVar('Result', retType);
  Procs[procIdx].RetSymIdx := SymCount - 1;
  Syms[SymCount-1].Kind := skLocal;
  
  { Prologue }
  patchPos := EmitProcPrologue;
  Procs[procIdx].FramePatch := patchPos;
  
  { Copy registers to stack params }
  for i := 0 to nparams-1 do
  begin
    idx := Procs[procIdx].Params[i].SymIdx;
    sz := ParamSize(idx);
    if i < 4 then
    begin
      if sz = 1 then
      begin
        if (i = 0) or (i = 1) then EmitB($40); { REX prefix for dil, sil }
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

      case i of
        0: EmitB($BD);   { rdi }
        1: EmitB($B5);   { rsi }
        2: EmitB($95);   { rdx }
        3: EmitB($8D);   { rcx }
      end;
      EmitI32(Syms[idx].Offset);
    end
    else if i = 4 then
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
    else if i = 5 then
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
  end;
  
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

function CEvalConstPrimary: Int64;
var idx: Integer;
begin
  Result := 0;
  if CurTok.Kind = tkLParen then
  begin
    Next; Result := CEvalConstExpr;
    if CurTok.Kind = tkRParen then Next;
  end
  else if CurTok.Kind = tkMinus then begin Next; Result := -CEvalConstPrimary(); end
  else if CurTok.Kind = tkPlus then begin Next; Result := CEvalConstPrimary(); end
  else if CurTok.Kind = tkNot then begin Next; Result := not CEvalConstPrimary(); end
  else if CurTok.Kind = tkInteger then begin Result := CurTok.IVal; Next; end
  else if CurTok.Kind = tkIdent then
  begin
    idx := FindSym(CurTok.SVal);
    if (idx >= 0) and (Syms[idx].Kind = skConst) then Result := Syms[idx].ConstVal;
    Next;
  end;
end;

function CEvalConstMul: Int64;
begin
  Result := CEvalConstPrimary;
  while CurTok.Kind = tkStar do begin Next; Result := Result * CEvalConstPrimary; end;
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
    begin
      if depth >= 1 then begin Result := False; Exit; end;  { nested aggregate body }
      Inc(depth);
    end
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
      { Bitfields can't be laid out (wrong following offsets) -> opaque fallback.
        struct/union/enum keywords are now OK as field types (`struct Tag *next`,
        `enum E e`) because ParseCDeclType resolves a tag reference; an INLINE
        anonymous aggregate body is still rejected via the nested-brace check
        above. }
      if Tokens[i].Kind = tkColon then begin Result := False; Exit; end;
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
var
  curOff, maxAlign, fnOff, fnLen, arrLen, declStars, sz, al, totalSz, thisOff: Integer;
  baseScalarTk, baseElemTk, baseElemRec, baseRecId, declTk, declElemTk, declElemRec, declRec: Integer;
  fTk: TTypeKind;
  isArr, firstDecl: Boolean;
begin
  Next; { consume the opening brace }
  curOff := 0;
  maxAlign := 1;
  while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
  begin
    if IsCTypeTok then
    begin
      fTk := ParseCDeclType;
      { Recover the base scalar/struct before pointer folding, so comma
        declarators with differing pointer levels (`int *a, b`) are correct. }
      if CTypePtrDepth > 0 then
      begin
        baseScalarTk := CTypeElemTk;
        baseElemRec := CTypeElemRec;
      end
      else
      begin
        baseScalarTk := Ord(fTk);
        baseElemRec := REC_NONE;
      end;
      baseRecId := CTypeBaseRec;
      baseElemTk := baseScalarTk;

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

        isArr := False; arrLen := 1;
        while CurTok.Kind = tkLBrack do
        begin
          Next;
          if CurTok.Kind = tkInteger then begin arrLen := arrLen * CurTok.IVal; Next; end;
          while (CurTok.Kind <> tkRBrack) and (CurTok.Kind <> tkEOF) do Next;
          Eat(tkRBrack);
          isArr := True;
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
          declElemTk := Ord(tyUnknown); declElemRec := REC_NONE;
          sz := TypeSize(IntToTypeKind(baseScalarTk));
          al := TypeAlign(IntToTypeKind(baseScalarTk));
        end;
        if al < 1 then al := 1;

        if isUnion then thisOff := 0
        else thisOff := AlignTo(curOff, al);

        { AddUField reads LastTypePointerElemTk/Rec for pointer fields. Skip the
          record (but keep advancing the offset, so size stays correct) if the
          field pool is nearly full — avoids a hard overflow on a giant struct. }
        if UFldCount < MAX_UFIELD - 1 then
        begin
          LastTypePointerElemTk := IntToTypeKind(declElemTk);
          LastTypePointerElemRec := declElemRec;
          AddUField(ci, fnOff, fnLen, thisOff, declTk, declRec);
          UFldIsArray[UFldCount-1] := isArr;
          UFldArrLen[UFldCount-1] := arrLen;
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
    end
    else
      Next;  { skip nested struct/union defs, attributes, unknown tokens }
  end;
  Eat(tkEnd); { consume the closing brace }
  UClsSize_[ci] := AlignTo(curOff, maxAlign);
  UClsAlign[ci] := maxAlign;
end;

{ Parse a top-level `typedef ...;` and register the new type name.
  - struct/union [tag] [body] Name   -> opaque, mapped to Pointer
  - enum [tag] body Name             -> Int32, enumerators become constants
  - <decl-specifiers> Name           -> the mapped scalar/pointer type
  Function-pointer typedefs `ret (*Name)(args)` are detected and registered
  as Pointer; their argument signature is not yet modelled. }
procedure ParseCTypedef;
var tk: TTypeKind; nm, tagName: AnsiString; isAggregate, isUnion, hasTag: Boolean;
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
    { No body: opaque forward declaration — pointer-only handle.
      The declarator may carry a pointer: typedef struct _X *XRef; }
    while CurTok.Kind = tkStar do Next;
    if CurTok.Kind = tkIdent then
    begin
      nm := CurTok.SVal; Next;
      AddCTypedef(nm, tyPointer); { opaque aggregate: pointer-only }
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
  { function-pointer form: ret (*Name)(...) — the declarator name sits inside
    parens. Detect a '(' next and recover the name, registering as Pointer. }
  if CurTok.Kind = tkLParen then
  begin
    Next;
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
  if CurTok.Kind = tkIdent then
  begin
    nmOff := Tokens[TokPos-1].SOffset;
    nmLen := Tokens[TokPos-1].SLen;
    nm := CurTok.SVal; Next;
    { Carry the pointed-at type for a pointer typedef (e.g. typedef char *PStr),
      so a Pascal/nilpy var of that type is a typed pointer (deref/index). The
      PtrAlias makes it resolvable by Pascal's type parser (FindTypeAlias). }
    if (tk = tyPointer) and (CTypePtrDepth > 0) then
    begin
      AddCTypedefEx(nm, tk, CTypeElemTk, CTypeElemRec);
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
var i: Integer;
begin
  i := TokPos;
  if (i < TokCount) and (Tokens[i].Kind = tkIdent) then Inc(i);  { skip tag }
  Result := (i < TokCount) and (Tokens[i].Kind in [tkBegin, tkSemicolon]);
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
