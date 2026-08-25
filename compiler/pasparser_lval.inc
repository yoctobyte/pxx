{ ===== pasparser_lval.inc — Pascal frontend: designators and selectors =======

  Carved out of pasparser_*.inc, byte-for-byte, by
  refactor-a-carve-out-plexer-pparser-so-p-owns-its-own-files.

  Owned by Track P (Pascal frontend). Included from compiler.pas at exactly the
  point it used to occupy, so include ORDER is unchanged — that is what makes
  the carve-out provable by the self-host fixedpoint rather than by reading it.

  Contents: everything that parses a DESIGNATOR — ParseLValueAST and the
  selector chain behind it (field, index, deref, class/record and metaclass
  member tails), lvalue address compilation, set and array-constructor
  literals, open-array and variant-record argument shapes, and the static
  `array of Char`-is-a-string rules.

  DO NOT factor anything here into a shared helper with pyparser.inc/cparser.inc.
  What is shared between frontends is the AST and the IR, never the parser:
  devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md }

{ ===== a name that did not resolve =====

  Both halves of recovering from one, so the four sites that report it stay in
  step. Splitting them was how the three-way diagnostic below drifted between
  its copies in the first place (normalise-dont-special-case.md).

  ReportUndefinedName prints, counts, and RETURNS; PoisonSym then hands the
  parse an ordinary Integer variable under the failed name, so everything after
  it -- the assignment being parsed, the expression it sits in, the rest of the
  file -- carries on against a symbol that behaves. It is REGISTERED under that
  name, so a typo repeated five times is reported once rather than five times.

  Nothing is ever emitted from a poisoned parse: the driver halts on ErrCount
  after ParseProgram, before any output.
  feature-a-error-does-not-halt-so-a-parse-can-be-speculative }
procedure ReportUndefinedName(const nm: AnsiString);
begin
  ErrorIdent := nm;
  if HiddenByDeclOrder(nm) then
    ErrorRecover('undefined variable — it is a global declared later, declare it before use')
  else if HiddenByForwardOrder(nm) then
    ErrorRecover('routine used before its declaration — define it above, or add a forward; declaration (--strict/require-forward)')
  else
    ErrorRecover('undefined variable');
end;

{ Consume a balanced (...) group starting at the current token, so a recovered
  statement does not leave its argument list behind for the statement parser to
  choke on. `NoSuchProc(1, 2);` is a CALL to a name that does not exist, and a
  stand-in VARIABLE cannot absorb the arguments — the second diagnostic was
  `unexpected token`, which says nothing and buries the one that mattered.
  feature-a-error-does-not-halt-so-a-parse-can-be-speculative }
procedure SkipParenGroup;
var depth: Integer;
begin
  if CurTok.Kind <> tkLParen then Exit;
  depth := 0;
  while CurTok.Kind <> tkEOF do
  begin
    if CurTok.Kind = tkLParen then Inc(depth)
    else if CurTok.Kind = tkRParen then
    begin
      Dec(depth);
      if depth = 0 then begin Next; Exit; end;
    end;
    Next;
  end;
end;

function PoisonSym(const nm: AnsiString): Integer;
begin
  { the same shape --auto-locals mints for an undeclared name, minus the warning
    and minus any chance of reaching codegen. A plain scalar deliberately: the
    point is a symbol no later check has to special-case. }
  LastTypeIsSub := False;
  LastTypeRecId := REC_NONE;
  Result := AllocVar(nm, tyInteger);
end;

procedure ResolveDerefShape(node: Integer; var tk: TTypeKind; var recName: Integer;
                            var remDepth, ptrBaseTk, ptrBaseRec: Integer); forward;

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
  guidRec: Integer;   { REC id of the built-in TGuid, for an interface name used as a GUID value }
  helperTk: TTypeKind; helperAi: Integer;   { TARGET-type-name receiver for a type helper — `UInt32.GetSignMask` }
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
      { …and a bare TYPED class const (`const X: T = ...`), which is writable
        STORAGE like a class var rather than a literal, so it resolves to a
        symbol and re-enters the same way. The untyped forms do NOT come through
        here — they have no symbol and are answered as literals by
        EmitClassConstNode further down. Placed beside the class-var lookup
        because they are the same question about the same kind of thing; a
        separate branch elsewhere is how the two would drift.
        bug-p-two-classes-typed-consts-of-the-same-name-collide }
      if (cvIdx < 0) and (fldIdx < 0) and (CurMethClass >= REC_UCLASS_BASE) and (CurProc >= 0) then
        cvIdx := FindClassConstSym(CurMethClass - REC_UCLASS_BASE, fieldName);
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
        { TARGET-TYPE-NAME receiver for a type helper: `UInt32.GetSignMask`,
          `UInt32.SIZED_SIGN_MASK[i]`. The type's own name is not a class, so
          FindUClass misses and this used to be `undefined variable (UInt32)`.

          Resolving it to the HELPER's ci makes it the exact spelling that
          already works — `TU32Helper.GetSignMask` — so the whole static /
          class-var / class-const block below serves it unchanged, including
          the `UClsIsRecord[ci]` arm that passes a by-value dummy Self because a
          helper has no metaclass. One resolver, two spellings, rather than a
          second dispatch path (devdocs/dev/normalise-dont-special-case.md).

          Guarded three ways so no other `.` path can be caught: a dot must
          follow (a BARE `UInt32` must stay a type name, not become a class
          reference), the name must denote a type, and that type must actually
          have a helper in scope. A member that then does not exist still gets
          the ordinary "class method not found", which names the helper —
          strictly more informative than "undefined variable".
          feature-pascal-type-helpers v3 }
        if (ci < 0) and (CurTok.Kind = tkDot) then
        begin
          helperTk := BuiltinTypeNameTk(fieldName);
          if helperTk = tyUnknown then
          begin
            helperAi := FindTypeAlias(fieldName);
            if helperAi >= 0 then helperTk := IntToTypeKind(AliasTk[helperAi]);
          end;
          if helperTk <> tyUnknown then
            ci := FindHelperForType(helperTk, REC_NONE);
        end;
        if PxxDbgEnabled('a.qual') then WriteLn('PXXDBG a.qual MEMBER field=', fieldName, ' flat=', ci);
        if ci >= 0 then
        begin
          if CurTok.Kind <> tkDot then
          begin
            { An INTERFACE name used as a value is NOT a metaclass -- an interface
              has no class reference. In Pascal it means its GUID, and nothing
              else: `g := IHello`, `obj.GetInterface(IHello, f)`. Falling through
              to AN_CLASSREF made the record copy read 16 bytes of the RTTI blob
              (a name pointer and a parent pointer) into the caller's TGuid, with
              no diagnostic and a plausible-looking result.
              bug-a-an-interface-name-as-a-guid-value-copies-rtti }
            if UClsIsInterface[ci] then
            begin
              if not UClsHasGuid[ci] then
                Error('interface "' + fieldName + '" has no GUID, so it has no value form');
              node := AllocNode(AN_GUIDCONST);
              ASTIVal[node] := InternGuidBlob(ci);
              { Typed as the RECORD TGuid, not as a pointer: that is what it is,
                and it is what lets the ordinary record paths carry it -- copy on
                assignment, by-address for a const parameter, overload matching
                against `const IID: TGuid`. RegisterBuiltinTGuid mints the record
                unconditionally, so the lookup cannot miss. }
              guidRec := FindUClass('TGuid');
              ASTTk[node] := Ord(tyRecord);
              tk := tyRecord;
              recName := REC_UCLASS_BASE + guidRec;
              ASTSLen[node] := recName;
              Result := node;
              Exit;
            end;
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
              { No literal backing — a TYPED class const (`const X: T = ...`)
                is writable STORAGE, not a value, so it has a symbol instead.
                Re-enter with that symbol exactly as the class-VAR branch above
                does, which is what makes `TFoo.TAG[1]` parse its suffixes.
                bug-p-two-classes-typed-consts-of-the-same-name-collide }
              fldIdx := FindSym(ccKey);
              if fldIdx >= 0 then
              begin
                Result := ParseLValueAST(fldIdx, qualNameTok);
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
          ReportUndefinedName(fieldName);
          { a CALL to a name that does not exist — swallow the argument list, or
            the stand-in below (a VARIABLE) leaves `(1, 2)` for the statement
            parser and the real diagnostic is buried under `unexpected token`. }
          if CurTok.Kind = tkLParen then SkipParenGroup;
          node := AllocNode(AN_IDENT);
          ASTIVal[node] := PoisonSym(fieldName);
          ASTTk[node] := Ord(tyInteger);
          tk := tyInteger;
          recName := REC_NONE;
          Result := node;
          Exit;
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
        ResolveDerefShape(node, tk, recName, remDepth, ptrBaseTk, ptrBaseRec);
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
      else if (tk = tyPointer) and (ASTKind[node] = AN_DEREF) then
      begin
        { `p^[i]` -- indexing the RESULT of a dereference. The caret branch above
          already parked that result's remaining depth in ASTSOffset and its
          ultimate base in ASTSLen/ASTIVal, so this arm reads the tag it wrote
          rather than re-deriving anything: one level left means the element IS
          the base type (`^PChar` -> `p^[i]` is a Char), two or more means the
          element is still a pointer.

          Without this arm `p^[i]` fell to the final else, which asks the BASE
          SYMBOL for its ElemType -- a pointer variable has none -- so the
          element came out tyUnknown and printed as an address. Both arms of the
          double case were broken identically, global and parameter alike, which
          is why the parameter-depth fix above did not move it. }
        if ASTSOffset[node] >= 2 then
        begin
          tk := tyPointer;
          recName := ASTIVal[node];
        end
        else if (ASTSOffset[node] = 1) and (ASTSLen[node] <> Ord(tyUnknown)) then
        begin
          tk := IntToTypeKind(ASTSLen[node]);
          recName := ASTIVal[node];
        end
        else
        begin
          tk := tyUnknown;
          recName := REC_NONE;
        end;
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
        { A SCALAR cannot be indexed. `i[2]` over an Integer reached this
          fallback, took Syms[i].ElemType -- which for a scalar is its own type,
          not an element type -- and emitted an element load off the variable's
          own address. It compiled clean and read OUT OF BOUNDS: -2099249120 in
          the measured case, a segfault with a larger index. FPC says "Illegal
          qualifier".

          Guarded narrowly on purpose: only an ordinal or float BASE, and only
          when the base symbol is not an array. Everything indexable has already
          been claimed by an arm above (array, string, pointer, pointer field,
          deref, N-D, comma sugar, default property), so what is left here with
          a scalar base is the mistake and nothing else.
          bug-p-ten-constructs-fpc-rejects-are-accepted-and-silently-wrong }
        if (idx >= 0) and (idx < SymCount) and (not Syms[idx].IsArray) and
           (TypeIsOrdinal(tk) or TypeIsFloat(tk)) then
        begin
          ErrorIdent := Syms[idx].Name;
          ErrorRecover('this value cannot be indexed — only arrays, strings and '
                       + 'pointers can');
        end;
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
      if (mmi < 0) and (mci >= 0) and (not UClsIsRecord[mci]) and
         (CurTok.Kind = tkIdent) and
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
        class has no member of that name, so a user's own still wins.

        A RECORD receiver is excluded, and a real FIELD of that name outranks the
        operation — the same two tests the sibling sites (the chained-value arm
        below, and the implicit-Self arm in pasparser_expr.inc) already make. This
        arm asked neither, which was invisible while the names were ClassName /
        ClassType / InheritsFrom / ClassParent — nobody calls a record field that.
        `InstanceSize` joined the set and IS a field of typinfo's TClassRTTI, so
        `cls^.InstanceSize` stopped being a field read at offset 16 and became
        __pxxRttiOf(cls^) — reading the record's first word as an object's class
        pointer. Every RTTI program segfaulted.
        bug-a-a-classref-operation-name-hijacks-a-record-field }
      if (mmi < 0) and (mci >= 0) and (CurTok.Kind = tkIdent) and
         IsClassRefOpName(fieldName) and
         (not UClsIsRecord[mci]) and (FindUField(mci, fieldName) < 0) then
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

      { …and the same record exclusion as the two arms above: these are TObject
        operations, and a RECORD has none of them. Both require a following `(`,
        so no field READ could reach them — but a proc-typed field called as
        `r.MethodAddress(x)` would, for the same reason
        `cls^.InstanceSize` did (bug-a-a-classref-operation-name-hijacks-a-record-field). }
      if (mmi < 0) and (mci >= 0) and (not UClsIsRecord[mci]) and
         (CurTok.Kind = tkIdent) and
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
            ExpectCallRParen(mpi);
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
                  OpenArrayCtorRowLen(mpi, mslot), ProcParamElemRowLo[mpi * MAX_PROC_PARAMS + mslot])
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
            ExpectCallRParen(mpi);
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
  { mmi = -1 is the IMPLICIT root constructor: the class declares none anywhere up
    its chain, so `Create` means FPC's empty TObject.Create. The static `TFoo.Create`
    path has always accepted that shape; this one rejected it with "a pointer has no
    members", so `cr.Create` compiled only for a hierarchy that happened to declare a
    ctor -- the same double case normalise-dont-special-case describes, with the
    unbuilt arm being the one that stayed broken.
    bug-a-metaclass-create-needs-a-declared-constructor }
  if mmi < 0 then mpi := -1 else mpi := UMthProc_[mmi];
  mcallNode := AllocNode(AN_METACLASS_NEW);
  ASTRight[mcallNode]   := crefNode;             { classref value }
  ASTIVal[mcallNode]    := mpi;                  { ctor proc idx, -1 = implicit root }
  if mmi < 0 then ASTSOffset[mcallNode] := -1
  else ASTSOffset[mcallNode] := UMthVirSlot[mmi]; { vmt slot, -1 if non-virtual }
  ASTSLen[mcallNode]    := REC_UCLASS_BASE + ci; { result record id }
  ASTTk[mcallNode]      := Ord(tyClass);
  mlastArg := -1;
  if mpi < 0 then
  begin
    { The root ctor takes nothing. Accept the empty parens FPC accepts and refuse
      arguments here rather than silently dropping them. }
    if CurTok.Kind = tkLParen then
    begin
      Next;
      if CurTok.Kind <> tkRParen then
        Error('this class declares no constructor, so Create takes no arguments');
      Expect(tkRParen, ')');
    end;
    Result := mcallNode;
    Exit;
  end;
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
    ExpectCallRParen(mpi);
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

function OpenArrayCtorRowLen(procIdx, argNo: Integer): Integer;
{ The `rowLen` to hand ParseArrayCtorAST for an open-array param, ENCODING both
  element shapes the temp can need. They are mutually exclusive (a named array
  type is fixed OR dynamic), so one integer carries both:
    > 0  the element is a named FIXED array — this many elements per row
    = 0  the element is a plain scalar/string
    < 0  the element is a named DYNAMIC array — its dyn depth, negated
  Without the third case the temp was built as `array of <base scalar>` and each
  `[a, b]` element stored a dyn HANDLE into a 4-byte Integer slot: silent garbage
  then a segfault (bug-p-open-array-of-a-named-dynamic-array-reads-garbage). }
begin
  Result := 0;
  if (procIdx < 0) or (argNo < 0) or (argNo >= MAX_PROC_PARAMS) then Exit;
  Result := ProcParamElemRowLen[procIdx * MAX_PROC_PARAMS + argNo];
  if Result = 0 then
    Result := -ProcParamElemDynDepth[procIdx * MAX_PROC_PARAMS + argNo];
end;

function ParseArrayCtorAST(elemTk: TTypeKind; rowLen, rowLo: Integer): Integer;
{ `[ e0, e1, ... ]` for an `array of T` (scalar/string) parameter. Builds an
  AN_ARRAY_CTOR whose Left is the element AN_ARG chain; ASTIVal/ASTTk carry the
  element type so overload matching binds it to the open-array param (whose
  TypeKind is the element type). Lowering builds a heap dyn-array temp.
  rowLen/rowLo (ASTSOffset/ASTSLen): the param's ELEMENT shape, encoded by
  OpenArrayCtorRowLen — > 0 a fixed-array row of that length (rowLo is its low
  bound; drives the temp's row stride and per-element row-copy), 0 a scalar,
  < 0 a dyn-array handle element of depth -rowLen. }
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
    ReportUndefinedName(name);
    idx := PoisonSym(name);
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
    ReportUndefinedName(name);
    { a CALL to a name that does not exist: consume the argument list and end
      the statement here, rather than poisoning the name into a variable and
      letting `(1, 2)` reach the statement parser as `unexpected token`. }
    if (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
    begin
      Next;
      SkipParenGroup;
      Exit;
    end;
    idx := PoisonSym(name);
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
                OpenArrayCtorRowLen(mpi, mai), ProcParamElemRowLo[mpi * MAX_PROC_PARAMS + mai]);
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
          ExpectCallRParen(mpi);
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
  { No member of that name anywhere up the chain, but the name is `Create`: that
    is the IMPLICIT root constructor every class inherits from TObject. The
    static `TFoo.Create` spelling has always accepted it; a metaclass receiver
    must too, or the factory idiom works only for classes that happen to declare
    a ctor of their own. bug-a-metaclass-create-needs-a-declared-constructor }
  if (mmi < 0) and CaseEqual(fieldName, 'Create') then
  begin
    Next;                            { consume `Create` }
    Result := BuildMetaclassNew(node, mcCi, -1);
    outTk  := tyClass;
    outRec := REC_UCLASS_BASE + mcCi;
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
    remDepth, ptrBaseTk, ptrBaseRec: Integer;
begin
  tk := Procs[procIdx].RetType;
  recId := REC_NONE;
  elemTk := ProcRetPtrElemTk[procIdx];
  elemRec := ProcRetPtrElemRec[procIdx];
  { The returned pointer's remaining levels and ultimate base, so a `^PChar`
    RESULT walks like a `^PChar` variable. Zero means "the declaration recorded
    no depth" -- the C fn-pointer signature path still does not -- and every arm
    below then keeps its old immediate-pointee behaviour.
    bug-p-dereferencing-a-function-result-of-pointer-to-pchar-loses-the-shape }
  remDepth := ProcRetPtrDepth[procIdx];
  ptrBaseTk := ProcRetPtrBaseTk[procIdx];
  ptrBaseRec := ProcRetPtrBaseRec[procIdx];

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
        if remDepth > 0 then
        begin
          Dec(remDepth);
          { the same tags the main deref chain writes on its own AN_DEREF nodes:
            levels REMAINING in ASTSOffset, the ultimate base in ASTSLen/ASTIVal.
            IsNodePChar's arm 7 and IRPointerStride both read them, and this
            fourth copy of the pointer walk stamped neither -- which is why
            `WriteLn(GetQ^)` printed the address while `c := GetQ^; WriteLn(c)`
            printed the string. }
          ASTSOffset[sub] := remDepth;
          ASTSLen[sub] := ptrBaseTk;
          if ptrBaseRec > 0 then ASTIVal[sub] := ptrBaseRec;
          if remDepth >= 1 then
          begin
            tk := tyPointer; recId := ptrBaseRec;
          end
          else if ptrBaseTk <> Ord(tyUnknown) then
          begin
            tk := IntToTypeKind(ptrBaseTk); recId := ptrBaseRec;
          end;
        end;
        ASTTk[sub] := StrValTk(tk);
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
        { `f()[i]` spends a level exactly as `f()^` does -- indexing a `^PChar`
          result yields a PChar, not another `^PChar`. }
        if remDepth > 0 then
        begin
          Dec(remDepth);
          if remDepth >= 1 then
          begin
            tk := tyPointer; recId := ptrBaseRec;
          end
          else if ptrBaseTk <> Ord(tyUnknown) then
          begin
            tk := IntToTypeKind(ptrBaseTk); recId := ptrBaseRec;
          end;
        end;
        ASTTk[sub] := StrValTk(tk);
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
    node := GenMakeStringValueIndex(node);
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

{ Index a string VALUE — something with no addressable base: a call result
  (`UpperCase(s)[2]`), a parenthesised expression (`(a + b)[3]`), a literal
  (`'hello'[1]`). AN_INDEX needs an address, so materialise the value into a
  hidden temp and yield `(tmp := value, tmp[i])` via AN_COMMA
  (evaluate-left-yield-right), which also evaluates the value exactly once.

  On entry CurTok is the `[`; on exit the `]` is consumed. Returns a node of
  type tyChar.

  Extracted so the call-result arm and the grouped-expression arm cannot drift:
  the grouped arm used to build a RAW AN_INDEX over the string, which compiled
  and then SEGFAULTED at run time (`(s)[3]`) because the base it indexed was the
  string handle rather than a slot holding one.
  bug-a-indexing-a-parenthesised-string-compiles-and-segfaults }
{ True when `(node)[i]` means "the i'th CHARACTER of a string value" rather than
  "the i'th ELEMENT of an array".

  ASTTk alone cannot tell them apart: an array node carries its ELEMENT kind, so
  an `array of AnsiString` and a plain AnsiString both read tyAnsiString there.
  Testing the tag alone sent `(sa)[2]` — indexing an array of strings — down the
  materialise-into-a-string-temp path and yielded the wrong value. The symbol is
  what actually knows, so an identifier is asked; every other node kind that can
  reach here with a string tag is a string VALUE (a literal, a concatenation, a
  call result, an element already selected out of an array).
  bug-a-indexing-a-parenthesised-string-compiles-and-segfaults }
function NodeIsIndexableStringValue(n: Integer): Boolean;
var fRec: Integer;
begin
  Result := False;
  if n < 0 then Exit;
  { every string flavour, not just tyAnsiString: a parenthesised LITERAL is
    tagged tyString and a ShortString variable tyShortString, and both used to
    fall through to the array path — `('hello')[2]` printed a chunk of the data
    segment and `(ss)[2]` printed nothing. Materialising through an AnsiString
    temp is correct for all of them, and one path beats three. }
  if not (IntToTypeKind(ASTTk[n]) in
          [tyAnsiString, tyString, tyShortString, tyFixedString]) then Exit;
  if (ASTKind[n] = AN_IDENT) and (ASTIVal[n] >= 0) and
     (ASTIVal[n] < SymCount) and Syms[ASTIVal[n]].IsArray then Exit;
  { …and a record FIELD the same way: `(r.sa)[2]` selects an array element and
    `(r.s)[2]` a character, and again only the declaration knows which. The
    field is identified by its source span, which is how codegen re-resolves it
    too, so this asks the same question the same way. }
  if ASTKind[n] = AN_FIELD then
  begin
    fRec := ResolveNodeRec(ASTLeft[n]);
    if (fRec >= REC_UCLASS_BASE) and
       RecFieldIsArray(fRec, GetTokenStrFromRaw(ASTSOffset[n], ASTSLen[n])) then Exit;
  end;
  Result := True;
end;

function GenMakeStringValueIndex(valNode: Integer): Integer;
var tmpSym, tmpN, asgn, idx, comma: Integer;
begin
  Next;                                      { consume '[' }
  tmpSym := AllocVar('', tyAnsiString);      { hidden temp (sym idx) }
  tmpN := AllocNode(AN_IDENT);
  ASTIVal[tmpN] := tmpSym;
  ASTTk[tmpN] := Ord(tyAnsiString);
  asgn := AllocNode(AN_ASSIGN);
  ASTLeft[asgn] := tmpN;
  ASTRight[asgn] := valNode;                 { the side-effect leg }
  tmpN := AllocNode(AN_IDENT);
  ASTIVal[tmpN] := tmpSym;
  ASTTk[tmpN] := Ord(tyAnsiString);
  idx := AllocNode(AN_INDEX);
  ASTLeft[idx] := tmpN;
  ParseExpr;
  ASTRight[idx] := CurASTNode;
  Expect(tkRBrack, ']');
  ASTTk[idx] := Ord(tyChar);
  comma := AllocNode(AN_COMMA);
  ASTLeft[comma] := asgn;
  ASTRight[comma] := idx;
  ASTTk[comma] := Ord(tyChar);
  Result := comma;
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
  whichever operand carries one. bug-p-a-pchar-plus-offset-loses-its-type-when-dereferenced

  The FIELD and PTR_CAST arms were added for
  bug-p-a-second-deref-on-a-typecast-pointer-field-is-dropped: the alias-cast
  postfix loop in pasparser_expr.inc answered every `^` in a chain from the
  ORIGINAL cast's alias, so `PRec(raw)^.n^` typed the second deref as the
  record the CAST points at instead of what the FIELD points at. Same shape as
  NodeMetaclassCi's note below — one predicate that knows every spelling beats
  a per-site copy that knows one, because the copy is what goes stale. }
var baseRec, fIdx: Integer;
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
  else if ASTKind[node] = AN_FIELD then
  begin
    { A pointer-typed FIELD: the pointee is the FIELD's, from UFldPtrElem*. }
    if IntToTypeKind(ASTTk[node]) <> tyPointer then Exit;
    baseRec := ResolveNodeRec(ASTLeft[node]);
    if baseRec < REC_UCLASS_BASE then Exit;
    fIdx := FindUField(baseRec - REC_UCLASS_BASE, GetASTIdentName(node));
    if fIdx < 0 then Exit;
    elemTk := IntToTypeKind(UFldPtrElemTk[fIdx]);
    elemRec := UFldPtrElemRec[fIdx];
    Result := elemTk <> tyUnknown;
  end
  else if ASTKind[node] = AN_PTR_CAST then
  begin
    { An inline typed pointer cast: the pointee is the alias's. A NEGATIVE
      ASTIVal is an adapter marker (-2 = the PChar +8 skip, -1 = a widening
      ordinal pun), not an alias row — those carry no pointee here. }
    if ASTIVal[node] < 0 then Exit;
    elemTk := IntToTypeKind(AliasElemTk[ASTIVal[node]]);
    elemRec := AliasElemRec[ASTIVal[node]];
    Result := elemTk <> tyUnknown;
  end
  else if (ASTKind[node] = AN_BINOP) and
          (TTokenKind(ASTIVal[node]) in [tkPlus, tkMinus]) then
  begin
    Result := NodePtrElem(ASTLeft[node], elemTk, elemRec, depth + 1);
    if not Result then
      Result := NodePtrElem(ASTRight[node], elemTk, elemRec, depth + 1);
  end;
end;

{ ONE pointer-shape walk for a dereference, `x^`.

  It answers the five-field question every PChar/pointer predicate downstream
  asks -- the immediate pointee (tk, recName), the pointer levels REMAINING
  after this `^`, and the ULTIMATE base (kind, rec) -- for a variable, a field,
  an array element, a nested deref, a call result, a typed cast, and pointer
  arithmetic.

  It exists because there were FOUR copies of this walk: the lvalue suffix
  chain, the parenthesised postfix tail in pasparser_expr.inc, the inherited-call
  tail, and ApplyCallResultPtrSuffix -- and the copies disagreed. The
  parenthesised one resolved the immediate pointee via NodePtrElem and stamped
  NOTHING, so `(qa[0])^` over an `array of ^PChar` lost the shape that the
  identical `qa[0]^` one character to the left keeps: WriteLn printed the
  address, `'x' + it` was empty, `Length` answered the pointer. One concept,
  correct through one spelling and wrong through another -- the exact failure
  devdocs/dev/normalise-dont-special-case.md is about, and the reason this is
  extracted rather than copied a fifth time.
  refactor-centralize-managed-string-pchar-conversion }
procedure ResolveDerefShape(node: Integer; var tk: TTypeKind; var recName: Integer;
                            var remDepth, ptrBaseTk, ptrBaseRec: Integer);
var baseNode, baseRec, fIdx: Integer;
    fieldName: AnsiString;
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
          { ...and the depth + ultimate base, exactly as the AN_IDENT arm
            reads them off a variable. `r.F^` over a `^PChar` FIELD came out a
            bare pointer with no levels left, so WriteLn printed the address
            and `=` compared pointers -- the same five-context signature the
            array-element and function-result shapes had.
            bug-p-dereferencing-a-function-result-of-pointer-to-pchar-loses-the-shape }
          if UFldPtrDepth[fIdx] > 0 then
          begin
            remDepth := UFldPtrDepth[fIdx] - 1;
            ptrBaseTk := UFldPtrBaseTk[fIdx];
            ptrBaseRec := UFldPtrBaseRec[fIdx];
          end;
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
          { ...and the element's DEPTH and ultimate BASE, exactly as the
            AN_IDENT arm above reads them. This arm read only the immediate
            pointee, so `qa[0]^` over `array[0..1] of ^PChar` came out as a
            bare pointer with no depth and no base -- and every predicate that
            asks "one level remaining over a char base?" answered no.
            WriteLn(qa[0]^) printed the address, `'x' + qa[0]^` was empty and
            `qa[0]^ = 'alpha'` compared pointers, while the three contexts that
            work by the blanket AnsiString(<any pointer>) rule looked fine --
            the mix that reads as "half a shape is supported".

            This was recorded in the ticket as genuinely ABSENT metadata
            needing a new SymElemPtrDepth. It is not absent. An array symbol
            is not itself a pointer, so AllocArray parks the ELEMENT's depth
            and base in the symbol's own SymPtrDepth/SymPtrBaseTk slots --
            measured with PXXDBG=a.symptr, which needed extending to the array
            alloc paths before it could answer (it was scalar-only, i.e. blind
            to the one shape it was written to diagnose). Reader half, again.
            refactor-centralize-managed-string-pchar-conversion }
          if SymPtrDepth[ASTIVal[baseNode]] > 0 then
          begin
            remDepth := SymPtrDepth[ASTIVal[baseNode]] - 1;
            ptrBaseTk := SymPtrBaseTk[ASTIVal[baseNode]];
            ptrBaseRec := SymPtrBaseRec[ASTIVal[baseNode]];
          end;
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
      else if (ASTKind[node] = AN_CALL) or (ASTKind[node] = AN_VIRTUAL_CALL) or
              (ASTKind[node] = AN_INTF_CALL) or (ASTKind[node] = AN_CALL_IND) then
      begin
        { `GetQ^` -- dereferencing a function RESULT. The callee's declaration
          records the returned pointer's whole triple (ProcRetPtrElemTk/Rec
          plus ProcRetPtrDepth / ProcRetPtrBaseTk / ProcRetPtrBaseRec), so
          this reads it exactly as the AN_IDENT arm reads a variable's.

          There was no arm here at all: a dereferenced call fell to the final
          else and came out tyInteger, so `WriteLn(GetQ^)` printed the address
          as a number. All three call shapes carry the Procs[] index in IVal.
          bug-p-dereferencing-a-function-result-of-pointer-to-pchar-loses-the-shape }
        if (ASTIVal[node] >= 0) and (ASTIVal[node] < ProcCount) then
        begin
          tk := IntToTypeKind(ProcRetPtrElemTk[ASTIVal[node]]);
          recName := ProcRetPtrElemRec[ASTIVal[node]];
          if ProcRetPtrDepth[ASTIVal[node]] > 0 then
          begin
            remDepth := ProcRetPtrDepth[ASTIVal[node]] - 1;
            ptrBaseTk := ProcRetPtrBaseTk[ASTIVal[node]];
            ptrBaseRec := ProcRetPtrBaseRec[ASTIVal[node]];
          end;
        end
        else
        begin
          tk := tyUnknown;
          recName := REC_NONE;
        end;
      end
      else if (ASTKind[node] = AN_PTR_CAST) and (ASTIVal[node] >= 0) and
              (ASTIVal[node] < AliasCount) then
      begin
        { An inline typed pointer cast, `PPC(raw)^`. The alias row carries the
          same triple a variable's declaration does, and this walk had no arm
          for it at all -- it fell to the final else and came out tyInteger.
          NodePtrElem below reads the alias's immediate pointee, so the CAST
          spelling half-worked while the depth and base were dropped. }
        tk := IntToTypeKind(AliasElemTk[ASTIVal[node]]);
        recName := AliasElemRec[ASTIVal[node]];
        if AliasPtrDepth[ASTIVal[node]] > 0 then
        begin
          remDepth := AliasPtrDepth[ASTIVal[node]] - 1;
          ptrBaseTk := AliasPtrBaseTk[ASTIVal[node]];
          ptrBaseRec := AliasPtrBaseRec[ASTIVal[node]];
        end;
      end
      else
      begin
        { Anything else -- above all pointer ARITHMETIC, `(p + k)^`, which only
          the parenthesised tail can reach. NodePtrElem sees through the binop
          to whichever operand carries a pointee; it knows nothing of depth, so
          a `^PChar` reached this way still resolves one level only. That is the
          pre-existing behaviour of both callers, preserved rather than widened
          here. }
        tk := tyInteger;
        recName := REC_NONE;
        if not NodePtrElem(node, tk, recName, 0) then
        begin
          tk := tyInteger;
          recName := REC_NONE;
        end;
      end;
      if remDepth >= 1 then
      begin
        tk := tyPointer;
        recName := ptrBaseRec;
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
  { Two ways to be a WideChar value, and both must answer here. The -3 marker on
    an AN_PTR_CAST is the original one and still the only evidence a CAST leaves.
    The TYPE KIND is the one that survives a variable: since tyWideChar exists
    (bug-a-writeln-of-a-widechar-prints-its-ordinal) a `w: WideChar` read carries
    its own kind instead of collapsing to tyUInt16, so the callers that used to
    need a separate "...or the operand is tyUInt16" clause beside every call are
    answered here instead. Those clauses stay where they are — they are a
    fallback for shapes neither arm reaches, and retiring them is its own
    migration. }
  Result := (n >= 0) and
            (((ASTKind[n] = AN_PTR_CAST) and (Integer(ASTIVal[n]) = -3)) or
             (IntToTypeKind(ASTTk[n]) = tyWideChar));
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

  { ...and, beside it, which arguments are the literal `nil`. Same single entry
    point, same freshness guarantee across the retry matches below. Kept as its
    own channel rather than folded into MatchArgRec because it answers a
    different question -- not "which record is this" but "may this bind a
    nil-able parameter of ANY of the nil-able kinds".
    bug-a-nil-is-not-accepted-as-a-method-pointer-argument }
  currArg := argsHead;
  for i := 0 to nArgs-1 do
  begin
    if i < MAX_PROC_PARAMS then
      MatchArgNil[i] := IsNilLiteralNode(ASTLeft[currArg]);
    currArg := ASTRight[currArg];
  end;
  MatchArgNilValid := True;

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

{ Every built-in SCALAR type name, in ONE place: the kind it denotes, or
  tyUnknown for a name that is not one. The sibling of BuiltinPtrNameElemTk
  above, and consulted under the same rule — only after FindTypeAlias misses,
  so a source or RTL declaration of the name still wins.

  It exists because the table used to exist TWICE and the two copies disagreed.
  ParseTypeKind (pasparser_decl.inc) knew ~40 names; the built-in typecast in
  pasparser_expr.inc knew ~12. A name added to the first did not become
  CASTABLE, so `var b: ByteBool` compiled and `ByteBool(2)` was
  "undefined variable (ByteBool)" — along with WordBool, LongBool, Comp,
  ValReal, TDateTime, Currency, SizeUInt, UTF8String, RawByteString, OleVariant
  and CodePointer, every one of them a legal cast in FPC. And where the two
  overlapped they did not always answer the same thing: the cast chain called
  `longint` tyInteger, `nativeint`/`ptrint` tyInt64 and `nativeuint`/`ptruint`
  tyUInt64. The declaration's answers won the merge, because a cast that
  produces a different kind from the DECLARATION of the same name means one of
  them is wrong, and NativeInt is pointer-sized by definition — tyInt64 is
  simply false on every 32-bit target.
  bug-a-the-builtin-type-name-table-exists-twice-and-the-two-disagree

  Only side-effect-free names live here. `shortstring` (sets LastTypeStrCap),
  `pwidechar` / `pchar` / `object` (set LastTypePointerElemTk), `textfile`,
  `file` and the promotable-int family keep their own arms at the declaration
  site, because they do more than name a kind. }
function BuiltinScalarTypeKind(const nm: AnsiString): TTypeKind;
begin
  { The keyword-token builtins BY NAME. The real lexer tokenizes these as
    tkBoolean_T/tkInteger_T/..., so a DECLARATION reaches them here only from a
    synthetic token stream that spells them as plain identifiers — the
    parallel-for capture accessor (`capj: ^Boolean` built via NestStrOff) being
    the one in-tree producer, and without the mapping a captured Boolean deref
    re-typed as Integer (bug-parallel-for-captured-boolean-loses-type). A
    TYPECAST reaches them by name every time. }
  if CaseEqual(nm, 'boolean') then Result := tyBoolean
  else if CaseEqual(nm, 'integer') then Result := tyInteger
  else if CaseEqual(nm, 'char') or CaseEqual(nm, 'ansichar') then Result := tyChar
  else if CaseEqual(nm, 'shortint') or CaseEqual(nm, 'int8') then Result := tyInt8
  else if CaseEqual(nm, 'byte') or CaseEqual(nm, 'uint8') then Result := tyUInt8
  else if CaseEqual(nm, 'smallint') or CaseEqual(nm, 'int16') then Result := tyInt16
  else if CaseEqual(nm, 'word') or CaseEqual(nm, 'uint16') then Result := tyUInt16
  else if CaseEqual(nm, 'longint') or CaseEqual(nm, 'int32') then Result := tyInt32
  else if CaseEqual(nm, 'cardinal') or CaseEqual(nm, 'longword') or
          CaseEqual(nm, 'uint32') or CaseEqual(nm, 'dword') then Result := tyUInt32
  else if CaseEqual(nm, 'int64') then Result := tyInt64
  else if CaseEqual(nm, 'qword') or CaseEqual(nm, 'uint64') then Result := tyUInt64
  { pointer-sized by DEFINITION: the cast site used to answer tyInt64/tyUInt64,
    which is wrong on i386, arm32, riscv32 and xtensa }
  else if CaseEqual(nm, 'nativeint') or CaseEqual(nm, 'ptrint') or
          CaseEqual(nm, 'sizeint') then Result := tyNativeInt
  else if CaseEqual(nm, 'nativeuint') or CaseEqual(nm, 'ptruint') or
          CaseEqual(nm, 'sizeuint') then Result := tyNativeUInt
  else if CaseEqual(nm, 'pointer') or CaseEqual(nm, 'codepointer') then Result := tyPointer
  { floats. `Real` is the target's native float depth: ESP and riscv32 have no
    hardware double. `Extended` aliases Double on every target
    (feature-extended-alias-or-reject) and `ValReal` is FPC's "widest real". }
  else if CaseEqual(nm, 'real') then
  begin
    if (TargetArch = TARGET_XTENSA) or (TargetArch = TARGET_RISCV32) then
      Result := tySingle
    else
      Result := tyDouble;
  end
  else if CaseEqual(nm, 'single') then Result := tySingle
  else if CaseEqual(nm, 'double') or CaseEqual(nm, 'extended') or
          CaseEqual(nm, 'valreal') or CaseEqual(nm, 'tdatetime') or
          CaseEqual(nm, 'currency') then Result := tyDouble
  { FPC's sized booleans are C-ABI booleans — a fixed-width integer where
    nonzero means true. They must keep their WIDTH (LongBool 4, WordBool 2,
    ByteBool 1); mapping them onto tyBoolean would silently resize any struct
    or call that crosses to C. }
  else if CaseEqual(nm, 'longbool') then Result := tyInteger
  else if CaseEqual(nm, 'wordbool') then Result := tyUInt16
  else if CaseEqual(nm, 'bytebool') then Result := tyUInt8
  { WideChar is a UTF-16 code UNIT; UCS4Char is a CODE POINT and converts to a
    string as UTF-8. Distinct kinds on purpose — see defs.inc. }
  else if CaseEqual(nm, 'widechar') then Result := tyWideChar
  else if CaseEqual(nm, 'ucs4char') or CaseEqual(nm, 'unicodechar') then Result := tyUCS4Char
  else if CaseEqual(nm, 'comp') then Result := tyInt64
  else if CaseEqual(nm, 'variant') or CaseEqual(nm, 'olevariant') then Result := tyVariant
  { unicodestring/widestring: pragmatic alias to the native string type (byte
    semantics). FPC's UTF-16 payload model is a later slice. }
  else if CaseEqual(nm, 'ansistring') or CaseEqual(nm, 'unicodestring') or
          CaseEqual(nm, 'widestring') then
  begin
    if PasDefineExists('PXX_MANAGED_STRING') then
      Result := tyAnsiString
    else
      Result := tyString;
  end
  { UTF8String / RawByteString are unconditionally the managed kind, which is
    what the declaration site has always said. Kept distinct from the arm above
    rather than folded into it: the two differ, and merging tables is exactly
    how the divergence this function exists to end got started. }
  else if CaseEqual(nm, 'utf8string') or CaseEqual(nm, 'rawbytestring') then
    Result := tyAnsiString
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
  { WideChar — a UTF-16 code UNIT, 2 bytes. Its own kind (storage is tyUInt16's)
    so that WriteLn can tell it from a Word; see the note on tyWideChar in
    defs.inc. `WideChar(x)` is fpjson's \u escape decoder. }
  else if CaseEqual(nm, 'widechar') then Result := tyWideChar
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
function TryOrdinalVarBound(symIdx: Integer; wantHigh: Boolean;
                            var v: Int64; var tkOut: TTypeKind): Boolean;
{ Low(x)/High(x) where x is an ordinal VARIABLE -- `var b: Byte` gave 0 and -1,
  and so did every other scalar: Byte, SmallInt, Char, Boolean, Integer, an
  enum, and a named subrange. Only the array-variable arms and the type-name
  fold ever answered.

  0 and -1 is not a random wrong pair, it is `Length(x) - 1` reached through the
  fallback at the bottom of both intrinsics: a non-array, non-string operand has
  no [data-8] header, Length answers 0, and High answers -1. So the single most
  idiomatic loop in Pascal, `for i := Low(x) to High(x)`, ran ZERO times over
  any ordinal -- silently, since 0..-1 is a legal empty range -- and `High(b)`
  used as a mask or a bound was -1. Found 2026-08-22 by an fpc differential
  sweep over arrays; fpc answers the variable's TYPE bounds for all of these.

  The bound's type comes back in tkOut so the literal prints like fpc's:
  Low(Char) is #0 and not 0, Low(Boolean) is FALSE and not 0. A named subrange
  keeps its base type (`TL = 'a'..'e'` is a Char), which is what SymSubLo/Hi are
  already stamped alongside for {$R+}. }
var eLo, eHi: Integer;
begin
  Result := False;
  if (symIdx < 0) or (symIdx >= SymCount) then Exit;
  if Syms[symIdx].IsArray then Exit;
  tkOut := Syms[symIdx].TypeKind;
  { A named SUBRANGE answers its OWN bounds, not the base type's -- the same
    rule TryConstHighLowValue and TryFoldHighLowType apply to the type NAME.
    Without it `var i: TI` where `TI = 3..7` answered Integer's bounds, which
    is the bug bug-a-low-high-of-a-named-subrange-answer-the-base-type fixed
    for the type name and never reached the variable. }
  if SymIsSub[symIdx] then
  begin
    if wantHigh then v := SymSubHi[symIdx] else v := SymSubLo[symIdx];
    Result := True;
    Exit;
  end;
  if SymEnumId[symIdx] >= 0 then
  begin
    EnumTypeOrdRange(SymEnumId[symIdx], eLo, eHi);
    if wantHigh then v := eHi else v := eLo;
    Result := True;
    Exit;
  end;
  Result := OrdinalTypeBound(tkOut, wantHigh, v);
end;

function TryArrayTypeBound(const nm: AnsiString; wantHigh: Boolean; var v: Int64): Boolean;
{ Low(T)/High(T) where T is a named ARRAY type -- `TA = array[5..9] of Integer`
  answered `undefined variable (TA)` while `Low(a)` over a VARIABLE of that type
  worked, so the idiomatic `for i := Low(TA) to High(TA)` had to be spelled with
  a dummy variable. Measured against fpc 3.2.2: Low(TA)=5, High(TA)=9; on an N-D
  type the bounds are the FIRST dimension's (`array[0..2, 0..3]` gives 0 and 2);
  on a dynamic type Low is 0 and High is REFUSED, since there is no length until
  an instance exists.

  Called from both TryConstHighLowValue (const contexts) and TryFoldHighLowType
  (expressions) -- those two are one concept in two places, as their own
  comments already say, so the array rule lands as ONE function rather than a
  third copy. Does not consume the name; the callers do that.

  The bound's TYPE is Integer here, matching what the variable path already
  answers: `Low(c)` over `array['a'..'e']` prints 97, not 'a', in pxx today.
  That is a real divergence from fpc, but it is the VARIABLE path's divergence
  and predates this -- filed as bug-a-low-high-of-a-char-indexed-array-answer-
  the-ordinal. Answering differently here would make the type name and the
  variable disagree, which is worse than either answer. }
var ai, base: Integer;
begin
  Result := False;
  ai := FindArrayType(nm);
  if ai < 0 then Exit;
  if ArrTypeIsDyn[ai] or (ArrTypeDynDepth[ai] > 0) then
  begin
    { fpc: Low is 0, High is a compile error. Refusing High keeps a wrong
      answer out of `for i := Low(T) to High(T)`, which would otherwise run
      from 0 to whatever ArrTypeHi happened to hold for a dynamic alias. }
    if wantHigh then Exit;
    v := 0;
    Result := True;
    Exit;
  end;
  if ArrTypeNDims[ai] >= 1 then
  begin
    base := ai * MAX_ARR_DIMS;
    if wantHigh then v := ArrTypeDimLo[base] + ArrTypeDimSpan[base] - 1
    else v := ArrTypeDimLo[base];
  end
  else if wantHigh then v := ArrTypeHi[ai]
  else v := ArrTypeLo[ai];
  Result := True;
end;

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

  if TryArrayTypeBound(nm, wantHigh, v) then
  begin
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

  if TryArrayTypeBound(nm, wantHigh, bv) then
  begin
    Next; outNode := AllocNode(AN_INT_LIT); ASTIVal[outNode] := bv; ASTTk[outNode] := Ord(tyInteger);
    Result := True; Exit;
  end;
end;
