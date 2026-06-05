{ ===== C Parser ===== }

function ParseCBlockAST: Integer; forward;
function ParseCStatementAST: Integer; forward;
procedure SkipBraceBlock; forward;

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

function ParseCStatementAST: Integer;
var node, exprNode: Integer;
begin
  Result := -1;
  if CurTok.Kind = tkEOF then Exit;

  { return [expr]; — the expression is optional for void functions }
  if CurTok.Kind = tkExit then
  begin
    Next;
    node := AllocNode(AN_EXIT);
    if CurTok.Kind <> tkSemicolon then
    begin
      ParseExpr;
      ASTLeft[node] := CurASTNode;
    end
    else
      ASTLeft[node] := -1;
    Eat(tkSemicolon);
    Result := node;
    Exit;
  end;

  { printf(...) }
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

  { skip type declarations and unknown statements }
  while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEnd) and
        (CurTok.Kind <> tkEOF) do Next;
  Eat(tkSemicolon);
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

procedure ParseCProgram;
var jmpPatch, node: Integer; name: AnsiString;
begin
  BSS_INITIAL_RSP := BSSSize; Inc(BSSSize, 8);

  EmitB($48); EmitB($89); EmitB($24); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
  EmitB($E9); jmpPatch := CodeLen; EmitI32(0);

  { Scan top level for 'main' function definition }
  while CurTok.Kind <> tkEOF do
  begin
    if IsCTypeTok then
    begin
      ParseCDeclType;  { consume return type incl. pointer suffix }
      if CurTok.Kind = tkIdent then
      begin
        name := CurTok.SVal;
        Next;
        if CurTok.Kind = tkLParen then
        begin
          { skip parameter list }
          while (CurTok.Kind <> tkRParen) and (CurTok.Kind <> tkEOF) do Next;
          Expect(tkRParen, ')');
          if CurTok.Kind = tkBegin then
          begin
            if name = 'main' then
            begin
              Patch32(jmpPatch, CodeLen - (jmpPatch + 4));
              node := ParseCBlockAST;
              CompileAST(node);
              EmitExit(0);
              ApplyCallFixups;
              Exit;
            end
            else
            begin
              { skip non-main function bodies for now }
              node := ParseCBlockAST;
            end;
          end;
        end
        else
        begin
          { global variable declaration — skip to ; }
          while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
          Eat(tkSemicolon);
        end;
      end;
    end
    else
      Next;
  end;
  Error('main function not found');
end;

procedure ParseCSubroutine;
var
  retType, ptype: TTypeKind;
  name: AnsiString;
  isFunc: Boolean;
  nparams, pi, i, idx, patchPos, sz: Integer;
  retPtrElemTk, retPtrElemRec: Integer;
  ptypes: array[0..15] of TTypeKind;
  pnames: array[0..15] of AnsiString;
  pdepths: array[0..15] of Integer;
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
  pi := FindProc(name);
  if pi < 0 then
    pi := RegisterProc(name, isFunc, retType, nparams, pnames, ptypes);
  for i := 0 to nparams - 1 do
    ProcParamPtrDepth[pi * 16 + i] := pdepths[i];
  ProcRetPtrElemTk[pi] := retPtrElemTk;
  ProcRetPtrElemRec[pi] := retPtrElemRec;

  { If it is just a declaration (ends with ';'), we are done! }
  while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkBegin) and
        (CurTok.Kind <> tkEOF) do Next;
  if CurTok.Kind = tkSemicolon then
  begin
    ProcExternal[pi] := True;
    ProcLibrary[pi] := InternStr(CurrentCLibrary);
    Next;
    Exit;
  end;

  if CHeaderMode then
  begin
    ProcExternal[pi] := True;
    ProcLibrary[pi] := InternStr(CurrentCLibrary);
    SkipBraceBlock;
    Exit;
  end;
  
  { Otherwise, it has a body! }
  ProcExternal[pi] := False;
  Procs[pi].BodyAddr := CodeLen;
  
  { Save scope }
  savedSC := SymCount;
  savedFS := FrameSize;
  FrameSize := 0;
  CurProc := pi;
  Procs[pi].ScopeBase := SymCount;
  
  { Allocate parameter slots }
  for i := 0 to nparams-1 do
  begin
    idx := AllocParam(pnames[i], ptypes[i], False, False);
    Procs[pi].Params[i].SymIdx := idx;
  end;
  
  { Return value slot }
  AllocVar('Result', retType);
  Procs[pi].RetSymIdx := SymCount - 1;
  Syms[SymCount-1].Kind := skLocal;
  
  { Prologue }
  patchPos := EmitProcPrologue;
  Procs[pi].FramePatch := patchPos;
  
  { Copy registers to stack params }
  for i := 0 to nparams-1 do
  begin
    idx := Procs[pi].Params[i].SymIdx;
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
  EmitProcEpilog(Procs[pi].RetSymIdx);
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
  C token stream. The C lexer does not produce distinct shift/bitwise tokens,
  so `<<` arrives as two tkLt, `>>` as two tkGt, `|` as tkOr, `&` as tkAnd.
  Precedence, low to high: | , & , << >> , + - , * , unary , primary.
  Unknown/unsupported tokens evaluate to 0 rather than derailing. }
function CEvalConstExpr: Int64; forward;

function CEvalConstPrimary: Int64;
var idx: Integer;
begin
  Result := 0;
  if CurTok.Kind = tkLParen then
  begin
    Next; Result := CEvalConstExpr;
    if CurTok.Kind = tkRParen then Next;
  end
  else if CurTok.Kind = tkMinus then begin Next; Result := -CEvalConstPrimary; end
  else if CurTok.Kind = tkPlus then begin Next; Result := CEvalConstPrimary; end
  else if CurTok.Kind = tkNot then begin Next; Result := not CEvalConstPrimary; end
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
  while (CurTok.Kind = tkLt) or (CurTok.Kind = tkGt) do
  begin
    if CurTok.Kind = tkLt then
    begin
      Next; if CurTok.Kind = tkLt then Next; { second '<' of '<<' }
      Result := Result shl CEvalConstAdd;
    end
    else
    begin
      Next; if CurTok.Kind = tkGt then Next; { second '>' of '>>' }
      Result := Result shr CEvalConstAdd;
    end;
  end;
end;

function CEvalConstAnd: Int64;
begin
  Result := CEvalConstShift;
  while CurTok.Kind = tkAnd do begin Next; Result := Result and CEvalConstShift; end;
end;

function CEvalConstExpr: Int64;
begin
  Result := CEvalConstAnd;
  while CurTok.Kind = tkOr do begin Next; Result := Result or CEvalConstAnd; end;
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
         (Tokens[t].Kind = tkLt) or (Tokens[t].Kind = tkGt) or
         (Tokens[t].Kind = tkOr) or (Tokens[t].Kind = tkAnd) or
         (Tokens[t].Kind = tkNot) then
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
          RegisterPtrAlias(nmOff, nmLen, Ord(tyRecord), REC_UCLASS_BASE + ci);
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
      RegisterPtrAlias(nmOff, nmLen, CTypeElemTk, CTypeElemRec);
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
