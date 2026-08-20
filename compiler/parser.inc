{ SPDX-License-Identifier: MPL-2.0 }
{$ifdef FPC}
procedure LoadFile(const path: AnsiString; var dst: AnsiString); forward;
procedure LoadFileCI(const path: AnsiString; var dst: AnsiString); forward;
{$endif}
function GetFilePath(const path: AnsiString): AnsiString; forward;
function GetFileBaseName(const path: AnsiString): AnsiString; forward;
procedure NormalizePath(var p: AnsiString); forward;
procedure ExpandIncludes(var src: AnsiString; const baseDir, selfPath: AnsiString); forward;
procedure ExpandPasMacros(var src: AnsiString); forward;
{$ifndef PXX_NO_CFRONT}
procedure ParseCUnit; forward;
procedure RegisterCMacroConsts; forward;
{$endif}
procedure EmitAnsiStringRuntime; forward;
procedure EmitDiv0Stub; forward;
procedure EmitFpcFloatErrStub; forward;
procedure EmitCodeAbsToRdx(targetOff: Integer); forward;   { ir_codegen.inc is included AFTER this file, and the FPC seed build (only it) enforces that — bug-a-fpc-seed-drift-emitasmx64-forward }
procedure EmitPyBitFloatErrStub; forward;
procedure EmitSignalRuntime; forward;
procedure EmitIoLockStubs; forward;
{$ifndef PXX_NO_I386}procedure EmitIoLockStubs386; forward;{$endif}
{$ifndef PXX_NO_AARCH64}procedure EmitIoLockStubsA64; forward;{$endif}
{$ifndef PXX_NO_AARCH64}procedure EmitSignalRuntimeA64; forward;{$endif}
procedure EmitSignalRuntimeRISCV32; forward;
{$ifndef PXX_NO_ARM32}procedure EmitSignalRuntimeArm32; forward;{$endif}
{$ifndef PXX_NO_I386}procedure EmitSignalRuntime386; forward;{$endif}
{$ifndef PXX_NO_ARM32}
procedure EmitIoLockStubsArm32; forward;
{$endif}
{ The per-arch dispatcher every frontend driver must call instead of picking a
  stub itself — see its body in ir_codegen.inc for why that is not optional. }
procedure EmitIoLockStubsForTarget; forward;
procedure EmitSignalRuntimeForTarget; forward;   { its sibling: the one place the per-arch signal runtime is chosen }

{ pxx pre-scans declarations, so a routine may be CALLED above its definition; FPC
  cannot, and the cold-bootstrap seed is built by FPC. Anything defined later in this
  file but used earlier needs a forward here, or `make bootstrap` breaks while every
  pxx-built stage stays perfectly green -- a gap only the fpc-bootstrap job sees. }
function ParamIsVarRecArray(procIdx, argNo: Integer): Boolean; forward;
function ParamIsOpenArrayScalar(procIdx, argNo: Integer): Boolean; forward;
function ByRefArgStartsExpression(constVariantParam: Boolean): Boolean; forward;
function ParamIsConstVariant(pi, slot: Integer): Boolean; forward;
function ParseClassRecordSelectors(node, recId: Integer; var outTk: TTypeKind): Integer; forward;
function ParseMetaclassMemberTail(node, mcCi: Integer; var outTk: TTypeKind;
                                  var outRec: Integer; var finished: Boolean): Integer; forward;  { the ONE member-on-a-class-reference parser -- see its body }
function PyParseClassRecordSelectors(node, recId: Integer; var outTk: TTypeKind): Integer; forward;  { NilPy twin (pyparser.inc) }


{ ===== DWARF -g: the multi-file line table =====================================
  A source other than the main file joins the line table by INTERNING its path
  (DbgFileId) and MARKING the token index where its tokens start
  (DbgMarkTokFile). Two shapes use it:

    NilPy  an imported module is one contiguous run of appended tokens, so it
           marks once at its start.
    C      the preprocessor inlines every #include, so a header's tokens
           interleave with the main file's — a mark at every boundary, which is
           why ranges are a separate, much larger table than files.

  Sources that are NOT marked keep the line-0 treatment (no rows). The Pascal
  RTL and pylib are appended the same way and are left out on purpose: they
  would swamp the table and nobody wants to single-step pystr_upper. }

{ Intern a path, returning its .debug_line file index. 1 is the main file, so
  interned files start at 2. Repeated paths return the same id — a header
  included twice is one file entry with many ranges. }
function DbgFileId(const path: AnsiString): Integer;
var i: Integer;
begin
  DbgFileId := 1;
  if not DebugInfo then Exit;
  for i := 0 to DbgFileCount - 1 do
    if DbgFileName[i] = path then begin DbgFileId := i + 2; Exit; end;
  if DbgFileCount >= MAX_DBG_FILES then Exit;   { silently stop: -g must not fail a build }
  DbgFileName[DbgFileCount] := path;
  Inc(DbgFileCount);
  DbgFileId := DbgFileCount + 1;
end;

{ From token `startTok` on, tokens come from file `fileId`. Ranges must arrive
  in ascending token order (both callers lex forward). A mark identical to the
  current one is dropped, so a run of boundaries that do not actually change
  file costs nothing. }
function CPathIsCModule(const path: AnsiString): Boolean;
{ A top-level C SOURCE, i.e. `.c` — not a header. See CModRange* in defs.inc. }
var n: Integer;
begin
  n := Length(path);
  CPathIsCModule := (n >= 2) and (path[n] = 'c') and (path[n - 1] = '.');
end;

procedure CMarkTokModule(startTok: Integer; const path: AnsiString);
{ Tokens from `startTok` on belong to the C module `path`. Same collapse rules as
  DbgMarkTokFile: a repeat of the current module is a no-op, and a second mark
  at the same token index overwrites rather than stacks. NOT gated on
  DebugInfo — the duplicate-definition check needs this in every build.
  bug-c-static-functions-in-different-crtl-modules-collide }
var modId: Integer;
begin
  if CModRangeCount >= MAX_DBG_RANGES then Exit;
  { interned HERE, not at the call site: clexer.inc is included before emit.inc,
    where InternKey lives, and the FPC seed build has no declare-anywhere
    laxness (bug-a-fpc-seed-drift-emitasmx64-forward).
    InternKey, NOT InternStr: `path` carries ExeDir for anything resolved out of
    lib/crtl, and InternStr would append it to the EMITTED string pool, making a
    C binary's bytes depend on where the compiler binary sat. Measured: one
    `#include <stdio.h>` program compiled by ./compiler/pascal26 vs by a copy
    outside the repo came out 218207 vs 218095 bytes, the difference being
    './compiler/../lib/crtl/src/*.c' spelled into the output.
    bug-a-the-compilers-output-depends-on-argv0 }
  modId := InternKey(path);
  if (CModRangeCount > 0) and (CModRangeId[CModRangeCount - 1] = modId) then Exit;
  if (CModRangeCount > 0) and (CModRangeStart[CModRangeCount - 1] = startTok) then
  begin
    CModRangeId[CModRangeCount - 1] := modId;
    Exit;
  end;
  CModRangeStart[CModRangeCount] := startTok;
  CModRangeId[CModRangeCount] := modId;
  Inc(CModRangeCount);
end;

function CModuleOfTok(t: Integer): Integer;
{ The C module a token belongs to: the last range starting at or before it, or
  -1 (the main source) when none does. Backward scan, like DbgFileOfTok — the
  token asked about is nearly always in the most recent range. }
var i: Integer;
begin
  CModuleOfTok := -1;
  for i := CModRangeCount - 1 downto 0 do
    if t >= CModRangeStart[i] then
    begin
      CModuleOfTok := CModRangeId[i];
      Exit;
    end;
end;

procedure DbgMarkTokFile(startTok, fileId: Integer);
begin
  if not DebugInfo then Exit;
  if DbgRangeCount >= MAX_DBG_RANGES then Exit;
  if (DbgRangeCount > 0) and (DbgRangeFile[DbgRangeCount - 1] = fileId) then Exit;
  if (DbgRangeCount > 0) and (DbgRangeStart[DbgRangeCount - 1] = startTok) then
  begin
    DbgRangeFile[DbgRangeCount - 1] := fileId;   { same index: overwrite, do not stack }
    Exit;
  end;
  DbgRangeStart[DbgRangeCount] := startTok;
  DbgRangeFile[DbgRangeCount] := fileId;
  Inc(DbgRangeCount);
end;

{ The .debug_line file index for a token: the file of the last range starting at
  or before it, or 1 (the main file) when no range does. Backward scan — the
  token being asked about is nearly always in the most recent range. }
function DbgFileOfTok(t: Integer): Integer;
var i: Integer;
begin
  DbgFileOfTok := 1;
  if not DebugInfo then Exit;
  for i := DbgRangeCount - 1 downto 0 do
    if t >= DbgRangeStart[i] then
    begin
      DbgFileOfTok := DbgRangeFile[i];
      Exit;
    end;
end;

{ TRUE when a token belongs to a source the line table describes — the main
  file, or a marked one. Drives ProcDbgMain, i.e. whether a routine gets a
  DW_TAG_subprogram: an imported `.py` module's defs need one or `break scale`
  finds nothing. }
function DbgTokIsDebuggable(t: Integer): Boolean;
begin
  DbgTokIsDebuggable := (t <= DbgMainTokEnd) or (DbgFileOfTok(t) > 1);
end;

procedure EnsureASTCapacity(need: Integer);
{ Grow the per-node AST arrays so index `need-1` is in bounds. Doubling from a base
  that already covers the low inline reserve; capacity never shrinks. ALL parallel
  AST arrays grow in lockstep — a missed one is a silent out-of-bounds. See
  feature-dynamic-compiler-tables. }
var n: Integer;
begin
  if need <= ASTCapacity then Exit;
  if ASTCapacity = 0 then n := 65536 else n := ASTCapacity;
  while n < need do n := n * 2;
  SetLength(ASTKind, n);       SetLength(ASTIVal, n);      SetLength(ASTSOffset, n);
  SetLength(ASTSLen, n);       SetLength(ASTCLongRank, n); SetLength(ASTLeft, n);
  SetLength(ASTRight, n);      SetLength(ASTTk, n);        SetLength(ASTLiftedVar, n);
  SetLength(ASTCallParenless, n);
  SetLength(ASTEnumId, n);     SetLength(ASTLine, n);      SetLength(ASTQChk, n);
  SetLength(ASTFile, n);
  SetLength(ASTRChk, n);       SetLength(ASTIChk, n);
  SetLength(ASTPyUser, n);
  ASTCapacity := n;
end;

function AllocNode(kind: Integer): Integer;
begin
  EnsureASTCapacity(ASTNodeCount + 1);
  ASTKind[ASTNodeCount]    := kind;
  ASTIVal[ASTNodeCount]    := 0;
  ASTSOffset[ASTNodeCount] := 0;
  ASTSLen[ASTNodeCount]    := 0;
  ASTCLongRank[ASTNodeCount] := 0;
  ASTLeft[ASTNodeCount]    := -1;
  ASTRight[ASTNodeCount]   := -1;
  ASTTk[ASTNodeCount]      := 0;
  ASTLiftedVar[ASTNodeCount] := -1;
  ASTCallParenless[ASTNodeCount] := False;
  ASTEnumId[ASTNodeCount]  := -1;
  ASTQChk[ASTNodeCount]    := False;
  { AN_ASSIGN carries its {$R+} region state from birth — one central tag
    instead of 27 build sites. Anchored at the enclosing STATEMENT's first
    token (StmtRChecks), not the current token: a directive between the RHS
    and the statement end must not retro-apply (trange4.pp)
    (feature-pascal-range-checks-r-plus). }
  ASTRChk[ASTNodeCount]    := ((kind = AN_ASSIGN) or (kind = AN_INDEX)) and
                              StmtRChecks;
  ASTIChk[ASTNodeCount]    := (kind = AN_CALL) and StmtIChecks;
  { the Python operator semantics apply to the USER's code, not to a Pascal RTL
    unit compiled into the same program — recorded at birth because the unit
    context is gone by IR lowering (see ASTPyUser in defs.inc) }
  ASTPyUser[ASTNodeCount]  := NilPyUserCode;
  { DWARF -g: stamp the line for nodes from the main source file, and for any
    MARKED source whose token range was recorded with DbgMarkTokFile (an
    imported `.py` module). Everything else — the Pascal RTL, pylib, the unit
    bodies nobody wants to step through — still gets line 0 and contributes no
    rows, which is what keeps the whole runtime out of the line table. }
  ASTFile[ASTNodeCount] := DbgFileOfTok(TokPos);
  if ASTFile[ASTNodeCount] > 1 then
    { a MARKED source: real line, its own file entry. Checked before the
      main-file bound because C's header tokens sit BELOW DbgMainTokEnd — the
      preprocessor inlines them, so they are not "appended" the way a NilPy
      import or a Pascal unit is. }
    ASTLine[ASTNodeCount] := CurTok.Line
  else if TokPos <= DbgMainTokEnd then
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
  ASTCallParenless[Result] := ASTCallParenless[node];
  ASTLine[Result]     := ASTLine[node];
  ASTFile[Result]     := ASTFile[node];
  ASTQChk[Result]     := ASTQChk[node];
  ASTRChk[Result]     := ASTRChk[node];
  ASTIChk[Result]     := ASTIChk[node];
  ASTPyUser[Result]   := ASTPyUser[node];
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
        if (cpi2 < 0) or (cpi2 >= MAX_PROCS) or (cpi2 >= ProcCount) then Exit;
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

procedure ParseExpr; forward;
procedure PyParseBoolExpr; forward;  { Nil Python boolean layer (defined in pyparser.inc) }
function PyParseLValueAST(idx: Integer; identTokIdx: Integer): Integer; forward;  { the NilPy half of ParseLValueAST, carved out into pyparser.inc — ParseLValueAST dispatches here on PyExprMode }
procedure PyParseFactorCore; forward;  { the NilPy half of ParseFactorCore, carved out into pyparser.inc — ParseFactorCore dispatches here on PyExprMode }
function PyMakeNone: Integer; forward;  { the None VALUE (a VT_EMPTY variant) — pyparser.inc }
function PyBuildGeneratorValue(gpi: Integer): Integer; forward;  { a generator CALL in value position becomes a cursor object (pyparser.inc) }
function PyProgSym(const name: AnsiString): Integer; forward;  { a name in the Nil Python PROGRAM's own scope, never a unit's (pyparser.inc) }
function PyParseSuite: Integer; forward;  { a Nil Python `: <suite>` block — the frontend tail of a for-in header (pyparser.inc) }
function PyNodeIsCallableValue(n: Integer): Boolean; forward;  { a bound method / lambda / function value — pyparser.inc }
function PyWrapHeapCallableCall(calleeNode, argsHead, n, defCall: Integer): Integer; forward;  { Callable-param call through a heap callable — pyparser.inc }
function PyBareNoneHere: Boolean; forward;  { a `None` with nothing after it that could continue an expression — pyparser.inc }
function PyNoneOperandHere: Boolean; forward;  { a `None` that is an OPERAND of the enclosing operator, whatever follows — pyparser.inc }
function PyMakeSuperCall(const name: AnsiString): Integer; forward;  { `super().m(args)` as a value (pyparser.inc) }
function PyRecIsCls(rec: Integer; const clsName: AnsiString): Boolean; forward;  { is this rec that pylib class, by identity OR inheritance? (pyparser.inc) }
function PyRecOverridesDunder(rec: Integer; const dunder: AnsiString): Boolean; forward;  { does this rec's own class DECLARE this dunder — an override a container fast-path must not step over? (pyparser.inc) }
function PySubscriptWantsDunder(mci, lbrackIdx: Integer): Boolean; forward;  { does this subscript belong to the class's own __getitem__/__setitem__ rather than to an INHERITED default property? (pyparser.inc) }
procedure PySuperConsumeArgs; forward;  { `super()` / `super(Cls, self)` argument list, either spelling (pyparser.inc) }
function PyDynAttrEverAssigned(const nm: AnsiString): Boolean; forward;  { is `.nm =` written anywhere? (pyparser.inc) }
function PyIndexCoerce(n: Integer): Integer; forward;  { Python __index__: an object used where an integer is required (pyparser.inc) }
function PyIndexNotIntKind(kind: AnsiString; idxNode: Integer): Integer; forward;  { …and the TypeError when it declares none (pyparser.inc) }
function PyIndexSeqKindCi(mci: Integer): AnsiString; forward;
function PyClassWantsIntIndex(ci: Integer): Boolean; forward;  { does a subscript of this class take an INTEGER (a sequence) rather than an object key? (pyparser.inc) }
function PyClsAttrSharedSym(const fname: AnsiString; var needsOvr: Boolean): Integer; forward;  { the one shared class-attribute slot of that name, for a VARIANT receiver (pyparser.inc) }
function PyClsAttrOvrSlot(ci: Integer; const fname: AnsiString): Integer; forward;  { that slot, when the attribute also needs per-instance overrides (pyparser.inc) }
function PyClsAttrOvrGet(baseNode: Integer; const fname: AnsiString; gsym: Integer): Integer; forward;  { instance read of an overridable class attribute: has? get : slot (pyparser.inc) }
function PyParseInputCall: Integer; forward;  { `input([prompt])` -> pyinput / pyinput_p, one builder for both intercepts (pyparser.inc) }
function PyParseFormatCall: Integer; forward; { `format(v[, spec])` -> pyformat_v, one builder for both intercepts (pyparser.inc) }
function PyParsePrint: Integer; forward;      { `print(...)`; a STATEMENT node — expression use wraps it in AN_COMMA (pyparser.inc) }
function PyIsClassNameChainAhead: Boolean; forward;   { CurTok begins `__class__ . __name__` (pyparser.inc) }
function PyMakeClassNameOf(node: Integer): Integer; forward;   { ...consume it and answer pytype_name_v(node) (pyparser.inc) }
function PyMethNameFor(ci: Integer; const mname: AnsiString): AnsiString; forward;  { the name to look up on this class for a Python method spelling — pylib's alias when the class does not declare it as written (pyparser.inc) }
function PyForceVariant(node: Integer): Integer; forward;  { box a value into a variant (pyparser.inc) }
function PyEvalOnce(node: Integer): Integer; forward;  { bind a value to a hidden temp so it is evaluated once (pyparser.inc) }
function PyMakePercentFormat(fmtNode, argsNode: Integer): Integer; forward;  { `str % args` (pyparser.inc) }
procedure PyParseListLiteral; forward; { Nil Python [a, b, c] literal (pyparser.inc) }
function PyParseStrMethod(baseNode: Integer; const mname: AnsiString): Integer; forward; { Nil Python s.upper() etc (pyparser.inc) }
function PyMakeDynCall(baseNode: Integer): Integer; forward; { Nil Python: call a callable stored in a variant (pyparser.inc) }
function PyBoxCallableValue(node: Integer): Integer; forward; { Nil Python: box a closure/bound-fn pointer into a callable variant (pyparser.inc) }
function PyMakeCallDunder(baseNode: Integer): Integer; forward; { Nil Python: call a class instance's __call__ (pyparser.inc) }
function PyWrapClosureFieldCall(fieldNode, argExpr, defCall: Integer): Integer; forward; { Nil Python: a Callable field may hold a pyeval closure (pyparser.inc) }
function PyMakeBoundMethod(mpi, selfNode: Integer): Integer; forward; { Nil Python: `obj.method` (no call) -> a bound-method value (pyparser.inc) }
procedure PyParseLambdaStub; forward; { Nil Python: lambda -> pyeval closure value (pyparser.inc) }
function PyNestedDefClosureValue(procIdx: Integer): Integer; forward; { Nil Python: nested-def-as-value with live bindings -> closure, or -1 (pyparser.inc) }
function PyIsIdent(const s: AnsiString): Boolean; forward; { (pyparser.inc) }
function PyMakeVariantGetItem(baseNode, idxNode: Integer): Integer; forward; { Nil Python v[key] on a variant (pyparser.inc) }
function PyMakeObjPtr(baseNode: Integer): Integer; forward; { Nil Python: object as a pointer for the dynattr store (pyparser.inc) }
function PyAugBinTok(k: TTokenKind): TTokenKind; forward; { Nil Python augmented-assign op (pyparser.inc) }
function PyMakePow(ppBase, ppExp: Integer): Integer; forward;  { Nil Python `**` lowering, shared with `**=` (pyparser.inc) }
function PyAugClassDunderNode(lhsNode: Integer; binTk: TTokenKind; rhsNode: Integer): Integer; forward; { Nil Python obj.field += x dunder dispatch (pyparser.inc) }
function PyNodeListCi(n: Integer): Integer; forward; { Nil Python: TPyList class index of a node, else -1 (pyparser.inc) }
function PyMakeDynAttrGet(baseNode: Integer; const fname: AnsiString): Integer; forward; { Nil Python obj.name dynamic read (pyparser.inc) }
function PyMakeDynAttrSet(baseNode: Integer; const fname: AnsiString; valNode: Integer): Integer; forward; { Nil Python obj.name = v dynamic write (pyparser.inc) }
function PyMakeVariantSetItem(baseNode, idxNode, valNode: Integer): Integer; forward; { Nil Python v[key]=val on a variant (pyparser.inc) }
function PyMakeIdent(symIdx: Integer): Integer; forward; { Nil Python: ident AST node for a symbol (pyparser.inc) }
function PyHiddenName(const stem: AnsiString): AnsiString; forward; { hidden temp name (pyparser.inc) }
function PyMakeSubscriptRead(selfNode, idxArgs, ci, pri: Integer): Integer; forward; { the read half of `d[k] += v` (pyparser.inc) }
function PyCloneArgChain(head: Integer): Integer; forward;
function PyMakeStrIndex(baseNode, idxNode: Integer): Integer; forward; { Nil Python s[i] (pyparser.inc) }
function PyQualifyNested(const name: AnsiString): AnsiString; forward; { Nil Python nested-def name lookup (pyparser.inc) }
function PyNestedDefOutranksSym(const name: AnsiString): Boolean; forward; { Nil Python: a nested def shadows a module global (pyparser.inc) }
function PyListRepeatPair(a, b: Integer): Boolean; forward;              { Nil Python `xs * n` (pyparser.inc) }
function PyMakeListRepeat(a, b: Integer): Integer; forward;              { Nil Python `xs * n` (pyparser.inc) }
function PyAugMulNode(left, right: Integer): Integer; forward;            { Nil Python `x *= n` on a sequence (pyparser.inc) }
function PyBytesRepeatPair(a, b: Integer): Boolean; forward;             { Nil Python `bytes * n` (pyparser.inc) }
function PyMakeBytesRepeat(a, b: Integer): Integer; forward;             { Nil Python `bytes * n` (pyparser.inc) }
function PyNodeIsPyBytes(n: Integer): Boolean; forward;                  { Nil Python: node typed TPyBytes? (pyparser.inc) }
function PyMakeBytesBinCall(const fname: AnsiString; a, b: Integer; retTk: TTypeKind): Integer; forward; { bytes binop helper call (pyparser.inc) }
function PyMakeListBinCall(const fname: AnsiString; a, b: Integer): Integer; forward; { list binop -> TPyList call (pyparser.inc) }
function PyMakeDictBinCall(const fname: AnsiString; a, b: Integer): Integer; forward; { dict binop -> TPyDict call, PEP 584 `|` (pyparser.inc) }
function PyNodeIsPyDict(n: Integer): Boolean; forward;                   { Nil Python: node typed TPyDict? (pyparser.inc) }
procedure ParsePyUnit(const uname: AnsiString); forward;   { a `.py` MODULE pulled in by an import (pyparser.inc) }
{ PyCallMeth1's forward lives in forwards.inc (FPC-seed catch-all, gated on
  PXX_NEED_FORWARDS) — a second one here duplicated it and FPC rejects a
  Function declared Public/Forward twice (regression-fpc-seed-drift-b1976-
  stale). PXX itself needs neither copy (lenient prescan). }
function PyCallMeth2(ci: Integer; const mname: AnsiString;
                     selfNode, arg1, arg2: Integer): Integer; forward;   { two-arg method call (pyparser.inc) }
function PyMakeTupleFrom(firstNode: Integer): Integer; forward;   { build a tuple from an existing first element (pyparser.inc) }
function PyBareGenExprAhead: Boolean; forward;   { bare genexpr as a call arg (pyparser.inc) }
{ a user object with __iter__ handed to a pylib routine that wants a container
  (bug-nilpy-builtins-over-a-user-iterable-answer-empty) — body in pyparser.inc }
function PyFixIterableArgs(procIdx, argsHead, nArgs: Integer): Boolean; forward;
{ a builtin TYPE handed to a callback (Pointer) parameter — body in pyparser.inc }
function PyFixCallableTypeArgs(const nm: AnsiString; argsHead, nArgs: Integer): Boolean; forward;
function PyStarForwardCall(procIdx, listNode, dictNode: Integer): Integer; forward;   { *args/**kwargs forwarding call (pyparser.inc) }
function PyNewContainerTemp(const clsName, tag: AnsiString): Integer; forward;   { a hoisted, empty pylib container temp (pyparser.inc) }
function PyReprContainer(n: Integer): Integer; forward;   { repr() of a container node (pyparser.inc) }
function PyMakeTruthy(n: Integer): Integer; forward;   { Nil Python truthiness, shared by bool()/if/not (pyparser.inc) }
function VariantCastToTemp(n: Integer; target: TTypeKind): Integer; forward;   { a typecast of a VARIANT is the CONVERSION, not a reinterpret of the record; defined beside PromoDemoteToInt64 }
function PromoDemoteToInt64(n: Integer): Integer; forward;   { promo -> machine int for a value CAST; defined beside PromoWidenToDouble, below its three call sites (FPC is strict about declaration order, pxx is not — bug-a-fpc-seed-drift-emitasmx64-forward) }
function PyWiden(a, b: TTypeKind): TTypeKind; forward;   { Nil Python numeric-kind widening (pyparser.inc) }
function PyRawName(off, len: Integer): AnsiString; forward;           { name text from the token pool (pyparser.inc) }                                   { Nil Python None literal node (pyparser.inc) }
function PyNodeIsPyList(n: Integer): Boolean; forward;                   { Nil Python: node typed TPyList? (pyparser.inc) }
function PySubscriptableSuffix(n: Integer): Boolean; forward; { Nil Python: may `[` follow this non-lvalue? (pyparser.inc) }
function PyMakeSuffixIndex(baseNode, idxNode: Integer): Integer; forward; { Nil Python x[i] on a non-lvalue (pyparser.inc) }
function PyNotSubscriptableNode(ci: Integer): Integer; forward; { Nil Python: run-time TypeError for a class with no __getitem__ (pyparser.inc) }
function PyClassErrCallNode(const procName: AnsiString; ci: Integer): Integer; forward; { Nil Python: a run-time error call naming the class (pyparser.inc) }
function PyClassStrNode(node, argCi: Integer): Integer; forward; { Nil Python: __str__/__repr__ else an Exception's .msg (pyparser.inc) }
function PyIsSliceBase(n: Integer): Boolean; forward;
function PySliceBracketAt(i: Integer): Boolean; forward; { Nil Python: is the bracket group at i a SLICE? (pyparser.inc) }
function PyParseSliceTail(baseNode, loNode: Integer): Integer; forward; { Nil Python x[a:b], from the ':' (pyparser.inc) }
function PyIterArgAsList(n: Integer): Integer; forward; { Nil Python: explode a str arg to an iterable builtin (pyparser.inc) }
function PyIsIntBaseTk(tk: TTypeKind): Boolean; forward; { Nil Python: is this an int base for .to_bytes? (pyparser.inc) }
function PyParseToBytes(baseNode: Integer): Integer; forward; { Nil Python <int>.to_bytes(...) intrinsic (pyparser.inc) }
function PyParseIntMethod(baseNode: Integer; const nm: AnsiString): Integer; forward; { Nil Python intercepted int method (pyparser.inc) }
function PyParseFloatMethod(baseNode: Integer; const nm: AnsiString; asInt: Boolean): Integer; forward; { Nil Python intercepted float method (pyparser.inc) }
function PyIsFloatMethodName(const nm: AnsiString): Boolean; forward; { Nil Python: is_integer/hex/as_integer_ratio/conjugate (pyparser.inc) }
function PyIsFloatBaseTk(tk: TTypeKind): Boolean; forward; { Nil Python: a STATICALLY float receiver (pyparser.inc) }
function PyIsFloatMethodBaseTk(tk: TTypeKind; const nm: AnsiString): Boolean; forward; { ...plus int for the three names it shares }
function PyIsIntFloatSharedMethodName(const nm: AnsiString): Boolean; forward; { is_integer / as_integer_ratio / conjugate }
function PyParseFromBytes: Integer; forward; { Nil Python int.from_bytes(...) intrinsic (pyparser.inc) }
function PyIsFromBytesAhead: Boolean; forward; { Nil Python: at `int.from_bytes(`? (pyparser.inc) }
function PyStoredName(const s: AnsiString): Integer; forward; { Nil Python: intern a name into TokChars (pyparser.inc) }
function PyAttrFieldIdx(recvNode: Integer; const attr: AnsiString): Integer; forward; { Nil Python hasattr/getattr field lookup (pyparser.inc) }
function PyMakeDynAttrSetByExpr(recvNode, nameNode, valNode: Integer): Integer; forward; { Nil Python setattr with a computed name (pyparser.inc) }
{ getattr(o, "p") where p is a PROPERTY — the read `o.p` builds (pyparser.inc) }
function PyMakePropRead(recvNode: Integer; const attr: AnsiString): Integer; forward;
function PyAttrExists(recvNode: Integer; const attr: AnsiString): Boolean; forward; { Nil Python hasattr: field OR method OR str/int method (pyparser.inc) }
function PyHasAttrClassChain(recvNode: Integer; const attr: AnsiString): Integer; forward; { Nil Python hasattr over a VARIANT receiver: run-time class test (pyparser.inc) }
function PyParseAttrName: AnsiString; forward; { Nil Python: the literal attr name in hasattr/getattr (pyparser.inc) }
function PyMakeDynAttrByExpr(recvNode, nameNode, dfltNode: Integer; wantHas: Boolean): Integer; forward; { ...and the COMPUTED-name form, resolved at run time (pyparser.inc) }
function PyTupleParenAhead: Boolean; forward; { Nil Python: is this '(' a tuple? (pyparser.inc) }
procedure PyParseListLiteralT(opener, closer: TTokenKind; dedup: Boolean); forward; { Nil Python list/tuple literal (pyparser.inc) }
function PyIsListCompAhead: Boolean; forward; { Nil Python: is `[ ... for ... ]` a comprehension? (pyparser.inc) }
function PyParseCompExprValue(bracketed: Boolean): Integer; forward;
function PyIsParenCompAhead: Boolean; forward;      { `(x for x in xs)` (pyparser.inc) }
function PyNextOverListAhead: Boolean; forward;     { is `next(...)`'s argument a sequence? (pyparser.inc) }
function PyParseParenComp: Integer; forward;
function PyMakeZip(aNode, bNode, cNode, dNode: Integer): Integer; forward;   { `zip(a, b[, c[, d]])` as a value; -1 for an absent stream (pyparser.inc) }
function PyMakeZipN(listNode: Integer): Integer; forward;                    { `zip(*rows)` / zip past four — over a LIST of iterables (pyparser.inc) }
function PyZipStarOperand(node: Integer): Integer; forward;                  { the star operand of `zip(*rows)` as a TPyList (pyparser.inc) }
function PyStarIterableNode(listNode: Integer): Integer; forward;            { `max(*xs)`: the iterable to compare — the one element's contents, or the list (pyparser.inc) }
function PyZipTailList(a, b, c, d: Integer): Integer; forward;               { four parsed zip operands plus the rest, as a TPyList temp (pyparser.inc) }
function PyStarIsIterableForm(const nm: AnsiString): Boolean; forward;       { `max(*xs)` means max(xs) — the two names that is true of (pyparser.inc) }
function PyIsSetCompAhead: Boolean; forward;    { set comprehension (pyparser.inc) }
function PyParseSetComp: Integer; forward;
function PyParseClassMethodCall(baseNode, ci: Integer; const mname: AnsiString): Integer; forward; { `Cls().m(...)` (pyparser.inc) } { Nil Python expression-position comprehension (pyparser.inc) }
function PyIsSysStreamAhead: Boolean; forward; { Nil Python: at `sys.stdout`/`sys.stderr`? (pyparser.inc) }
function PyStdlibCallAhead(var pname: AnsiString; var nTok: Integer): Boolean; forward; { Nil Python: at a mapped os./sys. call? (pyparser.inc) }
function PyUnboundStrMethodValue: Integer; forward; { Nil Python: `str.lower` as an unbound-method VALUE (pyparser.inc) }
function PyParseStdlibCall(const pname: AnsiString; nTok: Integer): Integer; forward; { Nil Python os./sys. call -> pylib shim (pyparser.inc) }
function PyParseVariadicMinMax(const nm: AnsiString): Integer; forward; { Nil Python min/max at 3+ args (pyparser.inc) }
function PyParseRangeList: Integer; forward;      { Nil Python: list(range(...)) materialised (pyparser.inc) }
function PyAnyProcWithArity(const nm: AnsiString; n: Integer): Boolean; forward; { any routine of this name with exactly n params (pyparser.inc) }
function PyParseSysStream: Integer; forward; { Nil Python sys.stdout/sys.stderr -> its fd (pyparser.inc) }
function PyIsIntMethodBaseTk(tk: TTypeKind; const nm: AnsiString): Boolean; forward; { Nil Python: may an int method claim this receiver? (pyparser.inc) }
function PyIsIntMethodName(const nm: AnsiString): Boolean; forward; { Nil Python: an intercepted int method name? (pyparser.inc) }
function PyIsIntMethodSuffixAhead: Boolean; forward; { Nil Python: at an intercepted int-method suffix? (pyparser.inc) }
function PyParseVariantMethod(baseNode: Integer; const mname: AnsiString): Integer; forward; { Nil Python obj.meth() on a VARIANT receiver (pyparser.inc) }
function PyMakeFuncValue: Integer; forward; { Nil Python bare def NAME as a value (pyparser.inc) }

{ Does proc pi declare any parameter with a DEFAULT? What decides whether a
  callable value has to carry a signature record rather than a bare code
  address -- see the call site in ParseFactorCore. }
function PyProcHasDefaultParam(pi: Integer): Boolean;
var k: Integer;
begin
  Result := False;
  if (pi < 0) or (pi >= ProcCount) then Exit;
  for k := 0 to Procs[pi].ParamCount - 1 do
    if (k < MAX_PROC_PARAMS) and ProcParamHasDefault[pi * MAX_PROC_PARAMS + k] then
    begin
      Result := True;
      Exit;
    end;
end;
function PyMakeFuncValueFor(pi: Integer; const nm: AnsiString): Integer; forward; { the same pair for a KNOWN proc (pyparser.inc) }
function PyFindVariantParamOverload(const nm: AnsiString; wantArity: Integer): Integer; forward; { Nil Python: same-arity all-Variant-param overload of nm (pyparser.inc) }
function PyGetOrMakeCallableWrapper(realPi: Integer): Integer; forward; { Nil Python: Variant-ABI wrapper around realPi, cached by name (pyparser.inc) }
function PyMakeCallablePtrArg(node: Integer; const what: AnsiString): Integer; forward; { Nil Python: a callable VALUE heading for a Pointer parameter (pyparser.inc) }
function PyClsAttrRedeclaredCi(ci: Integer; const nm: AnsiString): Boolean; forward; { Nil Python: is this class attribute redeclared down the chain? (pyparser.inc) }
function PyMakeClsAttrInstGet(baseNode: Integer; const fname: AnsiString): Integer; forward; { Nil Python: read it off the RECEIVER's runtime class (pyparser.inc) }
function PyHoistPark: Integer; forward; { Nil Python: take the hoist queue away for a TRIAL parse (pyparser.inc) }
procedure PyHoistRestore(saved: Integer); forward; { Nil Python: put a parked queue back, dropping the trial's (pyparser.inc) }
procedure PyHoistMerge(saved, trial: Integer); forward; { Nil Python: re-queue a parked trial parse's hoists (pyparser.inc) }
function PyScalarWrappableRetType(tk: TTypeKind): Boolean; forward; { Nil Python: is tk a genuine scalar/string result worth wrapping (pyparser.inc) }
function PyMakeVariantField(baseNode: Integer; const fname: AnsiString; var tk: TTypeKind; var recName: Integer): Integer; forward; { Nil Python obj.field on a VARIANT receiver (pyparser.inc) }
function PyMakeVariantPropRecv(baseNode: Integer; const pname: AnsiString; var ci: Integer): Integer; forward; { Nil Python obj.PROPERTY on a VARIANT receiver: the unboxed class-cast receiver (pyparser.inc) }
function PyKwArgIndex(mpi, firstParam: Integer): Integer; forward; { Nil Python `name=expr` call argument (pyparser.inc) }
function PyKwDictArgNode(mpi: Integer): Integer; forward; { Nil Python: `dict(a=1)` / `d.update(a=1)` keywords are KEYS (pyparser.inc) }
function PyKeywordsAreKeys(mpi: Integer): Boolean; forward; { Nil Python: is this the dict()/update() callee? (pyparser.inc) }
function PyDictKwArgsAhead: Boolean; forward; { Nil Python: at `name=` or `**expr` in an argument list? (pyparser.inc) }
function PyBuildKeywordDictHere: Integer; forward; { Nil Python: the dict `a=1, **e` describes, seeding it with a leading positional mapping when there is one (pyparser.inc) }
function PyKwDictArgsHere(mpi: Integer): Boolean; forward; { Nil Python: this callee's keywords are dict KEYS and a keyword run is in this argument list (pyparser.inc) }
function PyMinMaxDefaultAhead: Boolean; forward; { Nil Python: is there a `default=` keyword in this min/max call? (pyparser.inc) }
function PyBuiltinTypeCode(const nm: AnsiString): Integer; forward; { Nil Python: PYBT_* code for a builtin type NAME, else 0 (pyparser.inc) }
function PyMakeBuiltinTypeValue(code: Integer): Integer; forward; { Nil Python: a builtin type in VALUE position, as pybtype(code) (pyparser.inc) }
function PyDictKwOverloadAhead(ci: Integer; const name: AnsiString): Integer; forward; { Nil Python: the TPyDict.update arm a keywords-are-KEYS run resolves to (pyparser.inc) }
function PyKwNamesTokPos: Integer; forward; { Nil Python: '(' token index of the call at the current parse position, or -1 (pyparser.inc) }
function PyPromoteOverloadByKwAt(ci, mmi, parenTok: Integer; const mname: AnsiString): Integer; forward; { Nil Python: pick the UMeth overload a keyword argument names (pyparser.inc) }
function PyPromoteProcOverloadByKwAt(procIdx, firstParam, parenTok: Integer): Integer; forward; { Nil Python: pick the Procs[] overload a keyword argument names (pyparser.inc) }
procedure PyBindKwArgs(mpi: Integer; var argsHead, lastArg, nArgs: Integer); forward; { Nil Python keyword-argument reorder (pyparser.inc) }
procedure PyPackStarArgs(mpi: Integer; var argsHead, lastArg, nArgs: Integer;
                         selfSlots: Integer); forward; { Nil Python `*args`/`**kwargs` call-site packing (pyparser.inc) }
procedure PyParseStarMethodArgs(mpi, mcallNode: Integer; var mlastArg, mai: Integer); forward; { Nil Python varargs METHOD call (pyparser.inc) }
function PyStarArgAhead: Boolean; forward; { Nil Python: a `*expr` unpack left in this argument list (pyparser.inc) }
procedure PyStarUnpackMethodArgs(mpi, mcallNode: Integer; var mlastArg, mai: Integer); forward; { Nil Python `obj.m(*xs)` call-site unpack (pyparser.inc) }
procedure PyStarUnpackProcArgs(procIdx: Integer; var argsHead, lastArg, nArgs: Integer); forward; { Nil Python `f(1, *xs)` call-site unpack (pyparser.inc) }
function PyIsSetCall: Boolean; forward;   { Nil Python `set(...)` builtin, user definition permitting (pyparser.inc) }
function PyParseEmptySet: Integer; forward; { Nil Python set() / set(iterable) (pyparser.inc) }

procedure ParseArgExpr;
{ A call ARGUMENT under NilPy must be parsed by the Python precedence chain
  (or < and < not < comparison, and `in`/`is` with Python's meaning), not by
  the shared ParseExpr, which implements Pascal's -- where and/or bind TIGHTER
  than comparison and `in` is set membership. Without this `show(a in d)` and
  `show(x > 1 and y > 1)` were parse errors while the identical expressions
  worked in a statement, and every f-string hole is a call argument
  (bug-a-nilpy-and-or-in-unavailable-in-call-arguments).

  Same delegation PyParseListLiteral / PyParseStrMethod already use: the shared
  parser knows WHERE an expression is legal, pyparser.inc decides what it
  MEANS.

  A BARE generator expression — `f(x*2 for x in xs)` — is diverted HERE, which
  is the one place every call argument passes through. It must happen before
  the element expression is parsed, because that expression names the loop
  variable, which is not in scope until the `for`. The diversion used to sit at
  the ordinary-call argument loop and at the str-method path, so the same
  argument parsed one way for `sum(x for x in xs)` and failed with "undefined
  variable (x)" for `obj.take(x for x in xs)` and `f.writelines(s for s in xs)`
  — one construct, N argument loops, which is the shape
  devdocs/dev/normalise-dont-special-case.md is about
  (bug-nilpy-bare-genexpr-as-a-method-argument-does-not-parse). The ordinary
  site's own check is now redundant and harmless: it fires first and does the
  same thing. }
begin
  if PyExprMode and PyBareGenExprAhead then
  begin
    CurASTNode := PyParseCompExprValue(False);
    Exit;
  end;
  if PyExprMode then PyParseBoolExpr else ParseExpr;
end;

{ Types a NilPy str method may be called ON. tyChar is included because Python
  has NO character type: the shared lexer types a one-character literal like
  "b" (and `s[0]`) as tyChar, but to Python that is a str of length 1, so
  `"b".upper()` and `s[0].isspace()` must work. The pylib functions take
  AnsiString and the ordinary char->string conversion covers the argument. }
function PyIsStrBaseTk(tk: TTypeKind): Boolean;
begin
  PyIsStrBaseTk := (tk = tyString) or (tk = tyAnsiString) or (tk = tyChar);
end;
procedure PyParseSetLiteral; forward;  { Nil Python {a, b} literal (pyparser.inc) }
function PyClassCreateExpr: Integer; forward; { Nil Python ClassName(args) ctor (pyparser.inc) }
function PyIsExactCtorName(const nm: AnsiString): Boolean; forward; { Nil Python: `Name(` is a ctor only on an EXACT-case class match (pyparser.inc) }
function PyIsClassTypeExact(const nm: AnsiString): Boolean; forward; { Nil Python: is this name a class, matched EXACTLY (Python is case-sensitive)? (pyparser.inc) }
function PyBuiltinBaseCi(const nm: AnsiString): Integer; forward; { Nil Python: the pylib class a BUILTIN type name (list/dict/set/bytes) stands for, or -1 (pyparser.inc) }
function PyIsDictCompAhead: Boolean; forward; { Nil Python dict comprehension lookahead (pyparser.inc) }
function PyParseDictCompExprValue: Integer; forward; { Nil Python dict comp in expression position (pyparser.inc) }

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
{ Method-NAME position: FPC (delphi mode) lets methods be NAMED after built-in
  type keywords — generics.defaults declares `class function Integer(constref
  ALeft, ARight: Integer): Integer;` and ~30 siblings per class. These lex as
  type-keyword tokens whose SVal is EMPTY, so name reads at the sites that
  accept this predicate must go through GetTokenStr, never SVal. }
function IsMethodNameTok: Boolean;
begin
  IsMethodNameTok := IsMemberNameTok or
    (CurTok.Kind in [tkInteger_T, tkBoolean_T, tkChar_T, tkString_T, tkReal_T,
                     tkLongWord_T, tkSingle_T, tkDouble_T, tkExtended_T]);
end;

{ Index-addressed IsMethodNameTok, for LOOKAHEAD past the current token — same
  token set, deliberately sharing the predicate above so the two cannot drift.
  A caller that accepts this must read the name with GetTokenStr(idx): the
  type-keyword tokens carry an EMPTY SVal. }
function IsMethodNameTokAt(idx: Integer): Boolean;
begin
  IsMethodNameTokAt := (idx >= 0) and (idx < TokCount) and
    (Tokens[idx].Kind in [tkIdent, tkRead, tkwrite, tkReadln, tkwriteln,
                          tkArgCount, tkArgStr,
                          tkInteger_T, tkBoolean_T, tkChar_T, tkString_T, tkReal_T,
                          tkLongWord_T, tkSingle_T, tkDouble_T, tkExtended_T]);
end;

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
{ Python attribute names that Pascal reserves. A library exposes them with a
  trailing underscore; this maps the spelling the application writes onto it. }
function PyMapReservedMember(const nm: AnsiString): AnsiString;
begin
  PyMapReservedMember := nm;
  if CaseEqual(nm, 'END') or CaseEqual(nm, 'TYPE') or CaseEqual(nm, 'FILE') or
     CaseEqual(nm, 'LABEL') or CaseEqual(nm, 'SET') or CaseEqual(nm, 'STRING') or
     CaseEqual(nm, 'ARRAY') or CaseEqual(nm, 'RECORD') or CaseEqual(nm, 'TEXT') or
     CaseEqual(nm, 'DIV') or CaseEqual(nm, 'MOD') or CaseEqual(nm, 'IN') or
     CaseEqual(nm, 'IS') or CaseEqual(nm, 'OR') or CaseEqual(nm, 'AND') or
     CaseEqual(nm, 'NOT') or CaseEqual(nm, 'WITH') then
    PyMapReservedMember := nm + '_';
end;

{ A dotted qualifier as NILPY spells its units. Pascal namespace units really
  are named `Posix.SysSocket`, so the candidate below is looked up verbatim; a
  NilPy dotted import is MANGLED to one underscore-joined unit
  (`mypkg.core.origin` -> `mypkg_core_origin`), so the same qualifier text has
  to be tried in that spelling too or `import a.b.c` binds a name no expression
  can then use. Underscore form only under isNilPy, so no Pascal qualifier
  changes meaning. feature-nilpy-dotted-imports-resolve-to-source-files }
function PyFindUnitDotted(const cand: AnsiString): Integer;
var m: AnsiString; i: Integer;
begin
  Result := FindUnitOrAlias(cand);
  if (Result >= 0) or (not isNilPy) then Exit;
  m := '';
  for i := 1 to Length(cand) do
    if cand[i] = '.' then m := m + '_' else m := m + cand[i];
  Result := FindUnitOrAlias(m);
end;

{ Strip a leading `System.` qualifier. pxx has no separate System unit — System
  IS the builtin layer — so FPC's `System.Move(p, q, n)`, `System.Integer(x)` and
  `SizeOf(System.TMethod)` must resolve exactly like the bare name. CurTok sits on
  the candidate `System`; on True the name and its dot are consumed, CurTok is the
  member, and `name` holds the member's spelling. False consumes nothing —
  including when something REAL is named System (a loaded unit, or a local /
  record var), which keeps its own meaning.

  The member may lex as an IDENTIFIER (`System.Move`) or as a builtin TYPE
  KEYWORD (`System.Integer`, `System.LongWord`) — the two are the same
  declaration read two ways, and every hand-rolled dispatch that forgot the
  second half broke on it. ONE function, two callers (the unit-qualifier
  resolver and SizeOf's own type dispatch), because each had to learn the strip
  separately and only the first one ever did: `System.Integer(ALeft)` and
  `SizeOf(System.TMethod)` — adjacent lines in rtl-generics' TCompare — failed
  for the one missing rule. }
function EatSystemQualifier(var name: AnsiString): Boolean;
var mk: TTokenKind;
begin
  Result := False;
  if (CurTok.Kind <> tkIdent) or (not CaseEqual(name, 'System')) then Exit;
  if not ((TokPos + 1 < TokCount) and (Tokens[TokPos].Kind = tkDot)) then Exit;
  mk := Tokens[TokPos + 1].Kind;
  if not ((mk = tkIdent) or (mk = tkInteger_T) or (mk = tkLongWord_T) or
          (mk = tkBoolean_T) or (mk = tkChar_T) or (mk = tkString_T) or
          (mk = tkReal_T) or (mk = tkSingle_T) or (mk = tkDouble_T) or
          (mk = tkExtended_T)) then Exit;
  if (FindUnitOrAlias(name) >= 0) or (FindSym(name) >= 0) then Exit;
  Next;                 { consume 'System' (CurTok -> '.') }
  Expect(tkDot, '.');   { consume '.'      (CurTok -> the member) }
  name := CurTok.SVal;
  { a keyword token carries no SVal in every lexer path — fall back to its text }
  if name = '' then name := GetTokenStr(TokPos - 1);
  Result := True;
end;

function ConsumeUnitQualifier(var name: AnsiString): Integer;
var cand: AnsiString; bestUnit, bestExtra, extra, ti, k, u: Integer;
begin
  Result := -1;
  if CurTok.Kind <> tkIdent then Exit;
  { `System.X` — stripped, and reported as -2: like unqualified (-1) everywhere,
    but the builtin soft-aliases must WIN over a same-named method of the
    enclosing class — TFPSList.Delete's System.Move(...) names the builtin
    precisely because the class has its own Move(CurIndex, NewIndex). Checked
    BEFORE the `.ident` guard below, because a System member may be a builtin
    TYPE, which lexes as a keyword token rather than an identifier. }
  if EatSystemQualifier(name) then
  begin
    Result := -2;
    Exit;
  end;

  { Need at least one `.ident` after the name to be a qualifier at all — or, in
    NilPy, a `.KEYWORD`: `tk.END` is written by every tkinter application and
    END is a reserved word here, so the façade spells the constant END_ and the
    member name is mapped to it below. The same trailing-underscore convention
    the reserved METHOD names use (set_, destroy_). }
  if not ((TokPos + 1 < TokCount) and (Tokens[TokPos].Kind = tkDot) and
          ((Tokens[TokPos + 1].Kind = tkIdent) or
           (isNilPy and (Tokens[TokPos + 1].Kind = tkEnd)))) then Exit;

  { A local/param/global SYMBOL shadows a same-named unit (FPC scoping):
    `function NetToHost(Net: in_addr)...` must keep `Net.s_addr` a record
    field access even when unit net.pas is loaded — the qualifier greedily
    ate the param and s_addr resolved against the unit (undefined). }
  if FindSym(name) >= 0 then Exit;

  cand := name;
  bestUnit := -1; bestExtra := -1;
  { 0-extra: the bare name is the unit, member = Tokens[TokPos+1]. }
  u := PyFindUnitDotted(cand);
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
      u := PyFindUnitDotted(cand);
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
  if CurTok.Kind = tkIdent then
  begin
    name := CurTok.SVal;
    { The trailing-underscore convention is not only for RESERVED words: a
      façade renames any constant whose bare spelling collides with something
      already in the flat namespace, and which names collide depends on what
      else the program links (`tk.X` resolved on its own and stopped resolving
      once the app pulled in a C unit). So when the plain member is not
      declared in the named unit but `NAME_` is, take that — the same rule
      `tk.END` -> END_ already follows, applied where the collision is
      accidental rather than syntactic. Retired by
      [[bug-pascal-uses-is-transitive]], with the rest of the flat namespace. }
    if isNilPy and (FindStrConst(name) < 0) and
       (FindStrConst(name + '_') >= 0) then
      name := name + '_';
  end
  else
    name := GetTokenStr(TokPos - 1) + '_';   { `tk.END` -> END_ }
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

function EnumTypeNameOf(eid: Integer): AnsiString;
begin
  if (eid >= 0) and (eid < EnumTypeCount) then
    Result := GetTokenStrFromRaw(EnumTypeNOff[eid], EnumTypeNLen[eid])
  else
    Result := '<anonymous enum>';
end;

procedure SetLitBegin;
{ Open a fresh element tally for one `[...]`. Callers save/restore the three
  globals around it, so a set literal nested inside an element expression
  cannot corrupt the enclosing one's tally. }
begin
  SetLitEnumId := -1;
  SetLitMixed := False;
  SetLitHasPlain := False;
end;

procedure SetLitNoteEnum(eid: Integer);
{ Tally one element known to be a member of enum `eid`. }
begin
  if SetLitEnumId < 0 then SetLitEnumId := eid
  else if SetLitEnumId <> eid then SetLitMixed := True;
end;

procedure SetLitNoteElem(symIdx: Integer);
{ Tally one CONSTANT element by the symbol it came from (-1 = a literal integer
  or char, which is never an enum member). Runtime elements are not tallied:
  their ordinal type is not knowable here, and being lenient there costs a
  diagnostic rather than producing a wrong value. }
var eid: Integer;
begin
  eid := -1;
  if symIdx >= 0 then eid := SymEnumId[symIdx];
  if eid < 0 then SetLitHasPlain := True else SetLitNoteEnum(eid);
end;

procedure SetLitCheckAgainst(targetEnumId: Integer);
{ The one rule, at the one place the target type is known: in a literal bound to
  a `set of TEnum`, every constant element must be a member of THAT enum.

  It subsumes the whole reported surface -- a plain integer, a char, True and an
  out-of-range ordinal are all "not a member of TEnum", and so is a member of a
  DIFFERENT enum with the same ordinal, which was the sharpest case: `[cGreen]`
  silently answered dTue, so swapping one enum for another could not be caught
  anywhere a set literal was involved.

  `[]` is always legal (nothing to check), and a set whose element type is not
  an enum (`set of Char`, `set of Byte`, `set of 0..7`) is left alone entirely.
  bug-p-set-literal-elements-are-not-type-checked }
begin
  if SetLitMixed then
    Error('set literal mixes elements from two different enum types');
  if targetEnumId < 0 then Exit;
  if SetLitHasPlain then
    Error('set element is not a member of ' + EnumTypeNameOf(targetEnumId));
  if (SetLitEnumId >= 0) and (SetLitEnumId <> targetEnumId) then
    Error('set of ' + EnumTypeNameOf(SetLitEnumId) +
          ' element in a set of ' + EnumTypeNameOf(targetEnumId));
end;

procedure SetLitCheckArg(node, procIdx, slot: Integer);
{ The call-argument arm. `node` must be the literal just parsed — the tally the
  check reads is the one left in the globals by its `]`, so anything else would
  be reading a previous literal's.

  Skipped for an OVERLOADED routine: `procIdx` here is the candidate the name
  resolved to first, not necessarily the one the call will bind, so its element
  type is not yet knowable. (A literal that mixes two enums is still rejected —
  that needs no target at all.) }
begin
  if (node < 0) or (ASTKind[node] <> AN_SET_LIT) then Exit;
  if (procIdx < 0) or (slot < 0) or (slot >= MAX_PROC_PARAMS) then Exit;
  if slot >= Procs[procIdx].ParamCount then Exit;
  if ProcOverloadDirective[procIdx] then
  begin
    if SetLitMixed then
      Error('set literal mixes elements from two different enum types');
    Exit;
  end;
  SetLitCheckAgainst(ProcParamSetEnumId[procIdx * MAX_PROC_PARAMS + slot]);
end;

function ParseSetConst: Int64;
var idx: Integer;
begin
  if CurTok.Kind = tkInteger then
  begin
    Result := CurTok.IVal;
    SetLitNoteElem(-1);
    Next;
  end
  else if CurTok.Kind = tkString then
  begin
    if Length(CurTok.SVal) <> 1 then Error('set item must be one character');
    Result := Ord(CurTok.SVal[1]);
    SetLitNoteElem(-1);
    Next;
  end
  else if CurTok.Kind = tkIdent then
  begin
    idx := FindSym(CurTok.SVal);
    if (idx < 0) or (Syms[idx].Kind <> skConst) then Error('set item must be constant');
    Result := Syms[idx].ConstVal;
    SetLitNoteElem(idx);
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
function NodeEnumIdOf(node: Integer): Integer; forward;
function ParseVarRecLiteralAST: Integer; forward;
function ParseArrayCtorAST(elemTk: TTypeKind; rowLen, rowLo: Integer): Integer; forward;
function BuildMetaclassNew(crefNode, ci, mmi: Integer): Integer; forward;
function ParseStatementAST: Integer; forward;
procedure EnableCoroutineRuntime; forward;
function ParseWithStatementAST: Integer; forward;
function ParseAsmStatementAST: Integer; forward;
function ParseBlockAST: Integer; forward;
procedure CompileAST(node: Integer); forward;
function ParseTypeKind: TTypeKind; forward;
procedure ParseRecordFields(ci: Integer; isPackedRecord: Boolean); forward;
procedure ParseRecordMethodDecl(ci: Integer); forward;
var RecordMethodClassPrefix: Boolean = False;  { `class function` in a record/helper body }
procedure ParseRecordPropertyDecl(ci: Integer); forward;
function IsNodePChar(node: Integer): Boolean; forward;  { defined in ir.inc (included later) }
procedure ParseSubroutine; forward;
function NegWidensToInt64(tk: TTypeKind): Boolean; forward;  { FPC: unary minus yields Int64 for EVERY integer operand }
function ASTConstIntValue(node: Integer; var v: Int64; depth: Integer): Boolean; forward;  { ...except a CONSTANT, which FPC types by its folded VALUE }
procedure ParseGenericFunctionDef; forward;
procedure ParseOperatorDef; forward;
procedure ParseNestedRoutine; forward;
procedure FlushPendingNestedProcs; forward;
function ParseParallelFor: Integer; forward;

{ GetTokenStrFromRaw moved up to lexer.inc (before its lexer.inc use) for FPC
  declaration-order; see there. }

function IsClassMemberStartWord(const s: AnsiString): Boolean;
{ Soft keywords that open a class member or visibility section but lex as plain
  identifiers (they are not reserved words). A name list inside a class body must
  stop here instead of eating the word as another name. }
begin
  Result := CaseEqual(s, 'private') or CaseEqual(s, 'protected') or
            CaseEqual(s, 'public') or CaseEqual(s, 'published') or
            CaseEqual(s, 'constructor') or CaseEqual(s, 'destructor');
end;

{ The class/record that DECLARES the field at UFld index fIdx (its window
  contains fIdx). -1 if none — the caller then skips the visibility check. }
function FieldDeclClass(fIdx: Integer): Integer;
var c: Integer;
begin
  FieldDeclClass := -1;
  for c := 0 to UClsCount - 1 do
    if (fIdx >= UClsFBase[c]) and (fIdx < UClsFBase[c] + UClsFCount[c]) then
      begin FieldDeclClass := c; Exit; end;
end;

{ The class/record that DECLARES the method at UMth index mIdx. -1 if none. }
function MethDeclClass(mIdx: Integer): Integer;
var c: Integer;
begin
  MethDeclClass := -1;
  for c := 0 to UClsCount - 1 do
    if (mIdx >= UClsMBase[c]) and (mIdx < UClsMBase[c] + UClsMCount[c]) then
      begin MethDeclClass := c; Exit; end;
end;

{ Member-access control (feature member-visibility). No-op unless
  StrictVisibility (the PXX dialect is lax by default). Rejects an access to a
  member of visibility `vis` declared in class `declCi` from a context FPC would
  forbid. Context comes from globals: CurrentUnitIdx (accessing unit) and
  CurSelfClass (the class whose method is being compiled). FPC scoping:
  private/protected are UNIT-scoped (whole declaring unit sees them); the strict
  variants are TYPE-scoped (declaring class + — for strict protected — its
  descendants). A missing/unknown declCi fails OPEN (no rejection). }
procedure EnforceMemberVis(declCi, vis: Integer; const memberName: AnsiString);
var accUnit, accCi: Integer; sameUnit, inHier, ok: Boolean; vn: AnsiString;
begin
  if not StrictVisibility then Exit;
  if (declCi < 0) or (declCi >= UClsCount) then Exit;
  if vis = VIS_PUBLIC then Exit;
  accUnit := CurrentUnitIdx;
  if CurSelfClass >= REC_UCLASS_BASE then accCi := CurSelfClass - REC_UCLASS_BASE else accCi := -1;
  sameUnit := (accUnit = UClsUnitIdx[declCi]);
  inHier := (accCi = declCi) or ((accCi >= 0) and IsSubclassOf(accCi, declCi));
  ok := False;
  if vis = VIS_PRIVATE then ok := sameUnit
  else if vis = VIS_PROTECTED then ok := sameUnit or inHier
  else if vis = VIS_STRICT_PRIVATE then ok := (accCi = declCi)
  else if vis = VIS_STRICT_PROTECTED then ok := inHier;
  if ok then Exit;
  if vis = VIS_PRIVATE then vn := 'private'
  else if vis = VIS_PROTECTED then vn := 'protected'
  else if vis = VIS_STRICT_PRIVATE then vn := 'strict private'
  else vn := 'strict protected';
  Error('cannot access ' + vn + ' member "' + memberName + '" of ' +
        GetTokenStrFromRaw(UClsNOff[declCi], UClsNLen[declCi]) +
        ' from here (--strict-visibility)');
end;

{ Enforce access control for a field `fieldName` of class/record `recId` at a
  genuine access site. No-op unless StrictVisibility (so the lax default runs no
  FindUField and stays byte-identical). }
procedure EnforceFieldVis(recId: Integer; const fieldName: AnsiString);
var fi: Integer;
begin
  if not StrictVisibility then Exit;
  if recId < REC_UCLASS_BASE then Exit;
  fi := FindUField(recId - REC_UCLASS_BASE, fieldName);
  if fi >= 0 then EnforceMemberVis(FieldDeclClass(fi), UFldVis[fi], fieldName);
end;

{ Enforce access control for a METHOD call at a committed dispatch site (the
  resolved UMth index). No-op unless StrictVisibility. Call it only where the
  method call is actually being built, never on a speculative probe — a probe
  that would fall through to another meaning must not error. }
procedure EnforceMethVis(mIdx: Integer; const methName: AnsiString);
begin
  if not StrictVisibility then Exit;
  if mIdx < 0 then Exit;
  EnforceMemberVis(MethDeclClass(mIdx), UMthVis[mIdx], methName);
end;

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

function FindVarSym(const name: AnsiString): Integer;
{ FindSym, plus the bare `class var` a method body may name without a qualifier.

  FindSym only knows plain scoped symbols. A class var is reachable inside its own
  class's methods through the ClassVar registry, and ParseLValueAST does that lookup
  when it parses an lvalue — so an *expression* naming a class var has always worked.
  What did not work is the intrinsics that resolve their OPERAND themselves with a raw
  FindSym before handing it to ParseLValueAST: they saw -1 and silently took whatever
  their no-symbol arm was. For SetLength that arm classifies the target as a STRING, so
  `SetLength(G, n)` on a dynamic-array class var wrote a string header over the array
  handle and the next read segfaulted. For SizeOf it was the honest
  `SizeOf: unknown type or variable`.

  One lookup, one answer: an intrinsic that wants "the symbol this name denotes here"
  calls THIS, not FindSym. Roughly forty other operand lookups in this file still call
  FindSym directly; each is a one-word change when its own ticket arrives — do not
  grow a second class-var branch beside one
  (devdocs/dev/normalise-dont-special-case.md). }
begin
  Result := FindSym(name);
  if (Result < 0) and (CurMethClass >= REC_UCLASS_BASE) and (CurProc >= 0) then
    Result := FindClassVar(CurMethClass - REC_UCLASS_BASE, name);
end;

function ClassConstMangle(ownerCi: Integer; const nm: AnsiString): AnsiString;
{ The mangled backing key a class const lives under in the ordinary const tables
  (Syms skConst / StrConst / SetConst). Keyed by the OWNING class's NAME (unique
  per program) so an inherited const resolves to the ancestor that declared it,
  reconstructed identically from ClassConstCi at every access path. The '$cc$'
  prefix cannot occur in a user identifier, so it never collides with a global of
  the same bare name. }
begin
  ClassConstMangle := '$cc$' + GetTokenStrFromRaw(UClsNOff[ownerCi], UClsNLen[ownerCi]) + '.' + nm;
end;

function FindNestedType(ci: Integer; const nm: AnsiString): Integer;
{ A type declared inside class `ci`'s body, by its BARE name — walking own ->
  ancestors, the same order FindClassConst uses, because a nested type is
  inherited exactly as a class const is. -1 when this class chain declares none.
  bug-a-duplicate-class-name-check-is-scope-blind }
var i, c: Integer;
begin
  Result := -1;
  c := ci;
  while c >= 0 do
  begin
    for i := 0 to NestedTypeCount - 1 do
      if (NestedTypeOwner[i] = c) and CaseEqual(NestedTypeName[i], nm) then
      begin
        Result := NestedTypeCi[i];
        Exit;
      end;
    c := UClsParent[c];
  end;
end;

{ Register `nm` as a type declared inside class `ownerCi`'s body. Idempotent per
  (owner, name): a re-parse of the same body must not grow the table. }
procedure AddNestedType(ownerCi: Integer; const nm: AnsiString; ci: Integer);
var i: Integer;
begin
  if (ownerCi < 0) or (ci < 0) then Exit;
  for i := 0 to NestedTypeCount - 1 do
    if (NestedTypeOwner[i] = ownerCi) and CaseEqual(NestedTypeName[i], nm) then
    begin
      NestedTypeCi[i] := ci;
      Exit;
    end;
  if NestedTypeCount >= MAX_TYPEALIAS then Error('too many nested class types');
  NestedTypeOwner[NestedTypeCount] := ownerCi;
  NestedTypeName[NestedTypeCount]  := nm;
  NestedTypeCi[NestedTypeCount]    := ci;
  Inc(NestedTypeCount);
end;

function FindClassConst(ci: Integer; const nm: AnsiString): Integer;
{ Registry lookup by (class ci, bare name), walking the parent chain (own ->
  ancestors) so a subclass method sees an inherited class const. Returns the
  ClassConst* registry index, or -1. Newest-first within a class so a later
  redeclaration shadows an earlier one. }
var i, cur: Integer;
begin
  Result := -1;
  cur := ci;
  while cur >= 0 do
  begin
    for i := ClassConstCount - 1 downto 0 do
      if (ClassConstCi[i] = cur) and CaseEqual(ClassConstName[i], nm) then
        begin Result := i; Exit; end;
    cur := UClsParent[cur];
  end;
end;

function EmitClassConstNode(const key: AnsiString; var outTk: TTypeKind): Integer;
{ Build a literal AST node for a resolved class-const backing entry (its mangled
  key). Scalar -> AN_INT_LIT/AN_FLOAT_LIT (carrying any enum identity), string ->
  AN_STR_LIT, set -> AN_SET_CONST_REF — exactly the shapes an ordinary const use
  builds. Does NOT consume the source token (the caller does). Returns the node,
  or -1 if the key has no backing (should not happen once the registry hit). }
var si, sti, seti, nd: Integer;
begin
  Result := -1; outTk := tyUnknown;
  si := FindSym(key);
  if (si >= 0) and (Syms[si].Kind = skConst) then
  begin
    if TypeIsFloat(Syms[si].TypeKind) then nd := AllocNode(AN_FLOAT_LIT)
    else nd := AllocNode(AN_INT_LIT);
    ASTIVal[nd] := Syms[si].ConstVal;
    ASTTk[nd] := Ord(Syms[si].TypeKind);
    ASTEnumId[nd] := SymEnumId[si];
    outTk := Syms[si].TypeKind;
    Result := nd; Exit;
  end;
  sti := FindStrConst(key);
  if sti >= 0 then
  begin
    nd := AllocNode(AN_STR_LIT);
    ASTSOffset[nd] := StrConstSOff[sti];
    ASTSLen[nd] := StrConstSLen[sti];
    ASTTk[nd] := Ord(tyString);
    outTk := tyString;
    Result := nd; Exit;
  end;
  seti := FindSetConst(key);
  if seti >= 0 then
  begin
    nd := AllocNode(AN_SET_CONST_REF);
    ASTIVal[nd] := SetConstOff[seti];
    ASTTk[nd] := Ord(tySet);
    outTk := tySet;
    Result := nd; Exit;
  end;
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

function AddClassLikeType(existingCi, tnOff, tnLen: Integer;
                          const tname: AnsiString): Integer;
{ Register a class/record/interface type declaration, honouring an enclosing
  class body as a SCOPE rather than as part of the flat per-unit type table.

  Inside a class body the name is not the unit's, it is that class's:
  `TOuter.TInner` and `TOther.TInner` are two legal, distinct types, and a
  generic's nested type is re-materialised once per specialization on purpose
  (tgeneric72 asserts those two are unique). So when the bare name is already
  taken in this unit, register the nested one under its QUALIFIED name — the
  first keeps the bare one, and every existing unqualified use resolves exactly
  as before — and make it reachable by (owning class, bare name) either way.
  One registry, so the qualified `TOuter.TInner` spelling and a bare `TInner`
  inside the owner's own body find the same entry.
  bug-a-duplicate-class-name-check-is-scope-blind

  ONE function, because the class branch had this and the RECORD branch did
  not: a nested record was registered flat under its bare name and was invisible
  to FindNestedType, so `function TOuter.TInner.M` parsed when TInner was a
  class and failed when it was a record — the exact sibling case
  normalise-dont-special-case is about. rtl-generics' TComparerService.TInstance
  is a nested record. }
var qualNm: AnsiString;
begin
  if (existingCi >= 0) and (ParsingClassBodyCi >= 0) and
     (UClsUnitIdx[existingCi] = CurrentUnitIdx) then
  begin
    qualNm := GetTokenStrFromRaw(UClsNOff[ParsingClassBodyCi],
                                 UClsNLen[ParsingClassBodyCi]) + '.' + tname;
    Result := AddUClass(TokCharsAppend(qualNm), Length(qualNm));
  end
  else
    Result := AddUClass(tnOff, tnLen);
  if ParsingClassBodyCi >= 0 then
    AddNestedType(ParsingClassBodyCi, tname, Result);
end;

{ ===== Pascal generics — carved out into `pasparser_generic.inc`. ============
  Included from compiler.pas immediately after this file, in this position. }

{ ===== Pascal calls/operators/directives — carved out into `pasparser_call.inc`.
  Included from compiler.pas immediately after this file, in this position. }

{ ===== Pascal designators/selectors — carved out into `pasparser_lval.inc`. ==
  Included from compiler.pas immediately after this file, in this position. }

{ ===== The Pascal expression parser — carved out into `pasparser_expr.inc`. ==
  Included from compiler.pas immediately after this file, in this position. }

{ ===== Pascal statement parsing — carved out into `pasparser_stmt.inc`. ======
  Included from compiler.pas immediately after this file, in this position. }

{ ===== Pascal declaration parsing — carved out into `pasparser_decl.inc`. ====
  Included from compiler.pas immediately after this file, in this position. }

{ ===== Pascal routine parsing — carved out into `pasparser_proc.inc`. ========
  Included from compiler.pas immediately after this file, in this position. }

{ ===== Pascal program/unit driver — ParseProgram & co. ========================

  Carved out of this file into `pasparser_prog.inc`
  (refactor-a-carve-out-plexer-pparser-so-p-owns-its-own-files).

  It is included from `compiler.pas` on the line immediately after this file,
  NOT by a `{$include}` here, because a nested include cannot be used in the
  compiler's own source: `make compiler/pascal26` compiles it with the PINNED
  binary, and a binary that predates recursive expansion drops the directive.
  A flat list in compiler.pas is also how every other frontend is spelled. }

