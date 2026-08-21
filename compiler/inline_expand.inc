{ ===== inline_expand.inc — inline routine expansion (feature-inline-routines) =

  Carved out of parser.inc, byte-for-byte, by
  refactor-a-carve-out-plexer-pparser-so-p-owns-its-own-files.

  **Owned by Track A** (language-agnostic core), not by a frontend — and by the
  work-tag Track O, since this is a codegen-cost pass. It operates on the AST
  after parsing, so it serves every frontend; it lived in the Pascal parser's
  file only because Pascal was the seed.

  Included from compiler.pas at exactly the point it used to occupy, so include
  ORDER is unchanged — that is what makes the carve-out provable by the
  self-host fixedpoint rather than by reading it.

  Contents: deciding whether a routine body is simple enough to retain for
  inlining (expression bodies, single-assignment statement bodies, and if/else
  arms that reduce to a ternary), cloning it into the inline region with
  parameters substituted, and the -d diagnostics for what was retained. }

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
function InlineExprSimple(node, procIdx: Integer; allowLocals: Boolean; retSym: Integer;
                          allowResRead: Boolean): Boolean;
var idx, cpi2, argN, argCnt: Integer;
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
        if idx = retSym then
        begin
          { Result-read: slice 2c allows it (Clamp-style guards) — the
            definite-assignment walker (InlineStmtRhsLocalsWritten) separately
            requires an unconditional prior write, so -O0's stack-garbage
            Result is never observable. Shapes 1/2a/2b keep the ban. }
          if not allowResRead then Exit;
          if not InlineScalarTk(Syms[idx].TypeKind) then Exit;
          InlineExprSimple := True;
          Exit;
        end;
        if Syms[idx].IsArray then Exit;
        if not InlineScalarTk(Syms[idx].TypeKind) then Exit;
        if InlineParamIndexOf(procIdx, idx) >= 0 then
          InlineExprSimple := True
        else if Syms[idx].Kind = skGlobal then
        begin
          { Recorded for the PXXDBG=a.inline probe only. A global is MUTABLE, so
            it LOOKS like the same hazard the arguments have — but it is not:
            arguments are placeholders SUBSTITUTED at each use, while the body's
            own global read is cloned in place and lowered in the body's own
            order, so nothing can move it across the body's inner call. Measured
            both ways (`Result := Load + g` and `Result := g + Load`, where Load
            writes g) at -O0/-O2/-O3: identical. Left visible in the probe
            because it is the first thing anyone will suspect. }
          InlineRetentionSawGlobal := True;
          InlineExprSimple := True;
        end
        else if Syms[idx].Kind = skConst then
          InlineExprSimple := True
        else if allowLocals and (Syms[idx].Kind = skLocal) then
          InlineExprSimple := True;
      end;
    AN_BINOP, AN_NEG, AN_NOT:
      InlineExprSimple := InlineExprSimple(ASTLeft[node], procIdx, allowLocals, retSym, allowResRead) and
                          InlineExprSimple(ASTRight[node], procIdx, allowLocals, retSym, allowResRead);
    AN_CALL:
      begin
        { Non-leaf slice (-O3): a direct call to a plain internal scalar
          function is an acceptable expression element. The retained body's
          inner call stays a REAL call after the splice (InliningActive
          blocks re-inlining) — the win is the removed OUTER frame. The
          InlineRetentionSawCall flag makes the splice temp-capture every
          argument: a direct-substituted pure arg would otherwise be re-read
          AFTER the inner call's side effects. }
        if OptLevel < 3 then Exit;
        if ASTRight[node] <> -1 then Exit;         { plain call shape only }
        cpi2 := ASTIVal[node];
        if (cpi2 < 0) or (cpi2 >= ProcCount) then Exit;
        if ProcExternal[cpi2] or ProcCdecl[cpi2] or ProcVariadic[cpi2] then Exit;
        if ProcIsGenerator[cpi2] or ProcIsStackless[cpi2] then Exit;
        if not Procs[cpi2].IsFunc then Exit;
        if not InlineScalarTk(Procs[cpi2].RetType) then Exit;
        argN := ASTLeft[node]; argCnt := 0;
        while argN <> -1 do
        begin
          if ASTKind[argN] <> AN_ARG then Exit;
          if not InlineExprSimple(ASTLeft[argN], procIdx, allowLocals, retSym, allowResRead) then Exit;
          argN := ASTRight[argN];
          Inc(argCnt);
        end;
        if argCnt <> Procs[cpi2].ParamCount then Exit;
        InlineRetentionSawCall := True;
        InlineExprSimple := True;
      end;
  end;
end;

{ PXXDBG=a.inline — one line per routine whose body is RETAINED for inline
  expansion, with the two properties that make the non-leaf slice dangerous.
  Exists because an -O3 inline miscompile is otherwise invisible: the only
  evidence is a wrong value in an unrelated routine, and bisecting by flipping
  `OptLevel < 3` gates tells you which SLICE but never which ROUTINE.
  `shape` is 1 (Result := E), 2 (if/else ternary) or 3 (straight-line body). }
procedure DbgInlineRetained(procIdx, shape: Integer);
begin
  if not PxxDbgEnabled('a.inline') then Exit;
  Write('PXXDBG a.inline RETAIN ', Procs[procIdx].Name, ' shape=', shape,
        ' params=', Procs[procIdx].ParamCount);
  if InlineRetentionSawCall then Write(' hasCall');
  if InlineRetentionSawGlobal then Write(' readsGlobal');
  WriteLn;
end;

{ Alloc a node in the reserved low inline AST region [0..INLINE_AST_RESERVE);
  -1 when that fixed reserve is full (the caller then declines to inline). }
function AllocInlineNode(kind: Integer): Integer;
begin
  if InlineASTNext >= INLINE_AST_RESERVE then begin AllocInlineNode := -1; Exit; end;
  EnsureASTCapacity(INLINE_AST_RESERVE);
  ASTKind[InlineASTNext]     := kind;
  ASTIVal[InlineASTNext]     := 0;
  ASTSOffset[InlineASTNext]  := 0;
  ASTSLen[InlineASTNext]     := 0;
  ASTLeft[InlineASTNext]     := -1;
  ASTRight[InlineASTNext]    := -1;
  ASTTk[InlineASTNext]       := 0;
  ASTLiftedVar[InlineASTNext] := -1;
  ASTLine[InlineASTNext]     := 0;
  ASTFile[InlineASTNext]     := 1;
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
  already be marked written in InlineWrittenLocal, and a Result read requires
  InlineResultDef (slice 2c) — the DEFINITE (all-paths) assignment guard. }
function InlineStmtRhsLocalsWritten(node: Integer): Boolean;
var lidx: Integer;
begin
  InlineStmtRhsLocalsWritten := False;
  if node < 0 then begin InlineStmtRhsLocalsWritten := True; Exit; end;
  if ASTKind[node] = AN_IDENT then
  begin
    if (RetResSym >= 0) and (ASTIVal[node] = RetResSym) then
    begin
      if not InlineResultDef then Exit;
      InlineStmtRhsLocalsWritten := True;
      Exit;
    end;
    lidx := RetLocalIndexOf(ASTIVal[node]);
    if (lidx >= 0) and (not InlineWrittenLocal[lidx]) then Exit;
    InlineStmtRhsLocalsWritten := True;
    Exit;
  end;
  InlineStmtRhsLocalsWritten := InlineStmtRhsLocalsWritten(ASTLeft[node]) and
                                InlineStmtRhsLocalsWritten(ASTRight[node]);
end;

{ Slice 2c: validate one if-arm — a single statement or an AN_SEQ chain of
  statements, each `local := E` / `Result := E` (E over the same simple-expr
  class, reads gated by definite-at-if-entry OR written-earlier-in-THIS-arm)
  or a NESTED if (recursing through InlineIfValidate with the same
  save/validate/merge dataflow). Mutates InlineWrittenLocal/InlineResultDef
  in place (the caller saved the entry state and merges/restores).
  False = the whole retention declines. }
function InlineArmValidate(armNode, procIdx, retSym: Integer): Boolean; forward;

function InlineIfValidate(ifNode, procIdx, retSym: Integer): Boolean;
var condN, pairN, thenA, elseA, j: Integer;
    savedW, thenW: array[0..MAX_INLINE_LOCALS-1] of Boolean;
    savedR, thenR: Boolean;
begin
  InlineIfValidate := False;
  condN := ASTLeft[ifNode];
  pairN := ASTRight[ifNode];
  if (pairN < 0) or (ASTKind[pairN] <> AN_PAIR) then Exit;
  thenA := ASTLeft[pairN];
  elseA := ASTRight[pairN];
  if thenA < 0 then Exit;
  if not InlineExprSimple(condN, procIdx, True, retSym, True) then Exit;
  if not InlineStmtRhsLocalsWritten(condN) then Exit;
  { entry state }
  for j := 0 to RetLocalCnt - 1 do savedW[j] := InlineWrittenLocal[j];
  savedR := InlineResultDef;
  { then-arm (reads may use entry-definite ∪ own earlier writes) }
  if not InlineArmValidate(thenA, procIdx, retSym) then Exit;
  for j := 0 to RetLocalCnt - 1 do thenW[j] := InlineWrittenLocal[j];
  thenR := InlineResultDef;
  { back to entry for the else-arm }
  for j := 0 to RetLocalCnt - 1 do InlineWrittenLocal[j] := savedW[j];
  InlineResultDef := savedR;
  if elseA >= 0 then
  begin
    if not InlineArmValidate(elseA, procIdx, retSym) then Exit;
    { merge: definite after the if = entry ∪ (then ∩ else) }
    for j := 0 to RetLocalCnt - 1 do
      InlineWrittenLocal[j] := savedW[j] or (thenW[j] and InlineWrittenLocal[j]);
    InlineResultDef := savedR or (thenR and InlineResultDef);
  end;
  { no else: definite stays the entry state (already restored) }
  InlineIfValidate := True;
end;

function InlineArmValidate(armNode, procIdx, retSym: Integer): Boolean;
var stmtN, lhsN, rhsN, lidx: Integer;
begin
  InlineArmValidate := False;
  { normalize: a bare assign, a nested if, or a chain }
  if armNode < 0 then Exit;
  if ASTKind[armNode] = AN_ASSIGN then
  begin
    lhsN := ASTLeft[armNode];
    rhsN := ASTRight[armNode];
    if (lhsN < 0) or (ASTKind[lhsN] <> AN_IDENT) then Exit;
    if not InlineExprSimple(rhsN, procIdx, True, retSym, True) then Exit;
    if not InlineStmtRhsLocalsWritten(rhsN) then Exit;
    if ASTIVal[lhsN] = retSym then
      InlineResultDef := True
    else
    begin
      lidx := RetLocalIndexOf(ASTIVal[lhsN]);
      if lidx < 0 then Exit;
      InlineWrittenLocal[lidx] := True;
    end;
    InlineArmValidate := True;
    Exit;
  end;
  if ASTKind[armNode] = AN_IF then
  begin
    InlineArmValidate := InlineIfValidate(armNode, procIdx, retSym);
    Exit;
  end;
  if ASTKind[armNode] <> AN_SEQ then Exit;
  stmtN := armNode;
  while stmtN <> -1 do
  begin
    if ASTKind[stmtN] <> AN_SEQ then Exit;
    if not InlineArmValidate(ASTLeft[stmtN], procIdx, retSym) then Exit;
    stmtN := ASTRight[stmtN];
  end;
  InlineArmValidate := True;
end;

{ Slice 2b (-O2) + 2c (-O3): retain a multi-statement body — an AN_SEQ chain
  where every statement is `local := E` / `Result := E`, or (2c, OptLevel>=3)
  an `if C then <assigns> [else <assigns>]` whose arms are single assigns or
  straight-line assign chains. E over params / scalar globals-consts /
  DEFINITELY-written locals / DEFINITELY-written Result (the Clamp shape).
  Definite = assigned on ALL paths: an arm's writes only survive the merge
  when BOTH arms (with an else present) performed them; Result must be
  definite at the end. All locals scalar ordinal. Retains the whole chain
  with param/local/Result idents rewritten to placeholders. }
procedure TryRetainInlineStmtBody(procIdx, bodyNode, retSym: Integer);
var i, j, seqN, stmtN, startNext, cloned: Integer;
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
  { Validate the chain (definite-assignment dataflow). }
  for j := 0 to RetLocalCnt - 1 do InlineWrittenLocal[j] := False;
  InlineResultDef := False;
  seqN := bodyNode;
  while seqN <> -1 do
  begin
    if ASTKind[seqN] <> AN_SEQ then Exit;
    stmtN := ASTLeft[seqN];
    if stmtN < 0 then Exit;
    if ASTKind[stmtN] = AN_ASSIGN then
    begin
      { top-level assign: same checks as an arm statement, updates definite. }
      if not InlineArmValidate(stmtN, procIdx, retSym) then Exit;
    end
    else if ASTKind[stmtN] = AN_IF then
    begin
      if OptLevel < 3 then Exit;             { 2c lands behind -O3 first }
      if not InlineIfValidate(stmtN, procIdx, retSym) then Exit;
    end
    else
      Exit;
    seqN := ASTRight[seqN];
  end;
  if not InlineResultDef then Exit;          { Result assigned on ALL paths }
  { Retain the whole chain. }
  startNext := InlineASTNext;
  if InlineASTNext + 256 >= INLINE_AST_RESERVE then Exit;
  cloned := CloneToInlineRegion(bodyNode, procIdx);
  if cloned < 0 then begin InlineASTNext := startNext; Exit; end;
  if InlineASTNext - startNext > 256 then begin InlineASTNext := startNext; Exit; end;
  DbgInlineRetained(procIdx, 3);
  InlineBodyRoot[procIdx]   := cloned;
  InlineBodyIsStmt[procIdx] := True;
  InlineBodyHasCall[procIdx] := InlineRetentionSawCall;
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
  InlineRetentionSawCall := False;   { non-leaf slice: set by InlineExprSimple on any accepted AN_CALL }
  InlineRetentionSawGlobal := False; { ...and on any accepted GLOBAL read — diagnostic only, see InlineExprSimple }
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
    if not InlineExprSimple(rhs, procIdx, False, retSym, False) then Exit;
    startNext := InlineASTNext;
    if InlineASTNext + 48 >= INLINE_AST_RESERVE then Exit;    { budget guard }
    i := CloneToInlineRegion(rhs, procIdx);
    if i < 0 then begin InlineASTNext := startNext; Exit; end;
    if InlineASTNext - startNext > 48 then begin InlineASTNext := startNext; Exit; end;
    DbgInlineRetained(procIdx, 1);
    InlineBodyRoot[procIdx] := i;
    InlineParamCnt[procIdx] := Procs[procIdx].ParamCount;
    InlineBodyHasCall[procIdx] := InlineRetentionSawCall;
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
    if not InlineExprSimple(condN, procIdx, False, retSym, False) then Exit;
    if not InlineExprSimple(aE, procIdx, False, retSym, False) then Exit;
    if not InlineExprSimple(bE, procIdx, False, retSym, False) then Exit;
    startNext := InlineASTNext;
    if InlineASTNext + 96 >= INLINE_AST_RESERVE then Exit;
    i := BuildInlineTernary(condN, aE, bE, procIdx, Ord(Syms[retSym].TypeKind));
    if i < 0 then begin InlineASTNext := startNext; Exit; end;
    if InlineASTNext - startNext > 96 then begin InlineASTNext := startNext; Exit; end;
    DbgInlineRetained(procIdx, 2);
    InlineBodyRoot[procIdx] := i;
    InlineParamCnt[procIdx] := Procs[procIdx].ParamCount;
    InlineBodyHasCall[procIdx] := InlineRetentionSawCall;
  end
  else
    TryRetainInlineStmtBody(procIdx, bodyNode, retSym);
end;
