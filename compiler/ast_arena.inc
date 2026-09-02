{ ===== ast_arena.inc — the AST arena: capacity, allocation, cloning ==========

  Carved out of parser.inc, byte-for-byte, by
  refactor-a-carve-out-plexer-pparser-so-p-owns-its-own-files.

  **Owned by Track A** (language-agnostic core), not by a frontend. The AST is
  the substrate every frontend shares — Pascal, C, NilPy, Rust, Zig all build
  nodes through AllocNode — so this is as core as it gets; it sat in the Pascal
  parser's file only because Pascal was the seed
  (devdocs/dev/ir-as-substrate.md).

  Included from compiler.pas at exactly the point it used to occupy, so include
  ORDER is unchanged — that is what makes the carve-out provable by the
  self-host fixedpoint rather than by reading it. }

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
  SetLength(ASTNilChk, n);
  SetLength(ASTPyUser, n);
  SetLength(ASTStrElemTk, n);
  SetLength(ASTNDRowSubs, n);
  ASTCapacity := n;
end;

function IsNilLiteralNode(node: Integer): Boolean;
{ Is this AST node the literal `nil`?

  ONE predicate, because the question is asked from two directions that had
  already answered it differently: the assignment path (ir.inc's AN_ASSIGN /
  tyRecord arm, which zeroes a method pointer) and the overload matcher
  (symtab.inc, deciding whether `nil` may bind a class / interface /
  method-pointer parameter). The parser types `nil` as an INT_LIT 0 tagged
  tyPointer -- three facts, none of them obvious, and a third open-coded copy
  is how the two arms drift. normalise-dont-special-case.md. }
begin
  Result := (node >= 0) and (node < ASTNodeCount) and
            (ASTKind[node] = AN_INT_LIT) and (ASTIVal[node] = 0) and
            (IntToTypeKind(ASTTk[node]) = tyPointer);
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
  { 0 = tyUnknown = "narrow", the correct default for every existing string
    expression; only a wide-string PRODUCER overwrites it. feature-unicodestring-model }
  ASTStrElemTk[ASTNodeCount] := 0;
  { 0 = "an element, not a sub-array" -- correct for every node but the
    partial N-D index, which BuildPartialNDRowIndex stamps. }
  ASTNDRowSubs[ASTNodeCount] := 0;
  { Stamped on EVERY node, not on a chosen few: the sites that read it are call
    nodes and deref nodes, and tagging both lists here would be the second place
    to keep in step with ir.inc. It is one byte. feature-a-emitted-nil-checks }
  ASTNilChk[ASTNodeCount]  := Byte(StmtNChecks);
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
  ASTNilChk[Result]   := ASTNilChk[node];
  ASTPyUser[Result]   := ASTPyUser[node];
  ASTStrElemTk[Result] := ASTStrElemTk[node];
  ASTNDRowSubs[Result] := ASTNDRowSubs[node];
  ASTLeft[Result]     := CloneAST(ASTLeft[node]);
  ASTRight[Result]    := CloneAST(ASTRight[node]);
end;

{ ---- The dead-arm prune's escape guard -----------------------------------

  "Does this subtree contain a LABEL?" -- the one question that decides whether
  an unreachable `if` arm may be dropped.

  Reachability alone is NOT sufficient and this is the case that proves it:

      void f(void){ void *p = &&inside; if (0) { inside: N(); } goto *p; }

  gcc, clang and tcc all KEEP `N` here, at every level, because the label's
  address escaped and the arm is reachable through `goto *p`. pxx has both
  halves -- AN_LABELADDR is `&&label` and AN_GOTO_INDIRECT is `goto *expr` --
  so pruning on reachability would silently break computed-goto code.

  DELIBERATELY MORE CONSERVATIVE THAN "the address was taken": ANY label in the
  arm keeps it. Two reasons. A plain `goto` from outside into the arm is the
  same hazard wearing a different spelling, and Pascal has `goto` and no
  labels-as-values, so an address-taken test would answer "safe to prune" for
  the only shape Pascal can hurt itself with. And the cheap answer is the safe
  one: over-keeping costs bytes in dead code, under-keeping miscompiles.

  AN_CASE AND AN_DEFAULT ARE LABELS TOO, and leaving them out is what
  c-testsuite 00213.c caught -- on all five conformance targets at once, with
  `invalid IR conditional jump target (label not defined)`:

      switch (i) { if (0) { case 41: printf("caseok\n"); } }

  The `case` sits inside a constant-false `if`, so the arm went; but AN_SWITCH
  lowers to a DISPATCH that jumps to each case's label, and that dispatch is
  outside the arm. The jump survived its target. gcc prints `caseok`, and
  00213.c exists precisely to test "dead code inside if statements where there
  are non-obvious ways of how the code is actually not dead due to reachable by
  labels" -- its own header comment.

  It is the same hazard as the `goto` above wearing a third spelling, which is
  the tell: `goto`, `&&label` and `case` are three ways to name an entry point,
  and a guard that enumerates spellings will keep missing the next one. The
  boundary measured 2026-09-02: `if (1)`, a bare `{ }` block and a top-level
  `case` are all fine; `if (0)` and `while (0)` are not. So the discriminator
  was never the nesting, it was the pruning -- which means every future entry
  point kind has to be added HERE, and the header of AN_SWITCH in defs.inc says
  where the dispatch that needs them lives.

  SECOND SIGHTING, same omission, different pass and found independently the
  same day: the unreachable-tail prune (ASTSeqTailUnreachable, below) reaches
  this guard through the AN_BLOCK walk, and a C `case` arm ending in `return`
  made it drop every arm behind that one. The compiler then rejected its OWN
  crtl -- `invalid IR conditional jump target`, lib/crtl/src/stdio.c near
  vsnprintf -- and a five-line `switch (x) { case 1: return 10; ... }` besides.
  Two passes, two routes, one missing enumeration: it is the strongest evidence
  for the paragraph above that a guard listing SPELLINGS keeps coming up short.

  AN_ASM IS DELIBERATELY ABSENT, and this note exists because the paragraph
  above tells you to add every future entry-point kind HERE -- so the next
  reader will reach for asm and should not. An asm block is not an entry point:
  pxx resolves asm labels WITHIN one asm statement, so a jump out of a block is
  not expressible and pruning a whole block behind a terminator cannot orphan
  anything. Measured 2026-09-02: `asm jmp fwd7 end; Exit; asm fwd7: end` is
  refused at compile time with `asm: undefined label "fwd7"`, and an asm block
  alone behind an Exit prunes with the program still correct. Adding AN_ASM
  would not harden the guard -- it would answer TRUE for a node that is not an
  entry point and suppress a prune that is correct today (frankb-a9's argument,
  and it is the right one: conservative in the useless direction is just wrong
  in the cheap direction).

  WHAT WOULD CHANGE IT is `asm goto`, which by definition names C labels the
  template can jump to, and asm labels made visible across statements. Neither
  exists today; the C frontend refuses a non-empty template outright. If either
  lands, AN_ASM belongs in the list below and the tell is the usual one --
  `invalid IR jump target (label not defined)`, loud, not a miscompile. Carried
  in [[feature-c-gnu-inline-asm-with-a-non-empty-template]] rather than only here.

  THE BUDGET IS PART OF THE GUARD, not a performance tweak. A statement list
  chains through ASTRight, so a thousand-statement arm is a thousand-deep walk;
  exhausting the budget answers TRUE -- keep the arm -- because a guard that
  runs out of room must fail toward emitting code, never toward deleting it. }
function ASTSubtreeHasLabel(node: Integer; var budget: Integer): Boolean;
begin
  ASTSubtreeHasLabel := False;
  if node < 0 then Exit;
  if budget <= 0 then begin ASTSubtreeHasLabel := True; Exit; end;
  Dec(budget);
  if (ASTKind[node] = AN_LABEL) or (ASTKind[node] = AN_LABELADDR) or
     (ASTKind[node] = AN_GOTO_INDIRECT) or
     (ASTKind[node] = AN_CASE) or (ASTKind[node] = AN_DEFAULT) then
  begin
    ASTSubtreeHasLabel := True;
    Exit;
  end;
  if ASTSubtreeHasLabel(ASTLeft[node], budget) then
  begin ASTSubtreeHasLabel := True; Exit; end;
  if ASTSubtreeHasLabel(ASTRight[node], budget) then
    ASTSubtreeHasLabel := True;
end;

{ Does this statement unconditionally transfer control AWAY, so that whatever
  follows it in the same sequence cannot be reached by falling through?

  gcc, clang and tcc all drop the statements after one, at -O0 and with no
  optimiser asked for, which is what makes this LOWERING rather than an
  optimisation -- the same argument the constant-condition arm prune rests on
  (decide-should-unreachable-code-that-breaks-the-LOAD-be-pruned-at-O0).

  BREAK and CONTINUE are in the list on purpose: they leave the enclosing LOOP,
  so the rest of THIS sequence is as unreachable as it is after an Exit. What is
  deliberately NOT here is a call to a routine that never returns -- that is a
  property of the callee, not of this node, and guessing it wrong deletes live
  code. AN_IF is not here either, even when both its arms terminate: that is a
  real shape, and it needs its own reasoning rather than being smuggled in. }
function ASTIsTerminatorStmt(node: Integer): Boolean;
begin
  ASTIsTerminatorStmt := False;
  if node < 0 then Exit;
  if SourceOneToOne then Exit;
  ASTIsTerminatorStmt :=
    (ASTKind[node] = AN_HALT) or (ASTKind[node] = AN_EXIT) or
    (ASTKind[node] = AN_BREAK) or (ASTKind[node] = AN_CONTINUE) or
    (ASTKind[node] = AN_RAISE) or (ASTKind[node] = AN_GOTO) or
    (ASTKind[node] = AN_GOTO_INDIRECT);
end;

{ Given a node in an AN_SEQ chain, is everything BEHIND it unreachable?

  ONE function because there are TWO chain walks in ir.inc -- the AN_SEQ spine
  and the AN_BLOCK loop, which walks the same cons chain itself instead of
  handing the seq node to IRLowerAST. The first version of this prune lived
  only in the spine, and that is exactly the second path normalise-dont-special-case
  describes: MEASURED, a C function body is an AN_BLOCK, so `return; g=2;` kept
  emitting the store at -O0 (400 unreachable stores: -O0 and -OO both 425752B,
  while the Pascal shape was 89880B against -OO's 93976B) while the Pascal half
  of the very same change was already pruning. Duplicating the walks is
  tolerable -- they build different things -- but the DECISION must have one
  home, or the next walk added inherits the bug rather than the fix.

  The label guard is the whole risk and it lives here for the same reason: a
  `goto` may land anywhere behind the terminator, so ONE label in the remainder
  keeps ALL of it. Conservative on purpose -- splitting the chain at the label
  is a bigger claim than this pass makes. Budget exhaustion answers KEEP, since
  a guard that runs out of room must fail toward emitting code. }
function ASTSeqTailUnreachable(seqNode: Integer): Boolean;
var budget: Integer;
begin
  ASTSeqTailUnreachable := False;
  if seqNode < 0 then Exit;
  { AN_SEQ ONLY, never AN_PAIR, even though the spine walk in ir.inc accepts
    both kinds. AN_PAIR is a generic two-slot node and one of its uses is
    AN_IF's (then-arm, else-arm) -- on which "everything after Left is
    unreachable" would delete the ELSE ARM.

    No such pair reaches here today and that was measured, not assumed: `if c
    then Exit else n := 42` and a function whose two arms both Exit are correct
    at -O0 and -O2 and match FPC, because AN_IF lowers its own pair and never
    hands it to the spine. This line is a guard against that walk changing, and
    it is cheap in exactly the direction that matters -- being wrong without it
    silently deletes a branch, being conservative with it costs a few unpruned
    bytes in a shape that does not occur. }
  if ASTKind[seqNode] <> AN_SEQ then Exit;
  if not ASTIsTerminatorStmt(ASTLeft[seqNode]) then Exit;
  budget := 20000;
  ASTSeqTailUnreachable := not ASTSubtreeHasLabel(ASTRight[seqNode], budget);
end;

{ Is this `if` condition a COMPILE-TIME constant, and which way does it go?

  Literal-only, matching the folds in the parsers and the ruling: a `const z = 0`
  is not consulted, because gcc and tcc keep propagation-through-a-variable and
  clang prunes it, so nothing portable relies on either answer. By the time
  lowering sees the node, both frontends have already folded their short-circuit
  chains down to a literal, which is what makes this arm reachable at all. }
function ASTConstCond(node: Integer; var taken: Boolean): Boolean;
begin
  ASTConstCond := False;
  { -OO emits what the source says, so every fold in this file switches off
    HERE rather than at each call site: this helper is the single question they
    all ask, and a gate at the choke point cannot be forgotten by the next fold
    someone adds. }
  if SourceOneToOne then Exit;
  if node < 0 then Exit;
  if (ASTKind[node] <> AN_BOOL_LIT) and (ASTKind[node] <> AN_INT_LIT) then Exit;
  taken := ASTIVal[node] <> 0;
  ASTConstCond := True;
end;

{ ---- Dynamic-array SHAPE of an expression --------------------------------

  These four answer "is this expression a dynamic array, and of what" for any
  lvalue shape -- a bare name, a record/class field, an element of a nested
  array. They live HERE, next to the AST arrays they walk, rather than in
  ir.inc, because both sides need them: the PARSER has to decide whether
  Copy/Delete/Insert are looking at a dynamic array before it builds a node,
  and pasparser_*.inc is included long before ir.inc. That ordering is what
  produced CopySrcDynDepth, a hand-kept mirror of NodeDynDepth that answered
  0 for shapes the real one knew (bug-p-copy-rejects-a-dynamic-array-
  expression-that-is-not-a-bare-name was its second half). One walker, one
  answer -- devdocs/dev/normalise-dont-special-case.md.

  They depend only on symtab.inc (RecField*, ResolveNodeRec) and the AST
  arrays, both of which are in scope here. ---------------------------------}

function NodeDynDepth(node: Integer): Integer;
{ Dynamic-array nesting of an expression's value: 0 if not a dyn array, else the
  remaining `array of` levels. m (array of array of T) is 2; m[i] is 1; m[i][j]
  is 0 (a base value). }
var bd: Integer;
begin
  Result := 0;
  if node < 0 then Exit;
  case ASTKind[node] of
    AN_IDENT:
      if Syms[ASTIVal[node]].IsArray and (Syms[ASTIVal[node]].ArrLen = -1) then
        Result := SymDynDepth[ASTIVal[node]];
    AN_DEREF:
      { `p^` where p: ^TDyn. The pointee's nesting lives on the POINTER symbol
        (SymPtrElemDynDepth) because a dyn pointee has no extent to put in the
        fixed-array slot. Without this arm the deref was not a dyn-array value
        to anything downstream, so Length(p^) took the force-address path and
        read the DATA as a header: 0x900000000 -- the array's own elements 1 and
        0 packed into one 8-byte word -- where fpc says 5.
        bug-p-length-of-a-pointer-to-a-dynamic-array-answers-one }
      { Widened past the plain-identifier base in 2026-09-01: the same `^TDyn`
        held in a record FIELD, returned by a FUNCTION or read out of an array
        ELEMENT answered 0 here, and the deref stopped being a dyn-array value
        for exactly the reason above -- two SIGSEGVs and a HANG, one missing
        answer. DerefPtrArrayDynDepth still asks the pointer SYMBOL first, so
        the identifier spelling is byte-for-byte the path it was.
        bug-a-p-caret-index-is-only-correct-when-the-pointer-is-a-plain-identifier }
      Result := DerefPtrArrayDynDepth(node);
    AN_FIELD:
      Result := RecFieldDynDepth(ResolveNodeRec(ASTLeft[node]), GetASTIdentName(node));
    AN_CALL, AN_VIRTUAL_CALL, AN_INTF_CALL, AN_CALL_IND:
      { A dyn-array-returning CALL is a dyn-array VALUE, and the proc table has
        always said so (ProcRetIsDynArray + the element type). Only this reader
        was missing, so `SumI(MkI)` and `Copy(MkI)` saw a bare tyPointer where
        `SumI(dy)` and `Copy(dy)` saw an array -- five different outcomes for
        one shape, from "works" through "no overload matches: (Pointer)" to a
        segfault, depending on the element type.
        bug-p-a-call-result-is-refused-as-a-const-open-array-argument }
      if (Integer(ASTIVal[node]) >= 0) and (Integer(ASTIVal[node]) < ProcCount) and
         ProcRetIsDynArray[ASTIVal[node]] then
      begin
        Result := ProcRetDynDepth[ASTIVal[node]];
        if Result < 1 then Result := 1;
      end;
    AN_DYN_COPY, AN_DYN_INSERT:
      { `Copy(a)` / `Copy(a, i, n)` of a dyn array yields an array of the SAME
        shape -- its depth and element come straight from the source. So does
        the array-splice AN_DYN_INSERT, which is what `a + b` and
        `Concat(a, b)` build: same element, same nesting, more elements
        (feature-p-dynamic-array-concatenation). }
      Result := NodeDynDepth(ASTLeft[node]);
    AN_COMMA:
      { `(side-effect, value)` yields the RIGHT operand's value, so its shape is
        the right operand's -- the same rule ResolveNodeRec's comma arm states.
        This is the node the call-result materialisation builds, so without this
        arm every dyn-array CALL result stopped being a dyn array the moment it
        was lifted: `Length(MakeMat[1])` answered 0x600000007, the row's first
        two elements read as one 8-byte word, where the identical expression
        through a VARIABLE answered 2.
        bug-p-a-nested-dynamic-array-result-crashes-however-it-is-reached }
      Result := NodeDynDepth(ASTRight[node]);
    AN_INDEX:
      begin
        bd := NodeDynDepth(ASTLeft[node]);
        if bd > 0 then Result := bd - 1
        else if (ASTKind[ASTLeft[node]] = AN_IDENT) and
                (Syms[ASTIVal[ASTLeft[node]]].IsArray) and
                (Syms[ASTIVal[ASTLeft[node]]].ArrLen <> -1) and
                (SymElemDynDepth[ASTIVal[ASTLeft[node]]] > 0) then
          { Indexing a FIXED array whose element is a dynamic array
            (`array[..] of TA`): the element is a dyn array of this depth. }
          Result := SymElemDynDepth[ASTIVal[ASTLeft[node]]];
      end;
  end;
end;

function NodeDynBaseTk(node: Integer): TTypeKind;
{ Base element type of a (possibly nested) dynamic-array expression, walking to
  the root symbol or field. tyUnknown if not a dynamic array. }
var ndbtTk, ndbtRec, ndbtCap: Integer;
begin
  Result := tyUnknown;
  if node < 0 then Exit;
  if ASTKind[node] = AN_IDENT then
  begin
    if Syms[ASTIVal[node]].IsArray and (Syms[ASTIVal[node]].ArrLen = -1) then
      Result := Syms[ASTIVal[node]].ElemType
    else if Syms[ASTIVal[node]].IsArray and (Syms[ASTIVal[node]].ArrLen <> -1) and
            (SymElemDynDepth[ASTIVal[node]] > 0) then
      { fixed array of a dyn-array element: element base type lives in ElemType }
      Result := Syms[ASTIVal[node]].ElemType;
  end
  else if (ASTKind[node] = AN_CALL) or (ASTKind[node] = AN_VIRTUAL_CALL) or
          (ASTKind[node] = AN_INTF_CALL) or (ASTKind[node] = AN_CALL_IND) then
  begin
    if (Integer(ASTIVal[node]) >= 0) and (Integer(ASTIVal[node]) < ProcCount) and
       ProcRetIsDynArray[ASTIVal[node]] then
      Result := ProcRetElemTk[ASTIVal[node]];
  end
  else if (ASTKind[node] = AN_DEREF) and (DerefPtrArrayDynDepth(node) > 0) then
  begin
    { `p^` over ^TDyn: the pointee's element type. Read through the accessor
      rather than off Syms[..].PtrElemTk so the field / call / element
      spellings answer too — see NodeDynDepth's arm above. }
    if not DerefPtrArrayElem(node, ndbtTk, ndbtRec, ndbtCap) then
      ndbtTk := Ord(tyUnknown);
    Result := IntToTypeKind(ndbtTk);
  end
  else if ASTKind[node] = AN_FIELD then
    Result := RecFieldType(ResolveNodeRec(ASTLeft[node]), GetASTIdentName(node))
  else if (ASTKind[node] = AN_INDEX) or (ASTKind[node] = AN_DYN_COPY) or
          (ASTKind[node] = AN_DYN_INSERT) then
    Result := NodeDynBaseTk(ASTLeft[node])
  else if ASTKind[node] = AN_COMMA then
    { the comma's value is its RIGHT operand — see NodeDynDepth's arm }
    Result := NodeDynBaseTk(ASTRight[node]);
end;

function NodeDynBaseRec(node: Integer): Integer;
{ Base element record id of a (possibly nested) dynamic-array expression. }
var ndbrTk, ndbrRec, ndbrCap: Integer;
begin
  Result := REC_NONE;
  if node < 0 then Exit;
  if ASTKind[node] = AN_IDENT then
    Result := Syms[ASTIVal[node]].ElemRecName
  else if (ASTKind[node] = AN_CALL) or (ASTKind[node] = AN_VIRTUAL_CALL) or
          (ASTKind[node] = AN_INTF_CALL) or (ASTKind[node] = AN_CALL_IND) then
  begin
    if (Integer(ASTIVal[node]) >= 0) and (Integer(ASTIVal[node]) < ProcCount) and
       ProcRetIsDynArray[ASTIVal[node]] then
      Result := ProcRetElemRec[ASTIVal[node]];
  end
  else if (ASTKind[node] = AN_DEREF) and (DerefPtrArrayDynDepth(node) > 0) then
  begin
    { ...and its element RECORD, through the same accessor and for the same
      reason as NodeDynBaseTk's arm above. }
    if not DerefPtrArrayElem(node, ndbrTk, ndbrRec, ndbrCap) then
      ndbrRec := REC_NONE;
    Result := ndbrRec;
  end
  else if ASTKind[node] = AN_FIELD then
    Result := RecFieldRecId(ResolveNodeRec(ASTLeft[node]), GetASTIdentName(node))
  else if (ASTKind[node] = AN_INDEX) or (ASTKind[node] = AN_DYN_COPY) or
          (ASTKind[node] = AN_DYN_INSERT) then
    Result := NodeDynBaseRec(ASTLeft[node])
  else if ASTKind[node] = AN_COMMA then
    { the comma's value is its RIGHT operand — see NodeDynDepth's arm }
    Result := NodeDynBaseRec(ASTRight[node]);
end;

function NodeDynBaseSym(node: Integer): Integer;
{ Root dynamic-array symbol of a (possibly nested) index expression, or -1. }
begin
  Result := -1;
  if node < 0 then Exit;
  if ASTKind[node] = AN_IDENT then
  begin
    if Syms[ASTIVal[node]].IsArray and (Syms[ASTIVal[node]].ArrLen = -1) then
      Result := ASTIVal[node];
  end
  else if ASTKind[node] = AN_INDEX then
    Result := NodeDynBaseSym(ASTLeft[node])
  else if ASTKind[node] = AN_COMMA then
    Result := NodeDynBaseSym(ASTRight[node]);
end;

{ May a dynamic-array TARGET be read and then written back through the same
  expression? Delete/Insert build a fresh array from the old one and assign the
  result back, so the target expression is evaluated twice; anything with a
  side effect -- a call, or an index whose subscript is computed -- would run
  both times. A pure name / field / dereference path has none, and that is the
  shape real code uses (`obj.Items`, `p^.list`). Indexed targets (`m[i]`) are
  deliberately not here: they are re-readable only when the subscript is, and
  answering that needs a purity walk this does not have. }
function DynTargetIsRereadable(node: Integer): Boolean;
begin
  Result := False;
  if node < 0 then Exit;
  if ASTKind[node] = AN_IDENT then Result := True
  else if (ASTKind[node] = AN_FIELD) or (ASTKind[node] = AN_DEREF) then
    Result := DynTargetIsRereadable(ASTLeft[node]);
end;

function IsConstStrLitNode(n: Integer): Boolean;
{ A compile-time string-or-char literal (foldable in an ESP tyString concat). }
begin
  Result := (ASTKind[n] = AN_STR_LIT) or
            ((ASTKind[n] = AN_INT_LIT) and (IntToTypeKind(ASTTk[n]) = tyChar));
end;

function ConstStrLitValue(n: Integer): AnsiString;
{ The string value of a node accepted by IsConstStrLitNode. }
begin
  if ASTKind[n] = AN_STR_LIT then
    Result := GetTokenStrFromRaw(ASTSOffset[n], ASTSLen[n])
  else
  begin
    Result := '';
    AppendChar(Result, Chr(Integer(ASTIVal[n])));
  end;
end;

{ ===== case-statement label validation ===================================
  Checks every label against the selector's type (string vs ordinal), rejects
  inverted ranges (lo > hi) and any duplicate/overlapping label pair — FPC
  rejects all of these at compile time
  (bug-case-of-string-segfault-and-label-validation).

  Pure AST: no lowered type is read, only the caller's isStr answer. That is
  why it lives HERE and not in ir.inc, where it sat until
  bug-a-error-recovery-silences-every-lowering-only-diagnostic: these are
  Pascal DIALECT rules, and a rule reachable only through lowering stops
  firing the moment anything earlier in the file is recovered
  (`ErrCount > 0 -> Exit` at the top of CompileAST). The Pascal parser now
  calls this as soon as the branch list is built, with recover=True; the
  AN_CASE lowering keeps its own fatal call as the backstop for case nodes no
  Pascal parse produced. See devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md. }

procedure CaseLabelDiag(lab: Integer; const msg: AnsiString; recover: Boolean);
{ One label diagnostic, against the LABEL's own line — the caller may be the
  parser (position already past `end`) or the lowering (position meaningless). }
begin
  if recover then ErrorAtRecover(ASTLine[lab], msg)
  else ErrorAt(ASTLine[lab], msg);
end;

{ Lexicographic 3-way compare; orders string labels exactly the way the
  runtime comparison (EmitAnsiStrCmp3Reg et al.) orders them: byte-wise on
  the common prefix, then by length. }
function CaseStrCmp3(const a, b: AnsiString): Integer;
var i, n: Integer;
begin
  n := Length(a);
  if Length(b) < n then n := Length(b);
  i := 1;
  while i <= n do
  begin
    if a[i] <> b[i] then
    begin
      if Ord(a[i]) < Ord(b[i]) then Result := -1 else Result := 1;
      Exit;
    end;
    Inc(i);
  end;
  if Length(a) < Length(b) then Result := -1
  else if Length(a) > Length(b) then Result := 1
  else Result := 0;
end;

{ One label's [lo,hi] interval (hi = lo for a plain label), typed per the
  selector. Also the type check: a string selector needs string-constant
  labels (a char literal counts — its source span is preserved so the
  lowering can rebuild the literal); an ordinal selector rejects multi-char
  string labels. }
function CaseLabelBounds(lab: Integer; isStr, recover: Boolean;
                         var lo, hi: Int64; var slo, shi: AnsiString): Boolean;
{ False = this label was refused, so lo/hi/slo/shi hold nothing usable and the
  caller must skip it. Only reachable under recover=True; a fatal caller never
  returns from CaseLabelDiag. }
begin
  Result := False;
  if isStr then
  begin
    if (not IsConstStrLitNode(lab)) or
       ((ASTKind[lab] = AN_INT_LIT) and (ASTSLen[lab] = 0)) then
    begin
      CaseLabelDiag(lab, 'case of string: label must be a string constant', recover);
      Exit;
    end;
    slo := ConstStrLitValue(lab);
    shi := slo;
    if ASTRight[lab] <> -1 then
    begin
      if (not IsConstStrLitNode(ASTRight[lab])) or
         ((ASTKind[ASTRight[lab]] = AN_INT_LIT) and (ASTSLen[ASTRight[lab]] = 0)) then
      begin
        CaseLabelDiag(ASTRight[lab], 'case of string: label must be a string constant', recover);
        Exit;
      end;
      shi := ConstStrLitValue(ASTRight[lab]);
    end;
    if StrictCase and (CaseStrCmp3(slo, shi) > 0) then
    begin
      CaseLabelDiag(lab, 'case range: lower bound is greater than upper bound', recover);
      Exit;
    end;
  end
  else
  begin
    if ASTKind[lab] = AN_STR_LIT then
    begin
      CaseLabelDiag(lab, 'case label does not match the ordinal selector type', recover);
      Exit;
    end;
    lo := ASTIVal[lab];
    hi := lo;
    if ASTRight[lab] <> -1 then
    begin
      if ASTKind[ASTRight[lab]] = AN_STR_LIT then
      begin
        CaseLabelDiag(ASTRight[lab], 'case label does not match the ordinal selector type', recover);
        Exit;
      end;
      hi := ASTIVal[ASTRight[lab]];
    end;
    if StrictCase and (lo > hi) then
    begin
      CaseLabelDiag(lab, 'case range: lower bound is greater than upper bound', recover);
      Exit;
    end;
  end;
  Result := True;
end;

{ O(n^2) pairwise overlap check straight over the AST branch chain (no label
  arrays -- a case can be arbitrarily large). branchSeqHead = AN_SEQ chain of
  AN_PAIR(labels, stmt); the else branch has labels = -1. }
procedure ValidateCaseLabels(branchSeqHead: Integer; isStr, recover: Boolean);
var
  bs, ln, bs2, ln2: Integer;
  lo, hi, lo2, hi2: Int64;
  slo, shi, slo2, shi2: AnsiString;
  clash: Boolean;
begin
  lo := 0; hi := 0; lo2 := 0; hi2 := 0;
  bs := branchSeqHead;
  while bs <> -1 do
  begin
    if ASTLeft[bs] = -1 then ln := -1        { empty chain / else branch }
    else ln := ASTLeft[ASTLeft[bs]];
    while (ln <> -1) and (ASTLeft[ln] <> -1) do
    begin
      if not CaseLabelBounds(ASTLeft[ln], isStr, recover, lo, hi, slo, shi) then
      begin
        { refused and recovered: it has no interval, so it cannot be compared }
        ln := ASTRight[ln];
        continue;
      end;
      { against every label after this one -- FPC-parity duplicate/overlap
        rejection is opt-in (--strict-case); the lax dialect keeps first-match
        semantics for overlapping labels. The CaseLabelBounds walk above stays
        unconditional: it carries the selector-type checks the lowering needs. }
      if StrictCase then
      begin
        ln2 := ASTRight[ln];
        bs2 := bs;
        while bs2 <> -1 do
        begin
          while (ln2 <> -1) and (ASTLeft[ln2] <> -1) do
          begin
            if not CaseLabelBounds(ASTLeft[ln2], isStr, recover, lo2, hi2, slo2, shi2) then
            begin
              ln2 := ASTRight[ln2];
              continue;
            end;
            if isStr then
              clash := not ((CaseStrCmp3(shi, slo2) < 0) or (CaseStrCmp3(shi2, slo) < 0))
            else
              clash := not ((hi < lo2) or (hi2 < lo));
            if clash then
              CaseLabelDiag(ASTLeft[ln2], 'duplicate or overlapping case label', recover);
            ln2 := ASTRight[ln2];
          end;
          bs2 := ASTRight[bs2];
          if bs2 = -1 then ln2 := -1
          else if ASTLeft[bs2] = -1 then ln2 := -1
          else ln2 := ASTLeft[ASTLeft[bs2]];
        end;
      end;
      ln := ASTRight[ln];
    end;
    bs := ASTRight[bs];
  end;
end;
