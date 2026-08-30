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
  ASTLeft[Result]     := CloneAST(ASTLeft[node]);
  ASTRight[Result]    := CloneAST(ASTRight[node]);
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
      if (ASTLeft[node] >= 0) and (ASTKind[ASTLeft[node]] = AN_IDENT) and
         (Integer(ASTIVal[ASTLeft[node]]) >= 0) and
         (Integer(ASTIVal[ASTLeft[node]]) < SymCount) then
        Result := SymPtrElemDynDepth[ASTIVal[ASTLeft[node]]];
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
  else if (ASTKind[node] = AN_DEREF) and (ASTLeft[node] >= 0) and
          (ASTKind[ASTLeft[node]] = AN_IDENT) and
          (SymPtrElemDynDepth[ASTIVal[ASTLeft[node]]] > 0) then
    { `p^` over ^TDyn: the pointee's element type is the pointer's PtrElemTk. }
    Result := IntToTypeKind(Ord(Syms[ASTIVal[ASTLeft[node]]].PtrElemTk))
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
  else if (ASTKind[node] = AN_DEREF) and (ASTLeft[node] >= 0) and
          (ASTKind[ASTLeft[node]] = AN_IDENT) and
          (SymPtrElemDynDepth[ASTIVal[ASTLeft[node]]] > 0) then
    Result := Syms[ASTIVal[ASTLeft[node]]].PtrElemRec
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
