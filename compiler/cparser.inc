{ ===== C Parser ===== }

function ParseCBlockAST: Integer; forward;
function ParseCStatementAST: Integer; forward;

function FindCTypedef(const name: AnsiString): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to CTypedefCount-1 do
    if CTypedefName[i] = name then begin Result := i; Exit; end;
end;

procedure AddCTypedef(const name: AnsiString; tk: TTypeKind);
var idx: Integer;
begin
  idx := FindCTypedef(name);
  if idx >= 0 then begin CTypedefTk[idx] := Ord(tk); Exit; end;
  if CTypedefCount >= MAX_CTYPEDEF then Error('C typedef table overflow');
  CTypedefName[CTypedefCount] := name;
  CTypedefTk[CTypedefCount] := Ord(tk);
  Inc(CTypedefCount);
end;

function IsCTypeTok: Boolean;
begin
  Result := CurTok.Kind in [tkInteger_T, tkChar_T, tkCVoid, tkCShort,
    tkCLong, tkCSigned, tkCUnsigned, tkCFloat, tkCDouble, tkCBool, tkConst];
  if (not Result) and (CurTok.Kind = tkIdent) then
    Result := FindCTypedef(CurTok.SVal) >= 0;
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
  isUnsigned, isSigned, isFloatTy, isVoid, loop, sawBase, isTypedef: Boolean;
  shortCount, longCount, tdIdx: Integer;
  base: TTypeKind;
begin
  isUnsigned := False; isSigned := False; isFloatTy := False; isVoid := False;
  sawBase := False; isTypedef := False;
  shortCount := 0; longCount := 0; base := tyInt32;
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
      tkIdent:
        begin
          { A typedef name is a type only in type position (before any base
            type is seen); otherwise it is the declarator name — stop. }
          tdIdx := -1;
          if not sawBase then tdIdx := FindCTypedef(CurTok.SVal);
          if tdIdx >= 0 then
          begin
            base := IntToTypeKind(CTypedefTk[tdIdx]);
            sawBase := True; isTypedef := True;
            Next;
          end
          else loop := False;
        end;
      else loop := False;
    end;
  end;

  CTypeIsVoid := isVoid;

  if isVoid then
    Result := tyInteger          { placeholder; pointer suffix overrides below }
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

  { Any pointer depth collapses to an untyped 8-byte Pointer. }
  while CurTok.Kind = tkStar do
  begin
    Result := tyPointer;
    CTypeIsVoid := False;
    Next;
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
  ptypes: array[0..15] of TTypeKind;
  pnames: array[0..15] of AnsiString;
  savedSC, savedFS, node, savedCurProc: Integer;
begin
  retType := ParseCDeclType;
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

{ Consume a balanced { ... } block. CurTok must be at the opening tkBegin. }
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

{ Parse a top-level `typedef ...;` and register the new type name.
  - struct/union [tag] [{...}] Name  -> opaque, mapped to Pointer
  - enum [tag] {...} Name            -> Int32 (constants handled later)
  - <decl-specifiers> Name           -> the mapped scalar/pointer type
  Function-pointer typedefs `ret (*Name)(args)` are detected and registered
  as Pointer; their argument signature is not yet modelled. }
procedure ParseCTypedef;
var tk: TTypeKind; nm: AnsiString; isAggregate: Boolean;
begin
  Next; { consume 'typedef' }

  isAggregate := (CurTok.Kind = tkRecord) or
                 ((CurTok.Kind = tkIdent) and (CurTok.SVal = 'union'));
  if isAggregate then
  begin
    Next; { 'struct' / 'union' }
    if CurTok.Kind = tkIdent then Next;      { optional tag }
    if CurTok.Kind = tkBegin then SkipBraceBlock; { body, if present }
    { the declarator may carry a pointer: typedef struct _X *XRef; }
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
    if CurTok.Kind = tkBegin then SkipBraceBlock; { enumerator list }
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
    nm := CurTok.SVal; Next;
    AddCTypedef(nm, tk);
  end;
  while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
  Eat(tkSemicolon);
end;

procedure ParseCUnit;
begin
  while CurTok.Kind <> tkEOF do
  begin
    if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'typedef') then
      ParseCTypedef
    else if IsCTypeTok then
      ParseCSubroutine
    else
      Next;
  end;
end;
