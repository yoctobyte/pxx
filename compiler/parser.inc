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

{ ---- nested generic specializations ---------------------------------------

  A template body may name ANOTHER template using the ENCLOSING template's own
  type parameters — as a base class (`generic TDer<T> = class(specialize
  TBase<T>)`), as a field type, anywhere a type may appear. The
  concrete-argument form written inside a template (`specialize TBase<Integer>`)
  already resolves: DelphiRewriteGenericUses sweeps the token stream before the
  enclosing template captures it, mints `TBase$Integer` and inserts the alias
  declaration. The PARAMETER form cannot resolve there — `TBase$T` is not a
  type, and what T is only becomes known when the enclosing template is
  specialized.

  So it resolves at that moment instead. Before streaming TDer<Integer>'s body,
  ParseSpecialization walks the template tokens for `specialize NAME<args>`
  groups, maps each argument through the substitution it is about to apply, and
  mints the same alias name the concrete path would have. If that specialization
  does not exist yet, TDer<Integer> cannot be bound — a parent must exist before
  its child — so the declaration is DEFERRED: emit `TBase$Integer = specialize
  TBase<Integer>;` and then a fresh copy of the declaration we were in the
  middle of, and hand control back to the type-section loop. It parses the
  prerequisite (which defers again if IT nests, so a chain unwinds), then
  re-parses ours, which now finds the alias registered and proceeds. Termination
  is by construction: the retry mints the identical name and finds it.

  Once the prerequisites exist, SpecializeStream collapses each group to the
  single alias identifier, so the body it inserts speaks the ordinary
  non-generic surface the rest of the parser already understands.

  ONE mechanism, both surfaces: the mode-Delphi spelling `TBase<T>` is rewritten
  to `specialize TBase<T>` by DelphiRewriteGenericUses rather than given a
  resolver of its own. }

function FindSpecialization(const nm: AnsiString): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to SpecializationCount - 1 do
    if CaseEqual(Specializations[i].Name, nm) then Result := i;
end;

{ Does TemplateTokens[ts + i] open a `specialize NAME<...>` group naming a
  template we know? Returns the offset of the closing `>`, or -1. A binder
  (`X = specialize ...`, a nested type declaration) is ParseSpecialization's
  own business and is skipped. }
function NestedSpecGroup(ts, i, count: Integer): Integer;
var j, k, ti: Integer; nm: AnsiString; scanning: Boolean;
begin
  Result := -1;
  if i + 3 >= count then Exit;
  if TemplateTokens[ts + i].Kind <> tkIdent then Exit;
  if not CaseEqual(GetTokenStrFromRaw(TemplateTokens[ts + i].SOffset,
                                     TemplateTokens[ts + i].SLen), 'specialize') then Exit;
  if (i > 0) and (TemplateTokens[ts + i - 1].Kind = tkEq) then Exit;
  if TemplateTokens[ts + i + 1].Kind <> tkIdent then Exit;
  if TemplateTokens[ts + i + 2].Kind <> tkLt then Exit;
  nm := GetTokenStrFromRaw(TemplateTokens[ts + i + 1].SOffset, TemplateTokens[ts + i + 1].SLen);
  ti := -1;
  for k := 0 to TemplateCount - 1 do
    if CaseEqual(Templates[k].Name, nm) then ti := k;
  if ti < 0 then Exit;
  j := i + 3;
  scanning := True;
  while scanning do
  begin
    if j >= count then Exit;
    if not (TemplateTokens[ts + j].Kind in [tkIdent, tkInteger_T, tkBoolean_T, tkChar_T, tkString_T]) then Exit;
    Inc(j);
    if (j < count) and (TemplateTokens[ts + j].Kind = tkComma) then Inc(j)
    else scanning := False;
  end;
  if (j >= count) or (TemplateTokens[ts + j].Kind <> tkGt) then Exit;
  Result := j;
end;

{ One argument token of such a group, mapped through the substitution set in
  force (SpecSub*): a reference to the enclosing template's parameter becomes
  the concrete type it is being specialized with. }
procedure NestedSpecArg(ts, at: Integer; var t: TRawToken);
var k: Integer; nm: AnsiString;
begin
  t.Kind := TemplateTokens[ts + at].Kind;
  t.IVal := TemplateTokens[ts + at].IVal;
  t.Line := TemplateTokens[ts + at].Line;
  t.SOffset := TemplateTokens[ts + at].SOffset;
  t.SLen := TemplateTokens[ts + at].SLen;
  if t.Kind <> tkIdent then Exit;
  nm := GetTokenStrFromRaw(t.SOffset, t.SLen);
  for k := 0 to SpecSubCount - 1 do
    if CaseEqual(nm, SpecSubNames[k]) then
    begin
      t.Kind := SpecSubKinds[k];
      t.SOffset := TokCharsAppend(SpecSubValues[k]);
      t.SLen := Length(SpecSubValues[k]);
      Break;
    end;
end;

{ The alias name the group resolves to — the SAME minting DelphiRewriteGenericUses
  uses for a concrete use, so the two paths never disagree about a name. }
function NestedSpecAlias(ts, i, gEnd: Integer): AnsiString;
var j: Integer; t: TRawToken;
begin
  Result := GetTokenStrFromRaw(TemplateTokens[ts + i + 1].SOffset, TemplateTokens[ts + i + 1].SLen);
  j := i + 3;
  while j < gEnd do
  begin
    if TemplateTokens[ts + j].Kind <> tkComma then
    begin
      NestedSpecArg(ts, j, t);
      Result := Result + '$' + GetTokenStrFromRaw(t.SOffset, t.SLen);
    end;
    Inc(j);
  end;
end;

{ Is the alias already available as a type? }
function NestedSpecKnown(const nm: AnsiString): Boolean;
begin
  Result := (FindSpecialization(nm) >= 0) or (FindUClass(nm) >= 0);
end;

procedure SpecializeStream(tokStart, count: Integer; const specName: AnsiString);
{ Substitutions come from the SpecSub* globals (param name -> concrete
  name/kind), set by the caller — multi-param generics replace every type
  parameter in one pass. }
var
  i, j, k: Integer;
  subCount: Integer;
  gEnd: Integer;
  s, aliasNm: AnsiString;
begin
  subCount := 0;
  i := 0;
  while i < count do
  begin
    { A nested generic use collapses to the single alias identifier naming its
      specialization — `specialize TBase<T>` with T:=Integer becomes
      `TBase$Integer`. ParseSpecialization has already guaranteed the alias
      exists (it defers the whole declaration otherwise), so an unresolved group
      here means a name that is not a type at all: leave it alone and let the
      ordinary error reporting name it. }
    gEnd := NestedSpecGroup(tokStart, i, count);
    if gEnd >= 0 then
    begin
      aliasNm := NestedSpecAlias(tokStart, i, gEnd);
      if CaseEqual(aliasNm, specName) or NestedSpecKnown(aliasNm) then
      begin
        SpecializeTokens[subCount].Kind := tkIdent;
        SpecializeTokens[subCount].IVal := 0;
        SpecializeTokens[subCount].Line := TemplateTokens[tokStart + i].Line;
        SpecializeTokens[subCount].SOffset := TokCharsAppend(aliasNm);
        SpecializeTokens[subCount].SLen := Length(aliasNm);
        Inc(subCount);
        i := gEnd + 1;
        Continue;
      end;
    end;
    SpecializeTokens[subCount].Kind := TemplateTokens[tokStart + i].Kind;
    SpecializeTokens[subCount].IVal := TemplateTokens[tokStart + i].IVal;
    SpecializeTokens[subCount].Line := TemplateTokens[tokStart + i].Line;
    SpecializeTokens[subCount].SOffset := TemplateTokens[tokStart + i].SOffset;
    SpecializeTokens[subCount].SLen := TemplateTokens[tokStart + i].SLen;

    if SpecializeTokens[subCount].Kind = tkIdent then
    begin
      s := GetTokenStrFromRaw(SpecializeTokens[subCount].SOffset, SpecializeTokens[subCount].SLen);
      { …except in a BASE-CLASS position (`= class(` immediately before it),
        where the template's own name cannot mean this specialization -- a class
        may not inherit from itself -- and so must mean the ordinary class
        sharing the name (rtl-generics' `THashService<T> = class(THashService)`).
        Rewriting it there produced `base type not found: THS$LongInt`, i.e. the
        specialization looking for itself as its own parent.

        Keyed on the two preceding tokens being `class` `(`, so an ordinary
        typecast `TFoo(x)` inside the body -- where the name DOES mean the
        specialization -- is untouched. }
      if CaseEqual(s, SpecializeTemplateName) and (i >= 2) and
         (TemplateTokens[tokStart + i - 1].Kind = tkLParen) and
         (TemplateTokens[tokStart + i - 2].Kind = tkClass) then
      begin
        { leave the token exactly as it is: names the non-generic sibling }
      end
      else if CaseEqual(s, SpecializeTemplateName) then
      begin
        SpecializeTokens[subCount].SOffset := TokCharLen;
        SpecializeTokens[subCount].SLen := Length(specName);
        if TokCharLen + Length(specName) > STRING_CAP then Error('token char pool overflow');
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
            if TokCharLen + Length(SpecSubValues[k]) > STRING_CAP then Error('token char pool overflow');
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

  EnsureTokCapacity(TokCount + subCount + 1);
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

procedure ParseGenericTemplateNamed(const templateNameIn: AnsiString; delphiForm: Boolean); forward;
function OrdinalNameToTk(const nm: AnsiString): TTypeKind; forward;

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
procedure DelphiRewriteGenericUses(ti, insertAt: Integer; delphiPattern: Boolean);
const MAX_DGEN_TUPLES = 512;
var
  i, j, k, kk, na, np, seenCnt, insCnt, aOff, sOff, tOff: Integer;
  tname, aname, key: AnsiString;
  argTok: array[0..MAX_TEMPLATE_PARAMS-1] of TRawToken;
  seenKey: array[0..MAX_DGEN_TUPLES-1] of AnsiString;
  seenOff: array[0..MAX_DGEN_TUPLES-1] of Integer;
  seenLen: array[0..MAX_DGEN_TUPLES-1] of Integer;
  seenArg: array[0..MAX_DGEN_TUPLES*MAX_TEMPLATE_PARAMS-1] of TRawToken;
  ins: array[0..MAX_TEMPLATE_PARAMS*2+8] of TRawToken;
  ok, isParamForm, specB: Boolean;
  si: Integer;
begin
  tname := Templates[ti].Name;
  np := TemplateNParams[ti];
  seenCnt := 0;
  i := insertAt;
  while i < TokCount - 1 do
  begin
    { Pattern A (mode-Delphi only): bare `TFoo<Args>`. Pattern B (both modes):
      INLINE `specialize TFoo<Args>` in a non-binder position (^specialize
      pointer decls, `var x: specialize TFoo<T>`, typed consts — tgeneric33/
      87/88). The binder form `X = specialize TFoo<...>;` stays with the
      native ParseSpecialization path (previous token = '='). }
    specB := (i + 2 < TokCount) and (Tokens[i].Kind = tkIdent) and
             CaseEqual(GetTokenStr(i), 'specialize') and
             (Tokens[i+1].Kind = tkIdent) and CaseEqual(GetTokenStr(i+1), tname) and
             (Tokens[i+2].Kind = tkLt) and
             ((i = 0) or (Tokens[i-1].Kind <> tkEq));
    if specB or
       (delphiPattern and (Tokens[i].Kind = tkIdent) and (Tokens[i+1].Kind = tkLt) and
        CaseEqual(GetTokenStr(i), tname)) then
    begin
      { collect the <...> argument list }
      ok := True; na := 0;
      if specB then j := i + 3 else j := i + 2;
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
        { A `<...>` group can be resolved EAGERLY into an alias only when every
          argument is a concrete type. An argument spelled with one of this
          template's own parameter names is not concrete: inside another
          template's body it stands for whatever that outer template is
          specialized with, and the two spellings MIX in one group --
          rtl-generics writes
            `TGStringComparer<T> = class(TGStringComparer<T, TDelphiQuadrupleHashFactory>)`.
          So one parameter name anywhere in the group sends the whole group down
          the deferred path (method impls) or the nested-specialization path
          (type references). Matching is by name against ANY parameter, not
          position: `TBar<V, K>` forwards the same names in the other order. }
        isParamForm := False;
        for k := 0 to na - 1 do
          for kk := 0 to np - 1 do
            if (argTok[k].Kind = tkIdent) and
               CaseEqual(GetTokenStrFromRaw(argTok[k].SOffset, argTok[k].SLen),
                         TemplateParamNames[ti * MAX_TEMPLATE_PARAMS + kk]) then
              isParamForm := True;
        if DebugTrace then writeln('DGEN match at ', i, ' na=', na, ' paramform=', isParamForm);
        if isParamForm then
        begin
          if not specB then
          begin
            { `TFoo<T>` spelled with TFoo's OWN parameter names. Only a METHOD
              IMPLEMENTATION header — `procedure TFoo<T>.M` — means "this
              template's own methods", and only there is dropping the `<T>`
              right. Everywhere else it is a TYPE reference carrying the
              ENCLOSING template's parameters (`class(TOrdinalComparer<T,
              THashFactory>)`, a field, a local), which resolves only once that
              enclosing template is specialized: give it the objfpc spelling and
              let ParseSpecialization's nested-prerequisite pass do it. Stripping
              `<T>` there left a bare template name behind and produced
              `base type not found` on rtl-generics. }
            if (j + 1 < TokCount) and (Tokens[j + 1].Kind = tkDot) then
              RemoveTokens(i + 1, j - i)   { method impl reference }
            else
            begin
              ins[0].Kind := tkIdent; ins[0].IVal := 0; ins[0].Line := Tokens[i].Line;
              ins[0].SOffset := TokCharsAppend('specialize'); ins[0].SLen := 10;
              InsertTokens(i, ins, 1);
              i := j + 1;   { the loop's Inc(i) lands past the inserted group }
            end;
          end;
          { specB paramform (inside a later generic body): already objfpc }
        end
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
          { for specB, Tokens[i] was the 'specialize' keyword ident — it
            becomes the alias ident and the whole `TFoo<...>` tail goes }
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
  depth, startTok, cur, finalCur, np, gi, scan: Integer;
  pnames: array[0..MAX_TEMPLATE_PARAMS-1] of AnsiString;
  isOpener, doneParams, bodyless: Boolean;
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
  { A class or interface declaration need not HAVE a body: a forward
    `class;`, a bodyless derived class `class(TBase);`, or a metaclass
    `class of T;`. There is no `end` to count down to, so the depth loop
    below would run on and swallow whatever declaration ends next --
    rtl-generics' one-line
      `TGStringComparer<T> = class(TGStringComparer<T, TDelphiQuadrupleHashFactory>);`
    captured 126 further lines into the template and reported the damage as
    an error deep inside the swallowed text. Detect the bodyless forms up
    front; only a real body goes through the depth count. }
  bodyless := False;
  cur := TokPos;
  if (Tokens[startTok].Kind = tkClass) or
     ((Tokens[startTok].Kind = tkIdent) and CaseEqual(GetTokenStr(startTok), 'interface')) then
  begin
    if (Tokens[startTok].Kind = tkClass) and (cur < TokCount) and (Tokens[cur].Kind = tkOf) then
    begin
      while (cur < TokCount) and (Tokens[cur].Kind <> tkSemicolon) do Inc(cur);
      bodyless := True;
    end
    else
    begin
      scan := cur;
      if (scan < TokCount) and (Tokens[scan].Kind = tkLParen) then
      begin
        depth := 0;
        repeat
          if Tokens[scan].Kind = tkLParen then Inc(depth)
          else if Tokens[scan].Kind = tkRParen then Dec(depth);
          Inc(scan);
        until (scan >= TokCount) or (depth = 0);
      end;
      if (scan < TokCount) and (Tokens[scan].Kind = tkSemicolon) then
      begin
        cur := scan;
        bodyless := True;
      end;
    end;
  end;

  if bodyless then
  begin
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
  DelphiRewriteGenericUses(TemplateCount - 1, finalCur, delphiForm);

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

{ Emit one `alias = specialize NAME<args>;` declaration into NSpecIns, reading
  the argument tokens from NSpecArg[base..base+nArgs-1]. }
procedure EmitSpecDecl(const aliasNm, tmplNm: AnsiString; base, nArgs: Integer);
var k: Integer; ln: Integer;
begin
  ln := 0;
  if TokPos > 0 then ln := Tokens[TokPos - 1].Line;
  if NSpecInsCnt + 8 + 2 * nArgs > MAX_NESTED_SPECS * (8 + 2 * MAX_TEMPLATE_PARAMS) then
    Error('nested specialization token buffer overflow');
  NSpecIns[NSpecInsCnt].Kind := tkIdent; NSpecIns[NSpecInsCnt].IVal := 0;
  NSpecIns[NSpecInsCnt].Line := ln;
  NSpecIns[NSpecInsCnt].SOffset := TokCharsAppend(aliasNm);
  NSpecIns[NSpecInsCnt].SLen := Length(aliasNm); Inc(NSpecInsCnt);
  NSpecIns[NSpecInsCnt].Kind := tkEq; NSpecIns[NSpecInsCnt].IVal := 0;
  NSpecIns[NSpecInsCnt].Line := ln; NSpecIns[NSpecInsCnt].SOffset := 0;
  NSpecIns[NSpecInsCnt].SLen := 0; Inc(NSpecInsCnt);
  NSpecIns[NSpecInsCnt].Kind := tkIdent; NSpecIns[NSpecInsCnt].IVal := 0;
  NSpecIns[NSpecInsCnt].Line := ln;
  NSpecIns[NSpecInsCnt].SOffset := TokCharsAppend('specialize');
  NSpecIns[NSpecInsCnt].SLen := 10; Inc(NSpecInsCnt);
  NSpecIns[NSpecInsCnt].Kind := tkIdent; NSpecIns[NSpecInsCnt].IVal := 0;
  NSpecIns[NSpecInsCnt].Line := ln;
  NSpecIns[NSpecInsCnt].SOffset := TokCharsAppend(tmplNm);
  NSpecIns[NSpecInsCnt].SLen := Length(tmplNm); Inc(NSpecInsCnt);
  NSpecIns[NSpecInsCnt].Kind := tkLt; NSpecIns[NSpecInsCnt].IVal := 0;
  NSpecIns[NSpecInsCnt].Line := ln; NSpecIns[NSpecInsCnt].SOffset := 0;
  NSpecIns[NSpecInsCnt].SLen := 0; Inc(NSpecInsCnt);
  for k := 0 to nArgs - 1 do
  begin
    if k > 0 then
    begin
      NSpecIns[NSpecInsCnt].Kind := tkComma; NSpecIns[NSpecInsCnt].IVal := 0;
      NSpecIns[NSpecInsCnt].Line := ln; NSpecIns[NSpecInsCnt].SOffset := 0;
      NSpecIns[NSpecInsCnt].SLen := 0; Inc(NSpecInsCnt);
    end;
    NSpecIns[NSpecInsCnt] := NSpecArg[base + k]; Inc(NSpecInsCnt);
  end;
  NSpecIns[NSpecInsCnt].Kind := tkGt; NSpecIns[NSpecInsCnt].IVal := 0;
  NSpecIns[NSpecInsCnt].Line := ln; NSpecIns[NSpecInsCnt].SOffset := 0;
  NSpecIns[NSpecInsCnt].SLen := 0; Inc(NSpecInsCnt);
  NSpecIns[NSpecInsCnt].Kind := tkSemicolon; NSpecIns[NSpecInsCnt].IVal := 0;
  NSpecIns[NSpecInsCnt].Line := ln; NSpecIns[NSpecInsCnt].SOffset := 0;
  NSpecIns[NSpecInsCnt].SLen := 0; Inc(NSpecInsCnt);
end;

{ Result = True means the declaration was DEFERRED: its nested generic
  prerequisites have been emitted ahead of a fresh copy of it, nothing was
  registered, and the caller must go round the type-section loop again rather
  than bind a class. See the nested-specialization note above SpecializeStream. }
function ParseSpecialization(const specName: AnsiString): Boolean;
var
  templateName, aliasNm: AnsiString;
  cNames: array[0..MAX_TEMPLATE_PARAMS-1] of AnsiString;
  cKinds: array[0..MAX_TEMPLATE_PARAMS-1] of TTokenKind;
  nc, ti, i, j, k, na, ts, tc, gEnd, si, dfIdx: Integer;
  dup: Boolean;
begin
  Result := False;
  Next; { consume 'specialize' }
  if CurTok.Kind <> tkIdent then Error('expected generic template name');
  templateName := CurTok.SVal; Next;

  Expect(tkLt, '<');
  nc := 0;
  NSpecCount := 0;
  repeat
    if (CurTok.Kind <> tkIdent) and (CurTok.Kind <> tkInteger_T) and (CurTok.Kind <> tkBoolean_T) and (CurTok.Kind <> tkChar_T) and (CurTok.Kind <> tkString_T) then
      Error('expected concrete type name');
    if nc >= MAX_TEMPLATE_PARAMS then Error('too many specialization arguments (MAX_TEMPLATE_PARAMS)');
    cNames[nc] := CurTok.SVal;
    cKinds[nc] := CurTok.Kind;
    { keep the raw token too — a deferral re-emits this declaration verbatim }
    NSpecArg[(MAX_NESTED_SPECS - 1) * MAX_TEMPLATE_PARAMS + nc] := Tokens[TokPos - 1];
    Inc(nc);
    Next;
  until not Eat(tkComma);
  Expect(tkGt, '>');
  { Leave CurTok on the trailing ';' (do NOT Eat) so SpecializeStream inserts
    the class-body tokens right after it; the final Next then lands CurTok on
    the inserted 'class', and the caller falls through to the class-binding
    branch (which names the concrete class from the saved tnOff/tnLen). }

  { Arity-overloaded template names are legal (`TD`, `TD<K>`, `TD<K,V>` — see
    test_generic_name_overload.pas), so the ARGUMENT COUNT is part of the
    lookup. Order alone used to be enough because a concrete use's alias
    declaration is inserted right behind its own template, and so is parsed
    before the next arity is even captured; a nested prerequisite is emitted
    much further down the stream, where every arity is visible at once. }
  ti := -1;
  for i := 0 to TemplateCount - 1 do
    if CaseEqual(Templates[i].Name, templateName) then
      if (ti < 0) or (TemplateNParams[i] = nc) then ti := i;
  if ti < 0 then Error('generic template ' + templateName + ' not found');
  if nc <> TemplateNParams[ti] then
    Error('specialize ' + templateName + ': wrong number of type arguments');

  { The substitution set is established HERE, before anything is registered,
    because the prerequisite scan below decides whether this declaration gets
    registered at all this time round. }
  SpecSubCount := nc;
  for i := 0 to nc - 1 do
  begin
    SpecSubNames[i]  := TemplateParamNames[ti * MAX_TEMPLATE_PARAMS + i];
    SpecSubValues[i] := cNames[i];
    SpecSubKinds[i]  := cKinds[i];
  end;

  { Nested generic prerequisites: every `specialize NAME<args>` in the body,
    with args mapped through the substitution, that is not a type yet. }
  ts := Templates[ti].TokStart;
  tc := Templates[ti].TokCount;
  i := 0;
  while i < tc do
  begin
    gEnd := NestedSpecGroup(ts, i, tc);
    if gEnd >= 0 then
    begin
      aliasNm := NestedSpecAlias(ts, i, gEnd);
      if (not CaseEqual(aliasNm, specName)) and (not NestedSpecKnown(aliasNm)) then
      begin
        dup := False;
        for k := 0 to NSpecCount - 1 do
          if CaseEqual(NSpecName[k], aliasNm) then dup := True;
        if not dup then
        begin
          if NSpecCount >= MAX_NESTED_SPECS - 1 then
            Error('too many nested generic specializations (MAX_NESTED_SPECS)');
          NSpecName[NSpecCount] := aliasNm;
          NSpecTmpl[NSpecCount] := GetTokenStrFromRaw(TemplateTokens[ts + i + 1].SOffset,
                                                     TemplateTokens[ts + i + 1].SLen);
          na := 0;
          j := i + 3;
          while j < gEnd do
          begin
            if TemplateTokens[ts + j].Kind <> tkComma then
            begin
              NestedSpecArg(ts, j, NSpecArg[NSpecCount * MAX_TEMPLATE_PARAMS + na]);
              Inc(na);
            end;
            Inc(j);
          end;
          NSpecNArg[NSpecCount] := na;
          Inc(NSpecCount);
        end;
      end;
      i := gEnd + 1;
    end
    else
      Inc(i);
  end;

  { A prerequisite queued by one deferral may already have been satisfied by
    another: rtl-generics reaches TCustomComparer$string through BOTH
    TGStringComparer and TOrdinalComparer, and each deferral emits its own copy
    of the alias declaration. The second copy is an exact re-statement of the
    first -- same template, same arguments, and the name is minted from exactly
    those -- so it is a no-op, not a redeclaration. Consume it and let the
    type-section loop go round again. A name that collides with a DIFFERENT
    template or different arguments still falls through to the ordinary
    duplicate-class diagnosis. }
  si := FindSpecialization(specName);
  if (si >= 0) and CaseEqual(Specializations[si].TemplateName, templateName) and
     (SpecNParams[si] = nc) then
  begin
    dup := True;
    for i := 0 to nc - 1 do
      if not CaseEqual(SpecConcreteNames[si * MAX_TEMPLATE_PARAMS + i], cNames[i]) then
        dup := False;
    if dup then
    begin
      if DebugTrace then writeln('SPEC ', specName, ' = ', templateName, ' (already declared)');
      NSpecCount := 0;
      Next;
      Result := True;
      Exit;
    end;
  end;

  if DebugTrace then
  begin
    writeln('SPEC ', specName, ' = ', templateName, ' nested=', NSpecCount);
    for k := 0 to NSpecCount - 1 do
      writeln('  needs ', NSpecName[k], ' from ', NSpecTmpl[k]);
  end;

  if NSpecCount > 0 then
  begin
    { Defer. CurTok is this declaration's trailing ';', so TokPos is exactly
      where the type-section loop reads next: put the prerequisites there,
      followed by a fresh copy of this declaration. Nothing has been registered,
      so the retry is a clean re-parse. }
    dfIdx := -1;
    for k := 0 to SpecDeferCount - 1 do
      if CaseEqual(SpecDeferName[k], specName) then dfIdx := k;
    if dfIdx < 0 then
    begin
      if SpecDeferCount >= MAX_SPECIALIZATIONS then Error('too many deferred specializations');
      dfIdx := SpecDeferCount;
      SpecDeferName[dfIdx] := specName;
      SpecDeferRound[dfIdx] := 0;
      Inc(SpecDeferCount);
    end;
    Inc(SpecDeferRound[dfIdx]);
    { A deferral is only progress while the unmet prerequisite set shrinks, and
      it cannot legitimately take more rounds than there are specializations in
      the whole program. More than that means a CYCLE -- two specializations
      requiring each other -- which used to spin forever, inserting a fresh copy
      of both declarations into the token stream every round with no diagnostic
      and no end. Name both sides: the cycle is what the author has to break. }
    if SpecDeferRound[dfIdx] > MAX_SPECIALIZATIONS then
      Error('circular generic specialization: ' + specName + ' requires ' +
            NSpecName[0] + ', which requires ' + specName + ' back');
    NSpecInsCnt := 0;
    for k := 0 to NSpecCount - 1 do
      EmitSpecDecl(NSpecName[k], NSpecTmpl[k], k * MAX_TEMPLATE_PARAMS, NSpecNArg[k]);
    EmitSpecDecl(specName, templateName, (MAX_NESTED_SPECS - 1) * MAX_TEMPLATE_PARAMS, nc);
    InsertTokens(TokPos, NSpecIns, NSpecInsCnt);
    NSpecCount := 0;
    Next;
    Result := True;
    Exit;
  end;

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

function IsGenericTemplateName(const name: AnsiString): Boolean;
{ True when the name is a registered generic TEMPLATE (`TFoo<T>`), i.e. not a type on
  its own — it has no size and no zero value until it is specialized. A specialization
  is registered under its own concrete name, so this never fires for one. }
var i: Integer;
begin
  Result := False;
  for i := 0 to TemplateCount - 1 do
    if CaseEqual(Templates[i].Name, name) then begin Result := True; Exit; end;
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
  if TokCharLen + Length(funcName) > STRING_CAP then Error('token char pool overflow');
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
  opKey, dupPi: Integer;
  scalarTk, scalarTk2: TTypeKind;
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
  { `class operator TPt.+ (const a, b: TPt): TPt;` — FPC's ADVANCED-RECORD operator syntax.
    Both the `class` prefix and the `TRec.` qualifier are accepted and dropped: pxx keys an
    operator on its OPERAND TYPES, not on an owning type, so the qualifier carries no
    information the signature does not already have. A plain top-level
    `operator + (a, b: TPt): TPt` was already supported and means exactly the same thing —
    this just lets FPC's spelling through to the same machinery. }
  if CurTok.Kind = tkClass then Next;
  Next; { consume 'operator' }
  if (CurTok.Kind = tkIdent) and (TokPos < TokCount) and (Tokens[TokPos].Kind = tkDot) then
  begin
    Next;   { the TRec qualifier }
    Next;   { the dot }
  end;
  opKind := CurTok.Kind;
  opKey := -1;
  if opKind in [tkPlus, tkMinus, tkStar, tkSlash, tkDiv, tkMod, tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe] then
    opKey := Ord(opKind)
  else if opKind = tkAssign then
    { `operator :=(src): TDst` — implicit conversion at assignment }
    opKey := Ord(tkAssign)
  else if opKind = tkIdent then
  begin
    { Named operators (FPC): Implicit = the := form; Explicit fires at
      value casts; Inc/Dec at the Inc()/Dec() statements; Enumerator at for-in.
      Initialize/Finalize are MANAGEMENT operators — the compiler invokes them
      at a variable's lifetime events, not at an expression. }
    if CaseEqual(CurTok.SVal, 'implicit') then opKey := Ord(tkAssign)
    else if CaseEqual(CurTok.SVal, 'explicit') then opKey := OPK_EXPLICIT
    else if CaseEqual(CurTok.SVal, 'inc') then opKey := OPK_INC
    else if CaseEqual(CurTok.SVal, 'dec') then opKey := OPK_DEC
    else if CaseEqual(CurTok.SVal, 'enumerator') then opKey := OPK_ENUMERATOR
    else if CaseEqual(CurTok.SVal, 'initialize') then opKey := OPK_INITIALIZE
    else if CaseEqual(CurTok.SVal, 'finalize') then opKey := OPK_FINALIZE
    else if CaseEqual(CurTok.SVal, 'addref') then opKey := OPK_ADDREF
    else if CaseEqual(CurTok.SVal, 'copy') then opKey := OPK_COPY;
  end;
  if opKey < 0 then
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
  scalarTk2 := tyUnknown;
  if recId = REC_NONE then
  begin
    ci := FindUClass(typeName);
    if ci >= 0 then
    begin
      recId := REC_UCLASS_BASE + ci;
      opTypeKind := Ord(tyClass);
    end
    else
    begin
      { SCALAR operand types (FPC allows operators on any type —
        tgenfunc8's `operator := (aOther: LongInt): String`). Key the
        registration on the type kind with recId REC_NONE. `String`
        registers under BOTH the managed and frozen kinds — a string
        expression types as either depending on origin. }
      scalarTk := OrdinalNameToTk(typeName);
      if scalarTk = tyUnknown then
      begin
        if CaseEqual(typeName, 'string') or CaseEqual(typeName, 'ansistring') then
        begin
          scalarTk := tyAnsiString;
          scalarTk2 := tyString;
        end
        else if CaseEqual(typeName, 'single') then scalarTk := tySingle
        else if CaseEqual(typeName, 'double') or CaseEqual(typeName, 'real') or
                CaseEqual(typeName, 'extended') then scalarTk := tyDouble;
      end;
      if scalarTk = tyUnknown then
        Error('operator overloading: ' + typeName + ' is not a supported operand type');
      opTypeKind := Ord(scalarTk);
      recId := REC_NONE;
    end;
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
  EnsureTokCapacity(TokCount + 3);
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
  if TokCharLen + nameLen > STRING_CAP then Error('token char pool overflow');
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
  { Arity: conversion/unary named operators take exactly ONE parameter —
    FPC rejects `operator :=(S1, S2: String)` (tassignmentoperator1 %fail). }
  { Copy/AddRef are recognised so the spelling is not a syntax error, but they
    fire on a value COPY, which nothing dispatches yet — accepting one silently
    would give a record whose invariant simply never runs, which is worse than
    not compiling. Refuse loudly and name the ticket instead.
    feature-pascal-class-management-operators }
  if (opKey = OPK_ADDREF) or (opKey = OPK_COPY) then
    Error('operator Copy/AddRef is recognised but not dispatched yet — the copy '
          + 'lifetime event is a separate slice '
          + '(feature-pascal-management-operators-copy-and-addref)');
  if (opKey = OPK_INITIALIZE) or (opKey = OPK_FINALIZE) then
  begin
    { `class operator Initialize(var a: TFoo)` — exactly one VAR parameter of
      the record type, and no result. FPC's own shape. }
    if Procs[procIdx].ParamCount <> 1 then
      Error('a management operator must take exactly one parameter');
    if Procs[procIdx].IsFunc then
      Error('a management operator must be a procedure (no result)');
    if recId = REC_NONE then
      Error('a management operator needs a record or class operand type');
    if not Procs[procIdx].Params[0].IsRef then
      Error('a management operator takes its operand as a var parameter');
  end
  else if (opKey = Ord(tkAssign)) or (opKey = OPK_EXPLICIT) or (opKey = OPK_INC) or
     (opKey = OPK_DEC) or (opKey = OPK_ENUMERATOR) then
  begin
    if Procs[procIdx].ParamCount <> 1 then
      Error('this operator must take exactly one parameter');
    { FPC forbids conversion operators between two BUILT-IN ordinal types
      (toperator90's Explicit LongInt -> Boolean %fail): a standard
      conversion already exists. A string/record/class/float on either side
      makes it a legal user conversion (tgenfunc8's LongInt <-> String). }
    if ((opKey = Ord(tkAssign)) or (opKey = OPK_EXPLICIT)) and
       (recId = REC_NONE) and TypeIsOrdinal(IntToTypeKind(opTypeKind)) and
       TypeIsOrdinal(Procs[procIdx].RetType) then
      Error('impossible operator overload: a standard conversion between these types exists');
  end
  else
  begin
    if Procs[procIdx].ParamCount <> 2 then
      Error('binary operator must take exactly two parameters');
    { FPC forbids overloading a BINARY symbol operator when the operation is
      predefined for the operand types — at least one operand must be a
      record/class (toperator13..68 %fails: +,-,<,= on LongInt/AnsiString). }
    if recId = REC_NONE then
      Error('impossible operator overload: this operation is predefined for built-in operand types');
  end;
  { FPC-parity rejections (bug-pascal-missing-diagnostics-fail-tests): }
  { = / <> are predefined for CLASS operands (reference equality) and cannot
    be overloaded (toperator71). The PXX dialect deliberately allows it (value
    equality on classes, test_op_overload.pas), so the rejection is strict-only.
    Other operators on records/classes are the normal overload surface and stay. }
  if StrictOperator and (opTypeKind = Ord(tyClass)) and
     ((opKey = Ord(tkEq)) or (opKey = Ord(tkNeq))) then
    Error('impossible operator overload: = and <> are predefined for class types (reference equality)');
  { A SECOND := / Implicit / Explicit from the same source type to a result of
    the same TYPE KIND is ambiguous at every use site — String[80] vs
    String[90] targets are indistinguishable (toperator92; toperator95 splits
    the same pair across a class operator and a global one). Distinct result
    kinds (-> Integer vs -> String) remain legal. }
  if (opKey = Ord(tkAssign)) or (opKey = OPK_EXPLICIT) then
  begin
    dupPi := FindOpOverload(opKey, opTypeKind, recId);
    if (dupPi >= 0) and (Procs[dupPi].RetType = Procs[procIdx].RetType) then
      Error('duplicate conversion operator: this source type already converts to this result type');
  end;
  RegisterOpOverload(opKey, opTypeKind, recId, procIdx);
  if scalarTk2 <> tyUnknown then
    RegisterOpOverload(opKey, Ord(scalarTk2), REC_NONE, procIdx);
end;

{ Linear (row-major) index of an N-D fixed array element, built from AST nodes so
  it feeds the ordinary 1-D AN_INDEX (no codegen change). Reads the dims from
  NDInfoLo/Span and the parsed index exprs from NDIdxNode; nd dimensions.
  Horner form: acc = (i0-lo0); acc = acc*span_d + (i_d - lo_d) for d = 1..nd-1. }
function NDChkIdx(idxNode: Integer; lo, hi: Int64): Integer;
{ {$R+}: wrap ONE N-D subscript in PXXRangeChkI64(i, lo, hi) — the flattened
  Horner index reaches IR as a single expression, so per-dimension bounds can
  only be applied here at composition time (statement-anchored, like every
  other {$R+} site). Passthrough when checks are off / builtinheap absent
  (feature-range-checks-nd-bases). }
var pi, a1, a2, a3, litN: Integer;
begin
  Result := idxNode;
  if not StmtRChecks then Exit;
  pi := FindProc('PXXRangeChkI64');
  if pi < 0 then Exit;
  a1 := AllocNode(AN_ARG); ASTLeft[a1] := idxNode; ASTTk[a1] := Ord(tyInt64);
  litN := AllocNode(AN_INT_LIT); ASTIVal[litN] := lo; ASTTk[litN] := Ord(tyInt64);
  a2 := AllocNode(AN_ARG); ASTLeft[a2] := litN; ASTTk[a2] := Ord(tyInt64);
  ASTRight[a1] := a2;
  litN := AllocNode(AN_INT_LIT); ASTIVal[litN] := hi; ASTTk[litN] := Ord(tyInt64);
  a3 := AllocNode(AN_ARG); ASTLeft[a3] := litN; ASTTk[a3] := Ord(tyInt64);
  ASTRight[a2] := a3;
  Result := AllocNode(AN_CALL); ASTIVal[Result] := pi;
  ASTLeft[Result] := a1; ASTRight[Result] := -1; ASTTk[Result] := Ord(tyInt64);
end;

function BuildFlatNDIndex(nd: Integer): Integer;
var d, loLit, spanLit, diff, scaled, acc: Integer;
begin
  loLit := AllocNode(AN_INT_LIT); ASTIVal[loLit] := NDInfoLo[0]; ASTTk[loLit] := Ord(tyInteger);
  acc := AllocNode(AN_BINOP); ASTIVal[acc] := Ord(tkMinus);
  ASTLeft[acc] := NDChkIdx(NDIdxNode[0], NDInfoLo[0],
                           NDInfoLo[0] + NDInfoSpan[0] - 1);
  ASTRight[acc] := loLit; ASTTk[acc] := Ord(tyInteger);
  for d := 1 to nd - 1 do
  begin
    spanLit := AllocNode(AN_INT_LIT); ASTIVal[spanLit] := NDInfoSpan[d]; ASTTk[spanLit] := Ord(tyInteger);
    scaled := AllocNode(AN_BINOP); ASTIVal[scaled] := Ord(tkStar);   { acc * span_d }
    ASTLeft[scaled] := acc; ASTRight[scaled] := spanLit; ASTTk[scaled] := Ord(tyInteger);
    loLit := AllocNode(AN_INT_LIT); ASTIVal[loLit] := NDInfoLo[d]; ASTTk[loLit] := Ord(tyInteger);
    diff := AllocNode(AN_BINOP); ASTIVal[diff] := Ord(tkMinus);    { i_d - lo_d }
    ASTLeft[diff] := NDChkIdx(NDIdxNode[d], NDInfoLo[d],
                              NDInfoLo[d] + NDInfoSpan[d] - 1);
    ASTRight[diff] := loLit; ASTTk[diff] := Ord(tyInteger);
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
{ The `index N` constant of a property, as the accessor's first argument. Does nothing for a
  property without one, so it is safe to call unconditionally beside ParsePropIndexArgs. }
procedure PropIndexConstArg(pri: Integer; var head, tail: Integer);
var n: Integer;
begin
  if (pri < 0) or (not UPropHasIndex[pri]) then Exit;
  n := AllocNode(AN_INT_LIT);
  ASTIVal[n] := UPropIndexVal[pri];
  ASTTk[n] := Ord(tyInteger);
  head := AllocNode(AN_ARG);
  ASTLeft[head] := n;
  tail := head;
end;

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
{ The AST node for parameter k's declared default value. Errors when k has no
  default. Shared by the trailing-arg fill below and the Nil Python
  keyword-argument bind, which needs the same node for a HOLE in the middle. }
function DefaultArgValueNode(mpi, k: Integer): Integer;
var exprNode: Integer;
begin
  if (k >= MAX_PROC_PARAMS) or (not ProcParamHasDefault[mpi * MAX_PROC_PARAMS + k]) then
    Error('not enough arguments to ' + Procs[mpi].Name +
          ' (parameter ' + Procs[mpi].Params[k].Name + ' has no default)');
  { A NON-CONSTANT NilPy default (`b=[]`, `b={}`, `b=w`) was evaluated ONCE into
    a hidden global at the def statement, because that is when Python evaluates
    it — and it is what makes the shared-mutable-default idiom accumulate. The
    omitted argument therefore READS that global; it does not rebuild a value,
    which would give a fresh container per call and diverge on the accumulator
    idiom (bug-nilpy-non-constant-parameter-defaults-silently-become-none). }
  if ProcParamDefaultSym[mpi * MAX_PROC_PARAMS + k] >= 0 then
    exprNode := PyMakeIdent(ProcParamDefaultSym[mpi * MAX_PROC_PARAMS + k])
  else if ProcParamDefaultIsStr[mpi * MAX_PROC_PARAMS + k] then
  begin
    exprNode := AllocNode(AN_STR_LIT);
    ASTSOffset[exprNode] := ProcParamDefaultSOff[mpi * MAX_PROC_PARAMS + k];
    ASTSLen[exprNode] := ProcParamDefaultSLen[mpi * MAX_PROC_PARAMS + k];
    { Tag the literal with the PARAMETER's own string kind. tyString is the
      FROZEN inline-length kind; a parameter declared tyAnsiString is the
      managed refcounted one, and a frozen literal handed to it arrived as the
      EMPTY string. That is why a @dataclass `s: str = "t"` silently defaulted
      to '' while the int/float/bool defaults beside it were all correct —
      which is exactly what made the class look like defaults work.
      bug-nilpy-dataclass-str-field-default-is-dropped }
    if Procs[mpi].Params[k].TypeKind = tyAnsiString then
      ASTTk[exprNode] := Ord(tyAnsiString)
    else
      ASTTk[exprNode] := Ord(tyString);
  end
  else if ProcParamDefaultIsFloat[mpi * MAX_PROC_PARAMS + k] then
  begin
    { the stored ordinal IS the double's IEEE bits — see PyParamDefaultAt }
    exprNode := AllocNode(AN_FLOAT_LIT);
    ASTIVal[exprNode] := ProcParamDefaultVal[mpi * MAX_PROC_PARAMS + k];
    ASTTk[exprNode] := Ord(tyDouble);
  end
  else if ProcParamDefaultIsSet[mpi * MAX_PROC_PARAMS + k] then
  begin
    { a SET default: the value is the Data[] offset of the mask baked at the
      declaration, so the call site just references it }
    exprNode := AllocNode(AN_SET_CONST_REF);
    ASTIVal[exprNode] := ProcParamDefaultVal[mpi * MAX_PROC_PARAMS + k];
    ASTTk[exprNode] := Ord(tySet);
  end
  else if isNilPy and (Procs[mpi].Params[k].TypeKind = tyVariant) and
          (ProcParamDefaultIsNone[mpi * MAX_PROC_PARAMS + k] or
           ((ProcUnitIdx[mpi] >= 0) and
            (not UnitIsPyModule(ProcUnitIdx[mpi])))) then
    { A variant parameter is passed by REFERENCE — the callee reads a 16-byte
      slot through a pointer — so a `= None` default cannot be a bare ordinal:
      the callee dereferences it the moment it touches the parameter.
      `def go(self, x, s=None)` called as `A().go(1)` segfaulted on it.

      A NilPy def's declared value falls through to the ordinal node below and
      is boxed by IRLowerCallArg, exactly as a WRITTEN literal argument is —
      passing None for every default meant `def f(a=1)` called as `f()` ran
      with a=None, silently.

      A LIBRARY routine (ProcUnitIdx >= 0) is the other way round. Its
      `const opt: Variant = 0` spells "not supplied", and every façade in
      lib/pcl tests `pyvartag(v) <> 0` to find out. Boxing the 0 as an INTEGER
      made an omitted option look GIVEN: `canvas.configure(yscrollcommand=...)`
      passed a filled xscrollcommand too, and tkinter refused it — the first
      thing songformatter did at run time. }
    exprNode := PyMakeNone
  else if isNilPy and ProcParamDefaultIsBool[mpi * MAX_PROC_PARAMS + k] and
          (Procs[mpi].Params[k].TypeKind = tyVariant) then
  begin
    { `b=True` into a VARIANT parameter: recorded as the ordinal 1, and boxed as
      an integer the variant prints 1 rather than True. }
    exprNode := AllocNode(AN_BOOL_LIT);
    ASTIVal[exprNode] := ProcParamDefaultVal[mpi * MAX_PROC_PARAMS + k];
    ASTTk[exprNode] := Ord(tyBoolean);
  end
  else
  begin
    exprNode := AllocNode(AN_INT_LIT);
    ASTIVal[exprNode] := ProcParamDefaultVal[mpi * MAX_PROC_PARAMS + k];
    ASTTk[exprNode] := Ord(Procs[mpi].Params[k].TypeKind);
    { A VARIANT parameter takes the literal as an INTEGER, so IRLowerCallArg
      boxes it into a variant temp and passes the temp's address. Tagged with
      the parameter's own type it looked like a variant already, the boxing was
      skipped, and the callee dereferenced a bare ordinal — `def g(self, x,
      s=5)` called as `A().g(1)` segfaulted. }
    if Procs[mpi].Params[k].TypeKind = tyVariant then
      ASTTk[exprNode] := Ord(tyInteger);
  end;
  DefaultArgValueNode := exprNode;
end;

procedure FillDefaultArgs(mpi, fromIdx, callNode: Integer; var lastArg: Integer);
var exprNode, argSeq, k: Integer;
begin
  k := fromIdx;
  while k <= Procs[mpi].ParamCount - 1 do
  begin
    exprNode := DefaultArgValueNode(mpi, k);
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

{ A call written with FEWER arguments than any overload declares, where the
  missing ones all carry defaults — `filedialog.askopenfilename()` against
  `askopenfilename(title=''; filetypes=...; ...)`. The method paths have filled
  trailing defaults for a long time (CanFillDefaultsFrom); the plain
  qualified/unqualified CALL path never did, so a Python call that simply
  omitted every optional argument reported "no overload matches these
  arguments" and named no reason.

  Returns the proc it filled for, or -1 to leave the caller's diagnostic alone.
  Only trailing parameters are supplied, and only when EVERY one of them has a
  declared default — an arity that is short by a non-defaulted parameter is
  still a real mismatch. }
function TryFillTrailingDefaults(const name: AnsiString; qUnit: Integer;
  var nArgs, argsHead, lastArg: Integer): Integer;
var i, k, cand, exprNode, argSeq: Integer; ok: Boolean;
begin
  cand := -1;
  for i := 0 to ProcCount - 1 do
    if ((Procs[i].Name = name) or
        ((not ProcCaseSensitive[i]) and CaseEqual(Procs[i].Name, name))) and
       ((qUnit < 0) or (ProcUnitIdx[i] = qUnit)) and
       (Procs[i].ParamCount > nArgs) and (Procs[i].ParamCount <= MAX_PROC_PARAMS) then
    begin
      ok := True;
      for k := nArgs to Procs[i].ParamCount - 1 do
      begin
        if not ProcParamHasDefault[i * MAX_PROC_PARAMS + k] then ok := False;
      end;
      if ok then
      begin
        cand := i;
        Break;
      end;
    end;
  if cand < 0 then
  begin
    TryFillTrailingDefaults := -1;
    Exit;
  end;
  for k := nArgs to Procs[cand].ParamCount - 1 do
  begin
    exprNode := DefaultArgValueNode(cand, k);
    argSeq := AllocNode(AN_ARG);
    ASTLeft[argSeq] := exprNode;
    ASTRight[argSeq] := -1;
    if lastArg = -1 then argsHead := argSeq
    else ASTRight[lastArg] := argSeq;
    lastArg := argSeq;
  end;
  nArgs := Procs[cand].ParamCount;
  TryFillTrailingDefaults := cand;
end;

{ Count the arguments of the call whose NAME is CurTok (Tokens[TokPos] = '('
  when parenthesized): top-level commas + 1; 0 for `()` or no parens. Used to
  pick among method OVERLOADS before the signature-driven arg loop parses. }
function IsCallConvDirectiveTok: Boolean;
{ A calling-convention directive in ANY directive list — class-body member
  (`function QueryInterface(...): HResult; virtual; cdecl;` — testutils),
  record method, interface method signature, routine implementation header, and
  the routine pre-scan. They are plain identifiers, and pxx is a whole-program
  compiler with one internal convention, so they are parse-and-ignore
  everywhere.

  ONE list, five call sites, deliberately: each of those loops grew its own
  spelling of the set and they drifted apart — the implementation-side loop
  knew `cdecl` and `register` but not `stdcall`, so `procedure TC.Poke;
  stdcall;` parsed in the class body and then died on its own body's header.
  Add a convention here and every position accepts it.

  Guarded on a following ';' because these words are not reserved: a FIELD named
  `register` is legal, and `register: Integer;` has a ':' next, so it stays a
  field. A directive is always followed by the semicolon. }
begin
  Result := False;
  if CurTok.Kind <> tkIdent then Exit;
  if not (CaseEqual(CurTok.SVal, 'cdecl') or CaseEqual(CurTok.SVal, 'stdcall') or
          CaseEqual(CurTok.SVal, 'safecall') or CaseEqual(CurTok.SVal, 'register') or
          CaseEqual(CurTok.SVal, 'pascal') or CaseEqual(CurTok.SVal, 'mwpascal')) then Exit;
  Result := (TokPos < TokCount) and (Tokens[TokPos].Kind = tkSemicolon);
end;

function EatIntfMethodDirective: Boolean;
{ One directive on an INTERFACE method signature, plus its trailing ';'.
  An interface method is abstract and virtual by definition, so the dispatch
  directives (virtual/override/abstract/static) mean nothing here and FPC
  rejects them; what IS legal is `overload`, a calling convention, and the
  hint directives. All are parse-and-ignore -- overload resolution is
  signature-keyed, pxx is a whole-program compiler with one internal calling
  convention, and a hint changes no code.

  The interface member loop had NO directive handling at all, so a signature
  carrying one stopped the parse where it stood: rtl-generics' very first
  declaration is `function Compare(constref Left, Right: T): Integer;
  overload;`. Guarded like IsCallConvDirectiveTok -- these words are not
  reserved, so a directive is recognised only where a ';' (or `deprecated`'s
  message string) follows. }
begin
  Result := False;
  if CurTok.Kind = tkOverload then
  begin
    Next; Eat(tkSemicolon); Result := True; Exit;
  end;
  if IsCallConvDirectiveTok then
  begin
    Next; Eat(tkSemicolon); Result := True; Exit;
  end;
  if (CurTok.Kind = tkIdent) and
     (CaseEqual(CurTok.SVal, 'deprecated') or CaseEqual(CurTok.SVal, 'platform') or
      CaseEqual(CurTok.SVal, 'experimental') or CaseEqual(CurTok.SVal, 'unimplemented') or
      CaseEqual(CurTok.SVal, 'library') or CaseEqual(CurTok.SVal, 'varargs')) and
     (TokPos < TokCount) and
     ((Tokens[TokPos].Kind = tkSemicolon) or (Tokens[TokPos].Kind = tkString)) then
  begin
    Next;
    if CurTok.Kind = tkString then Next;   { `deprecated 'message'` }
    Eat(tkSemicolon);
    Result := True;
  end;
end;

function IsConstParamTok: Boolean;
{ `const` or FPC's `constref` opening a parameter group. constref is a plain
  identifier, not a keyword. FPC defines it as const that is ALWAYS passed by
  reference; pxx already passes const records/variants by reference (a TGUID is a
  record), and for a scalar the distinction is unobservable to the callee, so it
  maps onto const. testutils' IInterface.QueryInterface(constref IID: TGUID; ...)
  is what needs it. }
begin
  Result := (CurTok.Kind = tkConst) or
            ((CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'constref'));
end;

function TrailingCommaAt(i: Integer): Boolean;
{ Is the comma at token i a TRAILING one — nothing but the closing paren after
  it? Python allows `f(a, )` and so does this parser, but the argument COUNTER
  scored it as a second argument, which is the same silent miscount a
  brace-nested comma caused: no overload has the inflated arity, the candidate
  set comes back empty, and the caller falls back to the first-declared
  overload. `d.update(m, )` segfaulted for exactly that reason, with no dict
  literal in sight. Newlines are skipped so a comma trailing the last argument
  of a multi-line call reads the same as a single-line one. }
var k: Integer;
begin
  k := i + 1;
  while (k < TokCount) and (Tokens[k].Kind in [tkNewline, tkIndent, tkDedent]) do
    Inc(k);
  Result := (k < TokCount) and (Tokens[k].Kind = tkRParen);
end;

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
    { tkBegin/tkEnd count as a nesting level too. In Pascal they are the
      begin/end KEYWORDS — an opening brace is a comment there, so it never
      reaches the token stream — and only an anonymous-method argument brings
      them here, where nesting is what you want anyway. In NIL PYTHON they are
      the BRACES, and leaving them out meant every comma inside a dict or set
      literal counted as an ARGUMENT separator: a two-entry dict literal passed
      to d.update(...) was read as a 2-argument call, no update overload has
      that arity, so the arity-viable candidate set came back EMPTY and the
      caller fell back to the first-declared overload — update(TPyList) — which
      read a TPyDict as a list and segfaulted. A one-entry literal has no comma
      and was therefore always fine, which is what made this look like a
      dict-literal bug rather than a counting one.
      bug-n-inline-multi-entry-dict-literal-arg-loses-its-values }
    if Tokens[i].Kind in [tkLParen, tkLBrack, tkBegin] then Inc(d)
    else if Tokens[i].Kind in [tkRParen, tkRBrack, tkEnd] then
    begin
      Dec(d);
      if d = 0 then Exit;
    end
    else if (Tokens[i].Kind = tkSemicolon) or (Tokens[i].Kind = tkEOF) then Exit
    else if (Tokens[i].Kind = tkComma) and (d = 1) and
            not TrailingCommaAt(i) then Inc(Result);
    Inc(i);
  end;
end;

function OverloadArgRank(pTk, aTk: TTypeKind): Integer;
{ How good a fit an argument of type aTk is for a parameter of type pTk, lower is
  better: 0 exact, 1 preferred conversion, 2 merely compatible, 3 impossible.

  The ranking exists because TypesCompatible alone is too coarse to CHOOSE with: a
  Char argument is compatible with Integer (both ordinal) AND with string, so a
  first-match scan handed `P('x')` to `P(Integer)` and passed 120. FPC prefers the
  string conversion for a character, and prefers numeric widening between numbers,
  so those two get rank 1 and everything else compatible sinks to 2. }
begin
  if pTk = aTk then begin Result := 0; Exit; end;

  { char -> string, and string flavour -> string flavour (a frozen tyString
    literal onto a managed AnsiString param) }
  if ((pTk = tyString) or (pTk = tyAnsiString)) and
     ((aTk = tyString) or (aTk = tyAnsiString) or (aTk = tyChar)) then
  begin Result := 1; Exit; end;

  { numeric widening between non-character ordinals }
  if TypeIsOrdinal(pTk) and TypeIsOrdinal(aTk) and
     (pTk <> tyChar) and (aTk <> tyChar) then
  begin Result := 1; Exit; end;

  if TypesCompatible(pTk, aTk) then begin Result := 2; Exit; end;
  Result := 3;
end;

function HexDigitVal(c: Char): Integer;
begin
  if (c >= '0') and (c <= '9') then Result := Ord(c) - Ord('0')
  else if (c >= 'a') and (c <= 'f') then Result := Ord(c) - Ord('a') + 10
  else if (c >= 'A') and (c <= 'F') then Result := Ord(c) - Ord('A') + 10
  else Result := -1;
end;

procedure ParseGuidLiteral(ci: Integer; const s: AnsiString);
{ Record an interface's `['{XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}']` as the 16 raw
  bytes in TGuid MEMORY order — D1 is a little-endian u32, D2/D3 little-endian u16,
  D4 the remaining 8 bytes in written order. That is what a runtime `TGuid` looks
  like in memory, so GetInterface can compare the compile-time blob against the
  caller's TGuid byte for byte with no marshalling.

  A malformed literal is ignored rather than an error: the GUID is optional, and a
  source that carries a broken one still compiled before this. }
var
  hex: AnsiString;
  i, hi, lo, n: Integer;
  b: array[0..15] of Byte;
begin
  hex := '';
  for i := 1 to Length(s) do
  begin
    if HexDigitVal(s[i]) >= 0 then hex := hex + s[i]
    else if (s[i] <> '{') and (s[i] <> '}') and (s[i] <> '-') then Exit;  { junk }
  end;
  if Length(hex) <> 32 then Exit;

  { pack the 32 hex digits into 16 big-endian bytes first }
  for i := 0 to 15 do
  begin
    hi := HexDigitVal(hex[i * 2 + 1]);
    lo := HexDigitVal(hex[i * 2 + 2]);
    if (hi < 0) or (lo < 0) then Exit;
    b[i] := Byte(hi * 16 + lo);
  end;

  n := ci * 16;
  { D1: u32, byte-swapped to little-endian }
  UClsGuidB[n + 0] := b[3]; UClsGuidB[n + 1] := b[2];
  UClsGuidB[n + 2] := b[1]; UClsGuidB[n + 3] := b[0];
  { D2: u16 }
  UClsGuidB[n + 4] := b[5]; UClsGuidB[n + 5] := b[4];
  { D3: u16 }
  UClsGuidB[n + 6] := b[7]; UClsGuidB[n + 7] := b[6];
  { D4: 8 bytes, written order }
  for i := 0 to 7 do UClsGuidB[n + 8 + i] := b[8 + i];
  UClsHasGuid[ci] := True;
end;

{ NilPy spells `TFoo.ClassName` as `Foo.__name__` — the CLASS-side counterpart of
  `type(x).__name__`, which already answers through the same RTTI name. Mapped to
  the Pascal op rather than given a second lowering, so the two spellings cannot
  drift apart. bug-n-pyexception-leaks-through-name-and-repr }
function MapNilPyClassRefOpName(const nm: AnsiString): AnsiString;
begin
  if isNilPy and CaseEqual(nm, '__name__') then
    MapNilPyClassRefOpName := 'ClassName'
  else
    MapNilPyClassRefOpName := nm;
end;

{ The class-reference operations FPC puts on TObject in System, so they are reached
  with no `uses`:

    x.ClassName       the class's name
    x.ClassType       the class itself, as a TClass    (instances only)
    x.InheritsFrom(C) is x's class C, or a descendant of it

  Each is a walk over the RTTI blob, and each takes both shapes x can have:

    an INSTANCE       -> blob is __pxxRttiOf(x)   ([[x+0] - 8])
    a CLASS REFERENCE -> blob IS the value        (a TClass value is the blob ptr)

  blobNode is that blob. Returns -1 when the builtin helpers are not linked, so the
  caller can fall through to its normal handling. }
function GenMakeClassRefOp(blobNode: Integer; const opRaw: AnsiString; var outTk: TTypeKind): Integer;
var pi, callNode, argSeq, argSeq2: Integer; op: AnsiString;
begin
  Result := -1;
  { NilPy's `__name__` is ClassName — mapped here as well as in the predicate,
    so the two always agree about which names this handles. }
  op := MapNilPyClassRefOpName(opRaw);

  if CaseEqual(op, 'ClassType') then
  begin
    { ClassType IS the blob pointer -- no call at all, just a retype. }
    outTk := tyPointer;
    if CurTok.Kind = tkLParen then
    begin
      Next;
      Expect(tkRParen, ')');
    end;
    Result := blobNode;
    Exit;
  end;

  if CaseEqual(op, 'ClassName') then
  begin
    pi := FindProc('__pxxClassName');
    if pi < 0 then Exit;
    outTk := tyAnsiString;
  end
  else if CaseEqual(op, 'InheritsFrom') then
  begin
    pi := FindProc('__pxxInheritsFrom');
    if pi < 0 then Exit;
    outTk := tyBoolean;
  end
  else
    Exit;

  callNode := AllocNode(AN_CALL);
  ASTIVal[callNode] := pi;
  ASTTk[callNode] := Ord(Procs[pi].RetType);
  argSeq := AllocNode(AN_ARG);
  ASTLeft[argSeq] := blobNode;
  ASTLeft[callNode] := argSeq;

  if CaseEqual(op, 'InheritsFrom') then
  begin
    { the class to test against -- itself a class reference, i.e. a blob pointer }
    Expect(tkLParen, '(');
    ParseExpr;
    argSeq2 := AllocNode(AN_ARG);
    ASTLeft[argSeq2] := CurASTNode;
    ASTRight[argSeq] := argSeq2;
    Expect(tkRParen, ')');
  end
  else if CurTok.Kind = tkLParen then
  begin
    { FPC allows both `x.ClassName` and `x.ClassName()`. }
    Next;
    Expect(tkRParen, ')');
  end;

  Result := callNode;
end;

{ True for the three names GenMakeClassRefOp handles. }
function IsClassRefOpName(const nm: AnsiString): Boolean;
var m: AnsiString;
begin
  m := MapNilPyClassRefOpName(nm);
  IsClassRefOpName := CaseEqual(m, 'ClassName') or CaseEqual(m, 'ClassType') or
                      CaseEqual(m, 'InheritsFrom');
end;

{ The class RTTI blob of an INSTANCE expression. An IR node, not a builtin call:
  `obj.ClassMethod(...)` has to pass the instance's RUNTIME class as Self, and NOTHING
  in the token stream predicts such a call, so the token pre-scan cannot know to pull
  the builtin unit for it. It is two loads either way. }
function GenMakeRttiOfCall(objNode: Integer): Integer;
var n: Integer;
begin
  n := AllocNode(AN_RTTIOF);
  ASTLeft[n] := objNode;
  ASTTk[n] := Ord(tyPointer);
  Result := n;
end;

{ Chain further class-reference operations onto one that just produced a TClass.

  `E.ClassType.InheritsFrom(AExceptionClass)` (fpcunit) is the case: ClassType yields
  a class reference, and the next selector applies to THAT, not to E. Only a
  class-reference result (tyPointer, i.e. ClassType) can carry a tail -- ClassName
  gives a string and InheritsFrom a Boolean, and neither takes these selectors. }
function ParseClassRefOpTail(node: Integer; var outTk: TTypeKind): Integer;
var nm: AnsiString; nxt: Integer;
begin
  Result := node;
  while (outTk = tyPointer) and (CurTok.Kind = tkDot) and
        (Tokens[TokPos].Kind = tkIdent) and IsClassRefOpName(GetTokenStr(TokPos)) do
  begin
    Next;                 { consume '.' -- CurTok is now the operation name }
    nm := CurTok.SVal;
    Next;                 { consume the operation name }
    nxt := GenMakeClassRefOp(Result, nm, outTk);
    if nxt < 0 then Exit;
    Result := nxt;
  end;
end;

{ Build a call to a STATIC (class) method, given the node that supplies its Self --
  the metaclass. CurTok is on the token AFTER the method name; an argument list, if
  present, is parsed here. Mirrors the qualified `TA.M(...)` block, which is the same
  call with the class named explicitly.

  Used for the BARE, unqualified form inside a method body, where the receiver is
  implicit:
    in a CLASS method    Self already IS the metaclass -> pass it straight through,
                         so `TMyTest.Suite` reaches TAssert.Suite with Self = TMyTest
                         and the class propagates down the chain;
    in an INSTANCE method the runtime class of Self -> __pxxRttiOf(Self). }
function GenMakeStaticMethodCall(mpi: Integer; selfNode: Integer): Integer;
var callNode, lastArg, argSeq, exprNode, argIdx, ai: Integer;
    mkw, kwHead, kwCount: Integer;
begin
  callNode := AllocNode(AN_CALL);
  ASTIVal[callNode] := mpi;
  ASTTk[callNode] := Ord(Procs[mpi].RetType);
  { A VIRTUAL class method dispatches on the RUNTIME class, exactly as an instance one does:
    fpjson's `class function JSONType: TJSONType; virtual;` is read through a TJSONData
    reference and must answer for the object actually there. Self is the metaclass, so the
    VMT comes from the blob rather than from [Self+0] -- see AN_CLASS_VIRTUAL_CALL. }
  if GenVirtSlot >= 0 then
  begin
    ASTKind[callNode] := AN_CLASS_VIRTUAL_CALL;
    ASTSOffset[callNode] := GenVirtSlot;
  end;
  GenVirtSlot := -1;   { consumed: never leaks into the next call built }

  argSeq := AllocNode(AN_ARG);
  ASTLeft[argSeq] := selfNode;
  ASTLeft[callNode] := argSeq;
  lastArg := argSeq;

  if CurTok.Kind = tkLParen then
  begin
    Next;
    ai := 1;                    { param 0 is Self }
    { `obj.F()` -- EMPTY parens on a method whose parameters ALL have defaults. FPC accepts
      it (it is the ordinary way to call `FormatJSON()` in fcl-json's own test suite); the
      loop below would hand the `)` to ParseExpr and report "expected expression". A method
      with no parameters at all already worked, because the loop simply never ran. }
    if CurTok.Kind = tkRParen then
    begin
      if (Procs[mpi].ParamCount > 1) and CanFillDefaultsFrom(mpi, 1) then
        FillDefaultArgs(mpi, 1, callNode, lastArg);
      ai := Procs[mpi].ParamCount;    { nothing to parse; Expect(tkRParen) below consumes it }
    end;
    while ai <= Procs[mpi].ParamCount - 1 do
    begin
      { An `array of const` argument written as a LITERAL -- `DoError(msg, ['Nil', x])`
        (fpjson) -- and an open-array scalar literal. Without these the '[' is parsed as a
        SET and dies on "set item must be one character". The plain-routine call path has
        always checked for them; the method paths did not. }
      { `Base.st(1, b=7)` — a KEYWORD argument to a STATIC method reached
        through the class name. This loop is index-driven and interleaves
        FillDefaultArgs as it goes, which is why the keyword pair
        PyKwArgIndex/PyBindKwArgs was not simply bolted on when the INSTANCE
        shape got it: the two mechanisms would both claim the holes. So a
        keyword switches this call to the chain-driven discipline — tag the arg
        with its parameter index, stop at `)`, and let PyBindKwArgs do the
        reordering and hole-filling it already does for five other call sites.
        The no-keyword path below is untouched, and PyKwArgIndex returns 0
        unless isNilPy, so every Pascal call through here is byte-identical.
        bug-nilpy-a-static-method-called-on-the-class-takes-no-keyword-arguments }
      mkw := PyKwArgIndex(mpi, 1);
      if (CurTok.Kind = tkLBrack) and ParamIsVarRecArray(mpi, ai) then
        exprNode := ParseVarRecLiteralAST
      else if (CurTok.Kind = tkLBrack) and ParamIsOpenArrayScalar(mpi, ai) then
        exprNode := ParseArrayCtorAST(Procs[mpi].Params[ai].TypeKind,
          ProcParamElemRowLen[mpi * MAX_PROC_PARAMS + ai], ProcParamElemRowLo[mpi * MAX_PROC_PARAMS + ai])
      else if Procs[mpi].Params[ai].IsRef or Procs[mpi].Params[ai].IsArray then
      begin
        if ByRefArgStartsExpression(ParamIsConstVariant(mpi, ai)) then
        begin
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
      SetLitCheckArg(exprNode, mpi, ai);
      argSeq := AllocNode(AN_ARG);
      ASTLeft[argSeq] := exprNode;
      ASTIVal[argSeq] := mkw;
      ASTRight[lastArg] := argSeq;
      lastArg := argSeq;
      if mkw <> 0 then
      begin
        if CurTok.Kind = tkRParen then Break;
        Expect(tkComma, ',');
        Inc(ai);
        Continue;
      end;
      if (ai < Procs[mpi].ParamCount - 1) and CanFillDefaultsFrom(mpi, ai + 1) then
      begin
        FillDefaultArgs(mpi, ai + 1, callNode, lastArg);
        ai := Procs[mpi].ParamCount - 1;
      end
      else if ai < Procs[mpi].ParamCount - 1 then Expect(tkComma, ',');
      Inc(ai);
    end;
    Expect(tkRParen, ')');
    { The chain starts at the SELF argument, exactly as the instance path hands
      it over — PyKwArgIndex returns the ABSOLUTE parameter index, and self is
      parameter 0, so the two agree without an offset. A no-keyword chain is
      returned untouched (PyBindKwArgs exits on its own first test). }
    kwHead := ASTLeft[callNode];
    kwCount := 0;
    PyBindKwArgs(mpi, kwHead, lastArg, kwCount);
    ASTLeft[callNode] := kwHead;
  end
  else if CanFillDefaultsFrom(mpi, 1) then
    FillDefaultArgs(mpi, 1, callNode, lastArg);

  Result := callNode;
end;

{ The metaclass to pass as Self for a BARE static-method call in the CURRENT body.
  -1 when there is no enclosing method. }
function GenMakeImplicitMetaclass: Integer;
var selfIdx, selfNode: Integer;
begin
  Result := -1;
  if (CurProc < 0) or (Procs[CurProc].ParamCount <= 0) then Exit;
  selfIdx := Procs[CurProc].Params[0].SymIdx;
  if selfIdx < 0 then Exit;
  selfNode := AllocNode(AN_IDENT);
  ASTIVal[selfNode] := selfIdx;
  ASTTk[selfNode] := Ord(Syms[selfIdx].TypeKind);
  if CurSelfClass >= REC_UCLASS_BASE then
    { an INSTANCE method: Self is the object -- take its RUNTIME class }
    Result := GenMakeRttiOfCall(selfNode)
  else
    { a CLASS method: Self already IS the metaclass }
    Result := selfNode;
end;

{ Is this bare identifier a value of CLASS-REFERENCE type (a TClass variable, param,
  or a field of the enclosing class)? A class reference is tyPointer whose element is
  tyClass -- the shape TClass, a metaclass Self, and ClassType all carry. Used to spot
  `E is <classref>`, where the class is a runtime value rather than a name. }
function IdentIsClassRefValue(const nm: AnsiString): Boolean;
var si, fi: Integer;
begin
  IdentIsClassRefValue := False;
  si := FindSym(nm);
  if si >= 0 then
  begin
    if (Syms[si].TypeKind = tyPointer) and (Syms[si].PtrElemTk = tyClass) then
    begin
      IdentIsClassRefValue := True;
      Exit;
    end;
    if (Syms[si].TypeKind = tyClass) and (Syms[si].RecName = REC_NONE) then
    begin
      IdentIsClassRefValue := True;
      Exit;
    end;
    Exit;   { a symbol of some other type shadows -- `is` is not an operator here }
  end;
  if (CurProc >= 0) and (CurMethClass >= REC_UCLASS_BASE) then
  begin
    fi := FindUField(CurMethClass - REC_UCLASS_BASE, nm);
    if fi >= 0 then
    begin
      { a class-reference FIELD carries the same "class with no concrete class id"
        shape, whether it is recorded as a pointer-to-class or a bare class }
      if (UFldTk[fi] = Ord(tyPointer)) and (UFldPtrElemTk[fi] = Ord(tyClass)) then
        IdentIsClassRefValue := True
      else if (UFldTk[fi] = Ord(tyClass)) and (UFldRec_[fi] = REC_NONE) then
        IdentIsClassRefValue := True;
    end;
  end;
end;

function GenMakeGetInterfaceCall(objNode: Integer): Integer;
{ Rewrite `<obj>.GetInterface(IID, Obj)` (and the bare, implicit-Self form) to
  __pxxGetInterface(<obj>, @IID, @Obj). CurTok must be on the '('.

  Both arguments go by ADDRESS. An AN_ADDR over a by-ref parameter auto-derefs in
  IRLowerAddress and yields the CALLER's address, so this is correct whether the
  argument is a plain variable (`var o: IFoo; obj.GetInterface(g, o)`) or an untyped
  `out` parameter being forwarded — which is exactly testutils' shape:

      function TNoRefCountObject.QueryInterface(constref IID: TGUID; out Obj): HResult;
      begin
        if GetInterface(IID, Obj) then ...

  Returns -1 when the builtin helper is not linked, so the caller can fall through
  to its normal "no such method" handling. }
var
  pi, callNode, a1, a2, addr1, addr2: Integer;
begin
  Result := -1;
  pi := FindProc('__pxxGetInterface');
  if pi < 0 then Exit;

  Expect(tkLParen, '(');

  callNode := AllocNode(AN_CALL);
  ASTIVal[callNode] := pi;
  ASTTk[callNode] := Ord(Procs[pi].RetType);

  a1 := AllocNode(AN_ARG);            { arg 0 = the instance }
  ASTLeft[a1] := objNode;
  ASTLeft[callNode] := a1;

  ParseExpr;                          { IID }
  addr1 := AllocNode(AN_ADDR);
  ASTLeft[addr1] := CurASTNode;
  ASTTk[addr1] := Ord(tyPointer);
  a2 := AllocNode(AN_ARG);
  ASTLeft[a2] := addr1;
  ASTRight[a1] := a2;

  Expect(tkComma, ',');

  ParseExpr;                          { Obj }
  addr2 := AllocNode(AN_ADDR);
  ASTLeft[addr2] := CurASTNode;
  ASTTk[addr2] := Ord(tyPointer);
  a1 := AllocNode(AN_ARG);
  ASTLeft[a1] := addr2;
  ASTRight[a2] := a1;

  Expect(tkRParen, ')');
  Result := callNode;
end;

procedure EmitMainBodyIntfTempRelease;
{ Release the COM-interface `as`-cast temps materialised in the MAIN program body
  (skGlobal, AddRef'd on creation by IRMaterializeIntfCast) at program exit. FPC
  keeps such an expression temp alive to end-of-main, so its object is destroyed
  AFTER the last body statement — not early when the source `iwX := nil` drops the
  global var's reference. pxx modelled the temp as a plain skGlobal alias (no
  retain, no release), so the object died at `iwX := nil` and the differential
  oracle saw a wrong exit checksum (bug-pascal-mainbody-ascast-temp-finalization
  -timing). Emitted after the main body, before EmitExit; PXXIntfRelease is
  nil-safe, so an as-cast whose branch never ran (nil BSS slot) is harmless. }
var i, pi, seqNode, lastSeq, callNode, aAddr, arg0, arg1, identNode, ci, sym: Integer;
begin
  if MainBodyIntfTempCount = 0 then Exit;
  pi := FindProc('PXXIntfRelease');
  if pi < 0 then Exit;
  seqNode := AllocNode(AN_SEQ);
  lastSeq := seqNode;
  for i := 0 to MainBodyIntfTempCount - 1 do
  begin
    sym := MainBodyIntfTempSym[i];
    ci := Syms[sym].RecName - REC_UCLASS_BASE;
    identNode := AllocNode(AN_IDENT);
    ASTIVal[identNode] := sym;
    ASTTk[identNode] := Ord(Syms[sym].TypeKind);
    aAddr := AllocNode(AN_ADDR);            { @slot }
    ASTLeft[aAddr] := identNode;
    ASTTk[aAddr] := Ord(tyPointer);
    arg0 := AllocNode(AN_ARG);
    ASTLeft[arg0] := aAddr;
    arg1 := AllocNode(AN_ARG);
    ASTLeft[arg1] := AllocNode(AN_INT_LIT);
    ASTIVal[ASTLeft[arg1]] := ci;
    ASTTk[ASTLeft[arg1]] := Ord(tyNativeInt);
    ASTRight[arg0] := arg1;
    callNode := AllocNode(AN_CALL);
    ASTIVal[callNode] := pi;
    ASTTk[callNode] := Ord(Procs[pi].RetType);
    ASTLeft[callNode] := arg0;
    if ASTLeft[lastSeq] = -1 then
      ASTLeft[lastSeq] := callNode
    else
    begin
      ASTRight[lastSeq] := AllocNode(AN_SEQ);
      lastSeq := ASTRight[lastSeq];
      ASTLeft[lastSeq] := callNode;
    end;
  end;
  CompileAST(seqNode);
end;

function RegisterLineEndingConst: Integer;
{ Intern System.LineEnding as an ordinary untyped string constant and return its index,
  so every later use is just a frozen string literal. Called lazily, only once nothing
  else has claimed the name — see the callers. Posix; Windows is not a target. }
begin
  Result := FindStrConst('LineEnding');
  if Result >= 0 then Exit;
  if StrConstCount >= MAX_TYPEALIAS then Error('too many string constants');
  if TokCharLen >= STRING_CAP then Error('string constant buffer overflow');
  StrConstName[StrConstCount] := 'LineEnding';
  StrConstOwner[StrConstCount] := -1;   { System.LineEnding is global }
  StrConstSOff[StrConstCount] := TokCharLen;
  StrConstSLen[StrConstCount] := 1;
  TokChars[TokCharLen] := #10;
  Inc(TokCharLen);
  Result := StrConstCount;
  StrConstUnitIdx[StrConstCount] := CurrentUnitIdx; Inc(StrConstCount);
end;

function FindUMethOverloadAhead(ci: Integer; const name: AnsiString; nExplicitArgs: Integer): Integer;
{ TYPE-aware method overload selection.

  FindUMethArity picks the first name match whose ARITY fits, so same-arity
  overloads (`AssertEquals(string)` vs `AssertEquals(Integer)` — fpcunit is built
  out of these) always ran the FIRST body no matter what was passed: silent wrong
  code, no diagnostic.

  Candidates = name matches up the parent chain whose arity accepts the call. With
  0 or 1 candidate this IS FindUMethArity, so the single-method paths are
  untouched. With more than one, the call's argument expressions are parsed
  SPECULATIVELY to learn their types, the token stream is rewound to exactly where
  it was, and the candidate whose parameters match wins — exact types first, then
  TypesCompatible (which is what maps a tyString literal onto an `AnsiString`
  param). See bug-pascal-method-overload-ignores-arg-types. }
const MAX_OVL_CAND = 32;
var
  cand: array[0..MAX_OVL_CAND-1] of Integer;
  argTk: array[0..MAX_PROC_PARAMS-1] of TTypeKind;
  argRec: array[0..MAX_PROC_PARAMS-1] of Integer;
  nCand, nArgs, i, j, c, pi, base, want, curr, mbase, cnt, lp, savedCurIdx, best: Integer;
  score, bestScore, rank, pRec, aRec, upDist, upCurr: Integer;
  ok: Boolean;
  lo, name2: AnsiString;
begin
  Result := -1;
  name2 := name;
  lo := ULower(name2);

  { NilPy `d.update(a=1, b=2)` / `d.update(**e)`: the keywords are dict KEYS, so
    the argument list is ONE TPyDict however many of them there are. Answered
    before the arity filter (which counts them) and before the speculative probe
    (which cannot parse a `**` at all). PyDictKwOverloadAhead carries the why. }
  if isNilPy then
  begin
    i := PyDictKwOverloadAhead(ci, name);
    if i >= 0 then begin Result := i; Exit; end;
  end;

  { 1. collect the arity-viable candidates }
  nCand := 0;
  curr := ci;
  while curr >= 0 do
  begin
    mbase := UClsMBase[curr];
    cnt   := UClsMCount[curr];
    i := 0;
    while i < cnt do
    begin
      if UMemberNameMatch(UMthNOff[mbase + i], UMthNLen[mbase + i], curr, name, lo) then
      begin
        { EVERY method carries a Self at index 0 now -- a class method's Self is the
          metaclass. So the implicit arg is always there, static or not. }
        want := nExplicitArgs + 1;
        if ProcArityMatches(UMthProc_[mbase + i], want) and (nCand < MAX_OVL_CAND) then
        begin
          cand[nCand] := mbase + i;
          Inc(nCand);
        end;
      end;
      Inc(i);
    end;
    curr := UClsParent[curr];
  end;

  if nCand <= 1 then
  begin
    Result := FindUMethArity(ci, name, nExplicitArgs);
    Exit;
  end;

  { 2. probe the argument types, then rewind. CurTok is Tokens[TokPos-1], so
       restoring TokPos to that index and calling Next reproduces it exactly. }
  savedCurIdx := TokPos - 1;
  if (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
    lp := TokPos
  else if CurTok.Kind = tkLParen then
    lp := TokPos - 1
  else
    lp := -1;

  nArgs := 0;
  if (lp >= 0) and (nExplicitArgs > 0) then
  begin
    TokPos := lp + 1;
    Next;
    while (CurTok.Kind <> tkRParen) and (CurTok.Kind <> tkEOF) and
          (nArgs < MAX_PROC_PARAMS) do
    begin
      { NilPy `name=expr`: step over the keyword before probing, or the name is
        parsed as an expression and reported as an undefined variable — an
        OVERLOADED façade method could not be called with keyword arguments at
        all (`canvas.create_window((0,0), window=w)`). The probe only needs the
        argument's TYPE; which parameter it binds to is settled later by
        PyKwArgIndex. }
      if isNilPy and (CurTok.Kind = tkIdent) and
         (TokPos < TokCount) and (Tokens[TokPos].Kind = tkAssign) then
      begin
        Next;   { the name }
        Next;   { the '=' }
      end;
      { ParseArgExpr, not ParseExpr: under NilPy an argument obeys PYTHON
        precedence and grammar, so a tuple argument `(0, 0)` is one expression
        here. Probed with the Pascal chain it stopped at the comma, typed the
        argument Integer and counted the tuple as two — which then ranked a
        `(x, y: Integer)` overload above the tuple one. }
      ParseArgExpr;
      argTk[nArgs] := IntToTypeKind(ASTTk[CurASTNode]);
      if argTk[nArgs] = tyClass then
        argRec[nArgs] := ResolveNodeRec(CurASTNode)
      else
        argRec[nArgs] := REC_NONE;
      Inc(nArgs);
      if CurTok.Kind = tkComma then Next else Break;
    end;
  end;
  TokPos := savedCurIdx;
  Next;

  if nArgs <> nExplicitArgs then
  begin
    { probe disagreed with the token-level count (an unsupported arg shape) —
      keep the old behaviour rather than guess }
    Result := FindUMethArity(ci, name, nExplicitArgs);
    Exit;
  end;

  { 3. pick the candidate with the lowest total argument rank; ties keep the
       first-declared one (FPC's own tie-break). A candidate with any impossible
       argument is out. }
  best := -1;
  bestScore := 0;
  for c := 0 to nCand - 1 do
  begin
    pi := UMthProc_[cand[c]];
    base := 1;   { params[0] is always Self (metaclass for a class method) }
    ok := True;
    score := 0;
    for j := 0 to nArgs - 1 do
    begin
      rank := OverloadArgRank(Procs[pi].Params[base + j].TypeKind, argTk[j]);
      { CLASS-IDENTITY-aware refinement: two tyClass params tie at rank 0, so
        `Add(TJSONData)` vs `Add(TJSONObject)` picked whichever was declared
        first regardless of the argument's class. FPC picks the EXACT class,
        accepts an up-cast to an ancestor as merely compatible, and rejects an
        unrelated class. Both recs must be known — REC_NONE (nil, untagged)
        keeps the kind-level rank. (bug-pascal-overload-impl-decl-signature-match) }
      if (rank < 3) and (Procs[pi].Params[base + j].TypeKind = tyClass) and
         (argTk[j] = tyClass) and ((base + j) < MAX_PROC_PARAMS) then
      begin
        pRec := ProcParamRecId[pi * MAX_PROC_PARAMS + base + j];
        aRec := argRec[j];
        if (pRec >= REC_UCLASS_BASE) and (aRec >= REC_UCLASS_BASE) and (pRec <> aRec) then
        begin
          upDist := 0;
          upCurr := aRec - REC_UCLASS_BASE;
          while (upCurr >= 0) and (upCurr <> pRec - REC_UCLASS_BASE) do
          begin
            Inc(upDist);
            upCurr := UClsParent[upCurr];
          end;
          if upCurr < 0 then rank := 3        { unrelated class: impossible }
          else rank := 2;                     { ancestor up-cast: exact wins }
        end;
      end;
      if rank >= 3 then ok := False;
      score := score + rank;
    end;
    if ok and ((best < 0) or (score < bestScore)) then
    begin
      best := cand[c];
      bestScore := score;
    end;
  end;

  if best < 0 then best := FindUMethArity(ci, name, nExplicitArgs);
  Result := best;
end;

{ Does ANY constructor of class ci take an `array of const` / open array at explicit argument
  position argIdx (0-based, Self excluded)? The `TFoo.Create(args)` path parses its arguments
  BEFORE it picks the overload -- it has to, since it ranks the overloads by argument type --
  so it cannot ask the chosen signature whether a '[' is an array-of-const literal or a set.
  Asking whether ANY candidate wants one there is enough: `[` in that position has no other
  meaning for a constructor argument.

  Without this, `TJSONArray.Create([0, 'string', ...])` (fcl-json) parsed the literal as a SET
  and died on "set item must be one character" -- or, with an overloaded ctor, quietly picked
  the parameterless one and passed garbage. }
function ClassCtorWantsVarRecAt(ci, argIdx: Integer): Boolean;
var mi, mpi, base, cnt, k: Integer;
begin
  Result := False;
  if (ci < 0) or (ci >= UClsCount) then Exit;
  base := UClsMBase[ci];
  cnt := UClsMCount[ci];
  for k := 0 to cnt - 1 do
  begin
    mi := base + k;
    if not UMthIsCtor[mi] then continue;
    mpi := UMthProc_[mi];
    if mpi < 0 then continue;
    if (argIdx + 1) < Procs[mpi].ParamCount then
      if Procs[mpi].Params[argIdx + 1].IsArray then
      begin
        Result := True;
        Exit;
      end;
  end;
end;

function FindUCtorOverloadArgs(ci: Integer; argsHead: Integer): Integer;
{ Constructor overload selection from the ALREADY-PARSED argument list.

  Unlike a method call, a ctor's args are parsed BEFORE the ctor is chosen, so the
  argument types are sitting on the AST and no token probe is needed. Picking the
  first `Create` by name (the old behaviour) meant an overloaded ctor set always
  resolved to whichever Create was declared first — so `TFoo.Create('x')` against a
  parameterless first Create died with "too many arguments", and a same-arity set
  silently ran the wrong body. Same ranking as FindUMethOverloadAhead. }
const MAX_OVL_CAND = 32;
var
  cand: array[0..MAX_OVL_CAND-1] of Integer;
  argTk: array[0..MAX_PROC_PARAMS-1] of TTypeKind;
  nCand, nArgs, i, j, c, pi, want, curr, mbase, cnt, best: Integer;
  score, bestScore, rank, argSeq: Integer;
  ok: Boolean;
  lo, nm: AnsiString;
begin
  nm := 'create';
  lo := ULower(nm);

  nArgs := 0;
  argSeq := argsHead;
  while (argSeq <> -1) and (nArgs < MAX_PROC_PARAMS) do
  begin
    argTk[nArgs] := IntToTypeKind(ASTTk[ASTLeft[argSeq]]);
    Inc(nArgs);
    argSeq := ASTRight[argSeq];
  end;

  nCand := 0;
  curr := ci;
  while curr >= 0 do
  begin
    mbase := UClsMBase[curr];
    cnt   := UClsMCount[curr];
    i := 0;
    while i < cnt do
    begin
      if UMemberNameMatch(UMthNOff[mbase + i], UMthNLen[mbase + i], curr, nm, lo) then
      begin
        want := nArgs + 1;   { Self at 0 for every method, class methods included }
        if ProcArityMatches(UMthProc_[mbase + i], want) and (nCand < MAX_OVL_CAND) then
        begin
          cand[nCand] := mbase + i;
          Inc(nCand);
        end;
      end;
      Inc(i);
    end;
    { A Python __init__ REPLACES the base's — the type's own is what
      `Sub(arg)` runs, never an inherited constructor that happens to accept the
      same argument better. Ranking by argument TYPE picked the base's whenever
      the subclass's parameter was unannotated (i.e. a variant), so
      `class SettingsEditor(tk.Frame)` constructed a bare Frame and the
      subclass's body never ran. Pascal keeps the inherited-ctor lookup: FPC
      really does let `TSub.Create` resolve to the base's. }
    if isNilPy and (nCand > 0) then Break;
    curr := UClsParent[curr];
  end;

  if nCand = 0 then
  begin
    Result := FindUMeth(ci, 'create');
    Exit;
  end;

  best := -1;
  bestScore := 0;
  for c := 0 to nCand - 1 do
  begin
    pi := UMthProc_[cand[c]];
    ok := True;
    score := 0;
    for j := 0 to nArgs - 1 do
    begin
      rank := OverloadArgRank(Procs[pi].Params[1 + j].TypeKind, argTk[j]);
      if rank >= 3 then ok := False;
      score := score + rank;
    end;
    if ok and ((best < 0) or (score < bestScore)) then
    begin
      best := cand[c];
      bestScore := score;
    end;
  end;

  if best < 0 then best := cand[0];
  Result := best;
end;

function IsVarArgLvalueCast(n: Integer): Boolean;
{ FPC "variable typecast" as a var/out argument: `Cardinal(FTokenLength)` —
  an AN_PTR_CAST over a plain lvalue. The address is the operand's
  (IRLowerAddress peels the cast). Pascal Script's ParseToken call. }
begin
  Result := (n >= 0) and (ASTKind[n] = AN_PTR_CAST) and (ASTLeft[n] >= 0) and
            ((ASTKind[ASTLeft[n]] = AN_IDENT) or (ASTKind[ASTLeft[n]] = AN_FIELD) or
             (ASTKind[ASTLeft[n]] = AN_INDEX) or (ASTKind[ASTLeft[n]] = AN_DEREF));
end;

function PureDesignator(n: Integer): Boolean;
{ A node that can be re-evaluated with no observable effect: a variable, a field
  or element of one, a dereference, or a cast over any of those. Callers that
  CloneAST an operand into several places need this — a call or an operator
  expression would run more than once.

  A cast recurses into its operand rather than being accepted outright: `(f() as
  T)` is a cast, and re-evaluating it re-calls f(). An `as` cast also re-runs its
  runtime type check per copy, which is wasteful but not observable. }
var depth: Integer;
begin
  PureDesignator := False;
  depth := 0;
  while (n >= 0) and (depth < 32) do
  begin
    if (ASTKind[n] = AN_IDENT) or (ASTKind[n] = AN_FIELD) or
       (ASTKind[n] = AN_INDEX) or (ASTKind[n] = AN_DEREF) then
    begin
      PureDesignator := True;
      Exit;
    end;
    if (ASTKind[n] = AN_CLASS_CAST) or (ASTKind[n] = AN_PTR_CAST) or
       (ASTKind[n] = AN_AS_CAST) then
    begin
      n := ASTLeft[n];
      Inc(depth);
    end
    else
      Exit;
  end;
end;

function BuiltinFreeHere(node, recId: Integer; const fieldName: AnsiString;
                        afterNameTok: Integer): Boolean;
{ Is this `<designator>.Free;` — the built-in TObject.Free on a class instance
  with no user-declared Free — reached through a general member-access path?

  ParseStatementAST has recognised `obj.Free;` for a BARE IDENTIFIER for a long
  time, by matching the literal token shape `ident . Free ;`. Anything with a
  selector in front of it — `a[0].Free`, `d[0].Free`, `r.f.Free`, `h.f.Free`,
  `(o as T).Free` — misses that shape, falls through to ordinary member lookup,
  and dies as `"Free": no such member on this record/class`, because Free is
  not a member of any class the frontend knows. `FList[i].Free` is everyday
  Pascal, so that was a real hole
  (bug-p-free-and-destroy-only-work-on-a-simple-variable).

  The conditions, and why each is needed:
    - the base is a user CLASS, not a record (records are not freed);
    - the class declares no `Free` of its own — a user method named Free wins,
      exactly as the bare-identifier case already decides;
    - the token after the name ends a statement, so this is `x.Free;` and not
      a value position or a call with arguments. Same guard the existing case
      uses;
    - the base is a plain DESIGNATOR. GenMakeFreeObjectExpr CloneASTs its
      operand up to three times (nil test, Destroy, FreeMem), so a
      side-effecting base would run three times. An ident/field/index/deref/cast
      chain is a re-read, which is free.

  Destroy is deliberately not included: `Free` is the nil-guarded wrapper, and
  desugaring a direct `.Destroy` to the same thing would change its meaning. }
begin
  BuiltinFreeHere :=
    (node >= 0) and (recId >= REC_UCLASS_BASE) and
    (not UClsIsRecord[recId - REC_UCLASS_BASE]) and
    CaseEqual(fieldName, 'Free') and
    (FindUMeth(recId - REC_UCLASS_BASE, 'Free') < 0) and
    (afterNameTok < TokCount) and
    (Tokens[afterNameTok].Kind in [tkSemicolon, tkEnd, tkElse]) and
    PureDesignator(node);
end;

procedure RequireRecMember(recId: Integer; const fieldName: AnsiString);
{ Guard on the AN_FIELD fallthrough paths: a member name that resolved to
  NOTHING on a user record/class (no field, no method/property/class var —
  those all dispatched earlier) must ERROR. Without this, RecFieldType's
  not-found default (tyInteger at offset 0) let an undefined field COMPILE
  and read garbage (bug-pascal-undefined-field-on-empty-record-compiles).
  Builtin records keep the lax path — their field names are compiler-authored. }
begin
  if (recId >= REC_UCLASS_BASE) and
     (FindUField(recId - REC_UCLASS_BASE, fieldName) < 0) then
    Error('"' + fieldName + '": no such member on this record/class');
end;

function ParamIsConstVariant(pi, slot: Integer): Boolean;
{ True for a `const v: Variant` parameter — by-ref internally (boxed at
  IRLowerCallArg), but NEVER a genuine var-binding target, so an expression may
  bind to it. The by-ref argument VALIDATOR two call sites up already treats it
  that way; ByRefArgStartsExpression below needs the same fact to stop reading
  `obj.method(a + b)` as a bare lvalue.
  bug-a-const-variant-arg-expression-fails-outside-pyexprmode }
begin
  Result := (pi >= 0) and (slot >= 0) and (slot < MAX_PROC_PARAMS) and
            (slot < Procs[pi].ParamCount) and
            (Procs[pi].Params[slot].TypeKind = tyVariant) and
            ProcParamIsConst[pi * MAX_PROC_PARAMS + slot];
end;

function ByRefArgStartsExpression(constVariantParam: Boolean): Boolean;
var bx, bd: Integer;
{ True when the next by-ref/array argument cannot be a bare variable lvalue:
  not an ident at all, or an ident that names no symbol and is followed by
  '(' — a type-cast lvalue like `PChar(s)^` / `Pointer(p)^` passed to a
  var/untyped parameter (bug-cast-deref-as-varparam-arg). Such args go
  through ParseExpr, whose cast/deref path yields an addressable node. }
begin
  if CurTok.Kind <> tkIdent then begin Result := True; Exit; end;
  { NilPy: a `const` parameter is by-ref, so a Python argument that merely
    STARTS with a name — `xs.append(a + b)` — was parsed as a bare lvalue and
    the parser stopped at the operator ("unexpected token" on the second
    operand). An ident followed by anything that continues an EXPRESSION rather
    than an lvalue is therefore an expression. The lvalue continuations are
    '.', '[' and '^'; ',' and ')' end a bare-variable argument.

    Gated on PyExprMode: Pascal's var-parameter binding must keep passing a
    bare variable by reference, and that path is under the self-host gate.
    Literal operands already worked, which is what hid this — only two NAMED
    operands hit it (bug-nilpy-expression-arg-to-a-const-param).

    ...and on constVariantParam, which lifts the same logic into PASCAL source
    for a `const Variant` parameter only. That parameter is by-ref internally
    but is never a genuine var-binding target, so there is no bare-lvalue
    requirement to protect — `pair.append(start + i)` failed in a plain Pascal
    unit (pylib.pas's own body) for exactly this reason. Genuine var/out/array
    by-ref params still require the gate.
    bug-a-const-variant-arg-expression-fails-outside-pyexprmode }
  if PyExprMode or constVariantParam then
  begin
    { Skip the whole lvalue CHAIN — `self._tok_quote_char`, `a.b[i].c` — and
      judge by what FOLLOWS it. One-token lookahead is not enough: uforth's
      operand is a field chain, so the next token is '.' either way. }
    bx := TokPos;
    while bx < TokCount do
    begin
      if (Tokens[bx].Kind = tkDot) and (bx + 1 < TokCount) and
         (Tokens[bx + 1].Kind = tkIdent) then
        bx := bx + 2
      else if Tokens[bx].Kind = tkCaret then
        Inc(bx)
      else if Tokens[bx].Kind = tkLBrack then
      begin
        bd := 0;
        while bx < TokCount do
        begin
          if Tokens[bx].Kind = tkLBrack then Inc(bd)
          else if Tokens[bx].Kind = tkRBrack then
          begin
            Dec(bd);
            if bd = 0 then begin Inc(bx); Break; end;
          end;
          Inc(bx);
        end;
      end
      else Break;
    end;
    if (bx < TokCount) and not (Tokens[bx].Kind in [tkComma, tkRParen]) then
    begin
      Result := True;
      Exit;
    end;
  end;
  Result := (FindSym(CurTok.SVal) < 0) and (TokPos < TokCount) and
            (Tokens[TokPos].Kind = tkLParen);
end;

function OwnFieldBeatsSym(idx: Integer; const nm: AnsiString): Integer;
{ FPC scope order inside a method body: the enclosing class's OWN field beats
  any unit-level name of the same spelling (const, var, typed const); only a
  genuine local or parameter shadows the field. A name that bound to a unit
  symbol is demoted to "unbound" here, which is what lets the implicit-Self
  field paths — they all fire on `idx < 0` — resolve it instead.

  Every bare-name resolution site must call this, or reads and writes disagree:
  an earlier attempt that changed only the assignment path made `s := v` reach
  the field while `s[1]` still read the const, which is worse than a uniform
  error. Same rule the bare class-CONST path already implements.
  bug-unit-const-shadows-a-field. }
begin
  Result := idx;
  if idx < 0 then Exit;
  if Syms[idx].Kind in [skLocal, skParam] then Exit;
  { needs a real Self to hang the field off: an instance/advanced-record method,
    never a class procedure (no Self) or a plain routine. }
  if (CurProc < 0) or (CurSelfClass < REC_UCLASS_BASE) then Exit;
  if Procs[CurProc].ParamCount <= 0 then Exit;
  if FindUField(CurSelfClass - REC_UCLASS_BASE, nm) >= 0 then Result := -1;
end;

function ParseLValueAST(idx: Integer; identTokIdx: Integer): Integer;
var
  augBin: TTokenKind; augRead, augNode: Integer;   { `d[k] += v` }
  qualNameTok: Integer;   { token index of the member name in `TClass.member` }
  augPow: Boolean;   { `d[k] **= v` — `**` has no binary token, see PyAugDunderName }
  viaProp: Boolean;   { fieldName was rewritten from a PROPERTY's backing field — visibility is the property's, skip the field check }
  mblobNode, cpPri, cpMmi, cpMpi: Integer;
  mkw, mslot, mnArgs: Integer;   { NilPy keyword argument: binding+1, target param, rebound count }
  cpIsAssign: Boolean;
  cpName: AnsiString;
  node, indexNode, fieldNode, prevTok, recName, i: Integer;
  baseNode, baseRec, fIdx, aliasIdx: Integer;
  remDepth, ptrBaseTk, ptrBaseRec: Integer;
  isND: Boolean; nIdx: Integer; alreadyResolved: Boolean; mcFin: Boolean;
  tk: TTypeKind;
  fieldName: AnsiString;
  mci, mmi, mpi, mcallNode, mselfArg, mlastArg, margSeq, margIdx, mexprNode, mai, pri, ci: Integer;
  methName: AnsiString;
  isAssign: Boolean;
  selfClassCi, selfIdx, fldIdx, selfNode: Integer;
  cvIdx: Integer;
  w, withNode, recId: Integer;
  propFOff, propFLen: Integer;
  withResolved: Boolean;
  fldSigPi, callIndNode, argsHead2, lastArg2, argSeq2, baseRecFld: Integer;
  isMethodPtr: Boolean;
  autoDeref, peRec: Integer;
  ccReg, ccNode: Integer; ccKey: AnsiString; ccTk: TTypeKind;   { qualified TClass.Const }
  keyNode: Integer;   { __getitem__/__setitem__ subscript key }
  pyInitCall: Boolean;   { NilPy `Base.__init__(self, ...)` — run the ctor BODY on self, never construct }
begin
  { NilPy runs its own copy of this routine (pyparser.inc). The dispatch is here
    rather than at the ~50 call sites so that every caller stays untouched. }
  if PyExprMode then
  begin
    Result := PyParseLValueAST(idx, identTokIdx);
    Exit;
  end;
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

  { TYPE-HELPER dispatch: a '.' member on a plain (non-class/record) receiver
    whose type has a `record helper for T` in scope, and the member names one
    of the helper's methods — `s.ToLower` with s: AnsiString. Reuses the
    class/record selector machinery with the HELPER as the record id; the
    method's Self (param 0) is the target BY REFERENCE, so passing the
    receiver node as the Self argument takes its address, exactly like an
    advanced-record method. Guarded on the member actually existing, so every
    other '.' path is untouched. }
  if (idx >= 0) and (CurTok.Kind = tkDot) and
     (Syms[idx].RecName < REC_UCLASS_BASE) and (not Syms[idx].IsArray) and
     not (Syms[idx].TypeKind in [tyRecord, tyClass, tyVariant, tyPointer]) and
     (TokPos < TokCount) and (Tokens[TokPos].Kind = tkIdent) then
  begin
    mci := FindHelperForType(Syms[idx].TypeKind, Syms[idx].RecName);
    if (mci >= 0) and (FindUMeth(mci, GetTokenStr(TokPos)) >= 0) then
    begin
      node := AllocNode(AN_IDENT);
      ASTIVal[node] := idx;
      ASTTk[node] := Ord(Syms[idx].TypeKind);
      tk := Syms[idx].TypeKind;
      node := ParseClassRecordSelectors(node, REC_UCLASS_BASE + mci, tk);
      LastExprTk := tk;
      Result := node;
      Exit;
    end;
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
        mmi := FindUMethOverloadAhead(selfClassCi, fieldName, CountCallArgsAhead);
        if mmi >= 0 then
        begin
          EnforceMethVis(mmi, fieldName);
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

      { Bare `GetInterface(IID, Obj)` inside a method — implicit Self, which is how
        testutils' QueryInterface calls it. Only when the class has no method of that
        name, so a user's own GetInterface still wins. }
      if (CurSelfClass >= REC_UCLASS_BASE) and (CurProc >= 0) and
         (Procs[CurProc].ParamCount > 0) and
         CaseEqual(fieldName, 'GetInterface') and (CurTok.Kind = tkLParen) and
         (FindUMeth(CurSelfClass - REC_UCLASS_BASE, 'GetInterface') < 0) and
         (FindProc('__pxxGetInterface') >= 0) then
      begin
        selfIdx := Procs[CurProc].Params[0].SymIdx;
        selfNode := AllocNode(AN_IDENT);
        ASTIVal[selfNode] := selfIdx;
        { Self is tyClass for a class method but tyRecord for an ADVANCED RECORD's method
          — take the symbol's real type rather than assuming a class, or a record Self is
          dereferenced as an object pointer and the field access segfaults. }
        ASTTk[selfNode] := Ord(Syms[selfIdx].TypeKind);
        fldIdx := GenMakeGetInterfaceCall(selfNode);
        if fldIdx >= 0 then
        begin
          tk := tyBoolean;
          recName := REC_NONE;
          Result := fldIdx;
          Exit;
        end;
      end;

      { Bare `class var` name inside a method body (fpcunit's `Inc(AssertCount)`).
        Keyed on CurMethClass, not CurSelfClass, so it also resolves in a `class
        procedure` — that is static, has no Self, and a class var needs none: its
        storage is one shared global. An instance field of the same name wins,
        matching FPC. }
      cvIdx := -1;
      if (fldIdx < 0) and (CurMethClass >= REC_UCLASS_BASE) and (CurProc >= 0) then
        cvIdx := FindClassVar(CurMethClass - REC_UCLASS_BASE, fieldName);
      if cvIdx >= 0 then
      begin
        { Re-enter with the backing global resolved: the idx >= 0 path already
          handles every suffix (index, field, deref) on it. }
        Result := ParseLValueAST(cvIdx, identTokIdx);
        Exit;
      end;

      if fldIdx >= 0 then
    begin
      { --strict-visibility: a bare (implicit-Self) field access. Own-class members
        always pass; the check bites an INHERITED strict-private field reached from
        a descendant method (tclass12b). }
      if StrictVisibility then
        EnforceMemberVis(FieldDeclClass(fldIdx), UFldVis[fldIdx], fieldName);
      selfIdx := Procs[CurProc].Params[0].SymIdx;
      selfNode := AllocNode(AN_IDENT);
      ASTIVal[selfNode] := selfIdx;
      ASTTk[selfNode] := Ord(Syms[selfIdx].TypeKind);   { tyRecord for an advanced-record method }

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
      ASTTk[selfNode] := Ord(Syms[selfIdx].TypeKind);   { tyRecord for an advanced-record method }
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
        if PxxDbgEnabled('a.qual') then WriteLn('PXXDBG a.qual MEMBER field=', fieldName, ' flat=', ci);
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
          if not IsMethodNameTok then Error('expected class method name');
          fieldName := GetTokenStr(TokPos - 1);  { keyword-token names carry no SVal }
          qualNameTok := TokPos - 1;             { for a class var: re-enter on it, suffixes and all }
          Next;

          { `TOuter.TInner.Create` — the middle name is a nested TYPE, i.e. a
            SCOPE, not a member. Without this the lookup asked touter for a
            method called `tinner` and said "class method not found", so a
            nested class could be named in a declaration and never constructed —
            a half-working feature. Loops, because nesting does.
            bug-a-duplicate-class-name-check-is-scope-blind }
          while (CurTok.Kind = tkDot) and (FindNestedType(ci, fieldName) >= 0) do
          begin
            ci := FindNestedType(ci, fieldName);
            Expect(tkDot, '.');
            if not IsMethodNameTok then Error('expected class method name');
            fieldName := GetTokenStr(TokPos - 1);
            qualNameTok := TokPos - 1;
            Next;
          end;

          { Overload-aware: `TAssert.AssertNotNull(x)` and `TAssert.AssertNotNull(msg, x)`
            are different methods. FindUMeth takes the first NAME match and ignored the
            argument count, so the wrong overload was picked (and then complained about
            the arguments it did not get). CountCallArgsAhead reads the call ahead --
            the method name is already consumed here, so it is scanning from the '('. }
          mmi := -1;
          if mmi < 0 then mmi := FindUMethOverloadAhead(ci, fieldName, CountCallArgsAhead);
          if mmi < 0 then mmi := FindUMeth(ci, fieldName);

          { NilPy `Base.__init__(self, n)` — the pre-super() spelling of a
            base-class constructor call, and still ordinary Python. The ctor is
            registered under PyMethodName's 'create', so the raw name above
            finds nothing and this died on 'class method not found: __init__'
            while the neighbouring `Base.show(self)` and `super().__init__(n)`
            both worked (bug-nilpy-unbound-base-class-init-call-is-rejected).

            The flag is the load-bearing half. Resolving the name alone would
            hand a CTOR to the UMthIsCtor branch below, which CONSTRUCTS via
            BuildMetaclassNew — a fresh instance, initialised and then thrown
            away, leaving self's base fields unset with no diagnostic. That is
            a silent wrong value where we currently have a clean error, so the
            flag steers past that branch into the unbound path, which calls the
            ctor BODY with the caller's self as receiver — exactly what
            `super().__init__` already lowers to. }
          pyInitCall := False;

          { A CLASS PROPERTY reached through the class name: `TJSONData.CompressedJSON := False`
            (fcl-json). Its accessors are static class methods, whose Self is the METACLASS --
            so the receiver is the class reference itself, and GenMakeStaticMethodCall does the
            rest. Checked after methods (a method of that name wins) and before class vars. }
          if mmi < 0 then
          begin
            cpPri := FindUProp(ci, fieldName);
            if cpPri >= 0 then
            begin
              cpIsAssign := (CurTok.Kind = tkAssign) or
                            ((TokPos < TokCount) and (Tokens[TokPos].Kind = tkAssign));
              cpName := '';
              if cpIsAssign then
              begin
                if UPropWriteMLen[cpPri] <= 0 then Error('class property is read-only: ' + fieldName);
                for i := 0 to UPropWriteMLen[cpPri] - 1 do
                  AppendChar(cpName, TokChars[UPropWriteMOff[cpPri] + i]);
              end
              else
              begin
                if UPropReadMLen[cpPri] <= 0 then Error('class property is write-only: ' + fieldName);
                for i := 0 to UPropReadMLen[cpPri] - 1 do
                  AppendChar(cpName, TokChars[UPropReadMOff[cpPri] + i]);
              end;
              cpMmi := FindUMeth(ci, cpName);
              if cpMmi < 0 then Error('class property accessor not found: ' + cpName);
              cpMpi := UMthProc_[cpMmi];

              mselfArg := AllocNode(AN_CLASSREF);
              ASTIVal[mselfArg] := ci;
              ASTTk[mselfArg] := Ord(tyPointer);

              if cpIsAssign then
              begin
                Expect(tkAssign, ':=');
                ParseExpr;
                mcallNode := AllocNode(AN_CALL);
                ASTIVal[mcallNode] := cpMpi;
                ASTTk[mcallNode] := Ord(Procs[cpMpi].RetType);
                margSeq := AllocNode(AN_ARG);
                ASTLeft[margSeq] := mselfArg;
                ASTLeft[mcallNode] := margSeq;
                mlastArg := AllocNode(AN_ARG);
                ASTLeft[mlastArg] := CurASTNode;    { the value }
                ASTRight[margSeq] := mlastArg;
                { the index constant, if the property declares one }
                PropIndexConstArg(cpPri, margIdx, mexprNode);
                tk := tyInteger;
                recName := REC_NONE;
                Result := mcallNode;
                Exit;
              end;

              GenVirtSlot := UMthVirSlot[cpMmi];
              mcallNode := GenMakeStaticMethodCall(cpMpi, mselfArg);
              tk := Procs[cpMpi].RetType;
              recName := ProcRetRecId[cpMpi];
              if (tk <> tyClass) and (tk <> tyRecord) then recName := REC_NONE;
              Result := mcallNode;
              Exit;
            end;
          end;

          if mmi < 0 then
          begin
            { class variable: TClass.cnt -> the backing global var (an lvalue, so
              read and write both work). }
            fldIdx := FindClassVar(ci, fieldName);
            if fldIdx >= 0 then
            begin
              { Re-enter with the backing global resolved, exactly like the bare-name
                path above: the idx >= 0 arm of this same function already parses every
                suffix. Building a bare AN_IDENT here instead left a following `[` for
                a caller that had no use for it, so `TC.F[0]` — a class-qualified read
                of a class-var ARRAY — was `unexpected token` while the same array
                indexed fine through `Self` or an instance. One resolver, three
                spellings. }
              Result := ParseLValueAST(fldIdx, qualNameTok);
              Exit;
            end;

            { `TFoo.MaxItems` — a class CONST, qualified by its class. Scoped ones
              (scalar/string/set) live under a mangled key in the class-const
              registry, resolved by walking the class chain from `ci`; visibility
              enforced under --strict-visibility. bug-pascal-class-const-visibility. }
            ccReg := FindClassConst(ci, fieldName);
            if ccReg >= 0 then
            begin
              if StrictVisibility then
                EnforceMemberVis(ClassConstCi[ccReg], ClassConstVis[ccReg], fieldName);
              ccKey := ClassConstMangle(ClassConstCi[ccReg], fieldName);
              ccNode := EmitClassConstNode(ccKey, ccTk);
              if ccNode >= 0 then
              begin
                tk := ccTk; recName := REC_NONE;
                Result := ccNode;
                Exit;
              end;
            end;

            { Legacy/global fallback — a typed class const (real storage, still
              global) or a plain unit const named through its class. }
            fldIdx := FindStrConst(fieldName);     { a STRING const lives in its own table }
            if fldIdx >= 0 then
            begin
              node := AllocNode(AN_STR_LIT);
              ASTSOffset[node] := StrConstSOff[fldIdx];
              ASTSLen[node] := StrConstSLen[fldIdx];
              ASTTk[node] := Ord(tyString);
              tk := tyString;
              recName := REC_NONE;
              Result := node;
              Exit;
            end;
            fldIdx := FindSym(fieldName);
            if (fldIdx >= 0) and (Syms[fldIdx].Kind = skConst) then
            begin
              node := AllocNode(AN_INT_LIT);
              ASTIVal[node] := Syms[fldIdx].ConstVal;
              ASTTk[node] := Ord(Syms[fldIdx].TypeKind);
              tk := Syms[fldIdx].TypeKind;
              recName := REC_NONE;
              Result := node;
              Exit;
            end;

            { A class-reference operation named on the class LITERAL itself:
              `TMid.InheritsFrom(TBase)`, `TFoo.ClassName`. The class as a value IS
              its RTTI blob pointer (AN_CLASSREF), which is exactly the blob these
              operations walk. }
            if IsClassRefOpName(fieldName) then
            begin
              mcallNode := AllocNode(AN_CLASSREF);
              ASTIVal[mcallNode] := ci;
              ASTTk[mcallNode] := Ord(tyPointer);
              mcallNode := GenMakeClassRefOp(mcallNode, fieldName, tk);
              if mcallNode >= 0 then
              begin
                recName := REC_NONE;
                Result := ParseClassRefOpTail(mcallNode, tk);
                Exit;
              end;
            end;

            Error('class method not found: ' + fieldName);
          end;
          EnforceMethVis(mmi, fieldName);
          mpi := UMthProc_[mmi];

          if UMthIsCtor[mmi] and (not pyInitCall) then
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

          { Self (param 0) is the CLASS being named -- `TMyTest.Suite` passes TMyTest,
            which is precisely what makes the metaclass idiom work. Passed even with no
            argument list, since it is not optional.

            The argument list itself goes through GenMakeStaticMethodCall, the same builder
            the bare and instance-reached forms use -- so an `array of const` LITERAL
            argument (`TJSONData.DoError(msg, ['Nil', x])`, fpjson) is recognised here too.
            This block used to hand-roll its own arg loop, which parsed the '[' as a SET and
            died on "set item must be one character". }
          if UClsIsRecord[ci] then
          begin
            { a record/type HELPER's static reached through the TYPE name
              (TU32Helper.GetSignMask): no metaclass exists — Self is a
              by-value dummy the static body may not read. }
            mselfArg := AllocNode(AN_INT_LIT);
            ASTIVal[mselfArg] := 0;
            ASTTk[mselfArg] := Ord(Procs[mpi].Params[0].TypeKind);
          end
          else
          begin
            mselfArg := AllocNode(AN_CLASSREF);
            ASTIVal[mselfArg] := ci;
            ASTTk[mselfArg] := Ord(tyPointer);
          end;
          GenVirtSlot := UMthVirSlot[mmi];
          mcallNode := GenMakeStaticMethodCall(mpi, mselfArg);
          tk := Procs[mpi].RetType;
          recName := ProcRetRecId[mpi];
          if (tk <> tyClass) and (tk <> tyRecord) then recName := REC_NONE;

          Result := mcallNode;
          Exit;
        end
        else
        begin
          ErrorIdent := fieldName;
          if HiddenByDeclOrder(fieldName) then
            Error('undefined variable — it is a global declared later, declare it before use')
          else if HiddenByForwardOrder(fieldName) then
            Error('routine used before its declaration — define it above, or add a forward; declaration (--strict/require-forward)')
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
          { `d[k] += v` — an AUGMENTED assignment to a subscript. Python's most
            common counting idiom, and it reported "assignment target is not an
            lvalue" because the subscript lowered to a getter CALL and the
            augmented path then built an AN_ASSIGN over it. Desugared to
            `d[k] = d[k] OP v`; the index expression is evaluated twice, which is
            the same trade the `del d[k]` rewrite makes and is invisible for the
            pure index expressions the corpus uses.
            (feature-nilpy-augmented-subscript-assign) }
          augBin := tkEOF;
          augPow := False;

          ParsePropIndexArgs(margIdx, mlastArg);   { [a {, b}] (bracket consumed here) }

          if isAssign then
          begin
            if UPropWriteMLen[pri] <= 0 then Error('default property is read-only');
            methName := '';
            for i := 0 to UPropWriteMLen[pri] - 1 do AppendChar(methName, TokChars[UPropWriteMOff[pri] + i]);
            mmi := FindUMeth(mci, methName);
            if mmi < 0 then Error('setter method not found: ' + methName);
            mpi := UMthProc_[mmi];
            augRead := -1;
            if (augBin <> tkEOF) or augPow then
            begin
              { the read is built HERE, over a CLONE of the index arguments: the
                setter appends its value to margIdx's chain, and sharing that
                chain with the reader made the value an argument of the read —
                a cycle the compiler walked forever (it segfaulted). }
              augRead := PyMakeSubscriptRead(node, PyCloneArgChain(margIdx), mci, pri);
              Next;                                 { consume the `+=` token }
            end
            else Expect(tkAssign, ':=');
            ParseExpr;
            if augPow then
              { value := <current element> ** <rhs> — PyMakePow, not AN_BINOP,
                and it carries the __pow__/__rpow__ dispatch with it. }
              CurASTNode := PyMakePow(augRead, CurASTNode)
            else if augBin <> tkEOF then
            begin
              { value := <current element> OP <rhs> }
              augNode := AllocNode(AN_BINOP);
              ASTIVal[augNode] := Ord(augBin);
              ASTLeft[augNode] := augRead;
              ASTRight[augNode] := CurASTNode;
              ASTTk[augNode] := Ord(tyVariant);
              CurASTNode := augNode;
            end;
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
        end
        else if (FindUMeth(mci, '__getitem__') >= 0) or
                (FindUMeth(mci, '__setitem__') >= 0) then
        begin
          { A user class with NO Pascal default property (pylib's own
            TPyList/TPyDict declare one; a plain user class never does) but
            defining Python's `__getitem__`/`__setitem__`. Without this,
            `obj[i]` fell all the way through to the generic AN_INDEX
            fallback below — raw array/pointer arithmetic on the instance,
            a silent WRONG value (`0` observed), not even a crash.
            Single-key subscript only (no `obj[a, b]` tuple key, no `+=`
            augmented form) -- the common shape; either loudly errors below
            rather than guessing.
            bug-nilpy-dunder-protocols-ignored-fall-back-to-handle-arithmetic }
          isAssign := False;
          i := TokPos - 1; w := 0;   { TokPos-1 = the '[' }
          while i < TokCount do
          begin
            if Tokens[i].Kind = tkLBrack then Inc(w)
            else if Tokens[i].Kind = tkRBrack then
            begin Dec(w); if w = 0 then begin Inc(i); Break; end; end;
            Inc(i);
          end;
          if (i < TokCount) and (Tokens[i].Kind = tkAssign) then isAssign := True
          else if (i < TokCount) and ((PyAugBinTok(Tokens[i].Kind) <> tkEOF)
                                      or (Tokens[i].Kind = tkPowEq)) then
            { tkPowEq is listed explicitly: `**` has no binary token, so
              PyAugBinTok returns tkEOF for it and `obj[k] **= v` fell past this
              named refusal into a bare "expected expression". }
            Error('Nil Python: augmented assignment to a __getitem__/__setitem__ '
                  + 'subscript is not supported');
          Next;                       { consume '[' }
          PyParseBoolExpr;
          keyNode := CurASTNode;
          if CurTok.Kind = tkComma then
            Error('Nil Python: __getitem__/__setitem__ with a tuple key is not supported');
          Expect(tkRBrack, ']');
          if isAssign then
          begin
            Expect(tkAssign, ':=');
            ParseExpr;
            if FindUMeth(mci, '__setitem__') < 0 then
            begin
              { A genuine runtime error (a `try/except` around this must
                still compile and run its handler), not a compile-time
                Error() -- same reasoning as PyNotContainerError /
                PyNotCallableError above. The value is still parsed/
                evaluated first, matching Python's left-to-right order. }
              node := PyClassErrCallNode('PyNoSetitemError', mci);
              if node < 0 then Error('Nil Python: pylib (PyNoSetitemError) not loaded');
              Result := node; Exit;
            end;
            node := PyCallMeth2(mci, '__setitem__', node, keyNode, CurASTNode);
            Result := node; Exit;
          end
          else
          begin
            { …and the mirror of the missing-setter case: this arm is now
              entered for a class declaring only `__setitem__`, so a READ has
              no getter to call. Same run-time TypeError the neither-member arm
              above raises, rather than a compile error — `try: obj[k] /
              except TypeError:` must still compile.
              bug-nilpy-setitem-without-getitem-write-does-not-compile }
            if FindUMeth(mci, '__getitem__') < 0 then
            begin
              node := PyNotSubscriptableNode(mci);
              if node < 0 then Error('Nil Python: pylib (not-subscriptable) not loaded');
              tk := tyInt64; recName := REC_NONE;
              continue;
            end;
            node := PyCallMeth1(mci, '__getitem__', node, keyNode);
            tk := IntToTypeKind(ASTTk[node]); recName := ResolveNodeRec(node);
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
      begin
        tk := tyChar;
      end
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
      { …and the same refusal for every other memberless SCALAR, which the array
        check's own note assumed was already covered ("strings take Length()
        style intrinsics") and which nothing actually checked. The fall-through
        built a field access at offset 0 and READ THE VALUE'S OWN BYTES: on a
        string, `s.Length` for s='Hello' printed 1819043144 — the four bytes of
        'Hell' as an Int32 — and so did `s.NoSuchMember`, with no diagnostic
        either way. Ints, floats and booleans answered with themselves.

        Delphi's TStringHelper surface (`s.Length`, `s.ToUpper`, `s.Trim`,
        `s.Substring`) is exactly what modern Pascal writes, and FPC compiles it
        under {$modeswitch typehelpers}; we do not implement it yet. Refusing is
        the honest answer until we do, and the message says which it is so the
        reader is not left hunting a wrong number. Arrays and pointers already
        errored here — those are the shape this follows.

        NilPy is excluded: `s.upper()`, `n.bit_length()` and the dynamic-attribute
        fallback below are the ordinary Python spelling and resolve further down.
        tyRecord / tyClass / tyInterface / tyVariant / tyPointer / tyAuto /
        tyUnknown and the promotable-int family are all absent from the set on
        purpose — each has a real member path.

        Keyed on the RECEIVER SYMBOL's declared type, exactly like the array
        check above it, and NOT on the expression's `tk`. `tk` is wrong for a
        cast-then-deref receiver: `PPyVarRec(@v)^.Payload` (lib/rtl/atexit, ast,
        configparser) arrives here as a scalar with no record id, and a `tk`-keyed
        version of this check refused three working example programs. Requiring a
        plain declared variable keeps the refusal to the shape actually proved
        broken and leaves every computed receiver on its existing path.
        bug-p-a-member-on-a-scalar-silently-reads-the-values-own-bytes }
      if (not isNilPy) and (recName = REC_NONE) and
         (ASTKind[node] = AN_IDENT) and (ASTIVal[node] >= 0) and
         not Syms[ASTIVal[node]].IsArray and
         (Syms[ASTIVal[node]].TypeKind in
                [tyInteger, tyBoolean, tyChar, tyString, tyInt8, tyUInt8,
                 tyInt16, tyUInt16, tyInt32, tyUInt32, tyInt64, tyUInt64,
                 tyNativeInt, tyNativeUInt, tySingle, tyDouble, tyExtended,
                 tySet, tyAnsiString, tyShortString, tyFixedString]) then
      begin
        if Syms[ASTIVal[node]].TypeKind in
             [tyString, tyAnsiString, tyShortString, tyFixedString] then
          Error('a string has no members here: pxx does not implement Delphi''s ' +
                'string helpers (s.Length, s.ToUpper, s.Trim, s.Substring) — ' +
                'use the intrinsics Length(s), UpperCase(s), Trim(s), Copy(s, i, n)')
        else
          Error('a value of this type has no members (only records, classes, ' +
                'interfaces and variants do)');
      end;
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
      viaProp := False;

      { `x.__class__.__name__`, ahead of the dynamic-attribute fallback below —
        which is what used to claim it and raise AttributeError at run time. }
      if PyIsClassNameChainAhead then
      begin
        node := PyMakeClassNameOf(node);
        tk := tyAnsiString; recName := REC_NONE;
        Result := node;
        Exit;
      end;
      { NilPy DYNAMIC attribute on a class instance: `vm._trans_ptr` where the
        class declares no such field/method/property. Python adds attributes at
        run time; route reads to pydynattr_get and writes to pydynattr_set (the
        instance pointer keys the store). Guarded to genuinely undeclared names,
        so nothing that resolves today changes. }
      { Python's dict VIEWS, mapped before the dynamic-attribute fallback below:
        pylib spells them keylist/vallist/itemlist (dodging the default `Items[]`
        property, Pascal being case-insensitive). Undeclared as written, so
        `d.values()` used to become a dynamic attribute read of a name no object
        has, and CALLING that None-valued attribute jumped to address 0
        (bug-nilpy-dict-values-method-missing). }
      if isNilPy and (tk = tyClass) and (recName >= REC_UCLASS_BASE) and
         (TokPos + 1 < TokCount) and (Tokens[TokPos].Kind = tkLParen) and
         (Tokens[TokPos + 1].Kind = tkRParen) then
      begin
        if CaseEqual(fieldName, 'values') and
           (FindUMeth(recName - REC_UCLASS_BASE, 'vallist') >= 0) then
          fieldName := 'vallist'
        else if CaseEqual(fieldName, 'keys') and
                (FindUMeth(recName - REC_UCLASS_BASE, 'keylist') >= 0) then
          fieldName := 'keylist'
        { `w.destroy()` — Python's spelling of a name Pascal reserves for the
          destructor, so the façade declares `destroy_` and the Python form maps
          onto it here. Same treatment as the dict views above. }
        else if CaseEqual(fieldName, 'destroy') and
                (FindUMeth(recName - REC_UCLASS_BASE, 'destroy_') >= 0) then
          fieldName := 'destroy_';
      end;
      { A Python method name Pascal RESERVES — the library convention is a
        trailing underscore (`set_`, `destroy_`), and `cfg.set(section, key,
        value)` (configparser's own spelling) must reach it. Any argument list,
        unlike the view methods above, so this guard is only "a call follows". }
      if isNilPy and (tk = tyClass) and (recName >= REC_UCLASS_BASE) and
         (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        if (FindUMeth(recName - REC_UCLASS_BASE, fieldName) < 0) and
           (FindUProp(recName - REC_UCLASS_BASE, fieldName) < 0) and
           (FindUField(recName - REC_UCLASS_BASE, fieldName) < 0) and
           (FindUMeth(recName - REC_UCLASS_BASE, fieldName + '_') >= 0) then
          fieldName := fieldName + '_';
      end;
      { ...and the same for a pylib container method pylib declares under
        another name — `s.update(other)` on a set, which pylib spells
        setupdate. One table, shared with PyParseClassMethodCall's copy of this
        resolution (bug-nilpy-set-update-method-is-not-mapped). Guarded to
        names the class does NOT declare as written, so nothing that resolves
        today moves. }
      if isNilPy and (tk = tyClass) and (recName >= REC_UCLASS_BASE) and
         (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
        fieldName := PyMethNameFor(recName - REC_UCLASS_BASE, fieldName);
      { A class attribute written BOTH through its class name and through an
        instance: the one row where Python's model is visibly different from
        copy-at-construction, so it is spelled out. The instance's own override
        wins; absent one the read falls through to the shared slot; and a write
        CREATES the override rather than touching the slot every other instance
        reads. The `pydynattr` store is the same machinery an undeclared dynamic
        attribute uses — in Python `self.x = ...` and `obj.x = ...` really are
        the same operation, whether or not the class declares `x`. }
      if NilPyUserCode and (tk = tyClass) and (recName >= REC_UCLASS_BASE) and
         (FindUField(recName - REC_UCLASS_BASE, fieldName) < 0) and
         (FindUMeth(recName - REC_UCLASS_BASE, fieldName) < 0) and
         (PyClsAttrOvrSlot(recName - REC_UCLASS_BASE, fieldName) >= 0) then
      begin
        cvIdx := PyClsAttrOvrSlot(recName - REC_UCLASS_BASE, fieldName);
        Next;   { consume the field name }
        if CurTok.Kind = tkAssign then
        begin
          Next;
          ParseArgExpr;
          node := PyMakeDynAttrSet(node, fieldName, CurASTNode);
          tk := tyUnknown; Result := node; Exit;
        end;
        if PyAugBinTok(CurTok.Kind) <> tkEOF then
        begin
          fldSigPi := Ord(PyAugBinTok(CurTok.Kind));
          Next;
          ParseArgExpr;
          callIndNode := AllocNode(AN_BINOP);
          ASTIVal[callIndNode] := fldSigPi;
          ASTLeft[callIndNode] := PyClsAttrOvrGet(node, fieldName, cvIdx);
          ASTRight[callIndNode] := CurASTNode;
          ASTTk[callIndNode] := Ord(tyVariant);
          node := PyMakeDynAttrSet(node, fieldName, callIndNode);
          tk := tyUnknown; Result := node; Exit;
        end;
        node := PyClsAttrOvrGet(node, fieldName, cvIdx);
        tk := tyVariant; recName := REC_NONE;
        Continue;
      end;

      { NilPyUserCode, not isNilPy: `isNilPy` is true for the WHOLE compilation,
        including every PASCAL unit loaded into it (pylib and friends), so this
        Python-only fallback was hijacking ordinary Pascal member resolution
        inside those units. `o.ClassName` on a plain `TObject` local became a
        dynamic attribute fetch and died at run time with "'Dog' object has no
        attribute 'ClassName'", while the identical `TObject(p).ClassName` — a
        different SHAPE, same type — resolved to the RTTI call and worked
        (bug-classname-on-a-tobject-local-compiles-to-a-dynamic-attr-fetch).
        Same predicate that gates every other NilPy-only rule. }
      if NilPyUserCode and (tk = tyClass) and (recName >= REC_UCLASS_BASE) and
         (FindUField(recName - REC_UCLASS_BASE, fieldName) < 0) and
         (FindUMeth(recName - REC_UCLASS_BASE, fieldName) < 0) and
         (FindUProp(recName - REC_UCLASS_BASE, fieldName) < 0) and
         { a CLASS ATTRIBUTE lowered as a shared slot has no instance field on
           purpose — it is declared, not dynamic, and the class-variable branch
           further down resolves it. Without this the closed-world fallback
           claimed it first and every instance read raised AttributeError. }
         (FindClassVar(recName - REC_UCLASS_BASE, fieldName) < 0) then
      begin
        Next;   { consume the field name }
        if CurTok.Kind = tkAssign then
        begin
          Next;
          ParseArgExpr;
          node := PyMakeDynAttrSet(node, fieldName, CurASTNode);
          tk := tyUnknown; Result := node; Exit;
        end;
        { augmented assignment `vm._x += v` -> set(x, get(x) OP v). The base is
          re-read in the get; fine for the side-effect-free receivers here. }
        if PyAugBinTok(CurTok.Kind) <> tkEOF then
        begin
          fldSigPi := Ord(PyAugBinTok(CurTok.Kind));   { the binary op }
          Next;
          ParseArgExpr;
          callIndNode := AllocNode(AN_BINOP);
          ASTIVal[callIndNode] := fldSigPi;
          ASTLeft[callIndNode] := PyMakeDynAttrGet(node, fieldName);
          ASTRight[callIndNode] := CurASTNode;
          ASTTk[callIndNode] := Ord(tyVariant);
          node := PyMakeDynAttrSet(node, fieldName, callIndNode);
          tk := tyUnknown; Result := node; Exit;
        end;
        { A CALL of a name the class does not declare. Python would raise
          AttributeError; NilPy used to build a dynamic-attribute read, get None,
          and call it — a segfault before pyvar_callee_addr started checking, a
          runtime TypeError since, and either way no hint of which method. The
          class is a CLOSED world here, so the only way the name could be legal
          is a dynamic attribute holding a callable — which means some `.name =`
          exists somewhere in the module. If none does, say so at compile time
          (bug-nilpy-unknown-method-segfaults). }
        if (CurTok.Kind = tkLParen) and (not PyDynAttrEverAssigned(fieldName)) then
          Error('Nil Python: ' +
                PyRawName(UClsNOff[recName - REC_UCLASS_BASE],
                          UClsNLen[recName - REC_UCLASS_BASE])
                + ' has no method ' + fieldName);
        node := PyMakeDynAttrGet(node, fieldName);
        tk := tyVariant; recName := REC_NONE;
        Continue;
      end;

      { IMPLICIT DEREF: `p.field` where p is a pointer to a RECORD means `p^.field`
        (FPC/Delphi). Without this the AN_FIELD was built straight over the pointer,
        so the field resolved at an offset into the POINTER VALUE itself and read
        back garbage — silently, with no error. Only fires when the pointee is a
        record that really has this member, so nothing that resolves today changes:
        a metaclass (`class of T`) pointee is a CLASS, not a record, and keeps its
        own dispatch below. }
      if tk = tyPointer then
      begin
        autoDeref := AllocNode(AN_DEREF);
        ASTLeft[autoDeref] := node;
        peRec := ResolveNodeRec(autoDeref);
        if (peRec >= REC_UCLASS_BASE) and UClsIsRecord[peRec - REC_UCLASS_BASE] and
           ((FindUField(peRec - REC_UCLASS_BASE, fieldName) >= 0) or
            (FindUMeth(peRec - REC_UCLASS_BASE, fieldName) >= 0)) then
        begin
          ASTTk[autoDeref] := Ord(tyRecord);
          node := autoDeref;
          tk := tyRecord;
          recName := peRec;
        end;
      end;







      { Metaclass-dispatched construction `classRef.Create(args)`: the base is a
        metaclass value — either a `class of T` variable (AN_IDENT, a tyPointer
        whose element is a class) or an inline metaclass cast `TFooClass(expr)`
        (AN_PTR_CAST over a `class of` alias, e.g. the streamer's
        `TComponentClass(GetClass(name)).Create(owner)`). Build AN_METACLASS_NEW,
        which allocates the DYNAMIC class the ref points at and runs its virtual
        constructor — see the IR lowering. Distinct from the static `TFoo.Create`
        path, which resolves the class at compile time. }
      { All five spellings of a metaclass VALUE answer through one predicate —
        a `class of T` variable, an inline metaclass cast, an element of an
        array of them, a metaclass-typed field, and a function RESULT. The first
        four used to be four copies of the test right here, added one ticket at
        a time, which is why the fifth was missing for so long.
        bug-a-a-metaclass-returned-from-a-function-is-not-a-receiver }
      ci := NodeMetaclassCi(node);
      if ci >= 0 then
      begin
        { Constructors (any name -- UMthIsCtor, not the spelling), class methods,
          and the class-reference operations on a TYPED metaclass
          (`AClass.InheritsFrom(...)`, `AClass.ClassName` -- fpjson's
          SetJSONInstanceType does both) all live in ParseMetaclassMemberTail.
          A member of that name on the class still outranks an operation. }
        mcallNode := ParseMetaclassMemberTail(node, ci, tk, recName, mcFin);
        if mcallNode >= 0 then
        begin
          node := mcallNode;
          if mcFin then
          begin
            Result := node;
            Exit;
          end;
          Continue;   { allow trailing .field/[i] selectors on the value }
        end;
      end;

      { A class-reference OPERATION on ANY pointer-typed value: an array ELEMENT, a
        FIELD, a call result -- not just a bare identifier.

          MinJSONInstanceTypes[AType].ClassName      { fpjson }

        A class reference IS its RTTI blob pointer, and ClassName / ClassType /
        InheritsFrom need only that VALUE, not a compile-time class id -- so they can be
        answered for any pointer-typed expression. Nothing else on a pointer is spelled
        this way, which is what makes the test safe (the same reasoning as `is` against a
        class-reference value). Class-typed receivers with a concrete class id are handled
        further down, and take precedence via the mci path. }
      if (CurTok.Kind = tkIdent) and IsClassRefOpName(fieldName) and
         (tk = tyPointer) and (recName = REC_NONE) and
         (ASTKind[node] <> AN_IDENT) then
      begin
        Next;                          { consume the operation name }
        mcallNode := GenMakeClassRefOp(node, fieldName, tk);
        if mcallNode >= 0 then
        begin
          recName := REC_NONE;
          Result := ParseClassRefOpTail(mcallNode, tk);
          Exit;
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
      begin
        { ...but the class-reference OPERATIONS are answerable on it: a TClass value
          IS the RTTI blob pointer. `GetN(C: TClass)` reads C.ClassName;
          `AClass.InheritsFrom(TTestCase)` walks C's parent chain. Both fpcunit. }
        if (CurTok.Kind = tkIdent) and IsClassRefOpName(fieldName) then
        begin
          Next;                     { consume the operation name }
          mcallNode := GenMakeClassRefOp(node, fieldName, tk);
          if mcallNode >= 0 then
          begin
            recName := REC_NONE;
            Result := ParseClassRefOpTail(mcallNode, tk);
            Exit;
          end;
        end;
        Error('member access on a bare object reference; cast to a concrete class first');
      end;

      { Check if it is a property on a class }
      mci := -1; pri := -1;
      if recName >= REC_UCLASS_BASE then
      begin
        mci := recName - REC_UCLASS_BASE;
        { NilPy `d.items()` — Python's spelling collides with TPyDict's DEFAULT
          indexed property `Items[k]` (Pascal is case-insensitive), so the name
          resolved to the property and the following `(` was a parse error. A
          CALL is unambiguous: `d.items()` can only mean the method. Mapped onto
          `itemlist`, the same way keylist/vallist are named to stay clear of it. }
        if isNilPy and CaseEqual(fieldName, 'items') and
           (TokPos + 1 < TokCount) and (Tokens[TokPos].Kind = tkLParen) and
           (Tokens[TokPos + 1].Kind = tkRParen) and
           (FindUMeth(mci, 'itemlist') >= 0) then
          fieldName := 'itemlist';
        { `d.keys()` / `d.values()` as VALUES, same treatment: Python's spellings
          map onto keylist/vallist. Unmapped, they fell through to the dynamic
          method dispatch and produced a garbage receiver — `max(d.values())`
          segfaulted (bug-nilpy-dict-values-method-missing). }
        if isNilPy and (TokPos + 1 < TokCount) and
           (Tokens[TokPos].Kind = tkLParen) and (Tokens[TokPos + 1].Kind = tkRParen) then
        begin
          if CaseEqual(fieldName, 'keys') and (FindUMeth(mci, 'keylist') >= 0) then
            fieldName := 'keylist'
          else if CaseEqual(fieldName, 'values') and (FindUMeth(mci, 'vallist') >= 0) then
            fieldName := 'vallist';
        end;
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
        { AUGMENTED assignment through a method-backed property — `s.state += 1`.
          `isAssign` only ever tested for `:=`, so this fell into the READ arm
          below: the getter was called, its RESULT was handed to the assignment
          machinery as an lvalue, and the store went nowhere. Silently — the
          value simply never changed, on a STATICALLY typed receiver as much as a
          dynamic one, which is why it outlived the dropped-store bug it shares a
          concept with (bug-nilpy-property-setter-is-skipped-on-a-dynamically-
          typed-receiver: there the write vanished on the way IN, here on the way
          back OUT).

          Desugared the way Python defines it — `set(get() OP rhs)` — reusing
          this property's own accessors, so an override still dispatches through
          the VMT. The RECEIVER is evaluated twice (once per accessor); it is a
          variable, field or unboxed-cast read at every site that reaches here,
          so that is side-effect free — the same licence PyMakeTruthy and the
          dynamic-attribute augmented path already take, and the identical
          desugaring they use.

          Field-backed properties are untouched: they rewrite to their backing
          field above and the ordinary field lvalue handles `+=` correctly.
          Indexed properties keep the old path — the index expression would be
          evaluated twice too, and that is not always safe. }
        if (not isAssign) and (not UPropIsIndexed[pri]) and
           (UPropReadMLen[pri] > 0) and (UPropWriteMLen[pri] > 0) and
           (CurTok.Kind = tkIdent) and (TokPos < TokCount) and
           (PyAugBinTok(Tokens[TokPos].Kind) <> tkEOF) then
        begin
          methName := '';
          for i := 0 to UPropReadMLen[pri] - 1 do
            AppendChar(methName, TokChars[UPropReadMOff[pri] + i]);
          mmi := FindUMeth(mci, methName);
          if mmi < 0 then Error('getter method not found: ' + methName);
          mpi := UMthProc_[mmi];
          if UMthVirSlot[mmi] >= 0 then
          begin
            augRead := AllocNode(AN_VIRTUAL_CALL);
            ASTRight[augRead] := UMthVirSlot[mmi];
          end
          else
            augRead := AllocNode(AN_CALL);
          ASTIVal[augRead] := mpi;
          ASTTk[augRead] := Ord(Procs[mpi].RetType);
          mselfArg := AllocNode(AN_ARG);
          ASTLeft[mselfArg] := node;
          ASTRight[mselfArg] := -1;
          ASTLeft[augRead] := mselfArg;

          Next;                       { the property name }
          augBin := PyAugBinTok(CurTok.Kind);
          Next;                       { the augmented operator }
          ParseExpr;
          augNode := AllocNode(AN_BINOP);
          ASTIVal[augNode] := Ord(augBin);
          ASTLeft[augNode] := augRead;
          ASTRight[augNode] := CurASTNode;
          ASTTk[augNode] := Ord(Procs[mpi].RetType);

          methName := '';
          for i := 0 to UPropWriteMLen[pri] - 1 do
            AppendChar(methName, TokChars[UPropWriteMOff[pri] + i]);
          mmi := FindUMeth(mci, methName);
          if mmi < 0 then Error('setter method not found: ' + methName);
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
          ASTLeft[mselfArg] := node;
          margSeq := AllocNode(AN_ARG);
          ASTLeft[margSeq] := augNode;
          ASTRight[margSeq] := -1;
          ASTRight[mselfArg] := margSeq;
          ASTLeft[mcallNode] := mselfArg;

          node := mcallNode;
          Result := node; Exit;
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
            viaProp := True;
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
            if UPropIsIndexed[pri] then ParsePropIndexArgs(margIdx, mlastArg)
            else PropIndexConstArg(pri, margIdx, mlastArg);
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
            viaProp := True;
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
            if UPropIsIndexed[pri] then ParsePropIndexArgs(margIdx, mlastArg)
            else PropIndexConstArg(pri, margIdx, mlastArg);
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

            { ...and then KEEP GOING. A getter's result is an ordinary value, so a selector
              may follow it: `Self.Items[I].Clone` (fpjson's TJSONArray.Clone). This path used
              to Exit here, leaving the `.Clone` unconsumed -- which the ASSIGNMENT path
              tolerated (the statement ended there anyway) but an argument list did not
              ("expected comma or close parenthesis"). That asymmetry is why it survived: the
              obvious way to write it, `x := obj.Items[i].Method`, happened to work. }
            tk := Procs[mpi].RetType;
            recName := ProcRetRecId[mpi];
            if (tk <> tyClass) and (tk <> tyRecord) then recName := REC_NONE;
            if (CurTok.Kind = tkDot) or (CurTok.Kind = tkLBrack) then
              node := ParseClassRecordSelectors(node, recName, tk);

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
        mmi := FindUMethOverloadAhead(mci, fieldName, CountCallArgsAhead);
        { …and re-target by KEYWORD name too — arity alone still picks the
          first same-arity overload, which need not be the one declaring the
          name a `key=expr` argument uses (bug-nilpy-keyword-arg-vs-overload-set) }
        if isNilPy and (mmi >= 0) then
          mmi := PyPromoteOverloadByKwAt(mci, mmi, PyKwNamesTokPos, fieldName);
      end;

      { FPC's TObject.MethodAddress(name) / MethodName(addr): published-method RTTI,
        available with no `uses` because FPC declares them on TObject in System.
        fcl-fpcunit finds its tests with `Self.MethodAddress(FName)`. Rewritten to
        the __pxxMethodAddress / __pxxMethodName helpers in the builtin unit (pulled
        by the token pre-scan). Only when the class has NO method of that name, so a
        user's own MethodAddress still wins. }
      { obj.GetInterface(IID, Obj) — the GUID lookup, same builtin-shadowing rule }
      if (mmi < 0) and (mci >= 0) and (CurTok.Kind = tkIdent) and
         (Tokens[TokPos].Kind = tkLParen) and
         CaseEqual(fieldName, 'GetInterface') and
         (FindProc('__pxxGetInterface') >= 0) then
      begin
        Next;                        { consume 'GetInterface' }
        mcallNode := GenMakeGetInterfaceCall(node);
        if mcallNode >= 0 then
        begin
          tk := tyBoolean;
          recName := REC_NONE;
          Result := mcallNode;
          Exit;
        end;
      end;

      { obj.ClassName / obj.ClassType / obj.InheritsFrom(C) -- FPC has them on TObject
        in System. An instance reaches its blob through __pxxRttiOf. Only when the
        class has no member of that name, so a user's own still wins. }
      if (mmi < 0) and (mci >= 0) and (CurTok.Kind = tkIdent) and
         IsClassRefOpName(fieldName) then
      begin
        mblobNode := GenMakeRttiOfCall(node);
        if mblobNode >= 0 then
        begin
          Next;                      { consume the operation name }
          mcallNode := GenMakeClassRefOp(mblobNode, fieldName, tk);
          if mcallNode >= 0 then
          begin
            recName := REC_NONE;
            Result := ParseClassRefOpTail(mcallNode, tk);
            Exit;
          end;
        end;
      end;

      if (mmi < 0) and (mci >= 0) and (CurTok.Kind = tkIdent) and
         (Tokens[TokPos].Kind = tkLParen) and
         (CaseEqual(fieldName, 'MethodAddress') or CaseEqual(fieldName, 'MethodName')) then
      begin
        if CaseEqual(fieldName, 'MethodAddress') then
          ci := FindProc('__pxxMethodAddress')
        else
          ci := FindProc('__pxxMethodName');
        if ci >= 0 then
        begin
          Next;                  { consume the method name }
          Expect(tkLParen, '(');
          mcallNode := AllocNode(AN_CALL);
          ASTIVal[mcallNode] := ci;
          ASTTk[mcallNode] := Ord(Procs[ci].RetType);

          { arg 0 = the instance }
          margSeq := AllocNode(AN_ARG);
          ASTLeft[margSeq] := node;
          ASTLeft[mcallNode] := margSeq;

          { arg 1 = the name (or the code address) }
          ParseExpr;
          mlastArg := AllocNode(AN_ARG);
          ASTLeft[mlastArg] := CurASTNode;
          ASTRight[margSeq] := mlastArg;

          Expect(tkRParen, ')');
          tk := Procs[ci].RetType;
          recName := REC_NONE;
          Result := mcallNode;
          Exit;
        end;
      end;

      if mmi >= 0 then
      begin
        EnforceMethVis(mmi, fieldName);
        mpi := UMthProc_[mmi];
        Next; { consume method name }
        { NilPy: `obj.method` with NO following call is a BOUND-METHOD VALUE, not
          a paren-less call (Python has no paren-less calls). Capture {code, self}
          as a callable variant. uforth's exec env = {"push": self.push, ...} needs
          this to STORE without dropping self and segfaulting.
          (feature-nilpy-bound-method-value.) Virtual methods bind now off the
          receiver's VMT is a later refinement; uforth's push/pop are direct. }
        { The gate is "NilPy USER code", which is the main program OR a `.py`
          MODULE — not `CurrentUnitIdx < 0`, which means the main program only.
          A class defined in an imported `.py` therefore fell through to the
          call path and `self.canvas.yview` SEGFAULTED, while the identical
          class written in the main file worked; a method CALL on the same
          field was fine, so the field's class identity was never the problem
          (bug-nilpy-settings-editor-segfaults-on-bound-method-field).
          NilPyUserCode (symtab.inc) is that predicate — the whole NilPy-only
          rule set now shares it. }
        if NilPyUserCode and
           (CurTok.Kind <> tkLParen) and
           (mci >= 0) and not UClsIsInterface[mci] then
        begin
          node := PyMakeBoundMethod(mpi, node);
          tk := tyVariant; recName := REC_NONE;
          ASTTk[node] := Ord(tyVariant);
          Result := node;
          Exit;
        end;
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
            { `obj.F()` -- EMPTY parens on a method whose parameters ALL have defaults. FPC
              accepts it (fcl-json's own suite calls `J.FormatJSON()`); without this the loop hands
              the `)` to ParseExpr and reports "expected expression". A method with NO parameters
              already worked, because the loop simply never ran. }
            if CurTok.Kind = tkRParen then
            begin
              if (Procs[mpi].ParamCount > 1) and CanFillDefaultsFrom(mpi, 1) then
                FillDefaultArgs(mpi, 1, mcallNode, mlastArg)
              { ...but EMPTY parens on a method with REQUIRED parameters is a
                missing-argument error, not a free pass. This shortcut set mai
                PAST the arity loop unconditionally, so the loop never ran, the
                required slots were never filled, and the callee read an
                UNINITIALISED frame: `c.m()` against `def m(self, a)` SEGFAULTED
                and `[1,2,3].count()` quietly returned a wrong value — the worse
                of the two. A plain NAME receiver is what reaches this route; a
                literal or constructor receiver goes through
                PyParseClassMethodCall, which already checks
                (bug-nilpy-too-few-args-to-container-method-compiles-and-segfaults).

                NOT NilPy-only: `c.M()` against `function M(a: Integer)` was
                accepted in Pascal too, where FPC rejects it.

                `*args`/`**kwargs` methods are variadic by construction and are
                exempt; the call-site star-unpack form is handled below. }
              else if (Procs[mpi].ParamCount > 1) and
                      (ProcPyStarIdx[mpi] < 0) and (ProcPyKwIdx[mpi] < 0) then
                Error(fieldName + '() requires ' +
                      AIntToStr(Procs[mpi].ParamCount - 1) +
                      ' argument(s), none given');
              mai := Procs[mpi].ParamCount;   { nothing to parse; Expect(tkRParen) consumes it }
            end;
            { `d.update(a=1)` / `d.update(**e)` on a plain NAME receiver — the
              route this shape actually takes. Same builder as the other loops
              (four of them ask it now; that they are four is the shape
              devdocs/dev/normalise-dont-special-case.md warns about, and asking
              ONE function is how it is kept honest). }
            if PyKwDictArgsHere(mpi) then
            begin
              margSeq := AllocNode(AN_ARG);
              ASTLeft[margSeq] := PyBuildKeywordDictHere;
              ASTIVal[margSeq] := 0;
              ASTRight[mlastArg] := margSeq; mlastArg := margSeq;
              mai := Procs[mpi].ParamCount;
            end;
            { `obj.m(*xs)` — a call-site UNPACK (the callee declares ordinary
              parameters; the star is on the CALL). A star is not an expression, so
              the arity loop below cannot parse it: hand the whole argument list to
              the NilPy path, which expands the list across the remaining slots. }
            if isNilPy and (mai <= Procs[mpi].ParamCount-1) and PyStarArgAhead then
              PyStarUnpackMethodArgs(mpi, mcallNode, mlastArg, mai);
            while mai <= Procs[mpi].ParamCount-1 do
            begin
              if Procs[mpi].Params[mai].IsRef or Procs[mpi].Params[mai].IsArray then
              begin
                if ByRefArgStartsExpression(ParamIsConstVariant(mpi, mai)) then
                begin
                  { non-ident by-ref/array arg (@obj.Method to a method-pointer
                    param, [..] literals, casts): parse as an expression }
                  ParseArgExpr; mexprNode := CurASTNode;
                end
                else
                begin
                  { a bare def NAME passed as a value — Python's function object }
                  mexprNode := PyMakeFuncValue;
                  if mexprNode < 0 then
                  begin
                    margIdx := FindSym(CurTok.SVal); Next;
                    mexprNode := ParseLValueAST(margIdx, TokPos - 2);
                  end;
                end;
              end
              else begin ParseArgExpr; mexprNode := CurASTNode; end;
              margSeq := AllocNode(AN_ARG); ASTLeft[margSeq] := mexprNode;
              if mlastArg = -1 then ASTLeft[mcallNode] := margSeq
              else ASTRight[mlastArg] := margSeq;
              mlastArg := margSeq;
              if (mai < Procs[mpi].ParamCount-1) and CanFillDefaultsFrom(mpi, mai+1) then
              begin
                FillDefaultArgs(mpi, mai+1, mcallNode, mlastArg);
                mai := Procs[mpi].ParamCount-1;
              end
              else if mai < Procs[mpi].ParamCount-1 then Expect(tkComma, ',')
              else if isNilPy and (CurTok.Kind = tkComma) then Next;  { Python trailing comma }
              Inc(mai);
            end;
            Expect(tkRParen, ')');
          end;
          node := mcallNode;
          Result := node; Exit;
        end;
        if UMthIsStatic[mmi] then
        begin
          { A CLASS method reached through an INSTANCE: `obj.ClassMethod(...)`. FPC
            allows it, and Self is the instance's RUNTIME class -- not the static type
            of the variable -- so it comes from __pxxRttiOf(obj), not a fixed
            AN_CLASSREF. }
          mselfArg := GenMakeRttiOfCall(node);
          GenVirtSlot := UMthVirSlot[mmi];
          mcallNode := GenMakeStaticMethodCall(mpi, mselfArg);
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
            { `obj.F()` -- EMPTY parens on a method whose parameters ALL have defaults. FPC
              accepts it (fcl-json's own suite calls `J.FormatJSON()`); without this the loop hands
              the `)` to ParseExpr and reports "expected expression". A method with NO parameters
              already worked, because the loop simply never ran. }
            if CurTok.Kind = tkRParen then
            begin
              if (Procs[mpi].ParamCount > 1) and CanFillDefaultsFrom(mpi, 1) then
                FillDefaultArgs(mpi, 1, mcallNode, mlastArg)
              { ...but EMPTY parens on a method with REQUIRED parameters is a
                missing-argument error, not a free pass. This shortcut set mai
                PAST the arity loop unconditionally, so the loop never ran, the
                required slots were never filled, and the callee read an
                UNINITIALISED frame: `c.m()` against `def m(self, a)` SEGFAULTED
                and `[1,2,3].count()` quietly returned a wrong value — the worse
                of the two. A plain NAME receiver is what reaches this route; a
                literal or constructor receiver goes through
                PyParseClassMethodCall, which already checks
                (bug-nilpy-too-few-args-to-container-method-compiles-and-segfaults).

                NOT NilPy-only: `c.M()` against `function M(a: Integer)` was
                accepted in Pascal too, where FPC rejects it.

                `*args`/`**kwargs` methods are variadic by construction and are
                exempt; the call-site star-unpack form is handled below. }
              else if (Procs[mpi].ParamCount > 1) and
                      (ProcPyStarIdx[mpi] < 0) and (ProcPyKwIdx[mpi] < 0) then
                Error(fieldName + '() requires ' +
                      AIntToStr(Procs[mpi].ParamCount - 1) +
                      ' argument(s), none given');
              mai := Procs[mpi].ParamCount;   { nothing to parse; Expect(tkRParen) consumes it }
            end;
            { `d.update(**e)` — before the star branches below, because for
              `update` a `**` is not a kwargs pack to bind: its keys ARE the
              dict to merge. The plain-keyword form is caught in the loop, and
              both go through the one builder. }
            if PyKwDictArgsHere(mpi) then
            begin
              margSeq := AllocNode(AN_ARG);
              ASTLeft[margSeq] := PyBuildKeywordDictHere;
              ASTIVal[margSeq] := 0;
              ASTRight[mlastArg] := margSeq; mlastArg := margSeq;
              mai := Procs[mpi].ParamCount;    { the argument list is complete }
            end;
            { A method with `*args` / `**kwargs` has no fixed arity, so the
              arity-driven loop below cannot parse its call. Hand the whole
              argument list to the NilPy path, which packs the surplus. }
            if isNilPy and (mai <= Procs[mpi].ParamCount-1) and
               ((ProcPyStarIdx[mpi] >= 0) or (ProcPyKwIdx[mpi] >= 0)) then
              PyParseStarMethodArgs(mpi, mcallNode, mlastArg, mai);
            { `obj.m(*xs)` — a call-site UNPACK (the callee declares ordinary
              parameters; the star is on the CALL). A star is not an expression, so
              the arity loop below cannot parse it: hand the whole argument list to
              the NilPy path, which expands the list across the remaining slots. }
            if isNilPy and (mai <= Procs[mpi].ParamCount-1) and PyStarArgAhead then
              PyStarUnpackMethodArgs(mpi, mcallNode, mlastArg, mai);
            while mai <= Procs[mpi].ParamCount-1 do
            begin
              { `d.update(a=1)` / `d.update(**e)` — the method half of the
                keywords-are-KEYS case above; same builder, so the two forms
                cannot drift. }
              mexprNode := PyKwDictArgNode(mpi);
              if mexprNode >= 0 then
              begin
                margSeq := AllocNode(AN_ARG); ASTLeft[margSeq] := mexprNode;
                ASTIVal[margSeq] := 0;                { positional, not a keyword }
                ASTRight[mlastArg] := margSeq; mlastArg := margSeq;
                Break;
              end;
              { NilPy `key=expr` on the METHOD path. Params[0] is Self, so names
                resolve from 1 up; mslot is the parameter this argument actually
                fills, which drives the by-ref / open-array decisions below. }
              mkw := PyKwArgIndex(mpi, 1);
              if mkw > 0 then mslot := mkw - 1 else mslot := mai;
              if (CurTok.Kind = tkLBrack) and ParamIsVarRecArray(mpi, mslot) then
                mexprNode := ParseVarRecLiteralAST
              else if (CurTok.Kind = tkLBrack) and ParamIsOpenArrayScalar(mpi, mslot) then
                { `[...]` open-array literal to an instance/record method
                  (r.SumAll([10,20])) — was parsed as a SET literal (b334) }
                mexprNode := ParseArrayCtorAST(Procs[mpi].Params[mslot].TypeKind,
                  ProcParamElemRowLen[mpi * MAX_PROC_PARAMS + mslot], ProcParamElemRowLo[mpi * MAX_PROC_PARAMS + mslot])
              else if Procs[mpi].Params[mslot].IsRef or Procs[mpi].Params[mslot].IsArray then
              begin
                if ByRefArgStartsExpression(ParamIsConstVariant(mpi, mslot)) then
                begin
                  { non-ident by-ref/array arg (@obj.Method to a method-pointer
                    param, [..] literals, casts): parse as an expression }
                  ParseArgExpr; mexprNode := CurASTNode;
                end
                else
                begin
                  { a bare def NAME passed as a value — Python's function object }
                  mexprNode := PyMakeFuncValue;
                  if mexprNode < 0 then
                  begin
                    margIdx := FindSym(CurTok.SVal); Next;
                    mexprNode := ParseLValueAST(margIdx, TokPos - 2);
                  end;
                end;
              end
              else
              begin
                ParseArgExpr; mexprNode := CurASTNode;
              end;
              SetLitCheckArg(mexprNode, mpi, mslot);
              margSeq := AllocNode(AN_ARG); ASTLeft[margSeq] := mexprNode;
              ASTIVal[margSeq] := mkw;
              ASTRight[mlastArg] := margSeq; mlastArg := margSeq;
              if mkw > 0 then
              begin
                { a keyword argument decouples arity from position: stop at `)`
                  and let PyBindKwArgs order the chain and fill the holes }
                if CurTok.Kind = tkRParen then Break;
                Expect(tkComma, ',');
                Inc(mai);
                Continue;
              end;
              if (mai < Procs[mpi].ParamCount-1) and CanFillDefaultsFrom(mpi, mai+1) then
              begin
                FillDefaultArgs(mpi, mai+1, mcallNode, mlastArg);
                mai := Procs[mpi].ParamCount-1;
              end
              else if mai < Procs[mpi].ParamCount-1 then
              begin
                Expect(tkComma, ',');
                { Python's TRAILING comma before the closing paren — the shape a
                  multi-line call is written in:
                      w.bind(
                          "<Configure>",
                          lambda event: ...,
                      )
                  The loop would go round once more and demand another argument.
                  Stop here instead and let the omitted parameters take their
                  defaults, exactly as an argument list that simply ended. }
                if isNilPy and (CurTok.Kind = tkRParen) then
                begin
                  if CanFillDefaultsFrom(mpi, mai+1) then
                    FillDefaultArgs(mpi, mai+1, mcallNode, mlastArg);
                  Break;
                end;
              end
              else if isNilPy and (CurTok.Kind = tkComma) then Next;  { Python trailing comma }
              Inc(mai);
            end;
            Expect(tkRParen, ')');
            mnArgs := 0;
            PyBindKwArgs(mpi, mselfArg, mlastArg, mnArgs);
            ASTLeft[mcallNode] := mselfArg;
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
      { An interface-typed value exposes ONLY the interface's (and ancestors'/
        IUnknown's) METHODS — never the implementing class's fields. A method or
        parameterless-method access already exited above (mmi>=0 / AN_INTF_CALL);
        reaching here with an interface base means the name is a field/backing
        field, which FPC rejects ("identifier idents no member"). Without this the
        fall-through built an AN_FIELD at the class field offset THROUGH the
        interface pointer and miscompiled to a SIGSEGV
        (bug-pascal-field-access-through-interface-var). }
      if (recName >= REC_UCLASS_BASE) and UClsIsInterface[recName - REC_UCLASS_BASE] then
        Error('interface has no member "' + fieldName + '" (an interface exposes only its methods)');
      { A pointer with NO pointee record has no member namespace to search: a plain
        `Pointer`, or a typed pointer to a non-record. The old fall-through built an
        AN_FIELD over it anyway, which lowered to "the pointer, at offset 0" — so
        `q.NoSuchThing` compiled and yielded the pointer itself, turning a typo into
        a silent no-op. A pointer TO a record has already been auto-dereffed above,
        and a metaclass has taken its own branch, so neither reaches here. }
      if (tk = tyPointer) and (recName = REC_NONE) then
        Error('"' + fieldName + '": a pointer has no members (dereference it with ^, or the pointee type is unknown here)');

      { Property-backed access: FPC checks the PROPERTY's visibility, and the
        backing field is read on the declaring class's behalf — a private FField
        behind a public Count property must stay accessible (test_tfplist_b259). }
      { `<designator>.Free;` — see BuiltinFreeHere. Placed immediately before the
        member check that would otherwise reject it, because Free is not a
        member of anything. }
      if BuiltinFreeHere(node, recName, fieldName, TokPos) then
      begin
        Next;                        { consume 'Free' }
        Result := GenMakeFreeObjectExpr(node, recName - REC_UCLASS_BASE);
        Exit;
      end;
      if not viaProp then
      begin
        RequireRecMember(recName, fieldName);
        EnforceFieldVis(recName, fieldName);   { --strict-visibility member access control }
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
        { NilPy: a Callable field (Word.native) may hold a pyeval closure rather
          than a compiled function address (uforth's VARIABLE/CONSTANT words).
          Branch at runtime on the 1-arg `-> None` shape. Pascal is unaffected
          (gated on isNilPy). }
        if isNilPy and (not isMethodPtr) and (argsHead2 >= 0) and
           (ASTRight[argsHead2] = -1) and (Procs[fldSigPi].RetType = tyInteger) then
          node := PyWrapClosureFieldCall(fieldNode, ASTLeft[argsHead2], callIndNode);
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
    { `obj.F()` -- EMPTY parens on a method whose parameters ALL have defaults. FPC
      accepts it (fcl-json's own suite calls `J.FormatJSON()`); without this the loop hands
      the `)` to ParseExpr and reports "expected expression". A method with NO parameters
      already worked, because the loop simply never ran. }
    if CurTok.Kind = tkRParen then
    begin
      if (Procs[mpi].ParamCount > 1) and CanFillDefaultsFrom(mpi, 1) then
        FillDefaultArgs(mpi, 1, mcallNode, mlastArg);
      mai := Procs[mpi].ParamCount;   { nothing to parse; Expect(tkRParen) consumes it }
    end;
    { `obj.m(*xs)` — a call-site UNPACK (the callee declares ordinary
      parameters; the star is on the CALL). A star is not an expression, so
      the arity loop below cannot parse it: hand the whole argument list to
      the NilPy path, which expands the list across the remaining slots. }
    if isNilPy and (mai <= Procs[mpi].ParamCount-1) and PyStarArgAhead then
      PyStarUnpackMethodArgs(mpi, mcallNode, mlastArg, mai);
    while mai <= Procs[mpi].ParamCount-1 do
    begin
      if Procs[mpi].Params[mai].IsRef or Procs[mpi].Params[mai].IsArray then
      begin
        if (CurTok.Kind = tkLBrack) and Procs[mpi].Params[mai].IsArray then
          { `[e0, e1, ...]` open-array/array-of-const literal argument
            (Exception.CreateFmt(Msg, [Data]) shape) }
          mexprNode := ParseVarRecLiteralAST
        else if ByRefArgStartsExpression(ParamIsConstVariant(mpi, mai)) then
        begin
          { non-ident / cast-lvalue by-ref arg (PChar(s)^): full expression }
          ParseArgExpr; mexprNode := CurASTNode;
        end
        else
        begin
          if CurTok.Kind <> tkIdent then Error('expected variable');
          mexprNode := PyMakeFuncValue;
          if mexprNode < 0 then
          begin
            margIdx := FindSym(CurTok.SVal); Next;
            mexprNode := ParseLValueAST(margIdx, TokPos - 2);
          end;
        end;
      end
      else
      begin
        ParseArgExpr; mexprNode := CurASTNode;
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
      else if mai < Procs[mpi].ParamCount-1 then Expect(tkComma, ',')
      else if isNilPy and (CurTok.Kind = tkComma) then Next;  { Python trailing comma }
      Inc(mai);
    end;
    Expect(tkRParen, ')');
  end;
  Result := mcallNode;
end;

{ True when the `[...]` group starting at CurTok contains any element that is NOT a
  compile-time constant -- a variable, a deref, a computed expression. Scans to the matching
  ']' without consuming anything. }
function SetLiteralHasRuntimeElement: Boolean;
var i, d, si: Integer;
begin
  Result := False;
  if CurTok.Kind <> tkLBrack then Exit;
  i := TokPos;          { first token INSIDE the bracket }
  d := 1;
  while (i < TokCount) and (d > 0) do
  begin
    if Tokens[i].Kind = tkLBrack then Inc(d)
    else if Tokens[i].Kind = tkRBrack then
    begin
      Dec(d);
      if d = 0 then Exit;
    end
    else if Tokens[i].Kind = tkIdent then
    begin
      si := FindSym(GetTokenStr(i));
      { a plain constant (including an enum value) is fine; anything else is runtime }
      if (si < 0) or (Syms[si].Kind <> skConst) then
      begin
        Result := True;
        Exit;
      end;
    end
    else if not (Tokens[i].Kind in [tkInteger, tkString, tkComma, tkDotDot]) then
    begin
      { a deref, a call, an operator -- not a constant element }
      Result := True;
      Exit;
    end;
    Inc(i);
  end;
end;

function ParseSetMembershipAST(leftExpr: Integer): Integer;
var node, argNode, lastArg, loVal, hiVal, itemNode: Integer; done: Boolean;
begin
  { `x in [#0, C]` where C is a VARIABLE (fcl-json's scanner scans a string with
    `FTokenStr^ in [#0, C]`, C being the active quote character). The constant-only path
    below cannot express that -- it folds every element to an AN_INT_LIT.

    But a set LITERAL already supports runtime elements (ParseSetLiteralAST builds the mask at
    runtime), and `x in <set value>` already works as an ordinary AN_BINOP. So a runtime
    literal simply routes through those two, and the all-constant case keeps its baked-blob
    fast path untouched -- which matters, because that path is what the self-host binary
    depends on being byte-identical. }
  if SetLiteralHasRuntimeElement then
  begin
    node := AllocNode(AN_BINOP);
    ASTIVal[node] := Ord(tkIn);
    ASTLeft[node] := leftExpr;
    ASTRight[node] := ParseSetLiteralAST;
    ASTTk[node] := Ord(tyBoolean);
    { `x in [...]`: the target element type is the LEFT operand's, which is
      already known here — no plumbing needed for this arm. }
    SetLitCheckAgainst(NodeEnumIdOf(leftExpr));
    Result := node;
    Exit;
  end;

  node := AllocNode(AN_CALL);
  ASTIVal[node] := -SPECIAL_IN;
  { `x in [consts]` is a BOOLEAN. This node carried no type at all, so it defaulted to
    tyUnknown and was treated as an integer: `writeln(e in [a,b])` printed 1 instead of TRUE,
    and `(e in [a,b]) and (ch in ['a'..'z'])` did a BITWISE and of two booleans -- numerically
    right only because the operands happen to be 0/1. The runtime-set path (an ordinary binop)
    has always been typed tyBoolean, so the same expression behaved differently depending on
    which path it took. }
  ASTTk[node] := Ord(tyBoolean);

  argNode := AllocNode(AN_ARG);
  ASTLeft[argNode] := leftExpr;
  ASTLeft[node] := argNode;
  lastArg := argNode;

  Expect(tkLBrack, '[');
  SetLitBegin;
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
  SetLitCheckAgainst(NodeEnumIdOf(leftExpr));
  LastExprTk := tyBoolean;
  Result := node;
end;

function ParseSetElementAST: Integer;
{ One set-literal element. A compile-time constant (integer / 1-char string /
  const identifier — exactly what ParseSetConst accepts) folds to an AN_INT_LIT
  so an all-constant literal keeps the baked-blob fast path (byte-identical).
  Anything else (a variable, a computed expression) is parsed as a full
  expression for a runtime element; the lowering then builds the set at runtime
  with Include/range loops. }
var n, sci, savEnum: Integer; savMixed, savPlain: Boolean;
begin
  if CurTok.Kind = tkInteger then
  begin
    n := AllocNode(AN_INT_LIT); ASTIVal[n] := CurTok.IVal; ASTTk[n] := Ord(tyInteger); Next;
    SetLitNoteElem(-1);
    Result := n;
  end
  else if CurTok.Kind = tkString then
  begin
    if Length(CurTok.SVal) <> 1 then Error('set item must be one character');
    n := AllocNode(AN_INT_LIT); ASTIVal[n] := Ord(CurTok.SVal[1]); ASTTk[n] := Ord(tyChar); Next;
    SetLitNoteElem(-1);
    Result := n;
  end
  else if (CurTok.Kind = tkIdent) and (FindSym(CurTok.SVal) >= 0) and
          (Syms[FindSym(CurTok.SVal)].Kind = skConst) then
  begin
    sci := FindSym(CurTok.SVal);
    n := AllocNode(AN_INT_LIT); ASTIVal[n] := Syms[sci].ConstVal; ASTTk[n] := Ord(Syms[sci].TypeKind);
    ASTEnumId[n] := SymEnumId[sci];
    Next;
    SetLitNoteElem(sci);
    Result := n;
  end
  else
  begin
    { Runtime element: a variable or an arbitrary expression. The expression may
      itself contain a `[...]`, whose tally must not overwrite ours. }
    savEnum := SetLitEnumId; savMixed := SetLitMixed; savPlain := SetLitHasPlain;
    ParseExpr;
    SetLitEnumId := savEnum; SetLitMixed := savMixed; SetLitHasPlain := savPlain;
    { An enum-typed expression carries its identity on the symbol, so it can be
      tallied exactly. A BOOLEAN one can be tallied as plain: an enum-typed
      variable is tyInteger here, never tyBoolean, so this cannot mistake one
      for the other -- and `True` reaches this branch rather than the const-ident
      one above, which is why it was the row that still slipped through.
      Anything else stays untallied: a bare ordinal variable is indistinguishable
      from an enum-typed one at this level, and a missed diagnostic is a smaller
      failure than a wrong one. }
    if NodeEnumIdOf(CurASTNode) >= 0 then
      SetLitNoteEnum(NodeEnumIdOf(CurASTNode))
    else if (CurASTNode >= 0) and (IntToTypeKind(ASTTk[CurASTNode]) = tyBoolean) then
      SetLitHasPlain := True;
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
  SetLitBegin;
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
  { Needs no target, so it fires HERE rather than at a binding site -- which is
    what makes it reach the contexts the target-driven check cannot, notably an
    assignment to a set variable. }
  if SetLitMixed then
    Error('set literal mixes elements from two different enum types');
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

function ParamIsVarRecArrayAt(procIdx, argNo: Integer): Boolean;
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

function ParamIsVarRecArray(procIdx, argNo: Integer): Boolean;
{ ...asked of the whole visible OVERLOAD SET, not just the candidate the name
  happened to resolve to first.

  This decision is made BEFORE overload resolution — the parser has to know
  whether `[...]` is a TVarRec vector or a set literal in order to parse it at
  all — so asking only the first candidate made the answer depend on which unit
  came first in the uses clause. With two units both exporting `g`, one taking
  `array of const`, putting THAT unit last made `g('%s', ['a'])` fail with

      argument types: (ShortString, set)
      candidates: g(Variant, AnsiString)
                  g(AnsiString, record)

  — both candidates found, so the merge was fine; the literal had simply
  already been parsed as a set and could no longer match. The failure looked
  like the call was wrong when nothing was.

  A SET parameter anywhere at this slot vetoes it: then `[...]` really may be a
  set, and guessing the other way would break a working call to buy this one.
  Nothing in the tree has an overload set that mixes the two, so the veto costs
  nothing today and keeps the rule honest.
  bug-a-array-of-const-literal-does-not-match-in-a-cross-unit-overload-set }
var i: Integer; hasVarRec, hasSet: Boolean;
begin
  Result := ParamIsVarRecArrayAt(procIdx, argNo);
  if Result or (procIdx < 0) or not ProcOverloadDirective[procIdx] then Exit;
  hasVarRec := False;
  hasSet := False;
  i := ProcChainHead(Procs[procIdx].Name);
  while i >= 0 do
  begin
    if ParamIsVarRecArrayAt(i, argNo) then hasVarRec := True
    else if (argNo >= 0) and (argNo < Procs[i].ParamCount) and
            (not Procs[i].Params[argNo].IsArray) and
            (Procs[i].Params[argNo].TypeKind = tySet) then hasSet := True;
    i := ProcHashNext[i];
  end;
  Result := hasVarRec and not hasSet;
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

function ParseArrayCtorAST(elemTk: TTypeKind; rowLen, rowLo: Integer): Integer;
{ `[ e0, e1, ... ]` for an `array of T` (scalar/string) parameter. Builds an
  AN_ARRAY_CTOR whose Left is the element AN_ARG chain; ASTIVal/ASTTk carry the
  element type so overload matching binds it to the open-array param (whose
  TypeKind is the element type). Lowering builds a heap dyn-array temp.
  rowLen/rowLo (ASTSOffset/ASTSLen): the param's fixed-array ROW element shape
  (`array of T`, T a named fixed array) — 0 for a scalar element; drives the
  temp's row stride and per-element row-copy in the lowering. }
var node, argNode, lastArg: Integer; done: Boolean;
begin
  node := AllocNode(AN_ARRAY_CTOR);
  ASTIVal[node] := Ord(elemTk);
  ASTTk[node]   := Ord(elemTk);
  ASTSOffset[node] := rowLen;
  ASTSLen[node]    := rowLo;
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
    else if HiddenByForwardOrder(name) then
      Error('routine used before its declaration — define it above, or add a forward; declaration (--strict/require-forward)')
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
    else if HiddenByForwardOrder(name) then
      Error('routine used before its declaration — define it above, or add a forward; declaration (--strict/require-forward)')
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
  mmi := FindUMethOverloadAhead(parentCi, name, CountCallArgsAhead);
  if mmi < 0 then Error('inherited method not found: ' + name);
  EnforceMethVis(mmi, name);
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
var crBlob, crNode: Integer;   { class-reference ops on a chained value }
var dfCi, dfPri, dfMmi, dfMpi, dfI, dfSelf, dfIdxHead, dfIdxTail: Integer;   { default property on a chained value }
    dfName: AnsiString;
var sub, prevTok: Integer; fieldName, accName: AnsiString; tk: TTypeKind;
    ci, mmi, mpi, callN, selfArg, lastA, aSeq, aNode, aIdx, mai: Integer;
    pri, i, w, margIdx: Integer; isAssign: Boolean;
    cvIdx: Integer;
begin
  { NilPy has its OWN copy of this routine (PyParseClassRecordSelectors,
    pyparser.inc), split out 2026-08-09 by
    task-a-carve-nilpy-selectors-out-of-parser-inc. Everything below is the
    PASCAL selector parser; the dialect forks that used to be interleaved here
    live over there with their guards folded away. Keep it that way — a NilPy
    fix belongs in the twin, not in a new `if PyExprMode` arm here. }
  if PyExprMode then
  begin
    Result := PyParseClassRecordSelectors(node, recId, outTk);
    Exit;
  end;
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

      ci := -1;
      if recId >= REC_UCLASS_BASE then ci := recId - REC_UCLASS_BASE;

      { The class-reference OPERATIONS on a chained value: `(Data as TJSONArray).ClassType`,
        `(b as TD).ClassName`. They are not methods, so the method path below never matched --
        and a pointer accepts any member name silently, so the selector was simply DROPPED and
        the expression evaluated to the object pointer. It printed a number where a class name
        was expected, with no error at all.

        An INSTANCE reaches its blob through AN_RTTIOF; a class REFERENCE is the blob. A real
        member of that name on the class still wins. }
      if (ci >= 0) and (CurTok.Kind = tkIdent) and IsClassRefOpName(fieldName) and
         (FindUMeth(ci, fieldName) < 0) and (FindUField(ci, fieldName) < 0) and
         (not UClsIsRecord[ci]) then
      begin
        crBlob := GenMakeRttiOfCall(node);
        if crBlob >= 0 then
        begin
          Next;                          { consume the operation name }
          crNode := GenMakeClassRefOp(crBlob, fieldName, outTk);
          if crNode >= 0 then
          begin
            node := ParseClassRefOpTail(crNode, outTk);
            recId := REC_NONE;
            Continue;
          end;
        end;
      end;

      { Method call on the value: `.M(args)` (or 0-arg `.M`). Checked before the
        field path so a method name isn't mistaken for a field. Mirrors the
        instance-method arg parsing (ref/array params taken by lvalue). Self =
        the current node; virtual methods dispatch dynamically on the real object
        (a hard cast doesn't change the dynamic type). }

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
            if UPropIsIndexed[pri] then ParsePropIndexArgs(margIdx, lastA)
            else PropIndexConstArg(pri, margIdx, lastA);
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
            if UPropIsIndexed[pri] then ParsePropIndexArgs(margIdx, lastA)
            else PropIndexConstArg(pri, margIdx, lastA);
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
      if ci >= 0 then mmi := FindUMethOverloadAhead(ci, fieldName, CountCallArgsAhead);
      if mmi >= 0 then
      begin
        EnforceMethVis(mmi, fieldName);
        mpi := UMthProc_[mmi];
        { NilPy: `<expr>.method` with NO following call is a BOUND-METHOD VALUE,
          exactly as ParseLValueAST treats `name.method`. That was the ONLY site
          building one, so the value form worked only when the receiver was a
          bare identifier: `C().m`, `objs[0].m`, `a.b.m` — every receiver that
          reaches the selector path instead — fell through to the call path and
          yielded a bare code address with no receiver, which SEGFAULTED when
          called (bug-nilpy-bound-method-of-a-temporary-receiver-segfaults).

          The same bare-vs-selector split that hid a class-attribute read
          through a non-bare receiver, in this same routine. Two paths for one
          construct, and the second one stays broken —
          devdocs/dev/normalise-dont-special-case.md.

          A TEMPORARY receiver survives because the pair RETAINS it
          (pybound_new), so `C().m` keeps its instance alive for the pair's
          lifetime rather than reading a freed block. }
        if NilPyUserCode and
           (TokPos < TokCount) and (Tokens[TokPos].Kind <> tkLParen) and
           (ci >= 0) and not UClsIsInterface[ci] then
        begin
          Next;                                  { consume the method name }
          node := PyMakeBoundMethod(mpi, node);
          ASTTk[node] := Ord(tyVariant);
          outTk := tyVariant;
          Result := node;
          Exit;
        end;
        if (ci >= 0) and UClsIsInterface[ci] then
        begin
          { INTERFACE receiver reached through a chained value — `IFoo(List[i]).M`,
            `(x as IFoo).M`. Must dispatch through the IMT slot like the
            ParseLValueAST path does: an interface method's proc is a body-less
            SIGNATURE, so building a plain AN_CALL to it called address 0. }
          callN := AllocNode(AN_INTF_CALL);
          ASTRight[callN] := node;                  { the interface value }
          ASTIVal[callN] := mpi;                    { signature proc (marshalling) }
          ASTSOffset[callN] := UMthVirSlot[mmi];    { IMT slot }
          ASTTk[callN] := Ord(Procs[mpi].RetType);
          lastA := -1;
          Next; { consume method name }
          if CurTok.Kind = tkLParen then
          begin
            Next;
            mai := 1;   { param 0 = Self, supplied by the interface value }
            while CurTok.Kind <> tkRParen do
            begin
              ParseArgExpr; aNode := CurASTNode;
              aSeq := AllocNode(AN_ARG); ASTLeft[aSeq] := aNode;
              if lastA = -1 then ASTLeft[callN] := aSeq else ASTRight[lastA] := aSeq;
              lastA := aSeq;
              Inc(mai);
              if CurTok.Kind = tkComma then Next
              else if CurTok.Kind <> tkRParen then Error('expected comma or close parenthesis');
            end;
            Expect(tkRParen, ')');
          end;
          outTk := Procs[mpi].RetType;
          tk := outTk;
          recId := ProcRetRecId[mpi];
          if (tk <> tyClass) and (tk <> tyRecord) then recId := REC_NONE;
          node := callN;
          Continue;
        end;
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
          { `obj.F()` -- EMPTY parens on a method whose parameters ALL have defaults. FPC
            accepts it (fcl-json's own suite calls `J.FormatJSON()`); without this the loop hands
            the `)` to ParseExpr and reports "expected expression". A method with NO parameters
            already worked, because the loop simply never ran. }
          if CurTok.Kind = tkRParen then
          begin
            if (Procs[mpi].ParamCount > 1) and CanFillDefaultsFrom(mpi, 1) then
              FillDefaultArgs(mpi, 1, callN, lastA);
            mai := Procs[mpi].ParamCount;   { nothing to parse; Expect(tkRParen) consumes it }
          end;
          while mai <= Procs[mpi].ParamCount - 1 do
          begin
            if (CurTok.Kind = tkLBrack) and ParamIsVarRecArray(mpi, mai) then
            begin
              { `[...]` array-of-const literal to a method reached through a
                value/selector chain — same as the plain-call path (b287) }
              aNode := ParseVarRecLiteralAST;
            end
            else if (CurTok.Kind = tkLBrack) and ParamIsOpenArrayScalar(mpi, mai) then
            begin
              { `[...]` open-array literal (r.SumAll([10,20]) on a record
                method) — was parsed as a SET literal and crashed (b334) }
              aNode := ParseArrayCtorAST(Procs[mpi].Params[mai].TypeKind,
                ProcParamElemRowLen[mpi * MAX_PROC_PARAMS + mai], ProcParamElemRowLo[mpi * MAX_PROC_PARAMS + mai]);
            end
            else if Procs[mpi].Params[mai].IsRef or Procs[mpi].Params[mai].IsArray then
            begin
              if ByRefArgStartsExpression(ParamIsConstVariant(mpi, mai)) then
              begin
                { non-ident by-ref/array arg (@obj.Method to a method-pointer
                  param, [..] literals, casts): parse as an expression }
                ParseArgExpr; aNode := CurASTNode;
              end
              else
              begin
                aIdx := FindSym(CurTok.SVal); Next;
                aNode := ParseLValueAST(aIdx, TokPos - 2);
              end;
            end
            else
            begin
              ParseArgExpr; aNode := CurASTNode;
            end;
            aSeq := AllocNode(AN_ARG); ASTLeft[aSeq] := aNode;
            ASTRight[lastA] := aSeq; lastA := aSeq;
            if (mai < Procs[mpi].ParamCount-1) and CanFillDefaultsFrom(mpi, mai+1) then
            begin
              FillDefaultArgs(mpi, mai+1, callN, lastA);
              mai := Procs[mpi].ParamCount-1;
            end
            else if mai < Procs[mpi].ParamCount-1 then Expect(tkComma, ',')
            else if isNilPy and (CurTok.Kind = tkComma) then Next;  { Python trailing comma }
            Inc(mai);
          end;
          Expect(tkRParen, ')');
        end;
        tk := Procs[mpi].RetType;
        if (tk = tyClass) or (tk = tyRecord) then recId := ProcRetRecId[mpi]
        else recId := REC_NONE;
        node := callN;
        { A method whose result is a STRING (e.g. bytes.decode) may be followed
          by str methods — `bytes(b).decode("latin-1").upper()`. The generic
          selector loop cannot resolve `.upper` (the result is not a class), so
          chain them here, exactly as ParseFactor does for a call result. }
        while isNilPy and PyIsStrBaseTk(tk) and (CurTok.Kind = tkDot) and
              (TokPos < TokCount) and (Tokens[TokPos].Kind = tkIdent) and
              (TokPos + 1 < TokCount) and (Tokens[TokPos + 1].Kind = tkLParen) do
        begin
          Next;                          { consume '.'; CurTok = method name }
          prevTok := TokPos - 1;
          Next;                          { consume the name; CurTok = '(' }
          node := PyParseStrMethod(node, GetTokenStr(prevTok));
          tk := IntToTypeKind(ASTTk[node]);
          recId := REC_NONE;
        end;
        outTk := tk;
        Continue;
      end;

      { `(o as T).Free;` and friends — see BuiltinFreeHere. Same reason and same
        guard as the ParseLValueAST site; this is the path a `(`-led statement
        takes. }
      if BuiltinFreeHere(node, recId, fieldName, TokPos) then
      begin
        Next;                        { consume 'Free' }
        outTk := tyInteger;
        Result := GenMakeFreeObjectExpr(node, recId - REC_UCLASS_BASE);
        Exit;
      end;
      { Class variable / class ATTRIBUTE reached through a NON-BARE receiver —
        the same fall-through the bare-identifier path already does in
        ParseFactor ("class variable accessed via an instance"). A class-written
        class attribute has no instance field BY CONSTRUCTION (it is one shared
        slot), so without this arm `Base(1).made` reaches RequireRecMember and
        dies as "no such member" while `b.made` on the very same object works —
        the sibling arm of a double case (normalise-dont-special-case.md). }
      if (recId >= REC_UCLASS_BASE) and
         (FindUField(recId - REC_UCLASS_BASE, fieldName) < 0) then
      begin
        { An attribute that instances ALSO write needs the per-instance override
          fall-through, not the bare slot — same precedence as the ParseFactor
          site, where this branch sits ahead of the plain class-var one. Reading
          the slot directly here would ignore an override that `self.attr = x`
          in a constructor had just created. }
        cvIdx := PyClsAttrOvrSlot(recId - REC_UCLASS_BASE, fieldName);
        if cvIdx >= 0 then
        begin
          Next;                        { consume the field name }
          node := PyClsAttrOvrGet(node, fieldName, cvIdx);
          tk := tyVariant;
          recId := REC_NONE;
          outTk := tk;
          Continue;
        end;
        cvIdx := FindClassVar(recId - REC_UCLASS_BASE, fieldName);
        if cvIdx >= 0 then
        begin
          sub := AllocNode(AN_IDENT);
          ASTIVal[sub] := cvIdx;
          ASTTk[sub] := Ord(Syms[cvIdx].TypeKind);
          tk := Syms[cvIdx].TypeKind;
          recId := REC_NONE;
          Next;                        { consume the field name }
          node := sub;
          outTk := tk;
          Continue;
        end;
      end;
      RequireRecMember(recId, fieldName);
      sub := AllocNode(AN_FIELD);
      ASTLeft[sub] := node;
      ASTSOffset[sub] := Tokens[prevTok].SOffset;
      ASTSLen[sub] := Tokens[prevTok].SLen;
      EnforceFieldVis(recId, fieldName);   { --strict-visibility member access control }
      tk := RecFieldType(recId, fieldName);
      recId := RecFieldRecId(recId, fieldName);
      ASTTk[sub] := Ord(tk);
      Next;
      node := sub;
    end
    else { tkLBrack — a DEFAULT PROPERTY on a class value, else index the array just selected }
    begin
      { `(Data as TJSONArray)[0]` (fcl-json's suite), `obj.Child[i]`. A class value with a
        DEFAULT property means the getter, not an array index -- and building a raw AN_INDEX
        over it left the base (an as-cast, say) with no address to take, which surfaced as
        "IR_UNSUPPORTED: could not lower AST node". ParseLValueAST's suffix loop has always
        dispatched this; the chained loop never did. }
      dfCi := -1;
      if (tk = tyClass) and (recId >= REC_UCLASS_BASE) then dfCi := recId - REC_UCLASS_BASE;
      dfPri := -1;
      if dfCi >= 0 then dfPri := FindDefaultProp(dfCi);
      if (dfPri >= 0) and (UPropReadMLen[dfPri] > 0) then
      begin
        dfName := '';
        for dfI := 0 to UPropReadMLen[dfPri] - 1 do
          AppendChar(dfName, TokChars[UPropReadMOff[dfPri] + dfI]);
        dfMmi := FindUMeth(dfCi, dfName);
        if dfMmi < 0 then Error('default property getter not found: ' + dfName);
        dfMpi := UMthProc_[dfMmi];

        dfIdxHead := -1; dfIdxTail := -1;
        ParsePropIndexArgs(dfIdxHead, dfIdxTail);   { consumes [ .. ] }

        if UMthVirSlot[dfMmi] >= 0 then
        begin
          sub := AllocNode(AN_VIRTUAL_CALL);
          ASTRight[sub] := UMthVirSlot[dfMmi];
        end
        else
          sub := AllocNode(AN_CALL);
        ASTIVal[sub] := dfMpi;
        ASTTk[sub] := Ord(Procs[dfMpi].RetType);
        dfSelf := AllocNode(AN_ARG);
        ASTLeft[dfSelf] := node;
        ASTLeft[sub] := dfSelf;
        ASTRight[dfSelf] := dfIdxHead;       { self, index... }

        node := sub;
        tk := Procs[dfMpi].RetType;
        if (tk = tyClass) or (tk = tyRecord) then recId := ProcRetRecId[dfMpi]
        else recId := REC_NONE;
        Continue;
      end;

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

function ParseMetaclassMemberTail(node, mcCi: Integer; var outTk: TTypeKind;
                                  var outRec: Integer; var finished: Boolean): Integer;
{ One member access on a METACLASS VALUE (`class of T`), whatever the receiver is
  spelled as -- NodeMetaclassCi answers that, this answers what may follow it.
  CurTok is on the member NAME, the `.` already eaten by the caller.

  Returns the new node, or -1 having consumed NOTHING when the name is not a
  member this can serve (so a caller with further options can fall through, and
  one without can raise its own diagnostic). `finished` says the chain is
  complete -- the class-reference-operation tail consumes its own suffixes -- as
  opposed to a value the caller may keep applying selectors to.

  There were three copies of this: ParseLValueAST's suffix loop,
  ApplyCallResultPtrSuffix, and pyparser's twin, and the cast-deref chains had
  NONE, which is how `PRec(q)^.cr.Get(3)` came out as a plain AN_FIELD and
  evaluated to the class reference instead of calling the method -- the exact
  shape rtl-generics needs for `PPVmt(Self)^.__ClassRef.GetHashList(...)`.
  One resolver, not a fourth partial copy:
  devdocs/dev/normalise-dont-special-case.md.
  bug-pascal-record-cast-chain-drops-method-call }
var
  fieldName: AnsiString;
  mmi, mpi, mcallNode: Integer;
begin
  Result   := -1;
  finished := False;
  outRec   := REC_NONE;
  if CurTok.Kind <> tkIdent then Exit;
  fieldName := GetTokenStr(TokPos - 1);

  mmi := FindUMethOverloadAhead(mcCi, fieldName, CountCallArgsAhead);
  if mmi < 0 then mmi := FindUMeth(mcCi, fieldName);

  { a real member of that name outranks a class-reference operation }
  if (mmi < 0) and IsClassRefOpName(fieldName) then
  begin
    Next;                            { consume the operation name }
    mcallNode := GenMakeClassRefOp(node, fieldName, outTk);
    if mcallNode < 0 then
      Error('unknown class-reference operation: ' + fieldName);
    Result   := ParseClassRefOpTail(mcallNode, outTk);
    finished := True;
    Exit;
  end;
  if mmi < 0 then Exit;

  { ANY constructor, not just one spelled `Create` -- FPC names them freely, and
    UMthIsCtor is what actually marks one. }
  if UMthIsCtor[mmi] then
  begin
    EnforceMethVis(mmi, fieldName);
    Next;                            { consume the constructor name }
    Result := BuildMetaclassNew(node, mcCi, mmi);
    outTk  := tyClass;
    outRec := REC_UCLASS_BASE + mcCi;
    Exit;
  end;

  { A class method: Self is a real argument, so passing the metaclass VALUE makes
    the dispatch dynamic for free. }
  if UMthIsStatic[mmi] and (UMthProc_[mmi] >= 0) then
  begin
    mpi := UMthProc_[mmi];
    Next;                            { consume the method name }
    GenVirtSlot := UMthVirSlot[mmi];
    Result := GenMakeStaticMethodCall(mpi, node);
    outTk  := Procs[mpi].RetType;
    outRec := ProcRetRecId[mpi];
    if (outTk <> tyClass) and (outTk <> tyRecord) then outRec := REC_NONE;
    Exit;
  end;
  { an INSTANCE method: found, but not callable this way -- -1, caller diagnoses }
end;

procedure ApplyCallResultPtrSuffix(node, procIdx: Integer);
var tk: TTypeKind; elemTk, elemRec, recId, sub, prevTok, tmpN: Integer; fieldName: AnsiString;
    mcCi, mmi, mpi, mcallNode: Integer; mcFin: Boolean;
    arrAi, tmpSym, ndD, nIdx: Integer; isND: Boolean;
begin
  tk := Procs[procIdx].RetType;
  recId := REC_NONE;
  elemTk := ProcRetPtrElemTk[procIdx];
  elemRec := ProcRetPtrElemRec[procIdx];

  { A METACLASS-returning function is a RECEIVER, not a pointer whose fields you
    walk: `Give.Kind`, `Give.ClassName`, `Give.Create`. The pointer walk below
    would build an AN_FIELD over a class reference — which lowering cannot
    lower, so the user saw `IR_UNSUPPORTED ... would miscompile` rather than a
    diagnostic. Same three member kinds ParseLValueAST's metaclass arm handles,
    through the same builders; NodeMetaclassCi is the shared test.
    bug-a-a-metaclass-returned-from-a-function-is-not-a-receiver }
  mcCi := NodeMetaclassCi(node);
  if (mcCi >= 0) and (CurTok.Kind = tkDot) then
  begin
    Next;
    if CurTok.Kind <> tkIdent then Error('expected member name after .');
    prevTok := TokPos - 1;
    fieldName := GetTokenStr(prevTok);
    mcallNode := ParseMetaclassMemberTail(node, mcCi, tk, recId, mcFin);
    if mcallNode < 0 then
    begin
      if FindUMeth(mcCi, fieldName) >= 0 then
        Error('an INSTANCE method cannot be called through a class reference: '
              + fieldName);
      Error('unknown member on a class reference: ' + fieldName);
    end;
    CurASTNode := mcallNode;
    LastExprTk := tk;
    Exit;
  end;

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
        RequireRecMember(recId, fieldName);
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
  else if PyExprMode and (tk = tyAnsiString) and (CurTok.Kind = tkLBrack) then
  begin
    { NilPy indexes a str-returning call the same way it indexes a NAMED str:
      0-based, negative from the end, and slices allowed. It used to fall into
      the Pascal arm below, whose AN_INDEX is 1-BASED with neither — so
      `f()[1]` yielded character 0, `f()[-1]` yielded nothing, and `f()[1:2]`
      did not compile. Silent, and `f()[0]` was "correct", which is how it
      survived (bug-nilpy-subscript-of-a-call-result-ignores-the-index).

      No hidden temp is needed on this path: pystr_at and the slice builder take
      the string as an ARGUMENT, so the call is evaluated exactly once by
      construction — which is also the property the Pascal arm needs its temp
      for. }
    if PySliceBracketAt(TokPos - 1) then
    begin
      Next;
      if CurTok.Kind = tkColon then
        node := PyParseSliceTail(node, -1)
      else
      begin
        PyParseBoolExpr;
        node := PyParseSliceTail(node, CurASTNode);
      end;
      tk := IntToTypeKind(ASTTk[node]);
    end
    else
    begin
      Next;
      PyParseBoolExpr;
      node := PyMakeStrIndex(node, CurASTNode);
      Expect(tkRBrack, ']');
      tk := tyAnsiString;   { a 1-character str — see PyMakeStrIndex }
    end;
  end
  else if (tk = tyAnsiString) and (CurTok.Kind = tkLBrack) then
  begin
    { Index a STRING-returning call: `Uppercase(s)[2]` (ftpsend's permission
      chars). AN_INDEX needs an addressable base, so materialise the result
      into a hidden temp first and yield `(tmp := call, tmp[i])` via AN_COMMA
      (evaluate-left-yield-right). PASCAL ONLY — the NilPy arm above handles
      that dialect's 0-based/negative/slice semantics. }
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
  else if ((tk = tyClass) or (tk = tyRecord)) and (CurTok.Kind in [tkDot, tkLBrack]) and
          not ((CurTok.Kind = tkLBrack) and
               (ProcRetIsDynArray[procIdx] or (ProcRetFixedArrBytes[procIdx] > 0))) then
    { Member access on a class/record-returning call result: f(args).field[…].
      An ARRAY-of-record result reaching a `[` is NOT this case and is excluded:
      Procs[].RetType carries the ELEMENT kind, so `MkR[1].a` used to read as a
      record here by accident. It happened to work 1-D and could not work N-D --
      this arm consumes one subscript, so `MkR2[i,j].a` died as `unexpected
      token`. What decides the arm is whether the RESULT is an array, not what
      its elements happen to be; the element kind is then just the tail the
      shared arm hands back to these same selectors. }
    node := ParseClassRecordSelectors(node, ProcRetRecId[procIdx], tk)
  else if ((ProcRetFixedArrBytes[procIdx] > 0) or ProcRetIsDynArray[procIdx]) and
          (CurTok.Kind = tkLBrack) then
    { Indexing an ARRAY-returning call directly, `MkArr[1]`, when the element is
      not a record. The record-element spelling arrives through the arm above
      (Procs[].RetType is the ELEMENT kind, so an array OF RECORDS reads as
      tyRecord there) and works; this one has no addressable base to index —
      lowering answers IR_UNSUPPORTED — and reached the statement parser as a
      stray `[`, i.e. `unexpected token` pointing at the wrong place.
      Say what is actually unsupported instead. Making it WORK means
      materialising the result into a hidden temp shaped like the array and
      indexing that, the way the AnsiString arm above already does with
      AN_COMMA — which also brings the N-D spelling `MkArr2[i,j]` with it,
      since a shaped temp carries the dim spans.
      bug-a-indexing-a-function-call-result-drops-the-field-selector }
  begin
    { Index a FIXED-array-returning call directly: `MkArr[i]`, `MkArr2[i,j]`.
      Same move as the AnsiString arm above -- AN_INDEX needs an ADDRESSABLE
      base, so materialise the result into a hidden temp and yield
      `(tmp := call, tmp[i])` via AN_COMMA, which also evaluates the call
      exactly once.

      The temp is SHAPED like the array rather than merely sized like it:
      AllocArray over the type's flattened bounds plus the SymArrNDims /
      SymArrDimLo / SymArrDimSpan stamp, exactly as the callee's own Result
      slot is built. That is what makes NodeArrNDInfo recognise it below, so
      the N-D spelling comes for free instead of needing an arm of its own --
      and it is why this needed ProcRetArrAi: ProcRetFixedArrBytes is a byte
      count, which can size a temp but cannot shape one.

      DYNAMIC-array results are still refused. The ticket's open question: a dyn
      result is a heap handle with an ownership story, not a value copied into a
      temp, so the temp would have to own its reference and release at scope
      exit. Refusing beats guessing at a lifetime.
      feature-a-index-an-array-returning-call-directly
      compat-pascal-index-a-function-call-result }
    { A DYNAMIC-array result is still refused, and the reason is now MEASURED
      rather than assumed. The temp itself is fine: AllocDynArray in the
      enclosing scope gets the ordinary dyn-array release (200k iterations of
      `acc := acc + Make[1]` hold RSS flat at 264kB). What is not fine is the
      OTHER end -- IRLowerAddress must answer the address of a SLOT HOLDING the
      handle, and a dyn-array call's IR value is the handle itself. Letting that
      call through the aggregate arm there makes the index path read the handle
      as if it were the slot: `TBag.Create.Arr[0]` printed 25769803781, which is
      0x600000005 -- elements 0 and 1 as one 8-byte word. A SILENT wrong value
      where there had been a loud refusal.
      Materialising a temp inside IRLowerAddress fixes both spellings and leaks
      one array per call, because that temp has no owner and no scope. The real
      shape is to route every call-result suffix through THIS procedure so there
      is one materialisation point with one lifetime story -- the ~20 mcallNode
      sites in ParseFactorCore each index a call node on their own today, which
      is also why `b.Arr[1]` is refused by the PINNED compiler despite the
      ticket recording it as working.
      Banked in compat-pascal-index-a-function-call-result with the measurement. }
    if ProcRetIsDynArray[procIdx] or (ProcRetArrAi[procIdx] < 0) then
      Error('cannot index the result of an array-returning function directly — '
            + 'assign it to a variable first');
    arrAi := ProcRetArrAi[procIdx];
    { Take the element type from the ArrType entry, NOT from Procs[].RetType.
      They usually agree -- RetType IS the element kind for an array result --
      but the alias is the authority on a FROZEN-STRING element's width, and
      going through RetType lost it: `array[0..2] of string[8]` indexed off the
      call printed 3, the length byte, where FPC prints `mid`. Same source the
      variable-declaration path reads for exactly this reason. }
    tk := IntToTypeKind(ArrTypeElemTk[arrAi]);
    LastTypeRecId := ArrTypeElemRec[arrAi];
    LastTypePointerElemRec := ArrTypePtrElemRec[arrAi];
    if (tk = tyFixedString) or (tk = tyShortString) then
      LastTypeStrCap := ArrTypeElemStrCap[arrAi];
    tmpSym := AllocArray('', tk, ArrTypeLo[arrAi], ArrTypeHi[arrAi]);
    if ArrTypeNDims[arrAi] >= 2 then
    begin
      SymArrNDims[tmpSym] := ArrTypeNDims[arrAi];
      for ndD := 0 to ArrTypeNDims[arrAi] - 1 do
      begin
        SymArrDimLo[tmpSym * MAX_ARR_DIMS + ndD]   := ArrTypeDimLo[arrAi * MAX_ARR_DIMS + ndD];
        SymArrDimSpan[tmpSym * MAX_ARR_DIMS + ndD] := ArrTypeDimSpan[arrAi * MAX_ARR_DIMS + ndD];
      end;
    end;
    SymSyncTypeRef(tmpSym);
    { the side-effect leg: tmp := call }
    tmpN := AllocNode(AN_IDENT);
    ASTIVal[tmpN] := tmpSym;
    ASTTk[tmpN] := Ord(tk);
    sub := AllocNode(AN_ASSIGN);
    ASTLeft[sub] := tmpN;
    ASTRight[sub] := node;
    node := sub;
    { the value leg: tmp[i] / tmp[i,j] / tmp[i][j] }
    tmpN := AllocNode(AN_IDENT);
    ASTIVal[tmpN] := tmpSym;
    ASTTk[tmpN] := Ord(tk);
    sub := AllocNode(AN_INDEX);
    ASTLeft[sub] := tmpN;
    Next;                                   { the '[' }
    ParseExpr;
    isND := NodeArrNDInfo(tmpN);
    if isND and (CurTok.Kind = tkComma) then
    begin
      NDIdxNode[0] := CurASTNode; nIdx := 1;
      while Eat(tkComma) do
      begin
        if nIdx >= NDInfoNDims then Error('too many subscripts for array');
        ParseExpr; NDIdxNode[nIdx] := CurASTNode; Inc(nIdx);
      end;
      if nIdx <> NDInfoNDims then Error('wrong number of array subscripts');
      ASTRight[sub] := BuildFlatNDIndex(nIdx);
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
      ASTRight[sub] := BuildFlatNDIndex(nIdx);
    end
    else
    begin
      ASTRight[sub] := CurASTNode;
      Expect(tkRBrack, ']');
    end;
    { StrValTk, not Ord: a frozen string's STORAGE kind is tyFixedString and its
      VALUE kind is tyString -- the layouts are identical and only the slot size
      differs, so every `= tyString` value check downstream keys on the latter.
      Tagged with the storage kind, `MkStr[1]` on an `array[0..2] of string[8]`
      printed 3, its length word, where FPC prints `mid`: a SILENT wrong value,
      strictly worse than the refusal this arm replaced. }
    ASTTk[sub] := StrValTk(tk);
    { A RECORD/CLASS element continues into the ordinary selector walk --
      `MkR[1].a`, `MkR2[i,j].a.b`. On `sub` and not on the AN_COMMA below,
      because a field selector needs an ADDRESSABLE base and `tmp[i]` is one
      while the comma's yielded value is not. This is the whole reason the
      record spelling gets no arm of its own any more. }
    if ((tk = tyRecord) or (tk = tyClass)) and (CurTok.Kind in [tkDot, tkLBrack]) then
    begin
      nIdx := ArrTypeElemRec[arrAi];
      if nIdx = REC_NONE then nIdx := ProcRetRecId[procIdx];
      sub := ParseClassRecordSelectors(sub, nIdx, tk);
    end;
    prevTok := AllocNode(AN_COMMA);
    ASTLeft[prevTok] := node;
    ASTRight[prevTok] := sub;
    ASTTk[prevTok] := StrValTk(tk);
    node := prevTok;
    tk := IntToTypeKind(StrValTk(tk));
  end;
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
  { NilPy: the value in a `Callable[...]` parameter may be a lambda or a closure
    — a heap OBJECT, not a code address — and the typed indirect call above
    jumps straight into it. Branch at run time; a compiled def keeps this exact
    path (bug-nilpy-callable-annotated-param-segfaults-on-a-heap-callable). }
  if PyExprMode and (not isMethod) and (Procs[sigPi].RetType = tyVariant) then
    node := PyWrapHeapCallableCall(calleeNode, argsHead, nArgs, node);
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
  { …and an ALL-DEFAULTED function is paramless AT THE CALL SITE, so it is a
    value-producing call here too and belongs in the same fall-back: FPC prints
    6 for `Chk('x', F, 6)` under {$MODE DELPHI} with `F(k: Integer = 3)`, while
    taking the address unconditionally passed a POINTER into an Integer sink and
    printed 4247470 — a silent wrong value, measured against FPC. It reaches
    @F through MatchCallDelphiProcAddr's retry when the sink really is
    procedural, which is exactly how a paramless function already gets there.
    Defaults are trailing in Pascal, so parameter 0 having one means all do.
    bug-p-bare-all-defaulted-routine-refused-in-argument-position }
  if Procs[pi].IsFunc and (Procs[pi].ParamCount = 0) then Exit;
  if Procs[pi].IsFunc and (Procs[pi].ParamCount > 0) and
     ProcParamHasDefault[pi * MAX_PROC_PARAMS] then Exit;
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

function NodePtrElem(node: Integer; var elemTk: TTypeKind; var elemRec: Integer;
                    depth: Integer): Boolean;
{ The POINTEE type of a pointer-valued expression, seen through the arithmetic.

  `(p + k)^` used to resolve its pointee only when the inner node was a bare
  identifier or `arr[i]`; a binop "carries no element-type tag" and defaulted to
  Integer. That default is right for a ^Integer and wrong for every other
  pointer, so `(pc + 2)^` read FOUR bytes as an integer -- 1717920867, the bytes
  'dcef' -- where `pc^` and `pc[2]`, the two other spellings of the same access,
  both answered 'c'. Silent, and on a ^Byte or ^SmallInt it is a wrong SPAN, not
  just a wrong tag.

  Pointer arithmetic keeps the pointer's type, so the pointee comes from
  whichever operand carries one. bug-p-a-pchar-plus-offset-loses-its-type-when-dereferenced }
begin
  Result := False;
  if (node < 0) or (node >= ASTNodeCount) or (depth > 8) then Exit;
  if ASTKind[node] = AN_IDENT then
  begin
    if (ASTIVal[node] < 0) or (ASTIVal[node] >= SymCount) then Exit;
    if IntToTypeKind(ASTTk[node]) <> tyPointer then Exit;
    elemTk := Syms[ASTIVal[node]].PtrElemTk;
    elemRec := Syms[ASTIVal[node]].PtrElemRec;
    Result := elemTk <> tyUnknown;
  end
  else if ASTKind[node] = AN_INDEX then
    Result := NodePtrElem(ASTLeft[node], elemTk, elemRec, depth + 1)
  else if (ASTKind[node] = AN_BINOP) and
          (TTokenKind(ASTIVal[node]) in [tkPlus, tkMinus]) then
  begin
    Result := NodePtrElem(ASTLeft[node], elemTk, elemRec, depth + 1);
    if not Result then
      Result := NodePtrElem(ASTRight[node], elemTk, elemRec, depth + 1);
  end;
end;

{ ===== A static `array of Char` IS a string =====

  FPC treats `array[lo..hi] of Char` as string-compatible in BOTH directions and
  pxx did not, because the arrayness lives on the SYMBOL (Syms[].IsArray/ArrLen)
  while the AST node for `a` is typed tyChar. Every string context therefore saw
  a plain Char and quietly did something defensible with it: `a := 'abcdefgh'`
  stored the low byte of the literal's HANDLE into a[0] and left the rest alone,
  `s := a` answered '', `a = 'abcdefgh'` was False. All silent.

  These are the one conversion, called from the places that want a string —
  the same shape WrapPCharToString and WrapCharToStringExpr already have, and
  for the same reason: a wrap at the boundary beats a special case grown at
  each site. bug-p-a-char-array-is-not-a-string-in-any-direction }

function ASTCharArrayCap(node: Integer): Integer;
{ The element count if `node` denotes a STATIC Char array, else -1. A DYNAMIC
  array (ArrLen = -1) is a managed handle and a different animal; an array of
  anything but Char is not a string at all. }
var sym: Integer;
begin
  Result := -1;
  if (node < 0) or (node >= ASTNodeCount) then Exit;
  if ASTKind[node] <> AN_IDENT then Exit;
  sym := ASTIVal[node];
  if (sym < 0) or (sym >= SymCount) then Exit;
  if not Syms[sym].IsArray then Exit;
  if Syms[sym].ArrLen < 0 then Exit;
  if SymElemDynDepth[sym] <> 0 then Exit;
  if Syms[sym].ElemType <> tyChar then Exit;
  Result := Syms[sym].ArrLen;
end;

function WrapCharArrayToStringExpr(node: Integer): Integer;
{ `a` in a string context -> __pxxCharArrayToStr(@a, cap). The helper stops at
  the first #0 within cap, which is FPC's rule and not a plain memcpy: an
  array[0..7] holding 'ABC'#0'EFGH' is the 3-character 'ABC'. }
var procIdx, cap, addrNode, a0, a1, capNode, callNode: Integer;
begin
  Result := node;
  cap := ASTCharArrayCap(node);
  if cap < 0 then Exit;
  procIdx := FindProc('__pxxCharArrayToStr');
  if procIdx < 0 then
    Error('a Char array in a string context needs __pxxCharArrayToStr (builtin unit not loaded)');
  addrNode := AllocNode(AN_ADDR);
  ASTLeft[addrNode] := node;
  ASTTk[addrNode] := Ord(tyPointer);
  capNode := AllocNode(AN_INT_LIT);
  ASTIVal[capNode] := cap;
  ASTTk[capNode] := Ord(tyInteger);
  a0 := AllocNode(AN_ARG);
  ASTLeft[a0] := addrNode; ASTTk[a0] := Ord(tyPointer);
  a1 := AllocNode(AN_ARG);
  ASTLeft[a1] := capNode;  ASTTk[a1] := Ord(tyInteger);
  ASTRight[a0] := a1;      ASTRight[a1] := -1;
  callNode := AllocNode(AN_CALL);
  ASTIVal[callNode] := procIdx;
  ASTTk[callNode] := Ord(Procs[procIdx].RetType);
  ASTLeft[callNode] := a0; ASTRight[callNode] := -1;
  Result := callNode;
end;

function WrapStringToCharArrayStmt(destNode, valueNode: Integer): Integer;
{ `a := s` -> __pxxStrToCharArray(@a, cap, s): Min(Length(s), cap) characters
  and then a ZERO fill, which is what leaves `a := 'abc'` on an 8-element array
  as 97 98 99 0 0 0 0 0 rather than five stale bytes. }
var procIdx, cap, addrNode, capNode, a0, a1, a2, callNode: Integer;
begin
  Result := -1;
  cap := ASTCharArrayCap(destNode);
  if cap < 0 then Exit;
  procIdx := FindProc('__pxxStrToCharArray');
  if procIdx < 0 then
    Error('a string assigned to a Char array needs __pxxStrToCharArray (builtin unit not loaded)');
  addrNode := AllocNode(AN_ADDR);
  ASTLeft[addrNode] := destNode;
  ASTTk[addrNode] := Ord(tyPointer);
  capNode := AllocNode(AN_INT_LIT);
  ASTIVal[capNode] := cap;
  ASTTk[capNode] := Ord(tyInteger);
  a0 := AllocNode(AN_ARG);
  ASTLeft[a0] := addrNode; ASTTk[a0] := Ord(tyPointer);
  a1 := AllocNode(AN_ARG);
  ASTLeft[a1] := capNode;  ASTTk[a1] := Ord(tyInteger);
  a2 := AllocNode(AN_ARG);
  ASTLeft[a2] := valueNode; ASTTk[a2] := Ord(tyAnsiString);
  ASTRight[a0] := a1; ASTRight[a1] := a2; ASTRight[a2] := -1;
  callNode := AllocNode(AN_CALL);
  ASTIVal[callNode] := procIdx;
  ASTTk[callNode] := Ord(Procs[procIdx].RetType);
  ASTLeft[callNode] := a0; ASTRight[callNode] := -1;
  Result := callNode;
end;

{ Promote a Char-typed expression to a 1-char string VALUE, reusing the exact
  `String(c)` desugar: assign the char into a hidden tyString temp, then read the
  temp (AN_STR_FROM_CHAR: Left = the store side-effect, Right = the yielded read).
  Works in both frozen and managed string modes with no backend code. Used where a
  Char appears in a string context that expects a string value — e.g. `Copy('a',
  1, 1)`, which FPC accepts by promoting the char (mirrors the promotion the `+`
  concat and String() cast already do). }
function WrapCharToStringExpr(charNode: Integer): Integer;
var tmpSym, resNode, lhsIdent, assignNode, readIdent: Integer;
begin
  tmpSym := AllocVar('', tyString);
  resNode := AllocNode(AN_STR_FROM_CHAR);
  lhsIdent := AllocNode(AN_IDENT);
  ASTIVal[lhsIdent] := tmpSym; ASTTk[lhsIdent] := Ord(Syms[tmpSym].TypeKind);
  assignNode := AllocNode(AN_ASSIGN);
  ASTLeft[assignNode] := lhsIdent; ASTRight[assignNode] := charNode;
  ASTTk[assignNode] := Ord(Syms[tmpSym].TypeKind);
  ASTLeft[resNode] := assignNode;
  readIdent := AllocNode(AN_IDENT);
  ASTIVal[readIdent] := tmpSym; ASTTk[readIdent] := Ord(Syms[tmpSym].TypeKind);
  ASTRight[resNode] := readIdent;
  ASTTk[resNode] := Ord(Syms[tmpSym].TypeKind);
  Result := resNode;
end;

{ A WIDECHAR value cast node — AN_PTR_CAST with the -3 sentinel (see the
  ordinal-cast site). String contexts convert it to UTF-8 instead of treating
  the 16-bit ordinal as a string pointer. }
function NodeIsWideCharVal(n: Integer): Boolean;
begin
  Result := (n >= 0) and (ASTKind[n] = AN_PTR_CAST) and (Integer(ASTIVal[n]) = -3);
end;

{ Wrap a WideChar value node in __pxxWideCharToUTF8(node) so the UTF-16 code
  unit becomes its UTF-8 byte encoding (builtin unit, auto-pulled when a
  `widechar(` cast appears in the token pre-scan). }
function WrapWideCharToUTF8(argNode: Integer): Integer;
var procIdx, wArg, wCall: Integer;
begin
  procIdx := FindProc('__pxxWideCharToUTF8');
  if procIdx < 0 then Error('WideChar->string conversion: __pxxWideCharToUTF8 helper not loaded');
  wArg := AllocNode(AN_ARG);
  ASTLeft[wArg] := argNode; ASTRight[wArg] := -1; ASTTk[wArg] := Ord(tyInteger);
  wCall := AllocNode(AN_CALL);
  ASTIVal[wCall] := procIdx;
  ASTTk[wCall] := Ord(Procs[procIdx].RetType);
  ASTLeft[wCall] := wArg; ASTRight[wCall] := -1;
  Result := wCall;
end;

{ Wrap a tyUCS4Char value in __pxxUCS4ToUTF8(node), so a CODE POINT reaching a
  string context becomes its UTF-8 encoding rather than its ordinal. This is the
  conversion that makes tyUCS4Char worth its own kind — storage is tyUInt32's,
  but `s + c` must yield the character, not 104+233 truncated to a byte.
  feature-nilpy-text-string-kind }
function WrapUCS4ToUTF8(argNode: Integer): Integer;
var procIdx, wArg, wCall: Integer;
begin
  procIdx := FindProc('__pxxUCS4ToUTF8');
  if procIdx < 0 then Error('UCS4Char->string conversion: __pxxUCS4ToUTF8 helper not loaded');
  wArg := AllocNode(AN_ARG);
  ASTLeft[wArg] := argNode; ASTRight[wArg] := -1; ASTTk[wArg] := Ord(tyInteger);
  wCall := AllocNode(AN_CALL);
  ASTIVal[wCall] := procIdx;
  ASTTk[wCall] := Ord(Procs[procIdx].RetType);
  ASTLeft[wCall] := wArg; ASTRight[wCall] := -1;
  Result := wCall;
end;

{ NilPy: wrap a tyChar VALUE as pystr_ofchar(char) -> a real 1-char managed
  string. Used at call-arg marshalling to turn `s[i]` (pystr_at yields Char)
  into a tyAnsiString expression BEFORE argIsManagedTemp is decided, so a char
  passed to a string parameter (`len(s[i])`, a `const s: AnsiString` param)
  flows through the owning-arg-temp path and is released — instead of the raw
  char being materialised inline by codegen with no owner (leak). Returns the
  original node unchanged if pystr_ofchar is not loaded (non-NilPy builds). }
function WrapCharToPyStr(argNode: Integer): Integer;
var procIdx, wArg, wCall: Integer;
begin
  procIdx := FindProc('pystr_ofchar');
  if procIdx < 0 then begin WrapCharToPyStr := argNode; Exit; end;
  wArg := AllocNode(AN_ARG);
  ASTLeft[wArg] := argNode; ASTRight[wArg] := -1; ASTTk[wArg] := Ord(tyChar);
  wCall := AllocNode(AN_CALL);
  ASTIVal[wCall] := procIdx;
  ASTTk[wCall] := Ord(tyAnsiString);
  ASTLeft[wCall] := wArg; ASTRight[wCall] := -1;
  WrapCharToPyStr := wCall;
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
    litTypes: array[0..MAX_PROC_PARAMS-1] of TTypeKind;
    hasCand, needAddr, pcharRetry, hasPChar, litRetry: Boolean;
begin
  hasCand := False;
  if DelphiMode then
  begin
    currArg := argsHead;
    for i := 0 to nArgs-1 do
    begin
      exprNode := ASTLeft[currArg];
      { A PARENLESS all-defaulted call is a candidate too — `Apply(F, 5)` where
        `F(k: Integer = 3)` and Apply takes a procedural. Its arguments are
        compiler-filled, so ASTLeft is not -1 and ParamCount is not 0; the
        ASTCallParenless flag is what separates it from a written `F(2)`, which
        must NOT be silently turned into an address. }
      procCand[i] := (ASTKind[exprNode] = AN_CALL) and (ASTIVal[exprNode] >= 0) and
                     (((ASTLeft[exprNode] = -1) and
                       (Procs[ASTIVal[exprNode]].ParamCount = 0)) or
                      ASTCallParenless[exprNode]);
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
    if IsNodePChar(ASTLeft[currArg]) or NodeIsWideCharVal(ASTLeft[currArg]) or
       (argTypes[i] = tyUInt16) then
      hasPChar := True;   { either coercion retry below may run; quiet the first-match diag }
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
      { An AN_METHODREF argument is reported as tyRecord (it fills a method-pointer
        param) but ResolveNodeRec would yield the OBJECT's class, not the
        method-pointer record — leave the record identity unconstrained so it binds
        to the `of object` param (its {Code,Data} pair is built at IR lowering). }
      if ASTKind[ASTLeft[currArg]] = AN_METHODREF then MatchArgRec[i] := REC_NONE
      else if (argTypes[i] = tyRecord) or (argTypes[i] = tyClass) then
        { tyClass added with bug-a-overload-resolution-ignores-class-identity:
          without the argument's class id the matcher stays blind and binds an
          unrelated class to any class-typed parameter. }
        MatchArgRec[i] := ResolveNodeRec(ASTLeft[currArg])
      else MatchArgRec[i] := REC_NONE;
    end;
    currArg := ASTRight[currArg];
  end;
  MatchArgRecValid := True;

  { ...and, beside it, whether the argument is DEFINITELY a scalar value, which
    disqualifies an ARRAY parameter. argTypes cannot answer that: a fixed-array
    parameter and a fixed-array argument both present their ELEMENT kind, so an
    `array[0..2] of Integer` overload looked exactly like an `Integer` one and
    won by declaration order — `Sum(n)` then read three elements off a 4-byte
    variable and segfaulted. Only shapes whose scalar-ness is certain are
    marked; anything else stays False and matches as before.
    bug-a-an-integer-argument-binds-a-fixed-array-overload }
  currArg := argsHead;
  for i := 0 to nArgs-1 do
  begin
    if i < MAX_PROC_PARAMS then
    begin
      node := ASTLeft[currArg];
      MatchArgScalar[i] := (TypeIsOrdinal(argTypes[i]) or TypeIsFloat(argTypes[i])) and
                           (argTypes[i] <> tyChar) and (argTypes[i] <> tyPointer) and
        (((ASTKind[node] = AN_INT_LIT) or (ASTKind[node] = AN_FLOAT_LIT) or
          (ASTKind[node] = AN_BINOP)) or
         ((ASTKind[node] = AN_IDENT) and (ASTIVal[node] >= 0) and
          (ASTIVal[node] < SymCount) and not Syms[ASTIVal[node]].IsArray) or
         ((ASTKind[node] = AN_CALL) and (ASTIVal[node] >= 0) and
          (ProcRetFixedArrBytes[ASTIVal[node]] = 0) and
          not ProcRetIsDynArray[ASTIVal[node]]));
    end;
    currArg := ASTRight[currArg];
  end;
  MatchArgScalarValid := True;

  { FPC parity: an untyped integer LITERAL is typed by its VALUE — the smallest
    type that holds it — and overload resolution ranks against THAT. pxx types
    every literal LongInt (Int64 when it does not fit), so `hi($1234)` bound
    Hi(LongInt) and split 32 bits (0|4660) where FPC binds Hi(SmallInt) and
    splits 16 (18|52). Probed as a separate EXACT-only match ahead of the real
    one: an exact hit is unambiguously the candidate FPC would pick, and a miss
    costs one chain walk and changes nothing — which is what keeps `5` binding
    LongInt rather than Byte, since ShortInt does not widen into Byte and FPC
    ranks it the same way. The literal's own type is untouched, so arithmetic
    promotion is unaffected. }
  litRetry := False;
  currArg := argsHead;
  for i := 0 to nArgs-1 do
  begin
    if i < MAX_PROC_PARAMS then
    begin
      litTypes[i] := argTypes[i];
      exprNode := ASTLeft[currArg];
      { ASTEnumId >= 0: an enum MEMBER folds to an AN_INT_LIT carrying its
        ordinal — re-typing that by value would rank it as a plain number. }
      if (ASTKind[exprNode] = AN_INT_LIT) and (ASTEnumId[exprNode] < 0) and
         IsIntTypeKind(argTypes[i]) then
      begin
        litTypes[i] := LiteralIntKind(ASTIVal[exprNode]);
        if litTypes[i] <> argTypes[i] then litRetry := True;
      end;
    end;
    currArg := ASTRight[currArg];
  end;

  MatchQuiet := hasCand or hasPChar;   { the call-first / pchar probe must not print mismatch diag }
  match0 := -1;
  if litRetry and (nArgs <= MAX_PROC_PARAMS) then
  begin
    MatchExactOnly := True;
    if qUnit >= 0 then match0 := MatchProcCallInUnit(name, qUnit, nArgs, litTypes)
    else match0 := MatchProcCall(name, nArgs, litTypes, qUnit = -1);
    MatchExactOnly := False;
  end;
  if match0 < 0 then
  begin
    if qUnit >= 0 then match0 := MatchProcCallInUnit(name, qUnit, nArgs, argTypes)
    else match0 := MatchProcCall(name, nArgs, argTypes, qUnit = -1);   { qUnit=-1 plain unqualified -> builtin is fallback-only; -2 System keeps builtin }
  end;
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
      else pi := MatchProcCall(name, nArgs, retryTypes, qUnit = -1);
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
    { WideChar -> string implicit conversion in a call argument, same failed-match
      retry shape as PChar above: a WideChar VALUE binding a string parameter
      converts to its UTF-8 encoding (fpjson's UTF8Encode(WideChar(U1))). Catches
      both an explicit `WideChar(x)` cast (NodeIsWideCharVal) AND a bare `w: WideChar`
      variable read — the latter is a plain tyUInt16 ident (WideChar collapses to
      tyUInt16, no subtype marker), which the cast-only check missed, so `show(w)`
      failed overload resolution (bug-pascal-widechar-var-to-string-other-contexts).
      Mirrors the assign path (ir.inc: any tyUInt16 -> string is a widechar convert;
      a genuine Word->string is invalid in FPC and nonsensical here — strict-FPC
      parity would belong behind --strict-fpc). The as-is match already covers
      ordinal parameters and runs first, so this never overrides a stricter match. }
    pcharRetry := False;
    currArg := argsHead;
    for i := 0 to nArgs-1 do
    begin
      if NodeIsWideCharVal(ASTLeft[currArg]) or (argTypes[i] = tyUInt16) then
        begin retryTypes[i] := tyAnsiString; pcharRetry := True; end
      else
        retryTypes[i] := argTypes[i];
      currArg := ASTRight[currArg];
    end;
    if pcharRetry then
    begin
      if qUnit >= 0 then pi := MatchProcCallInUnit(name, qUnit, nArgs, retryTypes)
      else pi := MatchProcCall(name, nArgs, retryTypes, qUnit = -1);
      if pi >= 0 then
      begin
        currArg := argsHead;
        for i := 0 to nArgs-1 do
        begin
          exprNode := ASTLeft[currArg];
          if (NodeIsWideCharVal(exprNode) or (argTypes[i] = tyUInt16)) and
             ((Procs[pi].Params[i].TypeKind = tyString) or
              (Procs[pi].Params[i].TypeKind = tyAnsiString)) then
            ASTLeft[currArg] := WrapWideCharToUTF8(exprNode);
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
      { ProcParamProcSig, not the param SYMBOL's SymProcSig: RegisterProc leaves
        Params[].SymIdx pointing at a symbol that does NOT outlive the callee's
        scope, so in a program with enough symbols to recycle it the test
        silently answered "not procedural" and the spurious numeric match stood.
        Measured: `C2(Apply(F, 5), 10)` passed F's RESULT (6) where the callee
        called it as a function pointer and jumped to address 6, while the same
        `Apply(F, 5)` at statement level was fine — the parallel array is the
        one that answers from a caller, and its own comment in defs.inc says so.
        bug-p-bare-all-defaulted-routine-refused-in-argument-position }
      sidx := Procs[match0].Params[i].SymIdx;
      if procCand[i] and
         ((ProcParamProcSig[match0 * MAX_PROC_PARAMS + i] >= 0) or
          ((sidx >= 0) and (SymProcSig[sidx] >= 0))) then needAddr := True;
    end;
  if not needAddr then Exit;

  for i := 0 to nArgs-1 do
    if procCand[i] then retryTypes[i] := tyPointer else retryTypes[i] := argTypes[i];
  if qUnit >= 0 then pi := MatchProcCallInUnit(name, qUnit, nArgs, retryTypes)
  else pi := MatchProcCall(name, nArgs, retryTypes, qUnit = -1);
  if pi < 0 then Exit;   { retry failed -> leave the original result (genuine type error) }
  Result := pi;

  currArg := argsHead;
  for i := 0 to nArgs-1 do
  begin
    exprNode := ASTLeft[currArg];
    sidx := Procs[pi].Params[i].SymIdx;
    if procCand[i] and
       ((Procs[pi].Params[i].TypeKind = tyPointer) or
        (ProcParamProcSig[pi * MAX_PROC_PARAMS + i] >= 0) or
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
    { The 64-bit ALIASES answered nothing at all, so `High(NativeInt)` and
      `High(PtrInt)` — the idiomatic way FPC code spells a machine-word bound —
      were rejected with "expected an ordinal type name" while `High(Int64)`
      was fine. The unsigned 64-bit names (QWord/UInt64/NativeUInt/PtrUInt)
      stay out on purpose: their High is 2^64-1, which this evaluator's Int64
      cannot carry, and answering -1 would turn a refusal into a wrong value.
      bug-p-high-low-reject-the-64-bit-type-aliases }
    tyNativeInt: if wantHigh then v := 9223372036854775807 else v := -9223372036854775807 - 1;
    tyBoolean: if wantHigh then v := 1 else v := 0;
    tyChar:    if wantHigh then v := 255 else v := 0;
  else
    Result := False;
  end;
end;

{ Map a built-in ordinal TYPE name to its TTypeKind, or tyUnknown if the name is
  not a (supported) ordinal builtin. Covers the names that lex as tkIdent (the
  dedicated type tokens are handled directly via ParseTypeKind). }
{ The built-in POINTER type names (PInteger, PByte, PDouble, ...): the type they point AT, or
  tyUnknown if the name is not one of them. Element rec is never a record here.

  These are consulted ONLY AFTER FindTypeAlias misses, everywhere they are used. That ordering is
  the whole safety property, and it is not optional: registering them as real aliases up front
  looks right, compiles, and SILENTLY BREAKS THE COMPILER -- FindTypeAlias scans forward and
  returns the FIRST match, so a pre-registered builtin shadows the source's own declaration, and
  this compiler declares `PWord = ^NativeInt` (the machine word). The self-host byte-identical
  gate is what caught that. See bug-pascal-builtin-pointer-type-cast. }
function BuiltinPtrNameElemTk(const nm: AnsiString): TTypeKind;
begin
  if CaseEqual(nm, 'pinteger') or CaseEqual(nm, 'plongint') or CaseEqual(nm, 'pint32') then Result := tyInt32
  else if CaseEqual(nm, 'pshortint') or CaseEqual(nm, 'pint8') then Result := tyInt8
  else if CaseEqual(nm, 'psmallint') or CaseEqual(nm, 'pint16') then Result := tyInt16
  else if CaseEqual(nm, 'pbyte') or CaseEqual(nm, 'puint8') then Result := tyUInt8
  else if CaseEqual(nm, 'pword') or CaseEqual(nm, 'puint16') then Result := tyUInt16
  else if CaseEqual(nm, 'pcardinal') or CaseEqual(nm, 'plongword') or CaseEqual(nm, 'pdword') or CaseEqual(nm, 'puint32') then Result := tyUInt32
  else if CaseEqual(nm, 'pint64') then Result := tyInt64
  else if CaseEqual(nm, 'pqword') or CaseEqual(nm, 'puint64') then Result := tyUInt64
  else if CaseEqual(nm, 'pnativeint') or CaseEqual(nm, 'pptrint') then Result := tyNativeInt
  else if CaseEqual(nm, 'pnativeuint') or CaseEqual(nm, 'pptruint') then Result := tyNativeUInt
  else if CaseEqual(nm, 'psingle') then Result := tySingle
  else if CaseEqual(nm, 'pdouble') or CaseEqual(nm, 'pextended') then Result := tyDouble
  else if CaseEqual(nm, 'pboolean') then Result := tyBoolean
  else if CaseEqual(nm, 'pvariant') then Result := tyVariant
  else if CaseEqual(nm, 'ppointer') then Result := tyPointer
  { PShortString — FPC's typinfo/fpcunit method-name tables are built out of it
    (`TMethodNameRec.name : pshortstring`). tyChar for PAnsiChar/PChar is deliberately
    NOT here: PChar has its own dedicated handling (PChar<->string conversions, the
    NUL-terminated model), and routing it through the generic builtin-pointer alias
    would bypass that. }
  else if CaseEqual(nm, 'pshortstring') then Result := tyShortString
  else Result := tyUnknown;
end;

{ The alias index for a built-in pointer name, REGISTERING it on first use. Registering lazily is
  what keeps a source declaration winning: FindTypeAlias is consulted first by every caller, so a
  real `PInteger` in the source or the RTL is found before we ever get here. Returns -1 for a name
  that is not a builtin pointer. }
function EnsureBuiltinPtrAlias(const nm: AnsiString): Integer;
var elemTk: TTypeKind; noff, i: Integer;
begin
  Result := -1;
  elemTk := BuiltinPtrNameElemTk(nm);
  if elemTk = tyUnknown then Exit;
  noff := TokCharLen;
  for i := 1 to Length(nm) do
  begin
    if TokCharLen >= STRING_CAP then Error('token char buffer overflow');
    TokChars[TokCharLen] := nm[i];
    Inc(TokCharLen);
  end;
  RegisterPtrAlias(noff, Length(nm), Ord(elemTk), REC_NONE, 0, 0);
  Result := AliasCount - 1;
end;

function OrdinalNameToTk(const nm: AnsiString): TTypeKind;
begin
  if CaseEqual(nm, 'shortint') or CaseEqual(nm, 'int8') then Result := tyInt8
  else if CaseEqual(nm, 'byte') or CaseEqual(nm, 'uint8') then Result := tyUInt8
  else if CaseEqual(nm, 'smallint') or CaseEqual(nm, 'int16') then Result := tyInt16
  else if CaseEqual(nm, 'word') or CaseEqual(nm, 'uint16') then Result := tyUInt16
  else if CaseEqual(nm, 'longint') or CaseEqual(nm, 'int32') then Result := tyInt32
  else if CaseEqual(nm, 'integer') then Result := tyInteger
  else if CaseEqual(nm, 'cardinal') or CaseEqual(nm, 'longword') or CaseEqual(nm, 'uint32')
       or CaseEqual(nm, 'dword') then Result := tyUInt32
  else if CaseEqual(nm, 'int64') then Result := tyInt64
  else if CaseEqual(nm, 'qword') or CaseEqual(nm, 'uint64') then Result := tyUInt64
  else if CaseEqual(nm, 'nativeint') or CaseEqual(nm, 'ptrint')
       or CaseEqual(nm, 'sizeint') then Result := tyNativeInt
  else if CaseEqual(nm, 'nativeuint') or CaseEqual(nm, 'ptruint') then Result := tyNativeUInt
  else if CaseEqual(nm, 'boolean') then Result := tyBoolean
  else if CaseEqual(nm, 'char') or CaseEqual(nm, 'ansichar') then Result := tyChar
  { WideChar is a 2-byte ordinal here (this RTL is byte/ASCII throughout; the type exists so
    FPC sources that name it compile). `WideChar(x)` is fpjson's \u escape decoder. }
  else if CaseEqual(nm, 'widechar') then Result := tyUInt16
  { UCS4Char is FPC's own name for a code point (system unit: UCS4Char = type
    LongWord) and, unlike WideChar, holds any character. Its own kind because it
    CONVERTS to a string as UTF-8 — see the note on tyUCS4Char in defs.inc. }
  else if CaseEqual(nm, 'ucs4char') or CaseEqual(nm, 'unicodechar')
       then Result := tyUCS4Char
  else Result := tyUnknown;
end;

{ Map a BUILTIN scalar type NAME to its TTypeKind, tyUnknown when it is not one.
  The whole builtin set: the ordinals via OrdinalNameToTk above, plus the float
  family, Variant, Pointer and the string names.

  Exists because SizeOf kept its OWN copy of this table and the copy was a
  SUBSET -- integer family, Boolean, Char, String and nothing else -- so
  SizeOf(Double), SizeOf(Single), SizeOf(Extended), SizeOf(Real),
  SizeOf(Variant), SizeOf(WideChar) and SizeOf(UCS4Char) were every one of them
  REJECTED, with no diagnostic hinting that the type itself was fine. Found on
  rtl-generics' `SizeOf(System.Variant)`, then confirmed name by name against
  FPC 3.2.2. One table, so the next builtin type cannot be present in half the
  compiler (devdocs/dev/normalise-dont-special-case.md).

  Callers must consult a user type alias FIRST where that matters: this answers
  what the name means as a BUILTIN, not what the current scope binds it to. }
function BuiltinTypeNameTk(const nm: AnsiString): TTypeKind;
begin
  Result := OrdinalNameToTk(nm);
  if Result <> tyUnknown then Exit;
  if CaseEqual(nm, 'single') then Result := tySingle
  { Real is Double here, as it is in FPC on this target -- not a distinct type. }
  else if CaseEqual(nm, 'double') or CaseEqual(nm, 'real') then Result := tyDouble
  else if CaseEqual(nm, 'extended') then Result := tyExtended
  else if CaseEqual(nm, 'variant') then Result := tyVariant
  else if CaseEqual(nm, 'pointer') or CaseEqual(nm, 'codepointer') then Result := tyPointer
  else if CaseEqual(nm, 'string') then Result := tyString
  { the Ansi/Unicode/Wide string names are one model here -- bytes; which KIND
    that is depends on the managed-string build, exactly as SizeOf's own table
    had it }
  else if CaseEqual(nm, 'ansistring') or CaseEqual(nm, 'unicodestring') or
          CaseEqual(nm, 'widestring') then
  begin
    if PasDefineExists('PXX_MANAGED_STRING') then
      Result := tyAnsiString
    else
      Result := tyString;
  end
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
var btk: TTypeKind; etid, aliasIdx, eLo, eHi: Integer; nm: AnsiString;
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
    if aliasIdx >= 0 then
    begin
  { A named SUBRANGE answers its OWN bounds, not the base type's. `TDigit = 0..9`
    gave Low = -2147483648 / High = 2147483647 (Integer's), and `TLetter =
    'a'..'e'` gave #0/#255 — so the idiomatic `for i := Low(T) to High(T)` over a
    named subrange ran four billion times instead of ten, silently.
    The bounds are already retained: AliasIsSub/AliasSubLo/AliasSubHi were added
    for {$R+} range checks, and nothing here consulted them.
    bug-a-low-high-of-a-named-subrange-answer-the-base-type }
      if AliasIsSub[aliasIdx] then
      begin
        if wantHigh then v := AliasSubHi[aliasIdx] else v := AliasSubLo[aliasIdx];
        Next;
        Result := True; Exit;
      end;
      btk := IntToTypeKind(AliasTk[aliasIdx]);
    end;
  end;
  if (btk <> tyUnknown) and OrdinalTypeBound(btk, wantHigh, v) then
  begin
    Next;
    Result := True; Exit;
  end;
  etid := FindEnumType(nm);
  if etid >= 0 then
  begin
    EnumTypeOrdRange(etid, eLo, eHi);
    if wantHigh then v := eHi else v := eLo;
    Next;
    Result := True; Exit;
  end;
end;

function TryFoldHighLowType(wantHigh: Boolean; var outNode: Integer): Boolean;
var btk: TTypeKind; bv: Int64; etid, aliasIdx, eLo, eHi: Integer; nm: AnsiString;
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
    if aliasIdx >= 0 then
    begin
      { the same subrange rule as TryConstHighLowValue — these two are one
        concept in two places, so they change together }
      if AliasIsSub[aliasIdx] then
      begin
        if wantHigh then bv := AliasSubHi[aliasIdx] else bv := AliasSubLo[aliasIdx];
        Next; outNode := AllocNode(AN_INT_LIT); ASTIVal[outNode] := bv;
        ASTTk[outNode] := Ord(IntToTypeKind(AliasTk[aliasIdx]));
        Result := True; Exit;
      end;
      btk := IntToTypeKind(AliasTk[aliasIdx]);
    end;
  end;
  if (btk <> tyUnknown) and OrdinalTypeBound(btk, wantHigh, bv) then
  begin
    Next; outNode := AllocNode(AN_INT_LIT); ASTIVal[outNode] := bv; ASTTk[outNode] := Ord(btk);
    Result := True; Exit;
  end;

  etid := FindEnumType(nm);
  if etid >= 0 then
  begin
    EnumTypeOrdRange(etid, eLo, eHi);
    if wantHigh then bv := eHi else bv := eLo;
    Next; outNode := AllocNode(AN_INT_LIT); ASTIVal[outNode] := bv; ASTTk[outNode] := Ord(tyInteger);
    Result := True; Exit;
  end;
end;

procedure ParseFactor; forward;

{ The real factor parser. ParseFactor below wraps it to apply NilPy's str-method
  suffix uniformly — this body has 67 Exit points, so a suffix loop written at
  its tail would silently miss most of them (it missed str(t).upper(), the exact
  uforth shape). }
{ Zero every managed local in [fromSym, SymCount) — see the zero-init contract
  above EmitZeroFrameSlot. Extracted from the Pascal routine-body path so the
  NilPy def/method paths get the SAME guarantee: they build their locals through
  their own pre-pass and never ran this loop, which was invisible while an
  inferred NilPy string local was a FROZEN string (nothing to release) and
  became a release of stale stack bytes the moment those locals turned managed
  (bug-nilpy-string-local-truncates-at-255). }
procedure EmitManagedLocalsZeroInit(fromSym: Integer);
var i, zeroBytes: Integer;
begin
  { Managed locals (dynamic arrays, AnsiStrings, and records/arrays containing
    them) hold managed pointer slots. Zero their full extent before the body so
    a first SetLength / assignment sees nil rather than stale stack bytes — and
    so an ARC-correct whole-record copy can safely release the (nil) old fields. }
  for i := fromSym to SymCount - 1 do
    if Syms[i].Kind = skLocal then
    begin
      { Fixed array whose elements are dynamic-array handles (`array[..] of TA`):
        nil every pointer-sized slot so SetLength on an element does not release
        a garbage "old" handle. }
      zeroBytes := 0;
      if Syms[i].IsArray and (Syms[i].ArrLen <> -1) and (SymElemDynDepth[i] > 0) then
        zeroBytes := Syms[i].ArrLen * TARGET_PTR_SIZE
      else if Syms[i].IsArray and (Syms[i].ArrLen = -1) then
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
      { RecordNeedsZeroInit, not RecordHasManagedFields: an interface FIELD is
        excluded from the finalization predicate on purpose (releasing it under
        the record heap lock deadlocks), but it still has to START NIL — nilling
        a stack slot takes no lock. Sharing one predicate between the two
        questions meant a record whose only refcounted member was an interface
        was never zeroed, so `r.f := x` released stack garbage and dispatched
        _Release through a junk IMT. The documented trade was a benign LEAK; what
        it actually produced was a use-after-free.
        bug-a-a-record-with-an-interface-field-is-not-zero-initialised }
      else if (Syms[i].TypeKind = tyRecord) and not Syms[i].IsArray and
              RecordNeedsZeroInit(Syms[i].RecName) then
        zeroBytes := RecSize(Syms[i].RecName)
      else if (Syms[i].TypeKind = tyRecord) and Syms[i].IsArray and
              RecordNeedsZeroInit(Syms[i].ElemRecName) then
        zeroBytes := Syms[i].ArrLen * RecSize(Syms[i].ElemRecName)
      else if SymIsComInterface(i) then
        { COM/ARC interface fat pointer: must start nil so the ARC release at
          first overwrite / scope exit sees an empty slot, not stale stack bytes
          (a garbage IMT would dispatch _Release into nowhere). }
        zeroBytes := RecSize(Syms[i].RecName)
      else if SymElemIsComInterface(i) then
        { STATIC ARRAY of COM interfaces — `keep: array[0..N] of IFoo`. Exactly
          the arm above, one indirection out, and it did not exist: every
          managed-local pass keys on SymIsComInterface, which answers False for
          an array on purpose, and the managed-RECORD-array arm above does not
          claim it either (an interface UCls has no managed FIELDS). So the slots
          held stack garbage and the very first `keep[i] := x` ran the ARC
          release on that garbage, dispatching _Release through a junk IMT.

          It presented as `uses sysutils` causing a segfault -- add the unit and
          an otherwise identical program crashes -- which is a pure red herring:
          the unit's initialisation merely DIRTIES the stack the routine is about
          to use. With a hand-written stack-dirtying routine the same crash
          reproduces with no sysutils at all, and with a clean stack the bug is
          invisible because the garbage happens to be zero. A constant index and
          a global array both "worked" for the same accidental reason.
          bug-a-a-local-array-of-interfaces-is-not-zero-initialised }
        zeroBytes := Syms[i].ArrLen * RecSize(SymTR[i].ElemRec)
      else if (Syms[i].TypeKind = tyClass) and (not Syms[i].IsArray) and
              NilPyUserCode then
        { NilPy-user class local: refcounted binding — must start nil so the
          rebind release and the scope-exit release see an empty slot
          (feature-nilpy-object-reclamation slice 4). }
        zeroBytes := TARGET_PTR_SIZE
      else if TypeIsPromoInt(Syms[i].TypeKind) and (not Syms[i].IsArray) then
        { Promotable int: a {tag, payload} pair whose tag MUST start
          PROMO_TAG_INLINE (0). The scope-exit cleanup calls PXXPromoClear on
          every promo local unconditionally (EmitManagedLocalCleanup), and that
          routine RELEASES the payload as a managed string whenever the tag
          reads PROMO_TAG_HEAP (1) — so a local left unwritten on the executed
          path was cleared with stale stack bytes, and bytes that happened to
          read {1, <a live pointer>} freed a block nobody had freed.

          PXXPromoClear's own header says it cannot be used on uninitialised
          memory; the temps satisfy that through SymIsHiddenArgTemp's prologue
          zero, and named locals had NOTHING. Cleanup without init: this list
          is where the init half belongs, beside every other managed kind.

          Found via uforth: `w_repeat` returns early, leaving a promo local
          untouched, and the frame garbage under it read as a heap-tier slot
          pointing at a live bound-fn object. Freeing it put a live block on the
          free bin, PXXAlloc handed it out again for a string, and the next
          `word.native(vm)` through that object jumped into the string data —
          three layers and thousands of lines from the cause, with the object
          still refcount-alive the whole time.
          bug-nilpy-write-after-free-on-a-callable-held-in-a-dataclass-field }
        zeroBytes := TypeSize(Syms[i].TypeKind);
      { One owner for the guarantee, every target, every size. }
      EmitZeroFrameSlot(Syms[i].Offset, zeroBytes);
    end;
end;

function PyMakeUnsupportedOperand: Integer;
{ An AN_CALL to pylib's PyUnsupportedOperandError: a genuine RUNTIME TypeError
  where these sites previously called the compiler's Error() and aborted the
  build. CPython raises at run time, so `try: a + b / except TypeError:` — the
  normal way to probe for operator support — must COMPILE and run its handler.
  Same shape the __contains__ / ordering / bitwise misses already use.
  bug-nilpy-missing-arith-dunder-aborts-compile-instead-of-raising. }
var pi, node: Integer;
begin
  pi := FindProc('PyUnsupportedOperandError');
  if pi < 0 then Error('Nil Python: pylib (PyUnsupportedOperandError) not loaded');
  node := AllocNode(AN_CALL);
  ASTIVal[node] := pi;
  ASTTk[node] := Ord(tyBoolean);
  ASTLeft[node] := -1;
  PyMakeUnsupportedOperand := node;
end;

function PyReflName(op: TTokenKind): AnsiString;
{ The reflected dunder for a binary operator: `a <op> b` falls back to
  `b.__r<op>__(a)`. One table so the two call sites (ParseSimpleExpr for +/-,
  ParseTerm for * / // %) cannot drift. }
begin
  case op of
    tkPlus:  PyReflName := '__radd__';
    tkMinus: PyReflName := '__rsub__';
    tkStar:  PyReflName := '__rmul__';
    tkSlash: PyReflName := '__rtruediv__';
    tkDiv:   PyReflName := '__rfloordiv__';
    tkMod:   PyReflName := '__rmod__';
    tkAt:    PyReflName := '__rmatmul__';
    else     PyReflName := '';
  end;
end;

function PyReflectedDunder(const rname: AnsiString; left, right: Integer): Integer;
{ Python's REFLECTED fallback: when the LEFT operand does not implement the
  operator, the RIGHT operand's `__r<op>__` is tried with the operands swapped
  (`3 + C(4)` -> `C(4).__radd__(3)`). Returns -1 when the right operand is not a
  user class declaring that method, so the caller keeps its existing path.

  Measured absent before this: all seven reflected forms fell through to the
  numeric typing and computed on the class HANDLE — `3 + C(4)` gave 1744830491,
  `3 * C(4)` gave -1906311096, silently
  (feature-nilpy-arithmetic-dunders-full-protocol). The two comments in this
  file that said the fallback "is not implemented" were the only trace of it;
  there was no partially-wired path.

  The RIGHT operand becomes the receiver and the LEFT becomes the argument —
  that swap is the whole point, and getting it backwards yields a plausible
  wrong answer rather than an error. }
var ci: Integer;
begin
  PyReflectedDunder := -1;
  if not PyExprMode then Exit;
  if IntToTypeKind(ASTTk[right]) <> tyClass then Exit;
  if ResolveNodeRec(right) < REC_UCLASS_BASE then Exit;
  if PyRecIsPylibOwnClass(ResolveNodeRec(right)) then Exit;
  ci := ResolveNodeRec(right) - REC_UCLASS_BASE;
  if FindUMeth(ci, rname) < 0 then Exit;
  PyReflectedDunder := PyCallMeth1(ci, rname, right, left);
end;

{ Is `node` a DYNAMIC-ARRAY-typed expression, and at what nesting depth?
  Copy's parse sites need the answer before ir.inc's NodeDynDepth exists (parser.inc
  is included first), and they need it for more than a bare name: an element of a
  nested array (`g[0]`), a record/class field (`r.items`). Deliberately a small
  mirror of NodeDynDepth's ident / field / index arms rather than a general type
  walker — anything it cannot recognise answers 0 and Copy falls through to its
  existing string/error paths, which is the safe direction
  (bug-p-copy-rejects-a-dynamic-array-expression-that-is-not-a-bare-name). }
function CopySrcDynDepth(node: Integer): Integer;
var si, bd: Integer;
begin
  Result := 0;
  if node < 0 then Exit;
  case ASTKind[node] of
    AN_IDENT:
      begin
        si := ASTIVal[node];
        if (si >= 0) and Syms[si].IsArray and (Syms[si].ArrLen = -1) then
          Result := SymDynDepth[si];
      end;
    AN_FIELD:
      Result := RecFieldDynDepth(ResolveNodeRec(ASTLeft[node]), GetASTIdentName(node));
    AN_INDEX:
      begin
        bd := CopySrcDynDepth(ASTLeft[node]);
        if bd > 0 then Result := bd - 1;
      end;
  end;
end;

{ May this argument be duplicated for a by-value OPEN ARRAY parameter?

  Two source shapes carry a length header at [data-8] and so can be copied: a
  DYNAMIC ARRAY, and an OPEN-ARRAY PARAMETER being forwarded onward. The second
  is not optional — `procedure Outer(x: array of Integer); begin Inner(x)`
  must give Inner its own copy too, and leaving it out left the inner write
  visible to Outer (measured against FPC, which answers the caller's original
  value).

  Elements must own nothing: AN_DYN_COPY moves bytes, so a managed or nested
  element would be duplicated WITHOUT a retain and released twice. The Copy
  intrinsic refuses nesting for the same reason; the managed case is added here
  because this copy is emitted implicitly rather than asked for, so a crash
  would arrive unannounced. Those element types keep the old aliasing behaviour
  until AN_DYN_COPY learns element-aware retain
  (feature-dynarray-copy-nested-element-type). }
function OpenArrayCopyEligible(node: Integer): Boolean;
var si: Integer; et: TTypeKind; isDyn, isOpenParam: Boolean;
begin
  Result := False;
  if node < 0 then Exit;
  if ASTKind[node] <> AN_IDENT then Exit;   { a bare name is the censused shape }
  si := ASTIVal[node];
  if (si < 0) or (si >= SymCount) then Exit;
  if not Syms[si].IsArray then Exit;
  if SymElemDynDepth[si] > 0 then Exit;     { nested — AN_DYN_COPY refuses it too }
  isDyn := (Syms[si].ArrLen = -1) and (SymDynDepth[si] = 1);
  { an OPEN-ARRAY parameter: AllocParam stamps the ArrLen = 1000 "length
    unknown" placeholder and leaves the dyn depth at 0, which is exactly what
    distinguishes it from a named dynamic-array param (depth >= 1) and from a
    named FIXED array param (a real ArrLen) }
  isOpenParam := (Syms[si].Kind = skParam) and (SymDynDepth[si] = 0) and
                 (Syms[si].ArrLen = 1000);
  if not (isDyn or isOpenParam) then Exit;
  et := Syms[si].ElemType;
  Result := (et = tyInteger) or (et = tyBoolean) or (et = tyChar) or
            (et = tyInt8) or (et = tyUInt8) or (et = tyInt16) or (et = tyUInt16) or
            (et = tyInt32) or (et = tyUInt32) or (et = tyInt64) or (et = tyUInt64) or
            (et = tyNativeInt) or (et = tyNativeUInt) or (et = tyPointer) or
            (et = tySingle) or (et = tyDouble);
end;

{ `Copy(node)` — the whole-array duplicate, built as the very node the Copy
  intrinsic builds (source, index 0, count MaxInt). }
function MakeWholeDynCopy(node: Integer): Integer;
var idxN, cntN, argA, argB: Integer;
begin
  idxN := AllocNode(AN_INT_LIT);
  ASTIVal[idxN] := 0; ASTTk[idxN] := Ord(tyInteger);
  cntN := AllocNode(AN_INT_LIT);
  ASTIVal[cntN] := 2147483647; ASTTk[cntN] := Ord(tyInteger);
  Result := AllocNode(AN_DYN_COPY);
  ASTLeft[Result] := node;
  argA := AllocNode(AN_ARG); ASTLeft[argA] := idxN;
  argB := AllocNode(AN_ARG); ASTLeft[argB] := cntN;
  ASTRight[argA] := argB;
  ASTRight[Result] := argA;
  ASTTk[Result] := Ord(tyPointer);
end;

procedure ParseFactorCore;
var negConstVal: Int64;   { value of a negated CONSTANT — types the AN_NEG node }
    lenSavedHoist, lenTrialHoist: Integer;   { the len() intercept's parked hoist queue }
    rndRawArg: Integer;      { round(x, n): the argument node before the float unbox }
    intBaseArg, atRecv, atFld, atDflt, atProp: Integer; atIsGet, atExists: Boolean; atName: AnsiString; name, grpAcc: AnsiString; recName: Integer; idx, procIdx, i, node, left, prevTok, valNode: Integer; tk: TTypeKind; op, argSeq, argSeq2, argSeq3, lastArg, argIdx, exprNode, szArg: Integer;
    smmiS, smSelfNode, mselfArg, mcCtorCi, parenRec, ctorCi, ctorArgN: Integer;
    nestCtorCi: Integer;   { `TOuter.TInner.Create` — the nested class, resolved by scope }
    nestScanCi, nestScanPos, nestDepth, nestI: Integer;   { …walking N levels of it }
    mthName: AnsiString;   { @TClass.Method — name read via GetTokenStr (may be a type keyword) }
    mcCtorNm: AnsiString;
    nArgs, argsHead, currArg: Integer; argTypes: array[0..MAX_PROC_PARAMS-1] of TTypeKind;
    kwIdx, slotIdx: Integer;   { NilPy keyword argument: binding+1, and the param it fills }
    ci, mmi, mpi, mcallNode, mlastArg, smSelfIdx, smselfArg: Integer;
    aliasIdx, fieldNode, indexNode, baseNode, baseRec, fIdx, mci, margSeq, margIdx, mexprNode, mai, pri, qUnit: Integer;
    fieldName, methName: AnsiString; isAssign: Boolean; castTk: TTypeKind;
    liftedVar, identNode, addrNode: Integer;
    rcCi, rcMmi, rcPi, rcTmp, rcSelf, rcSelfArg, savedRecId: Integer;   { advanced-record ctor call }
    castTk2: TTypeKind;   { postfix tail on a record-factory result }
    helperPi, sci: Integer;
    isLiftedCall: Boolean;
    bitNot, opIsArith: Boolean; notOp: Integer; notOrdTk: TTypeKind;
    szAi, szFlatLen, szDi, szBrDepth, szNIdx, szBase, szRec, szQUnit: Integer;
    mcCi: Integer; mcFin: Boolean;   { metaclass receiver at the end of a cast-deref chain }
 szElemTk: TTypeKind; szBTk: TTypeKind;
    seEtid, seOrd: Integer;
    dfSym, dfRec, dfAi: Integer; dfTk: TTypeKind; dfSaveStatic: Boolean;  { Default(T) over an aggregate }
    lenFieldRec, lenFieldIdx: Integer;   { Length() of a static-array record field }
    cpyPi: Integer;   { Copy(s,i,n)[k]: the __pxxStrCopy proc index, kept past ci's reuse }
    ccReg, ccNode: Integer; ccKey: AnsiString; ccTk: TTypeKind;   { bare class-const in a method body }
    mapProc, mapConv: Integer; mapKind: AnsiString;   { NilPy map(<type>, xs) }
    rndArg: Integer;   { first operand of NilPy round(x, n) }
    rndIntArg: Boolean;      { …and was it an INTEGER? then round is identity }
    rndArgTk, rndRawTk: TTypeKind;   { its type, to restore after the identity }
    fwdList, fwdDict: Integer;   { `f(*args, **kwargs)` forwarded into fixed parameters }
    vcNode: Integer;   { a typecast of a VARIANT, rewritten as the conversion }
    tiName: AnsiString; tiTk: TTypeKind;   { widened TypeInfo(T): scalar/string/class/record }
    pyLateDefPi: Integer;   { NilPy def not yet bound at this call site; -1 = none }
begin
  { NilPy runs its own copy of this routine (pyparser.inc). The dispatch is
    here rather than at the call sites so that every caller — and every
    recursive re-entry through the expression layers — stays untouched. }
  if PyExprMode then
  begin
    PyParseFactorCore;
    Exit;
  end;
  LastExprTk := tyInteger;
  case CurTok.Kind of
    tkInteger:
    begin
      node := AllocNode(AN_INT_LIT); ASTIVal[node] := CurTok.IVal;
      { A literal wider than Int64 carries its DIGIT TEXT (the lexer sets SVal
        only in that case). ASTIVal holds the wrapped 64-bit reading, which is
        still the right QWord value; the span lets a promotable-int target take
        the exact value instead (feature-a-promoint-wide-literals). }
      { A literal that does not fit a signed 32-bit Integer is an Int64; the
        i386 backend keys its 64-bit codegen off this type. }
      if (CurTok.IVal > 2147483647) or (CurTok.IVal < -2147483648) then
        ASTTk[node] := Ord(tyInt64)
      else
        ASTTk[node] := Ord(tyInteger);
      if Tokens[TokPos - 1].SLen > 0 then
      begin
        ASTSOffset[node] := Tokens[TokPos - 1].SOffset;
        ASTSLen[node] := Tokens[TokPos - 1].SLen;
        { Force Int64 even though the WRAPPED value may look small: 2^64 wraps
          to 0 and would otherwise be typed tyInteger, which is both wrong and
          indistinguishable from a char literal's char-pool span. }
        ASTTk[node] := Ord(tyInt64);
      end;
      CurASTNode := node; Next;
    end;
    tkLBrack:
    begin
      CurASTNode := ParseSetLiteralAST;
      LastExprTk := tySet;
    end;
    tkBegin:
    begin
      Error('unexpected begin in expression');
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
          { An UNSPECIALIZED generic template is not a type — it has no size and no zero
            value, so Default(TTest) is undefined (tdefault11/12). `Default(TTest<Integer>)`
            (delphi) is fine, hence the '<' lookahead; the objfpc form starts with
            `specialize`, so CurTok is not the template name there. }
          if IsGenericTemplateName(CurTok.SVal) and
             not ((TokPos < TokCount) and (Tokens[TokPos].Kind = tkLt)) then
            Error('Default: the generic type ' + CurTok.SVal + ' must be specialized');
        end;
        { An AGGREGATE type has no integer zero: `Default(TRec)` used to yield
          the same INT_LIT 0 as `Default(Integer)`, and the record assignment
          then copied RecSize bytes from address 0 -- a SEGFAULT. A static
          array was worse, because it was silent: `ar := Default(TArr)` stored
          an integer into an array slot and left every element untouched, so a
          dirty array stayed dirty and nothing said so.

          Zero of an aggregate is a whole zeroed OBJECT, so materialise one:
          a hidden static (BSS, therefore zero-filled at load) variable of that
          exact type, which nothing can ever write to -- Default() is an rvalue,
          so it cannot be passed by reference or assigned through. The ordinary
          record/array copy then does the rest, managed fields included.
          A CLASS is not an aggregate here (IsRecordType excludes it) and keeps
          the integer 0, which is its correct nil.
          bug-p-default-of-a-record-segfaults-of-an-array-does-nothing }
        dfSym := -1;
        dfTk := tyInt64;
        if CurTok.Kind = tkIdent then
        begin
          dfRec := IsRecordType(CurTok.SVal);
          if dfRec <> REC_NONE then
          begin
            dfSaveStatic := AllocStaticLocal;
            AllocStaticLocal := True;
            LastTypeRecId := dfRec;
            LastTypeIsSub := False;
            dfSym := AllocVar('', tyRecord);
            AllocStaticLocal := dfSaveStatic;
            dfTk := tyRecord;
          end
          else
          begin
            dfAi := FindArrayType(CurTok.SVal);
            if (dfAi >= 0) and (not ArrTypeIsDyn[dfAi]) then
            begin
              { A FIXED array alias. Multi-dimensional and row-element forms
                carry shape AllocArray cannot rebuild from lo/hi alone -- refuse
                those LOUDLY rather than fall back to the integer 0 that made
                this a silent bug in the first place. }
              if (ArrTypeNDims[dfAi] > 1) or (ArrTypeElemRowLen[dfAi] <> 0) then
                Error('Default: multi-dimensional array types are not supported yet');
              dfSaveStatic := AllocStaticLocal;
              AllocStaticLocal := True;
              LastTypeRecId := ArrTypeElemRec[dfAi];
              LastTypeIsSub := False;
              LastTypeElemDynDepth := 0;
              dfSym := AllocArray('', IntToTypeKind(ArrTypeElemTk[dfAi]),
                                  ArrTypeLo[dfAi], ArrTypeHi[dfAi]);
              AllocStaticLocal := dfSaveStatic;
              dfTk := IntToTypeKind(ArrTypeElemTk[dfAi]);
            end;
          end;
        end;
        if dfSym >= 0 then
        begin
          node := AllocNode(AN_IDENT);
          ASTIVal[node] := dfSym;
          ASTTk[node] := Ord(dfTk);
        end
        else
        begin
          node := AllocNode(AN_INT_LIT);
          ASTIVal[node] := 0;
          ASTTk[node] := Ord(tyInt64);
        end;
        i := 1;
        while (i > 0) and (CurTok.Kind <> tkEOF) do
        begin
          if CurTok.Kind = tkLParen then Inc(i)
          else if CurTok.Kind = tkRParen then Dec(i);
          if i > 0 then Next;
        end;
        Expect(tkRParen, ')');
        CurASTNode := node;
        LastExprTk := dfTk;
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
        { Record the method's VMT slot (>=0 virtual, -1 non-virtual) so the code
          pointer resolves through the object's VMT at runtime, not the static base
          address — `@baseref.VirtualMethod` must capture the derived override
          (bug-a-method-pointer-virtual-captures-static-address). }
        ASTRight[node] := UMthVirSlot[mmi];
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
        ASTRight[node] := UMthVirSlot[mmi];   { VMT slot (>=0 virtual): resolve via VMT }
        ASTTk[node] := Ord(tyPointer);
        Next;            { consume method name }
        CurASTNode := node;
        LastExprTk := tyPointer;
      end
      { @TClass.Method — the method's raw CODE address, reached through the TYPE
        name rather than an instance. No Data half and no VMT lookup: with no
        object there is nothing to dispatch on, so FPC yields the static address
        of that class's own implementation even for a virtual method, which is
        exactly what makes the idiom useful — hand-built VMTs (rtl-generics'
        Generics.Defaults fills its IComparer VMT records with
        `@TRawInterface._AddRef` and friends).

        Guarded on idx < 0 so a VARIABLE of the same name keeps the @obj.method
        path above; a class TYPE is not in the sym table, which is precisely why
        this used to fall through to ParseLValueAST and get diagnosed as
        `cannot call non-static method on class type directly` — the @ never
        reached the decision, so taking an address was read as calling. }
      else if (idx < 0) and (TokPos < TokCount) and (Tokens[TokPos].Kind = tkDot) and
              (FindUClass(name) >= 0) then
      begin
        ci := FindUClass(name);
        Next;            { consume class name (CurTok = '.') }
        Next;            { consume '.' (CurTok = method name) }
        { A method may be NAMED after a type keyword (generics.defaults'
          `TCompare.Single`), and those tokens carry an empty SVal — read the
          name via GetTokenStr, never SVal. }
        if not IsMethodNameTok then Error('expected method name after @' + name + '.');
        mthName := GetTokenStr(TokPos - 1);
        mmi := FindUMeth(ci, mthName);
        if mmi < 0 then Error('@' + name + '.' + mthName + ': unknown method');
        node := AllocNode(AN_PROCADDR);
        ASTIVal[node] := UMthProc_[mmi];
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
      Next; ParseExpr;
      { C comma operator `(a, b, ...)`: each operand but the last is evaluated for
        its side effects then discarded; the value is the last. A parenthesised
        comma list is otherwise a syntax error in pxx, so this is conflict-free
        and reads identically to C. Right-nested AN_COMMA so lowering discards
        each Left in turn. }
      if (CurTok.Kind = tkComma) then
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
      while ((CurTok.Kind = tkCaret) or
             (CurTok.Kind in [tkDot, tkLBrack])) do
      begin
        { A grouped value whose type is a CLASS goes to the real member/index dispatcher --
          `(Data as TJSONArray)[0].ClassType` (fcl-json's suite).

          This tail used to hand-roll `.` and `[` itself, and it did so WITHOUT the class id:
          ResolveNodeRec has always known an as-cast's class, but the tail never asked. So
          `(b as T)[i]` built a raw AN_INDEX instead of dispatching the DEFAULT PROPERTY --
          leaving the AN_AS_CAST orphaned and unlowerable -- and `(b as T).Member` silently
          DROPPED an unresolvable member and evaluated to the object pointer.

          It was the THIRD copy of member/index dispatch (ParseLValueAST's suffix loop,
          ParseClassRecordSelectors, and this). The duplication was the bug, so this hands off
          rather than growing a fourth: default properties, virtual methods, properties and the
          class-reference ops all come along for free, and cannot drift again. }
        if (CurTok.Kind in [tkDot, tkLBrack]) then
        begin
          parenRec := ResolveNodeRec(node);
          if parenRec >= REC_UCLASS_BASE then
          begin
            tk := IntToTypeKind(ASTTk[node]);
            node := ParseClassRecordSelectors(node, parenRec, tk);
            recName := ResolveNodeRec(node);
            Continue;
          end;
        end;

        if CurTok.Kind = tkCaret then
        begin
          Next;
          indexNode := AllocNode(AN_DEREF);
          ASTLeft[indexNode] := node;
          { Resolve the pointee type from the inner node, mirroring the direct
            `ident^` path. NodePtrElem sees through pointer ARITHMETIC as well:
            this used to handle only a bare ident or `arr[i]` and default a binop
            to Integer, which is right for a ^Integer and a wrong SPAN for every
            other pointer — `(pc + 2)^` read four bytes.
            bug-p-a-pchar-plus-offset-loses-its-type-when-dereferenced }
          tk := tyInteger; recName := REC_NONE;
          if not NodePtrElem(node, tk, recName, 0) then
          begin
            { still no pointee to be had — Integer, as before }
            tk := tyInteger; recName := REC_NONE;
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
            begin
              mmi := FindUMethOverloadAhead(mci, fieldName, CountCallArgsAhead);
              if isNilPy and (mmi >= 0) then
                mmi := PyPromoteOverloadByKwAt(mci, mmi, PyKwNamesTokPos, fieldName);
            end;
          end;
          if (mmi >= 0) and (mci >= 0) then EnforceMethVis(mmi, fieldName);
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
              { `obj.F()` -- EMPTY parens on a method whose parameters ALL have defaults. FPC
                accepts it (fcl-json's own suite calls `J.FormatJSON()`); without this the loop hands
                the `)` to ParseExpr and reports "expected expression". A method with NO parameters
                already worked, because the loop simply never ran. }
              if CurTok.Kind = tkRParen then
              begin
                if (Procs[mpi].ParamCount > 1) and CanFillDefaultsFrom(mpi, 1) then
                  FillDefaultArgs(mpi, 1, mcallNode, mlastArg);
                mai := Procs[mpi].ParamCount;   { nothing to parse; Expect(tkRParen) consumes it }
              end;
              { `d.update(a=1)` / `d.update(**e)` — the keywords-are-KEYS case,
                asked the same way every other argument loop asks it. }
              if PyKwDictArgsHere(mpi) then
              begin
                margSeq := AllocNode(AN_ARG);
                ASTLeft[margSeq] := PyBuildKeywordDictHere;
                ASTIVal[margSeq] := 0;
                ASTRight[mlastArg] := margSeq; mlastArg := margSeq;
                mai := Procs[mpi].ParamCount;
              end;
              { `obj.m(*xs)` — a call-site UNPACK (the callee declares ordinary
                parameters; the star is on the CALL). A star is not an expression, so
                the arity loop below cannot parse it: hand the whole argument list to
                the NilPy path, which expands the list across the remaining slots. }
              if isNilPy and (mai <= Procs[mpi].ParamCount-1) and PyStarArgAhead then
                PyStarUnpackMethodArgs(mpi, mcallNode, mlastArg, mai);
              while mai <= Procs[mpi].ParamCount-1 do
              begin
                if Procs[mpi].Params[mai].IsRef or Procs[mpi].Params[mai].IsArray then
                begin
                  if ByRefArgStartsExpression(ParamIsConstVariant(mpi, mai)) then
                  begin
                    { non-ident by-ref/array arg (@obj.Method to a method-pointer
                      param, [..] literals, casts): parse as an expression }
                    ParseArgExpr; mexprNode := CurASTNode;
                  end
                  else
                  begin
                    margIdx := FindSym(CurTok.SVal); Next;
                    mexprNode := ParseLValueAST(margIdx, TokPos - 2);
                  end;
                end
                else begin ParseArgExpr; mexprNode := CurASTNode; end;
                SetLitCheckArg(mexprNode, mpi, mai);
                margSeq := AllocNode(AN_ARG); ASTLeft[margSeq] := mexprNode;
                if mlastArg = -1 then ASTLeft[mcallNode] := margSeq
                else ASTRight[mlastArg] := margSeq;
                mlastArg := margSeq;
                if (mai < Procs[mpi].ParamCount-1) and CanFillDefaultsFrom(mpi, mai+1) then
                begin
                  FillDefaultArgs(mpi, mai+1, mcallNode, mlastArg);
                  mai := Procs[mpi].ParamCount-1;
                end
                else if mai < Procs[mpi].ParamCount-1 then Expect(tkComma, ',')
              else if isNilPy and (CurTok.Kind = tkComma) then Next;  { Python trailing comma }
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
              { `obj.F()` -- EMPTY parens on a method whose parameters ALL have defaults. FPC
                accepts it (fcl-json's own suite calls `J.FormatJSON()`); without this the loop hands
                the `)` to ParseExpr and reports "expected expression". A method with NO parameters
                already worked, because the loop simply never ran. }
              if CurTok.Kind = tkRParen then
              begin
                if (Procs[mpi].ParamCount > 1) and CanFillDefaultsFrom(mpi, 1) then
                  FillDefaultArgs(mpi, 1, mcallNode, mlastArg);
                mai := Procs[mpi].ParamCount;   { nothing to parse; Expect(tkRParen) consumes it }
              end;
              nArgs := 0;
              while mai <= Procs[mpi].ParamCount - 1 do
              begin
                { NilPy `key=expr` here too. This is the loop a receiver reached
                  through a FIELD lands in (`self.canvas.create_window(...)`),
                  and it was the one method-call path with no keyword binding —
                  so an ordinary tkinter call worked through a local and failed
                  through a field (bug-nilpy-kwargs-on-a-field-receiver). }
                kwIdx := PyKwArgIndex(mpi, 1);
                if kwIdx > 0 then slotIdx := kwIdx - 1 else slotIdx := mai;
                if Procs[mpi].Params[slotIdx].IsRef or Procs[mpi].Params[slotIdx].IsArray then
                begin
                  if ByRefArgStartsExpression(ParamIsConstVariant(mpi, slotIdx)) then
                  begin
                    { non-ident by-ref/array arg (@obj.Method to a method-pointer
                      param, [..] literals, casts): parse as an expression }
                    ParseArgExpr; mexprNode := CurASTNode;
                  end
                  else
                  begin
                    margIdx := FindSym(CurTok.SVal); Next;
                    mexprNode := ParseLValueAST(margIdx, TokPos - 2);
                  end;
                end
                else begin ParseArgExpr; mexprNode := CurASTNode; end;
                margSeq := AllocNode(AN_ARG); ASTLeft[margSeq] := mexprNode;
                ASTIVal[margSeq] := kwIdx;
                ASTRight[mlastArg] := margSeq; mlastArg := margSeq;
                Inc(nArgs);
                if (kwIdx = 0) and (mai < Procs[mpi].ParamCount-1) and
                   CanFillDefaultsFrom(mpi, mai+1) then
                begin
                  FillDefaultArgs(mpi, mai+1, mcallNode, mlastArg);
                  mai := Procs[mpi].ParamCount-1;
                end
                else if mai < Procs[mpi].ParamCount-1 then
                begin
                  if isNilPy and (CurTok.Kind = tkRParen) then Break;
                  Expect(tkComma, ',');
                end
              else if isNilPy and (CurTok.Kind = tkComma) then Next;  { Python trailing comma }
                Inc(mai);
              end;
              { reorder keyword arguments into declaration order and fill the
                holes below the highest bound parameter }
              margSeq := ASTRight[ASTLeft[mcallNode]];   { first REAL arg (past Self) }
              if margSeq >= 0 then
              begin
                PyBindKwArgs(mpi, margSeq, mlastArg, nArgs);
                ASTRight[ASTLeft[mcallNode]] := margSeq;
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
              if UPropIsIndexed[pri] then ParsePropIndexArgs(margIdx, mlastArg)
            else PropIndexConstArg(pri, margIdx, mlastArg);
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
      node := AllocNode(AN_NEG); ASTLeft[node] := left;
      { Carry the operand's type, as the additive-level sign in ParseSimpleExpr
        does. Left untagged, `-(a // b)` on an Int64-returning helper printed
        18446744073709551613 instead of -3 — the untyped node read unsigned.

        ...except for an INTEGER operand, where FPC widens to Int64 first and
        carrying the operand's type is the bug. Measured, every integer type:
        `SizeOf(-x)` is 8 for Byte, ShortInt, Word, SmallInt, Integer, Cardinal,
        Int64, QWord, NativeInt and NativeUInt alike — FPC's unary minus has ONE
        result type. Carrying an unsigned operand's own width instead negated
        inside it, so `-b shr 1` on a Byte answered 2147483644 ($7FFFFFFC, a
        32-bit logical shift of $FFFFFFF8) where FPC says 9223372036854775804:
        the sign was gone before the shift ever ran, which is why the shift path
        was never where this could be fixed.

        The default dialect, not behind --strict-fpc: a silent wrong VALUE is a
        bug, not parity work (decide-unary-minus-widening-in-the-default-dialect,
        confirmed by the owner 2026-08-19).

        Deliberately NOT widened: tyBoolean and tyBool8 (not arithmetic),
        tyPointer (no sign), the promotable ints (already arbitrary precision,
        so a width has no meaning), and every float — where the operand type IS
        the result type. bug-p-unary-minus-on-an-unsigned-operand-truncates-to-32-bits }
      { A negated CONSTANT is the exception, and it is not a small one: FPC folds
        a constant expression and gives the result the SMALLEST SIGNED type that
        holds the value, so `-1` is a LongInt and stays one. Widening it changed
        three measured behaviours at once -- `IntToHex(-1, 8)` printed 16 digits
        because the Int64 overload won, `-7` in an `array of const` arrived as
        vtInt64 so a vtInteger reader skipped it, and the overload-width table
        moved its literal row to int64. All three are LongInt under FPC, and all
        three came back from Track T within the hour
        (regression-test-core-test-asm-emit and its two siblings). The widening
        below is about a negated VARIABLE, where FPC really does have one result
        type -- `-b` on a Byte is Int64 while `-7` is not. }
      if ASTConstIntValue(left, negConstVal, 0) then
      begin
        negConstVal := -negConstVal;
        if (negConstVal >= -2147483648) and (negConstVal <= 2147483647) then
          ASTTk[node] := Ord(tyInteger)
        else
          ASTTk[node] := Ord(tyInt64);
      end
      else if NegWidensToInt64(IntToTypeKind(ASTTk[left])) then ASTTk[node] := Ord(tyInt64)
      else ASTTk[node] := ASTTk[left];
      { {$Q+} region: unary minus is overflow-checked too. FPC raises
        EIntOverflow on `-Low(Int64)` and on nothing else once the widening
        above is in place — every narrower type's negation fits an Int64.
        The check itself is not a new IR op: ir.inc rewrites a tagged AN_NEG
        into `0 - x`, the same rewrite the promotable-int and variant arms
        already use, so the existing IR_BINOP check runs and no backend moves.
        feature-pascal-overflow-checks-q-plus }
      if TokQChecks[TokPos - 1] then ASTQChk[node] := True;
      CurASTNode := node;
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
                   (notOp = Ord(tkIdent)) or
                   { and/or/xor are distrusted in general because a LOGICAL
                     and/or is sometimes mistagged tyInteger (self-host relies
                     on those staying logical — trusting all integer-tagged
                     and/or breaks the fixedpoint). But an EXPLICIT sized type
                     tag (tyInt8..tyNativeUInt, 7..16) never comes from that
                     mistag — it means both operands really are that integer
                     type — so `not (q3 or q4)` on qwords is bitwise
                     (tint642's testnotqword printed a boolean flip). Plain
                     tyInteger(1)-tagged and/or/xor stays logical. }
                   (((notOp = Ord(tkAnd)) or (notOp = Ord(tkOr)) or
                     (notOp = Ord(tkXor))) and
                    (ASTTk[left] >= 7) and (ASTTk[left] <= 16));
      bitNot :=
        ((ASTTk[left] = 1) or ((ASTTk[left] >= 7) and (ASTTk[left] <= 16))) and
        ((ASTKind[left] = AN_INT_LIT) or (ASTKind[left] = AN_IDENT) or
         { An ARRAY ELEMENT, a record/class FIELD and a DEREF carry the declared type of
           the element / field / pointee, which is exactly as authoritative as a variable's
           — and they were missing from this list, so `not arr[i]` and `not rec.f` were
           lowered as a BOOLEAN not. `not rb[0]` printed TRUE, and `mask[i] and not
           rhs[i]` silently produced garbage: bit manipulation on array elements (masks,
           hashing, crypto) was quietly wrong while the same code on a plain variable was
           right. The tyBoolean guard above still keeps a genuine Boolean element logical. }
         (ASTKind[left] = AN_INDEX) or (ASTKind[left] = AN_FIELD) or
         (ASTKind[left] = AN_DEREF) or
         { a nested BITWISE not: its integer tag (checked above) is ours to
           trust — `not(not(q))` flipped the outer one to boolean (tint642
           error 2701). An inner LOGICAL not is tyBoolean and never gets here. }
         (ASTKind[left] = AN_NOT) or
         ((ASTKind[left] = AN_PTR_CAST) and
          ((Integer(ASTIVal[left]) = -1) or (Integer(ASTIVal[left]) = -3))) or
         ((ASTKind[left] = AN_CALL) and
          ((Integer(ASTIVal[left]) = -Ord(tkInteger_T)) or
           (Integer(ASTIVal[left]) = -Ord(tkLongWord_T)) or
           { Ord(x) is an integer by definition — it was missing here, so
             `not ord(e)` lowered as a BOOLEAN not (xor 1): silently wrong
             integers in any hash/mask over an ordinal
             (bug-pascal-not-of-ord-uses-boolean-negation). }
           (Integer(ASTIVal[left]) = -Ord(tkOrd)))) or
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
        { FPC complements `ord(x)` at the OPERAND's width: ord(char/boolean) is
          byte-sized (`not ord('a')` = 158, not -98); a subword/64-bit integer
          operand keeps its own width; an enum stays the 4-byte default. }
        if (ASTKind[left] = AN_CALL) and (Integer(ASTIVal[left]) = -Ord(tkOrd)) then
        begin
          notOrdTk := IntToTypeKind(ASTTk[ASTLeft[ASTLeft[left]]]);
          if (notOrdTk = tyChar) or (notOrdTk = tyBoolean) then
            ASTTk[node] := Ord(tyUInt8)
          else if (Ord(notOrdTk) >= 7) and (Ord(notOrdTk) <= 16) then
            ASTTk[node] := Ord(notOrdTk);
        end;
        LastExprTk := IntToTypeKind(ASTTk[node]);
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
        { demote a promotable operand first — see PromoDemoteToInt64 }
        CurASTNode := PromoDemoteToInt64(CurASTNode);
        vcNode := VariantCastToTemp(CurASTNode, tyUInt8);   { Byte(v) converts }
        if vcNode >= 0 then
        begin
          CurASTNode := vcNode;
          LastExprTk := tyUInt8;
        end
        else
        begin
          node := AllocNode(AN_PTR_CAST);
          ASTLeft[node] := CurASTNode;
          ASTIVal[node] := -1;
          ASTTk[node] := Ord(tyUInt8);
          CurASTNode := node;
          LastExprTk := tyUInt8;
        end;
      end
      else if CaseEqual(CurTok.SVal, 'longword') then
      begin
        Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
        { demote a promotable operand first — see PromoDemoteToInt64 }
        CurASTNode := PromoDemoteToInt64(CurASTNode);
        vcNode := VariantCastToTemp(CurASTNode, tyUInt32);   { LongWord(v) converts }
        if vcNode >= 0 then
        begin
          CurASTNode := vcNode;
          LastExprTk := tyUInt32;
        end
        else
        begin
          node := AllocNode(AN_PTR_CAST);
          ASTLeft[node] := CurASTNode;
          ASTIVal[node] := -1;
          ASTTk[node] := Ord(tyUInt32);
          CurASTNode := node;
          LastExprTk := tyUInt32;
        end;
      end
      else
      begin
        op := Ord(CurTok.Kind);
        Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
        { a promotable operand demotes before the pun — see PromoDemoteToInt64 }
        CurASTNode := PromoDemoteToInt64(CurASTNode);
        { …and a VARIANT operand is a CONVERSION, not a pun — see
          VariantCastToTemp. Same Exit shape as the Explicit-operator arm
          just below. }
        vcNode := VariantCastToTemp(CurASTNode, tyInteger);
        if vcNode >= 0 then
        begin
          CurASTNode := vcNode;
          LastExprTk := tyInteger;
          Exit;
        end;
        { `operator Explicit(a: TFoo): Integer` — an Integer(recordValue)
          cast with a matching Explicit overload is the conversion CALL
          (toperator11), not the value-pun. }
        if ((IntToTypeKind(ASTTk[CurASTNode]) = tyRecord) or
            (IntToTypeKind(ASTTk[CurASTNode]) = tyClass)) then
        begin
          i := FindOpOverload(OPK_EXPLICIT, ASTTk[CurASTNode], ResolveNodeRec(CurASTNode));
          if (i >= 0) and TypeIsOrdinal(Procs[i].RetType) then
          begin
            argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
            node := AllocNode(AN_CALL); ASTIVal[node] := i;
            ASTTk[node] := Ord(Procs[i].RetType);
            ASTLeft[node] := argSeq;
            CurASTNode := node;
            LastExprTk := Procs[i].RetType;
            Exit;
          end;
        end;
        { `Integer(x)` is a NARROWING cast the moment x is wider than 32 bits
          or 32-bit UNSIGNED, and FPC truncates it: Integer(LongWord(4000000000))
          is -294967296. The pun below hands the bit pattern through untouched,
          so it answered 4000000000 -- while `LongInt(x)`, the exact synonym,
          was right all along, because `longint` is not a type TOKEN and took
          the identifier path into a real AN_PTR_CAST. One concept, two
          spellings, and the fix for the other spellings (byte/longword, in
          bug-narrowing-typecast-rvalue-no-truncate) deliberately left this one
          alone -- which is precisely how the second path stays broken.
          An operand that cannot change value under the cast (a signed 32-bit
          or narrower ordinal, Char, Boolean) keeps the pun, so the common
          `Integer(someInteger)` emits no masking at all.
          bug-p-integer-cast-does-not-truncate-in-rvalue-position }
        castTk := IntToTypeKind(ASTTk[CurASTNode]);
        if TypeIsOrdinal(castTk) and (castTk <> tyBoolean) and (castTk <> tyChar) and
           ((TypeSize(castTk) > 4) or
            ((TypeSize(castTk) = 4) and not TypeSigned(castTk))) then
        begin
          node := AllocNode(AN_PTR_CAST);
          ASTLeft[node] := CurASTNode;
          ASTIVal[node] := -1;
          ASTTk[node] := Ord(tyInteger);
          CurASTNode := node;
          LastExprTk := tyInteger;
          Exit;
        end;
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
      { demote a promotable operand first, or the pun takes the low byte of the
        SLOT ADDRESS — `Char(n)` for n = 65 gave a character from the pointer,
        not 'A'. See PromoDemoteToInt64. }
      CurASTNode := PromoDemoteToInt64(CurASTNode);
      { a VARIANT operand converts instead of punning — see VariantCastToTemp.
        `Char(v)` punned the tag word into a control character and `Boolean(v)`
        was right only by accident (a non-zero tag reads as True). }
      if op = Ord(tkChar_T) then castTk := tyChar else castTk := tyBoolean;
      vcNode := VariantCastToTemp(CurASTNode, castTk);
      if vcNode >= 0 then
      begin
        CurASTNode := vcNode;
        LastExprTk := castTk;
      end
      else
      begin
        node := AllocNode(AN_CALL); ASTIVal[node] := -op;
        if op = Ord(tkChar_T) then ASTTk[node] := Ord(tyChar) else ASTTk[node] := Ord(tyBoolean);
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
        ASTLeft[node] := argSeq;
        CurASTNode := node;
      end;
    end;
    tkSingle_T, tkDouble_T, tkExtended_T:
    begin
      { Value typecast to a float type, `Single(expr)` / `Double(expr)`. Unlike
        the integer/char puns this is a real conversion (int->float, or
        double->single narrowing), so desugar to a hidden temp of the cast type
        plus an assignment — the ordinary store path already coerces the operand.
        Reuses the generic assign-then-yield node (AN_STR_FROM_CHAR: Left = the
        store side-effect, Right = the temp read). `Extended` aliases Double. }
      { The temp's type is the CAST's, not the OPERAND's: `ParseExpr` overwrites
        LastExprTk with the operand's kind, so `op := AllocVar('', LastExprTk)`
        handed the "conversion" a temp of the source type and the conversion
        never happened — `Single(d)` in expression position printed the
        unnarrowed double (3.7000000000 vs FPC's 3.7000000480), and for a
        VARIANT operand it built a VARIANT temp, so `Double(v)` stored the
        16-byte record through an 8-byte value and SEGFAULTED. Capturing the
        kind before ParseExpr fixes both: a variant temp becomes a real Double
        temp, and the store path then emits the variant unbox by itself.
        bug-p-a-typecast-of-a-variant-reinterprets-it-instead-of-converting }
      if CurTok.Kind = tkSingle_T then castTk := tySingle else castTk := tyDouble;
      LastExprTk := castTk;
      Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
      LastExprTk := castTk;
      op := AllocVar('', castTk);
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
      begin
        { A VARIANT operand is the variant->string CONVERSION (FPC's
          `String(v)`), which the store into a string temp already emits —
          see VariantCastToTemp. Before this it was a hard error. }
        vcNode := VariantCastToTemp(CurASTNode, tyString);
        if vcNode >= 0 then
        begin
          CurASTNode := vcNode;
          LastExprTk := tyString;
        end
        else if IntToTypeKind(ASTTk[CurASTNode]) = tyPointer then
        begin
          { `String(p)` on a PChar -- the NUL-terminated-to-Pascal conversion.
            PChar is tyPointer here, so it fell to the error below, while every
            other spelling of the same conversion worked: `AnsiString(p)`, the
            implicit `s := p`, and `StrPas(p)`. One concept, four spellings, and
            the one FPC code actually writes was the broken one -- exactly the
            shape devdocs/dev/normalise-dont-special-case.md is about, and the
            reason it survived is that `String` is a KEYWORD token (tkString_T)
            with its own branch, so it never reached the identifier-cast path
            where `ansistring` is handled. Build the same AN_PTR_CAST that path
            builds, with the same managed/frozen choice of string kind.
            bug-p-string-of-a-pchar-is-rejected-while-ansistring-of-it-works }
          node := AllocNode(AN_PTR_CAST);
          ASTLeft[node] := CurASTNode;
          ASTIVal[node] := -1;              { built-in cast, as the ident path does }
          if PasDefineExists('PXX_MANAGED_STRING') then
            ASTTk[node] := Ord(tyAnsiString)
          else
            ASTTk[node] := Ord(tyString);
          CurASTNode := node;
          LastExprTk := IntToTypeKind(ASTTk[node]);
        end
        else
          Error('String(): operand must be Char or string');
      end;
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
      node := AllocNode(AN_CALL); ASTIVal[node] := -Ord(tkArgCount);
      { ParamCount is an Integer, and the node has to SAY so. Left unset it
        defaulted to tyUnknown, and anything that materialises the value into a
        hidden temp copied that: `for i := 0 to ParamCount do` gave the loop
        LIMIT temp no type. x86-64 and the other backends do not inspect it and
        happened to work; i386 checks every symbol it touches, so it refused —
        which is why `uses pylib` could not be built for i386 AT ALL (pylib's
        pysys_argv is exactly this loop), taking base64, http and
        examples/net/httpdemo.pas with it, and every NilPy program besides.
        The tkArgStr arm below never had the bug because it allocates its
        destination temp explicitly typed. Hoisting the limit into a variable,
        or using a USER function as the limit, both worked — that pair is what
        localised it here rather than to the for-loop lowering.
        bug-a-paramcount-node-has-no-type-so-i386-refuses-any-pylib-user }
      ASTTk[node] := Ord(tyInteger);
      CurASTNode := node;
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
      if NilPyUserCode and (name = '__name__') then
      begin
        { compiled as the main program, so __name__ is always "__main__". }
        Next;
        node := AllocNode(AN_STR_LIT);
        ASTSOffset[node] := PyStoredName('__main__'); ASTSLen[node] := 8;
        ASTTk[node] := Ord(tyString);
        CurASTNode := node; LastExprTk := tyString;
        Exit;
      end;
      if NilPyUserCode and (name = '__file__') then
      begin
        { __file__ — derived from the RESOLVED executable at run time, never
          from the source path the compiler happened to see, which would leak
          the build environment into every shipped binary.
          decide-nilpy-dunder-file-for-a-compiled-program

          MAIN module: the executable itself, so os.path.exists(__file__) is
          True. IMPORTED module: <exe_dir>/<module>.py, a VIRTUAL path — no
          file is there, but os.path.dirname(os.path.abspath(__file__)), the
          only form real code uses, is the executable's directory for every
          module. Both are the freezer convention (PyInstaller/cx_Freeze).

          CurrentUnitIdx is the seam: >= 0 means "parsing an imported unit",
          which is the same test every other main-module-only NilPy rule uses. }
        Next;
        if CurrentUnitIdx >= 0 then
        begin
          idx := FindProc('pysys_module_file');
          if idx < 0 then
            Error('Nil Python: pylib (pysys_module_file) not loaded');
          valNode := AllocNode(AN_STR_LIT);
          ASTSOffset[valNode] :=
            PyStoredName(LowerCase(Strs[CurrentUnitIdx].Text) + '.py');
          ASTSLen[valNode] := Length(Strs[CurrentUnitIdx].Text) + 3;
          ASTTk[valNode] := Ord(tyString);
          argSeq := AllocNode(AN_ARG);
          ASTLeft[argSeq] := valNode;
          ASTRight[argSeq] := -1;
          node := AllocNode(AN_CALL);
          ASTIVal[node] := idx;
          ASTTk[node] := Ord(tyAnsiString);
          ASTLeft[node] := argSeq;
          CurASTNode := node; LastExprTk := tyAnsiString;
          Exit;
        end;
        node := AllocNode(AN_CALL);
        idx := FindProc('pysys_file');
        if idx < 0 then Error('Nil Python: pylib (pysys_file) not loaded');
        ASTIVal[node] := idx; ASTTk[node] := Ord(tyAnsiString); ASTLeft[node] := -1;
        CurASTNode := node; LastExprTk := tyAnsiString;
        Exit;
      end;
      if NilPyUserCode and (name = 'pystr_of') and (TokPos < TokCount) and
         (Tokens[TokPos].Kind = tkLParen) then
      begin
        { f-string hole: the LEXER desugars {x} to pystr_of(x), so the semantic
          rewrites str()/print() apply to a CLASS argument (Exception -> .msg,
          container -> repr) never fired here — an exception or a list inside
          an f-string rendered as an empty string
          (feature-nilpy-exception-message-text). Parse the argument; when a
          class rewrite applies the result is already a string, so the
          pystr_of call is dropped (it is the identity on strings). Any other
          argument type REWINDS and takes the ordinary overload path,
          unchanged byte for byte. }
        intBaseArg := TokPos;            { rewind point: CurTok = pystr_of }
        { park the hoist queue across the TRIAL parse — see the len() intercept
          below for what a discarded parse's leftover hoists do }
        lenSavedHoist := PyHoistPark;
        Next; Expect(tkLParen, '('); ParseArgExpr;
        lenTrialHoist := PyHoistPark;
        PyHoistRestore(lenSavedHoist);
        if IntToTypeKind(ASTTk[CurASTNode]) = tyClass then
        begin
          atRecv := ResolveNodeRec(CurASTNode);
          if atRecv >= REC_UCLASS_BASE then
          begin
            { __str__/__repr__ if declared, else an Exception's .msg — the one
              PyClassStrNode decision. This site used to test Exception FIRST
              and read .msg unconditionally, so a user __str__ on an exception
              subclass never ran and an f-string rendered the constructor
              argument instead
              (bug-nilpy-user-str-dunder-on-an-exception-subclass-is-ignored). }
            atDflt := PyClassStrNode(CurASTNode, atRecv - REC_UCLASS_BASE);
            if atDflt >= 0 then
            begin
              PyHoistMerge(lenSavedHoist, lenTrialHoist);   { the trial AST is kept }
              Expect(tkRParen, ')');
              CurASTNode := atDflt; LastExprTk := tyAnsiString;
              Exit;
            end;
            procIdx := -1;
            if atRecv - REC_UCLASS_BASE = FindUClass('TPyList') then
              procIdx := FindProc('pylist_repr')
            else if atRecv - REC_UCLASS_BASE = FindUClass('TPyDict') then
              procIdx := FindProc('pydict_repr')
            else
              { any OTHER user class: CPython's `<__main__.N object at 0x...>`,
                and 'None' for a nil handle — a CLASS-TYPED None, which is what
                a method returning `self` on one path and None on another
                yields. Without it an f-string hole fell through to the ordinary
                overload path and rendered the instance HANDLE as an integer,
                the same arm PyReprContainer had for print().
                bug-nilpy-str-of-a-plain-instance-prints-the-handle-and-a-class-typed-none-prints-zero }
              procIdx := FindProc('pyobj_str_of');
            if procIdx >= 0 then
            begin
              PyHoistMerge(lenSavedHoist, lenTrialHoist);   { the trial AST is kept }
              argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
              node := AllocNode(AN_CALL);
              ASTIVal[node] := procIdx; ASTTk[node] := Ord(tyAnsiString);
              ASTLeft[node] := argSeq;
              Expect(tkRParen, ')');
              CurASTNode := node; LastExprTk := tyAnsiString;
              Exit;
            end;
          end;
        end;
        { no class rewrite: rewind and take the ordinary overload path }
        TokPos := intBaseArg - 1; Next;
      end;
      { ...unless the program declares its own `len`, which REPLACES the
        builtin in Python. A name-keyed intrinsic never consults the symbol
        table, so it could not notice the user's def and the call went to the
        builtin silently (bug-nilpy-user-def-does-not-shadow-a-pylib-builtin).
        Checked here rather than inside, so the dunder rewrite below does not
        run either. }
      if NilPyUserCode and CaseEqual(name, 'len') and (not PyUserShadowsProc(name)) and
         (TokPos < TokCount) and
         (Tokens[TokPos].Kind = tkLParen) then
      begin
        { A class that defines `__len__` must be measured BY IT:
          `len(C())` otherwise falls through to len's ordinary Pascal
          overloads (TPyList/TPyDict/TPyBytes/AnsiString/Variant), none of
          which match a plain class instance -- yet the compiler's overload
          matcher still silently picks SOME overload (observed: the
          TPyList-only one, reading FLen off whatever bytes happen to sit
          at that offset in the instance -- a plausible-looking but WRONG
          number, no diagnostic
          (bug-nilpy-dunder-protocols-ignored-fall-back-to-handle-arithmetic).
          Parse the argument; a pylib CONTAINER class (TPyList/TPyDict/
          TPyBytes, which DO have a matching overload) REWINDS and takes the
          ordinary overload path unchanged. Any OTHER class -- with or
          without `__len__` -- is handled HERE and never rewound: the
          overload matcher's silent-wrong-pick for an unmatched tyClass
          argument is not safe to fall back on, unlike a genuinely absent
          overload for a scalar type. First attempt rewound unconditionally
          and depended on which OTHER classes happened to exist elsewhere in
          the same file for whether the no-`__len__` case raised or read
          garbage -- confirmed with PXXDBG=a.ir: the same wrong proc index
          got called either way; it only LOOKED fixed by coincidence. }
        intBaseArg := TokPos;
        { PARK the hoist queue across this TRIAL parse. The argument is parsed
          to learn its TYPE and, for most shapes, thrown away and re-parsed
          below — but a parse has SIDE EFFECTS: a string method on a call
          result queues a hidden-temp assignment, and the discarded parse's
          copy stayed in the queue and was emitted. So `len(f.read().upper())`
          read the file TWICE at run time — once for the abandoned AST and once
          for the real one — and the second read got the empty string a
          consumed file returns: len answered 0, exactly as if the file had
          been empty, and `.split("\n")` on it answered 1.
          Parked on a FRESH chain rather than by remembering the head, for the
          reason PyParseMethod records: PySeqAppend mutates the saved chain's
          tail in place, so a plain restore cannot unlink anything.
          bug-nilpy-len-of-a-string-method-on-a-file-read-answers-zero }
        lenSavedHoist := PyHoistPark;
        Next; Expect(tkLParen, '('); ParseArgExpr;
        lenTrialHoist := PyHoistPark;
        PyHoistRestore(lenSavedHoist);
        if IntToTypeKind(ASTTk[CurASTNode]) = tyClass then
        begin
          atRecv := ResolveNodeRec(CurASTNode);
          { TPyRange joins the pylib container classes here: it HAS a matching
            len() overload, so it rewinds into the ordinary overload path like
            they do. Without it a range fell into the no-__len__ arm below and
            `len(range(3))` raised "not a container". }
          { …unless the class OVERRIDES `__len__`, in which case it is that
            method CPython calls and this one has to as well. The container
            test above is by KIND, so a `dict` subclass matched it and went
            straight to pylib's count() — `len(c)` was right by luck (the
            override delegated) and would have been silently wrong for any
            override that did anything else.
            bug-n-a-builtin-subclass-subscript-operator-skips-the-override }
          if (atRecv >= REC_UCLASS_BASE) and
             (PyRecOverridesDunder(atRecv, '__len__') or
              ((not PyRecIsCls(atRecv, 'TPyList')) and
               (not PyRecIsCls(atRecv, 'TPyDict')) and
               (not PyRecIsCls(atRecv, 'TPyRange')) and
               (not PyRecIsCls(atRecv, 'TPyBytes')))) then
          begin
            { a CURSOR: CPython answers `object of type 'map' has no len()`,
              not a generic "not a container". Same runtime-raise shape as the
              no-__len__ arm below, just with the accurate message — and it is
              the one row going lazy deliberately makes stricter. }
            if (FindUClass('TPyIter') >= 0) and
               (atRecv = REC_UCLASS_BASE + FindUClass('TPyIter')) then
            begin
              PyHoistMerge(lenSavedHoist, lenTrialHoist);   { the trial AST is kept }
              prevTok := FindProc('pyiter_no_len');
              if prevTok < 0 then Error('Nil Python: pylib (pyiter_no_len) not loaded');
              atDflt := AllocNode(AN_ARG);
              ASTLeft[atDflt] := CurASTNode;
              ASTRight[atDflt] := -1;
              Expect(tkRParen, ')');
              atRecv := AllocNode(AN_CALL);
              ASTIVal[atRecv] := prevTok;
              ASTTk[atRecv] := Ord(tyInt64);
              ASTLeft[atRecv] := atDflt;
              CurASTNode := atRecv; LastExprTk := tyInt64;
              Exit;
            end;
            atFld := FindUMeth(atRecv - REC_UCLASS_BASE, '__len__');
            if atFld >= 0 then
            begin
              PyHoistMerge(lenSavedHoist, lenTrialHoist);   { the trial AST is kept }
              atDflt := PyCallMeth1(atRecv - REC_UCLASS_BASE,
                                    PyRawName(UMthNOff[atFld], UMthNLen[atFld]),
                                    CurASTNode, -1);
              if atDflt < 0 then Error('Nil Python: len() could not call __len__');
              Expect(tkRParen, ')');
              CurASTNode := atDflt; LastExprTk := IntToTypeKind(ASTTk[atDflt]);
              Exit;
            end;
            { no __len__ on a non-container class: a genuine RUNTIME error
              (try/except around this must still compile and run its
              handler), not a compile-time Error() or a rewind into the
              overload matcher's unsafe fallback. }
            { the argument's own setup still runs, as it did before this parse
              was parked — only its VALUE is unused }
            PyHoistMerge(lenSavedHoist, lenTrialHoist);
            prevTok := FindProc('PyNotContainerError');
            if prevTok < 0 then Error('Nil Python: pylib (PyNotContainerError) not loaded');
            Expect(tkRParen, ')');
            atDflt := AllocNode(AN_CALL);
            ASTIVal[atDflt] := prevTok;
            ASTTk[atDflt] := Ord(tyInt64);
            ASTLeft[atDflt] := -1;
            CurASTNode := atDflt; LastExprTk := tyInt64;
            Exit;
          end;
        end;
        { a pylib container class, or a non-class argument: rewind and take
          the ordinary overload path, unchanged byte for byte }
        TokPos := intBaseArg - 1; Next;
      end;
      { hex/bin/oct of an ARBITRARY-PRECISION int. Python's take any width, while
        pylib's are `function hex(n: Int64)`, so once a value has grown past a
        machine word (or came from a wide literal) the call simply has no
        matching overload — measured today, before the promotion default even
        lands: `x = 1180591620717411303424; hex(x)` fails to compile.

        A `PromoInt` OVERLOAD in pylib cannot be written: a PromoInt PARAMETER
        cannot be handed to the promo runtime at all, and `shr` / `Integer(n)`
        on one are both broken, so the digit loop is unwritable in Pascal
        source (bug-a-promoint-shr-yields-nothing-and-a-machine-int-cast-yields-
        the-slot-address). So this lowers to promocore's own base conversion,
        which works off the bignum limbs directly — the same shape `**` uses for
        pypow_v and `writeln` uses for PXXPromoToStr.

        Guarded by PyUserShadowsProc like every other name-keyed lowering: an
        IR-level rewrite doing exactly this without the guard is what made a
        user `def len(x)` unreachable
        (bug-nilpy-user-def-len-of-a-container-still-binds-the-builtin).

        A NON-promo argument REWINDS to the ordinary Int64 overload, so native
        values keep today's code path untouched. }
      if NilPyUserCode and (not PyUserShadowsProc(name)) and
         (CaseEqual(name, 'hex') or CaseEqual(name, 'bin') or CaseEqual(name, 'oct')) and
         (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        intBaseArg := TokPos;
        { same parked TRIAL parse as the two intercepts above }
        lenSavedHoist := PyHoistPark;
        Next; Expect(tkLParen, '('); ParseArgExpr;
        lenTrialHoist := PyHoistPark;
        PyHoistRestore(lenSavedHoist);
        if TypeIsPromoInt(IntToTypeKind(ASTTk[CurASTNode])) then
        begin
          PyHoistMerge(lenSavedHoist, lenTrialHoist);   { the trial AST is kept }
          if CaseEqual(name, 'hex') then i := 16
          else if CaseEqual(name, 'oct') then i := 8
          else i := 2;
          procIdx := FindProc('PXXPromoToBase');
          if procIdx < 0 then
            Error('Nil Python: promocore (PXXPromoToBase) not loaded');
          argSeq := AllocNode(AN_ARG);
          ASTLeft[argSeq] := CurASTNode;
          valNode := AllocNode(AN_INT_LIT);
          ASTIVal[valNode] := i;
          ASTTk[valNode] := Ord(tyInteger);
          argSeq2 := AllocNode(AN_ARG);
          ASTLeft[argSeq2] := valNode;
          ASTRight[argSeq2] := -1;
          ASTRight[argSeq] := argSeq2;
          node := AllocNode(AN_CALL);
          ASTIVal[node] := procIdx;
          ASTLeft[node] := argSeq;
          ASTTk[node] := Ord(tyAnsiString);
          Expect(tkRParen, ')');
          CurASTNode := node;
          LastExprTk := tyAnsiString;
          Exit;
        end;
        { a machine-width argument: rewind, take the ordinary overload }
        TokPos := intBaseArg - 1; Next;
      end;
      if NilPyUserCode and (name = 'int') and (not PyUserShadowsProc(name)) then
      begin
        Next; Expect(tkLParen, '('); ParseArgExpr;
        { `int(s, base)` — the two-argument radix form. A separate pylib
          function rather than another intrinsic, because it must RAISE
          ValueError on a bad parse (pylib declares the Python exception
          hierarchy so it can), and the -200 intrinsic has no way to fail. }
        if CurTok.Kind = tkComma then
        begin
          intBaseArg := CurASTNode;
          Next;
          ParseArgExpr;
          node := AllocNode(AN_CALL);
          ASTIVal[node] := FindProc('pyint_parse');
          if ASTIVal[node] < 0 then Error('Nil Python: pylib (pyint_parse) not loaded');
          ASTTk[node] := Ord(tyInt64);
          argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := intBaseArg;
          intBaseArg := AllocNode(AN_ARG); ASTLeft[intBaseArg] := CurASTNode;
          ASTRight[argSeq] := intBaseArg;
          ASTRight[intBaseArg] := -1;
          ASTLeft[node] := argSeq;
          Expect(tkRParen, ')');
          CurASTNode := node;
          LastExprTk := tyInt64;
          Exit;
        end;
        Expect(tkRParen, ')');
        { int() of an ARBITRARY-PRECISION int is the IDENTITY in Python, and it
          must STAY arbitrary precision — `int(2**70)` is 2**70, not a narrowed
          one. The -200 intrinsic's parameter is not a promo, and this site
          hand-builds its call (project_findproc_by_name_ignores_overloads), so
          the promo arrived as its SLOT ADDRESS and printed as a small number.
          Handing the argument straight back is both correct and free. }
        if TypeIsPromoInt(IntToTypeKind(ASTTk[CurASTNode])) then
        begin
          LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
          Exit;
        end;
        node := AllocNode(AN_CALL);
        { int(float) truncates toward zero, which is exactly the -203 Trunc
          intrinsic -- reuse it rather than duplicating its SSE lowering. Every
          other argument type goes to -200, whose lowering handles string
          (parse the text), variant (unbox) and int/bool (identity). }
        { A user class declaring `__int__`. Python asks the object; this asked
          nothing and handed the -200 intrinsic an object HANDLE, so
          `int(V(4))` printed 129729065648272 — the pointer. Silent, and the
          class plainly declares the member. The float twin is in float()'s
          arm below. bug-nilpy-int-and-float-ignore-their-dunders }
        if (IntToTypeKind(ASTTk[CurASTNode]) = tyClass) and
           (ResolveNodeRec(CurASTNode) >= REC_UCLASS_BASE) and
           (not PyRecIsPylibOwnClass(ResolveNodeRec(CurASTNode))) then
        begin
          if FindUMeth(ResolveNodeRec(CurASTNode) - REC_UCLASS_BASE, '__int__') >= 0 then
            node := PyCallMeth1(ResolveNodeRec(CurASTNode) - REC_UCLASS_BASE,
                                '__int__', CurASTNode, -1)
          else
            { no __int__ at all: CPython raises TypeError naming the class, and
              at RUN time, so `try: int(o) / except TypeError:` still compiles —
              the trade PyNoSetitemError already makes }
            node := PyClassErrCallNode('PyNoIntError',
                                       ResolveNodeRec(CurASTNode) - REC_UCLASS_BASE);
          if node >= 0 then
          begin
            CurASTNode := node;
            LastExprTk := IntToTypeKind(ASTTk[node]);
            Exit;
          end;
        end;
        { The NODE's type, not LastExprTk. `int(7/2)` printed
          4615063718147915776 -- 3.5's BIT PATTERN read as an integer -- because
          LastExprTk after an operator expression is the last FACTOR's type
          (tyInteger for the `2`), so the float arm was skipped and the -200
          intrinsic took the raw payload. The identical `x = 7/2; int(x)` was
          correct, which is what makes this a side-channel bug rather than an
          int() one: an ident leaves LastExprTk agreeing with the node.
          Take the kind from the VALUE, not from a side channel -- the rule
          project_variant_store_kind_came_from_the_ast_not_the_value records.
          bug-nilpy-int-of-a-division-reads-the-doubles-bits }
        if TypeIsFloat(IntToTypeKind(ASTTk[CurASTNode])) or TypeIsFloat(LastExprTk) then
        begin
          ASTIVal[node] := -203; ASTTk[node] := Ord(tyInt64);
        end
        else if IntToTypeKind(ASTTk[CurASTNode]) = tyVariant then
        begin
          { int(<variant>) — the ordinary shape for a module-scope binding, a
            container element or an unannotated parameter. The variant may hold
            an arbitrary-precision int, so the result cannot be Int64 either:
            typed VARIANT and lowered to pylib's pyint_v, which passes a
            VT_PROMO_INT64 payload straight through and narrows nothing.
            (bug-nilpy-int-of-a-variant-held-bignum-raises — `int(2**64)` used
            to abort with EVariantError, which is not a value Python has.) }
          ASTIVal[node] := -200; ASTTk[node] := Ord(tyVariant);
          argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
          ASTLeft[node] := argSeq;
          CurASTNode := node;
          LastExprTk := tyVariant;
          Exit;
        end
        else if (IntToTypeKind(ASTTk[CurASTNode]) = tyString) or
                (IntToTypeKind(ASTTk[CurASTNode]) = tyAnsiString) then
        begin
          { int(<str>) is where a value WIDER THAN Int64 actually enters a
            program — the digits are data, so nothing about the parse can be
            decided at compile time — and Python's int has no width. So it is
            typed a PROMOTABLE INT, the same type a wide LITERAL already gets a
            few hundred lines up, which is what makes `n = int(s)` then `n + 1`
            and `str(n)` all stay exact. Typed HERE and not patched during
            lowering: `write` reads its argument's type before lowering the
            argument, so a retype at lowering lands too late for the one
            consumer that most needs it
            (bug-nilpy-int-of-a-long-decimal-string-narrows).
            tyChar is deliberately NOT here: a one-character string cannot
            exceed 9, so it keeps the cheaper Int64 path. }
          ASTIVal[node] := -200; ASTTk[node] := Ord(tyPromoInt64);
          argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
          ASTLeft[node] := argSeq;
          CurASTNode := node;
          LastExprTk := tyPromoInt64;
          Exit;
        end
        else
        begin
          { tyInt64, not tyInteger: NilPy's int is a 64-bit cell. The -200
            result is a full 64-bit value; typing it 32-bit made an inferred
            local truncate it at the store (`start = int(vm.pop())` of
            maxint read back as -1 — uforth's DO index). }
          ASTIVal[node] := -200; ASTTk[node] := Ord(tyInt64);
        end;
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
        ASTLeft[node] := argSeq;
        CurASTNode := node;
        LastExprTk := tyInt64;
        Exit;
      end
      else if isNilPy and ((name = 'hasattr') or (name = 'getattr')) then
      begin
        { Resolved against the receiver's DECLARED fields — see PyAttrFieldIdx
          for why a compile-time answer is the right shape here. }
        atIsGet := name = 'getattr';
        Next; Expect(tkLParen, '(');
        ParseExpr;
        atRecv := CurASTNode;
        { A COMPUTED name — `getattr(self, "do_" + verb)` — cannot be answered
          from the receiver's declared fields at compile time, which is what
          the whole path below does. Route it to the runtime resolver instead
          of refusing it. }
        { A string LITERAL is only the literal path when the whole argument is
          that literal — `"zz" + "z"` starts with a string token and is still a
          computed name, and reading it as the literal choked on the '+'. }
        if (CurTok.Kind = tkComma) and (TokPos < TokCount) and
           ((Tokens[TokPos].Kind <> tkString) or
            ((TokPos + 1 < TokCount) and
             (not (Tokens[TokPos + 1].Kind in [tkComma, tkRParen])))) then
        begin
          Expect(tkComma, ',');
          ParseExpr;
          atFld := CurASTNode;             { the name EXPRESSION }
          atDflt := -1;
          if CurTok.Kind = tkComma then
          begin
            Next;
            ParseExpr;
            atDflt := CurASTNode;
          end;
          Expect(tkRParen, ')');
          CurASTNode := PyMakeDynAttrByExpr(atRecv, atFld, atDflt, not atIsGet);
          LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
          Exit;
        end;
        atName := PyParseAttrName;
        atFld := PyAttrFieldIdx(atRecv, atName);
        { hasattr asks a WIDER question than "is it a declared field" — a method
          is an attribute too. Answered from the same tables the call uses; see
          PyAttrExists. Only the hasattr ANSWER moves: `atFld` stays the field
          index, because getattr builds a field read out of it and a method
          index there would be read as an offset.
          bug-nilpy-hasattr-on-a-builtin-container-or-str-answers-false }
        atExists := (atFld >= 0) or ((not atIsGet) and PyAttrExists(atRecv, atName));
        { a PROPERTY is neither a field nor a dynamic attribute: getattr must
          build the read `o.p` builds, or it raises AttributeError for a name
          hasattr (which does see properties) has just said yes to
          (bug-nilpy-hasattr-does-not-see-a-property) }
        atProp := -1;
        if atFld < 0 then atProp := PyMakePropRead(atRecv, atName);
        if atProp >= 0 then atExists := True;
        atDflt := -1;
        if CurTok.Kind = tkComma then
        begin
          Next;
          ParseExpr;
          atDflt := CurASTNode;
        end;
        Expect(tkRParen, ')');
        if atIsGet and (atProp >= 0) then
        begin
          CurASTNode := atProp;
          LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
          Exit;
        end;
        { An undeclared attribute may be set DYNAMICALLY at run time (on a
          variant OR a class instance), which a compile-time field check cannot
          see — resolve hasattr/getattr through the dynamic-attribute store. A
          getattr WITH a default keeps the old behaviour (return the default for
          an unknown attribute) rather than the store, which is what the
          censused getattr(e, "errno", 1) probes want. }
        if (not atExists) and (not (atIsGet and (atDflt >= 0))) and
           (IntToTypeKind(ASTTk[atRecv]) in [tyVariant, tyClass]) then
        begin
          { A VARIANT receiver has no static class, so atFld < 0 here does NOT
            mean "not declared" — it means "not knowable yet". Answering the
            dynamic store alone reported False for a field that is declared and
            reads fine on the same receiver: `box[0].x` worked while
            `hasattr(box[0], "x")` said False, silently, and the idiom that
            breaks is the guard `if not hasattr(o, "x")`, so control went down
            the wrong branch rather than raising
            (bug-nilpy-hasattr-on-a-variant-receiver-always-answers-false).
            A tyCLASS receiver keeps today's answer exactly: its class WAS
            resolved, so atFld < 0 there genuinely means undeclared. }
          if (not atIsGet) and (IntToTypeKind(ASTTk[atRecv]) = tyVariant) then
          begin
            atRecv := PyEvalOnce(atRecv);   { read once per candidate + once for the tag }
            atDflt := PyHasAttrClassChain(atRecv, atName);
          end
          else
            atDflt := -1;
          if atIsGet then CurASTNode := PyMakeDynAttrGet(atRecv, atName)
          else
          begin
            { a VARIANT receiver keeps its tag: a class held as a value has its
              attributes in the bind registry, and the unwrapped-pointer form
              would key the question on the RTTI blob's address and answer False
              (bug-nilpy-class-attribute-through-a-class-reference-reads-garbage) }
            { the WIDE predicates, not the store-only ones: hasattr must answer
              True for a method and for a name the class's __getattr__ answers
              for, which is CPython's definition of it (getattr does not raise).
              bug-nilpy-getattr-dunder-not-supported }
            if IntToTypeKind(ASTTk[atRecv]) = tyVariant then
              idx := FindProc('pydynattr_has_any_v')
            else
              idx := FindProc('pydynattr_hasattr');
            if idx < 0 then Error('Nil Python: pylib (pydynattr_hasattr) not loaded');
            argSeq := AllocNode(AN_ARG);
            if IntToTypeKind(ASTTk[atRecv]) = tyVariant then ASTLeft[argSeq] := atRecv
            else ASTLeft[argSeq] := PyMakeObjPtr(atRecv);
            argSeq2 := AllocNode(AN_STR_LIT);
            ASTSOffset[argSeq2] := PyStoredName(atName); ASTSLen[argSeq2] := Length(atName);
            ASTTk[argSeq2] := Ord(tyString);
            argSeq3 := AllocNode(AN_ARG); ASTLeft[argSeq3] := argSeq2; ASTRight[argSeq3] := -1;
            ASTRight[argSeq] := argSeq3;
            node := AllocNode(AN_CALL); ASTIVal[node] := idx;
            ASTTk[node] := Ord(tyBoolean); ASTLeft[node] := argSeq;
            { ...or the receiver's RUN-TIME class declares it }
            if atDflt >= 0 then
            begin
              argSeq2 := AllocNode(AN_BINOP);
              ASTIVal[argSeq2] := Ord(tkOr);
              ASTLeft[argSeq2] := node; ASTRight[argSeq2] := atDflt;
              ASTTk[argSeq2] := Ord(tyBoolean);
              node := argSeq2;
            end;
            CurASTNode := node;
          end;
          LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
          Exit;
        end;
        if not atIsGet then
        begin
          node := AllocNode(AN_INT_LIT);
          if atExists then ASTIVal[node] := 1 else ASTIVal[node] := 0;
          ASTTk[node] := Ord(tyBoolean);
          CurASTNode := node;
          LastExprTk := tyBoolean;
          Exit;
        end;
        { getattr WITH a default on an undeclared attribute of a class/variant:
          the attribute may have been set DYNAMICALLY, so return the stored value
          if present else the default — `pydynattr_has(o,n) ? pydynattr_get(o,n) :
          default`. Without the store check this always returned the default, so
          `getattr(vm, "_x", None)` reported None even after `vm._x = ...`. }
        if (atFld < 0) and (atDflt >= 0) and
           (IntToTypeKind(ASTTk[atRecv]) in [tyVariant, tyClass]) then
        begin
          { same tag-preserving choice as the hasattr branch above }
          { the wide predicates, same reason as the hasattr arm above — a
            default must not win over a value __getattr__ would have produced }
          if IntToTypeKind(ASTTk[atRecv]) = tyVariant then
            idx := FindProc('pydynattr_has_any_v')
          else
            idx := FindProc('pydynattr_hasattr');
          if idx < 0 then Error('Nil Python: pylib (pydynattr_hasattr) not loaded');
          argSeq := AllocNode(AN_ARG);
          if IntToTypeKind(ASTTk[atRecv]) = tyVariant then ASTLeft[argSeq] := atRecv
          else ASTLeft[argSeq] := PyMakeObjPtr(atRecv);
          argSeq2 := AllocNode(AN_STR_LIT);
          ASTSOffset[argSeq2] := PyStoredName(atName); ASTSLen[argSeq2] := Length(atName);
          ASTTk[argSeq2] := Ord(tyString);
          argSeq3 := AllocNode(AN_ARG); ASTLeft[argSeq3] := argSeq2; ASTRight[argSeq3] := -1;
          ASTRight[argSeq] := argSeq3;
          node := AllocNode(AN_CALL); ASTIVal[node] := idx;
          ASTTk[node] := Ord(tyBoolean); ASTLeft[node] := argSeq;
          { box the default into a variant so both ternary branches share the
            variant representation (a raw scalar branch would be misread) }
          idx := FindProc('pyvar_box');
          if idx < 0 then Error('Nil Python: pylib (pyvar_box) not loaded');
          argSeq2 := AllocNode(AN_ARG); ASTLeft[argSeq2] := atDflt; ASTRight[argSeq2] := -1;
          argSeq3 := AllocNode(AN_CALL); ASTIVal[argSeq3] := idx;
          ASTTk[argSeq3] := Ord(tyVariant); ASTLeft[argSeq3] := argSeq2;
          atDflt := argSeq3;
          { the value branch and the boxed default, joined by a ternary typed variant }
          argSeq2 := AllocNode(AN_PAIR);
          ASTLeft[argSeq2] := PyMakeDynAttrGet(atRecv, atName);
          ASTRight[argSeq2] := atDflt;
          argSeq3 := AllocNode(AN_TERNARY);
          ASTLeft[argSeq3] := node; ASTRight[argSeq3] := argSeq2;
          ASTTk[argSeq3] := Ord(tyVariant);
          CurASTNode := argSeq3;
          LastExprTk := tyVariant;
          Exit;
        end;
        if atFld >= 0 then
        begin
          { the field exists: an ordinary field read }
          node := AllocNode(AN_FIELD);
          ASTLeft[node] := atRecv;
          ASTSOffset[node] := PyStoredName(atName);
          ASTSLen[node] := Length(atName);
          ASTTk[node] := UFldTk[atFld];
          CurASTNode := node;
          LastExprTk := IntToTypeKind(UFldTk[atFld]);
          Exit;
        end;
        if atDflt < 0 then
          Error('Nil Python: getattr on an attribute this type does not declare needs a default');
        CurASTNode := atDflt;
        LastExprTk := IntToTypeKind(ASTTk[atDflt]);
        Exit;
      end
      else if isNilPy and (name = 'setattr') and (not PyUserShadowsProc('setattr')) then
      begin
        { The third member of the attribute trio. hasattr and getattr have been
          here since the protocol landed and setattr was simply absent —
          `undefined variable (setattr)` — so the read half of a dynamic
          attribute was expressible and the write half was not, on a receiver
          whose `o.name = v` form already writes through the same store.
          bug-nilpy-setattr-is-absent }
        Next; Expect(tkLParen, '(');
        ParseExpr;
        atRecv := CurASTNode;
        { A COMPUTED name — `setattr(o, "f_" + k, v)`, which is the shape that
          makes setattr worth having at all. Same literal-vs-expression test
          getattr uses: a string TOKEN is the literal path only when the whole
          argument is that token. }
        if (CurTok.Kind = tkComma) and (TokPos < TokCount) and
           ((Tokens[TokPos].Kind <> tkString) or
            ((TokPos + 1 < TokCount) and
             (not (Tokens[TokPos + 1].Kind in [tkComma, tkRParen])))) then
        begin
          Expect(tkComma, ',');
          ParseExpr;
          atFld := CurASTNode;             { the name EXPRESSION }
          Expect(tkComma, ',');
          ParseExpr;
          atDflt := CurASTNode;            { the value }
          Expect(tkRParen, ')');
          CurASTNode := PyMakeDynAttrSetByExpr(atRecv, atFld, atDflt);
          LastExprTk := tyUnknown;
          Exit;
        end;
        atName := PyParseAttrName;         { consumes the ',' and the literal }
        Expect(tkComma, ',');
        ParseExpr;
        atDflt := CurASTNode;              { the value }
        Expect(tkRParen, ')');
        atFld := PyAttrFieldIdx(atRecv, atName);
        if atFld >= 0 then
        begin
          { a DECLARED field: the ordinary field store, so setattr and
            `o.name = v` write the same slot rather than two }
          node := AllocNode(AN_FIELD);
          ASTLeft[node] := atRecv;
          ASTSOffset[node] := PyStoredName(atName);
          ASTSLen[node] := Length(atName);
          ASTTk[node] := UFldTk[atFld];
          argSeq := AllocNode(AN_ASSIGN);
          ASTLeft[argSeq] := node;
          ASTRight[argSeq] := atDflt;
          CurASTNode := argSeq;
          LastExprTk := tyUnknown;
          Exit;
        end;
        CurASTNode := PyMakeDynAttrSet(atRecv, atName, PyForceVariant(atDflt));
        LastExprTk := tyUnknown;
        Exit;
      end
      else if NilPyUserCode and (name = 'exec') then
      begin
        { exec(src, globals[, locals]) -> EvalPyStmts(src, g, l), which now
          actually BINDS into the locals dict — it used to run and publish
          nothing (bug-n-exec-builtin-is-a-silent-no-op-and-eval-is-absent).
          A missing locals argument passes the globals dict for both, as
          Python does. }
        Next; Expect(tkLParen, '(');
        ParseExpr; atRecv := CurASTNode;         { src }
        { The AMBIENT form `exec(src)` writes into the CALLER's own locals, and
          in a compiled dialect those are stack slots with no run-time name
          table to write through — a genuinely different and much harder thing
          than the explicit-dict form. Refused BY NAME rather than left to
          fail as "expected ," on the closing paren, which reads like a parser
          limitation when the real answer is a scoping one.
          nilpy-semantics-divergences.md }
        if CurTok.Kind = tkRParen then
          Error('Nil Python: exec(src) with no namespace is not supported — ' +
                'it would bind into the caller''s own locals, which are ' +
                'compiled stack slots with no run-time name table. Use the ' +
                'explicit form Python also has: d = {}; exec(src, d, d), then ' +
                'read the results out of d');
        Expect(tkComma, ',');
        ParseExpr; atFld := CurASTNode;          { globals }
        if CurTok.Kind = tkComma then
        begin
          Next;
          ParseExpr; atDflt := CurASTNode;       { locals }
        end
        else
          atDflt := atFld;
        Expect(tkRParen, ')');
        idx := FindProc('EvalPyStmts');
        if idx < 0 then Error('Nil Python: pyeval (EvalPyStmts) not loaded');
        node := AllocNode(AN_CALL);
        ASTIVal[node] := idx;
        ASTTk[node] := Ord(tyUnknown);           { procedure — no result }
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := atRecv;
        argSeq2 := AllocNode(AN_ARG); ASTLeft[argSeq2] := atFld;
        argSeq3 := AllocNode(AN_ARG); ASTLeft[argSeq3] := atDflt;
        ASTRight[argSeq] := argSeq2; ASTRight[argSeq2] := argSeq3;
        ASTRight[argSeq3] := -1;
        ASTLeft[node] := argSeq;
        CurASTNode := node;
        LastExprTk := tyUnknown;
        Exit;
      end
      else if NilPyUserCode and (name = 'eval') and (FindSym(name) < 0) and
              (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        { eval(expr[, globals[, locals]]) -> EvalPyExpr, the expression twin of
          exec above. It was absent entirely — `undefined variable (eval)`.
          Loud, so far less dangerous than exec's silence, but still a program
          CPython runs that this did not.

          Unlike exec, the no-namespace form IS supported: an expression only
          READS, and reading nothing is a run-time NameError naming the name,
          not a silent wrong answer. What it cannot see is the caller's
          compiled locals — so `eval("1+2")` works and `eval("x+1")` raises
          rather than quietly finding some other x.
          bug-n-exec-builtin-is-a-silent-no-op-and-eval-is-absent }
        Next; Expect(tkLParen, '(');
        ParseExpr; atRecv := CurASTNode;         { the expression source }
        if CurTok.Kind = tkComma then
        begin
          Next;
          ParseExpr; atFld := CurASTNode;        { globals }
          if CurTok.Kind = tkComma then
          begin
            Next;
            ParseExpr; atDflt := CurASTNode;     { locals }
          end
          else
            atDflt := atFld;
        end
        else
        begin
          { no namespaces: nil for both, which EvalPyExpr treats as empty }
          atFld := AllocNode(AN_INT_LIT);
          ASTIVal[atFld] := 0; ASTTk[atFld] := Ord(tyPointer);
          atDflt := AllocNode(AN_INT_LIT);
          ASTIVal[atDflt] := 0; ASTTk[atDflt] := Ord(tyPointer);
        end;
        Expect(tkRParen, ')');
        idx := FindProc('pyeval_expr');
        if idx < 0 then Error('Nil Python: pyeval (pyeval_expr) not loaded');
        node := AllocNode(AN_CALL);
        ASTIVal[node] := idx;
        ASTTk[node] := Ord(tyVariant);           { the expression's value }
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := atRecv;
        argSeq2 := AllocNode(AN_ARG); ASTLeft[argSeq2] := atFld;
        argSeq3 := AllocNode(AN_ARG); ASTLeft[argSeq3] := atDflt;
        ASTRight[argSeq] := argSeq2; ASTRight[argSeq2] := argSeq3;
        ASTRight[argSeq3] := -1;
        ASTLeft[node] := argSeq;
        CurASTNode := node;
        LastExprTk := tyVariant;
        Exit;
      end
      else if NilPyUserCode and (name = 'input') and (FindSym(name) < 0) and
              (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        { input([prompt]) -> PyParseInputCall, the SHARED builder — this arm
          used to have its own lowering that parsed the prompt and threw it
          away, where Python writes it to stdout
          (bug-nilpy-input-has-two-lowerings-one-discards-the-prompt).

          Only when a '(' follows AND nothing else is called `input`: Python
          lets a parameter shadow a builtin, and songformatter's
          `int_to_roman(input)` does exactly that — `isinstance(input, int)`
          was read as the BUILTIN and demanded its parenthesis. }
        CurASTNode := PyParseInputCall;
        LastExprTk := tyAnsiString;
        Exit;
      end
      else if NilPyUserCode and CaseEqual(name, 'format') and (FindSym(name) < 0) and
              (not PyUserShadowsProc(name)) and
              (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        { format(v[, spec]) -> PyParseFormatCall (pyformat_v). Intercepted even
          though a proc of that name resolves, because the one that resolves is
          sysutils' `Format(fmt, [args])` as soon as the program imports
          anything reaching sysutils — and a later unit SHADOWS the name rather
          than joining an overload set, so declaring the builtin in pylib made
          `format(7.5, ".1f")` compile until you added `import json`.
          The .npy's OWN `def format` must still win — Python lets a def
          shadow a builtin — and that question is PyUserShadowsProc's, not this
          arm's: it is the one predicate every name-keyed lowering asks, and it
          also knows Python rebinds the name only from the `def` statement
          onward. An arm that answers it itself is how `open` came to ignore a
          user def entirely.

          NilPyUserCode, not isNilPy: isNilPy is true for the WHOLE compilation
          including every PASCAL unit loaded into it, and `Format` is a name the
          Pascal RTL genuinely calls — sysutils' own `Format(fmt, args)` inside
          `Exception.CreateFmt` lowered to pyformat_v(msg, args) in any .npy
          that reached sysutils, so an RTL raise came back as `unsupported
          format spec ""` instead of its message. Same fix, same predicate, as
          the member-resolution hijack at PyClsAttrOvrGet. }
        CurASTNode := PyParseFormatCall;
        LastExprTk := tyAnsiString;
        Exit;
      end
      else if NilPyUserCode and (name = 'open') and (not PyUserShadowsProc(name)) then
      begin
        { open(path[, mode]) -> a TPyFile, whatever the mode. The no-mode form
          goes through pyopen, which is now just pyfile_open(path, 'r') —
          Python's default mode. Later positional/keyword args (encoding=...)
          are skipped either way. }
        Next; Expect(tkLParen, '(');
        ParseExpr;
        atRecv := CurASTNode;
        if CurTok.Kind = tkComma then
        begin
          Next;
          ParseArgExpr;
          { ONE class for every mode. A text read used to lower to pyopen and
            yield a TPyList of lines (the read-slurp model), so `open` answered
            TPyList or TPyFile depending on the mode STRING — two Pascal classes
            for one Python type. Binding one name to both widened it to a
            variant, and then `f.read()` resolved against TPyFile.read(u) and was
            refused for an arity Python does not have; worse, an append through
            a name that had widened to the read class dispatched .write to
            TPyList.write and silently DROPPED the data. TPyFile now carries the
            read side too — read()/readlines(), and for-in iterates its lines
            (PyParseForIn) — so the mode no longer picks a type.
            bug-nilpy-open-returns-two-different-classes-by-mode }
          node := AllocNode(AN_ARG);
          ASTLeft[node] := atRecv;
          atFld := AllocNode(AN_ARG);
          ASTLeft[atFld] := CurASTNode;
          ASTRight[node] := atFld;
          atRecv := AllocNode(AN_CALL);
          ASTIVal[atRecv] := FindProc('pyfile_open');
          if ASTIVal[atRecv] < 0 then Error('Nil Python: pylib (pyfile_open) not loaded');
          ASTTk[atRecv] := Ord(tyClass);
          ASTLeft[atRecv] := node;
          ASTRight[atRecv] := REC_UCLASS_BASE + FindUClass('TPyFile');   { .write/.seek resolve }
          while CurTok.Kind = tkComma do
          begin
            Next;
            atFld := 0;
            while (CurTok.Kind <> tkEOF) and
                  not ((atFld = 0) and (CurTok.Kind in [tkComma, tkRParen])) do
            begin
              if CurTok.Kind = tkLParen then Inc(atFld)
              else if CurTok.Kind = tkRParen then Dec(atFld);
              Next;
            end;
          end;
          Expect(tkRParen, ')');
          CurASTNode := atRecv;
          LastExprTk := tyClass;
          Exit;
        end;
        while CurTok.Kind = tkComma do
        begin
          Next;
          { skip one argument, balanced across nested parens }
          atFld := 0;
          while (CurTok.Kind <> tkEOF) and
                not ((atFld = 0) and (CurTok.Kind in [tkComma, tkRParen])) do
          begin
            if CurTok.Kind = tkLParen then Inc(atFld)
            else if CurTok.Kind = tkRParen then Dec(atFld);
            Next;
          end;
        end;
        Expect(tkRParen, ')');
        node := AllocNode(AN_CALL);
        idx := FindProc('pyopen');
        if idx < 0 then Error('Nil Python: pylib (pyopen) not loaded');
        ASTIVal[node] := idx;
        ASTTk[node] := Ord(tyClass);
        ASTRight[node] := REC_UCLASS_BASE + FindUClass('TPyFile');
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := atRecv;
        ASTLeft[node] := argSeq;
        CurASTNode := node;
        LastExprTk := tyClass;
        Exit;
      end
      { ...and, like `int` / `str` above, only while the module has not rebound
        the name: a `def float(x)` is ordinary Python and must win from its own
        `def` statement onward. Without the guard this arm claimed the name
        unconditionally and the user's def was NEVER called — silently, on
        both sides of the def.
        bug-nilpy-a-def-named-float-or-bool-is-never-called }
      else if NilPyUserCode and (name = 'float') and (not PyUserShadowsProc(name)) then
      begin
        Next; Expect(tkLParen, '('); ParseArgExpr; Expect(tkRParen, ')');
        { …and a user class declaring `__float__` — the twin of int()'s
          `__int__` arm. bug-nilpy-int-and-float-ignore-their-dunders }
        if (IntToTypeKind(ASTTk[CurASTNode]) = tyClass) and
           (ResolveNodeRec(CurASTNode) >= REC_UCLASS_BASE) and
           (not PyRecIsPylibOwnClass(ResolveNodeRec(CurASTNode))) then
        begin
          if FindUMeth(ResolveNodeRec(CurASTNode) - REC_UCLASS_BASE, '__float__') >= 0 then
            node := PyCallMeth1(ResolveNodeRec(CurASTNode) - REC_UCLASS_BASE,
                                '__float__', CurASTNode, -1)
          else
            node := PyClassErrCallNode('PyNoFloatError',
                                       ResolveNodeRec(CurASTNode) - REC_UCLASS_BASE);
          if node >= 0 then
          begin
            CurASTNode := node;
            LastExprTk := IntToTypeKind(ASTTk[node]);
            Exit;
          end;
        end;
        { Dispatched on the ARGUMENT type, not by overload: a string is PARSED
          (and raises ValueError on failure, which uforth catches), an integer
          is widened, and a float is already the answer. }
        if TypeIsFloat(LastExprTk) then
        begin
          CurASTNode := CurASTNode;   { already a Double — nothing to convert }
          LastExprTk := tyDouble;
          Exit;
        end;
        node := AllocNode(AN_CALL);
        if (LastExprTk = tyString) or (LastExprTk = tyAnsiString) or
           (LastExprTk = tyChar) then
          ASTIVal[node] := FindProc('pyfloat_parse')
        else if LastExprTk = tyVariant then
          { the tag is a RUN-TIME fact: parse a str, widen a number }
          ASTIVal[node] := FindProc('pyfloat_any')
        else
          ASTIVal[node] := FindProc('pyfloat_ofint');
        if ASTIVal[node] < 0 then Error('Nil Python: pylib (pyfloat_*) not loaded');
        ASTTk[node] := Ord(tyDouble);
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
        ASTRight[argSeq] := -1;
        ASTLeft[node] := argSeq;
        CurASTNode := node;
        LastExprTk := tyDouble;
        Exit;
      end
      else if NilPyUserCode and (name = 'map') and (TokPos < TokCount) and
              (Tokens[TokPos].Kind = tkLParen) and (FindSym(name) < 0) then
      begin
        { `map(int, xs)` — the CONVERSION forms, which is what real code writes
          (`w, h = map(int, s.split("x"))`) — beside `map(f, xs)` over an
          arbitrary callable VALUE (a lifted lambda, a plain def, a bound
          method, or a builtin via PyGetOrMakeCallableWrapper), which reuses
          the same PyCallKey1 dispatch sorted()'s key= already does.
          feature-nilpy-aggregate-builtins }
        Next; Expect(tkLParen, '(');
        mapKind := '';
        if CurTok.Kind = tkIdent then mapKind := LowerCase(CurTok.SVal);
        { …and it really is the bare CONVERSION only when a comma follows it:
          `map(str.upper, xs)` starts with the same token and is an unbound
          METHOD (a callable value), which this arm would have consumed as
          `str` and then failed on the dot. }
        if ((mapKind = 'int') or (mapKind = 'str') or (mapKind = 'float')) and
           (TokPos < TokCount) and (Tokens[TokPos].Kind = tkComma) then
        begin
          if mapKind = 'int' then mapConv := 1
          else if mapKind = 'str' then mapConv := 2
          else mapConv := 3;
          Next;
          Expect(tkComma, ',');
          { the NilPy expression parser: the argument is normally a call with a
            string-method suffix (`get(...).split("x")`), which the Pascal chain
            does not apply }
          PyParseBoolExpr;
          Expect(tkRParen, ')');
          { LAZY, like every other map: the conversion forms carry no callable,
            so they ride the same cursor with the conversion CODE in place of a
            function pointer (pyiter_map_conv_*). The entry is picked by the
            iterable's static type because FindProc is not overload-aware. }
          CurASTNode := PyMakeIterOf(CurASTNode);
          mapProc := FindProc('pyiter_map_conv_i');
          if mapProc < 0 then Error('Nil Python: pylib (pyiter_map_conv_i) not loaded');
          node := AllocNode(AN_CALL);
          ASTIVal[node] := mapProc;
          exprNode := AllocNode(AN_INT_LIT);
          ASTIVal[exprNode] := mapConv;
          ASTTk[exprNode] := Ord(tyInt64);
          argSeq := AllocNode(AN_ARG);
          ASTLeft[argSeq] := exprNode;
          argSeq2 := AllocNode(AN_ARG);
          ASTLeft[argSeq2] := CurASTNode;
          ASTRight[argSeq2] := -1;
          ASTRight[argSeq] := argSeq2;
          ASTLeft[node] := argSeq;
          ASTTk[node] := Ord(tyClass);
          ASTRight[node] := ProcRetRecId[mapProc];
          CurASTNode := node;
          LastExprTk := tyClass;
          Exit;
        end
        else
        begin
          PyParseBoolExpr;
          exprNode := PyMakeCallablePtrArg(CurASTNode, 'the function map() applies');
          Expect(tkComma, ',');
          PyParseBoolExpr;
          Expect(tkRParen, ')');
          CurASTNode := PyMakeIterOf(CurASTNode);
          mapProc := FindProc('pymap_iter_i');
          if mapProc < 0 then Error('Nil Python: pyeval (pymap_iter_i) not loaded');
          node := AllocNode(AN_CALL);
          ASTIVal[node] := mapProc;
          argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := exprNode;
          argSeq2 := AllocNode(AN_ARG); ASTLeft[argSeq2] := CurASTNode; ASTRight[argSeq2] := -1;
          ASTRight[argSeq] := argSeq2;
          ASTLeft[node] := argSeq;
          ASTTk[node] := Ord(tyClass);
          ASTRight[node] := ProcRetRecId[mapProc];
          CurASTNode := node;
          LastExprTk := tyClass;
          Exit;
        end;
      end
      else if NilPyUserCode and (name = 'filter') and (TokPos < TokCount) and
              (Tokens[TokPos].Kind = tkLParen) and (FindSym(name) < 0) then
      begin
        { `filter(f, xs)` / `filter(None, xs)` (Python's own "keep the truthy
          elements" shorthand). Same callable dispatch as map(), above.
          feature-nilpy-aggregate-builtins }
        Next; Expect(tkLParen, '(');
        if CurTok.Kind = tkNil then
        begin
          Next;
          exprNode := AllocNode(AN_INT_LIT);
          ASTIVal[exprNode] := 0;
          ASTTk[exprNode] := Ord(tyPointer);
        end
        else
        begin
          PyParseBoolExpr;
          exprNode := PyMakeCallablePtrArg(CurASTNode, 'the predicate filter() applies');
        end;
        Expect(tkComma, ',');
        PyParseBoolExpr;
        Expect(tkRParen, ')');
        CurASTNode := PyMakeIterOf(CurASTNode);
        mapProc := FindProc('pyfilter_iter_i');
        if mapProc < 0 then Error('Nil Python: pyeval (pyfilter_iter_i) not loaded');
        node := AllocNode(AN_CALL);
        ASTIVal[node] := mapProc;
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := exprNode;
        argSeq2 := AllocNode(AN_ARG); ASTLeft[argSeq2] := CurASTNode; ASTRight[argSeq2] := -1;
        ASTRight[argSeq] := argSeq2;
        ASTLeft[node] := argSeq;
        ASTTk[node] := Ord(tyClass);
        ASTRight[node] := ProcRetRecId[mapProc];
        CurASTNode := node;
        LastExprTk := tyClass;
        Exit;
      end
      else if NilPyUserCode and (name = 'next') and (TokPos < TokCount) and
              (Tokens[TokPos].Kind = tkLParen) and PyNextOverListAhead then
      begin
        { `next(<list>)` / `next(<list>, default)` — Python's builtin over a
          sequence. Routed by ARGUMENT TYPE rather than by an overload: the name
          is already itertools' counter advance, and a TPyList overload beside it
          made an untyped argument pick the wrong one and segfault. }
        Next; Expect(tkLParen, '(');
        { the argument may be a BARE generator, which has to be diverted before
          its element expression is parsed (the loop variable is not in scope
          until the `for`) }
        if PyBareGenExprAhead then CurASTNode := PyParseCompExprValue(False)
        else ParseArgExpr;
        { boxed, and the RUN-TIME entry point: the argument may be a list, a
          cursor (a genexpr bound to a name is one), a range or a user
          iterable, and only a cursor must ADVANCE. Picking a TPyList-taking
          routine statically handed a TPyIter to a list parameter and answered
          the default — `next((c for c in cs if ...), "none")` said "none" for
          a match that plainly existed. }
        CurASTNode := PyForceVariant(CurASTNode);
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode; ASTRight[argSeq] := -1;
        node := argSeq;
        if CurTok.Kind = tkComma then
        begin
          Next;
          ParseArgExpr;
          atDflt := AllocNode(AN_ARG); ASTLeft[atDflt] := PyForceVariant(CurASTNode);
          ASTRight[atDflt] := -1;
          ASTRight[argSeq] := atDflt;
          procIdx := FindProc('pynext_or_v');
        end
        else
          procIdx := FindProc('pynext_v');
        if procIdx < 0 then Error('Nil Python: pylib (pynext_first) not loaded');
        Expect(tkRParen, ')');
        CurASTNode := AllocNode(AN_CALL);
        ASTIVal[CurASTNode] := procIdx;
        ASTTk[CurASTNode] := Ord(tyVariant);
        ASTLeft[CurASTNode] := node;
        LastExprTk := tyVariant;
        Exit;
      end
      { ...and, like `int` / `str` above, only while the module has not rebound
        the name: a `def bool(x)` is ordinary Python and must win from its own
        `def` statement onward. Without the guard this arm claimed the name
        unconditionally and the user's def was NEVER called — silently, on
        both sides of the def.
        bug-nilpy-a-def-named-float-or-bool-is-never-called }
      else if NilPyUserCode and (name = 'bool') and (not PyUserShadowsProc(name)) then
      begin
        { `bool(x)` is Python's TRUTHINESS, the same rule `if x:` and `not x`
          use — so it goes through PyMakeTruthy rather than resolving to pylib's
          bool() overloads. It had NO NilPy arm at all, so a user-class argument
          resolved as a plain overloaded call and bound to `bool(l: TPyList)`,
          reading count off the wrong layout; once class-identity resolution was
          fixed nothing matched and it fell to the variant path instead, so it
          answered True for every instance. Either way `__bool__`/`__len__` were
          never consulted (bug-nilpy-bool-protocol-ignored-object-always-truthy).
          Routing through PyMakeTruthy is what stops the three truth contexts
          drifting apart again — the whole reason PyClassTruthyDunder exists. }
        Next; Expect(tkLParen, '('); ParseArgExpr;
        atDflt := PyMakeTruthy(CurASTNode);
        if (atDflt = CurASTNode) and (IntToTypeKind(ASTTk[CurASTNode]) <> tyBoolean) then
        begin
          { PyMakeTruthy has no rule for this operand and hands it back raw —
            a number, or a class with neither dunder. As a CONDITION that is
            already correct (non-zero / non-nil is truthy), but bool() must
            yield an actual Boolean, so compare against zero explicitly. For a
            protocol-less instance this is `handle <> nil`, which is Python's
            "any instance is true" and still evaluates the argument. }
          atRecv := AllocNode(AN_INT_LIT);
          ASTIVal[atRecv] := 0;
          ASTTk[atRecv] := ASTTk[CurASTNode];
          atFld := AllocNode(AN_BINOP);
          ASTIVal[atFld] := Ord(tkNeq);
          ASTLeft[atFld] := CurASTNode;
          ASTRight[atFld] := atRecv;
          ASTTk[atFld] := Ord(tyBoolean);
          atDflt := atFld;
        end;
        Expect(tkRParen, ')');
        CurASTNode := atDflt;
        ASTTk[CurASTNode] := Ord(tyBoolean);
        LastExprTk := tyBoolean;
        Exit;
      end
      else if NilPyUserCode and (name = 'str') and (not PyUserShadowsProc(name)) then
      begin
        Next; Expect(tkLParen, '('); ParseArgExpr;
        { str() of an ARBITRARY-PRECISION int renders through the promo runtime.
          This site hand-builds its call with FindProc, which returns ONE proc
          and never consults overloads
          (project_findproc_by_name_ignores_overloads) — so a promo argument
          reached a pystr_of whose parameter is not an integer, nothing narrowed
          or boxed it, and the SLOT ADDRESS was rendered as a number. Reachable
          today with a wide literal: `str(1180591620717411303424)`.
          PXXPromoToStr takes a Pointer, which IS the slot address, so the
          promo->Pointer argument arm carries it across unchanged. }
        if TypeIsPromoInt(IntToTypeKind(ASTTk[CurASTNode])) then
        begin
          procIdx := FindProc('PXXPromoToStr');
          if procIdx < 0 then Error('Nil Python: promocore (PXXPromoToStr) not loaded');
          argSeq := AllocNode(AN_ARG);
          ASTLeft[argSeq] := CurASTNode;
          ASTRight[argSeq] := -1;
          node := AllocNode(AN_CALL);
          ASTIVal[node] := procIdx;
          ASTLeft[node] := argSeq;
          ASTTk[node] := Ord(tyAnsiString);
          Expect(tkRParen, ')');
          CurASTNode := node;
          LastExprTk := tyAnsiString;
          Exit;
        end;
        { str(e) of a built-in Exception (or subclass) is its message: rewrite
          the argument to a read of the `.msg` field, so str() returns the text
          rather than the instance pointer (feature-nilpy-exception-message). }
        if IntToTypeKind(ASTTk[CurASTNode]) = tyClass then
        begin
          atRecv := ResolveNodeRec(CurASTNode);
          if atRecv >= REC_UCLASS_BASE then
          begin
            { __str__/__repr__ if declared, else an Exception's .msg — the one
              PyClassStrNode decision, shared with print() and the f-string
              path. This site tested Exception FIRST, so a user __str__ on an
              exception subclass was skipped and str(e) returned the
              constructor argument
              (bug-nilpy-user-str-dunder-on-an-exception-subclass-is-ignored).
              An exception declaring NEITHER dunder still reads .msg, so
              str(ValueError("x")) is unchanged. }
            atDflt := PyClassStrNode(CurASTNode, atRecv - REC_UCLASS_BASE);
            if atDflt >= 0 then
            begin
              if IntToTypeKind(ASTTk[atDflt]) = tyAnsiString then
              begin
                Expect(tkRParen, ')');
                CurASTNode := atDflt; LastExprTk := tyAnsiString;
                Exit;
              end;
              CurASTNode := atDflt;
            end
            else
            begin
              { ...and a pylib CONTAINER renders as its Python repr. print() has
                gone through PyReprContainer all along; str() had no arm for a
                list/dict/bytes handle, so it fell through to the numeric path
                and returned the POINTER as a number — silently
                (bug-nilpy-str-of-tuple-is-empty). One routine for both, so the
                two spellings cannot drift. }
              atDflt := PyReprContainer(CurASTNode);
              if atDflt <> CurASTNode then
              begin
                Expect(tkRParen, ')');
                CurASTNode := atDflt; LastExprTk := tyAnsiString;
                Exit;
              end;
            end;
          end;
        end;
        { A VARIANT argument may hold a container at run time, and the variant
          arm of pystr_of renders one as empty — which is what made
          `[str(k) for k in d.keys()]` a list of empty strings. pyvar_print_of
          dispatches on the tag: container to repr, scalar to str. }
        if isNilPy and (IntToTypeKind(ASTTk[CurASTNode]) = tyVariant) then
        begin
          atDflt := PyReprContainer(CurASTNode);
          if atDflt <> CurASTNode then
          begin
            Expect(tkRParen, ')');
            CurASTNode := atDflt; LastExprTk := tyAnsiString;
            Exit;
          end;
        end;
        { A FLOAT argument: route to pylib's pystr_of, which spells the
          non-finite values Python's way (inf / -inf / nan). The shared -201
          builtin below goes to FloatToStr, whose Inf / -Inf / Nan is correct for
          PASCAL and must not change — so this is a NilPy-only reroute, the same
          shape as the container one just above
          (bug-nilpy-inf-and-nan-print-pascal-spelled). }
        if isNilPy and (IntToTypeKind(ASTTk[CurASTNode]) in [tyDouble, tySingle]) then
        begin
          { PyFloatStr, not pystr_of: FindProc resolves a NAME to one proc index
            and never consults overloads, so 'pystr_of' would have picked the
            AnsiString overload and handed it a Double — the same trap that made
            zip/enumerate segfault on a str handle. PyFloatStr has one signature. }
          atDflt := FindProc('PyFloatStr');
          if atDflt >= 0 then
          begin
            Expect(tkRParen, ')');
            argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
            ASTRight[argSeq] := -1;
            node := AllocNode(AN_CALL);
            ASTIVal[node] := atDflt;
            ASTLeft[node] := argSeq;
            ASTTk[node] := Ord(tyAnsiString);
            CurASTNode := node; LastExprTk := tyAnsiString;
            Exit;
          end;
        end;
        Expect(tkRParen, ')');
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
              (not PyUserShadowsProc(name)) and
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
        Next; Expect(tkLParen, '('); ParseExpr;
        { NilPy hands these intrinsics whatever the expression's static type is,
          and an inferred local or parameter is a VARIANT. The lowering below is
          a raw SSE conversion of a double, so a variant argument converted its
          16-byte slot instead of the number it holds — `round(r * 255)` on a
          parameter printed a stack address. Unbox first. (An expression whose
          STATIC type came out non-variant can still be a variant at run time —
          `x * 255` types integer but lowers to a variant multiply — so the
          codegen's own IRTk = tyVariant check is the real backstop; this one
          only covers the plainly-typed cases.) }
        { …but the two-argument `round` must NOT be unboxed: its answer keeps the
          argument's INTNESS, and a double is where that information dies —
          `round(2 ** 70, 2)` came back as 1.18e+21. Remember the raw node and
          hand THAT to the variant-aware routine below.
          bug-nilpy-two-argument-round-of-an-int-returns-a-float }
        rndRawArg := CurASTNode;
        rndRawTk := LastExprTk;
        if isNilPy and (LastExprTk = tyVariant) then
        begin
          node := AllocNode(AN_CALL);
          ASTIVal[node] := FindProc('pyvar_to_float');
          if ASTIVal[node] < 0 then Error('Nil Python: pylib (pyvar_to_float) not loaded');
          ASTTk[node] := Ord(tyDouble);
          argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
          ASTRight[argSeq] := -1;
          ASTLeft[node] := argSeq;
          CurASTNode := node;
          LastExprTk := tyDouble;
        end;
        { Python's `round(x, ndigits)` — a FLOAT rounded to that many decimals,
          a different operation from the one-argument form (which yields an
          int). songformatter writes `round(pct, 2)` when normalising scores. }
        if NilPyUserCode and CaseEqual(name, 'round') and (CurTok.Kind = tkComma) then
        begin
          Next;
          rndArg := CurASTNode;
          { CPython's `round(x, n)` keeps x's TYPE: an int in, an int out,
            whatever n is. `round(6, 2)` is 6, not 6.0, and a report that
            rounds an integral total to two places printed 6.0 where every
            other implementation prints 6 — while the ONE-argument round(6)
            was right, so the two spellings disagreed with each other.
            bug-nilpy-two-argument-round-of-an-int-returns-a-float }
          rndIntArg := (rndRawTk = tyInteger) or (rndRawTk = tyInt64) or
                       (rndRawTk = tyBoolean) or TypeIsPromoInt(rndRawTk);
          rndArgTk := rndRawTk;
          rndArg := rndRawArg;               { the un-unboxed argument }
          ParseExpr;
          Expect(tkRParen, ')');
          { …and with a non-negative ndigits the rounding cannot change an
            integer at all, so the whole call is the identity. A NEGATIVE
            ndigits does round (`round(1234, -2)` is 1200, still an int) and a
            computed one is unknown here; both keep the float path below, which
            is what shipped — the int-typed answer for those needs a pylib
            routine and is recorded on the ticket. }
          { a statically-typed int with a non-negative LITERAL ndigits needs no
            call at all — rounding an integer up cannot change it. NOT a bool:
            `round(True, 2)` is 1 in CPython, an int, so the identity would keep
            a value that PRINTS as True. }
          if rndIntArg and (rndArgTk <> tyBoolean) and
             (ASTKind[CurASTNode] = AN_INT_LIT) and
             (ASTIVal[CurASTNode] >= 0) then
          begin
            CurASTNode := rndArg;
            LastExprTk := rndArgTk;
            Exit;
          end;
          { a statically-typed INT with any other ndigits: an int result, so
            `round(1234, -2)` is 1200 and not 1200.0 }
          if rndIntArg and (not TypeIsPromoInt(rndArgTk)) then
          begin
            argSeq := FindProc('pyround_int');
            if argSeq < 0 then Error('Nil Python: pylib (pyround_int) not loaded');
            node := AllocNode(AN_CALL);
            ASTIVal[node] := argSeq;
            argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := rndArg;
            prevTok := AllocNode(AN_ARG); ASTLeft[prevTok] := CurASTNode;
            ASTRight[prevTok] := -1;
            ASTRight[argSeq] := prevTok;
            ASTLeft[node] := argSeq;
            ASTTk[node] := Ord(tyInt64);
            CurASTNode := node;
            LastExprTk := tyInt64;
            Exit;
          end;
          { a VARIANT or a PROMO argument: the intness is a run-time fact, so the
            variant-aware routine decides — and it gets the RAW argument, before
            the float unbox that would have thrown that fact away }
          if isNilPy and ((rndRawTk = tyVariant) or TypeIsPromoInt(rndRawTk)) then
          begin
            argSeq := FindProc('pyround_v');
            if argSeq < 0 then Error('Nil Python: pylib (pyround_v) not loaded');
            node := AllocNode(AN_CALL);
            ASTIVal[node] := argSeq;
            argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := rndRawArg;
            prevTok := AllocNode(AN_ARG); ASTLeft[prevTok] := CurASTNode;
            ASTRight[prevTok] := -1;
            ASTRight[argSeq] := prevTok;
            ASTLeft[node] := argSeq;
            ASTTk[node] := Ord(tyVariant);
            CurASTNode := node;
            LastExprTk := tyVariant;
            Exit;
          end;
          argSeq := FindProc('pyround_n');
          if argSeq < 0 then Error('Nil Python: pylib (pyround_n) not loaded');
          node := AllocNode(AN_CALL);
          ASTIVal[node] := argSeq;
          argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := rndArg;
          prevTok := AllocNode(AN_ARG); ASTLeft[prevTok] := CurASTNode;
          ASTRight[prevTok] := -1;
          ASTRight[argSeq] := prevTok;
          ASTLeft[node] := argSeq;
          ASTTk[node] := Ord(tyDouble);
          CurASTNode := node;
          LastExprTk := tyDouble;
          Exit;
        end;
        Expect(tkRParen, ')');
        { round()/trunc() of an ARBITRARY-PRECISION int is the IDENTITY, same as
          int() above: rounding an integer cannot change it, and narrowing it
          would lose the precision that is the whole point. -203/-204 are raw
          SSE conversions, so a promo argument had its SLOT ADDRESS converted —
          `round(i + 1)` printed 5553816. Only the int-yielding pair: frac/int
          (-205/-206) are the float intrinsics and NilPy's own `int` is handled
          at its own site. }
        if isNilPy and ((prevTok = -203) or (prevTok = -204)) and
           TypeIsPromoInt(IntToTypeKind(ASTTk[CurASTNode])) then
        begin
          LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
          Exit;
        end;
        { …and the same value reached through a VARIANT — a module global
          holding `2 ** 70` types tyVariant here, not promo, so the guard above
          missed it and the SSE conversion of the unboxed double answered
          -9223372036854775808. The variant routine keeps a promo exact, an int
          an int, and rounds a float half-to-even into one.
          bug-nilpy-two-argument-round-of-an-int-returns-a-float }
        if isNilPy and (prevTok = -204) and (rndRawTk = tyVariant) then
        begin
          argSeq := FindProc('pyround1_v');
          if argSeq < 0 then Error('Nil Python: pylib (pyround1_v) not loaded');
          node := AllocNode(AN_CALL);
          ASTIVal[node] := argSeq;
          prevTok := AllocNode(AN_ARG); ASTLeft[prevTok] := rndRawArg;
          ASTRight[prevTok] := -1;
          ASTLeft[node] := prevTok;
          ASTTk[node] := Ord(tyVariant);
          CurASTNode := node;
          LastExprTk := tyVariant;
          Exit;
        end;
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
      { A qualified member whose name Pascal RESERVES: `tk.END` is what every
        tkinter application writes, and a library cannot declare a constant
        called END, so it declares END_ and the name is mapped here. The same
        trailing-underscore convention the reserved METHOD names already use
        (set_, destroy_). Applied to the qualified form only, so an ordinary
        Pascal `unit.End` is untouched — there is no such thing. }
      if isNilPy and (qUnit >= 0) then name := PyMapReservedMember(name);
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
        { `SizeOf(System.TMethod)` / `SizeOf(System.LongWord)` — and any OTHER
          unit qualifier: `SizeOf(Math.Float)` is how rtl-generics spells the
          width it hashes. ConsumeUnitQualifier is the expression parser's own
          resolver (it starts with EatSystemQualifier, so System.* is still
          covered) and returns -1 without consuming anything when the leading
          name is not a unit — which is what leaves `SizeOf(TOuter.TInner)` to
          the class-qualifier strip just below. One resolver, not a second
          hand-rolled copy: devdocs/dev/normalise-dont-special-case.md. }
        szQUnit := ConsumeUnitQualifier(name);   { the consumption is the point }
        { SizeOf has its own hand-rolled type dispatch, so it needs the class-qualifier
          strip too: `SizeOf(TOuter.TInner)` on a class-nested type. Without it the parse
          died on the '.' while `var r: TOuter.TInner` already worked — a half-working
          feature is worse than an absent one. Same rule as ParseTypeKind: pxx registers
          nested types globally, so the qualifier only disambiguates the parse. }
        if (CurTok.Kind = tkIdent) and (FindUClass(name) >= 0) and
           (TokPos < TokCount) and (Tokens[TokPos].Kind = tkDot) and
           (TokPos + 1 < TokCount) and (Tokens[TokPos + 1].Kind = tkIdent) then
        begin
          Next;               { past the class name — CurTok is now '.' }
          Next;               { past '.'            — CurTok is now the nested type name }
          name := CurTok.SVal;
        end;
        { A builtin type spelled as a KEYWORD token (Double, Char, String, ...)
          carries no SVal, so give `name` the token's own text -- then ONE
          name-keyed lookup answers every builtin, whichever way it lexed. That
          split is what left SizeOf(Double) and SizeOf(Variant) rejected while
          SizeOf(Integer) worked: the token-kind arms and the name arms were two
          tables, and only the second one ever got extended. }
        if name = '' then name := GetTokenStr(TokPos - 1);
        szBTk := BuiltinTypeNameTk(name);
        if szBTk <> tyUnknown then
          prevTok := TypeSize(szBTk)
        else if CurTok.Kind = tkIdent then
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
                sci := FindVarSym(name);   { a bare class var is a variable here too }
                if sci >= 0 then
                begin
                  if (Tokens[TokPos].Kind = tkDot) and (Syms[sci].RecName >= 0) and
                     (not Syms[sci].IsArray) then
                  begin
                    { SizeOf(obj.field[.field..]) — walk the selector chain
                      (never evaluating, like every SizeOf operand) and
                      report the FINAL field's size (blcksock's
                      SizeOf(Value.Value)).

                      Sized through RecFieldByteSize, NOT TypeSize(RecFieldType):
                      RecFieldType answers an array field's ELEMENT kind, so the
                      latter reported 4 for an `array[0..2] of Integer` field
                      while the same array as a plain VAR reported 12, silently
                      and with the comment here claiming array fields errored out
                      (bug-p-sizeof-an-array-field-returns-the-element-size). One
                      field-size answer for everyone rather than a formula per
                      caller: devdocs/dev/normalise-dont-special-case.md. }
                    szRec := Syms[sci].RecName;
                    szElemTk := tyUnknown;
                    Next;   { consume the identifier; CurTok = '.' }
                    while CurTok.Kind = tkDot do
                    begin
                      Next;   { consume '.'; CurTok = field name }
                      if CurTok.Kind <> tkIdent then Error('SizeOf: expected field name');
                      szElemTk := RecFieldType(szRec, CurTok.SVal);
                      if szElemTk = tyUnknown then Error('SizeOf: unknown field');
                      prevTok := RecFieldByteSize(szRec, CurTok.SVal);
                      szRec := RecFieldRecId(szRec, CurTok.SVal);
                      if Tokens[TokPos].Kind = tkDot then Next;   { deeper chain }
                    end;
                    { CurTok = the last field name; the shared trailing Next
                      below moves past it to the ')'. prevTok already holds that
                      field's size. }
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
                  else if Syms[sci].IsArray and
                          ((SymDynDepth[sci] > 0) or (Syms[sci].ArrLen < 0)) then
                    { A DYNAMIC array variable is a handle, so pointer width --
                      the rule the named dynamic-array ALIAS branch above already
                      applies, and the one a dynamic-array FIELD gets from
                      RecFieldByteSize. Falling into the static formula below
                      multiplied the element size by ArrLen = -1 and SizeOf(d)
                      answered **-4**: a negative size, silently, which
                      `GetMem(SizeOf(d))` and any Move/FillChar sized that way
                      would carry straight into the allocator
                      (found widening bug-p-sizeof-an-array-field-returns-the-element-size). }
                    prevTok := TARGET_PTR_SIZE
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

      { A value cast to an ordinal type NAMED BY AN IDENTIFIER -- `WideChar(x)` (fpjson's
        \u escape decoder). The builtin casts above key on the type KEYWORD token
        (tkInteger_T etc.), so a type whose name merely lexes as an identifier -- WideChar,
        QWord, NativeInt -- had no cast at all and came out as "undefined variable".

        AN_PTR_CAST with ASTIVal = -1 is the real-width-truncating value cast (the same node
        `Byte(x)` builds), not the Integer/LongWord value-pun. A variable, routine or user
        type alias of the same name still wins. }
      if ((qUnit = -2) or ((FindSym(name) < 0) and (FindProc(name) < 0) and
                           (FindTypeAlias(name) < 0))) and
         (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) and
         (OrdinalNameToTk(name) <> tyUnknown) then
      begin
        tk := OrdinalNameToTk(name);
        Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
        { a promotable operand demotes to a real machine integer BEFORE the
          width-truncating cast — otherwise the cast truncates the SLOT ADDRESS.
          This is the site every IDENT-spelled ordinal name reaches (Int64,
          LongInt, Cardinal, NativeInt, Word, Byte...); only `Integer`/`Byte`/
          `LongWord` have their own keyword TOKEN and their own branch, which is
          why fixing that one made Integer(n) right while Int64(n) stayed
          wrong. See PromoDemoteToInt64. }
        CurASTNode := PromoDemoteToInt64(CurASTNode);
        { …and the same two-sites trap applies to the VARIANT conversion: this
          is where `Int64(v)` / `QWord(v)` / `NativeInt(v)` land, so fixing only
          the keyword-token arms left exactly `Int64(v)` still answering the tag
          word. Convert here and WRAP the converted temp in the cast below
          rather than exiting — the wrap is then a no-op retag (or the 16-bit
          truncation WideChar wants) and the -3 WideChar marker survives.
          See VariantCastToTemp. }
        vcNode := VariantCastToTemp(CurASTNode, tk);
        if vcNode >= 0 then CurASTNode := vcNode;
        node := AllocNode(AN_PTR_CAST);
        ASTLeft[node] := CurASTNode;
        { -3 = a WIDECHAR value cast: same width-truncating value cast as -1
          (every consumer treats them alike), but string contexts recognise it
          and convert the UTF-16 code unit to UTF-8 (__pxxWideCharToUTF8 /
          the surrogate-aware pair helper) instead of mistreating the ordinal
          as a managed-string pointer. }
        if CaseEqual(name, 'widechar') then
          ASTIVal[node] := -3
        else
          ASTIVal[node] := -1;
        ASTTk[node] := Ord(tk);
        CurASTNode := node;
        LastExprTk := tk;
        Exit;
      end;

      { TypeInfo(T) -- FPC's System intrinsic. Enum types (the original support) yield
        the address of the enum RTTI blob {name, count, names[]} directly, unchanged --
        that is what typinfo.pas's GetEnumName/GetEnumNameCount already take, and
        fpjson's RTTI streaming is gated on it staying exactly as it was.

        Scalars, strings, classes and records (feature-pascal-corpus-generics: rung 3
        needs TypeInfo(T) for GENERIC PARAMETERS, e.g. Generics.Defaults selecting a
        comparer by Kind) go through a SEPARATE, uniform "PTypeInfo" header --
        {Kind, NamePtr, DataPtr} -- built by EmitTypeInfoHeaders once EmitRTTI has run
        (rtti_emit.inc) and read generically by typinfo.pas regardless of category. No
        FPC byte-layout parity is implied or needed (see feature-pascal-corpus-generics
        "NO DECISION NEEDED" recon note) -- typinfo.pas owns the whole translation. }
      { __pxxExceptAddr: the raise site of the exception in flight. Zero-arg, and the
        reserved prefix keeps it out of the user's namespace — sysutils.ExceptAddr is a
        one-line wrapper over it. Parens optional, like any zero-arg Pascal function. }
      if CaseEqual(name, '__pxxExceptAddr') and (FindProc(name) < 0) and (FindSym(name) < 0) then
      begin
        Next;
        if (TokPos <= TokCount) and (CurTok.Kind = tkLParen) then
        begin
          Next;
          Expect(tkRParen, ')');
        end;
        EnableExceptionRuntime;   { a program may read the raise site without raising itself }
        node := AllocNode(AN_EXCEPTADDR);
        ASTTk[node] := Ord(tyPointer);
        LastExprTk := tyPointer;
        CurASTNode := node;
        Exit;
      end;

      { __pxxSigCode / __pxxSigAddr / __pxxSigContext: the siginfo of the signal
        currently being dispatched. Zero-arg with optional parens and a reserved
        prefix, exactly like __pxxExceptAddr above — an RTL wrapper gives them
        friendly names.

        si_code is THE reason SA_SIGINFO exists here: it is the only carrier of
        which fault occurred (the MXCSR status flags read 0x00 inside a handler,
        measured — see feature-float-exception-mask-control).

        Hosted Linux targets only, and REFUSED elsewhere (xtensa/ESP) rather than
        answering 0: a target whose handlers are installed without SA_SIGINFO
        never writes the slots, and a plausible 0 ("SI_USER", "no fault address")
        is exactly the silent wrong value this dialect refuses to invent — the
        same call the ESP PAL makes with PAL_ERR_UNSUPPORTED.
        feature-signal-siginfo-ucontext }
      { __pxxSigPCPtr joins them: the ADDRESS of the saved program counter inside
        that ucontext — the one word whose location is per-arch knowledge the
        compiler already has and a Pascal program does not.

        A POINTER rather than a read/write pair on purpose. Handing back the slot
        address makes reading it (`PPtrUInt(__pxxSigPCPtr)^`) and rewriting it
        (`PPtrUInt(__pxxSigPCPtr)^ := PtrUInt(@Recover)`) ordinary Pascal, so one
        intrinsic covers both directions and the compiler owns exactly one fact:
        the offset. Rewriting it is what turns a fault into a catchable raise —
        the handler points the PC at a Pascal proc that raises, and the exception
        runtime's shadow stack (BSS_EXC_TOP, a setjmp chain) unwinds from there
        regardless of the interrupted SP. WHICH exception to raise stays a
        library question, deliberately: see
        decide-int-div-zero-behavior-unification, still open on where a builtin
        exception class should live.

        Meaningful only while a handler is running (ctx is nil otherwise, so the
        pointer would be a small bogus address) — same caller-must-know contract
        as si_addr being a pid for a kill()-delivered signal. }
      if (CaseEqual(name, '__pxxSigCode') or CaseEqual(name, '__pxxSigAddr') or
          CaseEqual(name, '__pxxSigContext') or CaseEqual(name, '__pxxSigPCPtr')) and
         (FindProc(name) < 0) and (FindSym(name) < 0) then
      begin
        { Every hosted Linux target now installs with SA_SIGINFO; only xtensa/ESP
          is left out, and deliberately — FreeRTOS is not a Unix and has no
          signal runtime at all (EmitSignalRuntime* has no xtensa sibling). }
        if TargetArch = TARGET_XTENSA then
          Error(name + ' needs SA_SIGINFO, which this target''s signal runtime '
                + 'does not install (feature-signal-siginfo-ucontext)');
        if NoSignals then
          Error(name + ' requires the signal runtime (built with --no-signals)');
        Next;
        if (TokPos <= TokCount) and (CurTok.Kind = tkLParen) then
        begin
          Next;
          Expect(tkRParen, ')');
        end;
        node := AllocNode(AN_SIGINFO);
        if CaseEqual(name, '__pxxSigCode') then
        begin
          { tyInteger, NOT tyInt64: si_code's real width is a signed 32-bit int,
            and on the ILP32 targets an Int64 is a register PAIR — a stub would
            have to write a second sign word into the slot, and every backend's
            IR_EXC_STORE moves exactly one machine word. Typing it at the field's
            true width sidesteps the pair on all six backends at once. (Decided
            2026-08-13, feature-signal-siginfo-ucontext: small now, breaking
            later.) The x86-64 stub still sign-extends into its 8-byte slot, so
            the slot stays self-consistent whoever reads it. }
          ASTIVal[node] := 0; ASTTk[node] := Ord(tyInteger);
        end
        else if CaseEqual(name, '__pxxSigAddr') then
        begin
          ASTIVal[node] := 1; ASTTk[node] := Ord(tyPointer);
        end
        else if CaseEqual(name, '__pxxSigContext') then
        begin
          ASTIVal[node] := 2; ASTTk[node] := Ord(tyPointer);
        end
        else
        begin
          ASTIVal[node] := 3; ASTTk[node] := Ord(tyPointer);
        end;
        LastExprTk := IntToTypeKind(ASTTk[node]);
        CurASTNode := node;
        Exit;
      end;

      if CaseEqual(name, 'TypeInfo') and
         ((qUnit = -2) or ((FindProc(name) < 0) and (FindSym(name) < 0))) and
         (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        i := -1; ci := -1; tiTk := tyUnknown; tiName := '';
        if CurTok.Kind = tkIdent then
        begin
          tiName := CurTok.SVal;
          i := FindEnumType(tiName);
          if i < 0 then
          begin
            ci := FindUClass(tiName);
            if ci < 0 then
            begin
              tiTk := OrdinalNameToTk(tiName);
              if tiTk = tyUnknown then
              begin
                if CaseEqual(tiName, 'string') or CaseEqual(tiName, 'ansistring') then tiTk := tyAnsiString
                else if CaseEqual(tiName, 'shortstring') then tiTk := tyShortString
                else if CaseEqual(tiName, 'single') then tiTk := tySingle
                else if CaseEqual(tiName, 'double') or CaseEqual(tiName, 'real') then tiTk := tyDouble
                else if CaseEqual(tiName, 'extended') then tiTk := tyExtended;
              end;
            end;
          end;
        end
        else if CurTok.Kind in [tkInteger_T, tkBoolean_T, tkChar_T, tkString_T, tkReal_T,
                                 tkLongWord_T, tkSingle_T, tkDouble_T, tkExtended_T] then
        begin
          { Type-keyword tokens (Integer/Boolean/Char/String/Real/LongWord/Single/
            Double/Extended lex as their OWN token kind, not tkIdent -- SVal is
            empty for these, read the spelling via GetTokenStr like the class-body
            method-named-after-a-type-keyword path does, b332. }
          tiName := GetTokenStr(TokPos);
          case CurTok.Kind of
            tkInteger_T:  tiTk := tyInteger;
            tkBoolean_T:  tiTk := tyBoolean;
            tkChar_T:     tiTk := tyChar;
            tkString_T:   tiTk := tyAnsiString;
            tkReal_T:     tiTk := tyDouble;
            tkLongWord_T: tiTk := tyUInt32;
            tkSingle_T:   tiTk := tySingle;
            tkDouble_T:   tiTk := tyDouble;
            tkExtended_T: tiTk := tyExtended;
          end;
        end
        else
          Error('TypeInfo expects a type name');
        Next;
        Expect(tkRParen, ')');
        node := AllocNode(AN_TYPEINFO);
        if i >= 0 then
          { legacy enum path: ASTLeft stays -1, ASTIVal = enum type id, exactly as before }
          ASTIVal[node] := i
        else if ci >= 0 then
        begin
          ASTLeft[node] := 1;
          if UClsIsRecord[ci] then
            ASTIVal[node] := RegisterTypeInfoReq(TYPEINFO_REQ_CAT_RECORD, ci)
          else
            ASTIVal[node] := RegisterTypeInfoReq(TYPEINFO_REQ_CAT_CLASS, ci);
        end
        else if tiTk <> tyUnknown then
        begin
          ASTLeft[node] := 1;
          ASTIVal[node] := RegisterTypeInfoReq(TYPEINFO_REQ_CAT_ORD, Ord(tiTk));
        end
        else
          Error('TypeInfo is not supported for type: ' + tiName);
        ASTTk[node] := Ord(tyPointer);
        LastExprTk := tyPointer;
        CurASTNode := node;
        Exit;
      end;

      if (CaseEqual(name, 'get_frame') or CaseEqual(name, 'get_pc_addr')) and
         (FindProc(name) < 0) and (FindSym(name) < 0) then
      begin
        { FPC's System stack-frame intrinsics, reached with no `uses` -- so they are
          soft keywords (a real symbol of the same name still wins, per the guard).

            get_frame    the current function's frame pointer
            get_pc_addr  the return address of the current function

          FPC allows both bare and with an empty (). Diagnostic code (fpcunit's
          CallerAddr, any backtrace) walks the chain with these plus
          get_caller_stackinfo below. }
        { The program body runs at the ELF entry, where SysV leaves no linked frame
          (rbp = 0 -- it IS the outermost frame). So there is nothing to read and
          nothing to walk: say so at compile time rather than fault at runtime.
          Routines, including unit init sections, all have a real prologue. }
        if CurProc < 0 then
          Error(name + ' needs a stack frame, and the program body has none (it is the outermost frame): call it from a routine');
        FrameIntrinsicUsed := True;
        if CurProc >= 0 then ProcFrameSensitive[CurProc] := True;
        if CaseEqual(name, 'get_frame') then node := AllocNode(AN_FRAME)
        else node := AllocNode(AN_PCADDR);
        ASTTk[node] := Ord(tyPointer);
        Next;
        if CurTok.Kind = tkLParen then
        begin
          Next;
          Expect(tkRParen, ')');
        end;
        LastExprTk := tyPointer;
        CurASTNode := node;
        Exit;
      end;

      { __pxxGetFPUMask / __pxxSetFPUMask(m): the float-exception MASK.

        The value is a 6-bit set in FPC's TFPUException order — bit 0
        exInvalidOp, 1 exDenormalized, 2 exZeroDivide, 3 exOverflow,
        4 exUnderflow, 5 exPrecision — where 1 means MASKED, i.e. the quiet
        IEEE behaviour (inf/NaN propagate) that is pxx's default and stays it.
        Clearing a bit UNMASKS: the offending SSE instruction then traps
        SIGFPE, and __pxxSigCode says which (FPE_FLTDIV/OVF/UND/INV) — the
        MXCSR status flags cannot, they read 0x00 inside a handler because
        Linux hands it a clean FP state (measured, see the ticket).

        SET returns the PREVIOUS mask, so save/restore is one expression and
        this family needs no statement-position hook — the same call
        __pxxSigPCPtr made by handing back a pointer instead of adding a setter.

        x86-64 only for now, and REFUSED elsewhere rather than accepted as a
        no-op. On aarch64/arm32 the FPCR/FPSCR trap-enable bits are permitted
        to be RES0 (most implementations never trap), and RISC-V has no
        trapping FP at all — only sticky flags. Accepting the call there would
        report a mask that does nothing, which is the silent wrong answer this
        dialect refuses to invent. feature-float-exception-mask-control }
      if (CaseEqual(name, '__pxxGetFPUMask') or CaseEqual(name, '__pxxSetFPUMask')) and
         (FindProc(name) < 0) and (FindSym(name) < 0) then
      begin
        if TargetArch = TARGET_I386 then
          Error(name + ' is not ported to i386 yet: it does its float '
                + 'arithmetic in SSE too, so MXCSR is the same mechanism, but '
                + 'its x87 control word (used for the int conversions) would '
                + 'have to move with it '
                + '(feature-float-exception-mask-control)')
        else if TargetArch <> TARGET_X86_64 then
          Error(name + ' is x86-64 only: this target has no architecturally '
                + 'guaranteed float-exception trap enable '
                + '(feature-float-exception-mask-control)');
        node := AllocNode(AN_FPUMASK);
        ASTTk[node] := Ord(tyInteger);
        if CaseEqual(name, '__pxxGetFPUMask') then
        begin
          ASTIVal[node] := 0;
          Next;
          if (TokPos <= TokCount) and (CurTok.Kind = tkLParen) then
          begin
            Next;
            Expect(tkRParen, ')');
          end;
        end
        else
        begin
          ASTIVal[node] := 1;
          Next;
          Expect(tkLParen, '(');
          ParseExpr;
          ASTLeft[node] := CurASTNode;
          Expect(tkRParen, ')');
        end;
        LastExprTk := tyInteger;
        CurASTNode := node;
        Exit;
      end;

      if CaseEqual(name, '__pxxmulhi_u64') then
      begin
        { __pxxmulhi_u64(a, b): the HIGH 64 bits of the unsigned 128-bit product
          a*b (the low half is an ordinary a*b). Lowers to IR_MULHI -- x86-64
          `mul`, aarch64 `umulh`. 64-bit targets only; lowering rejects the
          32-bit ones. Portable callers use lib/rtl's MulHiU64 wrapper. }
        node := AllocNode(AN_MULHI);
        ASTTk[node] := Ord(tyUInt64);
        Next; { consume the intrinsic name }
        Expect(tkLParen, '(');
        ParseExpr;
        ASTLeft[node] := CurASTNode;
        Expect(tkComma, ',');
        ParseExpr;
        ASTRight[node] := CurASTNode;
        Expect(tkRParen, ')');
        LastExprTk := tyUInt64;
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
        { NOT FindProcBound: this arm exists so an explicit `System.X` reaches
          the BUILTIN, and scope hiding would hand back the used unit's
          same-named routine instead — `System.Random(i+1)` stopped reaching
          System's generator (test_builtin_name_demote). A qualified call names
          its scope; hiding is for unqualified ones. }
        procIdx := FindProc(name);
      end
      else
      begin
        idx := FindSym(name);
        { a BARE reference binds under the scope-hiding rule — FindProc alone
          answers with the set's representative, which ignores `uses` order.
          In NilPy user code a pylib row must match EXACTLY: Python is
          case-sensitive and pylib IS its builtin namespace. }
        if NilPyUserCode then procIdx := FindProcNilPyBound(name)
        else procIdx := FindProcBound(name);
      end;

      { The EXPRESSION half of the own-field-beats-a-unit-name rule; the
        statement half sits on the assignment path in ParseStatementAST. Skipped
        for an explicitly qualified `unit.Name`, which asks for that unit's
        symbol by construction. }
      if qUnit < 0 then idx := OwnFieldBeatsSym(idx, name);

      { A NilPy program's OWN class beats a pylib routine of the same name.
        Shadowing a builtin is ordinary Python — `class Counter:`, `def list(...)`
        — and from that point on the name means the user's. pylib spells
        collections.Counter as overloaded FUNCTIONS, so `Counter` bound to those
        instead, and `Counter.k` on the user's class died with
        '"k": no such member on this record/class': an error about a MEMBER,
        which sends the reader to the class body rather than to the name
        (bug-nilpy-user-class-named-like-a-pylib-builtin-is-shadowed).

        UClsUnitIdx = -1 is "declared in the main program", so this only fires
        for a class the user wrote; a pylib class keeps losing to a pylib
        routine exactly as before, and Pascal is untouched. }
      { …matched EXACTLY. FindUClassInUnit is case-insensitive, Pascal-style, so
        a lowercase `def f` lost its proc to `class F` — and then, since classes
        became values, `f(1, 2)` compiled clean and raised "takes 0 positional
        arguments" from the ctor of a class the program never named. Python is
        case-sensitive: `f` and `F` are unrelated names and neither shadows the
        other. This is the site that decides it; PyIsClassTypeExact (typing),
        PyIsExactCtorName (construction) and the two guards added beside them
        are the same rule at the other four
        (bug-nilpy-a-lowercase-name-is-hijacked-by-a-case-matching-class). }
      if NilPyUserCode and (qUnit < 0) and (procIdx >= 0) and (idx < 0) and
         (FindUClassInUnit(name, -1) >= 0) and PyIsClassTypeExact(name) then
        procIdx := -1;

      { A NilPy module-level `def` is NOT bound above its own `def` statement —
        Python rebinds the name when that statement RUNS, so a module-body call
        that precedes it still reaches whatever the name meant before.

        PyUserShadowsProc already answers that question, and it gates both the
        overload demote and every name-keyed intrinsic below. But each of those
        intrinsic guards ALSO requires `procIdx < 0`, and for a builtin that has
        no proc of its own name — `ord`, `chr`, `abs`, `set`, `id`, `hash`,
        `ascii`, `callable`, `iter`, `range`, … are lowered by NAME dispatch,
        not as pylib routines — the user's def is then the ONLY proc called
        `ord`, ordinary resolution found it from anywhere in the module, and the
        intrinsic never got the chance. `print(ord("A"))` above a `def ord(x)`
        printed the user's answer where CPython prints 65, silently. The
        positional rule was being enforced by COMPETITION, not by the gate, and
        it lapsed for exactly the builtins that have no competitor.
        bug-nilpy-intrinsic-only-builtin-is-shadowed-from-the-top-of-the-module

        So unbind the name here, where every intrinsic guard downstream reads
        it, and REBIND it just before the ordinary call paths (`sci :=
        FindStrConst(name)` below). Unbinding it permanently would turn a
        module-body forward call into a compile error, and CPython accepts one
        that never executes (`if False: helper()` above `def helper()`) — NilPy
        is upward compatible with CPython, so refusing that is not allowed.

        Module body only (CurProc < 0): inside a def body the code runs after
        the whole module has executed, so an ordinary forward reference between
        two defs is legal Python and must keep working. }
      { A LOCAL BINDING BEATS A `def` OF THE SAME NAME.

        In Python a `def` is not a namespace of its own -- it is a name binding
        like any other, and inside a function body a local binding shadows the
        module-level one for the WHOLE body. NilPy resolved a bare-name call
        against declared procedures first and only fell back to variables, so a
        `def` outranked every later rebinding. `normalise-dont-special-case`:
        one concept (a name that denotes something callable) served by two
        mechanisms, and the second one is the one that was broken.

        Silent, which is what made it expensive -- the WRONG function ran and
        returned a plausible value. It only turned loud where the two arities
        disagree, which is how it was found: webencodings' `iter_decode` does
        `decode = decoder.decode` and then `decode(b'', final=True)`, bound to
        the module-level `def decode(input, fallback_encoding, errors=...)`,
        and the compiler said `decode has no parameter named 'final'` -- a
        diagnostic that is CORRECT ABOUT THE WRONG CALLEE, which is why it read
        as a signature bug. That one line was the first wall on 12 of the 38
        remaining third-party corpus files.

        skLocal/skParam only, deliberately. Python's scoping makes a local
        binding unconditionally win for the whole body, so no ordering question
        arises and the rule needs no token positions. A MODULE-level rebinding
        (`f = o.f` after `def f`) is the same bug and is NOT fixed here: at
        module level the answer depends on which statement ran last, which this
        site cannot see. That arm stays open in the ticket rather than being
        guessed at.

        NOT fixable by re-ranking FindProc -- see the warning above MatchElig in
        symtab.inc: that was tried and broke the compiler's own self-compile and
        the NilPy stdlib, because FindProc returns an overload-set
        representative whose SIGNATURE callers read types off. It is not a "what
        does this name call" query. The decision belongs here.
        bug-nilpy-a-callable-in-a-variable-loses-to-a-def-of-the-same-name }
      if NilPyUserCode and (qUnit < 0) and (procIdx >= 0) and
         (idx >= 0) and (Syms[idx].Kind in [skLocal, skParam]) then
        procIdx := -1;

      pyLateDefPi := -1;
      if NilPyUserCode and (qUnit < 0) and (procIdx >= 0) and
         (ProcUnitIdx[procIdx] = -1) and (not PyDefBoundHere(procIdx)) and
         (not PyUserShadowsProc(name)) then
      begin
        pyLateDefPi := procIdx;
        procIdx := -1;
      end;

      { Bare class const inside a method body — `Result := Max` where TFoo declares
        `const Max`. FPC scope order: a genuine local/param shadows it, but a class
        const BEATS a unit global of the same name (repro 2: a method's `Size` is
        the class const 777, not the unit const 10). So fire whenever the name did
        not bind to a local/param. Walks own class then ancestors; qualified
        `TFoo.Max` is handled separately in ParseLValueAST.
        bug-pascal-class-const-visibility. }
      if (qUnit < 0) and (CurProc >= 0) and (CurMethClass >= REC_UCLASS_BASE) and
         (not ((idx >= 0) and (Syms[idx].Kind in [skLocal, skParam]))) then
      begin
        ccReg := FindClassConst(CurMethClass - REC_UCLASS_BASE, name);
        if ccReg >= 0 then
        begin
          if StrictVisibility then
            EnforceMemberVis(ClassConstCi[ccReg], ClassConstVis[ccReg], name);
          ccKey := ClassConstMangle(ClassConstCi[ccReg], name);
          ccNode := EmitClassConstNode(ccKey, ccTk);
          if ccNode >= 0 then
          begin
            Next;
            CurASTNode := ccNode;
            LastExprTk := ccTk;
            Exit;
          end;
        end;
      end;

      { A bare class-reference OPERATION inside a method body -- implicit Self:
        `ClassName`, `ClassType`, `InheritsFrom(C)` with no receiver (fpcunit's
        TTestCase.GetTestName reads a bare ClassName).

        GenMakeImplicitMetaclass already yields the right blob for either method kind:
        an instance method's Self walks to its RUNTIME class, a class method's Self IS
        the class. So this is the same operation as the qualified form, with the
        receiver implied. A member of that name on the class still wins. }
      if (procIdx < 0) and (idx < 0) and (qUnit < 0) and
         (CurProc >= 0) and (CurMethClass >= REC_UCLASS_BASE) and
         IsClassRefOpName(name) and
         (FindUMeth(CurMethClass - REC_UCLASS_BASE, name) < 0) and
         (FindUField(CurMethClass - REC_UCLASS_BASE, name) < 0) then
      begin
        smSelfNode := GenMakeImplicitMetaclass;
        if smSelfNode >= 0 then
        begin
          Next;                    { consume the operation name }
          node := GenMakeClassRefOp(smSelfNode, name, tk);
          if node >= 0 then
          begin
            node := ParseClassRefOpTail(node, tk);
            LastExprTk := tk;
            CurASTNode := node;
            Exit;
          end;
        end;
      end;

      { Bare call to a sibling CLASS (static) method, from inside a class method.

        CurSelfClass is deliberately unset in a `class procedure` -- it is static and
        has no Self -- so every implicit-Self dispatch above is skipped, and the name
        used to fall through to "undefined variable". But a static method needs no
        Self: it is callable exactly like a plain proc, so all that was missing was
        finding it. Bind procIdx and let the ordinary call machinery (args, defaults,
        overloads) do the rest.

        Keyed on CurMethClass, which IS set for both method kinds -- the same reason
        the bare `class var` lookup uses it. Only STATIC methods qualify: an instance
        method reached from a class method has no instance to run on, and must keep
        failing. A local/param (idx >= 0), a real proc (procIdx >= 0) or a unit
        qualifier all still win. This is fpcunit's TAssert.FailEquals calling Fail. }
      if (procIdx < 0) and (idx < 0) and (qUnit < 0) and
         (CurProc >= 0) and (CurMethClass >= REC_UCLASS_BASE) then
      begin
        smmiS := FindUMethOverloadAhead(CurMethClass - REC_UCLASS_BASE, name, CountCallArgsAhead);
        if (smmiS >= 0) and UMthIsStatic[smmiS] and (UMthProc_[smmiS] >= 0) then
        begin
          EnforceMethVis(smmiS, name);
          smSelfNode := GenMakeImplicitMetaclass;
          if smSelfNode >= 0 then
          begin
            Next;                 { consume the method name }
            GenVirtSlot := UMthVirSlot[smmiS];
            node := GenMakeStaticMethodCall(UMthProc_[smmiS], smSelfNode);
            LastExprTk := Procs[UMthProc_[smmiS]].RetType;
            CurASTNode := node;
            Exit;
          end;
        end;
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
      { qUnit = -1 only: `System.X` (qUnit = -2) names the RTL routine
        explicitly, so the class method must not shadow it — the statement-side
        twin has the same guard (fpjson's System.Delete vs TJSONArray.Delete). }
      { …but NOT in NilPy, where a bare name is NEVER a method: Python reaches
        a method only through `self.`, so an unqualified call names the
        module-level function even when the class has one of the same name.
        songformatter's `def select_image(self): select_image()` is exactly
        that — a method delegating to the module function it shadows — and
        routing it to implicit-Self dispatch made it a call of ITSELF with the
        wrong arity. }
      { …and NOT isNilPy, which is true for the WHOLE compilation. A Pascal
        RTL unit pulled in behind a NilPy program is still Pascal and still
        wants FPC's shadowing rule: lib/rtl/classes.pas `uses sysutils`, so
        TStrings.SetValueFromIndex's bare `Delete(Index)` bound
        sysutils.Delete(var s; index, count) and the unit failed to compile at
        all under NilPy while compiling clean under Pascal — the same file, the
        same pin. NilPyUserCode is the predicate that asks what was actually
        meant ("code the NilPy user wrote", PyExprMode telling a .py module
        body from a Pascal unit). bug-a-the-import-escape-hatch-fails-on-classes-pas }
      if (procIdx >= 0) and (qUnit = -1) and (idx < 0) and (not NilPyUserCode) and
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
      if CaseEqual(name, 'GetMem') and
         ((qUnit = -2) or ((procIdx < 0) and (FindSym(name) < 0))) and
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
      if (CaseEqual(name, 'Ord') or CaseEqual(name, 'Chr')) and
         ((qUnit = -2) or ((procIdx < 0) and (FindSym(name) < 0))) and
         (Tokens[TokPos].Kind = tkLParen) then
      begin
        if CaseEqual(name, 'Chr') then
        begin op := Ord(tkChr); LastExprTk := tyChar; end
        else
        begin op := Ord(tkOrd); LastExprTk := tyInteger; end;
        Next; Expect(tkLParen, '(');
        ParseExpr;
        Expect(tkRParen, ')');
        node := AllocNode(AN_CALL); ASTIVal[node] := -op;
        if op = Ord(tkChr) then ASTTk[node] := Ord(tyChar) else ASTTk[node] := Ord(tyInteger);
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
        ASTLeft[node] := argSeq;
        CurASTNode := node;
        Exit;
      end;

      { High(x): soft-keyword intrinsic. High(arr) := Length(arr) - 1 — reuses
        the Length call + a subtraction, so no new IR/codegen; works for open
        arrays, dyn arrays and (via the folds) static arrays alike.

        `(qUnit = -2)` is the SYSTEM-QUALIFIER EXEMPTION, and the same expression
        appears verbatim at every soft-keyword intrinsic here — grep it. Writing
        `System.High(a)` names the builtin on purpose, exactly as `System.Move`
        does inside a class with its own Move, so a same-named local must not
        take it: `var High: Integer` made `System.High(a)` report "undefined
        variable (High)" where FPC 3.2.2 prints the bound.

        It is spelled out per site because each intrinsic tests its own
        preconditions. That is also how it drifted: `Ord`/`Chr` and `Length` had
        it (someone hit Synapse's `System.Length(buf)`), and `High`, `Low`,
        `GetMem`, `TypeInfo` and the ident-spelled ordinal casts did not — every
        site broken until somebody tripped over that one. Found by enumerating
        the guards rather than by falling over them.
        meta-a-second-paths-reimplement-the-first-paths-decisions }
      if CaseEqual(name, 'High') and
         ((qUnit = -2) or ((procIdx < 0) and (FindSym(name) < 0))) and
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
        else if (idx >= 0) and (ASTKind[valNode] = AN_IDENT) and (ASTIVal[valNode] = idx) and
                Syms[idx].IsArray and (Syms[idx].ArrLen >= 0) and (Syms[idx].Kind <> skParam) and
                (SymArrNDims[idx] >= 2) then
        begin
          { High of a WHOLE multi-dim static array = the FIRST dimension's upper
            bound (FPC: `High(m)` reports dim 0). The runtime -tkLength path reads
            a [data-8] header a static array has none of, so multi-dim used to
            return -1. First-dim low/span live in SymArrDim{Lo,Span}[sym*MAX+0]. }
          CurASTNode := AllocNode(AN_INT_LIT);
          ASTIVal[CurASTNode] := SymArrDimLo[idx * MAX_ARR_DIMS] + SymArrDimSpan[idx * MAX_ARR_DIMS] - 1;
          ASTTk[CurASTNode] := Ord(tyInteger);
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
      if CaseEqual(name, 'Low') and
         ((qUnit = -2) or ((procIdx < 0) and (FindSym(name) < 0))) and
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
        else if (idx >= 0) and Syms[idx].IsArray and (Syms[idx].Kind <> skParam) and
                (SymArrNDims[idx] >= 2) then
          { Low of a whole multi-dim static array = the FIRST dimension's lower
            bound (SymArrDimLo[sym*MAX+0]); was silently 0. }
          ASTIVal[CurASTNode] := SymArrDimLo[idx * MAX_ARR_DIMS]
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
      if CaseEqual(name, 'Length') and
         ((qUnit = -2) or ((procIdx < 0) and (FindSym(name) < 0))) and
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
        lenFieldRec := -1; lenFieldIdx := -1;
        if ASTKind[valNode] = AN_FIELD then
        begin
          lenFieldRec := ResolveNodeRec(ASTLeft[valNode]);
          if lenFieldRec >= REC_UCLASS_BASE then
            lenFieldIdx := FindUField(lenFieldRec - REC_UCLASS_BASE, GetASTIdentName(valNode));
        end;
        if (IntToTypeKind(ASTTk[valNode]) = tyChar) and (ASTCharArrayCap(valNode) < 0) then
        begin
          { …but NOT a static `array of Char`, whose AST node is ALSO typed
            tyChar (the arrayness is on the symbol). `Length(a)` on an
            array[0..7] of Char is 8, the array's length — this arm answered 1,
            the length of a Char, for as long as it has existed.
            bug-p-a-char-array-is-not-a-string-in-any-direction }
          { `Length(c)` where c is a CHAR is 1 — FPC's answer, and the same one
            `Length('y')` on a character LITERAL already gave. A Char VARIABLE
            fell through to the runtime -tkLength path, which read the value as
            a string handle and returned the CODE POINT: `c := 'x'; Length(c)`
            answered 120. Latent for as long as chars have existed; surfaced by
            bug-pascal-ord-of-a-one-char-string-const-is-its-address, which makes
            `const Sep = '/'` a Char, at which point `Length(Sep)` SEGFAULTED
            instead of merely lying. Folded here so every target gets it. }
          node := AllocNode(AN_INT_LIT);
          ASTIVal[node] := 1; ASTTk[node] := Ord(tyInteger);
          CurASTNode := node;
        end
        else if (ASTKind[valNode] = AN_IDENT) and (ASTIVal[valNode] >= 0) and
           Syms[ASTIVal[valNode]].IsArray and (Syms[ASTIVal[valNode]].ArrLen >= 0) and
           (Syms[ASTIVal[valNode]].Kind <> skParam) and (SymArrNDims[ASTIVal[valNode]] <= 1) then
        begin
          node := AllocNode(AN_INT_LIT);
          ASTIVal[node] := Syms[ASTIVal[valNode]].ArrLen; ASTTk[node] := Ord(tyInteger);
          CurASTNode := node;
        end
        else if (ASTKind[valNode] = AN_IDENT) and (ASTIVal[valNode] >= 0) and
                Syms[ASTIVal[valNode]].IsArray and (Syms[ASTIVal[valNode]].ArrLen >= 0) and
                (Syms[ASTIVal[valNode]].Kind <> skParam) and (SymArrNDims[ASTIVal[valNode]] >= 2) then
        begin
          { Length of a WHOLE multi-dim static array = the FIRST dimension's count
            (FPC). A static array carries no [data-8] header, so the runtime
            -tkLength path returned 0 for multi-dim; fold to the first-dim span
            (SymArrDimSpan[sym*MAX+0]). }
          node := AllocNode(AN_INT_LIT);
          ASTIVal[node] := SymArrDimSpan[ASTIVal[valNode] * MAX_ARR_DIMS]; ASTTk[node] := Ord(tyInteger);
          CurASTNode := node;
        end
        else if (lenFieldIdx >= 0) and UFldIsArray[lenFieldIdx] and
                (UFldArrLen[lenFieldIdx] >= 0) and (UFldDynDepth[lenFieldIdx] = 0) and
                (UFldArrNDims[lenFieldIdx] <= 1) then
        begin
          { Length of a whole 1-D static-array FIELD (`Length(rec.arr)`, or a bare
            `Length(arr)` reaching an implicit-Self field) — like the AN_IDENT case,
            a static array carries no runtime [data-8] header, so fold to the field's
            declared count. Without this the runtime -tkLength path read a nonexistent
            header and returned 0 (tforin25: a record enumerator's `FIndex < Length(FArr)`
            was `< 0`, so the for-in ran zero times). }
          node := AllocNode(AN_INT_LIT);
          ASTIVal[node] := UFldArrLen[lenFieldIdx]; ASTTk[node] := Ord(tyInteger);
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
        { {$Q+}: FPC checks Succ/Pred too — the desugar IS a +/- binop, so
          tag it like one (feature-overflow-checks-cross-and-intrinsics). }
        if TokQChecks[TokPos - 1] then ASTQChk[op] := True;
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
        { Tag it: `Assigned(fp)` must keep testing the POINTER even in Delphi
          mode, where the identical `fp <> nil` node calls fp instead. }
        ASTSLen[CurASTNode] := PAS_BINOP_ASSIGNED;
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

      { RolDWord/RorDWord/RolQWord/RorQWord(value, n): FPC System bit-rotate
        intrinsics (generics.hashes' xxHash mixers). Same soft-alias shape as
        UpCase: hidden __pxx helpers so no real proc of these names exists to
        shadow a user's own. }
      if (CaseEqual(name, 'RolDWord') or CaseEqual(name, 'RorDWord') or
          CaseEqual(name, 'RolQWord') or CaseEqual(name, 'RorQWord')) and
         (procIdx < 0) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        ParseExpr; node := CurASTNode;
        Expect(tkComma, ',');
        ParseExpr; op := CurASTNode;
        Expect(tkRParen, ')');
        helperPi := FindProc('__pxx' + name);
        if helperPi < 0 then Error(name + ': builtin helper unavailable (needs the builtin unit; not on ESP)');
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := node;
        left := AllocNode(AN_ARG); ASTLeft[left] := op; ASTRight[argSeq] := left;
        CurASTNode := AllocNode(AN_CALL); ASTIVal[CurASTNode] := helperPi;
        ASTLeft[CurASTNode] := argSeq;
        ASTTk[CurASTNode] := Ord(Procs[helperPi].RetType);
        LastExprTk := Procs[helperPi].RetType;
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
      { …and in NilPy USER code the intrinsic also wins over a routine of the
        same name that came from a PASCAL RTL UNIT. `abs` is a Python builtin
        there, and what a pulled unit happens to declare must not change what it
        means: `import math` links lib/rtl/math, whose Abs(Integer) is declared
        first, and the whole block below was skipped because `abs` now RESOLVED
        — so `abs(-0.0)` answered -0.0 (math's Abs is `if x < 0 then -x`, and
        -0.0 < 0 is False) and `abs([-0.0][0])` answered 6626872, a variant read
        as an integer. Own language first, and it overrules import order:
        the same rule that says a Python name means the Python thing.

        A NilPy `def abs(x)` of the user's OWN still shadows — that proc is
        declared in the user's unit (or the main program, unit index -1), which
        is exactly what the unit test excludes. Pascal parsing is untouched:
        NilPyUserCode is false there, so the gate stays `procIdx < 0`.
        bug-nilpy-uses-math-breaks-abs-on-a-float }
      if (CaseEqual(name, 'Abs') or CaseEqual(name, 'Sqr')) and
         ((procIdx < 0) or
          (NilPyUserCode and (procIdx < ProcCount) and
           (ProcUnitIdx[procIdx] <> CurrentUnitIdx) and
           (ProcUnitIdx[procIdx] >= 0))) and
         (Tokens[TokPos].Kind = tkLParen) then
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

      { divmod(a, b) -> (a // b, a % b), both already correct on negative
        operands via pyfloordiv_v/pyfloormod_v.
        feature-nilpy-power-operator-and-divmod }
      if NilPyUserCode and CaseEqual(name, 'divmod') and (procIdx < 0) and
         (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        ParseExpr; node := CurASTNode;
        Expect(tkComma, ',');
        ParseExpr; left := CurASTNode;
        Expect(tkRParen, ')');
        helperPi := FindProc('pydivmod_v');
        if helperPi < 0 then Error('Nil Python: pylib (pydivmod_v) not loaded');
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := node;
        argSeq2 := AllocNode(AN_ARG); ASTLeft[argSeq2] := left; ASTRight[argSeq2] := -1;
        ASTRight[argSeq] := argSeq2;
        CurASTNode := AllocNode(AN_CALL);
        ASTIVal[CurASTNode] := helperPi;
        ASTLeft[CurASTNode] := argSeq;
        ASTTk[CurASTNode] := Ord(Procs[helperPi].RetType);
        ASTRight[CurASTNode] := ProcRetRecId[helperPi];
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
      if CaseEqual(name, 'Copy') and ((qUnit = -2) or (procIdx < 0)) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        ParseExpr; exprNode := CurASTNode;            { source array }
        { The index is OPTIONAL: `Copy(a)` is FPC's whole-array shorthand for a
          dynamic array, and it is the escape hatch users need once assignment
          aliases, so it is the natural way to duplicate an array
          (bug-p-copy-single-argument-form-missing-for-dynamic-arrays). Parsed
          permissively here and rejected below for a non-array, because the
          string-vs-dynarray decision needs the first argument's TYPE and that is
          not known until it has been parsed. }
        node := -1; addrNode := -1;
        if Eat(tkComma) then
        begin
          ParseExpr; node := CurASTNode;              { index }
          if Eat(tkComma) then begin ParseExpr; addrNode := CurASTNode; end;  { count }
        end;
        Expect(tkRParen, ')');
        { ANY dyn-array-typed expression, not just a bare name: `Copy(g[0])` and
          `Copy(r.items)` are what a per-level deep copy is spelled with, and FPC
          accepts both. }
        if CopySrcDynDepth(exprNode) >= 1 then
        begin
          { NESTED source: the raw byte copy in AN_DYN_COPY would move SUB-ARRAY
            HANDLES with the base element's size — TypeSize of the deepest type, 4
            for `array of array of Integer` — so element 1 onward read a bogus
            handle and `h[1][1]` segfaulted. Refused loudly here, exactly as
            dynamic-array Delete and Insert already refuse the same shape, until
            AN_DYN_COPY learns the handle stride AND the element-aware retain a
            nested copy needs (feature-dynarray-copy-nested-element-type).
            Reproduced on pinned, so it is not a regression — just a crash nobody
            had asked for yet. }
          if CopySrcDynDepth(exprNode) > 1 then
            Error('Copy: nested element type not yet supported for dynamic-array Copy');
          if (ASTKind[exprNode] = AN_IDENT) and (ASTIVal[exprNode] >= 0) and
             (SymElemDynDepth[ASTIVal[exprNode]] > 0) then
            Error('Copy: nested element type not yet supported for dynamic-array Copy');
          if node = -1 then
          begin
            node := AllocNode(AN_INT_LIT);
            ASTIVal[node] := 0; ASTTk[node] := Ord(tyInteger);
          end;
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
        { One argument and NOT a dynamic array. FPC rejects `Copy(s)` on a string
          too — the shorthand is a dynamic-array feature only — so this is a
          match with the reference implementation, not a gap. Diagnosed by name
          rather than falling into the string path below, which would report a
          missing index as a type error. }
        if node = -1 then
          Error('Copy: the one-argument Copy(a) is the whole-array shorthand and ' +
                'needs a DYNAMIC ARRAY; on a string give the index and count ' +
                '(Copy(s, 1, n)), which is what FPC requires too');
        { A Char first argument (`Copy('a', 1, 1)`): FPC promotes char -> string,
          so materialise a 1-char string and route through the string-Copy path
          below — the same promotion `+` and String() already do. Without this a
          char fell through to the dynamic-array error (a loud rejection of valid
          Pascal). }
        if IntToTypeKind(ASTTk[exprNode]) = tyChar then
          exprNode := WrapCharToStringExpr(exprNode);
        { String first argument: bare `Copy(s, index[, count])` lowers to the
          __pxxStrCopy substring helper (builtin unit, pulled by the pre-scan), so
          string Copy needs no `uses sysutils`. 2-arg form -> count = rest (huge,
          clamped to the end by the helper). The lib `sysutils.Copy` keeps the
          explicit-uses overload path. }
        ci := FindProc('__pxxStrCopy');
        cpyPi := ci;
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
          { `Copy(s, 2, 3)[1]` -- the postfix chain, which this branch used to
            Exit straight past. A builtin's branch returns an ordinary AN_CALL,
            so it wants the SAME suffix walk a user call gets; without the call
            the trailing `[` reached the statement parser as a stray token and
            reported `unexpected token` pointing at the wrong place. This is why
            `Nm()[1]` and `Copy(s,2,3)[1]` disagreed despite both being a string
            indexed off a call. compat-pascal-index-a-function-call-result }
          if CurTok.Kind in [tkLBrack, tkCaret, tkDot] then
          begin
            ApplyCallResultPtrSuffix(argSeq, cpyPi);
            Exit;
          end;
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
      { `IsClassType` matches case-INSENSITIVELY, Pascal-style, and this branch
        reads `Name(x)` as a CLASS CAST. In NilPy that is wrong twice over:
        Python has no cast syntax, and its names are case-sensitive — so
        `class F` plus `def f(a, b)` made `f(1, 2)` parse as a cast of `F` and
        fail with "Expected: )" on the second argument, naming a call that is
        ordinary Python. The exact-case construction intercept above already
        claims a genuine `F(...)`, so under PyExprMode a name reaching here is
        by definition NOT that class and must fall through to the call path.

        Same family as bug-nilpy-calling-an-instance-named-like-its-class-runs-
        the-constructor and the TYPING half PyIsClassTypeExact fixed: one
        case-insensitive lookup per site, each found separately
        (bug-nilpy-a-lowercase-name-is-hijacked-by-a-case-matching-class). }
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
        if CurTok.Kind = tkDot then
        begin
          { VALUE typecast used directly with `.field` — `TRec(q).high` — is
            FPC's in-place reinterpret: the field lives at @q + offset. Build a
            rec-tagged deref of the OPERAND'S ADDRESS so the ordinary field
            path resolves offsets (mirrors `TRec(p)^.field`, which derefs the
            pointer VALUE instead). Previously the AN_FIELD sat straight on the
            PTR_CAST, ResolveNodeRec saw REC_NONE, and every field silently
            resolved at offset 0 (bug-pascal-record-cast-field-offset). }
          fieldNode := AllocNode(AN_ADDR);
          ASTLeft[fieldNode] := ASTLeft[node];
          ASTTk[fieldNode] := Ord(tyPointer);
          indexNode := AllocNode(AN_DEREF);
          ASTLeft[indexNode] := fieldNode;
          ASTIVal[indexNode] := baseRec;   { pointee rec for ResolveNodeRec }
          ASTTk[indexNode] := Ord(tyRecord);
          node := indexNode;
          tk := tyRecord;
        end;
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
            { A METHOD or a property is not a field, and the builder below can
              only make fields -- RecFieldType's miss returns the tyInteger
              default, so `PRec(q)^.o.F(2)` built an AN_FIELD on the object and
              evaluated to the OBJECT POINTER: it compiled, ran, and printed a
              number instead of calling F. Nothing crashed.
              (bug-pascal-record-cast-chain-drops-method-call.) Methods,
              properties and default properties on a record/class value are what
              ParseClassRecordSelectors resolves, so once the name is not a
              field, the rest of the chain is its job -- one resolver, not a
              second partial copy (devdocs/dev/normalise-dont-special-case.md). }
            if (recName >= REC_UCLASS_BASE) and
               (FindUField(recName - REC_UCLASS_BASE, GetTokenStr(TokPos)) < 0) then
            begin
              node := ParseClassRecordSelectors(node, recName, tk);
              recName := REC_NONE;
              Break;
            end;
            { ...and a metaclass-typed field is a RECEIVER, not something to walk
              into either: `PPVmt(Self)^.__ClassRef.GetHashList(...)`. A
              `class of T` field records REC_NONE (the class lives in
              UFldPtrElemRec), so RecFieldRecId answers REC_NONE, the not-a-field
              guard above cannot fire, and the builder below made an AN_FIELD of
              the METHOD name -- `PRec(q)^.cr.Get(3)` evaluated to the class
              reference. Same silent wrong value, one spelling further out.
              NodeMetaclassCi is the shared five-spelling predicate;
              ParseMetaclassMemberTail is the shared member parser. }
            mcCi := NodeMetaclassCi(node);
            if mcCi >= 0 then
            begin
              Next;
              if CurTok.Kind <> tkIdent then Error('expected member name after .');
              fieldName := GetTokenStr(TokPos - 1);
              fieldNode := ParseMetaclassMemberTail(node, mcCi, tk, recName, mcFin);
              if fieldNode < 0 then
                Error('unknown member on a class reference: ' + fieldName);
              node := fieldNode;
              if mcFin then Break;
              Continue;
            end;
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
        { ...and, only if that missed, a BUILT-IN pointer name: `PInteger(p)^`. Registered
          lazily, on first use, which is what keeps a source declaration winning -- FindTypeAlias
          ran first, so a real PInteger in the source or the RTL was already found. Registering
          these up front instead shadows the source (FindTypeAlias is first-wins) and silently
          re-types this compiler's own `PWord = ^NativeInt`. }
        if aliasIdx < 0 then aliasIdx := EnsureBuiltinPtrAlias(name);
        if aliasIdx >= 0 then
        begin
          Next; { consume alias type name }
          Expect(tkLParen, '(');
          ParseExpr;
          Expect(tkRParen, ')');
          if (AliasTk[aliasIdx] = Ord(tyAnsiString)) or
             (AliasTk[aliasIdx] = Ord(tyString)) then
          begin
            { STRING-typed alias cast — `tbtstring(' ')` (Pascal Script):
              a value-level no-op, NOT a pointer reinterpret. Keep the
              operand node and its own string kind; consumers coerce
              frozen<->managed as usual. Tagging it tyPointer made
              Pos(tbtstring(' '), s) miss every string overload. }
            LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
            Exit;
          end;
          if AliasTk[aliasIdx] = Ord(tyRecord) then
          begin
            { RECORD-typed alias cast. A METHOD-POINTER type is one of these: a
              `procedure of object` value is a 16-byte {Code, Data} record, and so is
              System.TMethod -- so `TRunMethod(m)` (fpcunit's RunBare, building a
              callable from a MethodAddress result) is a pure REINTERPRET of the same
              two words, not a pointer conversion.

              Records are carried BY ADDRESS in this IR, so the operand node is already
              exactly the right thing; it only needs retyping. Wrapping it in AN_PTR_CAST
              took the record's first word as if it were the value and produced a method
              pointer whose Code was garbage -- which called into nothing. }
            ASTTk[CurASTNode] := Ord(tyRecord);
            LastExprTk := tyRecord;
            LastTypeRecId := AliasElemRec[aliasIdx];
            Exit;
          end;
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
          { `TFooClass(expr).AnyCtor(args)` -- an inline metaclass CAST, then construct.

            Two things this used to get wrong, both the same shape as the metaclass-VAR path:
            it matched only a constructor literally spelled `create`, and it picked the
            overload with FindUMeth (first NAME match, argument count ignored). fpjson does
            `TJSONObjectClass(DefaultJSONInstanceTypes[jitObject]).Create(Data)` where Create
            is overloaded (parameterless, and `array of const`) -- so it picked the
            PARAMETERLESS one and then complained about the argument it did not want.

            The name is only consumed once it is known to BE a constructor, so a non-ctor
            member still falls through to the paths below. }
          if (IntToTypeKind(AliasElemTk[aliasIdx]) = tyClass) and
             (AliasElemRec[aliasIdx] >= REC_UCLASS_BASE) and
             (CurTok.Kind = tkDot) and (Tokens[TokPos].Kind = tkIdent) and
             (FindUMeth(AliasElemRec[aliasIdx] - REC_UCLASS_BASE, GetTokenStr(TokPos)) >= 0) and
             UMthIsCtor[FindUMeth(AliasElemRec[aliasIdx] - REC_UCLASS_BASE, GetTokenStr(TokPos))] then
          begin
            mcCtorCi := AliasElemRec[aliasIdx] - REC_UCLASS_BASE;
            mcCtorNm := GetTokenStr(TokPos);
            Next;   { consume '.'  -> CurTok is the ctor name, '(' at TokPos }
            i := FindUMethOverloadAhead(mcCtorCi, mcCtorNm, CountCallArgsAhead);
            if i < 0 then i := FindUMeth(mcCtorCi, mcCtorNm);
            if i >= 0 then
            begin
              EnforceMethVis(i, mcCtorNm);
              Next; { consume the constructor name }
              node := BuildMetaclassNew(node, mcCtorCi, i);
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
              { Not a field -> not this loop's job. See the twin note in the
                record-name cast above: the hand-rolled builder here can only
                make AN_FIELD, so a METHOD at the end of the chain silently
                evaluated to the receiver instead of being called
                (bug-pascal-record-cast-chain-drops-method-call). Hand the rest
                to the shared selector parser, which resolves methods,
                properties and default properties. }
              if (recName >= REC_UCLASS_BASE) and
                 (FindUField(recName - REC_UCLASS_BASE, GetTokenStr(TokPos)) < 0) then
              begin
                node := ParseClassRecordSelectors(node, recName, tk);
                recName := REC_NONE;
                Break;
              end;
              { ...and a metaclass-typed field is a RECEIVER, not something to walk
                into either: `PPVmt(Self)^.__ClassRef.GetHashList(...)`. A
                `class of T` field records REC_NONE (the class lives in
                UFldPtrElemRec), so RecFieldRecId answers REC_NONE, the not-a-field
                guard above cannot fire, and the builder below made an AN_FIELD of
                the METHOD name -- `PRec(q)^.cr.Get(3)` evaluated to the class
                reference. Same silent wrong value, one spelling further out.
                NodeMetaclassCi is the shared five-spelling predicate;
                ParseMetaclassMemberTail is the shared member parser. }
              mcCi := NodeMetaclassCi(node);
              if mcCi >= 0 then
              begin
                Next;
                if CurTok.Kind <> tkIdent then Error('expected member name after .');
                fieldName := GetTokenStr(TokPos - 1);
                fieldNode := ParseMetaclassMemberTail(node, mcCi, tk, recName, mcFin);
                if fieldNode < 0 then
                  Error('unknown member on a class reference: ' + fieldName);
                node := fieldNode;
                if mcFin then Break;
                Continue;
              end;
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
            { a promotable operand demotes before the pun — see
              PromoDemoteToInt64.

              NOT for `Pointer(n)`: TypeIsOrdinal INCLUDES tyPointer (the same
              trap IRLowerCallArg's promo arms document), and `Pointer(n)` on a
              promotable int is the deliberate spelling for its SLOT ADDRESS —
              it is how `PXXPromoToStr(Pointer(n))` reaches the runtime. Demoting
              it handed the runtime a value where it expects an address, which
              segfaulted. }
            if TypeIsOrdinal(castTk) and (castTk <> tyPointer) then
              CurASTNode := PromoDemoteToInt64(CurASTNode);
            { ...and on a promotable int that spelling IS `@n`, so make it one.
              Punning the operand worked for a LOCAL, whose rvalue already is
              its slot address, and CRASHED for a by-ref PARAMETER, whose cell
              holds the address instead — one spelling, two meanings, with a
              segfault on the side that a line earlier had worked. AN_ADDR is
              right for both: it resolves through the parameter cell exactly as
              `@n` does. }
            if (castTk = tyPointer) and
               TypeIsPromoInt(IntToTypeKind(ASTTk[CurASTNode])) then
            begin
              node := AllocNode(AN_ADDR);
              ASTLeft[node] := CurASTNode;
              ASTTk[node] := Ord(tyPointer);
              CurASTNode := node;
              LastExprTk := tyPointer;
              Exit;
            end;
            { A VARIANT operand converts rather than reinterpreting the record —
              the named-type spellings (`Int64(v)`, `Cardinal(v)`, `AnsiString(v)`,
              an enum cast) reach the cast here, and every one of them used to
              read the tag word. See VariantCastToTemp. `Pointer(v)` is excluded
              there and stays a reinterpret. }
            vcNode := VariantCastToTemp(CurASTNode, castTk);
            if vcNode >= 0 then
            begin
              CurASTNode := vcNode;
              LastExprTk := castTk;
              Exit;
            end;
            { `operator Explicit(a: TFoo): Integer` — a value cast of a
              record/class operand with a matching Explicit overload is the
              conversion CALL, not a reinterpret (toperator11's Integer(a)). }
            if ((IntToTypeKind(ASTTk[CurASTNode]) = tyRecord) or
                (IntToTypeKind(ASTTk[CurASTNode]) = tyClass)) then
            begin
              sci := FindOpOverload(OPK_EXPLICIT, ASTTk[CurASTNode], ResolveNodeRec(CurASTNode));
              if (sci >= 0) and (Procs[sci].RetType = castTk) then
              begin
                argSeq := AllocNode(AN_ARG);
                ASTLeft[argSeq] := CurASTNode;
                node := AllocNode(AN_CALL);
                ASTIVal[node] := sci;
                ASTTk[node] := Ord(castTk);
                ASTLeft[node] := argSeq;
                CurASTNode := node;
                LastExprTk := castTk;
                Exit;
              end;
            end;
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

      { `TRec.Create(...)` — an advanced-record CONSTRUCTOR, invoked on the TYPE.

        A record ctor has no heap and no VMT: it just fills a fresh receiver. So the call
        materialises a hidden temp of the record type, passes it as Self (by reference, like
        any record method), and the expression's VALUE is that temp — which is exactly the
        ASTLiftedVar shape (call emitted as a statement, node yields the var).

        Checked BEFORE the class path below: that one lowers to GetMem, which would
        heap-allocate a record and hand back a pointer where a value belongs. }
      if (idx < 0) and (procIdx < 0) and (IsRecordType(name) <> REC_NONE) and
         (CurTok.Kind = tkIdent) and (Tokens[TokPos].Kind = tkDot) and
         (Tokens[TokPos+1].Kind = tkIdent) and
         (FindUMeth(IsRecordType(name) - REC_UCLASS_BASE, GetTokenStr(TokPos+1)) >= 0) then
      begin
        rcCi := IsRecordType(name) - REC_UCLASS_BASE;
        rcMmi := FindUMeth(rcCi, GetTokenStr(TokPos+1));
        rcPi := UMthProc_[rcMmi];

        Next; { record type name }
        Next; { dot }
        Next; { method name }

        if (UClsHelperTk[rcCi] >= 0) or UMthIsStatic[rcMmi] then
        begin
          { A STATIC method through the type name — a TYPE HELPER's
            (TU32Helper.GetSignMask) or a plain record's
            (`TRec.MakeI(5)`, rtl-generics' TComparerService). No receiver
            exists: Self is a by-value dummy the static body may not read, and
            the call's type is the method's REAL return type.

            The discriminator is STATIC, not helper-ness. It was written as
            `UClsHelperTk >= 0` because a helper was the case in hand, so a
            plain record's static kept the record-FACTORY shape below: it
            allocated a temp receiver, typed the call tyRecord, and the
            expression read that untouched temp — `TRec.MakeI(5)` returned
            GARBAGE with no diagnostic, at every call site, for any return type.
            One test (`class function` in a record, called on the type) covers
            both arms now. }
          mcallNode := AllocNode(AN_CALL);
          ASTIVal[mcallNode] := rcPi;
          ASTTk[mcallNode] := Ord(Procs[rcPi].RetType);
          rcSelf := AllocNode(AN_INT_LIT);
          ASTIVal[rcSelf] := 0;
          ASTTk[rcSelf] := Ord(Procs[rcPi].Params[0].TypeKind);
        end
        else
        begin
          savedRecId := LastTypeRecId;
          LastTypeRecId := REC_UCLASS_BASE + rcCi;
          rcTmp := AllocVar('', tyRecord);          { the fresh receiver }
          LastTypeRecId := savedRecId;

          mcallNode := AllocNode(AN_CALL);
          ASTIVal[mcallNode] := rcPi;
          ASTTk[mcallNode] := Ord(tyRecord);
          ASTLiftedVar[mcallNode] := rcTmp;

          rcSelf := AllocNode(AN_IDENT);            { Self = the temp, passed by reference }
          ASTIVal[rcSelf] := rcTmp;
          ASTTk[rcSelf] := Ord(tyRecord);
        end;
        rcSelfArg := AllocNode(AN_ARG);
        ASTLeft[rcSelfArg] := rcSelf;
        ASTLeft[mcallNode] := rcSelfArg;
        mlastArg := rcSelfArg;

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

        if (UClsHelperTk[rcCi] >= 0) or UMthIsStatic[rcMmi] then
          LastExprTk := Procs[rcPi].RetType
        else
        begin
          LastTypeRecId := REC_UCLASS_BASE + rcCi;
          LastExprTk := tyRecord;
          { postfix chaining on the ctor result: TPt.Create(7,8).Sum — the
            lifted temp is an addressable record, so the ordinary selector
            machinery works on the call node (the known gap on
            feature-pascal-record-constructors). }
          if CurTok.Kind in [tkDot, tkLBrack] then
          begin
            castTk2 := tyRecord;
            mcallNode := ParseClassRecordSelectors(mcallNode, REC_UCLASS_BASE + rcCi, castTk2);
            LastExprTk := castTk2;
          end;
        end;
        CurASTNode := mcallNode;
        Exit;
      end;

      { `TOuter.TInner.Create` — a nested class constructed through its owner.
        One extra hop, taken before the fast path below so that path sees the
        shape it already knows; the resolved nested ci is carried past the flat
        lookup, which would otherwise bind whichever class of that bare name
        registered first. bug-a-duplicate-class-name-check-is-scope-blind }
      nestCtorCi := -1;
      if (idx < 0) and (procIdx < 0) and IsClassType(name) and
         (CurTok.Kind = tkIdent) and (TokPos + 1 < TokCount) and
         (Tokens[TokPos].Kind = tkDot) and (Tokens[TokPos+1].Kind = tkIdent) and
         (FindNestedType(FindUClass(name), GetTokenStr(TokPos+1)) >= 0) then
      begin
        { Walk the whole `. nested . nested ...` run, then require `Create` after
          it. This was a FIXED three-token lookahead, so exactly one level of
          nesting could be constructed and `tthree.tmid.tleaf.Create` reported
          "class method not found: Create". Scanning before consuming keeps the
          non-constructor spellings untouched: nothing is eaten unless the run
          really does end in Create.
          bug-p-a-nested-class-method-implementation-takes-only-one-qualifier }
        nestScanCi := FindUClass(name);
        nestScanPos := TokPos;          { at the '.' after the outermost name }
        nestDepth := 0;
        while (nestScanPos + 1 < TokCount) and (Tokens[nestScanPos].Kind = tkDot) and
              (Tokens[nestScanPos+1].Kind = tkIdent) and
              (FindNestedType(nestScanCi, GetTokenStr(nestScanPos+1)) >= 0) do
        begin
          nestScanCi := FindNestedType(nestScanCi, GetTokenStr(nestScanPos+1));
          Inc(nestDepth);
          nestScanPos := nestScanPos + 2;
        end;
        if (nestDepth > 0) and (nestScanPos + 1 < TokCount) and
           (Tokens[nestScanPos].Kind = tkDot) and (Tokens[nestScanPos+1].Kind = tkIdent) and
           ((GetTokenStr(nestScanPos+1) = 'Create') or (GetTokenStr(nestScanPos+1) = 'create')) then
        begin
          nestCtorCi := nestScanCi;
          for nestI := 1 to nestDepth do
          begin
            Next;   { the enclosing class name }
            Next;   { '.' — CurTok is now the next nested type name }
          end;
          name := GetTokenStr(TokPos - 1);
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
        { `sysutils.Exception.Create(..)` must construct SYSUTILS' class. The
          qualifier was already consumed into qUnit above, and until now it was
          only consumed — the class itself resolved by flat first match, so a
          qualified name silently built whichever unit's class registered
          first. That was invisible while at most one unit declared any given
          class name; it stopped being invisible when pylib and sysutils each
          got their own `Exception` (siblings under ExceptionBase). Falls back
          to the flat lookup when the qualified one finds nothing, so a
          qualifier that names a module rather than the declaring unit behaves
          as before. }
        ctorCi := -1;
        if nestCtorCi >= 0 then ctorCi := nestCtorCi;   { the nested hop above }
        if (ctorCi < 0) and (qUnit >= 0) then ctorCi := FindUClassInUnit(name, qUnit);
        if ctorCi < 0 then ctorCi := FindUClass(name);
        if PxxDbgEnabled('a.qual') then WriteLn('PXXDBG a.qual CTOR name=', name,
          ' qunit=', qUnit, ' inunit=', FindUClassInUnit(name, qUnit),
          ' flat=', FindUClass(name), ' -> ctorCi=', ctorCi);
        ctorArgN := 0;
        if CurTok.Kind = tkLParen then
        begin
          Next;
          while CurTok.Kind <> tkRParen do
          begin
            { an `array of const` / open-array LITERAL argument -- not a set }
            if (CurTok.Kind = tkLBrack) and ClassCtorWantsVarRecAt(ctorCi, ctorArgN) then
              CurASTNode := ParseVarRecLiteralAST
            else
              ParseExpr;
            Inc(ctorArgN);
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
          { Use the class ALREADY resolved above, do not resolve it a second
            time. `ctorCi` honours the unit qualifier; a fresh `FindUClass(name)`
            here is flat, so it silently answered the other unit's `Exception`
            and `idx` — which is what every consumer below uses (RecSize, the
            overload match, the emitted class) — disagreed with `ctorCi`. Two
            lookups for one question, and only one of them had the fix. }
          if ctorCi >= 0 then
            idx := REC_UCLASS_BASE + ctorCi;
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
          i := FindUCtorOverloadArgs(idx - REC_UCLASS_BASE, argsHead);
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
              { ONE builder for a declared default, shared with every other call
                path (DefaultArgValueNode). This site used to hand-roll a
                str/ordinal pair of its own, which meant it missed everything
                the shared builder had learned since: float and set defaults,
                the AnsiString-vs-frozen tagging, and — the one that smashed the
                stack — retagging a VARIANT parameter's ordinal as tyInteger so
                IRLowerCallArg BOXES it. Tagged tyVariant the boxing was skipped
                and the callee dereferenced the bare ordinal 0 as a 16-byte
                variant slot, corrupting the caller's frame far from the call
                (bug-p-constructor-with-a-defaulted-variant-param-corrupts-memory). }
              exprNode := DefaultArgValueNode(mpi, mlastArg + 1);
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

        { A SELECTOR on the fresh instance — `TThing.Create(2).n`,
          `TList.Create.Count`. Without this the chain was simply DROPPED: the
          IR went straight from the GetMem call to the store, so an Integer
          variable received the instance POINTER and the program printed
          garbage with no diagnostic at all
          (bug-p-member-off-a-constructor-result-yields-garbage). The identical
          shape on an ordinary function result — `Make(4).n` — was always
          correct, which is what said the machinery works and only this exit
          was missing it. Same call the TClass(expr) path makes.

          `idx` is ALREADY a full rec id here (REC_UCLASS_BASE + ci, assigned
          just above alongside the arity check) — not a bare class index,
          despite what ASTRight's "user-class id" comment reads like. Adding
          REC_UCLASS_BASE again lands on a different record and every member
          comes back "no such member". }
        castTk := tyClass;
        if CurTok.Kind in [tkDot, tkLBrack] then
        begin
          node := ParseClassRecordSelectors(node, idx, castTk);
          LastExprTk := castTk;
        end;

        CurASTNode := node;
        Exit;
      end;
      if (idx < 0) and (procIdx < 0) and IsClassType(name) and
         (Tokens[TokPos].Kind = tkDot) and (Tokens[TokPos+1].Kind = tkIdent) then
      begin
        { Same qualified resolution as the `.Create` fast path above: a bare
          FindUClass here is flat, so `sysutils.Exception.CreateFmt` picked
          whichever unit's `Exception` registered first. }
        ci := -1;
        if qUnit >= 0 then ci := FindUClassInUnit(name, qUnit);
        if ci < 0 then ci := FindUClass(name);
        if PxxDbgEnabled('a.qual') then WriteLn('PXXDBG a.qual STATICM name=', name,
          ' mem=', GetTokenStr(TokPos+1), ' qunit=', qUnit, ' flat=', FindUClass(name),
          ' -> ci=', ci);
        mmi := FindUMeth(ci, GetTokenStr(TokPos+1));
        if (mmi >= 0) and (qUnit >= 0) and UMthIsCtor[mmi] and
           (not UMthIsStatic[mmi]) then
        begin
          { A QUALIFIED, NAMED constructor: `sysutils.Exception.CreateFmt(..)`.
            The fast path above matches only the exact spelling `Create`, and
            everything else fell through to ParseLValueAST's class-member arm,
            which resolves the class flat and never sees a qualifier — so the
            wrong unit's constructor ran and `CreateFmt('[%5d]',[3])` came out
            `[%5d]` instead of `[    3]`.

            Construction itself is NOT reimplemented here: this hands off to
            BuildMetaclassNew, the same builder the unqualified arm uses, so the
            two shapes differ only in how the class is looked up. Gated on
            qUnit >= 0 deliberately — with no qualifier there is nothing this
            path knows that the existing one does not. }
          mcCtorNm := GetTokenStr(TokPos+1);
          Next;                        { consume class name }
          Expect(tkDot, '.');          { CurTok is now the ctor name }
          i := FindUMethOverloadAhead(ci, mcCtorNm, CountCallArgsAhead);
          if i < 0 then i := FindUMeth(ci, mcCtorNm);
          if i >= 0 then
          begin
            EnforceMethVis(i, mcCtorNm);
            Next;                      { consume ctor name }
            mselfArg := AllocNode(AN_CLASSREF);
            ASTIVal[mselfArg] := ci;
            ASTTk[mselfArg] := Ord(tyPointer);
            CurASTNode := BuildMetaclassNew(mselfArg, ci, i);
            LastExprTk := tyClass;
            Exit;
          end;
        end;
        if mmi >= 0 then
        begin
          if UMthIsStatic[mmi] then
          begin
            { `TClassName.ClassMethod(...)` in an EXPRESSION. Self is the class named,
              which is exactly what makes `TMyTest.Suite` see Self = TMyTest. }
            mpi := UMthProc_[mmi];
            Next; { consume class name }
            Expect(tkDot, '.');
            Next; { consume method name }
            mselfArg := AllocNode(AN_CLASSREF);
            ASTIVal[mselfArg] := ci;
            ASTTk[mselfArg] := Ord(tyPointer);
            GenVirtSlot := UMthVirSlot[mmi];
          mcallNode := GenMakeStaticMethodCall(mpi, mselfArg);
            LastExprTk := Procs[mpi].RetType;
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
      { Past every name-keyed intrinsic: nothing claimed the name, so restore the
        not-yet-bound NilPy def unbound above and let the ordinary call paths use
        it. See the comment at the unbind for why this is not left at -1. }
      if pyLateDefPi >= 0 then procIdx := pyLateDefPi;
      sci := FindStrConst(name);
      { A VARIABLE in scope beats an untyped string constant of the same name. The string
        constant table is not scoped -- a `const S = 'A string';` declared inside one method
        stays visible to every later one -- so without this test a later method's local
        `var S : TJSONString` was silently EXPANDED INTO THE CONSTANT'S TEXT. ParseFactor
        handed back an AN_STR_LIT, consumed the identifier, and left `.AsJSON` unconsumed;
        the caller then reported "expected ," at the dot, pointing at the selector rather
        than at the name it had just mis-resolved.

        Pascal scoping says the innermost declaration wins, and the local var IS innermost
        here. Same discipline the LineEnding fallback below already applies. Found in
        fcl-json's testjsondata.pp, which declares a method-local `const S` early on and a
        method-local `var S : TJSONString` later -- hence the decl-ORDER dependence.

        (The constant table not being SCOPED at all is a separate, larger defect --
        bug-pascal-string-const-not-scoped -- and this guard does not pretend to fix it.)

        …and NOT when the name was reached through an explicit qualifier. A
        written `unit.Name` asks for THAT unit's declaration by construction, so
        an unrelated same-named variable elsewhere has no business cancelling
        it — the same exemption `OwnFieldBeatsSym` already takes above. Without
        it, `mimic_string.digits` stopped resolving the moment the program
        declared anything called `digits`, and the diagnostic named `digits` —
        i.e. it accused the very line that was creating the variable, pointing
        away from the const it had just refused to see. In NilPy that is the
        ordinary spelling of a module import (`digits = string.digits`), which
        is how it reached the corpus as a wall.
        bug-n-assigning-to-a-name-that-collides-with-a-pascal-shim-attribute-fails }
      if (sci >= 0) and (qUnit = -1) and (FindSym(name) >= 0) then sci := -1;
      if (sci < 0) and CaseEqual(name, 'LineEnding') and
         ((qUnit <> -1) or (FindSym(name) < 0)) then
      begin
        { System.LineEnding as an ordinary expression (`s := s + LineEnding;`). Same
          FALLBACK discipline as the const-concat path: only when nothing else declares
          the name, so a source's own LineEnding still wins. Interned so it becomes an
          ordinary frozen string literal from here on. }
        sci := RegisterLineEndingConst;
      end;
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
        ASTIVal[node] := Syms[idx].ConstVal; ASTTk[node] := Ord(Syms[idx].TypeKind);
        { An enum MEMBER const folds to its ordinal here, which is where the enum
          identity would be lost — carry it on the literal (see ASTEnumId). }
        ASTEnumId[node] := SymEnumId[idx];
        CurASTNode := node; Next;
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
        { keyword-name-aware overload re-target — `html.escape(s, quote=False)`
          (bug-nilpy-keyword-arg-vs-overload-set): FindProc/FindProcInUnit above
          hands back whichever overload was declared first; a sibling in the
          same unit may be the one that actually declares the keyword used. }
        if isNilPy then procIdx := PyPromoteProcOverloadByKwAt(procIdx, 0, PyKwNamesTokPos);
        Expect(tkLParen, '(');
        argsHead := -1;
        lastArg := -1;
        nArgs := 0;
        { `dict(**src)` — before the star-forward branch below, because for
          `dict` a `**` is not a forwarded kwargs pack: its keys ARE the dict
          being built, so the spread merges rather than binding parameters.
          The keyword form is handled inside the loop; both go through the one
          builder. }
        if PyKwDictArgsHere(procIdx) or
           (isNilPy and PyKeywordsAreKeys(procIdx) and
            CaseEqual(Procs[procIdx].Name, 'dict') and (CurTok.Kind = tkRParen)) then
        begin
          { The empty `dict()` rides the same builder: it is the keyword form
            with no keywords, and pylib's `dict` has no zero-argument overload
            (`dict()` answered "no overload of dict matches these arguments"
            before this, on the pinned binary too). }
          argSeq := AllocNode(AN_ARG);
          ASTLeft[argSeq] := PyBuildKeywordDictHere;
          ASTIVal[argSeq] := 0;
          argsHead := argSeq;
          lastArg := argSeq;
          nArgs := 1;
        end
        { `f(*args, **kwargs)` FORWARDED into this callee's ordinary parameters:
          the argument count is a run-time fact, so it desugars to a dispatch on
          len(args) (PyStarForwardCall). Detected before the argument loop —
          which parses expressions, and `*x` is not one. }
        else if isNilPy and (CurTok.Kind = tkStar) and (ProcPyStarIdx[procIdx] < 0) and
                not PyStarIsIterableForm(name) then
        begin
          Next;                          { the '*' }
          { `f(**d)` with NO leading `*args`. `**` lexes as two tkStar, and only
            the TRAILING star pair below ever looked ahead for the second one —
            this leading position ate one star and handed `*d` to ParseArgExpr,
            which reported `expected expression` at the call. One concept, two
            sites, and only the second was told.

            Lowered to the `f(*[], **d)` spelling that ALREADY works rather than
            given a forwarding path of its own: PyStarForwardCall takes the dict
            and binds its keys onto named slots, preserving defaults for the
            absent ones. Building a second mechanism here would be the thing
            normalise-dont-special-case warns about — measured by frank2, who
            found the ticket's proposed keyword desugar already existed.
            bug-a-nilpy-leading-double-star-in-a-call-is-not-detected }
          if CurTok.Kind = tkStar then
          begin
            Next;                        { the second '*' }
            ParseArgExpr;
            fwdDict := CurASTNode;
            { an empty positional list — same idiom the *args collectors use }
            fwdList := PyMakeIdent(PyNewContainerTemp('TPyList', 'starkw'));
            Expect(tkRParen, ')');
            CurASTNode := PyStarForwardCall(procIdx, fwdList, fwdDict);
            LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
            Exit;
          end;
          ParseArgExpr;
          fwdList := CurASTNode;
          fwdDict := -1;
          if CurTok.Kind = tkComma then
          begin
            Next;
            if CurTok.Kind = tkStar then
            begin
              Next;
              if CurTok.Kind = tkStar then Next;   { `**` is two tkStar }
              ParseArgExpr;
              fwdDict := CurASTNode;
            end
            else
              Error('Nil Python: an argument after *unpacking is not supported yet');
          end;
          Expect(tkRParen, ')');
          CurASTNode := PyStarForwardCall(procIdx, fwdList, fwdDict);
          LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
          Exit;
        end;
        { `max(*xs)` / `min(*xs)` — for these two, and only these two, CPython's
          starred call means exactly the ITERABLE form the callee already takes,
          so the run-time arity dispatch is the wrong mechanism: it looked for a
          three-argument max and raised "forwarded call got 3 arguments,
          expected 2 to 2" at run time. One argument, and ordinary overload
          matching below picks max(TPyList).
          bug-nilpy-star-unpack-into-a-fixed-arity-builtin

          The equivalence `max(*xs)` == `max(xs)` holds only for TWO OR MORE
          starred elements, where comparing the elements is comparing the list.
          With exactly one it is `max(xs[0])` — over that element's CONTENTS —
          so `max(*[[4, 9, 2]])` is 9 and the bare rewrite answered `[4, 9, 2]`,
          a silent wrong value. The count is a run-time fact, so pystar_iterable
          picks between the two; for two or more it hands the list straight back
          and this is exactly the old lowering.
          bug-nilpy-max-and-min-of-a-starred-list-pick-the-wrong-overload }
        if isNilPy and (CurTok.Kind = tkStar) and PyStarIsIterableForm(name) and
           (TokPos < TokCount) and (Tokens[TokPos].Kind <> tkStar) then
        begin
          Next;                          { the '*' }
          ParseArgExpr;
          argSeq := AllocNode(AN_ARG);
          ASTLeft[argSeq] := PyStarIterableNode(PyZipStarOperand(CurASTNode));
          ASTIVal[argSeq] := 0;
          ASTRight[argSeq] := -1;
          argsHead := argSeq;
          lastArg := argSeq;
          nArgs := 1;
        end;
        { `f(1, *xs)` — a star that is not the FIRST argument, which the
          forwarding arm above is the only one that handles. Same helper the
          method-call sites use, so the two spellings of one construct agree. }
        if isNilPy and (ProcPyStarIdx[procIdx] < 0) and PyStarArgAhead then
          PyStarUnpackProcArgs(procIdx, argsHead, lastArg, nArgs);
        while CurTok.Kind <> tkRParen do
        begin
          { `dict(a=1, b=2)` / `dict(**e)` — in Python the keyword NAMES are dict
            KEYS, not parameter names, so this is not keyword binding at all:
            the run becomes the one dict argument `dict()` already takes.
            The whole run up to `)` is consumed here. }
          node := PyKwDictArgNode(procIdx);
          if node >= 0 then
          begin
            argSeq := AllocNode(AN_ARG);
            ASTLeft[argSeq] := node;
            ASTIVal[argSeq] := 0;
            if argsHead = -1 then argsHead := argSeq else ASTRight[lastArg] := argSeq;
            lastArg := argSeq;
            Inc(nArgs);
            Break;
          end;
          { `f(*xs)` where `f` itself COLLECTS. The forwarding arm above declines
            this by construction (it dispatches into a callee's fixed slots, of
            which a variadic has none), so it used to reach the expression parse
            and report "expected expression". A collecting callee wants the
            operand SPLICED into the packing instead — `extend` where a written
            argument `append`s — which PyPackStarArgs does with the marker set
            here. bug-nilpy-star-unpack-into-a-star-args-callee }
          if isNilPy and (CurTok.Kind = tkStar) and (ProcPyStarIdx[procIdx] >= 0) and
             (TokPos < TokCount) and (Tokens[TokPos].Kind <> tkStar) then
          begin
            Next;                        { the '*' }
            ParseArgExpr;
            argSeq := AllocNode(AN_ARG);
            ASTLeft[argSeq] := CurASTNode;
            ASTIVal[argSeq] := PY_ARG_SPLICE;
            if argsHead = -1 then argsHead := argSeq else ASTRight[lastArg] := argSeq;
            lastArg := argSeq;
            Inc(nArgs);
            if CurTok.Kind = tkComma then Next
            else if CurTok.Kind <> tkRParen then
              Error('expected comma or close parenthesis');
            Continue;
          end;
          { NilPy `key=expr`: consumes the name, yields paramIndex+1 (0 = positional) }
          kwIdx := PyKwArgIndex(procIdx, 0);
          if kwIdx > 0 then slotIdx := kwIdx - 1 else slotIdx := nArgs;
          if (CurTok.Kind = tkLBrack) and ParamIsVarRecArray(procIdx, slotIdx) then
            CurASTNode := ParseVarRecLiteralAST
          else if (CurTok.Kind = tkLBrack) and ParamIsOpenArrayScalar(procIdx, slotIdx) then
            CurASTNode := ParseArrayCtorAST(Procs[procIdx].Params[slotIdx].TypeKind,
              ProcParamElemRowLen[procIdx * MAX_PROC_PARAMS + slotIdx], ProcParamElemRowLo[procIdx * MAX_PROC_PARAMS + slotIdx])
          else if isNilPy and PyBareGenExprAhead then
            { a BARE generator expression as an argument — `sum(x*2 for x in xs)`.
              It must be diverted BEFORE the element expression is parsed, since
              that expression names the loop variable, which is not in scope
              until the `for`. The str-method argument path already did this for
              `"".join(...)`; ordinary calls did not, so every other consumer of
              a genexpr (sum, max, any, ...) failed on the loop variable. }
            CurASTNode := PyParseCompExprValue(False)
          else
          begin
            node := TryDelphiBareProcArg;
            if node >= 0 then CurASTNode := node else ParseArgExpr;
          end;
          SetLitCheckArg(CurASTNode, procIdx, slotIdx);
          argSeq := AllocNode(AN_ARG);
          ASTLeft[argSeq] := CurASTNode;
          ASTIVal[argSeq] := kwIdx;
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
        PyPackStarArgs(procIdx, argsHead, lastArg, nArgs, 0);
        PyBindKwArgs(procIdx, argsHead, lastArg, nArgs);

        { a builtin TYPE in a callback slot becomes the address of the routine
          that type performs — BEFORE the types below are read, since they are
          what picks the overload (bug-nilpy-a-builtin-type-as-a-key-callback-
          segfaults) }
        if isNilPy then PyFixCallableTypeArgs(name, argsHead, nArgs);
        currArg := argsHead;
        for i := 0 to nArgs - 1 do
        begin
          exprNode := ASTLeft[currArg];
          argTypes[i] := IntToTypeKind(ASTTk[exprNode]);
          { `@obj.Method` (AN_METHODREF) surfaces as tyPointer in a value context,
            but as a call argument it fills a method-pointer (`of object`, tyRecord)
            parameter — the IR lowering materialises its {Code,Data} pair for a
            tyRecord param. Report it as tyRecord so overload matching binds it to
            the method-pointer param, mirroring the assignment path
            (bug-pascal-methodref-arg-to-named-of-object-param-no-match). }
          if ASTKind[exprNode] = AN_METHODREF then argTypes[i] := tyRecord;
          currArg := ASTRight[currArg];
        end;

        procIdx := MatchCallDelphiProcAddr(name, qUnit, nArgs, argsHead, argTypes);
        { A user object implementing the iterator protocol, passed to a pylib
          routine that wants a container: drain it and retry ONCE, or fix the
          argument of a match that was made on class assignability rather than
          on meaning. See PyFixIterableArgs — one rule keyed on the PARAMETER,
          not a list of builtin names
          (bug-nilpy-builtins-over-a-user-iterable-answer-empty). }
        if isNilPy and (procIdx < 0) and PyFixIterableArgs(-1, argsHead, nArgs) then
        begin
          currArg := argsHead;
          for i := 0 to nArgs - 1 do
          begin
            argTypes[i] := IntToTypeKind(ASTTk[ASTLeft[currArg]]);
            currArg := ASTRight[currArg];
          end;
          procIdx := MatchCallDelphiProcAddr(name, qUnit, nArgs, argsHead, argTypes);
        end
        else if isNilPy and (procIdx >= 0) then
          PyFixIterableArgs(procIdx, argsHead, nArgs);
        if procIdx < 0 then
        begin
          { Generic dynamic-array Copy(arr[, index [, count]]) intrinsic. Only when
            no Copy function matches (so a string `sysutils.Copy` is never
            shadowed) and the first argument is a dynamic array. Lowered into a
            fresh element-type-aware `array of T` (AN_DYN_COPY). String Copy keeps
            the RTL path.

            nArgs = 1 — FPC's whole-array shorthand — is accepted here as well as
            at the bare-intrinsic site in ParseFactor, and BOTH are needed: which
            path a program takes depends on whether a `Copy` function is in scope
            at all, so fixing only one made `Copy(a)` compile without `uses
            sysutils` and fail with "no overload of Copy matches" with it. The two
            arms even failed with different messages, which is exactly how a
            double case stays half-broken
            (devdocs/dev/normalise-dont-special-case.md). }
          if CaseEqual(name, 'Copy') and (nArgs >= 1) and (nArgs <= 3) and
             (CopySrcDynDepth(ASTLeft[argsHead]) >= 1) then
          begin
            if CopySrcDynDepth(ASTLeft[argsHead]) > 1 then
              Error('Copy: nested element type not yet supported for dynamic-array Copy');
            if (ASTKind[ASTLeft[argsHead]] = AN_IDENT) and
               (ASTIVal[ASTLeft[argsHead]] >= 0) and
               (SymElemDynDepth[ASTIVal[ASTLeft[argsHead]]] > 0) then
              Error('Copy: nested element type not yet supported for dynamic-array Copy');
            node := AllocNode(AN_DYN_COPY);
            ASTLeft[node] := ASTLeft[argsHead];                 { source array }
            if nArgs >= 2 then
              exprNode := ASTLeft[ASTRight[argsHead]]           { index }
            else
            begin
              exprNode := AllocNode(AN_INT_LIT);
              ASTIVal[exprNode] := 0; ASTTk[exprNode] := Ord(tyInteger);
            end;
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
          procIdx := TryFillTrailingDefaults(name, qUnit, nArgs, argsHead, lastArg);
          if procIdx < 0 then
            Error('no overload of ' + name + ' matches these arguments' + OverloadReport);
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
                    (ASTKind[exprNode] = AN_DEREF) or IsVarArgLvalueCast(exprNode) or
                    (ASTKind[exprNode] = AN_METHODREF) or
                    (ASTKind[exprNode] = AN_VARREC_ARRAY) or (ASTKind[exprNode] = AN_ARRAY_CTOR)) then
            begin
              { A record param passed by-ref may bind a non-lvalue temporary (e.g.
                a function result) when it is `const` OR plain by-value (>8-byte
                records are passed by-ref only for ABI; the callee copies, so a
                hidden-local temp is sound). Only a genuine `var`/`out` record
                (explicitly declared by-ref) still needs a true lvalue for
                write-back. An array-constructor literal ([...]) is itself the
                open-array temp. `@obj.Method` is materialised into a method-pointer
                record temp at IR lowering, so it too is a valid non-lvalue record
                argument. }
              { A `const Variant` param likewise accepts a non-lvalue: the
                scalar is boxed into a hidden variant temp at IR lowering
                (IRLowerCallArg) and the temp's address is passed. }
              { A PROMO param is the same case as the by-value record above: it
                is by-ref for ABI only ({tag, payload} is 8 or 16 bytes and the
                rvalue IS the slot address), and IRLowerCallArg copies it into a
                hidden temp with PXXPromoCopy before the call — the callee always
                gets its own slot. So a non-lvalue is sound, and rejecting it
                made `f(g())` fail for a promo parameter while every other
                numeric parameter type accepts it.
                bug-a-promoint-parameter-rejects-literals-and-call-results }
              { A FIXED-ARRAY call result is the same case as the by-value /
                `const` record above, and was the one aggregate still refused:
                the callee already returns into a caller-owned scratch
                (IRBuildHiddenDest sizes it from ProcRetFixedArrBytes), so the
                argument HAS an address to pass and no write-back is expected.
                A genuine `var`/`out` array parameter still needs a real lvalue
                — FPC refuses a call result there too.
                bug-a-a-fixed-array-call-result-is-refused-as-a-const-byref-argument }
              if not (((IntToTypeKind(ASTTk[exprNode]) = tyRecord) and
                      (ProcParamIsConst[procIdx * MAX_PROC_PARAMS + i] or
                       not ProcParamExplicitByRef[procIdx * MAX_PROC_PARAMS + i])) or
                      ((ASTKind[exprNode] = AN_CALL) and (ASTIVal[exprNode] >= 0) and
                       (ProcRetFixedArrBytes[ASTIVal[exprNode]] > 0) and
                       (ProcParamIsConst[procIdx * MAX_PROC_PARAMS + i] or
                        not ProcParamExplicitByRef[procIdx * MAX_PROC_PARAMS + i])) or
                      TypeIsPromoInt(Procs[procIdx].Params[i].TypeKind) or
                      ((Procs[procIdx].Params[i].TypeKind = tyVariant) and
                       ProcParamIsConst[procIdx * MAX_PROC_PARAMS + i])) then
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

        ApplyCallResultPtrSuffix(node, procIdx);  { f(...)^ / ^.field / [i] }
        if isLiftedCall then
        begin
          CurASTNode := node;
          LastExprTk := tyPointer;
        end;
        Exit;
      end
      else if (idx < 0) and (procIdx >= 0) and Procs[procIdx].IsFunc and
              ((Procs[procIdx].ParamCount = 0) or
               ((Procs[procIdx].ParamCount > 0) and
                ProcParamHasDefault[procIdx * MAX_PROC_PARAMS + 0])) then
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
        { ...or ALL-DEFAULTED, which is paramless at the call site. The EXPRESSION
          arm of the same defect the statement path had (`a := F` alongside `P;`),
          found by testing the sibling rather than the ticket's own repro: the
          ticket reported statement position only, and fixing that one left
          `a := F` still reporting "undefined variable (F)". Defaults are trailing
          in Pascal, so parameter 0 having one means they all do.
          bug-p-parenless-call-to-an-all-defaulted-routine-is-an-undefined-variable. }
        if Procs[procIdx].ParamCount > 0 then
        begin
          argSeq := -1;
          FillDefaultArgs(procIdx, 0, node, argSeq);
        end;
        { …and record that the arguments are all compiler-filled, so Delphi
          mode's @-optional retry can tell this from a written `F(2)`. }
        ASTCallParenless[node] := True;
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
          mmi := FindUMethOverloadAhead(ci, name, CountCallArgsAhead);
          if mmi >= 0 then
          begin
            EnforceMethVis(mmi, name);
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
              { `d.update(**e)` reaches THIS loop (the plain class-method one,
                which has no keyword handling at all and met the `*` with
                "expected expression"), while `d.update(a=1)` reaches the
                arity-driven loop above — the same construct through two paths,
                so both ask the one builder. }
              if PyKwDictArgsHere(mpi) then
              begin
                argSeq := AllocNode(AN_ARG);
                ASTLeft[argSeq] := PyBuildKeywordDictHere;
                ASTIVal[argSeq] := 0;
                ASTRight[mlastArg] := argSeq;
                mlastArg := argSeq;
                Inc(i);
              end;
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

{ NilPy str-method suffix, applied to EVERY factor however ParseFactorCore
  returned. The postfix `.member` path inside the core catches ident and field
  bases (they run through ParseLValueAST); a string LITERAL and a CALL RESULT
  are not lvalues and arrive here with CurTok still on the '.'. Both routes
  share pyparser's PyParseStrMethod.

  Factor level is the ONLY correct level: a method binds tighter than `+`.
  Applying this after the additive layer made `"a" + "b".upper()` parse as
  `("a" + "b").upper()` and silently print AB where CPython prints aB. }
function ProcIsConstructor(pi: Integer): Boolean;
{ Does proc index pi belong to a method declared `constructor`? A constructor
  is registered with IsFunc=False — its declaration keyword is neither
  `function` nor `procedure` — so the no-result check below has to let it
  through: `v := TFoo.Create` is the ordinary way to build an object and IS a
  value. A `destructor` shares that IsFunc=False and is deliberately NOT
  exempted: `x := v.Destroy` is not a value in any dialect.

  A linear scan, deliberately: it only ever runs for a call whose proc is not a
  function, which is a constructor call or the bug being caught, never a hot
  path. UMthIsCtor is per-METHOD; the reverse map from a proc index does not
  exist and is not worth adding for this. }
var m: Integer;
begin
  ProcIsConstructor := False;
  for m := 0 to UMthCount - 1 do
    if UMthProc_[m] = pi then
    begin
      if UMthIsCtor[m] then ProcIsConstructor := True;
      Exit;
    end;
end;

procedure ParseFactor;
var smNameTok, smBase, sdTok, tpObjNode, tpBlobNode, tpCallNode: Integer;
    sdName: AnsiString;
    smName: AnsiString;      { the intercepted int-method name at this suffix }
    smTk, tpTk: TTypeKind;   { receiver kind for a suffix on a fresh construction }
    ppBase, ppExp, ppPi, ppArgSeq, ppArgSeq2: Integer;   { `**` power operator }
    enStart, enArg0, enArg1: Integer;   { enumerate(xs, start=N) }
    zipB, zipC, zipD: Integer;   { zip(a, b[, c[, d]]) — -1 for an absent stream }
    pySuffixTokPos: Integer;   { token cursor at the top of the suffix cluster }
begin
  { `type(x).__name__` -- the ONLY shape of Python's `type()` builtin this
    frontend accepts (not a general type-object value: no bare `type(x)`,
    no equality/printing of it). Lowered straight onto the existing FPC
    class-reference machinery a NilPy class instance already has: the same
    __pxxRttiOf + __pxxClassName pair `obj.ClassName` uses.
    feature-nilpy-aggregate-builtins }
  if PyExprMode and isNilPy and PyIsIdent('type') and (TokPos < TokCount) and
     (Tokens[TokPos].Kind = tkLParen) and (FindSym('type') < 0) and
     (not PyUserShadowsProc('type')) then
  begin
    Next; Expect(tkLParen, '(');
    ParseExpr;
    tpObjNode := CurASTNode;
    Expect(tkRParen, ')');
    if (CurTok.Kind <> tkDot) or (TokPos >= TokCount) or
       (Tokens[TokPos].Kind <> tkIdent) or
       (not CaseEqual(GetTokenStr(TokPos), '__name__')) then
    begin
      { Any OTHER shape — `type(x) == int`, `print(type(x))`, `type(x) is str`
        — is the type OBJECT, which exists now that builtin types are values:
        pytype_of_v answers a VT_BTYPE for a builtin value and the instance's
        VT_CLASSREF for a user object, so `type(a) == A` and `isinstance(a, A)`
        agree by construction. This used to be refused outright
        ("type(x) is only supported as type(x).__name__") because there was no
        representation for the answer.

        The `.__name__` form above keeps its own lowering rather than becoming
        `pytype_of_v(x).__name__`: it is a direct pylib call with no variant to
        box, it is the overwhelmingly common shape, and it is already pinned by
        tests. bug-n-a-type-name-is-not-a-first-class-value }
      tpCallNode := AllocNode(AN_ARG);
      ASTLeft[tpCallNode] := PyForceVariant(tpObjNode);
      tpBlobNode := AllocNode(AN_CALL);
      ASTIVal[tpBlobNode] := FindProc('pytype_of_v');
      if ASTIVal[tpBlobNode] < 0 then
        Error('Nil Python: pylib (pytype_of_v) not loaded');
      ASTTk[tpBlobNode] := Ord(tyVariant);
      ASTLeft[tpBlobNode] := tpCallNode;
      CurASTNode := tpBlobNode;
      LastExprTk := tyVariant;
      Exit;
    end;
    Next; Next;                { '.', '__name__' }
    { Answered by pylib at RUN time, not from the RTTI ClassName here. Reading
      ClassName reported the Pascal class backing a pylib container — `TPyList`
      for a list, `TPyDict` for a dict — a silently wrong string; and `tuple`
      and `list` share ONE class, so the honest answer needs FIsTuple and cannot
      come from a class name at all. Going through a variant also means scalars
      work (`type(1).__name__` is `int`), which the RTTI route had to refuse.
      bug-nilpy-type-name-reports-the-internal-pascal-class }
    tpCallNode := FindProc('pytype_name_v');
    if tpCallNode < 0 then
      Error('Nil Python: pylib (pytype_name_v) not loaded');
    tpBlobNode := AllocNode(AN_ARG);
    ASTLeft[tpBlobNode] := tpObjNode;
    ASTRight[tpBlobNode] := -1;
    tpTk := tyAnsiString;
    CurASTNode := AllocNode(AN_CALL);
    ASTIVal[CurASTNode] := tpCallNode;
    ASTLeft[CurASTNode] := tpBlobNode;
    ASTTk[CurASTNode] := Ord(tpTk);
    ASTRight[CurASTNode] := -1;
    LastExprTk := tpTk;
    Exit;
  end;
  { A `lambda` expression. Consumed and reduced to a placeholder None value:
    full lambda support is function-value synthesis (like nested defs), and the
    body would only run through exec()/native dispatch, which is stubbed
    (feature-lib-pyexec). So a lambda parses and yields None, keeping the file
    compiling; its body does not execute yet (feature-nilpy-lambda). }
  { `super().m(args)` as a VALUE — `return "B" + super().who()`. super() was
    recognised in STATEMENT position only, so an overridden method reached from
    inside an expression failed with "undefined variable (super)". The node is
    the same inherited call the statement path builds; only the position is new
    (bug-nilpy-super-and-unbound-parent-method-calls). }
  if PyExprMode and PyIsIdent('super') and (TokPos < TokCount) and
     (Tokens[TokPos].Kind = tkLParen) then
  begin
    Next; PySuperConsumeArgs;
    Expect(tkDot, '.');
    if CurTok.Kind <> tkIdent then Error('Nil Python: expected method after super().');
    sdName := CurTok.SVal;
    Next;
    Expect(tkLParen, '(');
    CurASTNode := PyMakeSuperCall(sdName);
    if CurASTNode < 0 then
      Error('Nil Python: super().' + sdName + ' — no such method on the parent class');
    LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
    Exit;
  end;
  if PyExprMode and PyIsIdent('lambda') then
  begin
    PyParseLambdaStub;
    Exit;
  end;
  { `int.from_bytes(...)` is an INTRINSIC, not a call on a value: `int` is a
    type name, so the ordinary factor path would try to resolve it as a
    variable and fail. Recognised before the core for that reason. }
  if PyExprMode and PyIsFromBytesAhead then
  begin
    Next; Next; Next;           { 'int', '.', 'from_bytes'; CurTok = '(' }
    CurASTNode := PyParseFromBytes;
    LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
  end
  else if PyExprMode and PyStdlibCallAhead(sdName, sdTok) then
    { `os.path.join(...)`, `sys.exit(...)` — mapped by name onto a pylib shim. }
    CurASTNode := PyParseStdlibCall(sdName, sdTok)
  else if PyExprMode and (CurTok.Kind = tkIdent) and (CurTok.SVal = 'str') and
          (TokPos + 1 < TokCount) and (Tokens[TokPos].Kind = tkDot) and
          (Tokens[TokPos + 1].Kind = tkIdent) and (FindSym('str') < 0) and
          not ((TokPos + 2 < TokCount) and (Tokens[TokPos + 2].Kind = tkLParen)) then
  begin
    { `str.lower` with no call after it — an UNBOUND METHOD as a value, which
      is what `sorted(xs, key=str.lower)` and `map(str.strip, xs)` are made of.
      The CALLED form (`str.maketrans(...)`) is the arm above; this one exists
      only for the value form, which the ordinary factor path cannot reach
      because `str` is a type name and not a variable. }
    CurASTNode := PyUnboundStrMethodValue;
    if CurASTNode < 0 then
      Error('Nil Python: str.' + GetTokenStr(TokPos + 1) + ' cannot be taken '
            + 'as a value — only the str methods that take no arguments can');
    LastExprTk := tyVariant;
  end
  else if PyExprMode and (PyIsIdent('min') or PyIsIdent('max')) and
          (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) and
          (FindSym(CurTok.SVal) < 0) and (CountCallArgsAhead >= 3) and
          (not PyAnyProcWithArity(CurTok.SVal, CountCallArgsAhead)) then
    { 3+ positional arguments that NO routine of that arity can serve: fold
      through the 2-arg overload. 1 and 2 args keep the ordinary call path,
      whose overload set (iterable, AnsiString, the scalar pairs) is what the
      fold itself relies on — as do pylib's hand-written 3/4-arg overloads and
      any `def min(x, y, z)` the program declares over the builtin. }
    CurASTNode := PyParseVariadicMinMax(CurTok.SVal)
  else if PyExprMode and PyIsIdent('range') and (TokPos < TokCount) and
          (Tokens[TokPos].Kind = tkLParen) and (FindSym('range') < 0) and
          (not PyUserShadowsProc('range')) then
    { `range(...)` as a VALUE — a TPyRange, lazy and re-iterable, in EVERY
      position. No gate: the old arm only fired inside a whitelist of callees
      that promised to merely iterate their argument, because there was no
      range value to produce and materialising elsewhere would have turned a
      loud compile error into a quiet `[0, 1, 2]` where CPython prints
      `range(0, 3)`. feature-nilpy-range-as-a-value

      The `for i in range(...)` HEADER is recognised earlier (PyParseFor) and
      keeps its counted-loop lowering — a range there is a loop bound, not a
      value, and lowering it as one would put an object where an induction
      variable belongs. }
    CurASTNode := PyParseRangeList
  else if PyExprMode and PyIsIdent('enumerate') and (TokPos < TokCount) and
          (Tokens[TokPos].Kind = tkLParen) and (FindSym('enumerate') < 0) and
          (not PyUserShadowsProc('enumerate')) then
  begin
    { `enumerate(xs)` / `enumerate(xs, N)` / `enumerate(xs, start=N)` as a
      VALUE — `for i, s in reversed(list(enumerate(t)))`. The for-HEADER form
      is recognised earlier and walks by index; here the pairs have to exist
      as a list, exactly as for zip. }
    Next; Expect(tkLParen, '(');
    ParseArgExpr;
    smBase := CurASTNode;
    enStart := -1;
    if Eat(tkComma) then
    begin
      if PyIsIdent('start') and (TokPos < TokCount) and
         (Tokens[TokPos].Kind = tkAssign) then
      begin
        Next; Next;   { 'start', '=' }
      end;
      ParseArgExpr;
      enStart := CurASTNode;
    end;
    Expect(tkRParen, ')');
    { LAZY, like map/filter: `enumerate(xs)` is a CURSOR. The str case needs no
      charlist explosion any more — PyMakeIterOf builds a str cursor directly,
      which is what closes the old "an AnsiString handle dereferenced as an
      object" hole (bug-nilpy-str-iterable-builtins-segfault-on-a-string-handle)
      without a second representation of the same idea. }
    smBase := PyMakeIterOf(smBase);
    smNameTok := FindProc('pyiter_enum_i');
    if smNameTok < 0 then Error('Nil Python: pylib (pyiter_enum_i) not loaded');
    if enStart < 0 then
    begin
      enStart := AllocNode(AN_INT_LIT);
      ASTIVal[enStart] := 0;
      ASTTk[enStart] := Ord(tyInt64);
    end;
    enArg0 := AllocNode(AN_ARG); ASTLeft[enArg0] := smBase;
    enArg1 := AllocNode(AN_ARG); ASTLeft[enArg1] := enStart; ASTRight[enArg1] := -1;
    ASTRight[enArg0] := enArg1;
    CurASTNode := AllocNode(AN_CALL);
    ASTIVal[CurASTNode] := smNameTok;
    ASTLeft[CurASTNode] := enArg0;
    ASTTk[CurASTNode] := Ord(tyClass);
    ASTRight[CurASTNode] := ProcRetRecId[smNameTok];
    LastExprTk := tyClass;
  end
  else if PyExprMode and PyIsIdent('zip') and (TokPos < TokCount) and
          (Tokens[TokPos].Kind = tkLParen) and
          (not PyUserShadowsProc('zip')) then
  begin
    { `zip(a, b)` as a VALUE — `list(zip(chords, chords[1:]))`. The for-header
      form is recognised earlier (PyParseForZip) and walks both containers by
      index; here the pairs have to exist as a list. }
    Next; Expect(tkLParen, '(');
    { `zip(*rows)` — the TRANSPOSE idiom, and the one zip whose stream count is
      a RUN-TIME fact. It cannot ride the fixed argument chain below, which is
      why it did not parse at all; the operand IS the list of iterables. }
    if isNilPy and (CurTok.Kind = tkStar) and (TokPos < TokCount) and
       (Tokens[TokPos].Kind <> tkStar) then
    begin
      Next;                                { the '*' }
      ParseArgExpr;
      CurASTNode := PyMakeZipN(PyZipStarOperand(CurASTNode));
      Expect(tkRParen, ')');
      LastExprTk := tyClass;
      Exit;
    end;
    ParseArgExpr;
    smBase := CurASTNode;
    Expect(tkComma, ',');
    ParseArgExpr;
    zipB := CurASTNode;
    { …and the THREE- and four-way forms, which used to fail at the second
      comma with `unexpected token`. Four is where it stops: past that the
      shape is a list of lists, and a fixed argument chain has to end
      somewhere — the diagnostic says so rather than silently dropping a
      stream. }
    zipC := -1; zipD := -1;
    if CurTok.Kind = tkComma then
    begin
      Next; ParseArgExpr; zipC := CurASTNode;
      if CurTok.Kind = tkComma then
      begin
        Next; ParseArgExpr; zipD := CurASTNode;
        { …and past four, where the fixed chain used to stop with "not
          supported yet — zip the first four and zip the result". The N-way
          entry takes a LIST, so the remaining streams are collected into one
          and the ceiling is gone rather than raised. }
        if CurTok.Kind = tkComma then
        begin
          CurASTNode := PyMakeZipN(PyZipTailList(smBase, zipB, zipC, zipD));
          Expect(tkRParen, ')');
          LastExprTk := tyClass;
          Exit;
        end;
      end;
    end;
    CurASTNode := PyMakeZip(smBase, zipB, zipC, zipD);
    Expect(tkRParen, ')');
    LastExprTk := tyClass;
  end
  else if PyExprMode and PyIsSetCompAhead then
    { A set comprehension, checked before the dict-literal path: a brace group
      with a `for` and no colon in it is not a dict. }
    CurASTNode := PyParseSetComp
  else if PyExprMode and PyIsParenCompAhead then
    { `(x for x in xs)` — a generator expression in its own parentheses. Checked
      before the tuple form, which would otherwise take the '(' and then fail on
      the `for`. }
    CurASTNode := PyParseParenComp
  else if PyExprMode and PyTupleParenAhead then
    { A parenthesised TUPLE as a value — `return (pfx, rest)`, `x = (a, b)`.
      Built as the same TPyList a `[...]` literal produces, which is what makes
      the existing tuple-unpack assignment consume it. A plain `(expr)` has no
      top-level comma and still parses as grouping. }
    PyParseListLiteralT(tkLParen, tkRParen, False)
  else if PyExprMode and PyIsSysStreamAhead then
  begin
    { `sys.stderr` is a VALUE (its fd), not a member access on a variable —
      `sys` is a deferred import and never becomes a symbol. }
    CurASTNode := PyParseSysStream;
    LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
  end
  else
    ParseFactorCore;
  { --- the Python SUFFIX cluster -------------------------------------------
    Nine loops follow, each claiming one (suffix token, receiver shape) pair:
    `.method()` on a str base, on a call result, on a class expression, on a
    variant; `[i]`; a dynamic CALL through a variant; the `__call__` protocol.
    They are written as a SEQUENCE, so without this outer loop each one gets
    exactly one turn and a suffix is only reachable in the ORDER the loops
    happen to appear. `g(3).show()` needs the dynamic-call loop (last) and then
    the call-result method loop (third) — backwards through the sequence — so it
    was a parse error, while `o = g(3); o.show()` worked
    (bug-nilpy-a-method-call-on-a-callable-values-result-is-refused).

    Python's grammar has no such ordering: a primary takes `.attr`, `[i]` and
    `(args)` suffixes in ANY sequence, any number of times. So the cluster
    re-runs until a pass consumes nothing, which makes it order-independent
    without touching the nine loops individually. The right shape is ONE
    dispatcher over the suffix tokens rather than nine loops — nine mechanisms
    for one concept is well past the two-is-a-smell line — but that is a rewrite
    of a hot region, and this makes the composition correct meanwhile.

    Termination is on TOKEN PROGRESS, not on the node changing: a loop that
    rewrites the node without consuming input would otherwise spin forever. }
  repeat
    pySuffixTokPos := TokPos;
  { `<int>.to_bytes(n, "little", signed=s)` / `<int>.bit_length()`, the other
    half of the pair. }
  while PyExprMode and (CurTok.Kind = tkDot) and (TokPos + 1 < TokCount) and
        (Tokens[TokPos].Kind = tkIdent) and
        PyIsIntMethodName(LowerCase(GetTokenStr(TokPos))) and
        (Tokens[TokPos + 1].Kind = tkLParen) and
        PyIsIntMethodBaseTk(IntToTypeKind(ASTTk[CurASTNode]),
                            LowerCase(GetTokenStr(TokPos))) do
  begin
    smBase := CurASTNode;
    smName := LowerCase(GetTokenStr(TokPos));
    Next; Next;                 { '.' and the name; CurTok = '(' }
    CurASTNode := PyParseIntMethod(smBase, smName);
    LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
  end;
  { the float half of the same pair — see PyIsFloatMethodName }
  while PyExprMode and (CurTok.Kind = tkDot) and (TokPos + 1 < TokCount) and
        (Tokens[TokPos].Kind = tkIdent) and
        PyIsFloatMethodName(LowerCase(GetTokenStr(TokPos))) and
        (Tokens[TokPos + 1].Kind = tkLParen) and
        PyIsFloatMethodBaseTk(IntToTypeKind(ASTTk[CurASTNode]),
                              LowerCase(GetTokenStr(TokPos))) do
  begin
    smBase := CurASTNode;
    smName := LowerCase(GetTokenStr(TokPos));
    Next; Next;                 { '.' and the name; CurTok = '(' }
    CurASTNode := PyParseFloatMethod(smBase, smName,
                     PyIsIntBaseTk(IntToTypeKind(ASTTk[smBase])));
    LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
  end;
  while PyExprMode and (CurTok.Kind = tkDot) and (TokPos + 1 < TokCount) and
        (Tokens[TokPos].Kind = tkIdent) and
        (Tokens[TokPos + 1].Kind = tkLParen) and
        PyIsStrBaseTk(IntToTypeKind(ASTTk[CurASTNode])) do
  begin
    Next;                       { consume '.'; CurTok = the method name }
    smNameTok := TokPos - 1;
    Next;                       { consume the name; CurTok = '(' }
    CurASTNode := PyParseStrMethod(CurASTNode, GetTokenStr(smNameTok));
    LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
  end;
  { A method on a CALL RESULT whose declared type is a scalar — `get(a, b,
    c).split("x")`. An unannotated def's result is inferred, and an expression
    the inferrer cannot type comes back tyInteger while the VALUE at run time
    is whatever Python made it (the same call prints its string correctly).
    The string loop above needs a string-typed base, so this shape did not
    parse at all. Routed to runtime dispatch, which is what decides a variant's
    method everywhere else; a receiver that really is a number still fails
    there, by name. Restricted to a CALL base so nothing else changes.

    AN_TERNARY is admitted for the SECOND link of such a chain: the
    runtime-dispatched method this loop builds comes back as a ternary (the
    `pyvar_is_strtag(recv) ? str-method : class-method` fan PyParseVariantMethod
    assembles), not as an AN_CALL, so `open(p).read().strip().upper()` had a
    receiver no loop in this cluster claimed and reported `unexpected token` at
    the second name — while `.strip()` alone parsed. Latent until a name was
    declared by BOTH a class and the str table (which is program-dependent: it
    fires the moment any class in the program declares `strip`/`upper`), so
    adding the Python method set to TPyBytes made it universal. A user's own
    `(a if c else b).upper()` lands here too, which is the same rule Python
    has — a primary takes a suffix whatever produced it.
    bug-nilpy-a-chained-method-on-a-runtime-dispatched-result-is-refused }
  while PyExprMode and (CurTok.Kind = tkDot) and (TokPos + 1 < TokCount) and
        (Tokens[TokPos].Kind = tkIdent) and
        (Tokens[TokPos + 1].Kind = tkLParen) and
        ((ASTKind[CurASTNode] = AN_CALL) or
         (ASTKind[CurASTNode] = AN_TERNARY)) and
        not (IntToTypeKind(ASTTk[CurASTNode]) in [tyClass, tyRecord]) do
  begin
    Next;                       { consume '.'; CurTok = the method name }
    smNameTok := TokPos - 1;
    Next;                       { consume the name; CurTok = '(' }
    CurASTNode := PyParseVariantMethod(CurASTNode, GetTokenStr(smNameTok));
    LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
  end;
  { A METHOD call on a class-typed expression that is not an ident — a fresh
    construction, `Cls().m()`. ParseFactorCore does this for an ident receiver
    and the ctor intercept exits before it, so the call was a parse error
    (bug-nilpy-method-call-on-fresh-construction). Looped, so chains compose. }
  while PyExprMode and (CurTok.Kind = tkDot) and (TokPos + 1 < TokCount) and
        (Tokens[TokPos].Kind = tkIdent) and
        (Tokens[TokPos + 1].Kind = tkLParen) and
        (IntToTypeKind(ASTTk[CurASTNode]) = tyClass) and
        (ResolveNodeRec(CurASTNode) >= REC_UCLASS_BASE) do
  begin
    smBase := CurASTNode;
    Next;                       { consume '.'; CurTok = the method name }
    smNameTok := TokPos - 1;
    Next;                       { consume the name; CurTok = '(' }
    CurASTNode := PyParseClassMethodCall(smBase,
                    ResolveNodeRec(smBase) - REC_UCLASS_BASE, GetTokenStr(smNameTok));
    LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
  end;
  { …and a PROPERTY or FIELD read on that fresh construction, which carries no
    parentheses: `Path(self.file_path).name`. The loop above needs a '(' after
    the member, so the no-argument form — the one pathlib's name/stem/suffix
    are written with — still had nowhere to go and reported "expected newline
    after statement". Read through the ordinary class-selector machinery, the
    same as for an ident receiver. }
  while PyExprMode and (CurTok.Kind = tkDot) and (TokPos + 1 < TokCount) and
        (Tokens[TokPos].Kind = tkIdent) and
        (Tokens[TokPos + 1].Kind <> tkLParen) and
        (IntToTypeKind(ASTTk[CurASTNode]) = tyClass) and
        (ResolveNodeRec(CurASTNode) >= REC_UCLASS_BASE) do
  begin
    smBase := CurASTNode;
    smTk := IntToTypeKind(ASTTk[smBase]);
    CurASTNode := ParseClassRecordSelectors(smBase, ResolveNodeRec(smBase), smTk);
    LastExprTk := smTk;
  end;
  { …and a bare ATTRIBUTE on a receiver the frontend cannot type as a class:
    `mk(3).v`, `g(3).v` — a call RESULT, where there is no symbol to key on. The
    class-selector loop just above needs a statically known class; the method
    loops all need a '(' after the name. So a bare attribute on a call result
    was claimed by nobody and reported `unexpected token`, while
    `o = mk(3); o.v` worked — the same asymmetry the '.method()' and '[i]'
    halves of this family already had.

    Routed to the dynamic attribute read, which is what an unknown receiver
    gets everywhere else. That was only half a fix until pylib's getter learned
    to fall back to the class's DECLARED fields (PyDeclaredAttrGet): before
    that it consulted the setattr side-store alone and answered a false
    AttributeError for a field that plainly exists, which is why this ticket
    was filed rather than the parse gap papered over.
    bug-nilpy-a-bare-attribute-on-a-call-result-is-refused

    AN_TERNARY for the same reason as the '.method()' loop above — a
    runtime-dispatched result is a ternary, so `x.split(",").foo` needs it too. }
  while PyExprMode and (CurTok.Kind = tkDot) and (TokPos + 1 < TokCount) and
        (Tokens[TokPos].Kind = tkIdent) and
        (Tokens[TokPos + 1].Kind <> tkLParen) and
        ((ASTKind[CurASTNode] = AN_CALL) or
         (ASTKind[CurASTNode] = AN_TERNARY)) and
        not (IntToTypeKind(ASTTk[CurASTNode]) in [tyClass, tyRecord]) do
  begin
    smBase := CurASTNode;
    Next;                       { consume '.'; CurTok = the attribute name }
    smNameTok := TokPos - 1;
    Next;                       { consume the name }
    CurASTNode := PyMakeDynAttrGet(smBase, GetTokenStr(smNameTok));
    LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
  end;
  { Same asymmetry for the SUBSCRIPT suffix: `s[i]` on an ident goes through
    ParseLValueAST, but a string literal and a call RESULT are not lvalues, so
    `"abc"[1]` and `"a b".split(" ")[1]` never consumed the '[' and were parse
    errors (bug-nilpy-subscript-on-literal). Reaching here at all means nobody
    else claimed the bracket. Looped, and with the str-method suffix re-applied
    inside, so `"abc"[1].upper()` and longer chains keep composing. }
  while PyExprMode and (CurTok.Kind = tkLBrack) and
        (PySubscriptableSuffix(CurASTNode) or PyIsSliceBase(CurASTNode)) do
  begin
    smBase := CurASTNode;
    Next;                       { consume '[' }
    { A SLICE is a subscript whose index is followed by ':' — and `b[:n]` has
      no low bound at all, so the colon can also be the very first token. }
    if CurTok.Kind = tkColon then
      CurASTNode := PyParseSliceTail(smBase, -1)
    else
    begin
      PyParseBoolExpr;
      if CurTok.Kind = tkColon then
        CurASTNode := PyParseSliceTail(smBase, CurASTNode)
      else
      begin
        Expect(tkRBrack, ']');
        CurASTNode := PyMakeSuffixIndex(smBase, CurASTNode);
      end;
    end;
    LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
    while PyExprMode and (CurTok.Kind = tkDot) and (TokPos + 1 < TokCount) and
          (Tokens[TokPos].Kind = tkIdent) and
          (Tokens[TokPos + 1].Kind = tkLParen) and
          PyIsStrBaseTk(IntToTypeKind(ASTTk[CurASTNode])) do
    begin
      Next;
      smNameTok := TokPos - 1;
      Next;
      CurASTNode := PyParseStrMethod(CurASTNode, GetTokenStr(smNameTok));
      LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
    end;
    { A subscript of a CONTAINER yields a VARIANT, not a str — a list holds
      variants — so the str-method loop above never fired for `make()[0].upper()`
      and the '.' was left for whoever came next: "unexpected token". Routed to
      the runtime-dispatching variant method path, which is what an ident
      receiver of the same shape already gets. }
    while PyExprMode and (CurTok.Kind = tkDot) and (TokPos + 1 < TokCount) and
          (Tokens[TokPos].Kind = tkIdent) and
          (Tokens[TokPos + 1].Kind = tkLParen) and
          (IntToTypeKind(ASTTk[CurASTNode]) = tyVariant) do
    begin
      Next;
      smNameTok := TokPos - 1;
      Next;
      CurASTNode := PyParseVariantMethod(CurASTNode, GetTokenStr(smNameTok));
      LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
    end;
  end;
  { A value followed by '(' is a DYNAMIC call through whatever it holds —
    `ns["__body__"]()`, the function exec() built. Nothing else claimed the '(',
    so a call is the only reading: Python has no juxtaposition operator, so
    there is no other thing `x(y)` can mean. Looped so a returned callable can
    be called again.

    The test USED to be `= tyVariant`, and a non-variant factor therefore fell
    out of the loop leaving the '(' for nobody — the argument list was SILENTLY
    DISCARDED and the expression evaluated to the callee. `x = (add)(4, 5)`
    answered a raw code address instead of 9 and `(3 + 4)(1)` answered 7, while
    the identical call through a variant-typed name worked
    (bug-nilpy-a-parenthesised-callee-drops-its-arguments). Silently dropping
    half an expression is the worst available reading of a '(' — even "not
    callable" is better, because it is CPython's answer and it is loud.

    Widening is only SAFE now: pyvar_callv<n> takes `const cb: Variant`, so the
    ordinary argument coercion boxes a non-variant callee, and until callables
    had their own variant tag a boxed code address was indistinguishable from a
    boxed integer — this loop would have started routing `(3 + 4)(1)` to an
    indirect jump to address 7 rather than to a TypeError. With VT_CALLABLE the
    guard tells them apart, so a real callable dispatches and everything else
    raises (feature-nilpy-a-callable-value-needs-its-own-variant-tag).

    A user-class INSTANCE is excluded because the loop below claims it: that is
    the `__call__` protocol, which needs the receiver, not a boxed handle. A
    pylib CONTAINER (tyClass, but below REC_UCLASS_BASE) is NOT excluded — it
    belongs here, where `(1, 2)(3)` becomes CPython's TypeError. }
  while PyExprMode and (CurTok.Kind = tkLParen) and (CurASTNode >= 0) and
        not ((IntToTypeKind(ASTTk[CurASTNode]) = tyClass) and
             (ResolveNodeRec(CurASTNode) >= REC_UCLASS_BASE)) do
  begin
    CurASTNode := PyMakeDynCall(CurASTNode);
    LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
  end;
  { A CLASS INSTANCE followed by '(' -- Python's callable-object protocol,
    `a(10)` where `a`'s class defines `__call__`. Loops so a `__call__`
    that itself returns another callable instance composes.
    feature-nilpy-dunder-call-protocol }
  while PyExprMode and (CurTok.Kind = tkLParen) and
        (IntToTypeKind(ASTTk[CurASTNode]) = tyClass) and
        (ResolveNodeRec(CurASTNode) >= REC_UCLASS_BASE) do
  begin
    CurASTNode := PyMakeCallDunder(CurASTNode);
    LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
  end;
  until (not PyExprMode) or (TokPos = pySuffixTokPos);
  { --- end of the suffix cluster ------------------------------------------- }
  { `**` -- Python's power operator: right-associative, and binding TIGHTER
    than unary minus (`-2 ** 2` is `-(2**2)` = -4, not `(-2)**2`). Recognized
    here, at the very end of ParseFactor, rather than in ParseTerm alongside
    `*`/`/`: a unary-minus operand recurses into THIS SAME ParseFactor (see
    ParseFactorCore's tkMinus case), so checking for `**` here means the
    unary minus wraps the WHOLE power expression, and the exponent's own
    recursive ParseFactor call gives right-associativity
    (`2**3**2` = `2**(3**2)` = 512) for free -- no separate precedence
    plumbing needed. Lexed as two adjacent tkStar tokens; the NilPy lexer has
    no dedicated `**` token (the same shape `**kwargs` already relies on, in
    the unrelated parameter-list grammar).
    feature-nilpy-power-operator-and-divmod }
  if PyExprMode and (CurTok.Kind = tkStar) and (TokPos < TokCount) and
     (Tokens[TokPos].Kind = tkStar) then
  begin
    Next; Next;                { the two '*' tokens }
    ppBase := CurASTNode;
    ParseFactor;
    ppExp := CurASTNode;
    { the lowering itself (dunders, then pypow_v) is PyMakePow — shared with
      `**=`, which must produce the identical node }
    CurASTNode := PyMakePow(ppBase, ppExp);
    LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
  end;

  { A PROCEDURE used as a VALUE. ParseFactor only ever runs in expression
    position, so a call node reaching here whose proc has no result is the
    error FPC reports as "Can't read or write variables of this type".

    Without this the call COMPILED and yielded whatever happened to be in the
    return register: `n := f.DoIt` assigned stack junk and `f.DoArg(3) + 1`
    evaluated to 4 — the argument read back out
    (bug-p-procedure-method-in-an-expression-yields-garbage). Silent, and it
    also absorbed signature drift: it is what hid pxx's `WaitFor: procedure`
    from a probe written to compare against FPC's `WaitFor: LongWord`.

    METHOD calls are the shape that got here; a bare procedure name was already
    rejected (as "undefined variable"), which is why only methods produced
    garbage. Constructors are exempt — see ProcIsConstructor.

    Pascal only. C has its own void-value diagnostics and NilPy's `None`-typed
    calls are values by design, so neither goes through this.

    StmtCallDepth: the `(`-led STATEMENT branch of ParseStatementAST runs
    the expression parser over what is really a statement — `(o as T).M;` — so
    the check stands down inside it. Sub-expressions of such a statement are
    unchecked as a result; that shape is rare and the alternative is a false
    error on every `(o as T).M;`. }
  if (not isNilPy) and (not PyExprMode) and (not CProgramMode) and
     (StmtCallDepth = 0) and (CurASTNode >= 0) and
     ((ASTKind[CurASTNode] = AN_CALL) or (ASTKind[CurASTNode] = AN_VIRTUAL_CALL)) and
     (ASTIVal[CurASTNode] >= 0) and (ASTIVal[CurASTNode] < ProcCount) and
     (not Procs[ASTIVal[CurASTNode]].IsFunc) and
     (not ProcIsConstructor(ASTIVal[CurASTNode])) then
    Error('"' + Procs[ASTIVal[CurASTNode]].Name +
          '" is a procedure and has no result to use in an expression');
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

{ Rewrite a PROMO operand of a float-typed binop into an explicit
  PXXPromoToDouble call; anything else is handed back untouched.

  A float binop lowers its operands as machine values, and a promo rvalue IS
  the slot address (decide-promoint-rvalue-representation) — so `(i + 1) + 2.5`
  added 2.5 to a POINTER and printed 5553978.5, and `(i + 1) / 2` was just as
  wrong. Converting HERE, as an ordinary AN_CALL, is the same lever hex/bin/oct
  and str() use: the promo->Pointer argument arm in IRLowerCallArg carries the
  slot address to promocore without any hand-built IR.

  PXXPromoToDouble reads the true value off the limbs rather than narrowing
  first, so a bignum operand converts to a large float, not to an approximation
  of its low 64 bits. }
function PromoWidenToDouble(n: Integer): Integer;
var pwProc, pwArg, pwCall: Integer;
begin
  PromoWidenToDouble := n;
  if n < 0 then Exit;
  if not TypeIsPromoInt(IntToTypeKind(ASTTk[n])) then Exit;
  pwProc := FindProc('PXXPromoToDouble');
  if pwProc < 0 then Exit;        { promocore not loaded — leave as-is }
  pwArg := AllocNode(AN_ARG);
  ASTLeft[pwArg] := n;
  ASTRight[pwArg] := -1;
  pwCall := AllocNode(AN_CALL);
  ASTIVal[pwCall] := pwProc;
  ASTTk[pwCall] := Ord(tyDouble);
  ASTLeft[pwCall] := pwArg;
  PromoWidenToDouble := pwCall;
end;

{ Rewrite a PROMO operand of a machine-integer TYPECAST into an explicit
  PXXPromoToInt64 call; anything else is handed back untouched.

  `Integer(n)` / `Int64(n)` are value-PUNS: the result's bit pattern is the
  operand's. For a promotable int the operand's bit pattern is its SLOT ADDRESS
  (decide-promoint-rvalue-representation), so `n := 12; writeln(Int64(n))`
  printed a pointer. Demoting first makes the pun operate on a real machine
  integer, which leaves every existing cast rule (width truncation, sign) doing
  exactly what it did before.

  CHECKED (PXXPromoToInt64, RunError 215) rather than the wrapping demote: a
  Pascal cast of a value that does not fit is the case a programmer wants told
  about, and silently delivering `value mod 2^64` is the defect the whole type
  exists to remove. NilPy's own int-annotated narrowing is separate and stays
  wrapping — it goes through IRLowerCallArg and the assignment path, not here. }
function PromoDemoteToInt64(n: Integer): Integer;
var pdProc, pdArg, pdCall: Integer;
begin
  PromoDemoteToInt64 := n;
  if n < 0 then Exit;
  if not TypeIsPromoInt(IntToTypeKind(ASTTk[n])) then Exit;
  pdProc := FindProc('PXXPromoToInt64');
  if pdProc < 0 then Exit;        { promocore not loaded — leave as-is }
  pdArg := AllocNode(AN_ARG);
  ASTLeft[pdArg] := n;
  ASTRight[pdArg] := -1;
  pdCall := AllocNode(AN_CALL);
  ASTIVal[pdCall] := pdProc;
  ASTTk[pdCall] := Ord(tyInt64);
  ASTLeft[pdCall] := pdArg;
  PromoDemoteToInt64 := pdCall;
end;

{ A typecast of a VARIANT operand, rewritten as the variant CONVERSION.

  FPC and Delphi define `Int64(v)` / `Double(v)` / `Char(v)` as exactly the
  conversion `i := v` performs; pxx lowered them as ordinary hard casts of the
  16-byte variant RECORD, so the value read was the TAG word (`Int64(v)` on
  v=9 answered 1) and the float kinds reinterpreted those bytes as an address
  and segfaulted. The assignment form was already right, which is the
  double-case shape normalise-dont-special-case.md warns about — so this
  NORMALISES the cast onto the assignment: store into a hidden temp of the
  cast's type (ir.inc's AN_ASSIGN arm emits the VariantTo*/pyvar_to_* unbox
  there) and yield the temp. One mechanism, every spelling, all six backends,
  no new IR op. Reuses the generic assign-then-yield node AN_STR_FROM_CHAR
  (Left = the store side-effect, Right = the temp read), same as the float and
  String() casts below.

  Returns -1 for "not mine" — a non-variant operand, or a target no variant
  payload can stand in for (pointer/record/set/class; mirror of ir.inc's
  IRVariantUnboxKind, minus tyPointer: `Pointer(v)` stays a reinterpret, since
  the address of the record is the only sensible reading of it).
  bug-p-a-typecast-of-a-variant-reinterprets-it-instead-of-converting }
function VariantCastToTemp(n: Integer; target: TTypeKind): Integer;
var vcTmp, vcAsg, vcLhs, vcRd, vcNd: Integer;
begin
  VariantCastToTemp := -1;
  if n < 0 then Exit;
  if IntToTypeKind(ASTTk[n]) <> tyVariant then Exit;
  if not (TypeIsFloat(target) or (target = tyBoolean) or (target = tyChar) or
          (target = tyString) or (target = tyAnsiString) or
          (target = tyInteger) or (target = tyInt8) or (target = tyInt16) or
          (target = tyInt32) or (target = tyInt64) or (target = tyNativeInt) or
          (target = tyUInt8) or (target = tyUInt16) or (target = tyUInt32) or
          (target = tyUInt64) or (target = tyNativeUInt)) then Exit;
  vcTmp := AllocVar('', target);
  vcNd  := AllocNode(AN_STR_FROM_CHAR);
  vcLhs := AllocNode(AN_IDENT);
  ASTIVal[vcLhs] := vcTmp; ASTTk[vcLhs] := Ord(Syms[vcTmp].TypeKind);
  vcAsg := AllocNode(AN_ASSIGN);
  ASTLeft[vcAsg] := vcLhs; ASTRight[vcAsg] := n;
  ASTTk[vcAsg] := Ord(Syms[vcTmp].TypeKind);
  ASTLeft[vcNd] := vcAsg;
  vcRd := AllocNode(AN_IDENT);
  ASTIVal[vcRd] := vcTmp; ASTTk[vcRd] := Ord(Syms[vcTmp].TypeKind);
  ASTRight[vcNd] := vcRd;
  ASTTk[vcNd] := Ord(Syms[vcTmp].TypeKind);
  VariantCastToTemp := vcNd;
end;

{ Apply PromoWidenToDouble to both operands of a float-typed binop, in place. }
{ Pascal widens a `div`/`mod` pair to a type that holds BOTH operands, and an
  integer LITERAL's range is its own value, not a declared type -- so `q div 10`
  is an unsigned division (10 fits QWord) while `q div n` with `n: Int64` is a
  signed one. The signedness rule below reads only the two operand TYPES, so a
  positive literal divisor carried tyInteger into it and would have flipped every
  unsigned division by a constant to signed, turning any QWord above 2^63
  negative. Retype the LITERAL instead of teaching the rule about literals: one
  "unsigned iff both operands are" rule then serves the result type and all six
  backends, with no second path to keep in step (normalise-dont-special-case). }
procedure NormalizeUnsignedLiteralOperand(typed, lit: Integer);
begin
  if CProgramMode then Exit;
  if (typed < 0) or (lit < 0) then Exit;
  if ASTKind[lit] <> AN_INT_LIT then Exit;
  if ASTIVal[lit] < 0 then Exit;
  if not TypeIsOrdinal(IntToTypeKind(ASTTk[typed])) then Exit;
  if TypeSigned(IntToTypeKind(ASTTk[typed])) then Exit;
  ASTTk[lit] := Ord(tyUInt64);
end;

procedure PromoWidenBinopOperands(node: Integer);
begin
  if node < 0 then Exit;
  ASTLeft[node] := PromoWidenToDouble(ASTLeft[node]);
  ASTRight[node] := PromoWidenToDouble(ASTRight[node]);
end;

procedure ParseTerm;
var op: TTokenKind; left, right, node, opSOffset, opSLen, opci: Integer;
    ixTry: Integer;   { a repeat count coerced through __index__ }
begin
  ParseFactor;
  while (((CurTok.Kind in [tkStar, tkSlash, tkDiv, tkMod, tkAnd, tkShl]) or
        ((CurTok.Kind = tkIdent) and (CurTok.SVal = 'shr'))) and
        not (PyExprMode and (CurTok.Kind in [tkAnd, tkShl]))) or
        { Python's `@` (matrix multiply) binds at THIS precedence. Only in
          NilPy: `@` is Pascal's address-of prefix, which ParseFactor owns.
          Decorator-`@` never reaches here — it is consumed at statement
          start, before any expression is parsed
          (bug-nilpy-matmul-operator-does-not-parse). }
        (PyExprMode and (CurTok.Kind = tkAt)) do
  begin
    opSOffset := Tokens[TokPos - 1].SOffset;
    opSLen := Tokens[TokPos - 1].SLen;
    op := CurTok.Kind; Next;
    left := CurASTNode;
    ParseFactor;
    right := CurASTNode;
    node := AllocNode(AN_BINOP); ASTIVal[node] := Ord(op); ASTLeft[node] := left; ASTRight[node] := right;
    ASTSOffset[node] := opSOffset; ASTSLen[node] := opSLen;
    { {$Q+} region: * is overflow-checked (feature-pascal-overflow-checks-q-plus) }
    if (op = tkStar) and TokQChecks[TokPos - 1] then ASTQChk[node] := True;
    { `a @ b` — `__matmul__`, then the reflected `__rmatmul__`, then TypeError.
      Never an AN_BINOP: `@` has NO arithmetic meaning in Python at all (no
      builtin type implements it), so falling through to the numeric typing
      would compute on the class handle exactly as the other dunders did before
      they were dispatched. The node allocated above is discarded, like the
      list-repeat and bytes-repeat arms below. }
    if PyExprMode and (op = tkAt) then
    begin
      node := -1;
      if (IntToTypeKind(ASTTk[left]) = tyClass) and
         (ResolveNodeRec(left) >= REC_UCLASS_BASE) and
         (not PyRecIsPylibOwnClass(ResolveNodeRec(left))) then
        node := PyCallMeth1(ResolveNodeRec(left) - REC_UCLASS_BASE, '__matmul__',
                            left, right);
      if node < 0 then node := PyReflectedDunder(PyReflName(op), left, right);
      if node < 0 then node := PyMakeUnsupportedOperand;
      CurASTNode := node;
      continue;
    end;
    { A sequence REPEAT COUNT may be an object with `__index__` — `[0] * C(3)`,
      `"ab" * C(2)`. The repeat tests below only recognise an ordinal, so the
      object fell past them into the arithmetic/dunder path and raised
      TypeError. Coerce ONLY when doing so actually turns the pair into a
      repeat: `C(3) * 5` with no `__mul__` must stay a TypeError, not silently
      become 15 (bug-nilpy-unary-numeric-dunders-return-raw-handle). }
    if PyExprMode and (op = tkStar) then
    begin
      ixTry := PyIndexCoerce(right);
      if (ixTry <> right) and
         (PyListRepeatPair(left, ixTry) or PyBytesRepeatPair(left, ixTry) or
          PyIsStrBaseTk(IntToTypeKind(ASTTk[left]))) then
      begin right := ixTry; ASTRight[node] := right; end
      else
      begin
        ixTry := PyIndexCoerce(left);
        if (ixTry <> left) and
           (PyListRepeatPair(ixTry, right) or PyBytesRepeatPair(ixTry, right) or
            PyIsStrBaseTk(IntToTypeKind(ASTTk[right]))) then
        begin left := ixTry; ASTLeft[node] := left; end;
      end;
    end;
    opci := -1;
    if (IntToTypeKind(ASTTk[left]) = tyRecord) or (IntToTypeKind(ASTTk[left]) = tyClass) then
      opci := FindOpOverload2(Ord(op), ASTTk[left], ResolveNodeRec(left),
                              ASTTk[right], ResolveNodeRec(right));
    if opci >= 0 then
      { Overloaded operator on a record/class operand returns its result type. }
      ASTTk[node] := Ord(Procs[opci].RetType)
    { `xs * n` on a LIST repeats it, and `bytes([ch]) * u` on BYTES. Built as
      direct calls rather than tagged like the string case, because the RESULT's
      class identity has to survive into a local: an AN_BINOP carries no record
      id, so an inferred local would hold a tyClass with no identity and len()
      would mis-pick its overload (feature-nilpy-list-repeat).

      BEFORE the variant arm below, not after. A repeat is decided by the
      SEQUENCE operand, which is statically known here — one side IS a list or
      bytes node — while the COUNT may be anything, including a variant. Sitting
      after the variant arm, the whole pair was tagged tyVariant the moment the
      count had no static type and the repeat builders were never reached: the
      statement stayed an arithmetic multiply and coerced the SEQUENCE to a
      number, so uforth's `bytes([ch]) * u` inside `def w_fill(vm2)` raised
      "expected a number, got object" — pointing at a coercion rather than at a
      missed repeat. `[7] * u` survived only because the runtime variant
      multiply happens to handle a list on the LEFT, which is why `u * [7]`
      failed while `[7] * u` passed.
      bug-nilpy-sequence-repeat-with-a-variant-count-falls-through-to-arithmetic }
    { complex `*` and `/`, either operand order, mixed with int/float. Before
      every arm below: complex is a pylib class, so the dunder arms exclude it
      and it would otherwise reach the generic arithmetic and compute on the
      object HANDLE. }
    else if PyExprMode and (op in [tkStar, tkSlash]) and
            (PyNodeIsComplex(left) or PyNodeIsComplex(right)) then
    begin
      node := PyMakeComplexBinop(op, left, right);
      if node < 0 then node := PyMakeUnsupportedOperand;
      CurASTNode := node;
      continue;
    end
    else if PyExprMode and (op = tkStar) and PyListRepeatPair(left, right) then
    begin
      node := PyMakeListRepeat(left, right);
      CurASTNode := node;
      continue;
    end
    else if PyExprMode and (op = tkStar) and PyBytesRepeatPair(left, right) then
    begin
      node := PyMakeBytesRepeat(left, right);
      CurASTNode := node;
      continue;
    end
    else if (ASTTk[left] = Ord(tyVariant)) or (ASTTk[right] = Ord(tyVariant)) then
      ASTTk[node] := Ord(tyVariant)
    { Python's `s * n` REPEATS the text (either operand order), and the IR
      lowers it to pystr_repeat — but the node had been tagged with the
      arithmetic result here, so a local taking its value was typed Integer and
      `len(s)` found no overload
      (bug-a-nilpy-str-repeat-local-infers-as-int). Tag it at parse time, where
      the inference reads it. }
    else if PyExprMode and (op = tkStar) and
            (PyIsStrBaseTk(IntToTypeKind(ASTTk[left])) <>
             PyIsStrBaseTk(IntToTypeKind(ASTTk[right]))) then
      ASTTk[node] := Ord(tyAnsiString)
    { `xs * n` on a LIST repeats it. Built as a direct call rather than tagged
      like the string case, because the RESULT's class identity has to survive
      into a local: an AN_BINOP carries no record id, so an inferred local would
      hold a tyClass with no identity and len() would mis-pick its overload
      (feature-nilpy-list-repeat). }
    else if PyExprMode and (op in [tkStar, tkSlash, tkDiv, tkMod]) and (opci < 0) and
            (IntToTypeKind(ASTTk[left]) <> tyClass) and
            (PyReflectedDunder(PyReflName(op), left, right) >= 0) then
    begin
      CurASTNode := PyReflectedDunder(PyReflName(op), left, right);
      continue;
    end
    else if PyExprMode and (op in [tkStar, tkSlash, tkDiv, tkMod]) and (opci < 0) and
            (IntToTypeKind(ASTTk[left]) = tyClass) and
            (ResolveNodeRec(left) >= REC_UCLASS_BASE) then
    begin
      { `Vector(1,2) * 3` — a user class's own `__mul__`/`__truediv__` dunder.
        Neither the list-repeat nor bytes-repeat branch above matched, so a
        bare tyClass LEFT operand is a genuine user object — dispatch to its
        dunder rather than falling through to the arithmetic AN_BINOP built
        above, which silently computed garbage on the class HANDLE as if it
        were a number (bug-nilpy-arithmetic-operator-dunders-not-dispatched,
        same root cause as the +/- fix in ParseSimpleExpr). Only the LEFT
        operand's class is consulted, matching Python's left-operand-first
        dunder lookup — no `__rmul__`/`__rtruediv__` fallback. }
      { `//` and `%` join the same branch: measured, they were NOT dispatched —
        C(7) // C(3) answered 0 and C(7) % C(3) answered 126959237464088, both
        computed on the class HANDLE (feature-nilpy-arithmetic-dunders-full-
        protocol).

        pylib's OWN rows reach here only when no earlier branch claimed them —
        list-repeat and bytes-repeat already handled the `*` forms — so for them
        the operator has no Python meaning and the answer is the runtime
        TypeError below, NOT the dunder lookup and NOT a fall-through. Excluding
        them from the branch entirely was measured WRONG: `[1,2] / 3` then fell
        past this arm into the generic arithmetic and silently computed on the
        list HANDLE, where it had previously produced a loud (if compile-time)
        error. Skip the lookup, keep the raise. }
      if PyRecIsPylibOwnClass(ResolveNodeRec(left)) then node := -1
      else if op = tkStar then node := PyCallMeth1(ResolveNodeRec(left) - REC_UCLASS_BASE, '__mul__', left, right)
      else if op = tkDiv then node := PyCallMeth1(ResolveNodeRec(left) - REC_UCLASS_BASE, '__floordiv__', left, right)
      else if op = tkMod then node := PyCallMeth1(ResolveNodeRec(left) - REC_UCLASS_BASE, '__mod__', left, right)
      else node := PyCallMeth1(ResolveNodeRec(left) - REC_UCLASS_BASE, '__truediv__', left, right);
      if node < 0 then
        node := PyMakeUnsupportedOperand;   { runtime TypeError, not a build abort }
      CurASTNode := node;
      continue;
    end
    { Python's `"%s=%d" % args` — string INTERPOLATION, not arithmetic. With no
      case for it the node kept the numeric `mod` typing and the lowering applied
      integer mod to a string handle: `"%.2f" % 3.14159` printed 0.0 and
      `"%s" % s` printed a pointer, compiling clean either way
      (bug-nilpy-percent-string-format-garbage). Recognised on the LEFT operand
      being a str, which is what Python dispatches on too. }
    else if PyExprMode and (op = tkMod) and
            PyIsStrBaseTk(IntToTypeKind(ASTTk[left])) then
    begin
      node := PyMakePercentFormat(left, right);
      CurASTNode := node;
      continue;
    end
    else if (op = tkAnd) and (ASTTk[left] = Ord(tyBoolean)) and (ASTTk[right] = Ord(tyBoolean)) then
      ASTTk[node] := Ord(tyBoolean)
    else if (ASTTk[left] = Ord(tySet)) or (ASTTk[right] = Ord(tySet)) then
      ASTTk[node] := Ord(tySet)
    else if op = tkSlash then
    begin
      ASTTk[node] := Ord(FloatBinopResultTk(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])));  { '/' produces native-depth float }
      PromoWidenBinopOperands(node);
    end
    else if PyExprMode and ((op = tkDiv) or (op = tkMod)) and
            (TypeIsFloat(IntToTypeKind(ASTTk[left])) or
             TypeIsFloat(IntToTypeKind(ASTTk[right]))) then
      { Python's `//` and `%` yield a FLOAT as soon as either operand is one.
        Typing from the LEFT operand alone made `3 % 2.5` an integer-typed
        node, and ir.inc's retype to tyDouble (when it routes to pyfloormod_f)
        came too late for anything that had already bound an overload from the
        node's type: `str(3 % 2.5)` picked the Int64 str() and printed
        4602678819172646912, the double's BIT PATTERN, while a bare
        `print(3 % 2.5)` was right because print reads the type after lowering
        (bug-nilpy-str-of-mixed-mod-prints-double-bits).

        PyExprMode-only: Pascal's own `div`/`mod` are integer spellings, so the
        Pascal dialect and the self-host binary are untouched. }
    begin
      ASTTk[node] := Ord(FloatBinopResultTk(IntToTypeKind(ASTTk[left]),
                                            IntToTypeKind(ASTTk[right])));
      PromoWidenBinopOperands(node);
    end
    else if (op = tkDiv) or (op = tkMod) then
    begin
      NormalizeUnsignedLiteralOperand(left, right);
      NormalizeUnsignedLiteralOperand(right, left);
      ASTTk[node] := Ord(TypeDivideResultPair(IntToTypeKind(ASTTk[left]),
                                              IntToTypeKind(ASTTk[right])));
    end
    else if (op = tkIdent) or (op = tkShl) then
    begin
      { A SHIFT happens at NATIVE width, and its result is not truncated back to
        the operand's declared width — `1 shl 40` is 2^40, not 0, and
        `-a shr 1` (a: Integer) is the 64-bit logical shift.
        decide-shift-operator-promotion-width (user, 2026-08-10): "pxx
        truncating to 32-bit is wrong"; FPC's own answers are inconsistent here
        (it widens the operand for `shr` but masks the count for `shl`, and its
        constant folder contradicts its runtime path), so copying them is left
        to --strict-fpc. Widening never loses information; truncating does, and
        truncating is how `1 shl 40` became 0.
        C keeps its own semantics: CProgramMode's `<<` wraps at the declared
        width, which is what the standard says, so the promotion is Pascal-only.
        bug-a-shr-on-a-32-bit-operand-does-not-promote-like-fpc }
      { …and under --strict-fpc, promote ONLY a compile-time constant operand.
        That is FPC's own asymmetry, faithfully: its constant FOLDER answers
        `1 shl 40` = 2^40 and `-8 shr 1` = 9223372036854775804 at full width,
        while the same expressions over a VARIABLE wrap at the operand's
        declared width. Strict mode is documented as copying FPC's bugs, and
        this is one of them.
        bug-a-strict-fpc-does-not-reproduce-fpc-shift-widths }
      { …and a NEGATED operand of any shape, not just a negated literal, because
        FPC's unary minus yields a 64-bit value: measured, `SizeOf(-x)` is 8 for
        EVERY integer operand type (Byte, ShortInt, Word, SmallInt, Integer,
        Cardinal, Int64) and all seven answer 9223372036854775804 for
        `-x shr 1`. So FPC's operand is already wide and its narrow-shift
        asymmetry never applies to it — reproducing that asymmetry over `-a`
        made --strict-fpc the ONE mode that disagreed with FPC on this row,
        while pxx's own default agreed.
        bug-p-strict-fpc-narrows-a-negated-integer-shift-the-default-gets-right }
      if (not CProgramMode) and
         ((not StrictShiftWidth) or (ASTKind[left] = AN_INT_LIT) or
          (ASTKind[left] = AN_NEG)) and
         TypeIsMachineInt(IntToTypeKind(ASTTk[left])) and
         (TypeSize(IntToTypeKind(ASTTk[left])) < TypeSize(tyNativeInt)) then
      begin
        if TypeSigned(IntToTypeKind(ASTTk[left])) then
          ASTTk[node] := Ord(tyNativeInt)
        else
          ASTTk[node] := Ord(tyNativeUInt);
      end
      else
        ASTTk[node] := ASTTk[left];
    end
    else if (ASTTk[left] = Ord(tySingle)) or (ASTTk[left] = Ord(tyDouble)) or (ASTTk[left] = Ord(tyExtended)) or
            (ASTTk[right] = Ord(tySingle)) or (ASTTk[right] = Ord(tyDouble)) or (ASTTk[right] = Ord(tyExtended)) then
    begin
      ASTTk[node] := Ord(FloatBinopResultTk(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])));
      PromoWidenBinopOperands(node);
    end
    else if TypeIsPromoInt(IntToTypeKind(ASTTk[left])) or
            TypeIsPromoInt(IntToTypeKind(ASTTk[right])) then
      { Promotable int is infectious — see the twin arm in the other binop
        typing site. Above the ordinal arm because promo is deliberately not
        TypeIsOrdinal. }
      ASTTk[node] := Ord(TypeArithmeticResult(IntToTypeKind(ASTTk[left]),
                                              IntToTypeKind(ASTTk[right])))
    else if PyExprMode and PyIntGrowsOp(op) and
            PyIsMachineIntTk(IntToTypeKind(ASTTk[left])) and
            PyIsMachineIntTk(IntToTypeKind(ASTTk[right])) then
      { NilPy: `*` over two NATIVE ints is still arbitrary precision — see
        PyIntGrowsOp. Below the promo arm (which already covers the mixed
        case) and above the ordinal one, which would type it tyInteger. }
      ASTTk[node] := Ord(tyPromoInt64)
    else if TypeIsOrdinal(IntToTypeKind(ASTTk[left])) and TypeIsOrdinal(IntToTypeKind(ASTTk[right])) then
      ASTTk[node] := Ord(TypeArithmeticResult(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])))
    else
      ASTTk[node] := Ord(tyInteger);
    CurASTNode := node;
    { Keep the side channel with the VALUE. LastExprTk was last written by
      ParseFactor, so after `7 / 2` it held the type of the `2` — and every
      consumer that asks it about "the expression I just parsed" got the last
      FACTOR instead. `int(7/2)` printed 3.5's bit pattern and `float(7/2)`
      printed 4.6e18, while the identical `x = 7/2; int(x)` was correct because
      an ident leaves the two agreeing. Fixed at the source rather than at each
      consumer: the arms below and in ParseSimpleExpr end the same way.
      bug-nilpy-int-of-a-division-reads-the-doubles-bits }
    LastExprTk := IntToTypeKind(ASTTk[node]);
  end;
end;

procedure ParseSimpleExpr;
var op: TTokenKind; neg: Boolean; left, right, node, opci: Integer;
begin
  { Unary minus binds TIGHTER than the multiplicative level in EVERY frontend
    here — Pascal included. It used to be treated as an additive-level sign for
    Pascal/C on the grounds that FPC reads `-7 div 2` as `-(7 div 2)`; that is
    true and also unobservable, because both readings give -3. The operators
    that DO expose it are `and` and `shr`, and measured against FPC:

        var x: Integer; x := 8;
        -x and 12    FPC 8                     pxx -8      { -(x and 12) }
        -x shr 1     FPC 9223372036854775804   pxx -4      { -(x shr 1)  }

    so the old note picked `div` to check the very question `div` cannot answer.
    C agrees with FPC here too (`-a & b` is `(-a) & b`).

    The minus now always falls through to ParseFactor's own tkMinus case, which
    negates ONE factor — the path PyExprMode already took, for the same reason.
    bug-a-unary-minus-binds-looser-than-and-shr }
  neg := False;
  { Unary plus is identity, so its binding is unobservable — keep eating it here
    rather than teaching the factor a no-op case. }
  Eat(tkPlus);
  ParseTerm;
  if neg then
  begin
    node := AllocNode(AN_NEG); ASTLeft[node] := CurASTNode; ASTTk[node] := ASTTk[CurASTNode]; CurASTNode := node;
  end;
  { tkSymDiff (`><`, set symmetric difference) rides the ADDITIVE level, which is
    where FPC puts it alongside set `+` and `-`. Only the Pascal lexer produces
    the token, so no frontend gate is needed. }
  while (CurTok.Kind in [tkPlus, tkMinus, tkOr, tkXor, tkSymDiff]) and
        not (PyExprMode and (CurTok.Kind in [tkOr, tkXor])) do
  begin
    op := CurTok.Kind; Next;
    left := CurASTNode;
    ParseTerm;
    right := CurASTNode;
    { WideChar concatenation is STRING building, not integer addition (FPC:
      WideChar+WideChar is a two-unit UTF-16 string). Both sides widechar ->
      the surrogate-aware pair helper, so `WideChar(u1)+WideChar(u2)` of a
      surrogate pair yields the single 4-byte code point (fpjson's \uXXXX
      decoder). One widechar side against a string -> convert that side to
      its UTF-8 encoding and concatenate normally. }
    if (op = tkPlus) and NodeIsWideCharVal(left) and NodeIsWideCharVal(right) then
    begin
      opci := FindProc('__pxxWideCharPairToUTF8');
      if opci < 0 then Error('WideChar concatenation: __pxxWideCharPairToUTF8 helper not loaded');
      node := AllocNode(AN_ARG);
      ASTLeft[node] := left; ASTTk[node] := Ord(tyInteger);
      left := AllocNode(AN_ARG);
      ASTLeft[left] := right; ASTRight[left] := -1; ASTTk[left] := Ord(tyInteger);
      ASTRight[node] := left;
      left := node;
      node := AllocNode(AN_CALL);
      ASTIVal[node] := opci;
      ASTTk[node] := Ord(Procs[opci].RetType);
      ASTLeft[node] := left; ASTRight[node] := -1;
      CurASTNode := node;
      continue;
    end;
    { A 2-byte ordinal (tyUInt16 = WideChar; there is no distinct WideChar type)
      concatenated with a string/char MUST be a widechar — `Word + string` is
      invalid Pascal — so convert it, matching the widechar(x)-cast case. This
      catches a bare `w: WideChar` variable, which NodeIsWideCharVal (cast-only)
      misses; without it `'x' + w` crashed. Restricted to the SINGLE-sided form:
      `tyUInt16 + tyUInt16` stays integer addition (Word+Word), since two 2-byte
      ordinals are ambiguous and must not be silently turned into string-building.
      See bug-pascal-widechar-var-to-string-other-contexts. }
    if (op = tkPlus) and
       (NodeIsWideCharVal(left) or (IntToTypeKind(ASTTk[left]) = tyUInt16)) and
       ((ASTTk[right] = Ord(tyAnsiString)) or (ASTTk[right] = Ord(tyString)) or
        (ASTTk[right] = Ord(tyChar))) then
      left := WrapWideCharToUTF8(left)
    else if (op = tkPlus) and
       (NodeIsWideCharVal(right) or (IntToTypeKind(ASTTk[right]) = tyUInt16)) and
       ((ASTTk[left] = Ord(tyAnsiString)) or (ASTTk[left] = Ord(tyString)) or
        (ASTTk[left] = Ord(tyChar))) then
      right := WrapWideCharToUTF8(right);
    node := AllocNode(AN_BINOP); ASTIVal[node] := Ord(op); ASTLeft[node] := left; ASTRight[node] := right;
    { {$Q+} region: + and - are overflow-checked (feature-pascal-overflow-checks-q-plus) }
    if ((op = tkPlus) or (op = tkMinus)) and TokQChecks[TokPos - 1] then
      ASTQChk[node] := True;
    opci := -1;
    if (IntToTypeKind(ASTTk[left]) = tyRecord) or (IntToTypeKind(ASTTk[left]) = tyClass) then
      opci := FindOpOverload2(Ord(op), ASTTk[left], ResolveNodeRec(left),
                              ASTTk[right], ResolveNodeRec(right));
    if opci >= 0 then
      { Overloaded operator on a record/class operand: the node's type is the
        operator's result type, so an inferred target and the aggregate-return
        copy are sized correctly (not the tyInteger catch-all below). }
      ASTTk[node] := Ord(Procs[opci].RetType)
    else if (ASTTk[left] = Ord(tyVariant)) or (ASTTk[right] = Ord(tyVariant)) then
      ASTTk[node] := Ord(tyVariant)
    else if PyExprMode and (op = tkPlus) and PyNodeIsPyBytes(left) and PyNodeIsPyBytes(right) then
    begin
      { b1 + b2 — bytes concatenation (uforth WRITE-LINE) }
      node := PyMakeBytesBinCall('pybytes_concat', left, right, tyClass);
      CurASTNode := node;
      continue;
    end
    else if PyExprMode and (op = tkPlus) and PyNodeIsPyList(left) and PyNodeIsPyList(right) then
    begin
      { xs + ys — list concatenation (uforth {: :} locals: list(a)+list(b)) }
      node := PyMakeListBinCall('pylist_concat', left, right);
      CurASTNode := node;
      continue;
    end
    else if PyExprMode and (op = tkPipe) and PyNodeIsPyDict(left) and PyNodeIsPyDict(right) then
    begin
      { d1 | d2 — PEP 584 dict union. Checked before the set arm below since
        a dict is a distinct tyClass identity from TPyList, and only dict
        needs `|` disambiguated from set's own use of it. }
      node := PyMakeDictBinCall('pydict_or', left, right);
      CurASTNode := node;
      continue;
    end
    else if PyExprMode and (op in [tkAmp, tkPipe, tkMinus, tkXor]) and
            PyNodeIsPyList(left) and PyNodeIsPyList(right) then
    begin
      { Python's set operators: & (intersection), | (union), - (difference),
        ^ (symmetric difference). A list supports NONE of these four, so two
        TPyList operands here are unambiguously a set operation — see
        pyset_and's own comment for why this silently did raw pointer
        arithmetic before (bug-nilpy-set-and-dict-operators-do-raw-pointer-
        arithmetic). }
      if op = tkAmp then node := PyMakeListBinCall('pyset_and', left, right)
      else if op = tkPipe then node := PyMakeListBinCall('pyset_or', left, right)
      else if op = tkMinus then node := PyMakeListBinCall('pyset_sub', left, right)
      else node := PyMakeListBinCall('pyset_xor', left, right);
      CurASTNode := node;
      continue;
    end
    else if PyExprMode and (op = tkPlus) and
            (PyNodeIsPyList(left) or PyNodeIsPyList(right)) then
    begin
      { `[1,2] + "x"` — one side is a list and the other is not: CPython
        raises TypeError at RUN time (`can only concatenate list (not "str")
        to list`); NilPy's list-concat branch above already requires BOTH
        sides typed as a list, so a mismatched pair fell through into the
        tyString-concat branch below, which only checks "either side is a
        string" and ignores that the OTHER side is a raw class/list POINTER —
        silently reinterpreting it as string data instead of raising
        (bug-nilpy-list-plus-nonlist-silently-corrupts-instead-of-typeerror).
        NilPy resolves types statically, so this is caught here as a compile
        error rather than deferred to a run-time exception. }
      { runtime TypeError, matching CPython, rather than a build abort — the
        static type is known here but Python's answer is an exception. }
      CurASTNode := PyMakeUnsupportedOperand;
      continue;
    end
    { complex `+` and `-`, either operand order, mixed with int/float — before
      the reflected and user-class arms, both of which exclude pylib classes. }
    else if PyExprMode and (op in [tkPlus, tkMinus]) and
            (PyNodeIsComplex(left) or PyNodeIsComplex(right)) then
    begin
      node := PyMakeComplexBinop(op, left, right);
      if node < 0 then node := PyMakeUnsupportedOperand;
      CurASTNode := node;
      continue;
    end
    else if PyExprMode and (op in [tkPlus, tkMinus]) and
            (IntToTypeKind(ASTTk[left]) <> tyClass) and
            (PyReflectedDunder(PyReflName(op), left, right) >= 0) then
    begin
      { reflected: the LEFT operand is not a user class, so try the RIGHT
        operand's __radd__/__rsub__ with the operands swapped. }
      CurASTNode := PyReflectedDunder(PyReflName(op), left, right);
      continue;
    end
    else if PyExprMode and (op in [tkPlus, tkMinus]) and
            (IntToTypeKind(ASTTk[left]) = tyClass) and
            (ResolveNodeRec(left) >= REC_UCLASS_BASE) then
    begin
      { `Vector(1,2) + Vector(3,4)` — a user class's own operator dunder
        (`__add__`/`__sub__`). Neither operand reached here as a TPyList/
        TPyDict (those branches above already `continue`d), so a bare tyClass
        LEFT operand is a genuine user object: dispatch to its dunder method
        rather than falling through to the arithmetic/pointer typing below,
        which silently computed garbage on the two class HANDLES as if they
        were integers (bug-nilpy-arithmetic-operator-dunders-not-dispatched).
        Only the LEFT operand's class is consulted — matching Python's
        left-operand-first dunder lookup; the right-operand `__radd__`/
        `__rsub__` fallback (e.g. `3 * Vector(...)`) is not implemented. }
      if op = tkPlus then node := PyCallMeth1(ResolveNodeRec(left) - REC_UCLASS_BASE, '__add__', left, right)
      else node := PyCallMeth1(ResolveNodeRec(left) - REC_UCLASS_BASE, '__sub__', left, right);
      if node < 0 then
        node := PyMakeUnsupportedOperand;   { runtime TypeError, not a build abort }
      CurASTNode := node;
      continue;
    end
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
    begin
      ASTTk[node] := Ord(FloatBinopResultTk(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])));
      PromoWidenBinopOperands(node);
    end
    else if TypeIsPromoInt(IntToTypeKind(ASTTk[left])) or
            TypeIsPromoInt(IntToTypeKind(ASTTk[right])) then
      { A promotable int is infectious: mixing it with any ordinary integer
        yields a promotable int. This arm must sit ABOVE the ordinal arm because
        promo is deliberately not reported by TypeIsOrdinal — without it the
        result fell through to the tyInteger default and the IR lowering never
        saw a promo type, so overflow silently WRAPPED (25! came out as 25! mod
        2^64 instead of trapping). Below the float arm, so promo-with-float
        still resolves as float. }
      ASTTk[node] := Ord(TypeArithmeticResultOp(IntToTypeKind(ASTTk[left]),
                                                IntToTypeKind(ASTTk[right]), op))
    else if PyExprMode and PyIntGrowsOp(op) and
            PyIsMachineIntTk(IntToTypeKind(ASTTk[left])) and
            PyIsMachineIntTk(IntToTypeKind(ASTTk[right])) then
      { NilPy: `+`/`-` over two NATIVE ints is still arbitrary precision — see
        PyIntGrowsOp. Below the promo arm (which already covers the mixed case)
        and above the ordinal one, which would type it tyInteger and wrap. }
      ASTTk[node] := Ord(tyPromoInt64)
    else if TypeIsOrdinal(IntToTypeKind(ASTTk[left])) and TypeIsOrdinal(IntToTypeKind(ASTTk[right])) then
    begin
      { FPC range-based constants: a NON-NEGATIVE integer literal paired with a
        QWord operand joins the UNSIGNED domain. The literal $f0000000 widens to
        tyInt64 at parse (> maxint), and the equal-width signed-wins rule then
        demoted `q + $f0000000` to Int64 — correct bits, but printed/compared
        SIGNED (tint642's lo/hi section). A negative literal keeps the old rule. }
      if (ASTTk[left] = Ord(tyUInt64)) and (ASTKind[right] = AN_INT_LIT) and
         (ASTIVal[right] >= 0) then
        ASTTk[node] := Ord(TypeArithmeticResultOp(tyUInt64, tyUInt64, op))
      else if (ASTTk[right] = Ord(tyUInt64)) and (ASTKind[left] = AN_INT_LIT) and
              (ASTIVal[left] >= 0) then
        ASTTk[node] := Ord(TypeArithmeticResultOp(tyUInt64, tyUInt64, op))
      else
        ASTTk[node] := Ord(TypeArithmeticResultOp(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right]), op));
    end
    else
      ASTTk[node] := Ord(tyInteger);
    CurASTNode := node;
    { the additive level's half of the same rule — see ParseTerm's note }
    LastExprTk := IntToTypeKind(ASTTk[node]);
  end;
end;

{ Enum type index of an expression node, or -1. Ident-level only: enum
  identity lives on the SYMBOL (SymEnumId, tagged at var decls). }
function NodeEnumIdOf(node: Integer): Integer;
begin
  Result := -1;
  if node < 0 then Exit;
  if (ASTKind[node] = AN_IDENT) and (ASTIVal[node] >= 0) then
    Result := SymEnumId[ASTIVal[node]]
  else
    { An enum MEMBER reached here as a folded ordinal literal; ASTEnumId is the only
      thing that still remembers which enum minted it. }
    Result := ASTEnumId[node];
end;

procedure ParseExpr;
var op: TTokenKind; left, right, node, isci, isNode, isArg, isArg2: Integer; isIsTest: Boolean;
    chMid, chSym, chAssign, chSeq, chRight, chCmp, chAnd: Integer;   { Python comparison chaining }
    spDepth, spI: Integer;
    ordDirect, ordRefl: AnsiString; ordLCi, ordRCi, ordErr: Integer;   { Python ordering dunders }
    caOp, caRhs: Integer;   { compound assignment: the binop token, and the NilPy variant rewrite }
    caBinTk: TTokenKind;    { same token as caOp, kept typed for the NilPy dunder dispatch }
begin
  { NilPy argument UNPACKING of a list literal: `f(*[a, b, c])` means
    `f(a, b, c)`, and with a literal that is purely syntactic — songformatter
    writes `canvas.setStrokeColorRGB(*[0.0, 0.0, 0.0])`.

    The '*' and '[' are consumed here and the elements are then parsed as
    ordinary arguments: every argument loop in this parser already reads
    `expr (',' expr)*`, so the commas INSIDE the literal do the work. The only
    token the loops cannot make sense of is the closing ']', which is consumed
    at the end of whichever ParseExpr call lands on it.

    Nothing is mutated. An earlier version rewrote the ']' into a comma, which
    worked once and then broke: NilPy re-parses a body (the module-local
    pre-pass trial-parses, def bodies are compiled from stored token
    positions), and the second pass met a '[' whose ']' had been overwritten.

    Only a LITERAL list splices: unpacking a variable needs its length at
    compile time, so `f(*xs)` still walls at the '*' rather than quietly
    passing one argument. }
  if isNilPy and (CurTok.Kind = tkStar) and (TokPos < TokCount) and
     (Tokens[TokPos].Kind = tkLBrack) then
  begin
    Next;                              { consume '*' }
    Next;                              { consume '[' }
    Inc(PyStarSpliceDepth);
  end;
  ParseSimpleExpr;
  { `X is T` / `X as T` — is/as are contextual identifiers (not reserved tokens),
    treated as operators only when followed by a known class name, so a stray
    identifier is never hijacked. Parser-resolved into their own AST nodes (per
    the and/or lesson: never key behaviour off a global flag). }
  { `E is <class-reference VALUE>` -- the class to test against is only known at
    runtime: a TClass variable, param, or field (fpcunit's
    `if not (E is FExpectedException)`, where FExpectedException: TClass is a field).

    AN_IS_TEST carries a compile-time class INDEX, so it cannot express this. But the
    test is exactly InheritsFrom on the instance's blob:

        E is cr   ==   __pxxInheritsFrom(rtti_of(E), cr)

    which is the operation already built for `x.InheritsFrom(C)`. Recognised only when
    the right-hand ident is a class-reference-typed symbol or field -- a known class
    NAME still takes the compile-time path above, and anything else leaves `is` alone. }
  if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'is') and
     (not PyExprMode) and
     (TokPos < TokCount) and (Tokens[TokPos].Kind = tkIdent) and
     (FindUClass(GetTokenStr(TokPos)) < 0) and
     IdentIsClassRefValue(GetTokenStr(TokPos)) and
     (FindProc('__pxxInheritsFrom') >= 0) then
  begin
    Next;                       { consume 'is' }
    left := CurASTNode;
    node := GenMakeRttiOfCall(left);            { the instance's runtime class }
    ParseFactor;                                { the class-reference operand }
    right := CurASTNode;
    isci := FindProc('__pxxInheritsFrom');
    isNode := AllocNode(AN_CALL);
    ASTIVal[isNode] := isci;
    ASTTk[isNode] := Ord(tyBoolean);
    isArg := AllocNode(AN_ARG);
    ASTLeft[isArg] := node;
    ASTLeft[isNode] := isArg;
    isArg2 := AllocNode(AN_ARG);
    ASTLeft[isArg2] := right;
    ASTRight[isArg] := isArg2;
    LastExprTk := tyBoolean;
    CurASTNode := isNode;
    Exit;
  end;

  { NOT under PyExprMode for `is`: Pascal's `E is TClass` is a TYPE test, but
    Python's `is` is IDENTITY and never a type test (`isinstance` is the type
    test, and has its own branch). This intercept sits in the SHARED ParseExpr
    and fired first, so NilPy's `x is K(2)` was read as the Pascal type test
    `x is K` — the constructor never ran, the trailing `(2)` was left behind,
    and the answer was True because x really is a K. Silent at module scope,
    a bare parse error inside a def, and INVISIBLE to a boolean-only test
    because `X() is Y()` is False either way — which is how it was filed as
    "a construction on the right of is does not parse".
    `is not` was unaffected (this pattern does not match it), which is what
    made the two shapes look unrelated.
    bug-nilpy-construction-on-the-right-of-is-does-not-parse }
  if (CurTok.Kind = tkIdent) and
     ((CaseEqual(CurTok.SVal, 'is') and (not PyExprMode)) or
      CaseEqual(CurTok.SVal, 'as')) and
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
  if (CurTok.Kind = tkIn) and not PyExprMode then
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
    { ...and two DIFFERENT enum types have no common ordering either: `aColor = apple`
      compared TColor against TFruit's ordinal and quietly answered yes/no. Same
      identity, same ident-level limits as the assignment check. }
    if (NodeEnumIdOf(left) >= 0) and (NodeEnumIdOf(right) >= 0) and
       (NodeEnumIdOf(left) <> NodeEnumIdOf(right)) then
      Error('cannot compare enum type ' +
            GetTokenStrFromRaw(EnumTypeNOff[NodeEnumIdOf(left)], EnumTypeNLen[NodeEnumIdOf(left)]) +
            ' with enum type ' +
            GetTokenStrFromRaw(EnumTypeNOff[NodeEnumIdOf(right)], EnumTypeNLen[NodeEnumIdOf(right)]));
    { FPC range-based constants: a NON-NEGATIVE literal compared against an
      UNSIGNED operand compares UNSIGNED — retag the literal so codegen's
      TypeCompareUnsigned sees two unsigned operands. Without this
      `q > $f0000000` (literal widened to tyInt64 at parse) compared signed
      and a qword >= 2^63 answered wrong (tint642 family). This read
      `= tyUInt64` for years, i.e. it fixed the 8-byte arm of a rule that
      applies at every width; it is the same normalisation `div`/`mod` needs,
      so both now call the one helper. }
    NormalizeUnsignedLiteralOperand(left, right);
    NormalizeUnsignedLiteralOperand(right, left);
    if PyExprMode and (op in [tkEq, tkNeq]) and
       PyNodeIsPyBytes(left) and PyNodeIsPyBytes(right) then
    begin
      { bytes VALUE equality (`raw == b""`): the class-pair fallthrough
        compared POINTERS, which is Python-wrong for bytes }
      node := PyMakeBytesBinCall('pybytes_eq', left, right, tyBoolean);
      if op = tkNeq then
      begin
        left := AllocNode(AN_NOT);
        ASTLeft[left] := node;
        ASTTk[left] := Ord(tyBoolean);
        node := left;
      end;
      CurASTNode := node;
      Exit;
    end;
    { A user class that defines `__eq__` is compared BY IT — Python's own rule,
      and the same shape as PyStrOfValue dispatching `__str__`. Without it `==`
      fell through to a pointer compare, so `V(1) == V(1)` was False with the
      method sitting right there unused, and `!=` was wrong from the same cause.
      The failure direction is the bad one: two equal values report unequal, so
      a membership test or an `if got == expected` takes the wrong branch
      silently (bug-nilpy-eq-dunder-ignored).

      `__lt__` and `__len__` already dispatched, so this is wiring rather than
      machinery. Built at AST level through PyCallMeth1, NOT as hand-rolled IR:
      the `other` parameter is normally unannotated, i.e. a by-reference
      variant, and a hand-built IR_ARG skips IRLowerCallArg
      (project_irlowercallarg_hand_built_args_landmine).

      The result keeps the METHOD's own return type rather than being forced to
      Boolean — the callee's ABI decides, and an annotated `-> bool` or an
      inferred boolean body both land there anyway. Non-virtual, exactly like
      the `__str__` dispatch: it resolves against the operand's static class. }
    { `!=` prefers a declared `__ne__`. CPython does NOT define `!=` as
      `not __eq__` when `__ne__` is present — it calls `__ne__`, whose result is
      returned as-is and need not even be a Boolean. Without this a class that
      deliberately breaks the symmetry (three-valued comparisons, NaN-like
      sentinels, "always unequal" wrappers) had its method silently ignored and
      got the negated `__eq__` instead (bug-nilpy-ne-dunder-ignored-always-
      negates-eq). The auto-derived case below stays: with only `__eq__`
      declared, CPython DOES derive `!=` as its negation, and that already
      matched. }
    { complex `==` / `!=` compares the two components. Without this the pair
      fell through to a reference compare, so `complex(1,2) == complex(1,2)`
      answered False -- two equal numbers by every Python rule, unequal here
      only because they were separate allocations. Either operand may be a
      real: `complex(2,0) == 2` is True in CPython. }
    if PyExprMode and (op in [tkEq, tkNeq]) and
       (PyNodeIsComplex(left) or PyNodeIsComplex(right)) then
    begin
      node := PyMakeComplexBinop(op, left, right);
      if node >= 0 then
      begin
        CurASTNode := node;
        Exit;
      end;
    end;
    if PyExprMode and (op = tkNeq) and
       (IntToTypeKind(ASTTk[left]) = tyClass) and
       (IntToTypeKind(ASTTk[right]) = tyClass) and
       (ResolveNodeRec(left) >= REC_UCLASS_BASE) and
       not PyRecIsPylibOwnClass(ResolveNodeRec(left)) and
       (FindUMeth(ResolveNodeRec(left) - REC_UCLASS_BASE, '__ne__') >= 0) then
    begin
      node := PyCallMeth1(ResolveNodeRec(left) - REC_UCLASS_BASE, '__ne__',
                          left, right);
      if node >= 0 then
      begin
        CurASTNode := node;
        Exit;
      end;
    end;
    if PyExprMode and (op in [tkEq, tkNeq]) and
       (IntToTypeKind(ASTTk[left]) = tyClass) and
       (IntToTypeKind(ASTTk[right]) = tyClass) and
       (ResolveNodeRec(left) >= REC_UCLASS_BASE) and
       (FindUMeth(ResolveNodeRec(left) - REC_UCLASS_BASE, '__eq__') >= 0) then
    begin
      node := PyCallMeth1(ResolveNodeRec(left) - REC_UCLASS_BASE, '__eq__',
                          left, right);
      if node >= 0 then
      begin
        if op = tkNeq then
        begin
          right := AllocNode(AN_NOT);
          ASTLeft[right] := node;
          ASTTk[right] := Ord(tyBoolean);
          node := right;
        end;
        CurASTNode := node;
        Exit;
      end;
    end;
    { ORDERING dunders — `<` `<=` `>` `>=` between two class instances. Without
      this the operands fell through to a raw POINTER compare, so `C(3) < C(1)`
      answered by allocation address with `__lt__` sitting right there unused —
      silent and wrong, the same failure family as the `__eq__` case above
      (measured: `a < b` -> True where CPython says False).

      CPython's rule, measured rather than assumed: try the DIRECT dunder on the
      left operand, else the REFLECTED partner on the right operand (`a > b`
      falls back to `b.__lt__(a)`, which is why a class defining only `__lt__`
      supports both `<` and `>`). Ordering has NO identity fallback the way `==`
      does — when neither exists CPython raises TypeError, so a runtime raise is
      the correct answer, not a pointer compare.

      Built through PyCallMeth1 at AST level for the reason the `__eq__` block
      records: the `other` parameter is normally an unannotated by-reference
      variant, and a hand-built IR_ARG would skip IRLowerCallArg
      (project_irlowercallarg_hand_built_args_landmine).

      pylib's OWN containers are excluded, and that exclusion is load-bearing: a
      TPyList is `tyClass` too, but it already compares LEXICOGRAPHICALLY further
      down (`[1,2] < [1,3]`). A first version without the guard captured lists
      here and, finding no `__lt__` on them, raised "comparison not supported" —
      turning working list comparison into a runtime abort
      (caught by test_nilpy_mixed_type_operands). Same exclusion the
      `__contains__` dispatch makes in pyparser.inc, for the same reason: a bare
      tyClass operand only means "genuine user object" AFTER pylib's own rows are
      ruled out. }
    if PyExprMode and (op in [tkLt, tkLe, tkGt, tkGe]) and
       (IntToTypeKind(ASTTk[left]) = tyClass) and
       (IntToTypeKind(ASTTk[right]) = tyClass) and
       (ResolveNodeRec(left) >= REC_UCLASS_BASE) and
       (ResolveNodeRec(right) >= REC_UCLASS_BASE) and
       not PyRecIsPylibOwnClass(ResolveNodeRec(left)) and
       not PyRecIsPylibOwnClass(ResolveNodeRec(right)) then
    begin
      case op of
        tkLt: begin ordDirect := '__lt__'; ordRefl := '__gt__'; end;
        tkLe: begin ordDirect := '__le__'; ordRefl := '__ge__'; end;
        tkGt: begin ordDirect := '__gt__'; ordRefl := '__lt__'; end;
        else  begin ordDirect := '__ge__'; ordRefl := '__le__'; end;
      end;
      ordLCi := ResolveNodeRec(left) - REC_UCLASS_BASE;
      ordRCi := ResolveNodeRec(right) - REC_UCLASS_BASE;
      node := -1;
      if FindUMeth(ordLCi, ordDirect) >= 0 then
        node := PyCallMeth1(ordLCi, ordDirect, left, right)
      else if FindUMeth(ordRCi, ordRefl) >= 0 then
        { reflected: the RIGHT operand is the receiver and the left the argument }
        node := PyCallMeth1(ordRCi, ordRefl, right, left);
      if node < 0 then
      begin
        { Neither dunder — a genuine RUNTIME TypeError (a try/except around it
          must still compile and run its handler), not a compile-time Error()
          that would abort the whole build. Same shape the `__contains__` miss
          uses in pyparser.inc. }
        ordErr := FindProc('PyNotOrderableError');
        if ordErr < 0 then Error('Nil Python: pylib (PyNotOrderableError) not loaded');
        node := AllocNode(AN_CALL);
        ASTIVal[node] := ordErr;
        ASTTk[node] := Ord(tyBoolean);
        ASTLeft[node] := -1;
      end;
      CurASTNode := node;
      Exit;
    end;
    { `3 == "ab"` — a STRING compared with a NUMBER under ==/!=. In Python that
      is simply False (True for !=): objects of different types are unequal, it
      is not an error. Here it reached the string comparison with the NUMBER as
      the string handle and dereferenced 3 as a pointer, so the one-liner
      `print(3 == "ab")` SEGFAULTED (bug-nilpy-int-equals-string-segfaults).
      A string against a bool, a class handle or None crashed the same way.

      Answered at parse time, since both static types are known: a `str` is
      equal only to a `str`. PyEqDisjointFromString (symtab.inc) says which
      types qualify and, more importantly, which do not — tyChar (a
      one-character literal can carry it, so `"a" == c` must stay a real
      comparison) and tyVariant (not known until run time).

      The operands are still EVALUATED, through a right-nested comma, because
      `f() == "x"` must still call f. Folding to a bare literal would have
      dropped the call. Ordering comparisons (`3 < "ab"`) are a different
      question — Python raises TypeError there — and are left to
      decide-nilpy-mixed-type-operand-policy. }
    if PyExprMode and (op in [tkEq, tkNeq]) and
       ((IntToTypeKind(ASTTk[left]) in [tyString, tyAnsiString, tyShortString, tyFixedString]) <>
        (IntToTypeKind(ASTTk[right]) in [tyString, tyAnsiString, tyShortString, tyFixedString])) and
       (PyEqDisjointFromString(IntToTypeKind(ASTTk[left])) or
        PyEqDisjointFromString(IntToTypeKind(ASTTk[right]))) then
    begin
      node := AllocNode(AN_BOOL_LIT);
      ASTIVal[node] := Ord(op = tkNeq);
      ASTTk[node] := Ord(tyBoolean);
      chSeq := AllocNode(AN_COMMA);
      ASTLeft[chSeq] := right;
      ASTRight[chSeq] := node;
      ASTTk[chSeq] := Ord(tyBoolean);
      node := AllocNode(AN_COMMA);
      ASTLeft[node] := left;
      ASTRight[node] := chSeq;
      ASTTk[node] := Ord(tyBoolean);
      CurASTNode := node;
      Exit;
    end;
    node := AllocNode(AN_BINOP); ASTIVal[node] := Ord(op); ASTLeft[node] := left; ASTRight[node] := right;
    ASTTk[node] := Ord(tyBoolean); CurASTNode := node;

    { Python COMPARISON CHAINING: `0 <= i < n` means `(0 <= i) and (i < n)` with
      the middle operand evaluated ONCE. That single evaluation is why it cannot
      be desugared by repeating the token text — `a < f() < b` would call f
      twice (feature-nilpy-comparison-chaining). Anything but a plain
      ident/literal is bound to a hidden local first: an IR value node is a
      SUBTREE, so referencing one twice RE-EMITS it. Pascal has no chained
      comparison (`a < b < c` is a type error there), so this is PyExprMode-only. }
    while PyExprMode and (CurTok.Kind in [tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe]) do
    begin
      if (ASTKind[right] = AN_IDENT) or (ASTKind[right] = AN_INT_LIT) or
         (ASTKind[right] = AN_FLOAT_LIT) then
        chMid := right
      else
      begin
        chSym := AllocVar('', IntToTypeKind(ASTTk[right]));
        chMid := AllocNode(AN_IDENT);
        ASTIVal[chMid] := chSym;
        ASTTk[chMid] := ASTTk[right];
        chAssign := AllocNode(AN_ASSIGN);
        ASTLeft[chAssign] := chMid;
        ASTRight[chAssign] := right;
        { (t := mid, t) — evaluate the middle operand once, yield the temp }
        chSeq := AllocNode(AN_COMMA);
        ASTLeft[chSeq] := chAssign;
        ASTRight[chSeq] := chMid;
        ASTTk[chSeq] := ASTTk[right];
        ASTRight[node] := chSeq;    { the FIRST comparison consumes the binding }
      end;
      op := CurTok.Kind; Next;
      ParseSimpleExpr;
      chRight := CurASTNode;
      chCmp := AllocNode(AN_BINOP);
      ASTIVal[chCmp] := Ord(op);
      ASTLeft[chCmp] := chMid;
      ASTRight[chCmp] := chRight;
      ASTTk[chCmp] := Ord(tyBoolean);
      chAnd := AllocNode(AN_BINOP);
      ASTIVal[chAnd] := Ord(tkAnd);
      ASTLeft[chAnd] := node;
      ASTRight[chAnd] := chCmp;
      ASTTk[chAnd] := Ord(tyBoolean);
      node := chAnd;
      right := chRight;
      CurASTNode := node;
    end;
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
    { tkSlashEq means DIFFERENT operators in different frontends, which is the
      trap here: NilPy's lexer emits it for `//=` (floor division — `/=` gets
      tkTrueDivEq), while Pascal and C emit it for `/=` (real division). Mapping
      it unconditionally to tkSlash made `self.n //= 3` perform TRUE division —
      25 //= 3 gave 8.333… instead of 8, silently
      (bug-nilpy-floor-div-assign-is-true-division).

      The ELSE is no longer a silent fallthrough to division either: that shape
      is exactly how this bug arrived, and it would have done the same for the
      next compound token added. }
    case op of
      tkPlusEq:  caBinTk := tkPlus;
      tkMinusEq: caBinTk := tkMinus;
      tkStarEq:  caBinTk := tkStar;
      tkSlashEq: if NilPyUserCode then caBinTk := tkDiv
                 else caBinTk := tkSlash;
      else       begin caBinTk := tkSlash;
                       Error('internal: unhandled compound-assignment operator'); end;
    end;
    caOp := Ord(caBinTk);
    { A NilPy VARIANT lvalue must NOT take the compound-assign node. That node
      computes the lvalue address once and does a scalar read-modify-write, which
      on a 16-byte variant slot reads the payload as a raw machine word: `self.n
      += 3` yielded True, `-=` an empty line and `*=` 4.94e-323 — the integer's
      bit pattern read as a double
      (bug-nilpy-augmented-assign-to-a-variant-typed-field-corrupts-it).

      This tail is documented as "inert for non-C code", and it is for Pascal —
      but NilPy's `+=` lexes to tkPlusEq too, and a DOTTED target (`self.n += 3`)
      reaches the expression parser before NilPy's own augmented-assignment path
      can see it. A field initialised from an UNANNOTATED ctor parameter is
      variant-typed, which is the most idiomatic constructor in Python, so this
      was the common case rather than a corner.

      Rewritten to the explicit `lv = lv <op> rhs`, which is exactly what NilPy's
      own augmented path builds for a bare name and is measured correct — the
      binop goes through the variant-aware dispatch instead of a raw word
      update. `+` keeps the AUGADD mark so a variant holding a LIST still extends
      IN PLACE (bug-nilpy-augmented-add-on-variant-list-is-not-in-place).

      EITHER side, not just the lvalue: the mirror case is an INT field with a
      variant OPERAND (`def add(self, v): self.n += v`, v an unannotated
      parameter), where the raw update added the variant's low word read as a
      truthy 1 — `C(10).add(5)` returned 11
      (bug-nilpy-augmented-assign-of-a-variant-param-to-an-int-field-adds-one).
      Same missing conversion seen from the other end, and the same explicit
      rewrite fixes it; the binop's own typing then widens as it does for a
      written-out `self.n = self.n + v`. }
    { A NilPy target holding a USER CLASS instance takes neither the compound
      node nor the variant rewrite: `h.acc += 5` must call __iadd__ (or __add__
      and rebind), and with neither declared must RAISE. The raw read-modify-
      write added the two instance HANDLES and stored the sum into a class slot,
      so the field read back as 0 — silently, dunder never called
      (bug-nilpy-augmented-assign-to-a-class-typed-FIELD-silently-yields-zero).

      It lands HERE rather than in NilPy's own augmented path for the same
      reason the variant fix above does: a DOTTED target reaches this shared
      expression tail first, so pyparser's site never sees it. The helper is
      NilPy's (pyparser.inc) and returns -1 for anything that is not a user
      class, which keeps Pascal and C on their existing path. }
    caRhs := -1;
    { `h.xs += [3]` on a LIST-typed field is Python's in-place extend, the same
      rule bug-a-nilpy-list-augmented-add-segfaults established for a bare name.
      pyparser's augmented path carries that special case, but — again — only a
      bare name reaches it, so the dotted spelling fell through to the compound
      node, added the two list HANDLES and SEGFAULTED (measured against the
      pinned binary too: pre-existing, not a regression of the dunder work). }
    if NilPyUserCode and (caBinTk = tkPlus) and (PyNodeListCi(left) >= 0) then
    begin
      caRhs := PyCallMeth1(PyNodeListCi(left), 'extend', left, right);
      if caRhs < 0 then Error('Nil Python: pylib TPyList.extend not loaded');
    end;
    { `o.xs *= 2` / `d[k] *= 2` on a SEQUENCE is the REPEAT, not a multiply —
      see PyAugMulNode. Unlike the in-place `extend` above, the repeat is a
      VALUE, so it needs the store built around it. }
    if (caRhs < 0) and NilPyUserCode and (caBinTk = tkStar) then
    begin
      node := PyAugMulNode(left, right);
      if node >= 0 then
      begin
        { …unless the repeat was built IN PLACE, in which case the mutation IS
          the statement: storing the same handle back through this target
          released the list before the append ran and `h.xs *= 2` came out
          EMPTY, while the identical local was right. }
        if PyAugMulInPlace then
          caRhs := node
        else
        begin
          caRhs := AllocNode(AN_ASSIGN);
          ASTLeft[caRhs] := left;
          ASTRight[caRhs] := node;
        end;
      end;
    end;
    if (caRhs < 0) and NilPyUserCode then
      caRhs := PyAugClassDunderNode(left, caBinTk, right);
    if caRhs >= 0 then
      CurASTNode := caRhs
    else if NilPyUserCode and ((IntToTypeKind(ASTTk[left]) = tyVariant) or
                               (IntToTypeKind(ASTTk[right]) = tyVariant)) then
    begin
      node := AllocNode(AN_BINOP);
      ASTIVal[node] := caOp;
      ASTLeft[node] := left; ASTRight[node] := right;
      { WIDEN the two operand types, exactly as NilPy's own augmented path does
        for a bare name. Taking the lvalue's type instead makes an int-typed
        binop over a VARIANT operand, which reads the variant's 16-byte slot as
        a machine word and yields a pointer; taking tyVariant unconditionally
        would box the result into a scalar field. The widen is what the written
        out `self.n = self.n + v` gets, and that spelling is measured correct. }
      ASTTk[node] := Ord(PyWiden(IntToTypeKind(ASTTk[left]),
                                 IntToTypeKind(ASTTk[right])));
      if (caOp = Ord(tkPlus)) and (IntToTypeKind(ASTTk[left]) = tyVariant) then
        ASTSLen[node] := PY_BINOP_AUGADD;
      caRhs := node;
      node := AllocNode(AN_ASSIGN);
      ASTLeft[node] := left; ASTRight[node] := caRhs;
      CurASTNode := node;
    end
    else
    begin
      node := AllocNode(AN_COMPOUND_ASSIGN);
      ASTLeft[node] := left; ASTRight[node] := right;
      ASTIVal[node] := caOp;
      ASTTk[node] := ASTTk[left];
      CurASTNode := node;
    end;
  end;
  { The closing ']' of a `*[...]` argument splice: the elements were handed to
    the caller's argument loop one comma at a time, and this is the token the
    loop would not know what to do with. Consumed by whichever ParseExpr call
    lands on it — the last element's. }
  if (PyStarSpliceDepth > 0) and (CurTok.Kind = tkRBrack) then
  begin
    Dec(PyStarSpliceDepth);
    Next;
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
procedure ParseArrayDimBounds(var lo, hi: Integer); forward;   { body sits with the const helpers }

function ConstEvalFactor: Int64;
{ Primary of a const expression: literal / true / false / single-char literal /
  named const / parenthesised expr / integer typecast. Unary +/- binds tightest
  (so -2*3 = -(2)*3 = -6 and 2*-3 = -6). No code emitted. }
var r: Int64; idx: Integer; castBytes: Integer; castSigned: Boolean;
    cName: AnsiString; cQUnit, ceOrd: Integer; hasConstCast, hlHigh: Boolean; sofTk: TTypeKind;
    ccBaseCi, ccReg: Integer;
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
  else if (CurTok.Kind = tkIdent) and
          (CaseEqual(CurTok.SVal, 'ord') or CaseEqual(CurTok.SVal, 'succ') or
           CaseEqual(CurTok.SVal, 'pred')) and
          (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
  begin
    { Ord(x)/Succ(x)/Pred(x) as compile-time constants
      (compat-pascal-const-expr-ord-chr-succ): `case KeyCode of Ord('q'): ...`
      is the ordinary way to write a key handler and none of these folded, so
      it had to be spelled as a bare numeric literal with a comment instead.
      This evaluator already represents every ordinal value (char, enum,
      bool) as a bare Int64 — a char literal folds to its own ordinal via the
      tkString branch above, an enum member via the TEnum.member branch — so
      Ord(x) needs no conversion at all: it IS whatever x already evaluates
      to here. Succ/Pred are the same value +/-1, same as the runtime
      intrinsics. }
    cName := LowerCase(CurTok.SVal);
    Next; Expect(tkLParen, '(');
    r := ConstEval();
    Expect(tkRParen, ')');
    if cName = 'succ' then r := r + 1
    else if cName = 'pred' then r := r - 1;
  end
  else if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'chr') and
          (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
  begin
    { Chr(x): the inverse of Ord above, and for the same reason a no-op on the
      underlying Int64 value here — this evaluator has no separate
      char/integer representation, only the eventual type annotation on the
      const/case-label distinguishes them. }
    Next; Expect(tkLParen, '(');
    r := ConstEval();
    Expect(tkRParen, ')');
  end
  else if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'length') and
          (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) and
          (TokPos + 1 < TokCount) and (Tokens[TokPos + 1].Kind = tkString) then
  begin
    { Length('literal') as a compile-time constant — the only const-foldable
      shape (a variable's length is not known until runtime, and this
      evaluator has no string representation beyond a literal's own token).
      Only entered when the very next token IS a string literal, so
      Length(someConstStringVariable) falls through to the ordinary "not a
      constant" diagnostic below rather than being silently mishandled. }
    Next; Expect(tkLParen, '(');
    r := Length(CurTok.SVal);
    Next;
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
    { A bare scalar class const in a const context — a sibling reference while the
      class body is still being parsed (`const B = A + 1`) or a class const used in
      a method's const expression. The backing lives under a mangled key, so the
      bare FindSym above misses it; recover it via the class-const registry.
      bug-pascal-class-const-visibility. }
    if (cQUnit < 0) and (idx < 0) then
    begin
      ccBaseCi := -1;
      if ParsingClassConstCi >= 0 then ccBaseCi := ParsingClassConstCi
      else if CurMethClass >= REC_UCLASS_BASE then ccBaseCi := CurMethClass - REC_UCLASS_BASE;
      if ccBaseCi >= 0 then
      begin
        ccReg := FindClassConst(ccBaseCi, cName);
        if ccReg >= 0 then idx := FindSym(ClassConstMangle(ClassConstCi[ccReg], cName));
      end;
    end;
    if (idx >= 0) and (Syms[idx].Kind = skConst) then
      r := Syms[idx].ConstVal
    else
      { compat-pascal-const-expr-ord-chr-succ: this used to dump raw lexer
        token state (line/kind/offset for a 10-token window) to stderr before
        erroring — internal debugging output that leaked onto every failing
        const expression, not just this fold's own development. The error
        message alone already names the offending token. }
      Error('not a constant');
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

{ ===== REAL-valued constant expressions =====

  ConstEval above is integer-only, and for a long time the only real a const
  section could hold was a bare literal token recognised by its FIRST token.
  Everything else went to the integer evaluator, which produced four distinct
  wrongs from the one gap (bug-p-const-expressions-are-integer-only):

    const A = 3.14; B = A;        -> B printed 4614253070214989087 (the IEEE
                                     bits, read as an integer). SILENT.
    const A: double = 3;          -> 0.00  (integer 3 stored where bits go)
    const A: double = -3;         -> Nan
    const TwoPi = 3.14 * 2;       -> "unexpected token" at the `*`

  So: a parallel evaluator over Double, entered only when the expression is
  provably real (ConstExprIsFloat). When it is not, the integer path runs
  exactly as before -- which is what keeps every existing const byte-identical. }

function ConstEvalF: Double; forward;

function ConstSymIsFloat(idx: Integer): Boolean;
begin
  ConstSymIsFloat := (idx >= 0) and (Syms[idx].Kind = skConst) and
                     ((Syms[idx].TypeKind = tyDouble) or
                      (Syms[idx].TypeKind = tySingle) or
                      (Syms[idx].TypeKind = tyExtended));
end;

function ConstExprIsFloat: Boolean;
{ Lookahead from the CURRENT token over one const expression: is a real
  involved? A real literal, a `/` (real division always yields a real, so
  `6 / 3` is 2.0 and not 2), or a bare name that already resolves to a real
  const. Stops at the expression's terminator at paren depth 0.

  Deliberately conservative: a false answer costs nothing (the integer path is
  unchanged), a true answer only routes to an evaluator that also handles pure
  integers. Bare names only -- a qualified `unit.RealConst` falls through to the
  integer path and its old behaviour rather than resolving units in lookahead. }
var i, depth: Integer; k: TTokenKind;
begin
  ConstExprIsFloat := False;
  i := TokPos - 1;   { CurTok is Tokens[TokPos-1] }
  depth := 0;
  while i < TokCount do
  begin
    k := Tokens[i].Kind;
    if (k = tkLParen) or (k = tkLBrack) then Inc(depth)
    else if (k = tkRParen) or (k = tkRBrack) then
    begin
      if depth = 0 then Exit;
      Dec(depth);
    end
    else if depth = 0 then
    begin
      if (k = tkSemicolon) or (k = tkComma) or (k = tkEq) then Exit;
    end;
    if k = tkFloat then begin ConstExprIsFloat := True; Exit; end;
    if k = tkSlash then begin ConstExprIsFloat := True; Exit; end;
    if (k = tkIdent) and
       ConstSymIsFloat(FindSym(GetTokenStrFromRaw(Tokens[i].SOffset, Tokens[i].SLen))) then
      begin ConstExprIsFloat := True; Exit; end;
    Inc(i);
  end;
end;

function ConstEvalFFactor: Double;
{ Primary of a real const expression: unary +/-, a real or integer literal, a
  named const (real -> its bits decoded, integer -> widened), parens. }
var r: Double; idx: Integer;
begin
  r := 0;
  { NB: the parens on the recursive call are required -- a bare own function
    name reads the Result var instead of recursing (project note:
    bare-funcname-is-Result). }
  if CurTok.Kind = tkMinus then begin Next; ConstEvalFFactor := -ConstEvalFFactor(); Exit; end;
  if CurTok.Kind = tkPlus  then begin Next; ConstEvalFFactor :=  ConstEvalFFactor(); Exit; end;
  if CurTok.Kind = tkFloat then
  begin
    r := ExDecBitsToDouble(CurTok.IVal); Next;
  end
  else if CurTok.Kind = tkInteger then
  begin
    r := CurTok.IVal; Next;
  end
  else if CurTok.Kind = tkLParen then
  begin
    Next; r := ConstEvalF(); Expect(tkRParen, ')');
  end
  else if (CurTok.Kind = tkIdent) and ConstSymIsFloat(FindSym(CurTok.SVal)) then
  begin
    idx := FindSym(CurTok.SVal);
    r := ExDecBitsToDouble(Syms[idx].ConstVal);
    Next;
  end
  else
    { Anything this evaluator does not model itself -- SizeOf, Ord/Chr/Succ, an
      integer typecast, an enum member, a unit-qualified or class const -- is an
      INTEGER factor, so hand the same token to the integer evaluator and widen
      its result. ConstEvalFactor and not ConstEval: a factor keeps the
      precedence, where a full expression would swallow the `* 2.5` after it. }
    r := ConstEvalFactor;
  ConstEvalFFactor := r;
end;

function ConstEvalFTerm: Double;
{ Multiplicative level: `*` and `/`. `div`/`mod` are integer operators and are
  deliberately absent -- an expression containing one is not routed here. }
var r, v: Double; op: TTokenKind;
begin
  r := ConstEvalFFactor;
  while (CurTok.Kind = tkStar) or (CurTok.Kind = tkSlash) do
  begin
    op := CurTok.Kind; Next; v := ConstEvalFFactor;
    if op = tkStar then r := r * v
    else
    begin
      if v = 0 then Error('division by zero in a constant expression');
      r := r / v;
    end;
  end;
  ConstEvalFTerm := r;
end;

function ConstEvalF: Double;
{ Additive level: + and -, left-associative. }
var r, v: Double; op: TTokenKind;
begin
  r := ConstEvalFTerm;
  while (CurTok.Kind = tkPlus) or (CurTok.Kind = tkMinus) do
  begin
    op := CurTok.Kind; Next; v := ConstEvalFTerm;
    if op = tkPlus then r := r + v else r := r - v;
  end;
  ConstEvalF := r;
end;

{ Parse one constant initializer value (scalar). A float literal yields its IEEE
  754 bit pattern (carried as Int64, same as AN_FLOAT_LIT); everything else goes
  through the integer ConstEval. Lets a `Double` initializer like 3.14 work. }
function ParseInitVal: Int64;
begin
  { Anything real -- a bare literal, a signed literal (the lexer emits the sign
    as its own token), or a whole expression like `3.14 * 2`, `1 / 3` or an
    alias of a real const -- goes through the real evaluator and yields IEEE
    bits. One path, so `= -2.5` and `= 2.5 * -1` cannot disagree. }
  if ConstExprIsFloat then Result := ExDecDoubleToBits(ConstEvalF())
  else Result := ConstEval;
end;

function ParseInitValTk(tk: TTypeKind): Int64;
{ ParseInitVal where the DESTINATION type is known. A real destination always
  yields IEEE bits, so `const A: Double = 3` stores 3.0 rather than the integer
  3 -- which read back as 0.00, and as Nan for `= -3`. }
begin
  if TypeIsFloat(tk) then ParseInitValTk := ExDecDoubleToBits(ConstEvalF())
  else ParseInitValTk := ParseInitVal;
end;

{ Recognise the constant-initializer value forms that are NOT plain ordinals, so
  a record-constant field can carry them: a string literal, `@proc`, and `@var`.
  ConstEval cannot evaluate any of these -- and, crucially, does not CONSUME them
  either, so letting one reach ParseInitValTk desyncs the field loop and the next
  iteration reports `expected field name in record constant` pointing at the
  value rather than at the real gap (that misleading message is what this exists
  to prevent).

  The three shapes map onto init kinds the emitter ALREADY implements -- 1 =
  AN_STR_LIT, 2 = AN_PROCADDR, 4 = AN_ADDR of an ident -- which the C frontend
  has been producing for struct initializers all along; only the Pascal side was
  never wired to them. Kinds 1/2/4 leave FOff untouched, so they compose with the
  record-field target the emitter builds when FOff >= 0.

  Returns True and sets kind/val/aux with the tokens consumed; returns False with
  NOTHING consumed, so the caller falls through to the ordinal path unchanged. }
function TryParseInitValForm(tk: TTypeKind; var kind: Integer; var val: Int64; var aux: Integer): Boolean;
var pi, si, ci, mi: Integer;
begin
  TryParseInitValForm := False;
  kind := 0; val := 0; aux := 0;

  { The string arm keys on the DESTINATION type, not on the token: a single-char
    literal in a tyChar field is an ORDINAL, and ConstEvalFactor special-cases it
    as one. Taking it as a string here compiled fine and stored the wrong bytes —
    `C: Char = 'Z'` printed garbage (test_typed_const_record). Same hazard the
    array-of-record path documents a few hundred lines below; it is the token
    being ambiguous, so only the target can decide. }
  if (CurTok.Kind = tkString) and
     (TypeIsFrozenString(tk) or (tk in [tyString, tyAnsiString, tyShortString])) then
  begin
    kind := 1;
    val  := Tokens[TokPos - 1].SOffset;
    aux  := Tokens[TokPos - 1].SLen;
    Next;
    TryParseInitValForm := True;
    Exit;
  end;

  { `@name` -- a link-time address. A routine wins over a variable of the same
    name here for the same reason MatchEligBase does: `@F` names the routine. }
  if (CurTok.Kind = tkAt) and (TokPos < TokCount) and (Tokens[TokPos].Kind = tkIdent) then
  begin
    { `@TClass.Method` -- the same raw code address the expression-level @ arm
      yields, so a hand-built VMT can be a CONSTANT rather than filled in at
      startup. This is the shape rtl-generics' Generics.Defaults uses. }
    if (TokPos + 2 < TokCount) and (Tokens[TokPos + 1].Kind = tkDot) and
       IsMethodNameTokAt(TokPos + 2) then
    begin
      ci := FindUClass(GetTokenStr(TokPos));
      if ci >= 0 then
      begin
        mi := FindUMeth(ci, GetTokenStr(TokPos + 2));
        if mi >= 0 then
        begin
          kind := 2; val := UMthProc_[mi];
          Next; Next; Next; Next;   { @ Class . Method }
          TryParseInitValForm := True;
          Exit;
        end;
      end;
    end;
    pi := FindProc(GetTokenStr(TokPos));
    if pi >= 0 then
    begin
      kind := 2; val := pi;
      Next; Next;
      TryParseInitValForm := True;
      Exit;
    end;
    si := FindSym(GetTokenStr(TokPos));
    if si >= 0 then
    begin
      kind := 4; val := si;
      Next; Next;
      TryParseInitValForm := True;
      Exit;
    end;
  end;
end;

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

