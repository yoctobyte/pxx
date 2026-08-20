{ ===== ast_syminfer.inc — AST-driven symbol typing, layout and debug vars ====

  Carved out of parser.inc, byte-for-byte, by
  refactor-a-carve-out-plexer-pparser-so-p-owns-its-own-files.

  **Owned by Track A** (language-agnostic core), not by a frontend. It reached
  the Pascal parser's file the way most of this did — Pascal was the seed, so
  its file was where things went — but nothing here parses Pascal: every
  frontend that allocates a symbol or infers its type from an AST node runs
  through it.

  Included from compiler.pas at exactly the point it used to occupy, so include
  ORDER is unchanged — that is what makes the carve-out provable by the
  self-host fixedpoint rather than by reading it.

  Contents: the DWARF Tier-3 symbol snapshot (taken while a proc's slots are
  still live, since slots recycle across procs), inferring a symbol's type from
  the node assigned to it, stack-offset allocation, and token text. }

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
  { feature-a-typeref-migrate-consumers: every branch above mutates one of
    TypeKind/RecName/PtrElemTk/PtrElemRec on symIdx; resync SymTR once at the
    single exit point that follows all of them. }
  SymSyncTypeRef(symIdx);
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
