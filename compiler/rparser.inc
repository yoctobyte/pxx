{ SPDX-License-Identifier: MPL-2.0 }
{ ===== Rust Parser (skeleton) =====

  Scope (feature-rust-frontend-skeleton, sub-ticket 1/12 of the Rust umbrella):
  fn / let(+mut, no-op) / plain expressions+binops / if-else / while / loop /
  plain (non-generic, non-trait) struct / calls / return. No match, no
  generics, no traits, no enum-with-data, no impl blocks, no references — all
  deferred to later sub-tickets (see feature-rust-frontend.md). Lowers
  directly onto the existing shared AST nodes (AN_IF/AN_WHILE/AN_CALL/...),
  same shape as clexer.inc/cparser.inc and pylexer.inc/pyparser.inc.

  Two-pass, C-frontend-shaped: pass 1 registers struct layouts and function
  signatures (so forward calls resolve via FindProc without requiring
  top-to-bottom definition order); pass 2 re-walks the same tokens and
  compiles bodies.

  x86-64 only (no new backend/ABI work — ticket scope). Functions take at
  most 4 scalar params (rdi/rsi/rdx/rcx), matching the same limit
  pyparser.inc's Nil-Python frontend has. Struct-typed params/returns are
  explicitly rejected for now (RTypeKindFromName below) to keep the calling
  convention scalar-only; passing structs by value/reference is follow-up
  work, not this skeleton. }

function RParseExpr: Integer; forward;
function RParseBlock: Integer; forward;
function RParseStatement: Integer; forward;
function RParseIf: Integer; forward;

function RSeqAppend(head, stmt: Integer): Integer;
var tail: Integer;
begin
  Result := head;
  if stmt < 0 then Exit;
  if Result < 0 then
  begin
    Result := AllocNode(AN_SEQ);
    ASTLeft[Result] := stmt;
    ASTRight[Result] := -1;
    Exit;
  end;
  tail := Result;
  while ASTRight[tail] >= 0 do tail := ASTRight[tail];
  ASTRight[tail] := AllocNode(AN_SEQ);
  tail := ASTRight[tail];
  ASTLeft[tail] := stmt;
  ASTRight[tail] := -1;
end;

function RMakeIdent(symIdx: Integer): Integer;
begin
  Result := AllocNode(AN_IDENT);
  ASTIVal[Result] := symIdx;
  ASTTk[Result] := Ord(Syms[symIdx].TypeKind);
end;

{ Rust type name -> TTypeKind. Sets LastTypeRecId when the name is a known
  struct (the AllocVar/AddUField convention every frontend already uses to
  pass a record id alongside tyRecord). allowStruct=False rejects struct
  names — used for fn params/return types, keeping the call ABI scalar-only
  for this skeleton; allowStruct=True is for `let` annotations and struct
  fields (nested value-type structs are fine, they're just bytes). }
function RTypeKindFromName(const name: AnsiString; allowStruct: Boolean): TTypeKind;
var ci: Integer;
begin
  LastTypeRecId := REC_NONE;
  if name = 'i32' then begin Result := tyInteger; Exit; end;
  if name = 'i64' then begin Result := tyInt64; Exit; end;
  if name = 'u32' then begin Result := tyUInt32; Exit; end;
  if name = 'u64' then begin Result := tyUInt64; Exit; end;
  if name = 'isize' then begin Result := tyNativeInt; Exit; end;
  if name = 'usize' then begin Result := tyNativeUInt; Exit; end;
  if name = 'f32' then begin Result := tySingle; Exit; end;
  if name = 'f64' then begin Result := tyDouble; Exit; end;
  if name = 'bool' then begin Result := tyBoolean; Exit; end;
  if name = 'char' then begin Result := tyChar; Exit; end;
  ci := FindUClass(name);
  if ci >= 0 then
  begin
    if not allowStruct then
      Error('Rust: struct-typed parameters/return values are not supported by the frontend skeleton yet (feature-rust-frontend-skeleton)');
    LastTypeRecId := REC_UCLASS_BASE + ci;
    Result := tyRecord;
    Exit;
  end;
  Error('Rust: unknown type ' + name);
  Result := tyUnknown;
end;

function RWiden(a, b: TTypeKind): TTypeKind;
begin
  if (a = tyDouble) or (b = tyDouble) or (a = tySingle) or (b = tySingle) then Result := tyDouble
  else if (a = tyInt64) or (b = tyInt64) then Result := tyInt64
  else Result := tyInteger;
end;

function RBinOp(opTk: TTokenKind; left, right: Integer; resultTk: TTypeKind): Integer;
var node: Integer;
begin
  node := AllocNode(AN_BINOP);
  ASTIVal[node] := Ord(opTk);
  ASTLeft[node] := left;
  ASTRight[node] := right;
  ASTTk[node] := Ord(resultTk);
  Result := node;
end;

function RParsePrimary: Integer;
var node, fieldNode, symIdx, procIdx, argNode, lastArg, fTokIdx: Integer; name: AnsiString;
begin
  case CurTok.Kind of
    tkInteger:
    begin
      node := AllocNode(AN_INT_LIT); ASTIVal[node] := CurTok.IVal; ASTTk[node] := Ord(tyInteger);
      Next; Result := node;
    end;
    tkFloat:
    begin
      node := AllocNode(AN_FLOAT_LIT); ASTIVal[node] := CurTok.IVal; ASTTk[node] := Ord(tyDouble);
      Next; Result := node;
    end;
    tkTrue:
    begin
      node := AllocNode(AN_BOOL_LIT); ASTIVal[node] := 1; ASTTk[node] := Ord(tyBoolean);
      Next; Result := node;
    end;
    tkFalse:
    begin
      node := AllocNode(AN_BOOL_LIT); ASTIVal[node] := 0; ASTTk[node] := Ord(tyBoolean);
      Next; Result := node;
    end;
    tkLParen:
    begin
      Next; node := RParseExpr; Expect(tkRParen, ')'); Result := node;
    end;
    tkIdent:
    begin
      name := CurTok.SVal; Next;
      if CurTok.Kind = tkLParen then
      begin
        procIdx := FindProc(name);
        if procIdx < 0 then Error('Rust: call to undefined function ' + name);
        Next;
        node := AllocNode(AN_CALL);
        ASTIVal[node] := procIdx;
        ASTTk[node] := Ord(Procs[procIdx].RetType);
        lastArg := -1;
        if CurTok.Kind <> tkRParen then
          repeat
            argNode := AllocNode(AN_ARG);
            ASTLeft[argNode] := RParseExpr;
            ASTRight[argNode] := -1;
            if lastArg < 0 then ASTLeft[node] := argNode else ASTRight[lastArg] := argNode;
            lastArg := argNode;
          until not Eat(tkComma);
        Expect(tkRParen, ')');
        Result := node;
        Exit;
      end;
      symIdx := FindSym(name);
      if symIdx < 0 then Error('Rust: undefined variable ' + name);
      node := RMakeIdent(symIdx);
      if CurTok.Kind = tkDot then
      begin
        Next;
        if CurTok.Kind <> tkIdent then Error('Rust: expected field name after .');
        fTokIdx := TokPos - 1;
        fieldNode := AllocNode(AN_FIELD);
        ASTLeft[fieldNode] := node;
        ASTSOffset[fieldNode] := Tokens[fTokIdx].SOffset;
        ASTSLen[fieldNode] := Tokens[fTokIdx].SLen;
        ASTTk[fieldNode] := Ord(RecFieldType(Syms[symIdx].RecName, CurTok.SVal));
        node := fieldNode;
        Next;
      end;
      Result := node;
    end;
    else
    begin
      Error('Rust: unexpected token in expression');
      Result := -1;
    end;
  end;
end;

function RParseUnary: Integer;
var node: Integer;
begin
  if CurTok.Kind = tkMinus then
  begin
    Next;
    node := AllocNode(AN_NEG);
    ASTLeft[node] := RParseUnary;
    ASTTk[node] := ASTTk[ASTLeft[node]];
    Result := node;
    Exit;
  end;
  if CurTok.Kind = tkLogNot then
  begin
    Next;
    node := AllocNode(AN_NOT);
    ASTLeft[node] := RParseUnary;
    ASTTk[node] := Ord(tyBoolean);
    Result := node;
    Exit;
  end;
  Result := RParsePrimary;
end;

function RParseMul: Integer;
var left, right, node: Integer; opTk: TTokenKind;
begin
  left := RParseUnary;
  while CurTok.Kind in [tkStar, tkSlash, tkMod] do
  begin
    opTk := CurTok.Kind; Next;
    right := RParseUnary;
    node := RBinOp(opTk, left, right, RWiden(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])));
    left := node;
  end;
  Result := left;
end;

function RParseAdd: Integer;
var left, right, node: Integer; opTk: TTokenKind;
begin
  left := RParseMul;
  while CurTok.Kind in [tkPlus, tkMinus] do
  begin
    opTk := CurTok.Kind; Next;
    right := RParseMul;
    node := RBinOp(opTk, left, right, RWiden(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])));
    left := node;
  end;
  Result := left;
end;

function RParseCmp: Integer;
var left, right, node: Integer; opTk: TTokenKind;
begin
  left := RParseAdd;
  if CurTok.Kind in [tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe] then
  begin
    opTk := CurTok.Kind; Next;
    right := RParseAdd;
    node := RBinOp(opTk, left, right, tyBoolean);
    left := node;
  end;
  Result := left;
end;

function RParseAnd: Integer;
var left, right, node: Integer;
begin
  left := RParseCmp;
  while CurTok.Kind = tkAnd do
  begin
    Next;
    right := RParseCmp;
    node := RBinOp(tkAnd, left, right, tyBoolean);
    left := node;
  end;
  Result := left;
end;

function RParseExpr: Integer;
var left, right, node: Integer;
begin
  left := RParseAnd;
  while CurTok.Kind = tkOr do
  begin
    Next;
    right := RParseAnd;
    node := RBinOp(tkOr, left, right, tyBoolean);
    left := node;
  end;
  Result := left;
end;

function RParseIf: Integer;
var node, pairNode, condNode, thenNode, elseNode: Integer;
begin
  Next; { if }
  condNode := RParseExpr;
  Expect(tkBegin, '{');
  thenNode := RParseBlock;
  Expect(tkEnd, '}');
  elseNode := -1;
  if CurTok.Kind = tkElse then
  begin
    Next;
    if CurTok.Kind = tkIf then
      elseNode := RParseIf
    else
    begin
      Expect(tkBegin, '{');
      elseNode := RParseBlock;
      Expect(tkEnd, '}');
    end;
  end;
  pairNode := AllocNode(AN_PAIR);
  ASTLeft[pairNode] := thenNode;
  ASTRight[pairNode] := elseNode;
  node := AllocNode(AN_IF);
  ASTLeft[node] := condNode;
  ASTRight[node] := pairNode;
  Result := node;
end;

function RParseWhile: Integer;
var node: Integer;
begin
  Next; { while }
  node := AllocNode(AN_WHILE);
  ASTLeft[node] := RParseExpr;
  Expect(tkBegin, '{');
  ASTRight[node] := RParseBlock;
  Expect(tkEnd, '}');
  Result := node;
end;

function RParseLoop: Integer;
var node, condNode: Integer;
begin
  Next; { loop }
  Expect(tkBegin, '{');
  node := AllocNode(AN_WHILE);
  condNode := AllocNode(AN_BOOL_LIT); ASTIVal[condNode] := 1; ASTTk[condNode] := Ord(tyBoolean);
  ASTLeft[node] := condNode;
  ASTRight[node] := RParseBlock;
  Expect(tkEnd, '}');
  Result := node;
end;

{ `let [mut] name [: Type] [= expr];` — mut is accepted and ignored (no
  borrow/mutability enforcement, per the umbrella's non-goal list). Two RHS
  shapes: a plain scalar expression, or a struct literal `Type { f: v, ... }`
  which lowers to one AN_ASSIGN per field (no single-node "construct" op
  exists for value-type structs, so the declaration is really N field
  stores chained by AN_SEQ). Trailing `;` is left for the caller. }
function RParseLet: Integer;
var name, typeName: AnsiString; symIdx, ci, structCi, fTokIdx: Integer;
    annotTk: TTypeKind; hasType: Boolean;
    identNode, fieldNode, valNode, assignNode, seq: Integer;
begin
  Next; { let }
  if CurTok.Kind = tkMut then Next;
  if CurTok.Kind <> tkIdent then Error('Rust: expected variable name after let');
  name := CurTok.SVal; Next;
  hasType := False; annotTk := tyUnknown; structCi := -1;
  if CurTok.Kind = tkColon then
  begin
    Next;
    if CurTok.Kind <> tkIdent then Error('Rust: expected type after :');
    typeName := CurTok.SVal;
    structCi := FindUClass(typeName);
    annotTk := RTypeKindFromName(typeName, True);
    Next;
    hasType := True;
  end;
  if CurTok.Kind <> tkAssign then
  begin
    if not hasType then Error('Rust: let without initializer needs a type annotation');
    if annotTk = tyRecord then LastTypeRecId := REC_UCLASS_BASE + structCi;
    symIdx := AllocVar(name, annotTk);
    Result := -1;
    Exit;
  end;
  Next; { = }
  { struct literal RHS: `Type { field: expr, ... }` }
  if (CurTok.Kind = tkIdent) and (FindUClass(CurTok.SVal) >= 0) and (Tokens[TokPos].Kind = tkBegin) then
  begin
    ci := FindUClass(CurTok.SVal);
    Next; Expect(tkBegin, '{');
    LastTypeRecId := REC_UCLASS_BASE + ci;
    symIdx := AllocVar(name, tyRecord);
    identNode := RMakeIdent(symIdx);
    seq := -1;
    while CurTok.Kind <> tkEnd do
    begin
      if CurTok.Kind <> tkIdent then Error('Rust: expected field name in struct literal');
      fTokIdx := TokPos - 1;
      Next;
      Expect(tkColon, ':');
      valNode := RParseExpr;
      fieldNode := AllocNode(AN_FIELD);
      ASTLeft[fieldNode] := identNode;
      ASTSOffset[fieldNode] := Tokens[fTokIdx].SOffset;
      ASTSLen[fieldNode] := Tokens[fTokIdx].SLen;
      ASTTk[fieldNode] := Ord(RecFieldType(REC_UCLASS_BASE + ci, GetTokenStr(fTokIdx)));
      assignNode := AllocNode(AN_ASSIGN);
      ASTLeft[assignNode] := fieldNode;
      ASTRight[assignNode] := valNode;
      seq := RSeqAppend(seq, assignNode);
      if not Eat(tkComma) then Break;
    end;
    Expect(tkEnd, '}');
    Result := seq;
    Exit;
  end;
  { plain scalar initializer }
  valNode := RParseExpr;
  if hasType then
  begin
    if annotTk = tyRecord then Error('Rust: struct assignment from a non-literal expression is not supported by the skeleton yet');
    symIdx := AllocVar(name, annotTk);
  end
  else
    symIdx := AllocVar(name, IntToTypeKind(ASTTk[valNode]));
  identNode := RMakeIdent(symIdx);
  assignNode := AllocNode(AN_ASSIGN);
  ASTLeft[assignNode] := identNode;
  ASTRight[assignNode] := valNode;
  Result := assignNode;
end;

function RParseStatement: Integer;
var name, fname: AnsiString; symIdx, node, rhsNode, lhsNode, baseNode, fieldNode, fTokIdx: Integer;
begin
  case CurTok.Kind of
    tkIf: begin Result := RParseIf; Exit; end;
    tkWhile: begin Result := RParseWhile; Exit; end;
    tkLoop: begin Result := RParseLoop; Exit; end;
    tkBegin: begin Next; Result := RParseBlock; Expect(tkEnd, '}'); Exit; end;
    tkSemicolon: begin Next; Result := -1; Exit; end;
    tkLet: begin Result := RParseLet; Expect(tkSemicolon, ';'); Exit; end;
    tkExit:
    begin
      Next;
      node := AllocNode(AN_EXIT);
      if CurTok.Kind <> tkSemicolon then ASTLeft[node] := RParseExpr;
      Expect(tkSemicolon, ';');
      Result := node;
      Exit;
    end;
    tkBreak: begin Next; Expect(tkSemicolon, ';'); Result := AllocNode(AN_BREAK); Exit; end;
    tkContinue: begin Next; Expect(tkSemicolon, ';'); Result := AllocNode(AN_CONTINUE); Exit; end;
  end;

  if (CurTok.Kind = tkIdent) and (Tokens[TokPos].Kind = tkAssign) then
  begin
    name := CurTok.SVal;
    symIdx := FindSym(name);
    if symIdx < 0 then Error('Rust: assignment to undefined variable ' + name);
    Next; Expect(tkAssign, '=');
    rhsNode := RParseExpr;
    lhsNode := RMakeIdent(symIdx);
    node := AllocNode(AN_ASSIGN);
    ASTLeft[node] := lhsNode; ASTRight[node] := rhsNode;
    Expect(tkSemicolon, ';');
    Result := node;
    Exit;
  end;

  if (CurTok.Kind = tkIdent) and (Tokens[TokPos].Kind = tkDot) and
     (Tokens[TokPos + 1].Kind = tkIdent) and (Tokens[TokPos + 2].Kind = tkAssign) then
  begin
    name := CurTok.SVal;
    symIdx := FindSym(name);
    if symIdx < 0 then Error('Rust: assignment to undefined variable ' + name);
    Next; Next; { ident, . }
    fname := CurTok.SVal;
    fTokIdx := TokPos - 1;
    Next; Expect(tkAssign, '=');
    rhsNode := RParseExpr;
    baseNode := RMakeIdent(symIdx);
    fieldNode := AllocNode(AN_FIELD);
    ASTLeft[fieldNode] := baseNode;
    ASTSOffset[fieldNode] := Tokens[fTokIdx].SOffset;
    ASTSLen[fieldNode] := Tokens[fTokIdx].SLen;
    ASTTk[fieldNode] := Ord(RecFieldType(Syms[symIdx].RecName, fname));
    node := AllocNode(AN_ASSIGN);
    ASTLeft[node] := fieldNode; ASTRight[node] := rhsNode;
    Expect(tkSemicolon, ';');
    Result := node;
    Exit;
  end;

  Result := RParseExpr;
  Expect(tkSemicolon, ';');
end;

function RParseBlock: Integer;
var stmt: Integer;
begin
  Result := -1;
  while CurTok.Kind <> tkEnd do
  begin
    if CurTok.Kind = tkEOF then Error('Rust: unterminated block (missing })');
    stmt := RParseStatement;
    Result := RSeqAppend(Result, stmt);
  end;
end;

{ ===== Top-level: struct/fn signature prescan, then body compilation ===== }

procedure RRegisterStructShells;
var i: Integer;
begin
  for i := 0 to MainProgramTokCount - 2 do
    if (Tokens[i].Kind = tkRecord) and (Tokens[i + 1].Kind = tkIdent) and
       (FindUClass(GetTokenStr(i + 1)) < 0) then
      AddUClass(Tokens[i + 1].SOffset, Tokens[i + 1].SLen);
end;

procedure RRegisterStructFields;
var i, j, ci, curOff, sz, align, nameTokIdx: Integer; tk: TTypeKind;
begin
  i := 0;
  while i < MainProgramTokCount - 2 do
  begin
    if (Tokens[i].Kind = tkRecord) and (Tokens[i + 1].Kind = tkIdent) and (Tokens[i + 2].Kind = tkBegin) then
    begin
      ci := FindUClass(GetTokenStr(i + 1));
      UClsIsRecord[ci] := True;
      curOff := 0; align := 1;
      j := i + 3;
      while Tokens[j].Kind <> tkEnd do
      begin
        if Tokens[j].Kind <> tkIdent then Error('Rust: expected field name in struct ' + GetTokenStr(i + 1));
        nameTokIdx := j; Inc(j);
        if Tokens[j].Kind <> tkColon then Error('Rust: expected : after field name');
        Inc(j);
        if Tokens[j].Kind <> tkIdent then Error('Rust: expected field type');
        tk := RTypeKindFromName(GetTokenStr(j), True);
        Inc(j);
        sz := TypeSize(tk);
        if TypeAlign(tk) > align then align := TypeAlign(tk);
        curOff := AlignTo(curOff, TypeAlign(tk));
        AddUField(ci, Tokens[nameTokIdx].SOffset, Tokens[nameTokIdx].SLen, curOff, Ord(tk), LastTypeRecId);
        Inc(curOff, sz);
        if Tokens[j].Kind = tkComma then Inc(j);
      end;
      UClsAlign[ci] := align;
      UClsSize_[ci] := AlignTo(curOff, align);
    end;
    Inc(i);
  end;
end;

procedure RRegisterFnSignatures;
var i, j, depth, nparams: Integer; name: AnsiString;
    pnames: array[0..3] of AnsiString; ptypes: array[0..3] of TTypeKind;
    retType: TTypeKind;
begin
  depth := 0; i := 0;
  while i < MainProgramTokCount do
  begin
    if Tokens[i].Kind = tkBegin then Inc(depth)
    else if Tokens[i].Kind = tkEnd then Dec(depth)
    else if (depth = 0) and (Tokens[i].Kind = tkFn) and
            (Tokens[i + 1].Kind = tkIdent) and (Tokens[i + 2].Kind = tkLParen) then
    begin
      name := GetTokenStr(i + 1);
      j := i + 3; nparams := 0;
      while Tokens[j].Kind <> tkRParen do
      begin
        if Tokens[j].Kind = tkMut then Inc(j);
        if nparams >= 4 then Error('Rust: too many parameters (skeleton limit is 4)');
        if Tokens[j].Kind <> tkIdent then Error('Rust: expected parameter name in ' + name);
        pnames[nparams] := GetTokenStr(j); Inc(j);
        if Tokens[j].Kind <> tkColon then Error('Rust: expected : in parameter list');
        Inc(j);
        if Tokens[j].Kind <> tkIdent then Error('Rust: expected parameter type');
        ptypes[nparams] := RTypeKindFromName(GetTokenStr(j), False);
        Inc(j);
        Inc(nparams);
        if Tokens[j].Kind = tkComma then Inc(j);
      end;
      Inc(j); { consume ) }
      retType := tyInteger; { Rust's () return; unused Result slot, same trick C's void uses }
      if (Tokens[j].Kind = tkMinus) and (Tokens[j + 1].Kind = tkGt) then
      begin
        j := j + 2;
        if Tokens[j].Kind <> tkIdent then Error('Rust: expected return type after ->');
        retType := RTypeKindFromName(GetTokenStr(j), False);
      end;
      RegisterProc(name, True, retType, nparams, pnames, ptypes);
    end;
    Inc(i);
  end;
end;

procedure RParseTopLevelStruct;
begin
  Next; { struct }
  if CurTok.Kind <> tkIdent then Error('Rust: expected struct name');
  Next;
  Expect(tkBegin, '{');
  { fields were already registered by RRegisterStructFields; nothing left to
    compile for a plain value-type struct declaration. }
  while CurTok.Kind <> tkEnd do Next;
  Expect(tkEnd, '}');
end;

procedure RParseTopLevelFn;
var name, pname: AnsiString;
    procIdx, nparams, i, idx, savedSC, savedFS, patchPos, bodyNode: Integer;
    pnames: array[0..3] of AnsiString; ptypes: array[0..3] of TTypeKind;
begin
  Next; { fn }
  if CurTok.Kind <> tkIdent then Error('Rust: expected function name');
  name := CurTok.SVal; Next;
  procIdx := FindProc(name);
  if procIdx < 0 then Error('Rust: internal error — signature prescan missed ' + name);
  Expect(tkLParen, '(');
  nparams := 0;
  while CurTok.Kind <> tkRParen do
  begin
    if CurTok.Kind = tkMut then Next;
    if CurTok.Kind <> tkIdent then Error('Rust: expected parameter name');
    pname := CurTok.SVal; Next;
    Expect(tkColon, ':');
    if CurTok.Kind <> tkIdent then Error('Rust: expected parameter type');
    ptypes[nparams] := RTypeKindFromName(CurTok.SVal, False);
    pnames[nparams] := pname;
    Next;
    Inc(nparams);
    if not Eat(tkComma) then Break;
  end;
  Expect(tkRParen, ')');
  if CurTok.Kind = tkMinus then
  begin
    Next; Expect(tkGt, '>');
    if CurTok.Kind <> tkIdent then Error('Rust: expected return type after ->');
    Next;
  end;

  savedSC := SymCount; savedFS := FrameSize;
  FrameSize := 0; CurProc := procIdx;
  Procs[procIdx].BodyAddr := CodeLen;
  Procs[procIdx].ScopeBase := SymCount;
  for i := 0 to nparams - 1 do
  begin
    idx := AllocParam(pnames[i], ptypes[i], False, False);
    Procs[procIdx].Params[i].SymIdx := idx;
  end;
  idx := AllocVar('Result', Procs[procIdx].RetType);
  Procs[procIdx].RetSymIdx := idx;

  patchPos := EmitProcPrologue;
  Procs[procIdx].FramePatch := patchPos;
  for i := 0 to nparams - 1 do
  begin
    idx := Procs[procIdx].Params[i].SymIdx;
    if TypeSize(Syms[idx].TypeKind) = 8 then EmitB($48);
    EmitB($89);
    case i of
      0: EmitB($BD);
      1: EmitB($B5);
      2: EmitB($95);
      3: EmitB($8D);
    end;
    EmitI32(Syms[idx].Offset);
  end;

  Expect(tkBegin, '{');
  bodyNode := RParseBlock;
  Expect(tkEnd, '}');

  CompileAST(bodyNode);
  EmitProcEpilog(Procs[procIdx].RetSymIdx);
  PatchProcPrologue(patchPos, FrameSize);
  SymRollbackTo(savedSC);
  FrameSize := savedFS;
  CurProc := -1;
end;

procedure ParseRustProgram;
var callPatch, mainIdx: Integer;
begin
  if TargetArch <> TARGET_X86_64 then
    Error('Rust frontend: only the x86-64 target is supported by the skeleton (feature-rust-frontend-skeleton)');

  BSS_INITIAL_RSP := BSSSize; Inc(BSSSize, 8);
  { Entry stub: call main(), then exit_group(main's i32 return) — println!/
    process::exit are out of scope (sub-ticket 12), so the trivial test
    programs this skeleton targets report their result via exit code, same
    convention as a hosted C `int main()`. }
  EmitB($48); EmitB($89); EmitB($24); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
  EmitB($E8); callPatch := CodeLen; EmitI32(0);   { call main }
  EmitB($89); EmitB($C7);            { mov edi, eax }
  EmitB($B8); EmitI32(231);          { mov eax, 231 (exit_group) }
  EmitB($0F); EmitB($05);            { syscall }

  RRegisterStructShells;
  RRegisterStructFields;
  RRegisterFnSignatures;

  mainIdx := FindProc('main');
  if mainIdx < 0 then Error('Rust: no fn main() found');

  while CurTok.Kind <> tkEOF do
  begin
    if CurTok.Kind = tkRecord then RParseTopLevelStruct
    else if CurTok.Kind = tkFn then RParseTopLevelFn
    else Error('Rust: expected fn or struct at top level');
  end;

  ApplyCallFixups;
  Patch32(callPatch, Procs[mainIdx].BodyAddr - (callPatch + 4));
end;
