{ ===== pasparser_proc.inc — Pascal frontend: routine parsing =================

  Carved out of pasparser_*.inc, byte-for-byte, by
  refactor-a-carve-out-plexer-pparser-so-p-owns-its-own-files.

  Owned by Track P (Pascal frontend). Included from compiler.pas at exactly the
  point it used to occupy, so include ORDER is unchanged — that is what makes
  the carve-out provable by the self-host fixedpoint rather than by reading it.

  Contents: the procedure/function parser — signatures, calling conventions,
  overload and method resolution, the prologue/epilogue, routine-local typed
  consts, and the Pass-2 body walk.

  DO NOT factor anything here into a shared helper with pyparser.inc/cparser.inc.
  What is shared between frontends is the AST and the IR, never the parser:
  devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md }

{ Host soname discovery lives at the bottom of this file, next to the library
  table it replaced — but the `external 'lib.so'` parser near the top calls it.
  PXX resolves that itself; FPC does not, and the FPC seed canary is what caught
  it (bug-a-fpc-seed-drift-emitasmx64-forward is the same shape). }
function ResolveHostSoname(const unversioned: AnsiString): AnsiString; forward;

{ ===== Procedure/function parser ===== }

procedure CompilePendingLocalInits;
{ Emit the recorded routine-local typed-const initializers as assignments, at the
  current code position (the routine prologue, after managed-local zero-init and
  before the body). Mirror of CompilePendingGlobalInits over the LocalInit list;
  the list is reset by the caller at routine entry. }
var i, identNode, valNode, idxLit, target, assignNode, initTk: Integer;
    innerAddr: Integer;
begin
  { -O2 register-residency: suppress r14/r15 residency assignment for these
    per-initializer CompileAST calls. Each would otherwise re-emit the save+load
    (growing a fresh save slot) and desync the single epilogue restore, which then
    restores a param value over the caller's r14/r15. Residency is assigned once,
    at the main body, after these run. See bug-a-o2-miscompiles-disassembler. }
  RcSuppressAssign := True;
  for i := 0 to LocalInitCount - 1 do
  begin
    { Value kind, not storage kind — see the same line in
      CompilePendingGlobalInits for why a frozen string[N] element must be
      spelled tyString here. This is that bug's ROUTINE-LOCAL twin. }
    initTk := StrValTk(IntToTypeKind(LocalInitTk[i]));
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
      ASTTk[target] := initTk;
    end
    else if LocalInitElem[i] <> PI_ELEM_NONE then   { an index MAY be negative — see PI_ELEM_NONE }
    begin
      idxLit := AllocNode(AN_INT_LIT);
      ASTIVal[idxLit] := LocalInitElem[i];
      ASTTk[idxLit] := Ord(tyInteger);
      target := AllocNode(AN_INDEX);
      ASTLeft[target] := identNode;
      ASTRight[target] := idxLit;
      ASTTk[target] := initTk;
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
    else if LocalInitKind[i] = 2 then
    begin
      { `@proc` -- Val is the PROC index (same encoding as the global path's
        kind 2, deliberately: the two emitters must not drift). }
      valNode := AllocNode(AN_PROCADDR);
      ASTIVal[valNode] := LocalInitVal[i];
      ASTTk[valNode] := Ord(tyPointer);
    end
    else if LocalInitKind[i] = 4 then
    begin
      { `@var` -- Val is the SYM index; address-of that ident. }
      valNode := AllocNode(AN_IDENT);
      ASTIVal[valNode] := LocalInitVal[i];
      ASTTk[valNode] := Ord(Syms[LocalInitVal[i]].TypeKind);
      innerAddr := AllocNode(AN_ADDR);
      ASTLeft[innerAddr] := valNode;
      ASTTk[innerAddr] := Ord(tyPointer);
      valNode := innerAddr;
    end
    else
    begin
      valNode := AllocNode(AN_INT_LIT);
      ASTIVal[valNode] := LocalInitVal[i];
      ASTTk[valNode] := initTk;
    end;

    assignNode := AllocNode(AN_ASSIGN);
    ASTLeft[assignNode] := target;
    ASTRight[assignNode] := valNode;

    CompileAST(assignNode);
    ASTNodeCount := ASTArenaFloor;
  end;
  RcSuppressAssign := False;
  LocalInitCount := 0;
end;

{ FPC finalizes a MANAGED `out` parameter on entry — and only a managed one.
  Measured against fpc 3.2.2, `out v: Integer` and `out c: Char` behave exactly
  like `var` (the caller's value survives), `out s: ShortString` likewise (a
  shortstring is not managed), while `out` of an AnsiString, a dynamic array, an
  interface, a Variant or a managed record hands the callee an EMPTY value. That
  matters because a callee which assigns on only some paths otherwise returns the
  caller its own previous value, with no way to tell — the same silent
  stale-value shape as bug-a-a-failed-supports-left-the-out-interface-set.

  Emitted as an ordinary ASSIGNMENT of the empty value rather than as a new
  finalize-through-pointer emitter, which is the whole reason this is short: a
  managed assignment ALREADY releases the old value before storing the new one,
  and assigning through a by-ref parameter already stores into the CALLER. So
  "finalize on entry" is exactly `s := ''` / `d := nil` / `f := nil` written at
  the top of the body, and every backend gets it from paths it already has.
  (`d := nil` through a var param only started working in
  bug-a-a-whole-dynarray-assignment-to-a-var-parameter-is-discarded — this pass
  would have been silently inert on dynarrays before that.)

  Returns True when it emitted a clear. Variant and managed-record `out` params
  are NOT handled yet and are listed in the ticket: neither has an empty-value
  assignment to synthesise here (`v := Unassigned` renders as "None", not the
  empty FPC prints, and a record has no empty literal at all), so they need the
  finalize primitive this pass was written to avoid.
  bug-a-an-out-parameter-of-a-managed-type-is-not-cleared }
function ClearManagedOutParam(symIdx: Integer): Boolean;
var identNode, valNode: Integer;
begin
  Result := False;
  if symIdx < 0 then Exit;
  identNode := AllocNode(AN_IDENT);
  ASTIVal[identNode] := symIdx;
  ASTTk[identNode] := Ord(Syms[symIdx].TypeKind);
  if Syms[symIdx].IsArray and (Syms[symIdx].ArrLen = -1) then
  begin
    { dynamic array -> nil: releases the caller's handle, stores nil }
    valNode := AllocNode(AN_INT_LIT);
    ASTIVal[valNode] := 0;
    ASTTk[valNode] := Ord(tyPointer);
  end
  else if (Syms[symIdx].TypeKind = tyAnsiString) and not Syms[symIdx].IsArray then
  begin
    valNode := AllocNode(AN_STR_LIT);
    ASTSOffset[valNode] := 0;
    ASTSLen[valNode] := 0;
    ASTTk[valNode] := Ord(tyString);
  end
  else if SymIsComInterface(symIdx) then
  begin
    { the fat pointer {IMT, instance} is zeroed by the interface := nil arm,
      which releases the old reference first }
    valNode := AllocNode(AN_INT_LIT);
    ASTIVal[valNode] := 0;
    ASTTk[valNode] := Ord(tyPointer);
  end
  else
    Exit;   { not managed, or a kind with no empty literal — see the note above }
  CompileAST(GenMakeAssign(identNode, valNode));
  Result := True;
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
            (CurTok.Kind = tkOverload) or IsCallConvDirectiveTok do
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

{ FPC's `class operator Initialize/Finalize` are MANAGEMENT operators: the
  compiler invokes them at a variable's LIFETIME events, not at an expression.
  So they are woven into the routine's body rather than dispatched from a call
  site:

    Initialize(v0); Initialize(v1); ...
    try BODY finally Finalize(v0); Finalize(v1); ... end;

  A desugar, deliberately, and not an extension of the managed-local cleanup:
  that cleanup is six per-target emitters deep, while `try..finally` already
  covers every way a routine can leave — falling off the end, `Exit`, an
  exception — on every target, which is exactly the guarantee a Finalize needs.
  One shape, no backend edit, right on xtensa the day it is right on x86-64.

  Order is FPC 3.2.2's, measured rather than assumed: BOTH lists run in
  DECLARATION order — a routine with x.n=1 and y.n=2 prints `fin 1` then
  `fin 2`, not the reverse a stack discipline would suggest.

  Deliberately NOT covered, each measured against FPC first: a function's
  Result slot (FPC does not initialize one either), and the slot is not zeroed
  before Initialize runs (FPC hands over raw memory — an ordinary Integer field
  still held $5A5A5A5A, only the managed fields were nil).

  GLOBALS are covered, wrapped around the main body (WrapMainBodyManagementOps)
  — and here we deliberately go PAST FPC 3.2.2, which initializes a record-typed
  global and then never finalizes it. Delphi's managed records do finalize
  globals, a Finalize that never runs is a leak by construction, and the whole
  point of the operator is the pairing; so the divergence is one FPC line
  missing, not one of ours too many.

  What is NOT reached is refused rather than left silent: an ARRAY of a managed
  record, and any record or class that merely CONTAINS one in a field, both of
  which FPC handles through recursive RTTI and this per-symbol desugar does not.
  feature-pascal-management-operators-nested-and-array }

{ Does this record type itself declare a management operator? }
function RecHasManagementOp(recId: Integer): Boolean;
begin
  Result := (recId <> REC_NONE) and
            ((FindOpOverload(OPK_INITIALIZE, Ord(tyRecord), recId) >= 0) or
             (FindOpOverload(OPK_FINALIZE, Ord(tyRecord), recId) >= 0));
end;

{ ...and does it CONTAIN one, at any depth, in a field? The depth cap is the
  cheap guard against a record graph that refers back to itself. }
function RecContainsManagementOp(recId, depth: Integer): Boolean;
var ci, i, base, cnt, frec: Integer;
begin
  { Only user records/classes can hold one: the builtin descriptors are the
    compiler's own TProc/TSymbol/..., which no user operator can name. }
  Result := False;
  if (recId < REC_UCLASS_BASE) or (depth > 8) then Exit;
  ci := recId - REC_UCLASS_BASE;
  base := UClsFBase[ci];
  cnt := UClsFCount[ci];
  for i := 0 to cnt - 1 do
    if IntToTypeKind(UFldTk[base + i]) = tyRecord then
    begin
      { UFldTk carries the ELEMENT kind, so an `array of TFoo` field lands here
        too — also unsupported, also refused. }
      frec := UFldRec_[base + i];
      if RecHasManagementOp(frec) or RecContainsManagementOp(frec, depth + 1) then
      begin
        Result := True;
        Exit;
      end;
    end;
end;

function WrapManagementOpsRange(loSym, hiSym, retSym: Integer; wantGlobal: Boolean;
                               bodyNode: Integer): Integer;
var i, ip, fp, callNode, headInit, tailInit, headFin, tailFin, newSeq, tryNode: Integer;
    isTarget: Boolean;
begin
  Result := bodyNode;
  headInit := -1; tailInit := -1; headFin := -1; tailFin := -1;
  for i := loSym to hiSym do
  begin
    if wantGlobal then isTarget := Syms[i].Kind = skGlobal
    else isTarget := Syms[i].Kind = skLocal;
    { Refuse the shapes the desugar cannot reach, rather than compile a variable
      whose declared invariant simply never runs. An array needs a loop and a
      nested field needs a path, both of which FPC gets free from recursive RTTI
      and this pass does not have. }
    if isTarget and (SymTR[i].RecId <> REC_NONE) and
       (Syms[i].TypeKind in [tyRecord, tyClass]) then
    begin
      if Syms[i].IsArray and RecHasManagementOp(SymTR[i].RecId) then
        Error('an array of a record with a management operator is not supported yet '
              + '(feature-pascal-management-operators-nested-and-array)');
      if RecContainsManagementOp(SymTR[i].RecId, 0) then
        Error('a field of a record with a management operator is not managed yet '
              + '(feature-pascal-management-operators-nested-and-array)');
    end;
    if isTarget and (Syms[i].TypeKind = tyRecord) and
       (not Syms[i].IsArray) and (i <> retSym) and
       (SymTR[i].RecId <> REC_NONE) then
    begin
      ip := FindOpOverload(OPK_INITIALIZE, Ord(tyRecord), SymTR[i].RecId);
      if ip >= 0 then
      begin
        callNode := GenMakeCall6(ip, tyUnknown, GenMakeIdent(i, tyRecord),
                                 -1, -1, -1, -1, -1);
        newSeq := GenMakeSeq(callNode, -1);
        if headInit = -1 then headInit := newSeq else ASTRight[tailInit] := newSeq;
        tailInit := newSeq;
      end;
      fp := FindOpOverload(OPK_FINALIZE, Ord(tyRecord), SymTR[i].RecId);
      if fp >= 0 then
      begin
        callNode := GenMakeCall6(fp, tyUnknown, GenMakeIdent(i, tyRecord),
                                 -1, -1, -1, -1, -1);
        newSeq := GenMakeSeq(callNode, -1);
        if headFin = -1 then headFin := newSeq else ASTRight[tailFin] := newSeq;
        tailFin := newSeq;
      end;
    end;
  end;
  if (headInit = -1) and (headFin = -1) then Exit;
  if headFin >= 0 then
  begin
    tryNode := AllocNode(AN_TRY_FINALLY);
    ASTLeft[tryNode] := bodyNode;
    ASTRight[tryNode] := headFin;
    Result := tryNode;
  end;
  if headInit >= 0 then
  begin
    ASTRight[tailInit] := GenMakeSeq(Result, -1);
    Result := headInit;
  end;
end;

{ A routine's own locals. }
function WrapManagementOps(procIdx, bodyNode: Integer): Integer;
begin
  if procIdx < 0 then Result := bodyNode
  else Result := WrapManagementOpsRange(Procs[procIdx].ScopeBase, SymCount - 1,
                                        Procs[procIdx].RetSymIdx, False, bodyNode);
end;

{ The program's GLOBALS, wrapped around the main body — same lifetime rule one
  scope up. Every skGlobal is in range, not just the program's own: a unit that
  declares a variable of such a record has the same claim on its Initialize, and
  the pass is one walk of the symbol table. }
function WrapMainBodyManagementOps(bodyNode: Integer): Integer;
begin
  Result := WrapManagementOpsRange(0, SymCount - 1, -1, True, bodyNode);
end;

procedure ParseSubroutine;
var
  pzi      : Integer;  { pFixedLen/pFixedLo entry-zero loop }
  nonGenCi : Integer;  { ordinary class sharing a generic template's name }
  isFunc   : Boolean;
  name     : AnsiString;
  retType  : TTypeKind;
  tk       : TTypeKind;
  pnames    : array[0..MAX_PROC_PARAMS-1] of AnsiString;
  ptypes    : array[0..MAX_PROC_PARAMS-1] of TTypeKind;
  ptypesRec : array[0..MAX_PROC_PARAMS-1] of Integer;
  ptypesSetEnum : array[0..MAX_PROC_PARAMS-1] of Integer;  { `set of TEnum` param: element enum index, -1 otherwise }
  ptypesPtrElemTk : array[0..MAX_PROC_PARAMS-1] of TTypeKind;
  ptypesPtrElemRec : array[0..MAX_PROC_PARAMS-1] of Integer;
  ptypesProcSig : array[0..MAX_PROC_PARAMS-1] of Integer;  { proc-typed param: signature index, -1 otherwise }
  parr      : array[0..MAX_PROC_PARAMS-1] of Boolean;
  pbyref    : array[0..MAX_PROC_PARAMS-1] of Boolean;
  pconst    : array[0..MAX_PROC_PARAMS-1] of Boolean;  { param declared `const` (read-only by-ref) — lets a temporary bind to it }
  pout      : array[0..MAX_PROC_PARAMS-1] of Boolean;  { param declared `out` rather than `var`. The two are the same by-REFERENCE mechanism and pxx modelled them as one token arm for years, which is correct for every ordinal — FPC treats an `out Integer` exactly like a `var Integer`, measured. It is wrong for a MANAGED type: FPC finalizes an `out AnsiString`/dynarray/interface/Variant/managed-record on entry, so a callee that assigns on only some paths hands back the empty value rather than the caller's previous one. bug-a-an-out-parameter-of-a-managed-type-is-not-cleared }
  puntyped  : array[0..MAX_PROC_PARAMS-1] of Boolean;  { param declared untyped (var/const/out, no type) — matches any arg type, address passed }
  pdefault  : array[0..MAX_PROC_PARAMS-1] of Boolean;  { param has a default value (`b: Integer = 10`) }
  pdefaultval : array[0..MAX_PROC_PARAMS-1] of Int64;  { the constant-folded default ordinal }
  pdefaultisstr : array[0..MAX_PROC_PARAMS-1] of Boolean;  { ...or a string literal (`s: string = ''`) }
  pdefaultisfloat : array[0..MAX_PROC_PARAMS-1] of Boolean;  { ...or a FLOAT literal (`d: Double = 2.5`): pdefaultval holds its IEEE 754 bits }
  pdefaultisset : array[0..MAX_PROC_PARAMS-1] of Boolean;  { ...or a SET (`o: TOpts = []`): pdefaultval holds the baked mask's Data[] offset }
  pdefaultsoff : array[0..MAX_PROC_PARAMS-1] of Integer;
  pdefaultslen : array[0..MAX_PROC_PARAMS-1] of Integer;
  hasDefault : Boolean; defaultVal : Int64;
  defaultIsStr, defaultIsFloat : Boolean;
  defaultIsSet : Boolean; defaultSOff, defaultSLen : Integer;
  pNDims    : array[0..MAX_PROC_PARAMS-1] of Integer;
  pDynDepth : array[0..MAX_PROC_PARAMS-1] of Integer;  { named dynamic-array param: dyn nesting depth (>0), 0 = not a dyn-array param }
  pFixedLen : array[0..MAX_PROC_PARAMS-1] of Integer;
  pElemRowLen : array[0..MAX_PROC_PARAMS-1] of Integer; { open-array param `array of T`, T a named FIXED array: elements per row (0 = scalar element) }
  pElemRowLo  : array[0..MAX_PROC_PARAMS-1] of Integer; { the row's low bound }
  pFixedLo : array[0..MAX_PROC_PARAMS-1] of Integer; { named fixed-array param's LOW BOUND — dropped before, so a[1] on a var 1..3 param indexed off by lo (silent neighbour write; found by the {$R+} arc) }  { named FIXED 1-D array param: its real element count (0 = unknown/open — keep AllocParam's placeholder) }
  pDimLo    : array[0..95] of Integer;
  pDimSpan  : array[0..95] of Integer;
  paramNDims, paramDynDepth, paramAi, pdi, paramFixedLen, paramFixedLo: Integer;
  paramElemRowLen, paramElemRowLo: Integer;
  psLo, psSpan: array[0..MAX_ARR_DIMS-1] of Integer;
  nparams  : Integer;
  procIdx, helperPi, i, sz, retRecId, savedLastTypeRecId: Integer;
  zeroBytes : Integer;
  zfLoop, zfDone : Integer;
  retIsDynArr : Boolean; retElemTk : TTypeKind; retElemRec : Integer;
  retFixedArrBytes : Integer;   { a FIXED-array result's byte size; 0 = not one }
  retArrAi : Integer;           { its ArrType index, so the Result slot can be shaped like the type; -1 = not one }
  retPtrElemTk, retPtrElemRec : Integer;
  savedSC, savedFS, savedCurProc : Integer;
  savedGLC, savedGFC, j, savedVisVarSeq: Integer;
  cleanupJnePatch: Integer;
  patchPos : Integer;
  depth    : Integer;
  doneArgs, doneParam, isArr, isByRef, isConst, isOut, declOverload, declFlexColumn, isClassKeyword, isStaticMethod, declInline: Boolean;
  isUntyped : Boolean;
  needsProcCleanupFrame, savedProcCleanupFrameActive: Boolean;
  isAsmFunc: Boolean;
  preScanBody: Boolean;
  isGenerator, isStackless, isAsync: Boolean;
  isIram, isInterrupt: Boolean;
  sawIram, sawCdecl, sawRegister, sawStackful, sawReintroduce: Boolean;
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
  xtVReg, xtVReg2, xtInBias: Integer;  { xtensa: incoming param word -> register,
                                         and the frame bias of the stack args }
  methName: AnsiString;
  extLib: AnsiString;
  extSym: AnsiString;
  liftIdx, lcb: Integer;   { lambda-lift descriptor index / captured-param base }
  hdrStartSOff: Integer;   { require-forward: this header's source position }
begin
  { pFixedLen/pFixedLo are only written on the named-array param branch; the
    other branches leave stack garbage in the untouched slots, and the
    finalize loop reads them for EVERY param — a stale non-zero broke an
    open-array-of-record method param's low bound
    (test_record_method_open_array_b334). Zero them up front. }
  for pzi := 0 to MAX_PROC_PARAMS - 1 do
  begin
    pFixedLen[pzi] := 0;
    pFixedLo[pzi] := 0;
    pElemRowLen[pzi] := 0;
    pElemRowLo[pzi] := 0;
  end;
  { require-forward: the header's SOffset (stable under pass-2 token edits,
    like CurBodyHdrTok) becomes the routine's visibility boundary when the
    strict flag gates lookups. Captured at entry, at the procedure/function
    keyword itself. }
  if (TokPos - 1 >= 0) and (TokPos - 1 < TokCount) then
    hdrStartSOff := Tokens[TokPos - 1].SOffset
  else
    hdrStartSOff := 0;
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
    { A generic template and an ORDINARY class may share a name -- FPC's
      TDictionary alongside TDictionary<K,V>, and rtl-generics' THashService.
      The bare `X.M` header served by this branch is ALSO how the non-generic
      class's own method impl is written, so with both declared the header is
      ambiguous and matching on the name alone silently gave it to the template:
      the real class's body was buffered as generic-method tokens, never
      compiled, and surfaced far away as `unresolved forward: X.M`.

      Resolve it by asking which class actually DECLARES this method, rather
      than by the spelling -- the two are indistinguishable here by construction.
      A `X<T>.M` header never reaches this branch (CurTok would be '<', not '.'),
      so nothing is taken away from the generic side; when no ordinary class of
      the name exists, FindUClass fails and the behaviour is exactly as before. }
    if depth >= 0 then
    begin
      nonGenCi := FindUClass(name);
      if (nonGenCi >= 0) and (FindUMeth(nonGenCi, GetTokenStr(TokPos)) >= 0) then
        depth := -1;
    end;
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
      { A `ClassName.MethodName` impl header always implements a class declared
        in THIS unit -- Pascal has no syntax for implementing another unit's
        method from outside it. So the lookup must prefer a same-unit class,
        which used to be defeated by the `Exception` shared-name exemption
        (bug-pascal-uses-order-breaks-pylib-exception): pylib and sysutils both
        declared `Exception`, and FindUClass's flat first-match (needed so
        `except Exception:` kept working regardless of
        uses order) was also catching this header, so whichever unit registered
        second had its OWN constructor bodies bound to the OTHER unit's class
        -- e.g. pylib's `Exception.Create` resolving fields against sysutils'
        `Exception` and reporting them undefined. FindUClassInUnit sidesteps
        the shared-name bypass entirely; only fall back to the flat search for
        the (non-existent in practice, but harmless) case of no local match. }
      methOwnerCi := FindUClassInUnit(name, CurrentUnitIdx);
      if methOwnerCi < 0 then methOwnerCi := FindUClass(name);
      if methOwnerCi >= 0 then
      begin
        methOwnerRec := REC_UCLASS_BASE + methOwnerCi;
        Next; { consume dot }
        if not IsMethodNameTok then Error('expected method name');
        methName := GetTokenStr(TokPos - 1);   { keyword-token names carry no SVal }
        methSNOff := Tokens[TokPos-1].SOffset;
        methSNLen := Tokens[TokPos-1].SLen;
        Next; { consume method name }
        { `function touter.tinner.Tag: string;` — every qualifier before the last
          names a nested TYPE, i.e. a SCOPE, not a member, so descend through it
          and keep reading. This parser took exactly one qualifier and stopped,
          which made the out-of-line implementation of a nested class's method a
          parse error even though declaring it inline, naming the type and
          constructing it all worked. Loops, because nesting does; mirrors the
          `TOuter.TInner.Create` walk on the expression path.
          bug-p-a-nested-class-method-implementation-takes-only-one-qualifier }
        while (CurTok.Kind = tkDot) and (FindNestedType(methOwnerCi, methName) >= 0) do
        begin
          methOwnerCi := FindNestedType(methOwnerCi, methName);
          methOwnerRec := REC_UCLASS_BASE + methOwnerCi;
          AppendChar(name, '.');
          i := 1;
          while i <= Length(methName) do begin AppendChar(name, methName[i]); Inc(i); end;
          Next; { consume dot }
          if not IsMethodNameTok then Error('expected method name');
          methName := GetTokenStr(TokPos - 1);
          methSNOff := Tokens[TokPos-1].SOffset;
          methSNLen := Tokens[TokPos-1].SLen;
          Next; { consume method name }
        end;
        AppendChar(name, '.');
        i := 1;
        while i <= Length(methName) do begin AppendChar(name, methName[i]); Inc(i); end;
      end;
  end;

  nparams := 0; retType := tyInteger; retRecId := REC_NONE;
  { A local array is stack garbage until written, and the Self/capture insertion
    paths below fill some slots without going through the typed-param branch. }
  for i := 0 to MAX_PROC_PARAMS - 1 do ptypesSetEnum[i] := -1;
  retIsDynArr := False; retElemTk := tyUnknown; retElemRec := REC_NONE;
  retFixedArrBytes := 0; retArrAi := -1;
  retPtrElemTk := Ord(tyUnknown); retPtrElemRec := REC_NONE;

  if CurTok.Kind = tkLParen then
  begin
    Next;
    doneArgs := False;
    while (CurTok.Kind <> tkRParen) and not doneArgs do
    begin
      isByRef := False;
      isConst := False;
      isOut := False;
      hasDefault := False; defaultVal := 0;
      defaultIsStr := False; defaultIsFloat := False; defaultIsSet := False;
      defaultSOff := 0; defaultSLen := 0;
      if (CurTok.Kind = tkVar) or
         ((CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'out')) then
      begin
        isByRef := True;
        isOut := CurTok.Kind <> tkVar;   { `out` and `var` differ only for MANAGED types }
        Next;
      end
      else if IsConstParamTok then
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
        paramElemRowLen := 0; paramElemRowLo := 0;
        LastTypeRecId := REC_NONE; LastTypePointerElemTk := tyUnknown;
        LastTypePointerElemRec := REC_NONE; LastTypeProcSig := -1;
      end
      else
      begin
      Next;  { consume ':' }
      isArr := False;
      paramNDims := 0;
      paramDynDepth := 0;
      paramFixedLen := 0;
      paramFixedLo := 0;
      paramElemRowLen := 0;
      paramElemRowLo := 0;
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
        LastTypePointerElemRec := ArrTypePtrElemRec[paramAi];
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
        { Named FIXED array type param: remember how many elements it really has
          (Lo/Hi are the FLATTENED bounds, so this is the total for N-D too).
          AllocParam stamps ArrLen := 1000 on every array param — the open-array
          "length unknown" placeholder — and the whole-array assign path sizes
          its IR_COPY_REC from ArrLen. Without this, `r := tmp` where r is a
          `var r: TFixed` param copied 1000 elements over a 4-element array and
          smashed the caller's frame (bug-array-assign-to-var-param). A true
          open array (`array of T`) has no named type here and keeps the
          placeholder, which is correct: its length genuinely is not known. }
        if not ArrTypeIsDyn[paramAi] then
        begin
          paramFixedLen := ArrTypeHi[paramAi] - ArrTypeLo[paramAi] + 1;
          paramFixedLo := ArrTypeLo[paramAi];
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
        begin
          { open array whose element is a named FIXED array (`a: array of T`):
            the element is a whole ROW; ParseTypeKind would collapse T to its
            base scalar and the callee would index/copy with the base stride
            (bug-pascal-openarray-of-array-param-marshal). }
          paramAi := -1;
          if CurTok.Kind = tkIdent then paramAi := FindArrayType(CurTok.SVal);
          if (paramAi >= 0) and (not ArrTypeIsDyn[paramAi]) then
          begin
            tk := IntToTypeKind(ArrTypeElemTk[paramAi]);
            LastTypeRecId := ArrTypeElemRec[paramAi];
            LastTypePointerElemRec := ArrTypePtrElemRec[paramAi];
            if (tk = tyAnsiString) or (tk = tyString) or
               (tk = tyFixedString) or (tk = tyShortString) or
               ((tk = tyRecord) and RecordHasManagedFields(LastTypeRecId)) then
              Error('array of <fixed array of managed elements> not supported');
            paramElemRowLen := ArrTypeHi[paramAi] - ArrTypeLo[paramAi] + 1;
            paramElemRowLo  := ArrTypeLo[paramAi];
            Next;             { consume the named array type }
          end
          else
            tk := ParseTypeKind;
        end;
        isArr := True;
      end
      else
        tk := ParseTypeKind;
      { Default value: `b: Integer = 10`. Constant-folded; supplied at a call that
        omits the (trailing) argument. A STRING literal default (`s: string = ''`)
        is not an ordinal — keep its text and rebuild an AN_STR_LIT at the call. }
      if CurTok.Kind = tkEq then
      begin
        Next;
        ParseParamDefaultValue(tk, defaultVal, defaultIsStr, defaultIsFloat,
                               defaultIsSet, defaultSOff, defaultSLen);
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
        { LastTypeSetEnumId is only meaningful when the type just parsed WAS a
          set — it is not cleared for other kinds. }
        if tk = tySet then ptypesSetEnum[i] := LastTypeSetEnumId
        else ptypesSetEnum[i] := -1;
        ptypesPtrElemTk[i] := LastTypePointerElemTk;
        ptypesPtrElemRec[i] := LastTypePointerElemRec;
        ptypesProcSig[i] := LastTypeProcSig;
        parr[i] := isArr;
        pbyref[i] := isByRef;
        pconst[i] := isConst;
        pout[i] := isOut;
        pdefault[i] := hasDefault;
        pdefaultval[i] := defaultVal;
        pdefaultisstr[i] := defaultIsStr;
        pdefaultisfloat[i] := defaultIsFloat;
        pdefaultisset[i] := defaultIsSet;
        pdefaultsoff[i] := defaultSOff;
        pdefaultslen[i] := defaultSLen;
        pNDims[i] := paramNDims;
        pDynDepth[i] := paramDynDepth;
        pFixedLen[i] := paramFixedLen;
        pFixedLo[i] := paramFixedLo;
        pElemRowLen[i] := paramElemRowLen;
        pElemRowLo[i] := paramElemRowLo;
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
      retPtrElemRec := ArrTypePtrElemRec[paramAi];
    end
    else
    begin
      { A named FIXED-array result (`function F: TArr` where TArr =
        array[0..2] of Integer). ParseTypeKind answers the ELEMENT kind, so
        without recording the aggregate here the result looked like a plain
        Integer: no hidden destination was allocated, the callee returned
        element 0 in a register and the caller stored that one scalar —
        `a := MkArr` gave `8 0 0` where FPC gives `8 9 10`, silently.
        Measured against FPC, 2026-08-09.
        bug-a-set-and-array-function-results-come-back-empty }
      if (CurTok.Kind = tkIdent) and (FindArrayType(CurTok.SVal) >= 0) and
         not ArrTypeIsDyn[FindArrayType(CurTok.SVal)] then
      begin
        { The 32-bit pair does not carry it yet: measured, i386 and arm32 both
          fault on the hidden-destination call for an array result even with the
          whole path wired (arm32 faulted BEFORE this work too — the shape has
          never worked there). Refuse with a diagnostic rather than emit a call
          that crashes: on arm32 that replaces a SIGSEGV, and on i386 it says
          plainly what its old "arrays not yet supported" meant.
          bug-a-fixed-array-function-result-faults-on-i386-and-arm32 }
        paramAi := FindArrayType(CurTok.SVal);
        retArrAi := paramAi;
        { ArrTypeLo/Hi are the FLATTENED bounds for an N-D alias too (the type
          decl stores 0..prod(spans)-1), so this byte count covers both. }
        retFixedArrBytes := (ArrTypeHi[paramAi] - ArrTypeLo[paramAi] + 1) *
                            TypeSize(IntToTypeKind(ArrTypeElemTk[paramAi]));
      end;
      if retArrAi >= 0 then
      begin
        { An array-type alias is NOT in the scalar alias table, so ParseTypeKind
          falls through its unknown-name default and answers tyInteger. That is
          right by accident for `array of Integer` and wrong for every other
          element: `array[0..2] of string[8]` and `array[0..2] of TRec` both
          returned an Integer-strided Result, so the callee's own
          `MkR[2].a := 5` landed mid-element. Take the element type from the
          ArrType entry, as ParseVarSection does for a variable of the alias. }
        retType := IntToTypeKind(ArrTypeElemTk[retArrAi]);
        LastTypeRecId := ArrTypeElemRec[retArrAi];
        LastTypePointerElemRec := ArrTypePtrElemRec[retArrAi];
        if (retType = tyFixedString) or (retType = tyShortString) then
          LastTypeStrCap := ArrTypeElemStrCap[retArrAi];
        Next;   { consume the alias name ParseTypeKind would have eaten }
      end
      else
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
  sawIram := False; sawCdecl := False; sawRegister := False;
  sawStackful := False; sawReintroduce := False;
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
        (CurTok.Kind = tkOverload) or IsCallConvDirectiveTok do
  begin
    if CurTok.Kind = tkOverload then declOverload := True;
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'flexcolumn') then declFlexColumn := True;
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'assembler') then isAsmFunc := True;
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'generator') then isGenerator := True;
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'async') then isAsync := True;
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'stackless') then isStackless := True;
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'inline') then declInline := True;
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'iram') then
    begin isIram := True; sawIram := True; end;
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'cdecl') then sawCdecl := True;
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'register') then sawRegister := True;
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'stackful') then sawStackful := True;
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'reintroduce') then sawReintroduce := True;
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
  { --warn-ignored-directives: say so when a directive was accepted and then
    dropped, and say WHY. Silent by default — these are all legal FPC source and
    warning unconditionally would fire on every ordinary unit. Hint directives
    (deprecated/platform/...) are deliberately excluded: they are meant to be
    inert until usage warnings exist. }
  if WarnIgnoredDirectives and not PreScanPass then
  begin
    if sawIram and (TargetArch <> TARGET_XTENSA) and (TargetArch <> TARGET_RISCV32) then
      Warn('directive ''iram'' ignored here: IRAM placement exists on the ESP ' +
           'targets (xtensa, riscv32) only; this target has no separate ' +
           'instruction RAM to place ' + name + ' in');
    if sawCdecl then
      Warn('directive ''cdecl'' ignored here: the calling convention is the ' +
           'target''s and is not selectable per routine, so ' + name +
           ' already uses it; the marker is documentation only');
    if sawRegister then
      Warn('directive ''register'' ignored here: the calling convention is the ' +
           'target''s and is not selectable per routine');
    if sawStackful then
      Warn('directive ''stackful'' ignored here: it is the default strategy, ' +
           'so it selects nothing');
    if sawReintroduce then
      Warn('directive ''reintroduce'' ignored here: it only suppresses a ' +
           'hidden-method warning, which is not emitted');
    { `inline` is the one with real user value: ProcInline is written and never
      read, and the -O2 inliner decides purely on shape. Report only the causes
      that are knowable HERE, precisely — the body has not been parsed yet, so
      "your body is too complex" cannot be claimed without measuring it. }
    if declInline then
    begin
      if OptLevel < 2 then
        Warn('directive ''inline'' ignored here: inlining runs at -O2 and ' +
             'above, and this build is -O' + AIntToStr(OptLevel))
      else if not isFunc then
        Warn('directive ''inline'' ignored here: only a function with a scalar ' +
             'result is inlined, and ' + name + ' is a procedure')
      else if isAsmFunc or isGenerator or isAsync or isStackless then
        Warn('directive ''inline'' ignored here: an assembler/generator/async/' +
             'stackless routine is never inlined')
      else if nparams > 6 then
        Warn('directive ''inline'' ignored here: the inliner takes at most six ' +
             'by-value scalar parameters and ' + name + ' has ' +
             AIntToStr(nparams));
    end;
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
      pout[nparams] := False;
      pNDims[nparams] := 0; pDynDepth[nparams] := 0;
      pElemRowLen[nparams] := 0; pElemRowLo[nparams] := 0;
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
      pout[nparams] := False;
      pNDims[nparams] := 0;
      pDynDepth[nparams] := LiftCapDyn[lcb + i];
      pElemRowLen[nparams] := 0;
      pElemRowLo[nparams] := 0;
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
    { `external 'libfoo.so'` names a library the way source code always spells
      it — unversioned. The loader wants the versioned soname, and on a machine
      with only the runtime package installed the unversioned name does not
      exist at all. Ask the host; unchanged when it has no answer, and untouched
      for a spelling that is already versioned (feature-dynamic-soname-discovery). }
    if (Length(extLib) > 3) and (Copy(extLib, Length(extLib) - 2, 3) = '.so') then
      extLib := ResolveHostSoname(extLib);
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
    { Record the return-element metadata like the normal registration paths do —
      without this an external `function f(...): PAnsiChar` leaves ProcRetPtrElemTk
      at tyUnknown, so IsNodePChar can't tell f() returns a char pointer and
      `AnsiString(f(...))` silently mis-lowers (reads a bogus managed-string
      header). See bug-pascal-ansistring-cast-of-cdecl-call-result. }
    ProcRetIsDynArray[procIdx] := retIsDynArr;
  ProcRetFixedArrBytes[procIdx] := retFixedArrBytes;
  ProcRetArrAi[procIdx] := retArrAi;
    ProcRetElemTk[procIdx] := retElemTk;
    ProcRetElemRec[procIdx] := retElemRec;
    ProcRetPtrElemTk[procIdx] := retPtrElemTk;
    ProcRetPtrElemRec[procIdx] := retPtrElemRec;
    for i := 0 to nparams-1 do
    begin
      Procs[procIdx].Params[i].IsArray := parr[i];
      Procs[procIdx].Params[i].IsRef := pbyref[i];
      if (i < MAX_PROC_PARAMS) and ((ptypes[i] = tyClass) or (ptypes[i] = tyRecord)) then
        ProcParamRecId[procIdx * MAX_PROC_PARAMS + i] := ptypesRec[i];
      if (i < MAX_PROC_PARAMS) and (ptypes[i] = tySet) then
        ProcParamSetEnumId[procIdx * MAX_PROC_PARAMS + i] := ptypesSetEnum[i];
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

  { Every method gets a Self at index 0 -- including a STATIC (class) method, whose
    Self is the CLASS, not an instance. FPC's idiom depends on it being the RUNTIME
    class: `class function TAssert.Suite: TTest; begin Result := TTestSuite.Create(Self)`
    must see Self = TMyTest when called as TMyTest.Suite, not TAssert. Passing the
    statically-known class instead would compile and silently build the wrong suite,
    so the class is passed as a real argument. A class Self is a bare CLASS REFERENCE
    (tyPointer -> tyClass, no rec id) -- the same shape a TClass variable has, so
    ClassName / InheritsFrom / passing it to a TClass param all work on it unchanged. }
  if methOwnerCi >= 0 then
  begin
    for i := nparams downto 1 do
    begin
      pnames[i] := pnames[i-1];
      ptypes[i] := ptypes[i-1];
      ptypesRec[i] := ptypesRec[i-1];
      ptypesSetEnum[i] := ptypesSetEnum[i-1];
      ptypesPtrElemTk[i] := ptypesPtrElemTk[i-1];
      ptypesPtrElemRec[i] := ptypesPtrElemRec[i-1];
      ptypesProcSig[i] := ptypesProcSig[i-1];
      parr[i]   := parr[i-1];
      pbyref[i] := pbyref[i-1];
      { pconst shifts with the params like every other per-param array. It was
        the ONE omission here, so a method implementation's real `const`
        parameter was written into Self's (meaningless) slot and the parameter's
        own slot read stale data — ProcParamIsConst was misregistered for EVERY
        method impl with a const parameter, not just Variant ones.
        bug-a-const-variant-arg-expression-fails-outside-pyexprmode }
      pconst[i] := pconst[i-1];
      pout[i] := pout[i-1];   { shifts like pconst — see the note above it }
      pNDims[i] := pNDims[i-1];
      pDynDepth[i] := pDynDepth[i-1];
      pElemRowLen[i] := pElemRowLen[i-1];
      pElemRowLo[i] := pElemRowLo[i-1];
      { The default-value arrays shift with the params. Leaving them unshifted
        wrote each default onto the PREVIOUS param's slot, so a method impl that
        repeats its defaults silently gave `M(a: Integer = 1; b: Integer = 2)`
        a=2 on a defaulted call (bug-pascal-method-default-param-self-shift). }
      pdefault[i] := pdefault[i-1];
      pdefaultval[i] := pdefaultval[i-1];
      pdefaultisstr[i] := pdefaultisstr[i-1];
      pdefaultisfloat[i] := pdefaultisfloat[i-1];
      pdefaultisset[i] := pdefaultisset[i-1];
      pdefaultsoff[i] := pdefaultsoff[i-1];
      pdefaultslen[i] := pdefaultslen[i-1];
      for pdi := 0 to MAX_ARR_DIMS - 1 do
      begin
        pDimLo[i * MAX_ARR_DIMS + pdi]   := pDimLo[(i-1) * MAX_ARR_DIMS + pdi];
        pDimSpan[i * MAX_ARR_DIMS + pdi] := pDimSpan[(i-1) * MAX_ARR_DIMS + pdi];
      end;
    end;
    pnames[0] := 'Self';
    pconst[0] := False;   { Self is never a `const` parameter }
    pout[0] := False;     { ...nor an `out` one }
    if isStaticMethod and (methOwnerCi >= 0) and (UClsHelperTk[methOwnerCi] >= 0) then
    begin
      { a HELPER's `class function ...; static;`: Self = the target BY VALUE
        (dummy; static bodies may not use Self) — must agree with the decl }
      ptypes[0] := IntToTypeKind(UClsHelperTk[methOwnerCi]);
      ptypesRec[0] := UClsHelperRec[methOwnerCi];
      pbyref[0] := False;
    end
    else if isStaticMethod then
    begin
      { class method: Self is the metaclass -- a class reference }
      ptypes[0] := tyPointer;
      ptypesRec[0] := REC_NONE;
      pbyref[0] := False;
    end
    else if (methOwnerCi >= 0) and (UClsHelperTk[methOwnerCi] >= 0) then
    begin
      { TYPE HELPER method impl: Self = the target type by reference — must
        agree with the decl side's registration or the impl never binds. }
      ptypes[0] := IntToTypeKind(UClsHelperTk[methOwnerCi]);
      ptypesRec[0] := UClsHelperRec[methOwnerCi];
      pbyref[0] := True;
    end
    else if UClsIsRecord[methOwnerCi] then
    begin
      { An ADVANCED RECORD's method: Self is the RECORD, passed BY REFERENCE. Records are
        already carried by address in this IR, and a method must be able to mutate its
        receiver (`p.Offset(dx, dy)`), so by-ref is both natural and required — a
        by-value Self would mutate a copy and silently lose the write. }
      ptypes[0] := tyRecord;
      ptypesRec[0] := methOwnerRec;
      pbyref[0] := True;
    end
    else
    begin
      ptypes[0] := tyClass;
      ptypesRec[0] := REC_NONE;   { Self's RecName is wired to the owner class below }
      pbyref[0] := False;
    end;
    if isStaticMethod then
    begin
      { PtrElemTk = tyClass with no rec id IS the bare-class-reference shape. }
      ptypesPtrElemTk[0] := tyClass;
      ptypesPtrElemRec[0] := REC_NONE;
    end
    else
    begin
      ptypesPtrElemTk[0] := tyUnknown;
      ptypesPtrElemRec[0] := REC_NONE;
    end;
    ptypesProcSig[0] := -1;
    parr[0]   := False;
    pNDims[0] := 0;
    pDynDepth[0] := 0;
    pElemRowLen[0] := 0;
    pElemRowLo[0] := 0;
    pdefault[0] := False;
    pdefaultval[0] := 0;
    pdefaultisstr[0] := False;
    pdefaultisfloat[0] := False;
    pdefaultisset[0] := False;
    pdefaultsoff[0] := 0;
    pdefaultslen[0] := 0;
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
      ptypesSetEnum[i] := ptypesSetEnum[i-1];
      ptypesPtrElemTk[i] := ptypesPtrElemTk[i-1];
      ptypesPtrElemRec[i] := ptypesPtrElemRec[i-1];
      ptypesProcSig[i] := ptypesProcSig[i-1];
      parr[i]   := parr[i-1];
      pbyref[i] := pbyref[i-1];
      { pconst shifts with the params like every other per-param array. It was
        the ONE omission here, so a method implementation's real `const`
        parameter was written into Self's (meaningless) slot and the parameter's
        own slot read stale data — ProcParamIsConst was misregistered for EVERY
        method impl with a const parameter, not just Variant ones.
        bug-a-const-variant-arg-expression-fails-outside-pyexprmode }
      pconst[i] := pconst[i-1];
      pout[i] := pout[i-1];   { shifts like pconst — see the note above it }
      pNDims[i] := pNDims[i-1];
      pDynDepth[i] := pDynDepth[i-1];
      pElemRowLen[i] := pElemRowLen[i-1];
      pElemRowLo[i] := pElemRowLo[i-1];
      for pdi := 0 to MAX_ARR_DIMS - 1 do
      begin
        pDimLo[i * MAX_ARR_DIMS + pdi]   := pDimLo[(i-1) * MAX_ARR_DIMS + pdi];
        pDimSpan[i * MAX_ARR_DIMS + pdi] := pDimSpan[(i-1) * MAX_ARR_DIMS + pdi];
      end;
    end;
    pnames[0] := '__genself';
    pconst[0] := False;
    pout[0] := False;
    ptypes[0] := tyPointer;
    ptypesRec[0] := REC_NONE;
    ptypesPtrElemTk[0] := tyUnknown;
    ptypesPtrElemRec[0] := REC_NONE;
    ptypesProcSig[0] := -1;
    parr[0]   := False;
    pbyref[0] := False;
    pNDims[0] := 0;
    pDynDepth[0] := 0;
    pElemRowLen[0] := 0;
    pElemRowLo[0] := 0;
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
        if StrictOverload and (FindProc(name) >= 0) and not DialectIsPxx then
        begin
          { --strict-overload polices code that is NOT written in the pxx dialect:
            the user's own program, and external units like Synapse or fgl. Our
            own RTL and builtins declare `{$MODE PXX}` and are exempt, because
            they use undirectived overloads by design (override/overload freely —
            a first-class feature) and a command-line flag has no business
            re-judging already-written library code.

            This used to read `CurrentUnitIdx < 0`, i.e. "the main program", which
            exempted EVERY unit — ours and Synapse's alike — and policed only the
            one file that is not FPC code. Backwards for a parity flag: Synapse IS
            what --strict-fpc exists to check. An UNMARKED unit is policed, so the
            flag cannot go quietly weaker as the tree grows. }
          if not declOverload then Error('overloaded routine requires overload directive');
          if HasNonOverloadProc(name) then Error('all overloaded routines require overload directive');
        end;
        procIdx := RegisterProc(name, isFunc, retType, nparams, pnames, ptypes);
        { require-forward visibility stamp: only MAIN-program top-level headers
          registered by the pre-scan (or an explicit `forward;`) get a source
          position. Interface sections, units, methods, builtins and nested
          routines keep 0 = always visible — FPC's four visibility rules.
          Appended-unit tokens sit at HIGHER SOffsets than the program's, so
          stamping them would wrongly hide uses-imported routines. }
        if (not InInterface) and (CurrentUnitIdx < 0) then
          ProcHdrTok[procIdx] := hdrStartSOff;
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
            ProcParamDefaultIsStr[procIdx * MAX_PROC_PARAMS + i] := pdefaultisstr[i];
            ProcParamDefaultIsFloat[procIdx * MAX_PROC_PARAMS + i] := pdefaultisfloat[i];
            ProcParamDefaultIsSet[procIdx * MAX_PROC_PARAMS + i] := pdefaultisset[i];
            ProcParamDefaultSOff[procIdx * MAX_PROC_PARAMS + i] := pdefaultsoff[i];
            ProcParamDefaultSLen[procIdx * MAX_PROC_PARAMS + i] := pdefaultslen[i];
            if (ptypes[i] = tyClass) or (ptypes[i] = tyRecord) then
              ProcParamRecId[procIdx * MAX_PROC_PARAMS + i] := ptypesRec[i];
            if ptypes[i] = tySet then
              ProcParamSetEnumId[procIdx * MAX_PROC_PARAMS + i] := ptypesSetEnum[i];
          end;
        end;
      end
      else if declOverload then
        ProcOverloadDirective[procIdx] := True;
      if declFlexColumn then ProcFlexColumn[procIdx] := True;
      ProcRetRecId[procIdx] := retRecId;
      ProcRetIsDynArray[procIdx] := retIsDynArr;
  ProcRetFixedArrBytes[procIdx] := retFixedArrBytes;
  ProcRetArrAi[procIdx] := retArrAi;
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
  ProcRetFixedArrBytes[procIdx] := retFixedArrBytes;
  ProcRetArrAi[procIdx] := retArrAi;
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
    { STACKLESS: bounded by the step call's width, not by CoAlloc's packing }
    if (nparams - 1) > SL_MAX_PARAMS then
      Error('stackless generator: at most ' + AIntToStr(SL_MAX_PARAMS)
            + ' parameters in v1');
  end
  else if isGenerator and (nparams > CO_MAX_PARAMS) then
    Error('generator: at most 4 parameters in v1');
  if retIsDynArr then Procs[procIdx].RetType := tyPointer; { 8-byte heap handle ABI }
  if TargetArch = TARGET_XTENSA then
    while (CodeLen mod 4) <> 0 do xtensa_nop; { CALL0 targets must be 4-aligned }

  { REDEFINITION: a second body for a routine that already has one, declared in
    the SAME scope. Silently accepted until now, and the second body simply won
    -- except for calls placed BETWEEN the two, which bound to the first, so two
    identical call sites called different routines
    (bug-a-duplicate-definition-silently-accepted).

    It is a warning rather than an error deliberately: `write` grew a hardcoded
    version, then a builtin, and nothing ever rejected the leftover, so there may
    be duplicates in the tree that a hard error would turn into a broken build.
    Promote it once the tree is known clean (-Werror already promotes it).

    Both conditions matter and neither is optional:

      BodyAddr >= 0   -- the existing entry already has a BODY. A `forward`
                         declaration leaves it at -1, so forward+implementation
                         (the normal, legal pairing) does not warn.

      not CProcHasLocalDef -- the earlier body must not have come from the C
                         frontend. crtl deliberately overrides Pascal builtins
                         (malloc, memcpy, strtod, ...) with C versions of the
                         same name, which is design, not duplication.

      same ProcUnitIdx -- SHADOWING IS LEGAL AND MUST STAY SILENT. FPC accepts a
                         program routine shadowing a builtin or a used unit's,
                         and accepts two units exporting the same name (the last
                         `uses` wins). Only a duplicate within one scope is the
                         mistake; -1 is the main program, >= 0 a unit.

    Only reached when FindProcOverloadRec matched an IDENTICAL signature, so a
    genuine overload -- different parameter types -- never lands here. That is
    also why --strict-overload cannot catch this case: its check sits under
    `if procIdx < 0`, which a duplicate never satisfies. }
  if (Procs[procIdx].BodyAddr >= 0) and (not CProcHasLocalDef[procIdx])
     and (ProcUnitIdx[procIdx] = CurrentUnitIdx) then
    Warn('duplicate definition of ''' + Procs[procIdx].Name
      + ''' with the same parameter types; the later body wins, but calls '
      + 'written between the two bind to the earlier one');

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
    if mmi < 0 then
    begin
      mmi := FindUMeth(methOwnerCi, methName);
      { ...but the name match is the FIRST entry with that name, so for an OVERLOADED
        method it is almost certainly a DIFFERENT overload -- and binding this body to it
        OVERWRITES that overload's proc. fpjson's TJSONArray declares Insert(Index) plus
        ten Insert(Index, ...) overloads; each two-arg body that failed the by-proc lookup
        landed on the one-arg entry and clobbered it, so `J.Insert(0)` could no longer find
        a one-argument Insert and the arity search fell through to a two-arg one --
        "expected ," at the closing paren.

        Only reuse a name match whose bound proc has THIS signature's arity; otherwise
        register a fresh entry rather than destroying someone else's. (An impl whose
        signature fails to match its declaration is the deeper defect -- that is what makes
        FindUMethByProc miss in the first place -- and is filed separately as
        bug-pascal-overload-impl-decl-signature-match.) }
      if (mmi >= 0) and (UMthProc_[mmi] >= 0) and
         (Procs[UMthProc_[mmi]].ParamCount <> Procs[procIdx].ParamCount) then
        mmi := -1;
    end;
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
    CurMethClass := methOwnerRec;

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
    if (procIdx >= 0) and (i < MAX_PROC_PARAMS) and pdefault[i] then ProcParamDefaultIsStr[procIdx * MAX_PROC_PARAMS + i] := pdefaultisstr[i];
    if (procIdx >= 0) and (i < MAX_PROC_PARAMS) and pdefault[i] then ProcParamDefaultIsFloat[procIdx * MAX_PROC_PARAMS + i] := pdefaultisfloat[i];
    if (procIdx >= 0) and (i < MAX_PROC_PARAMS) and pdefault[i] then ProcParamDefaultIsSet[procIdx * MAX_PROC_PARAMS + i] := pdefaultisset[i];
    if (procIdx >= 0) and (i < MAX_PROC_PARAMS) and pdefault[i] then ProcParamDefaultSOff[procIdx * MAX_PROC_PARAMS + i] := pdefaultsoff[i];
    if (procIdx >= 0) and (i < MAX_PROC_PARAMS) and pdefault[i] then ProcParamDefaultSLen[procIdx * MAX_PROC_PARAMS + i] := pdefaultslen[i];
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
    { Named FIXED 1-D array param: record its true element count, overriding
      AllocParam's open-array placeholder (ArrLen := 1000). The whole-array
      assign path sizes its IR_COPY_REC from ArrLen, so the placeholder made
      `r := tmp` (r a var param) copy 1000 elements over a 4-element array
      (bug-array-assign-to-var-param). Dyn-array params set ArrLen := -1 above
      and must not be touched. }
    { param sym SLOTS ARE REUSED across procs (see the RecName persistence
      note below) — an unwritten field keeps the previous proc's value, so
      the low bound must be RESET for every array param before the fixed
      override (a stale lo made an open-array-of-record method param index
      garbage — test_record_method_open_array_b334 caught it). }
    if parr[i] and (pDynDepth[i] = 0) then
      Syms[idx].ConstVal := 0;
    { open-array param with a fixed-array ROW element: stamp the row shape on
      the param sym (drives callee-side indexing/copy strides) and persist it
      on the proc (drives the call-site `[..]` ctor / static-array copy-in).
      Param sym slots are reused across procs, so ALWAYS write (0 clears). }
    SymDynElemRowLen[idx] := pElemRowLen[i];
    SymDynElemRowLo[idx]  := pElemRowLo[i];
    if (procIdx >= 0) and (i < MAX_PROC_PARAMS) then
    begin
      ProcParamElemRowLen[procIdx * MAX_PROC_PARAMS + i] := pElemRowLen[i];
      ProcParamElemRowLo[procIdx * MAX_PROC_PARAMS + i] := pElemRowLo[i];
      if ptypes[i] = tySet then
        ProcParamSetEnumId[procIdx * MAX_PROC_PARAMS + i] := ptypesSetEnum[i];
    end;
    if (pFixedLen[i] > 0) and (pDynDepth[i] = 0) then
    begin
      Syms[idx].ArrLen := pFixedLen[i];
      { ...and its LOW BOUND: without it, IR_INDEX subtracted lo=0 and a[1]
        on a `var a: array[1..3]` param silently wrote the NEXT element
        (g[1] stayed 0, g[2] got the value — found by the {$R+} arc's probe;
        FPC writes 7 8, pxx wrote 0 7). }
      Syms[idx].ConstVal := pFixedLo[i];
    end;
    if parr[i] and (ptypes[i] = tyRecord) then
    begin
      { Open array of records (e.g. `array of const`): the slot holds a dyn-array
        data pointer; element type/record live in ElemType/ElemRecName, not a
        by-value RecName, and it must NOT be promoted to by-ref. }
      Syms[idx].ElemType := tyRecord;
      Syms[idx].ElemRecName := ptypesRec[i];
    end
    else if TypeIsPromoInt(ptypes[i]) then
    begin
      { A PROMOTABLE INT parameter is an AGGREGATE — {tag, payload}, 16 bytes on
        a 64-bit target — so it travels the same way a large record does: by
        reference, with the CALLER copying into a hidden temp first, which is
        what gives Pascal's value semantics over an address-passing ABI.

        Without this it was in no class at all: the caller passed the slot
        ADDRESS (an rvalue promo IS its slot address) while the callee's `lea n`
        addressed an unfilled 16-byte frame cell, so `@n` was a pointer to a
        pointer and `n + 0` read the caller's address as a TAG word and crashed
        in the runtime's heap branch
        (bug-a-promoint-parameter-cannot-be-used-at-all).

        tyPromoInt64 ONLY, not TypeIsPromoInt. On a 32-bit target `PromoInt` is
        the 8-byte tyPromoInt32, and there this promotion does NOT work: the
        by-ref indirection is not resolved the same way, so the runtime reads a
        garbage tag, `PromoShiftCount` returns a huge count and `n shr 4` on a
        parameter spins in BShr's doubling loop — a HANG, which is worse than
        the crash it replaced. Measured on i386; 64-bit is verified correct.
        Restricting the arm leaves 32-bit exactly as it was (promo parameters
        unusable, as on `pinned`) instead of changing one failure mode for a
        worse one. Tracked as
        bug-a-promoint-parameter-32bit-by-ref-indirection-hangs. }
      Syms[idx].IsRef := True;
      if (procIdx >= 0) and (i < MAX_PROC_PARAMS) then
        Procs[procIdx].Params[i].IsRef := True;
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
        into one machine word. (No-op on 64-bit, so self-host stays identical.)

        A record with MANAGED FIELDS joins them at any size. A <=8-byte record
        travels INLINE in the param slot (see AllocParam) — a raw byte copy of
        the caller's handles with no retain, so the callee's copy BORROWS them.
        That is fine while the callee only reads, but a store into the parameter
        (`a := q`, ordinary by-value mutation) lowers to IR_COPY_REC_MANAGED,
        which RELEASES the destination's old fields — i.e. releases the CALLER's
        handles, which nobody retained. The caller's dynarray is freed under it
        and the next read gets a recycled block: silent wrong values, then a
        write-after-free segfault far away
        (bug-a-arm32-write-after-free-kills-four-lib-tests — ecdsa's
        `BigToBytes(a: TBigInt; ...)` does exactly `a := q`).

        By-ref puts them on the >8-byte path, which is already correct:
        IRLowerCallArg makes a private temp and fills it with
        IR_COPY_REC_MANAGED, so the copy OWNS its fields and the callee's
        stores release the temp's handles, never the caller's.

        Filed as arm32-only because the trigger is ptr-width dependent —
        `TBigInt` (Boolean + dynarray handle) is 16 bytes on 64-bit, so it was
        already by-ref there, but 8 bytes on 32-bit. The defect is not: a record
        that is <=8 bytes on x86-64 too (a lone dynarray or string field)
        corrupts identically. Measured on x86-64, arm32, aarch64 and riscv32. }
      if (ptypes[i] = tyRecord) and
         ((RecSize(ptypesRec[i]) > 8) or
          RecordHasManagedFields(ptypesRec[i]) or
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
    { Record the parameter's procedural signature on the PROC entry too, not only
      on the parameter's symbol. A param symbol is a local: RegisterProc leaves
      Params[].SymIdx = -1 and the symbol itself does not outlive the callee's
      scope, so a CALLER lowering `Takes(fp)` has no way back to it.
      A PARALLEL ARRAY, like ProcParamUntyped: TParam has no ProcSig field.
      Consumer: IRProcVarAutoCall's call-argument sink (Delphi-mode
      bare-procvar auto-call), which must pass `fp` untouched to a proc-typed
      parameter and CALL it for any other.
      bug-pascal-procvar-value-context-outside-assignment }
    ProcParamProcSig[procIdx * MAX_PROC_PARAMS + i] := ptypesProcSig[i];

    { feature-a-typeref-migrate-consumers: this per-param body has several
      independent mutation points above (ArrLen/SymDynDepth, ElemType/
      ElemRecName, RecName, PtrElemTk/PtrElemRec, SymProcSig) — resync once
      at the loop-body's single exit rather than after each. }
    SymSyncTypeRef(idx);
  end;
  { Wire Self's RecName so field lookups resolve against the owner class }
  if (methOwnerCi >= 0) and not isStaticMethod then
  begin
    Syms[Procs[procIdx].Params[0].SymIdx].RecName := methOwnerRec;
    SymSyncTypeRef(Procs[procIdx].Params[0].SymIdx);
  end;

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
    else if retArrAi >= 0 then
    begin
      { Result is a FIXED array. It must be allocated AS an array: AllocVar
        stamps IsArray=False/ArrLen=0/SymArrNDims=0 and reserves ONE ELEMENT
        (`Procs[].RetType` holds the element kind for `function F: TArr`), so
        `Result[i] := v` indexed off a 4-byte slot and wrote over the rest of
        the frame — `array[0..2]` survived on frame padding, `array[0..3]`
        reached the return address and SIGSEGVed, and an N-D result indexed
        with no dim spans at all (`1 2 3 4` read back as `1 3 3 4`).
        bug-a-nd-array-function-result-indexes-the-wrong-slot }
      { Params were parsed since the return type, so re-state the element's
        frozen-string width from the alias rather than trusting LastTypeStrCap. }
      if (retType = tyFixedString) or (retType = tyShortString) then
        LastTypeStrCap := ArrTypeElemStrCap[retArrAi];
      idx := AllocArray('Result', retType, ArrTypeLo[retArrAi], ArrTypeHi[retArrAi]);
      Syms[idx].Kind := skLocal;
      if ArrTypeNDims[retArrAi] >= 2 then
      begin
        SymArrNDims[idx] := ArrTypeNDims[retArrAi];
        for i := 0 to ArrTypeNDims[retArrAi] - 1 do
        begin
          SymArrDimLo[idx * MAX_ARR_DIMS + i]   := ArrTypeDimLo[retArrAi * MAX_ARR_DIMS + i];
          SymArrDimSpan[idx * MAX_ARR_DIMS + i] := ArrTypeDimSpan[retArrAi * MAX_ARR_DIMS + i];
        end;
      end;
      SymSyncTypeRef(idx);
      Procs[procIdx].RetSymIdx := idx;
      { Restate the returned byte count from the element's real SLOT size. The
        count above came from TypeSize(elemTk), which is the whole-value size
        only for scalars: `array[0..2] of string[8]` copied 3*8 of a 3*(2+8)
        slot run and came back blank, and a record element copied one pointer's
        worth. Same elemSize rule as the whole-static-array copy in ir.inc. }
      if retType = tyRecord then
        sz := RecSize(Syms[idx].ElemRecName)
      else if TypeIsFrozenString(retType) then
        sz := FrozenStrSlotSize(retType, SymStrCap[idx])
      else
        sz := TypeSize(retType);
      retFixedArrBytes := Syms[idx].ArrLen * sz;
      ProcRetFixedArrBytes[procIdx] := retFixedArrBytes;
      ProcRetArrAi[procIdx] := retArrAi;
    end
    else
    begin
      AllocVar('Result', retType);
      Procs[procIdx].RetSymIdx := SymCount - 1;
      Syms[SymCount-1].Kind := skLocal;
    end;
    LastTypeRecId := savedLastTypeRecId;
    if not retIsDynArr and (RetViaHiddenDest(retType) or (retFixedArrBytes > 0)) then
    begin
      { …or a FIXED-ARRAY result, whose aggregate nature the kind cannot show }
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

  { Spill the incoming params into their frame slots. The six per-arch arms
    that used to sit here — ~570 lines — are target machinery, not Pascal,
    and living in this driver is why NilPy and Rust each grew a raw-x86-64
    copy. refactor-a-the-missing-layer-between-frontends-and-backends }
  EmitParamSpillsForTarget(procIdx, nparams);

  { Optional var/const/type/label sections }
  while CurTok.Kind in [tkVar, tkConst, tkType, tkProcedure, tkFunction] do
    case CurTok.Kind of
      tkVar:   ParseVarSection;
      tkConst: ParseConstSection(-1, 0);
      tkType:  ParseTypeSection;
      tkProcedure, tkFunction: ParseNestedRoutine;
    end;
  EmitManagedLocalsZeroInit(savedSC);
  { Routine-local typed constants: now that storage is allocated and managed
    locals are nil'd, emit the recorded initializer assignments into the
    prologue (re-run on each call). }
  CompilePendingLocalInits;
  { ...and FINALIZE the managed `out` parameters, for the same reason and in the
    same place: the body must not be able to observe (or hand back) whatever the
    caller's variable happened to hold. Managed kinds only — an ordinal `out` is
    indistinguishable from `var` in FPC too. See ClearManagedOutParam. }
  for i := 0 to nparams - 1 do
    if pout[i] and (i < MAX_PROC_PARAMS) then
      ClearManagedOutParam(Procs[procIdx].Params[i].SymIdx);
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

  { A proc holding managed locals that can be unwound PAST needs a landing pad
    of its own: neither its epilogue nor the eventual handler's frame runs, so
    without one the locals are never released. The gate used to read
    `TargetArch = TARGET_X86_64`, which is why an interface held across a raise
    leaked on every other target, silently — an unwind leak prints nothing.
    The sequence itself is each backend's own IR_EXC_ENTER, lifted into
    ir_codegen.inc; xtensa is the one target still without it. }
  needsProcCleanupFrame := TargetHasProcCleanupFrame and ExceptionUsed and
                           (not isAsmFunc) and ProcHasManagedLocalCleanup(procIdx, -1);
  if needsProcCleanupFrame then
  begin
    EmitProcCleanupFrameEnterForTarget(cleanupJnePatch);
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
    ASTNodeCount := ASTArenaFloor;
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
    ASTNodeCount := ASTArenaFloor;
  end
  else
  begin
    Expect(tkBegin, 'begin');
    { Split ParseBlock so the body AST can be retained for inline expansion
      (feature-inline-routines) before CompileAST emits + the pool resets. Only a
      non-method plain routine is a candidate; TryRetainInlineBody re-checks all
      eligibility and no-ops unless OptLevel>=2. Behaviour is otherwise identical
      to ParseBlock, so -O0/-O1 stay byte-identical. }
    inlineBodyNode := WrapManagementOps(procIdx, ParseBlockAST);
    if methOwnerCi < 0 then TryRetainInlineBody(procIdx, inlineBodyNode);
    CompileAST(inlineBodyNode);
    ASTNodeCount := ASTArenaFloor;
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
    EmitProcCleanupLandingPadForTarget(cleanupJnePatch);

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
  ProcDbgMain[procIdx] := DbgTokIsDebuggable(TokPos);
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
  CurMethClass := REC_NONE;
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

{ ===== Host soname discovery =================================================

  A library name (`libz.so`) has to become the versioned DT_NEEDED name the
  loader will actually accept (`libz.so.1`). Until now that came from a
  hardcoded table of eight libraries, and everything else got the unversioned
  spelling, which links against the -dev symlink when it exists and fails on a
  machine that only has the runtime package.

  The self-hosted compiler has no execve, so pkg-config / `ldconfig -p` are out
  of reach. But the answer they would print is in /etc/ld.so.cache, which is a
  plain file: the loader's own name -> path index. Reading it needs no new
  capability and no host-specific configuration.

  Format (glibc's `cache_file_new`, the only one glibc has written for years):

    offset  size  field
    0       17    magic "glibc-ld.so.cache"   (not NUL-terminated)
    17      3     version "1.1"
    20      4     nlibs
    24      4     len_strings
    28      4     flags/padding
    32      4     extension_offset
    36      12    unused
    48      24*n  entries: int32 flags, uint32 key, uint32 value, uint32 osver,
                  uint64 hwcap  — key/value are FILE-relative string offsets

  `key` is the soname, `value` the resolved path. We want the key only: the
  compiler emits a DT_NEEDED name, it never opens the library.

  Every read is bounds-checked against the actual file length rather than
  trusting the header — this parses a file written by something else, and a
  compiler that segfaults on a truncated /etc/ld.so.cache would be a worse bug
  than the one this fixes. }

function LdCacheU32(off: Integer): Int64;
{ Little-endian u32 at 1-based `off`. Returns -1 when the read would run past
  the end, which every caller treats as "give up on the cache". }
begin
  LdCacheU32 := -1;
  if (off < 1) or (off + 3 > Length(LdCacheBody)) then Exit;
  LdCacheU32 := Int64(Ord(LdCacheBody[off])) +
                Int64(Ord(LdCacheBody[off + 1])) * 256 +
                Int64(Ord(LdCacheBody[off + 2])) * 65536 +
                Int64(Ord(LdCacheBody[off + 3])) * 16777216;
end;

procedure LdCacheLoad;
var pth: AnsiString;
begin
  if LdCacheLoaded then Exit;
  LdCacheLoaded := True;
  LdCacheBody := '';
  { NATIVE ONLY. The host's library set says nothing about a cross target's, and
    silently linking an aarch64 binary against this machine's soname list is the
    kind of wrong answer that shows up as a runtime loader error on a different
    machine. Same rule the C include-path defaults follow. }
  if TargetArch <> TARGET_X86_64 then Exit;
  pth := '/etc/ld.so.cache';
  LoadFile(pth, LdCacheBody);
end;

function LdCacheStringAt(off: Integer; var out_: AnsiString): Boolean;
{ The NUL-terminated string at 0-based FILE offset `off`. }
var i, n: Integer;
begin
  LdCacheStringAt := False;
  out_ := '';
  n := Length(LdCacheBody);
  i := off + 1;                       { 0-based file offset -> 1-based string }
  if (i < 1) or (i > n) then Exit;
  while (i <= n) and (LdCacheBody[i] <> Chr(0)) do
  begin
    out_ := out_ + LdCacheBody[i];
    Inc(i);
  end;
  LdCacheStringAt := i <= n;          { unterminated => the file is truncated }
end;

function LdCacheFindSoname(const unversioned: AnsiString; var soname: AnsiString): Boolean;
{ `libz.so` -> `libz.so.1` when the host has one. Only a VERSIONED key counts:
  an exact `libz.so` hit is the -dev symlink, which is what we would have
  emitted anyway, so it is not an answer worth preferring over the table. }
var nlibs, i, entOff: Integer;
    keyOff: Int64;
    key, want: AnsiString;
begin
  LdCacheFindSoname := False;
  LdCacheLoad;
  if Length(LdCacheBody) < 48 then Exit;
  if Copy(LdCacheBody, 1, 17) <> 'glibc-ld.so.cache' then Exit;
  if Copy(LdCacheBody, 18, 3) <> '1.1' then Exit;
  nlibs := Integer(LdCacheU32(21));
  if (nlibs <= 0) or (48 + nlibs * 24 > Length(LdCacheBody)) then Exit;
  want := unversioned + '.';          { the version suffix must be present }
  for i := 0 to nlibs - 1 do
  begin
    entOff := 49 + i * 24;            { 1-based start of entry i }
    keyOff := LdCacheU32(entOff + 4);
    if keyOff < 0 then Exit;
    if not LdCacheStringAt(Integer(keyOff), key) then Exit;
    if (Length(key) > Length(want)) and (Copy(key, 1, Length(want)) = want) then
    begin
      soname := key;
      LdCacheFindSoname := True;
      Exit;
    end;
  end;
end;

function ResolveHostSoname(const unversioned: AnsiString): AnsiString;
{ The one funnel: hand it the unversioned spelling, get back what the loader on
  this machine actually answers to, or the same string when it cannot be found.
  Callers do not branch on whether the library is "known" — that double case is
  precisely what the hardcoded table was. }
var found: AnsiString;
begin
  ResolveHostSoname := unversioned;
  if LdCacheFindSoname(unversioned, found) then ResolveHostSoname := found;
end;

function CSonameForStem(const stem: AnsiString; var soname: AnsiString): Boolean;
var unver: AnsiString;
begin
  Result := True;
  { HOST FIRST, table second. The table is eight libraries' worth of guess about
    what a Linux box has; /etc/ld.so.cache is what this box actually has. Asking
    the host first is also what removes the double case — "known library" and
    "unknown library" stop being different code paths, so the next soname bump
    (libz.so.1 -> .2) needs no edit here at all. Falls through to the table when
    the cache is absent, unreadable, foreign, or cross-compiling. }
  ConcatThree('lib', LowerCase(stem), '.so', unver);
  if LdCacheFindSoname(unver, soname) then Exit;
  if CStemMatches(stem, 'c') then soname := 'libc.so.6'
  else if CStemMatches(stem, 'm') then soname := 'libm.so.6'
  else if CStemMatches(stem, 'pthread') then soname := 'libpthread.so.0'
  else if CStemMatches(stem, 'gtk-3') then soname := 'libgtk-3.so.0'
  else if CStemMatches(stem, 'gtk-x11-2.0') then soname := 'libgtk-x11-2.0.so.0'
  else if CStemMatches(stem, 'dl') then soname := 'libdl.so.2'
  else if CStemMatches(stem, 'rt') then soname := 'librt.so.1'
  else if CStemMatches(stem, 'z') then soname := 'libz.so.1'
  else if CStemMatches(stem, 'sqlite3') then soname := 'libsqlite3.so.0'
  else soname := unver;
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

function CStemOfSoname(const soname: AnsiString): AnsiString;
{ `libz.so.1` -> `z`, `libgtk-x11-2.0.so.0` -> `gtk-x11-2.0`, `libc.so.6` -> `c`.
  Derived, not tabulated: this used to be a nine-line if-chain that listed the
  same sonames as CSonameForStem's table in the opposite direction, so any
  soname outside those nine — including every one the host cache can now supply,
  and every future version bump — answered "not selected" and silently ignored
  `--system-libs=<that lib>`. Deriving it is the only spelling that cannot drift
  from its sibling (devdocs/dev/normalise-dont-special-case.md). }
var i, cut: Integer;
    body: AnsiString;
begin
  body := soname;
  if (Length(body) > 3) and (Copy(body, 1, 3) = 'lib') then
    body := Copy(body, 4, Length(body) - 3);
  cut := 0;
  for i := 1 to Length(body) - 2 do
    if (body[i] = '.') and (body[i + 1] = 's') and (body[i + 2] = 'o') then
    begin
      cut := i;
      Break;
    end;
  if cut > 0 then body := Copy(body, 1, cut - 1);
  CStemOfSoname := body;
end;

function CSystemLibSelectedForSoname(const soname: AnsiString): Boolean;
begin
  Result := CUseSystemLibs;
  if Result then Exit;
  Result := CSystemLibStemSelected(CStemOfSoname(soname));
end;

procedure EnableExceptionRuntime;
begin
  if not ExceptionUsed then
  begin
    ExceptionUsed := True;
    BSS_EXC_TOP := BSSSize; Inc(BSSSize, 8);
    BSS_EXC_OBJ := BSSSize; Inc(BSSSize, 8);
    BSS_EXC_CLS := BSSSize; Inc(BSSSize, 8);
    BSS_EXC_ADDR := BSSSize; Inc(BSSSize, 8);
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

{ Compiling a unit sets up and tears down PROC context of its own — CurProc,
  the frame size, the enclosing class. A NilPy `import` may appear inside a
  function body (Python allows one anywhere, and a `try: import x / except
  ImportError:` in a def is the standard optional-dependency idiom), so the
  compile can start while a proc body is half-emitted. Without this save the
  importing routine came back with the unit's leftovers: the def's own body
  never ran and the call returned whatever the last unit routine did — a
  `try: import math` in a def made every call return math's pi, silently
  (bug-nilpy-import-inside-def-clobbers-proc-context). }
procedure ParseUsesUnitBody(const name: AnsiString); forward;

{ The two HOST-HEADER probes of the unit resolver, in one place because they are
  now called from two positions: early for every non-NilPy frontend, and late
  for NilPy (after the .py/.npy library lookup and the mimic_ shim, so a Python
  stdlib name that also names a C header does not lose to the header).
  Two call sites, one body — a second copy is exactly how the two positions
  would drift.
  bug-nilpy-python-import-resolves-against-c-headers }
procedure PyTryHostHeader(const cName: AnsiString; var path: AnsiString;
                          var content: AnsiString;
                          var isCUnit, isCHeader: Boolean);
begin
  if Length(content) > 0 then Exit;
  ConcatThree('/usr/include/', cName, '.h', path);
  LoadFile(path, content);
  if Length(content) = 0 then
  begin
    ConcatThree('/usr/include/gtk-2.0/gtk/', cName, '.h', path);
    LoadFile(path, content);
  end;
  if Length(content) > 0 then begin isCUnit := True; isCHeader := True; end;
end;

{ Does this `lib/rtl` unit SERVE the Python module of the same name — i.e. must
  a bare NilPy `import <name>` keep resolving to it?

  A bare NilPy import means PYTHON (decide-nilpy-imports-that-collide-with-a-
  pascal-rtl-unit, user 2026-08-19), so the .pas chain is closed to it — except
  for the units below, which ARE the Python module and are reached by that
  spelling on purpose. `classes`, `types` and `strings` are deliberately absent:
  they are ordinary Pascal units that happen to share a Python name, and
  `from classes import Foo` failing with a message about `Delete` inside a unit
  the program never mentioned is the bug this list exists to fix. A Pascal unit
  is still reachable from NilPy — with an explicit extension, `import
  'classes.pas' as c`.

  ADDING A UNIT TO THIS LIST IS PART OF WRITING ONE. When a new unit is written
  to serve a Python module, it does not resolve by bare name until its name is
  here, and the failure lands at the import of a unit that plainly exists — far
  from the omission that caused it.

  NOT ONLY lib/rtl, despite this function's name. `tkinter` is lib/pcl's, and it
  was missing from the first version of this list for no better reason than that
  the list was built by sweeping lib/rtl — which broke seven examples/tk jobs
  that had done nothing wrong. Where the unit lives is not the question this list
  answers; what it is FOR is.

  AND THE TEST IS PURPOSE, NOT INVENTORY. "Is there a Python module by this name"
  does not work: `tk` is a real PyPI package, and `tkinter` itself needs a distro
  package on most systems, so neither stdlib membership nor installability
  separates anything — anything can be published to PyPI. Ask instead whether the
  unit was WRITTEN TO BE that Python module; each unit's own header answers it.
  lib/pcl/tk.pas is the counterexample that makes this concrete: it is a Tcl/Tk
  embed, tkinter.pas is the Python module built on top of it, and listing `tk`
  would silently bind a program's `import tk` — legal, resolvable, wrong — to our
  binding instead of the package it installed.

  A CURATED LIST, and not a property read off the unit, because every derivable
  form of the question is wrong. The header prose is wrong in BOTH directions:
  `math`, `json` and `random` read as ordinary Pascal libraries and serve
  Python's modules, while `sysutils` names NilPy in its header and is a
  genuinely Pascal unit that must STOP resolving by bare name. Nor is "was it
  written for the NilPy frontend" answerable from the file. The intent is a
  fact about each unit, so it is recorded, not inferred — which is also why the
  list is worth more than the behaviour it selects.

  `collections` is the case that proves the point: its header describes a
  generic growable list and nothing else, yet it belongs here, because plain
  `import collections` is deliberately routed to the resolver so that a
  `collections.Sym` qualifier has a unit to resolve against — see
  PyImportRootPlainIsConsumedOnly, which says exactly that and is why
  `from collections import Counter` (consumed, never resolved) does not
  contradict it.

  The `mimic_*` shims are NOT here: they are Python modules by construction and
  the resolver reaches them through the prefix path, not through this list. }
{ Did this resolution land on a PASCAL source? Asked of the path a probe
  actually loaded, rather than of the eight scattered places one could come
  from — so an import that pinned another language discards the find on the
  evidence instead of on a predicate per probe site. }
function PathIsPascalSource(const p: AnsiString): Boolean;
var e: AnsiString; i, lastDot: Integer;
begin
  lastDot := 0;
  for i := 1 to Length(p) do
    if p[i] = '.' then lastDot := i;
  e := '';
  if lastDot > 0 then e := LowerCase(Copy(p, lastDot + 1, Length(p) - lastDot));
  Result := (e = 'pas') or (e = 'pp');
end;

function PyRtlUnitServesPython(const lo: AnsiString): Boolean;
begin
  Result := (lo = 'ast') or (lo = 'atexit') or (lo = 'base64') or
            (lo = 'collections') or (lo = 'configparser') or (lo = 'html') or
            (lo = 'io') or (lo = 'json') or (lo = 'markdown') or
            (lo = 'math') or (lo = 'pathlib') or (lo = 'random') or
            (lo = 're') or (lo = 'subprocess') or (lo = 'tempfile') or
            (lo = 'tkinter');
end;

{ `mypkg.core.bus` -> `mypkg/core/bus`. A dotted absolute import names a
  DIRECTORY PATH under a package root; the underscore-mangled unit name it also
  carries cannot be turned back into one (`a.b_c` and `a_b.c` mangle alike), so
  the path is built from the dotted spelling the frontend kept.
  feature-nilpy-dotted-imports-resolve-to-source-files }
function PyDottedToRelPath(const dotted: AnsiString): AnsiString;
var i: Integer;
begin
  Result := '';
  for i := 1 to Length(dotted) do
    if dotted[i] = '.' then Result := Result + '/'
    else Result := Result + dotted[i];
end;

{ The unit name a dotted path mangles to, lowercased — used to CHECK that a
  carried-over dotted spelling really belongs to the import being resolved. }
function PyDottedMangled(const dotted: AnsiString): AnsiString;
var i: Integer;
begin
  Result := '';
  for i := 1 to Length(dotted) do
    if dotted[i] = '.' then Result := Result + '_'
    else Result := Result + dotted[i];
  Result := LowerCase(Result);
end;

{ One package root's worth of probes for a dotted module: the module file
  itself, then the package directory's `__init__`. `.py` before `.npy` at each
  step so a package written in plain Python wins over a stray same-named NilPy
  file, matching the flat sibling probe's order. }
procedure PyTryPackageSource(const root, relPath: AnsiString;
                             const wantModuleFile: Boolean;
                             var path: AnsiString; var content: AnsiString);
begin
  if Length(content) > 0 then Exit;
  if wantModuleFile then
  begin
    ConcatThree(root, relPath, '.py', path); LoadFile(path, content);
    if Length(content) = 0 then
    begin
      ConcatThree(root, relPath, '.npy', path); LoadFile(path, content);
    end;
  end;
  if Length(content) = 0 then
  begin
    ConcatThree(root, relPath, '/__init__.py', path); LoadFile(path, content);
  end;
  if Length(content) = 0 then
  begin
    ConcatThree(root, relPath, '/__init__.npy', path); LoadFile(path, content);
  end;
end;

{ The directory a relative import of LEVEL dots resolves against, starting from
  the importing file's own directory. Level 0 and 1 both mean "here" — `from
  .mod` is this package — and each dot beyond the first climbs one package.
  Returns '' when the climb would go above the root, so the caller simply finds
  nothing rather than resolving against something arbitrary.

  `dir` carries a trailing separator throughout the resolver, so a climb is:
  drop the trailing '/', then drop back to and including the previous '/'. }
function PyRelativeDir(const dir: AnsiString; level: Integer): AnsiString;
var i, climbs: Integer;
begin
  Result := dir;
  climbs := level - 1;
  while climbs > 0 do
  begin
    if Length(Result) = 0 then begin Result := ''; Exit; end;
    { drop the trailing separator }
    if Result[Length(Result)] = '/' then
      Result := Copy(Result, 1, Length(Result) - 1);
    { …then the last segment }
    i := Length(Result);
    while (i > 0) and (Result[i] <> '/') do Dec(i);
    if i <= 0 then begin Result := ''; Exit; end;
    Result := Copy(Result, 1, i);
    Dec(climbs);
  end;
end;

{ Does a `mimic_<name>` shim exist as a FILE? Asked before falling back to a
  host header for a NilPy import: the shim mapping itself runs later still, and
  by then the header would already have won. A file probe rather than a
  registry, because the shim is not loaded at this point — the question is only
  whether one is there to be loaded.

  A shim may be written in EITHER language, so all four spellings are one
  lookup rather than two mechanisms. Some Python modules cannot honestly be
  expressed in Pascal — `six` is entirely aliases (`text_type = str`), and "the
  `str` type object as a value" is not a thing a Pascal unit says — so those
  ship as `mimic_<name>.py` and the NilPy loader below picks them up. Asking
  only about `.pas` here made a `.py` shim invisible to THIS question alone: it
  loaded fine for a plain name, but any name that also names a host C header
  lost to the header, and the failure surfaced far away as `undefined variable`
  on the first attribute touched.
  feature-a-the-shim-slot-should-find-a-python-shaped-shim }
{ One root, all four spellings a shim may be written in. }
function PyMimicShimAt(const root, lo: AnsiString): Boolean;
var pfx, p, c: AnsiString;
begin
  Result := False;
  if Length(root) = 0 then Exit;
  ConcatThree(root, 'mimic_', '', pfx);
  ConcatThree(pfx, lo, '.pas', p); LoadFile(p, c);
  if Length(c) > 0 then begin Result := True; Exit; end;
  ConcatThree(pfx, lo, '.pp', p);  LoadFile(p, c);
  if Length(c) > 0 then begin Result := True; Exit; end;
  ConcatThree(pfx, lo, '.py', p);  LoadFile(p, c);
  if Length(c) > 0 then begin Result := True; Exit; end;
  ConcatThree(pfx, lo, '.npy', p); LoadFile(p, c);
  if Length(c) > 0 then begin Result := True; Exit; end;
end;

function PyMimicShimExists(const lo, rtldir, lcldir: AnsiString): Boolean;
var i: Integer;
begin
  Result := True;
  { The -Fu roots first, matching the loader: the shim mapping resolves through
    ParseUsesUnit, which probes PasUnitDirs for `mimic_<name>.py` like any other
    unit — so a shim CAN live in a -Fu root, and this question has to be able to
    see one or it answers "no shim" about a shim that will then load. }
  for i := 0 to PasUnitDirCount - 1 do
    if PyMimicShimAt(PasUnitDirs[i], lo) then Exit;
  { …then the ExeDir-anchored library roots the loader uses… }
  if PyMimicShimAt(lcldir, lo) then Exit;
  if PyMimicShimAt(rtldir, lo) then Exit;
  { …then the CWD-relative fallback, for the same reason the loader carries one:
    the STABLE binary lives two levels down, so its '../lib/rtl' does not exist
    and only the relative form finds the tree. }
  if PyMimicShimAt('lib/pcl/', lo) then Exit;
  if PyMimicShimAt('lib/rtl/', lo) then Exit;
  Result := False;
end;

{ Plain substring test. `needle` must already be lower-case; `hay` is expected to
  be a LowerCase()d copy, so the caller pays for the fold once across both probes
  rather than per character here. }
function SrcContains(const hay, needle: AnsiString): Boolean;
var i, j, n, m: Integer; ok: Boolean;
begin
  Result := False;
  n := Length(hay); m := Length(needle);
  if (m = 0) or (n < m) then Exit;
  for i := 1 to n - m + 1 do
  begin
    ok := True;
    for j := 1 to m do
      if hay[i + j - 1] <> needle[j] then begin ok := False; Break; end;
    if ok then begin Result := True; Exit; end;
  end;
end;

{ Does a line of `hay` consist of exactly `needle` and nothing else but blanks?
  `hay` is a LowerCase()d copy and `needle` is lower-case, as above. }
function SrcHasLoneLine(const hay, needle: AnsiString): Boolean;
var i, n, ls, le: Integer; ln: AnsiString;
begin
  Result := False;
  n := Length(hay);
  ls := 1;
  for i := 1 to n + 1 do
    if (i > n) or (hay[i] = #10) then
    begin
      le := i - 1;
      if (le >= ls) and (hay[le] = #13) then Dec(le);
      while (ls <= le) and ((hay[ls] = ' ') or (hay[ls] = #9)) do Inc(ls);
      while (le >= ls) and ((hay[le] = ' ') or (hay[le] = #9)) do Dec(le);
      ln := Copy(hay, ls, le - ls + 1);
      if ln = needle then begin Result := True; Exit; end;
      ls := i + 1;
    end;
end;

{ ---- A cpyext EXTENSION MODULE is a Python module, not a Pascal unit ----------
  `import <name>` from NilPy resolves to Python only, and a Pascal unit of that
  name is refused with the error further down. An extension module is not that
  rule's subject: it is a Python module whose body happens to be Pascal + C, so
  the bare import is ordinary CPython — every stdlib accelerator is reached that
  way — and the rule simply never applies to it.
  decide-nilpy-import-rule-vs-a-cpyext-extension-module, DECIDED 2026-08-20.

  Shape (b) of that decision: the unit RECORDS the fact, the compiler does not
  infer it. `{$PYEXTENSION}` is the record; the unit binding the cpyext runtime
  is the CHECK, so the directive pasted onto an ordinary Pascal unit does not
  quietly make it bare-importable.

  The decision named `PyInit_<name>` as the check and it does not hold — measured
  on the six units the implementation ticket requires green:
    hello_ext, argerr_ext, container_ext   PyInit_<name>            3
    cyadd_ext        PyInit_cyadd          the VENDORED module's symbol, adapted
    markupsafe_ext   PyInit__speedups        by the unit's host shim
    fmt_ext          none at all           a C-API consumer, not a module
  So `PyInit_<name>` verifies 3 of 6, and rewriting the other three to satisfy it
  would be fabricating evidence for a predicate. The check below is the nearest
  recorded fact that holds for all six and for no ordinary Pascal unit.

  Both tests are textual, over the unit source the resolver is already holding —
  the alternative was grepping the unit's C files, which is the compiler reading
  C to make a Pascal decision. A pre-lex scan cannot tell a directive from the
  same text inside a comment, so the directive must stand ALONE on its line: this
  file's own negative-test unit mentioned it in prose and was admitted as an
  extension module until the rule tightened. What remains matchable is a
  commented-out directive on a line of its own, which is a unit opting in in its
  own source either way. }
function PyUnitDeclaresExtensionModule(const src: AnsiString): Boolean;
var lc: AnsiString;
begin
  lc := LowerCase(src);
  Result := SrcHasLoneLine(lc, '{$pyextension}') and SrcContains(lc, 'pyruntime.c');
end;


procedure ParseUsesUnitAmbient(const name: AnsiString); forward;

procedure ParseUsesUnit(const name: AnsiString);
var savedProc, savedFrame, savedSelf, vsym: Integer;
begin
  savedProc := CurProc; savedFrame := FrameSize; savedSelf := CurSelfClass;
  CurProc := -1;
  ParseUsesUnitBody(name);
  CurProc := savedProc; FrameSize := savedFrame; CurSelfClass := savedSelf;
  { RTL LAYOUT GUARD. This compiler's inline codegen assumes a runtime data
    layout (header size, refcount/magic offsets); the builtinheap it just linked
    IMPLEMENTS one. `pinned` keeps the two in step by freezing the RTL beside
    itself, but ./compiler/pascal26 resolves `uses builtinheap` from the LIVE
    tree — so after a layout change that seed builds a compiler that COMPILES
    CLEAN and whose product dumps core two generations later, reading as a
    codegen bug in whatever was touched. One line here instead
    (bug-a-self-host-seed-has-no-versioned-rtl).

    A MISSING constant is not a mismatch: an older frozen builtin (including the
    currently pinned one, until it is re-pinned) predates the stamp, and
    refusing those would break every build that uses them. Absent = unknown =
    allowed; only a present-and-different number is refused. }
  if LowerCase(name) = 'builtinheap' then
  begin
    vsym := FindSym('PXX_RTL_LAYOUT_VERSION');
    if (vsym >= 0) and (Syms[vsym].Kind = skConst) and
       (Syms[vsym].ConstVal <> PXX_RTL_LAYOUT_VERSION) then
      Error('RTL layout mismatch: this compiler emits code for layout version '
        + AIntToStr(PXX_RTL_LAYOUT_VERSION) + ' but the builtinheap it is '
        + 'linking implements version ' + AIntToStr(Syms[vsym].ConstVal)
        + '. The seed binary predates a runtime layout change, so it would '
        + 'build a compiler that compiles clean and then crashes. Reseed: '
        + '`make seed-from-stable` (or build from FPC) and retry');
  end;
end;

procedure ParseUsesUnitAmbient(const name: AnsiString);
{ Load a unit the COMPILER decided it needs — never one a source clause named.
  The unit is marked System-ambient, so --strict-uses does not report a name
  resolved through it as a leak: the program did not ask for the unit, so it
  cannot be leaking through it, which is the same argument that made
  builtin/builtinheap ambient. Nested loads are NOT ambient — a unit this one
  pulls in through its own `uses` is an ordinary edge. }
var saved: Boolean;
begin
  saved := UsesInjected;
  UsesInjected := True;
  ParseUsesUnit(name);
  UsesInjected := saved;
end;

procedure ResolveToolchainDirs(var cdir, bdir, rtldir, lcldir, asmdir: AnsiString);
{ Where the compiler's own libraries live, resolved from the binary's location
  (ExeDir) so a unit resolves regardless of CWD. ExeDir is e.g. <root>/compiler/,
  so the RTL/PCL dirs are its siblings via '../lib/...'. Falls back to
  CWD-relative when the binary path carried no directory (run via a bare name).

  Extracted from ParseUsesUnit so `pxx --where` can print exactly what the search
  will use, probe and all, instead of a second guess at the same rule. }
var probeFile, probeContent, probePath, home: AnsiString;
begin
  { Tier 2: PXX_HOME — an explicit install root, for the layout the ExeDir rule
    cannot guess (binary on PATH somewhere unrelated to its libraries). It wins
    outright rather than merging with the ExeDir guess: a half-applied override
    is the failure mode nobody can read, and `pxx --where` prints each root with
    [MISSING] so a typo shows up as a typo. }
  home := PxxGetEnv('PXX_HOME');
  if Length(home) = 0 then
  begin
    { Tier 3: pxx.cfg's `home`. Same all-or-nothing rule, one tier lower — an
      env var is a deliberate act for this one run, a config file is standing
      policy, so the run-specific one wins. }
    PxxCfgLoad;
    home := PxxCfgHome;
  end;
  if Length(home) > 0 then
  begin
    if home[Length(home)] <> '/' then home := home + '/';
    ConcatThree(home, 'compiler/', '', cdir);
    ConcatThree(home, 'compiler/builtin/', '', bdir);
    ConcatThree(home, 'lib/rtl/', '', rtldir);
    ConcatThree(home, 'lib/pcl/', '', lcldir);
    ConcatThree(home, 'lib/asmcore/', '', asmdir);
    Exit;
  end;
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
    { '../lib' assumes the binary sits at <root>/compiler/. The STABLE binary
      does not — it lives at <root>/stable_linux_amd64/<profile>/, two levels
      down — so its '../lib/rtl' does not exist and every RTL unit missed. In
      the repo that went unnoticed because the CWD-relative fallbacks below
      rescue it; run the stable binary from any other directory and
      `uses SysUtils` silently resolved to nothing, then every symbol it should
      have supplied failed one by one, far from the cause
      (bug-a-uses-sysutils-silently-no-ops-when-the-rtl-is-not-on-the-search-path).

      Probe for a unit that is certainly there rather than guess a depth: if
      '../lib/rtl/sysutils.pas' does not load, re-anchor one level higher. Done
      once, so every rtldir/lcldir/asmdir use below is fixed at the same time. }
    ConcatThree(rtldir, 'sysutils', '.pas', probeFile);
    LoadFileCI(probeFile, probeContent);
    if Length(probeContent) = 0 then
    begin
      ConcatThree(ExeDir, '../../lib/rtl/', '', probePath);
      ConcatThree(probePath, 'sysutils', '.pas', probeFile);
      LoadFileCI(probeFile, probeContent);
      if Length(probeContent) > 0 then
      begin
        rtldir := probePath;
        ConcatThree(ExeDir, '../../lib/pcl/', '', lcldir);
        ConcatThree(ExeDir, '../../lib/asmcore/', '', asmdir);
      end;
    end;
    probeContent := '';
  end;
end;

procedure ParseUsesUnitBody(const name: AnsiString);
var
  lo, cName, path: AnsiString;
  startPos, savedTokPos, strIdx, i, savedCurrentUnitIdx, savedCUC: Integer;
  aliasEdgeIdx: Integer;
  savedCurTokKind: TTokenKind;
  savedCurTokSVal: AnsiString;
  savedCurTokIVal: Int64;
  savedCurTokLine: Integer;
  savedSrcBase, savedUnitDir, savedCurrentCLibrary: AnsiString;
  savedUnitContent: AnsiString;
  cdir, bdir, rtldir, lcldir, asmdir, probeContent, probePath, probeFile: AnsiString;
  basePath, ext, emsg: AnsiString;
  lastSlash, lastDot: Integer;
  isCompiled, isCUnit, isCHeader, isPath, savedCaseMode, softMissOK: Boolean;
  guardIdx: Integer;   { CompiledUnitKey — see the note at its assignment }
  gPath: AnsiString;   { …the normalised path a path-form reference keys on }
  realIdx: Integer;    { alias-resolved unit for the already-compiled edge }
  { The RESOLVED FILE key, and the already-compiled entry holding it — what
    makes one file one unit however it was spelled. }
  pyFileIdx, pyDupIdx: Integer;
  { leading-dot count of this relative import; see PyRelativeDir }
  pyRelLevel: Integer;
  { Which language THIS import named, claimed from PyImportLang on entry: ''
    for anything that is not a NilPy import statement, 'py' for a bare one,
    'pas'/'c' for the explicit quoted spelling. See PyImportLang in defs.inc. }
  pyImportLang: AnsiString;
  pasLookupOK, pyLookupOK: Boolean;   { which chains this import may use }
  { The Pascal source a BARE NilPy import was refused, kept for the diagnostic:
    the name resolves, just not to a Python module, and saying so is the whole
    point of the rule. Empty when nothing was refused. }
  pasRefusedPath: AnsiString;
  isPyUnit, savedPyExprMode: Boolean;
  { The dotted module path this import was written with, claimed from the global
    on entry so a nested unit parse cannot see a stale one. Empty unless it
    re-mangles to exactly the unit name that arrived. }
  pyDotted: AnsiString;
  pyDottedIsPath: Boolean;   { it has >1 segment, so it names a file under a root }
  pyRootIdx: Integer;   { NilPy .py/.npy search over the library roots — see below }
  savedNestedComments, savedDelphiMode: Boolean;
  unitNeedsText: Boolean;
  savedPasDefineCount, savedPasDefineCharLen, pdi: Integer;
  savedPasDefineActive: array[0..MAX_PAS_DEFINES-1] of Boolean;
  savedPasDefineHasValue: array[0..MAX_PAS_DEFINES-1] of Boolean;
  savedPasDefineValue: array[0..MAX_PAS_DEFINES-1] of Int64;
begin
  isPath := False;
  isPyUnit := False;
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

  { Claim the dotted spelling of THIS import and clear the global immediately —
    the nested parse of whatever we resolve to must not inherit it. Kept only
    when it re-mangles to the unit name we were called with, which is what makes
    a value left behind by a consumed-and-ignored module path inert. }
  pyDotted := PyDottedImport;
  PyDottedImport := '';
  if PyDottedMangled(pyDotted) <> lo then pyDotted := '';
  { Same claim-and-clear for the relative LEVEL, and for the same reason: the
    nested parse of whatever this resolves to must not inherit it. }
  pyRelLevel := PyRelativeLevel;
  PyRelativeLevel := 0;
  { Same claim-and-clear for the LANGUAGE this import named, and for the same
    reason: what we resolve to is parsed with a clean slate, so a Pascal unit
    pulled in behind a NilPy import does not inherit Python's resolution rules. }
  pyImportLang := PyImportLang;
  PyImportLang := '';
  { WHICH CHAINS THIS IMPORT MAY USE. An explicit extension pins the language,
    so the other language's probes are closed rather than merely outranked — a
    `import 'classes.pas'` that fell through to a same-named .py would be a
    wrong answer, not a miss. Both default to open, so every non-NilPy `uses`
    and every bare import behaves exactly as before. }
  { A BARE NilPy import means PYTHON — .py/.npy, a mimic_ shim, or a C header
    the frontend has always reached — so the Pascal chain is closed to it,
    EXCEPT for the lib/rtl units that ARE the Python module of that name.
    `from classes import Foo` used to bind lib/rtl/classes.pas and fail with
    "no overload of Delete matches these arguments", naming a symbol inside a
    unit the program never mentioned, with no path back to the import.
    decide-nilpy-imports-that-collide-with-a-pascal-rtl-unit, user 2026-08-19. }
  pasLookupOK := (pyImportLang <> 'c') and
                 ((pyImportLang <> 'py') or PyRtlUnitServesPython(lo));
  pyLookupOK := (pyImportLang <> 'pas') and (pyImportLang <> 'c');
  pyDottedIsPath := False;
  for i := 1 to Length(pyDotted) do
    if pyDotted[i] = '.' then pyDottedIsPath := True;

  { Check if already compiled }
  strIdx := InternStr(lo);
  { ...but a path-form C/H reference gets its OWN key space for that check.

    `lo` for `uses './hello_ext.c'` is the file's BASE NAME with the extension
    stripped — the very same key a bare `uses hello_ext` resolves to. So a unit
    named hello_ext that pulls in its own C companion `./hello_ext.c` hit the
    already-compiled guard against ITSELF (a unit registers its name before its
    uses clause is parsed), the C file was never loaded, and every function it
    defined survived only as an unresolved extern: a clean COMPILE and a
    `symbol lookup error` at run time, with no diagnostic anywhere
    (bug-c-uses-path-basename-collides-with-enclosing-unit-name).

    Nothing about the path syntax suggests it shares a namespace with unit
    names, and a C source is never importable by bare name the way a `.pas`
    unit is — so the two spaces have no reason to share keys. Keyed on the path
    TEXT, which also makes a genuine repeat of the same `uses './x.c'` still
    dedupe. `strIdx` itself is untouched: it still tags the symbols this load
    registers (CurrentUnitIdx below), so qualified access by base name is
    unchanged. }
  guardIdx := strIdx;
  aliasEdgeIdx := -1;
  if isPath then
  begin
    { The path a probe will actually open, derived the way the path branch below
      derives it — CurUnitDir-relative unless absolute, then NormalizePath — so
      `./r1/math.pas` and `r1/math.pas` are ONE identity rather than two, which
      the raw-text `@cpath:` key could not say. Extension-less spellings resolve
      to the same prefix and therefore still share a key; that is right, since
      the .pas/.pp probe order makes them the same file. }
    if name[1] = '/' then
      gPath := name
    else
      ConcatThree(CurUnitDir, name, '', gPath);
    NormalizePath(gPath);
    guardIdx := InternStr('@path:' + LowerCase(gPath));
  end;
  { Record the edge for EVERY `uses X` clause, even one that hits the
    already-compiled guard below — a warn/count pass over
    bug-pascal-uses-is-transitive wants every clause, not just first-loads,
    since visibility is per-importer, not per-load. }
  RecordUsesEdge(CurrentUnitIdx, strIdx, InInterface);
  { ...and the RESOLVED edge, when the spelling is an alias for something else.
    The edge above points at the SPELLING (`codecs`, `xml.dom`), but visibility
    is per REAL unit and a shim's symbols live in `mimic_codecs`. Recording both
    here, at the one site every `uses` passes through, is what makes visibility
    correct by construction instead of by patches on the paths that happened to
    be reported: this used to be fixed at the already-compiled early exit alone,
    which is the arm the SECOND importer of a shim takes.

    A no-op on a first load — the shim branch below registers the alias and
    re-enters, so there is nothing to resolve yet and the recursion records the
    real edge on its own way in. It only fires once an alias for this spelling
    exists, which is exactly when the symbols live under another name.
    bug-a-a-shim-classes-are-invisible-when-two-modules-import-the-same-shim
    meta-a-lookups-that-ask-about-the-spelling-not-the-resolved-unit }
  aliasEdgeIdx := FindUnitOrAlias(Strs[strIdx].Text);
  if (aliasEdgeIdx >= 0) and (aliasEdgeIdx <> strIdx) then
    RecordUsesEdge(CurrentUnitIdx, aliasEdgeIdx, InInterface);
  if UsesInjected then
  begin
    MarkUnitAmbient(strIdx);
    { one level only for the FLAG: what this unit pulls in is an ordinary edge
      as far as the source is concerned. The wrapper restores it when the whole
      load returns. }
    UsesInjected := False;
  end
  else if UnitIsAmbient(CurrentUnitIdx) then
    { ...but ambience itself IS transitive, because the compiler's runtime is
      one namespace it injected and the user never asked for any of it. pylib
      `uses promocore`, and codegen emits calls to PXXPromoFromInt directly —
      no source in a NilPy program could have declared that dependency, which
      is exactly the argument that made pylib ambient in the first place. It
      only worked before because an interface-section `uses` re-exported
      everything; with that leak closed, the runtime graph has to say so
      itself. Roots stay compiler-injected, so no user unit can acquire
      ambience through this (bug-pascal-uses-non-transitivity-only-covers-routines-and-types). }
    MarkUnitAmbient(strIdx);
  isCompiled := False;
  for i := 0 to CompiledUnitCount - 1 do
  begin
    if CompiledUnitKey[i] = guardIdx then
      isCompiled := True;
  end;
  if isCompiled then
  begin
    { The edge recorded above points at the SPELLING (`codecs`), but visibility
      is per REAL unit and a shim's symbols live in `mimic_codecs`. On the FIRST
      import that does not matter — the shim branch below re-enters through
      `ParseUsesUnit('mimic_' + lo)`, which records the real edge on the way in.
      A SECOND importer never gets there: `guardIdx` is the spelling, so it is
      already marked compiled and exits here, leaving that module with an edge
      to a name nothing is declared under.

      The symptom was silent and shape-dependent. `codecs.lookup(...)` kept
      working, because a qualified PROC names its unit and never consults the
      visibility-filtered scan; only the flat class lookup did, so
      `codecs.CodecInfo(...)` in the second module reported `undefined variable
      (CodecInfo)` while the line above it resolved fine. Whichever module
      imported the shim first was the one that worked, which is what says the
      missing thing is the EDGE and not the alias.

      Same defect, same fix, as the duplicate-.py arm below (search
      `pyDupIdx`), whose comment records it the first time round: an alias
      answers a QUALIFIER, it does not make a module's symbols VISIBLE.
      bug-a-a-shim-classes-are-invisible-when-two-modules-import-the-same-shim }
    { The alias-resolved edge this arm used to record is now recorded for EVERY
      `uses` at the single RecordUsesEdge site above, so the special case here
      is redundant. Verified by removing it: the shim-visibility test that this
      arm was written for stays green, as do the three later import tests.
      Kept as a comment rather than deleted silently, because "the second
      importer of a shim sees nothing" is a symptom worth being able to find
      from here. }
    Exit;
  end;

  { Mark as compiled. Remembered so a SOFT miss (the fallback-import probe
    below) can take the mark back off: nothing was loaded, so a later import of
    the same name must search again rather than be skipped as done. }
  savedCUC := CompiledUnitCount;
  if CompiledUnitCount < 256 then
  begin
    CompiledUnits[CompiledUnitCount] := strIdx;   { the NAME — what everyone else means }
    CompiledUnitKey[CompiledUnitCount] := guardIdx; { …the identity it dedupes on }
    CompiledUnitFile[CompiledUnitCount] := -1;  { filled in once resolved }
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
      { A NilPy program importing a SIBLING MODULE: `from settings import get`
        must find settings.py next to the importer, the way Python looks in the
        script's own directory first. Only for a NilPy compilation — a Pascal
        `uses` must never start pulling Python in
        (feature-nilpy-py-module-loader). }
      if isNilPy and pyLookupOK and (Length(UnitContent) = 0) then
      begin
        ConcatThree(basePath, '.py', '', path);
        LoadFile(path, UnitContent);
        if Length(UnitContent) = 0 then
        begin
          ConcatThree(basePath, '.npy', '', path);
          LoadFile(path, UnitContent);
        end;
        if Length(UnitContent) > 0 then isPyUnit := True;
      end;
    end;
    if Length(UnitContent) = 0 then
    begin
      ConcatThree('uses: unit source not found: ', basePath, '', emsg);
      Error(emsg);
    end;
  end;

  { A NILPY import looks for a sibling MODULE first, which is Python's own rule:
    the importing script's directory comes before anything the implementation
    ships. `from settings import get` must bind to settings.py next to the
    program even though the search chain below would reach lib/rtl first.
    Restricted to .py/.npy and to a NilPy compilation, so no Pascal `uses`
    resolution changes and a name with no local module still falls through to
    the RTL — which is how `import re` keeps finding lib/rtl/re.pas.
    (feature-nilpy-py-module-loader; the shadowing question this settles for
    NilPy is bug-nilpy-stdlib-name-binds-pascal-unit.) }
  { CurUnitDir only, never SourceFileDir: the directory that matters is the one
    holding the file doing the importing. For the program that IS its own
    directory (compiler.pas seeds CurUnitDir with it), which is Python's rule;
    for a Pascal unit it is that unit's directory, so `lib/pcl/tkinter.pas`'s
    `uses tk` cannot be hijacked by a stray tk.npy sitting next to the user's
    script — which is exactly what happened the first time a build ran out of a
    directory full of old test files. }
  if isNilPy and pyLookupOK and (not isPath) and (Length(UnitContent) = 0) then
  begin
    { An empty CurUnitDir means the importer was named without a directory
      (`pascal26 main.py`), so the bare name IS the relative path — the sibling
      is in the working directory. }
    { PyTryPackageSource, not two hand-rolled LoadFiles: a sibling may be a
      package DIRECTORY as well as a flat file. `from .inner import IN` passes
      the bare `inner` (the relative form skips the dots), and probing only
      `<CurUnitDir>/inner.py` missed `<CurUnitDir>/inner/__init__.py` — so a
      relative subpackage import failed with "no unit named inner" while the
      absolute `from pkg.inner import IN` on the SAME directory resolved fine.
      The resolver was never missing the package concept; the relative spelling
      simply never reached the probe that already knew it.
      bug-a-a-python-module-s-identity-is-its-name-not-its-file (symptom 2).

      Scope is unchanged — still the importing file's own directory, Python's
      own first rule — so the `tk.npy` shadowing note above still holds: this
      adds the `__init__` spelling, not a new root. }
    { …and for `from ..mod` the search starts one package UP, not here. The
      relative form passes the bare name (the dots are stripped by the
      frontend), so without the LEVEL every relative import was looked up in the
      importing file's own directory — right for `.`, wrong for every `..`.
      html5lib reaches its parent that way throughout (`filters/lint.py`:
      `from ..constants import namespaces`), and it failed as "no unit named
      constants" while the absolute `from html5lib.constants import ...` on the
      same tree resolved fine.
      bug-a-package-and-sibling-module-resolution-is-the-corpus-wall }
    PyTryPackageSource(PyRelativeDir(CurUnitDir, pyRelLevel), lo, True,
                       path, UnitContent);
    if Length(UnitContent) > 0 then isPyUnit := True;
  end;

  { A NILPY import that names a PACKAGE ON DISK. The sibling probe above is
    Python's first rule and only ever finds a FLAT module; a dotted path
    (`from mypkg.core.bus import Bus`) is a directory path under a package
    ROOT, and until this existed it had exactly one resolution — the
    `mimic_<mangled>` shim built to stand in for third-party libraries — so no
    multi-module package could be compiled from its own source at all
    (feature-nilpy-dotted-imports-resolve-to-source-files).

    SOURCE BEFORE SHIM, deliberately: the program's own tree wins over a
    bundled stand-in of the same dotted name, which is both Python's sys.path
    order (the script's directory first) and the spirit of
    own-language-first resolution. The shim mapping is untouched and still
    answers everything this misses, so `import reportlab.pdfgen` is unchanged.

    Roots, in order: the MAIN script's directory (Python's sys.path[0] — not
    CurUnitDir, because an ABSOLUTE dotted path is resolved from the package
    root no matter which submodule wrote it, which is what makes
    `mypkg/document/dom.py`'s own `from mypkg.core.bus import ...` resolve),
    then the working directory, then the -Fu roots.

    A SINGLE-SEGMENT name only probes the `<name>/__init__` package form here:
    `<name>.py` is already covered — by the sibling probe above and the library
    -root lookup far below — and re-trying it at THIS position would move a
    flat module ahead of the `.pas` chain and let a stray `re.py` shadow
    lib/rtl/re.pas (bug-nilpy-stdlib-name-binds-pascal-unit). A package
    DIRECTORY shadowing an RTL unit is Python's own answer and is the shape
    `from mypkg import Bus` needs. }
  if isNilPy and pyLookupOK and (not isPath) and (Length(UnitContent) = 0) and (pyDotted <> '') then
  begin
    probePath := PyDottedToRelPath(pyDotted);
    PyTryPackageSource(SourceFileDir, probePath, pyDottedIsPath,
                       path, UnitContent);
    PyTryPackageSource('', probePath, pyDottedIsPath, path, UnitContent);
    pyRootIdx := 0;
    while (Length(UnitContent) = 0) and (pyRootIdx < PasUnitDirCount) do
    begin
      PyTryPackageSource(PasUnitDirs[pyRootIdx], probePath, pyDottedIsPath,
                         path, UnitContent);
      Inc(pyRootIdx);
    end;
    if Length(UnitContent) > 0 then isPyUnit := True;
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
    begin
      ConcatThree(ExeDir, '../lib/rtl/', '', rtldir);
      { same two-levels-down re-anchor as the main block below — see its note }
      ConcatThree(rtldir, 'sysutils', '.pas', probeFile);
      LoadFileCI(probeFile, probeContent);
      if Length(probeContent) = 0 then
      begin
        ConcatThree(ExeDir, '../../lib/rtl/', '', probePath);
        ConcatThree(probePath, 'sysutils', '.pas', probeFile);
        LoadFileCI(probeFile, probeContent);
        if Length(probeContent) > 0 then rtldir := probePath;
      end;
      probeContent := '';
    end;
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

  { Library directories, anchored to the compiler binary. ONE owner, because
    `pxx --where` has to report the same answer this search uses — a diagnostic
    that re-derives the paths is a diagnostic that goes stale silently.
    feature-toolchain-cli-ux }
  ResolveToolchainDirs(cdir, bdir, rtldir, lcldir, asmdir);

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

  { AN IMPORT THAT PINNED ANOTHER LANGUAGE does not get a Pascal source. Tested
    on the path a probe actually LOADED, once, rather than by guarding each of
    the eight .pas/.pp probes above: the question is what was resolved, and a
    predicate repeated at eight sites is eight chances for one of them to drift.
    Probes only read files, so dropping the content here is the same as never
    having run them.
    The carve-out: a unit that declares itself a cpyext EXTENSION MODULE is a
    Python module, so a bare NilPy import of it was never the refusal's subject
    — see PyUnitDeclaresExtensionModule above. }
  pasRefusedPath := '';
  if (Length(UnitContent) > 0) and (not pasLookupOK) and PathIsPascalSource(path) and
     not ((pyImportLang = 'py') and PyUnitDeclaresExtensionModule(UnitContent)) then
  begin
    if pyImportLang = 'py' then pasRefusedPath := path;
    UnitContent := '';
    path := '';
  end;

  { HOST HEADERS. `import <c-header>` is a DESIGNED NilPy feature — the
    wrapper-free NilPy-to-C arc that `import sqlite3` and `import stdlib`
    (test_nilpy_import_sqlite, test_nilpy_c_pointer) depend on — so this route
    stays. What was wrong is its POSITION: it ran before the .py/.npy library
    lookup and before the mimic_ shim, so a Python stdlib name that ALSO names
    a C header lost to the header. `import string` found /usr/include/string.h
    and the failure surfaced later as `undefined variable (ascii_lowercase)`,
    pointing at the attribute rather than at the import.
    For a NilPy import these probes therefore run LATER — see the second call
    below, after everything Python-shaped has had its turn. Every other
    frontend keeps the original order.
    bug-nilpy-python-import-resolves-against-c-headers }
  if (Length(UnitContent) = 0) and (not isNilPy) then
    PyTryHostHeader(cName, path, UnitContent, isCUnit, isCHeader);

  { A NilPy module SHIPPED IN A LIBRARY ROOT. The sibling probe far above is
    Python's own rule (the importing file's directory wins), but when it misses,
    the rest of the chain resolves UNITS — `.pas` / `.pp` / `.c` / `.h` — and
    never `.py`. So a NilPy module placed in `lib/**` was unreachable: the
    identical file imported fine as a sibling and failed from `lib/pcl/` with
    "no unit named ...". That is what blocks shipping any library written in
    NilPy (feature-nilpy-import-a-py-module-from-the-library-path).

    Deliberately LAST among the real lookups, and before the mimic_ shim
    mapping only:

      - after every `.pas` lookup, so no program that compiles today can change
        resolution — a NilPy library does not silently shadow a same-named
        Pascal unit, and replacing one is an explicit swap (delete the .pas).
        The ordering here carries more subtlety than it looks
        (bug-nilpy-stdlib-name-binds-pascal-unit);
      - before the shim, because a module we actually ship should beat a
        mimic_ substitution for the same name.

    The sibling-first rule above is untouched — it is load-bearing (see the
    `tk.npy` note there). }
  if (Length(UnitContent) = 0) and isNilPy and pyLookupOK and (not isPath) then
  begin
    pyRootIdx := 0;
    while (Length(UnitContent) = 0) and (pyRootIdx < PasUnitDirCount) do
    begin
      ConcatThree(PasUnitDirs[pyRootIdx], lo, '.py', path);
      LoadFile(path, UnitContent);
      if Length(UnitContent) = 0 then
      begin
        ConcatThree(PasUnitDirs[pyRootIdx], lo, '.npy', path);
        LoadFile(path, UnitContent);
      end;
      Inc(pyRootIdx);
    end;
    if Length(UnitContent) = 0 then
    begin
      ConcatThree(rtldir, lo, '.py', path);   LoadFile(path, UnitContent);
    end;
    if Length(UnitContent) = 0 then
    begin
      ConcatThree(rtldir, lo, '.npy', path);  LoadFile(path, UnitContent);
    end;
    if Length(UnitContent) = 0 then
    begin
      ConcatThree(lcldir, lo, '.py', path);   LoadFile(path, UnitContent);
    end;
    if Length(UnitContent) = 0 then
    begin
      ConcatThree(lcldir, lo, '.npy', path);  LoadFile(path, UnitContent);
    end;
    if Length(UnitContent) > 0 then isPyUnit := True;
  end;

  { …and NOW the host headers for a NilPy import — but only when no mimic_ shim
    of that name exists, since a shim we ship IS the Python module and must beat
    a same-named C header. `import sqlite3` still reaches sqlite3.h (nothing
    ships a mimic_sqlite3), and `import string` will reach mimic_string the
    moment it is written. }
  if (Length(UnitContent) = 0) and isNilPy and (pyImportLang <> 'pas') and
     (not PyMimicShimExists(lo, rtldir, lcldir)) then
    PyTryHostHeader(cName, path, UnitContent, isCUnit, isCHeader);

  { THE COLLISION, NAMED. A bare import found a Pascal unit of that name and was
    refused it, and nothing Python-shaped answered either — so the honest
    failure says which unit it declined and how to ask for it on purpose,
    instead of "no unit named classes and no shim mimic_classes", which denies
    the existence of a file the resolver just read.

    After the .py/.npy and host-header probes and before the shim mapping: a
    mimic_ shim IS the Python module of that name, so if one exists it answers
    and there is no collision to report. }
  if (Length(UnitContent) = 0) and isNilPy and (pasRefusedPath <> '') and
     (not PyMimicShimExists(lo, rtldir, lcldir)) then
  begin
    emsg := 'import: ' + lo + ' is the Pascal unit ' + pasRefusedPath +
            ', not a Python module — a bare NilPy import resolves to Python '
            + '(.py/.npy) only. To reach the Pascal unit, name it with its '
            + 'extension: import ''' + lo + '.pas'' as ' + lo;
    Error(emsg);
  end;

  { NilPy SHIM MAPPING. A Python module we implement ourselves lives under OUR
    name — `mimic_<module>` — so no file in the tree carries an upstream package
    name and the tree says what each shim is. The mapping is consulted only
    after every ordinary lookup has failed, so a real unit of that name (lib/rtl
    /re.pas, a sibling .py) always wins and Pascal `uses` is untouched. A dotted
    package arrives here already mangled by the frontend, which is what makes
    `from reportlab.pdfgen import canvas` reach `mimic_reportlab_pdfgen` with no
    package-directory machinery. Reported, so a build says which shims it used.
    feature-nilpy-dotted-package-imports. }
  if (Length(UnitContent) = 0) and isNilPy and pyLookupOK and (not isPath) and
     (not softMissOK) and (Copy(lo, 1, 6) <> 'mimic_') then
  begin
    if NoShims then
    begin
      ConcatThree('import: no unit named ', lo,
                  ' (--no-shims refuses the mimic_ substitution)', emsg);
      Error(emsg);
    end;
    CurrentCLibrary := savedCurrentCLibrary;
    { Record the substitution as a unit ALIAS as well, so a QUALIFIER still
      resolves: `import pkga.sub as ps` registered ps -> pkga_sub, and the
      symbols live in mimic_pkga_sub. FindCompiledUnitOrAlias chases the chain. }
    if UnitAliasCount < MAX_UNIT_ALIASES then
    begin
      UnitAliasName[UnitAliasCount] := InternStr(lo);
      UnitAliasReal[UnitAliasCount] := InternStr('mimic_' + lo);
      Inc(UnitAliasCount);
    end
    else
      { silently dropping one is how `ttk` stopped resolving in a program with
        enough imports — the failure then lands at RUN time, far away }
      Error('too many unit aliases (raise MAX_UNIT_ALIASES)');
    ParseUsesUnit('mimic_' + lo);
    if SoftUnitMissed then
      { the shim was not there either: this import is a soft miss too, and the
        name must go back to unresolved so the fallback branch can bind it }
      CompiledUnitCount := savedCUC
    else
    begin
      { say which shim answered — a build should state what it substituted }
      ConcatThree('note: ', lo, ' -> mimic_' + lo + ' (shim, subset)', emsg);
      WriteLn(emsg);
    end;
    Exit;
  end;

  if Length(UnitContent) = 0 then
  begin
    { sysutils/baseunix/unix with no source on the path: pass as a no-op so
      builtin-only FPC code keeps compiling (the historical behavior). }
    if softMissOK then
    begin
      { The no-op is load-bearing for FPC compat — code that says `uses SysUtils`
        but only touches builtins must keep compiling — but it must not be
        SILENT. When it fires, the `uses` clause simply vanishes and every symbol
        it should have supplied fails one at a time, far from the cause, with a
        message that accuses the program: `undefined variable (Format)` and
        nothing anywhere naming sysutils.
        bug-a-uses-sysutils-silently-no-ops-when-the-rtl-is-not-on-the-search-path }
      Warn('uses ' + lo + ': no unit source on the search path; continuing with '
           + 'builtins only — symbols it would supply will report as undefined');
      CurrentCLibrary := savedCurrentCLibrary;
      Exit;
    end;
    { Probing the imports of a `try:` guarded by `except ImportError:` — report
      the miss to the caller instead of failing the compile, and leave no trace
      that this name was looked at. }
    if SoftUnitResolve then
    begin
      SoftUnitMissed := True;
      CompiledUnitCount := savedCUC;
      CurrentCLibrary := savedCurrentCLibrary;
      Exit;
    end;
    if Copy(lo, 1, 6) = 'mimic_' then
      { reached through the shim mapping above: name the module the source
        actually wrote, not our internal spelling }
      ConcatThree('import: no unit named ', Copy(lo, 7, Length(lo) - 6),
                  ' and no shim ' + lo, emsg)
    else
      ConcatThree('uses: unit source not found: ', lo, '', emsg);
    Error(emsg);
  end;

  { A PYTHON MODULE'S IDENTITY IS ITS FILE, not the spelling that reached it.
    CompiledUnits is keyed on the unit NAME, and the two ways to import one
    module arrive under two different names: `from .sub import X` passes the
    bare `sub` (the relative form deliberately skips the dots — NilPy's unit
    scope is flat), while `from pkg.sub import X` passes the mangled `pkg_sub`.
    Two keys, no dedupe, so the file was compiled TWICE:

      - its module body RAN twice, where CPython guarantees once. Import-time
        registry population is exactly this shape — `codecs.register(...)`, what
        webencodings does — so the duplicate is silent and cumulative;
      - every class in it existed as two distinct copies, and an object built by
        one fails `isinstance` against the other.

    Measured, and it is why the value-based test would never have caught it: the
    repro printed the RIGHT answer (`5 5`) while running the body twice. The
    defect is in how many times something happened.

    So: once resolution has picked a FILE, ask whether that file is already
    compiled under some other name. If it is, this spelling is a second name for
    one module — register it as a unit ALIAS (the mechanism the shim mapping
    already uses; FindCompiledUnitOrAlias chases the chain, so `pkg.sub.X` still
    resolves) and do not parse it again.

    GENERALISED 2026-08-20 from the `.py` arm to every load that resolved to a
    file — decide-one-answer-to-have-i-already-compiled-this-unit, option B. The
    question "is this the same translation unit?" had three answers (the NAME
    key, the `@cpath:` key space, this one), two of which are the same question;
    a key space per surprise is what
    devdocs/dev/root-cause-over-microfix.md says to stop repeating.

    Keyed on the resolved path TEXT, which is now NormalizePath'd for a path form
    at the guard above, so `./x` and `x` are one identity. Two roots reaching one
    file by genuinely different routes (a symlink, two -Fu roots onto one tree)
    still slip through: this compares strings, not inodes.

    THE SENTINEL: CompiledUnitFile is -1 for every entry not resolved to a file
    and -1 = -1, so an unguarded comparison makes every unresolved unit identical
    to every other and the second ambient/builtin unit is skipped as already
    compiled. It passes the whole suite and surfaces far away as a builtin that
    silently did not load. Hence `>= 0` below, and it is the reason this must not
    be split across commits.
    bug-a-a-python-module-s-identity-is-its-name-not-its-file (symptom 1). }
  if Length(path) > 0 then
  begin
    pyFileIdx := InternKey(path);   { a KEY, not an emitted string — see KeyStrs }
    pyDupIdx := -1;
    for i := 0 to CompiledUnitCount - 1 do
      if (CompiledUnitFile[i] >= 0) and (CompiledUnitFile[i] = pyFileIdx) then
        pyDupIdx := i;
    if pyDupIdx >= 0 then
    begin
      { …but only when the two spellings are two NAMES. The same path written
        twice (`uses './x.c'` and `uses 'x.c'`) resolves to one name too, and
        aliasing a name to itself is a wasted slot in a table small enough to
        run out — MAX_UNIT_ALIASES exhaustion is an Error, not a degradation. }
      if CompiledUnits[pyDupIdx] <> strIdx then
      begin
        if UnitAliasCount < MAX_UNIT_ALIASES then
        begin
          UnitAliasName[UnitAliasCount] := strIdx;
          UnitAliasReal[UnitAliasCount] := CompiledUnits[pyDupIdx];
          Inc(UnitAliasCount);
        end
        else
          Error('too many unit aliases (raise MAX_UNIT_ALIASES)');
      end;
      { The alias answers a QUALIFIER; it does not make the module's symbols
        VISIBLE. Visibility is per uses-edge (symtab.inc:799) and the edge
        recorded on entry points at the SPELLING (`pkg_sub`), while the symbols
        are registered under the name the file was first compiled as (`sub`) —
        so without this, `from pkg.sub import C` left C unresolvable and
        isinstance reported "unknown type". Measured both ways round: whichever
        spelling lost the race was the one that broke, which is what says the
        missing thing is the edge and not the alias. }
      RecordUsesEdge(CurrentUnitIdx, CompiledUnits[pyDupIdx], InInterface);
      CurrentCLibrary := savedCurrentCLibrary;
      Exit;
    end;
    { Not a duplicate — record the file against the entry claimed above, so the
      NEXT spelling of it finds this one. }
    if (savedCUC >= 0) and (savedCUC < CompiledUnitCount) then
      CompiledUnitFile[savedCUC] := pyFileIdx;
  end;

  if isPyUnit then
  begin
    { A `.py` module: lex it onto the end of the token stream, parse it as this
      unit, then put the importer's own position back — the same shape the C and
      Pascal branches below use. }
    savedTokPos := TokPos;
    savedCurTokKind := CurTok.Kind;
    savedCurTokSVal := CurTok.SVal;
    savedCurTokIVal := CurTok.IVal;
    savedCurTokLine := CurTok.Line;
    savedUnitDir := CurUnitDir;
    CurUnitDir := GetFilePath(path);
    savedCurrentUnitIdx := CurrentUnitIdx;
    CurrentUnitIdx := strIdx;

    startPos := PyLexAppend(UnitContent);
    { -g: give the module its own .debug_line file entry, so a breakpoint
      inside it resolves and its frames show real lines instead of the line-0
      treatment every appended source otherwise gets. Registered BEFORE the
      parse: AllocNode consults the range as it builds the module's nodes. }
    DbgMarkTokFile(startPos, DbgFileId(path));
    TokPos := startPos;
    Next;
    ParsePyUnit(lo);

    CurrentUnitIdx := savedCurrentUnitIdx;
    CurUnitDir := savedUnitDir;
    TokPos := savedTokPos;
    CurTok.Kind := savedCurTokKind;
    CurTok.SVal := savedCurTokSVal;
    CurTok.IVal := savedCurTokIVal;
    CurTok.Line := savedCurTokLine;
    Exit;
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

    { pxx's own C headers belong on the `<>` search path here too. Only the
      C-PROGRAM path registered them, so a `.c` pulled from a Pascal or NilPy
      program resolved `#include <stdarg.h>` to the HOST header — whose va_list
      is __builtin_va_list, which pxx cannot lower, so every variadic C file
      failed with the va_list local reported as an undeclared identifier.
      bug-cfront-unit-globals-unregistered. }
    AddDefaultCIncludeDirs;

    { …and so does the C RUNTIME BRIDGE. A C translation unit lowers `malloc`
      onto pxxcio's `__pxx_malloc` and `write` onto `__pxx_write` whatever
      pulled it in, but only the C-PROGRAM path (cparser.inc's entry stub)
      marked those units ambient. A `.c` reached through a Pascal unit's uses
      clause therefore had no visibility edge to them, so under --strict-uses
      the lowering found no bodied proc, left the name a real external, and the
      program died at LOAD with `undefined symbol: __pxx_malloc`.

      Ambient for exactly the reason builtin/builtinheap/pylib already are:
      these hold the runtime helpers CODEGEN emits calls to, and no source
      clause could have declared them — the C TU has no uses clause at all.
      Same guard as the C-program pull, and idempotent, so an enclosing unit
      that already says `uses pxxcio` (lib/pcl's reportlab shims do) is
      unaffected.

      Exactly the shape of the AddDefaultCIncludeDirs fix directly above, which
      had the same cause: something the C-PROGRAM path registered and the
      pulled-from-a-unit path did not.
      bug-pascal-uses-is-transitive }
    if (not NoDefaultRtl) and (not TargetIsEspClass) then
    begin
      { UnitContent is a GLOBAL holding the C source we are about to
        preprocess, and a nested unit load overwrites it with ITS source. The
        first cut of this pull left that unsaved, so from here on the compiler
        preprocessed pxxcio.pas as if it were the C file: every declaration in
        the real header vanished and `uses <someheader>` reported the header's
        own functions as undefined variables, with no diagnostic pointing
        anywhere near the cause (regression from 63d1d0de9, caught by
        examples/life's GTK binding). }
      savedUnitContent := UnitContent;
      ParseUsesUnitAmbient('builtinheap');
      ParseUsesUnitAmbient('pxxcio');
      UnitContent := savedUnitContent;
    end;
{$ifdef PXX_NO_CFRONT}
    Error('this compiler was built without the C frontend (PXX_NO_CFRONT), '
          + 'so it cannot load the C source ' + path);
    startPos := 0;
{$else}
    CPreprocess(UnitContent, GetFilePath(path));

    { Append preprocessed tokens using C Lexer }
    startPos := CLexAppend(UnitContent);
{$endif}

    TokPos := startPos;
    Next;

    { C symbols are case-sensitive: force the mode so their proc names match
      exactly (the link symbol is exact), independent of the host's setting.
      Restored after so it does not leak into the including unit. }
    savedCaseMode := CaseSensitiveMode;
    savedCurrentUnitIdx := CurrentUnitIdx;
    CurrentUnitIdx := strIdx;
    { A .c SOURCE joins the program's flat C external-linkage namespace — see
      CTUnitIdx (defs.inc). A .h does not: a header pulled through `uses` names
      a foreign library's exports, which stay real externals.
      bug-c-sibling-translation-units-cannot-see-each-other }
    if not isCHeader then MarkUnitCTranslationUnit(strIdx);
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
      bug-unit-mode-directives-leak).

      DelphiMode moves with NestedComments and always has to: ONE line in
      lexer.inc's {$mode} handler sets both, so scoping one and not the other
      leaves half a directive leaking. It leaked for months without being
      noticed, because every mode a unit actually declared happened to set
      DelphiMode to its default value — until {$MODE PXX} was added to 136
      lib/rtl units, and from then on any `uses` of the RTL silently turned
      {$mode delphi} OFF for the rest of the program.
      bug-a-a-units-mode-directive-turns-delphi-mode-off-for-the-program }
    savedCaseMode := CaseSensitiveMode;
    savedNestedComments := NestedComments;
    savedDelphiMode := DelphiMode;
    { A PASCAL unit is parsed with PASCAL expression rules, whoever pulled it
      in. NilPy turns on Python's and/or/not precedence for its own body, and a
      `.py` MODULE that imports a Pascal unit (settings.py -> configparser)
      reached this branch with the flag still on: `(c >= 'A') and (c <= 'Z')`
      then failed on `and`. Restored below with the rest of the per-unit modes. }
    savedPyExprMode := PyExprMode;
    PyExprMode := False;
    { fresh per-unit default: FPC lexes each unit under its OWN mode — an
      includer's {$MODE DELPHI} (NestedComments off) must not change how this
      unit's comments nest. The unit's own MODE/NESTEDCOMMENTS directives
      still apply to it, and the caller's state is restored below. }
    NestedComments := True;
    savedCurrentUnitIdx := CurrentUnitIdx;
    CurrentUnitIdx := strIdx;
    { A PASCAL unit reached through a NilPy plain `import` is qualified-only —
      `import math` binds the name `math`, not the module's contents. Marked
      here, in the Pascal branch alone: a `.py` module import and every Pascal
      `uses` never reach this line with the flag set.
      bug-nilpy-import-leaks-the-units-names-into-the-python-namespace }
    if PyImportPending then MarkUnitQualifiedOnly(strIdx);

    { Pascal `{$define}` is scoped to the UNIT that writes it (like FPC/Delphi
      and like a C translation unit) — save the define table now and restore
      it once this unit is fully lexed AND parsed, below. Snapshotting here
      (before ExpandIncludes) rather than resetting anything means a nested
      `{$i}` still inherits the INCLUDING unit's ambient defines, which is the
      one case top-down visibility is correct for
      (bug-pascal-defines-leak-across-units): without this, `{$define}` in one
      unit stayed visible in every unit parsed afterward, so `{$ifdef}`
      compiled different code depending on `uses` ORDER, silently. Command-
      line/target-seeded defines (PasInitDefines, called once before any unit
      parses) are untouched by this — they are added before the first save and
      so survive every restore, same as an FPC/Delphi unit inherits its `-d`
      defines. Only Active/HasValue/Value + Count/CharLen are saved, matching
      ExpandIncludes' own save/restore shape below: PasDefineNameOff/NameLen
      are write-once per slot and only ever read up to Count, so rolling Count
      back is enough to also undo any NEW names this unit's own {$define}s
      registered. }
    savedPasDefineCount := PasDefineCount;
    savedPasDefineCharLen := PasDefineCharLen;
    for pdi := 0 to MAX_PAS_DEFINES - 1 do
    begin
      savedPasDefineActive[pdi] := PasDefineActive[pdi];
      savedPasDefineHasValue[pdi] := PasDefineHasValue[pdi];
      savedPasDefineValue[pdi] := PasDefineValue[pdi];
    end;

    { The unit names itself, so its own line markers are right and a diagnostic
      inside it can say which file it is in. This passed '' until 2026-08-21, to
      keep the unit out of the DWARF line table (the RTL would swamp it) — that
      is now arranged by LexMarkDbgLines instead, because suppressing the
      markers also suppressed correct LINE NUMBERS for every include the unit
      pulls. bug-a-a-parse-error-in-a-used-unit-reports-a-line-in-no-file }
    ExpandIncludes(UnitContent, GetFilePath(path), path);
    ExpandPasMacros(UnitContent);

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
    if unitNeedsText and (not NoDefaultRtl) and (not TargetIsEspClass) then
    begin
      ParseUsesUnitAmbient('builtin');
      ParseUsesUnitAmbient('textfile');
    end;

    { Point parser to first token of the unit }
    TokPos := startPos;
    Next;

    { Parse the unit }
    ParseUnit;

    { Undo every {$define}/{$undef} this unit made — see the save above. }
    PasDefineCount := savedPasDefineCount;
    PasDefineCharLen := savedPasDefineCharLen;
    for pdi := 0 to MAX_PAS_DEFINES - 1 do
    begin
      PasDefineActive[pdi] := savedPasDefineActive[pdi];
      PasDefineHasValue[pdi] := savedPasDefineHasValue[pdi];
      PasDefineValue[pdi] := savedPasDefineValue[pdi];
    end;

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
    DelphiMode := savedDelphiMode;
    PyExprMode := savedPyExprMode;
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
    if (UnitAliasCount < MAX_UNIT_ALIASES) and (aStrIdx <> realStrIdx) then
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
procedure ParseInitializationSection(const uname: AnsiString; isFini: Boolean);
var
  procIdx, savedSC, savedFS, savedGLC, savedGFC, j, patchPos: Integer;
  seqNode, lastSeq, stmtNode: Integer;
  dummyNames: array[0..0] of AnsiString;
  dummyTypes: array[0..0] of TTypeKind;
begin
  if isFini then
    procIdx := RegisterProc('__fini_' + uname, False, tyInteger, 0, dummyNames, dummyTypes)
  else
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
      tkConst: ParseConstSection(-1, 0);
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
  ASTNodeCount := ASTArenaFloor;

  EmitProcEpilog(-1);
  PatchProcPrologue(patchPos, FrameSize);

  SymRollbackTo(savedSC); FrameSize := savedFS;
  GotoLabelCount := savedGLC; GotoFixupCount := savedGFC;
  CurProc := -1;

  if isFini then
  begin
    if FiniProcCount < 256 then
    begin
      FiniProcs[FiniProcCount] := procIdx;
      Inc(FiniProcCount);
    end;
  end
  else if InitProcCount < 256 then
  begin
    InitProcs[InitProcCount] := procIdx;
    Inc(InitProcCount);
  end;
end;

{ Emit the __pxx_run_finalizers body: the registered unit finalizers in
  REVERSE init order, behind a run-once BSS guard (so a Halt inside a
  finalizer cannot recurse). Emitted after the main body — every unit's
  __fini_ proc exists by then; Halt sites called the shell forward and
  ApplyCallFixups resolves them. Runs (as a no-op shell) even when no unit
  has a finalization section, iff some Halt site registered the shell.
  Called before ApplyCallFixups by every frontend driver. }
procedure EmitFinalizerRunnerBody;
var
  procIdx, j, patchPos, savedSC, savedFS: Integer;
  identN, litN, condN, asgN, callN, seqN, lastSeq, pairN, ifN: Integer;
begin
  if (FiniRunnerProc < 0) and (FiniProcCount = 0) then Exit;
  procIdx := GetFiniRunnerProc;
  FiniGuardSym := AllocVar('__pxx_fini_done', tyInteger);  { CurProc<0: BSS, zeroed }

  if TargetArch = TARGET_XTENSA then
    while (CodeLen mod 4) <> 0 do xtensa_nop;
  Procs[procIdx].BodyAddr := CodeLen;
  savedSC := SymCount; savedFS := FrameSize;
  FrameSize := 0;
  CurProc := procIdx;
  Procs[procIdx].ScopeBase := SymCount;
  patchPos := EmitProcPrologue;
  Procs[procIdx].FramePatch := patchPos;
  if (TargetArch = TARGET_XTENSA) and (XtensaABI = XTENSA_ABI_WINDOWED) then
    xtensa_mov(reg_xtensa_a7, reg_xtensa_a15);

  { if __pxx_fini_done = 0 then begin
      __pxx_fini_done := 1; __fini_<N-1>; ...; __fini_<0> end }
  identN := AllocNode(AN_IDENT);
  ASTIVal[identN] := FiniGuardSym; ASTTk[identN] := Ord(tyInteger);
  litN := AllocNode(AN_INT_LIT);
  ASTIVal[litN] := 0; ASTTk[litN] := Ord(tyInteger);
  condN := AllocNode(AN_BINOP);
  ASTIVal[condN] := Ord(tkEq);
  ASTLeft[condN] := identN; ASTRight[condN] := litN;
  ASTTk[condN] := Ord(tyBoolean);

  identN := AllocNode(AN_IDENT);
  ASTIVal[identN] := FiniGuardSym; ASTTk[identN] := Ord(tyInteger);
  litN := AllocNode(AN_INT_LIT);
  ASTIVal[litN] := 1; ASTTk[litN] := Ord(tyInteger);
  asgN := AllocNode(AN_ASSIGN);
  ASTLeft[asgN] := identN; ASTRight[asgN] := litN;

  seqN := AllocNode(AN_SEQ);
  ASTLeft[seqN] := asgN;
  lastSeq := seqN;
  for j := FiniProcCount - 1 downto 0 do
  begin
    callN := AllocNode(AN_CALL);
    ASTIVal[callN] := FiniProcs[j];
    ASTTk[callN] := Ord(tyInteger);
    ASTRight[lastSeq] := AllocNode(AN_SEQ);
    lastSeq := ASTRight[lastSeq];
    ASTLeft[lastSeq] := callN;
  end;

  pairN := AllocNode(AN_PAIR);
  ASTLeft[pairN] := seqN; ASTRight[pairN] := -1;
  ifN := AllocNode(AN_IF);
  ASTLeft[ifN] := condN; ASTRight[ifN] := pairN;
  CompileAST(ifN);
  ASTNodeCount := ASTArenaFloor;

  EmitProcEpilog(-1);
  PatchProcPrologue(patchPos, FrameSize);
  SymRollbackTo(savedSC); FrameSize := savedFS;
  CurProc := -1;
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
  { `unit X deprecated 'use Y instead';` -- FPC and Delphi both accept a hint
    directive on the unit declaration, and a DEPRECATED unit is exactly the kind
    a real codebase keeps around for compatibility, so refusing it means the
    unit cannot be compiled at all. Synapse's ssl_openssl.pas ends with one.
    Same soft-identifier run every other declaration site already skips; the
    directive is advisory, so parse-and-ignore is the whole behaviour.
    compat-pascal-unit-deprecated-hint-directive }
  SkipHintDirectives;
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
      tkConst:    ParseConstSection(-1, 0);
      tkType:     ParseTypeSection;
      tkClass,
      tkProcedure,
      tkFunction: ParseSubroutine;
      tkIdent:
        { `resourcestring` sections (FPC rtlconsts et al) register as plain
          string constants — pxx has no resource tables; the format-arg
          machinery lives in whoever consumes the string. }
        if CaseEqual(CurTok.SVal, 'resourcestring') then ParseConstSection(-1, 0)
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
        tkConst:    ParseConstSection(-1, 0);
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
        tkBegin:
        begin
          { Classic Turbo-Pascal `begin ... end.` unit initialization — same
            emission as `initialization` (it was parsed, accepted, and silently
            dropped: bug-unit-init-begin-form-not-executed). The body's closing
            `end.` doubles as the unit terminator; ParseInitializationSection
            stops AT that `end`, which the tkEnd/tkDot check above then sees. }
          Next;                       { consume 'begin' }
          PreScanPass := False;
          ParseInitializationSection(uname, False);
          PreScanPass := True;
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
            ParseInitializationSection(uname, False);
            PreScanPass := True;
          end
          else if CaseEqual(CurTok.SVal, 'finalization') then
          begin
            { finalization emits its body in place, registered into FiniProcs;
              the exit chain runs them in reverse init order
              (bug-unit-finalization-not-executed). }
            Next;                       { consume 'finalization' }
            PreScanPass := False;
            ParseInitializationSection(uname, True);
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
            ParseConstSection(-1, 0)    { registers as plain string constants }
          else
            Next;
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
