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
    innerAddr, pk: Integer;
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
      { Record typed-const field: `sym.field := value`, and then any DEEPER
        spans — `sym.p.x`. One loop over the path, exactly as
        CompilePendingGlobalInits does it; the two emitters must not drift. }
      target := AllocNode(AN_FIELD);
      ASTLeft[target] := identNode;
      ASTSOffset[target] := LocalInitFOff[i];
      ASTSLen[target] := LocalInitFLen[i];
      ASTTk[target] := initTk;
      for pk := 0 to LocalInitPCount[i] - 1 do
      begin
        valNode := AllocNode(AN_FIELD);
        ASTLeft[valNode] := target;
        ASTSOffset[valNode] := PIPathOff[LocalInitPStart[i] + pk];
        ASTSLen[valNode] := PIPathLen[LocalInitPStart[i] + pk];
        ASTTk[valNode] := initTk;
        target := valNode;
      end;
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
      ASTSLen[valNode] := LocalInitValAux[i];
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
    else if LocalInitKind[i] = 9 then
    begin
      { SET element of a routine-local const array -- Val is the Data[] offset of
        the baked 32-byte mask (same encoding as the global path's kind 9,
        deliberately: the two emitters must not drift). }
      valNode := AllocNode(AN_SET_CONST_REF);
      ASTIVal[valNode] := LocalInitVal[i];
      ASTTk[valNode] := Ord(tySet);
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
  else if (Syms[symIdx].TypeKind = tyVariant) and not Syms[symIdx].IsArray then
  begin
    { Variant and managed record have no empty-value LITERAL to assign, which
      is why the assignment trick above stopped at three kinds. They go through
      the finalize primitive instead — the same AN_MANAGED_INIT node
      `Finalize(x)` builds, which by then knew both kinds. So this is still not
      a new emitter: it is the intrinsic the user can already write by hand,
      emitted at the head of the body.

      `Finalize`, not `Initialize`: an out param's incoming bytes ARE the
      caller's live references, and dropping them without releasing is the leak
      the ticket names. PXXVarClear reads the tag, releases what that tag says
      is a reference, and writes VT_EMPTY — idempotent, so a callee that also
      calls Finalize(v) itself decrements nothing the second time.
      feature-a-finalize-an-out-variant-and-managed-record }
    valNode := AllocNode(AN_MANAGED_INIT);
    ASTLeft[valNode] := identNode;
    ASTIVal[valNode] := 1;                { 1 = Finalize }
    CompileAST(valNode);
    Result := True;
    Exit;
  end
  else if (Syms[symIdx].TypeKind = tyRecord) and not Syms[symIdx].IsArray and
          RecordHasManagedFields(SymTR[symIdx].RecId) then
  begin
    { Managed record: PXXRecordFinalize releases each managed field and nils
      it, leaving the UNMANAGED members alone — which is FPC's `out` exactly.
      A record with no managed fields is deliberately not cleared: FPC does not
      finalize it either, so the caller's value survives, and zeroing it here
      would be a divergence in the other direction (the same trap the ordinal
      rows of the test guard against). }
    valNode := AllocNode(AN_MANAGED_INIT);
    ASTLeft[valNode] := identNode;
    ASTIVal[valNode] := 1;                { 1 = Finalize }
    CompileAST(valNode);
    Result := True;
    Exit;
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
    { NestIsRoutineDecl, not a bare keyword test: a procedural TYPE
      (`type TP = procedure(l: LongInt);`, `var cb: procedure;`) starts with the
      same keyword and is NOT a nested routine. This walk used to take the
      keyword alone, skip the "signature", eat the `;` and then hunt for that
      phantom routine's `begin` — which found the ENCLOSING routine's, so the
      real body was consumed as the phantom's and the parse ran off the end of
      the program. Any routine-local procedural type did it; a local record or
      pointer type was fine. NestIsRoutineDecl already carries exactly this
      discrimination, and documents it; this was a second hand-written copy
      that omitted it. bug-a-a-routine-local-procedural-type-eats-the-body }
    if NestIsRoutineDecl(TokPos - 1) then
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
            (CurTok.Kind = tkOverload) or IsCallConvDirectiveTok or
            IsInertRoutineDirectiveTok do
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

{ Does `recId` contain a managed field the FIELD WALK below cannot reach?

  The walk descends plain record-typed fields. It does not descend an ARRAY
  field -- `arr: array[0..1] of TFoo` inside a record needs the same synthesised
  loop the array-of-record symbol case needs, and that is the other arm of
  feature-pascal-management-operators-nested-and-array. Those stay REFUSED
  rather than silently skipped, which is this pass's whole convention: a
  declared invariant that never runs is a plausible wrong value far from the
  cause.

  UFldTk carries the ELEMENT kind for an array field, so `tyRecord` alone does
  not separate the two; UFldIsArray is what does. }
function RecContainsUnreachableManagedField(recId, depth: Integer): Boolean;
var ci, i, base, cnt, frec: Integer;
begin
  Result := False;
  if (recId < REC_UCLASS_BASE) or (depth > 8) then Exit;
  ci := recId - REC_UCLASS_BASE;
  base := UClsFBase[ci];
  cnt := UClsFCount[ci];
  for i := 0 to cnt - 1 do
    if IntToTypeKind(UFldTk[base + i]) = tyRecord then
    begin
      frec := UFldRec_[base + i];
      if UFldIsArray[base + i] then
      begin
        if RecHasManagementOp(frec) or RecContainsManagementOp(frec, depth + 1) then
        begin
          Result := True;
          Exit;
        end;
      end
      else if RecContainsUnreachableManagedField(frec, depth + 1) then
      begin
        Result := True;
        Exit;
      end;
    end;
end;

{ Append one management-operator call for `argNode` to a seq chain. The two
  copies this replaces differed only in which overload kind they asked for. }
procedure AppendManagedOpCall(opIdx, argNode: Integer; var head, tail: Integer);
var callNode, newSeq: Integer;
begin
  callNode := GenMakeCall6(opIdx, tyUnknown, argNode, -1, -1, -1, -1, -1);
  newSeq := GenMakeSeq(callNode, -1);
  if head = -1 then head := newSeq else ASTRight[tail] := newSeq;
  tail := newSeq;
end;

{ Walk the managed fields of `recId` under `baseNode` and append their calls.

  ORDER IS MEASURED, NOT ASSUMED, and it is not the same in both directions.
  Against fpc 3.2.2, for a record that has its OWN operator and a managed field:

      init Foo   <- the FIELD                 Initialize: fields, then self
      init Bar   <- the containing record
      fin  Bar   <- the containing record     Finalize:   self, then fields
      fin  Foo   <- the FIELD

  So Initialize is POST-order and Finalize is PRE-order, the construct/destruct
  symmetry. Within one level it is declaration order FORWARD for both -- fpc
  does NOT reverse siblings, array elements or the locals of a scope on the way
  out, which is the part that looks wrong beside the nesting rule and was
  measured separately (`a`, `n.p`, `n.q`, `b` finalize 0,1,2,3).

  `baseNode` is CLONED at every use. It has to be: the same path appears once as
  a call argument and again as the base of the recursion, and CloneAST exists
  for exactly this ("a value node must appear in two places without the two
  occurrences aliasing one node"). Sharing it would put one node under two
  parents.

  Array fields are skipped here and refused by the caller -- see
  RecContainsUnreachableManagedField. }
procedure AppendManagedFieldOps(baseNode, recId, depth, opk: Integer;
                                postOrder: Boolean; var head, tail: Integer);
var ci, i, base, cnt, frec, fldNode, opIdx: Integer;
begin
  if (recId < REC_UCLASS_BASE) or (depth > 8) then Exit;
  ci := recId - REC_UCLASS_BASE;
  base := UClsFBase[ci];
  cnt := UClsFCount[ci];
  for i := 0 to cnt - 1 do
    if (IntToTypeKind(UFldTk[base + i]) = tyRecord) and
       (not UFldIsArray[base + i]) and
       (UFldRec_[base + i] <> REC_NONE) then
    begin
      frec := UFldRec_[base + i];
      if RecHasManagementOp(frec) or RecContainsManagementOp(frec, depth + 1) then
      begin
        fldNode := AllocNode(AN_FIELD);
        ASTLeft[fldNode] := CloneAST(baseNode);
        ASTSOffset[fldNode] := UFldNOff[base + i];
        ASTSLen[fldNode] := UFldNLen[base + i];
        ASTTk[fldNode] := Ord(tyRecord);
        opIdx := FindOpOverload(opk, Ord(tyRecord), frec);
        if postOrder then
        begin
          AppendManagedFieldOps(fldNode, frec, depth + 1, opk, postOrder, head, tail);
          if opIdx >= 0 then AppendManagedOpCall(opIdx, CloneAST(fldNode), head, tail);
        end
        else
        begin
          if opIdx >= 0 then AppendManagedOpCall(opIdx, CloneAST(fldNode), head, tail);
          AppendManagedFieldOps(fldNode, frec, depth + 1, opk, postOrder, head, tail);
        end;
      end;
    end;
end;

{ Append one statement to a management-operator seq chain. }
procedure AppendManagedStmt(stmtNode: Integer; var head, tail: Integer);
var newSeq: Integer;
begin
  newSeq := GenMakeSeq(stmtNode, -1);
  if head = -1 then head := newSeq else ASTRight[tail] := newSeq;
  tail := newSeq;
end;

{ `k := lo; while k <= hi do begin <element ops>; k := k + 1 end` for a FIXED
  array of a managed record.

  A fixed array symbol keeps its bounds as `ConstVal` (the LOW bound -- see
  AllocArray, which stores it there) and `ArrLen`. The loop runs in SOURCE index
  space, not 0-based: the AN_INDEX node it builds is read exactly the way `a[3]`
  in the source is, so for `array[3..5] of TFoo` it must run 3..5.
  test_mgmt_operators_array covers a non-zero lower bound for that reason -- a
  0-based loop is right for the 0-based declaration and silently initializes the
  wrong three slots for the other one.

  ORDER: elements ASCENDING for both Initialize and Finalize. fpc does not
  reverse array elements on the way out; measured against 3.2.2, `init 0/1/2`
  then `fin 0/1/2`. That is the same forward rule that holds for sibling fields
  and for a scope's locals, and it is NOT the pre/post-order rule that holds
  ACROSS nesting levels -- which still applies WITHIN one element, so the body
  is built by the same AppendManagedFieldOps walk a plain record local gets.

  Built as an AN_WHILE with the increment at the BOTTOM of the body. The for-in
  desugars deliberately put theirs at the TOP because AN_WHILE's continue target
  is the condition test, so a `Continue` in a user body would skip a bottom
  increment and spin forever. That hazard cannot arise here: the body is
  synthesised operator calls and contains no user statement to `Continue` from. }
procedure AppendManagedArrayOps(symIdx, recId, opk, lo, hi: Integer;
                                postOrder: Boolean; var head, tail: Integer);
var kSym, condN, idxN, incN, whileN, opIdx: Integer;
    bHead, bTail: Integer;
begin
  bHead := -1; bTail := -1;
  kSym := AllocVar('', tyInteger);
  idxN := AllocNode(AN_INDEX);
  ASTLeft[idxN]  := GenMakeIdent(symIdx, tyRecord);
  ASTRight[idxN] := GenMakeIdent(kSym, tyInteger);
  ASTTk[idxN]    := Ord(tyRecord);
  opIdx := FindOpOverload(opk, Ord(tyRecord), recId);
  if postOrder then
  begin
    AppendManagedFieldOps(idxN, recId, 0, opk, postOrder, bHead, bTail);
    if opIdx >= 0 then AppendManagedOpCall(opIdx, CloneAST(idxN), bHead, bTail);
  end
  else
  begin
    if opIdx >= 0 then AppendManagedOpCall(opIdx, CloneAST(idxN), bHead, bTail);
    AppendManagedFieldOps(idxN, recId, 0, opk, postOrder, bHead, bTail);
  end;
  { No operator anywhere in the element: emit nothing at all rather than a loop
    whose body is empty, which would still cost hi-lo+1 iterations at runtime. }
  if bHead = -1 then Exit;
  incN := GenMakeAssign(GenMakeIdent(kSym, tyInteger),
                        GenMakeArith(Ord(tkPlus), GenMakeIdent(kSym, tyInteger),
                                     GenMakeIntLit(1)));
  AppendManagedStmt(incN, bHead, bTail);
  condN := GenMakeCmp(Ord(tkLe), GenMakeIdent(kSym, tyInteger), GenMakeIntLit(hi));
  whileN := AllocNode(AN_WHILE);
  ASTLeft[whileN]  := condN;
  ASTRight[whileN] := bHead;
  AppendManagedStmt(GenMakeAssign(GenMakeIdent(kSym, tyInteger),
                                  GenMakeIntLit(lo)), head, tail);
  AppendManagedStmt(whileN, head, tail);
end;

{ True iff an array symbol is the shape AppendManagedArrayOps can iterate: one
  dimension, a FIXED extent known here, and record ELEMENTS rather than
  dynamic-array handles. Spelled once because the refusal below and the emission
  below it must agree -- a shape the refusal lets through and the emission skips
  is a declared Initialize that silently never runs, which is the exact defect
  regression-test-core-test-mgmt-operators was written for. }
function SymIsLoopableManagedArray(idx: Integer): Boolean;
begin
  SymIsLoopableManagedArray :=
    Syms[idx].IsArray and (Syms[idx].TypeKind = tyRecord) and
    (Syms[idx].ArrLen > 0) and (SymArrNDims[idx] <= 1) and
    (SymElemDynDepth[idx] = 0) and (SymTR[idx].ElemRec <> REC_NONE);
end;

{ The record id a symbol's management operators would belong to.

  For a plain record variable that is `RecName` (mirrored as `SymTR[].RecId`).
  For an ARRAY of records it is `ElemRecName` — `RecName` is meaningless there,
  because only AllocVar/AllocParam ever write it.

  Split out because reading `RecId` for an array symbol was wrong in the way
  that hides: symbol slots are RECYCLED, so an array's `RecName` held whatever
  the previous occupant left behind, and for `var arr: array[0..1] of TFoo`
  inside a proc that was reliably TFoo itself. The refusal below therefore
  fired, correctly, for the wrong reason — until `4a3c88532` cleared the field
  on recycle and the refusal went silent, letting an array of a managed record
  compile with an Initialize that never runs. That commit did not cause this;
  it removed the accident this was standing on, and named the class in its own
  message: twenty more `RecName` reads guarded by `TypeKind = tyRecord`, which
  is not a guard at all for an array symbol, since that field carries the
  ELEMENT kind.
  regression-test-core-test-mgmt-operators
  bug-a-allocarray-leaves-recname-stale-on-a-recycled-symbol-slot }
function SymManagedRecId(idx: Integer): Integer;
begin
  if Syms[idx].IsArray then SymManagedRecId := SymTR[idx].ElemRec
  else SymManagedRecId := SymTR[idx].RecId;
end;

function WrapManagementOpsRange(loSym, hiSym, retSym: Integer; wantGlobal: Boolean;
                               bodyNode: Integer): Integer;
var i, ip, fp, headInit, tailInit, headFin, tailFin, tryNode: Integer;
    mrec, alo: Integer;
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
    mrec := SymManagedRecId(i);
    if isTarget and (mrec <> REC_NONE) and
       (Syms[i].TypeKind in [tyRecord, tyClass]) then
    begin
      { A fixed one-dimensional array of a managed record is a synthesised loop
        now; a DYNAMIC or MULTI-DIMENSIONAL one still is not, because neither
        has bounds this pass can read -- a dynamic array's extent is a runtime
        length and the desugar would have to call Length(). }
      if Syms[i].IsArray and (not SymIsLoopableManagedArray(i)) and
         (RecHasManagementOp(mrec) or RecContainsManagementOp(mrec, 0)) then
        Error('a dynamic or multi-dimensional array of a record with a management '
              + 'operator is not supported yet '
              + '(feature-pascal-management-operators-nested-and-array)');
      { ...and a loopable array whose ELEMENT hides a managed field behind an
        array field keeps the refusal the element's own shape would get. }
      if SymIsLoopableManagedArray(i) and
         RecContainsUnreachableManagedField(mrec, 0) then
        Error('a field of a record with a management operator is not managed yet '
              + '(feature-pascal-management-operators-nested-and-array)');
      { A CLASS field is still refused, and it is not the same shape at all: a
        class instance's lifetime is not scope-bound. Measured against fpc
        3.2.2 -- for `c: TCls` whose field is a managed record, fpc runs the
        field's Initialize at TCls.Create and NEVER runs Finalize, because
        nothing frees the object. Emitting a scope-bound try/finally here would
        finalize a live heap object at every scope exit, which is worse than
        refusing. }
      if (Syms[i].TypeKind = tyClass) and RecContainsManagementOp(mrec, 0) then
        Error('a field of a record with a management operator is not managed yet '
              + '(feature-pascal-management-operators-nested-and-array)');
      { ...and an ARRAY field at any depth needs the same synthesised loop the
        array SYMBOL above needs, so it keeps the same refusal. }
      if (Syms[i].TypeKind = tyRecord) and (not Syms[i].IsArray) and
         RecContainsUnreachableManagedField(mrec, 0) then
        Error('a field of a record with a management operator is not managed yet '
              + '(feature-pascal-management-operators-nested-and-array)');
    end;
    if isTarget and (i <> retSym) and SymIsLoopableManagedArray(i) then
    begin
      alo := Syms[i].ConstVal;
      AppendManagedArrayOps(i, SymTR[i].ElemRec, OPK_INITIALIZE,
                            alo, alo + Syms[i].ArrLen - 1, True,
                            headInit, tailInit);
      AppendManagedArrayOps(i, SymTR[i].ElemRec, OPK_FINALIZE,
                            alo, alo + Syms[i].ArrLen - 1, False,
                            headFin, tailFin);
    end;
    if isTarget and (Syms[i].TypeKind = tyRecord) and
       (not Syms[i].IsArray) and (i <> retSym) and
       (SymTR[i].RecId <> REC_NONE) then
    begin
      { INITIALIZE IS POST-ORDER: every managed field, depth-first in
        declaration order, and THEN this record's own operator. FINALIZE is the
        mirror -- own operator first, then the fields. Measured against fpc
        3.2.2 rather than assumed; see AppendManagedFieldOps for the run. }
      AppendManagedFieldOps(GenMakeIdent(i, tyRecord), SymTR[i].RecId, 0,
                            OPK_INITIALIZE, True, headInit, tailInit);
      ip := FindOpOverload(OPK_INITIALIZE, Ord(tyRecord), SymTR[i].RecId);
      if ip >= 0 then
        AppendManagedOpCall(ip, GenMakeIdent(i, tyRecord), headInit, tailInit);
      fp := FindOpOverload(OPK_FINALIZE, Ord(tyRecord), SymTR[i].RecId);
      if fp >= 0 then
        AppendManagedOpCall(fp, GenMakeIdent(i, tyRecord), headFin, tailFin);
      AppendManagedFieldOps(GenMakeIdent(i, tyRecord), SymTR[i].RecId, 0,
                            OPK_FINALIZE, False, headFin, tailFin);
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
  wasDelphiGenHdr : Boolean;  { this `X.M` header was `X<T>.M` in the source; the mode-Delphi rewrite deleted the group. See GenMethImplSOff. }
  isFunc   : Boolean;
  name     : AnsiString;
  retType  : TTypeKind;
  tk       : TTypeKind;
  pnames    : array[0..MAX_PROC_PARAMS-1] of AnsiString;
  ptypes    : array[0..MAX_PROC_PARAMS-1] of TTypeKind;
  ptypesRec : array[0..MAX_PROC_PARAMS-1] of Integer;
  ptypesSetEnum : array[0..MAX_PROC_PARAMS-1] of Integer;  { `set of TEnum` param: element enum index, -1 otherwise }
  ptypesAlias : array[0..MAX_PROC_PARAMS-1] of Integer;  { the alias row this parameter was DECLARED THROUGH, -1 otherwise. Staged and persisted to ProcParamAliasIdx for the reason ptypesSetEnum's own twin gives: a caller cannot read it back off the param symbol. }
  { The REST of a set parameter's element identity, staged in the same window and
    for the same reason as ptypesStrCap below. ptypesSetEnum alone was captured
    for the CALLER's benefit (it lands in ProcParamSetEnumId, an argument-check
    column) and nothing ever stamped the parameter's own SYMBOL -- so inside the
    body a set parameter had SymSetEnumId = -1 and SymSetElemTk = 0, which is
    exactly `no element kind recorded`, and `for x in p` refused with
    `set iteration supports set of <enum>, set of Char or an ordinal set
    constructor` for all three element kinds. The metadata was there; the reader
    inside the body reads a DIFFERENT column, and that one was never written.
    bug-p-a-set-parameter-loses-its-element-kind-so-for-in-refuses-it }
  ptypesSetElemTk : array[0..MAX_PROC_PARAMS-1] of Integer;  { set param: element TTypeKind ordinal; 0 = not a set }
  ptypesSetElemLo : array[0..MAX_PROC_PARAMS-1] of Int64;    { …and the element subrange bounds, Hi < Lo = none }
  ptypesSetElemHi : array[0..MAX_PROC_PARAMS-1] of Int64;
  ptypesSem : array[0..MAX_PROC_PARAMS-1] of Integer;  { a param's SEMANTIC IDENTITY (the ELEMENT's, for an array param), SEM_NONE otherwise -- an enum type index, or the width of a sized boolean. Was ptypesEnum and held only the first; enum SemIds are numerically unchanged. Staged here and persisted at the three registration sites, for the reason ProcParamRecId's note gives: a caller cannot ask the param symbol }
  ptypesStrElemTk : array[0..MAX_PROC_PARAMS-1] of Integer;  { managed-string param: the ELEMENT width, Ord(tyChar) or Ord(tyWideChar); 0 = not a managed string. Staged here and persisted to ProcParamStrElemTk, for the reason ptypesSetEnum's twin gives: a caller cannot read it back off the param symbol. }
  ptypesStrCap : array[0..MAX_PROC_PARAMS-1] of Integer;  { frozen-string param: the declared capacity N of a `string[N]`, or of an open array's ELEMENT; 0 = not a frozen string. The FOURTH member of the return-channel family above, and the one that was missing: AllocParam read LastTypeStrCap itself, in the ALLOCATION loop, which runs after every parameter's type has been parsed -- so a `string[N]` param got whatever capacity the LAST parameter's type left behind. bug-p-a-string-n-element-loses-its-capacity-in-three-container-shapes }
  ptypesFileRecSize : array[0..MAX_PROC_PARAMS-1] of Integer;  { `file of T` param: T's width in bytes; 0 = not a file. Staged here for EXACTLY the reason ptypesStrCap above is: the allocation loop runs after every parameter's type has been parsed, so LastTypeFileRecSize describes the LAST one. feature-pascal-typed-and-untyped-files }
  ptypesFileElemTk : array[0..MAX_PROC_PARAMS-1] of Integer;   { …and T's kind, same window, same reason }
  ptypesPtrElemTk : array[0..MAX_PROC_PARAMS-1] of TTypeKind;
  ptypesPtrElemRec : array[0..MAX_PROC_PARAMS-1] of Integer;
  { The rest of a pointer PARAMETER's identity. Without these three a `^PChar`
    parameter arrived at the callee as depth 1 -- indistinguishable from a plain
    PChar -- so `p^` inside the body yielded the raw address instead of the
    string, while the identical GLOBAL printed fine. cparser's parameter table
    has carried the triple (pdepths/pbasetk/pbaserec) all along; Pascal's had
    the pointee alone. feature-a-typeref-migrate-consumers }
  ptypesPtrDepth : array[0..MAX_PROC_PARAMS-1] of Integer;
  ptypesPtrBaseTk : array[0..MAX_PROC_PARAMS-1] of Integer;
  ptypesPtrBaseRec : array[0..MAX_PROC_PARAMS-1] of Integer;
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
  pElemDynDepth : array[0..MAX_PROC_PARAMS-1] of Integer; { open-array param `array of T`, T a named DYNAMIC array: the element's dyn depth (0 = element not dynamic) }
  pFixedLo : array[0..MAX_PROC_PARAMS-1] of Integer; { named fixed-array param's LOW BOUND — dropped before, so a[1] on a var 1..3 param indexed off by lo (silent neighbour write; found by the {$R+} arc) }  { named FIXED 1-D array param: its real element count (0 = unknown/open — keep AllocParam's placeholder) }
  pDimLo    : array[0..95] of Integer;
  pDimSpan  : array[0..95] of Integer;
  paramNDims, paramDynDepth, paramAi, pdi, paramFixedLen, paramFixedLo: Integer;
  paramElemRowLen, paramElemRowLo, paramElemDynDepth: Integer;
  psLo, psSpan: array[0..MAX_ARR_DIMS-1] of Integer;
  nparams  : Integer;
  procIdx, helperPi, i, sz, retRecId, savedLastTypeRecId: Integer;
  retProcSig: Integer;
  zeroBytes : Integer;
  zfLoop, zfDone : Integer;
  retIsDynArr : Boolean; retElemTk : TTypeKind; retElemRec : Integer;
  retSetEnumId, retSetElemTk : Integer;   { `set of T` RESULT -- the sixth carrier; see defs.inc ProcRetSetEnumId }
  retFixedArrBytes : Integer;   { a FIXED-array result's byte size; 0 = not one }
  retArrAi : Integer;           { its ArrType index, so the Result slot can be shaped like the type; -1 = not one }
  retPtrElemTk, retPtrElemRec, retPtrAlias : Integer;
  retPtrStrElemTk : Integer;   { ...and that pointee's element width when it is a managed string }
  retStrElemTk : Integer;   { managed-string result: element width ord, 0 = not one }
  retSem : Integer;   { enum-typed result: its enum index, else -1 }
  retPtrDepth, retPtrBaseTk, retPtrBaseRec : Integer;
  retDynDepth : Integer;   { `array of` levels of a dyn-array result }
  savedSC, savedFS, savedCurProc : Integer;
  savedGLC, savedGFC, savedGLB, j, savedVisVarSeq: Integer;
  cleanupJnePatch: Integer;
  savedCleanupFrameWanted, savedCleanupFrameLateArmed: Boolean;
  savedCleanupFrameLatePatch: Integer;
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
  sawVarargs: Boolean;
  savedGenIsGen, savedGenSeen, savedGenStackless, savedProcIsAsync: Boolean;
  savedGenSelf, savedGenTry, savedGenStateCtr, savedGenSlotNext: Integer;
  genBodyAST, genStepAST, declElemTk: Integer;
  genSelfIdx, gpi: Integer;
  asmNode: Integer;
  startIdx, idx: Integer;
  tokKindOrd: Integer;
  methOwnerCi, methOwnerRec, methSNOff, methSNLen, mmi, slot, otherCi: Integer;
  savedBodyUnitIdx, tmplDeclUnit, savedSpecHost: Integer;   { a specialization's method body parses as its DECLARING unit — see below }
  savedMIO: Integer;   { MethImplOwnerCi across this decl -- see defs.inc }
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
    pElemDynDepth[pzi] := 0;
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
  { Read/Write/Readln/Writeln lex as dedicated intrinsic tokens (paslexer.inc),
    so a plain tkIdent test refused `function Write(const Args: array of const)`
    at the DECLARATION -- `expected name`, before the name ever reached the
    symbol table. FPC accepts all four; they are intrinsics resolved by context
    at the CALL site, not reserved words, which is the premise
    pasparser_name.inc is already written around and the reason member- and
    method-name position have admitted them for a long time.

    THE DECLARATION AND THE CALL MOVE TOGETHER. Widening this test alone would
    give a routine that is declared and then silently never called, which is
    worse than today's refusal -- so the shadow test in pasparser_call.inc
    (IntrinsicNamesGlobalRoutineHere) and its two dispatch sites land in the
    same commit. Nothing existing changes behaviour: no unit can DECLARE such a
    routine today, so the predicate is False everywhere until someone writes one.
    bug-p-read-write-exit-and-halt-cannot-be-declared-as-user-routines }
  if not IsMemberNameTok then Error('expected name');
  { CurTok.SVal, unchanged: paslexer.inc sets it for every WORD token, keywords
    included (`CurTok.SVal := s` right after `Keyword(s)`), so the four
    intrinsic kinds carry their text here. The "keyword tokens carry no SVal"
    note on the property-name sites is about the RAW Tokens[] array, which
    stores SOffset/SLen and no string at all -- a different structure, not a
    different rule for the same one. }
  name := CurTok.SVal; Next;

  { Check for ClassName.MethodName pattern }
  savedMIO := MethImplOwnerCi;
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
      In objfpc that is the whole story: the source spells both headers `X.M`
      and they really are indistinguishable.

      In mode Delphi it is NOT, and this comment used to claim otherwise -- "a
      `X<T>.M` header never reaches this branch (CurTok would be '<', not '.')".
      DelphiRewriteGenericUses deletes the `<T>` group before the parser gets
      here, so such a header arrives spelled `X.M` and lands squarely in this
      branch, where the FindUMeth test above then gives the template's body to
      the ordinary class. The wasDelphiGenHdr test below restores what the
      rewrite dropped; when no ordinary class of the name exists, FindUClass
      fails and the behaviour is exactly as before. }
    if depth >= 0 then
    begin
      { ...unless the header DID say `<T>` and the mode-Delphi rewrite deleted it
        (GenMethImplSOff, defs.inc). Then the source was never ambiguous and the
        template is the answer by construction -- asking which class declares the
        method would hand the template's body to the ordinary class, whose scope
        lacks the template's class vars, and every one of them would be reported
        undefined. The class-name token is Tokens[TokPos-2]: `Next` leaves CurTok
        holding Tokens[TokPos-1], which is the dot.
        bug-p-a-generic-methods-out-of-line-header-binds-to-a-same-named-non-generic-class }
      wasDelphiGenHdr := False;
      if TokPos >= 2 then
        for i := 0 to GenMethImplCount - 1 do
          if GenMethImplSOff[i] = Tokens[TokPos - 2].SOffset then
            wasDelphiGenHdr := True;
      if not wasDelphiGenHdr then
      begin
        nonGenCi := FindUClass(name);
        if (nonGenCi >= 0) and (FindUMeth(nonGenCi, GetTokenStr(TokPos)) >= 0) then
          depth := -1;
      end;
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
          { The proc name is the ROW's registered name, not the source path we
            just walked. AddClassLikeType registers a nested type bare or
            qualified depending on whether the bare name was already taken, and
            the DECLARATION inside the class body names its methods after the
            row -- so composing `TOuter.TInner.GetIt` here from the tokens
            disagreed with the declared `TInner.GetIt` exactly when the row came
            out bare, and the two halves became two procs: one with a body and
            no callers, one with callers and no body. That is the whole of
            bug-p-a-nested-class-method-called-from-inside-its-generic-outer-is-unresolved
            -- a generic's nested type is re-materialised per specialization and
            registers bare against the template's own row, so it hit every time.
            Reading the row makes the two spellings agree by construction
            instead of by coincidence. }
          name := GetTokenStrFromRaw(UClsNOff[methOwnerCi], UClsNLen[methOwnerCi]);
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
        { From here the header's own types (params, return) and then the body
          are the owner's scope: `function TOuter.Make: TInner` names the
          NESTED TInner, not whatever else in the unit got the bare name first. }
        MethImplOwnerCi := methOwnerCi;
      end;
  end;

  nparams := 0; retType := tyInteger; retRecId := REC_NONE; retProcSig := -1;
  { A local array is stack garbage until written, and the Self/capture insertion
    paths below fill some slots without going through the typed-param branch. }
  for i := 0 to MAX_PROC_PARAMS - 1 do ptypesSetEnum[i] := -1;
  for i := 0 to MAX_PROC_PARAMS - 1 do ptypesAlias[i] := -1;
  for i := 0 to MAX_PROC_PARAMS - 1 do ptypesSetElemTk[i] := 0;
  for i := 0 to MAX_PROC_PARAMS - 1 do begin ptypesSetElemLo[i] := 0; ptypesSetElemHi[i] := -1; end;
  for i := 0 to MAX_PROC_PARAMS - 1 do ptypesSem[i] := -1;
  for i := 0 to MAX_PROC_PARAMS - 1 do ptypesStrElemTk[i] := 0;
  retIsDynArr := False; retElemTk := tyUnknown; retElemRec := REC_NONE;
  retSetEnumId := -1; retSetElemTk := 0;
  retDynDepth := 0;
  retFixedArrBytes := 0; retArrAi := -1;
  retPtrElemTk := Ord(tyUnknown); retPtrElemRec := REC_NONE; retPtrAlias := -1;
  retPtrStrElemTk := 0;
  retStrElemTk := 0;
  retSem := -1;
  retPtrDepth := 0; retPtrBaseTk := Ord(tyUnknown); retPtrBaseRec := REC_NONE;

  { Lambda-lift: a nested routine lifted to top level (matched by its mangled
    name) gains its captured enclosing state as LEADING params here, with type
    metadata snapshotted at the capture site — no synthetic type tokens needed.
    Runs for both the forward decl and the real definition (both pass through
    here with the same mangled name), so their signatures match.

    LEADING, and it used to be trailing. A trailing capture occupies the slots
    an omitted DEFAULT parameter needs, and a nested routine may have both:

      procedure SetMode(const M: TModeSwitch; ...; UseOtherwise: Boolean = True);
      SetMode(msFpc, FPCModeSwitches, false, bsFPCMode);   { 4 of 6 written }

    became `SetMode(..., bsFPCMode, Self, Param)` -- six actuals against
    (own0..own5, Self, Param), so Self landed on `RemoveBoolSwitches` and the
    call was refused. Filling the defaults at the call site would mean copying
    each default's token run out of the header; putting the captures FIRST
    costs nothing, because the parameter loop below indexes off nparams and
    ordinary default filling then works on the tail where it already belongs.
    The actual lists spliced by ParseNestedRoutine go in at the head to match.
    bug-p-a-nested-routine-with-default-parameters-loses-them-to-its-captures }
  liftIdx := FindLiftDesc(name);
  if liftIdx >= 0 then
  begin
    if LiftNeedSelf[liftIdx] then
    begin
      { MAX_PROC_PARAMS, not a smaller round number: the staging arrays and
        TProc.Params are both 32 wide, so 32 is the real bound and the literal
        16 refused half the space that exists.

        The message NAMES THE NUMBER, which is the other half of that bug. For
        as long as the bound was 16 the text read "too many params after
        capture" -- a limit asserted without a value, which the reader can only
        accept. Anyone who hit it counted their captures, got a number under
        what they would have guessed, and reshaped the routine instead of
        disbelieving the compiler; the code they wrote instead cannot be found
        from this side. Printing the cap and the count makes the claim
        CHECKABLE: a reader whose routine captures 17 things and is told the
        max is 32 has a contradiction in front of them, and a wrong bound
        becomes a bug report instead of a workaround. }
      if nparams >= MAX_PROC_PARAMS then
        Error('nested routine: too many params after capture (' +
              AIntToStr(nparams + 1) + ', max ' + AIntToStr(MAX_PROC_PARAMS) + ')');
      pnames[nparams] := '__nestself';
      ptypes[nparams] := tyClass;
      ptypesRec[nparams] := REC_UCLASS_BASE + LiftSelfCi[liftIdx];
      ptypesPtrElemTk[nparams] := tyUnknown; ptypesPtrElemRec[nparams] := REC_NONE;
      ptypesPtrDepth[nparams] := 0;
      ptypesPtrBaseTk[nparams] := Ord(tyUnknown);
      ptypesPtrBaseRec[nparams] := REC_NONE;
      ptypesProcSig[nparams] := -1;
      parr[nparams] := False; pbyref[nparams] := False; pconst[nparams] := False;
      ptypesStrCap[nparams] := 0;   { synthesized param: no declared capacity }
      pout[nparams] := False;
      pNDims[nparams] := 0; pDynDepth[nparams] := 0;
      pElemRowLen[nparams] := 0; pElemRowLo[nparams] := 0;
      pElemDynDepth[nparams] := 0;
      Inc(nparams);
    end;
    lcb := LiftCapStart[liftIdx];
    for i := 0 to LiftCapCount[liftIdx] - 1 do
    begin
      { names the number, for the reason at the sibling site above }
      if nparams >= MAX_PROC_PARAMS then
        Error('nested routine: too many params after capture (' +
              AIntToStr(nparams + 1) + ', max ' + AIntToStr(MAX_PROC_PARAMS) + ')');
      pnames[nparams] := LiftCapName[lcb + i];
      ptypes[nparams] := LiftCapTk[lcb + i];
      ptypesRec[nparams] := LiftCapRec[lcb + i];
      ptypesPtrElemTk[nparams] := LiftCapPtrTk[lcb + i];
      ptypesPtrElemRec[nparams] := LiftCapPtrRec[lcb + i];
      ptypesPtrDepth[nparams] := LiftCapPtrDepth[lcb + i];
      ptypesPtrBaseTk[nparams] := LiftCapPtrBaseTk[lcb + i];
      ptypesPtrBaseRec[nparams] := LiftCapPtrBaseRec[lcb + i];
      ptypesProcSig[nparams] := LiftCapProcSig[lcb + i];
      parr[nparams] := LiftCapArr[lcb + i];
      ptypesStrCap[nparams] := 0;   { a lifted capture carries no declared capacity }
      pbyref[nparams] := True;            { captured by reference }
      pconst[nparams] := False;
      pout[nparams] := False;
      pNDims[nparams] := 0;
      pDynDepth[nparams] := LiftCapDyn[lcb + i];
      { A captured FIXED array becomes exactly the named-fixed-array `var` param
        the arm below already handles: without the extent it would keep
        AllocParam's open-array placeholder (ArrLen := 1000) and size a
        whole-array copy at 1000 elements, and without the low bound IR_INDEX
        would subtract 0 and put `g[1]` of an `array[1..3]` one slot high.
        ALWAYS written -- these staging rows are reused across routines, so 0
        has to clear a previous capture's shape. }
      pFixedLen[nparams] := LiftCapFixedLen[lcb + i];
      pFixedLo[nparams] := LiftCapFixedLo[lcb + i];
      pElemRowLen[nparams] := 0;
      pElemRowLo[nparams] := 0;
      pElemDynDepth[nparams] := 0;
      Inc(nparams);
    end;
  end;

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
        paramElemRowLen := 0; paramElemRowLo := 0; paramElemDynDepth := 0;
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
      paramElemDynDepth := 0;
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
        LoadPointeeFromArrType(paramAi);
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
          { ...and, when that fixed type's ELEMENT is a named dynamic array
            (`TFD = array[0..1] of TRow`), the pointer-sized handle slots — the
            same field the var declaration threads into SymElemDynDepth. }
          paramElemDynDepth := ArrTypeElemDynDepth[paramAi];
        end;
        Next;
      end
      else if CurTok.Kind = tkArray then
      begin
        Next;
        Expect(tkOf, 'of');
        if ParseArrayOfConstElem(tk) then
        begin
          { nothing further: the helper set tk and LastTypeRecId. }
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
            LoadPointeeFromArrType(paramAi);
            if (tk = tyAnsiString) or (tk = tyString) or
               (tk = tyFixedString) or (tk = tyShortString) or
               ((tk = tyRecord) and RecordHasManagedFields(LastTypeRecId)) then
              Error('array of <fixed array of managed elements> not supported');
            paramElemRowLen := ArrTypeHi[paramAi] - ArrTypeLo[paramAi] + 1;
            paramElemRowLo  := ArrTypeLo[paramAi];
            Next;             { consume the named array type }
          end
          else if paramAi >= 0 then
          begin
            { open array whose element is a named DYNAMIC array
              (`a: array of TRow` where `TRow = array of Integer`): each element
              is a pointer-sized dyn-array HANDLE, not a base scalar.
              ParseTypeKind collapses TRow to its element base type, so the
              callee indexed the parameter with a 4-byte Integer stride and read
              garbage for m[i] / Length(m[i]) — a silent wrong value that
              segfaulted on a slightly bigger shape
              (bug-p-open-array-of-a-named-dynamic-array-reads-garbage). Mark
              the element dynamic instead; SymElemDynDepth then drives the
              pointer-sized stride and tags m[i] as a handle. }
            tk := IntToTypeKind(ArrTypeElemTk[paramAi]);
            LastTypeRecId := ArrTypeElemRec[paramAi];
            LoadPointeeFromArrType(paramAi);
            paramElemDynDepth := ArrTypeDynDepth[paramAi];
            if paramElemDynDepth <= 0 then paramElemDynDepth := 1;
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
        ParseParamDefaultValue(tk, Ord(LastTypePointerElemTk),
                               isArr and (paramDynDepth <= 0), defaultVal, defaultIsStr, defaultIsFloat,
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
        { …and the alias NAME the parameter was declared through. Unlike
          LastTypeSetEnumId below this one IS cleared for every kind (at the top
          of ParseTypeKindInner), so it needs no guard: -1 means the parameter
          was not written through a named alias.
          bug-p-a-distinct-type-declaration-is-parsed-but-is-not-distinct }
        ptypesAlias[i] := LastTypeAlias;
        { LastTypeSetEnumId is only meaningful when the type just parsed WAS a
          set — it is not cleared for other kinds. }
        if tk = tySet then ptypesSetEnum[i] := LastTypeSetEnumId
        else ptypesSetEnum[i] := -1;
        { …and the element KIND and BOUNDS under the same guard, because a
          `set of Char` and a `set of 1..9` carry no enum id and are just as
          much sets. Capturing only the enum arm is what left two of the three
          element kinds unrepresented on the parameter symbol. }
        if tk = tySet then
        begin
          ptypesSetElemTk[i] := LastTypeSetElemTk;
          ptypesSetElemLo[i] := LastTypeSetElemLo;
          ptypesSetElemHi[i] := LastTypeSetElemHi;
        end
        else
        begin
          ptypesSetElemTk[i] := 0;
          ptypesSetElemLo[i] := 0;
          ptypesSetElemHi[i] := -1;
        end;
        { ...and the same rule for a param's SEMANTIC IDENTITY: LastTypeSemId
          is only meaningful when the type just parsed actually HAS one, which
          is what SemKindMatches asks and what a bare `tk = tyInteger` could
          not. That spelling was exact while every carrier of an identity was
          integer-sized, and it stopped being so twice over: {$PACKENUM} narrows
          an enum, and a ByteBool param is tyInt8. `procedure P(b: ByteBool)`
          therefore lost the booleanness at the parameter list and `not b`
          inside the body complemented an integer.
          decide-how-a-type-carries-an-identity-its-kind-cannot-hold }
        if SemKindMatches(tk, LastTypeSemId) then ptypesSem[i] := LastTypeSemId
        else ptypesSem[i] := SEM_NONE;
        { ...and the same rule a third time for a managed string's ELEMENT
          WIDTH -- the window read and the normalisation are both stated where
          ParamStrElemOf is defined (symtab.inc), because ParseTypeSection's
          method rows have to capture the same fact the same way now that the
          width is part of an overload signature. }
        ptypesStrElemTk[i] := ParamStrElemOf(tk);
        { ...and a FOURTH time for the frozen-string CAPACITY, for exactly the
          reason the three notes above give. LastTypeStrCap is a return channel
          from the ParseTypeKind that just returned; capturing it here is the
          only window in which it describes THIS parameter. AllocParam reads it
          directly instead, from the allocation loop below -- which runs after
          every parameter has been parsed, so it reads the LAST one's capacity.
          Measured: `procedure P(var a: array of string[10]; t: LongInt)` gave
          a[] a stride of DEFAULT_STR_CAP+8 = 263 rather than 18, while the same
          parameter ALONE was correct, and `t: string[20]` gave it 20's stride.
          The following parameter's type decided the preceding one's layout. }
        if TypeIsFrozenString(tk) then ptypesStrCap[i] := LastTypeStrCap
        else ptypesStrCap[i] := 0;
        if tk = tyRecord then
        begin
          ptypesFileRecSize[i] := LastTypeFileRecSize;
          ptypesFileElemTk[i] := LastTypeFileElemTk;
        end
        else
        begin
          ptypesFileRecSize[i] := 0;
          ptypesFileElemTk[i] := 0;
        end;
        ptypesPtrElemTk[i] := LastTypePointerElemTk;
        ptypesPtrElemRec[i] := LastTypePointerElemRec;
        ptypesPtrDepth[i] := LastTypePointerDepth;
        ptypesPtrBaseTk[i] := LastTypePointerBaseTk;
        ptypesPtrBaseRec[i] := LastTypePointerBaseRec;
        ptypesProcSig[i] := LastTypeProcSig;
        parr[i] := isArr;
        pbyref[i] := isByRef;
        pconst[i] := isConst;
        pout[i] := isOut;
        { The open-array default refusal used to live HERE, after the value had
          been parsed and stored, and therefore guarded this parameter list and
          none of the other three. It is now inside ParseParamDefaultValue --
          the one function all four parsers call -- which also puts it AHEAD of
          the shape checks, so `array of string = ['x']` stops naming the string
          rule it was never breaking. `isArr` alone is the wrong half of the
          question and that is why the flag is computed at the call above rather
          than inside: isArr is true for an open array, a named FIXED array and a
          named DYNAMIC one alike, and the last of those legitimately takes
          `= nil`. bug-p-a-default-value-is-accepted-on-an-open-array-parameter }
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
        pElemDynDepth[i] := paramElemDynDepth;
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
    { The whole return-type parse -- including the array shapes ParseTypeKind
      alone cannot see -- now lives in ParseFuncReturnTypeShape
      (pasparser_decl.inc), so the procedural-type SIGNATURE path shares it
      instead of going without. Lifted, not copied: this function has already
      produced four dropped fields, which root-cause-over-microfix.md calls a
      design flaw rather than a smell.
      bug-p-a-procedural-type-cannot-return-an-array-or-another-procedural-type }
    ParseFuncReturnTypeShape(retType, retIsDynArr, retDynDepth, retElemTk,
                             retElemRec, retFixedArrBytes, retArrAi,
                             retSem, retSetEnumId, retSetElemTk, retStrElemTk,
                             retRecId, retProcSig,
                             retPtrElemTk, retPtrStrElemTk, retPtrElemRec,
                             retPtrDepth, retPtrBaseTk, retPtrBaseRec, retPtrAlias);
  end;

  Eat(tkSemicolon);
  declOverload := False;
  declFlexColumn := False;
  declInline := False;
  sawIram := False; sawCdecl := False; sawRegister := False;
  sawVarargs := False;
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
          CaseEqual(CurTok.SVal, 'library') or
          CaseEqual(CurTok.SVal, 'varargs'))) or
        (CurTok.Kind = tkOverload) or IsCallConvDirectiveTok or
        IsInertRoutineDirectiveTok do
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
    { `varargs` -- FPC's spelling for the trailing `...` of a C callee. NOT in
      IsInertRoutineDirectiveTok, whose comment names it as the first of the
      directives it refuses to swallow BECAUSE it changes how a call marshals;
      that refusal was correct while nothing could record the fact and it is
      what this now records. Accepted in both FPC orders: here, before the
      `external` clause (`cdecl; varargs; external 'c'`), and after it at the
      sibling site below (`external 'c'; varargs`). }
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'varargs') then sawVarargs := True;
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
    { x86-64 is no longer in this warning's population: there `cdecl` selects a
      genuine SysV prologue. Narrowed rather than deleted because the other five
      targets still cannot select a convention per routine.
      feature-cdecl-bodied-sysv-prologue }
    if sawCdecl and (TargetArch <> TARGET_X86_64) then
      Warn('directive ''cdecl'' ignored here: on this target the calling ' +
           'convention is not selectable per routine, so ' + name +
           ' already uses it; the marker is documentation only (on x86-64 it ' +
           'selects a genuine SysV prologue)');
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
    { The other legal order: `external 'c'; varargs;`. The directive loop above
      ran before the external clause, so this spelling arrives here. Both are in
      the wild -- FPC's own headers use each. }
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'varargs') and
       (TokPos < TokCount) and (Tokens[TokPos].Kind = tkSemicolon) then
    begin
      sawVarargs := True;
      Next;
      Eat(tkSemicolon);
    end;
    procIdx := FindProcOverloadRec(name, nparams, ptypes, ptypesRec, ptypesStrElemTk, ptypesPtrElemTk, parr, pbyref, ptypesAlias);
    if procIdx < 0 then
      procIdx := RegisterProc(name, isFunc, retType, nparams, pnames, ptypes);
    if sawVarargs then ProcVariadic[procIdx] := True;
    ProcRetRecId[procIdx] := retRecId;
      ProcRetProcSig[procIdx] := retProcSig;
    { Record the return-element metadata like the normal registration paths do —
      without this an external `function f(...): PAnsiChar` leaves ProcRetPtrElemTk
      at tyUnknown, so IsNodePChar can't tell f() returns a char pointer and
      `AnsiString(f(...))` silently mis-lowers (reads a bogus managed-string
      header). See bug-pascal-ansistring-cast-of-cdecl-call-result. }
    ProcRetIsDynArray[procIdx] := retIsDynArr;
    ProcRetDynDepth[procIdx] := retDynDepth;
  ProcRetFixedArrBytes[procIdx] := retFixedArrBytes;
  ProcRetArrAi[procIdx] := retArrAi;
    ProcRetElemTk[procIdx] := retElemTk;
    ProcRetSetEnumId[procIdx] := retSetEnumId;  ProcRetSetElemTk[procIdx] := retSetElemTk;
    ProcRetElemRec[procIdx] := retElemRec;
    ProcRetPtrElemTk[procIdx] := retPtrElemTk;
    ProcRetPtrAlias[procIdx] := retPtrAlias;
    ProcRetPtrElemStrTk[procIdx] := retPtrStrElemTk;
    ProcRetStrElemTk[procIdx] := retStrElemTk;
    ProcRetSemId[procIdx] := retSem;
    ProcRetPtrElemRec[procIdx] := retPtrElemRec;
    ProcRetPtrDepth[procIdx] := retPtrDepth;
    ProcRetPtrBaseTk[procIdx] := retPtrBaseTk;
    ProcRetPtrBaseRec[procIdx] := retPtrBaseRec;
    for i := 0 to nparams-1 do
    begin
      Procs[procIdx].Params[i].IsArray := parr[i];
      Procs[procIdx].Params[i].IsRef := pbyref[i];
      { THE DURABLE PARAM ROW. Read the canonical note at the body path's copy
        (search: THE DURABLE PARAM ROW -- canonical note) before editing any of
        the three copies; a column added to one of them and not the others is
        exactly the defect this block was widened to fix.

        This path wrote THREE of the ~20 columns and then Exits, ~750 lines
        before the body pass that fills the rest -- and an `external` routine
        has NO body pass, so the omissions were permanent rather than late.
        Measured 2026-08-30, two defects in OPPOSITE directions from the one
        omission set:

          procedure g(p: PInteger); external 'c' name 'abs';  g(someObject);
            was ACCEPTED, and called libc with an object pointer. FPC rejects
            it. PtrElemTk was never written, so the narrowing guard read the
            tyUnknown sentinel and failed OPEN.

          procedure g(a: Integer; b: Integer = 7); external 'c' name 'abs';
          g(1);  was REJECTED -- "candidates: g(Integer, Integer)". FPC accepts
            it. HasDefault was never written, so the same omission failed
            CLOSED. Counting the missing columns mattered more than fixing the
            one that was filed. }
      if i < MAX_PROC_PARAMS then
      begin
        ProcParamIsConst[procIdx * MAX_PROC_PARAMS + i] := pconst[i];
        ProcParamExplicitByRef[procIdx * MAX_PROC_PARAMS + i] := pbyref[i];
        ProcParamUntyped[procIdx * MAX_PROC_PARAMS + i] := puntyped[i];
        if pdefault[i] then
        begin
          ProcParamHasDefault[procIdx * MAX_PROC_PARAMS + i] := True;
          ProcParamDefaultVal[procIdx * MAX_PROC_PARAMS + i] := pdefaultval[i];
          ProcParamDefaultIsStr[procIdx * MAX_PROC_PARAMS + i] := pdefaultisstr[i];
          ProcParamDefaultIsFloat[procIdx * MAX_PROC_PARAMS + i] := pdefaultisfloat[i];
          ProcParamDefaultIsSet[procIdx * MAX_PROC_PARAMS + i] := pdefaultisset[i];
          ProcParamDefaultSOff[procIdx * MAX_PROC_PARAMS + i] := pdefaultsoff[i];
          ProcParamDefaultSLen[procIdx * MAX_PROC_PARAMS + i] := pdefaultslen[i];
        end;
        if pDynDepth[i] > 0 then ProcParamDynDepth[procIdx * MAX_PROC_PARAMS + i] := pDynDepth[i];
        ProcParamElemRowLen[procIdx * MAX_PROC_PARAMS + i] := pElemRowLen[i];
        ProcParamElemRowLo[procIdx * MAX_PROC_PARAMS + i] := pElemRowLo[i];
        ProcParamElemDynDepth[procIdx * MAX_PROC_PARAMS + i] := pElemDynDepth[i];
        if (ptypes[i] = tyClass) or (ptypes[i] = tyRecord) then
          ProcParamRecId[procIdx * MAX_PROC_PARAMS + i] := ptypesRec[i];
        if ptypes[i] = tySet then
          ProcParamSetEnumId[procIdx * MAX_PROC_PARAMS + i] := ptypesSetEnum[i];
          ProcParamAliasIdx[procIdx * MAX_PROC_PARAMS + i] := ptypesAlias[i];
          ProcParamSemId[procIdx * MAX_PROC_PARAMS + i] := ptypesSem[i];
        if ptypes[i] = tyAnsiString then
          ProcParamStrElemTk[procIdx * MAX_PROC_PARAMS + i] := ptypesStrElemTk[i];
        { The capacity twin of the width above, and NOT under that `if`: the width
          question is about tyAnsiString and this one is about the FROZEN kinds, so
          guarding it on tyAnsiString would record nothing for every string[N]
          there is. Written flat and dedented so the scope is visible -- the line
          above it ends its own `if`, and this file already has one line (the
          AliasIdx write under the tySet test) that reads as guarded and is not.
          ptypesStrCap is 0 for anything that is not a frozen string, so the write
          is unconditional by construction. defs.inc says why the N cannot be read
          back off the param SYMBOL. }
        ProcParamStrCap[procIdx * MAX_PROC_PARAMS + i] := ptypesStrCap[i];
        if ptypes[i] = tyPointer then
        begin
          ProcParamPtrElemTk[procIdx * MAX_PROC_PARAMS + i] := Ord(ptypesPtrElemTk[i]);
          ProcParamPtrElemRec[procIdx * MAX_PROC_PARAMS + i] := ptypesPtrElemRec[i];
        end;
        ProcParamProcSig[procIdx * MAX_PROC_PARAMS + i] := ptypesProcSig[i];
      end;
    end;
    Procs[procIdx].BodyAddr := -1;
    ProcExternal[procIdx] := True;
    if declFlexColumn then ProcFlexColumn[procIdx] := True;
    ProcLibrary[procIdx] := InternStr(extLib);
    if extSym <> '' then ProcExtName[procIdx] := InternStr(extSym);
    MethImplOwnerCi := savedMIO;
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
      ptypesAlias[i] := ptypesAlias[i-1];
      ptypesSetElemTk[i] := ptypesSetElemTk[i-1];
      ptypesSetElemLo[i] := ptypesSetElemLo[i-1];
      ptypesSetElemHi[i] := ptypesSetElemHi[i-1];
      ptypesSem[i] := ptypesSem[i-1];
      ptypesStrElemTk[i] := ptypesStrElemTk[i-1];
      ptypesStrCap[i] := ptypesStrCap[i-1];   { shifts like every other per-param column -- pconst's note above is about the one time this was forgotten }
      ptypesPtrElemTk[i] := ptypesPtrElemTk[i-1];
      ptypesPtrElemRec[i] := ptypesPtrElemRec[i-1];
      ptypesPtrDepth[i] := ptypesPtrDepth[i-1];
      ptypesPtrBaseTk[i] := ptypesPtrBaseTk[i-1];
      ptypesPtrBaseRec[i] := ptypesPtrBaseRec[i-1];
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
      { ...and so does UNTYPEDNESS -- the third of the same family and the last
        one still missing. It stayed invisible for as long as nothing asked a
        METHOD parameter whether it was untyped: the flag landed one slot LEFT
        of its parameter, so for `M(a: Integer; out b)` the typed `a` answered
        untyped and the untyped `b` answered typed. TWO defects in opposite
        directions out of the one omission, both measured on pin fe1e9c37d322
        as well as at HEAD, so both pre-date the work that found them:

          method   Integer(b) := 99   REFUSED, "cast-as-lvalue: the cast type
            must be the same size as the variable" -- but `b` IS untyped, and
            an untyped param has no declared width for the cast to disagree
            with, which is the whole reason that arm exists. The byte-identical
            FREE routine accepts it.
          method   Int64(a) := 99     ACCEPTED -- an 8-byte store into a 4-byte
            parameter slot, because `a` inherited b's untypedness. The
            byte-identical FREE routine correctly refuses it. That is the
            dangerous direction: a silent memory write, not a diagnostic.

        IsUntypedVarParamSym (pasparser_stmt.inc) matches the NAME at slot i
        against the FLAG at slot i, so a shift that moves one and not the other
        mislabels both ends at once.
        bug-p-the-self-shift-forgets-puntyped-so-a-method-param-is-mislabelled }
      puntyped[i] := puntyped[i-1];
      pNDims[i] := pNDims[i-1];
      pDynDepth[i] := pDynDepth[i-1];
      pElemRowLen[i] := pElemRowLen[i-1];
      pElemRowLo[i] := pElemRowLo[i-1];
      pElemDynDepth[i] := pElemDynDepth[i-1];
      { THE REST OF THE PER-PARAM FAMILY. Found by asking the CONCEPT -- "which
        arrays are indexed by parameter slot?" -- rather than by grepping the
        callers of any one of them, because a caller census can only return
        sites that already reached the helper. Enumerating the declared
        `array[0..MAX_PROC_PARAMS-1]` locals and differencing them against what
        this loop shifts named four more, on top of `puntyped`:

          pFixedLen / pFixedLo         a named fixed-array parameter's element
            count and LOW BOUND. Measured, and it is a silent out-of-bounds
            WRITE, not a diagnostic: for `W(n: Integer; var arr: array[1..3] of
            Integer)` the method assigning arr[1..3] produced `0 10 20` with the
            30 landing PAST THE END, where the byte-identical free routine and
            fpc 3.2.2 both give `10 20 30`. The lo lands on the Integer slot and
            the array slot reads an unset 0, so every index is off by lo.
          ptypesFileRecSize / ptypesFileElemTk   a `file of T` parameter's
            element width and kind, same shape.

        Each of these was staged into a per-param array for the reason the
        declarations give -- the allocation loop runs after every parameter is
        parsed, so the LastType* globals describe the last one -- which is
        exactly what makes the slot index load-bearing. }
      pFixedLen[i] := pFixedLen[i-1];
      pFixedLo[i] := pFixedLo[i-1];
      ptypesFileRecSize[i] := ptypesFileRecSize[i-1];
      ptypesFileElemTk[i] := ptypesFileElemTk[i-1];
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
    puntyped[0] := False; { ...nor an untyped one: Self always has a type }
    if isStaticMethod and (methOwnerCi >= 0) and
       (UClsHelperTk[methOwnerCi] = Ord(tyClass)) then
    begin
      { a CLASS HELPER's `class function`: Self = the METACLASS, the same as an
        ordinary class method one arm below. Forked here to agree with the decl
        side (pasparser_decl.inc's Self-at-param-0 block); the two must match or
        the impl never binds — the b321 lesson. A TYPE or RECORD helper keeps
        the by-value target dummy, because neither target has a metaclass.
        bug-p-a-class-helpers-class-method-is-refused-by-the-record-metaclass-rule }
      ptypes[0] := tyPointer;
      ptypesRec[0] := REC_NONE;
      pbyref[0] := False;
    end
    else if isStaticMethod and (methOwnerCi >= 0) and (UClsHelperTk[methOwnerCi] >= 0) then
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
        agree with the decl side's registration or the impl never binds. A
        CLASS helper is the exception: the instance is already a pointer, so
        Self goes by value (same fork as the decl side). }
      ptypes[0] := IntToTypeKind(UClsHelperTk[methOwnerCi]);
      ptypesRec[0] := UClsHelperRec[methOwnerCi];
      pbyref[0] := ptypes[0] <> tyClass;
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
    { Self is a class reference, not a typed pointer: no depth to speak of. }
    ptypesPtrDepth[0] := 0;
    ptypesPtrBaseTk[0] := Ord(tyUnknown);
    ptypesPtrBaseRec[0] := REC_NONE;
    ptypesProcSig[0] := -1;
    parr[0]   := False;
    pNDims[0] := 0;
    pDynDepth[0] := 0;
    pElemRowLen[0] := 0;
    pElemRowLo[0] := 0;
    pElemDynDepth[0] := 0;
    pFixedLen[0] := 0;
    pFixedLo[0] := 0;
    ptypesFileRecSize[0] := 0;
    ptypesFileElemTk[0] := 0;
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
      ptypesAlias[i] := ptypesAlias[i-1];
      ptypesSetElemTk[i] := ptypesSetElemTk[i-1];
      ptypesSetElemLo[i] := ptypesSetElemLo[i-1];
      ptypesSetElemHi[i] := ptypesSetElemHi[i-1];
      ptypesSem[i] := ptypesSem[i-1];
      ptypesStrElemTk[i] := ptypesStrElemTk[i-1];
      ptypesPtrElemTk[i] := ptypesPtrElemTk[i-1];
      ptypesPtrElemRec[i] := ptypesPtrElemRec[i-1];
      ptypesPtrDepth[i] := ptypesPtrDepth[i-1];
      ptypesPtrBaseTk[i] := ptypesPtrBaseTk[i-1];
      ptypesPtrBaseRec[i] := ptypesPtrBaseRec[i-1];
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
      { ...and untypedness, for the reason spelled out at the twin above }
      puntyped[i] := puntyped[i-1];
      pNDims[i] := pNDims[i-1];
      pDynDepth[i] := pDynDepth[i-1];
      pElemRowLen[i] := pElemRowLen[i-1];
      pElemRowLo[i] := pElemRowLo[i-1];
      pElemDynDepth[i] := pElemDynDepth[i-1];
      { ...the same family, and at this site also the DEFAULTS and ptypesStrCap,
        which the twin loop above already shifts. The default arrays carry
        their own bug reference there (bug-pascal-method-default-param-self-shift);
        this is the sibling arm that fix did not reach. }
      pFixedLen[i] := pFixedLen[i-1];
      pFixedLo[i] := pFixedLo[i-1];
      ptypesFileRecSize[i] := ptypesFileRecSize[i-1];
      ptypesFileElemTk[i] := ptypesFileElemTk[i-1];
      ptypesStrCap[i] := ptypesStrCap[i-1];
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
    pnames[0] := '__genself';
    pconst[0] := False;
    pout[0] := False;
    puntyped[0] := False; { ...nor an untyped one: Self always has a type }
    ptypes[0] := tyPointer;
    ptypesRec[0] := REC_NONE;
    ptypesPtrElemTk[0] := tyUnknown;
    ptypesPtrElemRec[0] := REC_NONE;
    ptypesPtrDepth[0] := 0;
    ptypesPtrBaseTk[0] := Ord(tyUnknown);
    ptypesPtrBaseRec[0] := REC_NONE;
    ptypesProcSig[0] := -1;
    parr[0]   := False;
    pbyref[0] := False;
    pNDims[0] := 0;
    pDynDepth[0] := 0;
    pElemRowLen[0] := 0;
    pElemRowLo[0] := 0;
    pElemDynDepth[0] := 0;
    pFixedLen[0] := 0;
    pFixedLo[0] := 0;
    ptypesFileRecSize[0] := 0;
    ptypesFileElemTk[0] := 0;
    ptypesStrCap[0] := 0;
    pdefaultisstr[0] := False;
    pdefaultisfloat[0] := False;
    pdefaultisset[0] := False;
    pdefaultsoff[0] := 0;
    pdefaultslen[0] := 0;
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
    MethImplOwnerCi := savedMIO;
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
      procIdx := FindProcOverloadRec(name, nparams, ptypes, ptypesRec, ptypesStrElemTk, ptypesPtrElemTk, parr, pbyref, ptypesAlias);
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
      ProcRetProcSig[procIdx] := retProcSig;
        ProcOverloadDirective[procIdx] := declOverload;
        Procs[procIdx].BodyAddr := -1;
        for i := 0 to nparams-1 do
        begin
          Procs[procIdx].Params[i].IsArray := parr[i];
          Procs[procIdx].Params[i].IsRef := pbyref[i];
          { THE DURABLE PARAM ROW (copy 2 of 3 -- canonical note is at the body
            path's copy; search that phrase). Persist the param metadata the
            call-site lowering reads, so a call made BEFORE the body is parsed
            (e.g. a lifted nested routine, whose definition is deferred to top
            level) lowers identically to one after. Without ProcParamDynDepth a
            `var dyn-array` arg passes the handle value instead of &slot →
            SetLength corrupts memory. }
          if i < MAX_PROC_PARAMS then
          begin
            if pDynDepth[i] > 0 then ProcParamDynDepth[procIdx * MAX_PROC_PARAMS + i] := pDynDepth[i];
            ProcParamIsConst[procIdx * MAX_PROC_PARAMS + i] := pconst[i];
            ProcParamExplicitByRef[procIdx * MAX_PROC_PARAMS + i] := pbyref[i];
            ProcParamUntyped[procIdx * MAX_PROC_PARAMS + i] := puntyped[i];
            { Write-only-TRUE, adopted from the body path's copy, which carries
              the reason: a method or forward BODY repeats the parameter list
              WITHOUT the defaults (FPC style -- they live in the class or
              interface declaration), and a plain copy clears what the
              declaration recorded. This path copied plainly. }
            if pdefault[i] then
            begin
              ProcParamHasDefault[procIdx * MAX_PROC_PARAMS + i] := True;
              ProcParamDefaultVal[procIdx * MAX_PROC_PARAMS + i] := pdefaultval[i];
              ProcParamDefaultIsStr[procIdx * MAX_PROC_PARAMS + i] := pdefaultisstr[i];
              ProcParamDefaultIsFloat[procIdx * MAX_PROC_PARAMS + i] := pdefaultisfloat[i];
              ProcParamDefaultIsSet[procIdx * MAX_PROC_PARAMS + i] := pdefaultisset[i];
              ProcParamDefaultSOff[procIdx * MAX_PROC_PARAMS + i] := pdefaultsoff[i];
              ProcParamDefaultSLen[procIdx * MAX_PROC_PARAMS + i] := pdefaultslen[i];
            end;
            ProcParamElemRowLen[procIdx * MAX_PROC_PARAMS + i] := pElemRowLen[i];
            ProcParamElemRowLo[procIdx * MAX_PROC_PARAMS + i] := pElemRowLo[i];
            ProcParamElemDynDepth[procIdx * MAX_PROC_PARAMS + i] := pElemDynDepth[i];
            if (ptypes[i] = tyClass) or (ptypes[i] = tyRecord) then
              ProcParamRecId[procIdx * MAX_PROC_PARAMS + i] := ptypesRec[i];
            if ptypes[i] = tySet then
              ProcParamSetEnumId[procIdx * MAX_PROC_PARAMS + i] := ptypesSetEnum[i];
              ProcParamAliasIdx[procIdx * MAX_PROC_PARAMS + i] := ptypesAlias[i];
              ProcParamSemId[procIdx * MAX_PROC_PARAMS + i] := ptypesSem[i];
            if ptypes[i] = tyAnsiString then
              ProcParamStrElemTk[procIdx * MAX_PROC_PARAMS + i] := ptypesStrElemTk[i];
            { The capacity twin of the width above, and NOT under that `if`: the width
              question is about tyAnsiString and this one is about the FROZEN kinds, so
              guarding it on tyAnsiString would record nothing for every string[N]
              there is. Written flat and dedented so the scope is visible -- the line
              above it ends its own `if`, and this file already has one line (the
              AliasIdx write under the tySet test) that reads as guarded and is not.
              ptypesStrCap is 0 for anything that is not a frozen string, so the write
              is unconditional by construction. defs.inc says why the N cannot be read
              back off the param SYMBOL. }
            ProcParamStrCap[procIdx * MAX_PROC_PARAMS + i] := ptypesStrCap[i];
            { The six columns this path did NOT write, the pointee among them.
              The ticket predicted this path was benign "because the body fills
              it in later" -- measured FALSE on 2026-08-30, because "later" is
              after any caller parsed in between:

                procedure g(p: PInteger); forward;
                procedure caller; begin g(someObject); end;   { parsed FIRST }
                procedure g(p: PInteger); begin end;

              compiled clean; FPC rejects it at the call. A forward declaration
              exists precisely so that something may be parsed between it and
              the body, so "the body fills it in later" is the one assumption
              this path may not make. }
            if ptypes[i] = tyPointer then
            begin
              ProcParamPtrElemTk[procIdx * MAX_PROC_PARAMS + i] := Ord(ptypesPtrElemTk[i]);
              ProcParamPtrElemRec[procIdx * MAX_PROC_PARAMS + i] := ptypesPtrElemRec[i];
            end;
            ProcParamProcSig[procIdx * MAX_PROC_PARAMS + i] := ptypesProcSig[i];
          end;
        end;
      end
      else if declOverload then
        ProcOverloadDirective[procIdx] := True;
      if declFlexColumn then ProcFlexColumn[procIdx] := True;
      ProcRetRecId[procIdx] := retRecId;
      ProcRetProcSig[procIdx] := retProcSig;
      ProcRetIsDynArray[procIdx] := retIsDynArr;
      ProcRetDynDepth[procIdx] := retDynDepth;
  ProcRetFixedArrBytes[procIdx] := retFixedArrBytes;
  ProcRetArrAi[procIdx] := retArrAi;
      ProcRetElemTk[procIdx] := retElemTk;
      ProcRetSetEnumId[procIdx] := retSetEnumId;  ProcRetSetElemTk[procIdx] := retSetElemTk;
      ProcRetElemRec[procIdx] := retElemRec;
      ProcRetPtrElemTk[procIdx] := retPtrElemTk;
      ProcRetPtrAlias[procIdx] := retPtrAlias;
      ProcRetPtrElemStrTk[procIdx] := retPtrStrElemTk;
      ProcRetStrElemTk[procIdx] := retStrElemTk;
      ProcRetSemId[procIdx] := retSem;
      ProcRetPtrElemRec[procIdx] := retPtrElemRec;
      ProcRetPtrDepth[procIdx] := retPtrDepth;
      ProcRetPtrBaseTk[procIdx] := retPtrBaseTk;
      ProcRetPtrBaseRec[procIdx] := retPtrBaseRec;
      if retIsDynArr then Procs[procIdx].RetType := tyPointer; { 8-byte heap handle ABI }
    end;
    { EVERYTHING BELOW THIS EXIT IS SKIPPED IN THE PRE-SCAN, AND THAT INCLUDES
      THE CALLING-CONVENTION FLAGS. `sawCdecl` is read above, but ProcCdecl
      (and ProcIram, ProcIsInterrupt) are only ASSIGNED further down, on the
      body pass. So after declaration pass 1 every routine still reads as
      non-cdecl -- not "unknown", but the wrong answer, silently.

      This is not a bug to fix by hoisting the assignment: the pre-scan
      deliberately registers a signature and nothing else. It is a fact anyone
      writing a pass-1 check has to know, because the failure mode does not
      look like one. Measured 2026-09-04: `exports` validation placed after
      pass 1 rejected EVERY exported routine as not-`cdecl`, including ones the
      object writer went on to export correctly under exactly the predicate the
      check was meant to agree with -- a check contradicting its own backend,
      with no crash and no diagnostic anywhere near the cause.
      Ask a routine's convention after pass 2, as ValidateExports does.
      feature-p-a-pascal-library-unit-does-not-parse }
    if preScanBody then PreScanSkipRoutineBody;
    MethImplOwnerCi := savedMIO;
    Exit;
  end;

  { Register or resolve }
  procIdx := FindProcOverloadRec(name, nparams, ptypes, ptypesRec, ptypesStrElemTk, ptypesPtrElemTk, parr, pbyref, ptypesAlias);
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
      ProcRetProcSig[procIdx] := retProcSig;
  ProcRetIsDynArray[procIdx] := retIsDynArr;
  ProcRetDynDepth[procIdx] := retDynDepth;
  ProcRetFixedArrBytes[procIdx] := retFixedArrBytes;
  ProcRetArrAi[procIdx] := retArrAi;
  ProcRetElemTk[procIdx] := retElemTk;
  ProcRetSetEnumId[procIdx] := retSetEnumId;  ProcRetSetElemTk[procIdx] := retSetElemTk;
  ProcRetElemRec[procIdx] := retElemRec;
  ProcRetPtrElemTk[procIdx] := retPtrElemTk;
  ProcRetPtrAlias[procIdx] := retPtrAlias;
  ProcRetPtrElemStrTk[procIdx] := retPtrStrElemTk;
  ProcRetStrElemTk[procIdx] := retStrElemTk;
  ProcRetSemId[procIdx] := retSem;
  ProcRetPtrElemRec[procIdx] := retPtrElemRec;
  ProcRetPtrDepth[procIdx] := retPtrDepth;
  ProcRetPtrBaseTk[procIdx] := retPtrBaseTk;
  ProcRetPtrBaseRec[procIdx] := retPtrBaseRec;
  ProcIsAsync[procIdx] := isAsync;
  ProcIsGenerator[procIdx] := isGenerator;
  ProcIsStackless[procIdx] := isStackless;
  { `cdecl;` on a BODIED proc SELECTS the convention on x86-64 rather than being
    documentation: the body gets a genuine SysV prologue (the ProcCdecl arm of
    EmitParamSpillsForTarget) and every direct call site already marshals SysV
    (ir_codegen.inc IR_CALL, `ProcExternal or ProcCdecl`), so the two agree and
    @-taking it as a `cdecl` function pointer is sound.
    feature-cdecl-bodied-sysv-prologue

    ONLY the targets that actually HAVE a C-convention prologue arm: x86-64,
    aarch64, arm32 and i386. This list grew one target at a time and the order
    mattered: the arm landed and was proven FIRST, and only then did that
    target join this condition. Setting the flag on a target with no arm would
    be actively wrong -- it would give that target no C prologue, and only make
    its direct calls marshal a convention its prologue does not read.

    RISCV32 IS DELIBERATELY ABSENT, AND NOT BECAUSE IT LACKS AN ARM. It needs
    no arm: after
    bug-a-riscv32-passes-stack-arguments-in-reverse-psabi-order its ordinary
    convention IS the C convention at every width -- word k in a[k], no FP bank
    to count separately (ILP32 soft-float), no even-register alignment rule, and
    the overflow tail now in psABI order. There is nothing for this flag to
    SELECT on riscv32, so setting it would assert a distinction the target does
    not have. XTENSA is absent for the original reason: no arm, internal
    prologue plus internal direct call, self-consistent and not C-compatible.
    Note aarch64 needed MORE than x86-64 did, so do not assume the next target
    is free either: x86-64's direct-call site already switched on
    `ProcExternal or ProcCdecl`, so its call side came matched for nothing,
    while aarch64 needed that switch added at ir_codegen_aarch64.inc's IR_CALL
    and needed a prologue arm written from the external path's classification
    (cparser.inc's aarch64 spill is POSITIONAL and was no use as a model).
    bug-a-the-cdecl-soundness-reject-still-has-its-argument-shaped-door-on-four-targets }
  if sawCdecl and ((TargetArch = TARGET_X86_64) or (TargetArch = TARGET_AARCH64) or
                   (TargetArch = TARGET_ARM32) or (TargetArch = TARGET_I386)) then
    ProcCdecl[procIdx] := True;
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

  SetProcBodyAddrHere(procIdx);
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
  { Same save/restore discipline as the flag above, and for the same reason: a
    nested proc's body is parsed and lowered DURING the outer proc's parse, so
    without this its late-gate answer would be read as the outer proc's. }
  savedCleanupFrameWanted := ProcCleanupFrameWanted;
  savedCleanupFrameLateArmed := ProcCleanupFrameLateArmed;
  savedCleanupFrameLatePatch := ProcCleanupFrameLatePatch;
  ProcCleanupFrameWanted := False;
  ProcCleanupFrameLateArmed := False;
  savedGLB := GotoLabelBase;
  GotoLabelBase := GotoLabelCount;   { this routine's labels start here; the
    enclosing scope's stay put. Resetting the COUNT to 0 restored the count on
    exit but not the slot CONTENTS, so a routine's labels overwrote the
    program's. }
  GotoFixupCount := 0;
  for j := GotoLabelBase to MAX_GOTO_LABELS - 1 do GotoLabelIRId[j] := -1;
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

    { Inside a CLASS HELPER's method, Self IS the extended instance, so an
      unqualified name binds to the extended class's members — `Tag + '2'`
      inside TThingHelper.Tag2 reaches TThing.Tag (class-helper-inherited in
      fpc_diff_probe). CurSelfClass is the rec the bare-name lookups search, so
      it is the extended class here, not the helper row. A helper's own sibling
      member still resolves through the qualified `Self.X`, which the class
      helper redirect (ClassHelperRecFor) sends back to the helper. }
    if (methOwnerCi >= 0) and (UClsHelperTk[methOwnerCi] = Ord(tyClass)) and
       (not UMthIsStatic[mmi]) then
      CurSelfClass := UClsHelperRec[methOwnerCi];

    if UMthVirSlot[mmi] >= 0 then
    begin
      slot := UMthVirSlot[mmi];
      AddMethodFix(UClsVMTOffset[methOwnerCi] + slot * 8, procIdx);

      { PROPAGATE INTO SUBCLASSES THAT INHERIT THIS SLOT -- AND ONLY THOSE.
        A subclass with no override of its own must get this body in its slot,
        which is what this loop is for. A subclass that DOES override must not,
        and the unconditional form overwrote it: the fixups are applied in the
        order they are recorded, so whichever body is parsed LAST wins the slot.
        With the base implemented after the override -- an ordering nothing in
        Pascal forbids and fpc compiles correctly -- the parent's body landed on
        top of the child's and the override became unreachable, including
        through a direct `TDer(o).Say`. Silent: no diagnostic, and the program
        runs and prints the base's answer.

        The question is not "is otherCi below methOwnerCi" but "is methOwnerCi
        the class otherCi actually INHERITS this slot from", which differs the
        moment anything sits in between: for A -> B -> C with B overriding, C
        takes B's body and not A's, so IsSubclassOf(C, A) is true and the
        propagation is still wrong.
        bug-p-an-override-implemented-before-its-base-loses-its-vmt-slot }
      for otherCi := 0 to UClsCount-1 do
      begin
        if IsSubclassOf(otherCi, methOwnerCi) and
           (DeclaringClassForSlot(otherCi, slot) = methOwnerCi) then
        begin
          AddMethodFix(UClsVMTOffset[otherCi] + slot * 8, procIdx);
        end;
      end;
    end;
  end;

  { Allocate param slots }
  for i := 0 to nparams-1 do
  begin
    idx := AllocParam(pnames[i], ptypes[i], pbyref[i], parr[i]);
    Procs[procIdx].Params[i].SymIdx := idx;
    { AllocParam set SymStrCap from LastTypeStrCap, which by now describes the
      LAST parameter parsed rather than this one. Overwrite it with the value
      captured in the parse loop, where the window was valid. Only when this
      parameter actually declared one: 0 means "not a frozen string" and must
      not overwrite anything AllocParam did for another kind. }
    if ptypesStrCap[i] > 0 then SymStrCap[idx] := ptypesStrCap[i];
    { Same overwrite, same window argument, for a `var f: TIntFile` parameter:
      without it the width on the parameter symbol is the last parameter's and
      `Read(f, r)` inside the body checks against the wrong element size. }
    if ptypesFileRecSize[i] > 0 then
    begin
      SymFileRecSize[idx] := ptypesFileRecSize[i];
      SymFileElemTk[idx] := ptypesFileElemTk[i];
    end;
    { A set param is a set-typed value inside the body — the same stamp the
      var-decl site makes (pasparser_decl.inc, the `VDTk = tySet` arm), so
      `for x in p` can find the element range there too. ptypesSetEnum was
      already captured but only ever went to ProcParamSetEnumId, which the
      CALLER reads to check arguments; nothing wrote the parameter's own symbol,
      and the for-in reader reads the symbol. All four columns, because
      `set of Char` and `set of 1..9` carry no enum id. }
    if ptypesSetElemTk[i] <> 0 then
    begin
      SymSetEnumId[idx] := ptypesSetEnum[i];
      SymSetElemTk[idx] := ptypesSetElemTk[i];
      SymSetElemLo[idx] := ptypesSetElemLo[i];
      SymSetElemHi[idx] := ptypesSetElemHi[i];
    end;
    { A param with an identity is a value with that identity INSIDE the body —
      the same stamp the var-decl sites make, so WriteLn(p) prints the member
      name there too and `not p` on a sized boolean is logical there too.
      SemEnumOf on the ELEMENT arm and not on the value arm, for the reason the
      var-decl sites give: SymElemEnumId has not been widened past enums, and a
      channel handed an identity from a family its readers do not know is how a
      set inherits its element's member names. }
    if SemKindMatches(ptypes[i], ptypesSem[i]) then
    begin
      if parr[i] then SymElemEnumId[idx] := SemEnumOf(ptypesSem[i])
      else SymSemId[idx] := ptypesSem[i];
    end;
    if (procIdx >= 0) and (i < MAX_PROC_PARAMS) then ProcParamIsConst[procIdx * MAX_PROC_PARAMS + i] := pconst[i];
    if (procIdx >= 0) and (i < MAX_PROC_PARAMS) then ProcParamExplicitByRef[procIdx * MAX_PROC_PARAMS + i] := pbyref[i];
    if (procIdx >= 0) and (i < MAX_PROC_PARAMS) then ProcParamUntyped[procIdx * MAX_PROC_PARAMS + i] := puntyped[i];
    { THE DURABLE PARAM ROW -- canonical note. The two other copies point here.

      Why the ProcParam* columns exist: a param SYMBOL is a local and its slot
      is RECYCLED across procs, so a CALLER doing overload matching or argument
      coercion cannot read a parameter's shape back off the symbol. It would not
      even read a stale value -- it reads whatever the next scope allocated
      there, and for the pointer column that is tyUnknown, the untyped-pointer
      sentinel, so the narrowing guard fails OPEN. defs.inc:2685 records the
      original reasoning at length.

      Why there are THREE copies and why that is the actual defect:
      ParseSubroutine registers params on three paths -- `external` (which then
      Exits), forward/interface, and this body pass where the param symbols are
      allocated. Each hand-copied its own overlapping-but-different subset.
      Measured 2026-08-30, BEFORE this widening: body wrote all ~20 columns,
      forward wrote 14, `external` wrote THREE. Three measured divergences from
      fpc 3.2.2 came out of that one asymmetry, in BOTH directions -- an
      external pointer param accepting a class (fails open), a forward pointer
      param accepting a class at a call parsed in between (fails open), and an
      external default argument being refused (fails closed). Counting the
      missing columns mattered more than fixing the one that was filed.

      All three copies are now complete, which closes the defects. The
      duplication itself is NOT closed: collapsing them into one nested
      PersistParamRow is written and blocked -- ParseSubroutine's ~21 staging
      arrays are fixed-size locals and the compiler refuses "capture of
      fixed-size array in a nested routine", while ParseSubroutine is
      re-entrant (pasparser_call.inc:272 calls it from an anonymous-method
      body) so they cannot become globals either. Both filed. UNTIL THAT LANDS:
      a column added here MUST be added to the other two copies. Search for
      "THE DURABLE PARAM ROW" to find them.

      Write-only-true: a method/forward body that repeats params WITHOUT the
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
    { open-array param whose ELEMENT is a named dynamic array: pointer-sized
      slots holding dyn handles. AllocParam cleared it, and param slots are
      reused across procs, so ALWAYS write (0 clears). }
    SymElemDynDepth[idx] := pElemDynDepth[i];
    if (procIdx >= 0) and (i < MAX_PROC_PARAMS) then
    begin
      ProcParamElemRowLen[procIdx * MAX_PROC_PARAMS + i] := pElemRowLen[i];
      ProcParamElemRowLo[procIdx * MAX_PROC_PARAMS + i] := pElemRowLo[i];
      ProcParamElemDynDepth[procIdx * MAX_PROC_PARAMS + i] := pElemDynDepth[i];
      if ptypes[i] = tySet then
        ProcParamSetEnumId[procIdx * MAX_PROC_PARAMS + i] := ptypesSetEnum[i];
        ProcParamAliasIdx[procIdx * MAX_PROC_PARAMS + i] := ptypesAlias[i];
        ProcParamSemId[procIdx * MAX_PROC_PARAMS + i] := ptypesSem[i];
      if ptypes[i] = tyAnsiString then
        ProcParamStrElemTk[procIdx * MAX_PROC_PARAMS + i] := ptypesStrElemTk[i];
      { The capacity twin of the width above, and NOT under that `if`: the width
        question is about tyAnsiString and this one is about the FROZEN kinds, so
        guarding it on tyAnsiString would record nothing for every string[N]
        there is. Written flat and dedented so the scope is visible -- the line
        above it ends its own `if`, and this file already has one line (the
        AliasIdx write under the tySet test) that reads as guarded and is not.
        ptypesStrCap is 0 for anything that is not a frozen string, so the write
        is unconditional by construction. defs.inc says why the N cannot be read
        back off the param SYMBOL. }
      ProcParamStrCap[procIdx * MAX_PROC_PARAMS + i] := ptypesStrCap[i];
    end;
    { The SYMBOL needs the width too, for a different reader than the durable
      column above: that one answers a CALLER, this answers the callee's own
      body, where ASTStrElemTkOf resolves a string parameter through its
      AN_IDENT arm. AllocParam cannot do it -- it stamps ElemType := tk and has
      no valid LastTypeStrElemTk to read, because a param's type is parsed long
      before its symbol is allocated and the channel's window (defs.inc) closed
      with the ParseTypeKind that set it. The staged value is the only live copy
      here, which is what the staging array is for.

      NOT FOR AN ARRAY PARAM, and this is the whole subtlety: `ptypes[i]` for an
      array param is the ELEMENT kind, so `array of AnsiString` reaches this
      line with ptypes[i] = tyAnsiString exactly as a scalar string does -- and
      for an array, Syms[].ElemType legitimately IS the element kind
      (tyAnsiString), which every backend's dyn-array arm reads to pick an
      8-byte managed stride. Overwriting it with tyChar retyped the elements to
      a 1-byte char and the compiler stopped reproducing itself: MEASURED as a
      self-host fixedpoint failure (no convergence after 4 rounds), not
      predicted. An array of managed strings keeps its ELEMENTS' width in
      SymStrElemTk instead -- that is what 6b's carrier is for, and the same
      IsArray split defs.inc:2502 already documents. }
    if (ptypes[i] = tyAnsiString) and (not parr[i]) and (pDynDepth[i] = 0) then
      Syms[idx].ElemType := IntToTypeKind(ptypesStrElemTk[i]);
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
      SetSymPointerType(idx, ptypesPtrElemTk[i], ptypesPtrElemRec[i],
                        ptypesPtrDepth[i], ptypesPtrBaseTk[i],
                        ptypesPtrBaseRec[i]);
      { Persist the param's POINTEE, for the same reason the rec id below is
        persisted and stated in the same words: param sym slots are reused
        across procs, so a caller's overload matching cannot read it back from
        the sym. It does not read a stale value -- it reads whatever the next
        scope allocated there, which for this field is tyUnknown, the
        untyped-pointer sentinel, so the narrowing guard fails OPEN. }
      if (procIdx >= 0) and (i < MAX_PROC_PARAMS) then
      begin
        ProcParamPtrElemTk[procIdx * MAX_PROC_PARAMS + i] := Ord(ptypesPtrElemTk[i]);
        ProcParamPtrElemRec[procIdx * MAX_PROC_PARAMS + i] := ptypesPtrElemRec[i];
      end;
      if PxxDbgEnabled('p.ptrparam') then
        writeln('PXXDBG p.ptrparam REG proc=', Procs[procIdx].Name,
                ' i=', i, ' sym=', idx,
                ' elemtk=', Ord(ptypesPtrElemTk[i]),
                ' stored=', Ord(Syms[idx].PtrElemTk),
                ' durable=', ProcParamPtrElemTk[procIdx * MAX_PROC_PARAMS + i],
                { depth and ultimate base, because they are what the char-pointer
                  predicates actually consult: `PChar` and `^PChar` share a base
                  and differ ONLY in depth, so a probe that prints the immediate
                  pointee alone cannot tell them apart at the one place it is
                  read. Note a.symptr cannot cover this -- it fires from Alloc*,
                  BEFORE SetSymPointerType, so for a parameter it prints the
                  recycled slot's previous occupant rather than the shape just
                  recorded. feature-a-typeref-migrate-consumers }
                ' depth=', ptypesPtrDepth[i],
                ' basetk=', ptypesPtrBaseTk[i],
                ' baserec=', ptypesPtrBaseRec[i],
                ' symcount=', SymCount);
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
  { Wire Self's RecName so field lookups resolve against the owner class — or,
    in a HELPER's method, against the EXTENDED type, which is what Self really
    is there. Without the fork a class helper's `Self.Value` searched the helper
    row (which has no fields) and the extended class's members were unreachable
    through Self. Only when the target HAS a rec: a helper for a scalar
    (`type helper for Integer`) leaves Self pointing at the helper row as
    before, which is what its own member lookups want. }
  if (methOwnerCi >= 0) and not isStaticMethod then
  begin
    if (UClsHelperTk[methOwnerCi] >= 0) and
       (UClsHelperRec[methOwnerCi] <> REC_NONE) then
      Syms[Procs[procIdx].Params[0].SymIdx].RecName := UClsHelperRec[methOwnerCi]
    else
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
      { …at the declared NESTING, not a hardcoded 1. `function F: TMat` where
        `TMat = array of array of Integer` gave Result depth 1, so an outer
        element was read as a 4-byte Integer instead of an 8-byte handle:
        inside the function `Length(Result[1])` answered garbage and
        `Result[1] := row` wrote a truncated handle, which the caller then
        indexed into a SEGFAULT. Everything else about the value was fine — a
        nested dyn-array LOCAL works, and the caller received the right value in
        `Result := loc` — so the defect was exactly this symbol's shape.
        bug-p-a-nested-dynamic-array-result-crashes-however-it-is-reached }
      idx := ProcRetDynDepth[procIdx];
      if idx < 1 then idx := 1;
      idx := AllocDynArray('Result', retElemTk, idx);
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
        if ArrTypeStrElemTk[retArrAi] <> 0 then
          LastTypeStrElemTk := IntToTypeKind(ArrTypeStrElemTk[retArrAi]);
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
        count above came from TypeSlotSize(elemTk), which is the whole-value size
        only for scalars: `array[0..2] of string[8]` copied 3*8 of a 3*(2+8)
        slot run and came back blank, and a record element copied one pointer's
        worth. Same elemSize rule as the whole-static-array copy in ir.inc. }
      if retType = tyRecord then
        sz := RecSize(Syms[idx].ElemRecName)
      else if TypeIsFrozenString(retType) then
        sz := FrozenStrSlotSize(retType, SymStrCap[idx])
      else
        sz := TypeSlotSize(retType);
      retFixedArrBytes := Syms[idx].ArrLen * sz;
      ProcRetFixedArrBytes[procIdx] := retFixedArrBytes;
      ProcRetArrAi[procIdx] := retArrAi;
    end
    else
    begin
      AllocVar('Result', retType);
      Procs[procIdx].RetSymIdx := SymCount - 1;
      Syms[SymCount-1].Kind := skLocal;
      { Furnish Result the way a DECLARED variable of the same type is furnished.
        pasparser_decl.inc's var path stamps `SymProcSig[idx] := LastTypeProcSig`
        for a tyRecord (method pointer) and for a tyPointer (plain procedural
        value); the result symbol is not declared, it is minted from the return
        KIND alone, so it carried -1 and looked like an ordinary record/pointer
        local. Every consumer that asks "is this lvalue a procedural value?" —
        the assignment arm that reaches for a parenless method reference, the
        statement-level and expression-level indirect-call arms — gates on
        `SymProcSig >= 0`, so `Result := s.Pick` was refused while
        `t := s.Pick; Result := t` on a local of the identical type compiled.
        The LHS spelling was a third axis nobody had furnished.
        bug-p-result-is-not-a-method-pointer-lvalue }
      if ((retType = tyRecord) or (retType = tyPointer)) and (retProcSig >= 0) then
      begin
        SymProcSig[SymCount-1] := retProcSig;
        SymSyncTypeRef(SymCount-1);
      end;
      { ...and its SEMANTIC IDENTITY, furnished from the row the return type
        already filled, for exactly the reason the paragraph above gives: Result
        is not DECLARED, it is minted from the return KIND alone, so every fact
        a declaration would have carried has to be restated here or it is lost.
        `function F: LongBool; begin Result := True; end` stored a plain 1 --
        the store is an ordinary assignment and ir.inc's AN_ASSIGN arm asks the
        DESTINATION's identity, which Result did not have. ProcRetSemId is
        already guarded by SemKindMatches at every site that writes it, so it
        needs no second guard here.
        decide-how-a-type-carries-an-identity-its-kind-cannot-hold }
      if ProcRetSemId[procIdx] <> SEM_NONE then
        SymSemId[SymCount-1] := ProcRetSemId[procIdx];
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

  { Optional var/const/type/label sections, in any order — `label` included,
    because ISO Pascal puts it FIRST and it used to be handled only by a
    separate loop further down, i.e. only when it came last.
    bug-a-a-label-section-must-come-last-in-a-routine }
  while (CurTok.Kind in [tkVar, tkConst, tkType, tkProcedure, tkFunction]) or
        ((CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'label')) do
    case CurTok.Kind of
      tkVar:   ParseVarSection;
      tkConst: ParseConstSection(-1, 0, False);
      tkType:  ParseTypeSection;
      tkProcedure, tkFunction: ParseNestedRoutine;
      tkIdent: ParseLabelSection;
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
  { A `label` section that came after everything else — the decl loop above
    stops at the out-param clearing, so a trailing one still lands here. }
  while (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'label') do
    ParseLabelSection;

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
    { INHERIT THE RESUMER'S EXCEPTION CHAIN. CoAlloc seeds this context's saved
      exc_top with 0 (`fresh chain on this stack`) and CoSwitch restores it on
      the way in, so a `raise` in a stackful generator body walked an EMPTY
      chain, found no handler and killed the process — while the IDENTICAL
      source as `generator; stackless;` gives caught=3, and so does a plain
      procedure raising inside the same try. Three-way control in the ticket.

      The consumer's chain head is recoverable from the instance and needs no
      new intrinsic: CoNext calls CoSwitch with pfrom = &callerctx, so
      [self + CO_OFF_CALLERCTX] is the consumer's rsp at the switch, and
      CoSwitch pushes exc_top LAST (lowest address) before storing rsp — so
      [[self + CO_OFF_CALLERCTX]] is exactly the chain the consumer was running
      with. Linking to it at body entry makes the generator's chain an extension
      of its resumer's, which is what a `call` would have given it.

      THE ASSUMPTION THIS RESTS ON, stated rather than left implicit: the link
      is made ONCE, at first entry, so it is only valid while the resumer's
      frame outlives the coroutine. That holds because CoAlloc and CoNext are
      reached from exactly one place — the for-in desugar — so creation and
      every resume are the same frame, and the resume happens at the loop HEAD,
      outside any try the loop BODY pushes and pops. A first-class stackful
      generator resumed from a different dynamic context would need the link
      refreshed per resume; there is no such thing today and the day there is,
      this is the site.
      bug-a-an-exception-raised-in-a-stackful-generator-body-does-not-reach-the-for-in-handler
      No nil guard on callerctx: CoSwitch does `mov [pfrom], rsp` BEFORE the
      switch and CoNext passes pfrom = &callerctx, so it is written on the way
      in and cannot be 0 at body entry. A guard here would have to jump over
      EmitStatusSlotX64, whose length is not fixed (the threadsafe build takes a
      `gs:` prefix) — a hand-counted branch distance over a variable-length
      emitter is a worse hazard than the one it would be guarding. }
    EmitB($48); EmitB($8B); EmitB($43); EmitB(CO_OFF_CALLERCTX);  { mov rax, [rbx+callerctx] }
    EmitB($48); EmitB($8B); EmitB($00);                           { mov rax, [rax]  (consumer's saved exc_top) }
    EmitStatusSlotX64(0, BSS_EXC_TOP, True);                      { mov [EXC_TOP], rax }
    for i := 0 to nparams - 1 do
    begin
      gpi := Procs[procIdx].Params[i].SymIdx;
      sz := ParamSlotWordSize(gpi);
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
    { ASK THE LANDING-PAD QUESTION AGAIN, exactly as the plain body below does.
      The old comment there said a generator body's frame "the prologue decision
      already covers" — measured 2026-09-04 and it does not, for the STACKLESS
      form. `raise Exception.Create(gmsg + Chr(65))` inside a
      `generator; stackless;` routine driven by `for x in Gen(1)` inside a try:

        raiser body                       live @2000  @8000   slope
        raise Create(gmsg)      no temp        1901    7815   0.986
        raise Create(gmsg+Chr)  temp           3608   14836   1.871
        Length(gmsg+Chr)=0      temp, no raise 1901    7815   0.986

      The third row is the parent ticket's discriminator and it says the same
      thing here: the SAME temp in the SAME routine is released on the normal
      path and not on the unwind path. The 0.986 baseline under all three rows
      is the generator INSTANCE, leaks with or without an exception, and is
      bug-nilpy-a-generator-instance-leaks-its-locals-and-argument-cells — a
      different leak that this arm does not touch and must not be credited with.

      Safe here for a reason the STACKFUL branch cannot borrow: a stackless step
      function is entered by an ordinary call and leaves by an ordinary return,
      so its frame is an ordinary frame and this pad is the same construct the
      plain body gets. The stackful branch is entered by CoSwitch `ret`ing into
      it and is deliberately NOT armed — and an exception raised in a stackful
      generator body does not reach the driving for-in's handler at all
      (measured the same day, filed separately), so there is no unwind path
      through that frame to give a pad to yet.
      bug-a-a-generator-body-raising-past-a-managed-temp-is-not-covered-by-the-unwind-landing-pad }
    if (not needsProcCleanupFrame) and TargetHasProcCleanupFrame and
       ExceptionUsed and (not isAsmFunc) then
      ProcCleanupFrameWanted := True;
    ProcCleanupFrameLateArmed := False;
    CompileAST(genStepAST);
    ProcCleanupFrameWanted := False;
    if ProcCleanupFrameLateArmed then
    begin
      needsProcCleanupFrame := True;
      cleanupJnePatch := ProcCleanupFrameLatePatch;
    end;
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
    { A METHOD OF A SPECIALIZATION IS A TEMPLATE BODY, copied here from another
      file, so it PARSES AS ITS DECLARING UNIT.

      A template's method bodies are buffered as tokens and streamed to each
      specialization, then re-parsed there — so by default they resolved their
      names in the SPECIALIZING scope. That gave them the declaring unit's
      INTERFACE (via the importer's `uses`) and the specializer's own
      declarations, which SHADOW, and never the declaring unit's implementation
      section: a unit template calling its own private helper ran the PROGRAM's
      same-named routine, and with no such routine the unit stopped compiling at
      all.

      Becoming the unit for the duration answers both halves at once. Its private
      names resolve on DeclVisibleSect's `declUnit = CurrentUnitIdx` path, and
      the PROGRAM's names stop being visible — which is correct rather than
      incidental: a unit cannot see a program's declarations, and this body is
      the unit's code no matter where its tokens were pasted.

      Making the unit merely VISIBLE was tried first and is not enough; the
      specializing scope's same-named routine still won, which is the silent
      wrong-binding half and the worse one.

      Saved and restored rather than assigned: a body can contain a nested
      routine that comes back through here.
      bug-p-a-generic-template-body-resolves-its-symbols-at-the-specialization-site }
    savedBodyUnitIdx := CurrentUnitIdx;
    savedSpecHost    := SpecBodyHostUnitIdx;
    if methOwnerCi >= 0 then
    begin
      tmplDeclUnit := SpecTemplateDeclUnit(
                        GetTokenStrFromRaw(UClsNOff[methOwnerCi], UClsNLen[methOwnerCi]));
      if tmplDeclUnit >= 0 then
      begin
        { Becoming the declaring unit is only half of the scope. The other half
          is where the specialization was WRITTEN, which is where its own
          synthesized rows were minted -- see ClassRowVisibleHere. }
        SpecBodyHostUnitIdx := CurrentUnitIdx;
        CurrentUnitIdx := tmplDeclUnit;
      end;
    end;
    inlineBodyNode := WrapManagementOps(procIdx, ParseBlockAST);
    CurrentUnitIdx := savedBodyUnitIdx;
    SpecBodyHostUnitIdx := savedSpecHost;
    if methOwnerCi < 0 then TryRetainInlineBody(procIdx, inlineBodyNode);
    { ASK THE LANDING-PAD QUESTION AGAIN, from inside CompileAST, once the
      hidden argument temps exist. Requested only when the prologue said NO -- a
      proc that already has its frame must not get a second one.
      An ASM body is still not re-asked: it emits its own code and mints no
      temps through lowering. A STACKLESS GENERATOR body now is — this comment
      used to say a generator's frame "the prologue decision already covers"
      and that was measured false on 2026-09-04; see the arm above. }
    if (not needsProcCleanupFrame) and TargetHasProcCleanupFrame and
       ExceptionUsed and (not isAsmFunc) then
      ProcCleanupFrameWanted := True;
    ProcCleanupFrameLateArmed := False;
    CompileAST(inlineBodyNode);
    ProcCleanupFrameWanted := False;
    if ProcCleanupFrameLateArmed then
    begin
      needsProcCleanupFrame := True;
      cleanupJnePatch := ProcCleanupFrameLatePatch;
    end;
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
  for i := GotoLabelBase to GotoLabelCount - 1 do
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
  ProcCleanupFrameWanted := savedCleanupFrameWanted;
  ProcCleanupFrameLateArmed := savedCleanupFrameLateArmed;
  ProcCleanupFrameLatePatch := savedCleanupFrameLatePatch;

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
  GotoLabelBase := savedGLB;
  CurProc   := -1;
  CurBodyHdrTok := savedVisVarSeq;   { restore decl-order horizon (see all outside a body) }
  CurSelfClass := REC_NONE;
  CurMethClass := REC_NONE;
  MethImplOwnerCi := savedMIO;
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

function CGtkIncludeRoot: AnsiString;
{ The ONE place a GTK version becomes an include root. Paired with CGtkStem
  below and read by cpreproc.inc's BuildCSysIncludeDirs, so the headers and the
  soname are derived from the same variable and cannot disagree -- which is the
  hazard decide-which-gtk-a-bare-gtk-gtk-h-means names: GTK 3 headers against a
  GTK 2 library is what doing HALF this change produces.
  feature-a-gtk-version-selection-at-the-header-and-soname-layer }
begin
  if CGtkVersion = 2 then Result := '/usr/include/gtk-2.0/'
  else if CGtkVersion = 4 then Result := '/usr/include/gtk-4.0/'
  else Result := '/usr/include/gtk-3.0/';
end;

function CGtkStem: AnsiString;
{ ...and the matching library stem, which CHeaderSoname turns into a soname.
  GTK 2's stem is `gtk-x11-2.0' rather than `gtk-2': the library is
  libgtk-x11-2.0.so.0, so the stem is not derivable from the version number and
  a table is the honest way to say that. }
begin
  if CGtkVersion = 2 then Result := 'gtk-x11-2.0'
  else if CGtkVersion = 4 then Result := 'gtk-4'
  else Result := 'gtk-3';
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
    { FOLLOWS THE SELECTOR, despite the `3' in the name, and that is deliberate.
      The C include list is FLAT AND GLOBAL -- there is no per-unit search path
      -- so one compilation has exactly one GTK's headers. Pinning this alias to
      GTK 3 while --gtk=2 moved the include root would hand it GTK 2's headers
      against libgtk-3.so.0, which is precisely the mismatch this feature exists
      to make unrepresentable. The flag wins and the two halves stay coherent.
      The name is a known wart, not an oversight: the ruling records that `gtk',
      `gtk3_c' and `gtk3' live in three different namespaces (two C aliases and
      a Pascal unit) and that renaming without fixing that just moves the
      confusion. }
    stem := CGtkStem
  else if lo = 'gtk' then
    { Selector-driven; GTK 3 by default, ruled 2026-08-31. `gtk` and `gtk3_c` now name the same library on
      purpose. NOTE these are not the parallel names they look like: `gtk` and
      `gtk3_c` are C-header ALIASES resolved here, while `gtk3` is a real Pascal
      unit (lib/pcl/gtk3.pas) that this map never sees -- so `uses gtk3` finds a
      source file, not an alias. Renaming without fixing that just moves the
      confusion; see decide-which-gtk-a-bare-gtk-gtk-h-means.
      The `gtk-x11-2.0` stem is intentionally LEFT in the soname map and the
      system-lib set below: nothing produces it from a `uses` clause any more, but
      it is still a valid stem to name explicitly, and deleting a mapping because
      one caller stopped using it is deleting code believed dead rather than
      verified dead -- and --gtk=2 now produces it again, so it is live. }
    stem := CGtkStem
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
  else if CStemMatches(stem, 'gtk-4') then soname := 'libgtk-4.so.1'   { --gtk=4; the runtime lib ships even where the -dev headers do not }
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
  Result := CStemMatches(stem, 'gtk-3') or CStemMatches(stem, 'gtk-4') or
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
procedure ParseUsesUnitBody(const name: AnsiString;
  diagLine: Integer; const diagSpell: AnsiString); forward;

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
{$ifndef PXX_NO_CFRONT}
var k: Integer;
{$endif}
begin
  if Length(content) > 0 then Exit;
{$ifndef PXX_NO_CFRONT}
  { PXX'S OWN HEADERS FIRST, and this procedure's NAME is the reason they were
    not. It probes /usr/include, it is called `PyTryHostHeader', and it is the
    ONLY header probe the unit resolver has -- so a header crtl SHIPS was
    invisible to `import <name>' while the very same name reached crtl's copy
    from an ordinary C `#include <name.h>'. Measured 2026-09-02: crtl has a
    4924-byte <stdlib.h>, a `.c` file including <stdlib.h> got it, and
    `import stdlib` from a .npy got glibc's.

    That is not just the wrong header, it is a MIXED CHAIN, and the mixture is
    what actually broke: glibc's stdlib.h pulled glibc's
    bits/libc-header-start.h, which asked for <features.h> and got CRTL's --
    deliberately empty, so __GLIBC__ stays undefined for busybox's makedev --
    and glibc's chain came out with no __GNUC_PREREQ. The next host header to
    use one, bits/floatn.h, then met `0 (4, 3)' inside an #if, three hops
    downstream of the cause. Keeping one universe per chain is the fix; making
    the preprocessor tolerate the other universe's headers is not.

    CIncludeDirs is walked rather than the crtl anchors being spelled out here:
    it is the SAME list the C `<>` search uses, so the PXX_HOME / ExeDir /
    stable-layout anchors have exactly one home and a user's -I can supply a
    header for an import too. AddDefaultCIncludeDirs is idempotent and Exits
    under -nostdinc. }
  AddDefaultCIncludeDirs;
  k := 0;
  while (Length(content) = 0) and (k < CIncludeDirCount) do
  begin
    ConcatThree(CIncludeDirs[k], cName, '.h', path);
    LoadFile(path, content);
    Inc(k);
  end;
{$endif}
  if Length(content) = 0 then
  begin
    ConcatThree('/usr/include/', cName, '.h', path);
    LoadFile(path, content);
  end;
  if Length(content) = 0 then
  begin
    ConcatThree(CGtkIncludeRoot + 'gtk/', cName, '.h', path);
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

procedure ParseUsesUnitAt(const name: AnsiString;
  diagLine: Integer; const diagSpell: AnsiString); forward;

procedure ParseUsesUnit(const name: AnsiString);
{ The ordinary entry: no diagnostic origin, so every message reports CurTok
  exactly as before. ParseUsesUnitAt is the same routine for a caller that has
  already consumed the tokens it wants blamed. }
begin
  ParseUsesUnitAt(name, 0, '');
end;

procedure ParseUsesUnitAt(const name: AnsiString;
  diagLine: Integer; const diagSpell: AnsiString);
var savedProc, savedFrame, savedSelf, vsym: Integer;
begin
  savedProc := CurProc; savedFrame := FrameSize; savedSelf := CurSelfClass;
  CurProc := -1;
  ParseUsesUnitBody(name, diagLine, diagSpell);
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
    savQ, savR, savStmtR, savI, savStmtI: Boolean;
    savN, savStmtN: Integer;
begin
  saved := UsesInjected;
  { A COMPILER-INJECTED runtime unit compiles under the COMPILER's default
    switches, never under whatever the user's source happened to leave on.
    These are lexer globals with exactly one reset (PasInitDefines, once per
    compilation), so before this they simply carried the user's last {$Q±} /
    {$R±} / {$I±} / {$NILCHECKS} state straight into builtin/*.pas.

    That is not a tidiness point, it produced a hard compile failure. A program
    ending with {$Q+} still on made softfloat.pas compile WITH overflow checks,
    and softfloat is pulled BEFORE builtinheap (pasparser_prog.inc), so the
    checks it emitted called a PXXOverflow that did not exist yet:

      pascal26:86: error: {$Q+}: PXXOverflow runtime helper not found
        in: ./compiler/builtin/softfloat.pas

    -- on arm32 and riscv32, the two targets that pull softfloat. The message
    blames "builtinheap not loaded" and that is a red herring: `uses sysutils`
    loads it and the error is unchanged, because the problem is ORDER, not
    absence. Moving {$Q-} above `end.` in the user program made both targets
    compile and trap correctly, which is what identified this.

    Reset to the DEFAULTS as a block rather than switch by switch: the rule is
    "a unit the program never asked for is not governed by the program's
    switches", and stating it once is what keeps the next switch from
    re-opening it. {$R+} leaks identically today and merely happens not to
    fail, which is the version of this bug nobody would have found.
    bug-a-q-plus-overflow-checking-has-no-runtime-helper-on-arm32-and-riscv32 }
  savQ := QChecksVal; savR := RChecksVal; savStmtR := StmtRChecks;
  savI := IChecksVal; savStmtI := StmtIChecks;
  savN := NChecksVal; savStmtN := StmtNChecks;
  QChecksVal := False;
  RChecksVal := False; StmtRChecks := False;
  IChecksVal := True;  StmtIChecks := False;
  NChecksVal := NILCHK_DEFAULT; StmtNChecks := NILCHK_DEFAULT;
  UsesInjected := True;
  ParseUsesUnit(name);
  UsesInjected := saved;
  QChecksVal := savQ; RChecksVal := savR; StmtRChecks := savStmtR;
  IChecksVal := savI; StmtIChecks := savStmtI;
  NChecksVal := savN; StmtNChecks := savStmtN;
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

procedure ParseUsesUnitBody(const name: AnsiString;
  diagLine: Integer; const diagSpell: AnsiString);
{ DIAGNOSTIC ORIGIN, supplied by a caller whose CurTok has already moved past
  the thing the user wrote. Zero means "there is none" and every message falls
  back to CurTok, which is right for a Pascal `uses` -- CurTok is still ON the
  unit name when the loader fails, so that path reported the correct line all
  along and is deliberately left alone.

  The C caller is the one that needs this. CParsePascalUnitMarker consumes the
  marker identifier, both string tokens and the semicolon BEFORE it calls, so
  by the time a miss is raised CurTok is the first token of the NEXT line and
  the error named a real, innocent line of the user's source. diagSpell is the
  author's own spelling (`nosuch.pas`), which the loader has by then rewritten
  into an absolute path with the extension stripped -- correct as input to the
  loader, wrong as output to a human.
  bug-c-a-missing-pascal-unit-diagnostic-points-at-the-wrong-line-and-leaks-an-internal-marker }
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
  { A C candidate found in a -I/-Fu search root, HELD BACK until the Pascal
    chain has had its turn. See the deferral note at the search-root loop. }
  deferredCPath, deferredCContent: AnsiString;
  deferredCIsHeader: Boolean;
  guardIdx: Integer;   { CompiledUnitKey — see the note at its assignment }
  gPath: AnsiString;   { …the normalised path a path-form reference keys on }
  realIdx: Integer;    { alias-resolved unit for the already-compiled edge }
  { True when the compiler INJECTED this `uses`, not the source. Captured at
    the ambience site below, because UsesInjected is cleared there and the
    file search that needs the answer runs several hundred lines later. }
  isAmbientLoad: Boolean;
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
  savedNestedComments, savedDelphiMode, savedUnitImplCU: Boolean;
  unitAlias: AnsiString;   { pxxlib.cfg `unitalias` answer for a dotted name }
  unitNeedsText: Boolean;
  unitNeedsRootMeth: Boolean;   { this unit calls .Equals/.GetHashCode/.ToString }
  unitNeedsMath: Boolean;       { …and sqrt/ln/exp/sin/cos/arctan/pi }
  unitNeedsThreads: Boolean;    { …and BeginThread/TThreadID/… }
  unitTnm: AnsiString;
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
  { Delphi dotted unit-scope names: `uses System.Classes` is `classes` when the
    importing unit's pxxlib.cfg says so. Applied HERE, before anything records
    an identity, so `System.Classes` and `Classes` dedupe as ONE compiled unit
    rather than two — which they are. A dotted name with no alias falls straight
    through to the existing chain and still fails with its own spelling in the
    message, so nothing about a plain misspelling changes.
    feature-p-resolve-delphi-dotted-unit-scope-names }
  if not isPath then
  begin
    unitAlias := PxxUnitAliasFor(CurUnitDir, lo);
    if Length(unitAlias) > 0 then
    begin
      lo := LowerCase(unitAlias);
      cName := unitAlias;
    end;
  end;
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
  isAmbientLoad := UsesInjected or UnitIsAmbient(CurrentUnitIdx);
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
  deferredCPath := '';
  deferredCContent := '';
  deferredCIsHeader := False;
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
      if diagLine > 0 then
      begin
        { The C author wrote `#include "x.pas"`, so say include and say it in
          their own spelling. ErrorAt also passes withContext=False, which drops
          the `near:` window -- and that window was printing the preprocessor's
          internal __pxx_pascal_unit marker, a token the author never wrote and
          cannot grep for. }
        ConcatThree('include: Pascal unit source not found: ', diagSpell, '', emsg);
        ErrorAt(diagLine, emsg);
      end;
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
  { The user's own source directory — for a unit the USER named, and only then.
    A compiler-INJECTED `uses` must never bind here: the program did not ask for
    builtinheap, so a file of that name sitting beside it is not an override, it
    is a collision, and the compiler would silently swap its own runtime for it.
    Measured 2026-09-02: an empty `unit builtinheap; interface implementation
    end.` next to a five-line hello program takes over, and a STALE but valid
    copy is the dangerous shape — it compiles, and every measurement afterwards
    reads as "my change to the RTL did nothing". That cost a session most of an
    afternoon; strace showed the openat and nothing else could.

    The .c/.h probes in this same group take the guard too, and not on
    principle: with only the Pascal probes guarded, a `builtinheap.c` of one
    line beside the same program still took over (`unresolved forward:
    PXXStrFromLit in lib/rtl/pxxcio.pas`). Every name reachable this way is an
    RTL unit the compiler injects -- builtinheap, builtin, math, textfile,
    pxxcio, softfloat, pylib, promocore, palthreadobj -- and `math` or
    `textfile` beside a user's program is not a far-fetched filename.

    Deliberately NOT extended to the -Fu roots below: an explicit -Fu override
    of an RTL unit is a supported mechanism and test/aintostr_units relies on it
    (its builtinheap.pas is a documented impostor whose whole job is to reach a
    compiler diagnostic). The difference is that -Fu is something the user
    typed and a file lying in a directory is not. }
  if (Length(UnitContent) = 0) and (not isAmbientLoad) then
  begin
    ConcatThree(SourceFileDir, lo, '.pas', path);
    LoadFileCI(path, UnitContent);
  end;
  if (Length(UnitContent) = 0) and (not isAmbientLoad) then
  begin
    ConcatThree(SourceFileDir, lo, '.pp', path);
    LoadFileCI(path, UnitContent);
  end;
  if (Length(UnitContent) = 0) and (not isAmbientLoad) then
  begin
    ConcatThree(SourceFileDir, cName, '.c', path);
    LoadFile(path, UnitContent);
    if Length(UnitContent) > 0 then isCUnit := True;
  end;
  if (Length(UnitContent) = 0) and (not isAmbientLoad) then
  begin
    ConcatThree(SourceFileDir, cName, '.h', path);
    LoadFile(path, UnitContent);
    if Length(UnitContent) > 0 then begin isCUnit := True; isCHeader := True; end;
  end;

  { User unit search roots (`-Fu<dir>` / `-I<dir>`), in flag order. Searched
    after the including file's own directory and before the compiler-anchored
    builtin/RTL/LCL dirs, so a project or per-platform dir (e.g.
    lib/rtl/platform/posix/) can supply or override a unit by name — the PAL
    backend-selection mechanism. Dirs carry a trailing '/' (AddPasUnitDir).

    A C CANDIDATE FOUND HERE IS HELD BACK, not taken. `-I<dir>` adds a root for
    BOTH `#include` and `uses` (compiler.pas, feature-dynamic-include-paths-
    config), so `-Ilib/crtl/include` put twenty-seven C headers on the Pascal
    unit path — three of which, math.h / netdb.h / strings.h, share a basename
    with an RTL unit. Taking the header here meant it beat lib/rtl/math.pas,
    which is searched further down, and the damage went two ways:

      * the loud one, when the header lacks the symbol: `uses strings` +
        `-Ilib/crtl/include` gives `undefined variable (StrPas)`, pointing at
        the use rather than at the flag;
      * the SILENT one, when the header HAS it: the reference binds, `ok:`
        prints, and the `uses` becomes a dynamic import — the binary carries a
        DT_NEEDED on `libstrings.so` and dies at load. Nothing in the build
        says so.

    So the rule is namespace ordering, not a special case for these three
    names: a Pascal unit ANYWHERE on the chain outranks a C header found in a
    search root. The header is still reachable — it is adopted below if the
    whole Pascal chain misses — which is what keeps a real FFI `uses <header>`
    working when no `.pas` of that name exists.

    NOT extended to the SourceFileDir probes above: a `.c`/`.h` sitting next to
    the program you are compiling is an explicit local choice, and the reported
    defect is about a root reached through a flag. Different question, left
    alone deliberately.
    bug-a-a-c-include-path-captures-a-pascal-uses-and-emits-a-dynamic-import }
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
    if (Length(UnitContent) = 0) and (Length(deferredCContent) = 0) then
    begin
      ConcatThree(PasUnitDirs[i], cName, '.c', path);
      LoadFile(path, deferredCContent);
      if Length(deferredCContent) > 0 then
      begin
        deferredCPath := path;
        deferredCIsHeader := False;
      end;
    end;
    if (Length(UnitContent) = 0) and (Length(deferredCContent) = 0) then
    begin
      ConcatThree(PasUnitDirs[i], cName, '.h', path);
      LoadFile(path, deferredCContent);
      if Length(deferredCContent) > 0 then
      begin
        deferredCPath := path;
        deferredCIsHeader := True;
      end;
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
    { A C candidate already held back from a search root OUTRANKS this one:
      the deferral reorders C behind Pascal, never behind other C. Without
      this guard `-Futest/gtk3stock`'s gtk3_c.h lost to lib/pcl/gtk3_c.h and
      the shadow was silently defeated — and the test that shadow exists for
      could not see it, because both headers now include the installed GTK
      surface and produce byte-identical output. Found with a `#error` poison
      probe, not by reading. }
    if (Length(UnitContent) = 0) and (Length(deferredCContent) = 0) then
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
    { A held-back search-root C candidate outranks these too — see the note at
      the RTL .h probe above. }
    if (Length(UnitContent) = 0) and (Length(deferredCContent) = 0) then
    begin
      ConcatThree(lcldir, cName, '.c', path);
      LoadFile(path, UnitContent);
      if Length(UnitContent) > 0 then isCUnit := True;
    end;
    if (Length(UnitContent) = 0) and (Length(deferredCContent) = 0) then
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
    if (Length(UnitContent) = 0) and (Length(deferredCContent) = 0) then
    begin
      ConcatThree('lib/rtl/', cName, '.h', path); LoadFile(path, UnitContent);
      if Length(UnitContent) = 0 then begin ConcatThree('lib/pcl/', cName, '.h', path); LoadFile(path, UnitContent); end;
      if Length(UnitContent) = 0 then begin ConcatThree('compiler/', cName, '.h', path); LoadFile(path, UnitContent); end;
      if Length(UnitContent) > 0 then begin isCUnit := True; isCHeader := True; end;
    end;
    if (Length(UnitContent) = 0) and (Length(deferredCContent) = 0) then
    begin
      ConcatThree('compiler/', cName, '.c', path); LoadFile(path, UnitContent);
      if Length(UnitContent) > 0 then isCUnit := True;
    end;
  end;

  { The held-back C candidate from a `-I`/`-Fu` search root, adopted now that
    every Pascal probe has missed. This is the second half of the deferral
    above and the reason it is an ORDERING change rather than a removal: a real
    FFI `uses <header>` still resolves exactly as before whenever no `.pas` of
    that name exists anywhere on the chain, which is every case in the tree
    except math / netdb / strings.

    Placed after the CWD-relative fallback so no other C probe can be reordered
    by this. That was checked rather than assumed: the only `.h`/`.c` files the
    later blocks can reach are lib/pcl/gl_c.h, lib/pcl/gtk3_c.h and
    lib/rtl/math_ext.h, and none of them shares a basename with anything a
    search root is likely to carry. }
  if (Length(UnitContent) = 0) and (Length(deferredCContent) > 0) then
  begin
    UnitContent := deferredCContent;
    path := deferredCPath;
    isCUnit := True;
    isCHeader := deferredCIsHeader;
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
    if diagLine > 0 then
    begin
      ConcatThree('include: Pascal unit source not found: ', diagSpell, '', emsg);
      ErrorAt(diagLine, emsg);
    end;
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
{$ifdef PXX_NO_NILPY}
    { A Pascal unit may `use` a `.py` MODULE, which is the one place the Pascal
      parser reaches into the NilPy frontend for something other than an
      expression hook. Refused BY NAME rather than by a parse failure, the same
      shape every other omitted frontend uses.
      feature-a-build-a-reduced-compiler-by-selecting-frontends-and-targets }
    Error('uses ' + lo + ': this compiler was built without the NilPy frontend (built with PXX_NO_NILPY); rebuild without that define to import a .py module');
    Exit;
{$else}
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
    { A `.py` MODULE has no interface/implementation split, so nothing it
      declares is section-private -- but the ENCLOSING scope may be a Pascal
      unit's implementation section, and InUnitImpl is global. Cleared here for
      the same reason the C branch below clears it. }
    savedUnitImplCU := InUnitImpl;
    InUnitImpl := False;

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
    InUnitImpl := savedUnitImplCU;
    CurUnitDir := savedUnitDir;
    TokPos := savedTokPos;
    CurTok.Kind := savedCurTokKind;
    CurTok.SVal := savedCurTokSVal;
    CurTok.IVal := savedCurTokIVal;
    CurTok.Line := savedCurTokLine;
    Exit;
{$endif}
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
    { C HAS NO INTERFACE/IMPLEMENTATION SECTION, so no C declaration is ever
      section-private -- and its linkage is FLAT across translation units on
      purpose (VisibilityAllows' UnitIsCTranslationUnit arm). InUnitImpl is a
      global, though, so a `uses './x.c'` written in a Pascal unit's
      implementation section would otherwise stamp every C symbol private and
      make `Twice(21)` undefined in the unit that pulled it. Measured: 3 corpus
      sources, test_c_unit_pulled_via_pascal_unit among them. }
    savedUnitImplCU := InUnitImpl;
    InUnitImpl := False;
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
    InUnitImpl := savedUnitImplCU;

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
    { CurrentUnitIdx now names the unit being set up, so the ambient pulls and
      root-method rows below must not inherit the ENCLOSING unit's
      implementation-section flag. ParseUnit sets its own; restored beside
      CurrentUnitIdx at the bottom. }
    savedUnitImplCU := InUnitImpl;
    InUnitImpl := False;
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

    { …and the per-library MANIFEST goes on top of that snapshot: the nearest
      pxxlib.cfg at or above this unit's own directory supplies its defines,
      undefs and dialect mode (defs.inc has the design note). It needs no
      restore of its own — the save above and the mode saves further up already
      cover everything it can touch, which is the whole reason it is applied
      HERE and not at the search-path tier.

      Scoped to the unit's own directory rather than the caller's, so a library
      unit and our own code each compile under their own profile and sibling
      libraries never see each other's defines. That is also what makes the
      PasApplyMimicDefines landmine ("NEVER call during a self-build") structural
      rather than remembered: a manifest under a library tree cannot reach
      compiler/**. feature-dynamic-include-paths-config }
    PxxLibApply(GetFilePath(path));

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
    unitNeedsRootMeth := False;
    unitNeedsMath := False;
    unitNeedsThreads := False;
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
           CaseEqual(GetTokenStr(i), 'ioresult') or
           { `file of T` / untyped `file` — FileRec lives in the same unit }
           CaseEqual(GetTokenStr(i), 'file') then
          unitNeedsText := True;
      { ...and the TObject ROOT METHODS, for exactly the reason above. `o.Equals(x)`
        / `.GetHashCode` / `.ToString` resolve through rows EnsureTObjectRootMethods
        mints only when the `builtin` unit's default bodies are visible, and the
        program-level pre-scan that pulls that unit sees only the PROGRAM's tokens.
        So the same call compiled in a program and failed with `"Equals": no such
        member on this record/class` in a UNIT — rtl-generics' Generics.Defaults
        hits it at TEquals.&Class, and any unit with a `constref L: TObject` helper
        does. Dot-preceded, exactly as the program-level trigger is, so a class that
        merely DECLARES a ToString does not drag 42 KB in. }
      if (Tokens[i].Kind = tkIdent) and (i > startPos) and (Tokens[i - 1].Kind = tkDot) and
         (RootVMTSlotCount > 0) and
         (CaseEqual(GetTokenStr(i), 'equals') or CaseEqual(GetTokenStr(i), 'gethashcode')
          or CaseEqual(GetTokenStr(i), 'tostring')) and
         { ...but a QUALIFIED IMPLEMENTATION HEADER is dot-preceded too, and it is
           a definition, not a call: `function TJSONValue.ToString(...)` in
           lib/rtl/json.pas fired this and pulled `builtin` + the root-method rows
           into every NilPy program that imports json — which then SEGFAULTED on a
           second parse (test_nilpy_json_reparse_heap) and dropped a line from
           test_nilpy_json_module. Walk back past `<TypeName> .` and refuse the
           four routine keywords, `class`/`static` prefix included.
           regression-test-core-test-nilpy-json-module }
         (not ((i >= startPos + 3) and (Tokens[i - 2].Kind = tkIdent) and
               ((Tokens[i - 3].Kind = tkFunction) or (Tokens[i - 3].Kind = tkProcedure)))) then
        unitNeedsRootMeth := True;
      { …and the elementary MATH functions, and the low-level THREAD API, for
        exactly the same reason: FPC declares both in the System unit, so a
        portable unit calls sqrt/ln/BeginThread with no `uses` line at all,
        while pxx keeps them in `math` / `palthreadobj`. The program-level
        pre-scan (ParseProgram) sees only the PROGRAM's tokens, so `sqrt(x)`
        compiled fine in a program and was `undefined variable (sqrt)` in a
        unit — which is where FPC's own cutils.pas stops.
        bug-p-the-system-math-and-thread-surfaces-are-not-ambient-in-units.
        Same triggers as the program-level scan, comments and all: a following
        '(' for the functions (so `var ln: Integer` does not drag 35KB in),
        bare for the paramless `pi`. A self-pull is harmless — this unit is
        already in CompiledUnits by now, so `math` scanning its own sqrt calls
        no-ops rather than recursing. }
      if (Tokens[i].Kind = tkIdent) and
         (Tokens[i].SLen >= 2) and (Tokens[i].SLen <= 6) then
      begin
        unitTnm := GetTokenStr(i);
        if (CaseEqual(unitTnm, 'sqrt') or CaseEqual(unitTnm, 'exp') or
            CaseEqual(unitTnm, 'ln') or CaseEqual(unitTnm, 'sin') or
            CaseEqual(unitTnm, 'cos') or CaseEqual(unitTnm, 'arctan')) and
           (i + 1 < TokCount) and (Tokens[i + 1].Kind = tkLParen) then
          unitNeedsMath := True;
        if CaseEqual(unitTnm, 'pi') then unitNeedsMath := True;
      end;
      if ThreadSafeMode and (Tokens[i].Kind = tkIdent) and
         (Tokens[i].SLen >= 9) and (Tokens[i].SLen <= 22) then
      begin
        unitTnm := GetTokenStr(i);
        if (CaseEqual(unitTnm, 'BeginThread') or CaseEqual(unitTnm, 'EndThread') or
            CaseEqual(unitTnm, 'WaitForThreadTerminate') or
            CaseEqual(unitTnm, 'CloseThread')) and
           (i + 1 < TokCount) and (Tokens[i + 1].Kind = tkLParen) then
          unitNeedsThreads := True;
        if CaseEqual(unitTnm, 'TThreadID') or CaseEqual(unitTnm, 'TThreadFunc') then
          unitNeedsThreads := True;
      end;
      Inc(i);
    end;

    { The rows can only be minted once `builtin` is in — and, unlike the program
      path (which mints them at the end of pass 1), a unit's bodies parse right
      after this, so it happens here. Idempotent. }
    if unitNeedsRootMeth and (not NoDefaultRtl) and (not TargetIsEspClass) then
    begin
      ParseUsesUnitAmbient('builtin');
      EnsureTObjectRootMethodsEx(False);   { NOT Destroy — see the note on that routine }
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

    { Same gating and same idempotence as the textfile pull above. }
    if unitNeedsMath and (not NoDefaultRtl) and (not TargetIsEspClass) then
      ParseUsesUnitAmbient('math');
    if unitNeedsThreads and (not NoDefaultRtl) and (not TargetIsEspClass) then
      ParseUsesUnitAmbient('palthreadobj');

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
    InUnitImpl := savedUnitImplCU;
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
    inPath, inLo: AnsiString;
begin
  uname := ReadDottedUsesName;
  if CurTok.Kind = tkIn then
  begin
    { `uses mymod in 'mymod.pas';` -- the Delphi/FPC spelling for naming a
      unit's source file, and the one every real .dpr uses. It is a
      WITHIN-LANGUAGE file selector: it says where a Pascal unit lives, not
      what language it is, so it is not an alternative to the quoted-path form
      and does not carry that form's cross-language reach.

      The two spellings differ in what they BIND, which is the whole reason
      this is not just the alias machinery with a different keyword:

        uses mymod in 'mymod.pas'   binds `mymod`, the unit's own declared name
        uses './mymod.pas' as m     binds `m`, an alias

      So the file is loaded through the ordinary path form (that is the half
      that already works), and then the DECLARED name is wired to it. When the
      file's basename already equals the declared name -- the overwhelmingly
      common case, and the only one FPC projects generate -- the two names
      intern to the same slot and the alias row below is skipped as a no-op.
      When they differ, both names resolve. Binding the basename as well is
      more permissive than FPC, which is not a defect (CLAUDE.md: us accepting
      what FPC rejects is not a defect) and is what falls out of reusing one
      loader instead of growing a second.
      feature-p-uses-a-unit-in-an-explicit-file }
    Next;                          { consume `in` }
    if CurTok.Kind <> tkString then
      Error('expected a quoted file name after `in` in a uses clause, as in '
            + '`uses ' + uname + ' in ''' + LowerCase(uname) + '.pas'';`');
    inPath := CurTok.SVal;
    Next;                          { consume the file name }
    { A BARE FILE NAME IS THE WHOLE POINT, and it is what every generated .dpr
      writes: `uses Unit1 in 'Unit1.pas'`. FPC resolves it against the
      directory of the file holding the clause, and `./` means exactly that
      here -- the loader's relative paths are taken against CurUnitDir, which
      is SourceFileDir for the program and the unit's own directory for a
      nested one. Without the prefix the loader treats the string as a UNIT
      NAME with a dot in it and reports `unit source not found: mymod.pas`,
      which was the ticket's measured symptom one step further in.

      Only when there is no separator at all: an author who wrote `in
      'sub/other.pas'` already has a path, and prefixing it would be wrong for
      an absolute one. A BACKSLASH is deliberately NOT treated as a separator
      -- Delphi sources write `in '..\shared\Foo.pas'` and pxx's existing
      quoted-path form does not accept that either, so it is one question about
      Windows path spelling across both spellings rather than something to
      answer twice, differently, here. }
    isPath := False;
    for i := 1 to Length(inPath) do if inPath[i] = '/' then isPath := True;
    if not isPath then inPath := './' + inPath;
    ParseUsesUnit(inPath);
    { Wire the declared name to whatever the loader registered the file as.
      Same normalisation ParseUsesEntry's `as` arm uses, and for the same
      reason: a path-form load tags its symbols with the file's BASENAME. }
    inLo := LowerCase(GetFileBaseName(inPath));
    aStrIdx := InternStr(LowerCase(uname));
    realStrIdx := InternStr(inLo);
    if (UnitAliasCount < MAX_UNIT_ALIASES) and (aStrIdx <> realStrIdx) then
    begin
      UnitAliasName[UnitAliasCount] := aStrIdx;
      UnitAliasReal[UnitAliasCount] := realStrIdx;
      Inc(UnitAliasCount);
    end;
    Exit;                          { `in` and `as` do not combine }
  end;
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

{ `uses a, b, c;` -- one shape, three sites (program decl part, unit interface,
  unit implementation), which is why it is a procedure: the Delphi-generics
  desugar below has to run at the END of every one of them, and a fourth copy is
  how the third site would have been the one that stayed broken. }
procedure ParseUsesClause;
var doneUses, savedPreScan: Boolean;
begin
  Next;   { consume `uses` }
  doneUses := False;
  while (CurTok.Kind in [tkIdent, tkString]) and not doneUses do
  begin
    ParseUsesEntry;
    if not Eat(tkComma) then doneUses := True;
  end;
  Eat(tkSemicolon);
  { Every template the clause just imported is registered now, and every use of
    one lies ahead of this point. See DesugarImportedDelphiGenericUses. }
  DesugarImportedDelphiGenericUses;
  { The generic-ROUTINE half of the same problem, at the same point and for the
    same reason -- a `specialize F<C>(...)` on a routine the clause just
    imported. Two mechanisms because the two are specialized differently (a
    class desugars to an alias declaration, a routine to an emitted body), but
    they answer one question -- "what did this clause just make visible" -- so
    they belong at one site rather than at two the next change can desynchronise.

  PreScanPass is cleared across it because this one EMITS: the sweep splices
    the specialized routine and calls ParseSubroutine, which under a pre-scan
    would register the signature and skip the body. Same save/clear/restore the
    program decl loop already does around ParseGenericFunctionDef. }
  savedPreScan := PreScanPass;
  PreScanPass := False;
  SpecializeImportedGenericFuncUses;
  { And the generic METHOD half, third at the same site for the same reason. It
    only RENAMES -- the members were emitted when the unit's class body was
    parsed -- so it needs no PreScanPass dance, but it must run inside the
    cleared window anyway: the routine sweep above can splice a body whose own
    tokens contain a method use. }
  SpecializeImportedGenericMethodUses;
  PreScanPass := savedPreScan;
end;

{ Compile a unit's `initialization` section into a synthesized parameterless
  proc and register it in InitProcs[]. The dialect has no real init execution,
  so ParseUnit used to drop these tokens; this emits a normal proc body that the
  program entry calls (in dependency order) before `main begin`. Precondition:
  the `initialization` keyword has been consumed; statements run until `end` or
  `finalization`. Leaves the parser positioned at that terminator. }
procedure ParseInitializationSection(const uname: AnsiString; isFini: Boolean);
var
  procIdx, savedSC, savedFS, savedGLC, savedGFC, savedGLB, j, patchPos: Integer;
  seqNode, lastSeq, stmtNode: Integer;
  dummyNames: array[0..0] of AnsiString;
  dummyTypes: array[0..0] of TTypeKind;
begin
  if isFini then
    procIdx := RegisterProc('__fini_' + uname, False, tyInteger, 0, dummyNames, dummyTypes)
  else
    procIdx := RegisterProc('__init_' + uname, False, tyInteger, 0, dummyNames, dummyTypes);
  SetProcBodyAddrHere(procIdx);

  savedSC := SymCount; savedFS := FrameSize;
  LocalInitCount := 0;   { routine-local typed-const initializers, flushed in the prologue }
  savedGLC := GotoLabelCount; savedGFC := GotoFixupCount;
  savedGLB := GotoLabelBase;
  GotoLabelBase := GotoLabelCount;   { see the other body parser above }
  GotoFixupCount := 0;
  for j := GotoLabelBase to MAX_GOTO_LABELS - 1 do GotoLabelIRId[j] := -1;
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
      tkConst: ParseConstSection(-1, 0, False);
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
  GotoLabelBase := savedGLB;
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

  SetProcBodyAddrHere(procIdx);
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

procedure SkipDeclHeaderToSemicolon;
{ Consume one bodiless declaration HEADER -- everything from the current token
  through the `;` that ends it, plus any trailing directives. Interface sections
  only: the implementation forms have bodies and go to their own parsers.

  Two callers, and they were one routine's worth of logic from the start:
    `operator <op> (params): T;`     -- ParseOperatorDef handles the impl form
    `generic function F<T>(p): T;`   -- ParseGenericFunctionDef handles the impl form
  Paren depth is tracked because a multi-argument header spells its arguments
  `(a: Double; b: TCx)`, with a semicolon INSIDE the parens that does not end
  the declaration.

  Named for what it does rather than for its first caller: the operator-only
  name is what made a second caller look like it needed a second routine.
  bug-p-a-generic-function-cannot-be-declared-in-a-unit }
var depth: Integer;
begin
  Next;   { the keyword that opened the declaration }
  depth := 0;
  while CurTok.Kind <> tkEOF do
  begin
    if CurTok.Kind = tkLParen then Inc(depth)
    else if CurTok.Kind = tkRParen then Dec(depth)
    else if (CurTok.Kind = tkSemicolon) and (depth <= 0) then
    begin
      Next;
      Break;
    end;
    Next;
  end;
  { `; inline;` / `; overload;` and the hint directives may follow the header }
  while (CurTok.Kind = tkOverload) or
        ((CurTok.Kind = tkIdent) and
         (CaseEqual(CurTok.SVal, 'inline') or CaseEqual(CurTok.SVal, 'deprecated') or
          CaseEqual(CurTok.SVal, 'platform') or CaseEqual(CurTok.SVal, 'experimental'))) do
  begin
    Next;
    if CurTok.Kind = tkString then Next;   { deprecated 'message' }
    Eat(tkSemicolon);
  end;
end;

procedure UnitSectionStrayToken(const sect: AnsiString);
{ A token that starts no declaration, at the top level of a unit's interface or
  implementation section.

  This used to be `Next` -- skip it and carry on. A PROGRAM's declaration
  section rejected the same token, so the two paths through one concept disagreed
  and the unit one lost. The damage is not the missing diagnostic: a MISTYPED
  SECTION HEADER (`cosnt K = 5;`) had the whole declaration thrown away, and the
  only complaint was `undefined variable (K)` at the use site, in another file.
  Had nothing used K, the unit compiled clean with a declaration missing --
  which quietly voids every "it compiled" signal the corpus ladder rests on.

  Measured before turning this on: across test/ and lib/rtl the skip path fired
  1949 times and every event was a piece of an operator DECLARATION header, now
  consumed as a unit by SkipDeclHeaderToSemicolon. Nothing else relied on it, and
  the implementation section's copy of this never fired at all.
  bug-p-stray-tokens-in-a-unit-declaration-section-are-silently-skipped }
begin
  Error('unexpected token in a unit ' + sect
        + ' section: it starts no declaration (a mistyped section header?)');
end;

procedure ParseUnit;
var
  uname: AnsiString;
  savedInterface, savedUnitImpl, doneImp, savedPreScan, savedPass2Active: Boolean;
  savedBase, afterImpTok, ii, savedPass2BodyTok: Integer;
  savedPendPtr: Integer;   { this unit's mark in the deferred `^T` list }
begin
  savedPendPtr := PendPtrCount;
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
  savedUnitImpl := InUnitImpl;
  InInterface := True;
  { An enclosing unit may be mid-implementation when its `uses` recursed in
    here; this unit's INTERFACE is not private to it. Restored below with
    InInterface. }
  InUnitImpl := False;

  while (CurTok.Kind <> tkEOF) and not ((CurTok.Kind = tkIdent) and ((CurTok.SVal = 'implementation') or (CurTok.SVal = 'Implementation'))) do
  begin
    case CurTok.Kind of
      tkUses:     ParseUsesClause;
      tkVar:      ParseVarSection;
      tkConst:    ParseConstSection(-1, 0, False);
      tkType:     ParseTypeSection;
      tkClass,
      tkProcedure,
      tkFunction:
        if IsGenericRoutineHeaderAhead then
          { `function Add<T>(...);` in the INTERFACE -- the mode-Delphi spelling
            of the `generic` arm below, and a header with no body for the same
            reason. Consumed as a unit; the template is registered from the
            implementation side.
            feature-p-generic-routines-in-a-class-body-and-in-delphi-spelling }
          SkipDeclHeaderToSemicolon
        else
          ParseSubroutine;
      tkIdent:
        { `resourcestring` sections (FPC rtlconsts et al) register as plain
          string constants — pxx has no resource tables; the format-arg
          machinery lives in whoever consumes the string. }
        if CaseEqual(CurTok.SVal, 'resourcestring') then ParseConstSection(-1, 0, True)
        else if CaseEqual(CurTok.SVal, 'operator') then
          { An operator DECLARATION in the interface: a header with no body. pxx
            keys an operator on its operand types and registers it from the
            IMPLEMENTATION section's definition, so the header carries nothing
            this side needs -- consume it as a unit and move on.

            Consuming it as a UNIT is the point. Until now it fell to the `else
            Next` below and was chewed one token at a time; measured across
            test/ and lib/rtl, that path fired 1949 times and every single event
            was a piece of an operator header (`+`, `(`, `a`, `:`, `TBigInt`,
            `;` ...). It looked harmless only because the implementation-side
            definition registered the real thing, and it is the whole reason the
            stray-token error below could not be turned on before. }
          SkipDeclHeaderToSemicolon
        else if CaseEqual(CurTok.SVal, 'generic') then
          { `generic function F<T>(a: T): T;` in the INTERFACE: a header with no
            body, exactly like the operator declaration above. The template is
            registered from the IMPLEMENTATION section's definition (which is
            parsed before any importer's body), so the header carries nothing
            this side needs -- consume it as a unit.

            Without this arm the header fell to UnitSectionStrayToken and the
            unit would not compile at all, while FPC 3.2.2 accepts it and runs.
            bug-p-a-generic-function-cannot-be-declared-in-a-unit }
          SkipDeclHeaderToSemicolon
        else
          UnitSectionStrayToken('interface')
      else
        UnitSectionStrayToken('interface');
    end;
  end;

  if CurTok.Kind = tkEOF then Error('expected implementation section');
  Next; { Skip 'implementation' }

  InInterface := False;
  { Everything registered from here to the unit's `end.` -- both the pre-scan
    below and the pass-2 body replay -- is private to this unit
    (bug-p-a-units-implementation-section-is-visible-to-its-importers). }
  InUnitImpl := True;

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
      { `end.` terminates the unit. Any OTHER top-level `end` in an
        implementation section is a routine body that closed one `end` too few
        -- the section has no other legitimate `end` -- and until 2026-09-04 a
        bare `Next` swallowed it, absorbing the evidence.

        THE CLASS WAS ASYMMETRIC, WHICH IS WHY ONLY HALF OF IT WAS EVER SEEN.
        One `end` too MANY lands the loop on the bare `.` and
        UnitSectionStrayToken errors -- but AT EOF, so the position is the
        file's last line rather than the defect's (measured on
        generics.collections.pas across three truncations: 4165 lines -> error
        at 4165, 4161 -> 4161, 2489 -> 2489). One too FEW produced no
        diagnostic at all and the unit compiled.

        Turned into an error only after the census its sibling
        (bug-p-stray-tokens-in-a-unit-declaration-section-are-silently-skipped)
        proved necessary: that arm's skip fired 1949 times across test/ and
        lib/rtl, every event a piece of an `operator` header, so erroring first
        would have stopped every operator-declaring RTL unit from compiling.
        This arm fires ZERO times across 2571 corpus sources under
        PXXDBG=p.strayend -- and the probe is proven live, not merely quiet: a
        unit with a spare top-level `end` reports one event, and compiled clean
        with no diagnostic before this.
        bug-p-a-stray-end-at-unit-implementation-top-level-is-silently-skipped }
      if (TokPos < TokCount) and (Tokens[TokPos].Kind = tkDot) then
        doneImp := True
      else
        Error('unexpected `end` at the top level of unit ' + uname
              + '''s implementation section: a routine body above it is short '
              + 'one `end`, and only `end.` ends the unit');
    end
    else
    begin
      case CurTok.Kind of
        tkUses:     ParseUsesClause;
        tkVar:      ParseVarSection;
        tkConst:    ParseConstSection(-1, 0, False);
        tkType:     ParseTypeSection;
        tkClass,
        tkProcedure,
        tkFunction:
        if IsGenericRoutineHeaderAhead then
          { The mode-Delphi generic-routine DEFINITION, in a unit's
            implementation -- same arm as `generic` below, reached without a
            keyword. feature-p-generic-routines-in-a-class-body-and-in-delphi-spelling }
          begin PreScanPass := False; ParseGenericFunctionDef; PreScanPass := True; end
        else
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
          else if CaseEqual(CurTok.SVal, 'generic') then
          begin
            { `generic function F<T>(a: T): T; begin ... end;` -- the DEFINITION.
              Like an operator def it buffers its own tokens and specializes
              them in place, so it is parsed in full during the pre-scan rather
              than body-deferred.

              This is the third copy of the top-level declaration dispatcher
              (program decls, unit interface, unit implementation) and the arms
              had drifted: `generic` was handled at PROGRAM level only, so the
              identical declaration compiled in a program and was rejected in a
              unit. FPC 3.2.2 accepts both.
              bug-p-a-generic-function-cannot-be-declared-in-a-unit }
            PreScanPass := False;
            ParseGenericFunctionDef;
            PreScanPass := True;
          end
          else if CaseEqual(CurTok.SVal, 'resourcestring') then
            ParseConstSection(-1, 0, True)    { real storage: see the section parser }
          else
            UnitSectionStrayToken('implementation')
        else
          UnitSectionStrayToken('implementation');
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
  InUnitImpl := savedUnitImpl;
  PreScanPass := savedPreScan;

  { Every `^T` this unit parked and nobody supplied. HERE, not at the program's
    end: a type declared in a unit reached only transitively is not visible from
    the program's scope, so the once-at-the-end version refused palsync's
    ordinary `PMutex = ^TMutex;` the moment it was reached through syncobjs
    rather than directly (393fe0184, reverted d11b8a1a9). Down to the mark taken
    on entry, so nested `uses` -- this procedure recurses -- each answer for
    their own rows in their own scope. }
  DrainPendingPtrTargets(savedPendPtr);

  Expect(tkEnd, 'end');
  Expect(tkDot, '.');
end;
