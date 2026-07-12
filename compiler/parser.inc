{ SPDX-License-Identifier: MPL-2.0 }
{$ifdef FPC}
procedure LoadFile(const path: AnsiString; var dst: AnsiString); forward;
procedure LoadFileCI(const path: AnsiString; var dst: AnsiString); forward;
{$endif}
function GetFilePath(const path: AnsiString): AnsiString; forward;
function GetFileBaseName(const path: AnsiString): AnsiString; forward;
procedure NormalizePath(var p: AnsiString); forward;
procedure ExpandIncludes(var src: AnsiString; const baseDir: AnsiString); forward;
procedure ParseCUnit; forward;
procedure RegisterCMacroConsts; forward;
procedure EmitAnsiStringRuntime; forward;
procedure EmitDiv0Stub; forward;
procedure EmitSignalRuntime; forward;
procedure EmitIoLockStubs; forward;
procedure EmitIoLockStubs386; forward;
procedure EmitIoLockStubsA64; forward;
procedure EmitIoLockStubsArm32; forward;


function AllocNode(kind: Integer): Integer;
begin
  if ASTNodeCount >= INLINE_AST_BASE then Error('AST node overflow');
  ASTKind[ASTNodeCount]    := kind;
  ASTIVal[ASTNodeCount]    := 0;
  ASTSOffset[ASTNodeCount] := 0;
  ASTSLen[ASTNodeCount]    := 0;
  ASTLeft[ASTNodeCount]    := -1;
  ASTRight[ASTNodeCount]   := -1;
  ASTTk[ASTNodeCount]      := 0;
  ASTLiftedVar[ASTNodeCount] := -1;
  { DWARF -g: only stamp lines for nodes from the main source file. Tokens from
    appended units (builtin/RTL, lexed past DbgMainTokEnd) get line 0 so they
    contribute no rows — the Tier 1 line table describes one file. }
  if TokPos <= DbgMainTokEnd then
    ASTLine[ASTNodeCount] := CurTok.Line
  else
    ASTLine[ASTNodeCount] := 0;
  Result := ASTNodeCount;
  Inc(ASTNodeCount);
end;

{ Deep-copy an AST subtree. Copies the full per-node field set AllocNode
  initialises (the only AST-indexed arrays) and recurses on both children, so
  the clone is an independent tree. Used where a value node must appear in two
  places (e.g. a for-in container reused for both the Length bound and the
  element access) without the two occurrences aliasing one node. }
function CloneAST(node: Integer): Integer;
begin
  if node < 0 then begin Result := -1; Exit; end;
  Result := AllocNode(ASTKind[node]);
  ASTIVal[Result]     := ASTIVal[node];
  ASTSOffset[Result]  := ASTSOffset[node];
  ASTSLen[Result]     := ASTSLen[node];
  ASTTk[Result]       := ASTTk[node];
  ASTLiftedVar[Result] := ASTLiftedVar[node];
  ASTLine[Result]     := ASTLine[node];
  ASTLeft[Result]     := CloneAST(ASTLeft[node]);
  ASTRight[Result]    := CloneAST(ASTRight[node]);
end;

{ ===== Inline routine expansion (feature-inline-routines) =====
  v1: a leaf function whose body is a single `Result := E` over scalar-by-value
  params, E a whitelist of int/ordinal literals + param/global/const idents +
  arithmetic/logical operators. E is retained in the reserved AST region with
  param idents rewritten to AN_INLINE_PARAM placeholders; a direct call site
  clones it back with the placeholders bound to fresh arg temps (ir.inc). All
  gated OptLevel>=2, so -O0/-O1 stay byte-identical. }

{ Scalar int/ptr/ordinal test (parser-local; RegcallScalarType lives in the later
  ir_codegen.inc). Matches the residency notion of a register-sized scalar. }
function InlineScalarTk(tk: TTypeKind): Boolean;
begin
  InlineScalarTk :=
    (tk = tyInteger) or (tk = tyBoolean) or (tk = tyChar) or
    ((tk >= tyInt8) and (tk <= tyNativeUInt)) or (tk = tyPointer);
end;

{ Param index of symIdx within procIdx's params, or -1. }
function InlineParamIndexOf(procIdx, symIdx: Integer): Integer;
var i: Integer;
begin
  InlineParamIndexOf := -1;
  for i := 0 to Procs[procIdx].ParamCount - 1 do
    if Procs[procIdx].Params[i].SymIdx = symIdx then
    begin InlineParamIndexOf := i; Exit; end;
end;

{ Is E built only from inline-safe nodes (literals, params, scalar globals/consts,
  arithmetic/logical operators)? Rejects calls, indexing, fields, managed/float,
  and any ident that is not allowed. `allowLocals` additionally permits a scalar
  callee local (slice 2b). `retSym` (>=0) is the Result symbol whose READ is
  forbidden (Result may only be an assignment target, never read — avoids the
  uninitialised-Result hazard). }
function InlineExprSimple(node, procIdx: Integer; allowLocals: Boolean; retSym: Integer): Boolean;
var idx: Integer;
begin
  InlineExprSimple := False;
  if node < 0 then begin InlineExprSimple := True; Exit; end;  { absent child = ok }
  case ASTKind[node] of
    AN_INT_LIT:
      InlineExprSimple := True;
    AN_IDENT:
      begin
        idx := ASTIVal[node];
        if (idx < 0) or (idx >= SymCount) then Exit;
        if idx = retSym then Exit;                     { Result-read not allowed }
        if Syms[idx].IsArray then Exit;
        if not InlineScalarTk(Syms[idx].TypeKind) then Exit;
        if InlineParamIndexOf(procIdx, idx) >= 0 then
          InlineExprSimple := True
        else if (Syms[idx].Kind = skGlobal) or (Syms[idx].Kind = skConst) then
          InlineExprSimple := True
        else if allowLocals and (Syms[idx].Kind = skLocal) then
          InlineExprSimple := True;
      end;
    AN_BINOP, AN_NEG, AN_NOT:
      InlineExprSimple := InlineExprSimple(ASTLeft[node], procIdx, allowLocals, retSym) and
                          InlineExprSimple(ASTRight[node], procIdx, allowLocals, retSym);
  end;
end;

{ Alloc a node in the reserved inline AST region; -1 on overflow. }
function AllocInlineNode(kind: Integer): Integer;
begin
  if InlineASTNext >= MAX_AST then begin AllocInlineNode := -1; Exit; end;
  ASTKind[InlineASTNext]     := kind;
  ASTIVal[InlineASTNext]     := 0;
  ASTSOffset[InlineASTNext]  := 0;
  ASTSLen[InlineASTNext]     := 0;
  ASTLeft[InlineASTNext]     := -1;
  ASTRight[InlineASTNext]    := -1;
  ASTTk[InlineASTNext]       := 0;
  ASTLiftedVar[InlineASTNext] := -1;
  ASTLine[InlineASTNext]     := 0;
  AllocInlineNode := InlineASTNext;
  Inc(InlineASTNext);
end;

{ Deep-copy E into the reserved region, rewriting each param ident into an
  AN_INLINE_PARAM placeholder (IVal = param index). -1 on overflow (caller bails). }
function RetLocalIndexOf(sym: Integer): Integer;
var j: Integer;
begin
  RetLocalIndexOf := -1;
  for j := 0 to RetLocalCnt - 1 do
    if RetLocalSym[j] = sym then begin RetLocalIndexOf := j; Exit; end;
end;

function CloneToInlineRegion(node, procIdx: Integer): Integer;
var r, pidx, lidx: Integer;
begin
  if node < 0 then begin CloneToInlineRegion := -1; Exit; end;
  if ASTKind[node] = AN_IDENT then
  begin
    pidx := InlineParamIndexOf(procIdx, ASTIVal[node]);
    if pidx >= 0 then
    begin
      r := AllocInlineNode(AN_INLINE_PARAM);
      if r < 0 then begin CloneToInlineRegion := -1; Exit; end;
      ASTIVal[r] := pidx;
      ASTTk[r]   := ASTTk[node];
      CloneToInlineRegion := r;
      Exit;
    end;
    { slice 2b: Result and local placeholders (Ret* context set by the caller). }
    if (RetResSym >= 0) and (ASTIVal[node] = RetResSym) then
    begin
      r := AllocInlineNode(AN_INLINE_RESULT);
      if r < 0 then begin CloneToInlineRegion := -1; Exit; end;
      ASTTk[r] := ASTTk[node];
      CloneToInlineRegion := r;
      Exit;
    end;
    lidx := RetLocalIndexOf(ASTIVal[node]);
    if lidx >= 0 then
    begin
      r := AllocInlineNode(AN_INLINE_LOCAL);
      if r < 0 then begin CloneToInlineRegion := -1; Exit; end;
      ASTIVal[r] := lidx;
      ASTTk[r]   := ASTTk[node];
      CloneToInlineRegion := r;
      Exit;
    end;
  end;
  r := AllocInlineNode(ASTKind[node]);
  if r < 0 then begin CloneToInlineRegion := -1; Exit; end;
  ASTIVal[r]    := ASTIVal[node];
  ASTSOffset[r] := ASTSOffset[node];
  ASTSLen[r]    := ASTSLen[node];
  ASTTk[r]      := ASTTk[node];
  if ASTLeft[node] >= 0 then
  begin
    ASTLeft[r] := CloneToInlineRegion(ASTLeft[node], procIdx);
    if ASTLeft[r] < 0 then begin CloneToInlineRegion := -1; Exit; end;
  end;
  if ASTRight[node] >= 0 then
  begin
    ASTRight[r] := CloneToInlineRegion(ASTRight[node], procIdx);
    if ASTRight[r] < 0 then begin CloneToInlineRegion := -1; Exit; end;
  end;
  CloneToInlineRegion := r;
end;

{ Build a retained AN_TERNARY(cond ? thenE : elseE) in the inline region from
  three source expressions, rewriting param idents to placeholders. -1 on
  overflow. Used to inline an `if c then Result:=A else Result:=B` one-liner as a
  value-bearing conditional (slice 2a). }
function BuildInlineTernary(cond, thenE, elseE, procIdx, retTk: Integer): Integer;
var t, pair, cc, aa, bb: Integer;
begin
  BuildInlineTernary := -1;
  cc := CloneToInlineRegion(cond, procIdx);   if cc < 0 then Exit;
  aa := CloneToInlineRegion(thenE, procIdx);  if aa < 0 then Exit;
  bb := CloneToInlineRegion(elseE, procIdx);  if bb < 0 then Exit;
  pair := AllocInlineNode(AN_PAIR);           if pair < 0 then Exit;
  ASTLeft[pair] := aa; ASTRight[pair] := bb;
  t := AllocInlineNode(AN_TERNARY);           if t < 0 then Exit;
  ASTLeft[t] := cc; ASTRight[t] := pair; ASTTk[t] := retTk;
  BuildInlineTernary := t;
end;

{ Walk a shape-3 RHS expression; every callee-local read (RetLocal map) must
  already be marked written in InlineWrittenLocal (read-before-write guard). }
function InlineStmtRhsLocalsWritten(node: Integer): Boolean;
var lidx: Integer;
begin
  InlineStmtRhsLocalsWritten := False;
  if node < 0 then begin InlineStmtRhsLocalsWritten := True; Exit; end;
  if ASTKind[node] = AN_IDENT then
  begin
    lidx := RetLocalIndexOf(ASTIVal[node]);
    if (lidx >= 0) and (not InlineWrittenLocal[lidx]) then Exit;
    InlineStmtRhsLocalsWritten := True;
    Exit;
  end;
  InlineStmtRhsLocalsWritten := InlineStmtRhsLocalsWritten(ASTLeft[node]) and
                                InlineStmtRhsLocalsWritten(ASTRight[node]);
end;

{ Slice 2b (-O3): retain a STRAIGHT-LINE multi-statement body — an AN_SEQ chain
  where every statement is `local := E` or `Result := E`, E over params / scalar
  globals-consts / already-written locals, no branches, no Result read, Result
  written at least once. All locals scalar ordinal. Retains the whole chain with
  param/local/Result idents rewritten to placeholders. }
procedure TryRetainInlineStmtBody(procIdx, bodyNode, retSym: Integer);
var i, j, seqN, stmtN, lhsN, rhsN, startNext, cloned, resultWrites, lidx: Integer;
begin
  if OptLevel < 2 then Exit;                 { -O2 (promoted from -O3 once proven) }
  { Enumerate scalar callee locals (excluding Result) → the Ret* placeholder map. }
  RetLocalCnt := 0;
  for i := Procs[procIdx].ScopeBase to SymCount - 1 do
  begin
    if Syms[i].Kind <> skLocal then Continue;
    if i = retSym then Continue;
    if Syms[i].IsArray then Exit;
    if not InlineScalarTk(Syms[i].TypeKind) then Exit;
    if RetLocalCnt >= MAX_INLINE_LOCALS then Exit;
    RetLocalSym[RetLocalCnt] := i;
    Inc(RetLocalCnt);
  end;
  RetResSym := retSym;
  { Validate the chain. }
  for j := 0 to RetLocalCnt - 1 do InlineWrittenLocal[j] := False;
  resultWrites := 0;
  seqN := bodyNode;
  while seqN <> -1 do
  begin
    if ASTKind[seqN] <> AN_SEQ then Exit;
    stmtN := ASTLeft[seqN];
    if (stmtN < 0) or (ASTKind[stmtN] <> AN_ASSIGN) then Exit;
    lhsN := ASTLeft[stmtN];
    rhsN := ASTRight[stmtN];
    if (lhsN < 0) or (ASTKind[lhsN] <> AN_IDENT) then Exit;
    if not InlineExprSimple(rhsN, procIdx, True, retSym) then Exit;
    if not InlineStmtRhsLocalsWritten(rhsN) then Exit;
    if ASTIVal[lhsN] = retSym then
      Inc(resultWrites)
    else
    begin
      lidx := RetLocalIndexOf(ASTIVal[lhsN]);
      if lidx < 0 then Exit;                 { LHS is neither Result nor a tracked local }
      InlineWrittenLocal[lidx] := True;
    end;
    seqN := ASTRight[seqN];
  end;
  if resultWrites < 1 then Exit;
  { Retain the whole chain. }
  startNext := InlineASTNext;
  if InlineASTNext + 256 >= MAX_AST then Exit;
  cloned := CloneToInlineRegion(bodyNode, procIdx);
  if cloned < 0 then begin InlineASTNext := startNext; Exit; end;
  if InlineASTNext - startNext > 256 then begin InlineASTNext := startNext; Exit; end;
  InlineBodyRoot[procIdx]   := cloned;
  InlineBodyIsStmt[procIdx] := True;
  InlineParamCnt[procIdx]   := Procs[procIdx].ParamCount;
  InlineLocalCnt[procIdx]   := RetLocalCnt;
  for j := 0 to RetLocalCnt - 1 do
    InlineLocalTk[procIdx*MAX_INLINE_LOCALS + j] := Ord(Syms[RetLocalSym[j]].TypeKind);
end;

{ If bodyNode is an inline-eligible function body, retain it. Handles: pure-
  expression `Result := E`, `if c then Result:=A else Result:=B` (AN_TERNARY),
  and (slice 2b, -O3) a straight-line multi-statement body. Called at the
  definition, after the body AST is parsed. OptLevel>=2 only. }
procedure TryRetainInlineBody(procIdx, bodyNode: Integer);
var seqNode, stmt, lhs, rhs, i, startNext, retSym: Integer;
    pair, thenA, elseA, condN, aE, bE: Integer;
begin
  if OptLevel < 2 then Exit;
  if procIdx < 0 then Exit;
  if not Procs[procIdx].IsFunc then Exit;
  if ProcExternal[procIdx] or ProcCdecl[procIdx] or ProcVariadic[procIdx] then Exit;
  if ProcIsGenerator[procIdx] or ProcIsStackless[procIdx] then Exit;
  if Procs[procIdx].ParamCount > 6 then Exit;
  { Result must be a scalar. }
  retSym := Procs[procIdx].RetSymIdx;
  if retSym < 0 then Exit;
  if not InlineScalarTk(Syms[retSym].TypeKind) then Exit;
  { Every param scalar, by value. }
  for i := 0 to Procs[procIdx].ParamCount - 1 do
  begin
    if Procs[procIdx].Params[i].IsRef or Procs[procIdx].Params[i].IsArray then Exit;
    if not InlineScalarTk(Procs[procIdx].Params[i].TypeKind) then Exit;
  end;
  { Body shape: ParseBlockAST returns an AN_SEQ chain. Shapes 1 & 2a are a single
    statement (Right=-1); shape 3 (slice 2b, -O3) is a straight-line multi-
    statement chain. The Ret* context defaults to neutral so shapes 1/2a never
    emit local/Result placeholders. }
  if bodyNode < 0 then Exit;
  if ASTKind[bodyNode] <> AN_SEQ then Exit;
  RetLocalCnt := 0;
  RetResSym := -1;
  seqNode := bodyNode;
  stmt := ASTLeft[seqNode];
  if stmt < 0 then Exit;

  if (ASTRight[seqNode] = -1) and (ASTKind[stmt] = AN_ASSIGN) then
  begin
    { Shape 1: `Result := E`. }
    lhs := ASTLeft[stmt];
    rhs := ASTRight[stmt];
    if (lhs < 0) or (ASTKind[lhs] <> AN_IDENT) or (ASTIVal[lhs] <> retSym) then Exit;
    if not InlineExprSimple(rhs, procIdx, False, retSym) then Exit;
    startNext := InlineASTNext;
    if InlineASTNext + 48 >= MAX_AST then Exit;    { budget guard }
    i := CloneToInlineRegion(rhs, procIdx);
    if i < 0 then begin InlineASTNext := startNext; Exit; end;
    if InlineASTNext - startNext > 48 then begin InlineASTNext := startNext; Exit; end;
    InlineBodyRoot[procIdx] := i;
    InlineParamCnt[procIdx] := Procs[procIdx].ParamCount;
  end
  else if (ASTRight[seqNode] = -1) and (ASTKind[stmt] = AN_IF) then
  begin
    { Shape 2a: `if C then Result:=A else Result:=B` -> AN_TERNARY(C?A:B). }
    condN := ASTLeft[stmt];
    pair := ASTRight[stmt];
    if (pair < 0) or (ASTKind[pair] <> AN_PAIR) then Exit;
    thenA := ASTLeft[pair];
    elseA := ASTRight[pair];
    if (thenA < 0) or (elseA < 0) then Exit;         { both arms present (has else) }
    if (ASTKind[thenA] <> AN_ASSIGN) or (ASTKind[elseA] <> AN_ASSIGN) then Exit;
    if (ASTKind[ASTLeft[thenA]] <> AN_IDENT) or (ASTIVal[ASTLeft[thenA]] <> retSym) then Exit;
    if (ASTKind[ASTLeft[elseA]] <> AN_IDENT) or (ASTIVal[ASTLeft[elseA]] <> retSym) then Exit;
    aE := ASTRight[thenA];
    bE := ASTRight[elseA];
    if not InlineExprSimple(condN, procIdx, False, retSym) then Exit;
    if not InlineExprSimple(aE, procIdx, False, retSym) then Exit;
    if not InlineExprSimple(bE, procIdx, False, retSym) then Exit;
    startNext := InlineASTNext;
    if InlineASTNext + 96 >= MAX_AST then Exit;
    i := BuildInlineTernary(condN, aE, bE, procIdx, Ord(Syms[retSym].TypeKind));
    if i < 0 then begin InlineASTNext := startNext; Exit; end;
    if InlineASTNext - startNext > 96 then begin InlineASTNext := startNext; Exit; end;
    InlineBodyRoot[procIdx] := i;
    InlineParamCnt[procIdx] := Procs[procIdx].ParamCount;
  end
  else
    TryRetainInlineStmtBody(procIdx, bodyNode, retSym);
end;

{ DWARF -g (Tier 3): snapshot one symbol into the DbgVar side table. Symbol
  slots recycle across procs, so this must run while the proc's scope is live.
  Filters compiler-internal slots (hidden temps, __-prefixed, Result-less). }
procedure DbgRecordVar(procIdx, symIdx: Integer; isGlobal: Boolean);
var nm: AnsiString;
begin
  if not DebugInfo then Exit;
  if DbgVarCount >= MAX_DBG_VARS then Exit;
  if not (Syms[symIdx].Kind in [skLocal, skGlobal, skParam]) then Exit;
  if SymIsHiddenArgTemp[symIdx] then Exit;
  nm := Syms[symIdx].Name;
  if Length(nm) = 0 then Exit;
  if (Length(nm) >= 2) and (nm[1] = '_') and (nm[2] = '_') then Exit;
  DbgVarProc[DbgVarCount]     := procIdx;
  DbgVarName[DbgVarCount]     := nm;
  DbgVarTk[DbgVarCount]       := Ord(Syms[symIdx].TypeKind);
  DbgVarRec[DbgVarCount]      := Syms[symIdx].RecName;
  DbgVarOff[DbgVarCount]      := Syms[symIdx].Offset;
  DbgVarIsParam[DbgVarCount]  := Syms[symIdx].Kind = skParam;
  DbgVarIsGlobal[DbgVarCount] := isGlobal;
  DbgVarIsRef[DbgVarCount]    := Syms[symIdx].IsRef;
  DbgVarIsArray[DbgVarCount]  := Syms[symIdx].IsArray;
  DbgVarArrLen[DbgVarCount]   := Syms[symIdx].ArrLen;
  DbgVarElemTk[DbgVarCount]   := Ord(Syms[symIdx].ElemType);
  DbgVarElemRec[DbgVarCount]  := Syms[symIdx].ElemRecName;
  Inc(DbgVarCount);
end;

{ Snapshot all params+locals of a proc (its live scope = ScopeBase..SymCount-1). }
procedure DbgCaptureProcLocals(procIdx: Integer);
var i: Integer;
begin
  if not DebugInfo then Exit;
  for i := Procs[procIdx].ScopeBase to SymCount - 1 do
    DbgRecordVar(procIdx, i, False);
end;

procedure InferSymTypeFromNode(symIdx: Integer; node: Integer);
var tk: TTypeKind; procIdx, recId, varIdx: Integer;
begin
  tk := IntToTypeKind(ASTTk[node]);
  Syms[symIdx].TypeKind := tk;
  
  if tk = tyRecord then
    Syms[symIdx].RecName := ResolveNodeRec(node)
  else if tk = tyClass then
    Syms[symIdx].RecName := ResolveNodeRec(node)
  else if tk = tyPointer then
  begin
    { If it's an identifier }
    if ASTKind[node] = AN_IDENT then
    begin
      varIdx := ASTIVal[node];
      if (varIdx >= 0) and (varIdx < SymCount) then
      begin
        Syms[symIdx].PtrElemTk := Syms[varIdx].PtrElemTk;
        Syms[symIdx].PtrElemRec := Syms[varIdx].PtrElemRec;
      end;
    end
    { If it's a field }
    else if ASTKind[node] = AN_FIELD then
    begin
      recId := ResolveNodeRec(ASTLeft[node]);
      if recId <> REC_NONE then
      begin
        Syms[symIdx].PtrElemTk := RecFieldPtrElemTk(recId, GetASTIdentName(node));
        Syms[symIdx].PtrElemRec := RecFieldPtrElemRec(recId, GetASTIdentName(node));
      end;
    end
    { If it's a function call }
    else if ASTKind[node] = AN_CALL then
    begin
      procIdx := ASTIVal[node];
      if (procIdx >= 0) and (procIdx < ProcCount) then
      begin
        Syms[symIdx].PtrElemTk := IntToTypeKind(ProcRetPtrElemTk[procIdx]);
        Syms[symIdx].PtrElemRec := ProcRetPtrElemRec[procIdx];
      end;
    end
    { If it's a typecast }
    else if ASTKind[node] = AN_PTR_CAST then
    begin
      if ASTIVal[node] = -2 then
      begin
        Syms[symIdx].PtrElemTk := tyChar;
        Syms[symIdx].PtrElemRec := REC_NONE;
      end
      else if ASTIVal[node] >= 0 then
      begin
        Syms[symIdx].PtrElemTk := IntToTypeKind(AliasElemTk[ASTIVal[node]]);
        Syms[symIdx].PtrElemRec := AliasElemRec[ASTIVal[node]];
      end;
    end
    { If it's an address-of operator }
    else if ASTKind[node] = AN_ADDR then
    begin
      Syms[symIdx].PtrElemTk := IntToTypeKind(ASTTk[ASTLeft[node]]);
      if (Syms[symIdx].PtrElemTk = tyRecord) or (Syms[symIdx].PtrElemTk = tyClass) then
        Syms[symIdx].PtrElemRec := ResolveNodeRec(ASTLeft[node]);
    end;
  end;
end;

procedure AllocateSymOffset(idx: Integer);
var sz, align: Integer; tk: TTypeKind;
begin
  tk := Syms[idx].TypeKind;
  sz := TypeSize(tk);
  if tk = tyString then
  begin
    if Syms[idx].Kind = skGlobal then sz := STRING_CAP + 8
    else sz := LOCAL_STR_CAP + 8;
  end
  else if tk = tyRecord then sz := RecSize(Syms[idx].RecName);
  if (tk = tyRecord) and (Syms[idx].RecName >= REC_UCLASS_BASE) and
     (UClsAlign[Syms[idx].RecName - REC_UCLASS_BASE] > TARGET_PTR_SIZE) then
    align := UClsAlign[Syms[idx].RecName - REC_UCLASS_BASE]
  else
    align := TypeAlign(tk);

  if Syms[idx].Kind = skGlobal then
  begin
    BSSSize := AlignTo(BSSSize, align);
    Syms[idx].Offset := BSSSize;
    Inc(BSSSize, sz);
  end
  else
  begin
    FrameSize := AlignTo(FrameSize + sz, align);
    Syms[idx].Offset := -FrameSize;
  end;
end;

function GetTokenStr(idx: Integer): AnsiString;
var s: AnsiString; i: Integer;
begin
  s := '';
  if (idx >= 0) and (idx < TokCount) then
  begin
    for i := Tokens[idx].SOffset to Tokens[idx].SOffset + Tokens[idx].SLen - 1 do
      AppendChar(s, TokChars[i]);
  end;
  Result := s;
end;

procedure ParseExpr; forward;
procedure PyParseBoolExpr; forward;  { Nil Python boolean layer (defined in pyparser.inc) }

{ Read/Write/Readln/Writeln are intrinsics resolved by context at the call site,
  not true reserved words — FPC lets a user declaration shadow them. Accept them
  (and plain identifiers) where a member/method NAME is expected, so e.g.
  TStream.Read / TStream.Write can be declared. The token's SVal carries the
  text, so name capture is unchanged. }
function IsMemberNameTok: Boolean;
begin
  IsMemberNameTok := (CurTok.Kind = tkIdent) or (CurTok.Kind = tkRead) or
    (CurTok.Kind = tkwrite) or (CurTok.Kind = tkReadln) or (CurTok.Kind = tkwriteln) or
    (CurTok.Kind = tkArgCount) or (CurTok.Kind = tkArgStr);   { ParamCount/ParamStr as member names (FPC custapp) }
end;

{ Predefined routines are not reserved words. In declaration-name position they
  must behave like ordinary identifiers so user parameters can shadow Chr/Ord,
  Length, Read/Write, etc. }
function IsDeclNameTok: Boolean;
begin
  if IsMemberNameTok then
  begin
    IsDeclNameTok := True;
    Exit;
  end;
  case CurTok.Kind of
    tkSysOpen, tkSysRead, tkSyswrite, tkSysClose, tkSysFchmod,
    tkArgCount, tkArgStr:
      IsDeclNameTok := True;
  else
    IsDeclNameTok := False;
  end;
end;

{ Resolve a (possibly dotted) unit qualifier at the front of a reference:
  `Unit.Member` or `Posix.SysSocket.Member`. Greedily matches the LONGEST dotted
  prefix that is a compiled unit and still leaves a trailing `.member`, so a
  namespace unit (`Posix.SysSocket`) wins over its first component. Returns the
  unit index and leaves the parser ON the member name; returns -1 and consumes
  nothing when the leading name is not a compiled unit (e.g. `record.field`). }
function ConsumeUnitQualifier(var name: AnsiString): Integer;
var cand: AnsiString; bestUnit, bestExtra, extra, ti, k, u: Integer;
begin
  Result := -1;
  if CurTok.Kind <> tkIdent then Exit;
  { Need at least one `.ident` after the name to be a qualifier at all. }
  if not ((TokPos + 1 < TokCount) and (Tokens[TokPos].Kind = tkDot) and
          (Tokens[TokPos + 1].Kind = tkIdent)) then Exit;

  { `System.X` — pxx has no separate System unit (System IS the builtin layer).
    Strip the qualifier so FPC's `System.Move(...)` / `System.FreeMem` resolve
    exactly like the bare name. Only when nothing real is named System (a
    loaded unit wins below; a local/record var named System wins here). }
  if CaseEqual(name, 'System') and (FindUnitOrAlias(name) < 0) and
     (FindSym(name) < 0) then
  begin
    Next;                 { consume 'System' (CurTok -> '.') }
    Expect(tkDot, '.');   { consume '.'      (CurTok -> member) }
    name := CurTok.SVal;
    Result := -2;         { SYSTEM marker: like unqualified (-1) everywhere,
                            but the builtin soft-aliases must WIN over a
                            same-named method of the enclosing class —
                            TFPSList.Delete's System.Move(...) names the
                            builtin precisely because the class has its own
                            Move(CurIndex, NewIndex). }
    Exit;
  end;

  { A local/param/global SYMBOL shadows a same-named unit (FPC scoping):
    `function NetToHost(Net: in_addr)...` must keep `Net.s_addr` a record
    field access even when unit net.pas is loaded — the qualifier greedily
    ate the param and s_addr resolved against the unit (undefined). }
  if FindSym(name) >= 0 then Exit;

  cand := name;
  bestUnit := -1; bestExtra := -1;
  { 0-extra: the bare name is the unit, member = Tokens[TokPos+1]. }
  u := FindUnitOrAlias(cand);
  if u >= 0 then begin bestUnit := u; bestExtra := 0; end;

  { Extend with `.ident` groups; each is a unit-qualifier candidate only while a
    further `.ident` (the member) still remains. }
  ti := TokPos;                       { points at the first '.' }
  extra := 1;
  while (ti + 1 < TokCount) and (Tokens[ti].Kind = tkDot) and
        (Tokens[ti + 1].Kind = tkIdent) do
  begin
    AppendChar(cand, '.');
    AppendString(cand, GetTokenStr(ti + 1));
    if (ti + 3 < TokCount) and (Tokens[ti + 2].Kind = tkDot) and
       (Tokens[ti + 3].Kind = tkIdent) then
    begin
      u := FindUnitOrAlias(cand);
      if u >= 0 then begin bestUnit := u; bestExtra := extra; end;
    end;
    Inc(extra);
    ti := ti + 2;
  end;

  if bestUnit < 0 then Exit;
  Result := bestUnit;
  { Consume (bestExtra+1) identifiers, each with its trailing '.', leaving the
    parser on the member name (mirrors the old single-dot behavior). }
  for k := 0 to bestExtra do
  begin
    Next;                 { consume identifier (CurTok -> '.') }
    Expect(tkDot, '.');   { consume '.'        (CurTok -> next ident) }
  end;
  name := CurTok.SVal;    { member name; parser left on it }
end;

function LastDotName(const s: AnsiString): AnsiString;
{ Part of s after the last '.', else s. }
var i, p: Integer;
begin
  p := 0;
  for i := 1 to Length(s) do
    if s[i] = '.' then p := i;
  Result := '';
  for i := p + 1 to Length(s) do
    AppendChar(Result, s[i]);
end;

{ Read a (possibly dotted) unit name in a `uses` clause: ident('.'ident)* joined
  with dots (`Posix.SysSocket`, `System.Generics.Collections`). A path/string
  token (`uses 'foo/bar'`) is returned as-is. Consumes the whole name, leaving the
  parser on the following token (',' / ';' / next clause). Non-dotted names are
  returned unchanged, so existing lookup is untouched. }
function ReadDottedUsesName: AnsiString;
begin
  Result := CurTok.SVal;
  if CurTok.Kind <> tkIdent then begin Next; Exit; end;
  Next;                                  { consume the first identifier }
  while (CurTok.Kind = tkDot) and (TokPos < TokCount) and
        (Tokens[TokPos].Kind = tkIdent) do
  begin
    Next;                                { consume '.'  (CurTok -> identifier) }
    AppendChar(Result, '.');
    AppendString(Result, CurTok.SVal);
    Next;                                { consume identifier }
  end;
end;

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

function ParseLValueAST(idx: Integer; identTokIdx: Integer): Integer; forward;
function GenMakeFreeObjectExpr(objNode, ci: Integer): Integer; forward;
function ParseSetMembershipAST(leftExpr: Integer): Integer; forward;
function ParseSetLiteralAST: Integer; forward;
function ParseVarRecLiteralAST: Integer; forward;
function ParseArrayCtorAST(elemTk: TTypeKind): Integer; forward;
function BuildMetaclassNew(crefNode, ci, mmi: Integer): Integer; forward;
function ParseStatementAST: Integer; forward;
procedure EnableCoroutineRuntime; forward;
function ParseWithStatementAST: Integer; forward;
function ParseAsmStatementAST: Integer; forward;
function ParseBlockAST: Integer; forward;
procedure CompileAST(node: Integer); forward;
function ParseTypeKind: TTypeKind; forward;
procedure ParseRecordFields(ci: Integer; isPackedRecord: Boolean); forward;
function IsNodePChar(node: Integer): Boolean; forward;  { defined in ir.inc (included later) }
procedure ParseSubroutine; forward;
procedure ParseGenericFunctionDef; forward;
procedure ParseOperatorDef; forward;
procedure ParseNestedRoutine; forward;
procedure FlushPendingNestedProcs; forward;

{ GetTokenStrFromRaw moved up to lexer.inc (before its lexer.inc use) for FPC
  declaration-order; see there. }

function FindClassVar(ci: Integer; const name: AnsiString): Integer;
{ Class-variable lookup by (class ci, name), walking up the parent chain so a
  subclass sees an inherited `class var`. Returns the backing global var sym idx,
  or -1. }
var i, cur: Integer;
begin
  Result := -1;
  cur := ci;
  while cur >= 0 do
  begin
    for i := 0 to ClassVarCount - 1 do
      if (ClassVarCi[i] = cur) and
         CaseEqual(GetTokenStrFromRaw(ClassVarNOff[i], ClassVarNLen[i]), name) then
      begin Result := ClassVarSym[i]; Exit; end;
    cur := UClsParent[cur];
  end;
end;

procedure SpecializeStream(tokStart, count: Integer; const specName: AnsiString);
{ Substitutions come from the SpecSub* globals (param name -> concrete
  name/kind), set by the caller — multi-param generics replace every type
  parameter in one pass. }
var
  i, j, k: Integer;
  subCount: Integer;
  s: AnsiString;
begin
  subCount := 0;
  i := 0;
  while i < count do
  begin
    SpecializeTokens[subCount].Kind := TemplateTokens[tokStart + i].Kind;
    SpecializeTokens[subCount].IVal := TemplateTokens[tokStart + i].IVal;
    SpecializeTokens[subCount].Line := TemplateTokens[tokStart + i].Line;
    SpecializeTokens[subCount].SOffset := TemplateTokens[tokStart + i].SOffset;
    SpecializeTokens[subCount].SLen := TemplateTokens[tokStart + i].SLen;

    if SpecializeTokens[subCount].Kind = tkIdent then
    begin
      s := GetTokenStrFromRaw(SpecializeTokens[subCount].SOffset, SpecializeTokens[subCount].SLen);
      if CaseEqual(s, SpecializeTemplateName) then
      begin
        SpecializeTokens[subCount].SOffset := TokCharLen;
        SpecializeTokens[subCount].SLen := Length(specName);
        j := 1;
        while j <= Length(specName) do
        begin
          TokChars[TokCharLen] := specName[j];
          Inc(TokCharLen);
          Inc(j);
        end;
      end
      else
        for k := 0 to SpecSubCount - 1 do
          if CaseEqual(s, SpecSubNames[k]) then
          begin
            SpecializeTokens[subCount].Kind := SpecSubKinds[k];
            SpecializeTokens[subCount].SOffset := TokCharLen;
            SpecializeTokens[subCount].SLen := Length(SpecSubValues[k]);
            j := 1;
            while j <= Length(SpecSubValues[k]) do
            begin
              TokChars[TokCharLen] := SpecSubValues[k][j];
              Inc(TokCharLen);
              Inc(j);
            end;
            Break;
          end;
    end;

    Inc(subCount);
    Inc(i);
  end;

  if TokCount + subCount >= MAX_TOKENS then Error('token buffer overflow');
  i := TokCount - 1;
  while i >= TokPos do
  begin
    Tokens[i + subCount].Kind := Tokens[i].Kind;
    Tokens[i + subCount].IVal := Tokens[i].IVal;
    Tokens[i + subCount].Line := Tokens[i].Line;
    Tokens[i + subCount].SOffset := Tokens[i].SOffset;
    Tokens[i + subCount].SLen := Tokens[i].SLen;
    Dec(i);
  end;
  i := 0;
  while i < subCount do
  begin
    Tokens[TokPos + i].Kind := SpecializeTokens[i].Kind;
    Tokens[TokPos + i].IVal := SpecializeTokens[i].IVal;
    Tokens[TokPos + i].Line := SpecializeTokens[i].Line;
    Tokens[TokPos + i].SOffset := SpecializeTokens[i].SOffset;
    Tokens[TokPos + i].SLen := SpecializeTokens[i].SLen;
    Inc(i);
  end;
  Inc(TokCount, subCount);
end;

{ Append a string to the TokChars pool and return its offset (for synthesized
  identifier tokens — the mode-Delphi generics desugar mints alias names). }
function TokCharsAppend(const s: AnsiString): Integer;
var i: Integer;
begin
  Result := TokCharLen;
  for i := 1 to Length(s) do
  begin
    if TokCharLen >= STRING_CAP then Error('token character pool overflow');
    TokChars[TokCharLen] := s[i];
    Inc(TokCharLen);
  end;
end;

procedure ParseGenericTemplateNamed(const templateName: AnsiString; delphiForm: Boolean); forward;

{ mode-Delphi generics desugar. After template ti (`TFoo<T> = class...`) is
  captured, rewrite every later use of the Delphi surface into the objfpc
  surface the existing template/specialization machinery parses:
  - `TFoo<Concrete,...>`  -> a minted alias ident `TFoo$Concrete$...`, with
    ONE alias declaration `TFoo$... = specialize TFoo<Concrete,...>;` inserted
    at insertAt (right after the template declaration, still inside the type
    section) per distinct argument tuple;
  - `TFoo<T>` spelled with the template's OWN param names (method impls:
    `procedure TFoo<T>.M;`) -> the `<...>` group is removed, leaving
    `procedure TFoo.M;` which BufferGenericMethod already handles.
  Guards: the name must match ti's, the `<...>` group must be a plain
  comma-separated list of type idents closed by `>`, and the arity must match
  — anything else (e.g. a real `a < b` comparison) is left untouched. }
procedure DelphiRewriteGenericUses(ti, insertAt: Integer);
const MAX_DGEN_TUPLES = 512;
var
  i, j, k, na, np, seenCnt, insCnt, aOff, sOff, tOff: Integer;
  tname, aname, key: AnsiString;
  argTok: array[0..MAX_TEMPLATE_PARAMS-1] of TRawToken;
  seenKey: array[0..MAX_DGEN_TUPLES-1] of AnsiString;
  seenOff: array[0..MAX_DGEN_TUPLES-1] of Integer;
  seenLen: array[0..MAX_DGEN_TUPLES-1] of Integer;
  seenArg: array[0..MAX_DGEN_TUPLES*MAX_TEMPLATE_PARAMS-1] of TRawToken;
  ins: array[0..MAX_TEMPLATE_PARAMS*2+8] of TRawToken;
  ok, isParamForm: Boolean;
  si: Integer;
begin
  tname := Templates[ti].Name;
  np := TemplateNParams[ti];
  seenCnt := 0;
  i := insertAt;
  while i < TokCount - 1 do
  begin
    if (Tokens[i].Kind = tkIdent) and (Tokens[i+1].Kind = tkLt) and
       CaseEqual(GetTokenStr(i), tname) then
    begin
      { collect the <...> argument list }
      ok := True; na := 0; j := i + 2;
      while ok do
      begin
        if (j < TokCount) and (na < MAX_TEMPLATE_PARAMS) and
           (Tokens[j].Kind in [tkIdent, tkInteger_T, tkBoolean_T, tkChar_T, tkString_T]) then
        begin
          argTok[na] := Tokens[j]; Inc(na); Inc(j);
          if (j < TokCount) and (Tokens[j].Kind = tkComma) then Inc(j)
          else Break;
        end
        else ok := False;
      end;
      if ok and ((j >= TokCount) or (Tokens[j].Kind <> tkGt)) then ok := False;
      if ok and (na <> np) then ok := False;
      if ok then
      begin
        isParamForm := True;
        for k := 0 to na - 1 do
          if not ((argTok[k].Kind = tkIdent) and
                  CaseEqual(GetTokenStrFromRaw(argTok[k].SOffset, argTok[k].SLen),
                            TemplateParamNames[ti * MAX_TEMPLATE_PARAMS + k])) then
            isParamForm := False;
        if DebugTrace then writeln('DGEN match at ', i, ' na=', na, ' paramform=', isParamForm);
        if isParamForm then
          RemoveTokens(i + 1, j - i)   { strip `<T>` — method impl reference }
        else
        begin
          key := '';
          for k := 0 to na - 1 do
          begin
            key := key + '$';
            key := key + GetTokenStrFromRaw(argTok[k].SOffset, argTok[k].SLen);
          end;
          si := -1;
          for k := 0 to seenCnt - 1 do
            if seenKey[k] = key then si := k;
          if si < 0 then
          begin
            if seenCnt >= MAX_DGEN_TUPLES then Error('too many distinct generic specializations (MAX_DGEN_TUPLES)');
            si := seenCnt;
            aname := tname + key;
            seenKey[si] := key;
            seenOff[si] := TokCharsAppend(aname);
            seenLen[si] := Length(aname);
            for k := 0 to na - 1 do
              seenArg[si * MAX_TEMPLATE_PARAMS + k] := argTok[k];
            Inc(seenCnt);
          end;
          Tokens[i].SOffset := seenOff[si];
          Tokens[i].SLen := seenLen[si];
          RemoveTokens(i + 1, j - i);
        end;
      end;
    end;
    Inc(i);
  end;

  { one alias declaration per distinct tuple, inserted in first-seen order }
  for si := 0 to seenCnt - 1 do
  begin
    sOff := TokCharsAppend('specialize');
    tOff := TokCharsAppend(tname);
    insCnt := 0;
    ins[insCnt].Kind := tkIdent; ins[insCnt].IVal := 0; ins[insCnt].Line := Tokens[insertAt].Line;
    ins[insCnt].SOffset := seenOff[si]; ins[insCnt].SLen := seenLen[si]; Inc(insCnt);
    ins[insCnt].Kind := tkEq; ins[insCnt].IVal := 0; ins[insCnt].Line := ins[0].Line;
    ins[insCnt].SOffset := 0; ins[insCnt].SLen := 0; Inc(insCnt);
    ins[insCnt].Kind := tkIdent; ins[insCnt].IVal := 0; ins[insCnt].Line := ins[0].Line;
    ins[insCnt].SOffset := sOff; ins[insCnt].SLen := 10; Inc(insCnt);
    ins[insCnt].Kind := tkIdent; ins[insCnt].IVal := 0; ins[insCnt].Line := ins[0].Line;
    ins[insCnt].SOffset := tOff; ins[insCnt].SLen := Length(tname); Inc(insCnt);
    ins[insCnt].Kind := tkLt; ins[insCnt].IVal := 0; ins[insCnt].Line := ins[0].Line;
    ins[insCnt].SOffset := 0; ins[insCnt].SLen := 0; Inc(insCnt);
    for k := 0 to np - 1 do
    begin
      if k > 0 then
      begin
        ins[insCnt].Kind := tkComma; ins[insCnt].IVal := 0; ins[insCnt].Line := ins[0].Line;
        ins[insCnt].SOffset := 0; ins[insCnt].SLen := 0; Inc(insCnt);
      end;
      ins[insCnt] := seenArg[si * MAX_TEMPLATE_PARAMS + k]; Inc(insCnt);
    end;
    ins[insCnt].Kind := tkGt; ins[insCnt].IVal := 0; ins[insCnt].Line := ins[0].Line;
    ins[insCnt].SOffset := 0; ins[insCnt].SLen := 0; Inc(insCnt);
    ins[insCnt].Kind := tkSemicolon; ins[insCnt].IVal := 0; ins[insCnt].Line := ins[0].Line;
    ins[insCnt].SOffset := 0; ins[insCnt].SLen := 0; Inc(insCnt);
    InsertTokens(insertAt, ins, insCnt);
    insertAt := insertAt + insCnt;
  end;
end;

procedure ParseGenericTemplate;
begin
  Next; { consume 'generic' }
  if CurTok.Kind <> tkIdent then Error('expected generic class name');
  ParseGenericTemplateNamed(CurTok.SVal, False);
end;

procedure ParseGenericTemplateNamed(const templateNameIn: AnsiString; delphiForm: Boolean);
var
  templateName, nextStr: AnsiString;
  depth, startTok, cur, finalCur, np, gi: Integer;
  pnames: array[0..MAX_TEMPLATE_PARAMS-1] of AnsiString;
  isOpener, doneParams: Boolean;
begin
  { Copy BEFORE Next: callers pass CurTok.SVal, and a const AnsiString param
    aliases it by reference — Next would mutate the name out from under us. }
  templateName := templateNameIn;
  Next; { consume the template name (caller verified it) }

  { <T> / <TKey, TData> / <T: TObject> / <TKey; TData: TObject> — groups of
    comma-separated names, each group with an optional `: constraint` (the
    constraint list runs to the next `;` or `>`), groups separated by `;`.
    Constraints are parse-and-ignore: pxx generics are token-substitution, so
    the constraint has no checked meaning here (FPC enforces it at compile of
    the generic itself, which substitution defers to the specialization). }
  Expect(tkLt, '<');
  np := 0;
  doneParams := False;
  repeat
    repeat
      if CurTok.Kind <> tkIdent then Error('expected generic parameter name');
      if np >= MAX_TEMPLATE_PARAMS then Error('too many generic parameters (MAX_TEMPLATE_PARAMS)');
      pnames[np] := CurTok.SVal; Inc(np); Next;
    until not Eat(tkComma);
    if Eat(tkColon) then
      while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkGt) and
            (CurTok.Kind <> tkEOF) do
        Next;   { skip the constraint list }
    if not Eat(tkSemicolon) then doneParams := True;
  until doneParams;
  Expect(tkGt, '>');
  Expect(tkEq, '=');

  { Generic templates: class / record / packed record (depth-counted to the
    matching `end`), or array / procedure / function types (run to the
    terminating `;`) — feature-pascal-generic-nonclass-templates. Generics are
    token substitution, so capture is purely lexical; the specialization
    streams the body and ParseTypeSection's ordinary type-decl dispatch
    (class/record/array/procvar branches) parses it. }
  if not ((CurTok.Kind in [tkClass, tkRecord, tkPacked, tkArray,
                            tkProcedure, tkFunction]) or
          ((CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'interface'))) then
    Error('generic templates must be class, record, interface, array or procedure declarations');

  startTok := TokPos - 1;
  if CurTok.Kind = tkPacked then
  begin
    Next;   { capture includes 'packed'; depth-count from the 'record' }
    if CurTok.Kind <> tkRecord then Error('generic packed template must be a record');
  end;
  if (Tokens[startTok].Kind = tkArray) or (Tokens[startTok].Kind = tkProcedure) or
     (Tokens[startTok].Kind = tkFunction) then
  begin
    { no `end`: the body runs to the first ';' outside (),[] — and outside an
      inline `record ... end` element type (tgeneric25's
      `array[0..1] of record A: T; B: String; end`), whose own semicolons
      must not terminate the capture. }
    depth := 0;
    cur := TokPos;
    while cur < TokCount do
    begin
      if (Tokens[cur].Kind = tkLParen) or (Tokens[cur].Kind = tkLBrack) then Inc(depth)
      else if (Tokens[cur].Kind = tkRParen) or (Tokens[cur].Kind = tkRBrack) then Dec(depth)
      else if (Tokens[cur].Kind = tkRecord) or (Tokens[cur].Kind = tkClass) then
      begin
        { skip the whole record/class body: end-depth count }
        gi := 1;   { reuse gi as the end-depth counter }
        Inc(cur);
        while (cur < TokCount) and (gi > 0) do
        begin
          if (Tokens[cur].Kind = tkRecord) or (Tokens[cur].Kind = tkClass) then Inc(gi)
          else if Tokens[cur].Kind = tkEnd then Dec(gi);
          Inc(cur);
        end;
        continue;
      end
      else if (Tokens[cur].Kind = tkSemicolon) and (depth = 0) then Break;
      Inc(cur);
    end;
    if cur < TokCount then Inc(cur);   { include the ';' }
    finalCur := cur;
  end
  else
  begin
  depth := 1;
  cur := TokPos;
  while (cur < TokCount) and (depth > 0) do
  begin
    if Tokens[cur].Kind = tkClass then
    begin
      { `class function/procedure/var/property/of` (and soft
        constructor/destructor/operator) is a member prefix, not a nested
        class body — counting it as an opener swallowed the rest of the
        unit into the template. }
      isOpener := True;
      if cur + 1 < TokCount then
      begin
        if Tokens[cur+1].Kind in [tkFunction, tkProcedure, tkVar, tkProperty, tkOf] then
          isOpener := False
        else if Tokens[cur+1].Kind = tkIdent then
        begin
          nextStr := GetTokenStr(cur+1);
          if CaseEqual(nextStr, 'constructor') or CaseEqual(nextStr, 'destructor') or
             CaseEqual(nextStr, 'operator') then
            isOpener := False;
        end;
      end;
      if isOpener then Inc(depth);
    end
    else if Tokens[cur].Kind = tkRecord then
      Inc(depth)
    else if Tokens[cur].Kind = tkEnd then
      Dec(depth);
    Inc(cur);
  end;

  if (cur < TokCount) and (Tokens[cur].Kind = tkSemicolon) then
    Inc(cur);

  finalCur := cur;  { save before for-loop clobbers 'cur' }
  end;

  if TemplateCount >= MAX_TEMPLATES then Error('too many generic templates');
  Templates[TemplateCount].Name := templateName;
  for gi := 0 to np - 1 do
    TemplateParamNames[TemplateCount * MAX_TEMPLATE_PARAMS + gi] := pnames[gi];
  TemplateNParams[TemplateCount] := np;
  Templates[TemplateCount].TokStart := TemplateTokenCount;
  Templates[TemplateCount].TokCount := 0;

  for cur := startTok to finalCur - 1 do
  begin
    if TemplateTokenCount >= MAX_TEMPLATE_TOKENS then
      Error('generic template tokens overflow');
    TemplateTokens[TemplateTokenCount].Kind := Tokens[cur].Kind;
    TemplateTokens[TemplateTokenCount].IVal := Tokens[cur].IVal;
    TemplateTokens[TemplateTokenCount].Line := Tokens[cur].Line;
    TemplateTokens[TemplateTokenCount].SOffset := Tokens[cur].SOffset;
    TemplateTokens[TemplateTokenCount].SLen := Tokens[cur].SLen;
    Inc(TemplateTokenCount);
    Templates[TemplateCount].TokCount := Templates[TemplateCount].TokCount + 1;
  end;

  Inc(TemplateCount);

  if DebugTrace then
    writeln('TEMPLATE ', templateName, ' startTok=', startTok, ' endTok=', finalCur,
            ' endLine=', Tokens[finalCur-1].Line);

  { mode-Delphi form (`TFoo<T> = class`): desugar the rest of the token stream
    to the objfpc surface the machinery above already speaks — rewrite each
    concrete use `TFoo<Args>` to a minted alias ident (registering the alias
    declaration tokens `alias = specialize TFoo<Args>;` right after this
    template), and strip `<T>` from method impls `procedure TFoo<T>.M`. }
  if delphiForm then
    DelphiRewriteGenericUses(TemplateCount - 1, finalCur);

  TokPos := finalCur;
  Next;
end;

{ Load the SpecSub* substitution set from a (template, specialization) pair. }
procedure SetSpecSubs(ti, si: Integer);
var k: Integer;
begin
  SpecSubCount := TemplateNParams[ti];
  for k := 0 to SpecSubCount - 1 do
  begin
    SpecSubNames[k]  := TemplateParamNames[ti * MAX_TEMPLATE_PARAMS + k];
    SpecSubValues[k] := SpecConcreteNames[si * MAX_TEMPLATE_PARAMS + k];
    SpecSubKinds[k]  := SpecConcreteKinds[si * MAX_TEMPLATE_PARAMS + k];
  end;
end;

procedure ParseSpecialization(const specName: AnsiString);
var
  templateName: AnsiString;
  cNames: array[0..MAX_TEMPLATE_PARAMS-1] of AnsiString;
  cKinds: array[0..MAX_TEMPLATE_PARAMS-1] of TTokenKind;
  nc, ti, i: Integer;
begin
  Next; { consume 'specialize' }
  if CurTok.Kind <> tkIdent then Error('expected generic template name');
  templateName := CurTok.SVal; Next;

  Expect(tkLt, '<');
  nc := 0;
  repeat
    if (CurTok.Kind <> tkIdent) and (CurTok.Kind <> tkInteger_T) and (CurTok.Kind <> tkBoolean_T) and (CurTok.Kind <> tkChar_T) and (CurTok.Kind <> tkString_T) then
      Error('expected concrete type name');
    if nc >= MAX_TEMPLATE_PARAMS then Error('too many specialization arguments (MAX_TEMPLATE_PARAMS)');
    cNames[nc] := CurTok.SVal;
    cKinds[nc] := CurTok.Kind;
    Inc(nc);
    Next;
  until not Eat(tkComma);
  Expect(tkGt, '>');
  { Leave CurTok on the trailing ';' (do NOT Eat) so SpecializeStream inserts
    the class-body tokens right after it; the final Next then lands CurTok on
    the inserted 'class', and the caller falls through to the class-binding
    branch (which names the concrete class from the saved tnOff/tnLen). }

  ti := -1;
  for i := 0 to TemplateCount - 1 do
    if CaseEqual(Templates[i].Name, templateName) then
      ti := i;
  if ti < 0 then Error('generic template ' + templateName + ' not found');
  if nc <> TemplateNParams[ti] then
    Error('specialize ' + templateName + ': wrong number of type arguments');

  if SpecializationCount >= MAX_SPECIALIZATIONS then Error('too many specializations');
  Specializations[SpecializationCount].Name := specName;
  Specializations[SpecializationCount].TemplateName := templateName;
  for i := 0 to nc - 1 do
  begin
    SpecConcreteKinds[SpecializationCount * MAX_TEMPLATE_PARAMS + i] := cKinds[i];
    SpecConcreteNames[SpecializationCount * MAX_TEMPLATE_PARAMS + i] := cNames[i];
  end;
  SpecNParams[SpecializationCount] := nc;
  Inc(SpecializationCount);

  { Stream the concrete class body inline so the fall-through binds the alias
    name. Methods that were buffered BEFORE this specialization (template in a
    used unit) cannot be streamed here — a `procedure` token would close the
    type section and orphan any following specialization — so defer them to a
    pending queue that ParseTypeSection flushes once the section ends. Methods
    buffered AFTER this point are streamed by BufferGenericMethod, so each
    (method, specialization) pair is materialised exactly once. }
  if GenericMethodCount > 0 then
  begin
    if PendingSpecCount >= MAX_PENDING_SPECS then Error('too many pending specializations');
    PendingSpecTi[PendingSpecCount] := ti;
    PendingSpecIdx[PendingSpecCount] := SpecializationCount - 1;
    Inc(PendingSpecCount);
  end;

  SpecializeTemplateName := Templates[ti].Name;
  SetSpecSubs(ti, SpecializationCount - 1);
  SpecializeStream(Templates[ti].TokStart, Templates[ti].TokCount, specName);
  Next;
end;

{ Materialise the methods of every class specialization buffered during the
  type section just parsed. Called once the section's token loop exits, so the
  streamed `procedure`/`function` bodies land after the whole `type` block and
  are parsed as ordinary top-level subroutines. Inserting at TokPos prepends
  before the section-terminating token, which was un-read by the caller. }
procedure FlushPendingClassSpecializations;
var p, gm, ti, si: Integer;
begin
  for p := 0 to PendingSpecCount - 1 do
  begin
    ti := PendingSpecTi[p];
    si := PendingSpecIdx[p];
    SpecializeTemplateName := Templates[ti].Name;
    SetSpecSubs(ti, si);
    for gm := 0 to GenericMethodCount - 1 do
      if GenericMethods[gm].TemplateIdx = ti then
        SpecializeStream(GenericMethods[gm].TokStart, GenericMethods[gm].TokCount,
          Specializations[si].Name);
  end;
  PendingSpecCount := 0;
end;

procedure BufferGenericMethod(ti, startTokIdx: Integer);
var
  depth, cur, finalCur: Integer;
  si, mStart, mCount: Integer;
begin
  depth := 0;
  cur := startTokIdx;
  while (cur < TokCount) and (Tokens[cur].Kind <> tkBegin) do
    Inc(cur);
  if cur >= TokCount then Error('expected begin in generic method');

  depth := 1;
  Inc(cur);
  while (cur < TokCount) and (depth > 0) do
  begin
    if Tokens[cur].Kind in [tkBegin, tkCase] then
      Inc(depth)
    else if Tokens[cur].Kind = tkEnd then
      Dec(depth);
    Inc(cur);
  end;

  if (cur < TokCount) and (Tokens[cur].Kind = tkSemicolon) then
    Inc(cur);

  finalCur := cur;  { save before for-loop clobbers 'cur' }

  mStart := TemplateTokenCount;
  mCount := 0;
  for cur := startTokIdx to finalCur - 1 do
  begin
    if TemplateTokenCount >= MAX_TEMPLATE_TOKENS then
      Error('generic template tokens overflow');
    TemplateTokens[TemplateTokenCount].Kind := Tokens[cur].Kind;
    TemplateTokens[TemplateTokenCount].IVal := Tokens[cur].IVal;
    TemplateTokens[TemplateTokenCount].Line := Tokens[cur].Line;
    TemplateTokens[TemplateTokenCount].SOffset := Tokens[cur].SOffset;
    TemplateTokens[TemplateTokenCount].SLen := Tokens[cur].SLen;
    Inc(TemplateTokenCount);
    mCount := mCount + 1;
  end;

  { Remember the buffered method so a later specialization (parsed after this
    method, e.g. template in a unit + `specialize` in the program) can still
    materialise it. See ParseSpecialization. }
  if GenericMethodCount >= MAX_GENERIC_METHODS then Error('too many generic methods');
  GenericMethods[GenericMethodCount].TemplateIdx := ti;
  GenericMethods[GenericMethodCount].TokStart := mStart;
  GenericMethods[GenericMethodCount].TokCount := mCount;
  Inc(GenericMethodCount);

  { Insert specializations AFTER the template method body, not at the dot
    position. Only specializations already registered are streamed here; ones
    declared later stream this method from ParseSpecialization, so each
    (method, specialization) pair is materialised exactly once. }
  TokPos := finalCur;
  for si := 0 to SpecializationCount - 1 do
  begin
    if CaseEqual(Specializations[si].TemplateName, Templates[ti].Name) then
    begin
      SpecializeTemplateName := Templates[ti].Name;
      SetSpecSubs(ti, si);
      SpecializeStream(mStart, mCount, Specializations[si].Name);
    end;
  end;

  { TokPos = finalCur (InsertTokens doesn't change it); parser reads from first specialization }
  Next;
end;

function FindGenericFunc(const name: AnsiString): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to GenericFuncCount - 1 do
    if CaseEqual(GenericFuncs[i].Name, name) then begin Result := i; Exit; end;
end;

{ Parses: generic function Max<T>(A, B: T): T; begin...end;
  Called when CurTok = tkIdent('generic') }
procedure ParseGenericFunctionDef;
var isFunc: Boolean; funcName, paramName: AnsiString;
    gfi, j, cur, finalCur, depth: Integer;
begin
  Next; { consume 'generic' }
  if (CurTok.Kind <> tkFunction) and (CurTok.Kind <> tkProcedure) then
    Error('expected function or procedure after generic');
  isFunc := CurTok.Kind = tkFunction;
  Next; { consume function/procedure }

  if CurTok.Kind <> tkIdent then Error('expected generic function name');
  funcName := CurTok.SVal; Next;

  Expect(tkLt, '<');
  if CurTok.Kind <> tkIdent then Error('expected generic type parameter');
  paramName := CurTok.SVal; Next;
  Expect(tkGt, '>');
  { CurTok = '(' of param list, or ';' / ':' if no params }

  if GenericFuncCount >= MAX_GENERIC_FUNCS then Error('too many generic functions');
  gfi := GenericFuncCount;
  GenericFuncs[gfi].Name     := funcName;
  GenericFuncs[gfi].Param    := paramName;
  GenericFuncs[gfi].IsFunc   := isFunc;
  GenericFuncs[gfi].TokStart := TemplateTokenCount;
  GenericFuncs[gfi].TokCount := 0;

  { Prepend synthetic 'function/procedure funcName' tokens into template buffer }
  TemplateTokens[TemplateTokenCount].IVal := 0;
  TemplateTokens[TemplateTokenCount].Line := 0;
  if isFunc then TemplateTokens[TemplateTokenCount].Kind := tkFunction
  else TemplateTokens[TemplateTokenCount].Kind := tkProcedure;
  TemplateTokens[TemplateTokenCount].SOffset := TokCharLen;
  TemplateTokens[TemplateTokenCount].SLen := 0;
  Inc(TemplateTokenCount);
  GenericFuncs[gfi].TokCount := GenericFuncs[gfi].TokCount + 1;

  TemplateTokens[TemplateTokenCount].Kind := tkIdent;
  TemplateTokens[TemplateTokenCount].IVal := 0;
  TemplateTokens[TemplateTokenCount].Line := 0;
  TemplateTokens[TemplateTokenCount].SOffset := TokCharLen;
  TemplateTokens[TemplateTokenCount].SLen := Length(funcName);
  for j := 1 to Length(funcName) do
  begin
    TokChars[TokCharLen] := funcName[j];
    Inc(TokCharLen);
  end;
  Inc(TemplateTokenCount);
  GenericFuncs[gfi].TokCount := GenericFuncs[gfi].TokCount + 1;

  { Buffer remaining tokens: (A,B:T):T; begin...end; }
  { TokPos-1 = index of current token '(' in Tokens array }
  cur := TokPos - 1;
  while (cur < TokCount) and (Tokens[cur].Kind <> tkBegin) do Inc(cur);
  depth := 1; Inc(cur);
  while (cur < TokCount) and (depth > 0) do
  begin
    if Tokens[cur].Kind in [tkBegin, tkCase] then Inc(depth)
    else if Tokens[cur].Kind = tkEnd then Dec(depth);
    Inc(cur);
  end;
  if (cur < TokCount) and (Tokens[cur].Kind = tkSemicolon) then Inc(cur);
  finalCur := cur;

  for cur := TokPos - 1 to finalCur - 1 do
  begin
    if TemplateTokenCount >= MAX_TEMPLATE_TOKENS then Error('generic template tokens overflow');
    TemplateTokens[TemplateTokenCount].Kind := Tokens[cur].Kind;
    TemplateTokens[TemplateTokenCount].IVal := Tokens[cur].IVal;
    TemplateTokens[TemplateTokenCount].Line := Tokens[cur].Line;
    TemplateTokens[TemplateTokenCount].SOffset := Tokens[cur].SOffset;
    TemplateTokens[TemplateTokenCount].SLen := Tokens[cur].SLen;
    Inc(TemplateTokenCount);
    GenericFuncs[gfi].TokCount := GenericFuncs[gfi].TokCount + 1;
  end;

  Inc(GenericFuncCount);
  TokPos := finalCur;
  Next;
end;

{ Parses: specialize Max<Integer> as MaxInt;
  Called when CurTok = tkIdent('specialize') at top level }
procedure ParseTopLevelSpecialize;
var templateName, concreteName, specName: AnsiString;
    concreteKind: TTokenKind; gfi, i: Integer;
begin
  Next; { consume 'specialize' }
  if CurTok.Kind <> tkIdent then Error('expected generic function name after specialize');
  templateName := CurTok.SVal; Next;

  Expect(tkLt, '<');
  if (CurTok.Kind = tkIdent) or (CurTok.Kind = tkInteger_T) or
     (CurTok.Kind = tkBoolean_T) or (CurTok.Kind = tkChar_T) or
     (CurTok.Kind = tkString_T) then
  begin
    concreteName := CurTok.SVal;
    concreteKind := CurTok.Kind;
    Next;
  end
  else
    Error('expected concrete type in specialize');
  Expect(tkGt, '>');

  { Optional 'as Name' }
  if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'as') then
  begin
    Next;
    if CurTok.Kind <> tkIdent then Error('expected name after as');
    specName := CurTok.SVal; Next;
  end
  else
  begin
    { Auto-generate: Max_Integer }
    specName := templateName;
    AppendChar(specName, '_');
    i := 1;
    while i <= Length(concreteName) do begin AppendChar(specName, concreteName[i]); Inc(i); end;
  end;
  { CurTok = ';' — do NOT Eat here. Insert at TokPos (after ';') so that
    after ParseSubroutine finishes its own 'end;', CurTok lands on the next
    top-level token (next specialize/begin/etc.) rather than skipping it. }

  gfi := FindGenericFunc(templateName);
  if gfi < 0 then Error('generic function ' + templateName + ' not found');

  SpecializeTemplateName := GenericFuncs[gfi].Name;
  { generic FUNCTIONS stay single-parameter — load the substitution set directly }
  SpecSubCount := 1;
  SpecSubNames[0]  := GenericFuncs[gfi].Param;
  SpecSubValues[0] := concreteName;
  SpecSubKinds[0]  := concreteKind;
  SpecializeStream(GenericFuncs[gfi].TokStart, GenericFuncs[gfi].TokCount, specName);
  Next;
  ParseSubroutine;
end;

{ Parses: operator < (a, b: TMyType): Boolean; begin...end;
  Called when CurTok = tkIdent('operator') at top level }
procedure ParseOperatorDef;
var
  opKind: TTokenKind;
  synName: AnsiString;
  typeName: AnsiString;
  recId: Integer;
  opTypeKind: Integer;
  ci: Integer;
  depth, i, j: Integer;
  isFunc, foundClose: Boolean;
  nameOff, nameLen: Integer;
  procIdx: Integer;
begin
  Next; { consume 'operator' }
  opKind := CurTok.Kind;
  if not (opKind in [tkPlus, tkMinus, tkStar, tkSlash, tkDiv, tkMod, tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe]) then
    Error('expected operator symbol after operator keyword');
  { Stay on operator token — do NOT call Next. TokPos → '(' }

  { Lookahead: find first ':' inside '()' to get operand type name }
  typeName := '';
  depth := 0;
  i := TokPos; { Tokens[TokPos] = '(' }
  while (i < TokCount) and (typeName = '') do
  begin
    if Tokens[i].Kind = tkLParen then Inc(depth)
    else if Tokens[i].Kind = tkRParen then Dec(depth)
    else if (Tokens[i].Kind = tkColon) and (depth = 1) then
    begin
      Inc(i);
      if i < TokCount then
      begin
        if Tokens[i].Kind = tkIdent then
          typeName := GetTokenStrFromRaw(Tokens[i].SOffset, Tokens[i].SLen)
        else if Tokens[i].Kind = tkInteger_T then typeName := 'Integer'
        else if Tokens[i].Kind = tkBoolean_T then typeName := 'Boolean'
        else if Tokens[i].Kind = tkChar_T then typeName := 'Char'
        else if Tokens[i].Kind = tkString_T then typeName := 'String';
      end;
      i := TokCount; { break }
    end;
    Inc(i);
  end;
  if typeName = '' then Error('operator: cannot determine operand type');

  { Resolve recId for the operand type. Record the operand's real type kind so
    the registration tag matches how the use site looks it up (a record operand
    carries ASTTk=tyRecord, a class operand tyClass). Registering everything as
    tyClass made FindOpOverload miss for record operands, so `a + b` on records
    silently fell through to a scalar binop. }
  recId := IsRecordType(typeName);
  if recId = REC_NONE then
  begin
    ci := FindUClass(typeName);
    if ci < 0 then Error('operator overloading: ' + typeName + ' is not a record or class type');
    recId := REC_UCLASS_BASE + ci;
    opTypeKind := Ord(tyClass);
  end
  else
    opTypeKind := Ord(tyRecord);

  { Determine function vs procedure: find matching ')' then check for ':' }
  depth := 0;
  i := TokPos;
  foundClose := False;
  while (i < TokCount) and not foundClose do
  begin
    if Tokens[i].Kind = tkLParen then Inc(depth)
    else if Tokens[i].Kind = tkRParen then
    begin
      Dec(depth);
      if depth = 0 then begin Inc(i); foundClose := True; end;
    end;
    if not foundClose then Inc(i);
  end;
  isFunc := (i < TokCount) and (Tokens[i].Kind = tkColon);

  { FPC named-result form: `operator + (a, b: T) z: T;` — the ident between ')'
    and ':' names the result variable. Excise it from the token stream (leaving
    the plain `): T` form) and bind it as an alias of Result for the body via
    OpResultAlias (consumed in FindSym). An alias — not a copy-out epilogue —
    so an early Exit still returns the value assigned so far. }
  OpResultAlias := '';
  if (not isFunc) and (i + 1 < TokCount) and (Tokens[i].Kind = tkIdent) and
     (Tokens[i + 1].Kind = tkColon) then
  begin
    OpResultAlias := GetTokenStrFromRaw(Tokens[i].SOffset, Tokens[i].SLen);
    for j := i to TokCount - 2 do
    begin
      Tokens[j].Kind := Tokens[j + 1].Kind;
      Tokens[j].IVal := Tokens[j + 1].IVal;
      Tokens[j].Line := Tokens[j + 1].Line;
      Tokens[j].SOffset := Tokens[j + 1].SOffset;
      Tokens[j].SLen := Tokens[j + 1].SLen;
    end;
    Dec(TokCount);
    isFunc := True;
  end;

  { Synthesize unique proc name __op__NN }
  synName := '__op__';
  AppendChar(synName, Chr(Ord('0') + OvrlCount div 10));
  AppendChar(synName, Chr(Ord('0') + OvrlCount mod 10));

  { Insert 'function/procedure synName' at TokPos (before '(') }
  if TokCount + 2 >= MAX_TOKENS then Error('token buffer overflow in operator def');
  for j := TokCount - 1 downto TokPos do
  begin
    Tokens[j + 2].Kind := Tokens[j].Kind;
    Tokens[j + 2].IVal := Tokens[j].IVal;
    Tokens[j + 2].Line := Tokens[j].Line;
    Tokens[j + 2].SOffset := Tokens[j].SOffset;
    Tokens[j + 2].SLen := Tokens[j].SLen;
  end;
  Inc(TokCount, 2);

  if isFunc then Tokens[TokPos].Kind := tkFunction
  else Tokens[TokPos].Kind := tkProcedure;
  Tokens[TokPos].IVal := 0; Tokens[TokPos].Line := 0;
  Tokens[TokPos].SOffset := 0; Tokens[TokPos].SLen := 0;

  nameOff := TokCharLen;
  nameLen := Length(synName);
  for j := 1 to nameLen do
  begin
    TokChars[TokCharLen] := synName[j];
    Inc(TokCharLen);
  end;
  Tokens[TokPos+1].Kind := tkIdent;
  Tokens[TokPos+1].IVal := 0; Tokens[TokPos+1].Line := 0;
  Tokens[TokPos+1].SOffset := nameOff;
  Tokens[TokPos+1].SLen := nameLen;

  { Advance into the injected 'function/procedure' token }
  Next;
  ParseSubroutine;
  OpResultAlias := '';

  { After ParseSubroutine, the proc is registered — look it up by synName }
  procIdx := FindProc(synName);
  if procIdx < 0 then Error('operator: internal error, proc not found after parse');
  RegisterOpOverload(Ord(opKind), opTypeKind, recId, procIdx);
end;

{ Linear (row-major) index of an N-D fixed array element, built from AST nodes so
  it feeds the ordinary 1-D AN_INDEX (no codegen change). Reads the dims from
  NDInfoLo/Span and the parsed index exprs from NDIdxNode; nd dimensions.
  Horner form: acc = (i0-lo0); acc = acc*span_d + (i_d - lo_d) for d = 1..nd-1. }
function BuildFlatNDIndex(nd: Integer): Integer;
var d, loLit, spanLit, diff, scaled, acc: Integer;
begin
  loLit := AllocNode(AN_INT_LIT); ASTIVal[loLit] := NDInfoLo[0]; ASTTk[loLit] := Ord(tyInteger);
  acc := AllocNode(AN_BINOP); ASTIVal[acc] := Ord(tkMinus);
  ASTLeft[acc] := NDIdxNode[0]; ASTRight[acc] := loLit; ASTTk[acc] := Ord(tyInteger);
  for d := 1 to nd - 1 do
  begin
    spanLit := AllocNode(AN_INT_LIT); ASTIVal[spanLit] := NDInfoSpan[d]; ASTTk[spanLit] := Ord(tyInteger);
    scaled := AllocNode(AN_BINOP); ASTIVal[scaled] := Ord(tkStar);   { acc * span_d }
    ASTLeft[scaled] := acc; ASTRight[scaled] := spanLit; ASTTk[scaled] := Ord(tyInteger);
    loLit := AllocNode(AN_INT_LIT); ASTIVal[loLit] := NDInfoLo[d]; ASTTk[loLit] := Ord(tyInteger);
    diff := AllocNode(AN_BINOP); ASTIVal[diff] := Ord(tkMinus);    { i_d - lo_d }
    ASTLeft[diff] := NDIdxNode[d]; ASTRight[diff] := loLit; ASTTk[diff] := Ord(tyInteger);
    acc := AllocNode(AN_BINOP); ASTIVal[acc] := Ord(tkPlus);       { scaled + diff }
    ASTLeft[acc] := scaled; ASTRight[acc] := diff; ASTTk[acc] := Ord(tyInteger);
  end;
  Result := acc;
end;

{ A single leading subscript on an >=2-D fixed array selects a whole sub-array
  (row): `m[i]` of `array[a..b, c..d] of T` is the row `array[c..d] of T` at
  byte offset (i-lo0)*span1*..*span_{nd-1} elements. Build that flat element
  index so the ordinary element-stride AN_INDEX lands on the row's first
  element; its address is then the row base (what a `var`/`const` array param or
  whole-row reference needs). NDInfo* must be filled (NodeArrNDInfo). }
function BuildPartialNDRowIndex(rowIdxNode: Integer): Integer;
var d, trailing, loLit, diff, spanLit: Integer;
begin
  trailing := 1;
  for d := 1 to NDInfoNDims - 1 do trailing := trailing * NDInfoSpan[d];
  loLit := AllocNode(AN_INT_LIT); ASTIVal[loLit] := NDInfoLo[0]; ASTTk[loLit] := Ord(tyInteger);
  diff := AllocNode(AN_BINOP); ASTIVal[diff] := Ord(tkMinus);
  ASTLeft[diff] := rowIdxNode; ASTRight[diff] := loLit; ASTTk[diff] := Ord(tyInteger);
  spanLit := AllocNode(AN_INT_LIT); ASTIVal[spanLit] := trailing; ASTTk[spanLit] := Ord(tyInteger);
  Result := AllocNode(AN_BINOP); ASTIVal[Result] := Ord(tkStar);
  ASTLeft[Result] := diff; ASTRight[Result] := spanLit; ASTTk[Result] := Ord(tyInteger);
end;

{ If `node` is an N-D fixed array reference (a SymArrNDims ident or an
  UFldArrNDims record field), fill NDInfo* and return True. Lets m[..] and
  r.m[..] share one path. }
function NodeArrNDInfo(node: Integer): Boolean;
var baseRec, fIdx, sym, d, base: Integer; fname: AnsiString;
begin
  Result := False;
  if (ASTKind[node] = AN_IDENT) and (ASTIVal[node] >= 0) and (SymArrNDims[ASTIVal[node]] >= 2) then
  begin
    sym := ASTIVal[node];
    NDInfoNDims := SymArrNDims[sym];
    base := sym * MAX_ARR_DIMS;
    for d := 0 to NDInfoNDims - 1 do
    begin NDInfoLo[d] := SymArrDimLo[base + d]; NDInfoSpan[d] := SymArrDimSpan[base + d]; end;
    Result := True;
  end
  else if ASTKind[node] = AN_FIELD then
  begin
    baseRec := ResolveNodeRec(ASTLeft[node]);
    if baseRec >= REC_UCLASS_BASE then
    begin
      fname := GetASTIdentName(node);
      fIdx := FindUField(baseRec - REC_UCLASS_BASE, fname);
      if (fIdx >= 0) and (UFldArrNDims[fIdx] >= 2) then
      begin
        NDInfoNDims := UFldArrNDims[fIdx];
        base := fIdx * MAX_ARR_DIMS;
        for d := 0 to NDInfoNDims - 1 do
        begin NDInfoLo[d] := UFldArrDimLo[base + d]; NDInfoSpan[d] := UFldArrDimSpan[base + d]; end;
        Result := True;
      end;
    end;
  end;
end;

{ Parse an indexed-property subscript `[e1 {, e2}]` (bracket not yet consumed)
  into a chain of AN_ARG nodes. head = first arg, tail = last (so a setter's value
  arg can be spliced after). Supports multi-index `obj.Cells[a, b]` / `obj[a, b]`. }
procedure ParsePropIndexArgs(var head, tail: Integer);
var n: Integer;
begin
  Expect(tkLBrack, '[');
  ParseExpr;
  head := AllocNode(AN_ARG); ASTLeft[head] := CurASTNode; tail := head;
  while CurTok.Kind = tkComma do
  begin
    Next;
    ParseExpr;
    n := AllocNode(AN_ARG); ASTLeft[n] := CurASTNode;
    ASTRight[tail] := n; tail := n;
  end;
  Expect(tkRBrack, ']');
end;

{ Append AN_INT_LIT default-value args for method params fromIdx..ParamCount-1
  (a call that omitted trailing defaulted args — mirrors the ctor fill at the
  TFoo.Create arity check). Errors if a remaining param has no default. The
  caller links head into the call node when lastArg starts at -1. }
procedure FillDefaultArgs(mpi, fromIdx, callNode: Integer; var lastArg: Integer);
var exprNode, argSeq, k: Integer;
begin
  k := fromIdx;
  while k <= Procs[mpi].ParamCount - 1 do
  begin
    if (k >= MAX_PROC_PARAMS) or (not ProcParamHasDefault[mpi * MAX_PROC_PARAMS + k]) then
      Error('not enough arguments to ' + Procs[mpi].Name +
            ' (parameter ' + Procs[mpi].Params[k].Name + ' has no default)');
    exprNode := AllocNode(AN_INT_LIT);
    ASTIVal[exprNode] := ProcParamDefaultVal[mpi * MAX_PROC_PARAMS + k];
    ASTTk[exprNode] := Ord(Procs[mpi].Params[k].TypeKind);
    argSeq := AllocNode(AN_ARG);
    ASTLeft[argSeq] := exprNode;
    if lastArg = -1 then ASTLeft[callNode] := argSeq
    else ASTRight[lastArg] := argSeq;
    lastArg := argSeq;
    Inc(k);
  end;
end;

{ True when the arg list may stop here: next token is `)` and every remaining
  param (nextIdx..) carries a declared default. }
function CanFillDefaultsFrom(mpi, nextIdx: Integer): Boolean;
begin
  Result := (CurTok.Kind = tkRParen) and (nextIdx <= Procs[mpi].ParamCount - 1) and
            (nextIdx < MAX_PROC_PARAMS) and
            ProcParamHasDefault[mpi * MAX_PROC_PARAMS + nextIdx];
end;

{ Count the arguments of the call whose NAME is CurTok (Tokens[TokPos] = '('
  when parenthesized): top-level commas + 1; 0 for `()` or no parens. Used to
  pick among method OVERLOADS before the signature-driven arg loop parses. }
function CountCallArgsAhead: Integer;
var i, d: Integer;
begin
  Result := 0;
  { CurTok = the call NAME (paren at TokPos), or already ON the '(' (inherited
    path, name consumed) — scan from whichever position holds the '('  }
  if (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
    i := TokPos
  else if CurTok.Kind = tkLParen then
    i := TokPos - 1
  else
    Exit;
  if (i + 1 < TokCount) and (Tokens[i + 1].Kind = tkRParen) then Exit;
  Result := 1;
  d := 0;
  while i < TokCount do
  begin
    if Tokens[i].Kind in [tkLParen, tkLBrack] then Inc(d)
    else if Tokens[i].Kind in [tkRParen, tkRBrack] then
    begin
      Dec(d);
      if d = 0 then Exit;
    end
    else if (Tokens[i].Kind = tkSemicolon) or (Tokens[i].Kind = tkEOF) then Exit
    else if (Tokens[i].Kind = tkComma) and (d = 1) then Inc(Result);
    Inc(i);
  end;
end;

function ByRefArgStartsExpression: Boolean;
{ True when the next by-ref/array argument cannot be a bare variable lvalue:
  not an ident at all, or an ident that names no symbol and is followed by
  '(' — a type-cast lvalue like `PChar(s)^` / `Pointer(p)^` passed to a
  var/untyped parameter (bug-cast-deref-as-varparam-arg). Such args go
  through ParseExpr, whose cast/deref path yields an addressable node. }
begin
  if CurTok.Kind <> tkIdent then begin Result := True; Exit; end;
  Result := (FindSym(CurTok.SVal) < 0) and (TokPos < TokCount) and
            (Tokens[TokPos].Kind = tkLParen);
end;

function ParseLValueAST(idx: Integer; identTokIdx: Integer): Integer;
var
  node, indexNode, fieldNode, prevTok, recName, i: Integer;
  baseNode, baseRec, fIdx, aliasIdx, firstIdxNode: Integer;
  remDepth, ptrBaseTk, ptrBaseRec: Integer;
  isND: Boolean; nIdx: Integer; alreadyResolved: Boolean;
  tk: TTypeKind;
  fieldName: AnsiString;
  mci, mmi, mpi, mcallNode, mselfArg, mlastArg, margSeq, margIdx, mexprNode, mai, pri, ci: Integer;
  methName: AnsiString;
  isAssign: Boolean;
  selfClassCi, selfIdx, fldIdx, selfNode: Integer;
  w, withNode, recId: Integer;
  propFOff, propFLen: Integer;
  withResolved: Boolean;
  fldSigPi, callIndNode, argsHead2, lastArg2, argSeq2, baseRecFld: Integer;
  isMethodPtr: Boolean;
begin
  prevTok := identTokIdx;
  if DebugTrace then writeln('ParseLValueAST: idx = ', idx, ' prevTok = ', prevTok, ' TokenStr = "', GetTokenStr(prevTok), '" CurTok.Line = ', CurTok.Line, ' TokPos = ', TokPos);

  fieldName := GetTokenStr(prevTok);
  withResolved := False;

  { Indirect call through a proc-var / METHOD-POINTER ident: v(args). A
    method-pointer var is tyRecord, so ParseFactor routes it here (not its
    own proc-var branch) and it used to fall into the field path and die on
    the '('. Mirrors ParseProcVarCallAST minus the name consume. }
  if (idx >= 0) and (SymProcSig[idx] >= 0) and (CurTok.Kind = tkLParen) then
  begin
    isMethodPtr := Syms[idx].TypeKind = tyRecord;
    fldSigPi := SymProcSig[idx];
    node := AllocNode(AN_IDENT);
    ASTIVal[node] := idx;
    if isMethodPtr then ASTTk[node] := Ord(tyRecord)
    else ASTTk[node] := Ord(tyPointer);
    Next; { consume '(' }
    argsHead2 := -1; lastArg2 := -1; i := 0;
    while CurTok.Kind <> tkRParen do
    begin
      ParseExpr;
      argSeq2 := AllocNode(AN_ARG);
      ASTLeft[argSeq2] := CurASTNode;
      if argsHead2 = -1 then argsHead2 := argSeq2
      else ASTRight[lastArg2] := argSeq2;
      lastArg2 := argSeq2;
      Inc(i);
      if CurTok.Kind = tkComma then Next
      else if CurTok.Kind <> tkRParen then Error('expected comma or close parenthesis');
    end;
    Expect(tkRParen, ')');
    if i <> Procs[fldSigPi].ParamCount then
      Error('procedural call: wrong number of arguments');
    callIndNode := AllocNode(AN_CALL_IND);
    ASTLeft[callIndNode]  := argsHead2;
    ASTRight[callIndNode] := node;
    ASTIVal[callIndNode]  := fldSigPi;
    ASTTk[callIndNode]    := Ord(Procs[fldSigPi].RetType);
    if isMethodPtr then ASTSLen[callIndNode] := 1 else ASTSLen[callIndNode] := 0;
    Result := callIndNode;
    Exit;
  end;

  if WithStackDepth > 0 then
  begin
    for w := WithStackDepth - 1 downto 0 do
    begin
      withNode := WithStack[w];
      recId := ResolveNodeRec(withNode);
      if recId >= REC_UCLASS_BASE then
      begin
        selfClassCi := recId - REC_UCLASS_BASE;
        fldIdx := FindUField(selfClassCi, fieldName);
        if fldIdx < 0 then
        begin
          { with-scoped PROPERTY with a FIELD accessor — `with TFTPSend.Create
            do ... Username := User` (ftpsend): rewrite to the backing field.
            Write accessor when an assignment follows, read otherwise; method
            accessors are out of scope here (fall through). }
          pri := FindUProp(selfClassCi, fieldName);
          if pri >= 0 then
          begin
            if (CurTok.Kind = tkAssign) and (UPropWriteFLen[pri] > 0) then
            begin
              propFOff := UPropWriteFOff[pri];
              propFLen := UPropWriteFLen[pri];
            end
            else if UPropReadFLen[pri] > 0 then
            begin
              propFOff := UPropReadFOff[pri];
              propFLen := UPropReadFLen[pri];
            end
            else
              propFLen := 0;
            if propFLen > 0 then
            begin
              methName := '';
              for i := 0 to propFLen - 1 do
                AppendChar(methName, TokChars[propFOff + i]);
              fldIdx := FindUField(selfClassCi, methName);
              if fldIdx >= 0 then
              begin
                fieldNode := AllocNode(AN_FIELD);
                ASTLeft[fieldNode] := withNode;
                { codegen re-resolves the field by its own span }
                ASTSOffset[fieldNode] := propFOff;
                ASTSLen[fieldNode] := propFLen;
                tk := IntToTypeKind(UFldTk[fldIdx]);
                recName := UFldRec_[fldIdx];
                ASTTk[fieldNode] := Ord(tk);
                node := fieldNode;
                withResolved := True;
                Break;
              end;
            end;
          end;
        end;
        if fldIdx >= 0 then
        begin
          fieldNode := AllocNode(AN_FIELD);
          ASTLeft[fieldNode] := withNode;
          ASTSOffset[fieldNode] := Tokens[prevTok].SOffset;
          ASTSLen[fieldNode] := Tokens[prevTok].SLen;
          tk := IntToTypeKind(UFldTk[fldIdx]);
          recName := UFldRec_[fldIdx];
          ASTTk[fieldNode] := Ord(tk);
          node := fieldNode;
          withResolved := True;
          Break;
        end;
        { with-scoped `Free;` with no user Free method — the builtin
          TObject.Free desugar over the with operand (ftpsend's finally). }
        if CaseEqual(fieldName, 'Free') and (CurTok.Kind in [tkSemicolon, tkEnd, tkElse]) and
           (FindUMeth(selfClassCi, 'Free') < 0) then
        begin
          node := GenMakeFreeObjectExpr(CloneAST(withNode), selfClassCi);
          tk := tyInteger;
          recName := REC_NONE;
          withResolved := True;
          Break;
        end;
        { with-scoped METHOD, bare or with args — `with TFTPSend.Create do
          ... if not Login then` (ftpsend). Self = the with operand (a
          materialised temp for call operands, so evaluation is per-call of
          the METHOD, not a re-Create). }
        mmi := FindUMethArity(selfClassCi, fieldName, CountCallArgsAhead);
        if mmi >= 0 then
        begin
          mpi := UMthProc_[mmi];
          mselfArg := AllocNode(AN_ARG);
          ASTLeft[mselfArg] := withNode;
          if UMthVirSlot[mmi] >= 0 then
          begin
            mcallNode := AllocNode(AN_VIRTUAL_CALL);
            ASTRight[mcallNode] := UMthVirSlot[mmi];
          end
          else
            mcallNode := AllocNode(AN_CALL);
          ASTIVal[mcallNode] := mpi;
          ASTTk[mcallNode] := Ord(Procs[mpi].RetType);
          ASTLeft[mcallNode] := mselfArg;
          mlastArg := mselfArg;
          if CurTok.Kind = tkLParen then
          begin
            Next;
            while CurTok.Kind <> tkRParen do
            begin
              ParseExpr;
              margSeq := AllocNode(AN_ARG);
              ASTLeft[margSeq] := CurASTNode;
              ASTRight[mlastArg] := margSeq;
              mlastArg := margSeq;
              if CurTok.Kind = tkComma then Next
              else if CurTok.Kind <> tkRParen then Error('expected comma or close parenthesis');
            end;
            Expect(tkRParen, ')');
          end;
          tk := Procs[mpi].RetType;
          recName := ProcRetRecId[mpi];
          node := mcallNode;
          withResolved := True;
          Break;
        end;
      end
      else if (recId <> REC_NONE) and (recId < REC_UCLASS_BASE) then
      begin
        tk := RecFieldType(recId, fieldName);
        if tk <> tyUnknown then
        begin
          fieldNode := AllocNode(AN_FIELD);
          ASTLeft[fieldNode] := withNode;
          ASTSOffset[fieldNode] := Tokens[prevTok].SOffset;
          ASTSLen[fieldNode] := Tokens[prevTok].SLen;
          recName := RecFieldRecId(recId, fieldName);
          ASTTk[fieldNode] := Ord(tk);
          node := fieldNode;
          withResolved := True;
          Break;
        end;
      end;
    end;
  end;

  if not withResolved then
  begin
    if idx < 0 then
    begin
      fldIdx := -1;
      if (CurSelfClass >= REC_UCLASS_BASE) and (CurProc >= 0) and (Procs[CurProc].ParamCount > 0) then
      begin
        selfClassCi := CurSelfClass - REC_UCLASS_BASE;
        fldIdx := FindUField(selfClassCi, fieldName);
      end;

      if fldIdx >= 0 then
    begin
      selfIdx := Procs[CurProc].Params[0].SymIdx;
      selfNode := AllocNode(AN_IDENT);
      ASTIVal[selfNode] := selfIdx;
      ASTTk[selfNode] := Ord(tyClass);

      fieldNode := AllocNode(AN_FIELD);
      ASTLeft[fieldNode] := selfNode;
      ASTSOffset[fieldNode] := Tokens[prevTok].SOffset;
      ASTSLen[fieldNode] := Tokens[prevTok].SLen;

      tk := IntToTypeKind(UFldTk[fldIdx]);
      recName := UFldRec_[fldIdx];
      ASTTk[fieldNode] := Ord(tk);

      node := fieldNode;

      { Indirect call through a procedural-type FIELD, unqualified inside a
        method: FOnKeyPtrCompare(a, b) == Self.FOnKeyPtrCompare(a, b)
        (fgl's compare-callback fields). Mirrors the qualified rec.field(args)
        path below. }
      if (CurTok.Kind = tkLParen) and (not UFldIsArray[fldIdx]) and
         ((tk = tyPointer) or (tk = tyRecord)) and (UFldProcSig[fldIdx] >= 0) then
      begin
        fldSigPi := UFldProcSig[fldIdx];
        isMethodPtr := (tk = tyRecord);
        Expect(tkLParen, '(');
        argsHead2 := -1; lastArg2 := -1;
        while CurTok.Kind <> tkRParen do
        begin
          ParseExpr;
          argSeq2 := AllocNode(AN_ARG);
          ASTLeft[argSeq2] := CurASTNode;
          if argsHead2 = -1 then argsHead2 := argSeq2
          else ASTRight[lastArg2] := argSeq2;
          lastArg2 := argSeq2;
          if CurTok.Kind = tkComma then Next
          else if CurTok.Kind <> tkRParen then Error('expected comma or close parenthesis');
        end;
        Expect(tkRParen, ')');
        callIndNode := AllocNode(AN_CALL_IND);
        ASTLeft[callIndNode]  := argsHead2;
        ASTRight[callIndNode] := fieldNode;
        ASTIVal[callIndNode]  := fldSigPi;
        ASTTk[callIndNode]    := Ord(Procs[fldSigPi].RetType);
        if isMethodPtr then ASTSLen[callIndNode] := 1 else ASTSLen[callIndNode] := 0;
        node := callIndNode;
        tk := Procs[fldSigPi].RetType;
        recName := ProcRetRecId[fldSigPi];
      end;
    end
    else if (CurSelfClass >= REC_UCLASS_BASE) and (CurProc >= 0)
            and (Procs[CurProc].ParamCount > 0)
            and (FindUProp(CurSelfClass - REC_UCLASS_BASE, fieldName) >= 0) then
    begin
      { Bare (unqualified) property access inside a method -> implicit Self.<prop>.
        Field-backed read/write rewrites to the backing field (like the bare-field
        path above) using the correct accessor for the context. Method-backed READ
        builds the getter call; an INDEXED property builds the getter/setter call
        with the [index] args (fgl's InternalItems[i] / [i] := v). A non-indexed
        method-backed WRITE stays Self.<prop> := ... (needs the RHS earlier than
        this path sees it). See bug-unqualified-property-in-method. }
      selfClassCi := CurSelfClass - REC_UCLASS_BASE;
      pri := FindUProp(selfClassCi, fieldName);
      isAssign := (CurTok.Kind = tkAssign);
      selfIdx := Procs[CurProc].Params[0].SymIdx;
      selfNode := AllocNode(AN_IDENT);
      ASTIVal[selfNode] := selfIdx;
      ASTTk[selfNode] := Ord(tyClass);
      if UPropIsIndexed[pri] then
      begin
        if CurTok.Kind <> tkLBrack then
          Error('indexed property requires an index: ' + fieldName);
        { write iff `:=` follows the bracket group (CurTok = '[', at TokPos-1) }
        isAssign := False;
        i := TokPos - 1; w := 0;
        while i < TokCount do
        begin
          if Tokens[i].Kind = tkLBrack then Inc(w)
          else if Tokens[i].Kind = tkRBrack then
          begin Dec(w); if w = 0 then begin Inc(i); Break; end; end;
          Inc(i);
        end;
        if (i < TokCount) and (Tokens[i].Kind = tkAssign) then isAssign := True;
        ParsePropIndexArgs(margIdx, mlastArg);
        methName := '';
        if isAssign then
        begin
          if UPropWriteMLen[pri] = 0 then Error('indexed property has no setter: ' + fieldName);
          for i := 0 to UPropWriteMLen[pri] - 1 do
            AppendChar(methName, TokChars[UPropWriteMOff[pri] + i]);
        end
        else
        begin
          if UPropReadMLen[pri] = 0 then Error('indexed property has no getter method: ' + fieldName);
          for i := 0 to UPropReadMLen[pri] - 1 do
            AppendChar(methName, TokChars[UPropReadMOff[pri] + i]);
        end;
        mmi := FindUMeth(selfClassCi, methName);
        if mmi < 0 then Error('property accessor method not found: ' + methName);
        mpi := UMthProc_[mmi];
        if UMthVirSlot[mmi] >= 0 then
        begin
          mcallNode := AllocNode(AN_VIRTUAL_CALL);
          ASTRight[mcallNode] := UMthVirSlot[mmi];
        end
        else
          mcallNode := AllocNode(AN_CALL);
        ASTIVal[mcallNode] := mpi;
        ASTTk[mcallNode] := Ord(Procs[mpi].RetType);
        mselfArg := AllocNode(AN_ARG);
        ASTLeft[mselfArg] := selfNode;
        ASTLeft[mcallNode] := mselfArg;
        ASTRight[mselfArg] := margIdx;   { self, index... }
        if isAssign then
        begin
          Expect(tkAssign, ':=');
          ParseExpr;
          margSeq := AllocNode(AN_ARG);
          ASTLeft[margSeq] := CurASTNode;  { self, index..., value }
          ASTRight[mlastArg] := margSeq;
          Result := mcallNode;   { complete setter statement; the statement
                                   caller accepts a returned call node as-is }
          Exit;
        end;
        tk := Procs[mpi].RetType;
        if (tk = tyClass) or (tk = tyRecord) then recName := ProcRetRecId[mpi]
        else recName := REC_NONE;
        node := mcallNode;
        { falls through to the trailing-selector loop (e.g. InternalItems[i]^) }
      end
      else if isAssign then
      begin
        { assignment target: use the WRITE accessor }
        if UPropWriteFLen[pri] > 0 then
        begin
          fieldName := '';
          for i := 0 to UPropWriteFLen[pri] - 1 do
            AppendChar(fieldName, TokChars[UPropWriteFOff[pri] + i]);
          fldIdx := FindUField(selfClassCi, fieldName);
          if fldIdx < 0 then Error('property backing field not found: ' + fieldName);
          fieldNode := AllocNode(AN_FIELD);
          ASTLeft[fieldNode] := selfNode;
          ASTSOffset[fieldNode] := UPropWriteFOff[pri];
          ASTSLen[fieldNode] := UPropWriteFLen[pri];
          tk := IntToTypeKind(UFldTk[fldIdx]);
          recName := UFldRec_[fldIdx];
          ASTTk[fieldNode] := Ord(tk);
          node := fieldNode;
        end
        else if UPropWriteMLen[pri] > 0 then
        begin
          { unqualified setter-method write: Capacity := v -> Self.SetCapacity(v)
            (same complete-call-statement shape as the indexed branch above) }
          methName := '';
          for i := 0 to UPropWriteMLen[pri] - 1 do
            AppendChar(methName, TokChars[UPropWriteMOff[pri] + i]);
          mmi := FindUMeth(selfClassCi, methName);
          if mmi < 0 then Error('setter method not found: ' + methName);
          mpi := UMthProc_[mmi];
          Expect(tkAssign, ':=');
          ParseExpr;
          if UMthVirSlot[mmi] >= 0 then
          begin
            mcallNode := AllocNode(AN_VIRTUAL_CALL);
            ASTRight[mcallNode] := UMthVirSlot[mmi];
          end
          else
            mcallNode := AllocNode(AN_CALL);
          ASTIVal[mcallNode] := mpi;
          ASTTk[mcallNode] := Ord(Procs[mpi].RetType);
          mselfArg := AllocNode(AN_ARG);
          ASTLeft[mselfArg] := selfNode;
          ASTLeft[mcallNode] := mselfArg;
          margSeq := AllocNode(AN_ARG);
          ASTLeft[margSeq] := CurASTNode;   { value }
          ASTRight[mselfArg] := margSeq;
          Result := mcallNode;
          Exit;
        end
        else
          Error('property is read-only: ' + fieldName);
      end
      else if UPropReadFLen[pri] > 0 then
      begin
        { backing read field -> resolve + build Self.field }
        fieldName := '';
        for i := 0 to UPropReadFLen[pri] - 1 do
          AppendChar(fieldName, TokChars[UPropReadFOff[pri] + i]);
        fldIdx := FindUField(selfClassCi, fieldName);
        if fldIdx < 0 then Error('property backing field not found: ' + fieldName);
        fieldNode := AllocNode(AN_FIELD);
        ASTLeft[fieldNode] := selfNode;
        { source location of the BACKING field name (not the property name) — codegen
          re-resolves the field by this span, like the qualified Self.<prop> path. }
        ASTSOffset[fieldNode] := UPropReadFOff[pri];
        ASTSLen[fieldNode] := UPropReadFLen[pri];
        tk := IntToTypeKind(UFldTk[fldIdx]);
        recName := UFldRec_[fldIdx];
        ASTTk[fieldNode] := Ord(tk);
        node := fieldNode;
        { Indirect call through a PROCEDURAL-typed property, unqualified inside
          a method: OnStatus(Self, ...) with `property OnStatus: THook read
          FOnStatus` (blcksock's DoStatus). Same shape as the bare proc-field
          call above, over the backing field. }
        if (CurTok.Kind = tkLParen) and (not UFldIsArray[fldIdx]) and
           ((tk = tyPointer) or (tk = tyRecord)) and (UFldProcSig[fldIdx] >= 0) then
        begin
          fldSigPi := UFldProcSig[fldIdx];
          isMethodPtr := (tk = tyRecord);
          Expect(tkLParen, '(');
          argsHead2 := -1; lastArg2 := -1;
          while CurTok.Kind <> tkRParen do
          begin
            ParseExpr;
            argSeq2 := AllocNode(AN_ARG);
            ASTLeft[argSeq2] := CurASTNode;
            if argsHead2 = -1 then argsHead2 := argSeq2
            else ASTRight[lastArg2] := argSeq2;
            lastArg2 := argSeq2;
            if CurTok.Kind = tkComma then Next
            else if CurTok.Kind <> tkRParen then Error('expected comma or close parenthesis');
          end;
          Expect(tkRParen, ')');
          callIndNode := AllocNode(AN_CALL_IND);
          ASTLeft[callIndNode]  := argsHead2;
          ASTRight[callIndNode] := fieldNode;
          ASTIVal[callIndNode]  := fldSigPi;
          ASTTk[callIndNode]    := Ord(Procs[fldSigPi].RetType);
          if isMethodPtr then ASTSLen[callIndNode] := 1 else ASTSLen[callIndNode] := 0;
          node := callIndNode;
          tk := Procs[fldSigPi].RetType;
          recName := ProcRetRecId[fldSigPi];
        end;
      end
      else if UPropReadMLen[pri] > 0 then
      begin
        { backing getter method -> build a (virtual) call with Self as arg }
        methName := '';
        for i := 0 to UPropReadMLen[pri] - 1 do
          AppendChar(methName, TokChars[UPropReadMOff[pri] + i]);
        mmi := FindUMeth(selfClassCi, methName);
        if mmi < 0 then Error('property getter method not found: ' + methName);
        mpi := UMthProc_[mmi];
        if UMthVirSlot[mmi] >= 0 then
        begin
          mcallNode := AllocNode(AN_VIRTUAL_CALL);
          ASTRight[mcallNode] := UMthVirSlot[mmi];
        end
        else
          mcallNode := AllocNode(AN_CALL);
        ASTIVal[mcallNode] := mpi;
        ASTTk[mcallNode] := Ord(Procs[mpi].RetType);
        mselfArg := AllocNode(AN_ARG);
        ASTLeft[mselfArg] := selfNode;
        ASTLeft[mcallNode] := mselfArg;
        tk := Procs[mpi].RetType;
        recName := REC_NONE;
        node := mcallNode;
      end
      else
        Error('property is write-only: ' + fieldName);
    end
    else
    begin
      aliasIdx := FindTypeAlias(fieldName);
      if (aliasIdx >= 0) and (CurTok.Kind = tkLParen) then
      begin
        Next; { consume '(' }
        ParseExpr;
        Expect(tkRParen, ')');
        node := AllocNode(AN_PTR_CAST);
        ASTLeft[node] := CurASTNode;
        ASTIVal[node] := aliasIdx;
        ASTTk[node]   := Ord(tyPointer);
        tk := tyPointer;
        recName := AliasElemRec[aliasIdx];
      end
      else
      begin
        ci := FindUClass(fieldName);
        if ci >= 0 then
        begin
          if CurTok.Kind <> tkDot then
          begin
            { Class identifier used as a value (metaclass / class reference):
              `TForm1` passed to CreateForm etc. Yields the runtime address of
              the class's RTTI blob (PClassRTTI), resolved post-EmitRTTI. }
            node := AllocNode(AN_CLASSREF);
            ASTIVal[node] := ci;
            ASTTk[node] := Ord(tyPointer);
            tk := tyPointer;
            recName := REC_NONE;
            Result := node;
            Exit;
          end;
          Expect(tkDot, '.');
          if CurTok.Kind <> tkIdent then Error('expected class method name');
          fieldName := CurTok.SVal;
          Next;

          mmi := FindUMeth(ci, fieldName);
          if mmi < 0 then
          begin
            { class variable: TClass.cnt -> the backing global var (an lvalue, so
              read and write both work). }
            fldIdx := FindClassVar(ci, fieldName);
            if fldIdx >= 0 then
            begin
              node := AllocNode(AN_IDENT);
              ASTIVal[node] := fldIdx;
              ASTTk[node] := Ord(Syms[fldIdx].TypeKind);
              tk := Syms[fldIdx].TypeKind; recName := REC_NONE;
              Result := node;
              Exit;
            end;
            Error('class method not found: ' + fieldName);
          end;
          mpi := UMthProc_[mmi];

          if UMthIsCtor[mmi] then
          begin
            { TClass.AnyCtor(args) as an expression (raise EListError.CreateFmt
              ... shape) — construct via the metaclass path: static classref,
              virtual-or-direct ctor dispatch, defaults filled. The
              'create'-named fast path elsewhere covers only that name. }
            node := AllocNode(AN_CLASSREF);
            ASTIVal[node] := ci;
            ASTTk[node] := Ord(tyPointer);
            node := BuildMetaclassNew(node, ci, mmi);
            tk := tyClass;
            recName := REC_UCLASS_BASE + ci;
            Result := node;
            Exit;
          end;

          if not UMthIsStatic[mmi] then
            Error('cannot call non-static method on class type directly');

          mcallNode := AllocNode(AN_CALL);
          ASTIVal[mcallNode] := mpi;
          ASTTk[mcallNode] := Ord(Procs[mpi].RetType);
          mlastArg := -1;

          if CurTok.Kind = tkLParen then
          begin
            Next;
            mai := 0;
            while mai <= Procs[mpi].ParamCount-1 do
            begin
              if Procs[mpi].Params[mai].IsRef or Procs[mpi].Params[mai].IsArray then
              begin
                if ByRefArgStartsExpression then
                begin
                  { non-ident by-ref/array arg (@obj.Method to a method-pointer
                    param, [..] literals, casts): parse as an expression }
                  ParseExpr; mexprNode := CurASTNode;
                end
                else
                begin
                  margIdx := FindSym(CurTok.SVal); Next;
                  mexprNode := ParseLValueAST(margIdx, TokPos - 2);
                end;
              end
              else
              begin
                ParseExpr; mexprNode := CurASTNode;
              end;
              margSeq := AllocNode(AN_ARG); ASTLeft[margSeq] := mexprNode;
              if mlastArg = -1 then
                ASTLeft[mcallNode] := margSeq
              else
                ASTRight[mlastArg] := margSeq;
              mlastArg := margSeq;
              if (mai < Procs[mpi].ParamCount-1) and CanFillDefaultsFrom(mpi, mai+1) then
              begin
                FillDefaultArgs(mpi, mai+1, mcallNode, mlastArg);
                mai := Procs[mpi].ParamCount-1;
              end
              else if mai < Procs[mpi].ParamCount-1 then Expect(tkComma, ',');
              Inc(mai);
            end;
            Expect(tkRParen, ')');
          end;

          Result := mcallNode;
          Exit;
        end
        else
        begin
          ErrorIdent := fieldName;
          if HiddenByDeclOrder(fieldName) then
            Error('undefined variable — it is a global declared later, declare it before use')
          else
            Error('undefined variable');
        end;
      end;
    end;
  end
  else
  begin
    node := AllocNode(AN_IDENT);
    ASTIVal[node] := idx;
    ASTSOffset[node] := Tokens[prevTok].SOffset;
    ASTSLen[node] := Tokens[prevTok].SLen;
    tk := Syms[idx].TypeKind;
    recName := Syms[idx].RecName;
    ASTTk[node] := StrValTk(tk);   { frozen fixed/short string presents as a tyString value }
  end;
  end;

  while CurTok.Kind in [tkLBrack, tkDot, tkCaret] do
  begin
    if CurTok.Kind = tkCaret then
    begin
      Next;
      indexNode := AllocNode(AN_DEREF);
      ASTLeft[indexNode] := node;
      if tk = tyPointer then
      begin
        remDepth := 0;
        ptrBaseTk := Ord(tyUnknown);
        ptrBaseRec := REC_NONE;
        if ASTKind[node] = AN_IDENT then
        begin
          tk := Syms[ASTIVal[node]].PtrElemTk;
          recName := Syms[ASTIVal[node]].PtrElemRec;
          if SymPtrDepth[ASTIVal[node]] > 0 then
          begin
            remDepth := SymPtrDepth[ASTIVal[node]] - 1;
            ptrBaseTk := SymPtrBaseTk[ASTIVal[node]];
            ptrBaseRec := SymPtrBaseRec[ASTIVal[node]];
          end;
        end
        else if ASTKind[node] = AN_FIELD then
        begin
          baseNode := ASTLeft[node];
          baseRec := ResolveNodeRec(baseNode);
          fieldName := GetASTIdentName(node);
          fIdx := -1;
          if baseRec >= REC_UCLASS_BASE then
            fIdx := FindUField(baseRec - REC_UCLASS_BASE, fieldName);
          if fIdx >= 0 then
          begin
            tk := IntToTypeKind(UFldPtrElemTk[fIdx]);
            recName := UFldPtrElemRec[fIdx];
          end
          else
          begin
            tk := tyUnknown;
            recName := REC_NONE;
          end;
        end
        else if ASTKind[node] = AN_INDEX then
        begin
          baseNode := ASTLeft[node];
          if ASTKind[baseNode] = AN_IDENT then
          begin
            tk := Syms[ASTIVal[baseNode]].PtrElemTk;
            recName := Syms[ASTIVal[baseNode]].PtrElemRec;
          end
          else
          begin
            tk := tyUnknown;
            recName := REC_NONE;
          end;
        end
        else if ASTKind[node] = AN_DEREF then
        begin
          if ASTSOffset[node] > 0 then
          begin
            remDepth := ASTSOffset[node] - 1;
            ptrBaseTk := ASTSLen[node];
            ptrBaseRec := ASTIVal[node];
            if remDepth >= 1 then
            begin
              tk := tyPointer;
              recName := ptrBaseRec;
            end
            else if ptrBaseTk <> Ord(tyUnknown) then
            begin
              tk := IntToTypeKind(ptrBaseTk);
              recName := ptrBaseRec;
            end
            else
            begin
              tk := tyUnknown;
              recName := REC_NONE;
            end;
          end
          else
          begin
            tk := tyInteger;
            recName := REC_NONE;
          end;
        end
        else
        begin
          tk := tyInteger;
          recName := REC_NONE;
        end;
        if remDepth >= 1 then
        begin
          tk := tyPointer;
          recName := ptrBaseRec;
        end;
        ASTSOffset[indexNode] := remDepth;
        ASTSLen[indexNode] := ptrBaseTk;
        if ptrBaseRec > 0 then ASTIVal[indexNode] := ptrBaseRec;
      end
      else
        Error('dereferenced value is not a pointer');
      ASTTk[indexNode] := StrValTk(tk);
      node := indexNode;
    end
    else if CurTok.Kind = tkLBrack then
    begin
      { Default indexed property: `obj[i]` → obj.<default>[i] getter/setter. }
      if (tk = tyClass) and (recName >= REC_UCLASS_BASE) then
      begin
        mci := recName - REC_UCLASS_BASE;
        pri := FindDefaultProp(mci);
        if pri >= 0 then
        begin
          { peek past the [...] group for a trailing := (assignment context) }
          isAssign := False;
          i := TokPos - 1; w := 0;   { TokPos-1 = the '[' }
          while i < TokCount do
          begin
            if Tokens[i].Kind = tkLBrack then Inc(w)
            else if Tokens[i].Kind = tkRBrack then
            begin Dec(w); if w = 0 then begin Inc(i); Break; end; end;
            Inc(i);
          end;
          if (i < TokCount) and (Tokens[i].Kind = tkAssign) then isAssign := True;

          ParsePropIndexArgs(margIdx, mlastArg);   { [a {, b}] (bracket consumed here) }

          if isAssign then
          begin
            if UPropWriteMLen[pri] <= 0 then Error('default property is read-only');
            methName := '';
            for i := 0 to UPropWriteMLen[pri] - 1 do AppendChar(methName, TokChars[UPropWriteMOff[pri] + i]);
            mmi := FindUMeth(mci, methName);
            if mmi < 0 then Error('setter method not found: ' + methName);
            mpi := UMthProc_[mmi];
            Expect(tkAssign, ':=');
            ParseExpr;
            if UMthVirSlot[mmi] >= 0 then begin mcallNode := AllocNode(AN_VIRTUAL_CALL); ASTRight[mcallNode] := UMthVirSlot[mmi]; end
            else mcallNode := AllocNode(AN_CALL);
            ASTIVal[mcallNode] := mpi; ASTTk[mcallNode] := Ord(Procs[mpi].RetType);
            mselfArg := AllocNode(AN_ARG); ASTLeft[mselfArg] := node; ASTLeft[mcallNode] := mselfArg;
            margSeq := AllocNode(AN_ARG); ASTLeft[margSeq] := CurASTNode;  { value }
            ASTRight[mselfArg] := margIdx; ASTRight[mlastArg] := margSeq;
            node := mcallNode; Result := node; Exit;
          end
          else
          begin
            if UPropReadMLen[pri] <= 0 then Error('default property is write-only');
            methName := '';
            for i := 0 to UPropReadMLen[pri] - 1 do AppendChar(methName, TokChars[UPropReadMOff[pri] + i]);
            mmi := FindUMeth(mci, methName);
            if mmi < 0 then Error('getter method not found: ' + methName);
            mpi := UMthProc_[mmi];
            if UMthVirSlot[mmi] >= 0 then begin mcallNode := AllocNode(AN_VIRTUAL_CALL); ASTRight[mcallNode] := UMthVirSlot[mmi]; end
            else mcallNode := AllocNode(AN_CALL);
            ASTIVal[mcallNode] := mpi; ASTTk[mcallNode] := Ord(Procs[mpi].RetType);
            mselfArg := AllocNode(AN_ARG); ASTLeft[mselfArg] := node; ASTLeft[mcallNode] := mselfArg;
            ASTRight[mselfArg] := margIdx;
            node := mcallNode;
            tk := IntToTypeKind(UPropTk[pri]); recName := UPropRec[pri];
            ASTTk[node] := StrValTk(tk);
            continue;   { allow further postfix on the getter result }
          end;
        end;
      end;
      Next;
      alreadyResolved := False;
      indexNode := AllocNode(AN_INDEX);
      ASTLeft[indexNode] := node;
      ParseExpr;
      { N-D fixed array (variable or record field), both syntaxes folded into one
        flattened 1-D index: m[i0,i1,..]/r.m[..] (commas) and m[i0][i1]..
        (consecutive brackets). Handled here so no bogus intermediate m[i0] is
        built. NodeArrNDInfo fills NDInfo* (dims) for the base. }
      isND := NodeArrNDInfo(node);
      if isND and (CurTok.Kind = tkComma) then
      begin
        NDIdxNode[0] := CurASTNode; nIdx := 1;
        while Eat(tkComma) do
        begin
          if nIdx >= NDInfoNDims then Error('too many subscripts for array');
          ParseExpr; NDIdxNode[nIdx] := CurASTNode; Inc(nIdx);
        end;
        if nIdx <> NDInfoNDims then Error('wrong number of array subscripts');
        ASTRight[indexNode] := BuildFlatNDIndex(nIdx);
        Expect(tkRBrack, ']');
      end
      else if isND and (CurTok.Kind = tkRBrack) and (Tokens[TokPos].Kind = tkLBrack) then
      begin
        NDIdxNode[0] := CurASTNode; nIdx := 1;
        Expect(tkRBrack, ']');
        while (CurTok.Kind = tkLBrack) and (nIdx < NDInfoNDims) do
        begin
          Expect(tkLBrack, '[');
          ParseExpr; NDIdxNode[nIdx] := CurASTNode; Inc(nIdx);
          Expect(tkRBrack, ']');
        end;
        if nIdx <> NDInfoNDims then Error('wrong number of array subscripts');
        ASTRight[indexNode] := BuildFlatNDIndex(nIdx);
      end
      else if CurTok.Kind = tkComma then
      begin
        { Comma sugar m[i,j,..] == m[i][j].. for jagged / dynamic arrays: build
          the same nested AN_INDEX chain the bracket form does. (Fixed N-D arrays
          took the isND branch above; this is the dynamic / jagged path.) }
        ASTRight[indexNode] := CurASTNode;
        if IsNodeArray(node) then
        begin
          if ASTKind[node] = AN_IDENT then
          begin tk := Syms[ASTIVal[node]].ElemType; recName := Syms[ASTIVal[node]].ElemRecName; end
          else recName := ResolveNodeRec(node);
        end;
        ASTTk[indexNode] := StrValTk(tk);
        node := indexNode;
        while Eat(tkComma) do
        begin
          ParseExpr;
          indexNode := AllocNode(AN_INDEX);
          ASTLeft[indexNode] := node;
          ASTRight[indexNode] := CurASTNode;
          if IsNodeArray(node) then
          begin
            if ASTKind[node] = AN_IDENT then
            begin tk := Syms[ASTIVal[node]].ElemType; recName := Syms[ASTIVal[node]].ElemRecName; end
            else recName := ResolveNodeRec(node);
          end;
          ASTTk[indexNode] := StrValTk(tk);
          node := indexNode;
        end;
        Expect(tkRBrack, ']');
        alreadyResolved := True;
      end
      else if isND then
      begin
        { Partial: a single leading subscript on an N-D fixed array names a whole
          row (sub-array). Scale it to the row's first-element flat index so the
          element-stride AN_INDEX yields the row base address. }
        ASTRight[indexNode] := BuildPartialNDRowIndex(CurASTNode);
        Expect(tkRBrack, ']');
      end
      else
      begin
        ASTRight[indexNode] := CurASTNode;
        Expect(tkRBrack, ']');
      end;
      if alreadyResolved then
        { type + node already set by the comma-sugar chain above }
      else if IsNodeArray(node) then
      begin
        if ASTKind[node] = AN_IDENT then
        begin
          tk := Syms[ASTIVal[node]].ElemType;
          recName := Syms[ASTIVal[node]].ElemRecName;
        end
        else
          recName := ResolveNodeRec(node);
      end
      else if TypeIsFrozenString(tk) or (tk = tyAnsiString) then
        tk := tyChar
      else if (tk = tyPointer) and (ASTKind[node] = AN_IDENT) then
      begin
        { pointer indexing: p[i] yields the pointed-at element type }
        tk := Syms[ASTIVal[node]].PtrElemTk;
        recName := Syms[ASTIVal[node]].PtrElemRec;
      end
      else if (tk = tyPointer) and (ASTKind[node] = AN_PTR_CAST) then
      begin
        aliasIdx := ASTIVal[node];
        tk := IntToTypeKind(AliasElemTk[aliasIdx]);
        recName := AliasElemRec[aliasIdx];
      end
      else if (tk = tyPointer) and (ASTKind[node] = AN_FIELD) then
      begin
        { pointer-typed field indexing FField[i]: element type/rec from the
          field's pointed-at metadata, so a trailing .field resolves correctly }
        baseNode := ASTLeft[node];
        baseRec := ResolveNodeRec(baseNode);
        fieldName := GetASTIdentName(node);
        fIdx := -1;
        if baseRec >= REC_UCLASS_BASE then
          fIdx := FindUField(baseRec - REC_UCLASS_BASE, fieldName);
        if fIdx >= 0 then
        begin
          tk := IntToTypeKind(UFldPtrElemTk[fIdx]);
          recName := UFldPtrElemRec[fIdx];
        end
        else
        begin
          tk := tyUnknown;
          recName := REC_NONE;
        end;
      end
      else
      begin
        if idx >= 0 then
        begin
          tk := Syms[idx].ElemType;
          recName := Syms[idx].ElemRecName;
        end
        else
        begin
          tk := tyUnknown;
          recName := REC_NONE;
        end;
      end;
      ASTTk[indexNode] := StrValTk(tk);
      node := indexNode;

      { Indirect call through a proc-typed array element: `arr[i](args)`. The
        element value is the proc pointer (tyPointer) or a {Code,Data} method
        pointer (tyRecord); AN_CALL_IND evaluates ASTRight (the index node) as the
        callee. Mirrors the record-field path below. The element signature is
        SymElemProcSig, captured at the array declaration. }
      baseNode := ASTLeft[indexNode];
      fldSigPi := -1;
      if (ASTKind[baseNode] = AN_IDENT) and (CurTok.Kind = tkLParen) and
         ((tk = tyPointer) or (tk = tyRecord)) then
        fldSigPi := SymElemProcSig[ASTIVal[baseNode]];
      if fldSigPi >= 0 then
      begin
        isMethodPtr := (tk = tyRecord);
        Expect(tkLParen, '(');
        argsHead2 := -1; lastArg2 := -1;
        while CurTok.Kind <> tkRParen do
        begin
          ParseExpr;
          argSeq2 := AllocNode(AN_ARG);
          ASTLeft[argSeq2] := CurASTNode;
          if argsHead2 = -1 then argsHead2 := argSeq2
          else ASTRight[lastArg2] := argSeq2;
          lastArg2 := argSeq2;
          if CurTok.Kind = tkComma then Next
          else if CurTok.Kind <> tkRParen then Error('expected comma or close parenthesis');
        end;
        Expect(tkRParen, ')');
        callIndNode := AllocNode(AN_CALL_IND);
        ASTLeft[callIndNode]  := argsHead2;
        ASTRight[callIndNode] := indexNode;
        ASTIVal[callIndNode]  := fldSigPi;
        ASTTk[callIndNode]    := Ord(Procs[fldSigPi].RetType);
        if isMethodPtr then ASTSLen[callIndNode] := 1 else ASTSLen[callIndNode] := 0;
        node := callIndNode;
        tk := Procs[fldSigPi].RetType;
        recName := ProcRetRecId[fldSigPi];
      end;
    end
    else
    begin
      { `.member` directly on an ARRAY variable: arrays have no members in
        pxx (FPC's arr.Create constructor is only valid on the TYPE, and even
        that form is unsupported here). The old fall-through built a bogus
        field access that crashed at runtime (tarrconstr8). Element access
        `arr[i].field` takes the bracket branch above, strings take Length()
        style intrinsics — neither reaches this check. }
      if (ASTKind[node] = AN_IDENT) and (ASTIVal[node] >= 0) and
         Syms[ASTIVal[node]].IsArray and
         not (Syms[ASTIVal[node]].TypeKind in [tyRecord, tyClass]) then
        Error('an array variable has no members (use SetLength / index it)');
      Next;
      if CurTok.Kind in [tkEOF, tkSemicolon, tkAssign, tkRBrack, tkRParen] then Error('expected field name');
      prevTok := TokPos - 1;
      fieldName := '';
      for i := Tokens[prevTok].SOffset to Tokens[prevTok].SOffset + Tokens[prevTok].SLen - 1 do
        AppendChar(fieldName, TokChars[i]);
      { Default field-name source span = the parsed token; property-backed
        access overrides it below with the backing field's span. }
      propFOff := Tokens[prevTok].SOffset;
      propFLen := Tokens[prevTok].SLen;

      { Metaclass-dispatched construction `classRef.Create(args)`: the base is a
        metaclass value — either a `class of T` variable (AN_IDENT, a tyPointer
        whose element is a class) or an inline metaclass cast `TFooClass(expr)`
        (AN_PTR_CAST over a `class of` alias, e.g. the streamer's
        `TComponentClass(GetClass(name)).Create(owner)`). Build AN_METACLASS_NEW,
        which allocates the DYNAMIC class the ref points at and runs its virtual
        constructor — see the IR lowering. Distinct from the static `TFoo.Create`
        path, which resolves the class at compile time. }
      ci := -1;
      if (ASTKind[node] = AN_IDENT) and (ASTIVal[node] >= 0) and
         (Syms[ASTIVal[node]].TypeKind = tyPointer) and
         (Syms[ASTIVal[node]].PtrElemTk = tyClass) and
         (Syms[ASTIVal[node]].PtrElemRec >= REC_UCLASS_BASE) then
        ci := Syms[ASTIVal[node]].PtrElemRec - REC_UCLASS_BASE
      else if (ASTKind[node] = AN_PTR_CAST) and (ASTIVal[node] >= 0) and
              (IntToTypeKind(AliasElemTk[ASTIVal[node]]) = tyClass) and
              (AliasElemRec[ASTIVal[node]] >= REC_UCLASS_BASE) then
        ci := AliasElemRec[ASTIVal[node]] - REC_UCLASS_BASE;
      if (ci >= 0) and CaseEqual(fieldName, 'create') then
      begin
        mmi := FindUMeth(ci, 'create');
        if mmi >= 0 then
        begin
          Next; { consume the 'Create' method name }
          node := BuildMetaclassNew(node, ci, mmi);
          recName := REC_UCLASS_BASE + ci;
          tk := tyClass;
          Continue;   { allow trailing .field/[i] selectors on the new instance }
        end;
      end;

      { Bare `object` reference (tyPointer whose element is tyClass with NO
        class id): member access cannot resolve — the reference carries no
        class. Require an explicit cast to a concrete class first
        (feature-object-reference-type). }
      if (ASTKind[node] = AN_IDENT) and (ASTIVal[node] >= 0) and
         (Syms[ASTIVal[node]].TypeKind = tyPointer) and
         (Syms[ASTIVal[node]].PtrElemTk = tyClass) and
         (Syms[ASTIVal[node]].PtrElemRec = REC_NONE) then
        Error('member access on a bare object reference; cast to a concrete class first');

      { Check if it is a property on a class }
      mci := -1; pri := -1;
      if recName >= REC_UCLASS_BASE then
      begin
        mci := recName - REC_UCLASS_BASE;
        pri := FindUProp(mci, fieldName);
      end;

      if pri >= 0 then
      begin
        isAssign := (CurTok.Kind = tkAssign) or ((TokPos < TokCount) and (Tokens[TokPos].Kind = tkAssign));
        { Indexed property `obj.Items[i] := v`: `:=` follows the subscript, not the
          name. Peek past the bracket group (CurTok = name, TokPos = `[`). }
        if UPropIsIndexed[pri] and (not isAssign) and
           (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLBrack) then
        begin
          i := TokPos; w := 0;
          while i < TokCount do
          begin
            if Tokens[i].Kind = tkLBrack then Inc(w)
            else if Tokens[i].Kind = tkRBrack then
            begin Dec(w); if w = 0 then begin Inc(i); Break; end; end;
            Inc(i);
          end;
          if (i < TokCount) and (Tokens[i].Kind = tkAssign) then isAssign := True;
        end;
        if isAssign then
        begin
          if UPropWriteFLen[pri] > 0 then
          begin
            fieldName := '';
            for i := 0 to UPropWriteFLen[pri] - 1 do
              AppendChar(fieldName, TokChars[UPropWriteFOff[pri] + i]);
            propFOff := UPropWriteFOff[pri];
            propFLen := UPropWriteFLen[pri];
          end
          else if UPropWriteMLen[pri] > 0 then
          begin
            methName := '';
            for i := 0 to UPropWriteMLen[pri] - 1 do
              AppendChar(methName, TokChars[UPropWriteMOff[pri] + i]);
            mmi := FindUMeth(mci, methName);
            if mmi < 0 then Error('setter method not found: ' + methName);
            mpi := UMthProc_[mmi];

            if CurTok.Kind = tkIdent then Next; { consume property name }
            margIdx := -1;
            if UPropIsIndexed[pri] then ParsePropIndexArgs(margIdx, mlastArg);
            Expect(tkAssign, ':=');
            ParseExpr;

            if UMthVirSlot[mmi] >= 0 then
            begin
              mcallNode := AllocNode(AN_VIRTUAL_CALL);
              ASTRight[mcallNode] := UMthVirSlot[mmi];
            end
            else
            begin
              mcallNode := AllocNode(AN_CALL);
            end;
            ASTIVal[mcallNode] := mpi;
            ASTTk[mcallNode] := Ord(Procs[mpi].RetType);

            mselfArg := AllocNode(AN_ARG);
            ASTLeft[mselfArg] := node;
            ASTLeft[mcallNode] := mselfArg;

            margSeq := AllocNode(AN_ARG);
            ASTLeft[margSeq] := CurASTNode;   { value }
            { Setter args: self [, index...], value }
            if margIdx >= 0 then
            begin
              ASTRight[mselfArg] := margIdx;
              ASTRight[mlastArg] := margSeq;
            end
            else
              ASTRight[mselfArg] := margSeq;

            node := mcallNode;
            Result := node; Exit;
          end
          else
            Error('property is read-only');
        end
        else
        begin
          if UPropReadFLen[pri] > 0 then
          begin
            fieldName := '';
            for i := 0 to UPropReadFLen[pri] - 1 do
              AppendChar(fieldName, TokChars[UPropReadFOff[pri] + i]);
            propFOff := UPropReadFOff[pri];
            propFLen := UPropReadFLen[pri];
          end
          else if UPropReadMLen[pri] > 0 then
          begin
            methName := '';
            for i := 0 to UPropReadMLen[pri] - 1 do
              AppendChar(methName, TokChars[UPropReadMOff[pri] + i]);
            mmi := FindUMeth(mci, methName);
            if mmi < 0 then Error('getter method not found: ' + methName);
            mpi := UMthProc_[mmi];

            Next; { consume property name }
            margIdx := -1;
            if UPropIsIndexed[pri] then ParsePropIndexArgs(margIdx, mlastArg);
            if UMthVirSlot[mmi] >= 0 then
            begin
              mcallNode := AllocNode(AN_VIRTUAL_CALL);
              ASTRight[mcallNode] := UMthVirSlot[mmi];
            end
            else
            begin
              mcallNode := AllocNode(AN_CALL);
            end;
            ASTIVal[mcallNode] := mpi;
            ASTTk[mcallNode] := Ord(Procs[mpi].RetType);

            mselfArg := AllocNode(AN_ARG);
            ASTLeft[mselfArg] := node;
            ASTLeft[mcallNode] := mselfArg;
            { Getter args: self [, index...] }
            if margIdx >= 0 then ASTRight[mselfArg] := margIdx;

            node := mcallNode;
            { trailing ^ on the getter result — T(FList.Items[i]^) in fgl's
              enumerator: deref the returned (untyped) pointer; read as Int64,
              an outer ordinal cast narrows }
            while CurTok.Kind = tkCaret do
            begin
              Next;
              mselfArg := AllocNode(AN_DEREF);
              ASTLeft[mselfArg] := node;
              ASTTk[mselfArg] := Ord(tyInt64);
              node := mselfArg;
            end;
            Result := node; Exit;
          end
          else
            Error('property is write-only');
        end;
      end;

      { Check if this is a method call on a user class }
      mci := -1; mmi := -1; mpi := -1;
      if recName >= REC_UCLASS_BASE then
      begin
        mci := recName - REC_UCLASS_BASE;
        { overload-aware: pick the entry matching the call's arg count }
        mmi := FindUMethArity(mci, fieldName, CountCallArgsAhead);
      end;
      if mmi >= 0 then
      begin
        mpi := UMthProc_[mmi];
        Next; { consume method name }
        if (mci >= 0) and UClsIsInterface[mci] then
        begin
          { CORBA interface call `iface.M(args)`: dispatch through the IMT slot.
            Self comes from the fat pointer's instance word at call time. }
          mcallNode := AllocNode(AN_INTF_CALL);
          ASTRight[mcallNode] := node;                 { the interface value }
          ASTIVal[mcallNode] := mpi;                   { signature proc (marshalling) }
          ASTSOffset[mcallNode] := UMthVirSlot[mmi];   { IMT slot }
          ASTTk[mcallNode] := Ord(Procs[mpi].RetType);
          mlastArg := -1;
          if CurTok.Kind = tkLParen then
          begin
            Next;
            mai := 1; { param 0 = Self (provided by the fat pointer) }
            while mai <= Procs[mpi].ParamCount-1 do
            begin
              if Procs[mpi].Params[mai].IsRef or Procs[mpi].Params[mai].IsArray then
              begin
                if ByRefArgStartsExpression then
                begin
                  { non-ident by-ref/array arg (@obj.Method to a method-pointer
                    param, [..] literals, casts): parse as an expression }
                  ParseExpr; mexprNode := CurASTNode;
                end
                else
                begin
                  margIdx := FindSym(CurTok.SVal); Next;
                  mexprNode := ParseLValueAST(margIdx, TokPos - 2);
                end;
              end
              else begin ParseExpr; mexprNode := CurASTNode; end;
              margSeq := AllocNode(AN_ARG); ASTLeft[margSeq] := mexprNode;
              if mlastArg = -1 then ASTLeft[mcallNode] := margSeq
              else ASTRight[mlastArg] := margSeq;
              mlastArg := margSeq;
              if (mai < Procs[mpi].ParamCount-1) and CanFillDefaultsFrom(mpi, mai+1) then
              begin
                FillDefaultArgs(mpi, mai+1, mcallNode, mlastArg);
                mai := Procs[mpi].ParamCount-1;
              end
              else if mai < Procs[mpi].ParamCount-1 then Expect(tkComma, ',');
              Inc(mai);
            end;
            Expect(tkRParen, ')');
          end;
          node := mcallNode;
          Result := node; Exit;
        end;
        if UMthIsStatic[mmi] then
        begin
          mcallNode := AllocNode(AN_CALL);
          ASTIVal[mcallNode] := mpi;
          ASTTk[mcallNode] := Ord(Procs[mpi].RetType);
          mlastArg := -1;
          if CurTok.Kind = tkLParen then
          begin
            Next;
            mai := 0;
            while mai <= Procs[mpi].ParamCount-1 do
            begin
              if Procs[mpi].Params[mai].IsRef or Procs[mpi].Params[mai].IsArray then
              begin
                if ByRefArgStartsExpression then
                begin
                  { non-ident by-ref/array arg (@obj.Method to a method-pointer
                    param, [..] literals, casts): parse as an expression }
                  ParseExpr; mexprNode := CurASTNode;
                end
                else
                begin
                  margIdx := FindSym(CurTok.SVal); Next;
                  mexprNode := ParseLValueAST(margIdx, TokPos - 2);
                end;
              end
              else
              begin
                ParseExpr; mexprNode := CurASTNode;
              end;
              margSeq := AllocNode(AN_ARG); ASTLeft[margSeq] := mexprNode;
              if mlastArg = -1 then
                ASTLeft[mcallNode] := margSeq
              else
                ASTRight[mlastArg] := margSeq;
              mlastArg := margSeq;
              if (mai < Procs[mpi].ParamCount-1) and CanFillDefaultsFrom(mpi, mai+1) then
              begin
                FillDefaultArgs(mpi, mai+1, mcallNode, mlastArg);
                mai := Procs[mpi].ParamCount-1;
              end
              else if mai < Procs[mpi].ParamCount-1 then Expect(tkComma, ',');
              Inc(mai);
            end;
            Expect(tkRParen, ')');
          end;
          node := mcallNode;
          tk := Procs[mpi].RetType;
          Continue;
        end
        else
        begin
          if mmi >= 0 then
          begin
            if UMthVirSlot[mmi] >= 0 then
            begin
              mcallNode := AllocNode(AN_VIRTUAL_CALL);
              ASTRight[mcallNode] := UMthVirSlot[mmi];
            end
            else
              mcallNode := AllocNode(AN_CALL);
          end
          else
            mcallNode := AllocNode(AN_CALL);
          ASTIVal[mcallNode] := mpi;
          ASTTk[mcallNode] := Ord(Procs[mpi].RetType);
          mselfArg := AllocNode(AN_ARG);
          ASTLeft[mselfArg] := node;
          ASTLeft[mcallNode] := mselfArg;
          mlastArg := mselfArg;
          if CurTok.Kind = tkLParen then
          begin
            Next;
            mai := 1;
            while mai <= Procs[mpi].ParamCount-1 do
            begin
              if Procs[mpi].Params[mai].IsRef or Procs[mpi].Params[mai].IsArray then
              begin
                if ByRefArgStartsExpression then
                begin
                  { non-ident by-ref/array arg (@obj.Method to a method-pointer
                    param, [..] literals, casts): parse as an expression }
                  ParseExpr; mexprNode := CurASTNode;
                end
                else
                begin
                  margIdx := FindSym(CurTok.SVal); Next;
                  mexprNode := ParseLValueAST(margIdx, TokPos - 2);
                end;
              end
              else
              begin
                ParseExpr; mexprNode := CurASTNode;
              end;
              margSeq := AllocNode(AN_ARG); ASTLeft[margSeq] := mexprNode;
              ASTRight[mlastArg] := margSeq; mlastArg := margSeq;
              if (mai < Procs[mpi].ParamCount-1) and CanFillDefaultsFrom(mpi, mai+1) then
              begin
                FillDefaultArgs(mpi, mai+1, mcallNode, mlastArg);
                mai := Procs[mpi].ParamCount-1;
              end
              else if mai < Procs[mpi].ParamCount-1 then Expect(tkComma, ',');
              Inc(mai);
            end;
            Expect(tkRParen, ')');
          end;
          { Continue the selector loop (not Exit) so trailing `.field` / `[i]` on
            the method result are parsed: obj.M(args).field, obj.M.field, chained
            obj.M1.M2. The result's record (ProcRetRecId) drives field
            resolution; IR lowering materializes a record result temp. }
          node := mcallNode;
          tk := Procs[mpi].RetType;
          recName := ProcRetRecId[mpi];
          Continue;
        end;
      end;
      { class variable accessed via an instance (obj.cnt): not an instance field —
        resolve to the shared backing global, so reads/writes hit the class var
        (FPC: a class var is reachable from instances too). }
      if (recName >= REC_UCLASS_BASE) and
         (FindUField(recName - REC_UCLASS_BASE, fieldName) < 0) then
      begin
        fldIdx := FindClassVar(recName - REC_UCLASS_BASE, fieldName);
        if fldIdx >= 0 then
        begin
          node := AllocNode(AN_IDENT);
          ASTIVal[node] := fldIdx;
          ASTTk[node] := Ord(Syms[fldIdx].TypeKind);
          tk := Syms[fldIdx].TypeKind;
          recName := REC_NONE;
          Next;   { consume field name }
          Continue;
        end;
      end;
      fieldNode := AllocNode(AN_FIELD);
      ASTLeft[fieldNode] := node;
      ASTSOffset[fieldNode] := propFOff;
      ASTSLen[fieldNode] := propFLen;
      baseRecFld := recName;
      tk := RecFieldType(recName, fieldName);
      recName := RecFieldRecId(recName, fieldName);
      ASTTk[fieldNode] := Ord(tk);
      Next;
      node := fieldNode;

      { Indirect call through a procedural-type field: `rec.field(args)`. The
        field value is the proc pointer (tyPointer) or a {Code,Data} method
        pointer (tyRecord); AN_CALL_IND evaluates ASTRight (the field node) as
        the callee. Without this the statement parser sees a non-call lvalue and
        demands ':='. }
      fldSigPi := -1;
      if (baseRecFld >= REC_UCLASS_BASE) and (CurTok.Kind = tkLParen) and
         ((tk = tyPointer) or (tk = tyRecord)) then
      begin
        fIdx := FindUField(baseRecFld - REC_UCLASS_BASE, fieldName);
        if (fIdx >= 0) and (not UFldIsArray[fIdx]) then fldSigPi := UFldProcSig[fIdx];
      end;
      if fldSigPi >= 0 then
      begin
        isMethodPtr := (tk = tyRecord);
        Expect(tkLParen, '(');
        argsHead2 := -1; lastArg2 := -1;
        while CurTok.Kind <> tkRParen do
        begin
          ParseExpr;
          argSeq2 := AllocNode(AN_ARG);
          ASTLeft[argSeq2] := CurASTNode;
          if argsHead2 = -1 then argsHead2 := argSeq2
          else ASTRight[lastArg2] := argSeq2;
          lastArg2 := argSeq2;
          if CurTok.Kind = tkComma then Next
          else if CurTok.Kind <> tkRParen then Error('expected comma or close parenthesis');
        end;
        Expect(tkRParen, ')');
        callIndNode := AllocNode(AN_CALL_IND);
        ASTLeft[callIndNode]  := argsHead2;
        ASTRight[callIndNode] := fieldNode;
        ASTIVal[callIndNode]  := fldSigPi;
        ASTTk[callIndNode]    := Ord(Procs[fldSigPi].RetType);
        if isMethodPtr then ASTSLen[callIndNode] := 1 else ASTSLen[callIndNode] := 0;
        node := callIndNode;
        tk := Procs[fldSigPi].RetType;
        recName := ProcRetRecId[fldSigPi];
      end;
    end;
  end;
  Result := node;
end;

function BuildMetaclassNew(crefNode, ci, mmi: Integer): Integer;
{ Build an AN_METACLASS_NEW for `<cref>.Create(args)` — metaclass-dispatched
  construction (allocate the dynamic class the ref points at, run its virtual
  ctor; see the IR lowering). On entry the `.Create` token pair has already been
  consumed; CurTok is at `(` or the following token. `crefNode` yields the
  classref (RTTI blob ptr), `ci` is the static base class, `mmi` its `create`
  UMeth. Shared by the metaclass-var path (ParseLValueAST) and the inline
  metaclass-cast path `TFooClass(expr).Create` (ParseFactor). }
var mpi, mcallNode, mlastArg, margSeq, margIdx, mexprNode, mai: Integer;
begin
  mpi := UMthProc_[mmi];
  mcallNode := AllocNode(AN_METACLASS_NEW);
  ASTRight[mcallNode]   := crefNode;             { classref value }
  ASTIVal[mcallNode]    := mpi;                  { ctor proc idx }
  ASTSOffset[mcallNode] := UMthVirSlot[mmi];     { vmt slot, -1 if non-virtual }
  ASTSLen[mcallNode]    := REC_UCLASS_BASE + ci; { result record id }
  ASTTk[mcallNode]      := Ord(tyClass);
  mlastArg := -1;
  if CurTok.Kind = tkLParen then
  begin
    Next;
    mai := 1; { param 0 = Self (the allocated instance) }
    while mai <= Procs[mpi].ParamCount-1 do
    begin
      if Procs[mpi].Params[mai].IsRef or Procs[mpi].Params[mai].IsArray then
      begin
        if (CurTok.Kind = tkLBrack) and Procs[mpi].Params[mai].IsArray then
          { `[e0, e1, ...]` open-array/array-of-const literal argument
            (Exception.CreateFmt(Msg, [Data]) shape) }
          mexprNode := ParseVarRecLiteralAST
        else if ByRefArgStartsExpression then
        begin
          { non-ident / cast-lvalue by-ref arg (PChar(s)^): full expression }
          ParseExpr; mexprNode := CurASTNode;
        end
        else
        begin
          if CurTok.Kind <> tkIdent then Error('expected variable');
          margIdx := FindSym(CurTok.SVal); Next;
          mexprNode := ParseLValueAST(margIdx, TokPos - 2);
        end;
      end
      else
      begin
        ParseExpr; mexprNode := CurASTNode;
      end;
      margSeq := AllocNode(AN_ARG); ASTLeft[margSeq] := mexprNode;
      if mlastArg = -1 then ASTLeft[mcallNode] := margSeq
      else ASTRight[mlastArg] := margSeq;
      mlastArg := margSeq;
      if (mai < Procs[mpi].ParamCount-1) and CanFillDefaultsFrom(mpi, mai+1) then
      begin
        FillDefaultArgs(mpi, mai+1, mcallNode, mlastArg);
        mai := Procs[mpi].ParamCount-1;
      end
      else if mai < Procs[mpi].ParamCount-1 then Expect(tkComma, ',');
      Inc(mai);
    end;
    Expect(tkRParen, ')');
  end;
  Result := mcallNode;
end;

function ParseSetMembershipAST(leftExpr: Integer): Integer;
var node, argNode, lastArg, loVal, hiVal, itemNode: Integer; done: Boolean;
begin
  node := AllocNode(AN_CALL);
  ASTIVal[node] := -SPECIAL_IN;

  argNode := AllocNode(AN_ARG);
  ASTLeft[argNode] := leftExpr;
  ASTLeft[node] := argNode;
  lastArg := argNode;

  Expect(tkLBrack, '[');
  if CurTok.Kind <> tkRBrack then
  begin
    done := False;
    while not done do
    begin
      loVal := ParseSetConst;
      if Eat(tkDotDot) then
      begin
        hiVal := ParseSetConst;
        itemNode := AllocNode(AN_PAIR);
        ASTLeft[itemNode] := AllocNode(AN_INT_LIT);
        ASTIVal[ASTLeft[itemNode]] := loVal;
        ASTRight[itemNode] := AllocNode(AN_INT_LIT);
        ASTIVal[ASTRight[itemNode]] := hiVal;
      end
      else
      begin
        itemNode := AllocNode(AN_INT_LIT);
        ASTIVal[itemNode] := loVal;
      end;

      argNode := AllocNode(AN_ARG);
      ASTLeft[argNode] := itemNode;
      ASTRight[lastArg] := argNode;
      lastArg := argNode;

      if not Eat(tkComma) then done := True;
    end;
  end;
  Expect(tkRBrack, ']');
  Result := node;
end;

function ParseSetElementAST: Integer;
{ One set-literal element. A compile-time constant (integer / 1-char string /
  const identifier — exactly what ParseSetConst accepts) folds to an AN_INT_LIT
  so an all-constant literal keeps the baked-blob fast path (byte-identical).
  Anything else (a variable, a computed expression) is parsed as a full
  expression for a runtime element; the lowering then builds the set at runtime
  with Include/range loops. }
var n, sci: Integer;
begin
  if CurTok.Kind = tkInteger then
  begin
    n := AllocNode(AN_INT_LIT); ASTIVal[n] := CurTok.IVal; ASTTk[n] := Ord(tyInteger); Next;
    Result := n;
  end
  else if CurTok.Kind = tkString then
  begin
    if Length(CurTok.SVal) <> 1 then Error('set item must be one character');
    n := AllocNode(AN_INT_LIT); ASTIVal[n] := Ord(CurTok.SVal[1]); ASTTk[n] := Ord(tyChar); Next;
    Result := n;
  end
  else if (CurTok.Kind = tkIdent) and (FindSym(CurTok.SVal) >= 0) and
          (Syms[FindSym(CurTok.SVal)].Kind = skConst) then
  begin
    sci := FindSym(CurTok.SVal);
    n := AllocNode(AN_INT_LIT); ASTIVal[n] := Syms[sci].ConstVal; ASTTk[n] := Ord(Syms[sci].TypeKind); Next;
    Result := n;
  end
  else
  begin
    { Runtime element: a variable or an arbitrary expression. }
    ParseExpr;
    Result := CurASTNode;
  end;
end;

function ParseSetLiteralAST: Integer;
var node, argNode, lastArg, itemNode: Integer; done: Boolean;
begin
  node := AllocNode(AN_SET_LIT);
  ASTTk[node] := Ord(tySet);
  ASTLeft[node] := -1;
  lastArg := -1;

  Expect(tkLBrack, '[');
  if CurTok.Kind <> tkRBrack then
  begin
    done := False;
    while not done do
    begin
      itemNode := ParseSetElementAST;
      if Eat(tkDotDot) then
      begin
        { Range lo..hi. Either bound may be constant or runtime. }
        argNode := AllocNode(AN_PAIR);
        ASTLeft[argNode] := itemNode;
        ASTRight[argNode] := ParseSetElementAST;
        itemNode := argNode;
      end;

      argNode := AllocNode(AN_ARG);
      ASTLeft[argNode] := itemNode;
      ASTRight[argNode] := -1;

      if lastArg = -1 then
        ASTLeft[node] := argNode
      else
        ASTRight[lastArg] := argNode;
      lastArg := argNode;

      if not Eat(tkComma) then done := True;
    end;
  end;
  Expect(tkRBrack, ']');
  Result := node;
end;

function ParseVarRecLiteralAST: Integer;
{ `[ e0, e1, ... ]` in an `array of const` argument position. Each element is a
  full expression; the element's static type picks its TVarRec tag at lowering
  time. Yields an AN_VARREC_ARRAY whose Left is the AN_ARG element chain; tagged
  tyRecord so overload matching sees it as the open-array-of-record argument. }
var node, argNode, lastArg: Integer; done: Boolean;
begin
  node := AllocNode(AN_VARREC_ARRAY);
  ASTTk[node]   := Ord(tyRecord);
  ASTIVal[node] := TVarRecId;
  ASTLeft[node] := -1;
  lastArg := -1;
  Expect(tkLBrack, '[');
  if CurTok.Kind <> tkRBrack then
  begin
    done := False;
    while not done do
    begin
      ParseExpr;
      argNode := AllocNode(AN_ARG);
      ASTLeft[argNode] := CurASTNode;
      ASTRight[argNode] := -1;
      if lastArg = -1 then ASTLeft[node] := argNode
      else ASTRight[lastArg] := argNode;
      lastArg := argNode;
      if not Eat(tkComma) then done := True;
    end;
  end;
  Expect(tkRBrack, ']');
  Result := node;
end;

function ParamIsVarRecArray(procIdx, argNo: Integer): Boolean;
{ True when proc procIdx's parameter argNo is an `array of const` (open array whose
  element record is TVarRec) — the signal to parse a `[...]` argument as a
  TVarRec element vector rather than a set literal. }
begin
  { Use the durable Proc/Param signature, not the param's frame symbol — that
    symbol slot is reused once the callee's scope closes, so by the time a later
    routine's call is parsed it no longer holds the param. An open array whose
    element type is a record is, in this dialect, only ever `array of const`. }
  Result := (procIdx >= 0) and (TVarRecId <> REC_NONE) and
            (argNo >= 0) and (argNo < Procs[procIdx].ParamCount) and
            Procs[procIdx].Params[argNo].IsArray and
            (Procs[procIdx].Params[argNo].TypeKind = tyRecord);
end;

function ParamIsOpenArrayScalar(procIdx, argNo: Integer): Boolean;
{ True when param argNo is an `array of T` whose element is scalar/string (not
  `array of const` = tyRecord) — the signal to parse a `[...]` argument as an
  array constructor (temp dyn-array) rather than a set literal. }
begin
  Result := (procIdx >= 0) and (argNo >= 0) and
            (argNo < Procs[procIdx].ParamCount) and
            Procs[procIdx].Params[argNo].IsArray and
            (Procs[procIdx].Params[argNo].TypeKind <> tyRecord) and
            (Procs[procIdx].Params[argNo].TypeKind <> tyVariant);
end;

function ParseArrayCtorAST(elemTk: TTypeKind): Integer;
{ `[ e0, e1, ... ]` for an `array of T` (scalar/string) parameter. Builds an
  AN_ARRAY_CTOR whose Left is the element AN_ARG chain; ASTIVal/ASTTk carry the
  element type so overload matching binds it to the open-array param (whose
  TypeKind is the element type). Lowering builds a heap dyn-array temp. }
var node, argNode, lastArg: Integer; done: Boolean;
begin
  node := AllocNode(AN_ARRAY_CTOR);
  ASTIVal[node] := Ord(elemTk);
  ASTTk[node]   := Ord(elemTk);
  ASTLeft[node] := -1;
  lastArg := -1;
  Expect(tkLBrack, '[');
  if CurTok.Kind <> tkRBrack then
  begin
    done := False;
    while not done do
    begin
      ParseExpr;
      argNode := AllocNode(AN_ARG);
      ASTLeft[argNode] := CurASTNode;
      ASTRight[argNode] := -1;
      if lastArg = -1 then ASTLeft[node] := argNode
      else ASTRight[lastArg] := argNode;
      lastArg := argNode;
      if not Eat(tkComma) then done := True;
    end;
  end;
  Expect(tkRBrack, ']');
  Result := node;
end;

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
    if Syms[idx].TypeKind = tyClass then
    begin
      { Global class pointer: load value from BSS variable }
      EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset);
    end
    else
    begin
      EmitB($48); EmitB($8D); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset);
    end;
  end
  else
  begin
    { Local variable or parameter base address }
    if (Syms[idx].Kind = skParam) and
       (Syms[idx].IsRef or Syms[idx].IsArray or TypeIsFrozenString(Syms[idx].TypeKind)) then
    begin
      { param slot holds pointer P; address of string/array struct = P }
      EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[idx].Offset); { mov rax, [rbp+off] = P }
    end
    else
    begin
      { Local variable or regular parameter address }
      if Syms[idx].TypeKind = tyClass then
      begin
        { Local class pointer: load the heap address value }
        EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[idx].Offset);
      end
      else
      begin
        EmitB($48); EmitB($8D); EmitB($85); EmitI32(Syms[idx].Offset);
      end;
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
        if curTk = tyString then
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
        end
        else
          elemSize := TypeSize(curTk);

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
      if DebugTrace then writeln('Dot selector: curRec = ', curRec, ', field = ', CurTok.SVal);
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
    if HiddenByDeclOrder(name) then
      Error('undefined variable — it is a global declared later, declare it before use')
    else
      Error('undefined variable');
  end;
  CompileLValueAddressInternal(idx, tk, recName);
end;

procedure ParseLValue(const name: AnsiString);
var
  idx, si, si2, rhsIdx, i: Integer;
  isComplex: Boolean;
  tk, rhsTk: TTypeKind;
  recName, rhsRecName: Integer;
  rhsName: AnsiString;
begin
  if DebugTrace then writeln('Parsing LValue: ', name);
  idx := FindSym(name);
  if idx < 0 then
  begin
    ErrorIdent := name;
    if HiddenByDeclOrder(name) then
      Error('undefined variable — it is a global declared later, declare it before use')
    else
      Error('undefined variable');
  end;

  Next; { consume identifier }
  isComplex := CurTok.Kind in [tkLBrack, tkDot];

  if not isComplex then
  begin
    Expect(tkAssign, ':=');
    if TypeIsFrozenString(Syms[idx].TypeKind) then
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
        if (si2 >= 0) and TypeIsFrozenString(Syms[si2].TypeKind) then
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
              if DebugTrace then writeln('rhsTk: ', Ord(rhsTk));
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
          if DebugTrace then writeln('rhsTk: ', Ord(rhsTk));
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
      i := TypeSize(tk);
      if i = 1 then
        begin EmitB($88); EmitB($01); end
      else if i = 2 then
        begin EmitB($66); EmitB($89); EmitB($01); end
      else if i = 4 then
        begin EmitB($89); EmitB($01); end
      else
        begin EmitB($48); EmitB($89); EmitB($01); end;
    end;
  end;
end;

procedure ParseCallArg(procIdx, argNo: Integer);
var idx: Integer; tk: TTypeKind; recName: Integer;
begin
  if Procs[procIdx].Params[argNo].IsRef or Procs[procIdx].Params[argNo].IsArray then
  begin
    if CurTok.Kind <> tkIdent then Error('by-reference argument must be a variable');
    idx := FindSym(CurTok.SVal);
    if idx < 0 then Error('undefined by-reference argument');
    Next;
    CompileLValueAddressInternal(idx, tk, recName);
  end
  else
    ParseExpr;
  EmitB($50);
end;

function ParseInheritedCallAST: Integer;
var
  ci, parentCi, mmi, mpi, selfIdx, node, selfArg, lastArg, argSeq, argNo: Integer;
  name: AnsiString;
begin
  if (CurSelfClass < REC_UCLASS_BASE) or (CurProc < 0) then
    Error('inherited call outside method');
  ci := CurSelfClass - REC_UCLASS_BASE;
  parentCi := UClsParent[ci];

  Next; { consume inherited }
  if CurTok.Kind = tkIdent then
  begin
    name := CurTok.SVal;
    Next;
  end
  else
    name := LastDotName(Procs[CurProc].Name);

  { inherited Destroy / inherited Create with no ancestor implementation is the
    implicit-root call — FPC's TObject.Destroy/Create are empty — so emit a
    no-op instead of erroring. This makes the universal
    `destructor Destroy; override; ... inherited Destroy;` idiom (and a root
    ctor's `inherited Create`) compile on a direct-root class. Any trailing
    (args) are parsed and discarded (the root method ignores them). See
    bug-tobject-destroy-not-virtual-override. }
  if (FindUMeth(parentCi, name) < 0) and
     (CaseEqual(name, 'Destroy') or CaseEqual(name, 'Create')) then
  begin
    if CurTok.Kind = tkLParen then
    begin
      argNo := 0;
      repeat
        if CurTok.Kind = tkLParen then Inc(argNo)
        else if CurTok.Kind = tkRParen then Dec(argNo);
        Next;
      until (argNo = 0) or (CurTok.Kind = tkEOF);
    end;
    Result := GenMakeSeq(-1, -1);
    Exit;
  end;

  if parentCi < 0 then Error('inherited call has no parent class');
  { overload-aware: `inherited Insert(i)` must pick the parent overload
    matching THIS call's arg count (CurTok = '(' or the follower) }
  mmi := FindUMethArity(parentCi, name, CountCallArgsAhead);
  if mmi < 0 then Error('inherited method not found: ' + name);
  mpi := UMthProc_[mmi];

  node := AllocNode(AN_CALL); { Deliberately static: call the ancestor body. }
  ASTIVal[node] := mpi;
  ASTTk[node] := Ord(Procs[mpi].RetType);
  selfIdx := Procs[CurProc].Params[0].SymIdx;
  selfArg := AllocNode(AN_ARG);
  ASTLeft[selfArg] := AllocNode(AN_IDENT);
  ASTIVal[ASTLeft[selfArg]] := selfIdx;
  ASTTk[ASTLeft[selfArg]] := Ord(tyClass);
  ASTLeft[node] := selfArg;
  lastArg := selfArg;
  argNo := 1;

  if CurTok.Kind = tkLParen then
  begin
    Next;
    while CurTok.Kind <> tkRParen do
    begin
      ParseExpr;
      argSeq := AllocNode(AN_ARG);
      ASTLeft[argSeq] := CurASTNode;
      ASTRight[lastArg] := argSeq;
      lastArg := argSeq;
      Inc(argNo);
      if CurTok.Kind = tkComma then
        Next
      else if CurTok.Kind <> tkRParen then
        Error('expected comma or close parenthesis');
    end;
    Expect(tkRParen, ')');
  end;
  if argNo <> Procs[mpi].ParamCount then
    Error('inherited call argument count mismatch');
  { trailing ^ — T(inherited GetLast^) in fgl: deref the returned (untyped)
    pointer, read as Int64; an outer ordinal cast narrows }
  while CurTok.Kind = tkCaret do
  begin
    Next;
    argSeq := AllocNode(AN_DEREF);
    ASTLeft[argSeq] := node;
    ASTTk[argSeq] := Ord(tyInt64);
    node := argSeq;
  end;
  Result := node;
end;

{ Apply a chain of ^, [i], and .field to a function-call result that is a typed
  pointer, using the callee's recorded return element type (ProcRetPtrElemTk/Rec).
  Lets `f()^`, `f()^.field`, and `f()[i]` resolve without a typed intermediate
  variable. Sets CurASTNode and LastExprTk; consumes nothing when the result is
  not a typed pointer. }
{ Walk `.field` / `[i]` selectors on a class/record VALUE node (e.g. a call or
  method-call result whose record is recId). Returns the final node and the
  final element type in outTk. Method calls on the result and `^` deref are not
  handled (a class result is already the instance). Shared by the function-call
  suffix and the method-call sites so `f(a).x`, `Self.M(a).x`, `obj.M(a).x` all
  resolve their trailing members. }
function ParseClassRecordSelectors(node, recId: Integer; var outTk: TTypeKind): Integer;
var sub, prevTok: Integer; fieldName, accName: AnsiString; tk: TTypeKind;
    ci, mmi, mpi, callN, selfArg, lastA, aSeq, aNode, aIdx, mai: Integer;
    pri, i, w, margIdx: Integer; isAssign: Boolean;
begin
  tk := IntToTypeKind(ASTTk[node]);
  while CurTok.Kind in [tkDot, tkLBrack] do
  begin
    if CurTok.Kind = tkDot then
    begin
      Next;
      if CurTok.Kind in [tkEOF, tkSemicolon, tkAssign, tkRBrack, tkRParen] then
        Error('expected field name after .');
      prevTok := TokPos - 1;
      fieldName := GetTokenStr(prevTok);

      { Method call on the value: `.M(args)` (or 0-arg `.M`). Checked before the
        field path so a method name isn't mistaken for a field. Mirrors the
        instance-method arg parsing (ref/array params taken by lvalue). Self =
        the current node; virtual methods dispatch dynamically on the real object
        (a hard cast doesn't change the dynamic type). }
      ci := -1;
      if recId >= REC_UCLASS_BASE then ci := recId - REC_UCLASS_BASE;

      { Property on the value: TT(c).Prop — resolve to the backing field
        (rename the AN_FIELD to the accessor field) or the getter/setter call,
        mirroring the plain member-access property path (~2200). Previously the
        property name fell through to the field builder unresolved, so
        RecFieldOffset found nothing and read offset 0 — the VMT pointer
        (bug-downcast-inherited-property-wrong-offset). }
      pri := -1;
      if ci >= 0 then pri := FindUProp(ci, fieldName);
      if pri >= 0 then
      begin
        isAssign := (TokPos < TokCount) and (Tokens[TokPos].Kind = tkAssign);
        { Indexed property write: `:=` follows the subscript — peek past the
          bracket group (CurTok = name, TokPos = `[`). }
        if UPropIsIndexed[pri] and (not isAssign) and
           (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLBrack) then
        begin
          i := TokPos; w := 0;
          while i < TokCount do
          begin
            if Tokens[i].Kind = tkLBrack then Inc(w)
            else if Tokens[i].Kind = tkRBrack then
            begin Dec(w); if w = 0 then begin Inc(i); Break; end; end;
            Inc(i);
          end;
          if (i < TokCount) and (Tokens[i].Kind = tkAssign) then isAssign := True;
        end;
        if isAssign then
        begin
          if UPropWriteFLen[pri] > 0 then
          begin
            { field-backed write: rename to the backing field; the caller
              consumes the `:=` and builds the assignment }
            sub := AllocNode(AN_FIELD);
            ASTLeft[sub] := node;
            ASTSOffset[sub] := UPropWriteFOff[pri];
            ASTSLen[sub] := UPropWriteFLen[pri];
            accName := '';
            for i := 0 to UPropWriteFLen[pri] - 1 do
              AppendChar(accName, TokChars[UPropWriteFOff[pri] + i]);
            tk := RecFieldType(recId, accName);
            recId := RecFieldRecId(recId, accName);
            ASTTk[sub] := Ord(tk);
            Next; { consume property name }
            node := sub;
            Continue;
          end
          else if UPropWriteMLen[pri] > 0 then
          begin
            accName := '';
            for i := 0 to UPropWriteMLen[pri] - 1 do
              AppendChar(accName, TokChars[UPropWriteMOff[pri] + i]);
            mmi := FindUMeth(ci, accName);
            if mmi < 0 then Error('setter method not found: ' + accName);
            mpi := UMthProc_[mmi];
            Next; { consume property name }
            margIdx := -1;
            if UPropIsIndexed[pri] then ParsePropIndexArgs(margIdx, lastA);
            Expect(tkAssign, ':=');
            ParseExpr;
            if UMthVirSlot[mmi] >= 0 then
            begin
              callN := AllocNode(AN_VIRTUAL_CALL);
              ASTRight[callN] := UMthVirSlot[mmi];
            end
            else
              callN := AllocNode(AN_CALL);
            ASTIVal[callN] := mpi;
            ASTTk[callN] := Ord(Procs[mpi].RetType);
            selfArg := AllocNode(AN_ARG);
            ASTLeft[selfArg] := node;
            ASTLeft[callN] := selfArg;
            aSeq := AllocNode(AN_ARG);
            ASTLeft[aSeq] := CurASTNode;   { value }
            { Setter args: self [, index...], value }
            if margIdx >= 0 then
            begin
              ASTRight[selfArg] := margIdx;
              ASTRight[lastA] := aSeq;
            end
            else
              ASTRight[selfArg] := aSeq;
            outTk := Procs[mpi].RetType;
            Result := callN;   { a complete call statement; caller uses it as-is }
            Exit;
          end
          else
            Error('property is read-only');
        end
        else
        begin
          if UPropReadFLen[pri] > 0 then
          begin
            sub := AllocNode(AN_FIELD);
            ASTLeft[sub] := node;
            ASTSOffset[sub] := UPropReadFOff[pri];
            ASTSLen[sub] := UPropReadFLen[pri];
            accName := '';
            for i := 0 to UPropReadFLen[pri] - 1 do
              AppendChar(accName, TokChars[UPropReadFOff[pri] + i]);
            tk := RecFieldType(recId, accName);
            recId := RecFieldRecId(recId, accName);
            ASTTk[sub] := Ord(tk);
            Next; { consume property name }
            node := sub;
            Continue;
          end
          else if UPropReadMLen[pri] > 0 then
          begin
            accName := '';
            for i := 0 to UPropReadMLen[pri] - 1 do
              AppendChar(accName, TokChars[UPropReadMOff[pri] + i]);
            mmi := FindUMeth(ci, accName);
            if mmi < 0 then Error('getter method not found: ' + accName);
            mpi := UMthProc_[mmi];
            Next; { consume property name }
            margIdx := -1;
            if UPropIsIndexed[pri] then ParsePropIndexArgs(margIdx, lastA);
            if UMthVirSlot[mmi] >= 0 then
            begin
              callN := AllocNode(AN_VIRTUAL_CALL);
              ASTRight[callN] := UMthVirSlot[mmi];
            end
            else
              callN := AllocNode(AN_CALL);
            ASTIVal[callN] := mpi;
            ASTTk[callN] := Ord(Procs[mpi].RetType);
            selfArg := AllocNode(AN_ARG);
            ASTLeft[selfArg] := node;
            ASTLeft[callN] := selfArg;
            { Getter args: self [, index...] }
            if margIdx >= 0 then ASTRight[selfArg] := margIdx;
            tk := Procs[mpi].RetType;
            if (tk = tyClass) or (tk = tyRecord) then recId := ProcRetRecId[mpi]
            else recId := REC_NONE;
            node := callN;
            Continue;
          end
          else
            Error('property is write-only');
        end;
      end;

      mmi := -1;
      if ci >= 0 then mmi := FindUMethArity(ci, fieldName, CountCallArgsAhead);
      if mmi >= 0 then
      begin
        mpi := UMthProc_[mmi];
        if UMthVirSlot[mmi] >= 0 then
        begin
          callN := AllocNode(AN_VIRTUAL_CALL);
          ASTRight[callN] := UMthVirSlot[mmi];
        end
        else
          callN := AllocNode(AN_CALL);
        ASTIVal[callN] := mpi;
        ASTTk[callN] := Ord(Procs[mpi].RetType);
        selfArg := AllocNode(AN_ARG);
        ASTLeft[selfArg] := node;
        ASTLeft[callN] := selfArg;
        lastA := selfArg;
        Next; { consume method name }
        if CurTok.Kind = tkLParen then
        begin
          Next;
          mai := 1;  { param 0 = Self }
          while mai <= Procs[mpi].ParamCount - 1 do
          begin
            if Procs[mpi].Params[mai].IsRef or Procs[mpi].Params[mai].IsArray then
            begin
              if ByRefArgStartsExpression then
              begin
                { non-ident by-ref/array arg (@obj.Method to a method-pointer
                  param, [..] literals, casts): parse as an expression }
                ParseExpr; aNode := CurASTNode;
              end
              else
              begin
                aIdx := FindSym(CurTok.SVal); Next;
                aNode := ParseLValueAST(aIdx, TokPos - 2);
              end;
            end
            else
            begin
              ParseExpr; aNode := CurASTNode;
            end;
            aSeq := AllocNode(AN_ARG); ASTLeft[aSeq] := aNode;
            ASTRight[lastA] := aSeq; lastA := aSeq;
            if (mai < Procs[mpi].ParamCount-1) and CanFillDefaultsFrom(mpi, mai+1) then
            begin
              FillDefaultArgs(mpi, mai+1, callN, lastA);
              mai := Procs[mpi].ParamCount-1;
            end
            else if mai < Procs[mpi].ParamCount-1 then Expect(tkComma, ',');
            Inc(mai);
          end;
          Expect(tkRParen, ')');
        end;
        tk := Procs[mpi].RetType;
        if (tk = tyClass) or (tk = tyRecord) then recId := ProcRetRecId[mpi]
        else recId := REC_NONE;
        node := callN;
        Continue;
      end;

      sub := AllocNode(AN_FIELD);
      ASTLeft[sub] := node;
      ASTSOffset[sub] := Tokens[prevTok].SOffset;
      ASTSLen[sub] := Tokens[prevTok].SLen;
      tk := RecFieldType(recId, fieldName);
      recId := RecFieldRecId(recId, fieldName);
      ASTTk[sub] := Ord(tk);
      Next;
      node := sub;
    end
    else { tkLBrack — index the array field just selected }
    begin
      Next;
      sub := AllocNode(AN_INDEX);
      ASTLeft[sub] := node;
      ParseExpr;
      ASTRight[sub] := CurASTNode;
      Expect(tkRBrack, ']');
      if (tk = tyString) or (tk = tyAnsiString) then tk := tyChar;
      ASTTk[sub] := Ord(tk);
      node := sub;
    end;
  end;
  outTk := tk;
  Result := node;
end;

procedure ApplyCallResultPtrSuffix(node, procIdx: Integer);
var tk: TTypeKind; elemTk, elemRec, recId, sub, prevTok, tmpN: Integer; fieldName: AnsiString;
begin
  tk := Procs[procIdx].RetType;
  recId := REC_NONE;
  elemTk := ProcRetPtrElemTk[procIdx];
  elemRec := ProcRetPtrElemRec[procIdx];
  if (tk = tyPointer) and (elemTk <> Ord(tyUnknown)) then
  begin
    while CurTok.Kind in [tkCaret, tkDot, tkLBrack] do
    begin
      if CurTok.Kind = tkCaret then
      begin
        Next;
        sub := AllocNode(AN_DEREF);
        ASTLeft[sub] := node;
        tk := IntToTypeKind(elemTk); recId := elemRec;
        ASTTk[sub] := Ord(tk);
        node := sub;
      end
      else if CurTok.Kind = tkLBrack then
      begin
        Next;
        sub := AllocNode(AN_INDEX);
        ASTLeft[sub] := node;
        ParseExpr;
        ASTRight[sub] := CurASTNode;
        Expect(tkRBrack, ']');
        tk := IntToTypeKind(elemTk); recId := elemRec;
        ASTTk[sub] := Ord(tk);
        node := sub;
      end
      else { tkDot — field of the pointed-at record }
      begin
        Next;
        if CurTok.Kind in [tkEOF, tkSemicolon, tkAssign, tkRBrack, tkRParen] then
          Error('expected field name after .');
        prevTok := TokPos - 1;
        fieldName := GetTokenStr(prevTok);
        sub := AllocNode(AN_FIELD);
        ASTLeft[sub] := node;
        ASTSOffset[sub] := Tokens[prevTok].SOffset;
        ASTSLen[sub] := Tokens[prevTok].SLen;
        tk := RecFieldType(recId, fieldName);
        recId := RecFieldRecId(recId, fieldName);
        ASTTk[sub] := Ord(tk);
        Next;
        node := sub;
      end;
    end;
  end
  else if (tk = tyPointer) and (CurTok.Kind = tkCaret) then
  begin
    { Deref of an UNTYPED-pointer-returning call: `f(args)^` — legal where
      only the ADDRESS matters (untyped var/const args: blcksock's
      `Move(..., IncPoint(Buffer, rl)^, l)`). No pointee type, so model the
      deref as a Byte lvalue, same as the Pointer(expr)^ untyped deref. }
    Next;
    sub := AllocNode(AN_DEREF);
    ASTLeft[sub] := node;
    ASTTk[sub] := Ord(tyUInt8);
    node := sub;
    tk := tyUInt8;
  end
  else if (tk = tyAnsiString) and (CurTok.Kind = tkLBrack) then
  begin
    { Index a STRING-returning call: `Uppercase(s)[2]` (ftpsend's permission
      chars). AN_INDEX needs an addressable base, so materialise the result
      into a hidden temp first and yield `(tmp := call, tmp[i])` via AN_COMMA
      (evaluate-left-yield-right). }
    Next;
    prevTok := AllocVar('', tyAnsiString);   { hidden temp (sym idx) }
    tmpN := AllocNode(AN_IDENT);
    ASTIVal[tmpN] := prevTok;
    ASTTk[tmpN] := Ord(tyAnsiString);
    sub := AllocNode(AN_ASSIGN);
    ASTLeft[sub] := tmpN;
    ASTRight[sub] := node;
    node := sub;                             { the side-effect leg }
    tmpN := AllocNode(AN_IDENT);
    ASTIVal[tmpN] := prevTok;
    ASTTk[tmpN] := Ord(tyAnsiString);
    sub := AllocNode(AN_INDEX);
    ASTLeft[sub] := tmpN;
    ParseExpr;
    ASTRight[sub] := CurASTNode;
    Expect(tkRBrack, ']');
    ASTTk[sub] := Ord(tyChar);
    prevTok := AllocNode(AN_COMMA);
    ASTLeft[prevTok] := node;
    ASTRight[prevTok] := sub;
    ASTTk[prevTok] := Ord(tyChar);
    node := prevTok;
    tk := tyChar;
  end
  else if ((tk = tyClass) or (tk = tyRecord)) and (CurTok.Kind in [tkDot, tkLBrack]) then
    { Member access on a class/record-returning call result: f(args).field[…]. }
    node := ParseClassRecordSelectors(node, ProcRetRecId[procIdx], tk);
  CurASTNode := node;
  LastExprTk := tk;
end;

function ParseProcVarCallAST(calleeSym, sigPi: Integer): Integer;
{ Parse an indirect call `v(args)` through a procedural-type variable. CurTok is
  the variable identifier; consume it and the argument list. Builds AN_CALL_IND
  whose callee value (ASTRight) is the proc-var and whose ASTIVal is the signature
  proc index (marshalling + return type). A method-pointer var is a 16-byte
  {Code,Data} record (TypeKind tyRecord): ASTSLen[node]=1 flags it so lowering
  injects Self (Data) and calls Code. }
var node, calleeNode, argsHead, lastArg, argSeq, nArgs: Integer; isMethod: Boolean;
begin
  isMethod := (Syms[calleeSym].TypeKind = tyRecord);
  Next;                                  { consume the variable name }
  calleeNode := AllocNode(AN_IDENT);
  ASTIVal[calleeNode] := calleeSym;
  if isMethod then ASTTk[calleeNode] := Ord(tyRecord)
  else ASTTk[calleeNode] := Ord(tyPointer);
  Expect(tkLParen, '(');
  argsHead := -1; lastArg := -1; nArgs := 0;
  while CurTok.Kind <> tkRParen do
  begin
    ParseExpr;
    argSeq := AllocNode(AN_ARG);
    ASTLeft[argSeq] := CurASTNode;
    if argsHead = -1 then argsHead := argSeq
    else ASTRight[lastArg] := argSeq;
    lastArg := argSeq;
    Inc(nArgs);
    if CurTok.Kind = tkComma then Next
    else if CurTok.Kind <> tkRParen then Error('expected comma or close parenthesis');
  end;
  Expect(tkRParen, ')');
  if nArgs <> Procs[sigPi].ParamCount then
    Error('procedural call: wrong number of arguments');
  node := AllocNode(AN_CALL_IND);
  ASTLeft[node]  := argsHead;
  ASTRight[node] := calleeNode;
  ASTIVal[node]  := sigPi;
  ASTTk[node]    := Ord(Procs[sigPi].RetType);
  if isMethod then ASTSLen[node] := 1 else ASTSLen[node] := 0;
  Result := node;
end;

{ {$mode delphi} bare proc-value as a call argument: an identifier naming a
  routine (not a variable) that CANNOT be a value-producing call in this position
  -- a procedure, or a function that takes parameters -- standing alone as the
  whole argument (the next token closes/separates it) is that routine's address
  (@-optional). Paramless functions are deliberately NOT taken here: they parse
  as a call (call-first precedence) and only fall back to @F via
  MatchCallDelphiProcAddr. Returns an AN_PROCADDR node and consumes the name, or
  -1 with nothing consumed. }
function TryDelphiBareProcArg: Integer;
var pi, node: Integer;
begin
  Result := -1;
  if not DelphiMode then Exit;
  if CurTok.Kind <> tkIdent then Exit;
  if not (Tokens[TokPos].Kind in [tkComma, tkRParen]) then Exit;
  if FindSym(CurTok.SVal) >= 0 then Exit;
  pi := FindProc(CurTok.SVal);
  if pi < 0 then Exit;
  if Procs[pi].IsFunc and (Procs[pi].ParamCount = 0) then Exit;
  node := AllocNode(AN_PROCADDR);
  ASTIVal[node] := pi;
  ASTTk[node] := Ord(tyPointer);
  LastExprTk := tyPointer;
  Next;
  Result := node;
end;

{ {$mode delphi} call-arg @-relax. A bare paramless function name passed as a
  call argument first parses as a CALL (call-first precedence: a paramless
  function used as a value is called). When no overload accepts the resulting
  call-result types, retry the overload match with each such argument retyped as
  a procedural VALUE (its address, tyPointer) — the Delphi @-optional fallback.
  On a successful retry, rewrite the matched proc-typed / Pointer arguments in
  place to AN_PROCADDR (their ASTIVal already holds the callee proc index).
  Returns the resolved procIdx, or -1. Outside delphi mode (or with no candidate
  args) this is exactly the plain MatchProcCall[InUnit]. }
{ Wrap a PChar argument node in a `PCharToString(node)` call so a PChar binds a
  string/AnsiString parameter (FPC's implicit conversion). The helper lives in the
  builtin unit, auto-pulled when a PChar is in scope (see ParseProgram token scan). }
function WrapPCharToString(argNode: Integer): Integer;
var procIdx, wArg, wCall: Integer;
begin
  procIdx := FindProc('PCharToString');
  if procIdx < 0 then Error('PChar->string conversion: PCharToString helper not loaded');
  wArg := AllocNode(AN_ARG);
  ASTLeft[wArg] := argNode; ASTRight[wArg] := -1; ASTTk[wArg] := Ord(tyPointer);
  wCall := AllocNode(AN_CALL);
  ASTIVal[wCall] := procIdx;
  ASTTk[wCall] := Ord(Procs[procIdx].RetType);
  ASTLeft[wCall] := wArg; ASTRight[wCall] := -1;
  Result := wCall;
end;

{ Metaclass descendant enforcement. When the assignment target is a `class of
  TBase` variable (a tyPointer sym whose element is tyClass with a user-class
  rec id), the assigned value must be TBase or a descendant. Two RHS shapes
  carry a statically known class: a bare class name (AN_CLASSREF, ASTIVal =
  class id) and another metaclass variable (its own declared base id). Any
  other pointer expression (nil, casts, untyped pointers) stays unchecked —
  there is deliberately no general class-pointer assignment check today, this
  gates only the metaclass form. }
procedure CheckMetaclassAssign(lhsSym, rhsNode: Integer);
var baseCi, rhsCi, rhsSym, i: Integer; lhsName, rhsName: AnsiString;
begin
  if (lhsSym < 0) or (rhsNode < 0) then Exit;
  if (Syms[lhsSym].TypeKind <> tyPointer) or (Syms[lhsSym].PtrElemTk <> tyClass) or
     (Syms[lhsSym].PtrElemRec < REC_UCLASS_BASE) then Exit;
  baseCi := Syms[lhsSym].PtrElemRec - REC_UCLASS_BASE;
  rhsCi := -1;
  if ASTKind[rhsNode] = AN_CLASSREF then
    rhsCi := ASTIVal[rhsNode]
  else if (ASTKind[rhsNode] = AN_IDENT) and (ASTIVal[rhsNode] >= 0) then
  begin
    rhsSym := ASTIVal[rhsNode];
    if (Syms[rhsSym].TypeKind = tyPointer) and (Syms[rhsSym].PtrElemTk = tyClass) and
       (Syms[rhsSym].PtrElemRec >= REC_UCLASS_BASE) then
      rhsCi := Syms[rhsSym].PtrElemRec - REC_UCLASS_BASE;
  end;
  if rhsCi < 0 then Exit;
  if (rhsCi = baseCi) or IsSubclassOf(rhsCi, baseCi) then Exit;
  lhsName := ''; rhsName := '';
  for i := UClsNOff[baseCi] to UClsNOff[baseCi] + UClsNLen[baseCi] - 1 do
    AppendChar(lhsName, TokChars[i]);
  for i := UClsNOff[rhsCi] to UClsNOff[rhsCi] + UClsNLen[rhsCi] - 1 do
    AppendChar(rhsName, TokChars[i]);
  Error('metaclass type mismatch: ' + rhsName + ' is not ' + lhsName +
        ' or a descendant');
end;

{ flexcolumn call tail. After a value argument to a routine declared with the
  `flexcolumn` directive, an optional write-style `:width[:decimals]` may
  follow. Each value argument expands to THREE actuals — value, width,
  decimals — with defaults 0 and -1 when a modifier is absent (write's
  defaults), so the callee declares (v; w, d) triples and arity/type checks
  run on the expanded list. Width/decimals are full expressions, not just
  literals. Appends the two extra AN_ARG nodes to the open argument list. }
procedure ParseFlexColumnTail(var lastArg, nArgs: Integer);
var wNode, dNode, aSeq: Integer;
begin
  if CurTok.Kind = tkColon then
  begin
    Next;
    ParseExpr; wNode := CurASTNode;
  end
  else
  begin
    wNode := AllocNode(AN_INT_LIT); ASTIVal[wNode] := 0; ASTTk[wNode] := Ord(tyInt64);
  end;
  if CurTok.Kind = tkColon then
  begin
    Next;
    ParseExpr; dNode := CurASTNode;
  end
  else
  begin
    dNode := AllocNode(AN_INT_LIT); ASTIVal[dNode] := -1; ASTTk[dNode] := Ord(tyInt64);
  end;
  aSeq := AllocNode(AN_ARG); ASTLeft[aSeq] := wNode;
  ASTRight[lastArg] := aSeq; lastArg := aSeq; Inc(nArgs);
  aSeq := AllocNode(AN_ARG); ASTLeft[aSeq] := dNode;
  ASTRight[lastArg] := aSeq; lastArg := aSeq; Inc(nArgs);
end;

function MatchCallDelphiProcAddr(const name: AnsiString; qUnit, nArgs, argsHead: Integer;
  const argTypes: array of TTypeKind): Integer;
var i, currArg, exprNode, pi, sidx, node, match0: Integer;
    procCand: array[0..MAX_PROC_PARAMS-1] of Boolean; retryTypes: array[0..MAX_PROC_PARAMS-1] of TTypeKind;
    hasCand, needAddr, pcharRetry, hasPChar: Boolean;
begin
  hasCand := False;
  if DelphiMode then
  begin
    currArg := argsHead;
    for i := 0 to nArgs-1 do
    begin
      exprNode := ASTLeft[currArg];
      procCand[i] := (ASTKind[exprNode] = AN_CALL) and (ASTLeft[exprNode] = -1) and
                     (ASTIVal[exprNode] >= 0) and
                     (Procs[ASTIVal[exprNode]].ParamCount = 0);
      if procCand[i] then hasCand := True;
      currArg := ASTRight[currArg];
    end;
  end;

  { A PChar argument may need the PChar->string coercion retry below, whose
    initial match legitimately fails — quiet the mismatch diagnostic for it. }
  hasPChar := False;
  currArg := argsHead;
  for i := 0 to nArgs-1 do
  begin
    if IsNodePChar(ASTLeft[currArg]) then hasPChar := True;
    currArg := ASTRight[currArg];
  end;

  { Record identity of each argument, for rec-aware overload phases
    (bug-overload-resolution-record-identity). This function is the single
    entry into MatchProcCall*, so refilling here keeps the side channel fresh;
    it stays valid across the retry matches below (same argument list). }
  currArg := argsHead;
  for i := 0 to nArgs-1 do
  begin
    if i < MAX_PROC_PARAMS then
    begin
      if argTypes[i] = tyRecord then MatchArgRec[i] := ResolveNodeRec(ASTLeft[currArg])
      else MatchArgRec[i] := REC_NONE;
    end;
    currArg := ASTRight[currArg];
  end;
  MatchArgRecValid := True;

  MatchQuiet := hasCand or hasPChar;   { the call-first / pchar probe must not print mismatch diag }
  if qUnit >= 0 then match0 := MatchProcCallInUnit(name, qUnit, nArgs, argTypes)
  else match0 := MatchProcCall(name, nArgs, argTypes);
  MatchQuiet := False;
  Result := match0;

  { PChar -> string implicit conversion in a call argument (FPC parity): when no
    overload matches as-is, retry treating each PChar argument as an AnsiString.
    If that matches, wrap every PChar arg whose matched parameter is a string in
    PCharToString. Runs only on a failed match so it never overrides a stricter
    one; e.g. dynlibs.LoadLibrary(PChar) into a `string` param. }
  if Result < 0 then
  begin
    pcharRetry := False;
    currArg := argsHead;
    for i := 0 to nArgs-1 do
    begin
      if IsNodePChar(ASTLeft[currArg]) then
        begin retryTypes[i] := tyAnsiString; pcharRetry := True; end
      else
        retryTypes[i] := argTypes[i];
      currArg := ASTRight[currArg];
    end;
    if pcharRetry then
    begin
      if qUnit >= 0 then pi := MatchProcCallInUnit(name, qUnit, nArgs, retryTypes)
      else pi := MatchProcCall(name, nArgs, retryTypes);
      if pi >= 0 then
      begin
        currArg := argsHead;
        for i := 0 to nArgs-1 do
        begin
          exprNode := ASTLeft[currArg];
          if IsNodePChar(exprNode) and
             ((Procs[pi].Params[i].TypeKind = tyString) or
              (Procs[pi].Params[i].TypeKind = tyAnsiString)) then
            ASTLeft[currArg] := WrapPCharToString(exprNode);
          currArg := ASTRight[currArg];
        end;
        Result := pi;
        Exit;
      end;
    end;
  end;

  if not hasCand then Exit;

  { Call-first precedence: keep the plain call when it matched, UNLESS a bare
    paramless-function candidate landed on a procedural parameter -- a function
    RESULT is never a procedural value, so that match is spurious (PXX treats a
    proc-typed param as a pointer, which a numeric result compatibility-matches).
    In that case the bare name must be the routine's address instead. }
  needAddr := match0 < 0;
  if match0 >= 0 then
    for i := 0 to nArgs-1 do
    begin
      sidx := Procs[match0].Params[i].SymIdx;
      if procCand[i] and (sidx >= 0) and (SymProcSig[sidx] >= 0) then needAddr := True;
    end;
  if not needAddr then Exit;

  for i := 0 to nArgs-1 do
    if procCand[i] then retryTypes[i] := tyPointer else retryTypes[i] := argTypes[i];
  if qUnit >= 0 then pi := MatchProcCallInUnit(name, qUnit, nArgs, retryTypes)
  else pi := MatchProcCall(name, nArgs, retryTypes);
  if pi < 0 then Exit;   { retry failed -> leave the original result (genuine type error) }
  Result := pi;

  currArg := argsHead;
  for i := 0 to nArgs-1 do
  begin
    exprNode := ASTLeft[currArg];
    sidx := Procs[pi].Params[i].SymIdx;
    if procCand[i] and
       ((Procs[pi].Params[i].TypeKind = tyPointer) or
        ((sidx >= 0) and (SymProcSig[sidx] >= 0))) then
    begin
      { Replace the call node with a fresh AN_PROCADDR (a clean node, like the
        explicit `@F` path) rather than retagging the AN_CALL in place -- the
        call node carries other AST fields that AN_PROCADDR codegen would
        misread. The callee proc index is the call node's ASTIVal. }
      node := AllocNode(AN_PROCADDR);
      ASTIVal[node] := ASTIVal[exprNode];
      ASTTk[node] := Ord(tyPointer);
      ASTLeft[currArg] := node;
    end;
    currArg := ASTRight[currArg];
  end;
end;

{ Compile-time low/high bound of a built-in ordinal type. Returns False for a
  non-ordinal (float/string/record/etc). Ranges match FPC. UInt64/NativeInt high
  overflows signed Int64 storage, so it is left unsupported (returns False). }
function OrdinalTypeBound(tk: TTypeKind; wantHigh: Boolean; var v: Int64): Boolean;
begin
  Result := True;
  case tk of
    tyUInt8:   if wantHigh then v := 255 else v := 0;
    tyInt8:    if wantHigh then v := 127 else v := -128;
    tyUInt16:  if wantHigh then v := 65535 else v := 0;
    tyInt16:   if wantHigh then v := 32767 else v := -32768;
    tyUInt32:  if wantHigh then v := 4294967295 else v := 0;
    tyInt32:   if wantHigh then v := 2147483647 else v := -2147483647 - 1;
    tyInteger: if wantHigh then v := 2147483647 else v := -2147483647 - 1;
    tyInt64:   if wantHigh then v := 9223372036854775807 else v := -9223372036854775807 - 1;
    tyBoolean: if wantHigh then v := 1 else v := 0;
    tyChar:    if wantHigh then v := 255 else v := 0;
  else
    Result := False;
  end;
end;

{ Map a built-in ordinal TYPE name to its TTypeKind, or tyUnknown if the name is
  not a (supported) ordinal builtin. Covers the names that lex as tkIdent (the
  dedicated type tokens are handled directly via ParseTypeKind). }
function OrdinalNameToTk(const nm: AnsiString): TTypeKind;
begin
  if CaseEqual(nm, 'shortint') then Result := tyInt8
  else if CaseEqual(nm, 'byte') or CaseEqual(nm, 'uint8') then Result := tyUInt8
  else if CaseEqual(nm, 'smallint') then Result := tyInt16
  else if CaseEqual(nm, 'word') or CaseEqual(nm, 'uint16') then Result := tyUInt16
  else if CaseEqual(nm, 'longint') then Result := tyInt32
  else if CaseEqual(nm, 'integer') then Result := tyInteger
  else if CaseEqual(nm, 'cardinal') or CaseEqual(nm, 'longword') or CaseEqual(nm, 'uint32') then Result := tyUInt32
  else if CaseEqual(nm, 'int64') then Result := tyInt64
  else if CaseEqual(nm, 'boolean') then Result := tyBoolean
  else if CaseEqual(nm, 'char') or CaseEqual(nm, 'ansichar') then Result := tyChar
  else Result := tyUnknown;
end;

{ If the current token names an ordinal TYPE (a type-keyword token, a builtin
  ordinal name like ShortInt/Word, an ordinal type alias, or a user enum),
  consume it and produce an AN_INT_LIT for High/Low of that type; return True.
  Otherwise consume nothing and return False (the caller falls back to the
  High/Low-of-array-variable path). A name that resolves to a VARIABLE is left
  for that path. }
function TryConstHighLowValue(wantHigh: Boolean; var v: Int64): Boolean;
{ Value twin of TryFoldHighLowType for the constant evaluator: CurTok sits on
  the (candidate) type name inside High(...)/Low(...); on success the bound is
  in v and the type name is consumed (bug-pascal-high-low-in-const-expr —
  ZenGL's `array[0..High(LongWord) shr 1 - 1]`). }
var btk: TTypeKind; etid, aliasIdx: Integer; nm: AnsiString;
begin
  Result := False;
  if (CurTok.Kind = tkInteger_T) or (CurTok.Kind = tkLongWord_T) or
     (CurTok.Kind = tkBoolean_T) or (CurTok.Kind = tkChar_T) then
  begin
    btk := ParseTypeKind;   { consumes the type token, disambiguating byte/word/etc }
    Result := OrdinalTypeBound(btk, wantHigh, v);
    Exit;
  end;
  if CurTok.Kind <> tkIdent then Exit;
  nm := CurTok.SVal;
  btk := OrdinalNameToTk(nm);
  if btk = tyUnknown then
  begin
    aliasIdx := FindTypeAlias(nm);
    if aliasIdx >= 0 then btk := IntToTypeKind(AliasTk[aliasIdx]);
  end;
  if (btk <> tyUnknown) and OrdinalTypeBound(btk, wantHigh, v) then
  begin
    Next;
    Result := True; Exit;
  end;
  etid := FindEnumType(nm);
  if etid >= 0 then
  begin
    if wantHigh then v := EnumTypeValCount[etid] - 1 else v := 0;
    Next;
    Result := True; Exit;
  end;
end;

function TryFoldHighLowType(wantHigh: Boolean; var outNode: Integer): Boolean;
var btk: TTypeKind; bv: Int64; etid, aliasIdx: Integer; nm: AnsiString;
begin
  Result := False;
  if (CurTok.Kind = tkInteger_T) or (CurTok.Kind = tkLongWord_T) or
     (CurTok.Kind = tkBoolean_T) or (CurTok.Kind = tkChar_T) then
  begin
    btk := ParseTypeKind;   { consumes the type token, disambiguating byte/word/etc }
    if OrdinalTypeBound(btk, wantHigh, bv) then
    begin
      outNode := AllocNode(AN_INT_LIT); ASTIVal[outNode] := bv; ASTTk[outNode] := Ord(btk);
      Result := True;
    end;
    Exit;   { it was a type token — never fall through to the variable path }
  end;
  if CurTok.Kind <> tkIdent then Exit;
  nm := CurTok.SVal;
  { An array variable takes the variable path; a type name does not. }
  if FindSym(nm) >= 0 then Exit;

  btk := OrdinalNameToTk(nm);
  if btk = tyUnknown then
  begin
    aliasIdx := FindTypeAlias(nm);
    if aliasIdx >= 0 then btk := IntToTypeKind(AliasTk[aliasIdx]);
  end;
  if (btk <> tyUnknown) and OrdinalTypeBound(btk, wantHigh, bv) then
  begin
    Next; outNode := AllocNode(AN_INT_LIT); ASTIVal[outNode] := bv; ASTTk[outNode] := Ord(btk);
    Result := True; Exit;
  end;

  etid := FindEnumType(nm);
  if etid >= 0 then
  begin
    if wantHigh then bv := EnumTypeValCount[etid] - 1 else bv := 0;
    Next; outNode := AllocNode(AN_INT_LIT); ASTIVal[outNode] := bv; ASTTk[outNode] := Ord(tyInteger);
    Result := True; Exit;
  end;
end;

procedure ParseFactor;
var name, grpAcc: AnsiString; recName: Integer; idx, procIdx, i, node, left, prevTok, valNode: Integer; tk: TTypeKind; op, argSeq, argSeq2, argSeq3, lastArg, argIdx, exprNode, szArg: Integer;
    nArgs, argsHead, currArg: Integer; argTypes: array[0..MAX_PROC_PARAMS-1] of TTypeKind;
    ci, mmi, mpi, mcallNode, mlastArg, smSelfIdx, smselfArg: Integer;
    aliasIdx, fieldNode, indexNode, baseNode, baseRec, fIdx, mci, margSeq, margIdx, mexprNode, mai, pri, qUnit: Integer;
    fieldName, methName: AnsiString; isAssign: Boolean; castTk: TTypeKind;
    liftedVar, identNode, addrNode: Integer;
    helperPi, wrapperArg, wrapperCall, sci: Integer;
    isLiftedCall, isCStringCall: Boolean;
    bitNot, opIsArith: Boolean; notOp: Integer;
    szAi, szFlatLen, szDi, szBrDepth, szNIdx, szBase, szRec: Integer; szElemTk: TTypeKind;
    seEtid, seOrd: Integer;
begin
  LastExprTk := tyInteger;
  case CurTok.Kind of
    tkInteger:
    begin
      node := AllocNode(AN_INT_LIT); ASTIVal[node] := CurTok.IVal;
      { A literal that does not fit a signed 32-bit Integer is an Int64; the
        i386 backend keys its 64-bit codegen off this type. }
      if (CurTok.IVal > 2147483647) or (CurTok.IVal < -2147483648) then
        ASTTk[node] := Ord(tyInt64)
      else
        ASTTk[node] := Ord(tyInteger);
      CurASTNode := node; Next;
    end;
    tkLBrack:
    begin
      CurASTNode := ParseSetLiteralAST;
      LastExprTk := tySet;
    end;
    tkNil:
    begin
      node := AllocNode(AN_INT_LIT); ASTIVal[node] := 0; ASTTk[node] := Ord(tyPointer); CurASTNode := node; Next; LastExprTk := tyPointer;
    end;
    tkPlusPlus, tkMinusMinus:
    begin
      { Prefix `++lv` / `--lv`: bump first, yield the NEW value. Operand must be
        an lvalue (parsed as a factor so postfix/suffixes still bind). }
      bitNot := CurTok.Kind = tkPlusPlus; Next;   { bitNot reused as isIncrement }
      ParseFactor;
      node := AllocNode(AN_INCDEC);
      ASTLeft[node] := CurASTNode;
      if bitNot then ASTIVal[node] := 1 else ASTIVal[node] := -1;
      ASTSOffset[node] := 0;   { prefix → new value }
      ASTTk[node] := ASTTk[CurASTNode];
      CurASTNode := node; LastExprTk := IntToTypeKind(ASTTk[node]);
    end;
    tkIf:
    begin
      { Conditional EXPRESSION `if c then a else b` (the value-bearing form the C
        frontend's ternary `c ? a : b` lowers to). Reached only in expression
        position: a statement-leading `if` is parsed by ParseStatementAST before
        any factor, so this never shadows the if-statement. `else` is mandatory —
        an expression must yield a value. Arms are full expressions; parenthesize
        when embedding in a larger one. Result type = the then-arm's type. }
      Next;                          { consume 'if' }
      ParseExpr; left := CurASTNode; { condition }
      Expect(tkThen, 'then');
      ParseExpr; identNode := CurASTNode; tk := LastExprTk;  { then-arm }
      Expect(tkElse, 'else');
      ParseExpr; addrNode := CurASTNode;                     { else-arm }
      { A frozen string-literal arm types as tyString; carry the result as a
        managed AnsiString (managed-default) so it has a real handle downstream
        (writeln arg, assignment) — the IR per-arm assign coerces the literal. }
      if tk = tyString then tk := tyAnsiString;
      valNode := AllocNode(AN_PAIR);
      ASTLeft[valNode] := identNode; ASTRight[valNode] := addrNode;
      node := AllocNode(AN_TERNARY);
      ASTLeft[node] := left; ASTRight[node] := valNode;
      ASTTk[node] := Ord(tk);
      CurASTNode := node; LastExprTk := tk;
    end;
    tkDefault:
    begin
      if (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        { Default(T): zero value of the type — ordinals/pointers/chars in v1
          (records/strings later). `default` lexes as its own token. }
        Next; Expect(tkLParen, '(');
        { FPC-parity diagnostics: Default() is not defined for file types —
          neither TextFile itself nor a record that (transitively) contains one
          (bug-pascal-missing-diagnostics-fail-tests / tdefault2, tdefault6). }
        if CurTok.Kind = tkIdent then
        begin
          if CaseEqual(CurTok.SVal, 'text') or CaseEqual(CurTok.SVal, 'textfile') then
            Error('Default: file types are not allowed');
          i := IsRecordType(CurTok.SVal);
          if (i <> REC_NONE) and RecContainsTextRec(i) then
            Error('Default: the record type contains a file field');
        end;
        node := AllocNode(AN_INT_LIT);
        ASTIVal[node] := 0;
        ASTTk[node] := Ord(tyInt64);
        i := 1;
        while (i > 0) and (CurTok.Kind <> tkEOF) do
        begin
          if CurTok.Kind = tkLParen then Inc(i)
          else if CurTok.Kind = tkRParen then Dec(i);
          if i > 0 then Next;
        end;
        Expect(tkRParen, ')');
        CurASTNode := node;
        LastExprTk := tyInt64;
      end
      else
      begin
        node := AllocNode(AN_DEFAULT);
        ASTTk[node] := Ord(tyUnknown);
        CurASTNode := node;
        LastExprTk := tyUnknown;
        Next;
      end;
    end;
    tkAt:
    begin
      Next;
      if CurTok.Kind <> tkIdent then Error('expected identifier after @');
      name := CurTok.SVal;
      idx := FindSym(name);
      { @obj.method yields a TMethod (Code+Data): obj is a class instance var,
        method one of its methods. Code = method proc address,
        Data = the instance pointer. Only valid as the RHS of an assignment to
        a TMethod-shaped target (handled in AN_ASSIGN). }
      if (idx >= 0) and (Syms[idx].RecName >= REC_UCLASS_BASE) and
         (not UClsIsRecord[Syms[idx].RecName - REC_UCLASS_BASE]) and
         (TokPos < TokCount) and (Tokens[TokPos].Kind = tkDot) then
      begin
        ci := Syms[idx].RecName - REC_UCLASS_BASE;
        Next;            { consume obj name (CurTok = '.') }
        Next;            { consume '.' (CurTok = method name) }
        if CurTok.Kind <> tkIdent then Error('expected method name after @obj.');
        mmi := FindUMeth(ci, CurTok.SVal);
        if mmi < 0 then
        begin
          { @obj.field — ADDRESS of an instance field (blcksock's
            `buf := @Value.Value`). AN_ADDR over the field lvalue. }
          mmi := FindUField(ci, CurTok.SVal);
          if mmi < 0 then Error('@obj.method: unknown method or field');
          valNode := AllocNode(AN_IDENT);
          ASTIVal[valNode] := idx;
          ASTTk[valNode] := Ord(tyClass);
          node := AllocNode(AN_FIELD);
          ASTLeft[node] := valNode;
          ASTSOffset[node] := Tokens[TokPos-1].SOffset;
          ASTSLen[node] := Tokens[TokPos-1].SLen;
          ASTTk[node] := UFldTk[mmi];
          Next;   { consume field name }
          valNode := AllocNode(AN_ADDR);
          ASTLeft[valNode] := node;
          ASTTk[valNode] := Ord(tyPointer);
          CurASTNode := valNode;
          LastExprTk := tyPointer;
          Exit;
        end;
        valNode := AllocNode(AN_IDENT);   { object value = the instance pointer }
        ASTIVal[valNode] := idx;
        ASTTk[valNode] := Ord(tyClass);
        node := AllocNode(AN_METHODREF);
        ASTIVal[node] := UMthProc_[mmi];
        ASTLeft[node] := valNode;
        { Typed as a Pointer: in a value/argument context @obj.Method surfaces its
          CODE address (IR lowering yields IR_PROCADDR), so it matches a Pointer
          parameter — `TakesPtr(@h.M)`. Assignment to a TMethod target still
          captures code+data: AN_ASSIGN keys on the AN_METHODREF node kind, not
          this type, so `pm := @h.M` / `widget.OnClick := @h.M` are unaffected. }
        ASTTk[node] := Ord(tyPointer);
        Next;            { consume method name }
        CurASTNode := node;
        LastExprTk := tyPointer;
      end
      { @Method bare inside a method body: implicit Self — @BinaryCompareKey
        == @Self.BinaryCompareKey (an AN_METHODREF: Code+Data). Checked before
        the plain @proc case so a method wins over a same-named free routine
        (innermost scope), matching the other implicit-Self dispatches. }
      else if (idx < 0) and (CurProc >= 0) and (CurSelfClass >= REC_UCLASS_BASE) and
              (Procs[CurProc].ParamCount > 0) and
              (FindUMeth(CurSelfClass - REC_UCLASS_BASE, name) >= 0) and
              ((TokPos >= TokCount) or (Tokens[TokPos].Kind <> tkDot)) then
      begin
        mmi := FindUMeth(CurSelfClass - REC_UCLASS_BASE, name);
        valNode := AllocNode(AN_IDENT);
        ASTIVal[valNode] := Procs[CurProc].Params[0].SymIdx;   { Self }
        ASTTk[valNode] := Ord(tyClass);
        node := AllocNode(AN_METHODREF);
        ASTIVal[node] := UMthProc_[mmi];
        ASTLeft[node] := valNode;
        ASTTk[node] := Ord(tyPointer);
        Next;            { consume method name }
        CurASTNode := node;
        LastExprTk := tyPointer;
      end
      { @proc: not a variable but a known routine → absolute code address }
      else if (idx < 0) and (FindProc(name) >= 0) then
      begin
        node := AllocNode(AN_PROCADDR);
        ASTIVal[node] := FindProc(name);
        ASTTk[node] := Ord(tyPointer);
        Next;
        CurASTNode := node;
        LastExprTk := tyPointer;
      end
      else
      begin
        Next;
        valNode := ParseLValueAST(idx, TokPos - 2);
        node := AllocNode(AN_ADDR);
        ASTLeft[node] := valNode;
        ASTTk[node] := Ord(tyPointer);
        CurASTNode := node;
        LastExprTk := tyPointer;
      end;
    end;
    tkFloat:
    begin
      node := AllocNode(AN_FLOAT_LIT); ASTIVal[node] := CurTok.IVal; ASTTk[node] := Ord(tyDouble);
      CurASTNode := node; LastExprTk := tyDouble; Next;
    end;
    tkTrue:
    begin
      node := AllocNode(AN_BOOL_LIT); ASTIVal[node] := 1; ASTTk[node] := Ord(tyBoolean); CurASTNode := node; Next; LastExprTk := tyBoolean;
    end;
    tkFalse:
    begin
      node := AllocNode(AN_BOOL_LIT); ASTIVal[node] := 0; ASTTk[node] := Ord(tyBoolean); CurASTNode := node; Next; LastExprTk := tyBoolean;
    end;
    tkString:
    begin
      prevTok := TokPos - 1;
      if Length(CurTok.SVal) = 1 then
      begin
        node := AllocNode(AN_INT_LIT); ASTIVal[node] := Ord(CurTok.SVal[1]); ASTTk[node] := Ord(tyChar);
        ASTSOffset[node] := Tokens[prevTok].SOffset; ASTSLen[node] := Tokens[prevTok].SLen;
        CurASTNode := node; Next; LastExprTk := tyChar;
      end
      else
      begin
        prevTok := TokPos - 1; Next;
        node := AllocNode(AN_STR_LIT);
        ASTSOffset[node] := Tokens[prevTok].SOffset; ASTSLen[node] := Tokens[prevTok].SLen;
        ASTTk[node] := Ord(tyString); CurASTNode := node;
        LastExprTk := tyString;
      end;
    end;
    tkLParen:
    begin
      Next; if PyExprMode then PyParseBoolExpr else ParseExpr;
      { C comma operator `(a, b, ...)`: each operand but the last is evaluated for
        its side effects then discarded; the value is the last. A parenthesised
        comma list is otherwise a syntax error in pxx, so this is conflict-free
        and reads identically to C. Skipped in Python mode (there `(a, b)` is a
        tuple). Right-nested AN_COMMA so lowering discards each Left in turn. }
      if (not PyExprMode) and (CurTok.Kind = tkComma) then
      begin
        node := CurASTNode;
        while Eat(tkComma) do
        begin
          ParseExpr;
          valNode := AllocNode(AN_COMMA);
          ASTLeft[valNode] := node;
          ASTRight[valNode] := CurASTNode;
          ASTTk[valNode] := ASTTk[CurASTNode];
          node := valNode;
        end;
        CurASTNode := node;
        LastExprTk := IntToTypeKind(ASTTk[node]);
      end;
      Expect(tkRParen, ')');
      { Postfix suffix on a parenthesised expression: `(p)^`, `(p+k)^`, `(r).f`,
        `(a)[i]`. Without this the `^`/`.`/`[` were left dangling and the grouped
        value was used as-is (e.g. `(p)^` returned the pointer, not the pointee). }
      node := CurASTNode;
      while CurTok.Kind in [tkCaret, tkDot, tkLBrack] do
      begin
        if CurTok.Kind = tkCaret then
        begin
          Next;
          indexNode := AllocNode(AN_DEREF);
          ASTLeft[indexNode] := node;
          { Resolve the pointee type from the inner node, mirroring the direct
            `ident^` path. A non-trivial pointer expression (binop/cast) carries
            no element-type tag, so default to Integer (matches `else` below). }
          tk := tyInteger; recName := REC_NONE;
          if IntToTypeKind(ASTTk[node]) = tyPointer then
          begin
            if ASTKind[node] = AN_IDENT then
            begin
              tk := Syms[ASTIVal[node]].PtrElemTk;
              recName := Syms[ASTIVal[node]].PtrElemRec;
            end
            else if (ASTKind[node] = AN_INDEX) and (ASTKind[ASTLeft[node]] = AN_IDENT) then
            begin
              tk := Syms[ASTIVal[ASTLeft[node]]].PtrElemTk;
              recName := Syms[ASTIVal[ASTLeft[node]]].PtrElemRec;
            end;
          end;
          ASTTk[indexNode] := StrValTk(tk);
          node := indexNode;
        end
        else if CurTok.Kind = tkLBrack then
        begin
          Next;
          indexNode := AllocNode(AN_INDEX);
          ASTLeft[indexNode] := node;
          ParseExpr;
          ASTRight[indexNode] := CurASTNode;
          Expect(tkRBrack, ']');
          ASTTk[indexNode] := ASTTk[node];
          node := indexNode;
        end
        else { tkDot — field or method of the grouped record/class value }
        begin
          Next;
          if CurTok.Kind in [tkEOF, tkSemicolon, tkAssign, tkRBrack, tkRParen] then
            Error('expected field name after .');
          prevTok := TokPos - 1;
          fieldName := GetTokenStr(prevTok);
          baseRec := ResolveNodeRec(node);
          mci := -1; mmi := -1;
          if baseRec >= REC_UCLASS_BASE then
          begin
            mci := baseRec - REC_UCLASS_BASE;
            if FindUProp(mci, fieldName) < 0 then
              mmi := FindUMethArity(mci, fieldName, CountCallArgsAhead);
          end;
          if (mmi >= 0) and (mci >= 0) and UClsIsInterface[mci] then
          begin
            { `(iface-expr).M(args)` — dispatch through the IMT slot, exactly like
              the direct `iface.M` path. The grouped node is the interface value. }
            mpi := UMthProc_[mmi];
            Next; { consume method name }
            mcallNode := AllocNode(AN_INTF_CALL);
            ASTRight[mcallNode] := node;
            ASTIVal[mcallNode] := mpi;
            ASTSOffset[mcallNode] := UMthVirSlot[mmi];
            ASTTk[mcallNode] := Ord(Procs[mpi].RetType);
            mlastArg := -1;
            if CurTok.Kind = tkLParen then
            begin
              Next;
              mai := 1; { param 0 = Self (provided by the fat pointer) }
              while mai <= Procs[mpi].ParamCount-1 do
              begin
                if Procs[mpi].Params[mai].IsRef or Procs[mpi].Params[mai].IsArray then
                begin
                  if ByRefArgStartsExpression then
                  begin
                    { non-ident by-ref/array arg (@obj.Method to a method-pointer
                      param, [..] literals, casts): parse as an expression }
                    ParseExpr; mexprNode := CurASTNode;
                  end
                  else
                  begin
                    margIdx := FindSym(CurTok.SVal); Next;
                    mexprNode := ParseLValueAST(margIdx, TokPos - 2);
                  end;
                end
                else begin ParseExpr; mexprNode := CurASTNode; end;
                margSeq := AllocNode(AN_ARG); ASTLeft[margSeq] := mexprNode;
                if mlastArg = -1 then ASTLeft[mcallNode] := margSeq
                else ASTRight[mlastArg] := margSeq;
                mlastArg := margSeq;
                if (mai < Procs[mpi].ParamCount-1) and CanFillDefaultsFrom(mpi, mai+1) then
                begin
                  FillDefaultArgs(mpi, mai+1, mcallNode, mlastArg);
                  mai := Procs[mpi].ParamCount-1;
                end
                else if mai < Procs[mpi].ParamCount-1 then Expect(tkComma, ',');
                Inc(mai);
              end;
              Expect(tkRParen, ')');
            end;
            node := mcallNode;
          end
          else if mmi >= 0 then
          begin
            { `(expr).M(args)` on a non-interface class/record value (e.g.
              `(o as T).M`). The interface branch above only handled IMT dispatch;
              without this a class method silently lowered to an AN_FIELD read and
              was never called. Mirrors ParseClassRecordSelectors: static or
              virtual dispatch, Self = the grouped value (arg 0). }
            mpi := UMthProc_[mmi];
            if UMthVirSlot[mmi] >= 0 then
            begin
              mcallNode := AllocNode(AN_VIRTUAL_CALL);
              ASTRight[mcallNode] := UMthVirSlot[mmi];
            end
            else
              mcallNode := AllocNode(AN_CALL);
            ASTIVal[mcallNode] := mpi;
            ASTTk[mcallNode] := Ord(Procs[mpi].RetType);
            margSeq := AllocNode(AN_ARG); ASTLeft[margSeq] := node;   { Self = arg 0 }
            ASTLeft[mcallNode] := margSeq;
            mlastArg := margSeq;
            Next; { consume method name }
            if CurTok.Kind = tkLParen then
            begin
              Next;
              mai := 1;
              while mai <= Procs[mpi].ParamCount - 1 do
              begin
                if Procs[mpi].Params[mai].IsRef or Procs[mpi].Params[mai].IsArray then
                begin
                  if ByRefArgStartsExpression then
                  begin
                    { non-ident by-ref/array arg (@obj.Method to a method-pointer
                      param, [..] literals, casts): parse as an expression }
                    ParseExpr; mexprNode := CurASTNode;
                  end
                  else
                  begin
                    margIdx := FindSym(CurTok.SVal); Next;
                    mexprNode := ParseLValueAST(margIdx, TokPos - 2);
                  end;
                end
                else begin ParseExpr; mexprNode := CurASTNode; end;
                margSeq := AllocNode(AN_ARG); ASTLeft[margSeq] := mexprNode;
                ASTRight[mlastArg] := margSeq; mlastArg := margSeq;
                if (mai < Procs[mpi].ParamCount-1) and CanFillDefaultsFrom(mpi, mai+1) then
                begin
                  FillDefaultArgs(mpi, mai+1, mcallNode, mlastArg);
                  mai := Procs[mpi].ParamCount-1;
                end
                else if mai < Procs[mpi].ParamCount-1 then Expect(tkComma, ',');
                Inc(mai);
              end;
              Expect(tkRParen, ')');
            end;
            { result type for chaining (e.g. (o as T).GetChild.M) }
            if (Procs[mpi].RetType = tyClass) or (Procs[mpi].RetType = tyRecord) then
              ASTTk[mcallNode] := Ord(Procs[mpi].RetType);
            node := mcallNode;
          end
          else
          begin
            { Property on a grouped/cast value `(expr).Prop` — resolve to the
              backing field or getter call like ParseClassRecordSelectors (read
              side only: a grouped value is not an lvalue). Falling through to
              the raw field builder read offset 0 — the VMT pointer
              (bug-downcast-inherited-property-wrong-offset's sibling). }
            pri := -1;
            if mci >= 0 then pri := FindUProp(mci, fieldName);
            if (pri >= 0) and (UPropReadFLen[pri] > 0) then
            begin
              fieldNode := AllocNode(AN_FIELD);
              ASTLeft[fieldNode] := node;
              ASTSOffset[fieldNode] := UPropReadFOff[pri];
              ASTSLen[fieldNode] := UPropReadFLen[pri];
              grpAcc := '';
              for i := 0 to UPropReadFLen[pri] - 1 do
                AppendChar(grpAcc, TokChars[UPropReadFOff[pri] + i]);
              ASTTk[fieldNode] := Ord(RecFieldType(baseRec, grpAcc));
              Next;
              node := fieldNode;
            end
            else if (pri >= 0) and (UPropReadMLen[pri] > 0) then
            begin
              grpAcc := '';
              for i := 0 to UPropReadMLen[pri] - 1 do
                AppendChar(grpAcc, TokChars[UPropReadMOff[pri] + i]);
              mmi := FindUMeth(mci, grpAcc);
              if mmi < 0 then Error('getter method not found: ' + grpAcc);
              mpi := UMthProc_[mmi];
              Next; { consume property name }
              margIdx := -1;
              if UPropIsIndexed[pri] then ParsePropIndexArgs(margIdx, mlastArg);
              if UMthVirSlot[mmi] >= 0 then
              begin
                mcallNode := AllocNode(AN_VIRTUAL_CALL);
                ASTRight[mcallNode] := UMthVirSlot[mmi];
              end
              else
                mcallNode := AllocNode(AN_CALL);
              ASTIVal[mcallNode] := mpi;
              ASTTk[mcallNode] := Ord(Procs[mpi].RetType);
              margSeq := AllocNode(AN_ARG);
              ASTLeft[margSeq] := node;
              ASTLeft[mcallNode] := margSeq;
              { Getter args: self [, index...] }
              if margIdx >= 0 then ASTRight[margSeq] := margIdx;
              node := mcallNode;
            end
            else if pri >= 0 then
              Error('property is write-only')
            else
            begin
              fieldNode := AllocNode(AN_FIELD);
              ASTLeft[fieldNode] := node;
              ASTSOffset[fieldNode] := Tokens[prevTok].SOffset;
              ASTSLen[fieldNode] := Tokens[prevTok].SLen;
              ASTTk[fieldNode] := Ord(RecFieldType(baseRec, fieldName));
              Next;
              node := fieldNode;
            end;
          end;
        end;
      end;
      CurASTNode := node;
    end;
    tkMinus:
    begin
      Next; ParseFactor;
      left := CurASTNode;
      node := AllocNode(AN_NEG); ASTLeft[node] := left; CurASTNode := node;
    end;
    tkNot:
    begin
      Next; ParseFactor;
      left := CurASTNode;
      { `not` is bitwise complement for integer operands (matches FPC), logical
        for Boolean and everything else. The earlier all-logical rule existed
        because a prior attempt keyed bitwise-vs-logical off the GLOBAL
        LastExprTk tracker, which is clobbered between factors — so a boolean
        `while not done` was mistyped as bitwise and hung self-compile.

        Drive it off the operand node's OWN type, but ONLY trust that type for
        operand node kinds whose type is authoritative: an integer LITERAL or an
        IDENTIFIER (its symbol's declared type). Computed expressions — AN_BINOP
        (comparisons / boolean ops) and AN_CALL (boolean-returning functions) —
        are NOT trusted here: PXX tags some of them tyInteger/tyInt64 even when
        they are logically Boolean (e.g. `not (a = b)`, `not Eat(...)` appear in
        compiler.pas with ASTTk = tyInteger), and promoting those to bitwise
        diverges from FPC and breaks self-host / cross-bootstrap. So those keep
        the long-standing logical behaviour. The IR_NOT codegen already emits
        `not rax` for ordinal-non-boolean types. }
      node := AllocNode(AN_NOT); ASTLeft[node] := left;
      { Bitwise only when the operand's integer type is AUTHORITATIVE. Beyond the
        literal/identifier base case, three more operand shapes carry a trustworthy
        integer type and so were wrongly forced boolean (the result became `xor
        rax,1` — e.g. `not Int64(0)` printed TRUE):
          - a built-in ordinal value-cast `Int64(e)`/`Cardinal(e)` (AN_PTR_CAST,
            ASTIVal=-1) and the `Integer(e)`/`LongWord(e)` token-casts (AN_CALL
            with the cast's negative op id);
          - a pure ARITHMETIC/shift AN_BINOP (`x-1`, `x shr 1`): its operator is
            unambiguously numeric, so unlike a comparison/`and`/`or`/`xor` binop
            (which PXX sometimes mistags integer though it is logically boolean)
            it can never be boolean. `shr` is lexed as an identifier, so its
            operator id is Ord(tkIdent) — the only ident-operator binop.
        and/or/xor stay logical (ambiguous), matching the prior behaviour, so the
        compiler's own `not (a or b)` / `not (r and v)` keep self-host identical. }
      notOp := Integer(ASTIVal[left]);
      opIsArith := (notOp = Ord(tkPlus)) or (notOp = Ord(tkMinus)) or
                   (notOp = Ord(tkStar)) or (notOp = Ord(tkDiv)) or
                   (notOp = Ord(tkMod)) or (notOp = Ord(tkShl)) or
                   (notOp = Ord(tkIdent));
      bitNot :=
        ((ASTTk[left] = 1) or ((ASTTk[left] >= 7) and (ASTTk[left] <= 16))) and
        ((ASTKind[left] = AN_INT_LIT) or (ASTKind[left] = AN_IDENT) or
         ((ASTKind[left] = AN_PTR_CAST) and (Integer(ASTIVal[left]) = -1)) or
         ((ASTKind[left] = AN_CALL) and
          ((Integer(ASTIVal[left]) = -Ord(tkInteger_T)) or
           (Integer(ASTIVal[left]) = -Ord(tkLongWord_T)))) or
         { A user function call whose DECLARED return type is a non-boolean
           ordinal is authoritative (unlike the node's ASTTk, which PXX sometimes
           mistags). This trusts `not f()` for an Int64/Integer-returning f
           (e.g. C const-eval `~CEvalConstPrimary()`) as bitwise, while a
           Boolean-returning f (RetType = tyBoolean, e.g. `not Eat(..)`) still
           falls through to logical. }
         ((ASTKind[left] = AN_CALL) and (Integer(ASTIVal[left]) >= 0) and
          (Integer(ASTIVal[left]) < ProcCount) and
          TypeIsOrdinal(Procs[Integer(ASTIVal[left])].RetType) and
          (Procs[Integer(ASTIVal[left])].RetType <> tyBoolean)) or
         ((ASTKind[left] = AN_BINOP) and opIsArith));
      if bitNot then
      begin
        ASTTk[node] := ASTTk[left];
        LastExprTk := IntToTypeKind(ASTTk[left]);
      end
      else
      begin
        ASTTk[node] := Ord(tyBoolean);
        LastExprTk := tyBoolean;
      end;
      CurASTNode := node;
    end;
    tkInteger_T, tkLongWord_T:
    begin
      { 'byte'/'longword' collide with 'integer'/'longint' on token KIND (all
        four lex as tkInteger_T/tkLongWord_T -- see asmenc.inc's documented
        landmine on this), so disambiguate on the source text, same technique
        SizeOf's type-name parsing already uses. A genuine byte/cardinal cast
        needs real width truncation (AN_PTR_CAST, routes through the masking
        logic in ir.inc's AN_PTR_CAST case) -- not the Integer/LongWord
        "value-pun" passthrough (AN_CALL, result bit pattern = operand's,
        unchanged), which stays exactly as it was for actual Integer/LongInt
        casts. See bug-narrowing-typecast-rvalue-no-truncate. }
      if CaseEqual(CurTok.SVal, 'byte') then
      begin
        Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
        node := AllocNode(AN_PTR_CAST);
        ASTLeft[node] := CurASTNode;
        ASTIVal[node] := -1;
        ASTTk[node] := Ord(tyUInt8);
        CurASTNode := node;
        LastExprTk := tyUInt8;
      end
      else if CaseEqual(CurTok.SVal, 'longword') then
      begin
        Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
        node := AllocNode(AN_PTR_CAST);
        ASTLeft[node] := CurASTNode;
        ASTIVal[node] := -1;
        ASTTk[node] := Ord(tyUInt32);
        CurASTNode := node;
        LastExprTk := tyUInt32;
      end
      else
      begin
        op := Ord(CurTok.Kind);
        Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
        node := AllocNode(AN_CALL); ASTIVal[node] := -op;
        ASTTk[node] := Ord(tyInteger);
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
        ASTLeft[node] := argSeq;
        CurASTNode := node;
      end;
    end;
    tkChar_T, tkBoolean_T:
    begin
      { `Char(x)` / `Boolean(x)` value-puns — same passthrough model as Chr/Ord:
        the result type is the cast type, the bit pattern is the operand's. }
      op := Ord(CurTok.Kind);
      if CurTok.Kind = tkChar_T then LastExprTk := tyChar else LastExprTk := tyBoolean;
      Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
      node := AllocNode(AN_CALL); ASTIVal[node] := -op;
      if op = Ord(tkChar_T) then ASTTk[node] := Ord(tyChar) else ASTTk[node] := Ord(tyBoolean);
      argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
      ASTLeft[node] := argSeq;
      CurASTNode := node;
    end;
    tkSingle_T, tkDouble_T, tkExtended_T:
    begin
      { Value typecast to a float type, `Single(expr)` / `Double(expr)`. Unlike
        the integer/char puns this is a real conversion (int->float, or
        double->single narrowing), so desugar to a hidden temp of the cast type
        plus an assignment — the ordinary store path already coerces the operand.
        Reuses the generic assign-then-yield node (AN_STR_FROM_CHAR: Left = the
        store side-effect, Right = the temp read). `Extended` aliases Double. }
      if CurTok.Kind = tkSingle_T then LastExprTk := tySingle else LastExprTk := tyDouble;
      Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
      op := AllocVar('', LastExprTk);
      node := AllocNode(AN_STR_FROM_CHAR);
      argSeq := AllocNode(AN_IDENT);             { store LHS = the temp }
      ASTIVal[argSeq] := op; ASTTk[argSeq] := Ord(Syms[op].TypeKind);
      left := AllocNode(AN_ASSIGN);
      ASTLeft[left] := argSeq; ASTRight[left] := CurASTNode;
      ASTTk[left] := Ord(Syms[op].TypeKind);
      ASTLeft[node] := left;
      identNode := AllocNode(AN_IDENT);          { yielded value = the temp }
      ASTIVal[identNode] := op; ASTTk[identNode] := Ord(Syms[op].TypeKind);
      ASTRight[node] := identNode;
      ASTTk[node] := Ord(Syms[op].TypeKind);
      CurASTNode := node;
    end;
    tkString_T:
    begin
      { `String(x)`. For a string operand it is identity (passthrough). For a Char
        operand it must produce a *string value*; route through AN_STR_FROM_CHAR
        which reuses the `s := c` store into a hidden temp, then yields the temp —
        so it works in both frozen and managed string modes with no backend code. }
      LastExprTk := tyString;
      Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
      if (IntToTypeKind(ASTTk[CurASTNode]) = tyString) or
         (IntToTypeKind(ASTTk[CurASTNode]) = tyAnsiString) then
      begin
        node := AllocNode(AN_CALL); ASTIVal[node] := -Ord(tkString_T);
        ASTTk[node] := ASTTk[CurASTNode];
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
        ASTLeft[node] := argSeq;
        CurASTNode := node;
      end
      else if IntToTypeKind(ASTTk[CurASTNode]) = tyChar then
      begin
        { Build the desugar at parse time so it goes through the same AST passes
          as hand-written code: a hidden string temp, `__t := c` (char->string
          store), and a read of __t. AN_STR_FROM_CHAR.Left = the assign (side
          effect), .Right = the temp read (the yielded value). The temp is tyString
          to match the `String` keyword (always frozen tyString in this dialect,
          even under PXX_MANAGED_STRING where only `AnsiString` is managed). }
        op := AllocVar('', tyString);
        node := AllocNode(AN_STR_FROM_CHAR);
        argSeq := AllocNode(AN_IDENT);       { LHS of the store }
        ASTIVal[argSeq] := op; ASTTk[argSeq] := Ord(Syms[op].TypeKind);
        left := AllocNode(AN_ASSIGN);
        ASTLeft[left] := argSeq; ASTRight[left] := CurASTNode;
        ASTTk[left] := Ord(Syms[op].TypeKind);
        ASTLeft[node] := left;
        identNode := AllocNode(AN_IDENT);     { the yielded value }
        ASTIVal[identNode] := op; ASTTk[identNode] := Ord(Syms[op].TypeKind);
        ASTRight[node] := identNode;
        ASTTk[node] := Ord(Syms[op].TypeKind);
        CurASTNode := node;
      end
      else
        Error('String(): operand must be Char or string');
    end;
    tkSysOpen:
    begin
      Next; Expect(tkLParen, '(');
      if CurTok.Kind <> tkIdent then Error('SysOpen: expected string var');
      idx := FindSym(CurTok.SVal); Next;
      valNode := ParseLValueAST(idx, TokPos - 2);
      if (idx < 0) or ((not TypeIsFrozenString(Syms[idx].TypeKind)) and
                       (Syms[idx].TypeKind <> tyAnsiString)) then Error('SysOpen: not a string var');
      Expect(tkComma, ',');

      argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := valNode;
      ParseExpr;
      argSeq2 := AllocNode(AN_ARG); ASTLeft[argSeq2] := CurASTNode;
      ASTRight[argSeq] := argSeq2;
      Expect(tkRParen, ')');

      node := AllocNode(AN_CALL); ASTIVal[node] := -Ord(tkSysOpen);
      ASTLeft[node] := argSeq;
      CurASTNode := node;
    end;
    tkSysRead:
    begin
      Next; Expect(tkLParen, '(');
      ParseExpr;
      argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
      Expect(tkComma, ',');
      if CurTok.Kind <> tkIdent then Error('SysRead: expected array var');
      idx := FindSym(CurTok.SVal); Next;
      valNode := ParseLValueAST(idx, TokPos - 2);
      if (idx < 0) or not Syms[idx].IsArray then Error('SysRead: not an array var');
      Expect(tkComma, ',');

      argSeq2 := AllocNode(AN_ARG); ASTLeft[argSeq2] := valNode;
      ASTRight[argSeq] := argSeq2;
      ParseExpr;
      argSeq3 := AllocNode(AN_ARG); ASTLeft[argSeq3] := CurASTNode;
      ASTRight[argSeq2] := argSeq3;
      Expect(tkRParen, ')');

      node := AllocNode(AN_CALL); ASTIVal[node] := -Ord(tkSysRead);
      ASTLeft[node] := argSeq;
      CurASTNode := node;
    end;
    tkSyswrite:
    begin
      Next; Expect(tkLParen, '(');
      ParseExpr;
      argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
      Expect(tkComma, ',');
      if CurTok.Kind <> tkIdent then Error('Syswrite: expected array var');
      idx := FindSym(CurTok.SVal); Next;
      valNode := ParseLValueAST(idx, TokPos - 2);
      if (idx < 0) or not Syms[idx].IsArray then Error('Syswrite: not an array var');
      Expect(tkComma, ',');

      argSeq2 := AllocNode(AN_ARG); ASTLeft[argSeq2] := valNode;
      ASTRight[argSeq] := argSeq2;
      ParseExpr;
      argSeq3 := AllocNode(AN_ARG); ASTLeft[argSeq3] := CurASTNode;
      ASTRight[argSeq2] := argSeq3;
      Expect(tkRParen, ')');

      node := AllocNode(AN_CALL); ASTIVal[node] := -Ord(tkSyswrite);
      ASTLeft[node] := argSeq;
      CurASTNode := node;
    end;
    tkArgCount:
    begin
      Next;
      if CurTok.Kind = tkLParen then begin Next; Expect(tkRParen, ')'); end;
      node := AllocNode(AN_CALL); ASTIVal[node] := -Ord(tkArgCount); CurASTNode := node;
    end;
    tkArgStr:
    begin
      { Inline ParamStr(i): the 2-arg ArgStr(i, var) codegen needs a destination
        string. Synthesize a hidden frozen-string temp, copy argv[i] into it
        (EmitArgvToString — a frozen buffer write, no managed release, so the temp
        needs no nil-init), and yield the temp. Lets ParamStr(i) be used directly
        in any expression (comparison, argument), not only as an assignment RHS.
        The temp is tyString (frozen) even under managed strings, matching the
        `String` keyword temp above. }
      Next; Expect(tkLParen, '(');
      ParseExpr;                            { index expression }
      Expect(tkRParen, ')');
      op := AllocVar('', tyString);
      { 2-arg ArgStr call: arg0 = index, arg1 = the temp (lvalue) }
      argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
      identNode := AllocNode(AN_IDENT);
      ASTIVal[identNode] := op; ASTTk[identNode] := Ord(Syms[op].TypeKind);
      argSeq2 := AllocNode(AN_ARG); ASTLeft[argSeq2] := identNode;
      ASTRight[argSeq] := argSeq2;
      node := AllocNode(AN_CALL); ASTIVal[node] := -Ord(tkArgStr);
      ASTLeft[node] := argSeq;
      { AN_STR_FROM_CHAR: Left = the ArgStr side-effect, Right = read the temp. }
      left := AllocNode(AN_STR_FROM_CHAR);
      ASTLeft[left] := node;
      identNode := AllocNode(AN_IDENT);
      ASTIVal[identNode] := op; ASTTk[identNode] := Ord(Syms[op].TypeKind);
      ASTRight[left] := identNode;
      ASTTk[left] := Ord(Syms[op].TypeKind);
      CurASTNode := left;
    end;
    tkIdent:
    begin
      name := CurTok.SVal;
      if CaseEqual(name, 'await') and CurProcIsAsync then
      begin
        { `await E` as an expression. Binds tightly (a unary/primary operand, like
          Python) so `await f() + 1` is `(await f()) + 1`. STACKFUL: documentary —
          AN_AWAIT lowers straight to its operand; the awaited call suspends on its
          own via the reactor/CoYield. STACKLESS (later): the transform split point. }
        Next;
        ParseFactor;
        node := AllocNode(AN_AWAIT);
        ASTLeft[node] := CurASTNode;
        ASTTk[node]   := Ord(LastExprTk);
        CurASTNode := node;
        Exit;
      end;
      if isNilPy and (name = 'int') then
      begin
        Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
        node := AllocNode(AN_CALL); ASTIVal[node] := -200;
        ASTTk[node] := Ord(tyInteger);
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
        ASTLeft[node] := argSeq;
        CurASTNode := node;
        LastExprTk := tyInteger;
        Exit;
      end
      else if isNilPy and (name = 'str') then
      begin
        Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
        node := AllocNode(AN_CALL); ASTIVal[node] := -201;
        { str() lowers to StrInt/FloatToStr/VariantToStr, which return AnsiString
          in managed mode (the default) and frozen tyString under
          -uPXX_MANAGED_STRING. Tag to match so the write/store path treats the
          result as the right string kind. }
        if PasDefineExists('PXX_MANAGED_STRING') then
        begin
          ASTTk[node] := Ord(tyAnsiString); LastExprTk := tyAnsiString;
        end
        else
        begin
          ASTTk[node] := Ord(tyString); LastExprTk := tyString;
        end;
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
        ASTLeft[node] := argSeq;
        CurASTNode := node;
        Exit;
      end
      else if (CaseEqual(name, 'trunc') or CaseEqual(name, 'round') or
               CaseEqual(name, 'frac') or CaseEqual(name, 'int')) and
              (Tokens[TokPos].Kind = tkLParen) then
      begin
        { only a call `name(...)` is the float intrinsic; a bare identifier of the
          same name (e.g. the FRAC const) falls through to normal handling }
        { Float intrinsics via SSE conversions (specialId 203-206):
          Trunc -> Int64 (toward zero), Round -> Int64 (nearest-even),
          Frac/Int -> Double (fractional part / integer part as float). }
        if CaseEqual(name, 'trunc') then prevTok := -203
        else if CaseEqual(name, 'round') then prevTok := -204
        else if CaseEqual(name, 'frac') then prevTok := -205
        else prevTok := -206;
        Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
        node := AllocNode(AN_CALL); ASTIVal[node] := prevTok;
        if (prevTok = -203) or (prevTok = -204) then ASTTk[node] := Ord(tyInt64)
        else ASTTk[node] := Ord(tyDouble);
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
        ASTLeft[node] := argSeq;
        CurASTNode := node;
        LastExprTk := IntToTypeKind(ASTTk[node]);
        Exit;
      end;
      qUnit := ConsumeUnitQualifier(name);
      prevTok := TokPos - 1;
      if CaseEqual(name, 'inherited') then
      begin
        CurASTNode := ParseInheritedCallAST;
        LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
        Exit;
      end;
      { `TEnum.member` — scoped-enum member access (also legal on unscoped
        enums, FPC parity; bug-pascal-scopedenums-ignored). Folds to the
        member's ordinal. Guarded on the name not being a real symbol so a
        record var shadowing an enum type name keeps the field path. }
      if (qUnit < 0) and (CurTok.Kind = tkIdent) and (TokPos + 1 < TokCount) and
         (Tokens[TokPos].Kind = tkDot) and (Tokens[TokPos+1].Kind = tkIdent) and
         (FindSym(name) < 0) then
      begin
        seEtid := FindEnumType(name);
        if (seEtid >= 0) and
           FindEnumMemberOrd(seEtid, GetTokenStr(TokPos+1), seOrd) then
        begin
          Next; Next; Next;   { TEnum, '.', member }
          node := AllocNode(AN_INT_LIT);
          ASTIVal[node] := seOrd;
          ASTTk[node] := Ord(tyInteger);
          CurASTNode := node;
          LastExprTk := tyInteger;
          Exit;
        end;
      end;
      { ---- SizeOf(TypeName) intrinsic: resolved at parse time to AN_INT_LIT ---- }
      if CaseEqual(name, 'sizeof') then
      begin
        Next; { consume 'SizeOf' }
        Expect(tkLParen, '(');
        { Peek at the type token to determine the kind }
        name := CurTok.SVal;
        if CurTok.Kind = tkInteger_T then
        begin
          { 'Integer', 'LongInt', 'ShortInt', 'Byte', 'Word', 'SmallInt', 'Cardinal', 'LongWord' }
          if CaseEqual(name, 'shortint') then
            prevTok := TypeSize(tyInt8)
          else if CaseEqual(name, 'byte') then
            prevTok := TypeSize(tyUInt8)
          else if CaseEqual(name, 'smallint') then
            prevTok := TypeSize(tyInt16)
          else if CaseEqual(name, 'word') then
            prevTok := TypeSize(tyUInt16)
          else if CaseEqual(name, 'longint') or CaseEqual(name, 'integer') then
            prevTok := TypeSize(tyInt32)
          else if CaseEqual(name, 'cardinal') then
            prevTok := TypeSize(tyUInt32)
          else
            prevTok := TypeSize(tyInt32);  { default integer-family }
        end
        else if CurTok.Kind = tkLongWord_T then
          prevTok := TypeSize(tyUInt32)
        else if CurTok.Kind = tkBoolean_T then
          prevTok := TypeSize(tyUInt8)   { Boolean is 1 byte per FPC ObjFPC }
        else if CurTok.Kind = tkChar_T then
          prevTok := TypeSize(tyChar)
        else if CurTok.Kind = tkString_T then
          prevTok := TypeSize(tyString)
        else if CurTok.Kind = tkIdent then
        begin
          { Named type: check for known types by name }
          if CaseEqual(name, 'shortint') then
            prevTok := TypeSize(tyInt8)
          else if CaseEqual(name, 'byte') or CaseEqual(name, 'uint8') then
            prevTok := TypeSize(tyUInt8)
          else if CaseEqual(name, 'smallint') then
            prevTok := TypeSize(tyInt16)
          else if CaseEqual(name, 'word') or CaseEqual(name, 'uint16') then
            prevTok := TypeSize(tyUInt16)
          else if CaseEqual(name, 'longint') or CaseEqual(name, 'integer') then
            prevTok := TypeSize(tyInt32)
          else if CaseEqual(name, 'cardinal') or CaseEqual(name, 'longword') or CaseEqual(name, 'uint32') or CaseEqual(name, 'dword') then
            prevTok := TypeSize(tyUInt32)
          else if CaseEqual(name, 'int64') then
            prevTok := TypeSize(tyInt64)
          else if CaseEqual(name, 'qword') or CaseEqual(name, 'uint64') then
            prevTok := TypeSize(tyUInt64)
          else if CaseEqual(name, 'nativeint') or CaseEqual(name, 'ptrint') then
            prevTok := TypeSize(tyNativeInt)
          else if CaseEqual(name, 'nativeuint') or CaseEqual(name, 'ptruint') then
            prevTok := TypeSize(tyNativeUInt)
          else if CaseEqual(name, 'pointer') then
            prevTok := TypeSize(tyPointer)
          else if CaseEqual(name, 'boolean') then
            prevTok := TypeSize(tyUInt8)
          else if CaseEqual(name, 'char') or CaseEqual(name, 'ansichar') then
            prevTok := TypeSize(tyChar)
          else if CaseEqual(name, 'ansistring') or
                  CaseEqual(name, 'unicodestring') or CaseEqual(name, 'widestring') then
          begin
            if PasDefineExists('PXX_MANAGED_STRING') then
              prevTok := TypeSize(tyAnsiString)
            else
              prevTok := TypeSize(tyString);
          end
          else if CaseEqual(name, 'string') then
            prevTok := TypeSize(tyString)
          else
          begin
            { Try record/class type. A user `type X = ...` alias SHADOWS a
              same-named builtin descriptor record (the compiler exposes
              internal RTTI records like TProc/TParam under common names —
              see ParseTypeKind's identical guard) — only accept the record
              match if no user alias claims the same name, otherwise fall
              through to the alias branch below. }
            idx := IsRecordType(name);
            if idx = REC_NONE then
            begin
              ci := FindUClass(name);
              if ci >= 0 then
                idx := REC_UCLASS_BASE + ci;
            end;
            if (idx <> REC_NONE) and (FindTypeAlias(name) < 0) then
              prevTok := RecSize(idx)
            else
            begin
              { Named array type (`TArr = array[..] of T` / `array of T`):
                mirrors ParseVarSection's FindArrayType check, which resolves
                this BEFORE falling into ParseTypeKind's alias/enum lookup --
                so it must be tried here too, ahead of FindTypeAlias/
                FindEnumType below. A dynamic-array alias is a reference
                (handle), so its SizeOf is just the pointer width, same as
                any other managed handle. }
              szAi := FindArrayType(name);
              if szAi >= 0 then
              begin
                if ArrTypeIsDyn[szAi] then
                  prevTok := TARGET_PTR_SIZE
                else
                begin
                  if ArrTypeNDims[szAi] >= 2 then
                  begin
                    szFlatLen := 1;
                    for szDi := 0 to ArrTypeNDims[szAi] - 1 do
                      szFlatLen := szFlatLen * ArrTypeDimSpan[szAi * MAX_ARR_DIMS + szDi];
                  end
                  else
                    szFlatLen := ArrTypeHi[szAi] - ArrTypeLo[szAi] + 1;
                  szElemTk := IntToTypeKind(ArrTypeElemTk[szAi]);
                  if (szElemTk = tyRecord) and (ArrTypeElemRec[szAi] >= 0) then
                    prevTok := RecSize(ArrTypeElemRec[szAi]) * szFlatLen
                  else
                    prevTok := TypeSize(szElemTk) * szFlatLen;
                end;
              end
              else
              begin
                { Named type alias (integer/pointer/set/enum/proc-type alias --
                  anything ParseTypeKind resolves via FindTypeAlias/
                  FindEnumType for a `var x: T` declaration) or a named enum
                  type. Mirrors ParseTypeKind's tkIdent branch so `SizeOf(T)`
                  accepts the same type names a variable declaration does
                  (bug-sizeof-array-and-typename-wrong, symptom 2). }
                aliasIdx := FindTypeAlias(name);
                if aliasIdx >= 0 then
                begin
                  if AliasTk[aliasIdx] = Ord(tyRecord) then
                    prevTok := RecSize(AliasElemRec[aliasIdx])   { e.g. method-pointer-of-object alias }
                  else
                    prevTok := TypeSize(IntToTypeKind(AliasTk[aliasIdx]));
                end
                else if FindEnumType(name) >= 0 then
                  prevTok := TypeSize(tyInteger)   { enums are ordinal/integer-sized, cf. ParseTypeKind }
                else
                begin
                  { Not a type name — accept a VARIABLE operand (FPC/Delphi allow
                    SizeOf(v) = size of v's declared type, not just SizeOf(Type)).
                    A record-by-value var uses its record size; everything else its
                    scalar type size (TypeSize returns pointer width for class/
                    pointer references). }
                  sci := FindSym(name);
                  if sci >= 0 then
                  begin
                    if (Tokens[TokPos].Kind = tkDot) and (Syms[sci].RecName >= 0) and
                       (not Syms[sci].IsArray) then
                    begin
                      { SizeOf(obj.field[.field..]) — walk the selector chain
                        (never evaluating, like every SizeOf operand) and
                        report the FINAL field's size (blcksock's
                        SizeOf(Value.Value)). Scalar/record/class fields; an
                        array field is out of scope and errors below. }
                      szRec := Syms[sci].RecName;
                      szElemTk := tyUnknown;
                      Next;   { consume the identifier; CurTok = '.' }
                      while CurTok.Kind = tkDot do
                      begin
                        Next;   { consume '.'; CurTok = field name }
                        if CurTok.Kind <> tkIdent then Error('SizeOf: expected field name');
                        szElemTk := RecFieldType(szRec, CurTok.SVal);
                        if szElemTk = tyUnknown then Error('SizeOf: unknown field');
                        szRec := RecFieldRecId(szRec, CurTok.SVal);
                        if Tokens[TokPos].Kind = tkDot then Next;   { deeper chain }
                      end;
                      { CurTok = the last field name; the shared trailing Next
                        below moves past it to the ')'. }
                      if (szElemTk = tyRecord) and (szRec >= 0) then
                        prevTok := RecSize(szRec)
                      else
                        prevTok := TypeSize(szElemTk);
                    end
                    else if Syms[sci].IsArray and (Tokens[TokPos].Kind = tkLBrack) and
                       (SymArrNDims[sci] <= 1) then
                    begin
                      { SizeOf(arr[i]): the index expression's VALUE is never
                        evaluated by SizeOf (exactly like a type name's own
                        contents) -- skip the balanced brackets and report
                        the array's ELEMENT size, so the common idiom
                        `SizeOf(arr) div SizeOf(arr[0])` (element count)
                        works (bug-sizeof-array-and-typename-wrong, the
                        remaining symptom-2 gap). Only one level of
                        indexing on a genuinely 1-D array; a chained
                        `arr[i].field` is out of scope, and an N-D array
                        (SymArrNDims >= 2) needs its own row/sub-array
                        accounting depending on how many indices are given
                        (`m[0]` is a row, `m[0,1]` is a scalar) -- rather
                        than silently reporting the wrong (scalar) size,
                        that case falls through to the "unknown" error
                        below by NOT matching this guard. }
                      Next;                { consume the identifier; CurTok = '[' }
                      Next;                { consume '['; CurTok = start of index expr }
                      szBrDepth := 1;
                      while (szBrDepth > 0) and (CurTok.Kind <> tkEOF) do
                      begin
                        if CurTok.Kind = tkLBrack then Inc(szBrDepth)
                        else if CurTok.Kind = tkRBrack then Dec(szBrDepth);
                        if szBrDepth > 0 then Next;
                      end;
                      { CurTok = ']'; the shared trailing Next below moves past
                        it to the enclosing SizeOf(...)'s ')'. }
                      if (Syms[sci].ElemType = tyRecord) and (Syms[sci].ElemRecName >= 0) then
                        prevTok := RecSize(Syms[sci].ElemRecName)
                      else
                        prevTok := TypeSize(Syms[sci].ElemType);
                    end
                    else if Syms[sci].IsArray and (Tokens[TokPos].Kind = tkLBrack) then
                    begin
                      { SizeOf(m[i]) / SizeOf(m[i,j,..]) on a genuine N-D fixed
                        array (SymArrNDims[sci] >= 2 -- the <= 1 case is
                        handled above): mirrors the two subscript forms real
                        indexing supports (BuildPartialNDRowIndex /
                        BuildFlatNDIndex) -- a single subscript names a whole
                        row (sub-array), one subscript per dimension names a
                        scalar element. Indices are never evaluated (same
                        rationale as the 1-D case above), so just count
                        top-level commas while skipping the balanced
                        brackets. }
                      Next;                { consume the identifier; CurTok = '[' }
                      Next;                { consume '['; CurTok = start of first index expr }
                      szBrDepth := 1; szNIdx := 1;
                      while (szBrDepth > 0) and (CurTok.Kind <> tkEOF) do
                      begin
                        if CurTok.Kind = tkLBrack then Inc(szBrDepth)
                        else if CurTok.Kind = tkRBrack then Dec(szBrDepth)
                        else if (CurTok.Kind = tkComma) and (szBrDepth = 1) then Inc(szNIdx);
                        if szBrDepth > 0 then Next;
                      end;
                      { CurTok = ']'; the shared trailing Next below moves past
                        it to the enclosing SizeOf(...)'s ')'. }
                      szBase := sci * MAX_ARR_DIMS;
                      if szNIdx = 1 then
                      begin
                        szFlatLen := 1;
                        for szDi := 1 to SymArrNDims[sci] - 1 do
                          szFlatLen := szFlatLen * SymArrDimSpan[szBase + szDi];
                        if (Syms[sci].ElemType = tyRecord) and (Syms[sci].ElemRecName >= 0) then
                          prevTok := RecSize(Syms[sci].ElemRecName) * szFlatLen
                        else
                          prevTok := TypeSize(Syms[sci].ElemType) * szFlatLen;
                      end
                      else if szNIdx = SymArrNDims[sci] then
                      begin
                        if (Syms[sci].ElemType = tyRecord) and (Syms[sci].ElemRecName >= 0) then
                          prevTok := RecSize(Syms[sci].ElemRecName)
                        else
                          prevTok := TypeSize(Syms[sci].ElemType);
                      end
                      else
                      begin
                        Error('SizeOf: wrong number of array subscripts');
                        prevTok := 0;
                      end;
                    end
                    else if Syms[sci].IsArray then
                    begin
                      { Array symbols store the ELEMENT type in TypeKind/ElemType
                        (a recurring landmine throughout this codebase), so the
                        aggregate size is elementSize * ArrLen (ArrLen already
                        holds the flattened element count for N-D arrays too --
                        see bug-sizeof-array-and-typename-wrong). }
                      if (Syms[sci].ElemType = tyRecord) and (Syms[sci].ElemRecName >= 0) then
                        prevTok := RecSize(Syms[sci].ElemRecName) * Syms[sci].ArrLen
                      else
                        prevTok := TypeSize(Syms[sci].ElemType) * Syms[sci].ArrLen;
                    end
                    else if (Syms[sci].TypeKind = tyRecord) and (Syms[sci].RecName >= 0) then
                      prevTok := RecSize(Syms[sci].RecName)
                    else
                      prevTok := TypeSize(Syms[sci].TypeKind);
                  end
                  else
                  begin
                    Error('SizeOf: unknown type or variable');
                    prevTok := 0;
                  end;
                end;
              end;
            end;
          end;
        end
        else
        begin
          Error('SizeOf: expected type name');
          prevTok := 0;
        end;
        Next; { consume type token }
        Expect(tkRParen, ')');
        node := AllocNode(AN_INT_LIT);
        ASTIVal[node] := prevTok;
        ASTTk[node] := Ord(tyInteger);
        CurASTNode := node;
        Exit;
      end;

      if CaseEqual(name, '__pxxrawsyscall') then
      begin
        { Raw syscall intrinsic: lowered to the target's native syscall
          instruction. First arg = syscall number, then up to 6 arguments. }
        Next; { consume '__pxxrawsyscall' }
        Expect(tkLParen, '(');
        node := AllocNode(AN_SYSCALL);
        ASTTk[node] := Ord(tyInt64);
        lastArg := -1;
        nArgs := 0;
        repeat
          ParseExpr;
          exprNode := CurASTNode;
          argSeq := AllocNode(AN_ARG);
          ASTLeft[argSeq] := exprNode;
          if lastArg = -1 then
            ASTLeft[node] := argSeq
          else
            ASTRight[lastArg] := argSeq;
          lastArg := argSeq;
          Inc(nArgs);
        until not Eat(tkComma);
        Expect(tkRParen, ')');
        if nArgs > 7 then Error('__pxxrawsyscall: at most 7 arguments (nr + 6)');
        LastExprTk := tyInt64;
        CurASTNode := node;
        Exit;
      end;

      if CaseEqual(name, '__pxxcoswitch') then
      begin
        { Low-level coroutine context switch: __pxxcoswitch(pfrom, pto: Pointer).
          Both args are the addresses of the from/to TCoroCtx records. Lowers to
          a call to the bare CoSwitch runtime stub. }
        Next; { consume '__pxxcoswitch' }
        Expect(tkLParen, '(');
        node := AllocNode(AN_COSWITCH);
        ASTTk[node] := Ord(tyPointer);
        lastArg := -1;
        nArgs := 0;
        repeat
          ParseExpr;
          exprNode := CurASTNode;
          argSeq := AllocNode(AN_ARG);
          ASTLeft[argSeq] := exprNode;
          if lastArg = -1 then
            ASTLeft[node] := argSeq
          else
            ASTRight[lastArg] := argSeq;
          lastArg := argSeq;
          Inc(nArgs);
        until not Eat(tkComma);
        Expect(tkRParen, ')');
        if nArgs <> 2 then Error('__pxxcoswitch: expects exactly 2 arguments (pfrom, pto)');
        LastExprTk := tyPointer;
        CurASTNode := node;
        Exit;
      end;

      if CaseEqual(name, '__pxxclone') then
      begin
        { Libc-free thread spawn: __pxxclone(flags, childStack, entry, arg, ctidptr).
          Lowers to a call to the bare clone+trampoline stub. Returns the child tid
          (Int64) in the parent; never returns in the child. }
        Next; { consume '__pxxclone' }
        { Thread spawn requires the thread-safe runtime: without --threadsafe the
          heap allocator, ARC refcounts and console I/O have no locking, so any
          allocation/writeln from a second thread corrupts shared state. Fail at
          compile time, not as a heisencrash (feature-threadsafe-heap-contract). }
        if not ThreadSafeMode then
          Error('__pxxclone (thread creation) requires --threadsafe or {$threadsafe on}: the default heap/ARC/console-I/O runtime is not thread-safe');
        { The clone+trampoline stub is emitted lazily (jmp-over) at the first IR_CLONE
          codegen — see EnsureCloneStub — so nothing to arrange here. }
        Expect(tkLParen, '(');
        node := AllocNode(AN_CLONE);
        ASTTk[node] := Ord(tyInt64);
        lastArg := -1;
        nArgs := 0;
        repeat
          ParseExpr;
          exprNode := CurASTNode;
          argSeq := AllocNode(AN_ARG);
          ASTLeft[argSeq] := exprNode;
          if lastArg = -1 then
            ASTLeft[node] := argSeq
          else
            ASTRight[lastArg] := argSeq;
          lastArg := argSeq;
          Inc(nArgs);
        until not Eat(tkComma);
        Expect(tkRParen, ')');
        if nArgs <> 5 then Error('__pxxclone: expects exactly 5 arguments (flags, childStack, entry, arg, ctidptr)');
        LastExprTk := tyInt64;
        CurASTNode := node;
        Exit;
      end;

      if CaseEqual(name, '__pxxatomic_xchg') or CaseEqual(name, '__pxxatomic_cas')
         or CaseEqual(name, '__pxxatomic_add')
         or CaseEqual(name, '__pxxatomic_xchg64') or CaseEqual(name, '__pxxatomic_cas64')
         or CaseEqual(name, '__pxxatomic_add64') then
      begin
        { Atomic read-modify-write on addr^, returning the OLD value:
            __pxxatomic_xchg(addr, val)            *addr := val
            __pxxatomic_cas (addr, expected, newv)  if *addr=expected then *addr:=newv
            __pxxatomic_add (addr, delta)           *addr := *addr + delta
          The plain names are 32-bit ops; the *64 variants are full-width
          (Int64 counters / pointer-sized slots). The op is baked at parse
          time; lowers to IR_ATOMIC. }
        node := AllocNode(AN_ATOMIC);
        ASTTk[node] := Ord(tyInt64);
        if CaseEqual(name, '__pxxatomic_xchg') then ASTIVal[node] := ATOMIC_XCHG
        else if CaseEqual(name, '__pxxatomic_cas') then ASTIVal[node] := ATOMIC_CAS
        else if CaseEqual(name, '__pxxatomic_add') then ASTIVal[node] := ATOMIC_ADD
        else if CaseEqual(name, '__pxxatomic_xchg64') then ASTIVal[node] := ATOMIC_XCHG64
        else if CaseEqual(name, '__pxxatomic_cas64') then ASTIVal[node] := ATOMIC_CAS64
        else ASTIVal[node] := ATOMIC_ADD64;
        Next; { consume the intrinsic name }
        Expect(tkLParen, '(');
        lastArg := -1;
        nArgs := 0;
        repeat
          ParseExpr;
          exprNode := CurASTNode;
          argSeq := AllocNode(AN_ARG);
          ASTLeft[argSeq] := exprNode;
          if lastArg = -1 then
            ASTLeft[node] := argSeq
          else
            ASTRight[lastArg] := argSeq;
          lastArg := argSeq;
          Inc(nArgs);
        until not Eat(tkComma);
        Expect(tkRParen, ')');
        if (ASTIVal[node] = ATOMIC_CAS) or (ASTIVal[node] = ATOMIC_CAS64) then
        begin
          if nArgs <> 3 then Error('__pxxatomic_cas: expects 3 arguments (addr, expected, newval)');
        end
        else if nArgs <> 2 then Error('__pxxatomic_xchg/add: expects 2 arguments (addr, val)');
        LastExprTk := tyInt64;
        CurASTNode := node;
        Exit;
      end;

      if CaseEqual(name, '__resources') then
      begin
        Next; { consume '__resources' }
        if CurTok.Kind = tkLParen then
        begin
          Next;
          Expect(tkRParen, ')');
        end;
        node := AllocNode(AN_RESOURCES);
        ASTTk[node] := Ord(tyPointer);
        CurASTNode := node;
        Exit;
      end;

      if CaseEqual(name, '__rttireg') then
      begin
        Next; { consume '__rttireg' }
        if CurTok.Kind = tkLParen then
        begin
          Next;
          Expect(tkRParen, ')');
        end;
        node := AllocNode(AN_RTTI_REG);
        ASTTk[node] := Ord(tyPointer);
        CurASTNode := node;
        Exit;
      end;

      if qUnit >= 0 then
      begin
        idx := FindSymInUnit(name, qUnit);
        procIdx := FindProcInUnit(name, qUnit);
      end
      else if qUnit = -2 then
      begin
        { `System.X`: the builtin/global must win over any same-named
          local/param — Synapse's `System.Length(buf)` inside
          SendBufferTo(...; Length: Integer). Leave idx unbound so the
          builtin branches below take the name. }
        idx := -1;
        procIdx := FindProc(name);
      end
      else
      begin
        idx := FindSym(name);
        procIdx := FindProc(name);
      end;

      if (idx >= 0) and (Syms[idx].TypeKind = tyAuto) then
        Error('use of auto variable before type is inferred');

      { FPC scoping: inside a method, the enclosing class's own method shadows
        a same-name plain proc from an outer/uses scope (innermost scope wins —
        sysutils.Move vs TGame.Move). Clearing procIdx routes the name to the
        implicit-Self dispatch below instead of plain-proc overload matching,
        which knows nothing of methods. A local var/param (idx >= 0) still
        shadows the method; a unit-qualified name (qUnit >= 0) stays explicit.
        See bug-implicit-self-method-loses-to-unit-proc. }
      if (procIdx >= 0) and (qUnit < 0) and (idx < 0) and
         (CurSelfClass >= REC_UCLASS_BASE) and
         (FindUMeth(CurSelfClass - REC_UCLASS_BASE, name) >= 0) then
        procIdx := -1;

      { `Eof` (standard input), no args -> Boolean. The textfile RTL declares
        `Eof(var f: Text)`, but a bare `Eof` / `Eof()` cannot bind that file arg,
        so the no-arg form routes to stdin Eof regardless of that proc; the
        `Eof(f)` form (a `(` followed by an argument) falls through to the real
        routine. `idx < 0` keeps a user variable named Eof winning as a var.
        Lowers to the special-builtin call id 210 (EmitEof). }
      if CaseEqual(name, 'Eof') and (idx < 0) and
         (Tokens[TokPos].Kind <> tkLParen) then
      begin
        Next;                                  { consume Eof }
        node := AllocNode(AN_CALL);
        ASTIVal[node] := -210;
        ASTTk[node] := Ord(tyBoolean);
        ASTLeft[node] := -1;
        CurASTNode := node;
        LastExprTk := tyBoolean;
        Exit;
      end;
      if CaseEqual(name, 'Eof') and (idx < 0) and
         (Tokens[TokPos].Kind = tkLParen) and (Tokens[TokPos + 1].Kind = tkRParen) then
      begin
        Next; Next; Next;                      { consume Eof ( ) }
        node := AllocNode(AN_CALL);
        ASTIVal[node] := -210;
        ASTTk[node] := Ord(tyBoolean);
        ASTLeft[node] := -1;
        CurASTNode := node;
        LastExprTk := tyBoolean;
        Exit;
      end;

      { `Supports(obj, IFoo): Boolean` — the function form of `obj is IFoo`.
        Reuses the interface implementation query (AN_IS_TEST). }
      if CaseEqual(name, 'Supports') and (procIdx < 0) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        ParseExpr; exprNode := CurASTNode;
        Expect(tkComma, ',');
        if CurTok.Kind <> tkIdent then Error('Supports: expected interface name');
        ci := FindUClass(CurTok.SVal);
        if (ci < 0) or not UClsIsInterface[ci] then Error('Supports: second argument must be an interface');
        Next;
        Expect(tkRParen, ')');
        node := AllocNode(AN_IS_TEST);
        ASTLeft[node] := exprNode; ASTIVal[node] := ci; ASTTk[node] := Ord(tyBoolean);
        CurASTNode := node; LastExprTk := tyBoolean;
        Exit;
      end;

      { GetMem(size): function form, soft keyword (statement form GetMem(p, n)
        lives in ParseStatementAST). }
      if CaseEqual(name, 'GetMem') and (procIdx < 0) and (FindSym(name) < 0) and
         (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        ParseExpr;
        valNode := CurASTNode;
        Expect(tkRParen, ')');
        node := AllocNode(AN_CALL); ASTIVal[node] := -Ord(tkGetMem);
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := valNode;
        ASTLeft[node] := argSeq;
        CurASTNode := node;
        LastExprTk := tyPointer;
        Exit;
      end;

      { Ord(x)/Chr(x): soft-keyword intrinsics (same recipe as Length below —
        plain idents, name dispatch, user proc / in-scope symbol shadows,
        must be followed by '('). }
      if (CaseEqual(name, 'Ord') or CaseEqual(name, 'Chr')) and (procIdx < 0) and
         (FindSym(name) < 0) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        if CaseEqual(name, 'Chr') then
        begin op := Ord(tkChr); LastExprTk := tyChar; end
        else
        begin op := Ord(tkOrd); LastExprTk := tyInteger; end;
        Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
        node := AllocNode(AN_CALL); ASTIVal[node] := -op;
        if op = Ord(tkChr) then ASTTk[node] := Ord(tyChar) else ASTTk[node] := Ord(tyInteger);
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
        ASTLeft[node] := argSeq;
        CurASTNode := node;
        Exit;
      end;

      { High(x): soft-keyword intrinsic. High(arr) := Length(arr) - 1 — reuses
        the Length call + a subtraction, so no new IR/codegen; works for open
        arrays, dyn arrays and (via the folds) static arrays alike. }
      if CaseEqual(name, 'High') and (procIdx < 0) and (FindSym(name) < 0) and
         (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        { High(ordinalType) / High(enum) folds to a compile-time constant. }
        if TryFoldHighLowType(True, node) then
        begin
          Expect(tkRParen, ')');
          CurASTNode := node;
          Exit;
        end;
        if CurTok.Kind <> tkIdent then Error('High: expected array variable or ordinal type');
        idx := FindSym(CurTok.SVal); Next;
        { See Length below: ParseLValueAST handles implicit-Self + undefined. }
        valNode := ParseLValueAST(idx, TokPos - 2);
        Expect(tkRParen, ')');
        { High of a whole 1-D static array folds to its upper index bound (see
          the Length fold below for why the runtime path can't serve a static
          array). The lower bound is in Syms[].ConstVal (0 for a 0-based
          array), so the upper bound is ConstVal + count - 1 — NOT count - 1,
          which silently miscompiled non-zero-based arrays (array[5..9] -> 4
          instead of 9). }
        if (idx >= 0) and (ASTKind[valNode] = AN_IDENT) and (ASTIVal[valNode] = idx) and
           Syms[idx].IsArray and (Syms[idx].ArrLen >= 0) and (Syms[idx].Kind <> skParam) and
           (SymArrNDims[idx] <= 1) then
        begin
          CurASTNode := AllocNode(AN_INT_LIT);
          ASTIVal[CurASTNode] := Syms[idx].ConstVal + Syms[idx].ArrLen - 1; ASTTk[CurASTNode] := Ord(tyInteger);
        end
        else if (ASTKind[valNode] = AN_FIELD) and
                RecFieldIsArray(ResolveNodeRec(ASTLeft[valNode]), GetASTIdentName(valNode)) and
                (RecFieldArrLen(ResolveNodeRec(ASTLeft[valNode]), GetASTIdentName(valNode)) >= 0) and
                (RecFieldDynDepth(ResolveNodeRec(ASTLeft[valNode]), GetASTIdentName(valNode)) = 0) then
        begin
          { High of a whole fixed-size record/class FIELD array folds like the
            plain-var case; the runtime Length path would read a [data-8]
            header a raw field has none of, so High(ctx.Buffer) returned
            garbage/-1 and synacode's SHA1 never zeroed its buffers. Field
            arrays record only their COUNT (low bound normalised to 0). }
          CurASTNode := AllocNode(AN_INT_LIT);
          ASTIVal[CurASTNode] :=
            RecFieldArrLen(ResolveNodeRec(ASTLeft[valNode]), GetASTIdentName(valNode)) - 1;
          ASTTk[CurASTNode] := Ord(tyInteger);
        end
        else
        begin
          node := AllocNode(AN_CALL); ASTIVal[node] := -Ord(tkLength); ASTTk[node] := Ord(tyInteger);
          argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := valNode;
          ASTLeft[node] := argSeq;
          valNode := AllocNode(AN_INT_LIT); ASTIVal[valNode] := 1; ASTTk[valNode] := Ord(tyInteger);
          CurASTNode := AllocNode(AN_BINOP);
          ASTIVal[CurASTNode] := Ord(tkMinus);
          ASTLeft[CurASTNode] := node; ASTRight[CurASTNode] := valNode;
          ASTTk[CurASTNode] := Ord(tyInteger);
        end;
        LastExprTk := tyInteger;
        Exit;
      end;

      { Low(x): soft-keyword intrinsic. Low(ordinalType)/Low(enum) folds to a
        compile-time constant. Low of an array variable is the declared lower
        index bound — Syms[].ConstVal for a 1-D static array (array[5..9] ->
        5); 0 for open/dynamic arrays and 0-based statics. }
      if CaseEqual(name, 'Low') and (procIdx < 0) and (FindSym(name) < 0) and
         (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        if TryFoldHighLowType(False, node) then
        begin
          Expect(tkRParen, ')');
          CurASTNode := node;
          Exit;
        end;
        if CurTok.Kind <> tkIdent then Error('Low: expected array variable or ordinal type');
        idx := FindSym(CurTok.SVal); Next;
        valNode := ParseLValueAST(idx, TokPos - 2);   { consume the array variable }
        Expect(tkRParen, ')');
        CurASTNode := AllocNode(AN_INT_LIT);
        if (idx >= 0) and Syms[idx].IsArray and (Syms[idx].Kind <> skParam) and
           (SymArrNDims[idx] <= 1) then
          ASTIVal[CurASTNode] := Syms[idx].ConstVal
        else
          ASTIVal[CurASTNode] := 0;
        ASTTk[CurASTNode] := Ord(tyInteger);
        LastExprTk := tyInteger;
        Exit;
      end;

      { Length(x): soft-keyword intrinsic (lexes as a plain ident, so `var
        length: ...` is a legal identifier like in FPC — pilot for
        bug-hard-keyword-intrinsics-block-identifier-use). A user routine of
        the same name shadows it, and a plain `length` not followed by `(`
        resolves as an ordinary identifier via the normal paths below. }
      if CaseEqual(name, 'Length') and (procIdx < 0) and
         ((qUnit = -2) or (FindSym(name) < 0)) and
         (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        { Length of a string LITERAL folds to its char count at compile time
          (FPC: Length('hello') = 5). Covers the common literal forms without
          the runtime [-8]-header path, which only an lvalue string/array has. }
        if CurTok.Kind = tkString then
        begin
          node := AllocNode(AN_INT_LIT);
          ASTIVal[node] := Length(CurTok.SVal); ASTTk[node] := Ord(tyInteger);
          Next; Expect(tkRParen, ')');
          CurASTNode := node;
          Exit;
        end;
        { Any string/array r-value: an lvalue (var/field/element) keeps the
          force-addressed [data-8] header read; a non-lvalue managed-string
          value (concat / function result) lowers as a value (IR side
          de-references the handle directly — see IsASTLValue gate in ir.inc). }
        ParseExpr;
        valNode := CurASTNode;
        Expect(tkRParen, ')');
        { Length of a whole 1-D static array is a compile-time constant (FPC
          too): the runtime -tkLength path reads a [data-8] length header,
          which only a dyn array / open-array param has — a bare static array
          has none. Params (incl. open arrays) and multi-dim keep the runtime
          path. }
        if (ASTKind[valNode] = AN_IDENT) and (ASTIVal[valNode] >= 0) and
           Syms[ASTIVal[valNode]].IsArray and (Syms[ASTIVal[valNode]].ArrLen >= 0) and
           (Syms[ASTIVal[valNode]].Kind <> skParam) and (SymArrNDims[ASTIVal[valNode]] <= 1) then
        begin
          node := AllocNode(AN_INT_LIT);
          ASTIVal[node] := Syms[ASTIVal[valNode]].ArrLen; ASTTk[node] := Ord(tyInteger);
          CurASTNode := node;
        end
        else
        begin
          node := AllocNode(AN_CALL); ASTIVal[node] := -Ord(tkLength); ASTTk[node] := Ord(tyInteger);
          argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := valNode;
          ASTLeft[node] := argSeq;
          CurASTNode := node;
        end;
        LastExprTk := tyInteger;
        Exit;
      end;

      { Succ(e)/Pred(e)/Odd(e): System ordinal intrinsics, folded to arithmetic
        (no `uses`, target-independent, the argument used exactly once so no
        double-eval). Succ -> e+1, Pred -> e-1, Odd -> (e and 1) = 1 (Boolean).
        A user routine of the same name (procIdx>=0) shadows. }
      if (CaseEqual(name, 'Succ') or CaseEqual(name, 'Pred')) and
         (procIdx < 0) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        ParseExpr; node := CurASTNode;
        Expect(tkRParen, ')');
        left := AllocNode(AN_INT_LIT); ASTIVal[left] := 1; ASTTk[left] := Ord(tyInteger);
        op := AllocNode(AN_BINOP);
        if CaseEqual(name, 'Succ') then ASTIVal[op] := Ord(tkPlus) else ASTIVal[op] := Ord(tkMinus);
        ASTLeft[op] := node; ASTRight[op] := left; ASTTk[op] := ASTTk[node];
        CurASTNode := op; LastExprTk := IntToTypeKind(ASTTk[node]);
        Exit;
      end;
      if CaseEqual(name, 'Odd') and (procIdx < 0) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        ParseExpr; node := CurASTNode;
        Expect(tkRParen, ')');
        left := AllocNode(AN_INT_LIT); ASTIVal[left] := 1; ASTTk[left] := Ord(tyInteger);
        op := AllocNode(AN_BINOP); ASTIVal[op] := Ord(tkAnd);
        ASTLeft[op] := node; ASTRight[op] := left; ASTTk[op] := Ord(tyInteger);
        left := AllocNode(AN_INT_LIT); ASTIVal[left] := 1; ASTTk[left] := Ord(tyInteger);
        CurASTNode := AllocNode(AN_BINOP); ASTIVal[CurASTNode] := Ord(tkEq);
        ASTLeft[CurASTNode] := op; ASTRight[CurASTNode] := left; ASTTk[CurASTNode] := Ord(tyBoolean);
        LastExprTk := tyBoolean;
        Exit;
      end;

      { CompareByte/CompareChar(b1, b2, len): System memcmp primitives ->
        the __pxxCompareByte builtin (byte-wise; Char is a byte here). Soft
        alias like the statement-side Move/FillChar: rename + re-resolve so
        the normal call machinery (untyped const params) does the rest. }
      if (CaseEqual(name, 'CompareByte') or CaseEqual(name, 'CompareChar')) and
         (procIdx < 0) and (idx < 0) and (Tokens[TokPos].Kind = tkLParen) and
         (FindProc('__pxxCompareByte') >= 0) and
         ((CurSelfClass < REC_UCLASS_BASE) or
          (FindUMeth(CurSelfClass - REC_UCLASS_BASE, name) < 0)) then
      begin
        name := '__pxxCompareByte';
        procIdx := FindProc(name);
      end;

      { IsManagedType(T): compile-time intrinsic — True when T is a
        refcounted/managed type. v1: string kinds and dynamic-array type
        names; everything else False. Name-based (the argument is a type). }
      if CaseEqual(name, 'IsManagedType') and (procIdx < 0) and (idx < 0) and
         (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        node := AllocNode(AN_BOOL_LIT);
        ASTIVal[node] := 0;
        if (CurTok.Kind = tkString_T) or
           ((CurTok.Kind = tkIdent) and (CaseEqual(CurTok.SVal, 'ansistring') or
             (FindArrayType(CurTok.SVal) >= 0))) then
          ASTIVal[node] := 1;
        ASTTk[node] := Ord(tyBoolean);
        i := 1;
        while (i > 0) and (CurTok.Kind <> tkEOF) do
        begin
          if CurTok.Kind = tkLParen then Inc(i)
          else if CurTok.Kind = tkRParen then Dec(i);
          if i > 0 then Next;
        end;
        Expect(tkRParen, ')');
        CurASTNode := node;
        LastExprTk := tyBoolean;
        Exit;
      end;

      { Assigned(p): System intrinsic -> p <> nil (pointer/class/proc-var).
        Same eval-once inline shape as Succ/Pred/Odd; a user symbol shadows. }
      if CaseEqual(name, 'Assigned') and (procIdx < 0) and (idx < 0) and
         (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        ParseExpr; node := CurASTNode;
        Expect(tkRParen, ')');
        left := AllocNode(AN_INT_LIT); ASTIVal[left] := 0; ASTTk[left] := Ord(tyPointer);
        CurASTNode := AllocNode(AN_BINOP); ASTIVal[CurASTNode] := Ord(tkNeq);
        ASTLeft[CurASTNode] := node; ASTRight[CurASTNode] := left; ASTTk[CurASTNode] := Ord(tyBoolean);
        LastExprTk := tyBoolean;
        Exit;
      end;

      { UpCase(c): System intrinsic -> __pxxUpCase helper (Char->Char, eval-once). }
      if CaseEqual(name, 'UpCase') and (procIdx < 0) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        ParseExpr; node := CurASTNode;
        Expect(tkRParen, ')');
        helperPi := FindProc('__pxxUpCase');
        if helperPi < 0 then Error('UpCase: builtin helper unavailable (needs the builtin unit; not on ESP)');
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := node;
        CurASTNode := AllocNode(AN_CALL); ASTIVal[CurASTNode] := helperPi;
        ASTLeft[CurASTNode] := argSeq; ASTTk[CurASTNode] := Ord(tyChar);
        LastExprTk := tyChar;
        Exit;
      end;

      { Pos(sub, s): System substring search -> __pxxPos helper (1-based, 0 if not
        found). A `uses sysutils` Pos or any user routine shadows (procIdx>=0). }
      if CaseEqual(name, 'Pos') and (procIdx < 0) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        ParseExpr; node := CurASTNode;
        Expect(tkComma, ',');
        ParseExpr; op := CurASTNode;
        Expect(tkRParen, ')');
        helperPi := FindProc('__pxxPos');
        if helperPi < 0 then Error('Pos: builtin helper unavailable (needs the builtin unit; not on ESP)');
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := node;
        left := AllocNode(AN_ARG); ASTLeft[left] := op; ASTRight[argSeq] := left;
        CurASTNode := AllocNode(AN_CALL); ASTIVal[CurASTNode] := helperPi;
        ASTLeft[CurASTNode] := argSeq; ASTTk[CurASTNode] := Ord(tyInteger);
        LastExprTk := tyInteger;
        Exit;
      end;

      { Abs(e)/Sqr(e): System intrinsics lowered to builtin helpers (eval-once;
        int and float variants by the argument type). No `uses`; user routine of
        the same name shadows. ESP (no builtin unit) errors with a clear message. }
      if (CaseEqual(name, 'Abs') or CaseEqual(name, 'Sqr')) and
         (procIdx < 0) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        ParseExpr; node := CurASTNode;
        Expect(tkRParen, ')');
        if TypeIsFloat(IntToTypeKind(ASTTk[node])) then
        begin
          if CaseEqual(name, 'Abs') then helperPi := FindProc('__pxxAbsDbl')
          else helperPi := FindProc('__pxxSqrDbl');
        end
        else
        begin
          if CaseEqual(name, 'Abs') then helperPi := FindProc('__pxxAbsInt')
          else helperPi := FindProc('__pxxSqrInt');
        end;
        if helperPi < 0 then Error(name + ': builtin helper unavailable (needs the builtin unit; not on ESP)');
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := node;
        CurASTNode := AllocNode(AN_CALL); ASTIVal[CurASTNode] := helperPi;
        ASTLeft[CurASTNode] := argSeq;
        if TypeIsFloat(IntToTypeKind(ASTTk[node])) then ASTTk[CurASTNode] := Ord(tyDouble)
        else if CaseEqual(name, 'Abs') then ASTTk[CurASTNode] := ASTTk[node]
        else ASTTk[CurASTNode] := Ord(tyInt64);
        LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
        Exit;
      end;

      { Concat(s1, s2, ..., sn): the System string-concatenation intrinsic, just
        chained `+`. Folded here so it needs no `uses` and reuses the working
        string-concat codegen. A user `Concat` (procIdx>=0) shadows it. }
      if CaseEqual(name, 'Concat') and (procIdx < 0) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        ParseExpr; node := CurASTNode;
        while Eat(tkComma) do
        begin
          ParseExpr;
          left := AllocNode(AN_BINOP);
          ASTIVal[left] := Ord(tkPlus);
          ASTLeft[left] := node; ASTRight[left] := CurASTNode;
          ASTTk[left] := Ord(tyAnsiString);
          node := left;
        end;
        Expect(tkRParen, ')');
        CurASTNode := node;
        LastExprTk := tyAnsiString;
        Exit;
      end;

      { Generic dynamic-array Copy(arr, index [, count]) intrinsic, when no Copy
        function is in scope (a string `sysutils.Copy` keeps the proc path; that
        case, and Copy(dynarray) shadowed by a string Copy, are handled at the
        no-overload-match point below). Lowered into a fresh element-type-aware
        `array of T` via AN_DYN_COPY. }
      if CaseEqual(name, 'Copy') and (procIdx < 0) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        ParseExpr; exprNode := CurASTNode;            { source array }
        Expect(tkComma, ',');
        ParseExpr; node := CurASTNode;                { index }
        addrNode := -1;
        if Eat(tkComma) then begin ParseExpr; addrNode := CurASTNode; end;  { count }
        Expect(tkRParen, ')');
        if (ASTKind[exprNode] = AN_IDENT) and (ASTIVal[exprNode] >= 0) and
           Syms[ASTIVal[exprNode]].IsArray and (Syms[ASTIVal[exprNode]].ArrLen = -1) then
        begin
          if addrNode = -1 then
          begin
            addrNode := AllocNode(AN_INT_LIT);
            ASTIVal[addrNode] := 2147483647; ASTTk[addrNode] := Ord(tyInteger);
          end;
          argSeq := AllocNode(AN_DYN_COPY);
          ASTLeft[argSeq] := exprNode;
          lastArg := AllocNode(AN_ARG); ASTLeft[lastArg] := node;
          ci := AllocNode(AN_ARG); ASTLeft[ci] := addrNode;
          ASTRight[lastArg] := ci;
          ASTRight[argSeq] := lastArg;
          { Pointer-typed: the result is a dyn-array handle, so the assignment
            stores all 8 bytes (an element-typed tag would truncate it). }
          ASTTk[argSeq] := Ord(tyPointer);
          CurASTNode := argSeq;
          Exit;
        end;
        { String first argument: bare `Copy(s, index[, count])` lowers to the
          __pxxStrCopy substring helper (builtin unit, pulled by the pre-scan), so
          string Copy needs no `uses sysutils`. 2-arg form -> count = rest (huge,
          clamped to the end by the helper). The lib `sysutils.Copy` keeps the
          explicit-uses overload path. }
        ci := FindProc('__pxxStrCopy');
        if (ci >= 0) and (IntToTypeKind(ASTTk[exprNode]) in [tyString, tyAnsiString, tyFixedString]) then
        begin
          if addrNode = -1 then
          begin
            addrNode := AllocNode(AN_INT_LIT);
            ASTIVal[addrNode] := 2147483647; ASTTk[addrNode] := Ord(tyInteger);
          end;
          argSeq := AllocNode(AN_CALL);
          ASTIVal[argSeq] := ci;
          ASTTk[argSeq] := Ord(tyAnsiString);
          lastArg := AllocNode(AN_ARG); ASTLeft[lastArg] := exprNode;       { s }
          ASTLeft[argSeq] := lastArg;
          ci := AllocNode(AN_ARG); ASTLeft[ci] := node;                     { index }
          ASTRight[lastArg] := ci;
          lastArg := AllocNode(AN_ARG); ASTLeft[lastArg] := addrNode;       { count }
          ASTRight[ci] := lastArg;
          CurASTNode := argSeq;
          LastExprTk := tyAnsiString;
          Exit;
        end;
        Error('Copy: dynamic-array Copy needs a dynamic-array first argument ' +
              '(string Copy needs the strutils/sysutils unit)');
      end;

      { Indirect call through a procedural-type variable: v(args) as an expression. }
      if (idx >= 0) and (SymProcSig[idx] >= 0) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        node := ParseProcVarCallAST(idx, SymProcSig[idx]);
        CurASTNode := node;
        LastExprTk := IntToTypeKind(ASTTk[node]);
        Exit;
      end;

      { Class typecast as an expression: TClass(expr). A hard reinterpret (no
        runtime check, unlike `as`); classes are pointers so the value is
        unchanged, only the static type. Tagged AN_CLASS_CAST so a trailing
        .field / [i] resolves its offset against TClass (ResolveNodeRec maps the
        node to the class record). Must precede the pointer-alias cast below,
        which would otherwise mis-handle a class name as a plain pointer cast and
        resolve every field at offset 0. Field reads and writes both work via the
        class-typed AN_FIELD base path in IRLowerAddress. }
      if (idx < 0) and (procIdx < 0) and IsClassType(name) and
         (Tokens[TokPos].Kind = tkLParen) then
      begin
        ci := FindUClass(name);
        Next;                  { consume class name }
        Expect(tkLParen, '(');
        ParseExpr;
        Expect(tkRParen, ')');
        node := AllocNode(AN_CLASS_CAST);
        ASTLeft[node] := CurASTNode;
        ASTIVal[node] := ci;
        ASTTk[node]   := Ord(tyClass);
        tk := tyClass;
        if CurTok.Kind in [tkDot, tkLBrack] then
          node := ParseClassRecordSelectors(node, REC_UCLASS_BASE + ci, tk);
        CurASTNode := node;
        LastExprTk := tk;
        Exit;
      end;

      { TObject(expr) — cast to the IMPLICIT root class (no UCls row exists for
        the builtin TObject unless the user declared one, which the branch
        above catches). Classes are pointers, so this is a pure static retag;
        the value then feeds `is` / `as` / class casts (blcksock's
        `TObject(SocketList[n]) is TBlockSocket`). No member selectors — the
        root has none. }
      if (idx < 0) and (procIdx < 0) and (Tokens[TokPos].Kind = tkLParen) and
         CaseEqual(name, 'TObject') and (FindUClass(name) < 0) then
      begin
        Next;                  { consume 'TObject' }
        Expect(tkLParen, '(');
        ParseExpr;
        Expect(tkRParen, ')');
        ASTTk[CurASTNode] := Ord(tyClass);
        LastExprTk := tyClass;
        Exit;
      end;

      { Record-name reinterpret cast: TRec(ptr)^.field. Treats TRec(ptr) as a
        pointer reinterpret whose pointee is the record TRec, then handles the
        trailing ^ / .field / [i] (mirrors the pointer-alias path). A class name
        already went to AN_CLASS_CAST above; a record name is not a type alias so
        it would otherwise fall through to "unexpected token". }
      if (idx < 0) and (procIdx < 0) and (Tokens[TokPos].Kind = tkLParen) and
         (IsRecordType(name) >= REC_UCLASS_BASE) then
      begin
        baseRec := IsRecordType(name);
        Next;                  { consume record type name }
        Expect(tkLParen, '(');
        ParseExpr;
        Expect(tkRParen, ')');
        node := AllocNode(AN_PTR_CAST);
        ASTLeft[node] := CurASTNode;
        ASTIVal[node] := 0;          { plain pointer reinterpret (no char +8 adapter) }
        ASTTk[node]   := Ord(tyPointer);
        tk := tyPointer; recName := baseRec;
        while CurTok.Kind in [tkCaret, tkDot, tkLBrack] do
        begin
          if CurTok.Kind = tkCaret then
          begin
            Next;
            indexNode := AllocNode(AN_DEREF);
            ASTLeft[indexNode] := node;
            { Carry the pointee record id on the deref node so ResolveNodeRec
              (AN_DEREF, ASTIVal>0 path) resolves trailing .field offsets. }
            ASTIVal[indexNode] := baseRec;
            tk := tyRecord; recName := baseRec;
            ASTTk[indexNode] := Ord(tyRecord);
            node := indexNode;
          end
          else if CurTok.Kind = tkLBrack then
          begin
            Next;
            indexNode := AllocNode(AN_INDEX);
            ASTLeft[indexNode] := node;
            ParseExpr;
            ASTRight[indexNode] := CurASTNode;
            Expect(tkRBrack, ']');
            tk := tyRecord; recName := baseRec;
            ASTTk[indexNode] := Ord(tyRecord);
            node := indexNode;
          end
          else { tkDot }
          begin
            Next;
            if CurTok.Kind in [tkEOF, tkSemicolon, tkAssign, tkRBrack, tkRParen] then
              Error('expected field name after .');
            prevTok := TokPos - 1;
            fieldName := '';
            for i := Tokens[prevTok].SOffset to Tokens[prevTok].SOffset + Tokens[prevTok].SLen - 1 do
              AppendChar(fieldName, TokChars[i]);
            fieldNode := AllocNode(AN_FIELD);
            ASTLeft[fieldNode] := node;
            ASTSOffset[fieldNode] := Tokens[prevTok].SOffset;
            ASTSLen[fieldNode]   := Tokens[prevTok].SLen;
            tk      := RecFieldType(recName, fieldName);
            recName := RecFieldRecId(recName, fieldName);
            ASTTk[fieldNode] := Ord(tk);
            Next;
            node := fieldNode;
          end;
        end;
        CurASTNode := node;
        LastExprTk := tk;
        Exit;
      end;

      { C4: pointer-type-alias cast — PFoo(expr) where PFoo = ^TFoo }
      if (idx < 0) and (procIdx < 0) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        aliasIdx := FindTypeAlias(name);
        if aliasIdx >= 0 then
        begin
          Next; { consume alias type name }
          Expect(tkLParen, '(');
          ParseExpr;
          Expect(tkRParen, ')');
          node := AllocNode(AN_PTR_CAST);
          ASTLeft[node] := CurASTNode;
          { A custom alias to ^Char/^AnsiChar (e.g. `type PC = ^Char; PC(s)`)
            must behave like PChar(s): the -2 adapter skips the 8-byte length
            prefix for a string operand (and is a plain reinterpret otherwise),
            instead of pointing at the prefix. See bug-pointer-cast-custom-alias. }
          if AliasElemTk[aliasIdx] = Ord(tyChar) then
            ASTIVal[node] := -2
          else
            ASTIVal[node] := aliasIdx;
          ASTTk[node]   := Ord(tyPointer);
          { Set locals so the suffix loop below can resolve ^ and .field }
          tk      := tyPointer;
          recName := AliasElemRec[aliasIdx];  { pointee record id, used after ^ }
          { Inline metaclass-cast construction `TFooClass(expr).Create(args)`: the
            alias is a `class of T` (element tyClass) and the next selector is
            `.Create`. Dispatch through the metaclass like the variable form (the
            streamer's `TComponentClass(GetClass(n)).Create(owner)`). }
          if (IntToTypeKind(AliasElemTk[aliasIdx]) = tyClass) and
             (AliasElemRec[aliasIdx] >= REC_UCLASS_BASE) and
             (CurTok.Kind = tkDot) and (Tokens[TokPos].Kind = tkIdent) and
             CaseEqual(GetTokenStr(TokPos), 'create') then
          begin
            i := FindUMeth(AliasElemRec[aliasIdx] - REC_UCLASS_BASE, 'create');
            if i >= 0 then
            begin
              Next; { consume '.' }
              Next; { consume 'Create' }
              node := BuildMetaclassNew(node, AliasElemRec[aliasIdx] - REC_UCLASS_BASE, i);
              CurASTNode := node;
              LastExprTk := tyClass;
              Exit;
            end;
          end;
          { Run suffix loop: handle chains of ^, .field, and [i] on the cast result. }
          while CurTok.Kind in [tkCaret, tkDot, tkLBrack] do
          begin
            if CurTok.Kind = tkCaret then
            begin
              Next;
              indexNode := AllocNode(AN_DEREF);
              ASTLeft[indexNode] := node;
              { After ^, type becomes the pointee }
              tk      := IntToTypeKind(AliasElemTk[aliasIdx]);
              recName := AliasElemRec[aliasIdx];
              ASTTk[indexNode] := StrValTk(tk);
              node := indexNode;
            end
            else if CurTok.Kind = tkLBrack then
            begin
              Next;
              indexNode := AllocNode(AN_INDEX);
              ASTLeft[indexNode] := node;
              ParseExpr;
              ASTRight[indexNode] := CurASTNode;
              Expect(tkRBrack, ']');
              if tk = tyPointer then
              begin
                tk := IntToTypeKind(AliasElemTk[aliasIdx]);
                recName := AliasElemRec[aliasIdx];
              end
              else
              begin
                tk := tyUnknown;
                recName := REC_NONE;
              end;
              ASTTk[indexNode] := StrValTk(tk);
              node := indexNode;
            end
            else { tkDot }
            begin
              Next;
              if CurTok.Kind in [tkEOF, tkSemicolon, tkAssign, tkRBrack, tkRParen] then
                Error('expected field name after .');
              prevTok  := TokPos - 1;
              fieldName := '';
              for i := Tokens[prevTok].SOffset to Tokens[prevTok].SOffset + Tokens[prevTok].SLen - 1 do
                AppendChar(fieldName, TokChars[i]);
              fieldNode := AllocNode(AN_FIELD);
              ASTLeft[fieldNode] := node;
              ASTSOffset[fieldNode] := Tokens[prevTok].SOffset;
              ASTSLen[fieldNode]   := Tokens[prevTok].SLen;
              tk      := RecFieldType(recName, fieldName);
              recName := RecFieldRecId(recName, fieldName);
              ASTTk[fieldNode] := Ord(tk);
              Next;
              node := fieldNode;
            end;
          end;
          CurASTNode := node;
          LastExprTk := tk;
          Exit;
        end
        else
        begin
          { Built-in typecast }
          castTk := tyUnknown;
          if CaseEqual(name, 'pchar') or CaseEqual(name, 'pansichar') then
          begin
            { PChar(s): yields a C `const char*` into the string's char data.
              Lowered specially (sentinel -2) to skip the inline length prefix
              for string operands; a plain Pointer reinterpret otherwise. }
            Next; { consume type name }
            Expect(tkLParen, '(');
            ParseExpr;
            Expect(tkRParen, ')');
            node := AllocNode(AN_PTR_CAST);
            ASTLeft[node] := CurASTNode;
            ASTIVal[node] := -2; { PChar adapter }
            ASTTk[node]   := Ord(tyPointer);
            { `PChar(s)^` — deref of the cast: a char lvalue at the string's
              first data byte (Synapse's `Stream.Write(PAnsiChar(Value)^, ...)`
              — bug-cast-deref-as-varparam-arg). Mirrors the Pointer(expr)^
              untyped-deref below; by-ref args take the address. }
            if CurTok.Kind = tkCaret then
            begin
              Next;
              indexNode := AllocNode(AN_DEREF);
              ASTLeft[indexNode] := node;
              ASTTk[indexNode] := Ord(tyChar);
              CurASTNode := indexNode;
              LastExprTk := tyChar;
              Exit;
            end;
            { PChar(s)[i]: index the cast result -> a char element. The shared
              postfix loop's AN_PTR_CAST branch reads AliasElemTk[ASTIVal], which
              the -2 adapter has no entry for, so handle the subscript here. }
            while CurTok.Kind = tkLBrack do
            begin
              Next; { consume '[' }
              ParseExpr;
              Expect(tkRBrack, ']');
              indexNode := AllocNode(AN_INDEX);
              ASTLeft[indexNode]  := node;
              ASTRight[indexNode] := CurASTNode;
              ASTTk[indexNode]    := Ord(tyChar);
              node := indexNode;
            end;
            CurASTNode    := node;
            if ASTKind[node] = AN_INDEX then LastExprTk := tyChar
            else LastExprTk := tyPointer;
            Exit;
          end;
          if CaseEqual(name, 'pointer') then castTk := tyPointer
          else if CaseEqual(name, 'int64') or CaseEqual(name, 'nativeint') or CaseEqual(name, 'ptrint') then castTk := tyInt64
          else if CaseEqual(name, 'qword') or CaseEqual(name, 'uint64') or CaseEqual(name, 'nativeuint') or CaseEqual(name, 'ptruint') then castTk := tyUInt64
          else if CaseEqual(name, 'integer') or CaseEqual(name, 'longint') then castTk := tyInteger
          else if CaseEqual(name, 'cardinal') or CaseEqual(name, 'longword') or CaseEqual(name, 'uint32') or CaseEqual(name, 'dword') then castTk := tyUInt32
          else if CaseEqual(name, 'smallint') then castTk := tyInt16
          else if CaseEqual(name, 'word') or CaseEqual(name, 'uint16') then castTk := tyUInt16
          else if CaseEqual(name, 'shortint') then castTk := tyInt8
          else if CaseEqual(name, 'byte') or CaseEqual(name, 'uint8') then castTk := tyUInt8
          else if CaseEqual(name, 'char') or CaseEqual(name, 'ansichar') then castTk := tyChar
          else if CaseEqual(name, 'boolean') then castTk := tyBoolean
          else if CaseEqual(name, 'ansistring') or
                  CaseEqual(name, 'unicodestring') or CaseEqual(name, 'widestring') then
          begin
            if PasDefineExists('PXX_MANAGED_STRING') then
              castTk := tyAnsiString
            else
              castTk := tyString;
          end
          else if CaseEqual(name, 'string') then castTk := tyString
          else if FindEnumType(name) >= 0 then
            { Ordinal->enum typecast, TEnum(intExpr). Enums are integer-sized
              ordinals (cf. ParseTypeKind / the SizeOf branch above), so the
              cast is a plain integer reinterpret; the enum->ordinal direction
              already worked via the Integer(...) case above.
              See bug-integer-to-enum-typecast-undefined-variable. }
            castTk := tyInteger;

          if castTk <> tyUnknown then
          begin
            Next; { consume type name }
            Expect(tkLParen, '(');
            ParseExpr;
            Expect(tkRParen, ')');
            node := AllocNode(AN_PTR_CAST);
            ASTLeft[node] := CurASTNode;
            ASTIVal[node] := -1; { indicates built-in cast }
            ASTTk[node]   := Ord(castTk);
            { `Pointer(expr)^` — FPC's untyped deref, legal where only the
              ADDRESS matters (an untyped var/const argument: synautil's
              `Move(Pointer(Value)^, ...)` is the driving consumer). There is
              no pointee type, so model the deref as a Byte lvalue — the
              address is identical and untyped params take the address. }
            if (castTk = tyPointer) and (CurTok.Kind = tkCaret) then
            begin
              Next;
              indexNode := AllocNode(AN_DEREF);
              ASTLeft[indexNode] := node;
              ASTTk[indexNode] := Ord(tyUInt8);
              CurASTNode := indexNode;
              LastExprTk := tyUInt8;
              Exit;
            end;
            CurASTNode    := node;
            LastExprTk    := castTk;
            Exit;
          end;
        end;
      end;

      if (idx < 0) and (procIdx < 0) and IsClassType(name) and
         (CurTok.Kind = tkIdent) and (Tokens[TokPos].Kind = tkDot) and
         (Tokens[TokPos+1].Kind = tkIdent) and
         ((GetTokenStr(TokPos+1) = 'Create') or (GetTokenStr(TokPos+1) = 'create')) then
      begin
        Next; { Eat class name }
        Next; { Eat dot }
        Next; { Eat 'Create' }

        argsHead := -1;
        lastArg := -1;
        if CurTok.Kind = tkLParen then
        begin
          Next;
          while CurTok.Kind <> tkRParen do
          begin
            ParseExpr;
            argSeq := AllocNode(AN_ARG);
            ASTLeft[argSeq] := CurASTNode;
            if argsHead = -1 then
              argsHead := argSeq
            else
              ASTRight[lastArg] := argSeq;
            lastArg := argSeq;
            if CurTok.Kind = tkComma then
              Next
            else if CurTok.Kind <> tkRParen then
              Error('expected comma or close parenthesis');
          end;
          Expect(tkRParen, ')');
        end;

        idx := IsRecordType(name);
        if idx = REC_NONE then
        begin
          ci := FindUClass(name);
          if ci >= 0 then
            idx := REC_UCLASS_BASE + ci;
        end;
        prevTok := RecSize(idx);

        { Constructor ARITY check (FPC parity) + trailing-default fill. The
          codegen's ctor marshalling pops exactly ParamCount registers, so a
          missing (or extra) argument used to compile silently and desync the
          caller's stack by 8 bytes per miscount — a garbage-Self /
          nondeterministic-crash bug, not a wrong-answer one
          (bug-tthread-execute-writeln-crash's true root cause). }
        if idx >= REC_UCLASS_BASE then
        begin
          i := FindUMeth(idx - REC_UCLASS_BASE, 'create');
          if i >= 0 then
          begin
            mpi := UMthProc_[i];
            { count the explicit args parsed above }
            mlastArg := 0;
            argSeq := argsHead;
            while argSeq <> -1 do
            begin
              Inc(mlastArg);
              argSeq := ASTRight[argSeq];
            end;
            if mlastArg > Procs[mpi].ParamCount - 1 then
              Error('too many arguments to constructor ' + name + '.Create');
            { fill missing trailing args from declared defaults; a missing
              non-default arg is a compile error like FPC }
            while mlastArg < Procs[mpi].ParamCount - 1 do
            begin
              if not ProcParamHasDefault[mpi * MAX_PROC_PARAMS + (mlastArg + 1)] then
                Error('not enough arguments to constructor ' + name +
                      '.Create (parameter ' + Procs[mpi].Params[mlastArg + 1].Name + ' has no default)');
              exprNode := AllocNode(AN_INT_LIT);
              ASTIVal[exprNode] := ProcParamDefaultVal[mpi * MAX_PROC_PARAMS + (mlastArg + 1)];
              ASTTk[exprNode] := Ord(Procs[mpi].Params[mlastArg + 1].TypeKind);
              argSeq := AllocNode(AN_ARG);
              ASTLeft[argSeq] := exprNode;
              if argsHead = -1 then
                argsHead := argSeq
              else
                ASTRight[lastArg] := argSeq;
              lastArg := argSeq;
              Inc(mlastArg);
            end;
          end
          else if argsHead <> -1 then
            Error(name + ' has no constructor Create, but arguments were given');
        end;

        { Construct GetMem(sz) AST node }
        node := AllocNode(AN_CALL);
        ASTIVal[node] := -Ord(tkGetMem);
        ASTTk[node] := Ord(tyClass);
        ASTRight[node] := idx; { preserve created user-class id }

        exprNode := AllocNode(AN_INT_LIT);
        ASTIVal[exprNode] := prevTok;
        ASTTk[exprNode] := Ord(tyInteger);

        { The first argument to the GetMem call is the size }
        szArg := AllocNode(AN_ARG);
        ASTLeft[szArg] := exprNode;
        ASTLeft[node] := szArg;

        { The rest of the arguments are constructor arguments! }
        if argsHead <> -1 then
          ASTRight[szArg] := argsHead;

        CurASTNode := node;
        Exit;
      end;
      if (idx < 0) and (procIdx < 0) and IsClassType(name) and
         (Tokens[TokPos].Kind = tkDot) and (Tokens[TokPos+1].Kind = tkIdent) then
      begin
        ci := FindUClass(name);
        mmi := FindUMeth(ci, GetTokenStr(TokPos+1));
        if mmi >= 0 then
        begin
          if UMthIsStatic[mmi] then
          begin
            mpi := UMthProc_[mmi];
            Next; { consume class name }
            Expect(tkDot, '.');
            Next; { consume method name }
            mcallNode := AllocNode(AN_CALL);
            ASTIVal[mcallNode] := mpi;
            ASTTk[mcallNode] := Ord(Procs[mpi].RetType);
            mlastArg := -1;
            if CurTok.Kind = tkLParen then
            begin
              Next;
              i := 0;
              while i <= Procs[mpi].ParamCount-1 do
              begin
                if Procs[mpi].Params[i].IsRef or Procs[mpi].Params[i].IsArray then
                begin
                  if ByRefArgStartsExpression then
                  begin
                    { non-ident by-ref/array arg (@obj.Method to a method-pointer
                      param, [..] literals, casts): parse as an expression }
                    ParseExpr; exprNode := CurASTNode;
                  end
                  else
                  begin
                    argIdx := FindSym(CurTok.SVal); Next;
                    exprNode := ParseLValueAST(argIdx, TokPos - 2);
                  end;
                end
                else
                begin
                  ParseExpr; exprNode := CurASTNode;
                end;
                argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := exprNode;
                if mlastArg = -1 then
                  ASTLeft[mcallNode] := argSeq
                else
                  ASTRight[mlastArg] := argSeq;
                mlastArg := argSeq;
                if (i < Procs[mpi].ParamCount-1) and CanFillDefaultsFrom(mpi, i+1) then
                begin
                  FillDefaultArgs(mpi, i+1, mcallNode, mlastArg);
                  i := Procs[mpi].ParamCount-1;
                end
                else if i < Procs[mpi].ParamCount-1 then Expect(tkComma, ',');
                Inc(i);
              end;
              Expect(tkRParen, ')');
            end;
            CurASTNode := mcallNode;
            Exit;
          end;
        end;
      end;
      { Named set constant — but only if the name does not resolve to a real
        variable/parameter/const symbol first. A same-named variable (FindSetConst
        is case-insensitive: a `set of char` const `C` would otherwise shadow a
        char var `c`) must win. }
      sci := -1;
      if idx < 0 then sci := FindSetConst(name);
      if sci >= 0 then
      begin
        { Named set constant — yields the baked 32-byte mask's address, exactly
          like an all-constant set literal (lowered via IR_SET_LIT). }
        node := AllocNode(AN_SET_CONST_REF);
        ASTIVal[node] := SetConstOff[sci];
        ASTTk[node] := Ord(tySet); CurASTNode := node; Next;
        LastExprTk := tySet;
        Exit;
      end;
      sci := FindStrConst(name);
      if sci >= 0 then
      begin
        { Untyped string constant — expand to a string literal over its span. }
        node := AllocNode(AN_STR_LIT);
        ASTSOffset[node] := StrConstSOff[sci]; ASTSLen[node] := StrConstSLen[sci];
        ASTTk[node] := Ord(tyString); CurASTNode := node; Next;
        { Trailing index `RAMP[i]` -> a char from the literal's frozen storage
          (bug-const-string-index-miscompiles). The AN_STR_LIT base is lowered
          via its IR_CONST_STR value in IRLowerAddress. }
        while CurTok.Kind = tkLBrack do
        begin
          Next;
          indexNode := AllocNode(AN_INDEX);
          ASTLeft[indexNode] := node;
          ParseExpr;
          ASTRight[indexNode] := CurASTNode;
          Expect(tkRBrack, ']');
          ASTTk[indexNode] := Ord(tyChar);
          node := indexNode; CurASTNode := node;
          LastExprTk := tyChar;
        end;
      end
      else if (idx >= 0) and (Syms[idx].Kind = skConst) then
      begin
        { A float-typed const carries its IEEE-754 bits in ConstVal — emit a
          float literal, not an int literal (an AN_INT_LIT tagged tyDouble would
          be mis-codegen'd as an integer). }
        if TypeIsFloat(Syms[idx].TypeKind) then
          node := AllocNode(AN_FLOAT_LIT)
        else
          node := AllocNode(AN_INT_LIT);
        ASTIVal[node] := Syms[idx].ConstVal; ASTTk[node] := Ord(Syms[idx].TypeKind); CurASTNode := node; Next;
      end
      else if (CurProc >= 0) and Procs[CurProc].IsFunc and
              (Tokens[TokPos].Kind <> tkLParen) and
              not DelphiMode and
              ((name = Procs[CurProc].Name) or
               CaseEqual(name, LastDotName(Procs[CurProc].Name))) then
      begin
        { Bare function name in its own body, read as a value = the result var
          (FPC `FuncName` synonym for `Result`, e.g. `F := F + x`). The assign
          side (`FuncName := ...`) is handled at the statement level; this is the
          read side. A following `(` is a recursive call, not a result read, so
          it is excluded above and falls through to the call paths below.

          {$mode delphi} delta: in Delphi a bare own-name read is NEVER the result
          var — it is a (recursive) reference to the routine: paramless -> a call,
          with-params -> the function value (an error unless bound to a proc-typed
          target, which the @-relax bind sites handle). So this whole branch is
          skipped in delphi mode; `Result` is used to read the result there. In
          objfpc/default a bare own-name read is the result var (the project flip).

          Now FPC-faithful for ALL param counts (the paramless flip, bug-bare-
          function-name-call-vs-resultvar). A bare paramless own-name no longer
          recurses — `F()` is required to recurse. The 9 paramless self-recursion
          sites in the frontend were pre-hardened to explicit `F()` (commit
          c87785d) before this flip, so self-host stays byte-identical. Trailing
          `.field`/`[i]`/`^` resolve via ParseLValueAST. }
        { Opt-in footgun diagnostic (--warn-self-result): for a PARAMETERLESS
          function, a bare own-name value read is the Result, but a
          recursive-descent author usually meant `Name()`. Self-host-invisible
          (the rule is the same in seed and self-host), so it silently miscompiles
          user code — surface the ambiguity. Only paramless (with-params bare name
          can't be a call, so it is unambiguously Result). See
          bug-paramless-self-recursion-silent-result-read. }
        if WarnSelfResult and (Procs[CurProc].ParamCount = 0) then
          Warn('bare own name ''' + name + ''' reads the result of parameterless '
            + 'function ' + Procs[CurProc].Name + '; write ' + name
            + '() for a recursive call, or Result to read the result');
        Next;
        CurASTNode := ParseLValueAST(Procs[CurProc].RetSymIdx, TokPos - 2);
        LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
      end
      { NilPy: a `-> None` def is a procedure; its call statement flows through
        the expression parser (PyParseStatement's fallthrough), so accept
        proc calls here in NilPy mode only. Pascal keeps rejecting proc-in-expr. }
      else if (procIdx >= 0) and (Procs[procIdx].IsFunc or isNilPy) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next;
        Expect(tkLParen, '(');
        argsHead := -1;
        lastArg := -1;
        nArgs := 0;
        while CurTok.Kind <> tkRParen do
        begin
          if (CurTok.Kind = tkLBrack) and ParamIsVarRecArray(procIdx, nArgs) then
            CurASTNode := ParseVarRecLiteralAST
          else if (CurTok.Kind = tkLBrack) and ParamIsOpenArrayScalar(procIdx, nArgs) then
            CurASTNode := ParseArrayCtorAST(Procs[procIdx].Params[nArgs].TypeKind)
          else
          begin
            node := TryDelphiBareProcArg;
            if node >= 0 then CurASTNode := node else ParseExpr;
          end;
          argSeq := AllocNode(AN_ARG);
          ASTLeft[argSeq] := CurASTNode;
          if argsHead = -1 then
            argsHead := argSeq
          else
            ASTRight[lastArg] := argSeq;
          lastArg := argSeq;
          Inc(nArgs);
          if ProcFlexColumn[procIdx] then ParseFlexColumnTail(lastArg, nArgs);
          if CurTok.Kind = tkComma then
            Next
          else if CurTok.Kind <> tkRParen then
            Error('expected comma or close parenthesis');
        end;
        Expect(tkRParen, ')');

        currArg := argsHead;
        for i := 0 to nArgs - 1 do
        begin
          exprNode := ASTLeft[currArg];
          argTypes[i] := IntToTypeKind(ASTTk[exprNode]);
          currArg := ASTRight[currArg];
        end;

        procIdx := MatchCallDelphiProcAddr(name, qUnit, nArgs, argsHead, argTypes);
        if procIdx < 0 then
        begin
          { Generic dynamic-array Copy(arr, index [, count]) intrinsic. Only when
            no Copy function matches (so a string `sysutils.Copy` is never
            shadowed) and the first argument is a dynamic array. Lowered into a
            fresh element-type-aware `array of T` (AN_DYN_COPY). String Copy keeps
            the RTL path. }
          if CaseEqual(name, 'Copy') and (nArgs >= 2) and (nArgs <= 3) and
             (ASTKind[ASTLeft[argsHead]] = AN_IDENT) and
             (ASTIVal[ASTLeft[argsHead]] >= 0) and
             Syms[ASTIVal[ASTLeft[argsHead]]].IsArray and
             (Syms[ASTIVal[ASTLeft[argsHead]]].ArrLen = -1) then
          begin
            node := AllocNode(AN_DYN_COPY);
            ASTLeft[node] := ASTLeft[argsHead];                 { source array }
            exprNode := ASTLeft[ASTRight[argsHead]];            { index }
            if nArgs = 3 then
              addrNode := ASTLeft[ASTRight[ASTRight[argsHead]]] { count }
            else
            begin
              addrNode := AllocNode(AN_INT_LIT);
              ASTIVal[addrNode] := 2147483647; ASTTk[addrNode] := Ord(tyInteger);
            end;
            argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := exprNode;
            lastArg := AllocNode(AN_ARG); ASTLeft[lastArg] := addrNode;
            ASTRight[argSeq] := lastArg;
            ASTRight[node] := argSeq;
            { Pointer-typed: dyn-array handle result, stored full-width on assign. }
            ASTTk[node] := Ord(tyPointer);
            CurASTNode := node;
            Exit;
          end;
          Error('no overload of ' + name + ' matches these arguments');
        end;

        isLiftedCall := (procIdx >= 0) and (Procs[procIdx].ParamCount > nArgs) and
                        (ProcParamPtrDepth[procIdx * MAX_PROC_PARAMS + nArgs] = 2);

        if isLiftedCall then
        begin
          liftedVar := AllocVar('', tyPointer);
          identNode := AllocNode(AN_IDENT);
          ASTIVal[identNode] := liftedVar;
          ASTTk[identNode] := Ord(tyPointer);

          addrNode := AllocNode(AN_ADDR);
          ASTLeft[addrNode] := identNode;
          ASTTk[addrNode] := Ord(tyPointer);

          argSeq := AllocNode(AN_ARG);
          ASTLeft[argSeq] := addrNode;

          if argsHead = -1 then
          begin
            argsHead := argSeq;
            lastArg := argSeq;
          end
          else
          begin
            ASTRight[lastArg] := argSeq;
            lastArg := argSeq;
          end;

          argTypes[nArgs] := tyPointer;
          Inc(nArgs);

          while nArgs < Procs[procIdx].ParamCount do
          begin
            addrNode := AllocNode(AN_INT_LIT);
            ASTIVal[addrNode] := 0;
            ASTTk[addrNode] := Ord(tyPointer);

            argSeq := AllocNode(AN_ARG);
            ASTLeft[argSeq] := addrNode;

            if argsHead = -1 then
            begin
              argsHead := argSeq;
              lastArg := argSeq;
            end
            else
            begin
              ASTRight[lastArg] := argSeq;
              lastArg := argSeq;
            end;

            argTypes[nArgs] := tyPointer;
            Inc(nArgs);
          end;
        end;

        isCStringCall := PyExprMode and (Procs[procIdx].RetType = tyPointer) and
                         ((ProcRetPtrElemTk[procIdx] = Ord(tyChar)) or
                          (ProcRetPtrElemTk[procIdx] = Ord(tyUInt8)) or
                          (ProcRetPtrElemTk[procIdx] = Ord(tyInt8)));

        currArg := argsHead;
        for i := 0 to nArgs - 1 do
        begin
          exprNode := ASTLeft[currArg];
          if (TypeIsFrozenString(Procs[procIdx].Params[i].TypeKind)) and (IntToTypeKind(ASTTk[exprNode]) = tyChar) then
          begin
            if ASTKind[exprNode] = AN_INT_LIT then
            begin
              ASTKind[exprNode] := AN_STR_LIT;
              ASTTk[exprNode] := Ord(tyString);
            end;
          end;
          currArg := ASTRight[currArg];
        end;

        currArg := argsHead;
        for i := 0 to nArgs - 1 do
        begin
          exprNode := ASTLeft[currArg];
          if Procs[procIdx].Params[i].IsRef or Procs[procIdx].Params[i].IsArray then
          begin
            if not ((ASTKind[exprNode] = AN_IDENT) or (ASTKind[exprNode] = AN_INDEX) or (ASTKind[exprNode] = AN_FIELD) or
                    (ASTKind[exprNode] = AN_DEREF) or
                    (ASTKind[exprNode] = AN_VARREC_ARRAY) or (ASTKind[exprNode] = AN_ARRAY_CTOR)) then
            begin
              { A record param passed by-ref may bind a non-lvalue temporary (e.g.
                a function result) when it is `const` OR plain by-value (>8-byte
                records are passed by-ref only for ABI; the callee copies, so a
                hidden-local temp is sound). Only a genuine `var`/`out` record
                (explicitly declared by-ref) still needs a true lvalue for
                write-back. An array-constructor literal ([...]) is itself the
                open-array temp. }
              if not ((IntToTypeKind(ASTTk[exprNode]) = tyRecord) and
                      (ProcParamIsConst[procIdx * MAX_PROC_PARAMS + i] or
                       not ProcParamExplicitByRef[procIdx * MAX_PROC_PARAMS + i])) then
                Error('by-reference argument must be a variable');
            end;
          end;
          currArg := ASTRight[currArg];
        end;

        node := AllocNode(AN_CALL);
        ASTIVal[node] := procIdx;
        ASTTk[node] := Ord(Procs[procIdx].RetType);
        ASTLeft[node] := argsHead;
        if isLiftedCall then
        begin
          ASTLiftedVar[node] := liftedVar;
          ASTTk[node] := Ord(tyPointer);
        end;

        if isCStringCall then
        begin
          helperPi := FindProc('PCharToString');
          if helperPi < 0 then Error('builtin: PCharToString not found in Nil Python mode');
          wrapperArg := AllocNode(AN_ARG);
          ASTLeft[wrapperArg] := node;
          wrapperCall := AllocNode(AN_CALL);
          ASTIVal[wrapperCall] := helperPi;
          ASTTk[wrapperCall] := Ord(Procs[helperPi].RetType);
          ASTLeft[wrapperCall] := wrapperArg;
          node := wrapperCall;

          CurASTNode := node;
          LastExprTk := Procs[helperPi].RetType;
        end
        else
        begin
          ApplyCallResultPtrSuffix(node, procIdx);  { f(...)^ / ^.field / [i] }
          if isLiftedCall then
          begin
            CurASTNode := node;
            LastExprTk := tyPointer;
          end;
        end;
        Exit;
      end
      else if (idx < 0) and (procIdx >= 0) and Procs[procIdx].IsFunc and (Procs[procIdx].ParamCount = 0) then
      begin
        { Bare paramless function called by name in an expression. Guarded on
          `idx < 0`: a variable in scope with the same name (PXX is
          case-insensitive, so a local `clauseCount` collides with a function
          `ClauseCount`) must SHADOW the function — fall through to the var read
          below. Without this guard the local read was silently compiled as a
          call to the function (bug-impl-prescan-codegen-regression: the real
          defect was here, name resolution, not slot/offset allocation). }
        Next;
        node := AllocNode(AN_CALL);
        ASTIVal[node] := procIdx;
        ASTTk[node] := Ord(Procs[procIdx].RetType);
        ApplyCallResultPtrSuffix(node, procIdx);  { f()^ / ^.field / [i] }
        Exit;
      end
      else
      begin
        { Implicit Self.method dispatch for methods called bare inside a class body in expression context }
        node := -1;
        if (idx < 0) and (procIdx < 0) and (CurSelfClass >= REC_UCLASS_BASE) then
        begin
          ci := CurSelfClass - REC_UCLASS_BASE;
          mmi := FindUMethArity(ci, name, CountCallArgsAhead);
          if mmi >= 0 then
          begin
            mpi := UMthProc_[mmi];
            Next; { consume method name }
            smSelfIdx := Procs[CurProc].Params[0].SymIdx;
            smselfArg := AllocNode(AN_ARG);
            valNode := AllocNode(AN_IDENT);
            ASTIVal[valNode] := smSelfIdx;
            ASTTk[valNode] := Ord(tyClass);
            ASTLeft[smselfArg] := valNode;
            if UMthVirSlot[mmi] >= 0 then
            begin
              mcallNode := AllocNode(AN_VIRTUAL_CALL);
              ASTRight[mcallNode] := UMthVirSlot[mmi];
            end
            else
              mcallNode := AllocNode(AN_CALL);
            ASTIVal[mcallNode] := mpi;
            if (mpi >= 0) then
              ASTTk[mcallNode] := Ord(Procs[mpi].RetType)
            else
              ASTTk[mcallNode] := Ord(tyInteger);
            ASTLeft[mcallNode] := smselfArg;
            mlastArg := smselfArg;
            if CurTok.Kind = tkLParen then
            begin
              Next;
              i := 1;
              while CurTok.Kind <> tkRParen do
              begin
                ParseExpr;
                argSeq := AllocNode(AN_ARG);
                ASTLeft[argSeq] := CurASTNode;
                ASTRight[mlastArg] := argSeq;
                mlastArg := argSeq;
                Inc(i);
                if CurTok.Kind = tkComma then Next;
              end;
              Expect(tkRParen, ')');
            end;
            { trailing `.field` / `[i]` on a class/record method result }
            if (mpi >= 0) and (CurTok.Kind in [tkDot, tkLBrack]) and
               ((Procs[mpi].RetType = tyClass) or (Procs[mpi].RetType = tyRecord)) then
              mcallNode := ParseClassRecordSelectors(mcallNode, ProcRetRecId[mpi], tk);
            CurASTNode := mcallNode;
            node := mcallNode;
          end;
        end;
        if node = -1 then
        begin
          Next;
          CurASTNode := ParseLValueAST(idx, TokPos - 2);
          LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
        end;
      end;
    end;
    else Error('expected expression');
  end;
  { Postfix `lv++` / `lv--` on the parsed factor (must be an lvalue): yields the
    OLD value, bumps after. tkPlusPlus/tkMinusMinus are new tokens never produced
    for existing source, so this is inert for non-C code (self-host byte-identical). }
  while CurTok.Kind in [tkPlusPlus, tkMinusMinus] do
  begin
    node := AllocNode(AN_INCDEC);
    ASTLeft[node] := CurASTNode;
    if CurTok.Kind = tkPlusPlus then ASTIVal[node] := 1 else ASTIVal[node] := -1;
    ASTSOffset[node] := 1;   { postfix → old value }
    ASTTk[node] := ASTTk[CurASTNode];
    CurASTNode := node; LastExprTk := IntToTypeKind(ASTTk[node]);
    Next;
  end;
end;

function FloatBinopResultTk(ltk, rtk: TTypeKind): TTypeKind;
{ Result type of a float-producing binop. On double-native targets every float
  op widens to Double (Single is storage-only). On ESP (xtensa/riscv) Single is
  first-class: single op single -> single, only an explicit Double operand pulls
  the result to soft-Double. Ordinal operands count as "not Double" so int/int
  under '/' yields the native depth (Single on ESP). }
begin
  if (ltk = tyExtended) or (rtk = tyExtended) then
    FloatBinopResultTk := tyExtended
  else if (TargetArch = TARGET_XTENSA) or (TargetArch = TARGET_RISCV32) then
  begin
    if (ltk = tyDouble) or (rtk = tyDouble) then
      FloatBinopResultTk := tyDouble
    else
      FloatBinopResultTk := tySingle;
  end
  else
    FloatBinopResultTk := tyDouble;
end;

procedure ParseTerm;
var op: TTokenKind; left, right, node, opSOffset, opSLen, opci: Integer;
begin
  ParseFactor;
  while ((CurTok.Kind in [tkStar, tkSlash, tkDiv, tkMod, tkAnd, tkShl]) or
        ((CurTok.Kind = tkIdent) and (CurTok.SVal = 'shr'))) and
        not (PyExprMode and (CurTok.Kind = tkAnd)) do
  begin
    opSOffset := Tokens[TokPos - 1].SOffset;
    opSLen := Tokens[TokPos - 1].SLen;
    op := CurTok.Kind; Next;
    left := CurASTNode;
    ParseFactor;
    right := CurASTNode;
    node := AllocNode(AN_BINOP); ASTIVal[node] := Ord(op); ASTLeft[node] := left; ASTRight[node] := right;
    ASTSOffset[node] := opSOffset; ASTSLen[node] := opSLen;
    opci := -1;
    if (IntToTypeKind(ASTTk[left]) = tyRecord) or (IntToTypeKind(ASTTk[left]) = tyClass) then
      opci := FindOpOverload(Ord(op), ASTTk[left], ResolveNodeRec(left));
    if opci >= 0 then
      { Overloaded operator on a record/class operand returns its result type. }
      ASTTk[node] := Ord(Procs[opci].RetType)
    else if (ASTTk[left] = Ord(tyVariant)) or (ASTTk[right] = Ord(tyVariant)) then
      ASTTk[node] := Ord(tyVariant)
    else if (op = tkAnd) and (ASTTk[left] = Ord(tyBoolean)) and (ASTTk[right] = Ord(tyBoolean)) then
      ASTTk[node] := Ord(tyBoolean)
    else if (ASTTk[left] = Ord(tySet)) or (ASTTk[right] = Ord(tySet)) then
      ASTTk[node] := Ord(tySet)
    else if op = tkSlash then
      ASTTk[node] := Ord(FloatBinopResultTk(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])))  { '/' produces native-depth float }
    else if op = tkDiv then
      ASTTk[node] := Ord(TypeDivideResult(IntToTypeKind(ASTTk[left])))
    else if op = tkMod then
      ASTTk[node] := Ord(TypeDivideResult(IntToTypeKind(ASTTk[left])))
    else if (op = tkIdent) or (op = tkShl) then
      ASTTk[node] := ASTTk[left]
    else if (ASTTk[left] = Ord(tySingle)) or (ASTTk[left] = Ord(tyDouble)) or (ASTTk[left] = Ord(tyExtended)) or
            (ASTTk[right] = Ord(tySingle)) or (ASTTk[right] = Ord(tyDouble)) or (ASTTk[right] = Ord(tyExtended)) then
      ASTTk[node] := Ord(FloatBinopResultTk(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])))
    else if TypeIsOrdinal(IntToTypeKind(ASTTk[left])) and TypeIsOrdinal(IntToTypeKind(ASTTk[right])) then
      ASTTk[node] := Ord(TypeArithmeticResult(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])))
    else
      ASTTk[node] := Ord(tyInteger);
    CurASTNode := node;
  end;
end;

procedure ParseSimpleExpr;
var op: TTokenKind; neg: Boolean; left, right, node, opci: Integer;
begin
  neg := CurTok.Kind = tkMinus; Eat(tkMinus); Eat(tkPlus);
  ParseTerm;
  if neg then
  begin
    node := AllocNode(AN_NEG); ASTLeft[node] := CurASTNode; ASTTk[node] := ASTTk[CurASTNode]; CurASTNode := node;
  end;
  while (CurTok.Kind in [tkPlus, tkMinus, tkOr, tkXor]) and
        not (PyExprMode and (CurTok.Kind = tkOr)) do
  begin
    op := CurTok.Kind; Next;
    left := CurASTNode;
    ParseTerm;
    right := CurASTNode;
    node := AllocNode(AN_BINOP); ASTIVal[node] := Ord(op); ASTLeft[node] := left; ASTRight[node] := right;
    opci := -1;
    if (IntToTypeKind(ASTTk[left]) = tyRecord) or (IntToTypeKind(ASTTk[left]) = tyClass) then
      opci := FindOpOverload(Ord(op), ASTTk[left], ResolveNodeRec(left));
    if opci >= 0 then
      { Overloaded operator on a record/class operand: the node's type is the
        operator's result type, so an inferred target and the aggregate-return
        copy are sized correctly (not the tyInteger catch-all below). }
      ASTTk[node] := Ord(Procs[opci].RetType)
    else if (ASTTk[left] = Ord(tyVariant)) or (ASTTk[right] = Ord(tyVariant)) then
      ASTTk[node] := Ord(tyVariant)
    else if (op = tkPlus) and ((ASTTk[left] = Ord(tyAnsiString)) or (ASTTk[right] = Ord(tyAnsiString))) then
      ASTTk[node] := Ord(tyAnsiString)
    else if (op = tkPlus) and ((ASTTk[left] = Ord(tyString)) or (ASTTk[right] = Ord(tyString)) or
                          ((ASTTk[left] = Ord(tyChar)) and (ASTTk[right] = Ord(tyChar)))) then
    begin
      { Managed default: type literal/char concat as a MANAGED result. The
        frozen concat codegen builds its result in a 272-byte buffer carved
        off the stack with NO restore (documented in IRLowerCallArg) — fine
        for a one-off, but `s := 'p' + Chr(i)` in a loop leaked 272 bytes of
        stack per iteration and overflowed after ~30k iterations
        (bug-frozen-concat-stack-carve-loop-overflow). The managed concat
        path heap-allocates and already accepts tyString/tyChar operands.
        Frozen self-build (-uPXX_MANAGED_STRING) keeps the old typing. }
      if PasDefineExists('PXX_MANAGED_STRING') then
        ASTTk[node] := Ord(tyAnsiString)
      else
        ASTTk[node] := Ord(tyString);
    end
    else if ((op = tkPlus) or (op = tkMinus)) and
            (ASTTk[left] = Ord(tyPointer)) and
            TypeIsOrdinal(IntToTypeKind(ASTTk[right])) then
      ASTTk[node] := Ord(tyPointer)
    else if (op = tkPlus) and
            TypeIsOrdinal(IntToTypeKind(ASTTk[left])) and
            (ASTTk[right] = Ord(tyPointer)) then
      ASTTk[node] := Ord(tyPointer)
    else if (ASTTk[left] = Ord(tySet)) or (ASTTk[right] = Ord(tySet)) then
      ASTTk[node] := Ord(tySet)
    else if ((op = tkOr) or (op = tkXor)) and (ASTTk[left] = Ord(tyBoolean)) and (ASTTk[right] = Ord(tyBoolean)) then
      ASTTk[node] := Ord(tyBoolean)
    else if (ASTTk[left] = Ord(tySingle)) or (ASTTk[left] = Ord(tyDouble)) or (ASTTk[left] = Ord(tyExtended)) or
            (ASTTk[right] = Ord(tySingle)) or (ASTTk[right] = Ord(tyDouble)) or (ASTTk[right] = Ord(tyExtended)) then
      ASTTk[node] := Ord(FloatBinopResultTk(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])))
    else if TypeIsOrdinal(IntToTypeKind(ASTTk[left])) and TypeIsOrdinal(IntToTypeKind(ASTTk[right])) then
      ASTTk[node] := Ord(TypeArithmeticResultOp(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right]), op))
    else
      ASTTk[node] := Ord(tyInteger);
    CurASTNode := node;
  end;
end;

{ Enum type index of an expression node, or -1. Ident-level only: enum
  identity lives on the SYMBOL (SymEnumId, tagged at var decls). }
function NodeEnumIdOf(node: Integer): Integer;
begin
  Result := -1;
  if (node >= 0) and (ASTKind[node] = AN_IDENT) and (ASTIVal[node] >= 0) then
    Result := SymEnumId[ASTIVal[node]];
end;

procedure ParseExpr;
var op: TTokenKind; left, right, node, isci: Integer; isIsTest: Boolean;
begin
  ParseSimpleExpr;
  { `X is T` / `X as T` — is/as are contextual identifiers (not reserved tokens),
    treated as operators only when followed by a known class name, so a stray
    identifier is never hijacked. Parser-resolved into their own AST nodes (per
    the and/or lesson: never key behaviour off a global flag). }
  if (CurTok.Kind = tkIdent) and
     (CaseEqual(CurTok.SVal, 'is') or CaseEqual(CurTok.SVal, 'as')) and
     (TokPos < TokCount) and (Tokens[TokPos].Kind = tkIdent) and
     (FindUClass(GetTokenStr(TokPos)) >= 0) then
  begin
    isIsTest := CaseEqual(CurTok.SVal, 'is');
    Next;
    isci := FindUClass(CurTok.SVal);
    Next;
    left := CurASTNode;
    if isIsTest then
    begin
      node := AllocNode(AN_IS_TEST);
      ASTLeft[node] := left; ASTIVal[node] := isci; ASTTk[node] := Ord(tyBoolean);
    end
    else
    begin
      node := AllocNode(AN_AS_CAST);
      ASTLeft[node] := left; ASTIVal[node] := isci;
      { `obj as IFoo` yields an interface VALUE (a CORBA fat pointer, a 2-word
        record); `obj as TClass` yields a class reference. }
      if UClsIsInterface[isci] then ASTTk[node] := Ord(tyRecord)
      else ASTTk[node] := Ord(tyClass);
    end;
    CurASTNode := node;
    Exit;
  end;
  if CurTok.Kind = tkIn then
  begin
    Next;
    if CurTok.Kind = tkLBrack then
    begin
      CurASTNode := ParseSetMembershipAST(CurASTNode);
    end
    else
    begin
      left := CurASTNode;
      ParseSimpleExpr;
      right := CurASTNode;
      node := AllocNode(AN_BINOP);
      ASTIVal[node] := Ord(tkIn);
      ASTLeft[node] := left;
      ASTRight[node] := right;
      ASTTk[node] := Ord(tyBoolean);
      CurASTNode := node;
    end;
    Exit;
  end;
  if CurTok.Kind in [tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe] then
  begin
    op := CurTok.Kind; Next;
    left := CurASTNode;
    ParseSimpleExpr;
    right := CurASTNode;
    { FPC-parity: an ENUM operand cannot compare against a pointer — there is
      no implicit conversion between them (toperatorerror). Detection is
      ident-level (SymEnumId is tagged at var decls), so complex expressions
      stay unchecked — this is a diagnostic, not a type system. }
    if (NodeEnumIdOf(left) >= 0) and (IntToTypeKind(ASTTk[right]) = tyPointer) or
       (NodeEnumIdOf(right) >= 0) and (IntToTypeKind(ASTTk[left]) = tyPointer) then
      Error('cannot compare an enum with a pointer');
    node := AllocNode(AN_BINOP); ASTIVal[node] := Ord(op); ASTLeft[node] := left; ASTRight[node] := right;
    ASTTk[node] := Ord(tyBoolean); CurASTNode := node;
  end;
  { Compound assignment expression `lv += rhs` (and -= *= /=), right-associative
    so `a += b += c` nests on the Right and each yields its stored value. The
    tokens are new to pxx (no existing source produces them) so this tail is inert
    for non-C code → self-host byte-identical. The lvalue check is done at IR
    lowering (where IsASTLValue is visible), which also rejects `a++ += x`. The
    plain value-bearing `=` (op = tkAssign) is produced by the C frontend; the
    node + lowering handle it as the trivial store-and-yield subset of this. }
  if CurTok.Kind in [tkPlusEq, tkMinusEq, tkStarEq, tkSlashEq] then
  begin
    op := CurTok.Kind; Next;
    left := CurASTNode;
    ParseExpr;                 { right-assoc: RHS may itself be a compound assign }
    right := CurASTNode;
    node := AllocNode(AN_COMPOUND_ASSIGN);
    ASTLeft[node] := left; ASTRight[node] := right;
    case op of
      tkPlusEq:  ASTIVal[node] := Ord(tkPlus);
      tkMinusEq: ASTIVal[node] := Ord(tkMinus);
      tkStarEq:  ASTIVal[node] := Ord(tkStar);
      else       ASTIVal[node] := Ord(tkSlash);
    end;
    ASTTk[node] := ASTTk[left];
    CurASTNode := node;
  end;
end;

function ConstIntCastWidth(const nm: AnsiString; var bytes: Integer; var signed: Boolean): Boolean;
{ True if `nm` is an integer-family type name usable as a const typecast; sets
  the result width in bytes and whether it sign-extends. Recognises both the
  tk*_T keyword spellings and the tkIdent type aliases (Int64/UInt64/...).
  Uses CaseEqual (not LowerCase) so it stays callable before LowerCase is
  declared — self-host requires declaration-before-use. }
begin
  Result := True; signed := True; bytes := 8;
  if CaseEqual(nm, 'int64') or CaseEqual(nm, 'nativeint') or CaseEqual(nm, 'ptrint') then begin bytes := 8; signed := True; end
  else if CaseEqual(nm, 'uint64') or CaseEqual(nm, 'qword') or CaseEqual(nm, 'nativeuint') or CaseEqual(nm, 'ptruint') then begin bytes := 8; signed := False; end
  else if CaseEqual(nm, 'integer') or CaseEqual(nm, 'longint') then begin bytes := 4; signed := True; end
  else if CaseEqual(nm, 'cardinal') or CaseEqual(nm, 'longword') or CaseEqual(nm, 'dword') then begin bytes := 4; signed := False; end
  else if CaseEqual(nm, 'smallint') then begin bytes := 2; signed := True; end
  else if CaseEqual(nm, 'word') then begin bytes := 2; signed := False; end
  else if CaseEqual(nm, 'shortint') then begin bytes := 1; signed := True; end
  else if CaseEqual(nm, 'byte') or CaseEqual(nm, 'char') then begin bytes := 1; signed := False; end
  else Result := False;
end;

function ConstAliasCastWidth(const nm: AnsiString; var bytes: Integer; var signed: Boolean): Boolean;
{ True if `nm` is a user type alias whose target is ordinal and therefore usable
  as a const typecast. }
var aliasIdx: Integer; tk: TTypeKind;
begin
  Result := False;
  aliasIdx := FindTypeAlias(nm);
  if aliasIdx < 0 then Exit;
  tk := IntToTypeKind(AliasTk[aliasIdx]);
  if not TypeIsOrdinal(tk) then Exit;
  bytes := TypeSize(tk);
  signed := TypeSigned(tk);
  Result := True;
end;

function ConstApplyCast(r: Int64; bytes: Integer; signed: Boolean): Int64;
{ Reinterpret r to the cast width, matching the runtime wrap behaviour. Sign
  extension uses subtraction (Result - 2^width) rather than `not`, and decimal
  literals (which exceed signed-32 and so parse as Int64), avoiding the hex-width
  / `not Int64()` folding pitfalls. }
begin
  Result := r;
  if bytes = 1 then
  begin
    Result := r and 255;
    if signed and (Result >= 128) then Result := Result - 256;
  end
  else if bytes = 2 then
  begin
    Result := r and 65535;
    if signed and (Result >= 32768) then Result := Result - 65536;
  end
  else if bytes = 4 then
  begin
    Result := r and 4294967295;
    if signed and (Result >= 2147483648) then Result := Result - 4294967296;
  end;
  { bytes = 8: full width, no change }
end;

function ConstEval: Int64; forward;

function ConstEvalFactor: Int64;
{ Primary of a const expression: literal / true / false / single-char literal /
  named const / parenthesised expr / integer typecast. Unary +/- binds tightest
  (so -2*3 = -(2)*3 = -6 and 2*-3 = -6). No code emitted. }
var r: Int64; idx: Integer; castBytes: Integer; castSigned: Boolean;
    cName: AnsiString; cQUnit, ceOrd: Integer; hasConstCast, hlHigh: Boolean; sofTk: TTypeKind;
begin
  r := 0;
  { NB: the parens on the recursive ConstEvalFactor() are required — a bare own
    function name in an expression reads the (uninitialised) Result var instead
    of recursing, both under the FPC seed and self-hosted. }
  if CurTok.Kind = tkMinus then begin Next; Result := -ConstEvalFactor(); Exit; end;
  if CurTok.Kind = tkPlus  then begin Next; Result :=  ConstEvalFactor(); Exit; end;
  if CurTok.Kind = tkNot   then begin Next; Result := not ConstEvalFactor(); Exit; end;
  if CurTok.Kind = tkNil   then begin Next; Result := 0; Exit; end;   { `= nil` default params (FPC RTL) }
  hasConstCast := False;
  if (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
  begin
    hasConstCast := ConstIntCastWidth(CurTok.SVal, castBytes, castSigned);
    if not hasConstCast then
      hasConstCast := ConstAliasCastWidth(CurTok.SVal, castBytes, castSigned);
  end;
  if hasConstCast then
  begin
    { Integer typecast in a const expression, e.g. `Int64(1) shl 52`. Evaluate
      the inner expression then reinterpret to the cast width. FPC/Delphi fold
      these; ISO Pascal does not. NB: `ConstEval()` needs the parens — a bare
      `ConstEval` in an assignment RHS reads the function result var, not a call. }
    Next; Expect(tkLParen, '(');
    r := ConstEval(); Expect(tkRParen, ')');
    r := ConstApplyCast(r, castBytes, castSigned);
  end
  else if CurTok.Kind = tkInteger then begin r := CurTok.IVal; Next; end
  else if CurTok.Kind = tkTrue  then begin r := 1; Next; end
  else if CurTok.Kind = tkFalse then begin r := 0; Next; end
  else if (CurTok.Kind = tkString) and (Length(CurTok.SVal) = 1) then
    { single-char literal 'x' used as an ordinal constant (Char typed-const
      element, `Ord('A')`-free contexts) -> its character code. }
    begin r := Ord(CurTok.SVal[1]); Next; end
  else if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'sizeof') then
  begin
    { SizeOf(TypeName) as a compile-time constant — needed for default-parameter
      values (`= sizeof(Pointer)`) and const expressions; FPC folds it. Minimal
      scope: a type name/keyword resolved via ParseTypeKind -> its byte size
      (covers sizeof(Pointer)/sizeof(Integer)/sizeof(TRec)). A sizeof(variable)
      or sizeof(arr[i]) form is not folded here (rare in a const context; the
      full expression path in ParseFactor handles those). See
      feature-sizeof-const-intrinsic-in-const-eval. }
    Next; Expect(tkLParen, '(');
    sofTk := ParseTypeKind;
    if sofTk = tyRecord then r := RecSize(LastTypeRecId)
    else r := TypeSize(sofTk);
    Expect(tkRParen, ')');
  end
  else if (CurTok.Kind = tkIdent) and (TokPos + 1 < TokCount) and
          (Tokens[TokPos].Kind = tkDot) and (Tokens[TokPos+1].Kind = tkIdent) and
          (FindEnumType(CurTok.SVal) >= 0) and
          FindEnumMemberOrd(FindEnumType(CurTok.SVal), GetTokenStr(TokPos+1), ceOrd) then
  begin
    { `TEnum.member` in a constant expression (case labels, const decls) —
      scoped-enum access; folds to the ordinal. }
    r := ceOrd;
    Next; Next; Next;   { TEnum, '.', member }
  end
  else if (CurTok.Kind = tkIdent) and
          (CaseEqual(CurTok.SVal, 'high') or CaseEqual(CurTok.SVal, 'low')) and
          (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
  begin
    { High(T)/Low(T) as a compile-time constant — array bounds and const
      declarations (bug-pascal-high-low-in-const-expr). Type-name operands
      only, mirroring the sizeof fold above; High(variable) stays a runtime
      expression outside const contexts. }
    hlHigh := CaseEqual(CurTok.SVal, 'high');
    Next; Expect(tkLParen, '(');
    if not TryConstHighLowValue(hlHigh, r) then
      Error('High/Low in a constant expression: expected an ordinal type name');
    Expect(tkRParen, ')');
  end
  else if CurTok.Kind = tkIdent then
  begin
    { A `Unit.Const` qualifier (e.g. `termio.FIONREAD`) — ConsumeUnitQualifier
      leaves the parser on the member name and yields the unit index; resolve the
      const in that unit's scope, same as the ordinary-expression path. }
    cName := CurTok.SVal;
    cQUnit := ConsumeUnitQualifier(cName);
    if cQUnit >= 0 then
      idx := FindSymInUnit(cName, cQUnit)
    else
      idx := FindSym(cName);
    if (idx >= 0) and (Syms[idx].Kind = skConst) then
      r := Syms[idx].ConstVal
    else
    begin
      writeln('ConstEval error at SrcLine ', SrcLine, ': SVal = ', CurTok.SVal, ' Kind = ', Ord(CurTok.Kind), ' TokPos = ', TokPos);
      writeln('Tokens nearby:');
      for idx := TokPos - 5 to TokPos + 5 do
      begin
        if (idx >= 0) and (idx < TokCount) then
        begin
          writeln('  Token ', idx, ': Line = ', Tokens[idx].Line, ' Kind = ', Ord(Tokens[idx].Kind), ' SOffset = ', Tokens[idx].SOffset, ' SLen = ', Tokens[idx].SLen);
        end;
      end;
      Error('not a constant');
    end;
    Next;
  end
  else if CurTok.Kind = tkLParen then
  begin
    Next; r := ConstEval(); Expect(tkRParen, ')');
  end;
  Result := r;
end;

function ConstEvalTerm: Int64;
{ Multiplicative precedence level (binds tighter than +/-): * div mod and shl
  shr, left-associative. `shr` is lexed as an identifier (no tkShr token), like
  the runtime term parser. }
var r, v: Int64; op: TTokenKind;
begin
  r := ConstEvalFactor;
  while (CurTok.Kind in [tkStar, tkDiv, tkMod, tkAnd, tkShl]) or
        ((CurTok.Kind = tkIdent) and (CurTok.SVal = 'shr')) do
  begin
    if CurTok.Kind = tkIdent then
    begin Next; v := ConstEvalFactor; r := r shr v; end
    else
    begin
      op := CurTok.Kind; Next; v := ConstEvalFactor;
      case op of
        tkStar: r := r * v;
        tkDiv:  r := r div v;
        tkMod:  r := r mod v;
        tkAnd:  r := r and v;
        tkShl:  r := r shl v;
      end;
    end;
  end;
  Result := r;
end;

function ConstEval: Int64;
{ Evaluate a compile-time constant expression (no code emitted). Additive
  precedence level: + - or xor, left-associative; multiplicative ops bind
  tighter (ConstEvalTerm). Fixes the old flat right-to-left fold that ignored
  operator precedence (`2*3+1` gave 8, not 7). }
var r, v: Int64; op: TTokenKind;
begin
  r := ConstEvalTerm;
  while CurTok.Kind in [tkPlus, tkMinus, tkOr, tkXor] do
  begin
    op := CurTok.Kind; Next; v := ConstEvalTerm;
    case op of
      tkPlus:  r := r + v;
      tkMinus: r := r - v;
      tkOr:    r := r or v;
      tkXor:   r := (r or v) and not (r and v);  { a xor b; the compiler must
                 stay buildable by an older seed that lacks the xor operator }
    end;
  end;
  Result := r;
end;

{ Parse one constant initializer value (scalar). A float literal yields its IEEE
  754 bit pattern (carried as Int64, same as AN_FLOAT_LIT); everything else goes
  through the integer ConstEval. Lets a `Double` initializer like 3.14 work. }
function ParseInitVal: Int64;
var neg: Boolean; signMask: Int64;
begin
  { A leading unary +/- on a float literal: the lexer emits the sign as a
    separate operator token, so a typed `const A: Double = -2.5` would otherwise
    fall to the integer ConstEval and be rejected. Flip the IEEE-754 sign bit
    (bit 63) for a minus. }
  neg := False;
  if (CurTok.Kind = tkMinus) and (Tokens[TokPos].Kind = tkFloat) then begin neg := True; Next; end
  else if (CurTok.Kind = tkPlus) and (Tokens[TokPos].Kind = tkFloat) then Next;
  if CurTok.Kind = tkFloat then
  begin
    Result := CurTok.IVal; Next;
    if neg then begin signMask := 1; signMask := signMask shl 63; Result := Result xor signMask; end;
  end
  else Result := ConstEval;
end;

{ ===== Statement parser ===== }

procedure ParseStatement; forward;
procedure ParseBlock; forward;

function ParseIfStatementAST: Integer;
var condNode, thenNode, elseNode, pairNode, node: Integer;
begin
  ParseExpr; condNode := CurASTNode;
  Expect(tkThen, 'then');
  thenNode := ParseStatementAST;
  elseNode := -1;
  if Eat(tkElse) then
    elseNode := ParseStatementAST;

  node := AllocNode(AN_IF);
  ASTLeft[node] := condNode;
  pairNode := AllocNode(AN_PAIR);
  ASTLeft[pairNode] := thenNode;
  ASTRight[pairNode] := elseNode;
  ASTRight[node] := pairNode;
  Result := node;
end;

function ParseWhileStatementAST: Integer;
var condNode, bodyNode, node: Integer;
begin
  ParseExpr; condNode := CurASTNode;
  Expect(tkDo, 'do');
  bodyNode := ParseStatementAST;
  node := AllocNode(AN_WHILE);
  ASTLeft[node] := condNode;
  ASTRight[node] := bodyNode;
  Result := node;
end;

{ Synthesis helpers for the for-in generator desugar. }
function GenMakeIdent(symIdx: Integer; tk: TTypeKind): Integer;
begin
  Result := AllocNode(AN_IDENT);
  ASTIVal[Result] := symIdx;
  ASTTk[Result] := Ord(tk);
end;

{ Build an AN_CALL with up to 6 positional arg value-nodes (-1 = absent). No
  local arrays/open-arrays — the cross-target codegens (i386/arm32/aarch64) only
  support ordinal/pointer/string locals, and compiler.pas must cross-compile. }
function GenAddArg(callNode, prev, valNode: Integer): Integer;
var an: Integer;
begin
  if valNode < 0 then begin Result := prev; Exit; end;
  an := AllocNode(AN_ARG);
  ASTLeft[an] := valNode;
  if prev = -1 then ASTLeft[callNode] := an
  else ASTRight[prev] := an;
  Result := an;
end;

function GenMakeCall6(procIdx: Integer; retTk: TTypeKind; a0, a1, a2, a3, a4, a5: Integer): Integer;
var prev: Integer;
begin
  Result := AllocNode(AN_CALL);
  ASTIVal[Result] := procIdx;
  ASTTk[Result] := Ord(retTk);
  prev := -1;
  prev := GenAddArg(Result, prev, a0);
  prev := GenAddArg(Result, prev, a1);
  prev := GenAddArg(Result, prev, a2);
  prev := GenAddArg(Result, prev, a3);
  prev := GenAddArg(Result, prev, a4);
  prev := GenAddArg(Result, prev, a5);
end;

function GenMakeSeq(stmt, next: Integer): Integer;
begin
  Result := AllocNode(AN_SEQ);
  ASTLeft[Result] := stmt;
  ASTRight[Result] := next;
end;

function GenMakeAssign(lhs, rhs: Integer): Integer;
begin
  Result := AllocNode(AN_ASSIGN);
  ASTLeft[Result] := lhs;
  ASTRight[Result] := rhs;
end;

{ Desugar `for x in Gen(args) do BODY` (Gen a `; generator;` routine) into:
    __g := CoAlloc(@Gen, nargs, a0,a1,a2,a3);
    while CoNext(__g) do begin x := CoCurrent(__g); BODY end;
    CoFree(__g);
  Returns the synthesised AN_SEQ. Called from ParseForStatementAST once `in`
  is seen after the loop variable. }
function GenZeroLit: Integer;
begin
  Result := AllocNode(AN_INT_LIT);
  ASTIVal[Result] := 0;
  ASTTk[Result] := Ord(tyInt64);
end;

{ SlSet(g, off, val) statement for the for-in desugar (the transform-side
  GenSlSetStmt is declared later and takes the generator's self sym). }
function GenSlSetStmt2(gIdx, off, valNode: Integer): Integer;
var offLit: Integer;
begin
  offLit := AllocNode(AN_INT_LIT);
  ASTIVal[offLit] := off;
  ASTTk[offLit] := Ord(tyInt64);
  Result := GenMakeCall6(FindProc('SlSet'), tyInt64,
    GenMakeIdent(gIdx, tyPointer), offLit, valNode, -1, -1, -1);
end;

function ParseForInGeneratorAST(varIdx, gpi: Integer): Integer;
var
  bodyNode, nargs, gIdx: Integer;
  a0, a1, a2, a3: Integer;
  procAddr, nargsLit, callAlloc, callNext, callCur, callFree: Integer;
  assignG, assignX, whileNode, innerSeq, instLit: Integer;
  sa1, sa2, sa3, sa4: Integer;
  paCoAlloc, paCoNext, paCoCurrent, paCoFree: Integer;
  curDeref: Integer;
begin
  if Syms[varIdx].TypeKind = tyAuto then
    Error('for var .. in <generator>: inline loop variable not yet supported here — declare the variable explicitly (feature-inline-loop-var-rio)');
  { unused args default to 0 (no local array — must cross-compile) }
  a0 := GenZeroLit; a1 := GenZeroLit; a2 := GenZeroLit; a3 := GenZeroLit;
  nargs := 0;
  if Eat(tkLParen) then
  begin
    if CurTok.Kind <> tkRParen then
      repeat
        { A record argument (a stackless generator's `const pos: TRec` param is
          by-ref) is carried as its ADDRESS in the instance slot — the record
          value itself doesn't fit the one-word SlAlloc args, and ParseExpr has
          no value node for a bare record lvalue anyway. Parse it as an lvalue
          and take its address; the record must outlive the loop (a caller-side
          variable does). Stackless only: the stackful CoAlloc path keeps its
          existing lowering untouched. }
        if ProcIsStackless[gpi] and (CurTok.Kind = tkIdent) and
           (FindSym(CurTok.SVal) >= 0) and
           (Syms[FindSym(CurTok.SVal)].TypeKind = tyRecord) and
           (not Syms[FindSym(CurTok.SVal)].IsArray) then
        begin
          sa1 := FindSym(CurTok.SVal); sa2 := TokPos - 1; Next;
          instLit := AllocNode(AN_ADDR);
          ASTLeft[instLit] := ParseLValueAST(sa1, sa2);
          ASTTk[instLit] := Ord(tyPointer);
          CurASTNode := instLit;
        end
        else
          ParseExpr;
        case nargs of
          0: a0 := CurASTNode;
          1: a1 := CurASTNode;
          2: a2 := CurASTNode;
          3: a3 := CurASTNode;
          else Error('for-in generator: at most 4 arguments (v1)');
        end;
        Inc(nargs);
      until not Eat(tkComma);
    Expect(tkRParen, ')');
  end;
  Expect(tkDo, 'do');
  bodyNode := ParseStatementAST;

  gIdx := AllocVar('', tyPointer);
  nargsLit := AllocNode(AN_INT_LIT);  ASTIVal[nargsLit] := nargs; ASTTk[nargsLit] := Ord(tyInt64);

  if ProcIsStackless[gpi] then
  begin
    { Stackless: alloc + zero an instance, then store each provided argument
      into its persistent slot with its own SlSet — NOT the packed
      SlAlloc(instSize, nargs, a0..a3): its 6 Int64 params are 12 argument
      words, over the riscv32 backend's 8-word call limit. Advance by calling
      the generator's step function directly (the compiler knows it — PXX
      cannot call through a stored proc pointer with args).
        __g := SlNew(instSize);
        SlSet(__g, SLOTS+8k, ak) for each provided arg;
        while Gen(__g) do begin x := SlCurrent(__g); BODY end;
        SlFree(__g); }
    if (FindProc('SlNew') < 0) or (FindProc('SlSet') < 0) or
       (FindProc('SlCurrent') < 0) or (FindProc('SlFree') < 0) then
      Error('for-in generator: the slgen unit is not in scope (add `uses slgen;`)');
    instLit := AllocNode(AN_INT_LIT); ASTIVal[instLit] := ProcGenInstSize[gpi]; ASTTk[instLit] := Ord(tyInt64);
    callAlloc := GenMakeCall6(FindProc('SlNew'), tyPointer, instLit, -1, -1, -1, -1, -1);
    assignG := GenMakeAssign(GenMakeIdent(gIdx, tyPointer), callAlloc);
    assignG := GenMakeSeq(assignG, -1);
    if nargs >= 1 then
      assignG := GenMakeSeq(assignG, GenMakeSeq(GenSlSetStmt2(gIdx, SL_OFF_SLOTS + 0, a0), -1));
    if nargs >= 2 then
      assignG := GenMakeSeq(assignG, GenMakeSeq(GenSlSetStmt2(gIdx, SL_OFF_SLOTS + 8, a1), -1));
    if nargs >= 3 then
      assignG := GenMakeSeq(assignG, GenMakeSeq(GenSlSetStmt2(gIdx, SL_OFF_SLOTS + 16, a2), -1));
    if nargs >= 4 then
      assignG := GenMakeSeq(assignG, GenMakeSeq(GenSlSetStmt2(gIdx, SL_OFF_SLOTS + 24, a3), -1));

    { advance = a direct call to the step function with the instance pointer.
      The step proc's ABI is (self + the declared params); only self is real (the
      declared params are restored from the instance), but the call must provide
      one arg per param — the internal-call codegen pops ParamCount registers, so
      a short arg list would unbalance the stack. Pad with zeros. }
    { A by-ref (var / const-record) declared param can't be padded with a zero
      literal: the call lowering marshals by-ref args via IRLowerAddress, and a
      literal has no address. Pad those with the (addressable) instance var —
      the callee never reads the incoming pad, its restore prologue overwrites
      every param slot from the instance. }
    sa1 := -1; sa2 := -1; sa3 := -1; sa4 := -1;
    if ProcGenParamCnt[gpi] >= 1 then
      if Procs[gpi].Params[1].IsRef then sa1 := GenMakeIdent(gIdx, tyPointer) else sa1 := GenZeroLit;
    if ProcGenParamCnt[gpi] >= 2 then
      if Procs[gpi].Params[2].IsRef then sa2 := GenMakeIdent(gIdx, tyPointer) else sa2 := GenZeroLit;
    if ProcGenParamCnt[gpi] >= 3 then
      if Procs[gpi].Params[3].IsRef then sa3 := GenMakeIdent(gIdx, tyPointer) else sa3 := GenZeroLit;
    if ProcGenParamCnt[gpi] >= 4 then
      if Procs[gpi].Params[4].IsRef then sa4 := GenMakeIdent(gIdx, tyPointer) else sa4 := GenZeroLit;
    callNext := GenMakeCall6(gpi, tyBoolean, GenMakeIdent(gIdx, tyPointer), sa1, sa2, sa3, sa4, -1);
    callCur := GenMakeCall6(FindProc('SlCurrent'), tyInt64, GenMakeIdent(gIdx, tyPointer), -1, -1, -1, -1, -1);
    if Syms[varIdx].TypeKind = tyRecord then
    begin
      { Record element: the CURRENT word holds the ADDRESS of the record region
        at the instance tail (published at each yield) — deref and copy into the
        loop variable, same shape as the stackful CoCurrent path below. }
      curDeref := AllocNode(AN_DEREF);
      ASTLeft[curDeref] := callCur;
      ASTTk[curDeref] := Ord(tyRecord);
      ASTIVal[curDeref] := Syms[varIdx].RecName;
      assignX := GenMakeAssign(GenMakeIdent(varIdx, tyRecord), curDeref);
    end
    else
      assignX := GenMakeAssign(GenMakeIdent(varIdx, Syms[varIdx].TypeKind), callCur);

    innerSeq := GenMakeSeq(assignX, GenMakeSeq(bodyNode, -1));
    whileNode := AllocNode(AN_WHILE);
    ASTLeft[whileNode] := callNext;
    ASTRight[whileNode] := innerSeq;

    callFree := GenMakeCall6(FindProc('SlFree'), tyPointer, GenMakeIdent(gIdx, tyPointer), -1, -1, -1, -1, -1);
    Result := GenMakeSeq(assignG, GenMakeSeq(whileNode, GenMakeSeq(callFree, -1)));
    Exit;
  end;

  { Stackful: CoAlloc / while CoNext / CoCurrent / CoFree (heap coroutine stack). }
  paCoAlloc   := FindProc('CoAlloc');
  paCoNext    := FindProc('CoNext');
  paCoCurrent := FindProc('CoCurrent');
  paCoFree    := FindProc('CoFree');
  if (paCoAlloc < 0) or (paCoNext < 0) or (paCoCurrent < 0) or (paCoFree < 0) then
    Error('for-in generator: the coroutine unit is not in scope (add `uses coroutine;`)');

  procAddr := AllocNode(AN_PROCADDR); ASTIVal[procAddr] := gpi; ASTTk[procAddr] := Ord(tyPointer);

  callAlloc := GenMakeCall6(paCoAlloc, tyPointer, procAddr, nargsLit, a0, a1, a2, a3);
  assignG := GenMakeAssign(GenMakeIdent(gIdx, tyPointer), callAlloc);

  callNext := GenMakeCall6(paCoNext, tyBoolean, GenMakeIdent(gIdx, tyPointer), -1, -1, -1, -1, -1);

  callCur := GenMakeCall6(paCoCurrent, tyInt64, GenMakeIdent(gIdx, tyPointer), -1, -1, -1, -1, -1);
  if Syms[varIdx].TypeKind = tyRecord then
  begin
    { Record element: CoCurrent returns the address of the yielded record (in the
      generator's preserved frame); deref it and copy into the loop variable. The
      record id is carried on the deref node so ResolveNodeRec sizes the copy. }
    curDeref := AllocNode(AN_DEREF);
    ASTLeft[curDeref] := callCur;
    ASTTk[curDeref] := Ord(tyRecord);
    ASTIVal[curDeref] := Syms[varIdx].RecName;
    assignX := GenMakeAssign(GenMakeIdent(varIdx, tyRecord), curDeref);
  end
  else
    assignX := GenMakeAssign(GenMakeIdent(varIdx, Syms[varIdx].TypeKind), callCur);

  innerSeq := GenMakeSeq(assignX, GenMakeSeq(bodyNode, -1));
  whileNode := AllocNode(AN_WHILE);
  ASTLeft[whileNode] := callNext;
  ASTRight[whileNode] := innerSeq;

  callFree := GenMakeCall6(paCoFree, tyPointer, GenMakeIdent(gIdx, tyPointer), -1, -1, -1, -1, -1);

  Result := GenMakeSeq(assignG, GenMakeSeq(whileNode, GenMakeSeq(callFree, -1)));
end;

{ ===== Native `for x in <array|string|enum-type>` (Slice A) =====
  Desugars the FPC native-tier for-in sources into a plain indexed while loop in
  the AST, so all targets get it from shared lowering (no per-target codegen).
  Element semantics are by value: `x := C[__i]` per iteration. }

function GenMakeIntLit(v: Int64): Integer;
begin
  Result := AllocNode(AN_INT_LIT);
  ASTIVal[Result] := v;
  ASTTk[Result] := Ord(tyInt64);
end;

function GenMakeBinop(op: TTokenKind; l, r: Integer; tk: TTypeKind): Integer;
begin
  Result := AllocNode(AN_BINOP);
  ASTIVal[Result] := Ord(op);
  ASTLeft[Result] := l;
  ASTRight[Result] := r;
  ASTTk[Result] := Ord(tk);
end;

{ Length(symIdx) as an AST call node, matching what tkLength parsing builds: the
  argument is the container lvalue (by-ref). Works for ansistring/dynarray/open-
  array; the IR Length lowering reads the right header per the base symbol. }
function GenMakeLengthCall(symIdx: Integer; tk: TTypeKind): Integer;
var argSeq: Integer;
begin
  Result := AllocNode(AN_CALL);
  ASTIVal[Result] := -Ord(tkLength);
  ASTTk[Result] := Ord(tyInteger);
  argSeq := AllocNode(AN_ARG);
  ASTLeft[argSeq] := GenMakeIdent(symIdx, tk);
  ASTLeft[Result] := argSeq;
end;

{ Length(<arbitrary value node>): same intrinsic call as GenMakeLengthCall but
  wraps a caller-supplied node (e.g. an AN_FIELD over Self) instead of a bare
  symbol. Used by the for-in loop builder so the container can be either a plain
  variable or an implicit-Self field. }
function GenMakeLengthCallNode(valNode: Integer): Integer;
var argSeq: Integer;
begin
  Result := AllocNode(AN_CALL);
  ASTIVal[Result] := -Ord(tkLength);
  ASTTk[Result] := Ord(tyInteger);
  argSeq := AllocNode(AN_ARG);
  ASTLeft[argSeq] := valNode;
  ASTLeft[Result] := argSeq;
end;

{ ===== Structural enumerator for-in (Slice B) =====
  A zero-extra-arg method call C.M (self only). Handles virtual dispatch. }
function GenMakeMethodCall0(instNode, classIdx: Integer; const methName: AnsiString): Integer;
var mmi, mpi, selfArg: Integer;
begin
  mmi := FindUMeth(classIdx, methName);
  if mmi < 0 then Error('for-in: enumerator missing method ' + methName);
  mpi := UMthProc_[mmi];
  if UMthVirSlot[mmi] >= 0 then
  begin
    Result := AllocNode(AN_VIRTUAL_CALL);
    ASTRight[Result] := UMthVirSlot[mmi];
  end
  else
    Result := AllocNode(AN_CALL);
  ASTIVal[Result] := mpi;
  ASTTk[Result] := Ord(Procs[mpi].RetType);
  selfArg := AllocNode(AN_ARG);
  ASTLeft[selfArg] := instNode;
  ASTLeft[Result] := selfArg;
end;

{ Read `__e.Current`: a property (getter method OR backing field) or a plain
  public field. Returns the value node. }
function GenMakeCurrentRead(eSym, enumIdx, enumRec: Integer): Integer;
var pri, fIdx, i, fnode: Integer; mname: AnsiString;
begin
  pri := FindUProp(enumIdx, 'Current');
  if pri >= 0 then
  begin
    if UPropReadMLen[pri] > 0 then
    begin
      mname := '';
      for i := 0 to UPropReadMLen[pri] - 1 do AppendChar(mname, TokChars[UPropReadMOff[pri] + i]);
      Result := GenMakeMethodCall0(GenMakeIdent(eSym, tyClass), enumIdx, mname);
      Exit;
    end
    else if UPropReadFLen[pri] > 0 then
    begin
      fnode := AllocNode(AN_FIELD);
      ASTLeft[fnode] := GenMakeIdent(eSym, tyClass);
      ASTSOffset[fnode] := UPropReadFOff[pri];
      ASTSLen[fnode] := UPropReadFLen[pri];
      ASTTk[fnode] := Ord(UPropTk[pri]);
      Result := fnode;
      Exit;
    end;
  end;
  fIdx := FindUField(enumIdx, 'Current');
  if fIdx < 0 then Error('for-in: enumerator has no readable Current');
  fnode := AllocNode(AN_FIELD);
  ASTLeft[fnode] := GenMakeIdent(eSym, tyClass);
  ASTSOffset[fnode] := UFldNOff[fIdx];
  ASTSLen[fnode] := UFldNLen[fIdx];
  ASTTk[fnode] := Ord(RecFieldType(enumRec, 'Current'));
  Result := fnode;
end;

{ for X in C do BODY where C has GetEnumerator (FPC structural enumerator):
    __e := C.GetEnumerator;
    try while __e.MoveNext do begin X := __e.Current; BODY end;
    finally __e.Free end;       { __e.Free only when the enumerator has one }
  Duck-typed on the three names; no base class required. }
function ParseForInEnumeratorAST(varIdx, contSym, contClassIdx: Integer): Integer;
var
  bodyNode, gepi, enumRec, enumIdx, eSym: Integer;
  geCall, assignE, mnCall, curNode, assignX, innerSeq, whileNode: Integer;
  freeCall, tryNode: Integer;
  contTk: TTypeKind;
begin
  if Syms[varIdx].TypeKind = tyAuto then
    Error('for var .. in <GetEnumerator>: inline loop variable not yet supported here — declare the variable explicitly (feature-inline-loop-var-rio)');
  Expect(tkDo, 'do');
  bodyNode := ParseStatementAST;

  contTk := Syms[contSym].TypeKind;
  gepi := UMthProc_[FindUMeth(contClassIdx, 'GetEnumerator')];
  enumRec := ProcRetRecId[gepi];
  if enumRec < REC_UCLASS_BASE then Error('for-in: GetEnumerator must return a class/record');
  enumIdx := enumRec - REC_UCLASS_BASE;

  eSym := AllocVar('', tyClass);
  Syms[eSym].RecName := enumRec;

  geCall := GenMakeMethodCall0(GenMakeIdent(contSym, contTk), contClassIdx, 'GetEnumerator');
  assignE := GenMakeAssign(GenMakeIdent(eSym, tyClass), geCall);

  mnCall := GenMakeMethodCall0(GenMakeIdent(eSym, tyClass), enumIdx, 'MoveNext');

  curNode := GenMakeCurrentRead(eSym, enumIdx, enumRec);
  assignX := GenMakeAssign(GenMakeIdent(varIdx, Syms[varIdx].TypeKind), curNode);

  innerSeq := GenMakeSeq(assignX, GenMakeSeq(bodyNode, -1));
  whileNode := AllocNode(AN_WHILE);
  ASTLeft[whileNode] := mnCall;
  ASTRight[whileNode] := innerSeq;

  if FindUMeth(enumIdx, 'Free') >= 0 then
  begin
    freeCall := GenMakeMethodCall0(GenMakeIdent(eSym, tyClass), enumIdx, 'Free');
    tryNode := AllocNode(AN_TRY_FINALLY);
    ASTLeft[tryNode] := whileNode;
    ASTRight[tryNode] := freeCall;
    Result := GenMakeSeq(assignE, GenMakeSeq(tryNode, -1));
  end
  else
    Result := GenMakeSeq(assignE, GenMakeSeq(whileNode, -1));
end;

{ for X in <set var> do BODY iterates present members in ordinal order. Reuses
  the `in` membership operator over the element base-type range, so no knowledge
  of the 32-byte bitset layout is needed:
    X := lo;
    while X <= hi do begin if X in S then BODY; X := X + 1; end;
  X (the loop var) doubles as the scan ordinal. Range from the set element type:
  `set of <enum>` → 0..count-1; `set of Char` → 0..255. }
{ Shared membership-scan builder for `for x in <set>`. The set source is an
  abstract value node (setOperand) — a plain `set var` ident (ParseForInSetAST)
  or a qualified member-access lvalue (ParseForInNodeAST). The element range is
  given by setEnumId (`set of <enum>` → 0..count-1) or setElemTk = tyChar
  (`set of Char` → 0..255). bodyNode is the already-parsed loop body. }
function BuildForInSetLoop(varIdx, setEnumId, setElemTk, setOperand, bodyNode: Integer): Integer;
var
  loV, hiV, vtk, oSym, isChar: Integer;
  initN, scanCond, condIn, pairN, ifN, incN, innerSeq, whileN: Integer;
  valNode, assignE, chrArg: Integer;
begin
  isChar := 0;
  if setEnumId >= 0 then
  begin loV := 0; hiV := EnumTypeValCount[setEnumId] - 1; end
  else if setElemTk = Ord(tyChar) then
  begin loV := 0; hiV := 255; isChar := 1; end
  else
    Error('for-in: set iteration supports `set of <enum>` or `set of Char` only');

  { Scan with a separate Integer ordinal so the `<= hi` test cannot wrap on a
    narrow loop var (a Char counter overflows 255 -> 0 and loops forever). }
  oSym := AllocVar('', tyInteger);
  vtk := Ord(Syms[varIdx].TypeKind);
  initN := GenMakeAssign(GenMakeIdent(oSym, tyInteger), GenMakeIntLit(loV));
  scanCond := GenMakeBinop(tkLe, GenMakeIdent(oSym, tyInteger), GenMakeIntLit(hiV), tyBoolean);

  { loop var := ordinal (Chr() for char elements, plain ordinal for enums) }
  if isChar = 1 then
  begin
    valNode := AllocNode(AN_CALL);
    ASTIVal[valNode] := -Ord(tkChr);
    ASTTk[valNode] := Ord(tyChar);
    chrArg := AllocNode(AN_ARG);
    ASTLeft[chrArg] := GenMakeIdent(oSym, tyInteger);
    ASTLeft[valNode] := chrArg;
  end
  else
    valNode := GenMakeIdent(oSym, tyInteger);
  assignE := GenMakeAssign(GenMakeIdent(varIdx, IntToTypeKind(vtk)), valNode);

  condIn := GenMakeBinop(tkIn, GenMakeIdent(oSym, tyInteger), setOperand, tyBoolean);
  ifN := AllocNode(AN_IF);
  ASTLeft[ifN] := condIn;
  pairN := AllocNode(AN_PAIR);
  ASTLeft[pairN] := bodyNode;
  ASTRight[pairN] := -1;
  ASTRight[ifN] := pairN;

  incN := GenMakeAssign(GenMakeIdent(oSym, tyInteger),
    GenMakeBinop(tkPlus, GenMakeIdent(oSym, tyInteger), GenMakeIntLit(1), tyInteger));
  innerSeq := GenMakeSeq(assignE, GenMakeSeq(ifN, GenMakeSeq(incN, -1)));
  whileN := AllocNode(AN_WHILE);
  ASTLeft[whileN] := scanCond;
  ASTRight[whileN] := innerSeq;
  Result := GenMakeSeq(initN, GenMakeSeq(whileN, -1));
end;

function ParseForInSetAST(varIdx, setSym: Integer): Integer;
var bodyNode: Integer;
begin
  { Inline `for var x in setVar`: backfill x's type from the set's element
    base type before the body is parsed (feature-inline-loop-var-rio). }
  if Syms[varIdx].TypeKind = tyAuto then
  begin
    if SymSetElemTk[setSym] = Ord(tyChar) then Syms[varIdx].TypeKind := tyChar
    else Syms[varIdx].TypeKind := tyInteger;
  end;
  Expect(tkDo, 'do');
  bodyNode := ParseStatementAST;
  Result := BuildForInSetLoop(varIdx, SymSetEnumId[setSym], SymSetElemTk[setSym],
                              GenMakeIdent(setSym, tySet), bodyNode);
end;

{ for x in <string|static array|dynarray|open-array var> do BODY:
    __i := lo;
    while __i <= hi do begin x := C[__i]; BODY; __i := __i + 1; end;
  lo/hi pick the right base: strings 1..Length, arrays 0..count-1.
  A class/record container with GetEnumerator routes to the enumerator desugar;
  a set var routes to the membership-scan desugar. }

{ Build a fresh container value-node for the for-in array/string loop.
  ckind=0 → a plain symbol (GenMakeIdent); ckind=1 → an implicit-Self field
  (AN_FIELD over Self). A fresh node is built per call so the container is not
  aliased between the Length() bound and the element access (codegen walks the
  AST as a tree, not a DAG). }
function GenMakeContainerNode(ckind, csym, cselfSym, cfOff, cfLen, ctemplate: Integer; ctk: TTypeKind): Integer;
var fn: Integer;
begin
  if ckind = 0 then
    Result := GenMakeIdent(csym, ctk)
  else if ckind = 2 then
    { arbitrary lvalue expression (e.g. obj.field, Self.field) — a fresh deep
      copy per use so the Length bound and element access don't alias. }
    Result := CloneAST(ctemplate)
  else
  begin
    fn := AllocNode(AN_FIELD);
    ASTLeft[fn] := GenMakeIdent(cselfSym, tyClass);
    ASTSOffset[fn] := cfOff;
    ASTSLen[fn] := cfLen;
    ASTTk[fn] := Ord(ctk);
    Result := fn;
  end;
end;

{ Shared while-loop desugar for `for x in <array|string>`. The container is
  described abstractly (see GenMakeContainerNode) so the source can be either a
  plain variable (ParseForInVarAST) or an implicit-Self field
  (ParseForInFieldAST). Flags + elemTk are computed by the caller from whichever
  metadata table applies (Syms[...] vs UFld...). }
function BuildForInArrayLoop(varIdx, ckind, csym, cselfSym, cfOff, cfLen, ctemplate: Integer;
  contTk: TTypeKind; isString, isStaticArr, isArr: Boolean;
  staticLen, elemTk, bodyNode: Integer): Integer;
var
  idxSym, loNode, hiNode, condNode, elemAccess: Integer;
  assignX, incNode, whileNode, innerSeq, initI: Integer;
begin
  idxSym := AllocVar('', tyInteger);
  if isString then loNode := GenMakeIntLit(1)
  else if isArr then loNode := GenMakeIntLit(0)
  else begin Error('for-in: variable is not a string or array'); loNode := GenMakeIntLit(0); end;
  initI := GenMakeAssign(GenMakeIdent(idxSym, tyInteger), loNode);

  if isStaticArr then
    hiNode := GenMakeIntLit(staticLen - 1)
  else if isString then
    hiNode := GenMakeLengthCallNode(GenMakeContainerNode(ckind, csym, cselfSym, cfOff, cfLen, ctemplate, contTk))
  else
    hiNode := GenMakeBinop(tkMinus,
      GenMakeLengthCallNode(GenMakeContainerNode(ckind, csym, cselfSym, cfOff, cfLen, ctemplate, contTk)),
      GenMakeIntLit(1), tyInteger);

  condNode := GenMakeBinop(tkLe, GenMakeIdent(idxSym, tyInteger), hiNode, tyBoolean);

  elemAccess := AllocNode(AN_INDEX);
  ASTLeft[elemAccess] := GenMakeContainerNode(ckind, csym, cselfSym, cfOff, cfLen, ctemplate, contTk);
  ASTRight[elemAccess] := GenMakeIdent(idxSym, tyInteger);
  ASTTk[elemAccess] := elemTk;
  assignX := GenMakeAssign(GenMakeIdent(varIdx, Syms[varIdx].TypeKind), elemAccess);

  incNode := GenMakeAssign(GenMakeIdent(idxSym, tyInteger),
    GenMakeBinop(tkPlus, GenMakeIdent(idxSym, tyInteger), GenMakeIntLit(1), tyInteger));

  innerSeq := GenMakeSeq(assignX, GenMakeSeq(bodyNode, GenMakeSeq(incNode, -1)));
  whileNode := AllocNode(AN_WHILE);
  ASTLeft[whileNode] := condNode;
  ASTRight[whileNode] := innerSeq;

  Result := GenMakeSeq(initI, GenMakeSeq(whileNode, -1));
end;

function ParseForInVarAST(varIdx, contSym: Integer): Integer;
var
  bodyNode, elemTk: Integer;
  isString, isStaticArr: Boolean;
  contTk: TTypeKind;
  recId: Integer;
begin
  { set var → membership-scan over the element base-type range }
  if Syms[contSym].TypeKind = tySet then
  begin
    Result := ParseForInSetAST(varIdx, contSym);
    Exit;
  end;

  { class/record container with GetEnumerator → structural enumerator (Slice B) }
  recId := Syms[contSym].RecName;
  if (not (TypeIsFrozenString(Syms[contSym].TypeKind) or (Syms[contSym].TypeKind = tyAnsiString)))
     and (not Syms[contSym].IsArray) and (recId >= REC_UCLASS_BASE)
     and (FindUMeth(recId - REC_UCLASS_BASE, 'GetEnumerator') >= 0) then
  begin
    Result := ParseForInEnumeratorAST(varIdx, contSym, recId - REC_UCLASS_BASE);
    Exit;
  end;

  contTk := Syms[contSym].TypeKind;
  { A real string container is a non-array string var. For `array of String` /
    `array of AnsiString` the var's TypeKind is the element base type
    (tyAnsiString), so the array check MUST win — otherwise it is mis-iterated
    char-by-char. }
  isString := (not Syms[contSym].IsArray) and ((contTk = tyString) or (contTk = tyAnsiString));
  isStaticArr := Syms[contSym].IsArray and (Syms[contSym].ArrLen >= 0);

  if isString then elemTk := Ord(tyChar)
  else if Syms[contSym].IsArray then elemTk := Ord(Syms[contSym].ElemType)
  else begin Error('for-in: variable is not a string or array'); elemTk := Ord(tyInteger); end;

  { FPC-parity: iterating a STRING yields Char — a non-char ordinal loop var
    (`for b: byte in s`) is a type error, not an implicit Ord() conversion
    (bug-pascal-missing-diagnostics-fail-tests / tforin11). }
  if isString and (Syms[varIdx].TypeKind <> tyAuto) and
     (Syms[varIdx].TypeKind <> tyChar) then
    Error('for-in over a string: the loop variable must be of type Char');

  { Inline `for var x in coll`: backfill x's inferred type from the
    container's element type before the body is parsed, so a use of x
    inside the body resolves (feature-inline-loop-var-rio). }
  if Syms[varIdx].TypeKind = tyAuto then
  begin
    Syms[varIdx].TypeKind := IntToTypeKind(elemTk);
    if (IntToTypeKind(elemTk) = tyRecord) and Syms[contSym].IsArray then
      Syms[varIdx].RecName := Syms[contSym].ElemRecName;
  end;

  Expect(tkDo, 'do');
  bodyNode := ParseStatementAST;

  Result := BuildForInArrayLoop(varIdx, 0, contSym, -1, 0, 0, -1, contTk,
    isString, isStaticArr, Syms[contSym].IsArray,
    Syms[contSym].ArrLen, elemTk, bodyNode);
end;

{ for x in <implicit-Self array/string field> — same desugar as
  ParseForInVarAST, but the container is an AN_FIELD over Self rather than a
  plain symbol. Reached when an unqualified for-in source resolves to a field of
  the enclosing method's class (FindSym missed it). v1 covers dyn/static array
  and string fields; set / GetEnumerator container forms are not yet reachable
  through an unqualified field. }
function ParseForInFieldAST(varIdx, selfSym, fldIdx, fOff, fLen: Integer): Integer;
var
  bodyNode, elemTk, staticLen: Integer;
  contTk: TTypeKind;
  isString, isStaticArr, isArr: Boolean;
begin
  contTk := IntToTypeKind(UFldTk[fldIdx]);
  isArr := UFldIsArray[fldIdx];
  staticLen := UFldArrLen[fldIdx];
  isStaticArr := isArr and (staticLen >= 0);
  isString := (not isArr) and ((contTk = tyString) or (contTk = tyAnsiString));

  if isString then elemTk := Ord(tyChar)
  else if isArr then elemTk := UFldTk[fldIdx]
  else begin Error('for-in: implicit-Self field is not a string or array'); elemTk := Ord(tyInteger); end;

  { Inline `for var x in SelfArrayField`: backfill x's type before the body is
    parsed (feature-inline-loop-var-rio). A record-element field array has no
    element-record lookup wired here (unlike the plain-var path's
    Syms[].ElemRecName) -- reject explicitly rather than silently leave the
    loop var's RecName unset. }
  if Syms[varIdx].TypeKind = tyAuto then
  begin
    if IntToTypeKind(elemTk) = tyRecord then
      Error('for var .. in <implicit-Self record-array field>: inline loop variable not yet supported here — declare the variable explicitly (feature-inline-loop-var-rio)');
    Syms[varIdx].TypeKind := IntToTypeKind(elemTk);
  end;

  Expect(tkDo, 'do');
  bodyNode := ParseStatementAST;

  Result := BuildForInArrayLoop(varIdx, 1, -1, selfSym, fOff, fLen, -1, contTk,
    isString, isStaticArr, isArr, staticLen, elemTk, bodyNode);
end;

{ for x in <qualified member-access lvalue> — e.g. `for it in Player.Inventory`,
  where the source is an already-parsed lvalue node (AN_FIELD / AN_IDENT) rather
  than a bare name. Classifies the node's array/string metadata from the symbol
  table and drives the node-based loop builder, which deep-copies the node for
  each use (Length bound + element access) so the two occurrences don't alias.
  v1 covers array and string fields/vars; set / GetEnumerator / nested-index
  (jagged) sources through a member-access still fall through to an error. }
function ParseForInNodeAST(varIdx, contNode: Integer): Integer;
var
  bodyNode, elemTk, staticLen, recId, fldIdx: Integer;
  setEnumId, setElemTk: Integer;
  contTk: TTypeKind;
  isString, isStaticArr, isArr: Boolean;
  fname: AnsiString;
begin
  isArr := IsNodeArray(contNode);
  staticLen := -1;
  setEnumId := -1; setElemTk := 0;
  if ASTKind[contNode] = AN_IDENT then
  begin
    contTk := Syms[ASTIVal[contNode]].TypeKind;
    if isArr then elemTk := Ord(Syms[ASTIVal[contNode]].ElemType)
    else elemTk := Ord(contTk);
    staticLen := Syms[ASTIVal[contNode]].ArrLen;
    setEnumId := SymSetEnumId[ASTIVal[contNode]];
    setElemTk := SymSetElemTk[ASTIVal[contNode]];
  end
  else if ASTKind[contNode] = AN_FIELD then
  begin
    recId := ResolveNodeRec(ASTLeft[contNode]);
    fname := GetASTIdentName(contNode);
    contTk := RecFieldType(recId, fname);   { element base type for arrays }
    elemTk := Ord(contTk);
    fldIdx := -1;
    if recId >= REC_UCLASS_BASE then fldIdx := FindUField(recId - REC_UCLASS_BASE, fname);
    if fldIdx >= 0 then
    begin
      staticLen := UFldArrLen[fldIdx];
      setEnumId := UFldSetEnumId[fldIdx];
      setElemTk := UFldSetElemTk[fldIdx];
    end;
  end
  else
  begin
    Error('for-in: unsupported iterable expression');
    contTk := tyInteger; elemTk := Ord(tyInteger);
  end;

  { set-valued qualified source (obj.field / Self.field of `set of <enum|Char>`)
    → membership scan, equivalent to the symbol-based ParseForInSetAST. The set
    node is cloned so the loop builder owns a private copy. }
  if contTk = tySet then
  begin
    { Inline `for var x in obj.field` over a set: backfill before the body is
      parsed, mirroring ParseForInSetAST (feature-inline-loop-var-rio). }
    if Syms[varIdx].TypeKind = tyAuto then
    begin
      if setElemTk = Ord(tyChar) then Syms[varIdx].TypeKind := tyChar
      else Syms[varIdx].TypeKind := tyInteger;
    end;
    Expect(tkDo, 'do');
    bodyNode := ParseStatementAST;
    Result := BuildForInSetLoop(varIdx, setEnumId, setElemTk, CloneAST(contNode), bodyNode);
    Exit;
  end;

  isStaticArr := isArr and (staticLen >= 0);
  isString := (not isArr) and ((contTk = tyString) or (contTk = tyAnsiString));
  if isString then elemTk := Ord(tyChar);

  { Inline `for var x in obj.arr` / a qualified array/string source: backfill
    x's type before the body is parsed (feature-inline-loop-var-rio). The
    AN_FIELD source has no element-record lookup wired here (same limitation
    as ParseForInFieldAST) -- reject explicitly for a record element rather
    than silently leave RecName unset; the AN_IDENT source has one via
    Syms[].ElemRecName, mirroring ParseForInVarAST. }
  if Syms[varIdx].TypeKind = tyAuto then
  begin
    if (IntToTypeKind(elemTk) = tyRecord) and (ASTKind[contNode] <> AN_IDENT) then
      Error('for var .. in <record-array field access>: inline loop variable not yet supported here — declare the variable explicitly (feature-inline-loop-var-rio)');
    Syms[varIdx].TypeKind := IntToTypeKind(elemTk);
    if (IntToTypeKind(elemTk) = tyRecord) and (ASTKind[contNode] = AN_IDENT) and isArr then
      Syms[varIdx].RecName := Syms[ASTIVal[contNode]].ElemRecName;
  end;

  Expect(tkDo, 'do');
  bodyNode := ParseStatementAST;

  Result := BuildForInArrayLoop(varIdx, 2, -1, -1, 0, 0, contNode, contTk,
    isString, isStaticArr, isArr, staticLen, elemTk, bodyNode);
end;

{ for x in <EnumType> do BODY iterates ALL enum ordinals low..high. The loop
  variable itself holds the ordinal (enum vars are integer-sized), so no separate
  index is needed:  x := 0; while x <= count-1 do begin BODY; x := x + 1; end; }
function ParseForInEnumTypeAST(varIdx, etid: Integer): Integer;
var
  bodyNode, initN, condN, incN, whileN, innerSeq: Integer;
  cnt, vtk: Integer;
begin
  { Inline `for var x in TEnum`: enums are ordinal/integer-sized (no distinct
    tyEnum), so backfilling x's type is just tyInteger, mirroring the
    resolution ParseTypeKind already uses for a named enum type
    (feature-inline-loop-var-rio). }
  if Syms[varIdx].TypeKind = tyAuto then Syms[varIdx].TypeKind := tyInteger;
  Expect(tkDo, 'do');
  bodyNode := ParseStatementAST;

  cnt := EnumTypeValCount[etid];
  vtk := Ord(Syms[varIdx].TypeKind);
  initN := GenMakeAssign(GenMakeIdent(varIdx, IntToTypeKind(vtk)), GenMakeIntLit(0));
  condN := GenMakeBinop(tkLe, GenMakeIdent(varIdx, IntToTypeKind(vtk)),
                        GenMakeIntLit(cnt - 1), tyBoolean);
  incN := GenMakeAssign(GenMakeIdent(varIdx, IntToTypeKind(vtk)),
    GenMakeBinop(tkPlus, GenMakeIdent(varIdx, IntToTypeKind(vtk)),
                 GenMakeIntLit(1), tyInteger));
  innerSeq := GenMakeSeq(bodyNode, GenMakeSeq(incN, -1));
  whileN := AllocNode(AN_WHILE);
  ASTLeft[whileN] := condN;
  ASTRight[whileN] := innerSeq;
  Result := GenMakeSeq(initN, GenMakeSeq(whileN, -1));
end;

{ ===== Stackless-generator state-machine transform =====
  Turns a `; generator; stackless;` body into a flat goto/label state machine
  compiled into the generator's own proc, whose ABI is `function(self): Boolean`
  (has-next). Persistent locals/params live in the heap instance (offsets
  SL_OFF_SLOTS + 8*SymGenSlot); the step fn restores them on entry, dispatches to
  the resume point, runs to the next `yield` (which saves state + returns True),
  and on fall-off marks done + returns False. Library-/user-only — never used in
  compiler.pas (FPC has no generators). Targets ALL backends with zero asm: the
  whole thing lowers through the existing cross-target IR (goto/if/for/while +
  ordinary calls to the slgen RTL helpers). }

function GenMakeIntLit(v: Integer): Integer;
begin
  Result := AllocNode(AN_INT_LIT);
  ASTIVal[Result] := v;
  ASTTk[Result] := Ord(tyInt64);
end;

function GenMakeBoolLit(v: Integer): Integer;
begin
  Result := AllocNode(AN_BOOL_LIT);
  ASTIVal[Result] := v;
  ASTTk[Result] := Ord(tyBoolean);
end;

{ Concatenate two statements/sequences (-1 = empty) into one. AN_SEQ nests fine. }
function chainSeq(a, b: Integer): Integer;
begin
  if a < 0 then Result := b
  else if b < 0 then Result := a
  else Result := GenMakeSeq(a, b);
end;

function GenMakeCmp(opTok, l, r: Integer): Integer;
begin
  Result := AllocNode(AN_BINOP);
  ASTIVal[Result] := opTok;
  ASTLeft[Result] := l;
  ASTRight[Result] := r;
  ASTTk[Result] := Ord(tyBoolean);
end;

function GenMakeArith(opTok, l, r: Integer): Integer;
begin
  Result := AllocNode(AN_BINOP);
  ASTIVal[Result] := opTok;
  ASTLeft[Result] := l;
  ASTRight[Result] := r;
  ASTTk[Result] := Ord(tyInt64);
end;

{ Built-in TObject.Free for `obj.Free` on a class instance with no user-declared
  `Free` method. Desugars to the nil-guarded, double-free-safe FPC idiom:
    if obj <> nil then begin [obj.Destroy;] FreeMem(obj); obj := nil end
  `Destroy` is dispatched (virtually when declared `virtual`/`override`) only when
  the class or an ancestor declares one; otherwise just the instance heap block
  (the GetMem from `TFoo.Create`) is released. Niling the var makes a second
  `Free` a no-op. symIdx must be a non-record class-instance variable. }
function GenMakeFreeObject(symIdx: Integer): Integer;
var ci, freeArg, freeCall, nilLit, nilAssign, cond, thenSeq, pairNode, ifNode: Integer;
begin
  ci := Syms[symIdx].RecName - REC_UCLASS_BASE;

  { FreeMem(obj) }
  freeArg := AllocNode(AN_ARG);
  ASTLeft[freeArg] := GenMakeIdent(symIdx, tyClass);
  freeCall := AllocNode(AN_CALL);
  ASTIVal[freeCall] := -Ord(tkFreeMem);
  ASTLeft[freeCall] := freeArg;
  ASTTk[freeCall] := Ord(tyInteger);

  { obj := nil }
  nilLit := AllocNode(AN_INT_LIT);
  ASTIVal[nilLit] := 0;
  ASTTk[nilLit] := Ord(tyPointer);
  nilAssign := GenMakeAssign(GenMakeIdent(symIdx, tyClass), nilLit);

  thenSeq := chainSeq(freeCall, nilAssign);
  if FindUMeth(ci, 'Destroy') >= 0 then
    thenSeq := chainSeq(GenMakeMethodCall0(GenMakeIdent(symIdx, tyClass), ci, 'Destroy'), thenSeq);

  { if obj <> nil then thenSeq }
  nilLit := AllocNode(AN_INT_LIT);
  ASTIVal[nilLit] := 0;
  ASTTk[nilLit] := Ord(tyPointer);
  cond := GenMakeCmp(Ord(tkNeq), GenMakeIdent(symIdx, tyClass), nilLit);
  pairNode := AllocNode(AN_PAIR);
  ASTLeft[pairNode] := thenSeq;
  ASTRight[pairNode] := -1;
  ifNode := AllocNode(AN_IF);
  ASTLeft[ifNode] := cond;
  ASTRight[ifNode] := pairNode;
  Result := ifNode;
end;

function GenMakeSelfClassFieldNode(selfIdx, fOff, fLen: Integer): Integer;
{ Fresh `Self.field` AN_FIELD node (class-typed field named by its source
  span). Each call mints new nodes — the free-desugar below references the
  lvalue several times and the AST is a tree, not a DAG. }
var fn: Integer;
begin
  fn := AllocNode(AN_FIELD);
  ASTLeft[fn] := GenMakeIdent(selfIdx, tyClass);
  ASTSOffset[fn] := fOff;
  ASTSLen[fn] := fLen;
  ASTTk[fn] := Ord(tyClass);
  Result := fn;
end;

function GenMakeFreeObjectField(selfIdx, fOff, fLen, ci: Integer): Integer;
{ `FField.Free;` on an implicit-Self class-typed field with no user Free
  method: the field twin of GenMakeFreeObject above — nil-guarded
  [Destroy;] FreeMem; field := nil. }
var freeArg, freeCall, nilLit, nilAssign, cond, thenSeq, pairNode, ifNode: Integer;
begin
  { FreeMem(Self.field) }
  freeArg := AllocNode(AN_ARG);
  ASTLeft[freeArg] := GenMakeSelfClassFieldNode(selfIdx, fOff, fLen);
  freeCall := AllocNode(AN_CALL);
  ASTIVal[freeCall] := -Ord(tkFreeMem);
  ASTLeft[freeCall] := freeArg;
  ASTTk[freeCall] := Ord(tyInteger);

  { Self.field := nil }
  nilLit := AllocNode(AN_INT_LIT);
  ASTIVal[nilLit] := 0;
  ASTTk[nilLit] := Ord(tyPointer);
  nilAssign := GenMakeAssign(GenMakeSelfClassFieldNode(selfIdx, fOff, fLen), nilLit);

  thenSeq := chainSeq(freeCall, nilAssign);
  if FindUMeth(ci, 'Destroy') >= 0 then
    thenSeq := chainSeq(GenMakeMethodCall0(GenMakeSelfClassFieldNode(selfIdx, fOff, fLen), ci, 'Destroy'), thenSeq);

  { if Self.field <> nil then thenSeq }
  nilLit := AllocNode(AN_INT_LIT);
  ASTIVal[nilLit] := 0;
  ASTTk[nilLit] := Ord(tyPointer);
  cond := GenMakeCmp(Ord(tkNeq), GenMakeSelfClassFieldNode(selfIdx, fOff, fLen), nilLit);
  pairNode := AllocNode(AN_PAIR);
  ASTLeft[pairNode] := thenSeq;
  ASTRight[pairNode] := -1;
  ifNode := AllocNode(AN_IF);
  ASTLeft[ifNode] := cond;
  ASTRight[ifNode] := pairNode;
  Result := ifNode;
end;

function GenMakeFreeObjectExpr(objNode, ci: Integer): Integer;
{ `TClass(expr).Free;` — nil-guarded [Destroy;] FreeMem over an expression
  value (ftpsend's `TFTPListRec(FList[n]).Free`). Each occurrence is a
  CloneAST of the operand (the AST is a tree, not a DAG), so a side-effecting
  operand re-evaluates — fine for the cast-of-lvalue statements this serves.
  No nil write-back: there is no lvalue (FPC's Free never nils anyway). }
var freeArg, freeCall, nilLit, cond, thenSeq, pairNode, ifNode: Integer;
begin
  freeArg := AllocNode(AN_ARG);
  ASTLeft[freeArg] := CloneAST(objNode);
  freeCall := AllocNode(AN_CALL);
  ASTIVal[freeCall] := -Ord(tkFreeMem);
  ASTLeft[freeCall] := freeArg;
  ASTTk[freeCall] := Ord(tyInteger);

  thenSeq := freeCall;
  if FindUMeth(ci, 'Destroy') >= 0 then
    thenSeq := chainSeq(GenMakeMethodCall0(CloneAST(objNode), ci, 'Destroy'), chainSeq(freeCall, -1));

  { if expr <> nil then thenSeq }
  nilLit := AllocNode(AN_INT_LIT);
  ASTIVal[nilLit] := 0;
  ASTTk[nilLit] := Ord(tyPointer);
  cond := GenMakeCmp(Ord(tkNeq), objNode, nilLit);
  pairNode := AllocNode(AN_PAIR);
  ASTLeft[pairNode] := thenSeq;
  ASTRight[pairNode] := -1;
  ifNode := AllocNode(AN_IF);
  ASTLeft[ifNode] := cond;
  ASTRight[ifNode] := pairNode;
  Result := ifNode;
end;

{ Synthetic label: a GotoLabel slot with no name; AN_LABEL/AN_GOTO reference it
  directly via ASTIVal (ASTSOffset = -1 sentinel, see ir.inc). }
function NewSyntheticLabel: Integer;
begin
  if GotoLabelCount >= MAX_GOTO_LABELS then Error('too many labels (stackless generator)');
  Result := GotoLabelCount;
  GotoLabelNOff[Result] := -1;
  GotoLabelNLen[Result] := 0;
  GotoLabelCodePos[Result] := -1;
  GotoLabelIRId[Result] := -1;
  Inc(GotoLabelCount);
end;

function GenMakeGoto(lblIdx: Integer): Integer;
begin
  Result := AllocNode(AN_GOTO);
  ASTSOffset[Result] := -1;
  ASTSLen[Result] := 0;
  ASTIVal[Result] := lblIdx;
end;

function GenMakeLabel(lblIdx: Integer): Integer;
begin
  Result := AllocNode(AN_LABEL);
  ASTSOffset[Result] := -1;
  ASTSLen[Result] := 0;
  ASTIVal[Result] := lblIdx;
end;

{ if condNode then goto lblIdx; }
function GenMakeIfGoto(condNode, lblIdx: Integer): Integer;
var pairNode: Integer;
begin
  Result := AllocNode(AN_IF);
  ASTLeft[Result] := condNode;
  pairNode := AllocNode(AN_PAIR);
  ASTLeft[pairNode] := GenMakeGoto(lblIdx);
  ASTRight[pairNode] := -1;
  ASTRight[Result] := pairNode;
end;

{ SlGet(self, off): Int64 — read a machine word from the instance. }
function GenSlGet(selfSym, off: Integer): Integer;
begin
  Result := GenMakeCall6(FindProc('SlGet'), tyInt64,
    GenMakeIdent(selfSym, tyPointer), GenMakeIntLit(off), -1, -1, -1, -1);
end;

{ SlSet(self, off, val) — write a machine word into the instance (statement). }
function GenSlSetStmt(selfSym, off, valNode: Integer): Integer;
begin
  Result := GenMakeCall6(FindProc('SlSet'), tyInt64,
    GenMakeIdent(selfSym, tyPointer), GenMakeIntLit(off), valNode, -1, -1, -1);
end;

{ Does the subtree contain a suspension point — `yield` (generator) or `await`
  (async)? Both split the state machine the same way. }
function SLHasYield(node: Integer): Boolean;
begin
  if node < 0 then begin Result := False; Exit; end;
  if (ASTKind[node] = AN_YIELD) or (ASTKind[node] = AN_AWAIT) then begin Result := True; Exit; end;
  Result := SLHasYield(ASTLeft[node]) or SLHasYield(ASTRight[node]);
end;

{ Eligibility: every yield must sit only in flattenable statement positions —
  top-level / sequence / for-body / while-body / if-branch. A yield anywhere else
  (case/repeat/with/try, a loop condition or for-bound expression, a call arg) is
  a hard error under forced `stackless`. }
procedure SLCheckEligible(node: Integer);
var pairNode: Integer;
begin
  if node < 0 then Exit;
  case ASTKind[node] of
    AN_SEQ:
      begin SLCheckEligible(ASTLeft[node]); SLCheckEligible(ASTRight[node]); end;
    AN_YIELD: ; { reached only via a good position }
    AN_AWAIT: ; { reached only via a good position }
    AN_IF:
      begin
        if SLHasYield(ASTLeft[node]) then
          Error('stackless generator: yield not allowed in an if-condition');
        pairNode := ASTRight[node];
        SLCheckEligible(ASTLeft[pairNode]);
        SLCheckEligible(ASTRight[pairNode]);
      end;
    AN_WHILE:
      begin
        if SLHasYield(ASTLeft[node]) then
          Error('stackless generator: yield not allowed in a while-condition');
        SLCheckEligible(ASTRight[node]);
      end;
    AN_FOR:
      begin
        pairNode := ASTRight[node];        { pair3: Left=pair1(init,limit), Right=pair2(isDown,body) }
        if SLHasYield(ASTLeft[pairNode]) then
          Error('stackless generator: yield not allowed in a for-bound expression');
        SLCheckEligible(ASTRight[ASTRight[pairNode]]);
      end;
    AN_CASE:
      begin
        if SLHasYield(ASTLeft[node]) then
          Error('stackless generator: yield not allowed in a case selector');
        pairNode := ASTRight[node];                  { branch chain }
        while pairNode <> -1 do
        begin
          SLCheckEligible(ASTRight[ASTLeft[pairNode]]);  { branch stmt }
          pairNode := ASTRight[pairNode];
        end;
      end;
    else
      if SLHasYield(node) then
        Error('stackless generator: yield only allowed at top level or inside for/while/if/case (not in this construct)');
  end;
end;

{ AN_SLOTADDR node for sym i — the address of the local's OWN slot. }
function GenMakeSlotAddr(i: Integer): Integer;
begin
  Result := AllocNode(AN_SLOTADDR);
  ASTIVal[Result] := i;
  ASTTk[Result] := Ord(tyPointer);
end;

{ @lvalue as an AST node (AN_ADDR keeps by-ref auto-deref semantics — an IsRef
  sym yields the caller's address, which is what a copy source wants). }
function GenMakeAddrOf(lv: Integer): Integer;
begin
  Result := AllocNode(AN_ADDR);
  ASTLeft[Result] := lv;
  ASTTk[Result] := Ord(tyPointer);
end;

{ Deref of the slot address as one machine word (raw slot READ, no by-ref
  auto-deref): used to checkpoint a by-ref param's pointer word. Pointer-typed,
  NOT Int64: the frame slot is native-pointer-width — an 8-byte store through
  this deref would clobber the neighbouring slot on the 32-bit targets. }
function GenMakeSlotWord(i: Integer): Integer;
begin
  Result := AllocNode(AN_DEREF);
  ASTLeft[Result] := GenMakeSlotAddr(i);
  ASTTk[Result] := Ord(tyPointer);
end;

{ Build a sequence of SlSet(self, slotOff, localValue) for every persistent slot
  allocated so far — called at each yield to checkpoint live locals. A by-ref
  param saves its POINTER WORD via the raw slot read; a record local blob-copies
  its bytes (SlBlob). }
function SLSaveLocals(selfSym: Integer): Integer;
var i, head, tail, stmt: Integer;
begin
  head := -1; tail := -1;
  for i := CurGenScopeBase to SymCount - 1 do
    if SymGenSlot[i] >= 0 then
    begin
      if Syms[i].IsRef then
        stmt := GenSlSetStmt(selfSym, SL_OFF_SLOTS + 8 * SymGenSlot[i],
                             GenMakeSlotWord(i))
      else if (Syms[i].TypeKind = tyRecord) and not Syms[i].IsArray then
        stmt := GenMakeCall6(FindProc('SlBlob'), tyInt64,
                  GenMakeIdent(selfSym, tyPointer),
                  GenMakeIntLit(SL_OFF_SLOTS + 8 * SymGenSlot[i]),
                  GenMakeSlotAddr(i),
                  GenMakeIntLit(RecSize(Syms[i].RecName)), -1, -1)
      else
        stmt := GenSlSetStmt(selfSym, SL_OFF_SLOTS + 8 * SymGenSlot[i],
                             GenMakeIdent(i, Syms[i].TypeKind));
      if head < 0 then begin head := GenMakeSeq(stmt, -1); tail := head; end
      else begin ASTRight[tail] := GenMakeSeq(stmt, -1); tail := ASTRight[tail]; end;
    end;
  Result := head;
end;

{ Build assignments restoring every persistent slot into its local at step entry.
  By-ref params get the pointer word written RAW into their slot (a plain assign
  to an IsRef sym would store through the — at this point garbage — pointer);
  record locals blob-copy back (SlUnblob). }
function SLRestoreLocals(selfSym: Integer): Integer;
var i, head, tail, stmt: Integer;
begin
  head := -1; tail := -1;
  for i := CurGenScopeBase to SymCount - 1 do
    if SymGenSlot[i] >= 0 then
    begin
      if Syms[i].IsRef then
        stmt := GenMakeAssign(GenMakeSlotWord(i),
                              GenSlGet(selfSym, SL_OFF_SLOTS + 8 * SymGenSlot[i]))
      else if (Syms[i].TypeKind = tyRecord) and not Syms[i].IsArray then
        stmt := GenMakeCall6(FindProc('SlUnblob'), tyInt64,
                  GenMakeIdent(selfSym, tyPointer),
                  GenMakeIntLit(SL_OFF_SLOTS + 8 * SymGenSlot[i]),
                  GenMakeSlotAddr(i),
                  GenMakeIntLit(RecSize(Syms[i].RecName)), -1, -1)
      else
        stmt := GenMakeAssign(GenMakeIdent(i, Syms[i].TypeKind),
                              GenSlGet(selfSym, SL_OFF_SLOTS + 8 * SymGenSlot[i]));
      if head < 0 then begin head := GenMakeSeq(stmt, -1); tail := head; end
      else begin ASTRight[tail] := GenMakeSeq(stmt, -1); tail := ASTRight[tail]; end;
    end;
  Result := head;
end;

function SLNewSlotVar(tk: TTypeKind): Integer;
begin
  Result := AllocVar('', tk);
  SymGenSlot[Result] := CurGenSlotNext;
  Inc(CurGenSlotNext);
end;

function SLLower(node, selfSym, retSym: Integer): Integer; forward;

{ yield E -> current:=E; state:=k; save locals; Result:=True; Exit; Lk:
  Record element: E is always an lvalue here (a record call result was already
  materialised into a hidden temp at the yield parse site, parser.inc ~8690) —
  blob-copy its bytes into the instance CURRENT region and publish the region's
  address in the CURRENT word. }
function SLLowerYield(node, selfSym, retSym: Integer): Integer;
var k, resumeLbl, setCur, setState, saveSeq, setRes, exitNode: Integer;
begin
  k := CurGenStateCtr; Inc(CurGenStateCtr);
  if k >= MAX_GEN_STATES then Error('stackless generator: too many yields');
  resumeLbl := NewSyntheticLabel;
  GenStateLabelIdx[k] := resumeLbl;

  if CurGenElemOff >= 0 then
  begin
    setCur := GenMakeCall6(FindProc('SlBlob'), tyInt64,
                GenMakeIdent(selfSym, tyPointer),
                GenMakeIntLit(CurGenElemOff),
                GenMakeAddrOf(ASTLeft[node]),
                GenMakeIntLit(RecSize(CurGenElemRecId)), -1, -1);
    setCur := GenMakeSeq(setCur,
              GenMakeSeq(GenSlSetStmt(selfSym, SL_OFF_CURRENT,
                GenMakeArith(Ord(tkPlus),
                  GenMakeIdent(selfSym, tyPointer),
                  GenMakeIntLit(CurGenElemOff))), -1));
  end
  else
    setCur := GenSlSetStmt(selfSym, SL_OFF_CURRENT, ASTLeft[node]);
  setState := GenSlSetStmt(selfSym, SL_OFF_STATE, GenMakeIntLit(k));
  saveSeq  := SLSaveLocals(selfSym);
  setRes   := GenMakeAssign(GenMakeIdent(retSym, tyBoolean), GenMakeBoolLit(1));
  exitNode := AllocNode(AN_EXIT); ASTLeft[exitNode] := -1;

  Result := GenMakeSeq(setCur,
            GenMakeSeq(setState,
            chainSeq(saveSeq,
            GenMakeSeq(setRes,
            GenMakeSeq(exitNode,
            GenMakeSeq(GenMakeLabel(resumeLbl), -1))))));
end;

{ await Stmt -> Stmt; state:=k; save locals; Result:=True; Exit; Lk:
  The awaited statement runs for its side effects, then the coroutine suspends
  (returns True = "resume me"); the scheduler re-enters and dispatch jumps to Lk.
  Unlike yield there is no produced value, so no CURRENT store. }
function SLLowerAwait(node, selfSym, retSym: Integer): Integer;
var k, resumeLbl, setState, saveSeq, setRes, exitNode: Integer;
begin
  k := CurGenStateCtr; Inc(CurGenStateCtr);
  if k >= MAX_GEN_STATES then Error('stackless async: too many await points');
  resumeLbl := NewSyntheticLabel;
  GenStateLabelIdx[k] := resumeLbl;

  setState := GenSlSetStmt(selfSym, SL_OFF_STATE, GenMakeIntLit(k));
  saveSeq  := SLSaveLocals(selfSym);
  setRes   := GenMakeAssign(GenMakeIdent(retSym, tyBoolean), GenMakeBoolLit(1));
  exitNode := AllocNode(AN_EXIT); ASTLeft[exitNode] := -1;

  { ASTLeft[node] is the awaited statement (a possibly-void call). }
  Result := chainSeq(ASTLeft[node],
            GenMakeSeq(setState,
            chainSeq(saveSeq,
            GenMakeSeq(setRes,
            GenMakeSeq(exitNode,
            GenMakeSeq(GenMakeLabel(resumeLbl), -1))))));
end;

function SLLowerIf(node, selfSym, retSym: Integer): Integer;
var pairNode, cond, thenN, elseN, elseLbl, endLbl: Integer;
    test, thenLo, elseLo: Integer;
begin
  pairNode := ASTRight[node];
  cond  := ASTLeft[node];
  thenN := ASTLeft[pairNode];
  elseN := ASTRight[pairNode];
  elseLbl := NewSyntheticLabel;
  endLbl  := NewSyntheticLabel;
  { if (cond = false) goto elseLbl }
  test := GenMakeIfGoto(GenMakeCmp(Ord(tkEq), cond, GenMakeBoolLit(0)), elseLbl);
  thenLo := SLLower(thenN, selfSym, retSym);
  elseLo := SLLower(elseN, selfSym, retSym);
  Result := GenMakeSeq(test,
            chainSeq(thenLo,
            GenMakeSeq(GenMakeGoto(endLbl),
            GenMakeSeq(GenMakeLabel(elseLbl),
            chainSeq(elseLo,
            GenMakeSeq(GenMakeLabel(endLbl), -1))))));
end;

{ Rewrite break/continue belonging to a FLATTENED loop into gotos: the loop's
  own AN_WHILE/AN_FOR node is gone after flattening, so a verbatim (yield-free)
  subtree's break/continue would reach the normal IR path with no enclosing
  loop ("continue outside loop"). Descends the body but NOT into nested loop
  constructs — those own their break/continue (flattened nested loops rewrite
  for themselves when SLLowerFor/While recurses). }
procedure SLRewriteLoopJumps(node, contLbl, brkLbl: Integer);
begin
  if node < 0 then Exit;
  case ASTKind[node] of
    AN_FOR, AN_WHILE, AN_REPEAT: Exit;   { inner loop owns its break/continue }
    AN_BREAK:
      begin
        ASTKind[node] := AN_GOTO;
        ASTSOffset[node] := -1; ASTSLen[node] := 0;
        ASTIVal[node] := brkLbl;
      end;
    AN_CONTINUE:
      begin
        ASTKind[node] := AN_GOTO;
        ASTSOffset[node] := -1; ASTSLen[node] := 0;
        ASTIVal[node] := contLbl;
      end;
    else
      begin
        SLRewriteLoopJumps(ASTLeft[node], contLbl, brkLbl);
        SLRewriteLoopJumps(ASTRight[node], contLbl, brkLbl);
      end;
  end;
end;

function SLLowerWhile(node, selfSym, retSym: Integer): Integer;
var cond, body, topLbl, endLbl, test, bodyLo: Integer;
begin
  cond := ASTLeft[node];
  body := ASTRight[node];
  topLbl := NewSyntheticLabel;
  endLbl := NewSyntheticLabel;
  test := GenMakeIfGoto(GenMakeCmp(Ord(tkEq), cond, GenMakeBoolLit(0)), endLbl);
  SLRewriteLoopJumps(body, topLbl, endLbl);
  bodyLo := SLLower(body, selfSym, retSym);
  Result := GenMakeSeq(GenMakeLabel(topLbl),
            GenMakeSeq(test,
            chainSeq(bodyLo,
            GenMakeSeq(GenMakeGoto(topLbl),
            GenMakeSeq(GenMakeLabel(endLbl), -1)))));
end;

function SLLowerFor(node, selfSym, retSym: Integer): Integer;
var pair1, pair2, forVarNode, varSym: Integer;
    initN, limitN, isDown, body: Integer;
    limSym, topLbl, endLbl, incLbl: Integer;
    setVar, setLim, test, bodyLo, incN, cmpOp: Integer;
    vTk: TTypeKind;
begin
  forVarNode := ASTLeft[node];
  varSym := ASTIVal[forVarNode];
  vTk := Syms[varSym].TypeKind;
  pair1 := ASTLeft[ASTRight[node]];      { (init, limit) }
  pair2 := ASTRight[ASTRight[node]];     { (isDown, body) }
  initN  := ASTLeft[pair1];
  limitN := ASTRight[pair1];
  isDown := ASTIVal[ASTLeft[pair2]];
  body   := ASTRight[pair2];

  limSym := SLNewSlotVar(tyInt64);       { evaluate limit once (persistent) }
  topLbl := NewSyntheticLabel;
  endLbl := NewSyntheticLabel;
  incLbl := NewSyntheticLabel;           { continue target: run the increment }

  setVar := GenMakeAssign(GenMakeIdent(varSym, vTk), initN);
  setLim := GenMakeAssign(GenMakeIdent(limSym, tyInt64), limitN);

  if isDown <> 0 then cmpOp := Ord(tkLt) else cmpOp := Ord(tkGt);
  { ascending: exit when var > limit; descending: exit when var < limit }
  test := GenMakeIfGoto(
            GenMakeCmp(cmpOp, GenMakeIdent(varSym, vTk), GenMakeIdent(limSym, tyInt64)),
            endLbl);

  SLRewriteLoopJumps(body, incLbl, endLbl);
  bodyLo := SLLower(body, selfSym, retSym);

  if isDown <> 0 then
    incN := GenMakeAssign(GenMakeIdent(varSym, vTk),
              GenMakeArith(Ord(tkMinus), GenMakeIdent(varSym, vTk), GenMakeIntLit(1)))
  else
    incN := GenMakeAssign(GenMakeIdent(varSym, vTk),
              GenMakeArith(Ord(tkPlus), GenMakeIdent(varSym, vTk), GenMakeIntLit(1)));

  Result := GenMakeSeq(setVar,
            GenMakeSeq(setLim,
            GenMakeSeq(GenMakeLabel(topLbl),
            GenMakeSeq(test,
            chainSeq(bodyLo,
            GenMakeSeq(GenMakeLabel(incLbl),
            GenMakeSeq(incN,
            GenMakeSeq(GenMakeGoto(topLbl),
            GenMakeSeq(GenMakeLabel(endLbl), -1)))))))));
end;

{ case with a yield in a branch: flatten to the same test/goto shape the IR
  lowering (ir.inc AN_CASE) emits, but at the AST level so branch bodies can
  recurse through SLLower and split at their yields. The selector is evaluated
  ONCE into a plain (non-persistent) temp — it is only consulted by the label
  tests, which all run before the first suspension; a resume jumps straight to
  the label inside the chosen branch and never re-tests.
  See feature-stackless-generator-yield-in-case. }
function SLLowerCase(node, selfSym, retSym: Integer): Integer;
var selTmp, setSel, endLbl, branchSeq, branchPair, labelsHead, stmtNode: Integer;
    bodyLbl, nextLbl, skipLbl, labelNode, valNode, cv, hi: Integer;
    tests, piece: Integer;
begin
  selTmp := AllocVar('', tyInt64);
  setSel := GenMakeAssign(GenMakeIdent(selTmp, tyInt64), ASTLeft[node]);
  endLbl := NewSyntheticLabel;
  Result := GenMakeSeq(setSel, -1);

  branchSeq := ASTRight[node];
  while branchSeq <> -1 do
  begin
    branchPair := ASTLeft[branchSeq];
    labelsHead := ASTLeft[branchPair];
    stmtNode   := ASTRight[branchPair];
    if labelsHead = -1 then
    begin
      { else clause (parser builds it last): body runs when every prior test
        fell through; falls off into endLbl. }
      Result := chainSeq(Result, SLLower(stmtNode, selfSym, retSym));
    end
    else
    begin
      bodyLbl := NewSyntheticLabel;
      nextLbl := NewSyntheticLabel;
      tests := -1;
      labelNode := labelsHead;
      while labelNode <> -1 do
      begin
        valNode := ASTLeft[labelNode];
        if (ASTKind[valNode] = AN_STR_LIT) or
           ((ASTRight[valNode] <> -1) and (ASTKind[ASTRight[valNode]] = AN_STR_LIT)) then
          Error('stackless generator: case-of-string around a yield is not supported');
        cv := ASTIVal[valNode];
        if ASTRight[valNode] <> -1 then
        begin
          { range lo..hi: below lo -> skip both tests; else <= hi -> body }
          hi := ASTIVal[ASTRight[valNode]];
          skipLbl := NewSyntheticLabel;
          piece := GenMakeSeq(
            GenMakeIfGoto(GenMakeCmp(Ord(tkLt),
              GenMakeIdent(selTmp, tyInt64), GenMakeIntLit(cv)), skipLbl),
            GenMakeSeq(
              GenMakeIfGoto(GenMakeCmp(Ord(tkLe),
                GenMakeIdent(selTmp, tyInt64), GenMakeIntLit(hi)), bodyLbl),
              GenMakeSeq(GenMakeLabel(skipLbl), -1)));
        end
        else
          piece := GenMakeIfGoto(GenMakeCmp(Ord(tkEq),
            GenMakeIdent(selTmp, tyInt64), GenMakeIntLit(cv)), bodyLbl);
        tests := chainSeq(tests, piece);
        labelNode := ASTRight[labelNode];
      end;
      Result := chainSeq(Result,
                GenMakeSeq(tests,
                GenMakeSeq(GenMakeGoto(nextLbl),
                GenMakeSeq(GenMakeLabel(bodyLbl),
                chainSeq(SLLower(stmtNode, selfSym, retSym),
                GenMakeSeq(GenMakeGoto(endLbl),
                GenMakeSeq(GenMakeLabel(nextLbl), -1)))))));
    end;
    branchSeq := ASTRight[branchSeq];
  end;
  Result := chainSeq(Result, GenMakeSeq(GenMakeLabel(endLbl), -1));
end;

{ Lower one statement (recursively). Constructs WITHOUT a yield are emitted
  verbatim — they reference the restored stack locals like any code. Constructs
  that (transitively) contain a yield are flattened to goto/label form. }
function SLLower(node, selfSym, retSym: Integer): Integer;
begin
  if node < 0 then begin Result := -1; Exit; end;
  if ASTKind[node] = AN_SEQ then
  begin
    Result := GenMakeSeq(SLLower(ASTLeft[node], selfSym, retSym),
                         SLLower(ASTRight[node], selfSym, retSym));
    Exit;
  end;
  if not SLHasYield(node) then begin Result := node; Exit; end;
  case ASTKind[node] of
    AN_YIELD: Result := SLLowerYield(node, selfSym, retSym);
    AN_AWAIT: Result := SLLowerAwait(node, selfSym, retSym);
    AN_IF:    Result := SLLowerIf(node, selfSym, retSym);
    AN_WHILE: Result := SLLowerWhile(node, selfSym, retSym);
    AN_FOR:   Result := SLLowerFor(node, selfSym, retSym);
    AN_CASE:  Result := SLLowerCase(node, selfSym, retSym);
    else      Error('stackless generator: unsupported construct around yield');
  end;
end;

{ Any persistent record slot in the current generator scope? }
function SLHasRecordSlot: Boolean;
var i: Integer;
begin
  Result := False;
  for i := CurGenScopeBase to SymCount - 1 do
    if (SymGenSlot[i] >= 0) and (Syms[i].TypeKind = tyRecord) and
       (not Syms[i].IsArray) and (not Syms[i].IsRef) then
      begin Result := True; Exit; end;
end;

{ Build the full step-function body AST for a stackless generator proc `procIdx`.
  Persistent slots for the declared params + body locals must already be assigned
  (SymGenSlot). Returns the AST to CompileAST; sets CurGenSlotNext to its final
  value (caller derives ProcGenInstSize). }
function BuildStacklessStep(bodyAST, procIdx: Integer): Integer;
var selfSym, retSym, bodyLo, dispatch, dtail, restore: Integer;
    setDone, setRes, k, stmt: Integer;
begin
  if (FindProc('SlGet') < 0) or (FindProc('SlSet') < 0) then
    Error('stackless generator: the slgen unit is not in scope (add `uses slgen;`)');
  selfSym := Procs[procIdx].Params[0].SymIdx;
  retSym  := Procs[procIdx].RetSymIdx;

  { Record element type: reserve a record-sized CURRENT region at the current
    instance tail (synthetic slot vars appended by the transform land after it —
    offsets just need stability, not order). SL_OFF_CURRENT then holds a POINTER
    to this region; for-in derefs it into the loop variable. }
  CurGenElemOff := -1;
  CurGenElemRecId := REC_NONE;
  if ProcGenElemTk[procIdx] = tyRecord then
  begin
    CurGenElemRecId := ProcGenElemRec[procIdx];
    CurGenElemOff := SL_OFF_SLOTS + 8 * CurGenSlotNext;
    Inc(CurGenSlotNext, (RecSize(CurGenElemRecId) + 7) div 8);
  end;
  { Record locals / record element need the blob helpers (older slgen lacks them). }
  if (CurGenElemOff >= 0) or SLHasRecordSlot then
    if (FindProc('SlBlob') < 0) or (FindProc('SlUnblob') < 0) then
      Error('stackless generator: record support needs slgen SlBlob/SlUnblob (update lib/rtl/slgen.pas in scope)');

  CurGenStateCtr := 1;                   { state 0 = first entry (falls through) }
  bodyLo := SLLower(bodyAST, selfSym, retSym);

  { Dispatch: for each yield-state k, if state=k goto its resume label. }
  dispatch := -1; dtail := -1;
  for k := 1 to CurGenStateCtr - 1 do
  begin
    stmt := GenMakeIfGoto(
              GenMakeCmp(Ord(tkEq), GenSlGet(selfSym, SL_OFF_STATE), GenMakeIntLit(k)),
              GenStateLabelIdx[k]);
    if dispatch < 0 then begin dispatch := GenMakeSeq(stmt, -1); dtail := dispatch; end
    else begin ASTRight[dtail] := GenMakeSeq(stmt, -1); dtail := ASTRight[dtail]; end;
  end;

  restore := SLRestoreLocals(selfSym);

  { Fall-off: mark exhausted, return False. }
  setDone := GenSlSetStmt(selfSym, SL_OFF_DONE, GenMakeIntLit(1));
  setRes  := GenMakeAssign(GenMakeIdent(retSym, tyBoolean), GenMakeBoolLit(0));

  Result := chainSeq(restore,
            chainSeq(dispatch,
            chainSeq(bodyLo,
            GenMakeSeq(setDone,
            GenMakeSeq(setRes, -1)))));
end;

{ Assign a persistent instance slot to each declared param + body local of a
  stackless generator proc (skipping the hidden self param and the Boolean
  Result). Order = sym-allocation order, so declared params land in slots
  0..paramCnt-1 — matching how SlAlloc stores the for-in arguments. Sets
  CurGenSlotNext; the transform appends synthetic temps after these. v1: only
  ordinal/pointer-sized locals (managed/aggregate locals would need per-element
  ARC across yields — a documented later restriction). }
procedure AssignStacklessSlots(procIdx: Integer);
var i, selfS, retS: Integer; tk: TTypeKind;
begin
  selfS := Procs[procIdx].Params[0].SymIdx;
  retS  := Procs[procIdx].RetSymIdx;
  CurGenSlotNext := 0;
  CurGenScopeBase := Procs[procIdx].ScopeBase;
  for i := Procs[procIdx].ScopeBase to SymCount - 1 do
  begin
    if (i = selfS) or (i = retS) then Continue;
    if (Syms[i].Kind <> skParam) and (Syms[i].Kind <> skLocal) then Continue;
    tk := Syms[i].TypeKind;
    if Syms[i].IsRef then
    begin
      { by-ref (var/const-record) param: the slot persists the caller ADDRESS
        (one pointer word); save/restore go through AN_SLOTADDR so the word
        itself is copied, never the pointee. }
      SymGenSlot[i] := CurGenSlotNext;
      Inc(CurGenSlotNext);
      Continue;
    end;
    if (tk = tyRecord) and not Syms[i].IsArray then
    begin
      { record local: reserve RecSize bytes of slot region (rounded up to
        words); save/restore blob-copy it (SlBlob/SlUnblob). Plain-data
        records only — a record with managed (string/dynarray) fields would
        need per-field ARC across suspensions and is rejected.
        See feature-stackless-generator-record-locals. }
      if RecordHasManagedFields(Syms[i].RecName) then
        Error('stackless generator: a record local with managed (string/dynarray) fields is not supported');
      SymGenSlot[i] := CurGenSlotNext;
      Inc(CurGenSlotNext, (RecSize(Syms[i].RecName) + 7) div 8);
      Continue;
    end;
    if Syms[i].IsArray or
       (tk = tyString) or (tk = tyAnsiString) or
       (tk = tySet) or (tk = tyVariant) then
      Error('stackless generator: only ordinal/pointer/record locals are supported (arrays/strings/sets/variants pending)');
    SymGenSlot[i] := CurGenSlotNext;
    Inc(CurGenSlotNext);
  end;
end;

function ParseForStatementAST: Integer;
var
  varIdx, initNode, limitNode, bodyNode, node: Integer;
  pair1, pair2, pair3, isDownNode: Integer;
  gpi, fsym: Integer;
  selfClassCi, fldIdx, fldTokIdx, selfSym: Integer;
  srcIdx, srcTokIdx: Integer;
  down, inlineVar: Boolean;
begin
  { Delphi 10.3 Rio inline loop variable: `for var i := 0 to N` / `for var x in c`
    declares a fresh routine-local counter instead of binding an existing one.
    Forward-compatible — classic `for i := ...` (i pre-declared) is unchanged.
    Counted form -> Integer; for-in form -> tyAuto (element type inferred by the
    for-in path). Gated on EnableAutoVar (the inline-`var` inference switch).
    See feature-inline-loop-var-rio. }
  inlineVar := False;
  if EnableAutoVar and (CurTok.Kind = tkVar) then begin Next; inlineVar := True; end;
  if CurTok.Kind <> tkIdent then Error('for: expected variable');
  if inlineVar then
  begin
    { Counted `for var i := a to b`: fresh Integer counter. For-in
      `for var x in c`: fresh tyAuto local; each ParseForIn*AST variant that
      supports it backfills Syms[varIdx].TypeKind (and RecName, for a record
      element) from the iterable's element type before parsing the loop body,
      so a use of x inside the body resolves -- see feature-inline-loop-var-rio.
      Variants that don't support it yet (generator / GetEnumerator) reject a
      tyAuto loop var with their own clear error. }
    if (TokPos < TokCount) and (Tokens[TokPos].Kind = tkIn) then
      varIdx := AllocVar(CurTok.SVal, tyAuto)
    else
      varIdx := AllocVar(CurTok.SVal, tyInteger);
  end
  else
  begin
    varIdx := FindSym(CurTok.SVal);
    { --auto-locals / {$IMPLICITVARS ON}: an undeclared for-counter is created
      as an implicit local (like the `for var i` inline form, but no keyword) —
      counted form -> Integer, for-in -> tyAuto (element type backfilled by the
      for-in variant). Loops are the primary sloppy-mode use. See
      feature-implicit-locals-sloppy-switch. }
    if (varIdx < 0) and ImplicitVars then
    begin
      if (TokPos < TokCount) and (Tokens[TokPos].Kind = tkIn) then
        varIdx := AllocVar(CurTok.SVal, tyAuto)
      else
        varIdx := AllocVar(CurTok.SVal, tyInteger);
      WarnImplicitVar(CurTok.Line, CurTok.SVal);
    end;
    if varIdx < 0 then
    begin
      ErrorIdent := CurTok.SVal;
      if HiddenByDeclOrder(CurTok.SVal) then
        Error('for counter is a global declared later — declare it before use, or add a local')
      else
        Error('for: undefined');
    end;
  end;
  Next;
  if CurTok.Kind = tkIn then
  begin
    Next;
    if CurTok.Kind <> tkIdent then Error('for-in: expected a generator, enum type, or iterable variable');
    { qualified member-access / indexed source (`obj.field`, `Self.field`,
      `a.b[i]`...): the ident is followed by a `.`/`[` selector, so it is not a
      bare name — parse it as a general lvalue node and drive the node-based
      loop. Must come before the bare-name lookups: a local object var would
      otherwise match FindSym and then choke on the trailing `.`. }
    if (TokPos < TokCount) and (Tokens[TokPos].Kind in [tkDot, tkLBrack]) then
    begin
      srcIdx := FindSym(CurTok.SVal); srcTokIdx := TokPos - 1; Next;
      Result := ParseForInNodeAST(varIdx, ParseLValueAST(srcIdx, srcTokIdx));
      Exit;
    end;
    { generator call → existing coroutine/stackless desugar }
    gpi := FindProc(CurTok.SVal);
    if (gpi >= 0) and ProcIsGenerator[gpi] then
    begin
      Next;
      Result := ParseForInGeneratorAST(varIdx, gpi);
      Exit;
    end;
    { enum type name → iterate all ordinals }
    fsym := FindEnumType(CurTok.SVal);
    if fsym >= 0 then
    begin
      if EnumTypeHasHoles[fsym] then
        Error('for-in: the enum has non-contiguous values (explicit ordinals) — iteration order is undefined');
      Next;
      Result := ParseForInEnumTypeAST(varIdx, fsym);
      Exit;
    end;
    { iterable variable (string / array / dynarray / open-array param) }
    fsym := FindSym(CurTok.SVal);
    if fsym >= 0 then
    begin
      Next;
      Result := ParseForInVarAST(varIdx, fsym);
      Exit;
    end;
    { implicit-Self array/string field as the iterable (unqualified `Items`
      inside a method, the same resolution `Self.Items` gets). FindSym only
      sees locals/globals, so a field lands here. Only a *bare* field (next
      token `do`) is taken — `for x in Self.Field` and `for x in obj.field`
      qualified member-access sources are a separate, broader feature. }
    if (CurSelfClass >= REC_UCLASS_BASE) and (CurProc >= 0) and (Procs[CurProc].ParamCount > 0)
       and (TokPos < TokCount) and (Tokens[TokPos].Kind = tkDo) then
    begin
      selfClassCi := CurSelfClass - REC_UCLASS_BASE;
      fldIdx := FindUField(selfClassCi, CurTok.SVal);
      if fldIdx >= 0 then
      begin
        selfSym := Procs[CurProc].Params[0].SymIdx;
        fldTokIdx := TokPos - 1;
        Next;
        Result := ParseForInFieldAST(varIdx, selfSym, fldIdx,
                    Tokens[fldTokIdx].SOffset, Tokens[fldTokIdx].SLen);
        Exit;
      end;
    end;
    Error('for-in: not a generator, enum type, or iterable variable');
  end;
  Expect(tkAssign, ':=');
  ParseExpr; initNode := CurASTNode;
  down := CurTok.Kind = tkDownto;
  if down then Next else Expect(tkTo, 'to');
  ParseExpr; limitNode := CurASTNode;
  Expect(tkDo, 'do');
  bodyNode := ParseStatementAST;

  node := AllocNode(AN_FOR);
  ASTLeft[node] := AllocNode(AN_IDENT);
  ASTIVal[ASTLeft[node]] := varIdx;

  pair1 := AllocNode(AN_PAIR);
  ASTLeft[pair1] := initNode;
  ASTRight[pair1] := limitNode;

  isDownNode := AllocNode(AN_INT_LIT);
  if down then ASTIVal[isDownNode] := 1 else ASTIVal[isDownNode] := 0;

  pair2 := AllocNode(AN_PAIR);
  ASTLeft[pair2] := isDownNode;
  ASTRight[pair2] := bodyNode;

  pair3 := AllocNode(AN_PAIR);
  ASTLeft[pair3] := pair1;
  ASTRight[pair3] := pair2;

  ASTRight[node] := pair3;
  Result := node;
end;

function ParseRepeatStatementAST: Integer;
var
  seqNode, lastSeq, condNode, stmtNode, node: Integer;
begin
  seqNode := AllocNode(AN_SEQ);
  lastSeq := seqNode;
  while not (CurTok.Kind in [tkUntil, tkEOF]) do
  begin
    stmtNode := ParseStatementAST;
    Eat(tkSemicolon);
    if ASTLeft[lastSeq] = -1 then
      ASTLeft[lastSeq] := stmtNode
    else
    begin
      ASTRight[lastSeq] := AllocNode(AN_SEQ);
      lastSeq := ASTRight[lastSeq];
      ASTLeft[lastSeq] := stmtNode;
    end;
  end;
  Expect(tkUntil, 'until');
  ParseExpr; condNode := CurASTNode;
  node := AllocNode(AN_REPEAT);
  ASTLeft[node] := seqNode;
  ASTRight[node] := condNode;
  Result := node;
end;

{ One case-label constant. Selector type is unknown until IR lowering, so a
  string literal keeps its full text: length-1 -> char-ordinal AN_INT_LIT with
  the source span preserved (ASTSOffset/ASTSLen, so a string-typed selector can
  still rebuild the literal), any other length (incl. empty) -> AN_STR_LIT.
  The IR lowering (ir.inc AN_CASE) picks the char/ordinal or string path from
  the selector's type and validates label kinds against it. }
function ParseCaseLabelValue(const what: AnsiString): Integer;
var node, si, prevTok: Integer; neg: Boolean;
begin
  neg := False;
  if CurTok.Kind = tkMinus then
  begin
    neg := True;
    Next;
    if CurTok.Kind <> tkInteger then Error(what + ' must be constant');
  end;
  if CurTok.Kind = tkInteger then
  begin
    node := AllocNode(AN_INT_LIT);
    if neg then ASTIVal[node] := -CurTok.IVal
    else ASTIVal[node] := CurTok.IVal;
  end
  else if CurTok.Kind = tkString then
  begin
    prevTok := TokPos - 1;
    if Length(CurTok.SVal) = 1 then
    begin
      node := AllocNode(AN_INT_LIT);
      ASTIVal[node] := Ord(CurTok.SVal[1]);
      ASTTk[node] := Ord(tyChar);
    end
    else
    begin
      node := AllocNode(AN_STR_LIT);
      ASTTk[node] := Ord(tyString);
    end;
    ASTSOffset[node] := Tokens[prevTok].SOffset;
    ASTSLen[node] := Tokens[prevTok].SLen;
  end
  else if CurTok.Kind = tkIdent then
  begin
    si := FindSym(CurTok.SVal);
    if (si >= 0) and (Syms[si].Kind = skConst) then
    begin
      node := AllocNode(AN_INT_LIT);
      ASTIVal[node] := Syms[si].ConstVal;
      if Syms[si].TypeKind = tyChar then ASTTk[node] := Ord(tyChar);
    end
    else if (si < 0) and (TokPos + 1 < TokCount) and
            (Tokens[TokPos].Kind = tkDot) and (Tokens[TokPos+1].Kind = tkIdent) and
            (FindEnumType(CurTok.SVal) >= 0) and
            FindEnumMemberOrd(FindEnumType(CurTok.SVal), GetTokenStr(TokPos+1), prevTok) then
    begin
      { `TEnum.member` case label (scoped enums) — prevTok reused for the
        member ordinal. The trailing Next below consumes the member name. }
      node := AllocNode(AN_INT_LIT);
      ASTIVal[node] := prevTok;
      Next; Next;   { TEnum, '.' }
    end
    else Error(what + ' must be constant');
  end
  else Error('expected ' + what);
  Next;
  Result := node;
end;

function ParseCaseStatementAST: Integer;
var
  condNode, branchSeq, lastBranch, branchPair, labelsHead, lastLabel, labelValNode: Integer;
  stmtNode, node: Integer;
  hasElse: Boolean;
  elseLast, elseStmt, wdPos: Integer;
begin
  ParseExpr; condNode := CurASTNode;
  Expect(tkOf, 'of');

  branchSeq := AllocNode(AN_SEQ);
  lastBranch := branchSeq;
  hasElse := False;

  while (not (CurTok.Kind in [tkEnd, tkEOF])) and not hasElse do
  begin
    { `otherwise` (ISO 10206; FPC default mode) = soft-keyword synonym of
      `else` here. Only special at branch-start inside case, so a variable
      named `otherwise` stays usable everywhere else. }
    if (CurTok.Kind = tkElse) or
       ((CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'otherwise')) then
    begin
      hasElse := True;
      Next;
      { `case...else` takes an implicit statement LIST up to `end` (like
        try/except's exception-handler list, or a bare begin...end block) --
        not a single statement. A single ParseStatementAST call left any
        statement after the first one unconsumed, desyncing the parser and
        producing a confusing error far from the real cause (bug-case-else-
        multi-statement-parse-error). Mirrors ParseBlockAST's AN_SEQ chain +
        progress watchdog. }
      stmtNode := AllocNode(AN_SEQ);
      elseLast := stmtNode;
      while not (CurTok.Kind in [tkEnd, tkEOF]) do
      begin
        wdPos := TokPos;
        elseStmt := ParseStatementAST;
        Eat(tkSemicolon);
        if TokPos <= wdPos then
          Error('internal parser bug: statement made no progress in case-else (would hang)');
        if ASTLeft[elseLast] = -1 then
          ASTLeft[elseLast] := elseStmt
        else
        begin
          ASTRight[elseLast] := AllocNode(AN_SEQ);
          elseLast := ASTRight[elseLast];
          ASTLeft[elseLast] := elseStmt;
        end;
      end;

      branchPair := AllocNode(AN_PAIR);
      ASTLeft[branchPair] := -1;
      ASTRight[branchPair] := stmtNode;

      if ASTLeft[lastBranch] = -1 then
        ASTLeft[lastBranch] := branchPair
      else
      begin
        ASTRight[lastBranch] := AllocNode(AN_SEQ);
        lastBranch := ASTRight[lastBranch];
        ASTLeft[lastBranch] := branchPair;
      end;
    end
    else
    begin
      labelsHead := AllocNode(AN_ARG);
      lastLabel := labelsHead;
      repeat
        labelValNode := ParseCaseLabelValue('case label');

        { Range label `lo..hi`: stash hi in a second value node hung off
          ASTRight of the lo node; the IR lowering reads it as a [lo,hi]
          inclusive range test instead of a single equality. }
        if Eat(tkDotDot) then
          ASTRight[labelValNode] := ParseCaseLabelValue('case range upper bound');

        if ASTLeft[lastLabel] = -1 then
          ASTLeft[lastLabel] := labelValNode
        else
        begin
          ASTRight[lastLabel] := AllocNode(AN_ARG);
          lastLabel := ASTRight[lastLabel];
          ASTLeft[lastLabel] := labelValNode;
        end;
      until not Eat(tkComma);
      Expect(tkColon, ':');

      stmtNode := ParseStatementAST;
      Eat(tkSemicolon);

      branchPair := AllocNode(AN_PAIR);
      ASTLeft[branchPair] := labelsHead;
      ASTRight[branchPair] := stmtNode;

      if ASTLeft[lastBranch] = -1 then
        ASTLeft[lastBranch] := branchPair
      else
      begin
        ASTRight[lastBranch] := AllocNode(AN_SEQ);
        lastBranch := ASTRight[lastBranch];
        ASTLeft[lastBranch] := branchPair;
      end;
    end;
  end;
  Expect(tkEnd, 'end');

  node := AllocNode(AN_CASE);
  ASTLeft[node] := condNode;
  ASTRight[node] := branchSeq;
  Result := node;
end;

{ ===== File-handle (Text) keyword IO dispatch =====
  When `Text` is in scope (the implicit-textfile unit was loaded by a `var f:
  Text` declaration), Write/WriteLn/Read/ReadLn with a Text-typed first argument
  are rewritten to calls into the textfile RTL (TextWrite/TextWriteLn/
  TextReadLn) instead of the console builtins. The console path is untouched when
  no `Text` record exists (IsRecordType('text') = REC_NONE), so the compiler
  self-host output is byte-identical. }

{ Convert one write value into a string-valued node for TextWrite. Strings pass
  through; integers go via StrInt(x, width), floats via StrFloat(x, width, dec) —
  the same builtin formatters the console Str(...) lowering uses. widthNode /
  decNode are AST expression nodes (-1 = default width 0 / decimals -1). }
function TextStrArg(exprNode, widthNode, decNode: Integer): Integer;
var tk: TTypeKind; pi: Integer;
begin
  tk := IntToTypeKind(ASTTk[exprNode]);
  if widthNode < 0 then widthNode := GenMakeIntLit(0);
  if TypeIsFrozenString(tk) or (tk = tyAnsiString) then
    Result := exprNode
  else if TypeIsFloat(tk) then
  begin
    pi := FindProc('StrFloat');
    if pi < 0 then Error('write(Text): StrFloat not loaded (add `uses textfile;` deps)');
    if decNode < 0 then decNode := GenMakeIntLit(-1);
    Result := GenMakeCall6(pi, Procs[pi].RetType, exprNode,
                widthNode, decNode, -1, -1, -1);
  end
  else if TypeIsOrdinal(tk) and (tk <> tyChar) then
  begin
    pi := FindProc('StrInt');
    if pi < 0 then Error('write(Text): StrInt not loaded');
    Result := GenMakeCall6(pi, Procs[pi].RetType, exprNode,
                widthNode, -1, -1, -1, -1);
  end
  else
  begin
    Error('write(Text): unsupported argument type (string/integer/float only)');
    Result := exprNode;
  end;
end;

{ Rewrite `write[ln](f, v0, v1, ...)` over a Text handle into a sequence of
  TextWrite calls; for writeln the final value goes through TextWriteLn so the
  newline lands once after the last value. `fileSym` is the Text var; the caller
  has left CurTok on its identifier. }
function ParseTextWriteRest(isLn: Boolean; fileSym: Integer): Integer;
var
  procWrite, procWriteLn, callNode, sNode, exprNode: Integer;
  width, decw, headSeq, tailSeq, lastCall, emptyStr, newSeq: Integer;
begin
  Next;  { consume the Text file identifier }
  procWrite := FindProc('TextWrite');
  procWriteLn := FindProc('TextWriteLn');
  if (procWrite < 0) or (procWriteLn < 0) then
    Error('write(Text): textfile RTL not loaded');
  headSeq := -1; tailSeq := -1; lastCall := -1;
  while Eat(tkComma) do
  begin
    ParseExpr; exprNode := CurASTNode;
    { :width[:decimals] — ordinary integer expressions (FPC-legal), -1 = absent }
    width := -1; decw := -1;
    if CurTok.Kind = tkColon then
    begin
      Next;
      ParseExpr; width := CurASTNode;
      if CurTok.Kind = tkColon then
      begin
        Next;
        ParseExpr; decw := CurASTNode;
      end;
    end;
    sNode := TextStrArg(exprNode, width, decw);
    callNode := GenMakeCall6(procWrite, tyUnknown, GenMakeIdent(fileSym, tyRecord),
                             sNode, -1, -1, -1, -1);
    newSeq := GenMakeSeq(callNode, -1);
    if headSeq = -1 then headSeq := newSeq else ASTRight[tailSeq] := newSeq;
    tailSeq := newSeq;
    lastCall := callNode;
  end;
  Expect(tkRParen, ')');
  if isLn then
  begin
    if lastCall >= 0 then
      ASTIVal[lastCall] := procWriteLn   { last value carries the newline }
    else
    begin
      { writeln(f) with no values — newline only. An empty string literal
        (SLen=0) feeds TextWriteLn so just the '\n' is emitted. }
      emptyStr := AllocNode(AN_STR_LIT);
      ASTSOffset[emptyStr] := 0; ASTSLen[emptyStr] := 0; ASTTk[emptyStr] := Ord(tyString);
      callNode := GenMakeCall6(procWriteLn, tyUnknown, GenMakeIdent(fileSym, tyRecord),
                               emptyStr, -1, -1, -1, -1);
      headSeq := GenMakeSeq(callNode, -1);
    end;
  end;
  if headSeq = -1 then headSeq := GenMakeSeq(-1, -1);  { write(f) no values: no-op }
  Result := headSeq;
end;

{ Rewrite `read[ln](f, dest0, dest1, ...)` over a Text handle into TextReadLn
  calls (one per destination). v1 is line-oriented; read and readln map to the
  same line read. }
function ParseTextReadRest(fileSym: Integer): Integer;
var procRead, callNode, destNode, headSeq, tailSeq, newSeq: Integer;
begin
  Next;  { consume the Text file identifier }
  procRead := FindProc('TextReadLn');
  if procRead < 0 then Error('read(Text): textfile RTL not loaded');
  headSeq := -1; tailSeq := -1;
  while Eat(tkComma) do
  begin
    ParseExpr; destNode := CurASTNode;
    callNode := GenMakeCall6(procRead, tyUnknown, GenMakeIdent(fileSym, tyRecord),
                             destNode, -1, -1, -1, -1);
    newSeq := GenMakeSeq(callNode, -1);
    if headSeq = -1 then headSeq := newSeq else ASTRight[tailSeq] := newSeq;
    tailSeq := newSeq;
  end;
  Expect(tkRParen, ')');
  if headSeq = -1 then headSeq := GenMakeSeq(-1, -1);
  Result := headSeq;
end;

{ A Text-typed first argument? Only ever true once the implicit-textfile unit is
  loaded, so the console path is unaffected otherwise. Returns the file var sym
  or -1. }
function TextIOFileSym: Integer;
var textRecId, vidx: Integer;
begin
  Result := -1;
  textRecId := IsRecordType('text');
  if (textRecId = REC_NONE) or (CurTok.Kind <> tkIdent) then Exit;
  { Must be a BARE Text handle (next token `,` or `)`), not `f.field` / `f[i]` —
    `WriteLn(f.Name)` is a console write of the string field, not a file write. }
  if not ((TokPos < TokCount) and (Tokens[TokPos].Kind in [tkComma, tkRParen])) then Exit;
  vidx := FindSym(CurTok.SVal);
  if (vidx >= 0) and (Syms[vidx].TypeKind = tyRecord) and (Syms[vidx].RecName = textRecId) then
    Result := vidx;
end;

function ParseReadArgsAST(isLn: Boolean): Integer;
{ readln/read(target, ...): each target is an lvalue (ident/field/index). The
  args are kept as an AN_ARG chain; IR lowering takes each one's address and
  parses a value from the line buffer by the target's type. }
var node, argNode, lastArg, fileSym: Integer;
begin
  node := AllocNode(AN_READLN);
  if not isLn then ASTKind[node] := AN_READ;
  ASTLeft[node] := -1;
  if CurTok.Kind = tkLParen then
  begin
    Next;
    { read[ln](f, ...) over a Text handle → textfile RTL }
    fileSym := TextIOFileSym;
    if fileSym >= 0 then
    begin
      Result := ParseTextReadRest(fileSym);
      Exit;
    end;
    lastArg := -1;
    repeat
      ParseExpr;
      argNode := AllocNode(AN_ARG);
      ASTLeft[argNode] := CurASTNode;
      if lastArg = -1 then
        ASTLeft[node] := argNode
      else
        ASTRight[lastArg] := argNode;
      lastArg := argNode;
    until not Eat(tkComma);
    Expect(tkRParen, ')');
  end;
  Result := node;
end;

function ParsewriteArgsAST(isLn: Boolean): Integer;
var
  node, argNode, lastArg, exprNode, vidx, widthVal, decimalsVal: Integer;
begin
  node := AllocNode(AN_WRITE);
  if isLn then ASTKind[node] := AN_WRITELN;

  if CurTok.Kind = tkLParen then
  begin
    Next;
    { write[ln](f, ...) over a Text handle → textfile RTL (must precede the
      StdErr/console handling; a Text var is never the StdErr const). }
    vidx := TextIOFileSym;
    if vidx >= 0 then
    begin
      Result := ParseTextWriteRest(isLn, vidx);
      Exit;
    end;
    lastArg := -1;
    if CurTok.Kind = tkIdent then
    begin
      vidx := FindSym(CurTok.SVal);
      if (vidx >= 0) and (Syms[vidx].Kind = skConst) and (Syms[vidx].TypeKind = tyInteger) and (Syms[vidx].Name = 'StdErr') then
      begin
        Next; Eat(tkComma);
        { Route this write to fd 2. ASTIVal on the WRITE node carries the target
          fd (0/absent = stdout); codegen threads it to the write syscalls. }
        ASTIVal[node] := Syms[vidx].ConstVal;
      end;
    end;
    repeat
      ParseExpr; exprNode := CurASTNode;
      argNode := AllocNode(AN_ARG);
      ASTLeft[argNode] := exprNode;
      { Parse optional :width[:decimals] format specifiers. Literal (or
        const-folded) widths keep the classic path: codegen reads them off
        the WRITE arg node (ASTIVal/ASTSOffset). A VARIABLE width/decimals
        (FPC-legal, e.g. writeln(x:w:d)) can't ride those literal slots, so
        the value is pre-formatted through the same StrInt/StrFloat builtins
        the Str(...) lowering uses and written as a plain string. }
      widthVal := -1; decimalsVal := -1;
      if CurTok.Kind = tkColon then
      begin
        Next;
        ParseExpr; widthVal := CurASTNode;
        if CurTok.Kind = tkColon then
        begin
          Next;
          ParseExpr; decimalsVal := CurASTNode;
        end;
      end;
      if ((widthVal < 0) or (ASTKind[widthVal] = AN_INT_LIT)) and
         ((decimalsVal < 0) or (ASTKind[decimalsVal] = AN_INT_LIT)) then
      begin
        { literal path: stash the raw values on the arg node as before }
        if widthVal < 0 then ASTIVal[argNode] := 0
        else ASTIVal[argNode] := ASTIVal[widthVal];
        if decimalsVal < 0 then ASTSOffset[argNode] := -1
        else ASTSOffset[argNode] := ASTIVal[decimalsVal];
      end
      else
      begin
        { variable width/decimals: pre-format to a string node }
        if not (TypeIsFloat(IntToTypeKind(ASTTk[exprNode])) or
                (TypeIsOrdinal(IntToTypeKind(ASTTk[exprNode])) and
                 not (IntToTypeKind(ASTTk[exprNode]) in [tyChar, tyBoolean]))) then
          Error('write: variable width needs an integer or float value');
        ASTLeft[argNode] := TextStrArg(exprNode, widthVal, decimalsVal);
        ASTIVal[argNode] := 0;
        ASTSOffset[argNode] := -1;
      end;
      if lastArg = -1 then
        ASTLeft[node] := argNode
      else
        ASTRight[lastArg] := argNode;
      lastArg := argNode;
    until not Eat(tkComma);
    Expect(tkRParen, ')');
  end;
  Result := node;
end;

function ParseBlockAST: Integer;
var
  seqNode, lastSeq, stmtNode, savedBlockId, wdPos: Integer;
begin
  savedBlockId := CurBlockId;
  if EnableLazyVar then
  begin
    if BlockCount >= 32767 then Error('too many blocks');
    Inc(BlockCount);
    BlockParent[BlockCount] := CurBlockId;
    CurBlockId := BlockCount;
  end;

  seqNode := AllocNode(AN_SEQ);
  lastSeq := seqNode;
  while not (CurTok.Kind in [tkEnd, tkEOF, tkUntil]) do
  begin
    wdPos := TokPos;
    stmtNode := ParseStatementAST;
    Eat(tkSemicolon);
    { Watchdog: a statement that consumes no tokens would spin this loop forever
      (no progress, never reaching tkEnd). Bound it — turn an internal parser
      defect into a diagnostic instead of a hang (Error reports CurTok.Line).
      See bug-compiler-hang-on-nested-if-in-begin. }
    if TokPos <= wdPos then
      Error('internal parser bug: statement made no progress in block (would hang)');
    if ASTLeft[lastSeq] = -1 then
      ASTLeft[lastSeq] := stmtNode
    else
    begin
      ASTRight[lastSeq] := AllocNode(AN_SEQ);
      lastSeq := ASTRight[lastSeq];
      ASTLeft[lastSeq] := stmtNode;
    end;
  end;

  if EnableLazyVar then
  begin
    CurBlockId := savedBlockId;
  end;
  Result := seqNode;
end;

function ParseTryStatementAST: Integer;
var
  trySeq, tryLast, actionSeq, stmtNode, node: Integer;
  handlerHead, lastHandler, handlerNode, handlerVar, ci, recId: Integer;
  handlerName, className: AnsiString;
begin
  { yield inside try/except/finally is rejected in v1 — track nesting so a yield
    anywhere within (body, handler, or finally) is caught. }
  Inc(GenTryDepth);
  trySeq := AllocNode(AN_SEQ);
  tryLast := trySeq;
  while not (CurTok.Kind in [tkExcept, tkFinally, tkEnd, tkEOF]) do
  begin
    stmtNode := ParseStatementAST;
    Eat(tkSemicolon);
    if ASTLeft[tryLast] = -1 then
      ASTLeft[tryLast] := stmtNode
    else
    begin
      ASTRight[tryLast] := AllocNode(AN_SEQ);
      tryLast := ASTRight[tryLast];
      ASTLeft[tryLast] := stmtNode;
    end;
  end;

  if CurTok.Kind = tkFinally then
  begin
    Next;
    actionSeq := ParseBlockAST;
    Expect(tkEnd, 'end');
    node := AllocNode(AN_TRY_FINALLY);
  end
  else
  begin
    Expect(tkExcept, 'except');
    handlerHead := -1;
    lastHandler := -1;
    if CurTok.Kind = tkOn then
    begin
      while CurTok.Kind = tkOn do
      begin
        Next;
        if CurTok.Kind <> tkIdent then Error('on: expected handler variable');
        handlerName := CurTok.SVal;
        Next;
        if CurTok.Kind = tkColon then
        begin
          { `on E: TClass do` — named binder form. }
          Next;
          if CurTok.Kind <> tkIdent then Error('on: expected class type');
          className := CurTok.SVal;
          Next;
        end
        else
        begin
          { `on TClass do` — binderless FPC/Delphi form (Synapse synautil's
            `except on Exception do ;`): the first ident IS the class; bind a
            hidden variable so the handler machinery stays uniform. }
          className := handlerName;
          handlerName := '__on_anon';
        end;
        ci := FindUClass(className);
        if ci < 0 then Error('on: unknown exception class');
        recId := REC_UCLASS_BASE + ci;
        Expect(tkDo, 'do');
        handlerVar := AllocVar(handlerName, tyClass);
        Syms[handlerVar].RecName := recId;
        Inc(ExceptionHandlerParseDepth);
        actionSeq := ParseStatementAST;
        Dec(ExceptionHandlerParseDepth);
        Eat(tkSemicolon);
        handlerNode := AllocNode(AN_EXC_HANDLER);
        ASTIVal[handlerNode] := recId;
        ASTSOffset[handlerNode] := handlerVar;
        ASTLeft[handlerNode] := actionSeq;
        if handlerHead = -1 then handlerHead := handlerNode
        else ASTRight[lastHandler] := handlerNode;
        lastHandler := handlerNode;
      end;
      if Eat(tkElse) then
      begin
        Inc(ExceptionHandlerParseDepth);
        actionSeq := ParseBlockAST;
        Dec(ExceptionHandlerParseDepth);
        handlerNode := AllocNode(AN_EXC_HANDLER);
        ASTIVal[handlerNode] := -1;
        ASTSOffset[handlerNode] := -1;
        ASTLeft[handlerNode] := actionSeq;
        ASTRight[lastHandler] := handlerNode;
        lastHandler := handlerNode;
      end;
    end
    else
    begin
      Eat(tkElse); { Untyped catch-all handler form. }
      Inc(ExceptionHandlerParseDepth);
      actionSeq := ParseBlockAST;
      Dec(ExceptionHandlerParseDepth);
      handlerNode := AllocNode(AN_EXC_HANDLER);
      ASTIVal[handlerNode] := -1;
      ASTSOffset[handlerNode] := -1;
      ASTLeft[handlerNode] := actionSeq;
      handlerHead := handlerNode;
    end;
    Expect(tkEnd, 'end');
    node := AllocNode(AN_TRY_EXCEPT);
    actionSeq := handlerHead;
  end;
  ASTLeft[node] := trySeq;
  ASTRight[node] := actionSeq;
  Dec(GenTryDepth);
  Result := node;
end;

function ParseAsmStatementAST: Integer;
var
  node, startOff, len: Integer;
begin
  AsmParseBody(startOff, len);
  node := AllocNode(AN_ASM);
  ASTLeft[node] := startOff;
  ASTRight[node] := len;
  Result := node;
end;

function ParseWithStatementAST: Integer;
var
  varNode, bodyNode, wTmp, wAssign, wIdent, wSeq: Integer;
begin
  ParseExpr;
  varNode := CurASTNode;

  { A side-effecting with-operand (`with TFTPSend.Create do` — ftpsend's
    helpers) must evaluate ONCE: every member access shares the operand node,
    and a shared CALL node re-compiles (re-creating the object) per access.
    Materialise class-typed call results into a hidden temp and let the body
    reference the temp; the assignment is prepended to the result. }
  wAssign := -1;
  if (IntToTypeKind(ASTTk[varNode]) = tyClass) and
     ((ASTKind[varNode] = AN_CALL) or (ASTKind[varNode] = AN_VIRTUAL_CALL) or
      (ASTKind[varNode] = AN_CALL_IND)) then
  begin
    wTmp := AllocVar('', tyClass);
    Syms[wTmp].RecName := ResolveNodeRec(varNode);
    wIdent := AllocNode(AN_IDENT);
    ASTIVal[wIdent] := wTmp;
    ASTTk[wIdent] := Ord(tyClass);
    wAssign := AllocNode(AN_ASSIGN);
    ASTLeft[wAssign] := wIdent;
    ASTRight[wAssign] := varNode;
    varNode := AllocNode(AN_IDENT);
    ASTIVal[varNode] := wTmp;
    ASTTk[varNode] := Ord(tyClass);
  end;

  if Eat(tkComma) then
  begin
    { Push with variable }
    WithStack[WithStackDepth] := varNode;
    Inc(WithStackDepth);

    bodyNode := ParseWithStatementAST();

    { Pop }
    Dec(WithStackDepth);
  end
  else
  begin
    Expect(tkDo, 'do');

    { Push with variable }
    WithStack[WithStackDepth] := varNode;
    Inc(WithStackDepth);

    bodyNode := ParseStatementAST;

    { Pop }
    Dec(WithStackDepth);
  end;

  if wAssign >= 0 then
  begin
    wSeq := AllocNode(AN_SEQ);
    ASTLeft[wSeq] := wAssign;
    ASTRight[wSeq] := AllocNode(AN_SEQ);
    ASTLeft[ASTRight[wSeq]] := bodyNode;
    Result := wSeq;
  end
  else
    Result := bodyNode;
end;

function ParseLazyVarDeclAST: Integer;
var
  names: array[0..MAX_DECL_NAMES-1] of AnsiString;
  nameTokIdx: array[0..MAX_DECL_NAMES-1] of Integer;
  n, i, idx, assignNode, seqNode, lastSeq, node, valueNode, declNode: Integer;
  tk: TTypeKind;
  isArr: Boolean;
  arrLo, arrHi: Integer;
begin
  n := 0;
  repeat
    if CurTok.Kind <> tkIdent then Error('expected identifier in var declaration');
    if n >= MAX_DECL_NAMES then Error('too many comma-separated names in one var declaration');
    names[n] := CurTok.SVal;
    nameTokIdx[n] := TokPos - 1;
    Inc(n); Next;
  until not Eat(tkComma);

  tk := tyAuto;
  isArr := False; arrLo := 0; arrHi := 0;
  
  if Eat(tkColon) then
  begin
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
        Expect(tkOf, 'of');
      end
      else
        isArr := False;
    end;
    tk := ParseTypeKind;
  end;

  assignNode := -1;
  if Eat(tkAssign) then
  begin
    if n > 1 then Error('initialization is only supported for single variable declarations');
    
    ParseExpr;
    valueNode := CurASTNode;
    
    idx := AllocVar(names[0], tk);
    if (tk = tyInteger) and (LastTypeEnumId >= 0) then SymEnumId[idx] := LastTypeEnumId;
    if isArr then
    begin
      Syms[idx].IsArray := True;
      Syms[idx].ArrLen := arrHi - arrLo + 1;
    end;
    
    if Syms[idx].TypeKind = tyAuto then
    begin
      if ASTKind[valueNode] = AN_DEFAULT then
        Error('cannot infer type from default; specify type explicitly');
      if (LastExprTk = tyUnknown) or (LastExprTk = tyAuto) then
        Error('cannot infer type for auto variable');
      InferSymTypeFromNode(idx, valueNode);
      AllocateSymOffset(idx);
    end;

    node := AllocNode(AN_IDENT);
    ASTIVal[node] := idx;
    ASTSOffset[node] := Tokens[nameTokIdx[0]].SOffset;
    ASTSLen[node] := Tokens[nameTokIdx[0]].SLen;
    ASTTk[node] := Ord(Syms[idx].TypeKind);

    assignNode := AllocNode(AN_ASSIGN);
    ASTLeft[assignNode] := node;
    ASTRight[assignNode] := valueNode;
    ASTTk[assignNode] := Ord(Syms[idx].TypeKind);

    declNode := AllocNode(AN_VAR_DECL);
    ASTIVal[declNode] := idx;
    ASTLeft[declNode] := assignNode;
    Result := declNode;
  end
  else
  begin
    if tk = tyAuto then Error('auto variable must have an initialization');
    
    seqNode := AllocNode(AN_SEQ);
    lastSeq := seqNode;
    for i := 0 to n - 1 do
    begin
      idx := AllocVar(names[i], tk);
      if (tk = tyInteger) and (LastTypeEnumId >= 0) then SymEnumId[idx] := LastTypeEnumId;
      if isArr then
      begin
        Syms[idx].IsArray := True;
        Syms[idx].ArrLen := arrHi - arrLo + 1;
      end;
      
      declNode := AllocNode(AN_VAR_DECL);
      ASTIVal[declNode] := idx;
      ASTLeft[declNode] := -1;
      
      if ASTLeft[lastSeq] = -1 then
        ASTLeft[lastSeq] := declNode
      else
      begin
        ASTRight[lastSeq] := AllocNode(AN_SEQ);
        lastSeq := ASTRight[lastSeq];
        ASTLeft[lastSeq] := declNode;
      end;
    end;
    Result := seqNode;
  end;
end;

function MkForAsc(varIdx, initN, limitN, bodyN: Integer): Integer;
{ Synthesise `for <varIdx> := <initN> to <limitN> do <bodyN>` (ascending),
  matching ParseForStatementAST's AN_FOR layout. }
var node, p1, p2, p3, dn: Integer;
begin
  node := AllocNode(AN_FOR);
  ASTLeft[node] := AllocNode(AN_IDENT);
  ASTIVal[ASTLeft[node]] := varIdx;
  p1 := AllocNode(AN_PAIR); ASTLeft[p1] := initN; ASTRight[p1] := limitN;
  dn := AllocNode(AN_INT_LIT); ASTIVal[dn] := 0;       { 0 = ascending (to) }
  p2 := AllocNode(AN_PAIR); ASTLeft[p2] := dn; ASTRight[p2] := bodyN;
  p3 := AllocNode(AN_PAIR); ASTLeft[p3] := p1; ASTRight[p3] := p2;
  ASTRight[node] := p3;
  Result := node;
end;

function BuildSetLenNest(target, k: Integer): Integer; forward;

function BuildSetLenNest(target, k: Integer): Integer;
{ Inner levels of a multidim SetLength (k >= 1, so `target` is always a sub-array
  index node -> dynamic-array SetLength, -102). Returns
  `SetLength(target, dim[k])` for the last dim, else that plus
  `for i := 0 to dim[k]-1 do BuildSetLenNest(target[i], k+1)`. Dim exprs are
  re-cloned per use, so they must be side-effect-free (the FPC norm). }
var argSeq, call, loopVar, idxN, inner, limitN, lo, one, forN, seqN: Integer;
begin
  argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := target;
  ASTRight[argSeq] := AllocNode(AN_ARG);
  ASTLeft[ASTRight[argSeq]] := CloneAST(SetLenDimNode[k]);
  call := AllocNode(AN_CALL); ASTIVal[call] := -102; ASTLeft[call] := argSeq;
  if k = SetLenDimN - 1 then begin Result := call; Exit; end;
  loopVar := AllocVar('', tyInteger);
  idxN := AllocNode(AN_INDEX);
  ASTLeft[idxN] := CloneAST(target);
  ASTRight[idxN] := AllocNode(AN_IDENT); ASTIVal[ASTRight[idxN]] := loopVar;
  inner := BuildSetLenNest(idxN, k + 1);
  limitN := AllocNode(AN_BINOP); ASTIVal[limitN] := Ord(tkMinus);
  ASTLeft[limitN] := CloneAST(SetLenDimNode[k]);
  one := AllocNode(AN_INT_LIT); ASTIVal[one] := 1; ASTTk[one] := Ord(tyInteger);
  ASTRight[limitN] := one;
  lo := AllocNode(AN_INT_LIT); ASTTk[lo] := Ord(tyInteger);
  forN := MkForAsc(loopVar, lo, limitN, inner);
  seqN := AllocNode(AN_SEQ); ASTLeft[seqN] := call; ASTRight[seqN] := forN;
  Result := seqN;
end;

function BuildMultiSetLen(target: Integer; outerIsArr: Boolean): Integer;
{ Build the whole `SetLength(target, d0 [, d1, ...])` from the dim nodes in
  SetLenDimNode[0..SetLenDimN-1]. Single-dim returns just the call (same as the
  classic path); multidim adds nested loops sizing the sub-arrays. }
var argSeq, outerCall, loopVar, idxN, inner, limitN, lo, one, forN: Integer;
begin
  argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := target;
  ASTRight[argSeq] := AllocNode(AN_ARG);
  ASTLeft[ASTRight[argSeq]] := CloneAST(SetLenDimNode[0]);
  outerCall := AllocNode(AN_CALL);
  if outerIsArr then ASTIVal[outerCall] := -102 else ASTIVal[outerCall] := -101;
  ASTLeft[outerCall] := argSeq;
  if SetLenDimN = 1 then begin Result := outerCall; Exit; end;
  loopVar := AllocVar('', tyInteger);
  idxN := AllocNode(AN_INDEX);
  ASTLeft[idxN] := CloneAST(target);
  ASTRight[idxN] := AllocNode(AN_IDENT); ASTIVal[ASTRight[idxN]] := loopVar;
  inner := BuildSetLenNest(idxN, 1);
  limitN := AllocNode(AN_BINOP); ASTIVal[limitN] := Ord(tkMinus);
  ASTLeft[limitN] := CloneAST(SetLenDimNode[0]);
  one := AllocNode(AN_INT_LIT); ASTIVal[one] := 1; ASTTk[one] := Ord(tyInteger);
  ASTRight[limitN] := one;
  lo := AllocNode(AN_INT_LIT); ASTTk[lo] := Ord(tyInteger);
  forN := MkForAsc(loopVar, lo, limitN, inner);
  Result := AllocNode(AN_SEQ); ASTLeft[Result] := outerCall; ASTRight[Result] := forN;
end;

function ParseStatementAST: Integer;
var
  name: AnsiString;
   idx, procIdx, i, si, node, valNode, stepsNode, opNode, argSeq, argIdx, exprNode, lastArg, identTokIdx: Integer;
  nArgs, argsHead, currArg: Integer; argTypes: array[0..MAX_PROC_PARAMS-1] of TTypeKind;
  isLn, slIsArrTarget, slIsDynArr: Boolean;
  smci, smmii, smpii, smcallNode, smselfArg, smLastArg, smArgSeq, smMai, smSelfIdx: Integer;
  aliasIdx, fieldNode, indexNode, castPrevTok, qUnit: Integer;
  castFieldName: AnsiString; castTk: TTypeKind; castRec: Integer;
  decVal, decNode: Integer; strIsFloat: Boolean;
  valTmpSym, valTmpAssign, valTmpIdent: Integer;
begin
  node := -1;
  case CurTok.Kind of
    tkInteger_T, tkLongWord_T, tkChar_T, tkBoolean_T:
    begin
      { Cast-as-lvalue store: `Integer(expr^) := v` (fgl's
        `T(inherited Insert(Index)^) := Item` after substitution). The inner
        expression's trailing ^ yields an AN_DEREF; retag it to the cast's
        width so the store truncates like the cast. }
      castTk := tyInteger;
      if CurTok.Kind = tkLongWord_T then castTk := tyUInt32
      else if CurTok.Kind = tkChar_T then castTk := tyChar
      else if CurTok.Kind = tkBoolean_T then castTk := tyBoolean
      else if CaseEqual(CurTok.SVal, 'byte') then castTk := tyUInt8
      else if CaseEqual(CurTok.SVal, 'longint') or CaseEqual(CurTok.SVal, 'integer') then castTk := tyInteger
      else if CaseEqual(CurTok.SVal, 'int64') then castTk := tyInt64;
      Next; Expect(tkLParen, '(');
      ParseExpr;
      valNode := CurASTNode;
      Expect(tkRParen, ')');
      if ASTKind[valNode] <> AN_DEREF then
        Error('cast-as-lvalue statement requires a pointer deref inside the cast');
      ASTTk[valNode] := Ord(castTk);
      Expect(tkAssign, ':=');
      ParseExpr;
      node := AllocNode(AN_ASSIGN);
      ASTLeft[node] := valNode;
      ASTRight[node] := CurASTNode;
    end;
    tkVar:
    begin
      if not EnableLazyVar then Error('Lazy Variable Declarations are disabled; use --lazy-var to enable');
      Next;
      node := ParseLazyVarDeclAST;
    end;

    tkwriteln, tkwrite, tkReadln, tkRead:
    begin
      { A function named Read/Write/Readln/Writeln assigning its own result:
        `Read := x` / `Write.field := x`. The name lexes as an intrinsic token, so
        catch the own-name result assignment before the intrinsic statement —
        otherwise it silently misparses as a Read/Write intrinsic. }
      if (CurProc >= 0) and Procs[CurProc].IsFunc and
         (Tokens[TokPos].Kind in [tkAssign, tkDot, tkLBrack, tkCaret]) and
         CaseEqual(CurTok.SVal, LastDotName(Procs[CurProc].Name)) then
      begin
        { Assigning the function result by its own name, where that name is an
          intrinsic keyword (Read/Write/Readln/Writeln). Build the same
          AN_ASSIGN(Result, expr) as the non-keyword own-name path in the tkIdent
          case. See bug-virtual-keyword-name-result. }
        Next;   { consume the keyword-name token }
        if CurTok.Kind = tkAssign then
        begin
          Expect(tkAssign, ':=');
          valNode := AllocNode(AN_IDENT);
          ASTIVal[valNode] := Procs[CurProc].RetSymIdx;
        end
        else
        begin
          valNode := ParseLValueAST(Procs[CurProc].RetSymIdx, TokPos - 2);
          Expect(tkAssign, ':=');
        end;
        ParseExpr;
        node := AllocNode(AN_ASSIGN);
        ASTLeft[node] := valNode;
        ASTRight[node] := CurASTNode;
      end
      else if (CurProc >= 0) and (CurSelfClass >= REC_UCLASS_BASE) and
              (Tokens[TokPos].Kind = tkLParen) and
              (FindUMeth(CurSelfClass - REC_UCLASS_BASE, CurTok.SVal) >= 0) then
      begin
        { An unqualified `Read`/`Write`/`Readln`/`Writeln` naming a METHOD of the
          enclosing class binds to that member (Self.method), like FPC — not the
          console intrinsic. The names lex as intrinsic keyword tokens, so this is
          caught here before the intrinsic statement. Guarded on a following `(`,
          so a bare console `Write`/`Writeln` (or a class with no such member)
          keeps the intrinsic path; the own-name result assignment is rejected
          above. Mirrors the implicit-Self method statement dispatch in the tkIdent
          case. See bug-bare-read-write-in-method-hits-intrinsic. }
        smci := CurSelfClass - REC_UCLASS_BASE;
        smmii := FindUMeth(smci, CurTok.SVal);
        smpii := UMthProc_[smmii];
        Next; { consume the method name token }
        smSelfIdx := Procs[CurProc].Params[0].SymIdx;
        smselfArg := AllocNode(AN_ARG);
        valNode := AllocNode(AN_IDENT);
        ASTIVal[valNode] := smSelfIdx;
        ASTTk[valNode] := Ord(tyClass);
        ASTLeft[smselfArg] := valNode;
        if UMthVirSlot[smmii] >= 0 then
        begin
          smcallNode := AllocNode(AN_VIRTUAL_CALL);
          ASTRight[smcallNode] := UMthVirSlot[smmii];
        end
        else
          smcallNode := AllocNode(AN_CALL);
        ASTIVal[smcallNode] := smpii;
        if smpii >= 0 then
          ASTTk[smcallNode] := Ord(Procs[smpii].RetType)
        else
          ASTTk[smcallNode] := Ord(tyInteger);
        ASTLeft[smcallNode] := smselfArg;
        smLastArg := smselfArg;
        Next; { consume '(' }
        smMai := 1;
        while CurTok.Kind <> tkRParen do
        begin
          ParseExpr;
          smArgSeq := AllocNode(AN_ARG);
          ASTLeft[smArgSeq] := CurASTNode;
          ASTRight[smLastArg] := smArgSeq;
          smLastArg := smArgSeq;
          Inc(smMai);
          if CurTok.Kind = tkComma then Next;
        end;
        Expect(tkRParen, ')');
        node := smcallNode;
      end
      else if (CurTok.Kind = tkwriteln) or (CurTok.Kind = tkwrite) then
      begin
        isLn := CurTok.Kind = tkwriteln; Next;
        node := ParsewriteArgsAST(isLn);
      end
      else
      begin
        isLn := CurTok.Kind = tkReadln; Next;
        node := ParseReadArgsAST(isLn);
      end;
    end;

    tkRaise:
    begin
      Next;
      valNode := -1;
      if CurTok.Kind in [tkSemicolon, tkEnd, tkElse, tkExcept, tkUntil, tkEOF] then
      begin
        if ExceptionHandlerParseDepth = 0 then
          Error('raise without expression requires an exception handler');
      end
      else
      begin
        ParseExpr;
        valNode := CurASTNode;
        { FPC `raise E at addr[, frame]`: the at-clause only overrides the
          REPORTED address/frame. pxx's unwinder derives both itself — skip
          the clause tokens (they may use FPC-only get_caller_addr/get_frame
          intrinsics, so don't semantically parse them). }
        if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'at') then
          while not (CurTok.Kind in [tkSemicolon, tkEnd, tkElse, tkExcept, tkUntil, tkEOF]) do
            Next;
      end;
      node := AllocNode(AN_RAISE);
      ASTLeft[node] := valNode;
    end;

    tkSyswrite:
    begin
      Next; Expect(tkLParen, '(');
      ParseExpr; argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode; Expect(tkComma, ',');
      argIdx := FindSym(CurTok.SVal); identTokIdx := TokPos - 1; Next;
      valNode := ParseLValueAST(argIdx, identTokIdx);
      if (argIdx < 0) or not Syms[argIdx].IsArray then Error('Syswrite: not an array var');
      Expect(tkComma, ',');

      ASTRight[argSeq] := AllocNode(AN_ARG);
      ASTLeft[ASTRight[argSeq]] := valNode;

      ParseExpr;
      ASTRight[ASTRight[argSeq]] := AllocNode(AN_ARG);
      ASTLeft[ASTRight[ASTRight[argSeq]]] := CurASTNode;
      Expect(tkRParen, ')');

      node := AllocNode(AN_CALL);
      ASTIVal[node] := -Ord(tkSyswrite);
      ASTLeft[node] := argSeq;
    end;

    tkSysClose:
    begin
      Next; Expect(tkLParen, '(');
      ParseExpr; Expect(tkRParen, ')');
      node := AllocNode(AN_CALL);
      ASTIVal[node] := -Ord(tkSysClose);
      argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
      ASTLeft[node] := argSeq;
    end;

    tkSysFchmod:
    begin
      Next; Expect(tkLParen, '(');
      ParseExpr; argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode; Expect(tkComma, ',');
      ParseExpr;
      ASTRight[argSeq] := AllocNode(AN_ARG);
      ASTLeft[ASTRight[argSeq]] := CurASTNode;
      Expect(tkRParen, ')');

      node := AllocNode(AN_CALL);
      ASTIVal[node] := -Ord(tkSysFchmod);
      ASTLeft[node] := argSeq;
    end;

    tkArgStr:
    begin
      Next; Expect(tkLParen, '(');
      ParseExpr; argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode; Expect(tkComma, ',');
      if CurTok.Kind <> tkIdent then Error('ArgStr: expected string var');
      argIdx := FindSym(CurTok.SVal); identTokIdx := TokPos - 1; Next;
      valNode := ParseLValueAST(argIdx, identTokIdx);
      if (argIdx < 0) or
         (not (TypeIsFrozenString(Syms[argIdx].TypeKind) or
               (Syms[argIdx].TypeKind = tyAnsiString))) then Error('ArgStr: not a string var');
      Expect(tkRParen, ')');

      ASTRight[argSeq] := AllocNode(AN_ARG);
      ASTLeft[ASTRight[argSeq]] := valNode;

      node := AllocNode(AN_CALL);
      ASTIVal[node] := -Ord(tkArgStr);
      ASTLeft[node] := argSeq;
    end;

    tkIf:     begin Next; node := ParseIfStatementAST;    end;
    tkWhile:  begin Next; node := ParseWhileStatementAST; end;
    tkFor:    begin Next; node := ParseForStatementAST;   end;
    tkRepeat: begin Next; node := ParseRepeatStatementAST; end;
    tkCase:   begin Next; node := ParseCaseStatementAST;  end;
    tkTry:    begin Next; node := ParseTryStatementAST; end;
    tkWith:   begin Next; node := ParseWithStatementAST;  end;
    tkAsm:    begin Next; node := ParseAsmStatementAST;   end;

    tkBegin:
    begin
      Next;
      node := ParseBlockAST;
      Expect(tkEnd, 'end');
    end;

    tkIdent:
    begin
      name := CurTok.SVal;
      qUnit := ConsumeUnitQualifier(name);
      { Finalize(x[, n]) — releases a managed value in FPC. pxx manages
        AnsiStrings by scope/assignment (ARC), so v1 parses-and-discards the
        call (no-op). NOTE: a Finalize-reliant container leaks managed
        elements until this maps onto the ARC release helpers. }
      if (qUnit < 0) and CaseEqual(name, 'Finalize') and
         (Tokens[TokPos].Kind = tkLParen) and
         (FindProc(name) < 0) and (FindSym(name) < 0) and
         ((CurSelfClass < REC_UCLASS_BASE) or
          (FindUMeth(CurSelfClass - REC_UCLASS_BASE, name) < 0)) then
      begin
        Next; Expect(tkLParen, '(');
        i := 1;
        while (i > 0) and (CurTok.Kind <> tkEOF) do
        begin
          if CurTok.Kind = tkLParen then Inc(i)
          else if CurTok.Kind = tkRParen then Dec(i);
          if i > 0 then Next;
        end;
        Expect(tkRParen, ')');
        Result := GenMakeSeq(-1, -1);
        Exit;
      end;

      { Bare Move(...) / FillChar(...): soft-alias to the hidden builtin
        helpers (__pxxMove/__pxxFillChar) so the System primitives resolve
        with no `uses` (FPC parity) WITHOUT a real proc named Move/FillChar
        that would shadow a user proc, an in-scope symbol, or a method of the
        enclosing class (implicit-Self `Move(d)` inside a class with its own
        Move must stay a method call — the adventure-demo regression). }
      if (qUnit < 0) and (CaseEqual(name, 'Move') or CaseEqual(name, 'FillChar') or
          CaseEqual(name, 'FillByte') or CaseEqual(name, 'FillDWord')) and
         (Tokens[TokPos].Kind = tkLParen) and
         (FindProc(name) < 0) and (FindSym(name) < 0) and
         ((qUnit = -2) or (CurSelfClass < REC_UCLASS_BASE) or
          (FindUMeth(CurSelfClass - REC_UCLASS_BASE, name) < 0)) and
         (FindProc('__pxxMove') >= 0) then
      begin
        { FillByte(x, n, b) = FillChar with an ordinal value; FillDWord fills
          n 4-byte words. Both route to the byte filler (FillDWord's count is
          scaled by the wrapper in builtin). }
        if CaseEqual(name, 'Move') then name := '__pxxMove'
        else if CaseEqual(name, 'FillDWord') then name := '__pxxFillDWord'
        else name := '__pxxFillChar';
      end;
      { Label definition: 'labelname:' as a statement }
      if Tokens[TokPos].Kind = tkColon then
      begin
        node := AllocNode(AN_LABEL);
        ASTSOffset[node] := Tokens[TokPos-1].SOffset;
        ASTSLen[node]    := Tokens[TokPos-1].SLen;
        Next; Next; { consume ident and colon }
        Result := node;
        Exit;
      end;
      { Indirect call through a procedural-type variable: v(args) as a statement. }
      si := FindSym(name);
      if (si >= 0) and (SymProcSig[si] >= 0) and (Tokens[TokPos].Kind = tkLParen) then
        node := ParseProcVarCallAST(si, SymProcSig[si])
      else if CaseEqual(name, 'inherited') then
        node := ParseInheritedCallAST
      else if CaseEqual(name, 'yield') then
      begin
        { `yield E` — only inside a generator body; forbidden inside try/except/
          finally in v1 (sidesteps the cross-stack exception-frame swap). }
        if not CurProcIsGenerator then
          Error('yield must appear directly in a generator body, not in a ' +
                'nested routine (inline the helper for now)');
        if GenTryDepth > 0 then
          Error('yield inside try/except/finally is not allowed (v1)');
        Next;
        ParseExpr;
        exprNode := CurASTNode;
        { A record-returning call (or any non-addressable aggregate) yielded
          directly has no address for the stackful current-slot, so IRLowerAddress
          fell through to IR_UNSUPPORTED. Materialise it into a generator-frame
          local first, then yield that local — the same lvalue path that
          `tmp := MkRec(...)` uses. The stackful frame keeps the temp alive until
          the next resume. }
        if (IntToTypeKind(ASTTk[exprNode]) = tyRecord) and
           not (ASTKind[exprNode] in [AN_IDENT, AN_FIELD, AN_INDEX, AN_DEREF]) then
        begin
          idx := AllocVar('', tyRecord);
          InferSymTypeFromNode(idx, exprNode);
          AllocateSymOffset(idx);
          opNode := GenMakeAssign(GenMakeIdent(idx, tyRecord), exprNode);
          exprNode := GenMakeIdent(idx, tyRecord);
        end
        else
          opNode := -1;
        node := AllocNode(AN_YIELD);
        ASTLeft[node] := exprNode;
        ASTIVal[node] := CurGenSelfSym;
        CurGenSeenYield := True;
        if opNode >= 0 then
          node := GenMakeSeq(opNode, GenMakeSeq(node, -1));
      end
      else if CaseEqual(name, 'await') and CurProcIsAsync then
      begin
        { `await Call(...)` as a statement (the awaited call may be void, so parse
          it as a full statement, not an expression factor). STACKFUL: documentary
          — AN_AWAIT lowers to its operand. STACKLESS: the state-machine split
          point (SLLowerAwait). }
        Next;
        node := AllocNode(AN_AWAIT);
        if CurTok.Kind = tkSemicolon then
          ASTLeft[node] := -1          { bare `await;` — a pure suspension point }
        else
          ASTLeft[node] := ParseStatementAST();
        ASTTk[node]   := Ord(tyUnknown);
      end
      else if CaseEqual(name, 'AsyncGo') then
      begin
        { Spawn a `; async; stackless;` coroutine onto the stackless scheduler.
          AsyncGo(@Body) desugars to SLSpawn(@Body, SlNew(instSize)):
          the compiler supplies the step fn (the rewritten Body) and a zero-inited
          heap instance; the scheduler resumes it via an indirect (proc-typed)
          call (SLRunUntilDone). v1: the routine takes no params. }
        Next;
        Expect(tkLParen, '(');
        Expect(tkAt, '@');
        if CurTok.Kind <> tkIdent then Error('AsyncGo: expected @<an async stackless routine>');
        procIdx := FindProc(CurTok.SVal);
        if (procIdx < 0) or not ProcIsAsync[procIdx] or not ProcIsStackless[procIdx] then
          Error('AsyncGo: argument must be @<an `; async; stackless;` routine>');
        Next;
        Expect(tkRParen, ')');
        if (FindProc('SLSpawn') < 0) or (FindProc('SlNew') < 0) then
          Error('AsyncGo: slsched/slgen not in scope (add `uses slgen, slsched;`)');
        idx := AllocNode(AN_PROCADDR); ASTIVal[idx] := procIdx; ASTTk[idx] := Ord(tyPointer);
        valNode := AllocNode(AN_INT_LIT); ASTIVal[valNode] := ProcGenInstSize[procIdx]; ASTTk[valNode] := Ord(tyInt64);
        node := GenMakeCall6(FindProc('SLSpawn'), tyPointer, idx,
                  GenMakeCall6(FindProc('SlNew'), tyPointer, valNode,
                    -1, -1, -1, -1, -1),
                  -1, -1, -1, -1);
      end
      else if CaseEqual(name, '__pxxcoswitch') then
      begin
        { Statement form of the low-level coroutine switch:
          __pxxcoswitch(pfrom, pto). }
        Next; Expect(tkLParen, '(');
        node := AllocNode(AN_COSWITCH);
        ASTTk[node] := Ord(tyPointer);
        ParseExpr;
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
        ASTLeft[node] := argSeq;
        Expect(tkComma, ',');
        ParseExpr;
        exprNode := AllocNode(AN_ARG); ASTLeft[exprNode] := CurASTNode;
        ASTRight[argSeq] := exprNode;
        Expect(tkRParen, ')');
      end
      else if CaseEqual(name, 'LoadFile') then
      begin
        Next; Expect(tkLParen, '(');
        if CurTok.Kind <> tkIdent then Error('LoadFile: expected path');
        idx := FindSym(CurTok.SVal); identTokIdx := TokPos - 1; Next;
        valNode := ParseLValueAST(idx, identTokIdx);
        Expect(tkComma, ',');

        if CurTok.Kind <> tkIdent then Error('LoadFile: expected destination');
        si := FindSym(CurTok.SVal); identTokIdx := TokPos - 1; Next;
        stepsNode := ParseLValueAST(si, identTokIdx);
        Expect(tkRParen, ')');

        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := valNode;
        ASTRight[argSeq] := AllocNode(AN_ARG);
        ASTLeft[ASTRight[argSeq]] := stepsNode;

        node := AllocNode(AN_CALL);
        ASTIVal[node] := -100;
        ASTLeft[node] := argSeq;
      end
      else if (CaseEqual(name, 'Include') or CaseEqual(name, 'Exclude')) and
              (FindProc(name) < 0) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        { Include(s, v) / Exclude(s, v): set/clear bit v in set s at runtime.
          Left = set lvalue, Right = value expr (lowered via IRLowerSetBitMutate).
          Guarded like New/Insert/Delete/Str above: a user proc of the same
          name shadows this, and a plain variable named `include`/`exclude`
          not followed by `(` is not the intrinsic. }
        Next; Expect(tkLParen, '(');
        if CurTok.Kind <> tkIdent then Error('Include/Exclude: expected set variable');
        idx := FindSym(CurTok.SVal); identTokIdx := TokPos - 1; Next;
        valNode := ParseLValueAST(idx, identTokIdx);
        Expect(tkComma, ',');
        ParseExpr; Expect(tkRParen, ')');
        if CaseEqual(name, 'Include') then
          node := AllocNode(AN_SET_INCL)
        else
          node := AllocNode(AN_SET_EXCL);
        ASTLeft[node] := valNode;
        ASTRight[node] := CurASTNode;
      end
      else if (CaseEqual(name, 'Halt') or CaseEqual(name, 'Exit')) and
              (FindProc(name) < 0) and (FindSym(name) < 0) then
      begin
        { Halt / Exit: soft-keyword statements (bare, or with an optional
          (expr)). A user proc or in-scope symbol of the same name shadows —
          bug-hard-keyword-intrinsics-block-identifier-use. }
        if CaseEqual(name, 'Halt') then node := AllocNode(AN_HALT)
        else node := AllocNode(AN_EXIT);
        Next;
        if CurTok.Kind = tkLParen then
        begin
          Next; ParseExpr; Expect(tkRParen, ')');
          ASTLeft[node] := CurASTNode;
        end;
      end
      else if (CaseEqual(name, 'Break') or CaseEqual(name, 'Continue')) and
              (FindProc(name) < 0) and (FindSym(name) < 0) then
      begin
        { Break / Continue: bare soft-keyword statements. }
        if CaseEqual(name, 'Break') then node := AllocNode(AN_BREAK)
        else node := AllocNode(AN_CONTINUE);
        Next;
      end
      else if (CaseEqual(name, 'Inc') or CaseEqual(name, 'Dec')) and
              (FindProc(name) < 0) and (FindSym(name) < 0) and
              (Tokens[TokPos].Kind = tkLParen) then
      begin
        { Inc(x[,step]) / Dec(x[,step]): soft-keyword statements lowered to
          x := x +/- step. }
        if CaseEqual(name, 'Inc') then i := Ord(tkInc) else i := Ord(tkDec);
        Next; Expect(tkLParen, '(');
        if CurTok.Kind <> tkIdent then Error('expected variable');
        argIdx := FindSym(CurTok.SVal); identTokIdx := TokPos - 1; Next;

        { Parse the FULL target lvalue (consuming any .field / [i] / ^ selectors)
          BEFORE the optional step and ')'. Inc/Dec accept any assignable lvalue,
          exactly like a `var` parameter — a bare-symbol-only parse choked on
          `Inc(rec.f)` / `Inc(Self.field)`. argIdx may be -1 (an implicit-Self
          field): ParseLValueAST resolves it (and still errors on a true unknown). }
        valNode := ParseLValueAST(argIdx, identTokIdx);

        if Eat(tkComma) then
        begin
          ParseExpr; stepsNode := CurASTNode;
        end
        else
        begin
          stepsNode := AllocNode(AN_INT_LIT);
          ASTIVal[stepsNode] := 1;
        end;
        Expect(tkRParen, ')');

        opNode := AllocNode(AN_BINOP);
        if i = Ord(tkInc) then ASTIVal[opNode] := Ord(tkPlus) else ASTIVal[opNode] := Ord(tkMinus);
        ASTLeft[opNode] := valNode;
        ASTRight[opNode] := stepsNode;

        node := AllocNode(AN_ASSIGN);
        ASTLeft[node] := valNode;
        ASTRight[node] := opNode;
      end
      else if CaseEqual(name, 'FreeMem') and (FindProc(name) < 0) and
              (FindSym(name) < 0) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        { FreeMem(p) or FreeMem(p, size): return the block to the free list. The
          size argument (FPC's two-arg form) is accepted and ignored — the block's
          own size header drives reuse. }
        Next; Expect(tkLParen, '(');
        ParseExpr;                       { pointer to free }
        valNode := CurASTNode;
        if CurTok.Kind = tkComma then begin Next; ParseExpr; end;  { size: accepted, ignored }
        Expect(tkRParen, ')');

        argSeq := AllocNode(AN_ARG);
        ASTLeft[argSeq] := valNode;

        node := AllocNode(AN_CALL);
        ASTIVal[node] := -Ord(tkFreeMem);
        ASTLeft[node] := argSeq;
        ASTTk[node] := Ord(tyInteger);
      end
      else if CaseEqual(name, 'GetMem') and (FindProc(name) < 0) and
              (FindSym(name) < 0) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        { Two-argument procedure form GetMem(dest, size): allocate `size` bytes and
          store the pointer into the lvalue `dest`. (The function form
          `p := GetMem(size)` is handled in ParseFactor.) }
        Next; Expect(tkLParen, '(');
        ParseExpr;                       { destination lvalue (ident/field/index/deref) }
        valNode := CurASTNode;
        Expect(tkComma, ',');
        ParseExpr;                       { size in bytes }
        argSeq := AllocNode(AN_ARG);
        ASTLeft[argSeq] := CurASTNode;
        Expect(tkRParen, ')');

        opNode := AllocNode(AN_CALL);
        ASTIVal[opNode] := -Ord(tkGetMem);
        ASTLeft[opNode] := argSeq;
        ASTTk[opNode] := Ord(tyPointer);

        node := AllocNode(AN_ASSIGN);
        ASTLeft[node] := valNode;
        ASTRight[node] := opNode;
      end
      else if CaseEqual(name, 'SetSignalHandler') and (FindProc('SetSignalHandler') < 0) and
              (Tokens[TokPos].Kind = tkLParen) then
      begin
        { SetSignalHandler(sig, @proc): register a parameterless proc as the
          handler for signal sig (1..64) and install the signal runtime's
          dispatch for it; nil/0 reverts to the default disposition on the next
          delivery. Guarded like the other soft intrinsics: a user proc of the
          same name shadows this. x86-64 Linux only (IR_SET_SIGNAL errors on
          other targets); --no-signals programs must not call it. }
        Next; Expect(tkLParen, '(');
        ParseExpr; opNode := CurASTNode;                              { sig }
        Expect(tkComma, ',');
        ParseExpr; valNode := CurASTNode;                             { handler }
        Expect(tkRParen, ')');
        node := AllocNode(AN_SET_SIGNAL);
        ASTLeft[node] := opNode; ASTRight[node] := valNode;
      end
      else if CaseEqual(name, 'Delete') and (FindProc('Delete') < 0) and
              (Tokens[TokPos].Kind = tkLParen) then
      begin
        { Delete(s, index, count): in-place string delete, lowered to the
          __pxxStrDelete builtin (eval-once; the var param + assign inside the
          helper handle managed refcounting). A user `Delete` (e.g. a list
          method as a plain proc) shadows this. A dynamic-array first argument
          takes the AN_DYN_DELETE path below instead. }
        Next; Expect(tkLParen, '(');
        ParseExpr; valNode := CurASTNode;
        if (ASTKind[valNode] = AN_IDENT) and (ASTIVal[valNode] >= 0) and
           Syms[ASTIVal[valNode]].IsArray and (Syms[ASTIVal[valNode]].ArrLen = -1) then
        begin
          { Delete(arr, index, count) on a dynamic array: build a fresh array
            with the range removed (AN_DYN_DELETE, AN_DYN_COPY's template) and
            assign it back onto arr — the dyn-array IR_STORE_SYM path retains
            the new handle and releases the old one, and the temp's scope-exit
            release balances the retain. First cut: non-managed, depth-1
            element types only (a raw byte copy shares element handles with
            the OLD buffer, whose element-aware release would dangle them). }
          i := ASTIVal[valNode];
          { AnsiString and managed-field record elements are supported: the
            lowering retains the kept elements in the fresh buffer (records:
            field-walk via the layout descriptor) to balance the old buffer's
            element-aware release (feature-dynarray-insert-delete-managed-
            elements). Frozen strings / nested arrays are still deferred. }
          if (Syms[i].ElemType = tyString) or
             (SymDynDepth[i] > 1) or (SymElemDynDepth[i] > 0) then
            Error('Delete: frozen-string or nested element type not yet supported for dynamic-array Delete');
          Expect(tkComma, ','); ParseExpr; opNode := CurASTNode;       { index }
          Expect(tkComma, ','); ParseExpr; stepsNode := CurASTNode;    { count }
          Expect(tkRParen, ')');
          if FindProc('PXXDynDelNewLen') < 0 then
            Error('Delete: dynamic-array helper unavailable (needs the builtin unit; not on ESP)');
          exprNode := AllocNode(AN_DYN_DELETE);
          ASTLeft[exprNode] := valNode;
          argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := opNode;
          lastArg := AllocNode(AN_ARG); ASTLeft[lastArg] := stepsNode;
          ASTRight[argSeq] := lastArg;
          ASTRight[exprNode] := argSeq;
          ASTTk[exprNode] := Ord(tyPointer);
          argIdx := AllocNode(AN_IDENT);
          ASTIVal[argIdx] := i; ASTTk[argIdx] := Ord(tyPointer);
          node := AllocNode(AN_ASSIGN);
          ASTLeft[node] := argIdx; ASTRight[node] := exprNode;
        end
        else
        begin
        if not (IntToTypeKind(ASTTk[valNode]) in [tyString, tyAnsiString, tyFixedString]) then
          Error('Delete: string or plain dynamic-array variable expected (dyn-array fields/elements not yet supported)');
        Expect(tkComma, ','); ParseExpr; opNode := CurASTNode;       { index }
        Expect(tkComma, ','); ParseExpr; stepsNode := CurASTNode;    { count }
        Expect(tkRParen, ')');
        i := FindProc('__pxxStrDelete');
        if i < 0 then Error('Delete: string helper unavailable (needs the builtin unit; not on ESP)');
        node := AllocNode(AN_CALL); ASTIVal[node] := i; ASTTk[node] := Ord(tyUnknown);
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := valNode;
        lastArg := AllocNode(AN_ARG); ASTLeft[lastArg] := opNode; ASTRight[argSeq] := lastArg;
        argIdx := AllocNode(AN_ARG); ASTLeft[argIdx] := stepsNode; ASTRight[lastArg] := argIdx;
        ASTLeft[node] := argSeq;
        end;
      end
      else if CaseEqual(name, 'Insert') and (FindProc('Insert') < 0) and
              (Tokens[TokPos].Kind = tkLParen) then
      begin
        { Insert(src, s, index): in-place string insert, lowered to __pxxStrInsert.
          src by value, s by ref (var param). A dynamic-array destination takes
          the AN_DYN_INSERT path below instead. }
        Next; Expect(tkLParen, '(');
        ParseExpr; exprNode := CurASTNode;                            { src }
        Expect(tkComma, ','); ParseExpr; valNode := CurASTNode;       { s (dest) }
        if (ASTKind[valNode] = AN_IDENT) and (ASTIVal[valNode] >= 0) and
           Syms[ASTIVal[valNode]].IsArray and (Syms[ASTIVal[valNode]].ArrLen = -1) then
        begin
          { Insert(value, arr, index) on a dynamic array: fresh (len+1)-element
            array filled around a gap at the clamped index, value stored into
            the gap, assigned back onto arr (same shape and element-type
            restrictions as dynamic-array Delete above; records/sets need a
            memory store, deferred with them). }
          i := ASTIVal[valNode];
          { AnsiString and managed-field record elements supported (see Delete
            above; the managed-record gap store is an ARC-correct
            IR_COPY_REC_MANAGED). Non-managed record and set elements too
            (memory-copied into the gap; the value must be addressable).
            Frozen strings / nested arrays still deferred. }
          if (Syms[i].ElemType = tyString) or
             (SymDynDepth[i] > 1) or (SymElemDynDepth[i] > 0) then
            Error('Insert: frozen-string or nested element type not yet supported for dynamic-array Insert');
          if ((Syms[i].ElemType = tyRecord) or (Syms[i].ElemType = tySet)) and
             not (ASTKind[exprNode] in [AN_IDENT, AN_FIELD, AN_INDEX, AN_DEREF]) then
            Error('Insert: record/set value must be a variable, field, element or dereference (addressable)');
          Expect(tkComma, ','); ParseExpr; opNode := CurASTNode;      { index }
          Expect(tkRParen, ')');
          if FindProc('PXXDynInsFill') < 0 then
            Error('Insert: dynamic-array helper unavailable (needs the builtin unit; not on ESP)');
          stepsNode := AllocNode(AN_DYN_INSERT);
          ASTLeft[stepsNode] := valNode;
          argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := exprNode;   { value }
          lastArg := AllocNode(AN_ARG); ASTLeft[lastArg] := opNode;   { index }
          ASTRight[argSeq] := lastArg;
          ASTRight[stepsNode] := argSeq;
          ASTTk[stepsNode] := Ord(tyPointer);
          argIdx := AllocNode(AN_IDENT);
          ASTIVal[argIdx] := i; ASTTk[argIdx] := Ord(tyPointer);
          node := AllocNode(AN_ASSIGN);
          ASTLeft[node] := argIdx; ASTRight[node] := stepsNode;
        end
        else
        begin
        if not (IntToTypeKind(ASTTk[valNode]) in [tyString, tyAnsiString, tyFixedString]) then
          Error('Insert: string or plain dynamic-array variable destination expected (dyn-array fields/elements not yet supported)');
        Expect(tkComma, ','); ParseExpr; opNode := CurASTNode;        { index }
        Expect(tkRParen, ')');
        i := FindProc('__pxxStrInsert');
        if i < 0 then Error('Insert: string helper unavailable (needs the builtin unit; not on ESP)');
        node := AllocNode(AN_CALL); ASTIVal[node] := i; ASTTk[node] := Ord(tyUnknown);
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := exprNode;
        lastArg := AllocNode(AN_ARG); ASTLeft[lastArg] := valNode; ASTRight[argSeq] := lastArg;
        argIdx := AllocNode(AN_ARG); ASTLeft[argIdx] := opNode; ASTRight[lastArg] := argIdx;
        ASTLeft[node] := argSeq;
        end;
      end
      else if CaseEqual(name, 'SetLength') and (FindProc('SetLength') < 0) and
              (Tokens[TokPos].Kind = tkLParen) then
      begin
        { Guarded like New/Insert/Delete/Str above: a user proc named
          `SetLength` shadows this, and a plain variable named
          `setlength`/`SetLength` not followed by `(` is not the intrinsic. }
        Next; Expect(tkLParen, '(');
        if CurTok.Kind <> tkIdent then Error('SetLength: expected string or array variable');
        { Bare function name as the SetLength target = the result var (FPC: `F`
          synonym for `Result`), so `SetLength(F, n)` works like `SetLength(Result,
          n)` for a string/dynarray-returning F. FindSym does not know the own name
          (it is not a plain symbol) — map it to RetSymIdx, mirroring the bare-own-
          name read in ParseFactor. Excluded in {$mode delphi} (Result-only there).
          Was bug-bare-name-setlength-dynarray-result. }
        if (CurProc >= 0) and Procs[CurProc].IsFunc and not DelphiMode and
           ((CurTok.SVal = Procs[CurProc].Name) or
            CaseEqual(CurTok.SVal, LastDotName(Procs[CurProc].Name))) then
          idx := Procs[CurProc].RetSymIdx
        else
          idx := FindSym(CurTok.SVal);
        identTokIdx := TokPos - 1; Next;
        valNode := ParseLValueAST(idx, identTokIdx);
        Expect(tkComma, ',');

        { Collect the size dimension(s): `SetLength(a, d0)` or the multidim sugar
          `SetLength(a, d0, d1, ...)` (FPC: allocate a rectangular jagged array,
          each extra size dimensioning the sub-arrays). }
        ParseExpr;
        SetLenDimNode[0] := CurASTNode; SetLenDimN := 1;
        while CurTok.Kind = tkComma do
        begin
          Next; ParseExpr;
          if SetLenDimN >= 32 then Error('SetLength: too many dimensions');
          SetLenDimNode[SetLenDimN] := CurASTNode; Inc(SetLenDimN);
        end;
        Expect(tkRParen, ')');

        { Classify the target: -101 = string SetLength; -102 = dynamic-array (and
          managed AnsiString). From the resolved lvalue, not the base symbol
          (`SetLength(obj.field, n)` resolves `idx` to the object). }
        slIsArrTarget := False;
        if ASTKind[valNode] = AN_FIELD then
          slIsArrTarget := (RecFieldDynDepth(ResolveNodeRec(ASTLeft[valNode]),
                              GetASTIdentName(valNode)) > 0) or
                           (RecFieldType(ResolveNodeRec(ASTLeft[valNode]),
                              GetASTIdentName(valNode)) = tyAnsiString)
        else if ASTKind[valNode] = AN_INDEX then
          slIsArrTarget := True   { nested dynamic sub-array }
        else if idx >= 0 then
        begin
          { An open `array of T` param (ArrLen=1000) or a fixed array (ArrLen>=0)
            is not resizable — SetLength on it is a hard error, as in FPC. Declare
            the param/var as a named dynamic-array type to resize it. }
          if Syms[idx].IsArray and (Syms[idx].ArrLen <> -1) then
            Error('SetLength: not a dynamic array (declare the parameter as a named dynamic-array type to resize it)');
          slIsArrTarget := (Syms[idx].IsArray and (Syms[idx].ArrLen = -1)) or
                           (Syms[idx].TypeKind = tyAnsiString);
        end;
        { Multidim sugar requires a genuine dynamic array (not a managed string,
          which slIsArrTarget also covers): each extra dim sizes the sub-arrays. }
        if SetLenDimN > 1 then
        begin
          slIsDynArr := False;
          if ASTKind[valNode] = AN_FIELD then
            slIsDynArr := RecFieldDynDepth(ResolveNodeRec(ASTLeft[valNode]),
                            GetASTIdentName(valNode)) > 0
          else if ASTKind[valNode] = AN_INDEX then
            slIsDynArr := True
          else if idx >= 0 then
            slIsDynArr := Syms[idx].IsArray and (Syms[idx].ArrLen = -1);
          if not slIsDynArr then
            Error('SetLength: multiple dimensions require a dynamic array');
        end;
        node := BuildMultiSetLen(valNode, slIsArrTarget);
      end
      else if CaseEqual(name, 'New') and (FindProc('New') < 0) and
              (Tokens[TokPos].Kind = tkLParen) then
      begin
        { New(p): allocate SizeOf(p^) and store the block into the pointer p.
          Equivalent to p := GetMem(SizeOf(p^)); size comes from p's element
          type. Guarded like Insert/Delete/Str: a user proc named `New`
          shadows this, and a plain variable named `new`/`New` not followed
          by `(` (assignment, etc.) is not the intrinsic. }
        Next; Expect(tkLParen, '(');
        if CurTok.Kind <> tkIdent then Error('New: expected pointer variable');
        idx := FindSym(CurTok.SVal); identTokIdx := TokPos - 1; Next;
        valNode := ParseLValueAST(idx, identTokIdx);
        Expect(tkRParen, ')');
        if idx < 0 then Error('New: undefined variable');
        if Syms[idx].PtrElemTk = tyRecord then
          castPrevTok := RecSize(Syms[idx].PtrElemRec)
        else
          castPrevTok := TypeSize(Syms[idx].PtrElemTk);
        exprNode := AllocNode(AN_INT_LIT);
        ASTIVal[exprNode] := castPrevTok; ASTTk[exprNode] := Ord(tyInteger);
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := exprNode;
        opNode := AllocNode(AN_CALL);
        ASTIVal[opNode] := -Ord(tkGetMem);
        ASTLeft[opNode] := argSeq; ASTTk[opNode] := Ord(tyPointer);
        node := AllocNode(AN_ASSIGN);
        ASTLeft[node] := valNode; ASTRight[node] := opNode;
      end
      else if CaseEqual(name, 'Dispose') and (FindProc('Dispose') < 0) and
              (Tokens[TokPos].Kind = tkLParen) then
      begin
        { Dispose(p): return the block to the free list (= FreeMem(p)).
          Guarded like New above. }
        Next; Expect(tkLParen, '(');
        ParseExpr; valNode := CurASTNode;
        Expect(tkRParen, ')');
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := valNode;
        node := AllocNode(AN_CALL);
        ASTIVal[node] := -Ord(tkFreeMem);
        ASTLeft[node] := argSeq; ASTTk[node] := Ord(tyInteger);
      end
      else if CaseEqual(name, 'ReallocMem') and (FindProc('ReallocMem') < 0) and
              (Tokens[TokPos].Kind = tkLParen) then
      begin
        { ReallocMem(p, newsize): resize the block p points at, preserving
          min(oldsize, newsize) bytes, and store the new pointer back into p.
          Old size comes from the block's header; old block is freed. Modelled
          as p := <realloc>(p, newsize) (special id -103). p must be a simple
          pointer variable. Guarded like New above. }
        Next; Expect(tkLParen, '(');
        if CurTok.Kind <> tkIdent then Error('ReallocMem: expected pointer variable');
        idx := FindSym(CurTok.SVal); identTokIdx := TokPos - 1; Next;
        valNode := ParseLValueAST(idx, identTokIdx);   { assign target }
        Expect(tkComma, ',');
        ParseExpr;                                      { new size -> CurASTNode }
        Expect(tkRParen, ')');

        if idx >= 0 then
        begin
          exprNode := AllocNode(AN_IDENT);              { old pointer value }
          ASTIVal[exprNode] := idx; ASTTk[exprNode] := Ord(tyPointer);
        end
        else
          { field/complex lvalue (ReallocMem(FList, ...) in a method): reuse the
            resolved lvalue node as the read — AN_IDENT(-1) was a load_sym(-1)
            IR verify error. Double-lowering the node is pure address math. }
          exprNode := valNode;
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := exprNode;
        ASTRight[argSeq] := AllocNode(AN_ARG);
        ASTLeft[ASTRight[argSeq]] := CurASTNode;        { new size }

        opNode := AllocNode(AN_CALL);
        ASTIVal[opNode] := -103;
        ASTLeft[opNode] := argSeq; ASTTk[opNode] := Ord(tyPointer);
        node := AllocNode(AN_ASSIGN);
        ASTLeft[node] := valNode; ASTRight[node] := opNode;
      end
      else if CaseEqual(name, 'Str') and (FindProc('Str') < 0) and
              (Tokens[TokPos].Kind = tkLParen) then
      begin
        { Str(x[:w[:d]], s): format integer x into string s, right-justified to
          width w. Width/decimals are ordinary integer EXPRESSIONS (FPC-legal,
          e.g. Str(z.im:len:dec, s) in rtl-extra ucomplex; decimals ignored
          for integer Str). Rewritten to s := StrInt(x, w),
          which lives in the auto-included builtin unit.
          Guarded like Insert/Delete above: a user proc named `Str` shadows
          this, and a plain statement head not immediately followed by `(`
          (assignment `str := ...`, a proc-var call `str.field`, etc.) is not
          the intrinsic -- a variable named `str`/`Str` (a very natural name
          for a string) otherwise broke even on plain assignment, since this
          branch previously always committed to the Str(..) parse shape
          unconditionally. }
        Next; Expect(tkLParen, '(');
        ParseExpr; exprNode := CurASTNode;        { value }
        stepsNode := -1;                           { width expr node; -1 = default (0) }
        decNode := -1;                             { decimals expr node; -1 = none (natural for float) }
        if CurTok.Kind = tkColon then
        begin
          Next;
          ParseExpr; stepsNode := CurASTNode;      { width: any integer expression }
          if CurTok.Kind = tkColon then
          begin
            Next;
            ParseExpr; decNode := CurASTNode;      { decimals: any integer expression }
          end;
        end;
        Expect(tkComma, ',');
        if CurTok.Kind <> tkIdent then Error('Str: expected destination string variable');
        idx := FindSym(CurTok.SVal); identTokIdx := TokPos - 1; Next;
        valNode := ParseLValueAST(idx, identTokIdx);
        Expect(tkRParen, ')');

        { Float value -> StrFloat(x, width, decimals); integer -> StrInt(x, width).
          (decimals is ignored by StrInt, used by StrFloat.) }
        strIsFloat := TypeIsFloat(IntToTypeKind(ASTTk[exprNode]));
        if strIsFloat then procIdx := FindProc('StrFloat') else procIdx := FindProc('StrInt');
        if procIdx < 0 then Error('Str: builtin unit not loaded');
        if stepsNode < 0 then stepsNode := GenMakeIntLit(0);
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := exprNode;
        ASTRight[argSeq] := AllocNode(AN_ARG);
        ASTLeft[ASTRight[argSeq]] := stepsNode;
        if strIsFloat then
        begin
          { third arg: decimals }
          if decNode < 0 then decNode := GenMakeIntLit(-1);
          ASTRight[ASTRight[argSeq]] := AllocNode(AN_ARG);
          ASTLeft[ASTRight[ASTRight[argSeq]]] := decNode;
        end;
        opNode := AllocNode(AN_CALL);
        { Tag the call result with the builtin's ACTUAL return kind: StrInt/StrFloat
          return AnsiString in managed mode (the default) and frozen tyString under
          -uPXX_MANAGED_STRING. Hardcoding tyString miscompiled the frozen->managed
          store when the dest `s` is managed and the proc now returns AnsiString
          (slice 4p2). }
        ASTIVal[opNode] := procIdx; ASTLeft[opNode] := argSeq;
        ASTTk[opNode] := Ord(Procs[procIdx].RetType);
        node := AllocNode(AN_ASSIGN);
        ASTLeft[node] := valNode; ASTRight[node] := opNode;
      end
      else if (CaseEqual(name, 'Val')) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        { Val(s, dest, code): dispatch on the destination variable's type — a
          float dest -> ValFloat (string->Double), otherwise the integer Val.
          dest and code are by-ref; their marshalling follows the chosen proc's
          param flags at lowering time. }
        Next; Expect(tkLParen, '(');
        ParseExpr; exprNode := CurASTNode;                 { source string }
        Expect(tkComma, ',');
        if CurTok.Kind <> tkIdent then Error('Val: expected destination variable');
        idx := FindSym(CurTok.SVal); identTokIdx := TokPos - 1; Next;
        valNode := ParseLValueAST(idx, identTokIdx);        { dest value }
        Expect(tkComma, ',');
        if CurTok.Kind <> tkIdent then Error('Val: expected code variable');
        si := FindSym(CurTok.SVal); argIdx := TokPos - 1; Next;
        stepsNode := ParseLValueAST(si, argIdx);            { code }
        Expect(tkRParen, ')');

        if (idx >= 0) and TypeIsFloat(Syms[idx].TypeKind) then procIdx := FindProc('ValFloat')
        else procIdx := FindProc('Val');
        if procIdx < 0 then Error('Val: builtin unit not loaded');
        { A 1-char source literal (e.g. `Val('5', ...)`) parses as a Char; the
          builtin's first param is a string, so promote it to a string literal —
          the same coercion a normal call applies. Without it the Char is passed
          where a string pointer is expected and Length(s)/s[i] segfault. }
        if (ASTKind[exprNode] = AN_INT_LIT) and (IntToTypeKind(ASTTk[exprNode]) = tyChar) then
        begin
          ASTKind[exprNode] := AN_STR_LIT;
          ASTTk[exprNode] := Ord(tyString);
        end;
        { The integer `Val` writes an Int64 (8 bytes) through its `var v` param.
          A narrower destination (the common `var v: Integer`) would be overrun,
          clobbering the neighbouring `code`/stack and crashing. Marshal through a
          hidden Int64 temp and truncate into the real destination afterwards. }
        valTmpSym := -1;
        if (idx >= 0) and (not TypeIsFloat(Syms[idx].TypeKind)) and
           TypeIsOrdinal(Syms[idx].TypeKind) and (TypeSize(Syms[idx].TypeKind) < 8) then
        begin
          valTmpSym := AllocVar('', tyInt64);
          valTmpIdent := AllocNode(AN_IDENT);
          ASTIVal[valTmpIdent] := valTmpSym; ASTTk[valTmpIdent] := Ord(tyInt64);
        end;
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := exprNode;
        lastArg := AllocNode(AN_ARG);
        if valTmpSym >= 0 then ASTLeft[lastArg] := valTmpIdent
        else ASTLeft[lastArg] := valNode;
        ASTRight[argSeq] := lastArg;
        opNode := AllocNode(AN_ARG); ASTLeft[opNode] := stepsNode; ASTRight[lastArg] := opNode;
        node := AllocNode(AN_CALL);
        ASTIVal[node] := procIdx; ASTLeft[node] := argSeq; ASTTk[node] := Ord(Procs[procIdx].RetType);
        if valTmpSym >= 0 then
        begin
          { dest := tmp  (truncates the Int64 result into the narrower dest). }
          valTmpIdent := AllocNode(AN_IDENT);
          ASTIVal[valTmpIdent] := valTmpSym; ASTTk[valTmpIdent] := Ord(tyInt64);
          valTmpAssign := AllocNode(AN_ASSIGN);
          ASTLeft[valTmpAssign] := valNode; ASTRight[valTmpAssign] := valTmpIdent;
          node := GenMakeSeq(node, GenMakeSeq(valTmpAssign, -1));
        end;
      end
      else if (CurProc >= 0) and Procs[CurProc].IsFunc and
              (Tokens[TokPos].Kind in [tkAssign, tkDot, tkLBrack, tkCaret]) and
              ((name = Procs[CurProc].Name) or
               CaseEqual(name, LastDotName(Procs[CurProc].Name))) then
      begin
        Next;
        if CurTok.Kind = tkAssign then
        begin
          Expect(tkAssign, ':=');
          valNode := AllocNode(AN_IDENT);
          ASTIVal[valNode] := Procs[CurProc].RetSymIdx;
        end
        else
        begin
          { `FuncName.field := ` / `FuncName[i] := ` — assign through the result
            value's lvalue (FPC allows the function name as a synonym for Result;
            `Result.field` already worked). }
          valNode := ParseLValueAST(Procs[CurProc].RetSymIdx, TokPos - 2);
          Expect(tkAssign, ':=');
        end;

        ParseExpr;
        node := AllocNode(AN_ASSIGN);
        ASTLeft[node] := valNode;
        ASTRight[node] := CurASTNode;
      end
      else if CaseEqual(name, 'goto') then
      begin
        Next;
        if CurTok.Kind <> tkIdent then Error('expected label name after goto');
        node := AllocNode(AN_GOTO);
        ASTSOffset[node] := Tokens[TokPos-1].SOffset;
        ASTSLen[node]    := Tokens[TokPos-1].SLen;
        Next;
      end
      else
      begin
        if qUnit >= 0 then
          procIdx := FindProcInUnit(name, qUnit)
        else
          procIdx := FindProc(name);
        { FPC scoping: the enclosing class's own method shadows a same-name
          plain proc (innermost scope wins) — clear procIdx so the implicit-Self
          dispatch below takes the call instead of plain-proc matching. Guarded
          like that dispatch: si >= 0 (a local shadows the method) and unit-
          qualified names keep the plain path. Companion to the same clear on
          the expression side (bug-implicit-self-method-loses-to-unit-proc). }
        if (procIdx >= 0) and (qUnit < 0) and (si < 0) and
           (CurSelfClass >= REC_UCLASS_BASE) and
           (FindUMeth(CurSelfClass - REC_UCLASS_BASE, name) >= 0) then
          procIdx := -1;
        if (procIdx >= 0) and (Tokens[TokPos].Kind = tkLParen) then
        begin
          Next;
          Expect(tkLParen, '(');
          argsHead := -1;
          lastArg := -1;
          nArgs := 0;
          while CurTok.Kind <> tkRParen do
          begin
            if (CurTok.Kind = tkLBrack) and ParamIsVarRecArray(procIdx, nArgs) then
              CurASTNode := ParseVarRecLiteralAST
            else if (CurTok.Kind = tkLBrack) and ParamIsOpenArrayScalar(procIdx, nArgs) then
              CurASTNode := ParseArrayCtorAST(Procs[procIdx].Params[nArgs].TypeKind)
            else
            begin
              node := TryDelphiBareProcArg;
              if node >= 0 then CurASTNode := node else ParseExpr;
            end;
            argSeq := AllocNode(AN_ARG);
            ASTLeft[argSeq] := CurASTNode;
            if argsHead = -1 then
              argsHead := argSeq
            else
              ASTRight[lastArg] := argSeq;
            lastArg := argSeq;
            Inc(nArgs);
            if ProcFlexColumn[procIdx] then ParseFlexColumnTail(lastArg, nArgs);
            if CurTok.Kind = tkComma then
              Next
            else if CurTok.Kind <> tkRParen then
              Error('expected comma or close parenthesis');
          end;
          Expect(tkRParen, ')');

          currArg := argsHead;
          for i := 0 to nArgs - 1 do
          begin
            exprNode := ASTLeft[currArg];
            argTypes[i] := IntToTypeKind(ASTTk[exprNode]);
            currArg := ASTRight[currArg];
          end;

          procIdx := MatchCallDelphiProcAddr(name, qUnit, nArgs, argsHead, argTypes);
          if procIdx < 0 then
            Error('no overload of ' + name + ' matches these arguments');

          currArg := argsHead;
          for i := 0 to nArgs - 1 do
          begin
            exprNode := ASTLeft[currArg];
            if (TypeIsFrozenString(Procs[procIdx].Params[i].TypeKind)) and (IntToTypeKind(ASTTk[exprNode]) = tyChar) then
            begin
              if ASTKind[exprNode] = AN_INT_LIT then
              begin
                ASTKind[exprNode] := AN_STR_LIT;
                ASTTk[exprNode] := Ord(tyString);
              end;
            end;
            currArg := ASTRight[currArg];
          end;

          currArg := argsHead;
          for i := 0 to nArgs - 1 do
          begin
            exprNode := ASTLeft[currArg];
            if (Procs[procIdx].Params[i].IsRef or Procs[procIdx].Params[i].IsArray) and
               (ASTKind[exprNode] <> AN_VARREC_ARRAY) and (ASTKind[exprNode] <> AN_ARRAY_CTOR) then
            begin
              if not ((ASTKind[exprNode] = AN_IDENT) or (ASTKind[exprNode] = AN_INDEX) or (ASTKind[exprNode] = AN_FIELD) or
                      (ASTKind[exprNode] = AN_DEREF)) then
              begin
                { A `const` OR plain by-value record param accepts a non-lvalue
                  temporary (>8-byte records are by-ref only for ABI; the callee
                  copies). Only a genuine `var`/`out` record needs a true lvalue. }
                if not ((IntToTypeKind(ASTTk[exprNode]) = tyRecord) and
                        (ProcParamIsConst[procIdx * MAX_PROC_PARAMS + i] or
                         not ProcParamExplicitByRef[procIdx * MAX_PROC_PARAMS + i])) then
                  Error('by-reference argument must be a variable');
              end;
            end;
            currArg := ASTRight[currArg];
          end;

          node := AllocNode(AN_CALL);
          ASTIVal[node] := procIdx;
          ASTLeft[node] := argsHead;
        end
        else if (si < 0) and (procIdx >= 0) and (Procs[procIdx].ParamCount = 0) then
        begin
          { Bare paramless call statement. Guarded on `si < 0` (FindSym above): a
            variable in scope with the same name shadows the function, so
            `counter := ...` where a local `counter` collides with a function
            `ClauseCount`/`Counter` must reach the assignment path below, not be
            eaten as a paramless call. Companion to the same guard in ParseFactor
            (bug-impl-prescan-codegen-regression — name resolution, not slots). }
          Next;
          node := AllocNode(AN_CALL);
          ASTIVal[node] := procIdx;
        end;

        if node = -1 then
        begin
          { Implicit Self.method dispatch for methods called bare inside a class body.
            Guarded on si < 0: a local var (or param) of the same name shadows the
            method, so `child := ...` where `child` is a local must reach the
            assignment path below — not be eaten as a bare implicit-Self method
            call (which consumes only the name, leaving `:=` dangling and, via a
            following `else`, hanging ParseBlockAST). Companion to the same
            local-shadows guard on the paramless-call path above
            (bug-compiler-hang-on-nested-if-in-begin). }
          if (CurSelfClass >= REC_UCLASS_BASE) and (si < 0) then
          begin
            smci := CurSelfClass - REC_UCLASS_BASE;
            smmii := FindUMethArity(smci, name, CountCallArgsAhead);
            if smmii >= 0 then
            begin
              smpii := UMthProc_[smmii];
              Next; { consume method name }
              smSelfIdx := Procs[CurProc].Params[0].SymIdx;
              smselfArg := AllocNode(AN_ARG);
              valNode := AllocNode(AN_IDENT);
              ASTIVal[valNode] := smSelfIdx;
              ASTTk[valNode] := Ord(tyClass);
              ASTLeft[smselfArg] := valNode;
              if UMthVirSlot[smmii] >= 0 then
              begin
                smcallNode := AllocNode(AN_VIRTUAL_CALL);
                ASTRight[smcallNode] := UMthVirSlot[smmii];
              end
              else
                smcallNode := AllocNode(AN_CALL);
              ASTIVal[smcallNode] := smpii;
              if (smpii >= 0) then
                ASTTk[smcallNode] := Ord(Procs[smpii].RetType)
              else
                ASTTk[smcallNode] := Ord(tyInteger);
              ASTLeft[smcallNode] := smselfArg;
              smLastArg := smselfArg;
              if CurTok.Kind = tkLParen then
              begin
                Next;
                smMai := 1;
                while CurTok.Kind <> tkRParen do
                begin
                  ParseExpr;
                  smArgSeq := AllocNode(AN_ARG);
                  ASTLeft[smArgSeq] := CurASTNode;
                  ASTRight[smLastArg] := smArgSeq;
                  smLastArg := smArgSeq;
                  Inc(smMai);
                  if CurTok.Kind = tkComma then Next;
                end;
                Expect(tkRParen, ')');
              end;
              node := smcallNode;
            end;
          end;
          if node = -1 then
          begin
            { Class typecast as an lvalue statement — TClass(expr).field := val
              (and [i]). Mirrors the read path (AN_CLASS_CAST); the field offset
              resolves against TClass via ResolveNodeRec. Precedes the
              pointer-alias cast below, which would mis-handle a class name. }
            if IsClassType(name) and (Tokens[TokPos].Kind = tkLParen) then
            begin
              smci := FindUClass(name);
              Next; { consume class name }
              Expect(tkLParen, '(');
              ParseExpr;
              Expect(tkRParen, ')');
              valNode := AllocNode(AN_CLASS_CAST);
              ASTLeft[valNode] := CurASTNode;
              ASTIVal[valNode] := smci;
              ASTTk[valNode]   := Ord(tyClass);
              castTk := tyClass;
              { `TClass(expr).Free;` — plain form only, like obj.Free above }
              if (CurTok.Kind = tkDot) and (TokPos < TokCount) and
                 (Tokens[TokPos].Kind = tkIdent) and
                 CaseEqual(GetTokenStr(TokPos), 'Free') and
                 (Tokens[TokPos+1].Kind in [tkSemicolon, tkEnd, tkElse]) and
                 (FindUMeth(smci, 'Free') < 0) then
              begin
                Next; Next;   { consume '.', 'Free' }
                node := GenMakeFreeObjectExpr(valNode, smci);
                Result := node; Exit;
              end;
              if CurTok.Kind in [tkDot, tkLBrack] then
                valNode := ParseClassRecordSelectors(valNode, REC_UCLASS_BASE + smci, castTk);
              if (ASTKind[valNode] = AN_CALL) or (ASTKind[valNode] = AN_VIRTUAL_CALL) then
                { TClass(x).Method(args); — a method-call statement, not an assign }
                node := valNode
              else
              begin
                Expect(tkAssign, ':=');
                ParseExpr;
                node := AllocNode(AN_ASSIGN);
                ASTLeft[node]  := valNode;
                ASTRight[node] := CurASTNode;
              end;
            end;
          end;

          if node = -1 then
          begin
            { Record-name typecast as an lvalue statement — TRec(ptr)^.field := val.
              Mirrors the expression-side record cast: reinterpret ptr as ^TRec and
              carry the pointee rec on the deref node so ResolveNodeRec resolves the
              field offset. A class name went to AN_CLASS_CAST above. }
            if (IsRecordType(name) >= REC_UCLASS_BASE) and (Tokens[TokPos].Kind = tkLParen) then
            begin
              castRec := IsRecordType(name);
              Next; { consume record type name }
              Expect(tkLParen, '(');
              ParseExpr;
              Expect(tkRParen, ')');
              indexNode := AllocNode(AN_PTR_CAST);
              ASTLeft[indexNode] := CurASTNode;
              ASTIVal[indexNode] := 0;
              ASTTk[indexNode]   := Ord(tyPointer);
              valNode := indexNode;
              while CurTok.Kind in [tkCaret, tkDot] do
              begin
                if CurTok.Kind = tkCaret then
                begin
                  Next;
                  fieldNode := AllocNode(AN_DEREF);
                  ASTLeft[fieldNode] := valNode;
                  ASTIVal[fieldNode] := castRec;   { pointee rec for ResolveNodeRec }
                  castTk := tyRecord;
                  ASTTk[fieldNode] := Ord(tyRecord);
                  valNode := fieldNode;
                end
                else { tkDot }
                begin
                  Next;
                  if CurTok.Kind in [tkEOF, tkSemicolon, tkAssign, tkRBrack, tkRParen] then
                    Error('expected field name after .');
                  castPrevTok := TokPos - 1;
                  castFieldName := '';
                  for i := Tokens[castPrevTok].SOffset to Tokens[castPrevTok].SOffset + Tokens[castPrevTok].SLen - 1 do
                    AppendChar(castFieldName, TokChars[i]);
                  fieldNode := AllocNode(AN_FIELD);
                  ASTLeft[fieldNode] := valNode;
                  ASTSOffset[fieldNode] := Tokens[castPrevTok].SOffset;
                  ASTSLen[fieldNode]   := Tokens[castPrevTok].SLen;
                  castTk  := RecFieldType(castRec, castFieldName);
                  castRec := RecFieldRecId(castRec, castFieldName);
                  ASTTk[fieldNode] := Ord(castTk);
                  Next;
                  valNode := fieldNode;
                end;
              end;
              Expect(tkAssign, ':=');
              ParseExpr;
              node := AllocNode(AN_ASSIGN);
              ASTLeft[node]  := valNode;
              ASTRight[node] := CurASTNode;
            end;
          end;

          if node = -1 then
          begin
            { C4: pointer-type-alias cast as lvalue statement — PFoo(expr)^.field := val }
            aliasIdx := FindTypeAlias(name);
            if (aliasIdx >= 0) and (Tokens[TokPos].Kind = tkLParen) then
            begin
              Next; { consume alias name }
              Expect(tkLParen, '(');
              ParseExpr;
              Expect(tkRParen, ')');
              indexNode := AllocNode(AN_PTR_CAST);
              ASTLeft[indexNode] := CurASTNode;
              ASTIVal[indexNode] := aliasIdx;
              ASTTk[indexNode]   := Ord(tyPointer);
              castTk  := tyPointer;
              castRec := AliasElemRec[aliasIdx];
              valNode := indexNode;
              { Handle ^  and .field suffix chain }
              while CurTok.Kind in [tkCaret, tkDot] do
              begin
                if CurTok.Kind = tkCaret then
                begin
                  Next;
                  fieldNode := AllocNode(AN_DEREF);
                  ASTLeft[fieldNode] := valNode;
                  castTk := IntToTypeKind(AliasElemTk[aliasIdx]);
                  castRec := AliasElemRec[aliasIdx];
                  ASTTk[fieldNode] := Ord(castTk);
                  valNode := fieldNode;
                end
                else { tkDot }
                begin
                  Next;
                  if CurTok.Kind in [tkEOF, tkSemicolon, tkAssign, tkRBrack, tkRParen] then
                    Error('expected field name after .');
                  castPrevTok := TokPos - 1;
                  castFieldName := '';
                  for i := Tokens[castPrevTok].SOffset to Tokens[castPrevTok].SOffset + Tokens[castPrevTok].SLen - 1 do
                    AppendChar(castFieldName, TokChars[i]);
                  fieldNode := AllocNode(AN_FIELD);
                  ASTLeft[fieldNode] := valNode;
                  ASTSOffset[fieldNode] := Tokens[castPrevTok].SOffset;
                  ASTSLen[fieldNode]   := Tokens[castPrevTok].SLen;
                  castTk  := RecFieldType(castRec, castFieldName);
                  castRec := RecFieldRecId(castRec, castFieldName);
                  ASTTk[fieldNode] := Ord(castTk);
                  Next;
                  valNode := fieldNode;
                end;
              end;
              Expect(tkAssign, ':=');
              ParseExpr;
              node := AllocNode(AN_ASSIGN);
              ASTLeft[node]  := valNode;
              ASTRight[node] := CurASTNode;
            end
            else
            begin
              if qUnit >= 0 then
                idx := FindSymInUnit(name, qUnit)
              else
                idx := FindSym(name);
              { --auto-locals / {$IMPLICITVARS ON}: a simple assignment to a
                previously-undeclared bare name (`i := 0`) declares a routine-
                local tyAuto var here; the tyAuto-on-assignment block below
                infers its type from the RHS. Gated tight: opt-in only, name
                not a symbol/routine/unit-qualified, and the very next token is
                `:=` (a scalar target) — so `obj.f :=`, `a[i] :=`, a bare read,
                or a call all keep the normal (erroring) path. A read of an
                undeclared name still errors (only assignment creates one). See
                feature-implicit-locals-sloppy-switch. }
              if ImplicitVars and (idx < 0) and (qUnit < 0) and
                 (Tokens[TokPos].Kind = tkAssign) and (FindProc(name) < 0) then
              begin
                idx := AllocVar(name, tyAuto);
                WarnImplicitVar(CurTok.Line, name);
              end;
              { Built-in `obj.Free;` on a class instance with no user `Free` method
                (built-in TObject has none): desugar to nil-guarded Destroy/FreeMem.
                Restricted to the plain `obj.Free;`/`obj.Free end` form so a user
                method named Free, or any suffix/args, falls through to the lvalue
                path below. }
              if (idx >= 0) and (Syms[idx].RecName >= REC_UCLASS_BASE) and
                 (not UClsIsRecord[Syms[idx].RecName - REC_UCLASS_BASE]) and
                 (Tokens[TokPos].Kind = tkDot) and (Tokens[TokPos+1].Kind = tkIdent) and
                 CaseEqual(GetTokenStr(TokPos+1), 'Free') and
                 (Tokens[TokPos+2].Kind in [tkSemicolon, tkEnd, tkElse]) and
                 (FindUMeth(Syms[idx].RecName - REC_UCLASS_BASE, 'Free') < 0) then
              begin
                Next; Next; Next;   { consume obj, '.', 'Free' }
                node := GenMakeFreeObject(idx);
                Result := node; Exit;
              end;
              { The implicit-Self FIELD twin: `FField.Free;` inside a method,
                FField a class-typed field of the enclosing class (blcksock's
                `FDelayedOptions.Free`). Same plain-form restriction. }
              if (idx < 0) and (CurSelfClass >= REC_UCLASS_BASE) and (CurProc >= 0) and
                 (Tokens[TokPos].Kind = tkDot) and (Tokens[TokPos+1].Kind = tkIdent) and
                 CaseEqual(GetTokenStr(TokPos+1), 'Free') and
                 (Tokens[TokPos+2].Kind in [tkSemicolon, tkEnd, tkElse]) then
              begin
                smci := CurSelfClass - REC_UCLASS_BASE;
                smmii := FindUField(smci, name);
                if smmii < 0 then
                begin
                  { a read-FIELD property counts too — `FullResult.Free;` with
                    `property FullResult: TStringList read FFullResult`
                    (pop3send.Destroy): resolve the backing field. }
                  smpii := FindUProp(smci, name);
                  if (smpii >= 0) and (UPropReadFLen[smpii] > 0) then
                  begin
                    castFieldName := '';
                    for i := 0 to UPropReadFLen[smpii] - 1 do
                      AppendChar(castFieldName, TokChars[UPropReadFOff[smpii] + i]);
                    smmii := FindUField(smci, castFieldName);
                  end;
                end
                else
                  smpii := -1;
                if (smmii >= 0) and (UFldTk[smmii] = Ord(tyClass)) and
                   (UFldRec_[smmii] >= REC_UCLASS_BASE) and
                   (FindUMeth(UFldRec_[smmii] - REC_UCLASS_BASE, 'Free') < 0) then
                begin
                  smSelfIdx := Procs[CurProc].Params[0].SymIdx;
                  castPrevTok := TokPos - 1;   { the field-name token }
                  Next; Next; Next;   { consume field, '.', 'Free' }
                  if (smpii >= 0) and (UPropReadFLen[smpii] > 0) then
                    { property form: the FIELD's own span names the lvalue }
                    node := GenMakeFreeObjectField(smSelfIdx,
                      UPropReadFOff[smpii], UPropReadFLen[smpii],
                      UFldRec_[smmii] - REC_UCLASS_BASE)
                  else
                    node := GenMakeFreeObjectField(smSelfIdx,
                      Tokens[castPrevTok].SOffset, Tokens[castPrevTok].SLen,
                      UFldRec_[smmii] - REC_UCLASS_BASE);
                  Result := node; Exit;
                end;
              end;
              Next;
              valNode := ParseLValueAST(idx, TokPos - 2);
              if (ASTKind[valNode] = AN_CALL) or (ASTKind[valNode] = AN_VIRTUAL_CALL) or
                 (ASTKind[valNode] = AN_INTF_CALL) or (ASTKind[valNode] = AN_CALL_IND) or
                 { with-scoped `Free;` desugars to a nil-guarded IF — a
                   statement, never an lvalue }
                 (ASTKind[valNode] = AN_IF) then
                node := valNode
              else
              begin
                Expect(tkAssign, ':=');
                { Delphi-mode @-optional procedural value: `p := F` (no `@`) where
                  p is a proc-typed lvalue and F is a bare routine name not being
                  called takes F's address — the one {$mode delphi} behavioural
                  delta. Default/objfpc keep requiring `@F` (F here would be a
                  call). Guarded on a routine name that is NOT a variable and is
                  not followed by `(`; an explicit `@F` (tkAt) takes the normal
                  ParseExpr path. }
                argIdx := -1;
                if (CurTok.Kind = tkIdent) then argIdx := FindSym(CurTok.SVal);
                if DelphiMode and (idx >= 0) and (SymProcSig[idx] >= 0) and
                   (Syms[idx].TypeKind = tyRecord) and (argIdx >= 0) and
                   (Syms[argIdx].RecName >= REC_UCLASS_BASE) and
                   (not UClsIsRecord[Syms[argIdx].RecName - REC_UCLASS_BASE]) and
                   (Tokens[TokPos].Kind = tkDot) and (Tokens[TokPos+1].Kind = tkIdent) and
                   (Tokens[TokPos+2].Kind <> tkLParen) and
                   (FindUMeth(Syms[argIdx].RecName - REC_UCLASS_BASE, GetTokenStr(TokPos+1)) >= 0) then
                begin
                  { Delphi @-optional METHOD pointer: `p := obj.M` (no `@`) == `@obj.M`,
                    where p is a method-pointer lvalue (`procedure(...) of object`,
                    a 16-byte {Code,Data} record so TypeKind = tyRecord). Builds the
                    same AN_METHODREF the `@obj.M` path emits; AN_ASSIGN writes the
                    two pointers into the TMethod target. }
                  smci := Syms[argIdx].RecName - REC_UCLASS_BASE;
                  smmii := FindUMeth(smci, GetTokenStr(TokPos+1));
                  Next; Next;   { consume obj name and '.'; CurTok = method name }
                  opNode := AllocNode(AN_IDENT);
                  ASTIVal[opNode] := argIdx;
                  ASTTk[opNode] := Ord(tyClass);
                  CurASTNode := AllocNode(AN_METHODREF);
                  ASTIVal[CurASTNode] := UMthProc_[smmii];
                  ASTLeft[CurASTNode] := opNode;
                  ASTTk[CurASTNode] := Ord(tyRecord);
                  LastExprTk := tyRecord;
                  Next;   { consume method name }
                end
                else if DelphiMode and (idx >= 0) and (SymProcSig[idx] >= 0) and
                   (CurTok.Kind = tkIdent) and (argIdx < 0) and
                   (FindProc(CurTok.SVal) >= 0) and (Tokens[TokPos].Kind <> tkLParen) then
                begin
                  CurASTNode := AllocNode(AN_PROCADDR);
                  ASTIVal[CurASTNode] := FindProc(CurTok.SVal);
                  ASTTk[CurASTNode] := Ord(tyPointer);
                  LastExprTk := tyPointer;
                  Next;   { consume the routine name }
                end
                else
                  ParseExpr;
                if idx >= 0 then
                begin
                  if Syms[idx].TypeKind = tyAuto then
                  begin
                    if ASTKind[CurASTNode] = AN_DEFAULT then
                      Error('cannot infer type from default; specify type explicitly');
                    if (LastExprTk = tyUnknown) or (LastExprTk = tyAuto) then
                      Error('cannot infer type for auto variable');
                    InferSymTypeFromNode(idx, CurASTNode);
                    AllocateSymOffset(idx);
                    ASTTk[valNode] := Ord(Syms[idx].TypeKind);
                  end;
                end;
                if (idx >= 0) and (ASTKind[valNode] = AN_IDENT) then
                  CheckMetaclassAssign(idx, CurASTNode);
                node := AllocNode(AN_ASSIGN);
                ASTLeft[node] := valNode;
                ASTRight[node] := CurASTNode;
              end;
            end;
          end;
        end;
      end;
    end;

    tkLParen:
    begin
      { Statement starting with a parenthesised expression: a method/proc call on
        a grouped value, e.g. `(o as T).M;` (the as-inline-call bug), or a write
        through one, e.g. `(p)^ := v`. ParseExpr resolves the member access (incl.
        (as)-cast method dispatch via ParseFactor's grouped postfix); a trailing
        `:=` makes it an assignment, otherwise it is a call whose result is
        discarded. Previously the default branch below skipped to `;`, silently
        dropping the statement. }
      ParseExpr;
      valNode := CurASTNode;
      if CurTok.Kind = tkAssign then
      begin
        Next;
        ParseExpr;
        node := AllocNode(AN_ASSIGN);
        ASTLeft[node] := valNode;
        ASTRight[node] := CurASTNode;
      end
      else
        node := valNode;
    end;

    tkSemicolon, tkEnd, tkElse, tkUntil, tkEOF: ;
    else
    begin
      { Check for 'goto label' }
      if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'goto') then
      begin
        Next;
        if CurTok.Kind <> tkIdent then Error('expected label name after goto');
        node := AllocNode(AN_GOTO);
        ASTSOffset[node] := Tokens[TokPos-1].SOffset;
        ASTSLen[node]    := Tokens[TokPos-1].SLen;
        Next;
      end
      else
        while not (CurTok.Kind in [tkSemicolon,tkEnd,tkElse,tkUntil,tkEOF]) do Next;
    end;
  end;
  Result := node;
end;

procedure ParseStatement;
var node: Integer;
begin
  node := ParseStatementAST;
  CompileAST(node);
  ASTNodeCount := 0;
end;

procedure ParseBlock;
var node: Integer;
begin
  node := ParseBlockAST;
  CompileAST(node);
  ASTNodeCount := 0;
end;

{ ===== Declaration parsing ===== }

function ParseTypeKind: TTypeKind;
var lo: AnsiString; elemTk: TTypeKind; aliasIdx, ci: Integer;
    childDepth, childBaseTk, childBaseRec: Integer;
    wasPacked: Boolean;
begin
  LastTypeRecId := REC_NONE;
  LastTypePointerElemTk := tyUnknown;
  LastTypePointerElemRec := REC_NONE;
  LastTypePointerDepth := 0;
  LastTypePointerBaseTk := Ord(tyUnknown);
  LastTypePointerBaseRec := REC_NONE;
  LastTypeProcSig := -1;
  LastTypeEnumId := -1;
  LastTypeStrCap := 0;
  case CurTok.Kind of
    tkRecord, tkPacked:
    begin
      { Anonymous inline record type literal — `var x: record ... end;`,
        legal ISO/FPC anywhere a type is expected
        (feature-anonymous-record-type). Mint an unnamed UCls row
        (AddUClass(0,0), the EnsureMethodPtrRec precedent) and parse the
        fields with the shared named-record field parser. `packed` reaching
        here must introduce a record (`packed array` never routed through
        ParseTypeKind before either). }
      wasPacked := CurTok.Kind = tkPacked;
      if wasPacked then
      begin
        Next;
        Expect(tkRecord, 'record');
      end
      else
        Next;
      ci := AddUClass(0, 0);
      UClsParent[ci] := -1;
      UClsIsRecord[ci] := True;
      ParseRecordFields(ci, wasPacked);
      LastTypeRecId := REC_UCLASS_BASE + ci;
      Result := tyRecord;
      Exit;
    end;
    tkCaret:
    begin
      Next;
      elemTk := ParseTypeKind();
      childDepth := LastTypePointerDepth;
      childBaseTk := LastTypePointerBaseTk;
      childBaseRec := LastTypePointerBaseRec;
      LastTypePointerElemTk := elemTk;
      LastTypePointerElemRec := LastTypeRecId;
      if (elemTk = tyPointer) and (childDepth > 0) then
      begin
        LastTypePointerDepth := childDepth + 1;
        LastTypePointerBaseTk := childBaseTk;
        LastTypePointerBaseRec := childBaseRec;
      end
      else
      begin
        LastTypePointerDepth := 1;
        LastTypePointerBaseTk := Ord(elemTk);
        LastTypePointerBaseRec := LastTypeRecId;
      end;
      Result := tyPointer;
      Exit;
    end;
    tkInteger_T:
    begin
      lo := CurTok.SVal;
      if CaseEqual(lo, 'shortint') then Result := tyInt8
      else if CaseEqual(lo, 'byte') then Result := tyUInt8
      else if CaseEqual(lo, 'smallint') then Result := tyInt16
      else if CaseEqual(lo, 'word') then Result := tyUInt16
      else if CaseEqual(lo, 'longint') then Result := tyInt32
      else if CaseEqual(lo, 'cardinal') then Result := tyUInt32
      else Result := tyInteger; { Integer }
    end;
    tkLongWord_T: Result := tyUInt32;
    tkBoolean_T: Result := tyBoolean;
    tkChar_T:    Result := tyChar;
    tkString_T:
      { Bare `string`: per-use promotion to managed AnsiString for AGGREGATE
        ELEMENTS only (the token right before `string` is `of`, as in `array of
        string` / `array[..] of string`), in managed-string mode (the default).
        A frozen `string` element is huge inline and can't be a dynarray element,
        so promoting it to a managed handle is what makes `array of string` work
        (bug-string-type-size-mismatch / the PCL list controls). SCALAR `string`
        stays frozen so Str/Val and other frozen-buffer builtins keep working
        (the full string-model arc / tyFixedString handles the rest). `string[N]`
        stays a frozen fixed-length string. }
      if (Tokens[TokPos].Kind = tkLBrack) then
      begin
        { `string[N]` -> frozen fixed-length string (tyFixedString: NativeInt
          length word + N chars, capacity N). We consume our own `[N]` here, so
          Exit before the trailing Next that the simple cases rely on. }
        Next;                          { consume `string` }
        Expect(tkLBrack, '[');
        LastTypeStrCap := ConstEval;
        Expect(tkRBrack, ']');
        Result := tyFixedString;
        Exit;
      end
      else if PasDefineExists('PXX_MANAGED_STRING') then
        { Scalar bare `string` -> managed AnsiString (slice 4p2: managed is the
          default string model). `string[N]`/`shortstring` stay frozen
          tyFixedString; `-uPXX_MANAGED_STRING` keeps everything frozen tyString. }
        Result := tyAnsiString
      else
        Result := tyString;
    tkReal_T:     if (TargetArch = TARGET_XTENSA) or (TargetArch = TARGET_RISCV32) then Result := tySingle else Result := tyDouble;
    tkSingle_T:   Result := tySingle;
    tkDouble_T:   Result := tyDouble;
    tkExtended_T: Result := tyDouble;   { Extended aliases Double — see below }
    else
    begin
      lo := CurTok.SVal;
      { Unit-qualified type reference — `sockets.Tin6_addr` (Synapse's
        `TInAddr6 = sockets.Tin6_addr`). Strip the qualifier and resolve the
        member name like a bare type; ConsumeUnitQualifier consumes nothing
        when the prefix is not a compiled unit. Types live in one global
        table, so the qualifier only disambiguates the parse, not the lookup. }
      if (CurTok.Kind = tkIdent) and (ConsumeUnitQualifier(lo) <> -1) then
        ;   { lo is now the member name; CurTok sits on it }
      if CaseEqual(lo, 'set') then
      begin
        Next;
        Expect(tkOf, 'of');
        LastTypeEnumId := -1;
        if CurTok.Kind = tkInteger then
        begin
          { `set of <subrange>` e.g. `set of 1..10` — consume lo..hi (the element
            is an integer subrange). Without this the `..hi` leaked and the
            type-skip loop in ParseVarSection corrupted the variable's type away
            from tySet, so set ops/membership read garbage. }
          ConstEval;
          Expect(tkDotDot, '..');
          ConstEval;
          elemTk := tyInteger;
        end
        else
          elemTk := ParseTypeKind();
        { inline `set of TFoo`: the element parse records the enum identity in
          LastTypeEnumId; carry it as the set's element enum for RTTI. }
        LastTypeSetEnumId := LastTypeEnumId;
        LastTypeSetElemTk := Ord(elemTk);
        Result := tySet;
        Exit;
      end;
      if CaseEqual(lo, 'textfile') and (IsRecordType('text') <> REC_NONE) then
      begin
        { FPC: TextFile = Text. Resolve to the RTL `text` record — previously
          the unknown name fell through to a 4-byte integer slot. }
        LastTypeRecId := IsRecordType('text');
        Result := tyRecord;
      end
      else if CaseEqual(lo, 'file') then
        { untyped `file` / `file of T`: no file-variable model in pxx (the
          textfile RTL covers Text I/O). Reject at the type reference instead
          of silently minting an integer-sized slot
          (bug-pascal-missing-diagnostics-fail-tests / tdefault4). }
        Error('file types are not supported (use TextFile for text I/O)')
      else if CaseEqual(lo, 'ansistring') or
         CaseEqual(lo, 'unicodestring') or CaseEqual(lo, 'widestring') then
      begin
        { unicodestring/widestring: pragmatic alias to the native string type
          (byte semantics). FPC's UTF-16 payload model is a later slice; the
          alias gives literals/writeln/compare/case-of/indexing string
          behavior instead of a bare machine word
          (bug-pascal-unicodestring-widestring-type-missing). }
        if PasDefineExists('PXX_MANAGED_STRING') then
          Result := tyAnsiString
        else
          Result := tyString;
      end
      else if CaseEqual(lo, 'shortstring') then
      begin
        { Interim: `shortstring` maps to a 255-cap tyFixedString (word-prefix
          layout, so sizing matches the reused frozen codegen). The true
          byte-length-prefix tyShortString (FPC ABI) is a later codegen slice. }
        LastTypeStrCap := 255;
        Result := tyFixedString;
      end
      else if CaseEqual(lo, 'real') then
      begin
        if (TargetArch = TARGET_XTENSA) or (TargetArch = TARGET_RISCV32) then
          Result := tySingle  { Real = native float depth; ESP has no HW double }
        else
          Result := tyDouble;
      end
      else if CaseEqual(lo, 'single') then Result := tySingle
      else if CaseEqual(lo, 'double') then Result := tyDouble
      else if CaseEqual(lo, 'extended') then Result := tyDouble
        { Extended aliases Double (feature-extended-alias-or-reject, option a):
          arithmetic already ran in SSE2 double; the 10-byte x87 tyExtended
          storage gave no extra precision, so `Extended` is now plain Double on
          every target. The tyExtended enum + its x87 load/store paths remain but
          are no longer produced by the front end. }
      else if CaseEqual(lo, 'shortint') then Result := tyInt8
      else if CaseEqual(lo, 'byte') or CaseEqual(lo, 'uint8') then Result := tyUInt8
      else if CaseEqual(lo, 'smallint') then Result := tyInt16
      else if CaseEqual(lo, 'word') or CaseEqual(lo, 'uint16') then Result := tyUInt16
      else if CaseEqual(lo, 'longint') then Result := tyInt32
      else if CaseEqual(lo, 'cardinal') or CaseEqual(lo, 'longword') or CaseEqual(lo, 'uint32') or CaseEqual(lo, 'dword') then Result := tyUInt32
      else if CaseEqual(lo, 'int64') then Result := tyInt64
      else if CaseEqual(lo, 'qword') or CaseEqual(lo, 'uint64') then Result := tyUInt64
      else if CaseEqual(lo, 'nativeint') or CaseEqual(lo, 'ptrint') then Result := tyNativeInt
      else if CaseEqual(lo, 'nativeuint') or CaseEqual(lo, 'ptruint') then Result := tyNativeUInt
      else if CaseEqual(lo, 'pointer') then Result := tyPointer
      else if CaseEqual(lo, 'object') then
      begin
        { `object`: a rooted object reference — holds ANY class instance
          (pointer-sized, VMT at offset 0), no specific class bound. Modelled
          like the metaclass aliases: a tyPointer whose element is tyClass with
          no class id (PtrElemRec stays REC_NONE — "some object"). Assignable
          from any class reference; member access needs an explicit cast to a
          concrete class (`TFoo(o).M`), which errors naturally on the bare
          pointer. The tyClass element tag is what RTTI/tools key off to tell
          it from a raw Pointer. NOT legacy Object Pascal's value-`object`
          (record-with-methods); that syntax was never supported here.
          See feature-object-reference-type. }
        LastTypePointerElemTk := tyClass;
        Result := tyPointer;
      end
      else if CaseEqual(lo, 'pchar') or CaseEqual(lo, 'pansichar') then
      begin
        LastTypePointerElemTk := tyChar;
        Result := tyPointer;
      end
      else if CaseEqual(lo, 'variant') then Result := tyVariant
      else if EnableAutoVar and CaseEqual(lo, 'auto') then Result := tyAuto
      else
      begin
        { `Text`/`TextFile` resolve here as the record from the implicitly-loaded
          textfile unit (loaded up front in ParseProgram when a Text token is
          present), so no special-case is needed at this point. }
        ci := FindUClass(lo);
        if (ci >= 0) and UClsIsInterface[ci] then
        begin
          { Interface-typed variable: a 16-byte fat pointer {IMT, instance}.
            Modelled as a tyRecord whose rec id is the interface's UCls entry. }
          LastTypeRecId := REC_UCLASS_BASE + ci;
          Result := tyRecord;
        end
        else if IsClassType(lo) then
        begin
          ci := FindUClass(lo);
          if ci >= 0 then
            LastTypeRecId := REC_UCLASS_BASE + ci
          else
            LastTypeRecId := REC_NONE;
          Result := tyClass;
        end
        else
        begin
          LastTypeRecId := IsRecordType(lo);
          { A user `type X = ...` alias SHADOWS a same-named builtin record. The
            compiler exposes internal descriptor records (TProc, TParam, ...) under
            common names; a user program defining e.g. `type TProc = procedure(...)`
            must get its own type, not the builtin (FPC does not reserve these).
            Only triggers when both a record-name match and a user alias exist —
            which in valid source is exactly the user-alias-vs-builtin case. }
          if (LastTypeRecId <> REC_NONE) and (FindTypeAlias(lo) < 0) then
            Result := tyRecord
          else
          begin
            aliasIdx := FindTypeAlias(lo);
            if aliasIdx >= 0 then
            begin
              if AliasTk[aliasIdx] = Ord(tySet) then
              begin
                { Named set type: element enum kept in AliasElemTk but not
                  exposed as LastTypeEnumId, so the property kind stays SET.
                  Expose it as LastTypeSetEnumId for RTTI typeRef. }
                LastTypeSetEnumId := AliasElemTk[aliasIdx];
                Result := tySet;
              end
              else if AliasTk[aliasIdx] = Ord(tyPointer) then
              begin
                LastTypePointerElemTk := IntToTypeKind(AliasElemTk[aliasIdx]);
                LastTypePointerElemRec := AliasElemRec[aliasIdx];
                LastTypePointerDepth := AliasPtrDepth[aliasIdx];
                LastTypePointerBaseTk := AliasPtrBaseTk[aliasIdx];
                LastTypePointerBaseRec := AliasPtrBaseRec[aliasIdx];
                LastTypeProcSig := AliasProcSig[aliasIdx];
                Result := tyPointer;
              end
              else
              begin
                LastTypeRecId := AliasElemRec[aliasIdx];
                LastTypeProcSig := AliasProcSig[aliasIdx];  { method-pointer record carries a call signature }
                Result := IntToTypeKind(AliasTk[aliasIdx]);
              end;
            end
            else
            begin
              LastTypeEnumId := FindEnumType(lo);
              if (LastTypeEnumId < 0) and CaseEqual(lo, 'tobject') then
              begin
                { Builtin root class with no user TObject row (a user-declared
                  TObject won via IsClassType above): same rooted object
                  reference as `object` — pointer-sized, elem tyClass. It used
                  to fall through to tyInteger, silently TRUNCATING every
                  `Sender: TObject` param to 32 bits
                  (bug-tobject-param-truncated-32bit). }
                LastTypePointerElemTk := tyClass;
                Result := tyPointer;
              end
              else
                Result := tyInteger;  { enums are ordinal/integer-sized at codegen }
            end;
          end;
        end;
      end;
    end;
  end;
  Next;
end;

procedure ParseVarSection;
var names: array[0..MAX_DECL_NAMES-1] of AnsiString; n, i, idx: Integer; tk: TTypeKind;
    isArr, isDyn: Boolean; arrLo, arrHi: Integer; elemTk: TTypeKind; dynDepth: Integer;
    initElem: Integer; initVal: Int64; elemResolved: Boolean; elemDynDepth: Integer;
    isArrND: Boolean; ndCnt, dLo, dHi, di, flatLen, ai: Integer;
    moreDims: Boolean; elemProcSig: Integer;
    ndDimLo, ndDimSpan: array[0..MAX_ARR_DIMS-1] of Integer;
    initDepth, scOff, scLen: Integer;
begin
  Next;
  { Stop at section / declaration-introducer keywords: these are plain
    identifiers in this dialect, so a `var` block would otherwise consume the
    next one as a variable name. Besides the section words (implementation/
    initialization/finalization), this includes the decl-introducers that may
    follow a var section — `constructor`/`destructor` (method-impl bodies),
    `generic`/`specialize`/`operator`, and `label` — matching the top-level
    decl loop's soft-ident set. Without this, `var g: Integer; destructor
    TFoo.Destroy;` mis-reads `destructor` as a var name (real tokens like
    tkProcedure/tkFunction/tkBegin already stop the loop; the soft ones did
    not). See bug-var-section-eats-constructor-destructor. }
  while (CurTok.Kind = tkIdent) and
        not CaseEqual(CurTok.SVal, 'implementation') and
        not CaseEqual(CurTok.SVal, 'initialization') and
        not CaseEqual(CurTok.SVal, 'finalization') and
        not CaseEqual(CurTok.SVal, 'constructor') and
        not CaseEqual(CurTok.SVal, 'destructor') and
        not CaseEqual(CurTok.SVal, 'generic') and
        not CaseEqual(CurTok.SVal, 'specialize') and
        not CaseEqual(CurTok.SVal, 'operator') and
        not CaseEqual(CurTok.SVal, 'label') do
  begin
    n := 0;
    repeat
      if n >= MAX_DECL_NAMES then Error('too many comma-separated names in one var declaration');
      names[n] := CurTok.SVal; Inc(n); Next;
    until not Eat(tkComma);
    Expect(tkColon, ':');
    isArr := False; isDyn := False; arrLo := 0; arrHi := 0; elemTk := tyInteger;
    elemResolved := False; elemDynDepth := 0;
    elemProcSig := -1;
    isArrND := False; ndCnt := 0;
    ai := -1;
    if CurTok.Kind = tkIdent then ai := FindArrayType(CurTok.SVal);
    if ai >= 0 then
    begin
      { Variable of a named array type. }
      isArr := True;
      elemTk := IntToTypeKind(ArrTypeElemTk[ai]); tk := elemTk;
      LastTypeRecId := ArrTypeElemRec[ai];
      if ArrTypeIsDyn[ai] then
      begin
        { dynamic-array alias -> AllocDynArray below }
        isDyn := True; dynDepth := ArrTypeDynDepth[ai];
      end
      else
      begin
        arrLo := ArrTypeLo[ai]; arrHi := ArrTypeHi[ai];
        if ArrTypeNDims[ai] >= 2 then
        begin
          isArrND := True; ndCnt := ArrTypeNDims[ai];
          for di := 0 to ndCnt - 1 do
          begin
            ndDimLo[di]   := ArrTypeDimLo[ai * MAX_ARR_DIMS + di];
            ndDimSpan[di] := ArrTypeDimSpan[ai * MAX_ARR_DIMS + di];
          end;
        end;
      end;
      Next; { consume the type name }
    end
    else if CurTok.Kind = tkArray then
    begin
      isArr := True; Next;
      if CurTok.Kind = tkLBrack then
      begin
        { One or more comma-separated dimensions: `array[a..b, c..d, ...] of T`.
          An anonymous nested fixed array (`array[a] of array[b] of T`) has the
          SAME layout as `array[a,b] of T` in FPC, so merge the inner dims into
          the outer list. 1 dimension is an ordinary array; >=2 flattens to 1-D
          (N-D indexing via BuildFlatNDIndex). }
        ndCnt := 0;
        moreDims := True;
        while moreDims do
        begin
          Next;   { consume '[' }
          repeat
            dLo := ConstEval; Expect(tkDotDot, '..'); dHi := ConstEval;
            if ndCnt >= MAX_ARR_DIMS then Error('too many array dimensions');
            ndDimLo[ndCnt] := dLo; ndDimSpan[ndCnt] := dHi - dLo + 1; Inc(ndCnt);
          until not Eat(tkComma);
          Expect(tkRBrack, ']');
          Expect(tkOf, 'of');
          { Continue only for a FIXED nested array (`array [`), not a dynamic
            `array of` element or a scalar/record element type. }
          moreDims := (CurTok.Kind = tkArray) and (Tokens[TokPos].Kind = tkLBrack);
          if moreDims then Next;   { consume 'array'; loop head consumes '[' }
        end;
        if ndCnt = 1 then
        begin arrLo := ndDimLo[0]; arrHi := ndDimLo[0] + ndDimSpan[0] - 1; end
        else
        begin
          isArrND := True;
          flatLen := 1;
          for di := 0 to ndCnt - 1 do flatLen := flatLen * ndDimSpan[di];
          arrLo := 0; arrHi := flatLen - 1;
        end;
      end
      else
      begin
        isDyn := True;   { 'array of T' without bounds is a dynamic array }
        dynDepth := 1;
        Expect(tkOf, 'of');
        { Nested dynamic arrays: array of array of ... of BaseType. }
        while CurTok.Kind = tkArray do
        begin
          Next;
          if CurTok.Kind = tkLBrack then
            Error('mixed static/dynamic nested arrays not supported');
          Inc(dynDepth);
          Expect(tkOf, 'of');
        end;
        { A named dynamic-array alias as the element (`array of TA` where
          `TA = array of Integer`) composes its depth: the result is
          `array of (dyn TA)`, i.e. our dynDepth plus the alias's depth, with the
          alias's BASE element type. ParseTypeKind cannot do this — array-type
          aliases live in the ArrType table, not the scalar alias table, so it
          would resolve `TA` to a bare base type and drop the dynamic dimension. }
        if CurTok.Kind = tkIdent then
        begin
          ai := FindArrayType(CurTok.SVal);
          if (ai >= 0) and ArrTypeIsDyn[ai] then
          begin
            elemTk := IntToTypeKind(ArrTypeElemTk[ai]);
            LastTypeRecId := ArrTypeElemRec[ai];
            dynDepth := dynDepth + ArrTypeDynDepth[ai];
            Next;                 { consume the alias name }
            tk := elemTk;
            elemResolved := True;
          end;
        end;
      end;
      { A FIXED array whose element is a dynamic-array alias
        (`array[0..3] of TA`, TA = `array of T`): each element slot holds a
        pointer-sized dyn-array handle. Record the element's dyn depth in
        elemDynDepth (threaded into SymElemDynDepth via LastTypeElemDynDepth at
        AllocArray); base element type/rec come from the alias. The dynamic-outer
        case above already handled its own alias element. }
      if isArr and (not isDyn) and (not elemResolved) and (CurTok.Kind = tkIdent) then
      begin
        ai := FindArrayType(CurTok.SVal);
        if (ai >= 0) and ArrTypeIsDyn[ai] then
        begin
          elemTk := IntToTypeKind(ArrTypeElemTk[ai]);
          LastTypeRecId := ArrTypeElemRec[ai];
          elemDynDepth := ArrTypeDynDepth[ai];
          Next;                 { consume the alias name }
          tk := elemTk;
          elemResolved := True;
        end
        else if (ai >= 0) and (not ArrTypeIsDyn[ai]) then
        begin
          { A FIXED array whose element is a FIXED named-array type
            (`array[0..2] of TG`, `TG = array[0..3] of T`): same flat layout as
            `array[0..2,0..3] of T` — merge TG's dims into the outer list, like
            the anonymous-nested form. Without this ParseTypeKind drops TG's
            dimension and the element stride collapses to the base type's size. }
          if ArrTypeNDims[ai] >= 2 then
          begin
            for di := 0 to ArrTypeNDims[ai] - 1 do
            begin
              if ndCnt >= MAX_ARR_DIMS then Error('too many array dimensions');
              ndDimLo[ndCnt]   := ArrTypeDimLo[ai * MAX_ARR_DIMS + di];
              ndDimSpan[ndCnt] := ArrTypeDimSpan[ai * MAX_ARR_DIMS + di];
              Inc(ndCnt);
            end;
          end
          else
          begin
            if ndCnt >= MAX_ARR_DIMS then Error('too many array dimensions');
            ndDimLo[ndCnt]   := ArrTypeLo[ai];
            ndDimSpan[ndCnt] := ArrTypeHi[ai] - ArrTypeLo[ai] + 1;
            Inc(ndCnt);
          end;
          isArrND := True;
          flatLen := 1;
          for di := 0 to ndCnt - 1 do flatLen := flatLen * ndDimSpan[di];
          arrLo := 0; arrHi := flatLen - 1;
          elemTk := IntToTypeKind(ArrTypeElemTk[ai]);
          LastTypeRecId := ArrTypeElemRec[ai];
          tk := elemTk;
          elemResolved := True;
          Next;                 { consume the named array type }
        end;
      end;
      if not elemResolved then
      begin
        elemTk := ParseTypeKind;
        tk := elemTk;
        { array of <proctype>: element carries a call signature (plain proc =>
          tyPointer, method pointer => tyRecord). Captured for indexed indirect
          calls `arr[i](args)`. }
        if (elemTk = tyPointer) or (elemTk = tyRecord) then
          elemProcSig := LastTypeProcSig;
      end;
    end
    else
    begin
      { Skip qualifiers like pointer, ^, etc. Stop at `=` so a scalar
        initializer (`var x: Integer = 5`) is left for the init handler below. }
      while not (CurTok.Kind in [tkSemicolon, tkEq, tkBegin, tkVar, tkConst, tkType,
                 tkProcedure, tkFunction, tkEOF]) do
      begin
        tk := ParseTypeKind;
      end;
    end;
	    if isArr then
	      for i := 0 to n-1 do
	      begin
	        if isDyn then
	          idx := AllocDynArray(names[i], elemTk, dynDepth)
	        else
	        begin
	          LastTypeElemDynDepth := elemDynDepth;  { fixed array of a dyn-array element (consumed + reset by AllocArray) }
	          idx := AllocArray(names[i], elemTk, arrLo, arrHi);
	          if elemTk = tyRecord then
	            Syms[idx].ElemRecName := LastTypeRecId;
	          if isArrND then
	          begin
	            SymArrNDims[idx] := ndCnt;
	            for di := 0 to ndCnt - 1 do
	            begin
	              SymArrDimLo[idx * MAX_ARR_DIMS + di]   := ndDimLo[di];
	              SymArrDimSpan[idx * MAX_ARR_DIMS + di] := ndDimSpan[di];
	            end;
	          end;
	        end;
	        if elemProcSig >= 0 then SymElemProcSig[idx] := elemProcSig;  { array of proc-type: indexed indirect call arr[i](args) }
	      end
	    else
	      for i := 0 to n-1 do
	      begin
	        idx := AllocVar(names[i], tk);
	        if (tk = tyInteger) and (LastTypeEnumId >= 0) then SymEnumId[idx] := LastTypeEnumId;
	        if (tk = tyRecord) or (tk = tyClass) then
	        begin
	          Syms[idx].RecName := LastTypeRecId;
	          SymProcSig[idx] := LastTypeProcSig;   { method-pointer record: callable }
	        end
	        else if tk = tyPointer then
	        begin
	          Syms[idx].PtrElemTk := LastTypePointerElemTk;
	          Syms[idx].PtrElemRec := LastTypePointerElemRec;
	          SymProcSig[idx] := LastTypeProcSig;
	        end
	        else if tk = tySet then
	        begin
	          SymSetEnumId[idx] := LastTypeSetEnumId;
	          SymSetElemTk[idx] := LastTypeSetElemTk;
	        end;
	      end;
	    if Eat(tkEq) then
	    begin
	      { Constant initializer `= v` / `= (e0,e1,...)`. Recorded as pending
	        assignments compiled into the program entry just before `main begin`
	        (was silently discarded → globals read 0). Constants only; globals
	        only — a local section initializer should use inline `var x := v`. }
	      if n <> 1 then Error('initializer requires a single variable');
	      if CurProc >= 0 then
	        Error('local var-section initializer not supported; use `var x := value;`');
	      if isDyn then Error('dynamic array initializer not supported');
	      if CurTok.Kind = tkLParen then
	      begin
	        if not isArr then Error('parenthesised initializer requires an array variable');
	        Next;
	        initElem := 0;
	        { N-D array initializers nest one paren level per dimension
	          (`array[0..1,0..2] of T = ((a,b,c),(d,e,f))`); the flat store
	          fills in row-major order regardless of nesting depth, same as
	          ParseConstSection's array-constant loop. This used to be a flat
	          comma list (1-D only, no paren-depth tracking at all), so any
	          2+ dimensional var initializer broke structurally -- see
	          bug-array-const-too-many-elements-synapse. }
	        initDepth := 1;
	        while initDepth > 0 do
	        begin
	          if CurTok.Kind = tkLParen then begin Next; Inc(initDepth); end
	          else if CurTok.Kind = tkRParen then begin Next; Dec(initDepth); end
	          else if CurTok.Kind = tkComma then Next
	          else
	          begin
	            if PendingInitCount >= MAX_PENDING_INITS then Error('too many global initializers');
	            if initElem > (arrHi - arrLo) then Error('too many array initializer elements');
	            if elemTk in [tyString, tyAnsiString, tyFixedString, tyShortString] then
	            begin
	              { String/AnsiString elements can't go through ParseInitVal/
	                ConstEval -- ConstEvalFactor only special-cases single-char
	                literals as an ordinal; a multi-char literal falls through
	                without consuming the token, desyncing initElem from the
	                real token stream (same underlying bug as
	                bug-const-array-of-ansistring-literal-too-many-elements,
	                fixed there for ParseConstSection but never mirrored here
	                for ParseVarSection). Capture the literal's span directly
	                and record it as a Kind=1 (string literal) init, same as
	                ParseConstSection's array-constant string handling. }
	              if CurTok.Kind <> tkString then
	                Error('array constant: expected a string or char literal');
	              scOff := Tokens[TokPos-1].SOffset;
	              scLen := Tokens[TokPos-1].SLen;
	              Next;
	              PendingInitSym[PendingInitCount]    := idx;
	              PendingInitElem[PendingInitCount]   := arrLo + initElem;
	              PendingInitFOff[PendingInitCount]   := -1;
	              PendingInitKind[PendingInitCount]   := 1;
	              PendingInitVal[PendingInitCount]     := scOff;
	              PendingInitValAux[PendingInitCount] := scLen;
	              PendingInitTk[PendingInitCount]     := Ord(elemTk);
	            end
	            else
	            begin
	              initVal := ParseInitVal;
	              PendingInitSym[PendingInitCount]  := idx;
	              PendingInitElem[PendingInitCount] := arrLo + initElem;
	              PendingInitFOff[PendingInitCount] := -1;
	              PendingInitKind[PendingInitCount] := 0;
	              PendingInitVal[PendingInitCount]  := initVal;
	              PendingInitTk[PendingInitCount]   := Ord(elemTk);
	            end;
	            Inc(PendingInitCount);
	            Inc(initElem);
	          end;
	        end;
	      end
	      else
	      begin
	        if isArr then Error('array initializer must be parenthesised');
	        if PendingInitCount >= MAX_PENDING_INITS then Error('too many global initializers');
	        if (CurTok.Kind = tkIdent) and IsClassType(CurTok.SVal) and
	           (FindSym(CurTok.SVal) < 0) then
	        begin
	          { initialized metaclass var: `SSLImplementation: TSSLClass = TSSLNone;`
	            (blcksock) — init kind 5, an AN_CLASSREF (VMT address) assignment;
	            same shape as ParseConstSection's typed metaclass const. }
	          initVal := FindUClass(CurTok.SVal);
	          if initVal < 0 then Error('unknown class in initializer');
	          Next;
	          PendingInitKind[PendingInitCount] := 5;
	          PendingInitTk[PendingInitCount]   := Ord(tyPointer);
	        end
	        else
	        begin
	          initVal := ParseInitVal;
	          PendingInitKind[PendingInitCount] := 0;
	          PendingInitTk[PendingInitCount]   := Ord(tk);
	        end;
	        PendingInitSym[PendingInitCount]  := idx;
	        PendingInitElem[PendingInitCount] := -1;
        PendingInitFOff[PendingInitCount] := -1;
	        PendingInitVal[PendingInitCount]  := initVal;
	        Inc(PendingInitCount);
	      end;
	    end;
	    Eat(tkSemicolon);
	  end;
	end;

function BakeSetConst: Integer;
{ Parse a constant `[...]` set literal (elements + `lo..hi` ranges, all
  ConstEval-able) and bake its 32-byte (256-bit) bitmask into Data[]; return the
  Data offset. Same blob shape IR_SET_LIT emits for an all-constant literal, so a
  use resolves to that address. CurTok must be `[`. }
var lo, hi, vv, idx, i, bit, k: Integer;
begin
  Expect(tkLBrack, '[');
  while (DataLen mod 8) <> 0 do
  begin
    if DataLen >= MAX_DATA then Error('data overflow');
    Data[DataLen] := 0; Inc(DataLen);
  end;
  idx := DataLen;
  for i := 0 to 31 do
  begin
    if DataLen >= MAX_DATA then Error('data overflow');
    Data[DataLen] := 0; Inc(DataLen);
  end;
  if CurTok.Kind <> tkRBrack then
    repeat
      lo := ConstEval;
      hi := lo;
      if Eat(tkDotDot) then hi := ConstEval;
      if lo < 0 then lo := 0;
      if hi > 255 then hi := 255;
      for vv := lo to hi do
      begin
        { bit := 1 shl (vv mod 8) — built with *2 to avoid `shl` in compiler
          source (Shl8_ lives in ir.inc, included after this file). }
        bit := 1;
        for k := 1 to (vv mod 8) do bit := bit * 2;
        Data[idx + (vv div 8)] := Data[idx + (vv div 8)] or bit;
      end;
    until not Eat(tkComma);
  Expect(tkRBrack, ']');
  Result := idx;
end;

{ FPC hint directives — `deprecated ['msg']`, `platform`, `experimental`,
  `unimplemented`, `library` — may trail a const value, a type declaration, or a
  routine header. They only drive an optional compiler warning, so pxx parses and
  ignores them (no code effect). Soft identifiers in this dialect, so consume a
  run of them here rather than choke. `deprecated` takes an optional string
  message. See feature-hint-directives-deprecated-platform. }
procedure SkipHintDirectives;
begin
  while (CurTok.Kind = tkIdent) and
        (CaseEqual(CurTok.SVal, 'deprecated') or
         CaseEqual(CurTok.SVal, 'platform') or
         CaseEqual(CurTok.SVal, 'experimental') or
         CaseEqual(CurTok.SVal, 'unimplemented') or
         CaseEqual(CurTok.SVal, 'library')) do
  begin
    if CaseEqual(CurTok.SVal, 'deprecated') then
    begin
      Next;
      if CurTok.Kind = tkString then Next;   { optional 'use X instead' message }
    end
    else
      Next;
  end;
end;

procedure ParseConstSection;
var name: AnsiString; v: Int64;
    cTk, cElemTk: TTypeKind; cLo, cHi, cIdx, cElem: Integer;
    isLocalConst: Boolean;
    cRec, fNameOff, fNameLen: Integer; fName: AnsiString; fTk: TTypeKind;
    cnNDims, cFlatLen, cDi, cDepth: Integer;
    scOff, scLen, si, sci2, cCi, cAi: Integer;
    cnDimLo, cnDimSpan: array[0..MAX_ARR_DIMS-1] of Integer;
begin
  Next;
  { `constructor`/`destructor`/`operator` and the unit section words are plain
    identifiers in this dialect (not keyword tokens like `procedure`/`function`,
    which terminate the loop naturally). Without these guards a const section
    directly followed by a constructor/destructor body — or ending an interface
    before `implementation` — would consume that word as the next const NAME and
    then fail expecting `=`. Mirrors the type-section terminator set. }
  while (CurTok.Kind = tkIdent) and
        (not CaseEqual(CurTok.SVal, 'constructor')) and
        (not CaseEqual(CurTok.SVal, 'destructor')) and
        (not CaseEqual(CurTok.SVal, 'operator')) and
        (not CaseEqual(CurTok.SVal, 'implementation')) and
        (not CaseEqual(CurTok.SVal, 'initialization')) and
        (not CaseEqual(CurTok.SVal, 'finalization')) do
  begin
    name := CurTok.SVal; Next;
    if CurTok.Kind = tkColon then
    begin
      { Typed constant: `const Name: type = value | (e0,e1,...)`. FPC typed
        constants are writable storage with an initial value, so allocate storage
        and reuse the pending-init machinery (same as a `var = init`).

        Two destinations by scope: a GLOBAL typed const records into PendingInit
        (compiled before `main begin`); a routine-LOCAL one (CurProc >= 0)
        records into LocalInit, compiled into that routine's prologue so its
        stack-resident table is re-initialized on each call. AllocArray/AllocVar
        already place storage at the right scope from CurProc. Ordinal/Char/Int64
        element types; string/float/record initializers remain a follow-up. }
      isLocalConst := CurProc >= 0;
      Next;
      { A NAMED fixed-array type (`Action0: TLogonActions = (...)`, ftpsend)
        takes the same array-constant path as the inline `array[..] of T`
        form: load its dims/element from the ArrType tables. }
      cAi := -1;
      if CurTok.Kind = tkIdent then
      begin
        cAi := FindArrayType(CurTok.SVal);
        if (cAi >= 0) and ArrTypeIsDyn[cAi] then cAi := -1;
      end;
      if (CurTok.Kind = tkArray) or (cAi >= 0) then
      begin
        if cAi >= 0 then
        begin
          Next;   { consume the named array type }
          cnNDims := ArrTypeNDims[cAi];
          if cnNDims >= 2 then
          begin
            for cDi := 0 to cnNDims - 1 do
            begin
              cnDimLo[cDi]   := ArrTypeDimLo[cAi * MAX_ARR_DIMS + cDi];
              cnDimSpan[cDi] := ArrTypeDimSpan[cAi * MAX_ARR_DIMS + cDi];
            end;
          end
          else
          begin
            cnNDims := 1;
            cnDimLo[0]   := ArrTypeLo[cAi];
            cnDimSpan[0] := ArrTypeHi[cAi] - ArrTypeLo[cAi] + 1;
          end;
          cElemTk := IntToTypeKind(ArrTypeElemTk[cAi]);
          LastTypeRecId := ArrTypeElemRec[cAi];
        end
        else
        begin
        Next;
        Expect(tkLBrack, '[');
        { One or more comma-separated dimensions, mirroring the var-section ND
          path. >=2 dims flatten to a 1-D row-major store indexed as an N-D array
          (SymArrNDims), so `const M: array[0..1,0..1] of T = ((..),(..))` works
          like the var form. }
        cnNDims := 0;
        repeat
          cLo := ConstEval; Expect(tkDotDot, '..'); cHi := ConstEval;
          if cnNDims >= MAX_ARR_DIMS then Error('too many array dimensions');
          cnDimLo[cnNDims] := cLo; cnDimSpan[cnNDims] := cHi - cLo + 1; Inc(cnNDims);
        until not Eat(tkComma);
        Expect(tkRBrack, ']');
        Expect(tkOf, 'of');
        cElemTk := ParseTypeKind;
        end;
        if cnNDims = 1 then
        begin
          cLo := cnDimLo[0]; cFlatLen := cnDimSpan[0];
        end
        else
        begin
          cFlatLen := 1;
          for cDi := 0 to cnNDims - 1 do cFlatLen := cFlatLen * cnDimSpan[cDi];
          cLo := 0;
        end;
        cHi := cLo + cFlatLen - 1;
        cIdx := AllocArray(name, cElemTk, cLo, cHi);
        if cElemTk = tyRecord then Syms[cIdx].ElemRecName := LastTypeRecId;
        if cnNDims >= 2 then
        begin
          SymArrNDims[cIdx] := cnNDims;
          for cDi := 0 to cnNDims - 1 do
          begin
            SymArrDimLo[cIdx * MAX_ARR_DIMS + cDi]   := cnDimLo[cDi];
            SymArrDimSpan[cIdx * MAX_ARR_DIMS + cDi] := cnDimSpan[cDi];
          end;
        end;
        Expect(tkEq, '=');
        { Nested-paren initializer flattened in row-major encounter order. A 1-D
          array is one paren level; an N-D one nests one level per dimension, but
          the flat store fills in order regardless of nesting depth. }
        Expect(tkLParen, '(');
        cDepth := 1; cElem := 0;
        while cDepth > 0 do
        begin
          if CurTok.Kind = tkLParen then begin Next; Inc(cDepth); end
          else if CurTok.Kind = tkRParen then begin Next; Dec(cDepth); end
          else if CurTok.Kind = tkComma then Next
          else
          begin
            if cElem >= cFlatLen then Error('too many array constant elements');
            if cElemTk in [tyString, tyAnsiString, tyFixedString, tyShortString] then
            begin
              { String/AnsiString array-const elements can't go through
                ParseInitVal/ConstEval (ConstEvalFactor only special-cases
                single-char literals as an ordinal; a multi-char literal falls
                through without consuming the token, desyncing cElem from the
                real token stream -- bug-const-array-of-ansistring-literal-too-
                many-elements). Capture the literal's span directly, exactly
                like the scalar typed-string-const path above, and record it as
                a Kind=1 (string literal) init so the emitter builds an
                AN_STR_LIT assignment -- same managed-string coercion any
                ordinary `s := 'literal'` already gets. }
              if CurTok.Kind <> tkString then
                Error('array constant: expected a string or char literal');
              scOff := Tokens[TokPos-1].SOffset;
              scLen := Tokens[TokPos-1].SLen;
              Next;
              if isLocalConst then
              begin
                if LocalInitCount >= MAX_LOCAL_INITS then Error('too many local initializers');
                LocalInitSym[LocalInitCount]  := cIdx;
                LocalInitElem[LocalInitCount] := cLo + cElem;
                LocalInitFOff[LocalInitCount] := -1;
                LocalInitKind[LocalInitCount] := 1;
                LocalInitVal[LocalInitCount]  := scOff;
                LocalInitFLen[LocalInitCount] := scLen;
                LocalInitTk[LocalInitCount]   := Ord(cElemTk);
                Inc(LocalInitCount);
              end
              else
              begin
                if PendingInitCount >= MAX_PENDING_INITS then Error('too many global initializers');
                PendingInitSym[PendingInitCount]    := cIdx;
                PendingInitElem[PendingInitCount]   := cLo + cElem;
                PendingInitFOff[PendingInitCount]   := -1;
                PendingInitKind[PendingInitCount]   := 1;
                PendingInitVal[PendingInitCount]    := scOff;
                PendingInitValAux[PendingInitCount] := scLen;
                PendingInitTk[PendingInitCount]     := Ord(cElemTk);
                Inc(PendingInitCount);
              end;
            end
            else if isLocalConst then
            begin
              if LocalInitCount >= MAX_LOCAL_INITS then Error('too many local initializers');
              LocalInitSym[LocalInitCount]  := cIdx;
              LocalInitElem[LocalInitCount] := cLo + cElem;
              LocalInitFOff[LocalInitCount] := -1;
              LocalInitVal[LocalInitCount]  := ParseInitVal;
              LocalInitTk[LocalInitCount]   := Ord(cElemTk);
              Inc(LocalInitCount);
            end
            else
            begin
              if PendingInitCount >= MAX_PENDING_INITS then Error('too many global initializers');
              PendingInitSym[PendingInitCount]  := cIdx;
              PendingInitElem[PendingInitCount] := cLo + cElem;
              PendingInitFOff[PendingInitCount] := -1;
              PendingInitVal[PendingInitCount]  := ParseInitVal;
              PendingInitTk[PendingInitCount]   := Ord(cElemTk);
              Inc(PendingInitCount);
            end;
            Inc(cElem);
          end;
        end;
        if cElem <> cFlatLen then Error('wrong number of array constant elements');
      end
      else
      begin
        cTk := ParseTypeKind;
        if cTk = tySet then
        begin
          { Typed set constant `const S: TS = [..]`: bake the 32-byte mask and
            record it in the SetConst table; uses resolve to AN_SET_CONST_REF.
            No runtime var symbol is allocated — the const carries no storage, and
            a phantom var would shadow a same-named variable case-insensitively
            (bug-set-of-char-const-corrupts-char-codegen). }
          Expect(tkEq, '=');
          if SetConstCount >= MAX_TYPEALIAS then Error('too many set constants');
          SetConstName[SetConstCount]   := name;
          SetConstEnumId[SetConstCount] := LastTypeSetEnumId;
          SetConstOff[SetConstCount]    := BakeSetConst;
          Inc(SetConstCount);
        end
        else if cTk in [tyString, tyAnsiString, tyFixedString, tyShortString] then
        begin
          { Typed string constant `const Name: string = 'literal'` (and the
            `'a' + 'b'` / `#65 + #66` concatenation form). Treated as a read-only
            string-literal alias — registered in the StrConst table exactly like
            the untyped `const Name = 'literal'` path, with NO storage var (a
            phantom var would shadow a same-named variable and ParseInitVal has no
            string case). A use of the name expands to AN_STR_LIT over the span,
            which already coerces to a managed string where needed. }
          Expect(tkEq, '=');
          if CurTok.Kind <> tkString then
            Error('typed string constant: expected a string or char literal');
          if (Tokens[TokPos].Kind = tkPlus) then
          begin
            scOff := TokCharLen; scLen := 0;
            for si := 1 to Length(CurTok.SVal) do
            begin
              if TokCharLen >= STRING_CAP then Error('string constant buffer overflow');
              TokChars[TokCharLen] := CurTok.SVal[si]; Inc(TokCharLen); Inc(scLen);
            end;
            Next;
            while CurTok.Kind = tkPlus do
            begin
              Next;
              if CurTok.Kind <> tkString then
                Error('const string concatenation: expected a string or char literal');
              for si := 1 to Length(CurTok.SVal) do
              begin
                if TokCharLen >= STRING_CAP then Error('string constant buffer overflow');
                TokChars[TokCharLen] := CurTok.SVal[si]; Inc(TokCharLen); Inc(scLen);
              end;
              Next;
            end;
            if StrConstCount >= MAX_TYPEALIAS then Error('too many string constants');
            StrConstName[StrConstCount] := name;
            StrConstSOff[StrConstCount] := scOff;
            StrConstSLen[StrConstCount] := scLen;
            Inc(StrConstCount);
          end
          else
          begin
            if StrConstCount >= MAX_TYPEALIAS then Error('too many string constants');
            StrConstName[StrConstCount] := name;
            StrConstSOff[StrConstCount] := Tokens[TokPos-1].SOffset;
            StrConstSLen[StrConstCount] := Tokens[TokPos-1].SLen;
            Inc(StrConstCount);
            Next;
          end;
        end
        else
        begin
        cIdx := AllocVar(name, cTk);
        if cTk = tyPointer then
        begin
          { metaclass / pointer typed const: keep the pointee info so uses
            (SSLImplementation.Create) dispatch like a var of the type }
          Syms[cIdx].PtrElemTk := LastTypePointerElemTk;
          Syms[cIdx].PtrElemRec := LastTypePointerElemRec;
        end;
        Expect(tkEq, '=');
        if (cTk <> tyRecord) and (CurTok.Kind = tkIdent) and
           IsClassType(CurTok.SVal) and (FindSym(CurTok.SVal) < 0) then
        begin
          { Metaclass typed const initialized with a class NAME —
            `SSLImplementation: TSSLClass = TSSLNone;` (blcksock). Init kind 5:
            the emitter builds an AN_CLASSREF (VMT address) assignment. }
          cCi := FindUClass(CurTok.SVal);
          if cCi < 0 then Error('unknown class in constant initializer');
          Next;
          if isLocalConst then
          begin
            if LocalInitCount >= MAX_LOCAL_INITS then Error('too many local initializers');
            LocalInitSym[LocalInitCount]  := cIdx;
            LocalInitElem[LocalInitCount] := -1;
            LocalInitFOff[LocalInitCount] := -1;
            LocalInitKind[LocalInitCount] := 5;
            LocalInitVal[LocalInitCount]  := cCi;
            LocalInitTk[LocalInitCount]   := Ord(tyPointer);
            Inc(LocalInitCount);
          end
          else
          begin
            if PendingInitCount >= MAX_PENDING_INITS then Error('too many global initializers');
            PendingInitSym[PendingInitCount]  := cIdx;
            PendingInitElem[PendingInitCount] := -1;
            PendingInitFOff[PendingInitCount] := -1;
            PendingInitKind[PendingInitCount] := 5;
            PendingInitVal[PendingInitCount]  := cCi;
            PendingInitTk[PendingInitCount]   := Ord(tyPointer);
            Inc(PendingInitCount);
          end;
        end
        else if cTk = tyRecord then
        begin
          { Record typed constant: `const r: TRec = (f1: v1; f2: v2; ...)` (FPC
            named-field form). Each scalar field initializer is recorded as a
            `r.field := value` init (field span drives an AN_FIELD target in the
            init emitter). Nested record/array fields are not handled yet. }
          cRec := Syms[cIdx].RecName;
          Expect(tkLParen, '(');
          while CurTok.Kind <> tkRParen do
          begin
            if CurTok.Kind <> tkIdent then Error('expected field name in record constant');
            fName := CurTok.SVal;
            fNameOff := Tokens[TokPos-1].SOffset;
            fNameLen := Tokens[TokPos-1].SLen;
            Next;
            Expect(tkColon, ':');
            fTk := RecFieldType(cRec, fName);
            if fTk = tyUnknown then Error('unknown field in record constant: ' + fName);
            if isLocalConst then
            begin
              if LocalInitCount >= MAX_LOCAL_INITS then Error('too many local initializers');
              LocalInitSym[LocalInitCount]  := cIdx;
              LocalInitElem[LocalInitCount] := -1;
              LocalInitFOff[LocalInitCount] := fNameOff;
              LocalInitFLen[LocalInitCount] := fNameLen;
              LocalInitVal[LocalInitCount]  := ParseInitVal;
              LocalInitTk[LocalInitCount]   := Ord(fTk);
              Inc(LocalInitCount);
            end
            else
            begin
              if PendingInitCount >= MAX_PENDING_INITS then Error('too many global initializers');
              PendingInitSym[PendingInitCount]  := cIdx;
              PendingInitElem[PendingInitCount] := -1;
              PendingInitFOff[PendingInitCount] := fNameOff;
              PendingInitFLen[PendingInitCount] := fNameLen;
              PendingInitVal[PendingInitCount]  := ParseInitVal;
              PendingInitTk[PendingInitCount]   := Ord(fTk);
              Inc(PendingInitCount);
            end;
            { FPC separates fields with `;`; tolerate a trailing `,` too. }
            if not Eat(tkSemicolon) then Eat(tkComma);
          end;
          Expect(tkRParen, ')');
        end
        else if isLocalConst then
        begin
          if LocalInitCount >= MAX_LOCAL_INITS then Error('too many local initializers');
          LocalInitSym[LocalInitCount]  := cIdx;
          LocalInitElem[LocalInitCount] := -1;
          LocalInitFOff[LocalInitCount] := -1;
          LocalInitKind[LocalInitCount] := 0;   { slots are reused; clear a stale kind }
          LocalInitVal[LocalInitCount]  := ParseInitVal;
          LocalInitTk[LocalInitCount]   := Ord(cTk);
          Inc(LocalInitCount);
        end
        else
        begin
          if PendingInitCount >= MAX_PENDING_INITS then Error('too many global initializers');
          PendingInitSym[PendingInitCount]  := cIdx;
          PendingInitElem[PendingInitCount] := -1;
          PendingInitFOff[PendingInitCount] := -1;
          PendingInitKind[PendingInitCount] := 0;
          PendingInitVal[PendingInitCount]  := ParseInitVal;
          PendingInitTk[PendingInitCount]   := Ord(cTk);
          Inc(PendingInitCount);
        end;
        end;
      end;
    end
    else
    begin
      Expect(tkEq, '=');
      if CurTok.Kind = tkLBrack then
      begin
        { Untyped set constant `const S = [1,2,3]`: bake a plain-ordinal set mask
          (no element enum type) and record it; uses resolve to AN_SET_CONST_REF. }
        if SetConstCount >= MAX_TYPEALIAS then Error('too many set constants');
        SetConstName[SetConstCount]   := name;
        SetConstEnumId[SetConstCount] := -1;
        SetConstOff[SetConstCount]    := BakeSetConst;
        Inc(SetConstCount);
      end
      else if (CurTok.Kind = tkString) or
              ((CurTok.Kind = tkIdent) and (FindStrConst(CurTok.SVal) >= 0)) then
      begin
        if (CurTok.Kind = tkIdent) or (Tokens[TokPos].Kind = tkPlus) then
        begin
          { `+`-concatenation of string/char literals and NAMED string consts,
            e.g. `const T = #65 + #66`, `'foo' + 'bar'`, or blcksock's
            `CRLF = CR + LF` (CR/LF are prior #$0d/#$0a consts). #65 and 'A'
            both arrive as tkString tokens whose decoded value is in SVal; a
            named const contributes its recorded TokChars span. Build the
            concatenated value into a fresh TokChars span and point the string
            const at it; a use expands to an AN_STR_LIT over that span, like a
            single literal (bug-char-literal-concat-in-const-expr). A single
            named-const operand (`A = CR;`) shares the source span. }
          scOff := TokCharLen; scLen := 0;
          repeat
            if CurTok.Kind = tkString then
            begin
              for si := 1 to Length(CurTok.SVal) do
              begin
                if TokCharLen >= STRING_CAP then Error('string constant buffer overflow');
                TokChars[TokCharLen] := CurTok.SVal[si]; Inc(TokCharLen); Inc(scLen);
              end;
            end
            else if (CurTok.Kind = tkIdent) and (FindStrConst(CurTok.SVal) >= 0) then
            begin
              sci2 := FindStrConst(CurTok.SVal);
              for si := StrConstSOff[sci2] to StrConstSOff[sci2] + StrConstSLen[sci2] - 1 do
              begin
                if TokCharLen >= STRING_CAP then Error('string constant buffer overflow');
                TokChars[TokCharLen] := TokChars[si]; Inc(TokCharLen); Inc(scLen);
              end;
            end
            else
              Error('const string concatenation: expected a string/char literal or string constant');
            Next;
          until not Eat(tkPlus);
          if StrConstCount >= MAX_TYPEALIAS then Error('too many string constants');
          StrConstName[StrConstCount] := name;
          StrConstSOff[StrConstCount] := scOff;
          StrConstSLen[StrConstCount] := scLen;
          Inc(StrConstCount);
        end
        else
        begin
          { Untyped string constant: remember the literal's source span; a use of
            the name builds an AN_STR_LIT over it. }
          if StrConstCount >= MAX_TYPEALIAS then Error('too many string constants');
          StrConstName[StrConstCount] := name;
          StrConstSOff[StrConstCount] := Tokens[TokPos-1].SOffset;
          StrConstSLen[StrConstCount] := Tokens[TokPos-1].SLen;
          Inc(StrConstCount);
          Next;
        end;
      end
      else if (CurTok.Kind = tkFloat) or
              ((CurTok.Kind = tkMinus) and (Tokens[TokPos].Kind = tkFloat)) or
              ((CurTok.Kind = tkPlus) and (Tokens[TokPos].Kind = tkFloat)) then
      begin
        { Untyped real constant (`const EPS = 0.001;` / `= -2.5` / `= 1e-9`). FPC
          infers a real-typed const. Store the IEEE-754 double bits tagged
          tyDouble (sign handled by ParseInitVal); a use builds an AN_FLOAT_LIT. }
        AddConst(name, tyDouble, ParseInitVal);
      end
      else
      begin
        v := ConstEval;
        AddConst(name, tyInteger, v);
      end;
    end;
    SkipHintDirectives;   { const K = v deprecated; }
    Eat(tkSemicolon);
  end;
end;

{ Parse a variant part `case [tag:] T of c1,..: (fields); ...` into UCls
  entry `ci`, starting with CurTok on the `case` keyword. All branches are a
  union — their fields share the same base offset, and the record grows by
  the largest branch. A branch body may itself end in a nested variant part
  (`case f: T of` inside the parens — synsock's TVarSin), handled by direct
  recursion; a tagged discriminant declares its tag as an ordinary field at
  the variant offset; const case labels are skipped like any label list.
  Stops (without consuming) at the record's `end` (top level) or the
  enclosing branch's `)` (nested). Returns the field offset just past the
  variant part (base + largest branch). Scalar / fixed-array / record branch
  fields are supported. }
function ParseRecordVariantPart(ci: Integer; isPackedRecord: Boolean;
  startOff: Integer; var classAlign: Integer): Integer;
var
  variantBaseOff, variantMax, branchFieldOff, curOff: Integer;
  arrLen, loVal, hiVal, fRec, fSize, fAlign, nFldNames, fni: Integer;
  isArr: Boolean;
  fTk: TTypeKind;
  fldNOffs: array[0..15] of Integer;   { comma-separated field-name spans }
  fldNLens: array[0..15] of Integer;
begin
  curOff := startOff;
  Next;   { consume 'case' }
  if (CurTok.Kind = tkIdent) and (Tokens[TokPos].Kind = tkColon) then
  begin
    { discriminant is also a real (tag) field: `case tag: T of` }
    fldNOffs[0] := Tokens[TokPos-1].SOffset; fldNLens[0] := Tokens[TokPos-1].SLen;
    Next; Next;   { tag name, ':' }
    fTk := ParseTypeKind; fRec := LastTypeRecId;
    if fTk = tyRecord then fSize := RecSize(fRec) else fSize := TypeSize(fTk);
    fAlign := TypeAlign(fTk);
    if isPackedRecord then fAlign := 1;
    curOff := AlignTo(curOff, fAlign);
    AddUField(ci, fldNOffs[0], fldNLens[0], curOff, Ord(fTk), fRec);
    UFldIsArray[UFldCount-1] := False; UFldArrLen[UFldCount-1] := 1;
    UFldDynDepth[UFldCount-1] := 0;
    curOff := curOff + fSize;
    if fAlign > classAlign then classAlign := fAlign;
  end
  else
    ParseTypeKind;   { discriminant type only (no field) }
  Expect(tkOf, 'of');
  if isPackedRecord then
    variantBaseOff := curOff   { packed: branches overlay right after the tag }
  else
    variantBaseOff := AlignTo(curOff, TARGET_PTR_SIZE);
  variantMax := 0;
  while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkRParen) and
        (CurTok.Kind <> tkEOF) do
  begin
    { constant label list, e.g. `0, 1:` / `true:` / `AF_INET:` — skip to ':' }
    while (CurTok.Kind <> tkColon) and (CurTok.Kind <> tkEOF) do Next;
    Expect(tkColon, ':');
    Expect(tkLParen, '(');
    branchFieldOff := variantBaseOff;
    while (CurTok.Kind <> tkRParen) and (CurTok.Kind <> tkEOF) do
    begin
      if CurTok.Kind = tkCase then
      begin
        { nested variant part — grammatically the last item of the branch }
        branchFieldOff := ParseRecordVariantPart(ci, isPackedRecord,
          branchFieldOff, classAlign);
        break;
      end;
      if CurTok.Kind <> tkIdent then Error('expected field name in variant part');
      fldNOffs[0] := Tokens[TokPos-1].SOffset; fldNLens[0] := Tokens[TokPos-1].SLen;
      nFldNames := 1; Next;
      while CurTok.Kind = tkComma do
      begin
        Next;
        if CurTok.Kind <> tkIdent then Error('expected field name after ","');
        fldNOffs[nFldNames] := Tokens[TokPos-1].SOffset; fldNLens[nFldNames] := Tokens[TokPos-1].SLen;
        Inc(nFldNames); Next;
      end;
      Expect(tkColon, ':');
      isArr := False; arrLen := 1;
      if CurTok.Kind = tkArray then
      begin
        Next; Expect(tkLBrack, '[');
        loVal := ConstEval; Expect(tkDotDot, '..'); hiVal := ConstEval;
        arrLen := hiVal - loVal + 1;
        Expect(tkRBrack, ']'); Expect(tkOf, 'of');
        fTk := ParseTypeKind; fRec := LastTypeRecId; isArr := True;
      end
      else
      begin fTk := ParseTypeKind; fRec := LastTypeRecId; end;
      if fTk = tyRecord then fSize := RecSize(fRec) else fSize := TypeSize(fTk);
      fAlign := TypeAlign(fTk);
      if isPackedRecord then fAlign := 1;
      if isArr then fSize := fSize * arrLen;
      for fni := 0 to nFldNames - 1 do
      begin
        branchFieldOff := AlignTo(branchFieldOff, fAlign);
        AddUField(ci, fldNOffs[fni], fldNLens[fni], branchFieldOff, Ord(fTk), fRec);
        UFldIsArray[UFldCount-1] := isArr;
        UFldArrLen[UFldCount-1] := arrLen;
        UFldDynDepth[UFldCount-1] := 0;
        branchFieldOff := branchFieldOff + fSize;
      end;
      if fAlign > classAlign then classAlign := fAlign;
      Eat(tkSemicolon);
    end;
    Expect(tkRParen, ')');
    Eat(tkSemicolon);
    if (branchFieldOff - variantBaseOff) > variantMax then
      variantMax := branchFieldOff - variantBaseOff;
  end;
  Result := variantBaseOff + variantMax;
end;

{ Parse a record body's fields into UCls entry `ci`, from just after the
  `record` keyword through its closing `end` (consumed). Shared by named
  records (ParseTypeSection) and anonymous inline records
  (ParseTypeKind's tkRecord/tkPacked case — feature-anonymous-record-type).
  Handles comma field lists, nested fixed/dynamic array fields, and
  case/variant sections; sets UClsSize_/UClsAlign. }
procedure ParseRecordFields(ci: Integer; isPackedRecord: Boolean);
var
  arrLen, curFieldOff, fAi, fAlign, fDynDepth, fRec, fSize: Integer;
  hiVal, loVal, i, nFldNames, fni, fNDims: Integer;
  tdLo, tdHi, tdi, classAlign: Integer;
  isArr, fIsDyn: Boolean;
  fTk: TTypeKind;
  fldNOffs: array[0..15] of Integer;   { comma-separated field-name spans }
  fldNLens: array[0..15] of Integer;
  tdDimLo, tdDimSpan: array[0..MAX_ARR_DIMS-1] of Integer;
begin
  curFieldOff := 0;
  classAlign := 1;
  while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
  begin
    { `class var` inside a RECORD: no shared-storage model for record class
      vars in pxx (class-body class vars have one, see ParseTypeSection).
      FPC additionally forbids the local-type and anonymous-record contexts
      (terecs12c/terecs13c) — reject all three loudly instead of silently
      skipping the section (the old fall-through made TRec.X fail later with
      a misleading 'class method not found'). }
    if (CurTok.Kind = tkClass) and (TokPos < TokCount) and
       (Tokens[TokPos].Kind = tkVar) then
      Error('class var is not allowed in a record type');
    if CurTok.Kind = tkIdent then
    begin
      { comma-separated names share one type: `X, Y: Integer` }
      fldNOffs[0] := Tokens[TokPos-1].SOffset;
      fldNLens[0] := Tokens[TokPos-1].SLen;
      nFldNames := 1;
      Next;
      while CurTok.Kind = tkComma do
      begin
        Next;
        if CurTok.Kind <> tkIdent then Error('expected field name after ","');
        fldNOffs[nFldNames] := Tokens[TokPos-1].SOffset;
        fldNLens[nFldNames] := Tokens[TokPos-1].SLen;
        Inc(nFldNames);
        Next;
      end;
      Expect(tkColon, ':');
      isArr := False;
      arrLen := 1;
      fIsDyn := False;
      fDynDepth := 0;
      fNDims := 0;
      if CurTok.Kind = tkArray then
      begin
        Next;
        if CurTok.Kind = tkLBrack then
        begin
          Next;
          { Const-EXPRESSION bounds (`0..N - 1`), not just literals — same
            ConstEval the named array-type path uses
            (bug-inline-array-field-const-bound). }
          loVal := ConstEval;
          Expect(tkDotDot, '..');
          hiVal := ConstEval;
          arrLen := hiVal - loVal + 1;
          { N-D field: collect dim0 then any comma dims. }
          fNDims := 1; tdDimLo[0] := loVal; tdDimSpan[0] := hiVal - loVal + 1;
          while CurTok.Kind = tkComma do
          begin
            Eat(tkComma);
            tdLo := ConstEval;
            Expect(tkDotDot, '..');
            tdHi := ConstEval;
            if fNDims >= MAX_ARR_DIMS then Error('too many array dimensions');
            tdDimLo[fNDims] := tdLo; tdDimSpan[fNDims] := tdHi - tdLo + 1;
            arrLen := arrLen * tdDimSpan[fNDims];
            Inc(fNDims);
          end;
          Expect(tkRBrack, ']');
          Expect(tkOf, 'of');
          fTk := ParseTypeKind;
          fRec := LastTypeRecId;
          isArr := True;
        end
        else
        begin
          { Dynamic-array field: `array of T`, including nested. }
          fIsDyn := True;
          fDynDepth := 1;
          Expect(tkOf, 'of');
          while CurTok.Kind = tkArray do
          begin
            Next;
            Inc(fDynDepth);
            Expect(tkOf, 'of');
          end;
          fTk := ParseTypeKind;
          fRec := LastTypeRecId;
        end;
      end
      else
      begin
        { Named dynamic-array type field (`TDynArr = array of T`): mirror
          the inline `array of T` field so SetLength/Length/indexing see a
          real dynamic array. Without this the field's UFldDynDepth stayed
          0 and SetLength(Self.field, n) misrouted to the string path. }
        fAi := -1;
        if CurTok.Kind = tkIdent then fAi := FindArrayType(CurTok.SVal);
        if (fAi >= 0) and ArrTypeIsDyn[fAi] then
        begin
          fIsDyn := True;
          fDynDepth := ArrTypeDynDepth[fAi];
          fTk := IntToTypeKind(ArrTypeElemTk[fAi]);
          fRec := ArrTypeElemRec[fAi];
          Next;   { consume the named array type }
        end
        else if (fAi >= 0) and (not ArrTypeIsDyn[fAi]) then
        begin
          { Named FIXED-array type field (`a: TG`, `TG = array[..] of T`):
            make it a real array field (1-D or flattened N-D) so a.x[i]
            indexes with the right stride. Without this ParseTypeKind drops
            TG's dimension and the field collapses to a single base element
            (corrupting r.field[i] and r.field passed as a var array arg). }
          isArr := True;
          fTk := IntToTypeKind(ArrTypeElemTk[fAi]);
          fRec := ArrTypeElemRec[fAi];
          if ArrTypeNDims[fAi] >= 2 then
          begin
            fNDims := ArrTypeNDims[fAi];
            arrLen := 1;
            for tdi := 0 to fNDims - 1 do
            begin
              tdDimLo[tdi]   := ArrTypeDimLo[fAi * MAX_ARR_DIMS + tdi];
              tdDimSpan[tdi] := ArrTypeDimSpan[fAi * MAX_ARR_DIMS + tdi];
              arrLen := arrLen * tdDimSpan[tdi];
            end;
          end
          else
          begin
            fNDims := 1;
            tdDimLo[0]   := ArrTypeLo[fAi];
            tdDimSpan[0] := ArrTypeHi[fAi] - ArrTypeLo[fAi] + 1;
            arrLen := tdDimSpan[0];
          end;
          Next;   { consume the named array type }
        end
        else
        begin
          fTk := ParseTypeKind;
          fRec := LastTypeRecId;
        end;
      end;
      if fIsDyn then
      begin
        fSize := TARGET_PTR_SIZE;
        fAlign := TARGET_PTR_SIZE;
      end
      else if fTk = tyString then
      begin
        fSize := LOCAL_STR_CAP + 8;
        fAlign := TARGET_PTR_SIZE;
      end
      else if fTk = tyRecord then
      begin
        fSize := RecSize(fRec);
        if fRec >= REC_UCLASS_BASE then
          fAlign := UClsAlign[fRec - REC_UCLASS_BASE]
        else
          fAlign := TARGET_PTR_SIZE;
      end
      else
      begin
        fSize := TypeSize(fTk);
        fAlign := TypeAlign(fTk);
      end;
      if isPackedRecord then
        fAlign := 1
      else if fAlign > TokPackRecords[TokPos - 1] then
        fAlign := TokPackRecords[TokPos - 1];
      if isArr then
        fSize := fSize * arrLen;
      { A by-value field of the record's OWN type (direct or transitive) is
        infinitely recursive — FPC rejects it (terecs9); pxx used to lay out a
        zero-sized field silently. Dynarray fields (heap indirection) are fine
        and skipped by the walk. }
      if (fTk = tyRecord) and (not fIsDyn) and (fRec <> REC_NONE) and
         RecContainsRecId(fRec, REC_UCLASS_BASE + ci) then
        Error('record field cannot be of the enclosing record type');
      for fni := 0 to nFldNames - 1 do
      begin
        curFieldOff := AlignTo(curFieldOff, fAlign);
        AddUField(ci, fldNOffs[fni], fldNLens[fni], curFieldOff, Ord(fTk), fRec);
        UFldIsArray[UFldCount-1] := isArr or fIsDyn;
        if fIsDyn then UFldArrLen[UFldCount-1] := -1
        else UFldArrLen[UFldCount-1] := arrLen;
        UFldDynDepth[UFldCount-1] := fDynDepth;
        if fNDims >= 2 then
        begin
          UFldArrNDims[UFldCount-1] := fNDims;
          for tdi := 0 to fNDims - 1 do
          begin
            UFldArrDimLo[(UFldCount-1) * MAX_ARR_DIMS + tdi]   := tdDimLo[tdi];
            UFldArrDimSpan[(UFldCount-1) * MAX_ARR_DIMS + tdi] := tdDimSpan[tdi];
          end;
        end;
        curFieldOff := curFieldOff + fSize;
      end;
      if fAlign > classAlign then classAlign := fAlign;
      Eat(tkSemicolon);
    end
    else if CurTok.Kind = tkCase then
      { Variant part — see ParseRecordVariantPart. (Previously `case` fell to
        the skip-`else` below, so branch fields were laid out sequentially
        and r.i:=x; r.c read 0.) }
      curFieldOff := ParseRecordVariantPart(ci, isPackedRecord, curFieldOff,
        classAlign)
    else
      Next;
  end;
  UClsSize_[ci] := AlignTo(curFieldOff, classAlign);
  UClsAlign[ci] := classAlign;
  Expect(tkEnd, 'end');
end;

procedure ParseTypeSection;
{ Handles enum types, record/class type declarations }
var
  ordinal: Int64;
  tname: AnsiString;
  done, stopTypes: Boolean; loVal, hiVal, arrLen: Integer; isArr: Boolean; isPackedRecord: Boolean;
  fIsDyn: Boolean; fDynDepth: Integer; fAi: Integer; tMoreDims: Boolean;
  tnOff, tnLen, ci, fnOff, fnLen, curFieldOff, fRec, fSize, fAlign, classAlign, depth, targetNOff, targetNLen: Integer;
  variantBaseOff, variantMax, branchFieldOff: Integer;
  enumNOff, enumNLen: Integer; enumNm: AnsiString;
  fTk: TTypeKind;
  parentCi, slot, mmi, mnOff, mnLen, pnOff, pnLen, rFOff, rFLen, rMOff, rMLen, wFOff, wFLen, wMOff, wMLen, rnOff, rnLen, wnOff, wnLen, propRec, i, vmtSlots: Integer;
  implIntf: array[0..15] of Integer; implCnt, tmpCi, ii, imSlot, imProc: Integer;
  parentIntfCi, ancCur, ij, implOrig: Integer; alreadyImpl: Boolean;
  imName: AnsiString;
  isConstructor, isDestructor, isVirtual, isOverride, isAbstract, isClassMethod: Boolean;
  hadParens: Boolean;
  mname, propName, readName, writeName: AnsiString;
  propTk: TTypeKind;
  mIsFunc, mDoneArgs, mDoneParam, mIsArr, mIsByRef, mSawConst, mIsUntyped: Boolean;
  mRetType, mTk: TTypeKind;
  mNParams, mStartIdx, mTokKindOrd, mpi, mSelfIdx, mFullNameOff, mFullNameLen: Integer;
  curPublished: Integer;  { 1 while inside a published section of the current class body }
  etid, propEnumId, propSetEnumId: Integer;
  propIsIndexed, propIsDefault: Boolean;   { indexed (array) property + `default;` }
  mFullName: AnsiString;
  aLo, aHi: Integer; aElemTk: TTypeKind;
  tdCnt, tdLo, tdHi, tdi, tflatLen, fNDims: Integer;
  tdDimLo, tdDimSpan: array[0..MAX_ARR_DIMS-1] of Integer;
  mPNames: array[0..MAX_PROC_PARAMS-1] of AnsiString;
  mPTypes: array[0..MAX_PROC_PARAMS-1] of TTypeKind;
  mPTypesRec: array[0..MAX_PROC_PARAMS-1] of Integer;
  mPArr: array[0..MAX_PROC_PARAMS-1] of Boolean;
  fldNOffs: array[0..MAX_PROC_PARAMS-1] of Integer;   { comma-separated field-name spans }
  fldNLens: array[0..MAX_PROC_PARAMS-1] of Integer;
  nFldNames, fni: Integer;
  mPByRef: array[0..MAX_PROC_PARAMS-1] of Boolean;
  mPUntyped: array[0..MAX_PROC_PARAMS-1] of Boolean;
  mPDefault: array[0..MAX_PROC_PARAMS-1] of Boolean;
  mPDefaultVal: array[0..MAX_PROC_PARAMS-1] of Int64;
  mHasDefault: Boolean;
  mDefaultVal: Int64;
begin
  Next;
  stopTypes := False;
  { A plain entry must look like `Name = ...` — an ident NOT followed by `=`
    (e.g. `protected` resuming members after a NESTED class-body type section)
    ends the section instead of desyncing on Expect('='). generic/operator
    keep their keyword forms. }
  while (CurTok.Kind = tkIdent) and (not CaseEqual(CurTok.SVal, 'constructor')) and (not CaseEqual(CurTok.SVal, 'destructor')) and (not CaseEqual(CurTok.SVal, 'implementation')) and (not CaseEqual(CurTok.SVal, 'initialization')) and (not CaseEqual(CurTok.SVal, 'finalization')) and not stopTypes and
        (CaseEqual(CurTok.SVal, 'generic') or CaseEqual(CurTok.SVal, 'specialize') or CaseEqual(CurTok.SVal, 'operator') or
         ((TokPos < TokCount) and (Tokens[TokPos].Kind = tkEq)) or
         ((not CaseEqual(CurTok.SVal, 'operator')) and
          (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLt))) do
  begin
    { `TFoo<T> = class` — Delphi-style generic template. Accepted in every
      mode (not just {$mode delphi}): at type-declaration position the
      `ident <` shape is unambiguous — except `operator < (...)` overload
      definitions, which the operator branch below owns. }
    if (not CaseEqual(CurTok.SVal, 'operator')) and
       (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLt) then
    begin
      { mode-Delphi generic template `TFoo<T> = class ... end;` — the name
        comes first; ParseGenericTemplateNamed captures the template and
        desugars all later Delphi-surface uses (see DelphiRewriteGenericUses). }
      ParseGenericTemplateNamed(CurTok.SVal, True);
    end
    else if CaseEqual(CurTok.SVal, 'generic') then
    begin
      ParseGenericTemplate;
    end
    else if CaseEqual(CurTok.SVal, 'operator') then
      stopTypes := True  { top-level operator def follows type section }
    else
    begin
      tnOff := Tokens[TokPos-1].SOffset;
      tnLen := Tokens[TokPos-1].SLen;
      tname := CurTok.SVal; Next;
      Expect(tkEq, '=');
      { A generic class specialization streams the concrete class body in place
        and leaves CurTok on 'class', falling through to the class-binding
        branch below — the concrete name comes from the saved tnOff/tnLen. }
      if CaseEqual(CurTok.SVal, 'specialize') then
        ParseSpecialization(tname);
      if CurTok.Kind = tkLParen then
      begin
        etid := RegisterEnumType(tnOff, tnLen);
        { {$SCOPEDENUMS ON} at this token: members only under TEnum.member }
        EnumTypeScoped[etid] := TokScopedEnums[TokPos-1];
        Next; ordinal := 0;
        done := False;
        while (CurTok.Kind = tkIdent) and not done do
        begin
          { Optional explicit ordinal: `(a = 1, b = 5, c)` — a value sets the
            member's ordinal; the next valueless member continues from value+1
            (FPC semantics). }
          enumNOff := Tokens[TokPos-1].SOffset; enumNLen := Tokens[TokPos-1].SLen;
          enumNm := CurTok.SVal;
          Next;
          if CurTok.Kind = tkEq then
          begin
            Next;                 { consume '=' }
            hiVal := ordinal;     { the implicit next ordinal }
            ordinal := ConstEval; { explicit ordinal value }
            { A jump off the implicit 0..n-1 sequence makes the enum
              non-contiguous — for-in over the TYPE is then invalid (FPC,
              tforin20) and ordinal<->position no longer coincide. }
            if ordinal <> hiVal then EnumTypeHasHoles[etid] := True;
          end;
          AddEnumVal(enumNOff, enumNLen, ordinal);
          if not EnumTypeScoped[etid] then
            AddConst(enumNm, tyInteger, ordinal);
          Inc(ordinal);
          if not Eat(tkComma) then done := True;
        end;
        Expect(tkRParen, ')');
        EnumTypeValCount[etid] := EnumValCount - EnumTypeValBase[etid];
      end
      else if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'interface') then
      begin
        { `IFoo = interface [guid] <method signatures> end;` — CORBA-style.
          The interface is a UCls entry with no fields; its methods are slot
          signatures (declaration order = IMT slot). A var of it is a 16-byte
          fat pointer {IMT, instance}. }
        Next;
        { optional parent interface: `IBar = interface(IFoo)`. IFoo's method
          signatures are inherited at the leading IMT slots, so a value of IBar
          dispatches its inherited methods and a class implementing IBar also
          satisfies IFoo (the ancestor IMTs are built at the class below). }
        parentIntfCi := -1;
        if CurTok.Kind = tkLParen then
        begin
          Next;
          if CurTok.Kind <> tkIdent then Error('expected parent interface name');
          parentIntfCi := FindUClass(CurTok.SVal);
          if (parentIntfCi < 0) or not UClsIsInterface[parentIntfCi] then
            Error('the parent of an interface must be an interface');
          Next;
          Expect(tkRParen, ')');
        end;
        { COM/ARC interface ({$interfaces com}): with no explicit parent, derive
          implicitly from IInterface so the three reserved slots QueryInterface /
          _AddRef / _Release occupy IMT slots 0..2 (ARC dispatches _Release via
          slot 2). IInterface's own declaration finds no prior IInterface, so it
          does not self-parent and supplies the three slots itself. }
        if InterfacesComMode and (parentIntfCi < 0) then
        begin
          parentIntfCi := FindUClass('IInterface');
          if parentIntfCi < 0 then parentIntfCi := FindUClass('IUnknown');
          if (parentIntfCi >= 0) and not UClsIsInterface[parentIntfCi] then
            parentIntfCi := -1;
        end;
        ci := AddUClass(tnOff, tnLen);
        UClsIsInterface[ci] := True;
        UClsIsComInterface[ci] := InterfacesComMode;
        if InterfacesComMode then ComInterfaceUsed := True;
        UClsSize_[ci] := 2 * TARGET_PTR_SIZE;   { fat pointer {IMT, instance} }
        UClsAlign[ci] := TARGET_PTR_SIZE;
        UClsParent[ci] := parentIntfCi;
        { Inherit the parent interface's methods first (contiguously, before this
          interface's own), so IMT slot order is [parent methods..., own...]. }
        if parentIntfCi >= 0 then
          for i := 0 to UClsMCount[parentIntfCi] - 1 do
          begin
            AddUMeth(ci, UMthNOff[UClsMBase[parentIntfCi] + i],
                     UMthNLen[UClsMBase[parentIntfCi] + i],
                     UMthProc_[UClsMBase[parentIntfCi] + i]);
            UMthVirSlot[UMthCount - 1] := UClsMCount[ci] - 1;
            UMthIsStatic[UMthCount - 1] := False;
          end;
        { optional GUID literal ['{...}'] — parsed and ignored (v1) }
        if CurTok.Kind = tkLBrack then
        begin
          while (CurTok.Kind <> tkRBrack) and (CurTok.Kind <> tkEOF) do Next;
          Expect(tkRBrack, ']');
        end;
        while (CurTok.Kind = tkProcedure) or (CurTok.Kind = tkFunction) do
        begin
          mIsFunc := CurTok.Kind = tkFunction;
          Next;
          if CurTok.Kind <> tkIdent then Error('expected interface method name');
          mname := CurTok.SVal;
          mnOff := Tokens[TokPos-1].SOffset; mnLen := Tokens[TokPos-1].SLen;
          Next;
          mNParams := 0; mRetType := tyInteger;
          if CurTok.Kind = tkLParen then
          begin
            Next; mDoneArgs := False;
            while (CurTok.Kind <> tkRParen) and not mDoneArgs do
            begin
              mIsByRef := False;
              mSawConst := False;
              if (CurTok.Kind = tkVar) or ((CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'out')) then
              begin mIsByRef := True; Next; end
              else if CurTok.Kind = tkConst then begin mSawConst := True; Next; end;
              mStartIdx := mNParams; mDoneParam := False;
              while IsDeclNameTok and not mDoneParam do
              begin
                mPNames[mNParams] := CurTok.SVal; Inc(mNParams); Next;
                if not Eat(tkComma) then mDoneParam := True;
                if CurTok.Kind = tkColon then mDoneParam := True;
              end;
              Expect(tkColon, ':');
              mIsArr := False;
              if CurTok.Kind = tkArray then begin Next; Expect(tkOf, 'of'); mTk := ParseTypeKind; mIsArr := True; end
              else mTk := ParseTypeKind;
              { Default value: `n: Integer = 5` — mirror ParseSubroutine. }
              mHasDefault := False; mDefaultVal := 0;
              if CurTok.Kind = tkEq then
              begin Next; mDefaultVal := ConstEval; mHasDefault := True; end;
              { `const` record/variant param = by-ref, matching ParseSubroutine
                (sibling of the class-method fix; interface methods dispatch
                indirectly, so the mismatch would corrupt the arg silently).
                See bug-method-call-before-body-byvalue-small-record-arg. }
              if mSawConst and ((mTk = tyRecord) or (mTk = tyVariant)) and not mIsArr then
                mIsByRef := True;
              for i := mStartIdx to mNParams-1 do
              begin mPTypes[i] := mTk; mPTypesRec[i] := LastTypeRecId; mPArr[i] := mIsArr; mPByRef[i] := mIsByRef; mPDefault[i] := mHasDefault; mPDefaultVal[i] := mDefaultVal; end;
              if not Eat(tkSemicolon) then mDoneArgs := True;
            end;
            Expect(tkRParen, ')');
          end;
          if mIsFunc then begin Expect(tkColon, ':'); mRetType := ParseTypeKind; end;
          Eat(tkSemicolon);
          { inject implicit Self (the instance) at param 0, like a class method }
          for i := mNParams downto 1 do
          begin mPNames[i] := mPNames[i-1]; mPTypes[i] := mPTypes[i-1]; mPArr[i] := mPArr[i-1]; mPByRef[i] := mPByRef[i-1]; mPDefault[i] := mPDefault[i-1]; mPDefaultVal[i] := mPDefaultVal[i-1]; end;
          mPNames[0] := 'Self'; mPTypes[0] := tyClass; mPArr[0] := False; mPByRef[0] := False; mPDefault[0] := False; mPDefaultVal[0] := 0;
          mNParams := mNParams + 1;
          mFullName := tname; AppendChar(mFullName, '.');
          for i := 1 to Length(mname) do AppendChar(mFullName, mname[i]);
          mpi := RegisterProc(mFullName, mIsFunc, mRetType, mNParams, mPNames, mPTypes);
          Procs[mpi].BodyAddr := -1;
          for i := 0 to mNParams-1 do
          begin
            Procs[mpi].Params[i].IsArray := mPArr[i]; Procs[mpi].Params[i].IsRef := mPByRef[i];
            if (i < MAX_PROC_PARAMS) and mPDefault[i] then
            begin
              ProcParamHasDefault[mpi * MAX_PROC_PARAMS + i] := True;
              ProcParamDefaultVal[mpi * MAX_PROC_PARAMS + i] := mPDefaultVal[i];
            end;
          end;
          AddUMeth(ci, mnOff, mnLen, mpi);
          { slot = method position within this interface (IMT index) }
          UMthVirSlot[UMthCount-1] := UClsMCount[ci] - 1;
          UMthIsStatic[UMthCount-1] := False;
        end;
        Expect(tkEnd, 'end');
        Eat(tkSemicolon);
      end
      else if (CurTok.Kind = tkClass) and (Tokens[TokPos].Kind = tkOf) then
      begin
        { Named metaclass alias: TFooClass = class of TFoo. Values use the
          existing RTTI-pointer class-reference representation. }
        Next;
        Expect(tkOf, 'of');
        if CurTok.Kind <> tkIdent then Error('expected base class after class of');
        ci := FindUClass(CurTok.SVal);
        if ci < 0 then Error('class of base type not found: ' + CurTok.SVal);
        RegisterClassRefAlias(tnOff, tnLen, REC_UCLASS_BASE + ci);
        Next;
        Eat(tkSemicolon);
      end
      else if CurTok.Kind = tkClass then
      begin
        Next;
        parentCi := -1;
        implCnt := 0;
        hadParens := CurTok.Kind = tkLParen;
        if Eat(tkLParen) then
        begin
          { (ParentClass) and/or (Iface1, Iface2, ...): an interface name in the
            list is an implemented interface; a class name is the parent. }
          repeat
            if CurTok.Kind <> tkIdent then Error('expected base class or interface name');
            tmpCi := FindUClass(CurTok.SVal);
            if (tmpCi < 0) and
               (CaseEqual(CurTok.SVal, 'TObject') or CaseEqual(CurTok.SVal, 'TInterfacedObject')) then
            begin
              { Explicit root base `class(TObject)` / `class(TInterfacedObject, IFoo)`
                == the implicit root: leave parentCi = -1, same as a plain `class`.
                These names are not registered as user classes (the root is
                implicit), so accept them by name rather than erroring. }
            end
            else
            begin
              if tmpCi < 0 then Error('base type not found: ' + CurTok.SVal);
              if UClsIsInterface[tmpCi] then
              begin
                if implCnt > 15 then Error('too many implemented interfaces (v1: max 16)');
                implIntf[implCnt] := tmpCi; Inc(implCnt);
              end
              else
              begin
                if parentCi >= 0 then Error('a class may have only one parent class');
                parentCi := tmpCi;
              end;
            end;
            Next;
          until not Eat(tkComma);
          Expect(tkRParen, ')');
        end;

        { A class implementing a derived interface also implements every ancestor
          interface — add the ancestors so an IMT is built for each, making
          `is`/`as`/`Supports` and class->base-interface assignment work. }
        implOrig := implCnt;
        for ii := 0 to implOrig - 1 do
        begin
          ancCur := UClsParent[implIntf[ii]];
          while ancCur >= 0 do
          begin
            alreadyImpl := False;
            for ij := 0 to implCnt - 1 do
              if implIntf[ij] = ancCur then alreadyImpl := True;
            if not alreadyImpl then
            begin
              if implCnt > 15 then Error('too many implemented interfaces (v1: max 16)');
              implIntf[implCnt] := ancCur; Inc(implCnt);
            end;
            ancCur := UClsParent[ancCur];
          end;
        end;

        { A forward stub `TFoo = class;` already minted an entry that `class of`
          aliases and field types point at — the full decl must fill THAT entry.
          Registering a second one shadows it (FindUClass returns the first
          match), so the base + fields land on an entry no reference sees. }
        ci := FindUClass(tname);
        if (ci >= 0) and UClsForward[ci] then
        begin
          { counts are 0 on a stub; re-anchor the member windows to the current
            tails (other classes may have registered members in between). }
          UClsFBase[ci] := UFldCount;
          UClsMBase[ci] := UMthCount;
          UClsPBase[ci] := UPropCount;
          UClsVirtCount[ci] := 0;
          UClsForward[ci] := False;
        end
        else
          ci := AddUClass(tnOff, tnLen);
        UClsParent[ci] := parentCi;
        { bare `class;` with no heritage = a forward declaration (FPC).
          `class(TBase);` stays the empty-body shorthand. }
        UClsForward[ci] := (not hadParens) and (CurTok.Kind = tkSemicolon);

        curFieldOff := 0;
        classAlign := 1;
        if parentCi >= 0 then
        begin
          curFieldOff := UClsSize_[parentCi];
          UClsVirtCount[ci] := UClsVirtCount[parentCi];
        end
        else
        begin
          curFieldOff := 8; { reserve offset 0 for VMT pointer }
        end;

        { Implicit first section defaults to published, as Delphi/Lazarus do for
          $M+ (TPersistent-descended) classes — so a stock TForm's fields and
          event handlers are streamable/reflectable without an explicit
          `published`. We don't track $M+, so this applies to every class; the
          only effect is extra RTTI, which is harmless. }
        curPublished := 1;
        { FPC shorthand: `TFoo = class(TBase);` — semicolon closes the type
          declaration immediately with an empty body; no `end` needed. }
        if CurTok.Kind <> tkSemicolon then
        begin
        while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
        begin
          { Visibility section markers. Not reserved words, so treat as section
            switch only when immediately at member-start position. Access is not
            enforced (project policy); we only record the published flag for RTTI. }
          if (CurTok.Kind = tkIdent) and
             (CaseEqual(CurTok.SVal, 'private') or CaseEqual(CurTok.SVal, 'protected') or
              CaseEqual(CurTok.SVal, 'public') or CaseEqual(CurTok.SVal, 'published')) then
          begin
            if CaseEqual(CurTok.SVal, 'published') then curPublished := 1
            else curPublished := 0;
            Next;
            continue;
          end;

          { Nested `type` section inside a class body (fgl's private types:
            TCompareFunc = function(...), PT = ^T, ...). Parsed as GLOBAL type
            aliases — pxx does not scope class-local types (access control is
            unenforced project-wide). ParseTypeSection now stops at the first
            ident not followed by `=`, i.e. the next member/visibility word.
            NOTE: two specializations of one generic re-register the same
            names; first registration wins on lookup. }
          if CurTok.Kind = tkType then
          begin
            Inc(TypeSectionDepth);
            ParseTypeSection;
            Dec(TypeSectionDepth);
            continue;
          end;

          { class var x[, y]: T; — one shared GLOBAL slot per class (not per
            instance), addressed as TClass.x or obj.x. Registered in the ClassVar
            table; storage is an anonymous global var (CurProc < 0 here). }
          if (CurTok.Kind = tkClass) and (Tokens[TokPos].Kind = tkVar) then
          begin
            Next; Next;   { consume 'class' 'var' }
            while CurTok.Kind = tkIdent do
            begin
              nFldNames := 0;
              repeat
                if CurTok.Kind <> tkIdent then Error('expected class var name');
                fldNOffs[nFldNames] := Tokens[TokPos-1].SOffset;
                fldNLens[nFldNames] := Tokens[TokPos-1].SLen;
                Inc(nFldNames); Next;
              until not Eat(tkComma);
              Expect(tkColon, ':');
              fTk := ParseTypeKind; fRec := LastTypeRecId;
              for fni := 0 to nFldNames - 1 do
              begin
                if ClassVarCount >= MAX_TYPEALIAS then Error('too many class variables');
                i := AllocVar('', fTk);
                if (fTk = tyRecord) or (fTk = tyClass) then Syms[i].RecName := fRec;
                ClassVarCi[ClassVarCount]   := ci;
                ClassVarNOff[ClassVarCount] := fldNOffs[fni];
                ClassVarNLen[ClassVarCount] := fldNLens[fni];
                ClassVarSym[ClassVarCount]  := i;
                Inc(ClassVarCount);
              end;
              Eat(tkSemicolon);
            end;
            continue;
          end;

          isClassMethod := False;
          if (CurTok.Kind = tkClass) and ((Tokens[TokPos].Kind = tkProcedure) or (Tokens[TokPos].Kind = tkFunction)) then
          begin
            isClassMethod := True;
            Next; { consume 'class' }
          end;

          if (CurTok.Kind = tkProcedure) or (CurTok.Kind = tkFunction) or
             ((CurTok.Kind = tkIdent) and (CaseEqual(CurTok.SVal, 'constructor') or CaseEqual(CurTok.SVal, 'destructor'))) then
          begin
            mIsFunc := CurTok.Kind = tkFunction;
            isConstructor := False;
            isDestructor := False;
            if CurTok.Kind = tkIdent then
            begin
              isConstructor := CaseEqual(CurTok.SVal, 'constructor');
              isDestructor := CaseEqual(CurTok.SVal, 'destructor');
              Next;
            end
            else
              Next;

            if not IsMemberNameTok then Error('expected method name');
            mname := CurTok.SVal;
            mnOff := Tokens[TokPos-1].SOffset;
            mnLen := Tokens[TokPos-1].SLen;
            Next;

            mNParams := 0;
            mRetType := tyInteger;
            if CurTok.Kind = tkLParen then
            begin
              Next;
              mDoneArgs := False;
              while (CurTok.Kind <> tkRParen) and not mDoneArgs do
              begin
                mIsByRef := False;
                mSawConst := False;
                if (CurTok.Kind = tkVar) or
                   ((CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'out')) then
                begin
                  mIsByRef := True;
                  Next;
                end
                else if CurTok.Kind = tkConst then
                begin mSawConst := True; Next; end;
                mStartIdx := mNParams;
                mDoneParam := False;
                while IsDeclNameTok and not mDoneParam do
                begin
                  mPNames[mNParams] := CurTok.SVal; Inc(mNParams); Next;
                  if not Eat(tkComma) then mDoneParam := True;
                  if CurTok.Kind = tkColon then mDoneParam := True;
                end;
                mIsArr := False;
                mIsUntyped := False;
                mHasDefault := False;
                mDefaultVal := 0;
                if CurTok.Kind <> tkColon then
                begin
                  { Untyped method param (`var B` / `const B`, no type) — mirror the
                    standalone-routine path: by-ref, any arg type, address passed. }
                  if not (mIsByRef or mSawConst) then
                    Error('untyped parameter requires var, const, or out');
                  mIsUntyped := True; mIsByRef := True; mTk := tyPointer;
                  LastTypeRecId := REC_NONE;
                end
                else
                begin
                  Expect(tkColon, ':');
                  if CurTok.Kind = tkArray then
                  begin
                    Next;
                    Expect(tkOf, 'of');
                    if CurTok.Kind = tkConst then
                    begin
                      { `array of const` method param (Exception.CreateFmt):
                        TVarRec open array, same as the free-routine case. }
                      if TVarRecId = REC_NONE then
                        Error('array of const requires the builtinheap unit (use an array/heap feature)');
                      Next;
                      mTk := tyRecord;
                      LastTypeRecId := TVarRecId;
                    end
                    else
                      mTk := ParseTypeKind;
                    mIsArr := True;
                  end
                  else
                    mTk := ParseTypeKind;
                  { Default value: `n: Integer = 5` — mirror ParseSubroutine
                    (~13915). Constant-folded; a call omitting the trailing arg
                    supplies it (ctor fill at ~5609, general fill in ir.inc). }
                  if CurTok.Kind = tkEq then
                  begin
                    Next;
                    mDefaultVal := ConstEval;
                    mHasDefault := True;
                  end;
                end;
                { A `const` record/variant param is passed by reference — must
                  match ParseSubroutine's rule, or a call lowered BEFORE the
                  implementation body uses the by-value convention while the
                  compiled body expects an address (silently truncating on
                  x86-64 only when RecSize<=8; a hard backend error on i386).
                  See bug-method-call-before-body-byvalue-small-record-arg. }
                if mSawConst and ((mTk = tyRecord) or (mTk = tyVariant)) and not mIsArr then
                  mIsByRef := True;
                for i := mStartIdx to mNParams-1 do
                begin
                  mPTypes[i] := mTk;
                  mPTypesRec[i] := LastTypeRecId;
                  mPArr[i] := mIsArr;
                  mPByRef[i] := mIsByRef;
                  mPUntyped[i] := mIsUntyped;
                  mPDefault[i] := mHasDefault;
                  mPDefaultVal[i] := mDefaultVal;
                end;
                if not Eat(tkSemicolon) then mDoneArgs := True;
              end;
              Expect(tkRParen, ')');
            end;

            if mIsFunc then
            begin
              Expect(tkColon, ':');
              mRetType := ParseTypeKind;
            end;
            Eat(tkSemicolon);

            if not isClassMethod then
            begin
              for i := mNParams downto 1 do
              begin
                mPNames[i] := mPNames[i-1];
                mPTypes[i] := mPTypes[i-1];
                mPArr[i]   := mPArr[i-1];
                mPByRef[i] := mPByRef[i-1];
                mPUntyped[i] := mPUntyped[i-1];
                mPDefault[i] := mPDefault[i-1];
                mPDefaultVal[i] := mPDefaultVal[i-1];
              end;
              mPNames[0] := 'Self';
              mPTypes[0] := tyClass;
              mPArr[0]   := False;
              mPByRef[0] := False;
              mPUntyped[0] := False;
              mPDefault[0] := False;
              mPDefaultVal[0] := 0;
              mNParams := mNParams + 1;
            end;

            mFullName := tname;
            AppendChar(mFullName, '.');
            for i := 1 to Length(mname) do AppendChar(mFullName, mname[i]);

            mpi := FindProcOverload(mFullName, mNParams, mPTypes, mPArr, mPByRef);
            if mpi < 0 then
            begin
              mpi := RegisterProc(mFullName, mIsFunc, mRetType, mNParams, mPNames, mPTypes);
              Procs[mpi].BodyAddr := -1;
              for i := 0 to mNParams-1 do
              begin
                if (i < MAX_PROC_PARAMS) then ProcParamUntyped[mpi * MAX_PROC_PARAMS + i] := mPUntyped[i];
                if (i < MAX_PROC_PARAMS) and mPDefault[i] then
                begin
                  ProcParamHasDefault[mpi * MAX_PROC_PARAMS + i] := True;
                  ProcParamDefaultVal[mpi * MAX_PROC_PARAMS + i] := mPDefaultVal[i];
                end;
                Procs[mpi].Params[i].IsArray := mPArr[i];
                Procs[mpi].Params[i].IsRef := mPByRef[i];
                if (mPTypes[i] = tyClass) or (mPTypes[i] = tyRecord) then
                  Procs[mpi].Params[i].SymIdx := -1;
              end;
            end;

            isVirtual := False;
            isOverride := False;
            isAbstract := False;
            while (CurTok.Kind = tkIdent) and
                  (CaseEqual(CurTok.SVal, 'virtual') or
                   CaseEqual(CurTok.SVal, 'override') or
                   CaseEqual(CurTok.SVal, 'abstract') or
                   CaseEqual(CurTok.SVal, 'dynamic') or
                   CaseEqual(CurTok.SVal, 'inline') or
                   CaseEqual(CurTok.SVal, 'overload') or
                   CaseEqual(CurTok.SVal, 'static') or
                   CaseEqual(CurTok.SVal, 'reintroduce') or
                   CaseEqual(CurTok.SVal, 'deprecated') or
                   CaseEqual(CurTok.SVal, 'platform') or
                   CaseEqual(CurTok.SVal, 'experimental')) do
            begin
              { virtual/override/abstract drive dispatch; dynamic = virtual
                (FPC: same semantics, different table — pxx has one VMT).
                inline/overload/static/reintroduce + hint directives are
                parse-and-ignore: overload resolution is signature-keyed
                anyway, `class` already makes a method static, and
                reintroduce only silences an FPC hint. `deprecated` may
                carry a message string literal. }
              if CaseEqual(CurTok.SVal, 'virtual') or CaseEqual(CurTok.SVal, 'dynamic') then isVirtual := True;
              if CaseEqual(CurTok.SVal, 'override') then isOverride := True;
              if CaseEqual(CurTok.SVal, 'abstract') then
              begin
                isVirtual := True;   { abstract implies virtual }
                isAbstract := True;
              end;
              if CaseEqual(CurTok.SVal, 'deprecated') and (TokPos < TokCount) and
                 (Tokens[TokPos].Kind = tkString) then
                Next; { skip the message literal (consumed by the Next below) }
              Next;
              Eat(tkSemicolon);
            end;

            AddUMeth(ci, mnOff, mnLen, mpi);
            mmi := UMthCount - 1;
            UMthIsStatic[mmi] := isClassMethod;
            UMthIsCtor[mmi] := isConstructor;
            UMthPub[mmi] := curPublished;

            if isVirtual then
            begin
              slot := UClsVirtCount[ci];
              UClsVirtCount[ci] := UClsVirtCount[ci] + 1;
              UMthVirSlot[mmi] := slot;
            end
            else if isOverride then
            begin
              slot := FindParentVirtualSlot(parentCi, mname);
              if (slot < 0) and (CaseEqual(mname, 'Destroy') or CaseEqual(mname, 'Create')) then
              begin
                { FPC's TObject.Destroy (and TComponent-style virtual Create) are
                  virtual, but pxx's implicit root carries no method table, so
                  `override` finds no parent slot. Materialise the root virtual on
                  first override: allocate a fresh slot exactly as `virtual` would,
                  so `destructor Destroy; override;` compiles and dispatches
                  (Free's desugar already calls Destroy virtually). A descendant's
                  own `Destroy; override;` then finds THIS slot via
                  FindParentVirtualSlot and chains correctly. inherited Destroy /
                  Create at the root boundary is a no-op (ParseInheritedCallAST).
                  See bug-tobject-destroy-not-virtual-override. }
                slot := UClsVirtCount[ci];
                UClsVirtCount[ci] := UClsVirtCount[ci] + 1;
                UMthVirSlot[mmi] := slot;
              end
              else
              begin
                if slot < 0 then Error('cannot override: no virtual method found in parent chain: ' + mname);
                UMthVirSlot[mmi] := slot;
              end;
            end;
          end
          else if CurTok.Kind = tkProperty then
          begin
            Next;
            if not IsMemberNameTok then Error('expected property name');
            propName := GetTokenStr(TokPos - 1);   { keyword-token names (ParamCount) carry no SVal }
            pnOff := Tokens[TokPos-1].SOffset;
            pnLen := Tokens[TokPos-1].SLen;
            Next;
            { Indexed (array) property: `property Items[i: TIdx]: T ...`. The index
              parameter's name/type are defined by the accessor signature, so the
              declaration clause is parsed and discarded; we only mark the property
              indexed so accesses pass the subscript as an extra accessor arg. }
            propIsIndexed := False;
            propIsDefault := False;
            if CurTok.Kind = tkLBrack then
            begin
              propIsIndexed := True;
              Next;
              while (CurTok.Kind <> tkRBrack) and (CurTok.Kind <> tkEOF) do Next;
              Expect(tkRBrack, ']');
            end;
            Expect(tkColon, ':');
            LastTypeSetEnumId := -1;
            propTk := ParseTypeKind;
            propRec := LastTypeRecId;
            propEnumId := LastTypeEnumId;
            propSetEnumId := LastTypeSetEnumId;

            rFOff := 0; rFLen := 0;
            rMOff := 0; rMLen := 0;
            wFOff := 0; wFLen := 0;
            wMOff := 0; wMLen := 0;

            if CurTok.Kind = tkRead then
            begin
              Next;
              if CurTok.Kind <> tkIdent then Error('expected read field or method name');
              readName := CurTok.SVal;
              rnOff := Tokens[TokPos-1].SOffset;
              rnLen := Tokens[TokPos-1].SLen;
              Next;
              if FindUField(ci, readName) >= 0 then
              begin
                rFOff := rnOff; rFLen := rnLen;
              end
              else
              begin
                rMOff := rnOff; rMLen := rnLen;
              end;
            end;

            if CurTok.Kind = tkwrite then
            begin
              Next;
              if CurTok.Kind <> tkIdent then Error('expected write field or method name');
              writeName := CurTok.SVal;
              wnOff := Tokens[TokPos-1].SOffset;
              wnLen := Tokens[TokPos-1].SLen;
              Next;
              if FindUField(ci, writeName) >= 0 then
              begin
                wFOff := wnOff; wFLen := wnLen;
              end
              else
              begin
                wMOff := wnOff; wMLen := wnLen;
              end;
            end;

            Eat(tkSemicolon);
            { Optional `default;` on an indexed property → obj[i] routes here. }
            if CurTok.Kind = tkDefault then
            begin
              propIsDefault := True;
              Next;
              Eat(tkSemicolon);
            end;
            i := AddUProperty(ci, pnOff, pnLen, Ord(propTk), propRec);
            UPropReadFOff[i] := rFOff; UPropReadFLen[i] := rFLen;
            UPropReadMOff[i] := rMOff; UPropReadMLen[i] := rMLen;
            UPropWriteFOff[i] := wFOff; UPropWriteFLen[i] := wFLen;
            UPropWriteMOff[i] := wMOff; UPropWriteMLen[i] := wMLen;
            UPropPub[i] := curPublished;
            UPropEnumId[i] := propEnumId;
            UPropSetEnumId[i] := propSetEnumId;
            UPropIsIndexed[i] := propIsIndexed;
            UPropIsDefault[i] := propIsDefault;
          end
          else if CurTok.Kind = tkIdent then
          begin
            { comma-separated names share one type: `A, B: Integer` }
            fldNOffs[0] := Tokens[TokPos-1].SOffset;
            fldNLens[0] := Tokens[TokPos-1].SLen;
            nFldNames := 1;
            Next;
            while CurTok.Kind = tkComma do
            begin
              Next;
              if CurTok.Kind <> tkIdent then Error('expected field name after ","');
              fldNOffs[nFldNames] := Tokens[TokPos-1].SOffset;
              fldNLens[nFldNames] := Tokens[TokPos-1].SLen;
              Inc(nFldNames);
              Next;
            end;
            Expect(tkColon, ':');
            isArr := False;
            arrLen := 1;
            fIsDyn := False;
            fDynDepth := 0;
            fNDims := 0;
            if CurTok.Kind = tkArray then
            begin
              Next;
              if CurTok.Kind = tkLBrack then
              begin
                Next;
                { Const-EXPRESSION bounds (`0..N - 1`), not just literals —
                  same ConstEval the named array-type path uses
                  (bug-inline-array-field-const-bound). }
                loVal := ConstEval;
                Expect(tkDotDot, '..');
                hiVal := ConstEval;
                arrLen := hiVal - loVal + 1;
                { N-D field: collect dim0 then any comma dims. }
                fNDims := 1; tdDimLo[0] := loVal; tdDimSpan[0] := hiVal - loVal + 1;
                while CurTok.Kind = tkComma do
                begin
                  Eat(tkComma);
                  tdLo := ConstEval;
                  Expect(tkDotDot, '..');
                  tdHi := ConstEval;
                  if fNDims >= MAX_ARR_DIMS then Error('too many array dimensions');
                  tdDimLo[fNDims] := tdLo; tdDimSpan[fNDims] := tdHi - tdLo + 1;
                  arrLen := arrLen * tdDimSpan[fNDims];
                  Inc(fNDims);
                end;
                Expect(tkRBrack, ']');
                Expect(tkOf, 'of');
                fTk := ParseTypeKind;
                fRec := LastTypeRecId;
                isArr := True;
              end
              else
              begin
                { Dynamic-array field: `array of T`, including nested. The slot is
                  a pointer-sized handle; fTk/fRec carry the base element type. }
                fIsDyn := True;
                fDynDepth := 1;
                Expect(tkOf, 'of');
                while CurTok.Kind = tkArray do
                begin
                  Next;
                  Inc(fDynDepth);
                  Expect(tkOf, 'of');
                end;
                fTk := ParseTypeKind;
                fRec := LastTypeRecId;
              end;
            end
            else
            begin
              { Named dynamic-array type field (`TDynArr = array of T`): mirror
                the inline `array of T` field so SetLength/Length/indexing see a
                real dynamic array. Without this the field's UFldDynDepth stayed
                0 and SetLength(Self.field, n) misrouted to the string path. }
              fAi := -1;
              if CurTok.Kind = tkIdent then fAi := FindArrayType(CurTok.SVal);
              if (fAi >= 0) and ArrTypeIsDyn[fAi] then
              begin
                fIsDyn := True;
                fDynDepth := ArrTypeDynDepth[fAi];
                fTk := IntToTypeKind(ArrTypeElemTk[fAi]);
                fRec := ArrTypeElemRec[fAi];
                Next;   { consume the named array type }
              end
              else if (fAi >= 0) and (not ArrTypeIsDyn[fAi]) then
              begin
                { Named FIXED-array type field (`a: TG`, `TG = array[..] of T`):
                  make it a real array field (1-D or flattened N-D) so a.x[i]
                  indexes with the right stride. Without this ParseTypeKind drops
                  TG's dimension and the field collapses to a single base element
                  (corrupting r.field[i] and r.field passed as a var array arg). }
                isArr := True;
                fTk := IntToTypeKind(ArrTypeElemTk[fAi]);
                fRec := ArrTypeElemRec[fAi];
                if ArrTypeNDims[fAi] >= 2 then
                begin
                  fNDims := ArrTypeNDims[fAi];
                  arrLen := 1;
                  for tdi := 0 to fNDims - 1 do
                  begin
                    tdDimLo[tdi]   := ArrTypeDimLo[fAi * MAX_ARR_DIMS + tdi];
                    tdDimSpan[tdi] := ArrTypeDimSpan[fAi * MAX_ARR_DIMS + tdi];
                    arrLen := arrLen * tdDimSpan[tdi];
                  end;
                end
                else
                begin
                  fNDims := 1;
                  tdDimLo[0]   := ArrTypeLo[fAi];
                  tdDimSpan[0] := ArrTypeHi[fAi] - ArrTypeLo[fAi] + 1;
                  arrLen := tdDimSpan[0];
                end;
                Next;   { consume the named array type }
              end
              else
              begin
                fTk := ParseTypeKind;
                fRec := LastTypeRecId;
              end;
            end;
            if fIsDyn then
            begin
              fSize := TARGET_PTR_SIZE;
              fAlign := TARGET_PTR_SIZE;
            end
            else if fTk = tyString then
            begin
              fSize := LOCAL_STR_CAP + 8;
              fAlign := TARGET_PTR_SIZE;
            end
            else if fTk = tyRecord then
            begin
              fSize := RecSize(fRec);
              fAlign := TARGET_PTR_SIZE;
            end
            else
            begin
              fSize := TypeSize(fTk);
              fAlign := TypeAlign(fTk);
            end;
            if isArr then
              fSize := fSize * arrLen;
            for fni := 0 to nFldNames - 1 do
            begin
              curFieldOff := AlignTo(curFieldOff, fAlign);
              AddUField(ci, fldNOffs[fni], fldNLens[fni], curFieldOff, Ord(fTk), fRec);
              UFldIsArray[UFldCount-1] := isArr or fIsDyn;
              if fIsDyn then UFldArrLen[UFldCount-1] := -1
              else UFldArrLen[UFldCount-1] := arrLen;
              UFldDynDepth[UFldCount-1] := fDynDepth;
              if fNDims >= 2 then
              begin
                UFldArrNDims[UFldCount-1] := fNDims;
                for tdi := 0 to fNDims - 1 do
                begin
                  UFldArrDimLo[(UFldCount-1) * MAX_ARR_DIMS + tdi]   := tdDimLo[tdi];
                  UFldArrDimSpan[(UFldCount-1) * MAX_ARR_DIMS + tdi] := tdDimSpan[tdi];
                end;
              end;
              UFldPub[UFldCount-1] := curPublished;
              curFieldOff := curFieldOff + fSize;
            end;
            if fAlign > classAlign then classAlign := fAlign;
            Eat(tkSemicolon);
          end
          else
            Next;
        end;
        Expect(tkEnd, 'end');
        end; { end of non-shorthand body block }
        UClsSize_[ci] := AlignTo(curFieldOff, classAlign);

        UClsVMTOffset[ci] := DataLen;
        { Always reserve at least one slot so every class has a DISTINCT VMT
          address — that address is the per-class runtime identity used by is/as
          and stored at [instance+0]. Without this, classes with no virtual
          methods get 0-byte VMTs that all alias the same offset, so `obj is
          AnyClass` would match every class. The padding slot is never dispatched
          (the class has no virtuals), so it is harmless. }
        vmtSlots := UClsVirtCount[ci];
        if vmtSlots < 1 then vmtSlots := 1;
        for i := 0 to vmtSlots * 8 - 1 do
        begin
          if DataLen >= MAX_DATA then Error('data overflow');
          Data[DataLen] := 0;
          Inc(DataLen);
        end;
        { Fill every VMT slot from the effective method (own override or an
          inherited one). The per-override fixup loop only covers subclasses
          that already exist when the override is parsed, so a subclass
          declared later (or in a later unit) would leave inherited slots null
          and crash on dispatch. This makes each class's VMT self-contained. }
        for i := 0 to UClsVirtCount[ci] - 1 do
        begin
          slot := ResolveVMTSlotProc(ci, i);
          if slot >= 0 then
          begin
            if MethodFixCount >= MAX_METHFIX then Error('too many virtual method fixups');
            MethodFixups[MethodFixCount].DataPos := UClsVMTOffset[ci] + i * 8;
            MethodFixups[MethodFixCount].ProcIdx := slot;
            Inc(MethodFixCount);
          end;
        end;

        { Build one Interface Method Table per implemented interface: a Data[]
          array of code addresses, slot k = the class method implementing the
          interface's method k (matched by name), wired via MethodFixups like the
          VMT. A class->interface assignment captures the IMT address. }
        for ii := 0 to implCnt - 1 do
        begin
          tmpCi := implIntf[ii];
          if IMTCount >= MAX_IMT then Error('too many interface method tables');
          IMTClass[IMTCount] := ci;
          IMTIntf[IMTCount] := tmpCi;
          IMTOff[IMTCount] := DataLen;
          Inc(IMTCount);
          for imSlot := 0 to UClsMCount[tmpCi] - 1 do
          begin
            imName := '';
            for i := 0 to UMthNLen[UClsMBase[tmpCi] + imSlot] - 1 do
              AppendChar(imName, TokChars[UMthNOff[UClsMBase[tmpCi] + imSlot] + i]);
            mmi := FindUMeth(ci, imName);
            if mmi < 0 then Error('class does not implement interface method: ' + imName);
            imProc := UMthProc_[mmi];
            if MethodFixCount >= MAX_METHFIX then Error('too many method fixups (IMT)');
            MethodFixups[MethodFixCount].DataPos := DataLen;
            MethodFixups[MethodFixCount].ProcIdx := imProc;
            Inc(MethodFixCount);
            for i := 0 to 7 do begin if DataLen >= MAX_DATA then Error('data overflow'); Data[DataLen] := 0; Inc(DataLen); end;
          end;
        end;
      end
      else if (CurTok.Kind = tkPacked) or (CurTok.Kind = tkRecord) then
      begin
        isPackedRecord := CurTok.Kind = tkPacked;
        if isPackedRecord then
        begin
          Next;
          Expect(tkRecord, 'record');
        end
        else
          Next;
        ci := AddUClass(tnOff, tnLen);
        UClsParent[ci] := -1;
        UClsIsRecord[ci] := True;
        ParseRecordFields(ci, isPackedRecord);
      end
      else if CurTok.Kind = tkCaret then
      begin
        { Named pointer type alias: PFoo = ^TFoo }
        Next;
        targetNOff := Tokens[TokPos-1].SOffset;
        targetNLen := Tokens[TokPos-1].SLen;
        fTk := ParseTypeKind;
        RegisterPtrAlias(tnOff, tnLen, Ord(fTk), LastTypeRecId, targetNOff, targetNLen);
        if fTk = tyPointer then
        begin
          AliasPtrDepth[AliasCount-1] := LastTypePointerDepth + 1;
          AliasPtrBaseTk[AliasCount-1] := LastTypePointerBaseTk;
          AliasPtrBaseRec[AliasCount-1] := LastTypePointerBaseRec;
        end
        else
        begin
          AliasPtrDepth[AliasCount-1] := 1;
          AliasPtrBaseTk[AliasCount-1] := Ord(fTk);
          AliasPtrBaseRec[AliasCount-1] := LastTypeRecId;
        end;
        Eat(tkSemicolon);
      end
      else if CaseEqual(CurTok.SVal, 'set') then
      begin
        { Named set type: TFooSet = set of TFoo }
        Next;
        Expect(tkOf, 'of');
        propEnumId := FindEnumType(CurTok.SVal);
        RegisterSetAlias(tnOff, tnLen, propEnumId);
        while not (CurTok.Kind in [tkSemicolon,tkEOF]) do Next;
      end
      else if CurTok.Kind = tkArray then
      begin
        Next; { consume 'array' }
        if CurTok.Kind = tkLBrack then
        begin
          { Named fixed-array type `TA = array[a..b (, c..d, ...)] of T` —
            register it so a var/field/param of type TA becomes a real array
            (1-D or flattened N-D). An anonymous nested fixed array
            (`array[a] of array[b] of T`) is merged into `array[a,b] of T`
            (identical FPC layout). Previously skipped → TA was not an array. }
          tdCnt := 0;
          tMoreDims := True;
          while tMoreDims do
          begin
            Next;   { consume '[' }
            repeat
              tdLo := ConstEval; Expect(tkDotDot, '..'); tdHi := ConstEval;
              if tdCnt >= MAX_ARR_DIMS then Error('too many array dimensions');
              tdDimLo[tdCnt] := tdLo; tdDimSpan[tdCnt] := tdHi - tdLo + 1; Inc(tdCnt);
            until not Eat(tkComma);
            Expect(tkRBrack, ']');
            Expect(tkOf, 'of');
            { Continue only for a FIXED nested array, not a dynamic `array of`. }
            tMoreDims := (CurTok.Kind = tkArray) and (Tokens[TokPos].Kind = tkLBrack);
            if tMoreDims then Next;   { consume 'array'; loop head consumes '[' }
          end;
          { A FIXED named-array type as the element (`array[a..b] of TG`,
            `TG = array[c..d] of T`) has the SAME flat layout as `array[a..b,
            c..d] of T` — merge TG's dimensions into the outer list, exactly as
            the anonymous-nested form above does. Without this, ParseTypeKind
            resolves TG to its bare base element and the inner dimension is lost
            (the element stride collapses to the base type's size, corrupting
            p[i][j]). TG is already flattened in its own ArrType entry, so one
            merge covers arbitrary nesting depth. }
          fAi := -1;
          if CurTok.Kind = tkIdent then fAi := FindArrayType(CurTok.SVal);
          if (fAi >= 0) and (not ArrTypeIsDyn[fAi]) then
          begin
            if ArrTypeNDims[fAi] >= 2 then
            begin
              for tdi := 0 to ArrTypeNDims[fAi] - 1 do
              begin
                if tdCnt >= MAX_ARR_DIMS then Error('too many array dimensions');
                tdDimLo[tdCnt]   := ArrTypeDimLo[fAi * MAX_ARR_DIMS + tdi];
                tdDimSpan[tdCnt] := ArrTypeDimSpan[fAi * MAX_ARR_DIMS + tdi];
                Inc(tdCnt);
              end;
            end
            else
            begin
              if tdCnt >= MAX_ARR_DIMS then Error('too many array dimensions');
              tdDimLo[tdCnt]   := ArrTypeLo[fAi];
              tdDimSpan[tdCnt] := ArrTypeHi[fAi] - ArrTypeLo[fAi] + 1;
              Inc(tdCnt);
            end;
            aElemTk := IntToTypeKind(ArrTypeElemTk[fAi]);
            LastTypeRecId := ArrTypeElemRec[fAi];
            Next;   { consume the named array type }
          end
          else
            aElemTk := ParseTypeKind;
          if tdCnt = 1 then
          begin aLo := tdDimLo[0]; aHi := tdDimLo[0] + tdDimSpan[0] - 1; end
          else
          begin
            tflatLen := 1;
            for tdi := 0 to tdCnt - 1 do tflatLen := tflatLen * tdDimSpan[tdi];
            aLo := 0; aHi := tflatLen - 1;
          end;
          if ArrTypeCount >= MAX_TYPEALIAS then Error('too many array types');
          ArrTypeName[ArrTypeCount] := tname;
          ArrTypeLo[ArrTypeCount] := aLo;
          ArrTypeHi[ArrTypeCount] := aHi;
          ArrTypeElemTk[ArrTypeCount] := Ord(aElemTk);
          ArrTypeElemRec[ArrTypeCount] := LastTypeRecId;
          if tdCnt >= 2 then ArrTypeNDims[ArrTypeCount] := tdCnt
          else ArrTypeNDims[ArrTypeCount] := 0;
          for tdi := 0 to tdCnt - 1 do
          begin
            ArrTypeDimLo[ArrTypeCount * MAX_ARR_DIMS + tdi]   := tdDimLo[tdi];
            ArrTypeDimSpan[ArrTypeCount * MAX_ARR_DIMS + tdi] := tdDimSpan[tdi];
          end;
          ArrTypeIsDyn[ArrTypeCount] := False;
          Inc(ArrTypeCount);
        end
        else
        begin
          { Dynamic-array type alias `TArr = array of T` (nested: array of array
            of T). Register it so `var a: TArr` becomes a real dynamic array. }
          Expect(tkOf, 'of');
          tdCnt := 1; { reuse as dyn depth }
          while CurTok.Kind = tkArray do
          begin Next; Inc(tdCnt); Expect(tkOf, 'of'); end;
          aElemTk := ParseTypeKind;
          if ArrTypeCount >= MAX_TYPEALIAS then Error('too many array types');
          ArrTypeName[ArrTypeCount] := tname;
          ArrTypeElemTk[ArrTypeCount] := Ord(aElemTk);
          ArrTypeElemRec[ArrTypeCount] := LastTypeRecId;
          ArrTypeNDims[ArrTypeCount] := 0;
          ArrTypeIsDyn[ArrTypeCount] := True;
          ArrTypeDynDepth[ArrTypeCount] := tdCnt;
          Inc(ArrTypeCount);
        end;
      end
      else if (CurTok.Kind = tkProcedure) or (CurTok.Kind = tkFunction) then
      begin
        { Procedural type: `T = procedure(...)` / `function(...): R [of object]`.
          The signature is parsed into a body-less Procs[] entry; the alias keeps
          its index (AliasProcSig) so an indirect call `v(args)` through a var of
          this type marshals args/return via the same machinery as a direct call. }
        mIsFunc := (CurTok.Kind = tkFunction);
        Next;
        mNParams := 0;
        mRetType := tyInteger;
        if CurTok.Kind = tkLParen then
        begin
          Next;
          mDoneArgs := False;
          while (CurTok.Kind <> tkRParen) and not mDoneArgs do
          begin
            mIsByRef := False;
            mSawConst := False;
            if (CurTok.Kind = tkVar) or
               ((CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'out')) then
            begin mIsByRef := True; Next; end
            else if CurTok.Kind = tkConst then
            begin mSawConst := True; Next; end;
            mStartIdx := mNParams;
            mDoneParam := False;
            while IsDeclNameTok and not mDoneParam do
            begin
              mPNames[mNParams] := CurTok.SVal; Inc(mNParams); Next;
              if not Eat(tkComma) then mDoneParam := True;
              if CurTok.Kind = tkColon then mDoneParam := True;
            end;
            Expect(tkColon, ':');
            mIsArr := False;
            if CurTok.Kind = tkArray then
            begin
              Next; Expect(tkOf, 'of'); mTk := ParseTypeKind; mIsArr := True;
            end
            else
              mTk := ParseTypeKind;
            { A `const` record/variant param is passed by reference — must match
              ParseSubroutine's rule (parser.inc ~11403) so an INDIRECT call
              through this proc-type marshals the arg the same way the callee
              receives it (else the address/value mismatch segfaults — see
              bug-proc-typed-call-const-record-arg). }
            if mSawConst and ((mTk = tyRecord) or (mTk = tyVariant)) and not mIsArr then
              mIsByRef := True;
            for i := mStartIdx to mNParams-1 do
            begin
              mPTypes[i] := mTk;
              mPTypesRec[i] := LastTypeRecId;
              mPArr[i] := mIsArr;
              mPByRef[i] := mIsByRef;
            end;
            if not Eat(tkSemicolon) then mDoneArgs := True;
          end;
          Expect(tkRParen, ')');
        end;
        if mIsFunc then
        begin
          Expect(tkColon, ':');
          mRetType := ParseTypeKind;
        end;
        mpi := RegisterProc('$proctype', mIsFunc, mRetType, mNParams, mPNames, mPTypes);
        Procs[mpi].BodyAddr := -1;
        for i := 0 to mNParams-1 do
        begin
          Procs[mpi].Params[i].IsArray := mPArr[i];
          Procs[mpi].Params[i].IsRef := mPByRef[i];
        end;
        if CurTok.Kind = tkOf then
        begin
          { `of object` — a method pointer: a 16-byte {Code,Data} value. The
            signature drives arg marshalling; Self (Data) is injected at the call. }
          Next;
          if CurTok.Kind = tkIdent then Next;   { consume `object` }
          RegisterMethodPtrTypeAlias(tnOff, tnLen, mpi, EnsureMethodPtrRec);
        end
        else
          RegisterProcTypeAlias(tnOff, tnLen, mpi);
        { Optional `; cdecl` calling-convention directive on the procedural type
          (`T = function(...): R; cdecl;`). Marks the signature C-ABI so an
          indirect call through a value of this type marshals System V (needed for
          dlsym'd C functions). Other directives (stdcall etc.) are not modelled
          yet — only cdecl, which on x86-64 is the System V path the externs use. }
        if (CurTok.Kind = tkSemicolon) and (TokPos < TokCount) and
           (Tokens[TokPos].Kind = tkIdent) and CaseEqual(GetTokenStr(TokPos), 'cdecl') then
        begin
          Next;   { consume ';' }
          Next;   { consume 'cdecl' }
          ProcCdecl[mpi] := True;
        end;
      end
      else if (CurTok.Kind = tkInteger) or (CurTok.Kind = tkMinus) or (CurTok.Kind = tkString) then
      begin
        { Named ordinal subrange type: `T = lo..hi` (1..10, 'a'..'z'). Modelled as
          an alias to the base ordinal (tyChar for a char-literal bound, else
          tyInteger) — same treatment as an inline `var x: lo..hi` subrange (the
          bounds are not retained). }
        if CurTok.Kind = tkString then fTk := tyChar else fTk := tyInteger;
        ConstEval;                 { low bound }
        Expect(tkDotDot, '..');
        ConstEval;                 { high bound }
        RegisterGeneralAlias(tnOff, tnLen, Ord(fTk), REC_NONE);
      end
      else if (CurTok.Kind = tkIdent) and IsClassType(CurTok.SVal) and
              ((TokPos >= TokCount) or (Tokens[TokPos].Kind = tkSemicolon)) then
      begin
        { Class-name alias: `TOptionList = TList;` (blcksock). Registered in
          the UClass alias table so FindUClass resolves the new name to the
          SAME class row — var decls, X.Create, casts and is/as all see it. }
        ci := FindUClass(CurTok.SVal);
        RegisterUClassAlias(tnOff, tnLen, ci);
        Next;
      end
      else
      begin
        { Named simple type alias: PFoo = BaseType }
        fTk := ParseTypeKind;
        RegisterGeneralAlias(tnOff, tnLen, Ord(fTk), LastTypeRecId);
      end;
      SkipHintDirectives;   { type T = BaseType deprecated; }
      Eat(tkSemicolon);
    end;
  end;
  { Materialise deferred class-specialization methods after the section. The
    loop exited with the terminating token already loaded into CurTok (TokPos
    points past it); un-read it so the streamed methods are inserted before it,
    then reload CurTok from the first streamed token (or the terminator again if
    nothing was streamed). }
  { NOT from a nested class-local type section: flushing there would splice
    the pending method impls into the middle of the enclosing class body. }
  if (PendingSpecCount > 0) and (TypeSectionDepth = 0) then
  begin
    Dec(TokPos);
    FlushPendingClassSpecializations;
    Next;
  end;
  ResolvePendingPointerAliases;
end;

{ ===== Nested routines (Approach B: lambda-lifting) =====

  A procedure/function declared inside another routine's declaration section is
  NOT emitted in place (single-pass emission would drop its body into the middle
  of the enclosing routine's code). Instead, at the declaration point we:
    1. stash the nested routine's full token stream (PendNestTok), and
    2. rewrite the in-place copy into a FORWARD declaration so the enclosing
       body's calls to it resolve via the existing forward-completion path.
  When the enclosing routine finishes (end of ParseSubroutine),
  FlushPendingNestedProcs re-injects the stashed tokens after it, where the
  top-level driver parses them as ordinary sibling routines that complete the
  forward decl. This reuses the by-ref param ABI and forward machinery already
  byte-identical on all targets — no new per-target codegen.

  Slice 1: flatten only (own params/locals + globals).
  Slice 2a (this code): Self/field CAPTURE for a routine nested in a method. The
  lifted proc gains a trailing by-value param `__nestself: <EnclosingClass>`;
  implicit field/method references (and explicit `Self`) in the body are
  rewritten to go through it (`Rooms` -> `__nestself.Rooms`); call sites in the
  enclosing body get `Self` appended as the extra actual. Capture of an
  enclosing local/parameter is detected and rejected with a diagnostic (Slice 2b).

  PERFORMANCE: lifted nested routines are not speed-optimized — a captured field
  goes through the passed Self pointer rather than the enclosing frame's direct
  access. Correct and fully functional, just one extra indirection. }

{ Append s to TokChars and return its start offset (a fresh slice usable as a
  token's SOffset; SLen = Length(s)). }
function NestStrOff(const s: AnsiString): Integer;
var j: Integer;
begin
  Result := TokCharLen;
  for j := 1 to Length(s) do
  begin
    TokChars[TokCharLen] := s[j];
    Inc(TokCharLen);
  end;
end;

{ Decimal of a non-negative integer (no IntToStr in the compiler's own RTL). }
function MangleSuffix(n: Integer): AnsiString;
var d: array[0..15] of Char; c, m: Integer; s: AnsiString;
begin
  if n <= 0 then begin Result := '0'; Exit; end;
  c := 0; m := n;
  while m > 0 do begin d[c] := Chr(Ord('0') + (m mod 10)); Inc(c); m := m div 10; end;
  s := '';
  while c > 0 do begin Dec(c); AppendChar(s, d[c]); end;
  Result := s;
end;

{ Lambda-lift descriptor lookup by (mangled, unique) routine name. }
function FindLiftDesc(const nm: AnsiString): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to LiftCount - 1 do
    if StrEqual(LiftName[i], nm) then begin Result := i; Exit; end;
end;

{ Re-scan a nested routine's header ';' (paren-depth 0), its 'begin', and its end
  starting at nestedStart, after token edits may have shifted positions. (Kept a
  top-level helper, not a nested routine, so the compiler can self-host without
  needing nested-routine capture for its own source.) }
procedure NestScanSpans(nestedStart: Integer; var hdrEnd, bodyBegin, finalCur: Integer);
var cur, depth: Integer;
begin
  depth := 0; cur := nestedStart;
  while cur < TokCount do
  begin
    if Tokens[cur].Kind = tkLParen then Inc(depth)
    else if Tokens[cur].Kind = tkRParen then Dec(depth)
    else if (Tokens[cur].Kind = tkSemicolon) and (depth = 0) then Break;
    Inc(cur);
  end;
  if cur >= TokCount then Error('nested routine: malformed header');
  hdrEnd := cur;
  cur := hdrEnd;
  while (cur < TokCount) and (Tokens[cur].Kind <> tkBegin) do Inc(cur);
  if cur >= TokCount then Error('nested routine: expected begin');
  bodyBegin := cur;
  depth := 1; Inc(cur);
  while (cur < TokCount) and (depth > 0) do
  begin
    if (Tokens[cur].Kind = tkBegin) or (Tokens[cur].Kind = tkCase) then Inc(depth)
    else if Tokens[cur].Kind = tkEnd then Dec(depth);
    Inc(cur);
  end;
  if (cur < TokCount) and (Tokens[cur].Kind = tkSemicolon) then Inc(cur);
  finalCur := cur;
end;

procedure ParseNestedRoutine;
const MAX_NEST_REFS = 4096; MAX_NEST_CAPS = 64;
var
  nestedStart, nameTokIdx, hdrEnd, bodyBegin, finalCur, cur, depth, i, j, remCount: Integer;
  parenOpen, parenClose: Integer;
  ci, descIdx: Integer;
  needSelf, beforeColon, isOwnName, found: Boolean;
  nsOff, nsLen, selfOff, mOff, mLen: Integer;
  ownN: array[0..127] of AnsiString;
  ownCount: Integer;
  fieldPos: array[0..MAX_NEST_REFS-1] of Integer;  { implicit field/method refs to prefix with __nestself. }
  fieldCnt: Integer;
  selfPos: array[0..MAX_NEST_REFS-1] of Integer;   { explicit `Self` tokens to rename to __nestself }
  selfCnt: Integer;
  namePos: array[0..MAX_NEST_REFS-1] of Integer;   { body refs to the routine's own name (result-var / recursion) -> mangled }
  nameCnt: Integer;
  nm, nestedName, mangled: AnsiString;
  sidx: Integer;
  ins: array[0..7] of TRawToken;
  parentBegin, parentEnd: Integer;
  k: Integer;
  shift, tmpPos: Integer;
  { captured enclosing locals/params (snapshot at the capture site) }
  capNm: array[0..MAX_NEST_CAPS-1] of AnsiString;
  capTk: array[0..MAX_NEST_CAPS-1] of TTypeKind;
  capRec, capDyn, capPtrRec, capProcSig: array[0..MAX_NEST_CAPS-1] of Integer;
  capPtrTk: array[0..MAX_NEST_CAPS-1] of TTypeKind;
  capArr: array[0..MAX_NEST_CAPS-1] of Boolean;
  capActOff: array[0..MAX_NEST_CAPS-1] of Integer;
  capCount: Integer;
  core: array[0..2*MAX_NEST_CAPS+3] of TRawToken;
  coreCount, nact, emitted: Integer;
  coreSelf: array[0..2*MAX_NEST_CAPS+3] of TRawToken;
  coreSelfCount: Integer;
  nestSelfOff, nestSelfLen: Integer;
  ins2: array[0..2*MAX_NEST_CAPS+7] of TRawToken;
  ins2Count, rp: Integer;
begin
  nestedStart := TokPos - 1;   { the 'procedure'/'function' token (= CurTok) }
  nameTokIdx := nestedStart + 1;
  if Tokens[nameTokIdx].Kind <> tkIdent then Error('nested routine: expected name');
  nestedName := GetTokenStrFromRaw(Tokens[nameTokIdx].SOffset, Tokens[nameTokIdx].SLen);

  NestScanSpans(nestedStart, hdrEnd, bodyBegin, finalCur);

  { Param-list parens (if any). }
  parenOpen := -1; parenClose := -1;
  if Tokens[nameTokIdx + 1].Kind = tkLParen then
  begin
    parenOpen := nameTokIdx + 1;
    depth := 0; cur := parenOpen;
    while cur < hdrEnd do
    begin
      if Tokens[cur].Kind = tkLParen then Inc(depth)
      else if Tokens[cur].Kind = tkRParen then
      begin Dec(depth); if depth = 0 then begin parenClose := cur; Break; end; end;
      Inc(cur);
    end;
  end;

  ci := -1;
  if CurSelfClass >= REC_UCLASS_BASE then ci := CurSelfClass - REC_UCLASS_BASE;

  { Own names: the routine's own param names (idents before ':' inside the param
    parens) and decl-section local names (idents before ':'/'=' between the
    header and 'begin'). These shadow enclosing scope and must never be captured. }
  ownCount := 0;
  if parenOpen >= 0 then
  begin
    beforeColon := True;
    for i := parenOpen + 1 to parenClose - 1 do
    begin
      if Tokens[i].Kind = tkColon then beforeColon := False
      else if Tokens[i].Kind = tkSemicolon then beforeColon := True
      else if (Tokens[i].Kind = tkIdent) and beforeColon and (ownCount < 128) then
      begin ownN[ownCount] := GetTokenStrFromRaw(Tokens[i].SOffset, Tokens[i].SLen); Inc(ownCount); end;
    end;
  end;
  beforeColon := True;
  for i := hdrEnd + 1 to bodyBegin - 1 do
  begin
    if (Tokens[i].Kind = tkColon) or (Tokens[i].Kind = tkEq) then beforeColon := False
    else if Tokens[i].Kind = tkSemicolon then beforeColon := True
    else if (Tokens[i].Kind = tkVar) or (Tokens[i].Kind = tkConst) or (Tokens[i].Kind = tkType) then beforeColon := True
    else if (Tokens[i].Kind = tkIdent) and beforeColon and (ownCount < 128) then
    begin ownN[ownCount] := GetTokenStrFromRaw(Tokens[i].SOffset, Tokens[i].SLen); Inc(ownCount); end;
  end;

  { Free-variable analysis over the body. Classify each non-selector ident:
    own (skip) / explicit Self (rename) / enclosing local-or-param (capture by
    ref) / implicit Self field-or-method (capture Self) / global-or-other (skip).
    Inner nested routines are skipped wholesale — their captures are resolved
    when they are themselves lifted. }
  needSelf := False; fieldCnt := 0; selfCnt := 0; capCount := 0; nameCnt := 0;
  i := bodyBegin;
  while i < finalCur do
  begin
    if (Tokens[i].Kind = tkProcedure) or (Tokens[i].Kind = tkFunction) then
    begin
      while (i < finalCur) and (Tokens[i].Kind <> tkBegin) do Inc(i);
      depth := 1; Inc(i);
      while (i < finalCur) and (depth > 0) do
      begin
        if (Tokens[i].Kind = tkBegin) or (Tokens[i].Kind = tkCase) then Inc(depth)
        else if Tokens[i].Kind = tkEnd then Dec(depth);
        Inc(i);
      end;
      Continue;
    end;
    if Tokens[i].Kind = tkIdent then
    begin
      if (i > 0) and (Tokens[i-1].Kind = tkDot) then begin Inc(i); Continue; end;
      nm := GetTokenStrFromRaw(Tokens[i].SOffset, Tokens[i].SLen);
      { the routine's own name in its body = the function-result variable
        (FuncName := expr) or a recursive self-call; both must follow the mangle. }
      if CaseEqual(nm, nestedName) then
      begin
        if nameCnt < MAX_NEST_REFS then begin namePos[nameCnt] := i; Inc(nameCnt); end;
        Inc(i); Continue;
      end;
      isOwnName := False;
      for j := 0 to ownCount - 1 do
        if CaseEqual(ownN[j], nm) then begin isOwnName := True; Break; end;
      if isOwnName then begin Inc(i); Continue; end;
      if CaseEqual(nm, 'Self') then
      begin
        needSelf := True;
        if selfCnt < MAX_NEST_REFS then begin selfPos[selfCnt] := i; Inc(selfCnt); end;
      end
      else
      begin
        sidx := FindSym(nm);
        if (sidx >= 0) and ((Syms[sidx].Kind = skLocal) or (Syms[sidx].Kind = skParam)) then
        begin
          { Capture an enclosing local/param by reference. Snapshot its type now —
            the enclosing Syms slot is recycled before the lifted body is parsed.
            The lifted param keeps the same name so body refs resolve to it. }
          found := False;
          for j := 0 to capCount - 1 do
            if CaseEqual(capNm[j], nm) then begin found := True; Break; end;
          if not found then
          begin
            if capCount >= MAX_NEST_CAPS then Error('nested routine: too many captured variables');
            capNm[capCount] := Syms[sidx].Name;
            if Syms[sidx].IsArray and (SymDynDepth[sidx] > 0) then
            begin
              capTk[capCount] := Syms[sidx].ElemType;
              capRec[capCount] := Syms[sidx].ElemRecName;
              capArr[capCount] := True;
              capDyn[capCount] := SymDynDepth[sidx];
            end
            else if Syms[sidx].IsArray then
              Error('nested routine: capture of fixed-size array ''' + nm + ''' not yet supported')
            else
            begin
              capTk[capCount] := Syms[sidx].TypeKind;
              capRec[capCount] := Syms[sidx].RecName;
              capArr[capCount] := False;
              capDyn[capCount] := 0;
            end;
            capPtrTk[capCount] := Syms[sidx].PtrElemTk;
            capPtrRec[capCount] := Syms[sidx].PtrElemRec;
            capProcSig[capCount] := SymProcSig[sidx];
            Inc(capCount);
          end;
        end
        else if (sidx < 0) and (ci >= 0) and
                ((FindUField(ci, nm) >= 0) or (FindUMeth(ci, nm) >= 0)) then
        begin
          needSelf := True;
          if fieldCnt < MAX_NEST_REFS then begin fieldPos[fieldCnt] := i; Inc(fieldCnt); end;
        end;
      end;
    end;
    Inc(i);
  end;

  if needSelf and (ci < 0) then
    Error('nested routine: Self/field used but enclosing routine is not a method');

  { Mangle the routine to a unique name so the lift descriptor and forward-
    completion can't collide with another routine (the in-place forward decl and
    the stashed definition share this single rewritten name token). }
  mangled := nestedName;
  AppendChar(mangled, '$');
  mangled := mangled + MangleSuffix(nestedStart);
  mOff := NestStrOff(mangled); mLen := Length(mangled);
  Tokens[nameTokIdx].SOffset := mOff;
  Tokens[nameTokIdx].SLen := mLen;
  { Body refs to the own name (result var / recursion) are handled below,
    AFTER the field-prefix inserts (needSelf block) -- a self-referencing
    call may need the same extra actuals (Self/captures) a sibling call
    gets, which requires knowing whether the field-prefix pass shifted this
    occurrence's token position first (bug-nested-proc-sibling-call-
    unresolved symptom 2: a capturing nested routine's self-recursive call
    was missing its hidden captured-frame argument). }

  { Record the lift descriptor consumed by ParseSubroutine to inject the captured
    params (Self + by-ref enclosing vars). }
  if LiftCount >= MAX_LIFTS then Error('too many lifted nested routines');
  if LiftCapTot + capCount >= MAX_LIFT_CAPS then Error('too many nested captures');
  descIdx := LiftCount;
  LiftName[descIdx] := mangled;
  LiftNeedSelf[descIdx] := needSelf;
  LiftSelfCi[descIdx] := ci;
  LiftCapStart[descIdx] := LiftCapTot;
  LiftCapCount[descIdx] := capCount;
  for k := 0 to capCount - 1 do
  begin
    LiftCapName[LiftCapTot]   := capNm[k];
    LiftCapTk[LiftCapTot]     := capTk[k];
    LiftCapRec[LiftCapTot]    := capRec[k];
    LiftCapArr[LiftCapTot]    := capArr[k];
    LiftCapDyn[LiftCapTot]    := capDyn[k];
    LiftCapPtrTk[LiftCapTot]  := capPtrTk[k];
    LiftCapPtrRec[LiftCapTot] := capPtrRec[k];
    LiftCapProcSig[LiftCapTot]:= capProcSig[k];
    Inc(LiftCapTot);
  end;
  Inc(LiftCount);

  { Build the comma-separated actual list `Self, cap0, cap1, ...` (no outer
    parens) for external call sites (enclosing body / sibling routines,
    below). A self-recursive call site needs the same captured-var actuals
    but CANNOT use the literal `Self` -- that identifier isn't in scope
    inside the now-lifted, top-level routine body; the routine's own hidden
    parameter is named `__nestself` instead (captured vars, by contrast, use
    the SAME name either way, since the lifted routine's by-ref param shares
    the captured var's original name). `coreSelf` mirrors `core` with that
    one substitution, built alongside it so both are ready before the
    needSelf block runs. Moved earlier than the original single use site so
    both this and the self-splice below can share them. }
  selfOff := NestStrOff('Self');
  nestSelfOff := NestStrOff('__nestself'); nestSelfLen := 10;
  for k := 0 to capCount - 1 do
    capActOff[k] := NestStrOff(capNm[k]);
  coreCount := 0; emitted := 0;
  if needSelf then
  begin
    core[coreCount].Kind := tkIdent; core[coreCount].IVal := 0; core[coreCount].Line := 0;
    core[coreCount].SOffset := selfOff; core[coreCount].SLen := 4; Inc(coreCount); Inc(emitted);
  end;
  for k := 0 to capCount - 1 do
  begin
    if emitted > 0 then
    begin
      core[coreCount].Kind := tkComma; core[coreCount].IVal := 0; core[coreCount].Line := 0;
      core[coreCount].SOffset := 0; core[coreCount].SLen := 0; Inc(coreCount);
    end;
    core[coreCount].Kind := tkIdent; core[coreCount].IVal := 0; core[coreCount].Line := 0;
    core[coreCount].SOffset := capActOff[k]; core[coreCount].SLen := Length(capNm[k]); Inc(coreCount); Inc(emitted);
  end;
  nact := emitted;

  coreSelfCount := 0; emitted := 0;
  if needSelf then
  begin
    coreSelf[coreSelfCount].Kind := tkIdent; coreSelf[coreSelfCount].IVal := 0; coreSelf[coreSelfCount].Line := 0;
    coreSelf[coreSelfCount].SOffset := nestSelfOff; coreSelf[coreSelfCount].SLen := nestSelfLen; Inc(coreSelfCount); Inc(emitted);
  end;
  for k := 0 to capCount - 1 do
  begin
    if emitted > 0 then
    begin
      coreSelf[coreSelfCount].Kind := tkComma; coreSelf[coreSelfCount].IVal := 0; coreSelf[coreSelfCount].Line := 0;
      coreSelf[coreSelfCount].SOffset := 0; coreSelf[coreSelfCount].SLen := 0; Inc(coreSelfCount);
    end;
    coreSelf[coreSelfCount].Kind := tkIdent; coreSelf[coreSelfCount].IVal := 0; coreSelf[coreSelfCount].Line := 0;
    coreSelf[coreSelfCount].SOffset := capActOff[k]; coreSelf[coreSelfCount].SLen := Length(capNm[k]); Inc(coreSelfCount); Inc(emitted);
  end;

  { Body rewrites for Self capture: rename explicit `Self`, prefix `__nestself .`
    on each implicit field/method ref. Captured locals need no body rewrite — the
    injected by-ref param shares their name. }
  if needSelf then
  begin
    nsOff := NestStrOff('__nestself'); nsLen := 10;
    for k := 0 to selfCnt - 1 do
    begin
      Tokens[selfPos[k]].SOffset := nsOff;
      Tokens[selfPos[k]].SLen := nsLen;
    end;
    for k := fieldCnt - 1 downto 0 do
    begin
      ins[0].Kind := tkIdent; ins[0].IVal := 0; ins[0].Line := Tokens[fieldPos[k]].Line;
      ins[0].SOffset := nsOff; ins[0].SLen := nsLen;
      ins[1].Kind := tkDot; ins[1].IVal := 0; ins[1].Line := Tokens[fieldPos[k]].Line;
      ins[1].SOffset := 0; ins[1].SLen := 0;
      InsertTokens(fieldPos[k], ins, 2);
    end;
    NestScanSpans(nestedStart, hdrEnd, bodyBegin, finalCur);   { field prefixes shifted positions }
  end;

  { Body refs to the own name (result-var write, or a self-recursive call):
    rename to the mangled name; a genuine recursive CALL (not a result-var
    write, detected by NOT being followed by `:=`) also needs the same extra
    actuals (Self/captures) spliced in when this routine captures anything
    (nact > 0) -- the lifted routine's own by-ref capture params share the
    captured var's original name, so re-passing e.g. `acc` from inside a
    recursive call correctly forwards the same by-ref binding transitively.
    Without this, a capturing routine's self-call kept the OLD (pre-lift)
    arity, one hidden arg short (bug-nested-proc-sibling-call-unresolved
    symptom 2).

    namePos[] positions were captured during the free-variable scan, in the
    SAME pass as fieldPos[] -- and the needSelf block above may have already
    inserted 2 tokens at each fieldPos[] location. Any namePos[k] whose
    ORIGINAL position was past a given fieldPos[] entry has silently shifted
    by +2 for it (insertions preserve relative order, so the total shift for
    a stationary point is exactly 2 * count(fieldPos[j] < namePos[k]),
    independent of processing order). Correct for that, then splice in
    descending corrected-position order (mirroring fieldPos[]'s own pattern)
    so each insertion doesn't invalidate a not-yet-processed lower position. }
  for k := 0 to nameCnt - 1 do
  begin
    shift := 0;
    for j := 0 to fieldCnt - 1 do
      if fieldPos[j] < namePos[k] then Inc(shift, 2);
    namePos[k] := namePos[k] + shift;
  end;
  for k := 1 to nameCnt - 1 do
  begin
    tmpPos := namePos[k]; j := k - 1;
    while (j >= 0) and (namePos[j] < tmpPos) do
    begin
      namePos[j + 1] := namePos[j]; Dec(j);
    end;
    namePos[j + 1] := tmpPos;
  end;
  for k := 0 to nameCnt - 1 do
  begin
    Tokens[namePos[k]].SOffset := mOff;
    Tokens[namePos[k]].SLen := mLen;
    if (nact > 0) and (Tokens[namePos[k] + 1].Kind <> tkAssign) then
    begin
      if Tokens[namePos[k] + 1].Kind = tkLParen then
      begin
        depth := 0; rp := namePos[k] + 1;
        while rp < TokCount do
        begin
          if Tokens[rp].Kind = tkLParen then Inc(depth)
          else if Tokens[rp].Kind = tkRParen then begin Dec(depth); if depth = 0 then Break; end;
          Inc(rp);
        end;
        ins2Count := 0;
        if Tokens[namePos[k] + 2].Kind <> tkRParen then
        begin
          ins2[0].Kind := tkComma; ins2[0].IVal := 0; ins2[0].Line := Tokens[namePos[k]].Line; ins2[0].SOffset := 0; ins2[0].SLen := 0;
          ins2Count := 1;
        end;
        for j := 0 to coreSelfCount - 1 do begin ins2[ins2Count] := coreSelf[j]; ins2[ins2Count].Line := Tokens[namePos[k]].Line; Inc(ins2Count); end;
        InsertTokens(rp, ins2, ins2Count);
      end
      else
      begin
        { bare self-call `name;` -> `name( __nestself, ... )` }
        ins2[0].Kind := tkLParen; ins2[0].IVal := 0; ins2[0].Line := Tokens[namePos[k]].Line; ins2[0].SOffset := 0; ins2[0].SLen := 0;
        ins2Count := 1;
        for j := 0 to coreSelfCount - 1 do begin ins2[ins2Count] := coreSelf[j]; ins2[ins2Count].Line := Tokens[namePos[k]].Line; Inc(ins2Count); end;
        ins2[ins2Count].Kind := tkRParen; ins2[ins2Count].IVal := 0; ins2[ins2Count].Line := Tokens[namePos[k]].Line; ins2[ins2Count].SOffset := 0; ins2[ins2Count].SLen := 0; Inc(ins2Count);
        InsertTokens(namePos[k] + 1, ins2, ins2Count);
      end;
    end;
  end;
  if (nact > 0) and (nameCnt > 0) then
    NestScanSpans(nestedStart, hdrEnd, bodyBegin, finalCur);   { self-call splices may have shifted positions }

  i := finalCur; parentBegin := -1;
  while i < TokCount do
  begin
    if (Tokens[i].Kind = tkProcedure) or (Tokens[i].Kind = tkFunction) then
    begin
      while (i < TokCount) and (Tokens[i].Kind <> tkBegin) do Inc(i);
      depth := 1; Inc(i);
      while (i < TokCount) and (depth > 0) do
      begin
        if (Tokens[i].Kind = tkBegin) or (Tokens[i].Kind = tkCase) then Inc(depth)
        else if Tokens[i].Kind = tkEnd then Dec(depth);
        Inc(i);
      end;
    end
    else if Tokens[i].Kind = tkBegin then begin parentBegin := i; Break; end
    else Inc(i);
  end;
  if parentBegin >= 0 then
  begin
    depth := 1; i := parentBegin + 1;
    while (i < TokCount) and (depth > 0) do
    begin
      if (Tokens[i].Kind = tkBegin) or (Tokens[i].Kind = tkCase) then Inc(depth)
      else if Tokens[i].Kind = tkEnd then Dec(depth);
      Inc(i);
    end;
    parentEnd := i;
    { Lower bound is finalCur (not parentBegin): also rewrite call sites inside
      not-yet-lifted SIBLING nested routines declared between this routine and
      the enclosing 'begin' (skipped above only to locate parentBegin, not to
      exempt them) -- otherwise a sibling calling this routine (e.g. `b` calling
      `a`, both nested in the same `outer`) keeps the unmangled name and fails
      to resolve once this routine's own declaration is rewritten to `forward`
      (bug-nested-proc-sibling-call-unresolved). }
    for i := parentEnd - 1 downto finalCur do
      if (Tokens[i].Kind = tkIdent) and
         CaseEqual(GetTokenStrFromRaw(Tokens[i].SOffset, Tokens[i].SLen), nestedName) and
         ((i = 0) or (Tokens[i-1].Kind <> tkDot)) then
      begin
        Tokens[i].SOffset := mOff; Tokens[i].SLen := mLen;   { rename call -> mangled }
        if nact > 0 then
        begin
          if Tokens[i+1].Kind = tkLParen then
          begin
            depth := 0; rp := i + 1;
            while rp < TokCount do
            begin
              if Tokens[rp].Kind = tkLParen then Inc(depth)
              else if Tokens[rp].Kind = tkRParen then begin Dec(depth); if depth = 0 then Break; end;
              Inc(rp);
            end;
            ins2Count := 0;
            if Tokens[i+2].Kind <> tkRParen then   { non-empty arg list: prepend a comma }
            begin
              ins2[0].Kind := tkComma; ins2[0].IVal := 0; ins2[0].Line := Tokens[i].Line; ins2[0].SOffset := 0; ins2[0].SLen := 0;
              ins2Count := 1;
            end;
            for k := 0 to coreCount - 1 do begin ins2[ins2Count] := core[k]; ins2[ins2Count].Line := Tokens[i].Line; Inc(ins2Count); end;
            InsertTokens(rp, ins2, ins2Count);
          end
          else
          begin
            { bare call `name;` -> `name( Self, ... )` }
            ins2[0].Kind := tkLParen; ins2[0].IVal := 0; ins2[0].Line := Tokens[i].Line; ins2[0].SOffset := 0; ins2[0].SLen := 0;
            ins2Count := 1;
            for k := 0 to coreCount - 1 do begin ins2[ins2Count] := core[k]; ins2[ins2Count].Line := Tokens[i].Line; Inc(ins2Count); end;
            ins2[ins2Count].Kind := tkRParen; ins2[ins2Count].IVal := 0; ins2[ins2Count].Line := Tokens[i].Line; ins2[ins2Count].SOffset := 0; ins2[ins2Count].SLen := 0; Inc(ins2Count);
            InsertTokens(i + 1, ins2, ins2Count);
          end;
        end;
      end;
  end;

  { Stash the (possibly rewritten) full routine [nestedStart, finalCur) for
    top-level re-parse. Token SOffsets index TokChars (never shifted). Record this
    routine's start offset within the buffer so the flush emits one DeclItem span
    per routine (a body may stash several back to back). }
  if PendNestCount + (finalCur - nestedStart) >= MAX_NESTED_TOKENS then
    Error('nested routine token buffer overflow');
  if PendNestRtnCount >= MAX_LIFTS then Error('too many nested routines in one body');
  PendNestRtnStart[PendNestRtnCount] := PendNestCount;
  Inc(PendNestRtnCount);
  for i := nestedStart to finalCur - 1 do
  begin
    PendNestTok[PendNestCount] := Tokens[i];
    Inc(PendNestCount);
  end;

  { Rewrite the in-place copy to `<header>; forward;` by replacing the body range
    (hdrEnd+1 .. finalCur-1) with the two tokens `forward ;`. }
  Tokens[hdrEnd + 1].Kind := tkForward;
  Tokens[hdrEnd + 1].IVal := 0; Tokens[hdrEnd + 1].Line := Tokens[nestedStart].Line;
  Tokens[hdrEnd + 1].SOffset := 0; Tokens[hdrEnd + 1].SLen := 0;
  Tokens[hdrEnd + 2].Kind := tkSemicolon;
  Tokens[hdrEnd + 2].IVal := 0; Tokens[hdrEnd + 2].Line := Tokens[nestedStart].Line;
  Tokens[hdrEnd + 2].SOffset := 0; Tokens[hdrEnd + 2].SLen := 0;
  remCount := finalCur - (hdrEnd + 3);
  if remCount > 0 then
  begin
    for i := finalCur to TokCount - 1 do
      Tokens[i - remCount] := Tokens[i];
    TokCount := TokCount - remCount;
    { The removed inner body shifts every later token down by remCount — keep the
      body pass's still-pending DeclItem spans and body-begin marker in sync. }
    AdjustPass2Spans(finalCur, -remCount);
  end;

  { CurTok is still the 'procedure'/'function' token; parse the forward decl now
    (registers the signature, then Exits without emitting a body). }
  ParseSubroutine;
end;

{ Re-inject any nested routines stashed during this routine's body so they parse
  as top-level siblings that complete the forward decls left in place by
  ParseNestedRoutine. APPENDED at end-of-stream (not spliced mid-stream): the
  body pass replays fixed DeclItem spans, so a mid-stream insert would shift the
  remaining spans + the body-begin marker out from under it. Each stashed routine
  becomes its own DeclItem span; the body-pass driver loops `while i < DeclItemCount`
  so these appended items are parsed in turn (and may themselves append deeper
  nested routines). Outside the body pass (single-pass legacy path) the same append
  works: the driver there also consumes trailing DeclItems. }
procedure FlushPendingNestedProcs;
var appendStart, i, r, rtnStart, rtnEnd: Integer;
begin
  if PendNestCount = 0 then Exit;
  appendStart := TokCount;
  for i := 0 to PendNestCount - 1 do
  begin
    if TokCount >= MAX_TOKENS then Error('token buffer overflow');
    Tokens[TokCount] := PendNestTok[i];
    Inc(TokCount);
  end;
  { One DeclItem span per stashed routine (boundaries recorded at stash time), so
    the body-pass driver parses each as its own sibling. }
  for r := 0 to PendNestRtnCount - 1 do
  begin
    if DeclItemCount >= MAX_DECL_ITEMS then Error('too many declarations (nested routine flush)');
    rtnStart := appendStart + PendNestRtnStart[r];
    if r + 1 < PendNestRtnCount then
      rtnEnd := appendStart + PendNestRtnStart[r + 1]
    else
      rtnEnd := TokCount;
    DeclItemStart[DeclItemCount] := rtnStart;
    DeclItemEnd[DeclItemCount]   := rtnEnd;
    Inc(DeclItemCount);
  end;
  PendNestCount := 0;
  PendNestRtnCount := 0;
end;

{ ===== Procedure/function parser ===== }

procedure CompilePendingLocalInits;
{ Emit the recorded routine-local typed-const initializers as assignments, at the
  current code position (the routine prologue, after managed-local zero-init and
  before the body). Mirror of CompilePendingGlobalInits over the LocalInit list;
  the list is reset by the caller at routine entry. }
var i, identNode, valNode, idxLit, target, assignNode: Integer;
begin
  { -O2 register-residency: suppress r14/r15 residency assignment for these
    per-initializer CompileAST calls. Each would otherwise re-emit the save+load
    (growing a fresh save slot) and desync the single epilogue restore, which then
    restores a param value over the caller's r14/r15. Residency is assigned once,
    at the main body, after these run. See bug-a-o2-miscompiles-disassembler. }
  RcSuppressAssign := True;
  for i := 0 to LocalInitCount - 1 do
  begin
    identNode := AllocNode(AN_IDENT);
    ASTIVal[identNode] := LocalInitSym[i];
    ASTTk[identNode] := Ord(Syms[LocalInitSym[i]].TypeKind);

    if LocalInitFOff[i] >= 0 then
    begin
      { Record typed-const field: `sym.field := value`. }
      target := AllocNode(AN_FIELD);
      ASTLeft[target] := identNode;
      ASTSOffset[target] := LocalInitFOff[i];
      ASTSLen[target] := LocalInitFLen[i];
      ASTTk[target] := LocalInitTk[i];
    end
    else if LocalInitElem[i] >= 0 then
    begin
      idxLit := AllocNode(AN_INT_LIT);
      ASTIVal[idxLit] := LocalInitElem[i];
      ASTTk[idxLit] := Ord(tyInteger);
      target := AllocNode(AN_INDEX);
      ASTLeft[target] := identNode;
      ASTRight[target] := idxLit;
      ASTTk[target] := LocalInitTk[i];
    end
    else
      target := identNode;

    if LocalInitKind[i] = 1 then
    begin
      valNode := AllocNode(AN_STR_LIT);
      ASTSOffset[valNode] := LocalInitVal[i];
      ASTSLen[valNode] := LocalInitFLen[i];
      ASTTk[valNode] := Ord(tyString);
    end
    else if LocalInitKind[i] = 5 then
    begin
      { metaclass const init: class VMT address }
      valNode := AllocNode(AN_CLASSREF);
      ASTIVal[valNode] := LocalInitVal[i];
      ASTTk[valNode] := Ord(tyPointer);
    end
    else
    begin
      valNode := AllocNode(AN_INT_LIT);
      ASTIVal[valNode] := LocalInitVal[i];
      ASTTk[valNode] := LocalInitTk[i];
    end;

    assignNode := AllocNode(AN_ASSIGN);
    ASTLeft[assignNode] := target;
    ASTRight[assignNode] := valNode;

    CompileAST(assignNode);
    ASTNodeCount := 0;
  end;
  RcSuppressAssign := False;
  LocalInitCount := 0;
end;

procedure PreScanSkipRoutineBody;
{ Declaration pre-scan helper (pass 1). On entry CurTok is the first token after a
  routine's header + directives (i.e. the start of its local-declaration part or
  its `begin`/`asm`). Consumes the local declarations and the body, including the
  trailing `;`, so the top-level decl walk can continue to the next declaration.
  Nested routines are skipped recursively so their own `begin..end` do not
  terminate the enclosing body early. Statement bodies never contain type
  declarations, so the begin/asm block is closed by a plain begin/case/try/asm
  vs end depth count. }
var depth: Integer;
begin
  { Local declaration part: advance to this routine's begin/asm, recursing into
    any nested routine (its keyword is the only begin/asm-bearing construct that
    can appear here). var/const/type/label tokens — including a local
    `record..end` — are passed over verbatim; only a nested routine introduces a
    begin we must not mistake for our own. }
  while not (CurTok.Kind in [tkBegin, tkAsm, tkEOF]) do
  begin
    if CurTok.Kind in [tkProcedure, tkFunction] then
    begin
      Next;                       { proc/func keyword }
      { skip the signature up to the ';' at paren depth 0 }
      depth := 0;
      while (CurTok.Kind <> tkEOF) and
            not ((CurTok.Kind = tkSemicolon) and (depth = 0)) do
      begin
        if CurTok.Kind = tkLParen then Inc(depth)
        else if CurTok.Kind = tkRParen then Dec(depth);
        Next;
      end;
      Eat(tkSemicolon);
      { skip calling-convention / directive clauses }
      while ((CurTok.Kind = tkIdent) and
             (CaseEqual(CurTok.SVal, 'inline') or CaseEqual(CurTok.SVal, 'register') or
              CaseEqual(CurTok.SVal, 'cdecl') or CaseEqual(CurTok.SVal, 'assembler') or
              CaseEqual(CurTok.SVal, 'generator') or CaseEqual(CurTok.SVal, 'async') or
              CaseEqual(CurTok.SVal, 'stackful') or CaseEqual(CurTok.SVal, 'stackless') or
              CaseEqual(CurTok.SVal, 'iram') or CaseEqual(CurTok.SVal, 'interrupt') or
              CaseEqual(CurTok.SVal, 'flexcolumn') or
              CaseEqual(CurTok.SVal, 'deprecated') or CaseEqual(CurTok.SVal, 'platform') or
              CaseEqual(CurTok.SVal, 'experimental') or CaseEqual(CurTok.SVal, 'unimplemented') or
              CaseEqual(CurTok.SVal, 'library') or
              CaseEqual(CurTok.SVal, 'external'))) or
            (CurTok.Kind = tkOverload) do
      begin
        if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'external') then
        begin
          { external clause has no body; consume to its terminating ';' }
          while (CurTok.Kind <> tkEOF) and (CurTok.Kind <> tkSemicolon) do Next;
        end
        else if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'deprecated') and
                (Tokens[TokPos].Kind = tkString) then
        begin Next; Next; end   { consume 'deprecated' and its message string }
        else
          Next;
        Eat(tkSemicolon);
      end;
      if CurTok.Kind = tkForward then begin Next; Eat(tkSemicolon); end
      else
        PreScanSkipRoutineBody;   { nested routine body }
    end
    else
      Next;
  end;
  { Body: balanced begin/asm .. end (case/try open inner ends too). }
  if CurTok.Kind in [tkBegin, tkAsm] then
  begin
    depth := 1;
    Next;
    while (depth > 0) and (CurTok.Kind <> tkEOF) do
    begin
      if CurTok.Kind in [tkBegin, tkCase, tkTry, tkAsm, tkRecord] then Inc(depth)
      else if CurTok.Kind = tkEnd then Dec(depth);
      Next;
    end;
  end;
  Eat(tkSemicolon);
end;

procedure ParseSubroutine;
var
  isFunc   : Boolean;
  name     : AnsiString;
  retType  : TTypeKind;
  tk       : TTypeKind;
  pnames    : array[0..MAX_PROC_PARAMS-1] of AnsiString;
  ptypes    : array[0..MAX_PROC_PARAMS-1] of TTypeKind;
  ptypesRec : array[0..MAX_PROC_PARAMS-1] of Integer;
  ptypesPtrElemTk : array[0..MAX_PROC_PARAMS-1] of TTypeKind;
  ptypesPtrElemRec : array[0..MAX_PROC_PARAMS-1] of Integer;
  ptypesProcSig : array[0..MAX_PROC_PARAMS-1] of Integer;  { proc-typed param: signature index, -1 otherwise }
  parr      : array[0..MAX_PROC_PARAMS-1] of Boolean;
  pbyref    : array[0..MAX_PROC_PARAMS-1] of Boolean;
  pconst    : array[0..MAX_PROC_PARAMS-1] of Boolean;  { param declared `const` (read-only by-ref) — lets a temporary bind to it }
  puntyped  : array[0..MAX_PROC_PARAMS-1] of Boolean;  { param declared untyped (var/const/out, no type) — matches any arg type, address passed }
  pdefault  : array[0..MAX_PROC_PARAMS-1] of Boolean;  { param has a default value (`b: Integer = 10`) }
  pdefaultval : array[0..MAX_PROC_PARAMS-1] of Int64;  { the constant-folded default ordinal }
  hasDefault : Boolean; defaultVal : Int64;
  pNDims    : array[0..MAX_PROC_PARAMS-1] of Integer;
  pDynDepth : array[0..MAX_PROC_PARAMS-1] of Integer;  { named dynamic-array param: dyn nesting depth (>0), 0 = not a dyn-array param }
  pDimLo    : array[0..95] of Integer;
  pDimSpan  : array[0..95] of Integer;
  paramNDims, paramDynDepth, paramAi, pdi: Integer;
  psLo, psSpan: array[0..MAX_ARR_DIMS-1] of Integer;
  nparams  : Integer;
  procIdx, helperPi, i, sz, retRecId, savedLastTypeRecId: Integer;
  zeroBytes : Integer;
  zfLoop, zfDone : Integer;
  retIsDynArr : Boolean; retElemTk : TTypeKind; retElemRec : Integer;
  retPtrElemTk, retPtrElemRec : Integer;
  savedSC, savedFS, savedCurProc : Integer;
  savedGLC, savedGFC, j, savedVisVarSeq: Integer;
  cleanupJnePatch, cleanupJmpPatch: Integer;
  patchPos : Integer;
  depth    : Integer;
  doneArgs, doneParam, isArr, isByRef, isConst, declOverload, declFlexColumn, isClassKeyword, isStaticMethod, declInline: Boolean;
  isUntyped : Boolean;
  needsProcCleanupFrame, savedProcCleanupFrameActive: Boolean;
  isAsmFunc: Boolean;
  preScanBody: Boolean;
  isGenerator, isStackless, isAsync: Boolean;
  isIram, isInterrupt: Boolean;
  savedGenIsGen, savedGenSeen, savedGenStackless, savedProcIsAsync: Boolean;
  savedGenSelf, savedGenTry, savedGenStateCtr, savedGenSlotNext: Integer;
  genBodyAST, genStepAST, declElemTk: Integer;
  genSelfIdx, gpi: Integer;
  asmNode: Integer;
  startIdx, idx: Integer;
  tokKindOrd: Integer;
  methOwnerCi, methOwnerRec, methSNOff, methSNLen, mmi, slot, otherCi: Integer;
  inlineBodyNode: Integer;   { retained body root for inline expansion }
  pw, pnWords, wlo, whi: Integer;   { ARM32 word-based param spill (int64 = 2 words) }
  methName: AnsiString;
  extLib: AnsiString;
  extSym: AnsiString;
  liftIdx, lcb: Integer;   { lambda-lift descriptor index / captured-param base }
begin
  isClassKeyword := False;
  isAsmFunc := False;
  isGenerator := False;
  isStackless := False;
  isAsync := False;
  isIram := False;
  isInterrupt := False;
  GenericMethodBuffered := False;
  if CurTok.Kind = tkClass then
  begin
    isClassKeyword := True;
    Next;
  end;
  isFunc := CurTok.Kind = tkFunction;
  Next;
  if CurTok.Kind <> tkIdent then Error('expected name');
  name := CurTok.SVal; Next;

  { Check for ClassName.MethodName pattern }
  methOwnerCi := -1;
  methOwnerRec := REC_NONE;
  methSNOff := 0; methSNLen := 0;
  if CurTok.Kind = tkDot then
  begin
    depth := -1;
    for i := 0 to TemplateCount - 1 do
      if CaseEqual(Templates[i].Name, name) then
        depth := i;
    if depth >= 0 then
    begin
      { Start the captured range at the 'procedure'/'function' keyword (one
        token before the template name) so the specialized stream is a complete
        standalone subroutine the top-level loop can parse. A `class` method
        impl starts one token earlier so the prefix survives into the stream. }
      if isClassKeyword then
        BufferGenericMethod(depth, TokPos - 4)
      else
        BufferGenericMethod(depth, TokPos - 3);
      GenericMethodBuffered := True;
      Exit;
    end;
      methOwnerCi := FindUClass(name);
      if methOwnerCi >= 0 then
      begin
        methOwnerRec := REC_UCLASS_BASE + methOwnerCi;
        Next; { consume dot }
        if not IsMemberNameTok then Error('expected method name');
        methName := CurTok.SVal;
        methSNOff := Tokens[TokPos-1].SOffset;
        methSNLen := Tokens[TokPos-1].SLen;
        AppendChar(name, '.');
        i := 1;
        while i <= Length(CurTok.SVal) do begin AppendChar(name, CurTok.SVal[i]); Inc(i); end;
        Next; { consume method name }
      end;
  end;

  nparams := 0; retType := tyInteger; retRecId := REC_NONE;
  retIsDynArr := False; retElemTk := tyUnknown; retElemRec := REC_NONE;
  retPtrElemTk := Ord(tyUnknown); retPtrElemRec := REC_NONE;

  if CurTok.Kind = tkLParen then
  begin
    Next;
    doneArgs := False;
    while (CurTok.Kind <> tkRParen) and not doneArgs do
    begin
      isByRef := False;
      isConst := False;
      hasDefault := False; defaultVal := 0;
      if (CurTok.Kind = tkVar) or
         ((CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'out')) then
      begin
        isByRef := True;
        Next;
      end
      else if CurTok.Kind = tkConst then
      begin
        isConst := True;
        Next;
      end;
      startIdx := nparams;
      doneParam := False;
      while IsDeclNameTok and not doneParam do
      begin
        pnames[nparams] := CurTok.SVal; Inc(nparams); Next;
        if not Eat(tkComma) then doneParam := True;
        if CurTok.Kind = tkColon then doneParam := True;
      end;
      isUntyped := False;
      if CurTok.Kind <> tkColon then
      begin
        { Untyped parameter (`var x` / `const x` / `out x`, no type): an untyped
          by-reference param. The caller passes the address of any-typed lvalue;
          the callee reaches it via @x. Underpins Move/FillChar-style routines.
          A value param with no type is meaningless, so require var/const/out. }
        if not (isByRef or isConst) then
          Error('untyped parameter requires var, const, or out');
        isUntyped := True; isByRef := True;
        tk := tyPointer; isArr := False; paramNDims := 0; paramDynDepth := 0;
        LastTypeRecId := REC_NONE; LastTypePointerElemTk := tyUnknown;
        LastTypePointerElemRec := REC_NONE; LastTypeProcSig := -1;
      end
      else
      begin
      Next;  { consume ':' }
      isArr := False;
      paramNDims := 0;
      paramDynDepth := 0;
      tokKindOrd := Ord(CurTok.Kind);
      if DebugTrace then writeln('After colon, CurTok.Kind = ', tokKindOrd, ', CurTok.SVal = ', CurTok.SVal);
      paramAi := -1;
      if CurTok.Kind = tkIdent then paramAi := FindArrayType(CurTok.SVal);
      if paramAi >= 0 then
      begin
        { Named fixed-array type param — pass like an open array (by the data
          pointer); the element type drives indexing, N-D dims drive flattening.
          (Previously ParseTypeKind didn't know the name was an array, so the
          param was scalar and indexing it read garbage.) }
        tk := IntToTypeKind(ArrTypeElemTk[paramAi]);
        LastTypeRecId := ArrTypeElemRec[paramAi];
        isArr := True;
        { Named dynamic-array type param (`TDynArr = array of T`): mark it a real
          dynamic array so SetLength routes to -102 and (when var/out) the
          by-ref-handle ABI applies. Distinct from a named *fixed* array, which
          stays an open-array fat-ptr param. }
        if ArrTypeIsDyn[paramAi] then
          paramDynDepth := ArrTypeDynDepth[paramAi];
        if ArrTypeNDims[paramAi] >= 2 then
        begin
          paramNDims := ArrTypeNDims[paramAi];
          for pdi := 0 to paramNDims - 1 do
          begin
            psLo[pdi]   := ArrTypeDimLo[paramAi * MAX_ARR_DIMS + pdi];
            psSpan[pdi] := ArrTypeDimSpan[paramAi * MAX_ARR_DIMS + pdi];
          end;
        end;
        Next;
      end
      else if CurTok.Kind = tkArray then
      begin
        Next;
        Expect(tkOf, 'of');
        if CurTok.Kind = tkConst then
        begin
          { `array of const` (TVarRec open array): each element is a TVarRec
            record from builtinheap. The callee reads it like any open array of
            records; the call site builds the element vector (AN_VARREC_ARRAY). }
          if TVarRecId = REC_NONE then
            Error('array of const requires the builtinheap unit (use an array/heap feature)');
          Next;
          tk := tyRecord;
          LastTypeRecId := TVarRecId;
        end
        else
          tk := ParseTypeKind;
        isArr := True;
      end
      else
        tk := ParseTypeKind;
      { Default value: `b: Integer = 10`. Constant-folded; supplied at a call that
        omits the (trailing) argument. }
      if CurTok.Kind = tkEq then
      begin
        Next;
        defaultVal := ConstEval;
        hasDefault := True;
      end;
      end;  { close the typed (has-colon) branch }
      { A `const` record param is passed by reference (like FPC). Passing it by
        value truncates to a single qword, dropping all but the first field. }
      if isConst and ((tk = tyRecord) or (tk = tyVariant)) and not isArr then
        isByRef := True;
      for i := startIdx to nparams-1 do
      begin
        ptypes[i] := tk;
        puntyped[i] := isUntyped;
        ptypesRec[i] := LastTypeRecId;
        ptypesPtrElemTk[i] := LastTypePointerElemTk;
        ptypesPtrElemRec[i] := LastTypePointerElemRec;
        ptypesProcSig[i] := LastTypeProcSig;
        parr[i] := isArr;
        pbyref[i] := isByRef;
        pconst[i] := isConst;
        pdefault[i] := hasDefault;
        pdefaultval[i] := defaultVal;
        pNDims[i] := paramNDims;
        pDynDepth[i] := paramDynDepth;
        for pdi := 0 to paramNDims - 1 do
        begin
          pDimLo[i * MAX_ARR_DIMS + pdi]   := psLo[pdi];
          pDimSpan[i * MAX_ARR_DIMS + pdi] := psSpan[pdi];
        end;
      end;
      if not Eat(tkSemicolon) then doneArgs := True;
    end;
    Expect(tkRParen, ')');
  end;

  if isFunc then
  begin
    Expect(tkColon, ':');
    if CurTok.Kind = tkArray then
    begin
      { `array of T` result: a pointer-sized dynamic-array handle. retType holds
        the element type so the result is non-aggregate; the dyn-array nature is
        tracked separately in ProcRetIsDynArray. }
      Next;
      Expect(tkOf, 'of');
      retType := ParseTypeKind;
      retIsDynArr := True;
      retElemTk := retType;
      retElemRec := LastTypeRecId;
    end
    else if (CurTok.Kind = tkIdent) and (FindArrayType(CurTok.SVal) >= 0) and
            ArrTypeIsDyn[FindArrayType(CurTok.SVal)] then
    begin
      { Named dynamic-array type alias as the result (e.g. TByteArray =
        array of Byte): same handle ABI as a literal `array of T` result, so
        Result is a resizable dyn-array local (SetLength/indexing work). }
      paramAi := FindArrayType(CurTok.SVal);
      retType := ParseTypeKind;            { consume the alias name }
      retIsDynArr := True;
      retElemTk := IntToTypeKind(ArrTypeElemTk[paramAi]);
      retElemRec := ArrTypeElemRec[paramAi];
    end
    else
    begin
      retType := ParseTypeKind;
      if (retType = tyRecord) or (retType = tyClass) then
        retRecId := LastTypeRecId;
      if retType = tyPointer then
      begin
        retPtrElemTk := Ord(LastTypePointerElemTk);
        retPtrElemRec := LastTypePointerElemRec;
      end;
    end;
  end;

  Eat(tkSemicolon);
  declOverload := False;
  declFlexColumn := False;
  declInline := False;
  while ((CurTok.Kind = tkIdent) and
         ((CurTok.SVal = 'inline') or (CurTok.SVal = 'Inline') or (CurTok.SVal = 'INLINE') or
          (CurTok.SVal = 'register') or (CurTok.SVal = 'Register') or (CurTok.SVal = 'REGISTER') or
          (CurTok.SVal = 'cdecl') or (CurTok.SVal = 'Cdecl') or (CurTok.SVal = 'CDECL') or
          CaseEqual(CurTok.SVal, 'assembler') or
          CaseEqual(CurTok.SVal, 'generator') or
          CaseEqual(CurTok.SVal, 'async') or
          CaseEqual(CurTok.SVal, 'stackful') or
          CaseEqual(CurTok.SVal, 'stackless') or
          CaseEqual(CurTok.SVal, 'iram') or
          CaseEqual(CurTok.SVal, 'interrupt') or
          CaseEqual(CurTok.SVal, 'flexcolumn') or
          CaseEqual(CurTok.SVal, 'static') or
          CaseEqual(CurTok.SVal, 'reintroduce') or
          CaseEqual(CurTok.SVal, 'deprecated') or
          CaseEqual(CurTok.SVal, 'platform') or
          CaseEqual(CurTok.SVal, 'experimental') or
          CaseEqual(CurTok.SVal, 'unimplemented') or
          CaseEqual(CurTok.SVal, 'library'))) or
        (CurTok.Kind = tkOverload) do
  begin
    if CurTok.Kind = tkOverload then declOverload := True;
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'flexcolumn') then declFlexColumn := True;
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'assembler') then isAsmFunc := True;
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'generator') then isGenerator := True;
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'async') then isAsync := True;
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'stackless') then isStackless := True;
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'inline') then declInline := True;
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'iram') then isIram := True;
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'interrupt') then
    begin
      isInterrupt := True;
      isIram := True;   { interrupt handlers must also be IRAM-resident }
    end;
    { Hint directives (deprecated ['msg']/platform/experimental/…) are
      parse-and-ignore, like a routine modifier. `deprecated` takes an optional
      message string. `stackful` is the default strategy: accept as a no-op. }
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'deprecated') and
       (Tokens[TokPos].Kind = tkString) then
      Next;   { consume 'deprecated'; the message string is eaten by the Next below }
    Next;
    Eat(tkSemicolon);
  end;
  if isGenerator and not isFunc then
    Error('generator must be a function (its result type is the yielded element type)');
  if isGenerator and isAsmFunc then
    Error('a routine cannot be both generator and assembler');
  if isAsync and isGenerator then
    Error('a routine cannot be both async and generator');
  if isAsync and isAsmFunc then
    Error('a routine cannot be both async and assembler');
  { `stackless` selects the state-machine backend; valid after `generator` or
    `async`, meaningless on its own. }
  if isStackless and not (isGenerator or isAsync) then
    Error('stackless directive is only valid on a generator or async routine');

  { Lambda-lift: a nested routine lifted to top level (matched by its mangled
    name) gains its captured enclosing state as trailing params here, with type
    metadata snapshotted at the capture site — no synthetic type tokens needed.
    Runs for both the forward decl and the real definition (both pass through
    here with the same mangled name), so their signatures match. }
  liftIdx := FindLiftDesc(name);
  if liftIdx >= 0 then
  begin
    if LiftNeedSelf[liftIdx] then
    begin
      if nparams >= 16 then Error('nested routine: too many params after capture');
      pnames[nparams] := '__nestself';
      ptypes[nparams] := tyClass;
      ptypesRec[nparams] := REC_UCLASS_BASE + LiftSelfCi[liftIdx];
      ptypesPtrElemTk[nparams] := tyUnknown; ptypesPtrElemRec[nparams] := REC_NONE;
      ptypesProcSig[nparams] := -1;
      parr[nparams] := False; pbyref[nparams] := False; pconst[nparams] := False;
      pNDims[nparams] := 0; pDynDepth[nparams] := 0;
      Inc(nparams);
    end;
    lcb := LiftCapStart[liftIdx];
    for i := 0 to LiftCapCount[liftIdx] - 1 do
    begin
      if nparams >= 16 then Error('nested routine: too many params after capture');
      pnames[nparams] := LiftCapName[lcb + i];
      ptypes[nparams] := LiftCapTk[lcb + i];
      ptypesRec[nparams] := LiftCapRec[lcb + i];
      ptypesPtrElemTk[nparams] := LiftCapPtrTk[lcb + i];
      ptypesPtrElemRec[nparams] := LiftCapPtrRec[lcb + i];
      ptypesProcSig[nparams] := LiftCapProcSig[lcb + i];
      parr[nparams] := LiftCapArr[lcb + i];
      pbyref[nparams] := True;            { captured by reference }
      pconst[nparams] := False;
      pNDims[nparams] := 0;
      pDynDepth[nparams] := LiftCapDyn[lcb + i];
      Inc(nparams);
    end;
  end;

  { External binding: `procedure foo(...); cdecl; external 'libname.so' [name 'sym'];`
    Marks the routine as a dynamically-linked import. Symbol defaults to the
    routine's own name (GTK symbols are valid lowercase identifiers); an
    optional `name 'sym'` clause overrides the emitted symbol. }
  if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'external') then
  begin
    Next;
    extLib := '';
    extSym := '';
    if CurTok.Kind = tkString then begin extLib := CurTok.SVal; Next; end;
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'name') then
    begin
      Next;
      { `name 'sym'` sets the LINK symbol, NOT the Pascal routine identifier — the
        routine stays callable by its declared name (e.g. `c_dlopen ... name
        'dlopen'`). Previously this overwrote `name`, registering the proc under
        the link symbol and leaving the Pascal name undefined. }
      if CurTok.Kind = tkString then begin extSym := CurTok.SVal; Next; end;
    end;
    Eat(tkSemicolon);
    procIdx := FindProcOverloadRec(name, nparams, ptypes, ptypesRec, parr, pbyref);
    if procIdx < 0 then
      procIdx := RegisterProc(name, isFunc, retType, nparams, pnames, ptypes);
    ProcRetRecId[procIdx] := retRecId;
    for i := 0 to nparams-1 do
    begin
      Procs[procIdx].Params[i].IsArray := parr[i];
      Procs[procIdx].Params[i].IsRef := pbyref[i];
      if (i < MAX_PROC_PARAMS) and ((ptypes[i] = tyClass) or (ptypes[i] = tyRecord)) then
        ProcParamRecId[procIdx * MAX_PROC_PARAMS + i] := ptypesRec[i];
    end;
    Procs[procIdx].BodyAddr := -1;
    ProcExternal[procIdx] := True;
    if declFlexColumn then ProcFlexColumn[procIdx] := True;
    ProcLibrary[procIdx] := InternStr(extLib);
    if extSym <> '' then ProcExtName[procIdx] := InternStr(extSym);
    Exit;
  end;

  { Inject implicit Self parameter at index 0 for methods (unless static) }
  isStaticMethod := False;
  if methOwnerCi >= 0 then
  begin
    { overloads: match by the impl's explicit param count, not first-name }
    mmi := FindUMethArity(methOwnerCi, methName, nparams);
    if mmi >= 0 then
      if UMthIsStatic[mmi] then
        isStaticMethod := True;
  end;

  if (methOwnerCi >= 0) and not isStaticMethod then
  begin
    for i := nparams downto 1 do
    begin
      pnames[i] := pnames[i-1];
      ptypes[i] := ptypes[i-1];
      ptypesRec[i] := ptypesRec[i-1];
      ptypesPtrElemTk[i] := ptypesPtrElemTk[i-1];
      ptypesPtrElemRec[i] := ptypesPtrElemRec[i-1];
      ptypesProcSig[i] := ptypesProcSig[i-1];
      parr[i]   := parr[i-1];
      pbyref[i] := pbyref[i-1];
      pNDims[i] := pNDims[i-1];
      pDynDepth[i] := pDynDepth[i-1];
      for pdi := 0 to MAX_ARR_DIMS - 1 do
      begin
        pDimLo[i * MAX_ARR_DIMS + pdi]   := pDimLo[(i-1) * MAX_ARR_DIMS + pdi];
        pDimSpan[i * MAX_ARR_DIMS + pdi] := pDimSpan[(i-1) * MAX_ARR_DIMS + pdi];
      end;
    end;
    pnames[0] := 'Self';
    ptypes[0] := tyClass;
    ptypesRec[0] := REC_NONE;   { Self's RecName is wired to the owner class below }
    ptypesPtrElemTk[0] := tyUnknown;
    ptypesPtrElemRec[0] := REC_NONE;
    ptypesProcSig[0] := -1;
    parr[0]   := False;
    pbyref[0] := False;
    pNDims[0] := 0;
    pDynDepth[0] := 0;
    nparams := nparams + 1;
  end;

  { Stackless generator: rewrite the ABI to `function(__genself: Pointer): Boolean`.
    The declared params/result describe the produced SEQUENCE; the step function
    itself takes the heap-instance pointer and returns has-next. Declared params
    shift to 1..n and become persistent locals (restored from the instance each
    step); the declared (yielded) element type is remembered for for-in loop-var
    typing. }
  if isStackless then
  begin
    if methOwnerCi >= 0 then
      Error('stackless generator/async methods are not supported (v1)');
    if isAsync then
    begin
      { async stackless takes no declared params in v1 (the coroutine carries its
        own state in persistent locals); the spawn surface allocs the instance. }
      if nparams > 0 then
        Error('async stackless: parameters are not supported in v1');
      isFunc := True;     { a procedure becomes the function(self): Boolean step }
    end;
    declElemTk := Ord(retType);
    for i := nparams downto 1 do
    begin
      pnames[i] := pnames[i-1];
      ptypes[i] := ptypes[i-1];
      ptypesRec[i] := ptypesRec[i-1];
      ptypesPtrElemTk[i] := ptypesPtrElemTk[i-1];
      ptypesPtrElemRec[i] := ptypesPtrElemRec[i-1];
      ptypesProcSig[i] := ptypesProcSig[i-1];
      parr[i]   := parr[i-1];
      pbyref[i] := pbyref[i-1];
      pNDims[i] := pNDims[i-1];
      pDynDepth[i] := pDynDepth[i-1];
      for pdi := 0 to MAX_ARR_DIMS - 1 do
      begin
        pDimLo[i * MAX_ARR_DIMS + pdi]   := pDimLo[(i-1) * MAX_ARR_DIMS + pdi];
        pDimSpan[i * MAX_ARR_DIMS + pdi] := pDimSpan[(i-1) * MAX_ARR_DIMS + pdi];
      end;
    end;
    pnames[0] := '__genself';
    ptypes[0] := tyPointer;
    ptypesRec[0] := REC_NONE;
    ptypesPtrElemTk[0] := tyUnknown;
    ptypesPtrElemRec[0] := REC_NONE;
    ptypesProcSig[0] := -1;
    parr[0]   := False;
    pbyref[0] := False;
    pNDims[0] := 0;
    pDynDepth[0] := 0;
    nparams := nparams + 1;
    retType := tyBoolean;
  end;

  if CaseEqual(name, 'LoadFile') then
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

  { Forward / interface declaration, or the declaration pre-scan pass. In all
    three cases the routine's signature is registered without emitting a body.
    During the pre-scan (PreScanPass) the body tokens are then skipped so the
    top-level walk continues; a method (methOwnerCi >= 0) is left to the body
    pass — it resolves through its class method table, not by name. }
  if (CurTok.Kind = tkForward) or InInterface or PreScanPass then
  begin
    preScanBody := PreScanPass and (CurTok.Kind <> tkForward);
    if CurTok.Kind = tkForward then
    begin
      Next; Eat(tkSemicolon);
    end;
    if (not PreScanPass) or (methOwnerCi < 0) then
    begin
      procIdx := FindProcOverloadRec(name, nparams, ptypes, ptypesRec, parr, pbyref);
      if procIdx < 0 then
      begin
        if StrictOverload and (FindProc(name) >= 0) then
        begin
          if not declOverload then Error('overloaded routine requires overload directive');
          if HasNonOverloadProc(name) then Error('all overloaded routines require overload directive');
        end;
        procIdx := RegisterProc(name, isFunc, retType, nparams, pnames, ptypes);
        ProcRetRecId[procIdx] := retRecId;
        ProcOverloadDirective[procIdx] := declOverload;
        Procs[procIdx].BodyAddr := -1;
        for i := 0 to nparams-1 do
        begin
          Procs[procIdx].Params[i].IsArray := parr[i];
          Procs[procIdx].Params[i].IsRef := pbyref[i];
          { Persist the param metadata the call-site lowering reads, so a call made
            BEFORE the body is parsed (e.g. a lifted nested routine, whose
            definition is deferred to top level) lowers identically to one after.
            Without ProcParamDynDepth a `var dyn-array` arg passes the handle value
            instead of &slot → SetLength corrupts memory. }
          if i < MAX_PROC_PARAMS then
          begin
            if pDynDepth[i] > 0 then ProcParamDynDepth[procIdx * MAX_PROC_PARAMS + i] := pDynDepth[i];
            ProcParamIsConst[procIdx * MAX_PROC_PARAMS + i] := pconst[i];
            ProcParamExplicitByRef[procIdx * MAX_PROC_PARAMS + i] := pbyref[i];
            ProcParamUntyped[procIdx * MAX_PROC_PARAMS + i] := puntyped[i];
            ProcParamHasDefault[procIdx * MAX_PROC_PARAMS + i] := pdefault[i];
            ProcParamDefaultVal[procIdx * MAX_PROC_PARAMS + i] := pdefaultval[i];
            if (ptypes[i] = tyClass) or (ptypes[i] = tyRecord) then
              ProcParamRecId[procIdx * MAX_PROC_PARAMS + i] := ptypesRec[i];
          end;
        end;
      end
      else if declOverload then
        ProcOverloadDirective[procIdx] := True;
      if declFlexColumn then ProcFlexColumn[procIdx] := True;
      ProcRetRecId[procIdx] := retRecId;
      ProcRetIsDynArray[procIdx] := retIsDynArr;
      ProcRetElemTk[procIdx] := retElemTk;
      ProcRetElemRec[procIdx] := retElemRec;
      ProcRetPtrElemTk[procIdx] := retPtrElemTk;
      ProcRetPtrElemRec[procIdx] := retPtrElemRec;
      if retIsDynArr then Procs[procIdx].RetType := tyPointer; { 8-byte heap handle ABI }
    end;
    if preScanBody then PreScanSkipRoutineBody;
    Exit;
  end;

  { Register or resolve }
  procIdx := FindProcOverloadRec(name, nparams, ptypes, ptypesRec, parr, pbyref);
  if procIdx < 0 then
  begin
    if StrictOverload and (FindProc(name) >= 0) then
    begin
      if not declOverload then Error('overloaded routine requires overload directive');
      if HasNonOverloadProc(name) then Error('all overloaded routines require overload directive');
    end;
    procIdx := RegisterProc(name, isFunc, retType, nparams, pnames, ptypes);
    ProcOverloadDirective[procIdx] := declOverload;
  end
  else if declOverload then
    ProcOverloadDirective[procIdx] := True;
  if declFlexColumn then ProcFlexColumn[procIdx] := True;
  ProcRetRecId[procIdx] := retRecId;
  ProcRetIsDynArray[procIdx] := retIsDynArr;
  ProcRetElemTk[procIdx] := retElemTk;
  ProcRetElemRec[procIdx] := retElemRec;
  ProcRetPtrElemTk[procIdx] := retPtrElemTk;
  ProcRetPtrElemRec[procIdx] := retPtrElemRec;
  ProcIsAsync[procIdx] := isAsync;
  ProcIsGenerator[procIdx] := isGenerator;
  ProcIsStackless[procIdx] := isStackless;
  if isInterrupt and (TargetArch <> TARGET_RISCV32) and (TargetArch <> TARGET_XTENSA) then
    Error('interrupt directive: raw hardware-vector codegen implemented for riscv32 (esp32c3) and xtensa Call0 (esp32s3) only. Use `iram;` for an IDF-registered ISR.');
  if isInterrupt and (TargetArch = TARGET_XTENSA) and (XtensaABI = XTENSA_ABI_WINDOWED) then
    Error('interrupt directive on xtensa requires Call0 (build with --xtensa-abi=call0, or --esp-profile=bare). A windowed raw-vector ISR is out of scope by design: bare-metal cannot boot windowed, and under IDF you do not install a raw vector -- register a normal callback via esp_intr_alloc and mark it `iram;` (FreeRTOS spills the windows for you). See devdocs/progress/done/feature-esp32-isr-iram.');
  { `iram;` places the body in .iram1.text on ESP; on other targets (e.g. the
    x86-64 oracle build of a shared test) it is an accepted no-op. }
  ProcIram[procIdx] := isIram and ((TargetArch = TARGET_XTENSA) or (TargetArch = TARGET_RISCV32));
  ProcIsInterrupt[procIdx] := isInterrupt;
  if isStackless then
  begin
    ProcGenElemTk[procIdx] := IntToTypeKind(declElemTk);
    if IntToTypeKind(declElemTk) = tyRecord then
      ProcGenElemRec[procIdx] := retRecId
    else
      ProcGenElemRec[procIdx] := REC_NONE;
    ProcGenParamCnt[procIdx] := nparams - 1;   { exclude the injected __genself }
    if (nparams - 1) > CO_MAX_PARAMS then
      Error('generator: at most 4 parameters in v1');
  end
  else if isGenerator and (nparams > CO_MAX_PARAMS) then
    Error('generator: at most 4 parameters in v1');
  if retIsDynArr then Procs[procIdx].RetType := tyPointer; { 8-byte heap handle ABI }
  if TargetArch = TARGET_XTENSA then
    while (CodeLen mod 4) <> 0 do xtensa_nop; { CALL0 targets must be 4-aligned }
  Procs[procIdx].BodyAddr := CodeLen;
  if DebugTrace then writeln('PROC ', Procs[procIdx].Name, ' @', CodeLen);
  for i := 0 to nparams-1 do
  begin
    Procs[procIdx].Params[i].IsArray := parr[i];
    Procs[procIdx].Params[i].IsRef := pbyref[i];
  end;

  { Save scope }
  savedSC := SymCount;
  savedFS := FrameSize;
  LocalInitCount := 0;   { routine-local typed-const initializers, flushed in the prologue }
  savedGLC := GotoLabelCount;
  savedGFC := GotoFixupCount;
  savedProcCleanupFrameActive := ProcExceptionCleanupFrameActive;
  ProcExceptionCleanupFrameActive := False;
  GotoLabelCount := 0;
  GotoFixupCount := 0;
  for j := 0 to MAX_GOTO_LABELS - 1 do GotoLabelIRId[j] := -1;
  FrameSize := 0;
  CurProc := procIdx;
  if declInline then ProcInline[procIdx] := True;
  { Decl-order gating: this body may only see globals declared before its header
    (TokPos is now in this routine's header). FindSym hides later globals. We key
    on the header token's SOffset (its immutable char-pool position, monotonic in
    lex/source order) rather than the token INDEX: pass-2 nested-routine excisions
    and generic inserts renumber token indices (and shift the DeclItem spans that
    drive this TokPos) but never move a token's SOffset, so a token-index horizon
    drifted out of sync with the globals' recorded positions and falsely hid a
    top-of-file global in a late include (bug-impl-prescan-late-include-var-section).
    SOffset is stable under those edits, so decl-order stays correct with no
    per-edit fixups. }
  savedVisVarSeq := CurBodyHdrTok;
  if TokPos < TokCount then CurBodyHdrTok := Tokens[TokPos].SOffset
  else CurBodyHdrTok := $7FFFFFFF;
  Procs[procIdx].ScopeBase := SymCount;

  { Set method context before allocating params }
  if methOwnerCi >= 0 then
  begin
    { overloads: bind THIS signature's entry (the decl registered one proc per
      signature), falling back to the name match for a not-yet-declared method }
    mmi := FindUMethByProc(methOwnerCi, procIdx);
    if mmi < 0 then mmi := FindUMeth(methOwnerCi, methName);
    if mmi >= 0 then
    begin
      UMthProc_[mmi] := procIdx;
    end
    else
    begin
      AddUMeth(methOwnerCi, methSNOff, methSNLen, procIdx);
      mmi := UMthCount - 1;
    end;

    if not UMthIsStatic[mmi] then
      CurSelfClass := methOwnerRec;

    if UMthVirSlot[mmi] >= 0 then
    begin
      slot := UMthVirSlot[mmi];
      if MethodFixCount >= MAX_METHFIX then Error('too many virtual method fixups');
      MethodFixups[MethodFixCount].DataPos := UClsVMTOffset[methOwnerCi] + slot * 8;
      MethodFixups[MethodFixCount].ProcIdx := procIdx;
      Inc(MethodFixCount);

      for otherCi := 0 to UClsCount-1 do
      begin
        if IsSubclassOf(otherCi, methOwnerCi) then
        begin
          if MethodFixCount >= MAX_METHFIX then Error('too many virtual method fixups');
          MethodFixups[MethodFixCount].DataPos := UClsVMTOffset[otherCi] + slot * 8;
          MethodFixups[MethodFixCount].ProcIdx := procIdx;
          Inc(MethodFixCount);
        end;
      end;
    end;
  end;

  { Allocate param slots }
  for i := 0 to nparams-1 do
  begin
    idx := AllocParam(pnames[i], ptypes[i], pbyref[i], parr[i]);
    Procs[procIdx].Params[i].SymIdx := idx;
    if (procIdx >= 0) and (i < MAX_PROC_PARAMS) then ProcParamIsConst[procIdx * MAX_PROC_PARAMS + i] := pconst[i];
    if (procIdx >= 0) and (i < MAX_PROC_PARAMS) then ProcParamExplicitByRef[procIdx * MAX_PROC_PARAMS + i] := pbyref[i];
    if (procIdx >= 0) and (i < MAX_PROC_PARAMS) then ProcParamUntyped[procIdx * MAX_PROC_PARAMS + i] := puntyped[i];
    { Write-only-true: a method/forward body that repeats params WITHOUT the
      defaults (FPC style — defaults live in the class/interface decl) must not
      clear the decl's ProcParamHasDefault. RegisterProc initializes False. }
    if (procIdx >= 0) and (i < MAX_PROC_PARAMS) and pdefault[i] then ProcParamHasDefault[procIdx * MAX_PROC_PARAMS + i] := True;
    if (procIdx >= 0) and (i < MAX_PROC_PARAMS) and pdefault[i] then ProcParamDefaultVal[procIdx * MAX_PROC_PARAMS + i] := pdefaultval[i];
    if pDynDepth[i] > 0 then
    begin
      { Named dynamic-array type param: a real dynamic array, NOT an open-array
        fat ptr. ArrLen = -1 routes SetLength to -102; SymDynDepth drives nested
        element typing. When var/out, the slot will hold &caller_slot (see the
        call-site lowering + the IsRef read-deref). }
      Syms[idx].ArrLen := -1;
      SymDynDepth[idx] := pDynDepth[i];
      if (procIdx >= 0) and (i < MAX_PROC_PARAMS) then ProcParamDynDepth[procIdx * MAX_PROC_PARAMS + i] := pDynDepth[i];
    end;
    if pNDims[i] >= 2 then
    begin
      SymArrNDims[idx] := pNDims[i];
      for pdi := 0 to pNDims[i] - 1 do
      begin
        SymArrDimLo[idx * MAX_ARR_DIMS + pdi]   := pDimLo[i * MAX_ARR_DIMS + pdi];
        SymArrDimSpan[idx * MAX_ARR_DIMS + pdi] := pDimSpan[i * MAX_ARR_DIMS + pdi];
      end;
    end;
    if parr[i] and (ptypes[i] = tyRecord) then
    begin
      { Open array of records (e.g. `array of const`): the slot holds a dyn-array
        data pointer; element type/record live in ElemType/ElemRecName, not a
        by-value RecName, and it must NOT be promoted to by-ref. }
      Syms[idx].ElemType := tyRecord;
      Syms[idx].ElemRecName := ptypesRec[i];
    end
    else if (ptypes[i] = tyClass) or (ptypes[i] = tyRecord) then
    begin
      Syms[idx].RecName := ptypesRec[i];
      { Persist the param's rec id: param sym slots are reused across procs, so
        overload matching / call-arg coercion cannot read it back from the sym. }
      if (procIdx >= 0) and (i < MAX_PROC_PARAMS) then ProcParamRecId[procIdx * MAX_PROC_PARAMS + i] := ptypesRec[i];
      { Records larger than a qword are passed by reference. A CORBA interface is
        a fat pointer ({IMT, instance}); on 64-bit that is 16 bytes (already >8),
        but on 32-bit targets it is only 8 bytes — force by-ref there too so the
        whole fat pointer crosses the call uniformly instead of being squeezed
        into one machine word. (No-op on 64-bit, so self-host stays identical.) }
      if (ptypes[i] = tyRecord) and
         ((RecSize(ptypesRec[i]) > 8) or
          ((ptypesRec[i] >= REC_UCLASS_BASE) and UClsIsInterface[ptypesRec[i] - REC_UCLASS_BASE])) then
      begin
        Syms[idx].IsRef := True;
        Procs[procIdx].Params[i].IsRef := True;
      end;
    end;
    if ptypes[i] = tyPointer then
    begin
      Syms[idx].PtrElemTk := ptypesPtrElemTk[i];
      Syms[idx].PtrElemRec := ptypesPtrElemRec[i];
      SymProcSig[idx] := ptypesProcSig[i];
    end
    else if (ptypes[i] = tyRecord) and (ptypesProcSig[i] >= 0) then
      { method-pointer param ({Code,Data} record, `of object` type): callable —
        Compare(a, b) inside the body must see the signature (fgl QuickSort) }
      SymProcSig[idx] := ptypesProcSig[i];
  end;
  { Wire Self's RecName so field lookups resolve against the owner class }
  if (methOwnerCi >= 0) and not isStaticMethod then
    Syms[Procs[procIdx].Params[0].SymIdx].RecName := methOwnerRec;

  { Return value slot }
  if isFunc then
  begin
    savedLastTypeRecId := LastTypeRecId;
    if retType = tyRecord then
      LastTypeRecId := ProcRetRecId[procIdx];
    if retIsDynArr then
    begin
      { Result is a dynamic array: a pointer-sized local heap handle. Indexing,
        Length, and SetLength operate on it like any dyn-array local. }
      LastTypeRecId := retElemRec;
      idx := AllocDynArray('Result', retElemTk, 1);
      Procs[procIdx].RetSymIdx := idx;
    end
    else if retType = tyString then
    begin
      { Frozen-string Result is a routine LOCAL (was a shared BSS global — not
        reentrant, bug-frozen-string-result-global). Returns via the hidden
        caller-destination ABI like records. Capacity LOCAL_STR_CAP (ShortString). }
      AllocVar('Result', retType);
      Procs[procIdx].RetSymIdx := SymCount - 1;
    end
    else
    begin
      AllocVar('Result', retType);
      Procs[procIdx].RetSymIdx := SymCount - 1;
      Syms[SymCount-1].Kind := skLocal;
    end;
    LastTypeRecId := savedLastTypeRecId;
    if not retIsDynArr and RetViaHiddenDest(retType) then
    begin
      idx := AllocVar('', tyPointer);
      ProcAggregateDestSym[procIdx] := idx;
    end;
  end;

  { Generator body context: a `; generator;` routine is compiled as a stackful
    coroutine body (see lib/rtl/coroutine.pas). Allocate a hidden self-pointer
    local; the body prologue copies the instance ptr (handed off in rbx by
    CoSwitch) into it, then loads params from the instance. yield/finish use it.
    Save/restore any enclosing generator context for nested routine defs. }
  savedGenIsGen := CurProcIsGenerator;
  savedGenSelf  := CurGenSelfSym;
  savedGenSeen  := CurGenSeenYield;
  savedGenTry   := GenTryDepth;
  savedGenStackless := CurProcIsStackless;
  savedGenStateCtr  := CurGenStateCtr;
  savedGenSlotNext  := CurGenSlotNext;
  savedProcIsAsync  := CurProcIsAsync;
  CurProcIsAsync := isAsync;
  CurProcIsGenerator := isGenerator;
  CurProcIsStackless := isStackless;
  CurGenSelfSym := -1;
  CurGenSeenYield := False;
  GenTryDepth := 0;
  if isGenerator and not isStackless then
  begin
    { Stackful lowering: the body runs on a heap coroutine stack, swapped in by
      CoSwitch (x86-64 asm). The instance pointer arrives in the rbx slot. }
    if TargetArch <> TARGET_X86_64 then
      Error('generator: only the x86-64 target is supported for the stackful backend (use `stackless` for other targets)');
    EnableCoroutineRuntime;
    genSelfIdx := AllocVar('', tyPointer);   { hidden self pointer }
    CurGenSelfSym := genSelfIdx;
  end;

  { Prologue }
  patchPos := EmitProcPrologue;
  Procs[procIdx].FramePatch := patchPos;
  EmitAggregateDestStash(procIdx);

  if TargetArch = TARGET_I386 then
  begin
    { i386 internal convention: the caller evaluated and pushed args left to
      right (leftmost ends up deepest), so param i of n sits at
      [ebp + 8 + (n-1-i)*4]. Copy each into its frame slot; the caller cleans
      the arg area after the call. Ordinal by-value params only for now. }
    for i := 0 to nparams-1 do
    begin
      idx := Procs[procIdx].Params[i].SymIdx;
      { Ordinals and pointer-sized handles (pointer/string/class) are passed as
        one 4-byte stack slot. 8-byte ordinals (Int64) use the low dword only,
        consistent with the rest of the i386 backend's fat-slot model. }
      { A by-ref param (var/const aggregate) is a pointer-sized handle whatever
        its declared type, and the caller pushes the argument's address; the
        4-byte copy below moves that pointer into the slot. tyVariant is passed
        the same way (pointer to the 16-byte value). By-value set params are
        copied as their full 32-byte value. Reject remaining true aggregate
        payloads such as records. }
      if (not Syms[idx].IsRef) and (not Syms[idx].IsArray) and
         not (TypeIsOrdinal(Syms[idx].TypeKind) or
              TypeIsFloat(Syms[idx].TypeKind) or
              (Syms[idx].TypeKind in [tyString, tyAnsiString, tyPointer, tyClass, tyVariant, tySet])) then
        Error('target i386: only ordinal/pointer parameters supported yet');
      sz := 0;
      for j := i + 1 to nparams - 1 do
      begin
        if parr[j] then
        begin
          { Open-array param stack width must match how the caller pushes the
            argument (the i386 caller dispatches on the param's element type, so
            `ptypes[j]` here is the element type). A 64-bit element (Int64/UInt64/
            Double) goes through the 8-byte push path; `array of const` (a single
            dyn-array handle) and 32-bit-element open arrays are one 4-byte slot.
            NOTE: regular open arrays don't yet carry a real high word, so
            Length() over them is unreliable — tracked separately. }
          if (ptypes[j] = tyInt64) or (ptypes[j] = tyUInt64) or (ptypes[j] = tyDouble) then
            Inc(sz, 8)
          else
            Inc(sz, 4);
        end
        else if pbyref[j] or (ptypes[j] = tyString) or
           (ptypes[j] in [tyAnsiString, tyPointer, tyClass, tyVariant]) then
          Inc(sz, 4)
        else if ptypes[j] = tyDouble then
          Inc(sz, 8)
        else if ptypes[j] = tySingle then
          Inc(sz, 4)
        else if (ptypes[j] = tyInt64) or (ptypes[j] = tyUInt64) then
          Inc(sz, 8)                                 { 64-bit by-value param }
        else if ptypes[j] = tySet then
          Inc(sz, TypeSize(tySet))                    { 32-byte by-value set }
        else
          Inc(sz, 4);
      end;
      if (not Syms[idx].IsRef) and (not Syms[idx].IsArray) and
         (Syms[idx].TypeKind = tySet) then
      begin
        for j := 0 to (TypeSize(tySet) div 4) - 1 do
        begin
          EmitB($8B); EmitB($85); EmitI32(8 + sz + j * 4);      { mov eax, [ebp+disp] }
          EmitB($89); EmitB($85); EmitI32(Syms[idx].Offset + j * 4);
        end;
      end
      else if Syms[idx].TypeKind = tyDouble then
      begin
        EmitB($8B); EmitB($85); EmitI32(8 + sz);     { mov eax, [ebp+disp] }
        EmitB($89); EmitB($85); EmitI32(Syms[idx].Offset);
        EmitB($8B); EmitB($85); EmitI32(12 + sz);    { mov eax, [ebp+disp+4] }
        EmitB($89); EmitB($85); EmitI32(Syms[idx].Offset + 4);
      end
      else if (not Syms[idx].IsRef) and (not Syms[idx].IsArray) and
              ((Syms[idx].TypeKind = tyInt64) or (Syms[idx].TypeKind = tyUInt64)) then
      begin
        { Int64/UInt64 by-value param: the caller pushes both dwords (8-byte arg
          slot), so copy the full 64-bit value into the frame slot. }
        EmitB($8B); EmitB($85); EmitI32(8 + sz);     { mov eax, [ebp+disp] }
        EmitB($89); EmitB($85); EmitI32(Syms[idx].Offset);            { mov [off], eax }
        EmitB($8B); EmitB($85); EmitI32(12 + sz);    { mov eax, [ebp+disp+4] }
        EmitB($89); EmitB($85); EmitI32(Syms[idx].Offset + 4);        { mov [off+4], eax }
      end
      else
      begin
        EmitB($8B); EmitB($85); EmitI32(8 + sz);     { mov eax, [ebp+disp] }
        { Store at the param's type width: frame slots are packed by size, so a
          1-byte char/boolean sits adjacent to the next slot. A blanket 4-byte
          store would clobber that neighbour (e.g. a var-param pointer next to a
          Char arg). By-ref/array/handle params are always 4-byte. }
        if (not Syms[idx].IsRef) and (not Syms[idx].IsArray) and
           not (Syms[idx].TypeKind in [tyString, tyAnsiString, tyPointer, tyClass, tyVariant]) and
           (TypeSize(Syms[idx].TypeKind) = 1) then
          begin EmitB($88); EmitB($85); EmitI32(Syms[idx].Offset); end          { mov [ebp+off], al }
        else if (not Syms[idx].IsRef) and (not Syms[idx].IsArray) and
           not (Syms[idx].TypeKind in [tyString, tyAnsiString, tyPointer, tyClass, tyVariant]) and
           (TypeSize(Syms[idx].TypeKind) = 2) then
          begin EmitB($66); EmitB($89); EmitB($85); EmitI32(Syms[idx].Offset); end { mov [ebp+off], ax }
        else
          begin EmitB($89); EmitB($85); EmitI32(Syms[idx].Offset); end;          { mov [ebp+off], eax }
      end;
    end;
  end
  else if TargetArch = TARGET_AARCH64 then
  begin
    for i := 0 to nparams-1 do
    begin
      idx := Procs[procIdx].Params[i].SymIdx;
      sz := ParamSize(idx);
      if i < 8 then
      begin
        { Load local offset into x9 }
        EmitLoadImmA64(9, Syms[idx].Offset);
        { add x8, x29, x9 }
        EmitI32($8B0903A8);
        if (Syms[idx].TypeKind = tySingle) and
           (not Syms[idx].IsRef) and (not Syms[idx].IsArray) then
        begin
          { Single by-value: x[i] holds the value as DOUBLE bits (value model);
            narrow to single before the 4-byte slot store. }
          EmitI32($9E670000 + (i shl 5));  { fmov d0, x[i] }
          EmitI32($1E624000);              { fcvt s0, d0 }
          EmitI32($BD000100);              { str s0, [x8] }
        end
        { Store parameter register i (x0..x7) into [x8] }
        else if sz = 1 then
          EmitI32($39000100 + i)
        else if sz = 2 then
          EmitI32($79000100 + i)
        else if sz = 4 then
          EmitI32($B9000100 + i)
        else
          EmitI32($F9000100 + i);
      end
      else
      begin
        { Stack-passed param (AAPCS): the caller left args 8.. in an outgoing
          block; after the prologue `stp x29,x30,[sp,#-16]!` the incoming block
          sits at [x29 + 16 + (i-8)*8]. Copy it into this param's local slot. }
        EmitLoadImmA64(9, 16 + (i - 8) * 8);
        EmitI32($8B0903A8);              { add x8, x29, x9  -> &incoming arg }
        EmitI32($F9400109);              { ldr x9, [x8]     -> arg value }
        EmitLoadImmA64(10, Syms[idx].Offset);
        EmitI32($8B0A03A8);              { add x8, x29, x10 -> &local slot }
        if sz = 1 then
          EmitI32($39000109)            { strb w9, [x8] }
        else if sz = 2 then
          EmitI32($79000109)            { strh w9, [x8] }
        else if sz = 4 then
          EmitI32($B9000109)            { str w9, [x8] }
        else
          EmitI32($F9000109);           { str x9, [x8] }
      end;
    end;
  end
  else if TargetArch = TARGET_ARM32 then
  begin
    { Word-based spill: each scalar param is one machine word, an Int64/UInt64
      param is two (lo then hi). Word k arrives in r[k] when k<4, else on the
      stack at [fp + 8 + (pnWords-1-k)*4] (the caller pushed words in index
      order, leaving the lowest-index stack word at the highest address; see
      ir_codegen_arm32.inc IR_CALL). }
    { A by-ref or open-array Int64 param is a single pointer word, not a 64-bit
      value, so only count/spill it as two words when passed by value. A
      by-value record over 4 bytes (up to 8) is likewise two words -- mirrors
      the matching widening in ir_codegen_arm32.inc's IR_CALL arg-push loop
      (bug-arm32-record-byvalue-over-4-bytes-abi-gap); without it this loop
      counted such a param as one word while the caller (once fixed) pushes
      two, desyncing every later param's stack offset. }
    pnWords := 0;
    for i := 0 to nparams-1 do
      if ((Procs[procIdx].Params[i].TypeKind = tyInt64) or
          (Procs[procIdx].Params[i].TypeKind = tyUInt64) or
          (Procs[procIdx].Params[i].TypeKind = tyDouble) or
          (Procs[procIdx].Params[i].TypeKind = tyExtended)) and
         (not Procs[procIdx].Params[i].IsRef) and (not Procs[procIdx].Params[i].IsArray) then
        Inc(pnWords, 2)   { by-value 8-byte param (Int64/Double): two words }
      else if (Procs[procIdx].Params[i].TypeKind = tyRecord) and
              (not Procs[procIdx].Params[i].IsRef) and (not Procs[procIdx].Params[i].IsArray) and
              (i < MAX_PROC_PARAMS) and
              (RecSize(ProcParamRecId[procIdx * MAX_PROC_PARAMS + i]) > 4) and
              (RecSize(ProcParamRecId[procIdx * MAX_PROC_PARAMS + i]) <= 8) then
        Inc(pnWords, 2)   { by-value 5-8 byte record: two words }
      else Inc(pnWords, 1);
    pw := 0;
    for i := 0 to nparams-1 do
    begin
      idx := Procs[procIdx].Params[i].SymIdx;
      sz := ParamSize(idx);
      EmitLoadImmArm32(9, Syms[idx].Offset);
      EmitI32($E08B9009);   { add r9, fp, r9 (slot addr) }
      if (((Syms[idx].TypeKind = tyInt64) or (Syms[idx].TypeKind = tyUInt64) or
           (Syms[idx].TypeKind = tyDouble) or (Syms[idx].TypeKind = tyExtended)) and
          (not Syms[idx].IsRef) and (not Syms[idx].IsArray)) or
         ((Syms[idx].TypeKind = tyRecord) and not Syms[idx].IsRef and not Syms[idx].IsArray and
          (RecSize(Syms[idx].RecName) > 4) and (RecSize(Syms[idx].RecName) <= 8)) then
      begin
        { lo = word pw -> [r9]; hi = word pw+1 -> [r9, #4] }
        if pw < 4 then EmitI32($E5890000 or (pw shl 12))
        else begin EmitI32($E59B0000 or (8 + (pnWords-1-pw)*4)); EmitI32($E5890000); end;
        whi := pw + 1;
        if whi < 4 then EmitI32($E5890004 or (whi shl 12))
        else begin EmitI32($E59B0000 or (8 + (pnWords-1-whi)*4)); EmitI32($E5890004); end;
        Inc(pw, 2);
      end
      else
      begin
        if pw < 4 then
        begin
          if sz = 1 then EmitI32($E5C90000 or (pw shl 12))  { strb r[pw], [r9] }
          else if sz = 2 then EmitI32($E1C900B0 or (pw shl 12))
          else EmitI32($E5890000 or (pw shl 12));            { str r[pw], [r9] }
        end
        else
        begin
          EmitI32($E59B0000 or (8 + (pnWords - 1 - pw) * 4)); { ldr r0, [fp, #off] }
          if sz = 1 then EmitI32($E5C90000)
          else if sz = 2 then EmitI32($E1C900B0)
          else EmitI32($E5890000);
        end;
        Inc(pw, 1);
      end;
    end;
  end
  else if TargetArch = TARGET_RISCV32 then
  begin
    { RV32 word-based convention: args arrive in a0..a7 (word k in a[k]); each
      scalar param is one word, a by-value Int64/UInt64 is two (lo then hi).
      Words 8+ stay on the CALLER's stack (it keeps the whole pushed word
      block live across the call when the total exceeds 8): word k sits at
      [entry_sp + (pnWords-1-k)*4] = [s0 + 16 + (pnWords-1-k)*4] after the
      ra/s0 prologue. The call side (ir_codegen_riscv32.inc IR_CALL) pushes
      the matching layout. }
    pnWords := 0;
    for i := 0 to nparams-1 do
      if ((Procs[procIdx].Params[i].TypeKind = tyInt64) or
          (Procs[procIdx].Params[i].TypeKind = tyUInt64) or
          (Procs[procIdx].Params[i].TypeKind = tyDouble)) and
         (not Procs[procIdx].Params[i].IsRef) and (not Procs[procIdx].Params[i].IsArray) then
        Inc(pnWords, 2)
      else if (Procs[procIdx].Params[i].TypeKind = tySet) and
         (not Procs[procIdx].Params[i].IsRef) and (not Procs[procIdx].Params[i].IsArray) then
        Inc(pnWords, 8)   { by-value 32-byte set: 8 words inline (mirrors i386) }
      else
        Inc(pnWords, 1);
    pw := 0;
    for i := 0 to nparams-1 do
    begin
      idx := Procs[procIdx].Params[i].SymIdx;
      sz := ParamSize(idx);
      EmitLoadImmRISCV32(reg_t0, Syms[idx].Offset);
      rv32_add(reg_t0, reg_s0, reg_t0);
      if (Syms[idx].TypeKind = tySet) and
         (not Syms[idx].IsRef) and (not Syms[idx].IsArray) then
      begin
        { by-value set: rebuild all 8 words in the 32-byte param slot; word
          pw+w comes from a[pw+w] or, past a7, from the caller-kept stack
          block (same formula as the scalar stack-arg path). }
        for sz := 0 to 7 do
        begin
          if pw + sz < 8 then
            rv32_sw(reg_a0 + pw + sz, reg_t0, sz * 4)
          else
          begin
            rv32_lw(reg_t1, reg_s0, 16 + (pnWords - 1 - (pw + sz)) * 4);
            rv32_sw(reg_t1, reg_t0, sz * 4);
          end;
        end;
        Inc(pw, 8);
      end
      else if ((Syms[idx].TypeKind = tyInt64) or (Syms[idx].TypeKind = tyUInt64) or
          (Syms[idx].TypeKind = tyDouble)) and
         (not Syms[idx].IsRef) and (not Syms[idx].IsArray) then
      begin
        if pw < 8 then
          rv32_sw(reg_a0 + pw, reg_t0, 0)                       { lo (word pw) }
        else
        begin
          rv32_lw(reg_t1, reg_s0, 16 + (pnWords - 1 - pw) * 4);
          rv32_sw(reg_t1, reg_t0, 0);
        end;
        if pw + 1 < 8 then
          rv32_sw(reg_a0 + pw + 1, reg_t0, 4)                   { hi (word pw+1) }
        else
        begin
          rv32_lw(reg_t1, reg_s0, 16 + (pnWords - 1 - (pw + 1)) * 4);
          rv32_sw(reg_t1, reg_t0, 4);
        end;
        Inc(pw, 2);
      end
      else
      begin
        if pw < 8 then
        begin
          if sz = 1 then rv32_sb(reg_a0 + pw, reg_t0, 0)
          else if sz = 2 then rv32_sh(reg_a0 + pw, reg_t0, 0)
          else rv32_sw(reg_a0 + pw, reg_t0, 0);
        end
        else
        begin
          rv32_lw(reg_t1, reg_s0, 16 + (pnWords - 1 - pw) * 4);
          if sz = 1 then rv32_sb(reg_t1, reg_t0, 0)
          else if sz = 2 then rv32_sh(reg_t1, reg_t0, 0)
          else rv32_sw(reg_t1, reg_t0, 0);
        end;
        Inc(pw, 1);
      end;
    end;
  end
  else if TargetArch = TARGET_XTENSA then
  begin
    { Call0 ABI word-based convention: args arrive in a2..a7 (word k in a[2+k]);
      each scalar param is one word, a by-value Int64/UInt64 is two (lo then hi).
      The call side (ir_codegen_xtensa.inc IR_CALL) pushes the matching word
      layout. Up to 6 words total (no stack args yet). }
    pw := 0;
    for i := 0 to nparams-1 do
    begin
      idx := Procs[procIdx].Params[i].SymIdx;
      sz := ParamSize(idx);
      if pw >= 6 then
        Error('target xtensa: more than 6 parameter words not yet supported');
      if XtensaABI = XTENSA_ABI_WINDOWED then
      begin
        if (Syms[idx].Offset >= -128) and (Syms[idx].Offset <= 127) then
          xtensa_addi(reg_xtensa_a8, reg_xtensa_a15, Syms[idx].Offset)
        else
          Error('target xtensa windowed: parameter frame offset out of range');
      end
      else
        EmitFrameAddrXtensa(reg_xtensa_a8, Syms[idx].Offset);
      if ((Syms[idx].TypeKind = tyInt64) or (Syms[idx].TypeKind = tyUInt64) or
          (Syms[idx].TypeKind = tyDouble)) and
         (not Syms[idx].IsRef) and (not Syms[idx].IsArray) then
      begin
        xtensa_s32i(reg_xtensa_a2 + pw, reg_xtensa_a8, 0);     { lo (word pw) }
        if pw + 1 >= 6 then
          Error('target xtensa: more than 6 parameter words not yet supported');
        xtensa_s32i(reg_xtensa_a2 + pw + 1, reg_xtensa_a8, 4); { hi (word pw+1) }
        Inc(pw, 2);
      end
      else
      begin
        if sz = 1 then xtensa_s8i(reg_xtensa_a2 + pw, reg_xtensa_a8, 0)
        else if sz = 2 then xtensa_s16i(reg_xtensa_a2 + pw, reg_xtensa_a8, 0)
        else xtensa_s32i(reg_xtensa_a2 + pw, reg_xtensa_a8, 0);
        Inc(pw, 1);
      end;
    end;
    if XtensaABI = XTENSA_ABI_WINDOWED then
      xtensa_mov(reg_xtensa_a7, reg_xtensa_a15);
  end
  else
  if nparams > 6 then
  begin
    { All-stack internal convention for procs with more than 6 parameters
      (bug-many-param-call-corruption: the register convention silently
      shifted arguments). The caller pushed every arg left to right and
      cleans up after the call, so param i of n sits at
      [rbp + 16 + (n-1-i)*8]. Copy each into its frame slot. }
    for i := 0 to nparams-1 do
    begin
      idx := Procs[procIdx].Params[i].SymIdx;
      sz := ParamSize(idx);
      EmitB($48); EmitB($8B); EmitB($85);
      EmitI32(16 + (nparams - 1 - i) * 8);        { mov rax, [rbp+disp] }
      if (Syms[idx].TypeKind = tySingle) and
         (not Syms[idx].IsRef) and (not Syms[idx].IsArray) then
      begin
        { Single by-value: rax holds double bits; narrow to single before store. }
        EmitB($66); EmitB($48); EmitB($0F); EmitB($6E); EmitB($C0); { movq xmm0, rax }
        EmitB($F2); EmitB($0F); EmitB($5A); EmitB($C0);             { cvtsd2ss xmm0, xmm0 }
        EmitB($F3); EmitB($0F); EmitB($11); EmitB($85); EmitI32(Syms[idx].Offset); { movss [rbp+off], xmm0 }
        Continue;
      end;
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
    end;
  end
  else
  { Copy params from registers to stack: mov [rbp+off], rdi/rsi/rdx/rcx/r8/r9 }
  for i := 0 to nparams-1 do
  begin
    idx := Procs[procIdx].Params[i].SymIdx;
    sz := ParamSize(idx);
    if (Syms[idx].TypeKind = tySingle) and
       (not Syms[idx].IsRef) and (not Syms[idx].IsArray) then
    begin
      { Single by-value param: the arg register holds the value as DOUBLE bits
        (the IR float value model). Narrow to single before the 4-byte slot
        store, else the low dword of the double bits is garbage.
        LANDMINE — the tySingle narrow point is NOT uniform across targets: x86-64
        and aarch64 narrow HERE in the CALLEE prologue (caller pushes double bits
        in a GPR); i386 and arm32 narrow in the CALLER before the 4-byte push
        (ir_codegen386.inc / ir_codegen_arm32.inc). Looks innocent and local, but
        a float-ABI change must touch the matching site on every target — see
        devdocs/progress/done/feature-single-first-class.md. }
      case i of
        0: begin EmitB($48); EmitB($89); EmitB($F8); end; { mov rax, rdi }
        1: begin EmitB($48); EmitB($89); EmitB($F0); end; { mov rax, rsi }
        2: begin EmitB($48); EmitB($89); EmitB($D0); end; { mov rax, rdx }
        3: begin EmitB($48); EmitB($89); EmitB($C8); end; { mov rax, rcx }
        4: begin EmitB($4C); EmitB($89); EmitB($C0); end; { mov rax, r8 }
        5: begin EmitB($4C); EmitB($89); EmitB($C8); end; { mov rax, r9 }
      end;
      EmitB($66); EmitB($48); EmitB($0F); EmitB($6E); EmitB($C0); { movq xmm0, rax }
      EmitB($F2); EmitB($0F); EmitB($5A); EmitB($C0);             { cvtsd2ss xmm0, xmm0 }
      EmitB($F3); EmitB($0F); EmitB($11); EmitB($85); EmitI32(Syms[idx].Offset); { movss [rbp+off], xmm0 }
      Continue;
    end;
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

  { Optional var/const/type/label sections }
  while CurTok.Kind in [tkVar, tkConst, tkType, tkProcedure, tkFunction] do
    case CurTok.Kind of
      tkVar:   ParseVarSection;
      tkConst: ParseConstSection;
      tkType:  ParseTypeSection;
      tkProcedure, tkFunction: ParseNestedRoutine;
    end;
  { Managed locals (dynamic arrays, AnsiStrings, and records/arrays containing
    them) hold managed pointer slots. Zero their full extent before the body so
    a first SetLength / assignment sees nil rather than stale stack bytes — and
    so an ARC-correct whole-record copy can safely release the (nil) old fields. }
  for i := savedSC to SymCount - 1 do
    if Syms[i].Kind = skLocal then
    begin
      { Fixed array whose elements are dynamic-array handles (`array[..] of TA`):
        nil each pointer-sized slot so SetLength on an element does not release a
        garbage "old" handle. Done as a per-element loop of pointer-sized stores
        (not one multi-byte memset) so it works on every target — the cross
        backends reject the >pointer-sized managed-aggregate zero path. }
      if Syms[i].IsArray and (Syms[i].ArrLen <> -1) and (SymElemDynDepth[i] > 0) then
      begin
        for j := 0 to Syms[i].ArrLen - 1 do
        begin
          if TargetArch = TARGET_I386 then
          begin
            EmitB($C7); EmitB($85); EmitI32(Syms[i].Offset + j * TARGET_PTR_SIZE); EmitI32(0);
          end
          else if TargetArch = TARGET_ARM32 then
          begin
            EmitLoadImmArm32(9, Syms[i].Offset + j * TARGET_PTR_SIZE);
            EmitI32($E08B9009);                                          { add r9, fp, r9 }
            EmitI32($E3A00000);                                          { mov r0, #0 }
            EmitI32($E5890000);                                          { str r0, [r9] }
          end
          else if TargetArch = TARGET_AARCH64 then
          begin
            EmitLoadImmA64(9, Syms[i].Offset + j * TARGET_PTR_SIZE);
            EmitI32($8B0903A9);                                          { add x9, x29, x9 }
            EmitI32($F900013F);                                          { str xzr, [x9] }
          end
          else if TargetArch = TARGET_XTENSA then
          begin
            EmitFrameAddrXtensa(reg_xtensa_a8, Syms[i].Offset + j * TARGET_PTR_SIZE);
            xtensa_movi(reg_xtensa_a9, 0);
            xtensa_s32i(reg_xtensa_a9, reg_xtensa_a8, 0);
          end
          else if TargetArch = TARGET_RISCV32 then
          begin
            EmitLoadImmRISCV32(reg_t0, Syms[i].Offset + j * TARGET_PTR_SIZE);
            rv32_add(reg_t0, reg_s0, reg_t0);
            rv32_sw(reg_zero, reg_t0, 0);
          end
          else
          begin
            EmitB($48); EmitB($C7); EmitB($85); EmitI32(Syms[i].Offset + j * TARGET_PTR_SIZE); EmitI32(0);
          end;
        end;
        Continue;
      end;
      zeroBytes := 0;
      if Syms[i].IsArray and (Syms[i].ArrLen = -1) then
        zeroBytes := TARGET_PTR_SIZE                          { dyn-array handle }
      else if Syms[i].TypeKind = tyAnsiString then
      begin
        if Syms[i].IsArray then
          zeroBytes := Syms[i].ArrLen * TARGET_PTR_SIZE       { static array of AnsiString }
        else
          zeroBytes := TARGET_PTR_SIZE;                       { scalar AnsiString }
      end
      else if Syms[i].TypeKind = tyVariant then
        zeroBytes := TypeSize(tyVariant)
      else if (Syms[i].TypeKind = tyRecord) and not Syms[i].IsArray and
              RecordHasManagedFields(Syms[i].RecName) then
        zeroBytes := RecSize(Syms[i].RecName)
      else if (Syms[i].TypeKind = tyRecord) and Syms[i].IsArray and
              RecordHasManagedFields(Syms[i].ElemRecName) then
        zeroBytes := Syms[i].ArrLen * RecSize(Syms[i].ElemRecName)
      else if SymIsComInterface(i) then
        { COM/ARC interface fat pointer: must start nil so the ARC release at
          first overwrite / scope exit sees an empty slot, not stale stack bytes
          (a garbage IMT would dispatch _Release into nowhere). }
        zeroBytes := RecSize(Syms[i].RecName);
      { i386: only pointer-sized managed handles (scalar AnsiString / dyn-array)
        are supported; the larger managed aggregates (records/variants/arrays of
        managed) are not on this target yet. }
      if (zeroBytes > TARGET_PTR_SIZE) and (TargetArch = TARGET_ARM32) then
      begin
        { Zero the full extent of a managed-aggregate local (record with managed
          fields / variant / array of managed) so first use sees nil fields and
          an ARC-correct copy releases nil, not stale stack bytes. Byte loop. }
        EmitLoadImmArm32(0, Syms[i].Offset);
        EmitI32($E08B0000);                  { add r0, fp, r0 (dest) }
        EmitLoadImmArm32(1, zeroBytes);       { r1 = count }
        EmitI32($E3A02000);                  { mov r2, #0 }
        zfLoop := CodeLen;
        EmitI32($E3510000);                  { cmp r1, #0 }
        zfDone := CodeLen; EmitI32($0A000000); { beq done }
        EmitI32($E5C02000);                  { strb r2, [r0] }
        EmitI32($E2800001);                  { add r0, r0, #1 }
        EmitI32($E2411001);                  { sub r1, r1, #1 }
        EmitI32($EA000000 or ((((zfLoop - CodeLen) div 4) - 2) and $00ffffff)); { b loop }
        Patch32(zfDone, $0A000000 or ((((CodeLen - zfDone) div 4) - 2) and $00ffffff));
      end
      else if (zeroBytes > TARGET_PTR_SIZE) and (TargetArch = TARGET_AARCH64) then
      begin
        EmitLoadImmA64(9, Syms[i].Offset);
        EmitI32($8B0903A0);                  { add x0, x29, x9 (dest) }
        EmitLoadImmA64(1, zeroBytes);         { x1 = count }
        helperPi := FindProc('PXXMemZero');
        if helperPi < 0 then Error('compiler error: PXXMemZero not found');
        EmitCallProc(helperPi);
      end
      else if (zeroBytes > TARGET_PTR_SIZE) and (TargetArch = TARGET_I386) then
      begin
        EmitB($8D); EmitB($85); EmitI32(Syms[i].Offset); { lea eax, [ebp+off] }
        EmitB($50);                                      { push dest }
        EmitB($68); EmitI32(zeroBytes);                  { push count }
        helperPi := FindProc('PXXMemZero');
        if helperPi < 0 then Error('compiler error: PXXMemZero not found');
        EmitCallProc(helperPi);
        EmitB($81); EmitB($C4); EmitI32(8);              { add esp, 8 }
      end
      else if (zeroBytes > TARGET_PTR_SIZE) and (TargetArch <> TARGET_X86_64) then
        Error('target: managed aggregate locals not yet supported');
      if (zeroBytes = TARGET_PTR_SIZE) and (TargetArch = TARGET_I386) then
      begin
        EmitB($C7); EmitB($85); EmitI32(Syms[i].Offset); EmitI32(0);  { mov dword [ebp+off], 0 }
      end
      else if (zeroBytes = TARGET_PTR_SIZE) and (TargetArch = TARGET_ARM32) then
      begin
        EmitLoadImmArm32(9, Syms[i].Offset);
        EmitI32($E08B9009);                                          { add r9, fp, r9 }
        EmitI32($E3A00000);                                          { mov r0, #0 }
        EmitI32($E5890000);                                          { str r0, [r9] }
      end
      else if (zeroBytes = TARGET_PTR_SIZE) and (TargetArch = TARGET_AARCH64) then
      begin
        EmitLoadImmA64(9, Syms[i].Offset);
        EmitI32($8B0903A9);                                          { add x9, x29, x9 }
        EmitI32($F900013F);                                          { str xzr, [x9] }
      end
      else if (zeroBytes = TARGET_PTR_SIZE) and (TargetArch = TARGET_XTENSA) then
      begin
        { Nil the pointer-sized managed handle so an uninitialised local reads as
          nil (Length 0, scope-exit DecRef is a no-op rather than a wild free). }
        EmitFrameAddrXtensa(reg_xtensa_a8, Syms[i].Offset);
        xtensa_movi(reg_xtensa_a9, 0);
        xtensa_s32i(reg_xtensa_a9, reg_xtensa_a8, 0);
      end
      else if (zeroBytes = TARGET_PTR_SIZE) and (TargetArch = TARGET_RISCV32) then
      begin
        EmitLoadImmRISCV32(reg_t0, Syms[i].Offset);
        rv32_add(reg_t0, reg_s0, reg_t0);
        rv32_sw(reg_zero, reg_t0, 0);
      end
      else if zeroBytes = TARGET_PTR_SIZE then
      begin
        EmitB($48); EmitB($C7); EmitB($85); EmitI32(Syms[i].Offset); EmitI32(0); { mov qword [rbp+off], 0 }
      end
      else if (zeroBytes > 0) and (TargetArch = TARGET_X86_64) then
      begin
        EmitB($48); EmitB($8D); EmitB($BD); EmitI32(Syms[i].Offset);  { lea rdi, [rbp+off] }
        EmitB($48); EmitB($31); EmitB($C0);                           { xor rax, rax }
        EmitB($48); EmitB($C7); EmitB($C1); EmitI32(zeroBytes);       { mov rcx, zeroBytes }
        EmitB($F3); EmitB($AA);                                       { rep stosb }
      end;
    end;
  { Routine-local typed constants: now that storage is allocated and managed
    locals are nil'd, emit the recorded initializer assignments into the
    prologue (re-run on each call). }
  CompilePendingLocalInits;
  { label declarations: label foo, bar; }
  while (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'label') do
  begin
    Next;
    while CurTok.Kind = tkIdent do
    begin
      if GotoLabelCount >= MAX_GOTO_LABELS then Error('too many labels');
      GotoLabelNOff[GotoLabelCount]    := Tokens[TokPos-1].SOffset;
      GotoLabelNLen[GotoLabelCount]    := Tokens[TokPos-1].SLen;
      GotoLabelCodePos[GotoLabelCount] := -1;
      Inc(GotoLabelCount);
      Next;
      if not Eat(tkComma) then break;
    end;
    Eat(tkSemicolon);
  end;

  needsProcCleanupFrame := (TargetArch = TARGET_X86_64) and ExceptionUsed and
                           (not isAsmFunc) and ProcHasManagedLocalCleanup(procIdx, -1);
  if needsProcCleanupFrame then
  begin
    EmitB($48); EmitB($83); EmitB($EC); EmitB(EXC_FRAME_SIZE);
    EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_TOP);
    EmitB($48); EmitB($89); EmitB($04); EmitB($24);
    EmitB($48); EmitB($89); EmitB($E0);
    EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_TOP);
    EmitB($48); EmitB($8D); EmitB($7C); EmitB($24); EmitB(EXC_JMP_OFFSET);
    IREmitCodeCall(ExcSetJmpAddr);
    EmitB($85); EmitB($C0);
    EmitB($0F); EmitB($85); cleanupJnePatch := CodeLen; EmitI32(0);
    ProcExceptionCleanupFrameActive := True;
  end;

  { Generator body prologue: this proc is entered not by a normal `call` but by
    CoSwitch `ret`ing into it, with the instance pointer handed off in rbx (the
    initial frame's rbx slot, set by CoAlloc). Copy it into the hidden self
    local, then load each declared param from the instance (the ABI param regs
    hold garbage since there was no real call). }
  if isGenerator and not isStackless then
  begin
    { mov [rbp+selfOff], rbx }
    EmitB($48); EmitB($89); EmitB($9D); EmitI32(Syms[CurGenSelfSym].Offset);
    for i := 0 to nparams - 1 do
    begin
      gpi := Procs[procIdx].Params[i].SymIdx;
      sz := ParamSize(gpi);
      { rax = self }
      EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[CurGenSelfSym].Offset);
      { rax = [rax + CO_OFF_PARAMS + 8*i]  (instance stores each param as a qword) }
      EmitB($48); EmitB($8B); EmitB($80); EmitI32(CO_OFF_PARAMS + 8 * i);
      { Store only the param's own width into its frame slot — slots are packed by
        size, so a qword store would clobber the adjacent param slot. }
      if sz = 1 then
        begin EmitB($88); EmitB($85); end                  { mov [rbp+off], al }
      else if sz = 2 then
        begin EmitB($66); EmitB($89); EmitB($85); end       { mov [rbp+off], ax }
      else if sz = 4 then
        begin EmitB($89); EmitB($85); end                   { mov [rbp+off], eax }
      else
        begin EmitB($48); EmitB($89); EmitB($85); end;       { mov [rbp+off], rax }
      EmitI32(Syms[gpi].Offset);
    end;
  end;

  { Body }
  if isAsmFunc then
  begin
    { Whole-function asm body: 'asm ... end;'. Params already copied to their
      stack slots, so the asm can read/write them by name. The asm is
      responsible for leaving the result in rax (FPC accumulator convention),
      so the epilogue below must not reload Result. }
    Expect(tkAsm, 'asm');
    asmNode := ParseAsmStatementAST;
    CompileAST(asmNode);
    ASTNodeCount := 0;
  end
  else if isStackless then
  begin
    { Stackless generator: parse the body to AST, verify yield placement, assign
      persistent instance slots, transform to a flat goto/label state machine,
      and compile that as the step function. No asm, no coroutine stack — runs on
      every target through the shared IR. }
    Expect(tkBegin, 'begin');
    genBodyAST := ParseBlockAST;
    Expect(tkEnd, 'end');
    Eat(tkSemicolon);
    if isAsync then
    begin
      if not SLHasYield(genBodyAST) then
        Error('async stackless routine has no await (cannot suspend)');
    end
    else if not CurGenSeenYield then
      Error('generator has no yield');
    SLCheckEligible(genBodyAST);
    AssignStacklessSlots(procIdx);
    genStepAST := BuildStacklessStep(genBodyAST, procIdx);
    ProcGenInstSize[procIdx] := SL_OFF_SLOTS + 8 * CurGenSlotNext;
    CompileAST(genStepAST);
    ASTNodeCount := 0;
  end
  else
  begin
    Expect(tkBegin, 'begin');
    { Split ParseBlock so the body AST can be retained for inline expansion
      (feature-inline-routines) before CompileAST emits + the pool resets. Only a
      non-method plain routine is a candidate; TryRetainInlineBody re-checks all
      eligibility and no-ops unless OptLevel>=2. Behaviour is otherwise identical
      to ParseBlock, so -O0/-O1 stay byte-identical. }
    inlineBodyNode := ParseBlockAST;
    if methOwnerCi < 0 then TryRetainInlineBody(procIdx, inlineBodyNode);
    CompileAST(inlineBodyNode);
    ASTNodeCount := 0;
    Expect(tkEnd, 'end');
    Eat(tkSemicolon);
  end;

  { Generator body epilogue: falling off the end means exhaustion. Mark done and
    CoSwitch back to the consumer; this never returns (the consumer's CoNext
    sees done and stops, never resuming this stack). Emitted before the normal
    epilogue, which is therefore unreachable for a generator. Validation: a
    generator with no yield is almost certainly a mistake. }
  if isGenerator and not isStackless then
  begin
    if not CurGenSeenYield then
      Error('generator has no yield');
    EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[CurGenSelfSym].Offset);  { mov rax, [rbp+selfOff] }
    EmitB($48); EmitB($C7); EmitB($80); EmitI32(CO_OFF_DONE); EmitI32(1);      { mov qword [rax+DONE], 1 }
    EmitB($48); EmitB($8D); EmitB($78); EmitB(CO_OFF_GENCTX);                  { lea rdi, [rax+genctx]  (from) }
    EmitB($48); EmitB($8D); EmitB($70); EmitB(CO_OFF_CALLERCTX);               { lea rsi, [rax+callerctx] (to) }
    IREmitCodeCall(CoSwitchAddr);
  end;

  if needsProcCleanupFrame then
  begin
    EmitB($E9); cleanupJmpPatch := CodeLen; EmitI32(0);
    Patch32(cleanupJnePatch, CodeLen - (cleanupJnePatch + 4));
    EmitLeaveExceptionFrameX64;
    EmitManagedLocalCleanup(-1);
    IREmitCodeCall(ExcRaiseAddr);
    Patch32(cleanupJmpPatch, CodeLen - (cleanupJmpPatch + 4));
  end;

  { Verify all forward goto fixups were resolved }
  for i := 0 to GotoLabelCount - 1 do
    if GotoLabelCodePos[i] = -1 then
    begin
      for j := 0 to GotoFixupCount - 1 do
        if TokSlicesMatch(GotoFixupNOff[j], GotoFixupNLen[j], GotoLabelNOff[i], GotoLabelNLen[i]) then
          Error('goto target label never placed: ' +
            GetTokenStrFromRaw(GotoLabelNOff[i], GotoLabelNLen[i]));
    end;

  { Epilogue. For assembler functions the asm body already set rax, so pass
    -1 to skip reloading Result (which would clobber the asm's return value). }
  if isAsmFunc then
    EmitProcEpilog(-1)
  else
    EmitProcEpilog(Procs[procIdx].RetSymIdx);
  ProcExceptionCleanupFrameActive := savedProcCleanupFrameActive;

  { End of this proc's body bytes — the iram byte-range is [BodyAddr, ProcBodyEnd). }
  ProcBodyEnd[procIdx] := CodeLen;
  { DWARF -g: this proc is in the main source file iff we are still parsing main-
    file tokens (units lex past DbgMainTokEnd). Drives DW_TAG_subprogram emission.
    Snapshot its params+locals now, before the scope (Syms[]) is torn down. }
  ProcDbgMain[procIdx] := TokPos <= DbgMainTokEnd;
  if DebugInfo and ProcDbgMain[procIdx] then DbgCaptureProcLocals(procIdx);

  { Patch frame size }
  if DebugTrace then writeln('FRAME ', Procs[procIdx].Name, ' = ', FrameSize);
  PatchProcPrologue(patchPos, FrameSize);

  { Oversized stack-frame diagnostic: this routine's locals total FrameSize bytes,
    all on the small fixed process stack. Warn (once, at the body end) when that
    exceeds the threshold — a fat frame risks a runtime stack overflow. }
  if (MaxStackFrameSize > 0) and (FrameSize > MaxStackFrameSize) then
    WarnStackFrame(CurTok.Line, Procs[procIdx].Name, FrameSize, MaxStackFrameSize);

  { Restore scope }
  SymRollbackTo(savedSC);
  FrameSize := savedFS;
  GotoLabelCount := savedGLC;
  GotoFixupCount := savedGFC;
  CurProc   := -1;
  CurBodyHdrTok := savedVisVarSeq;   { restore decl-order horizon (see all outside a body) }
  CurSelfClass := REC_NONE;
  CurProcIsAsync := savedProcIsAsync;
  CurProcIsGenerator := savedGenIsGen;
  CurProcIsStackless := savedGenStackless;
  CurGenSelfSym := savedGenSelf;
  CurGenSeenYield := savedGenSeen;
  GenTryDepth := savedGenTry;
  CurGenStateCtr := savedGenStateCtr;
  CurGenSlotNext := savedGenSlotNext;

  { Re-inject any nested routines declared in this routine's body so they parse
    next as top-level siblings (completing the forward decls left in place). }
  FlushPendingNestedProcs;
end;

function LowerCase(const s: AnsiString): AnsiString;
var
  i: Integer;
  res: AnsiString;
begin
  res := s;
  for i := 1 to Length(res) do
  begin
    if res[i] in ['A'..'Z'] then
      res[i] := Chr(Ord(res[i]) + 32);
  end;
  Result := res;
end;

procedure ParseUnit; forward;

procedure ConcatThree(const s1, s2, s3: AnsiString; var dst: AnsiString);
var
  i, len1, len2, len3: Integer;
begin
  len1 := Length(s1);
  len2 := Length(s2);
  len3 := Length(s3);
  SetLength(dst, len1 + len2 + len3);
  for i := 1 to len1 do
    dst[i] := s1[i];
  for i := 1 to len2 do
    dst[len1 + i] := s2[i];
  for i := 1 to len3 do
    dst[len1 + len2 + i] := s3[i];
end;

function CStemMatches(const a, b: AnsiString): Boolean;
begin
  Result := CaseEqual(a, b);
  if (not Result) and CaseEqual(a, 'lib' + b) then Result := True;
end;

function CSystemLibStemSelected(const stem: AnsiString): Boolean;
var i: Integer;
begin
  Result := False;
  if CUseSystemLibs then begin Result := True; Exit; end;
  for i := 0 to CSystemLibCount - 1 do
    if CStemMatches(CSystemLibs[i], stem) then begin Result := True; Exit; end;
end;

procedure AddCSystemLibStem(const stem: AnsiString);
var i: Integer;
begin
  if Length(stem) = 0 then Exit;
  for i := 0 to CSystemLibCount - 1 do
    if CaseEqual(CSystemLibs[i], stem) then Exit;
  if CSystemLibCount >= MAX_C_INCLUDE_DIRS then Error('too many --system-libs entries');
  CSystemLibs[CSystemLibCount] := LowerCase(stem);
  Inc(CSystemLibCount);
end;

procedure AddCSystemLibSpec(const spec: AnsiString);
var i: Integer; stem: AnsiString;
begin
  stem := '';
  for i := 1 to Length(spec) do
  begin
    if spec[i] = ',' then
    begin
      AddCSystemLibStem(stem);
      stem := '';
    end
    else if not (spec[i] in [' ', #9]) then
      AppendChar(stem, spec[i]);
  end;
  AddCSystemLibStem(stem);
end;

function CHeaderStem(const name: AnsiString; var stem: AnsiString): Boolean;
var lo: AnsiString;
begin
  lo := LowerCase(name);
  Result := True;
  stem := lo;
  if (lo = 'ctype') or (lo = 'errno') or (lo = 'locale') or
     (lo = 'math_ext') or (lo = 'setjmp') or (lo = 'signal') or
     (lo = 'stdio') or (lo = 'stdlib') or (lo = 'string') or
     (lo = 'unistd') or (lo = 'wchar') or (lo = 'wctype') or
     (lo = 'arpa/inet') or (lo = 'netinet/in') or
     (lo = 'sys/socket') or (lo = 'sys/types') or
     (lo = 'sys/_types') or (lo = 'sys/cdefs') then
    stem := 'c'
  else if (lo = 'math') or (lo = 'm') then
    stem := 'm'
  else if lo = 'gtk3_c' then
    stem := 'gtk-3'
  else if lo = 'gtk' then
    stem := 'gtk-x11-2.0'
  else if (lo = 'stddef') or (lo = 'stdint') or (lo = 'stdbool') or
          (lo = 'stdarg') or (lo = 'limits') or (lo = 'assert') then
    stem := 'c'
  else if Length(lo) = 0 then
    Result := False;
end;

function CSonameForStem(const stem: AnsiString; var soname: AnsiString): Boolean;
begin
  Result := True;
  if CStemMatches(stem, 'c') then soname := 'libc.so.6'
  else if CStemMatches(stem, 'm') then soname := 'libm.so.6'
  else if CStemMatches(stem, 'pthread') then soname := 'libpthread.so.0'
  else if CStemMatches(stem, 'gtk-3') then soname := 'libgtk-3.so.0'
  else if CStemMatches(stem, 'gtk-x11-2.0') then soname := 'libgtk-x11-2.0.so.0'
  else if CStemMatches(stem, 'dl') then soname := 'libdl.so.2'
  else if CStemMatches(stem, 'rt') then soname := 'librt.so.1'
  else if CStemMatches(stem, 'z') then soname := 'libz.so.1'
  else if CStemMatches(stem, 'sqlite3') then soname := 'libsqlite3.so.0'
  else ConcatThree('lib', LowerCase(stem), '.so', soname);
end;

function CSonameForHeader(const name: AnsiString; var soname: AnsiString): Boolean;
var stem: AnsiString;
begin
  Result := CHeaderStem(name, stem);
  if Result then Result := CSonameForStem(stem, soname);
end;

function CHeaderDefaultSystem(const name: AnsiString): Boolean;
var stem: AnsiString;
begin
  Result := False;
  if not CHeaderStem(name, stem) then Exit;
  { pthread is NOT default-system: pxx ships a libc-free `<pthread.h>` + pthread.c
    shim over the PAL (lib/crtl, bridged via palpthread.pas), so `#include
    <pthread.h>` resolves to the project's own implementation like <stdio.h>/
    <math.h>. The real glibc libpthread is still available on demand via
    `--system-libs=pthread` (CSystemLibStemSelected below still honours it). }
  Result := CStemMatches(stem, 'gtk-3') or
            CStemMatches(stem, 'gtk-x11-2.0') or CStemMatches(stem, 'dl') or
            CStemMatches(stem, 'rt') or CStemMatches(stem, 'z') or
            CStemMatches(stem, 'sqlite3');
end;

function CHeaderUsesSystemLib(const name: AnsiString): Boolean;
var stem: AnsiString;
begin
  Result := CUseSystemLibs or CHeaderDefaultSystem(name);
  if Result then Exit;
  if CHeaderStem(name, stem) then
    Result := CSystemLibStemSelected(stem);
end;

function CSystemLibSelectedForSoname(const soname: AnsiString): Boolean;
begin
  Result := CUseSystemLibs;
  if Result then Exit;
  if CaseEqual(soname, 'libc.so.6') then Result := CSystemLibStemSelected('c')
  else if CaseEqual(soname, 'libm.so.6') then Result := CSystemLibStemSelected('m')
  else if CaseEqual(soname, 'libpthread.so.0') then Result := CSystemLibStemSelected('pthread')
  else if CaseEqual(soname, 'libdl.so.2') then Result := CSystemLibStemSelected('dl')
  else if CaseEqual(soname, 'librt.so.1') then Result := CSystemLibStemSelected('rt')
  else if CaseEqual(soname, 'libz.so.1') then Result := CSystemLibStemSelected('z')
  else if CaseEqual(soname, 'libsqlite3.so.0') then Result := CSystemLibStemSelected('sqlite3')
  else if CaseEqual(soname, 'libgtk-3.so.0') then Result := CSystemLibStemSelected('gtk-3')
  else if CaseEqual(soname, 'libgtk-x11-2.0.so.0') then Result := CSystemLibStemSelected('gtk-x11-2.0');
end;

procedure EnableExceptionRuntime;
begin
  if not ExceptionUsed then
  begin
    ExceptionUsed := True;
    BSS_EXC_TOP := BSSSize; Inc(BSSSize, 8);
    BSS_EXC_OBJ := BSSSize; Inc(BSSSize, 8);
    BSS_EXC_CLS := BSSSize; Inc(BSSSize, 8);
    EmitExceptionRuntime;
  end;
end;

procedure EnableCoroutineRuntime;
begin
  if not CoroutineUsed then
  begin
    CoroutineUsed := True;
    { CoSwitch saves/restores BSS_EXC_TOP, so the exception slot must exist even
      if the program itself has no try/except. }
    EnableExceptionRuntime;
    EmitCoroutineRuntime;
  end;
end;

procedure ParseUsesUnit(const name: AnsiString);
var
  lo, cName, path: AnsiString;
  startPos, savedTokPos, strIdx, i, savedCurrentUnitIdx: Integer;
  savedCurTokKind: TTokenKind;
  savedCurTokSVal: AnsiString;
  savedCurTokIVal: Int64;
  savedCurTokLine: Integer;
  savedSrcBase, savedUnitDir, savedCurrentCLibrary: AnsiString;
  cdir, bdir, rtldir, lcldir, asmdir: AnsiString;
  basePath, ext, emsg: AnsiString;
  lastSlash, lastDot: Integer;
  isCompiled, isCUnit, isCHeader, isPath, savedCaseMode, softMissOK: Boolean;
  savedNestedComments: Boolean;
  unitNeedsText: Boolean;
begin
  isPath := False;
  for i := 1 to Length(name) do
    if name[i] = '/' then isPath := True;
  if isPath then
    lo := LowerCase(GetFileBaseName(name))
  else
    lo := LowerCase(name);
  if isPath then
    cName := GetFileBaseName(name)
  else
    cName := name;
  { sysutils/baseunix/unix: FPC RTL units that PXX programs historically `uses`
    purely to satisfy FPC source while relying on builtins. Load a real
    lib/rtl/<name> source if one exists (the canonical home for the conversion
    helpers); otherwise the miss is a graceful no-op (today's behavior), not an
    error — see the not-found handler below. }
  softMissOK := (lo = 'sysutils') or (lo = 'baseunix') or (lo = 'unix');

  { Check if already compiled }
  strIdx := InternStr(lo);
  isCompiled := False;
  for i := 0 to CompiledUnitCount - 1 do
  begin
    if CompiledUnits[i] = strIdx then
      isCompiled := True;
  end;
  if isCompiled then Exit;

  { Mark as compiled }
  if CompiledUnitCount < 256 then
  begin
    CompiledUnits[CompiledUnitCount] := strIdx;
    Inc(CompiledUnitCount);
  end;

  isCUnit := False;
  isCHeader := False;
  savedCurrentCLibrary := CurrentCLibrary;
  CurrentCLibrary := '';
  UnitContent := '';

  if isPath then
  begin
    { Path-form reference (uses './sub/unit' or '/abs/unit'): resolve relative
      to the directory of the file containing the directive (CurUnitDir);
      absolute paths are used as-is. Extension may be omitted (.pas then .pp
      inferred); an explicit .pas/.pp/.c/.h is honoured. The path is
      authoritative — no directory search chain, miss is an error. }
    lastSlash := 0; lastDot := 0;
    for i := 1 to Length(name) do
    begin
      if name[i] = '/' then lastSlash := i;
      if name[i] = '.' then lastDot := i;
    end;
    if name[1] = '/' then
      basePath := name
    else
      ConcatThree(CurUnitDir, name, '', basePath);
    NormalizePath(basePath);
    if lastDot > lastSlash then
    begin
      ext := '';
      for i := lastDot + 1 to Length(name) do AppendChar(ext, name[i]);
      ext := LowerCase(ext);
      if (Length(ext) = 1) and (ext[1] = 'c') then isCUnit := True;
      if (Length(ext) = 1) and (ext[1] = 'h') then
      begin
        isCUnit := True; isCHeader := True;
      end;
      path := basePath;
      if isCUnit then
        LoadFile(path, UnitContent)
      else
        LoadFileCI(path, UnitContent);
    end
    else
    begin
      ConcatThree(basePath, '.pas', '', path);
      LoadFileCI(path, UnitContent);
      if Length(UnitContent) = 0 then
      begin
        ConcatThree(basePath, '.pp', '', path);
        LoadFileCI(path, UnitContent);
      end;
    end;
    if Length(UnitContent) = 0 then
    begin
      ConcatThree('uses: unit source not found: ', basePath, '', emsg);
      Error(emsg);
    end;
  end;

  { --mimic-fpc: pxx's own RTL SHADOWS every search root (the unit's own dir,
    -Fu, ...) for units pxx ships. The mode exists to compile external FPC
    source against pxx's RTL surface, and an FPC tree carries its own
    types/sysutils/classes right next to the unit being compiled — parsing
    those walls immediately (e.g. types.pp:136, advanced-record class
    operators). Units pxx does not ship (fgl, rtlconsts, ...) fall through
    unchanged. Non-mimic order is untouched (-Fu before RTL = the PAL supply
    mechanism); mimic is never set during self-build. }
  if MimicFpc and (not isPath) and (Length(UnitContent) = 0) then
  begin
    if ExeDir = '' then
      rtldir := 'lib/rtl/'
    else
      ConcatThree(ExeDir, '../lib/rtl/', '', rtldir);
    ConcatThree(rtldir, lo, '.pas', path);
    LoadFileCI(path, UnitContent);
    if Length(UnitContent) = 0 then
    begin
      ConcatThree(rtldir, lo, '.pp', path);
      LoadFileCI(path, UnitContent);
    end;
    { CWD-relative fallback, mirroring the tail block (self-host tests run a
      /tmp compiler copy with CWD at the repo root) }
    if (Length(UnitContent) = 0) and (ExeDir <> '') then
    begin
      ConcatThree('lib/rtl/', lo, '.pas', path);
      LoadFileCI(path, UnitContent);
    end;
  end;

  { The including UNIT's own directory first, Pascal-only (.pas/.pp). A unit's
    sibling `uses` should bind to the Pascal unit next to it, never to an
    unrelated C header of the same base name reachable via a -I include root —
    e.g. lib/rtl/pxxcio's `uses math` must find lib/rtl/math.pas, NOT a
    -Ilib/crtl/include/math.h. Restricted to .pas/.pp so a C `uses "foo.c"`
    still resolves through the normal chain. }
  if (Length(UnitContent) = 0) and (CurUnitDir <> '') and (CurUnitDir <> SourceFileDir) then
  begin
    ConcatThree(CurUnitDir, lo, '.pas', path);
    LoadFileCI(path, UnitContent);
    if Length(UnitContent) = 0 then
    begin
      ConcatThree(CurUnitDir, lo, '.pp', path);
      LoadFileCI(path, UnitContent);
    end;
  end;
  if Length(UnitContent) = 0 then
  begin
    ConcatThree(SourceFileDir, lo, '.pas', path);
    LoadFileCI(path, UnitContent);
  end;
  if Length(UnitContent) = 0 then
  begin
    ConcatThree(SourceFileDir, lo, '.pp', path);
    LoadFileCI(path, UnitContent);
  end;
  if Length(UnitContent) = 0 then
  begin
    ConcatThree(SourceFileDir, cName, '.c', path);
    LoadFile(path, UnitContent);
    if Length(UnitContent) > 0 then isCUnit := True;
  end;
  if Length(UnitContent) = 0 then
  begin
    ConcatThree(SourceFileDir, cName, '.h', path);
    LoadFile(path, UnitContent);
    if Length(UnitContent) > 0 then begin isCUnit := True; isCHeader := True; end;
  end;

  { User unit search roots (`-Fu<dir>` / `-I<dir>`), in flag order. Searched
    after the including file's own directory and before the compiler-anchored
    builtin/RTL/LCL dirs, so a project or per-platform dir (e.g.
    lib/rtl/platform/posix/) can supply or override a unit by name — the PAL
    backend-selection mechanism. Dirs carry a trailing '/' (AddPasUnitDir). }
  i := 0;
  while (Length(UnitContent) = 0) and (i < PasUnitDirCount) do
  begin
    ConcatThree(PasUnitDirs[i], lo, '.pas', path);
    LoadFileCI(path, UnitContent);
    if Length(UnitContent) = 0 then
    begin
      ConcatThree(PasUnitDirs[i], lo, '.pp', path);
      LoadFileCI(path, UnitContent);
    end;
    if Length(UnitContent) = 0 then
    begin
      ConcatThree(PasUnitDirs[i], cName, '.c', path);
      LoadFile(path, UnitContent);
      if Length(UnitContent) > 0 then isCUnit := True;
    end;
    if Length(UnitContent) = 0 then
    begin
      ConcatThree(PasUnitDirs[i], cName, '.h', path);
      LoadFile(path, UnitContent);
      if Length(UnitContent) > 0 then begin isCUnit := True; isCHeader := True; end;
    end;
    Inc(i);
  end;

  { Library directories, anchored to the compiler binary (ExeDir) so units
    resolve regardless of CWD. ExeDir is e.g. <root>/compiler/, so the RTL/PCL
    dirs are its siblings via '../lib/...'. Falls back to CWD-relative when the
    binary path carried no directory (run via a bare name). }
  if ExeDir = '' then
  begin
    cdir := 'compiler/'; bdir := 'compiler/builtin/';
    rtldir := 'lib/rtl/'; lcldir := 'lib/pcl/'; asmdir := 'lib/asmcore/';
  end
  else
  begin
    cdir := ExeDir;
    ConcatThree(ExeDir, 'builtin/', '', bdir);   { ExeDir is <root>/compiler/ }
    ConcatThree(ExeDir, '../lib/rtl/', '', rtldir);
    ConcatThree(ExeDir, '../lib/pcl/', '', lcldir);
    ConcatThree(ExeDir, '../lib/asmcore/', '', asmdir);
  end;

  if Length(UnitContent) = 0 then
  begin
    { If not found in base dir, try compiler's local directory or common locations }
    ConcatThree(cdir, lo, '.pas', path);
    LoadFileCI(path, UnitContent);
    if Length(UnitContent) = 0 then
    begin
      ConcatThree(cdir, lo, '.pp', path);
      LoadFileCI(path, UnitContent);
    end;
    if Length(UnitContent) = 0 then
    begin
      ConcatThree(cdir, cName, '.c', path);
      LoadFile(path, UnitContent);
      if Length(UnitContent) > 0 then isCUnit := True;
    end;
    if Length(UnitContent) = 0 then
    begin
      ConcatThree(cdir, cName, '.h', path);
      LoadFile(path, UnitContent);
      if Length(UnitContent) > 0 then begin isCUnit := True; isCHeader := True; end;
    end;
  end;

  if Length(UnitContent) = 0 then
  begin
    { Compiler-specific runtime units (builtin: the auto-included heap allocator
      and Str/Val/variant helpers). Not user RTL, so it lives with the compiler. }
    ConcatThree(bdir, lo, '.pas', path);
    LoadFileCI(path, UnitContent);
    if Length(UnitContent) = 0 then
    begin
      ConcatThree(bdir, lo, '.pp', path);
      LoadFileCI(path, UnitContent);
    end;
  end;

  if Length(UnitContent) = 0 then
  begin
    { RTL library units }
    ConcatThree(rtldir, lo, '.pas', path);
    LoadFileCI(path, UnitContent);
    if Length(UnitContent) = 0 then
    begin
      ConcatThree(rtldir, lo, '.pp', path);
      LoadFileCI(path, UnitContent);
    end;
    if Length(UnitContent) = 0 then
    begin
      ConcatThree(rtldir, cName, '.h', path);
      LoadFile(path, UnitContent);
      if Length(UnitContent) > 0 then begin isCUnit := True; isCHeader := True; end;
    end;
  end;

  if Length(UnitContent) = 0 then
  begin
    { PCL widgetset units (.pas/.pp), plus C-header/C-source imports that live
      alongside them (e.g. lib/pcl/gtk3_c.h, the GTK binding pulled by gtk3.pas).
      The RTL dir already tries .h; mirror it here so a PCL unit can `uses` a
      sibling .h/.c with no explicit -Fu/-I. }
    ConcatThree(lcldir, lo, '.pas', path);
    LoadFileCI(path, UnitContent);
    if Length(UnitContent) = 0 then
    begin
      ConcatThree(lcldir, lo, '.pp', path);
      LoadFileCI(path, UnitContent);
    end;
    if Length(UnitContent) = 0 then
    begin
      ConcatThree(lcldir, cName, '.c', path);
      LoadFile(path, UnitContent);
      if Length(UnitContent) > 0 then isCUnit := True;
    end;
    if Length(UnitContent) = 0 then
    begin
      ConcatThree(lcldir, cName, '.h', path);
      LoadFile(path, UnitContent);
      if Length(UnitContent) > 0 then begin isCUnit := True; isCHeader := True; end;
    end;
  end;

  if Length(UnitContent) = 0 then
  begin
    { lib/asmcore — the standalone multi-target instruction-encoder library
      (feature-asmcore-encoder-library). A built-in peer of RTL/PCL: any
      program can `uses asmcore_base, asmcore_x64` with no -Fu, same as the
      compiler's own .asm frontend / inline-asm branch encoding do. }
    ConcatThree(asmdir, lo, '.pas', path);
    LoadFileCI(path, UnitContent);
    if Length(UnitContent) = 0 then
    begin
      ConcatThree(asmdir, lo, '.pp', path);
      LoadFileCI(path, UnitContent);
    end;
  end;

  { CWD-relative fallback (only meaningful when ExeDir is set and differs from
    the repo root, e.g. the self-host tests run a /tmp copy of the compiler with
    CWD at the repo root where compiler/ + lib/ live). }
  if (Length(UnitContent) = 0) and (ExeDir <> '') then
  begin
    ConcatThree('compiler/', lo, '.pas', path);
    LoadFileCI(path, UnitContent);
    if Length(UnitContent) = 0 then begin ConcatThree('compiler/builtin/', lo, '.pas', path); LoadFileCI(path, UnitContent); end;
    if Length(UnitContent) = 0 then begin ConcatThree('lib/rtl/', lo, '.pas', path); LoadFileCI(path, UnitContent); end;
    if Length(UnitContent) = 0 then begin ConcatThree('lib/pcl/', lo, '.pas', path); LoadFileCI(path, UnitContent); end;
    if Length(UnitContent) = 0 then begin ConcatThree('lib/asmcore/', lo, '.pas', path); LoadFileCI(path, UnitContent); end;
    if Length(UnitContent) = 0 then begin ConcatThree('compiler/', lo, '.pp', path); LoadFileCI(path, UnitContent); end;
    if Length(UnitContent) = 0 then begin ConcatThree('lib/rtl/', lo, '.pp', path); LoadFileCI(path, UnitContent); end;
    if Length(UnitContent) = 0 then begin ConcatThree('lib/pcl/', lo, '.pp', path); LoadFileCI(path, UnitContent); end;
    if Length(UnitContent) = 0 then begin ConcatThree('lib/asmcore/', lo, '.pp', path); LoadFileCI(path, UnitContent); end;
    if Length(UnitContent) = 0 then
    begin
      ConcatThree('lib/rtl/', cName, '.h', path); LoadFile(path, UnitContent);
      if Length(UnitContent) = 0 then begin ConcatThree('lib/pcl/', cName, '.h', path); LoadFile(path, UnitContent); end;
      if Length(UnitContent) = 0 then begin ConcatThree('compiler/', cName, '.h', path); LoadFile(path, UnitContent); end;
      if Length(UnitContent) > 0 then begin isCUnit := True; isCHeader := True; end;
    end;
    if Length(UnitContent) = 0 then
    begin
      ConcatThree('compiler/', cName, '.c', path); LoadFile(path, UnitContent);
      if Length(UnitContent) > 0 then isCUnit := True;
    end;
  end;

  if Length(UnitContent) = 0 then
  begin
    ConcatThree('/usr/include/', cName, '.h', path);
    LoadFile(path, UnitContent);
    if Length(UnitContent) > 0 then begin isCUnit := True; isCHeader := True; end;
  end;

  if Length(UnitContent) = 0 then
  begin
    ConcatThree('/usr/include/gtk-2.0/gtk/', cName, '.h', path);
    LoadFile(path, UnitContent);
    if Length(UnitContent) > 0 then begin isCUnit := True; isCHeader := True; end;
  end;

  if Length(UnitContent) = 0 then
  begin
    { sysutils/baseunix/unix with no source on the path: pass as a no-op so
      builtin-only FPC code keeps compiling (the historical behavior). }
    if softMissOK then
    begin
      CurrentCLibrary := savedCurrentCLibrary;
      Exit;
    end;
    ConcatThree('uses: unit source not found: ', lo, '', emsg);
    Error(emsg);
  end;

  if isCUnit then
  begin
    if isCHeader then
    begin
      { Map the header/unit name to the DT_NEEDED soname the system ships.
        Versioned sonames (not the unversioned dev symlink lib<name>.so) so
        the emitted ELF loads against the runtime libraries present on a
        stock system without -dev packages. Dynamic ld.so.cache probing is a
        later refinement; the registry covers the FFI targets in use and marks
        non-emulated integrations (GTK, sqlite, zlib, pthread, dl) as external
        by default. }
      if not CSonameForHeader(cName, CurrentCLibrary) then
        ConcatThree('lib', LowerCase(cName), '.so', CurrentCLibrary);
    end;
    savedTokPos := TokPos;
    savedCurTokKind := CurTok.Kind;
    savedCurTokSVal := CurTok.SVal;
    savedCurTokIVal := CurTok.IVal;
    savedCurTokLine := CurTok.Line;

    CPreprocess(UnitContent, GetFilePath(path));

    { Append preprocessed tokens using C Lexer }
    startPos := CLexAppend(UnitContent);

    TokPos := startPos;
    Next;

    { C symbols are case-sensitive: force the mode so their proc names match
      exactly (the link symbol is exact), independent of the host's setting.
      Restored after so it does not leak into the including unit. }
    savedCaseMode := CaseSensitiveMode;
    savedCurrentUnitIdx := CurrentUnitIdx;
    CurrentUnitIdx := strIdx;
    CaseSensitiveMode := True;
    CHeaderMode := isCHeader;
    ParseCUnit;
    { Surface object-like integer #define macros (e.g. SQLITE_ROW) as constants,
      still under the header's case-sensitive mode and unit index. }
    RegisterCMacroConsts;
    CaseSensitiveMode := savedCaseMode;
    CurrentUnitIdx := savedCurrentUnitIdx;

    TokPos := savedTokPos;
    CurTok.Kind := savedCurTokKind;
    CurTok.SVal := savedCurTokSVal;
    CurTok.IVal := savedCurTokIVal;
    CurTok.Line := savedCurTokLine;
    CurrentCLibrary := savedCurrentCLibrary;
  end
  else
  begin
    savedTokPos := TokPos;
    savedCurTokKind := CurTok.Kind;
    savedCurTokSVal := CurTok.SVal;
    savedCurTokIVal := CurTok.IVal;
    savedCurTokLine := CurTok.Line;
    { A unit's own CASESENSITIVE directive (processed during LexAppend below)
      applies to that unit only — saved here, restored after ParseUnit, so it
      does not leak into the including file. A unit with no directive inherits
      the caller's mode. Same per-unit scoping for the comment-nesting flag:
      a unit's {$MODE DELPHI} / {$NESTEDCOMMENTS OFF} must not change how
      LATER units' comments lex (Synapse's jedi.inc sets MODE DELPHI and
      every lib/rtl unit lexed after it broke on nested-brace doc comments —
      bug-unit-mode-directives-leak). }
    savedCaseMode := CaseSensitiveMode;
    savedNestedComments := NestedComments;
    { fresh per-unit default: FPC lexes each unit under its OWN mode — an
      includer's {$MODE DELPHI} (NestedComments off) must not change how this
      unit's comments nest. The unit's own MODE/NESTEDCOMMENTS directives
      still apply to it, and the caller's state is restored below. }
    NestedComments := True;
    savedCurrentUnitIdx := CurrentUnitIdx;
    CurrentUnitIdx := strIdx;

    ExpandIncludes(UnitContent, GetFilePath(path));

    { This unit's name resolves the `*` in its own $R *.lfm (processed during
      LexAppend below). Restored after, so a nested `uses` doesn't leak its base. }
    savedSrcBase := CurSrcBaseName;
    CurSrcBaseName := lo;

    { Nested path-form `uses` inside this unit resolve relative to the unit's
      own directory. Restored after, like CurSrcBaseName. }
    savedUnitDir := CurUnitDir;
    CurUnitDir := GetFilePath(path);

    { Append tokens to global Token stream }
    startPos := LexAppend(UnitContent);
    i := startPos;
    unitNeedsText := False;
    while i < TokCount do
    begin
      if Tokens[i].Kind in [tkTry, tkRaise] then EnableExceptionRuntime;
      { A unit (e.g. coroutine.pas) using the low-level __pxxcoswitch intrinsic
        needs the CoSwitch stub emitted before its body compiles. }
      if (Tokens[i].Kind = tkIdent) and CaseEqual(GetTokenStr(i), '__pxxcoswitch') then
        EnableCoroutineRuntime;
      { A unit that references the Text file type needs the implicit textfile RTL
        too — the program-level pre-scan only sees the program's own tokens, so a
        unit using `var f: Text; Assign(f,...)` (the idiomatic FPC form, no
        explicit `uses textfile`) would otherwise hit `undefined variable
        (Assign)` (bug-textfile-primitives-not-ambient-in-units). }
      if (Tokens[i].Kind = tkIdent) and
         ((Tokens[i].SLen = 4) or (Tokens[i].SLen = 8)) then
        if CaseEqual(GetTokenStr(i), 'text') or CaseEqual(GetTokenStr(i), 'textfile') or
           CaseEqual(GetTokenStr(i), 'ioresult') then
          unitNeedsText := True;
      Inc(i);
    end;

    { Load the implicit textfile surface (builtin first, for its numeric write
      dispatch) before parsing the unit body, so the unit's Assign/Reset/Rewrite/
      Close resolve. Same gating as the program-level default surface; idempotent
      via the CompiledUnits guard, so an explicit `uses textfile` is harmless. }
    if unitNeedsText and (not NoDefaultRtl) and
       (TargetArch <> TARGET_XTENSA) and ((TargetArch <> TARGET_RISCV32) or (not EspBareBoot)) then
    begin
      ParseUsesUnit('builtin');
      ParseUsesUnit('textfile');
    end;

    { Point parser to first token of the unit }
    TokPos := startPos;
    Next;

    { Parse the unit }
    ParseUnit;

    { Restore parser position }
    TokPos := savedTokPos;
    CurTok.Kind := savedCurTokKind;
    CurTok.SVal := savedCurTokSVal;
    CurTok.IVal := savedCurTokIVal;
    CurTok.Line := savedCurTokLine;
    CurSrcBaseName := savedSrcBase;
    CurUnitDir := savedUnitDir;
    CaseSensitiveMode := savedCaseMode;
    NestedComments := savedNestedComments;
    CurrentUnitIdx := savedCurrentUnitIdx;
    CurrentCLibrary := savedCurrentCLibrary;
  end;
end;

procedure ParseUsesEntry;
{ One `uses` entry: a (possibly dotted/quoted) unit name with an optional
  `as <alias>` suffix. The alias gives a valid-identifier handle for a quoted
  unit whose real name is not a Pascal identifier (`uses 'wayland-client' as
  wayland;`) or that clashes with a keyword (`uses 'string' as cstrings;`), so
  `wayland.Sym` / `cstrings.strlen` qualifiers parse. Symbol lookup is flat, so
  the alias only needs to be a findable compiled-unit name (FindCompiledUnit) —
  registering it there is enough for ConsumeUnitQualifier to accept the prefix.
  See feature-uses-alias-as. }
var uname, alias, realLo: AnsiString; aStrIdx, realStrIdx, i: Integer; isPath: Boolean;
begin
  uname := ReadDottedUsesName;
  ParseUsesUnit(uname);
  if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'as') then
  begin
    Next;                          { consume `as` }
    if CurTok.Kind <> tkIdent then
      Error('expected an identifier after `as` in a uses clause');
    alias := CurTok.SVal;
    Next;                          { consume the alias identifier }
    { Map the alias to the REAL unit's Strs[] index — the same normalisation
      ParseUsesUnit used to tag the unit's symbols (basename for a path). }
    isPath := False;
    for i := 1 to Length(uname) do if uname[i] = '/' then isPath := True;
    if isPath then realLo := LowerCase(GetFileBaseName(uname)) else realLo := LowerCase(uname);
    realStrIdx := InternStr(realLo);
    aStrIdx := InternStr(LowerCase(alias));
    if (UnitAliasCount < 64) and (aStrIdx <> realStrIdx) then
    begin
      UnitAliasName[UnitAliasCount] := aStrIdx;
      UnitAliasReal[UnitAliasCount] := realStrIdx;
      Inc(UnitAliasCount);
    end;
  end;
end;

{ Compile a unit's `initialization` section into a synthesized parameterless
  proc and register it in InitProcs[]. The dialect has no real init execution,
  so ParseUnit used to drop these tokens; this emits a normal proc body that the
  program entry calls (in dependency order) before `main begin`. Precondition:
  the `initialization` keyword has been consumed; statements run until `end` or
  `finalization`. Leaves the parser positioned at that terminator. }
procedure ParseInitializationSection(const uname: AnsiString);
var
  procIdx, savedSC, savedFS, savedGLC, savedGFC, j, patchPos: Integer;
  seqNode, lastSeq, stmtNode: Integer;
  dummyNames: array[0..0] of AnsiString;
  dummyTypes: array[0..0] of TTypeKind;
begin
  procIdx := RegisterProc('__init_' + uname, False, tyInteger, 0, dummyNames, dummyTypes);
  if TargetArch = TARGET_XTENSA then
    while (CodeLen mod 4) <> 0 do xtensa_nop; { CALL0 targets must be 4-aligned }
  Procs[procIdx].BodyAddr := CodeLen;

  savedSC := SymCount; savedFS := FrameSize;
  LocalInitCount := 0;   { routine-local typed-const initializers, flushed in the prologue }
  savedGLC := GotoLabelCount; savedGFC := GotoFixupCount;
  GotoLabelCount := 0; GotoFixupCount := 0;
  for j := 0 to MAX_GOTO_LABELS - 1 do GotoLabelIRId[j] := -1;
  FrameSize := 0;
  CurProc := procIdx;
  Procs[procIdx].ScopeBase := SymCount;

  patchPos := EmitProcPrologue;
  Procs[procIdx].FramePatch := patchPos;
  if (TargetArch = TARGET_XTENSA) and (XtensaABI = XTENSA_ABI_WINDOWED) then
    xtensa_mov(reg_xtensa_a7, reg_xtensa_a15);

  { Optional local var/const/type sections (rare in init, but harmless). }
  while CurTok.Kind in [tkVar, tkConst, tkType] do
    case CurTok.Kind of
      tkVar:   ParseVarSection;
      tkConst: ParseConstSection;
      tkType:  ParseTypeSection;
    end;
  for j := savedSC to SymCount - 1 do
    if (Syms[j].Kind = skLocal) and Syms[j].IsArray and (Syms[j].ArrLen = -1) then
    begin
      EmitB($48); EmitB($C7); EmitB($85); EmitI32(Syms[j].Offset); EmitI32(0);
    end;
  CompilePendingLocalInits;   { routine-local typed-const init assignments }

  { Statements until `end` or `finalization` (an identifier, not a token). }
  seqNode := AllocNode(AN_SEQ);
  lastSeq := seqNode;
  while not (CurTok.Kind in [tkEnd, tkEOF]) and
        not ((CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'finalization')) do
  begin
    stmtNode := ParseStatementAST;
    Eat(tkSemicolon);
    if ASTLeft[lastSeq] = -1 then
      ASTLeft[lastSeq] := stmtNode
    else
    begin
      ASTRight[lastSeq] := AllocNode(AN_SEQ);
      lastSeq := ASTRight[lastSeq];
      ASTLeft[lastSeq] := stmtNode;
    end;
  end;
  CompileAST(seqNode);
  ASTNodeCount := 0;

  EmitProcEpilog(-1);
  PatchProcPrologue(patchPos, FrameSize);

  SymRollbackTo(savedSC); FrameSize := savedFS;
  GotoLabelCount := savedGLC; GotoFixupCount := savedGFC;
  CurProc := -1;

  if InitProcCount < 256 then
  begin
    InitProcs[InitProcCount] := procIdx;
    Inc(InitProcCount);
  end;
end;

procedure ParseUnit;
var
  uname: AnsiString;
  doneUses, savedInterface, doneImp, savedPreScan, savedPass2Active: Boolean;
  savedBase, afterImpTok, ii, savedPass2BodyTok: Integer;
begin
  { A used unit parses in its own normal (single-pass) mode: its interface is
    already forward-visible, so the enclosing program's pre-scan must not leak in
    and make ParseSubroutine skip the unit's bodies. }
  savedPreScan := PreScanPass;
  PreScanPass := False;
  Expect(tkUnit, 'unit');
  if CurTok.Kind <> tkIdent then Error('expected unit name');
  uname := ReadDottedUsesName;   { accept dotted `unit Posix.SysSocket;` headers }
  Expect(tkSemicolon, ';');

  if CurTok.Kind <> tkIdent then Error('expected interface section');
  if (CurTok.SVal <> 'interface') and (CurTok.SVal <> 'Interface') then
    Error('expected interface section');
  Next;

  savedInterface := InInterface;
  InInterface := True;

  while (CurTok.Kind <> tkEOF) and not ((CurTok.Kind = tkIdent) and ((CurTok.SVal = 'implementation') or (CurTok.SVal = 'Implementation'))) do
  begin
    case CurTok.Kind of
      tkUses:
      begin
        Next;
        doneUses := False;
        while (CurTok.Kind in [tkIdent, tkString]) and not doneUses do
        begin
          ParseUsesEntry;
          if not Eat(tkComma) then doneUses := True;
        end;
        Eat(tkSemicolon);
      end;
      tkVar:      ParseVarSection;
      tkConst:    ParseConstSection;
      tkType:     ParseTypeSection;
      tkClass,
      tkProcedure,
      tkFunction: ParseSubroutine;
      tkIdent:
        { `resourcestring` sections (FPC rtlconsts et al) register as plain
          string constants — pxx has no resource tables; the format-arg
          machinery lives in whoever consumes the string. }
        if CaseEqual(CurTok.SVal, 'resourcestring') then ParseConstSection
        else Next;
      else
        Next;
    end;
  end;

  if CurTok.Kind = tkEOF then Error('expected implementation section');
  Next; { Skip 'implementation' }

  InInterface := False;

  { ===== Implementation pre-scan (pass 1) =====
    Same whole-section forward visibility as the program body, but scoped to this
    unit's implementation: an impl-private helper may be called before it is
    defined (and mutual recursion needs no `forward`). The unit's interface
    routines were already registered above, so this only adds the impl-only ones.
    Subroutine spans are recorded in a region of the shared DeclItem arrays based
    at the caller's DeclItemCount, so nested `uses` (which recurse into ParseUnit)
    stack cleanly and the enclosing program's spans are preserved. }
  savedBase := DeclItemCount;
  PreScanPass := True;
  doneImp := False;
  while (CurTok.Kind <> tkEOF) and not doneImp do
  begin
    if CurTok.Kind = tkEnd then
    begin
      { Could be 'end.' or end of a case/begin inside a subroutine. }
      { However, at top level of implementation, a standalone 'end' is the end of the unit. }
      { Let's see if the next token is tkDot. }
      if (TokPos < TokCount) and (Tokens[TokPos].Kind = tkDot) then
        doneImp := True
      else
        Next;
    end
    else
    begin
      case CurTok.Kind of
        tkUses:
        begin
          Next;
          doneUses := False;
          while (CurTok.Kind in [tkIdent, tkString]) and not doneUses do
          begin
            ParseUsesEntry;
            if not Eat(tkComma) then doneUses := True;
          end;
          Eat(tkSemicolon);
        end;
        tkVar:      ParseVarSection;
        tkConst:    ParseConstSection;
        tkType:     ParseTypeSection;
        tkClass,
        tkProcedure,
        tkFunction:
        begin
          if DeclItemCount >= MAX_DECL_ITEMS then Error('too many implementation declarations');
          DeclItemStart[DeclItemCount] := TokPos - 1;
          ParseSubroutine;
          if not GenericMethodBuffered then
          begin
            DeclItemEnd[DeclItemCount] := TokPos - 1;
            Inc(DeclItemCount);
          end;
        end;
        tkIdent:
          { constructor/destructor are identifiers in this dialect, not tokens;
            their method bodies live in the unit implementation just like
            procedure/function bodies. }
          if CaseEqual(CurTok.SVal, 'constructor') or CaseEqual(CurTok.SVal, 'destructor') then
          begin
            if DeclItemCount >= MAX_DECL_ITEMS then Error('too many implementation declarations');
            DeclItemStart[DeclItemCount] := TokPos - 1;
            ParseSubroutine;
            if not GenericMethodBuffered then
            begin
              DeclItemEnd[DeclItemCount] := TokPos - 1;
              Inc(DeclItemCount);
            end;
          end
          else if CaseEqual(CurTok.SVal, 'initialization') then
          begin
            { initialization emits its body in place; run it in full (not
              body-deferred) — all routines above are already registered. }
            Next;                       { consume 'initialization' }
            PreScanPass := False;
            ParseInitializationSection(uname);
            PreScanPass := True;
          end
          else if CaseEqual(CurTok.SVal, 'operator') then
          begin
            { operator defs rewrite the token stream and emit their body in
              place, like the top-level decl loop. Without this dispatch the
              `else Next` below silently skipped the whole definition, so no
              overload was registered and `a + b` on records fell through to
              a scalar binop (bug-unit-operator-def-silently-skipped). }
            PreScanPass := False;
            ParseOperatorDef;
            PreScanPass := True;
          end
          else if CaseEqual(CurTok.SVal, 'resourcestring') then
            ParseConstSection           { registers as plain string constants }
          else
            Next;                       { 'finalization' + its body are skipped }
        else
          Next;
      end;
    end;
  end;
  PreScanPass := False;
  afterImpTok := TokPos - 1;   { the unit's terminating `end` }

  { ===== Body pass (pass 2) =====
    Replay the recorded impl subroutines to emit their bodies, now that the whole
    implementation is visible. }
  savedPass2Active := Pass2Active;
  savedPass2BodyTok := Pass2BodyTok;
  Pass2BodyTok := afterImpTok;
  Pass2Active  := True;
  ii := savedBase;
  while ii < DeclItemCount do   { not a fixed `for`: a lifted nested routine appends fresh items mid-loop }
  begin
    TokPos := DeclItemStart[ii];
    Next;
    ParseSubroutine;
    Inc(ii);
  end;
  afterImpTok := Pass2BodyTok;   { kept in sync with pass-2 token edits }
  Pass2Active  := savedPass2Active;
  Pass2BodyTok := savedPass2BodyTok;
  TokPos := afterImpTok;
  Next;
  DeclItemCount := savedBase;

  InInterface := savedInterface;
  PreScanPass := savedPreScan;

  Expect(tkEnd, 'end');
  Expect(tkDot, '.');
end;

{ ===== Program ===== }

procedure DetectPascalRuntimeNeeds(var needsHeap, needsAnsiRuntime: Boolean);
{ Conservative pre-scan for optional emitted runtime support. Imported units
  are treated as opaque: keep the support bundle if uses is present. }
var i: Integer; name: AnsiString;
begin
  needsHeap := False;
  needsAnsiRuntime := PasDefineExists('PXX_MANAGED_STRING');
  i := 0;
  while i < TokCount do
  begin
    if Tokens[i].Kind in [tkUses, tkArray, tkClass] then
      needsHeap := True;
    { 32-bit cross targets write floats through the builtinheap Pascal
      helpers (PXXWriteFloat*), so any float-producing token pulls the unit.
      tkSlash counts: integer / integer yields a float. }
    if ((TargetArch = TARGET_I386) or (TargetArch = TARGET_ARM32) or
        (TargetArch = TARGET_XTENSA) or (TargetArch = TARGET_RISCV32)) and
       (Tokens[i].Kind in [tkFloat, tkSlash]) then
      needsHeap := True;
    if Tokens[i].Kind = tkUses then
      needsAnsiRuntime := True;
    if Tokens[i].Kind = tkIdent then
    begin
      name := GetTokenStr(i);
      if CaseEqual(name, 'AnsiString') or CaseEqual(name, 'Variant') then
        needsAnsiRuntime := True;
      if ((TargetArch = TARGET_I386) or (TargetArch = TARGET_ARM32) or
          (TargetArch = TARGET_XTENSA) or (TargetArch = TARGET_RISCV32)) and
         (CaseEqual(name, 'Single') or CaseEqual(name, 'Double') or
          CaseEqual(name, 'Real') or CaseEqual(name, 'Extended')) then
        needsHeap := True;
      if CaseEqual(name, 'New') or CaseEqual(name, 'Dispose') or
         CaseEqual(name, 'ReallocMem') or CaseEqual(name, 'SetLength') or
         { getmem/freemem are soft keywords (plain idents) now — match by name
           like New/Dispose, replacing the old tkGetMem/tkFreeMem kind check. }
         CaseEqual(name, 'GetMem') or CaseEqual(name, 'FreeMem') then
        needsHeap := True;
    end;
    Inc(i);
  end;
  if needsAnsiRuntime then needsHeap := True;
end;

procedure FixupTVarRecLayout;
{ builtinheap declares TVarRec with three sequential fields; here we overlap
  VAnsiString onto the value union (VInteger's offset) and right-size the record
  to a pointer-sized tag plus one pointer-sized value slot — exactly FPC's
  system.TVarRec (SizeOf 16 on x86-64, 8 on i386). Records the resolved id in
  TVarRecId for the `array of const` parser/lowering paths. }
var ci, fi: Integer;
begin
  TVarRecId := REC_NONE;
  ci := FindUClass('TVarRec');
  if ci < 0 then Exit;
  TVarRecId := REC_UCLASS_BASE + ci;
  { Overlap every value-union field onto the single pointer-sized value slot at
    offset TARGET_PTR_SIZE (field 0 = VType stays at offset 0). VInteger already
    lands there from the sequential layout; VAnsiString/VBoolean/VChar/VPointer/
    VPChar/VInt64/VExtended are forced onto it so `array of const` element reads
    by tag all hit the same slot — exactly FPC's variant TVarRec. }
  for fi := UClsFBase[ci] + 1 to UClsFBase[ci] + UClsFCount[ci] - 1 do
    UFldOff_[fi] := TARGET_PTR_SIZE;
  UClsSize_[ci] := 2 * TARGET_PTR_SIZE;
  UClsAlign[ci] := TARGET_PTR_SIZE;
end;

procedure CompilePendingGlobalInits;
{ Emit the recorded constant global-var initializers as assignments, at the
  current code position (just before `main begin`). }
var i, identNode, valNode, idxLit, target, assignNode, lenVal, innerAddr: Integer;
begin
  for i := 0 to PendingInitCount - 1 do
  begin
    identNode := AllocNode(AN_IDENT);
    ASTIVal[identNode] := PendingInitSym[i];
    ASTTk[identNode] := Ord(Syms[PendingInitSym[i]].TypeKind);

    target := identNode;

    if PendingInitElem[i] >= 0 then
    begin
      idxLit := AllocNode(AN_INT_LIT);
      ASTIVal[idxLit] := PendingInitElem[i];
      ASTTk[idxLit] := Ord(tyInteger);
      target := AllocNode(AN_INDEX);
      ASTLeft[target] := identNode;
      ASTRight[target] := idxLit;
      ASTTk[target] := PendingInitTk[i];
    end;

    if PendingInitFOff[i] >= 0 then
    begin
      { Record typed-const field: `sym.field := value`; when Elem is also set,
        this becomes `sym[elem].field := value`. }
      valNode := AllocNode(AN_FIELD);
      ASTLeft[valNode] := target;
      ASTSOffset[valNode] := PendingInitFOff[i];
      ASTSLen[valNode] := PendingInitFLen[i];
      target := valNode;
      ASTTk[target] := PendingInitTk[i];
    end;

    if PendingInitElem[i] = -2 then
    begin
      { Address-of-global pointer init: `T *p = &g;` or `T *p = &arr[N];`.
        Emit `p := @g` (AN_ADDR of target sym) or `p := @g + byte_offset`
        (ValAux carries the byte offset; 0 = plain &g). }
      valNode := AllocNode(AN_IDENT);
      ASTIVal[valNode] := PendingInitVal[i];
      ASTTk[valNode] := Ord(Syms[PendingInitVal[i]].TypeKind);
      innerAddr := AllocNode(AN_ADDR);
      ASTLeft[innerAddr] := valNode;
      ASTTk[innerAddr] := Ord(tyPointer);
      valNode := innerAddr;
      if PendingInitValAux[i] <> 0 then
      begin
        { &arr[offset]: add constant byte offset to array base pointer }
        idxLit := AllocNode(AN_INT_LIT);
        ASTIVal[idxLit] := PendingInitValAux[i];
        ASTTk[idxLit] := Ord(tyInt64);
        innerAddr := AllocNode(AN_BINOP);
        ASTIVal[innerAddr] := Ord(tkPlus);
        ASTLeft[innerAddr] := valNode;
        ASTRight[innerAddr] := idxLit;
        ASTTk[innerAddr] := Ord(tyPointer);
        valNode := innerAddr;
      end;
      { re-point: assignment target is the pointer sym, value is the address }
      target := identNode;
    end
    else if PendingInitFOff[i] = -4 then
    begin
      { C pointer-array element initialized to the address of a named global
        (a `char[]` array name decaying to `char*`, or `&g`). Value index in
        PendingInitVal is the target sym; emit `arr[ei] := @g`. The array
        element target was already built above (Elem >= 0 => AN_INDEX). }
      valNode := AllocNode(AN_IDENT);
      ASTIVal[valNode] := PendingInitVal[i];
      ASTTk[valNode] := Ord(Syms[PendingInitVal[i]].TypeKind);
      innerAddr := AllocNode(AN_ADDR);
      ASTLeft[innerAddr] := valNode;
      ASTTk[innerAddr] := Ord(tyPointer);
      valNode := innerAddr;
    end
    else if (PendingInitFOff[i] = -3) or (PendingInitKind[i] = 1) then
    begin
      { C pointer-array string initializer, e.g. char-star array from strings.
        PendingInitVal/FLen carry the raw token-string span; assignment lowering
        applies the C string-literal-to-char-pointer +8 adjustment. }
      valNode := AllocNode(AN_STR_LIT);
      ASTSOffset[valNode] := PendingInitVal[i];
      if PendingInitFOff[i] = -3 then lenVal := PendingInitFLen[i]
      else lenVal := PendingInitValAux[i];
      ASTSLen[valNode] := lenVal;
      ASTTk[valNode] := Ord(tyString);
    end
    else if PendingInitKind[i] = 2 then
    begin
      valNode := AllocNode(AN_PROCADDR);
      ASTIVal[valNode] := PendingInitVal[i];
      ASTTk[valNode] := Ord(tyPointer);
    end
    else if PendingInitKind[i] = 4 then
    begin
      valNode := AllocNode(AN_IDENT);
      ASTIVal[valNode] := PendingInitVal[i];
      ASTTk[valNode] := Ord(Syms[PendingInitVal[i]].TypeKind);
      innerAddr := AllocNode(AN_ADDR);
      ASTLeft[innerAddr] := valNode;
      ASTTk[innerAddr] := Ord(tyPointer);
      valNode := innerAddr;
    end
    else if PendingInitKind[i] = 3 then
    begin
      valNode := AllocNode(AN_FLOAT_LIT);
      ASTIVal[valNode] := PendingInitVal[i];
      ASTTk[valNode] := PendingInitTk[i];
    end
    else if PendingInitKind[i] = 5 then
    begin
      { metaclass const init: class VMT address }
      valNode := AllocNode(AN_CLASSREF);
      ASTIVal[valNode] := PendingInitVal[i];
      ASTTk[valNode] := Ord(tyPointer);
    end
    else
    begin
      valNode := AllocNode(AN_INT_LIT);
      ASTIVal[valNode] := PendingInitVal[i];
      ASTTk[valNode] := PendingInitTk[i];
    end;

    assignNode := AllocNode(AN_ASSIGN);
    ASTLeft[assignNode] := target;
    ASTRight[assignNode] := valNode;

    CompileAST(assignNode);
    ASTNodeCount := 0;
  end;
end;

procedure ParseProgram;
var jmpPatch, i, j: Integer; doneUses, doneDecls, hasExceptions, needsBuiltin,
    needsHeap, needsAnsiRuntime, needHeapUnit, hasCoroutine, needsTextfile: Boolean;
    usesTextfile: Boolean; tnm: AnsiString;
    savedUnitIdx, afterDeclTok: Integer;
    dummyNames: array[0..7] of AnsiString;
    dummyTypes: array[0..7] of TTypeKind;
begin
  PendingInitCount := 0;
  ArrTypeCount := 0;
  StrConstCount := 0;
  SetConstCount := 0;
  { Decl-order gating defaults: no body active (a high sentinel means "see all"
    outside a routine body — main body + pre-scan), strict by default. }
  CurBodyHdrTok    := $7FFFFFFF;
  DeclOrderStrict  := not LaxDeclOrder;   { strict by default; --lax-decl-order / {$DECLORDER OFF} opts out }
  { The `program Name;` header is OPTIONAL, matching FPC (and Turbo Pascal
    back to 1.0, where the heading was decorative) — a source that opens
    directly with uses/type/var/const/begin/... is a valid program
    (bug-pascal-headerless-program; 111 FPC-conformance tests hit this).
    A file that opens with `unit` is a unit compiled as a program: pxx is a
    whole-program compiler with no .ppu model, so say that plainly instead
    of "expected program". }
  if CurTok.Kind = tkUnit then
    Error('this file is a unit, not a program — compile a program that uses it (pxx has no standalone-unit output)');
  if CurTok.Kind = tkProgram then
  begin
    Next;
    if CurTok.Kind = tkEOF then Error('expected program name');
    DbgProgName := CurTok.SVal;  { -g: names the main-body subprogram }
    Next;  { program name can be any identifier (even keyword) }
    if CurTok.Kind = tkLParen then
      begin Next; while CurTok.Kind <> tkRParen do Next; Next; end;
    Eat(tkSemicolon);
  end
  else
    DbgProgName := 'program';    { headerless: anonymous main subprogram for -g }

  { Reserve BSS[0..7] for initial rsp (argv access) }
  BSS_INITIAL_RSP := BSSSize; Inc(BSSSize, 8);
  BSS_HEAP_PTR    := BSSSize; Inc(BSSSize, 8);
  BSS_HEAP_END    := BSSSize; Inc(BSSSize, 8);
  BSS_FREE_LIST   := BSSSize; Inc(BSSSize, 8);
  BSS_HEAP_LOCK   := BSSSize; Inc(BSSSize, 8);
  BSS_LINE_POS    := BSSSize; Inc(BSSSize, 8);
  BSS_LINE_LEN    := BSSSize; Inc(BSSSize, 8);
  BSS_PEEK_VALID  := BSSSize; Inc(BSSSize, 8);
  BSS_PEEK_BYTE   := BSSSize; Inc(BSSSize, 8);
  BSS_LINE_BUF    := BSSSize; Inc(BSSSize, LINE_BUF_SIZE);
  BSS_INTBUF      := BSSSize; Inc(BSSSize, INTBUF_SIZE);
  BSS_IO_OWNER    := BSSSize; Inc(BSSSize, 8);
  BSS_IO_DEPTH    := BSSSize; Inc(BSSSize, 8);
  BSS_SIG_HOOKS   := BSSSize; Inc(BSSSize, 64 * 8);
  BSS_SIG_SCRATCH := BSSSize; Inc(BSSSize, 32);
  ExceptionUsed := False;
  CoroutineUsed := False;
  CloneStubAddr := 0;        { 0 = clone+trampoline stub not yet emitted (lazy) }
  hasExceptions := False;
  hasCoroutine := False;
  needsBuiltin := False;
  needsTextfile := False;
  { Default standard surface: textfile (classic Text/Assign/Reset/WriteLn) is
    loaded by default on every non-ESP program, so `var f: Text` resolves
    uniformly in programs, units, methods, and nested scopes — no token-scan
    special case. Its numeric write dispatch formats through builtin's
    StrInt/StrFloat, so builtin is pulled in too. ESP backends (xtensa/riscv32)
    cannot compile either unit yet, so they stay opt-in via explicit `uses`. }
  { Source opt-out: a program defining PXX_NODEFAULTRTL (the compiler itself does)
    suppresses the default surface the same as the --no-default-rtl flag. The
    define travels with the source, so every self-build path — bootstrap,
    cross-bootstrap, stabilize, manual — opts out without per-site Makefile flags. }
  if PasDefineExists('PXX_NODEFAULTRTL') then NoDefaultRtl := True;
  { Only pull the implicit textfile surface when the source actually references
    the file type. Scanning the already-lexed token stream up front for a bare
    `Text`/`TextFile`/`IOResult` identifier (any position — var/param/field/
    return/method, so more robust than the old `: Text` positional scan) skips
    the ~0.19s textfile+builtin load for the common file-less program (plain
    writeln to stdout uses builtins, not the textfile RTL). A length pre-check
    avoids building a string for every token. An explicit `uses textfile` still
    loads it regardless (handled in the token loop below). }
  if (not NoDefaultRtl) and
     (TargetArch <> TARGET_XTENSA) and ((TargetArch <> TARGET_RISCV32) or (not EspBareBoot)) then
  begin
    usesTextfile := False;
    for i := 0 to TokCount - 1 do
      if (Tokens[i].Kind = tkIdent) and
         ((Tokens[i].SLen = 4) or (Tokens[i].SLen = 8)) then
      begin
        tnm := GetTokenStr(i);
        if CaseEqual(tnm, 'text') or CaseEqual(tnm, 'textfile') or CaseEqual(tnm, 'ioresult') then
        begin usesTextfile := True; Break; end;
      end;
    if usesTextfile then
    begin
      needsBuiltin := True;
      needsTextfile := True;
    end;
  end;
  DetectPascalRuntimeNeeds(needsHeap, needsAnsiRuntime);
  { Full builtin (Str/Val/Variant) is pulled only for AnsiString/exception
    programs and on demand for Str/Val (token loop below). The heap allocator
    and managed-string helpers live in the separate `builtinheap` unit so a
    heap-only program does not drag in the conversion routines (which need
    features not yet on every target). }
  { Plain AnsiString needs only builtinheap (allocator + PXXStr*), not the full
    builtin conversions. Variant/Str/Val/uses pull builtin in the token loop. }
  needHeapUnit := needsHeap or needsAnsiRuntime or ComInterfaceUsed;

  if needHeapUnit then
  begin
    savedUnitIdx := CurrentUnitIdx;
    CurrentUnitIdx := InternStr('builtinheap');

    dummyNames[0] := 'size';  dummyTypes[0] := tyNativeInt;
    dummyNames[1] := 'align'; dummyTypes[1] := tyInteger;
    i := RegisterProc('PXXAlloc', True, tyPointer, 2, dummyNames, dummyTypes);

    dummyNames[0] := 'p';     dummyTypes[0] := tyPointer;
    i := RegisterProc('PXXFree', False, tyPointer, 1, dummyNames, dummyTypes);

    dummyNames[0] := 'p';     dummyTypes[0] := tyPointer;
    dummyNames[1] := 'newSize'; dummyTypes[1] := tyNativeInt;
    dummyNames[2] := 'align'; dummyTypes[2] := tyInteger;
    i := RegisterProc('PXXRealloc', True, tyPointer, 3, dummyNames, dummyTypes);

  { Managed-string ARC helpers are target-independent (allocator-backed), so
    register them on every target including ESP. }
  dummyNames[0] := 'len';   dummyTypes[0] := tyNativeInt;
  dummyNames[1] := 'src';   dummyTypes[1] := tyPointer;
  i := RegisterProc('PXXStrFromLit', True, tyPointer, 2, dummyNames, dummyTypes);

  { PChar('') / PChar(emptyAnsiString) must not be nil: substitutes a static #0
    byte for a nil managed handle (FPC-compat, prevents nil-deref at C calls). }
  dummyNames[0] := 'p';     dummyTypes[0] := tyPointer;
  i := RegisterProc('PXXPCharOf', True, tyPointer, 1, dummyNames, dummyTypes);

  { Generic dynamic-array Copy support helpers (clamp count + raw byte copy). }
  dummyNames[0] := 'srcData'; dummyTypes[0] := tyPointer;
  dummyNames[1] := 'index';   dummyTypes[1] := tyNativeInt;
  dummyNames[2] := 'count';   dummyTypes[2] := tyNativeInt;
  i := RegisterProc('PXXClampLen', True, tyNativeInt, 3, dummyNames, dummyTypes);

  dummyNames[0] := 'dest';  dummyTypes[0] := tyPointer;
  dummyNames[1] := 'src';   dummyTypes[1] := tyPointer;
  dummyNames[2] := 'n';     dummyTypes[2] := tyNativeInt;
  i := RegisterProc('PXXMemCopy', True, tyPointer, 3, dummyNames, dummyTypes);

  dummyNames[0] := 'lenA';  dummyTypes[0] := tyNativeInt;
  dummyNames[1] := 'srcA';  dummyTypes[1] := tyPointer;
  dummyNames[2] := 'srcB';  dummyTypes[2] := tyPointer;
  dummyNames[3] := 'lenB';  dummyTypes[3] := tyNativeInt;
  i := RegisterProc('PXXStrConcat', True, tyPointer, 4, dummyNames, dummyTypes);

  dummyNames[0] := 'p';     dummyTypes[0] := tyPointer;
  i := RegisterProc('PXXStrIncRef', False, tyPointer, 1, dummyNames, dummyTypes);
  i := RegisterProc('PXXStrDecRef', False, tyPointer, 1, dummyNames, dummyTypes);
  { COM/ARC interface ARC helpers: not on ESP (indirect IMT dispatch the ESP
    backends can't lower; bodies are {$ifndef PXX_ESP}-guarded in builtinheap). }
  if (TargetArch <> TARGET_XTENSA) and (TargetArch <> TARGET_RISCV32) then
  begin
    dummyNames[0] := 'fatptr'; dummyTypes[0] := tyPointer;
    i := RegisterProc('PXXIntfAddRef', True, tyNativeInt, 1, dummyNames, dummyTypes);
    i := RegisterProc('PXXIntfRelease', True, tyNativeInt, 1, dummyNames, dummyTypes);
    dummyNames[0] := 'imt';  dummyTypes[0] := tyPointer;
    dummyNames[1] := 'inst'; dummyTypes[1] := tyPointer;
    i := RegisterProc('PXXIntfAddRefRaw', True, tyNativeInt, 2, dummyNames, dummyTypes);
    dummyNames[0] := 'dest'; dummyTypes[0] := tyPointer;
    dummyNames[1] := 'src';  dummyTypes[1] := tyPointer;
    i := RegisterProc('PXXIntfAssign', False, tyPointer, 2, dummyNames, dummyTypes);
  end;
  dummyNames[0] := 'strSlot'; dummyTypes[0] := tyPointer;
  i := RegisterProc('PXXStrUnique', True, tyPointer, 1, dummyNames, dummyTypes);
  dummyNames[0] := 'strSlot'; dummyTypes[0] := tyPointer;
  dummyNames[1] := 'newLen';  dummyTypes[1] := tyNativeInt;
  i := RegisterProc('PXXStrSetLen', False, tyPointer, 2, dummyNames, dummyTypes);

  dummyNames[0] := 'lenA';  dummyTypes[0] := tyNativeInt;
  dummyNames[1] := 'srcA';  dummyTypes[1] := tyPointer;
  dummyNames[2] := 'lenB';  dummyTypes[2] := tyNativeInt;
  dummyNames[3] := 'srcB';  dummyTypes[3] := tyPointer;
  i := RegisterProc('PXXStrEq', True, tyInt64, 4, dummyNames, dummyTypes);

  { Xtensa software integer-divide helpers: only when targeting an LX6 part
    (--xtensa-cpu=lx6). Registered (hence emitted) only then so LX7 images
    stay lean and keep their native quos/rems. }
  if (TargetArch = TARGET_XTENSA) and XtensaSoftDivide then
  begin
    dummyNames[0] := 'n'; dummyTypes[0] := tyUInt32;
    dummyNames[1] := 'd'; dummyTypes[1] := tyUInt32;
    i := RegisterProc('__pxx_udivsi3', True, tyUInt32, 2, dummyNames, dummyTypes);
    dummyNames[0] := 'a'; dummyTypes[0] := tyInteger;
    dummyNames[1] := 'b'; dummyTypes[1] := tyInteger;
    i := RegisterProc('__pxx_divsi3', True, tyInteger, 2, dummyNames, dummyTypes);
    i := RegisterProc('__pxx_modsi3', True, tyInteger, 2, dummyNames, dummyTypes);
  end;

  { File load, variant and float-format helpers are not on ESP yet. }
  if (TargetArch <> TARGET_XTENSA) and (TargetArch <> TARGET_RISCV32) then
  begin
    dummyNames[0] := 'path';  dummyTypes[0] := tyPointer;
    i := RegisterProc('PXXStrLoadFile', True, tyPointer, 1, dummyNames, dummyTypes);

    dummyNames[0] := 'dest';      dummyTypes[0] := tyPointer;
    dummyNames[1] := 'left';      dummyTypes[1] := tyPointer;
    dummyNames[2] := 'right';     dummyTypes[2] := tyPointer;
    dummyNames[3] := 'opTk';      dummyTypes[3] := tyNativeInt;
    dummyNames[4] := 'isCompare'; dummyTypes[4] := tyNativeInt;
    i := RegisterProc('PXXVarBinOp', True, tyInt64, 5, dummyNames, dummyTypes);

    dummyNames[0] := 'v';         dummyTypes[0] := tyPointer;
    i := RegisterProc('PXXVarClear', False, tyPointer, 1, dummyNames, dummyTypes);
    i := RegisterProc('PXXVarRetain', False, tyPointer, 1, dummyNames, dummyTypes);
    i := RegisterProc('PXXWriteVariant', False, tyPointer, 1, dummyNames, dummyTypes);

    dummyNames[0] := 'p';         dummyTypes[0] := tyPointer;
    i := RegisterProc('PXXWriteFloatNat', False, tyPointer, 1, dummyNames, dummyTypes);
    i := RegisterProc('PXXWriteFloatSci', False, tyPointer, 1, dummyNames, dummyTypes);
    dummyNames[1] := 'decimals';  dummyTypes[1] := tyNativeInt;
    i := RegisterProc('PXXWriteFloatFixed', False, tyPointer, 2, dummyNames, dummyTypes);
  end;

    CurrentUnitIdx := savedUnitIdx;
  end;
  for i := 0 to MAX_GOTO_LABELS - 1 do GotoLabelIRId[i] := -1;
  i := 0;
  while i < TokCount do
  begin
    if Tokens[i].Kind in [tkTry, tkRaise] then hasExceptions := True;
    { The coroutine context-switch stub must be emitted before the main body
      (it is reached only by `call`), so detect any use of the low-level
      __pxxcoswitch intrinsic up front. }
    if (Tokens[i].Kind = tkIdent) and CaseEqual(GetTokenStr(i), '__pxxcoswitch') then
      hasCoroutine := True;
    { Pull in the builtin unit (Str/Val backing) only if the program calls
      Str(...) or Val(...) — name immediately followed by '(', so plain
      variables/params named str/val don't drag it in. No DCE, so this keeps it
      out of programs that never use them. }
    { The full `builtin` unit (Str/Val/Variant) uses frozen-string concat, which
      the ESP backends (xtensa/riscv32) cannot lower, so it is never pulled there
      — a program that genuinely needs Str/Val on ESP fails at the call site
      instead of dragging in an uncompilable unit. }
    if (Tokens[i].Kind = tkIdent) and (i + 1 < TokCount) and
       (Tokens[i + 1].Kind = tkLParen) and
       (CaseEqual(GetTokenStr(i), 'str') or CaseEqual(GetTokenStr(i), 'val')) and
       (TargetArch <> TARGET_XTENSA) and ((TargetArch <> TARGET_RISCV32) or (not EspBareBoot)) then
      needsBuiltin := True;
    { Bare `Copy(...)` on a string lowers to the __pxxStrCopy substring helper in
      the builtin unit (see ParseFactor). Pull the unit so the helper resolves;
      the string-vs-dynarray decision is made at the call site, so a dynarray-only
      Copy just leaves the extra helper unused. ESP can't compile builtin. }
    if (Tokens[i].Kind = tkIdent) and (i + 1 < TokCount) and
       (Tokens[i + 1].Kind = tkLParen) and CaseEqual(GetTokenStr(i), 'copy') and
       (TargetArch <> TARGET_XTENSA) and ((TargetArch <> TARGET_RISCV32) or (not EspBareBoot)) then
      needsBuiltin := True;
    { Bare `Delete(...)` / `Insert(...)` on a string lower to __pxxStrDelete /
      __pxxStrInsert in the builtin unit (see ParseStatementAST). Pull the unit so
      the helpers resolve; a user routine of the same name shadows at the call
      site, leaving the helpers unused. ESP can't compile builtin. }
    if (Tokens[i].Kind = tkIdent) and (i + 1 < TokCount) and
       (Tokens[i + 1].Kind = tkLParen) and
       (CaseEqual(GetTokenStr(i), 'delete') or CaseEqual(GetTokenStr(i), 'insert')) and
       (TargetArch <> TARGET_XTENSA) and ((TargetArch <> TARGET_RISCV32) or (not EspBareBoot)) then
      needsBuiltin := True;
    { Bare `Abs(...)` / `Sqr(...)` lower to the __pxxAbs*/__pxxSqr* helpers in the
      builtin unit (see ParseFactor). Pull the unit so they resolve; a user
      routine of the same name shadows. ESP can't compile builtin. }
    if (Tokens[i].Kind = tkIdent) and (i + 1 < TokCount) and
       (Tokens[i + 1].Kind = tkLParen) and
       (CaseEqual(GetTokenStr(i), 'abs') or CaseEqual(GetTokenStr(i), 'sqr')) and
       (TargetArch <> TARGET_XTENSA) and ((TargetArch <> TARGET_RISCV32) or (not EspBareBoot)) then
      needsBuiltin := True;
    { Bare `UpCase(...)` / `Pos(...)` lower to __pxxUpCase / __pxxPos in the
      builtin unit (see ParseFactor); pull it so they resolve. ESP can't. }
    if (Tokens[i].Kind = tkIdent) and (i + 1 < TokCount) and
       (Tokens[i + 1].Kind = tkLParen) and
       (CaseEqual(GetTokenStr(i), 'upcase') or CaseEqual(GetTokenStr(i), 'pos')) and
       (TargetArch <> TARGET_XTENSA) and ((TargetArch <> TARGET_RISCV32) or (not EspBareBoot)) then
      needsBuiltin := True;
    { Bare `Move(...)` / `FillChar(...)`: System memory primitives live in the
      builtin unit (FPC keeps them in System, no `uses` needed). Pull the unit
      so they resolve; a user routine of the same name shadows at the call
      site. ESP can't compile builtin. }
    if (Tokens[i].Kind = tkIdent) and (i + 1 < TokCount) and
       (Tokens[i + 1].Kind = tkLParen) and
       (CaseEqual(GetTokenStr(i), 'move') or CaseEqual(GetTokenStr(i), 'fillchar') or
        CaseEqual(GetTokenStr(i), 'fillbyte') or CaseEqual(GetTokenStr(i), 'filldword') or
        CaseEqual(GetTokenStr(i), 'comparebyte') or CaseEqual(GetTokenStr(i), 'comparechar')) and
       (TargetArch <> TARGET_XTENSA) and ((TargetArch <> TARGET_RISCV32) or (not EspBareBoot)) then
      needsBuiltin := True;
    { Variant use needs VariantToStr (in builtin) for variant writes — on
      x86-64. Cross targets serve variants from builtinheap (PXXVar* helpers)
      and cannot compile the full builtin unit yet. }
    if (Tokens[i].Kind = tkIdent) and CaseEqual(GetTokenStr(i), 'Variant') and
       (TargetArch = TARGET_X86_64) then
      needsBuiltin := True;
    if (Tokens[i].Kind = tkUses) and
       (TargetArch <> TARGET_XTENSA) and ((TargetArch <> TARGET_RISCV32) or (not EspBareBoot)) then
      needsBuiltin := True;
    { A PChar/PAnsiChar in scope may be converted to string — implicitly in a
      `string` assignment or string-param call, or explicitly via string(pc).
      Both lower to the PCharToString helper (in builtin). Pull the unit so the
      helper resolves in a standalone program. Gated by `not NoDefaultRtl` so the
      compiler's own PXX_NODEFAULTRTL self-build (uses PChar heavily, ships its own
      builtins) never drags in builtin.pas. ESP can't compile builtin. }
    if (not NoDefaultRtl) and (Tokens[i].Kind = tkIdent) and
       (CaseEqual(GetTokenStr(i), 'pchar') or CaseEqual(GetTokenStr(i), 'pansichar')) and
       (TargetArch <> TARGET_XTENSA) and ((TargetArch <> TARGET_RISCV32) or (not EspBareBoot)) then
      needsBuiltin := True;
    Inc(i);
  end;

  if TargetArch = TARGET_I386 then
  begin
    { Cross-target i386: heap (New/Dispose/GetMem), managed strings, and exception runtime. }
    { Entry stub: save esp for argv access, then jmp to main body.
      mov [abs32], esp: 89 25 <GlobRef> }
    EmitB($89); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
    EmitB($E9); jmpPatch := CodeLen; EmitI32(0);
  end
  else if TargetArch = TARGET_ARM32 then
  begin
    { ARM32 entry stub: save sp for argv access, then branch to main body. }
    EmitI32($E59F1000);  { ldr r1, [pc] }
    EmitI32($EA000000);  { b .+8 }
    EmitGlobRef(BSS_INITIAL_RSP);
    EmitI32($E581D000);  { str sp, [r1] }
    jmpPatch := CodeLen;
    EmitI32($EA000000);
  end
  else if TargetArch = TARGET_AARCH64 then
  begin
    { AArch64 entry stub: save sp for argv access, then branch to main body. }
    EmitI32($18000041);  { ldr w1, [pc+8] }
    EmitI32($14000002);  { b [pc+8] }
    EmitGlobRef(BSS_INITIAL_RSP);
    EmitI32($910003E0);  { mov x0, sp }
    EmitI32($F9000020);  { str x0, [x1] }
    jmpPatch := CodeLen;
    EmitI32($14000000);
  end
  else if TargetArch = TARGET_XTENSA then
  begin
    { Bare-metal (Call0 only): no kernel set up a stack, so establish sp at the
      top of SRAM before entering main. EmitLoadConstXtensa drops a literal
      island for the 32-bit address. Must run before any call. }
    if EspBareBoot then
      EmitLoadConstXtensa(reg_xtensa_sp, ESP_BARE_STACK_TOP);
    if XtensaABI = XTENSA_ABI_WINDOWED then
    begin
      { app_main: program-level vars are globals (BSS), so no stack locals --
        but the body still uses the constant-sp expression stack, so reserve
        the spill region up front (no patchable addi on this path). }
      xtensa_entry(reg_xtensa_sp, 32 + XT_EXPR_REGION);
      xtensa_mov(reg_xtensa_a7, reg_xtensa_sp);
      XtSpillDepth := 0;
    end;
    { Enable the FP coprocessor before any add.s/mul.s (bare metal leaves CPENABLE
      clear -> FP would trap). Enable all CPs (harmless: no context switching). }
    if XtensaHasFpu then
    begin
      EmitLoadConstXtensa(reg_xtensa_a8, $FF);
      xtensa_wsr_cpenable(reg_xtensa_a8);
      xtensa_rsync;
    end;
    { Xtensa entry stub: jump to main body. }
    jmpPatch := CodeLen;
    xtensa_j(0);
  end
  else if TargetArch = TARGET_RISCV32 then
  begin
    { Bare-metal: no kernel set up a stack, so establish sp at the top of SRAM
      (grows down toward the image) before entering main. lui+addi covers any
      low bits in the stack-top constant. }
    if EspBareBoot then
    begin
      EmitI32((((ESP_BARE_STACK_TOP + $800) shr 12) shl 12) or (2 shl 7) or $37); { lui sp,hi }
      EmitI32(((ESP_BARE_STACK_TOP and $FFF) shl 20) or (2 shl 15) or (2 shl 7) or $13); { addi sp,sp,lo }
    end;
    { Hosted: save the kernel-provided initial sp (points at argc) for
      ParamCount/ParamStr, like the other hosted targets. }
    if not EspBareBoot then
    begin
      rv32_auipc(reg_t1, 0);
      rv32_jal(reg_zero, 8);
      EmitGlobRef(BSS_INITIAL_RSP);
      rv32_lw(reg_t1, reg_t1, 8);       { t1 = &BSS_INITIAL_RSP }
      rv32_sw(reg_sp, reg_t1, 0);
    end;
    { RISC-V entry stub: jump to main body. }
    jmpPatch := CodeLen;
    EmitI32($0000006F);
  end
  else
  begin
    { Emit entry stub: save rsp then jmp to main body }
    { mov [bss_initial_rsp], rsp: 48 89 24 25 <GlobRef(0)> }
    EmitB($48); EmitB($89); EmitB($24); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
    EmitB($E9); jmpPatch := CodeLen; EmitI32(0);
  end;
  { The emitted AnsiString runtime is x86-64 machine code; i386 string IR ops
    call the builtinheap Pascal helpers directly instead, so skip the shim
    emission there (its AnsiStr*Addr labels stay 0 and are never referenced). }
  if needsAnsiRuntime and (TargetArch = TARGET_X86_64) then EmitAnsiStringRuntime;
  { Integer div-by-zero abort stub (Runtime error 200): unconditional, tiny, and
    referenced by every div/mod site that has no builtinheap PXXDivZero to call.
    x86-64 only for now (other backends keep their per-target hardware behavior
    until their sites get the check — see bug-integer-div-zero-sigfpe-uncatchable). }
  if TargetArch = TARGET_X86_64 then EmitDiv0Stub;
  { Signal runtime (restorer/dispatch/sethook/install stubs): default on for
    the PC target, --no-signals opts out (user decision: no auto-detection —
    predictable process behavior beats size sniffing; the whole runtime is
    ~200 bytes). See feature-signal-handlers. }
  if (TargetArch = TARGET_X86_64) and not NoSignals then EmitSignalRuntime;
  { --threadsafe statement-atomic I/O lock stubs (x86-64 only, like the
    threadsafe atomics themselves). }
  if (TargetArch = TARGET_X86_64) and ThreadSafeMode then EmitIoLockStubs;
  if (TargetArch = TARGET_I386) and ThreadSafeMode then EmitIoLockStubs386;
  if (TargetArch = TARGET_AARCH64) and ThreadSafeMode then EmitIoLockStubsA64;
  if (TargetArch = TARGET_ARM32) and ThreadSafeMode then EmitIoLockStubsArm32;
  if hasExceptions then EnableExceptionRuntime;
  if hasCoroutine then EnableCoroutineRuntime;

  { Compile the runtime units before user declarations, so their proc bodies
    land in the proc region after the entry jump and are resolvable. builtinheap
    (allocator + PXXStr*) first, then the Str/Val/Variant conversions. }
  { The ESP-class targets have no FPU codegen: every float op lowers to the
    __pxx_* soft-float kernels. Pull the softfloat unit implicitly (like
    builtinheap) so hosted riscv32 programs with floats (sysutils pulls float
    code) do not each need a manual `uses softfloat`. FIRST — the builtinheap/
    builtin float bodies compile against the kernels. }
  { arm32 has hardware VFP, but its double->int convert is 32-bit only; a 64-bit
    Trunc/Round of a large double routes to the soft-float __pxx_d2i64 kernel
    (mirrors the C-frontend pull in cparser), so arm32 pulls softfloat too. }
  if ((((TargetArch = TARGET_RISCV32) and (not EspBareBoot))) or (TargetArch = TARGET_ARM32)) and
     (needHeapUnit or needsBuiltin) then
    ParseUsesUnit('softfloat');
  if needHeapUnit then ParseUsesUnit('builtinheap');
  if needsBuiltin then ParseUsesUnit('builtin');
  { Implicit text-file unit (classic `Text`/Assign/Reset/... surface), loaded
    like an explicit `uses textfile` would be — before user declarations, so the
    Text record + its procedures resolve and proc-local `var f: Text` gets normal
    managed-field zero-init. }
  if needsTextfile then ParseUsesUnit('textfile');
  FixupTVarRecLayout;
  DbgGlobalScopeBase := SymCount;  { -g: program globals are declared past here }

  { ===== Declaration pre-scan (pass 1) =====
    Walk the program's top-level declarations registering every routine's header
    (signature), and parsing types/consts/vars/uses for real, but SKIPPING the
    routine bodies — recording each subroutine's token span. After this pass the
    whole section is visible, so a routine may call any other regardless of
    source order and mutual recursion needs no `forward`. Generic/operator/
    specialize/label declarations are handled in full here (not body-deferred);
    they keep their existing source-order visibility. }
  PreScanPass := True;
  DeclItemCount := 0;
  doneDecls := False;
  while not doneDecls do
    case CurTok.Kind of
      tkUses:
      begin
        Next;
        doneUses := False;
        while (CurTok.Kind in [tkIdent, tkString]) and not doneUses do
        begin
          ParseUsesEntry;
          if not Eat(tkComma) then doneUses := True;
        end;
        Eat(tkSemicolon);
      end;
      tkVar:      ParseVarSection;
      tkConst:    ParseConstSection;
      tkType:     ParseTypeSection;
      tkClass,
      tkProcedure,
      tkFunction:
      begin
        if DeclItemCount >= MAX_DECL_ITEMS then Error('too many top-level declarations');
        DeclItemStart[DeclItemCount] := TokPos - 1;
        ParseSubroutine;
        if not GenericMethodBuffered then
        begin
          DeclItemEnd[DeclItemCount] := TokPos - 1;
          Inc(DeclItemCount);
        end;
      end;
      tkIdent:
        { generic / specialize / operator definitions emit their body in place
          (and rewrite the token stream), so they are parsed in full during the
          pre-scan pass — not body-deferred — by clearing PreScanPass around
          them. They are not recorded for the body pass. }
        if CaseEqual(CurTok.SVal, 'generic') then
        begin PreScanPass := False; ParseGenericFunctionDef; PreScanPass := True; end
        else if CaseEqual(CurTok.SVal, 'specialize') then
        begin PreScanPass := False; ParseTopLevelSpecialize; PreScanPass := True; end
        else if CaseEqual(CurTok.SVal, 'operator') then
        begin PreScanPass := False; ParseOperatorDef; PreScanPass := True; end
        else if CaseEqual(CurTok.SVal, 'constructor') or CaseEqual(CurTok.SVal, 'destructor') then
        begin
          if DeclItemCount >= MAX_DECL_ITEMS then Error('too many top-level declarations');
          DeclItemStart[DeclItemCount] := TokPos - 1;
          ParseSubroutine;
          if not GenericMethodBuffered then
          begin
            DeclItemEnd[DeclItemCount] := TokPos - 1;
            Inc(DeclItemCount);
          end;
        end
        else if CaseEqual(CurTok.SVal, 'resourcestring') then
          ParseConstSection             { registers as plain string constants }
        else if CaseEqual(CurTok.SVal, 'label') then
        begin
          Next;
          while CurTok.Kind = tkIdent do
          begin
            if GotoLabelCount >= MAX_GOTO_LABELS then Error('too many labels');
            GotoLabelNOff[GotoLabelCount]    := Tokens[TokPos-1].SOffset;
            GotoLabelNLen[GotoLabelCount]    := Tokens[TokPos-1].SLen;
            GotoLabelCodePos[GotoLabelCount] := -1;
            Inc(GotoLabelCount);
            Next;
            if not Eat(tkComma) then Break;
          end;
          Eat(tkSemicolon);
        end
        else
          doneDecls := True;
      else
        doneDecls := True;
    end;
  PreScanPass := False;
  afterDeclTok := TokPos - 1;   { the program-body `begin` (re-read after pass 2) }

  { ===== Body pass (pass 2) =====
    Re-parse each recorded subroutine, now with the whole section visible, to emit
    its body (the header pass left it as a forward; this completes it). Spans are
    replayed in source order so body code lands in its original relative order. }
  Pass2BodyTok := afterDeclTok;
  Pass2Active  := True;
  i := 0;
  while i < DeclItemCount do   { not a fixed `for`: a lifted nested routine appends fresh items mid-loop }
  begin
    TokPos := DeclItemStart[i];
    Next;
    ParseSubroutine;
    Inc(i);
  end;
  Pass2Active := False;
  TokPos := Pass2BodyTok;
  Next;

  { Patch jmp to point here (start of main body) }
  if TargetArch = TARGET_ARM32 then
    Patch32(jmpPatch, $EA000000 or ((((CodeLen - jmpPatch) div 4) - 2) and $00ffffff))
  else if TargetArch = TARGET_AARCH64 then
    Patch32(jmpPatch, $14000000 or (((CodeLen - jmpPatch) div 4) and $03ffffff))
  else if TargetArch = TARGET_XTENSA then
    Patch24(jmpPatch, EncodeXtensaJ(CodeLen - jmpPatch))
  else if TargetArch = TARGET_RISCV32 then
    Patch32(jmpPatch, EncodeRISCVJAL(0, CodeLen - jmpPatch))
  else
    Patch32(jmpPatch, CodeLen - (jmpPatch + 4));

  { Install the default-managed signals (SIGINT, SIGTERM) at program start —
    graceful Ctrl-C / termination via the dispatch stub (no hook registered =
    redefault + re-raise, so unhandled signals still kill with proper
    killed-by-signal status). }
  if (TargetArch = TARGET_X86_64) and not NoSignals then
  begin
    EmitAsmX64(['mov edi, %', 2]);   IREmitCodeCall(SigInstallAddr);   { SIGINT }
    EmitAsmX64(['mov edi, %', 15]);  IREmitCodeCall(SigInstallAddr);   { SIGTERM }
  end;

  { Run unit initialization sections before the program body, in dependency
    order (a used unit is fully parsed — and its init proc registered — before
    the using unit). This is where e.g. the LCL `Forms` unit creates Application. }
  for i := 0 to InitProcCount - 1 do
    EmitCallProc(InitProcs[i]);

  { Constant global-var initializers run after unit init, before the body. }
  CompilePendingGlobalInits;

  Expect(tkBegin, 'begin');
  DbgMainBodyStart := CodeLen;   { -g: program-body code range → main subprogram }
  ParseBlock;
  DbgMainBodyEnd := CodeLen;
  { -g: snapshot the program's own global vars (skGlobal past the runtime units)
    as children of the main-body subprogram. }
  if DebugInfo then
    for i := DbgGlobalScopeBase to SymCount - 1 do
      if Syms[i].Kind = skGlobal then DbgRecordVar(-1, i, True);
  Expect(tkEnd, 'end');
  Eat(tkDot);

  { Verify all forward goto fixups were resolved }
  for i := 0 to GotoLabelCount - 1 do
    if GotoLabelCodePos[i] = -1 then
    begin
      for j := 0 to GotoFixupCount - 1 do
        if TokSlicesMatch(GotoFixupNOff[j], GotoFixupNLen[j], GotoLabelNOff[i], GotoLabelNLen[i]) then
          Error('goto target label never placed: ' +
            GetTokenStrFromRaw(GotoLabelNOff[i], GotoLabelNLen[i]));
    end;

  EmitExit(0);
  ApplyCallFixups;
end;
