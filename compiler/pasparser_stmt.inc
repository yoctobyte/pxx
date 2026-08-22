{ ===== pasparser_stmt.inc — Pascal frontend: statement parsing ===============

  Carved out of pasparser_*.inc, byte-for-byte, by
  refactor-a-carve-out-plexer-pparser-so-p-owns-its-own-files.

  Owned by Track P (Pascal frontend). Included from compiler.pas at exactly the
  point it used to occupy, so include ORDER is unchanged — that is what makes
  the carve-out provable by the self-host fixedpoint rather than by reading it.

  Contents: the statement parser and the constructs that are statements in this
  dialect — both `for ... in` forms (native and structural-enumerator), the
  stackless-generator state-machine transform, keyword file IO, and `parallel for`.

  DO NOT factor anything here into a shared helper with pyparser.inc/cparser.inc.
  What is shared between frontends is the AST and the IR, never the parser:
  devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md }

{ ===== Statement parser ===== }

procedure ParseStatement; forward;
{ Does unary minus on this operand type yield an Int64, the way FPC's does?
  True for every INTEGER type and nothing else — see the long note at
  ParseFactor's tkMinus case. }
function ASTConstIntValue(node: Integer; var v: Int64; depth: Integer): Boolean;
{ Is this an integer CONSTANT expression, and what is its value?

  Used only to TYPE a negated constant (ParseFactor's tkMinus arm); nothing is
  folded in the AST or the IR on the strength of it, so an arithmetic surprise
  here costs a type, not a value. Wide literals are excluded -- their digits live
  in the token span and ASTIVal holds only the wrapped reading, so they are not a
  value this can read (see IsWideIntLit).

  Depth-capped, and deliberately small: literals, a nested negation, and the
  integer operators a constant expression is built from. Anything else answers
  False and takes the widening path. }
var a, b: Int64;
begin
  Result := False;
  v := 0;
  if (node < 0) or (depth > 16) then Exit;
  case ASTKind[node] of
    AN_INT_LIT:
      begin
        if (ASTSLen[node] > 0) and
           ((ASTTk[node] = Ord(tyInt64)) or (ASTTk[node] = Ord(tyPromoInt64))) then Exit;
        if ASTTk[node] = Ord(tyPromoInt64) then Exit;
        v := ASTIVal[node];
        Result := True;
      end;
    AN_NEG:
      begin
        Result := ASTConstIntValue(ASTLeft[node], a, depth + 1);
        if Result then v := -a;
      end;
    AN_BINOP:
      begin
        if not ASTConstIntValue(ASTLeft[node], a, depth + 1) then Exit;
        if not ASTConstIntValue(ASTRight[node], b, depth + 1) then Exit;
        Result := True;
        case TTokenKind(ASTIVal[node]) of
          tkPlus:  v := a + b;
          tkMinus: v := a - b;
          tkStar:  v := a * b;
          tkDiv:   if b = 0 then Result := False else v := a div b;
          tkMod:   if b = 0 then Result := False else v := a mod b;
          tkShl:   if (b < 0) or (b > 63) then Result := False else v := a shl b;
          tkShr:   if (b < 0) or (b > 63) then Result := False else v := a shr b;
          tkAnd:   v := a and b;
          tkOr:    v := a or b;
          tkXor:   v := a xor b;
          else     Result := False;
        end;
      end;
  end;
end;

function NegWidensToInt64(tk: TTypeKind): Boolean;
begin
  Result := False;
  case Ord(tk) of
    1, 3,            { tyInteger, tyChar }
    7, 8, 9, 10,     { tyInt8, tyUInt8, tyInt16, tyUInt16 }
    11, 12, 13, 14,  { tyInt32, tyUInt32, tyInt64, tyUInt64 }
    15, 16:          { tyNativeInt, tyNativeUInt }
      Result := True;
  end;
end;

procedure ParseBlock; forward;
function WrapMainBodyManagementOps(bodyNode: Integer): Integer; forward;  { class operator Initialize/Finalize on globals }

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

{ Eight-argument twin of GenMakeCall6, for the stackless step call: the
  instance pointer plus one pad per declared parameter (see SL_MAX_PARAMS). }
function GenMakeCall8(procIdx: Integer; retTk: TTypeKind;
                      a0, a1, a2, a3, a4, a5, a6, a7: Integer): Integer;
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
  prev := GenAddArg(Result, prev, a6);
  prev := GenAddArg(Result, prev, a7);
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

{ A generator's declared parameter is stored into its persistent instance slot
  by the for-in desugar, as ONE machine word. A Nil Python variant parameter is
  by-REF, so the word must be an ADDRESS — and it must outlive the loop, which a
  caller-side temporary does not: the callee reads it again at every resume,
  long after the statement that produced the argument has finished.

  So the argument gets a 16-byte heap cell (the same pycell_new a `nonlocal`
  capture uses) and the slot holds the cell. Assigning INTO the cell goes down
  the managed-variant path, so the argument is retained for the generator's
  whole life. One cell per generator instance per variant argument, released
  with neither the instance nor the loop — a bounded leak, recorded on the
  ticket rather than hidden here. }
{ Does argument `k` of this generator need a heap cell to carry it?

  ONLY a Nil Python VARIANT parameter. The test that shipped first was
  `Params[k].IsRef`, which is also true of a Pascal `var` parameter and of the
  by-ref `const record` a stackless generator takes — so a plain Pascal
  generator was told it needed pylib's pycell_new, a unit a Pascal program has
  no reason to have in scope, and test_stackless_gen went red. The by-ref
  spellings are not interchangeable: a Pascal `var` argument already has a
  caller-side address that outlives the loop, which is exactly what a Python
  temporary does not. }
function PyGenArgNeedsCell(gpi, k: Integer): Boolean;
begin
  Result := PyExprMode and (k < Procs[gpi].ParamCount) and
            Procs[gpi].Params[k].IsRef and
            (Procs[gpi].Params[k].TypeKind = tyVariant);
end;

function GenMakeVariantArgCell(argNode: Integer; var preSeq: Integer): Integer;
var ps, newPi, callNode, asgn, derefNode: Integer;
begin
  newPi := FindProc('pycell_new');
  if newPi < 0 then
    Error('for-in generator: a variant argument needs pylib (pycell_new) in scope');
  ps := AllocVar('', tyPointer);
  Syms[ps].PtrElemTk := tyVariant;
  callNode := AllocNode(AN_CALL);
  ASTIVal[callNode] := newPi;
  ASTLeft[callNode] := -1;
  ASTTk[callNode] := Ord(tyPointer);
  preSeq := GenMakeSeq(preSeq, GenMakeSeq(
              GenMakeAssign(GenMakeIdent(ps, tyPointer), callNode), -1));
  derefNode := AllocNode(AN_DEREF);
  ASTLeft[derefNode] := GenMakeIdent(ps, tyPointer);
  ASTTk[derefNode] := Ord(tyVariant);
  preSeq := GenMakeSeq(preSeq, GenMakeSeq(
              GenMakeAssign(derefNode, argNode), -1));
  Result := GenMakeIdent(ps, tyPointer);
end;

{ Concatenate two AN_SEQ statement chains, keeping `a` first (-1 = empty).
  chainSeq does the same job but is declared with the stackless transform, far
  below this desugar. }
function chainSeqFwd(a, b: Integer): Integer;
var t: Integer;
begin
  if a < 0 then begin Result := b; Exit; end;
  if b < 0 then begin Result := a; Exit; end;
  t := a;
  while ASTRight[t] >= 0 do t := ASTRight[t];
  ASTRight[t] := b;
  Result := a;
end;

function ParseForInGeneratorAST(varIdx, gpi, recvNode, elemPrologue: Integer): Integer;
var
  savedHoist, argHoist, hoistSeq: Integer;
  bodyNode, nargs, gIdx: Integer;
  a0, a1, a2, a3, a4, a5: Integer;
  procAddr, nargsLit, callAlloc, callNext, callCur, callFree: Integer;
  assignG, assignX, whileNode, innerSeq, instLit: Integer;
  sa1, sa2, sa3, sa4, sa5, sa6: Integer;
  paCoAlloc, paCoNext, paCoCurrent, paCoFree: Integer;
  curDeref: Integer;
begin
  if Syms[varIdx].TypeKind = tyAuto then
    Error('for var .. in <generator>: inline loop variable not yet supported here — declare the variable explicitly (feature-inline-loop-var-rio)');
  { PARK the Nil Python hoist queue across the argument parse. A Python argument
    can need setup statements of its own — a list/dict LITERAL is built by
    hoisted statements, not by one expression node — and this desugar bypasses
    the statement loop that would normally flush them. Dropped, the literal was
    never constructed and the generator received None: `for v in g(["a","b"])`
    raised a TypeError from inside `g`, while `d = ["a","b"]; for v in g(d)`
    worked, which is the tell. They are spliced back in ahead of the instance
    setup below, since the setup CONSUMES what they build. }
  argHoist := -1;
  savedHoist := PyHoistPark;
  { unused args default to 0 (no local array — must cross-compile) }
  a0 := GenZeroLit; a1 := GenZeroLit; a2 := GenZeroLit; a3 := GenZeroLit;
  a4 := GenZeroLit; a5 := GenZeroLit;
  nargs := 0;
  { A generator METHOD is an ordinary generator whose first declared parameter
    is `self`, so the receiver is simply argument 0 and the rest of this desugar
    is unchanged. The caller has already parsed it (it is an arbitrary
    expression, and only the frontend knows how to read one). }
  if recvNode >= 0 then
  begin
    a0 := recvNode;
    nargs := 1;
  end;
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
        else if PyExprMode then
          PyParseBoolExpr        { the Nil Python expression grammar, not Pascal's }
        else
          ParseExpr;
        case nargs of
          0: a0 := CurASTNode;
          1: a1 := CurASTNode;
          2: a2 := CurASTNode;
          3: a3 := CurASTNode;
          { …and two more for a STACKLESS generator only; the stackful CoAlloc
            below packs its arguments into one call and still stops at four. }
          4: if ProcIsStackless[gpi] then a4 := CurASTNode
             else Error('for-in generator: at most 4 arguments (v1)');
          5: if ProcIsStackless[gpi] then a5 := CurASTNode
             else Error('for-in generator: at most 4 arguments (v1)');
          else Error('for-in generator: at most ' + AIntToStr(SL_MAX_PARAMS)
                     + ' arguments (v1)');
        end;
        Inc(nargs);
      until not Eat(tkComma);
    Expect(tkRParen, ')');
  end;
  argHoist := PyHoistPark;      { what the arguments queued }
  PyHoistRestore(savedHoist);   { …and the enclosing statement's own queue back }
  { The header's tail is the FRONTEND's, not the generator machinery's: Pascal
    writes `do <statement>`, Nil Python writes `: <suite>`. PyParseSuite, not
    PyParseBlock — the latter expects to be standing inside the block already and
    reports `unexpected token` on the NEWLINE/INDENT the header still owns. }
  if PyExprMode then
  begin
    Expect(tkColon, ':');
    bodyNode := PyParseSuite;
  end
  else
  begin
    Expect(tkDo, 'do');
    bodyNode := ParseStatementAST;
  end;

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
    { The arguments' own setup runs FIRST — the slot stores read what it builds.
      The hoist queue is already an AN_SEQ chain in queue order, so it is
      CONCATENATED at its tail rather than re-queued statement by statement:
      prepending them one at a time reverses the order, and a literal's setup is
      order-dependent (build the list, then append to it). }
    if argHoist >= 0 then
    begin
      hoistSeq := argHoist;
      while ASTRight[hoistSeq] >= 0 do hoistSeq := ASTRight[hoistSeq];
      ASTRight[hoistSeq] := assignG;
      assignG := argHoist;
    end;
    if nargs >= 1 then
    begin
      if PyGenArgNeedsCell(gpi, 1) then a0 := GenMakeVariantArgCell(a0, assignG);
      assignG := GenMakeSeq(assignG, GenMakeSeq(GenSlSetStmt2(gIdx, SL_OFF_SLOTS + 0, a0), -1));
    end;
    if nargs >= 2 then
    begin
      if PyGenArgNeedsCell(gpi, 2) then a1 := GenMakeVariantArgCell(a1, assignG);
      assignG := GenMakeSeq(assignG, GenMakeSeq(GenSlSetStmt2(gIdx, SL_OFF_SLOTS + 8, a1), -1));
    end;
    if nargs >= 3 then
    begin
      if PyGenArgNeedsCell(gpi, 3) then a2 := GenMakeVariantArgCell(a2, assignG);
      assignG := GenMakeSeq(assignG, GenMakeSeq(GenSlSetStmt2(gIdx, SL_OFF_SLOTS + 16, a2), -1));
    end;
    if nargs >= 4 then
    begin
      if PyGenArgNeedsCell(gpi, 4) then a3 := GenMakeVariantArgCell(a3, assignG);
      assignG := GenMakeSeq(assignG, GenMakeSeq(GenSlSetStmt2(gIdx, SL_OFF_SLOTS + 24, a3), -1));
    end;
    if nargs >= 5 then
    begin
      if PyGenArgNeedsCell(gpi, 5) then a4 := GenMakeVariantArgCell(a4, assignG);
      assignG := GenMakeSeq(assignG, GenMakeSeq(GenSlSetStmt2(gIdx, SL_OFF_SLOTS + 32, a4), -1));
    end;
    if nargs >= 6 then
    begin
      if PyGenArgNeedsCell(gpi, 6) then a5 := GenMakeVariantArgCell(a5, assignG);
      assignG := GenMakeSeq(assignG, GenMakeSeq(GenSlSetStmt2(gIdx, SL_OFF_SLOTS + 40, a5), -1));
    end;

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
    sa1 := -1; sa2 := -1; sa3 := -1; sa4 := -1; sa5 := -1; sa6 := -1;
    if ProcGenParamCnt[gpi] >= 1 then
      if Procs[gpi].Params[1].IsRef then sa1 := GenMakeIdent(gIdx, tyPointer) else sa1 := GenZeroLit;
    if ProcGenParamCnt[gpi] >= 2 then
      if Procs[gpi].Params[2].IsRef then sa2 := GenMakeIdent(gIdx, tyPointer) else sa2 := GenZeroLit;
    if ProcGenParamCnt[gpi] >= 3 then
      if Procs[gpi].Params[3].IsRef then sa3 := GenMakeIdent(gIdx, tyPointer) else sa3 := GenZeroLit;
    if ProcGenParamCnt[gpi] >= 4 then
      if Procs[gpi].Params[4].IsRef then sa4 := GenMakeIdent(gIdx, tyPointer) else sa4 := GenZeroLit;
    if ProcGenParamCnt[gpi] >= 5 then
      if Procs[gpi].Params[5].IsRef then sa5 := GenMakeIdent(gIdx, tyPointer) else sa5 := GenZeroLit;
    if ProcGenParamCnt[gpi] >= 6 then
      if Procs[gpi].Params[6].IsRef then sa6 := GenMakeIdent(gIdx, tyPointer) else sa6 := GenZeroLit;
    callNext := GenMakeCall8(gpi, tyBoolean, GenMakeIdent(gIdx, tyPointer),
                             sa1, sa2, sa3, sa4, sa5, sa6, -1);
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
    else if ProcGenElemTk[gpi] = tyVariant then
    begin
      { Variant element — every Nil Python generator. Same indirection as the
        record case (CURRENT holds the region's address), but the copy out is an
        ordinary variant assignment, so the loop variable retains it properly. }
      curDeref := AllocNode(AN_DEREF);
      ASTLeft[curDeref] := callCur;
      ASTTk[curDeref] := Ord(tyVariant);
      assignX := GenMakeAssign(GenMakeIdent(varIdx, Syms[varIdx].TypeKind), curDeref);
    end
    else
      assignX := GenMakeAssign(GenMakeIdent(varIdx, Syms[varIdx].TypeKind), callCur);

    { A TUPLE loop target — `for a, b, c in gen():` — binds the yielded element
      to a hidden name and then unpacks it. The unpack statements are built by
      the frontend (only it knows how to index a Python tuple) and run here,
      between the element assignment and the body. }
    innerSeq := GenMakeSeq(assignX,
                  chainSeqFwd(elemPrologue, GenMakeSeq(bodyNode, -1)));
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
var pri, fIdx, i, fnode: Integer; mname: AnsiString; eTk: TTypeKind;
begin
  { The enumerator var is a record VALUE (advancedrecords enumerator) or a class
    pointer — read its Current field/getter through the matching receiver kind so
    an AN_FIELD over a record takes @eSym+off rather than dereferencing a pointer. }
  eTk := Syms[eSym].TypeKind;
  pri := FindUProp(enumIdx, 'Current');
  if pri >= 0 then
  begin
    if UPropReadMLen[pri] > 0 then
    begin
      mname := '';
      for i := 0 to UPropReadMLen[pri] - 1 do AppendChar(mname, TokChars[UPropReadMOff[pri] + i]);
      Result := GenMakeMethodCall0(GenMakeIdent(eSym, eTk), enumIdx, mname);
      Exit;
    end
    else if UPropReadFLen[pri] > 0 then
    begin
      fnode := AllocNode(AN_FIELD);
      ASTLeft[fnode] := GenMakeIdent(eSym, eTk);
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
  ASTLeft[fnode] := GenMakeIdent(eSym, eTk);
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
  contTk, eTk: TTypeKind;
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

  { A record enumerator (FPC advancedrecords: GetEnumerator returns a record by
    value) is held as an embedded record VALUE — `__e := C.GetEnumerator` is a
    record-copy and `__e.MoveNext` / `__e.Current` take @__e as Self. Modelling it
    as tyClass (a pointer) made MoveNext mutate/read through a stale temp pointer,
    so the loop ran zero times (tforin25). A real class enumerator stays tyClass. }
  if UClsIsRecord[enumIdx] then eTk := tyRecord else eTk := tyClass;

  if eTk = tyRecord then LastTypeRecId := enumRec;   { AllocVar sizes tyRecord by RecSize(LastTypeRecId) }
  eSym := AllocVar('', eTk);
  Syms[eSym].RecName := enumRec;
  SymSyncTypeRef(eSym);

  geCall := GenMakeMethodCall0(GenMakeIdent(contSym, contTk), contClassIdx, 'GetEnumerator');
  assignE := GenMakeAssign(GenMakeIdent(eSym, eTk), geCall);

  mnCall := GenMakeMethodCall0(GenMakeIdent(eSym, eTk), enumIdx, 'MoveNext');

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

{ for X in C do BODY where the container's TYPE has an `operator enumerator`
  overload (tforin5): same protocol as GetEnumerator, but the enumerator
  comes from the operator call:
    __e := EnumOp(C);
    while __e.MoveNext do begin X := __e.Current; BODY end;  [finally Free] }
function ParseForInOpEnumeratorAST(varIdx, contSym, opPi: Integer): Integer;
var
  bodyNode, enumRec, enumIdx, eSym: Integer;
  argSeq, geCall, assignE, mnCall, curNode, assignX, innerSeq, whileNode: Integer;
  freeCall, tryNode: Integer;
begin
  if Syms[varIdx].TypeKind = tyAuto then
    Error('for var .. in <operator enumerator>: declare the loop variable explicitly');
  Expect(tkDo, 'do');
  bodyNode := ParseStatementAST;

  enumRec := ProcRetRecId[opPi];
  if enumRec < REC_UCLASS_BASE then Error('for-in: operator enumerator must return a class/record');
  enumIdx := enumRec - REC_UCLASS_BASE;

  eSym := AllocVar('', tyClass);
  Syms[eSym].RecName := enumRec;
  SymSyncTypeRef(eSym);

  argSeq := AllocNode(AN_ARG);
  ASTLeft[argSeq] := GenMakeIdent(contSym, Syms[contSym].TypeKind);
  geCall := AllocNode(AN_CALL);
  ASTIVal[geCall] := opPi;
  ASTTk[geCall] := Ord(Procs[opPi].RetType);
  ASTLeft[geCall] := argSeq;
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
    X := lo - 1;
    while X < hi do begin X := X + 1; if X in S then BODY; end;
  X (the loop var) doubles as the scan ordinal. Range from the set element type:
  `set of <enum>` → the enum's ordinal range; `set of Char` → 0..255. }
{ Shared membership-scan builder for `for x in <set>`. The set source is an
  abstract value node (setOperand) — a plain `set var` ident (ParseForInSetAST)
  or a qualified member-access lvalue (ParseForInNodeAST). The element range is
  given by setEnumId (`set of <enum>` → its ordinal range) or setElemTk = tyChar
  (`set of Char` → 0..255). bodyNode is the already-parsed loop body. }
function BuildForInSetLoop(varIdx, setEnumId, setElemTk, setOperand, bodyNode: Integer): Integer;
var
  loV, hiV, vtk, oSym, isChar: Integer;
  initN, scanCond, condIn, pairN, ifN, incN, innerSeq, whileN: Integer;
  valNode, assignE, chrArg: Integer;
begin
  isChar := 0;
  if setEnumId >= 0 then
    EnumTypeOrdRange(setEnumId, loV, hiV)
  else if setElemTk = Ord(tyChar) then
  begin loV := 0; hiV := 255; isChar := 1; end
  else if TypeIsOrdinal(IntToTypeKind(setElemTk)) then
    { An ORDINAL-element set — what a bare `[5, 1, 3, 2]` constructor is. The
      set domain here is 0..255 (the `in` codegen refuses anything above), so
      that is the scan range, and iteration comes out in ORDINAL order, which is
      what FPC does with the same construct: `for i in [5,1,3,2]` prints 1 2 3 5,
      not 5 1 3 2.
      bug-a-for-in-refuses-a-set-constructor-and-a-string-literal }
  begin loV := 0; hiV := 255; end
  else
    Error('for-in: set iteration supports `set of <enum>`, `set of Char` or an '
          + 'ordinal set constructor');

  { Scan with a separate Integer ordinal so the `<= hi` test cannot wrap on a
    narrow loop var (a Char counter overflows 255 -> 0 and loops forever). }
  oSym := AllocVar('', tyInteger);
  vtk := Ord(Syms[varIdx].TypeKind);
  { …and it starts ONE BELOW the range, advancing at the TOP of the body, for
    the same reason BuildForInArrayLoop does: AN_WHILE's continue target is the
    condition test, so an increment at the bottom is unreachable from a
    `Continue` and the loop spins forever. `for e in st do if e = gn then
    Continue` HUNG, as did the set-constructor form.
    bug-a-continue-in-a-for-in-loop-never-advances }
  initN := GenMakeAssign(GenMakeIdent(oSym, tyInteger), GenMakeIntLit(loV - 1));
  scanCond := GenMakeBinop(tkLt, GenMakeIdent(oSym, tyInteger), GenMakeIntLit(hiV), tyBoolean);

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
  { advance FIRST — see initN above }
  innerSeq := GenMakeSeq(incN, GenMakeSeq(assignE, GenMakeSeq(ifN, -1)));
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
    SymSyncTypeRef(varIdx);
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
  staticLen, elemTk, bodyNode: Integer; idxScale, staticLo: Integer): Integer;
var
  idxSym, loNode, hiNode, condNode, elemAccess, idxNode: Integer;
  assignX, incNode, whileNode, innerSeq, initI: Integer;
begin
  idxSym := AllocVar('', tyInteger);
  if isString then loNode := GenMakeIntLit(1)
  else if isStaticArr then
    { iterate the array's OWN index range: `for i in r` over array[1..3] /
      array[5..7] used a hardwired 0..count-1 and read SHIFTED garbage,
      silently (bug-pascal-forin-variants-wrong-output / tforin14). AN_INDEX
      subtracts the low bound itself, so __i in [lo..hi] is the correct
      domain. Dynamic/open arrays stay 0-based (staticLo = 0 there). }
    loNode := GenMakeIntLit(staticLo)
  else if isArr then loNode := GenMakeIntLit(0)
  else begin Error('for-in: variable is not a string or array'); loNode := GenMakeIntLit(0); end;
  { __i starts ONE BEFORE the low bound and is advanced at the TOP of the body,
    not the bottom. The bottom form is the obvious desugar and it makes
    `Continue` an infinite loop: AN_WHILE's continue target is the condition
    test, so a Continue jumps over the increment and re-runs the same element
    forever. `for n in dy do if Odd(n) then Continue` HUNG.
    The C frontend hit the identical problem with `for(init; cond; post)` and
    solved it with a first-iteration flag; this needs no flag, because the
    counter is ours and starting it one low costs nothing. The condition moves
    from `__i <= hi` to `__i < hi` to match.
    bug-a-continue-in-a-for-in-loop-never-advances }
  initI := GenMakeAssign(GenMakeIdent(idxSym, tyInteger),
             GenMakeBinop(tkMinus, loNode, GenMakeIntLit(1), tyInteger));

  if isStaticArr then
    hiNode := GenMakeIntLit(staticLo + staticLen - 1)
  else if isString then
    hiNode := GenMakeLengthCallNode(GenMakeContainerNode(ckind, csym, cselfSym, cfOff, cfLen, ctemplate, contTk))
  else
    hiNode := GenMakeBinop(tkMinus,
      GenMakeLengthCallNode(GenMakeContainerNode(ckind, csym, cselfSym, cfOff, cfLen, ctemplate, contTk)),
      GenMakeIntLit(1), tyInteger);

  condNode := GenMakeBinop(tkLt, GenMakeIdent(idxSym, tyInteger), hiNode, tyBoolean);

  elemAccess := AllocNode(AN_INDEX);
  ASTLeft[elemAccess] := GenMakeContainerNode(ckind, csym, cselfSym, cfOff, cfLen, ctemplate, contTk);
  { idxScale > 1: an N-D container iterated by ROW — the flat index of row
    __i's first element is __i * rowElemCount (the container stays flattened,
    the assign's dest size copies the whole row). }
  if idxScale > 1 then
    idxNode := GenMakeBinop(tkStar,
                 GenMakeBinop(tkMinus, GenMakeIdent(idxSym, tyInteger),
                              GenMakeIntLit(staticLo), tyInteger),
                 GenMakeIntLit(idxScale), tyInteger)
  else
    idxNode := GenMakeIdent(idxSym, tyInteger);
  ASTRight[elemAccess] := idxNode;
  ASTTk[elemAccess] := elemTk;
  assignX := GenMakeAssign(GenMakeIdent(varIdx, Syms[varIdx].TypeKind), elemAccess);

  incNode := GenMakeAssign(GenMakeIdent(idxSym, tyInteger),
    GenMakeBinop(tkPlus, GenMakeIdent(idxSym, tyInteger), GenMakeIntLit(1), tyInteger));

  { advance FIRST, then read the element — see initI above }
  innerSeq := GenMakeSeq(incNode, GenMakeSeq(assignX, GenMakeSeq(bodyNode, -1)));
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

  { `operator enumerator (c: TCont): TEnum` overload for the container type —
    same duck-typed MoveNext/Current protocol over the operator's result. }
  if not Syms[contSym].IsArray then
  begin
    if TypeIsFrozenString(Syms[contSym].TypeKind) or
       (Syms[contSym].TypeKind = tyAnsiString) then
      elemTk := FindOpOverload(OPK_ENUMERATOR, Ord(Syms[contSym].TypeKind), REC_NONE)
    else
      elemTk := FindOpOverload(OPK_ENUMERATOR, Ord(Syms[contSym].TypeKind),
                               Syms[contSym].RecName);
    if elemTk >= 0 then
    begin
      Result := ParseForInOpEnumeratorAST(varIdx, contSym, elemTk);
      Exit;
    end;
  end;

  contTk := Syms[contSym].TypeKind;
  { A real string container is a non-array string var. For `array of String` /
    `array of AnsiString` the var's TypeKind is the element base type
    (tyAnsiString), so the array check MUST win — otherwise it is mis-iterated
    char-by-char. }
  isString := (not Syms[contSym].IsArray) and ((contTk = tyString) or (contTk = tyAnsiString));
  { An open-array param keeps AllocParam's ArrLen=1000 placeholder — its real
    length lives at [data-8] like a dyn array's, so it must take the runtime
    Length bound, not a fake static one (`for r in a` over a 2-element open
    array ran 1000 iterations; tforin14). A NAMED fixed-array param has its
    true ArrLen stamped and stays static. }
  isStaticArr := Syms[contSym].IsArray and (Syms[contSym].ArrLen >= 0) and
                 not ((Syms[contSym].Kind = skParam) and (Syms[contSym].ArrLen = 1000));

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
    SymSyncTypeRef(varIdx);
  end;

  Expect(tkDo, 'do');
  bodyNode := ParseStatementAST;

  { An N-D static array iterates its OUTER dimension only — ArrLen is the
    FLATTENED element count, so `for r in a` over array[0..1] of array[1..3]
    ran SIX iterations of garbage rows instead of two
    (bug-pascal-forin-variants-wrong-output / tforin14). Each element is a
    row; `r := a[__i]` already row-copies. }
  if isStaticArr and (SymArrNDims[contSym] >= 2) then
    Result := BuildForInArrayLoop(varIdx, 0, contSym, -1, 0, 0, -1, contTk,
      isString, isStaticArr, Syms[contSym].IsArray,
      SymArrDimSpan[contSym * MAX_ARR_DIMS + 0], elemTk, bodyNode,
      Syms[contSym].ArrLen div SymArrDimSpan[contSym * MAX_ARR_DIMS + 0],
      SymArrDimLo[contSym * MAX_ARR_DIMS + 0])
  else
    Result := BuildForInArrayLoop(varIdx, 0, contSym, -1, 0, 0, -1, contTk,
      isString, isStaticArr, Syms[contSym].IsArray,
      Syms[contSym].ArrLen, elemTk, bodyNode, 1,
      Integer(Syms[contSym].ConstVal));
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
    SymSyncTypeRef(varIdx);
  end;

  Expect(tkDo, 'do');
  bodyNode := ParseStatementAST;

  Result := BuildForInArrayLoop(varIdx, 1, -1, selfSym, fOff, fLen, -1, contTk,
    isString, isStaticArr, isArr, staticLen, elemTk, bodyNode, 1, 0);
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
  fnRec, fnSym, fnAssign, fnLoop, fnSeq: Integer;   { class container w/ GetEnumerator }
  bodyNode, elemTk, staticLen, recId, fldIdx: Integer;
  setEnumId, setElemTk: Integer;
  contTk: TTypeKind;
  isString, isStaticArr, isArr: Boolean;
  fname: AnsiString;
begin
  { A CLASS container with GetEnumerator, reached through a QUALIFIED source:
    `for x in o.Bag do` (Bag a property), `for x in rec.List do`.

    This function is the qualified-source path, and it only ever knew arrays, strings and sets
    -- so a class node fell through to "for-in: variable is not a string or array". The
    enumerator protocol was already implemented (ParseForInEnumeratorAST); it just needed a
    container SYMBOL, which a qualified source has not got.

    Materialise the node into a hidden local and drive the existing loop with that. The
    container is evaluated exactly ONCE, which a property getter with side effects requires. }
  fnRec := ResolveNodeRec(contNode);
  if (fnRec >= REC_UCLASS_BASE) and (not UClsIsRecord[fnRec - REC_UCLASS_BASE]) and
     (FindUMeth(fnRec - REC_UCLASS_BASE, 'GetEnumerator') >= 0) then
  begin
    fnSym := AllocVar('', tyClass);
    Syms[fnSym].RecName := fnRec;
    SymSyncTypeRef(fnSym);
    fnAssign := GenMakeAssign(GenMakeIdent(fnSym, tyClass), contNode);
    fnLoop := ParseForInEnumeratorAST(varIdx, fnSym, fnRec - REC_UCLASS_BASE);
    Result := AllocNode(AN_SEQ);
    ASTLeft[Result] := fnAssign;
    fnSeq := AllocNode(AN_SEQ);
    ASTLeft[fnSeq] := fnLoop;
    ASTRight[fnSeq] := -1;
    ASTRight[Result] := fnSeq;
    Exit;
  end;

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
      SymSyncTypeRef(varIdx);
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
    SymSyncTypeRef(varIdx);
  end;

  Expect(tkDo, 'do');
  bodyNode := ParseStatementAST;

  Result := BuildForInArrayLoop(varIdx, 2, -1, -1, 0, 0, contNode, contTk,
    isString, isStaticArr, isArr, staticLen, elemTk, bodyNode, 1, 0);
end;

{ for x in <EnumType> do BODY iterates ALL enum ordinals low..high, as
    __i := -1; while __i < count-1 do begin __i := __i + 1; x := __i; BODY; end
  The advance is at the TOP and driven by a hidden counter — see the comment on
  the body below, and BuildForInArrayLoop, which has the identical shape for the
  identical reason (Continue). }
function ParseForInEnumTypeAST(varIdx, etid: Integer): Integer;
var
  bodyNode, initN, condN, incN, whileN, innerSeq, idxSym, assignE: Integer;
  cnt, vtk: Integer;
begin
  { Inline `for var x in TEnum`: enums are ordinal/integer-sized (no distinct
    tyEnum), so backfilling x's type is just tyInteger, mirroring the
    resolution ParseTypeKind already uses for a named enum type
    (feature-inline-loop-var-rio). }
  if Syms[varIdx].TypeKind = tyAuto then
  begin
    Syms[varIdx].TypeKind := tyInteger;
    SymSyncTypeRef(varIdx);
  end;
  Expect(tkDo, 'do');
  bodyNode := ParseStatementAST;

  cnt := EnumTypeValCount[etid];
  vtk := Ord(Syms[varIdx].TypeKind);
  { Same shape as BuildForInArrayLoop, and for the same reason: advance at the
    TOP so `Continue` — whose target is AN_WHILE's condition test — cannot skip
    it and spin forever. `for e in TC do if e = gn then Continue` HUNG.
    A HIDDEN Integer counter drives it rather than the loop variable itself, so
    the user's enum variable never momentarily holds -1 (out of range for its
    type, and a trap waiting for {$R+}); it is assigned from the counter at the
    top of each iteration, exactly as the array loop assigns its element. That
    also leaves the variable at the LAST enum value after a normal exit instead
    of one past the end, which is the more defensible of the two.
    bug-a-continue-in-a-for-in-loop-never-advances }
  idxSym := AllocVar('', tyInteger);
  initN := GenMakeAssign(GenMakeIdent(idxSym, tyInteger), GenMakeIntLit(-1));
  condN := GenMakeBinop(tkLt, GenMakeIdent(idxSym, tyInteger),
                        GenMakeIntLit(cnt - 1), tyBoolean);
  incN := GenMakeAssign(GenMakeIdent(idxSym, tyInteger),
    GenMakeBinop(tkPlus, GenMakeIdent(idxSym, tyInteger),
                 GenMakeIntLit(1), tyInteger));
  assignE := GenMakeAssign(GenMakeIdent(varIdx, IntToTypeKind(vtk)),
                           GenMakeIdent(idxSym, tyInteger));
  innerSeq := GenMakeSeq(incN, GenMakeSeq(assignE, GenMakeSeq(bodyNode, -1)));
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

  { Managed-field finalization (PXXClassFinalize) is injected at the IR lowering
    of the FreeMem intrinsic when its argument is class-typed — parse-time
    FindProc cannot see builtin procs yet
    (bug-a-class-managed-fields-not-finalized-on-destroy). }
  thenSeq := freeCall;
  if (ci >= 0) and (FindUMeth(ci, 'Destroy') >= 0) then
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

{ The instance's CURRENT region as a VARIANT lvalue: `PVariant(self + off)^`.
  Used for a variant element type, where the one-word CURRENT slot cannot carry
  the value. Assigning through this deref goes down the ordinary managed-variant
  assignment path, so the previous element is released and the new one retained
  — a blob copy (what the RECORD element does) would be ARC-blind and hand the
  consumer a pointer whose payload the step function's own cleanup had freed. }
function GenMakeVariantAt(selfSym, off: Integer): Integer;
begin
  Result := AllocNode(AN_DEREF);
  ASTLeft[Result] := GenMakeArith(Ord(tkPlus),
                       GenMakeIdent(selfSym, tyPointer), GenMakeIntLit(off));
  ASTTk[Result] := Ord(tyVariant);
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
      if Syms[i].IsRef or (Syms[i].TypeKind = tyString) or
         (Syms[i].TypeKind = tyAnsiString) then
        { by-ref param: the caller ADDRESS. Managed string: the handle. Either
          way ONE raw word, moved without touching a reference count. }
        stmt := GenSlSetStmt(selfSym, SL_OFF_SLOTS + 8 * SymGenSlot[i],
                             GenMakeSlotWord(i))
      else if Syms[i].TypeKind = tyVariant then
        stmt := GenMakeCall6(FindProc('SlBlob'), tyInt64,
                  GenMakeIdent(selfSym, tyPointer),
                  GenMakeIntLit(SL_OFF_SLOTS + 8 * SymGenSlot[i]),
                  GenMakeSlotAddr(i),
                  GenMakeIntLit(16), -1, -1)
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
      if Syms[i].IsRef or (Syms[i].TypeKind = tyString) or
         (Syms[i].TypeKind = tyAnsiString) then
        stmt := GenMakeAssign(GenMakeSlotWord(i),
                              GenSlGet(selfSym, SL_OFF_SLOTS + 8 * SymGenSlot[i]))
      else if Syms[i].TypeKind = tyVariant then
        stmt := GenMakeCall6(FindProc('SlUnblob'), tyInt64,
                  GenMakeIdent(selfSym, tyPointer),
                  GenMakeIntLit(SL_OFF_SLOTS + 8 * SymGenSlot[i]),
                  GenMakeSlotAddr(i),
                  GenMakeIntLit(16), -1, -1)
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
  materialised into a hidden temp at the yield parse site, pasparser_*.inc ~8690) —
  blob-copy its bytes into the instance CURRENT region and publish the region's
  address in the CURRENT word. }
function SLLowerYield(node, selfSym, retSym: Integer): Integer;
var k, resumeLbl, setCur, setState, saveSeq, setRes, exitNode: Integer;
begin
  k := CurGenStateCtr; Inc(CurGenStateCtr);
  if k >= MAX_GEN_STATES then Error('stackless generator: too many yields');
  resumeLbl := NewSyntheticLabel;
  GenStateLabelIdx[k] := resumeLbl;

  if CurGenElemIsVariant then
  begin
    { variant element: assign into the instance region (ARC-correct), then
      publish the region's address in the CURRENT word. }
    setCur := GenMakeAssign(GenMakeVariantAt(selfSym, CurGenElemOff), ASTLeft[node]);
    setCur := GenMakeSeq(setCur,
              GenMakeSeq(GenSlSetStmt(selfSym, SL_OFF_CURRENT,
                GenMakeArith(Ord(tkPlus),
                  GenMakeIdent(selfSym, tyPointer),
                  GenMakeIntLit(CurGenElemOff))), -1));
  end
  else if CurGenElemOff >= 0 then
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
{ Any persistent slot in the current generator scope that is checkpointed by
  BLOB copy — a record local, or a variant one (every Nil Python generator has
  those). Both need slgen's SlBlob/SlUnblob. }
function SLHasRecordSlot: Boolean;
var i: Integer;
begin
  Result := False;
  for i := CurGenScopeBase to SymCount - 1 do
    if (SymGenSlot[i] >= 0) and (not Syms[i].IsArray) and (not Syms[i].IsRef) and
       ((Syms[i].TypeKind = tyRecord) or (Syms[i].TypeKind = tyVariant)) then
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
  CurGenElemIsVariant := False;
  if ProcGenElemTk[procIdx] = tyRecord then
  begin
    CurGenElemRecId := ProcGenElemRec[procIdx];
    CurGenElemOff := SL_OFF_SLOTS + 8 * CurGenSlotNext;
    Inc(CurGenSlotNext, (RecSize(CurGenElemRecId) + 7) div 8);
  end
  else if ProcGenElemTk[procIdx] = tyVariant then
  begin
    { A variant is a 16-byte {tag, payload} pair and does not fit the CURRENT
      word, so it gets a two-slot region at the instance tail like a record —
      but written by assignment, not by blob copy (see GenMakeVariantAt). Every
      Nil Python generator lands here, because Nil Python's values are variants. }
    CurGenElemIsVariant := True;
    CurGenElemOff := SL_OFF_SLOTS + 8 * CurGenSlotNext;
    Inc(CurGenSlotNext, 2);
  end;
  { Record locals / record element need the blob helpers (older slgen lacks them). }
  if ((CurGenElemOff >= 0) and not CurGenElemIsVariant) or SLHasRecordSlot then
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
    { A CELL-PROMOTED name (SymCellPtr) keeps its symbol but its storage is the
      heap cell, and every read and write already spells itself `cell^` — the
      frame slot is dead, so persisting it would checkpoint garbage. The cell
      POINTER is an ordinary pointer local and gets its own slot below, which is
      how a Nil Python generator persists a variant across a yield without this
      pass having to understand variant ARC. }
    if SymCellPtr[i] >= 0 then Continue;
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
    if tk = tyVariant then
    begin
      { A VARIANT is a 16-byte {tag, payload} pair, so it gets a two-word slot
        region and is checkpointed by BLOB COPY — bitwise, deliberately not by
        assignment. Bitwise is what makes it refcount-neutral: the value has
        exactly one live owner at a time (the frame while the step runs, the
        instance while it is suspended), and neither copy is ever released
        behind the other's back, because a generator step's epilogue does not
        release its locals at all (EmitManagedLocalCleanup). An ASSIGNMENT here
        would release whatever the destination happened to hold and retain the
        source, on a slot region that is raw bytes rather than a live variant.

        This is what a Nil Python generator body is made of: its named locals
        are variants and so are the hidden temps the desugars mint mid-body —
        which is why this cannot be solved on the frontend side by promoting
        the ones it can see. }
      SymGenSlot[i] := CurGenSlotNext;
      Inc(CurGenSlotNext, 2);
      Continue;
    end;
    if (tk = tyString) or (tk = tyAnsiString) then
    begin
      { A managed STRING local is one pointer-sized handle. Persisted as a RAW
        WORD for the same reason a variant is blob-copied: bitwise moves keep
        the reference count untouched, where an assignment would release the
        destination's stale bytes. }
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
    if Syms[i].IsArray or (tk = tySet) then
      { NAME the local and its type kind. Without them this said only that some
        local somewhere in the body was of an unsupported kind, and the ones that
        actually trip it are HIDDEN desugar temps a reader cannot see in the
        source at all — so the message pointed at a generator whose every visible
        local was fine. The type kind is the ordinal because there is no
        kind-to-text helper in the compiler; it is still the fastest way to tell
        a string temp from a set temp. }
      Error('stackless generator: local `' + Syms[i].Name + '` (type kind ' +
            AIntToStr(Ord(tk)) + ') is not supported — only ordinal, pointer '
            + 'and record locals persist across a yield '
            + '(arrays/strings/sets/variants pending)');
    SymGenSlot[i] := CurGenSlotNext;
    Inc(CurGenSlotNext);
  end;
end;

function ParseForStatementAST: Integer;
var forcNode, forcRec, forcSym, forcAssign, forcLoop: Integer;   { for-in over a container EXPRESSION }
    forcCtorTk: TTypeKind;   { non-ordinal loop var => `[...]` is an ARRAY constructor, not a set }
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
    { `for x in [ ... ]` — a SET CONSTRUCTOR, not a list: FPC iterates the
      MEMBERS in ordinal order (`[5,1,3,2]` gives 1 2 3 5), and so do we. Written
      as list iteration this would silently produce a different ORDER, which is
      the expensive kind of wrong.
      bug-a-for-in-refuses-a-set-constructor-and-a-string-literal }
    if CurTok.Kind = tkLBrack then
    begin
      { …but only when the LOOP VARIABLE is ORDINAL. FPC decides the bracket
        list's kind from the variable it is iterating into, not from the
        elements: with an ordinal variable `[...]` is a set (ordinal order),
        with anything else it is an ARRAY CONSTRUCTOR (source order). Measured
        against FPC 3.2.2, which is unambiguous about it — `for c: Char in
        ['b','a']` prints `a b` and `for s: AnsiString in ['b','a']` prints
        `b a`, the SAME literal read two ways.

        pxx keyed on the ELEMENT type instead and had no non-ordinal arm at
        all, so `for d in [1.5, 2.5, 3.5]` built a SET out of float bits: the
        loop ran ONCE and bound 0.0, losing the count and every value, while
        the integer, char and dynamic-array-of-Double forms beside it were
        right. `for s in ['abc','de']` did not compile.
        bug-p-for-in-over-a-float-array-constructor-iterates-once-with-zero }
      forcCtorTk := tyUnknown;
      if Syms[varIdx].TypeKind = tyAuto then
      begin
        { tyAuto is pxx's own extension, so there is no FPC answer to copy:
          infer from the first element, and keep the set reading for everything
          that is not plainly a float or a multi-character string — that is
          exactly today's behaviour for those. }
        if (TokPos < TokCount) and (Tokens[TokPos].Kind = tkFloat) then
          forcCtorTk := tyDouble
        else if (TokPos < TokCount) and (Tokens[TokPos].Kind = tkString) and
                (Tokens[TokPos].SLen <> 1) then
          forcCtorTk := tyAnsiString;
      end
      else if not TypeIsOrdinal(Syms[varIdx].TypeKind) then
        forcCtorTk := Syms[varIdx].TypeKind;
      if forcCtorTk <> tyUnknown then
      begin
        if Syms[varIdx].TypeKind = tyAuto then
        begin
          Syms[varIdx].TypeKind := forcCtorTk;
          SymSyncTypeRef(varIdx);
        end;
        forcNode := ParseArrayCtorAST(forcCtorTk, 0, 0);
        { a dyn-array temp holds the constructor, and the ordinary iterable-
          variable loop walks it — same shape the string-LITERAL arm below uses,
          so length and element load come from the one lowering. }
        LastTypeDynElemRowLen := 0;   { consumed + reset by AllocDynArray }
        LastTypeDynElemRowLo := 0;
        forcSym := AllocDynArray('', forcCtorTk, 1);
        forcAssign := GenMakeAssign(GenMakeIdent(forcSym, forcCtorTk), forcNode);
        { ParseForInVarAST consumes the `do` and the body itself, exactly as the
          string-LITERAL arm below relies on }
        forcLoop := ParseForInVarAST(varIdx, forcSym);
        Result := AllocNode(AN_SEQ);
        ASTLeft[Result] := forcAssign;
        forcNode := AllocNode(AN_SEQ);
        ASTLeft[forcNode] := forcLoop;
        ASTRight[forcNode] := -1;
        ASTRight[Result] := forcNode;
        Exit;
      end;
      forcNode := ParseSetLiteralAST;
      forcRec := Ord(tyInteger);            { element kind of the loop variable }
      if (ASTLeft[forcNode] >= 0) and
         (IntToTypeKind(ASTTk[ASTLeft[ASTLeft[forcNode]]]) = tyChar) then
        forcRec := Ord(tyChar);
      if Syms[varIdx].TypeKind = tyAuto then
      begin
        Syms[varIdx].TypeKind := IntToTypeKind(forcRec);
        SymSyncTypeRef(varIdx);
      end;
      Expect(tkDo, 'do');
      Result := BuildForInSetLoop(varIdx, -1, forcRec, forcNode, ParseStatementAST);
      Exit;
    end;
    { `for c in 'hello'` — a string LITERAL, in SOURCE order, exactly like the
      string-VARIABLE form that already worked. The two-spellings tell: only the
      variable form was ever implemented. }
    if CurTok.Kind = tkString then
    begin
      ParseExpr;
      forcNode := CurASTNode;
      if Syms[varIdx].TypeKind = tyAuto then
      begin
        Syms[varIdx].TypeKind := tyChar;
        SymSyncTypeRef(varIdx);
      end;
      forcSym := AllocVar('', tyAnsiString);
      forcAssign := GenMakeAssign(GenMakeIdent(forcSym, tyAnsiString), forcNode);
      forcLoop := ParseForInVarAST(varIdx, forcSym);
      Result := AllocNode(AN_SEQ);
      ASTLeft[Result] := forcAssign;
      forcNode := AllocNode(AN_SEQ);
      ASTLeft[forcNode] := forcLoop;
      ASTRight[forcNode] := -1;
      ASTRight[Result] := forcNode;
      Exit;
    end;
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
      Result := ParseForInGeneratorAST(varIdx, gpi, -1, -1);
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
    { iterable variable (string / array / dynarray / open-array param).

      Only a BARE one: `for x in o.Bag do` starts with an identifier too, and used to be
      grabbed here as the variable `o` -- which then failed with "variable is not a string or
      array" instead of reaching the container-expression path below. `do` immediately after
      the name is what says the container really is just this variable. }
    fsym := FindSym(CurTok.SVal);
    if (fsym >= 0) and (TokPos < TokCount) and (Tokens[TokPos].Kind = tkDo) then
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
    { GENERAL container EXPRESSION with a GetEnumerator: `for F in Data do` where Data is a
      PROPERTY (fcl-json's own suite), a field of another object, a function result -- anything
      that is not a bare variable and so has no symbol for the paths above to key on.

      Parse it as an expression, materialise it into a hidden local, and hand THAT to the
      existing enumerator loop. The container is evaluated exactly ONCE, which is both what FPC
      does and what a property getter with side effects requires. }
    ParseExpr;
    forcNode := CurASTNode;
    forcRec := ResolveNodeRec(forcNode);
    if (forcRec >= REC_UCLASS_BASE) and
       (FindUMeth(forcRec - REC_UCLASS_BASE, 'GetEnumerator') >= 0) then
    begin
      forcSym := AllocVar('', tyClass);
      Syms[forcSym].RecName := forcRec;
      SymSyncTypeRef(forcSym);
      forcAssign := GenMakeAssign(GenMakeIdent(forcSym, tyClass), forcNode);
      forcLoop := ParseForInEnumeratorAST(varIdx, forcSym, forcRec - REC_UCLASS_BASE);
      Result := AllocNode(AN_SEQ);
      ASTLeft[Result] := forcAssign;
      forcNode := AllocNode(AN_SEQ);
      ASTLeft[forcNode] := forcLoop;
      ASTRight[forcNode] := -1;
      ASTRight[Result] := forcNode;
      Exit;
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
var node, si, prevTok: Integer; neg, isChrFold: Boolean;
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
  else if (CurTok.Kind = tkIdent) and
          (CaseEqual(CurTok.SVal, 'ord') or CaseEqual(CurTok.SVal, 'chr') or
           CaseEqual(CurTok.SVal, 'succ') or CaseEqual(CurTok.SVal, 'pred') or
           CaseEqual(CurTok.SVal, 'length') or CaseEqual(CurTok.SVal, 'high') or
           CaseEqual(CurTok.SVal, 'low')) and
          (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
  begin
    { Ord('q')/Chr(n)/Length('s')/Succ(n)/Pred(n)/High(T)/Low(T) as a case
      label (compat-pascal-const-expr-ord-chr-succ) — `case KeyCode of
      Ord('q'): ...` is the ordinary way to write a key handler, and this
      function (unlike ConstEvalFactor, the const-DECLARATION evaluator
      those five already fold in) parses case labels with its own narrow
      grammar that never called into it. Delegate to ConstEval — same
      Int64-valued fold, no AST built for the inner expression — rather than
      duplicating the fold logic here. Only Chr's result is tagged tyChar,
      matching the single-char-string-literal case label a few lines up;
      everything else defaults like the plain-integer branch above. }
    isChrFold := CaseEqual(CurTok.SVal, 'chr');
    node := AllocNode(AN_INT_LIT);
    ASTIVal[node] := ConstEval();
    if isChrFold then ASTTk[node] := Ord(tyChar);
    Result := node;
    Exit;
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
  begin
    { A field width on a STRING used to be dropped here — silently, and for a
      LITERAL width too, so `write(f, s:5)` to a Text file wrote `ab` where FPC
      writes `   ab`. The value was handed straight through because a string
      needs no conversion; it still needs PADDING.
      bug-a-a-variable-field-width-is-refused-for-strings-and-needs-an-rtl-unit }
    pi := FindProc('StrStrW');
    if pi < 0 then Error('write(Text): StrStrW not loaded');
    Result := GenMakeCall6(pi, Procs[pi].RetType, exprNode,
                widthNode, -1, -1, -1, -1);
  end
  else if tk = tyBoolean then
  begin
    { ...and a Boolean must print FPC's TRUE/FALSE, not the ordinal StrInt
      would give it. The stdout literal-width path has always branched to text
      (IRLowerBoolWrite); this one fell into the ordinal arm below. }
    pi := FindProc('StrBool');
    if pi < 0 then Error('write(Text): StrBool not loaded');
    Result := GenMakeCall6(pi, Procs[pi].RetType, exprNode,
                widthNode, -1, -1, -1, -1);
  end
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
    { An UNSIGNED value goes through the unsigned formatter — StrInt printed
      values >= 2^63 with a minus sign (tint642's testioqword). This read
      `tk = tyUInt64`, which is one of the four spellings of an 8-byte unsigned:
      `write(f, pu)` with `pu: PtrUInt` (tyNativeUInt) still printed -1. The
      stdout path has always keyed on `not TypeSigned`, and that is the whole
      rule — a narrower unsigned is zero-extended and formats the same either
      way, so there is nothing left for a width test to add. }
    if not TypeSigned(tk) then pi := FindProc('StrQWord')
    else pi := FindProc('StrInt');
    if pi < 0 then Error('write(Text): StrInt not loaded');
    Result := GenMakeCall6(pi, Procs[pi].RetType, exprNode,
                widthNode, -1, -1, -1, -1);
  end
  else if tk = tyChar then
  begin
    { A Char is written as its CHARACTER, not its ordinal — which is exactly why
      the ordinal arm above excludes tyChar. Without this arm the exclusion fell
      straight through to the error below, so `write(f, 'a')` — a one-character
      literal IS a Char in Pascal — did not compile while `write(f, 'ab')` did.
      stdout has always accepted both. bug-p-writeln-text-rejects-char }
    pi := FindProc('StrChar');
    if pi < 0 then Error('write(Text): StrChar not loaded');
    Result := GenMakeCall6(pi, Procs[pi].RetType, exprNode,
                widthNode, -1, -1, -1, -1);
  end
  else
  begin
    Error('write(Text): unsupported argument type (string/Char/integer/float only)');
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

{ Rewrite `read[ln](f, dest0, dest1, ...)` over a Text handle into textfile RTL
  calls (one per destination). A STRING or NUMERIC destination takes a whole
  line (v1 is line-oriented there: read and readln map to the same line read); a
  CHAR destination takes exactly one character, which is what FPC does for every
  type and is the only shape where the read/readln difference is observable
  here — hence `isLn`. }
function ParseTextReadRest(isLn: Boolean; fileSym: Integer): Integer;
var procRead, procVal, procReadChar, callNode, destNode, headSeq, tailSeq, newSeq: Integer;
    trTmpSym, trCodeSym, trValTmp, trIdent, trAsn: Integer;
    trTk: TTypeKind;
    trLastWasChar: Boolean;
begin
  Next;  { consume the Text file identifier }
  procRead := FindProc('TextReadLn');
  if procRead < 0 then Error('read(Text): textfile RTL not loaded');
  headSeq := -1; tailSeq := -1; trLastWasChar := False;
  while Eat(tkComma) do
  begin
    ParseExpr; destNode := CurASTNode;
    trTk := IntToTypeKind(ASTTk[destNode]);
    if TypeIsFloat(trTk) or (TypeIsOrdinal(trTk) and (trTk <> tyChar)) then
    begin
      { readln(f, number): TextReadLn only reads STRINGS — the dest slot used
        to be handed over AS an AnsiString handle, silently corrupting it
        (tint642's testioqword). Read the line into a hidden string, then
        Val it into the destination with the same dispatch as a Val statement
        (ValQWord for a QWord dest; Int64 temp for a narrow ordinal so the
        8-byte var write cannot overrun). }
      if TypeIsFloat(trTk) then procVal := FindProc('ValFloat')
      else if trTk = tyUInt64 then procVal := FindProc('ValQWord')
      else procVal := FindProc('Val');
      if procVal < 0 then Error('read(Text): Val builtin not loaded');
      trTmpSym := AllocVar('', tyAnsiString);
      trCodeSym := AllocVar('', tyInteger);
      callNode := GenMakeCall6(procRead, tyUnknown, GenMakeIdent(fileSym, tyRecord),
                               GenMakeIdent(trTmpSym, tyAnsiString), -1, -1, -1, -1);
      newSeq := GenMakeSeq(callNode, -1);
      if headSeq = -1 then headSeq := newSeq else ASTRight[tailSeq] := newSeq;
      tailSeq := newSeq;
      trValTmp := -1;
      if TypeIsOrdinal(trTk) and (trTk <> tyUInt64) and (TypeSize(trTk) < 8) then
        trValTmp := AllocVar('', tyInt64);
      if trValTmp >= 0 then
        callNode := GenMakeCall6(procVal, Procs[procVal].RetType,
                                 GenMakeIdent(trTmpSym, tyAnsiString),
                                 GenMakeIdent(trValTmp, tyInt64),
                                 GenMakeIdent(trCodeSym, tyInteger), -1, -1, -1)
      else
        callNode := GenMakeCall6(procVal, Procs[procVal].RetType,
                                 GenMakeIdent(trTmpSym, tyAnsiString),
                                 destNode,
                                 GenMakeIdent(trCodeSym, tyInteger), -1, -1, -1);
      newSeq := GenMakeSeq(callNode, -1);
      ASTRight[tailSeq] := newSeq; tailSeq := newSeq;
      if trValTmp >= 0 then
      begin
        trIdent := AllocNode(AN_IDENT);
        ASTIVal[trIdent] := trValTmp; ASTTk[trIdent] := Ord(tyInt64);
        trAsn := AllocNode(AN_ASSIGN);
        ASTLeft[trAsn] := destNode; ASTRight[trAsn] := trIdent;
        newSeq := GenMakeSeq(trAsn, -1);
        ASTRight[tailSeq] := newSeq; tailSeq := newSeq;
      end;
      trLastWasChar := False;
    end
    else if trTk = tyChar then
    begin
      { ONE character, through the RTL's TextReadChar — not a line-read plus
        [1], which is right for the first read and wrong for every one after
        it. It shares the cursor with TextReadLn (both drain f.Peek first), so
        `read(f, c)` then `readln(f, s)` gives the REST of the line in s, and a
        line terminator is an ordinary character the way FPC hands it over.
        Until the RTL half landed this arm raised an error rather than fall
        into the string branch below, whose `var AnsiString` slot would have
        written a string handle into ONE BYTE. }
      procReadChar := FindProc('TextReadChar');
      if procReadChar < 0 then
        Error('read(Text): TextReadChar not in the textfile RTL');
      callNode := GenMakeCall6(procReadChar, tyUnknown, GenMakeIdent(fileSym, tyRecord),
                               destNode, -1, -1, -1, -1);
      newSeq := GenMakeSeq(callNode, -1);
      if headSeq = -1 then headSeq := newSeq else ASTRight[tailSeq] := newSeq;
      tailSeq := newSeq;
      trLastWasChar := True;
    end
    else
    begin
      callNode := GenMakeCall6(procRead, tyUnknown, GenMakeIdent(fileSym, tyRecord),
                               destNode, -1, -1, -1, -1);
      newSeq := GenMakeSeq(callNode, -1);
      if headSeq = -1 then headSeq := newSeq else ASTRight[tailSeq] := newSeq;
      tailSeq := newSeq;
      trLastWasChar := False;
    end;
  end;
  Expect(tkRParen, ')');
  { `readln` means "and then through the end of the line". The string and
    numeric arms already consume the terminator (TextReadLn eats it), so the
    skip is emitted ONLY when the LAST destination was the char arm — or when
    there were no destinations at all, `readln(f)`, which was a no-op. Measured
    against FPC 3.2.2 on 'ab'#10'cd'#10: two `readln(f, c)` give 'a' then 'c',
    not 'a' then 'b'; a bare `readln(f)` then `readln(f, s)` gives 'cd'.
    A blanket skip would eat a whole extra line after `readln(f, s)`. }
  if isLn and (trLastWasChar or (headSeq = -1)) then
  begin
    trTmpSym := AllocVar('', tyAnsiString);
    callNode := GenMakeCall6(procRead, tyUnknown, GenMakeIdent(fileSym, tyRecord),
                             GenMakeIdent(trTmpSym, tyAnsiString), -1, -1, -1, -1);
    newSeq := GenMakeSeq(callNode, -1);
    if headSeq = -1 then headSeq := newSeq else ASTRight[tailSeq] := newSeq;
    tailSeq := newSeq;
  end;
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
      Result := ParseTextReadRest(isLn, fileSym);
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
        { Strings, Chars and Booleans have formatters too (StrStrW / StrChar /
          StrBool) — they were simply not routed, so a VARIABLE width was
          refused for exactly the types the LITERAL-width path handles inline.
          Two paths disagreeing about what is writable, the recurring shape.
          bug-a-a-variable-field-width-is-refused-for-strings-and-needs-an-rtl-unit }
        if not (TypeIsFloat(IntToTypeKind(ASTTk[exprNode])) or
                TypeIsOrdinal(IntToTypeKind(ASTTk[exprNode])) or
                TypeIsFrozenString(IntToTypeKind(ASTTk[exprNode])) or
                (IntToTypeKind(ASTTk[exprNode]) = tyAnsiString)) then
          Error('write: a variable field width needs a string, Char, Boolean, '
                + 'integer or float value');
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
        SymSyncTypeRef(handlerVar);
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
    SymSyncTypeRef(wTmp);
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
        ParseArrayDimBounds(arrLo, arrHi);
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
      SymSyncTypeRef(idx);
    end;

    if Syms[idx].TypeKind = tyAuto then
    begin
      if ASTKind[valueNode] = AN_DEFAULT then
        Error('cannot infer type from default; specify type explicitly');
      if (LastExprTk = tyUnknown) or (LastExprTk = tyAuto) then
        Error('cannot infer type for auto variable');
      InferSymTypeFromNode(idx, valueNode);   { syncs SymTR internally }
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
        SymSyncTypeRef(idx);
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
  { TYPE the synthesised limit. Every other synthesiser in this parser stamps
    ASTTk on the AN_BINOP it mints (BuildFlatNDIndex is the model) because the
    IR lowering copies ASTTk[node] into the IR node VERBATIM — it never infers
    the type from the operands. Leaving it 0 handed the for-limit temp
    (`AllocVar('', IntToTypeKind(IRTk[limitValNode]))` in the AN_FOR lowering)
    the type tyUnknown, which x86-64 absorbed into its 8-byte slot and i386
    rightly refused: "a compiler-minted temporary reached codegen with an
    UNRESOLVED type". So `SetLength(m, 3, 5)` did not build for i386 at all.
    bug-a-i386-multidim-setlength-mints-an-untyped-temporary }
  limitN := AllocNode(AN_BINOP); ASTIVal[limitN] := Ord(tkMinus);
  ASTTk[limitN] := Ord(tyInteger);
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
  { the sibling arm of the same omission — see the note in BuildSetLenNest }
  limitN := AllocNode(AN_BINOP); ASTIVal[limitN] := Ord(tkMinus);
  ASTTk[limitN] := Ord(tyInteger);
  ASTLeft[limitN] := CloneAST(SetLenDimNode[0]);
  one := AllocNode(AN_INT_LIT); ASTIVal[one] := 1; ASTTk[one] := Ord(tyInteger);
  ASTRight[limitN] := one;
  lo := AllocNode(AN_INT_LIT); ASTTk[lo] := Ord(tyInteger);
  forN := MkForAsc(loopVar, lo, limitN, inner);
  Result := AllocNode(AN_SEQ); ASTLeft[Result] := outerCall; ASTRight[Result] := forN;
end;

{ ===== `parallel for` (feature-parallel-processing, Track A/P) =====
  Desugars at parse time — the only place this compiler can mint a proc — into a
  synthesized worker + a PXXParallelFor call that fans the range across the
  libc-free worker pool (lib/rtl/palparallel.pas).

      parallel for V := lo to hi do BODY
   ->
      procedure __pf_<n>(__pfctx: Pointer; __pflo, __pfhi: NativeInt);
      var V: NativeInt; begin for V := __pflo to __pfhi do BODY end;
      ... PXXParallelFor(lo, hi, @__pf_<n>, nil);

  v1: the body may reference the loop var + globals only; capturing an enclosing
  local is a clear error (full implicit capture follows). Must sit inside a
  routine (the main program body has no nested-proc flush point). Requires
  --threadsafe and `uses palparallel`. }

function PFScalarKw(tk: TTypeKind): AnsiString;
{ Type keyword for a scalar capture's `^T` accessor in the worker. '' = not a
  Phase-A scalar (record/class/array/string capture — rejected until Phase B). }
begin
  case tk of
    tyInteger, tyInt32: PFScalarKw := 'Integer';
    tyInt64:      PFScalarKw := 'Int64';
    tyBoolean:    PFScalarKw := 'Boolean';
    tyChar:       PFScalarKw := 'Char';
    tyInt8:       PFScalarKw := 'ShortInt';
    tyUInt8:      PFScalarKw := 'Byte';
    tyInt16:      PFScalarKw := 'SmallInt';
    tyUInt16:     PFScalarKw := 'Word';
    tyUInt32:     PFScalarKw := 'Cardinal';
    tyUInt64:     PFScalarKw := 'UInt64';
    tyNativeInt:  PFScalarKw := 'NativeInt';
    tyNativeUInt: PFScalarKw := 'NativeUInt';
    tyPointer:    PFScalarKw := 'Pointer';
    tySingle:     PFScalarKw := 'Single';
    tyDouble:     PFScalarKw := 'Double';
  else PFScalarKw := '';
  end;
end;

procedure PFSet(k: TTokenKind; so, sl, ln: Integer);
{ Emit one token into the PFScratch worker-header build buffer. }
begin
  if PFScratchN > High(PFScratch) then Error('parallel for: header token overflow');
  PFScratch[PFScratchN].Kind := k;
  PFScratch[PFScratchN].IVal := 0;
  PFScratch[PFScratchN].Line := ln;
  PFScratch[PFScratchN].SOffset := so;
  PFScratch[PFScratchN].SLen := sl;
  Inc(PFScratchN);
end;

procedure PFStash(k: TTokenKind; so, sl, ln: Integer);
{ Append a token to PendNestTok (the stashed worker body, flushed in pass 2). }
begin
  if PendNestCount >= MAX_NESTED_TOKENS then Error('parallel for: nested token buffer overflow');
  PendNestTok[PendNestCount].Kind := k;
  PendNestTok[PendNestCount].IVal := 0;
  PendNestTok[PendNestCount].Line := ln;
  PendNestTok[PendNestCount].SOffset := so;
  PendNestTok[PendNestCount].SLen := sl;
  Inc(PendNestCount);
end;

{ TParDist / TParWorkers value name -> ordinal (must match the enum order in
  lib/rtl/palparallel.pas). -1 = not that enum. Used to constant-fold the
  `parallel(...)` named-arg clause. }
function PFDistOrd(const s: AnsiString): Integer;
begin
  if CaseEqual(s, 'pdChunked') then PFDistOrd := 0
  else if CaseEqual(s, 'pdGuided') then PFDistOrd := 1
  else if CaseEqual(s, 'pdOnDemand') then PFDistOrd := 2
  else PFDistOrd := -1;
end;

function PFWorkersOrd(const s: AnsiString): Integer;
begin
  if CaseEqual(s, 'pwAllCores') then PFWorkersOrd := 0
  else if CaseEqual(s, 'pwFixed') then PFWorkersOrd := 1
  else if CaseEqual(s, 'pwLoadOnce') then PFWorkersOrd := 2
  else if CaseEqual(s, 'pwLoadCont') then PFWorkersOrd := 3
  else PFWorkersOrd := -1;
end;

{ True when a `parallel(` clause opens a NAMED-arg list (a key or a bare enum
  value) rather than a single TParPolicy expression (preset/var). }
function PFIsNamedPolicyStart(const s: AnsiString): Boolean;
begin
  PFIsNamedPolicyStart :=
    CaseEqual(s, 'cap') or CaseEqual(s, 'chunk') or CaseEqual(s, 'n') or
    CaseEqual(s, 'dist') or CaseEqual(s, 'workers') or
    (PFDistOrd(s) >= 0) or (PFWorkersOrd(s) >= 0);
end;

function ParseParallelFor: Integer;
const MAX_PFCAP = 32; MAX_REDVARS = 8;
var
  Vname, wname, capNm, kw: AnsiString;
  loNode, hiNode, bodyAst, node, callNode: Integer;
  a1, a2, a3, a4, procAddr, ctxNode: Integer;
  bodyStart, bodyEnd, i, j, si, scopeBase, ppi, workerIdx: Integer;
  savedTokPos, savedTokCount, ln: Integer;
  savedCurProc, savedSC, savedFS, savedSelf: Integer;
  wnameOff, wnameLen, ctxOff, loPOff, hiPOff, ptrOff, niOff, vOff, vLen: Integer;
  { captured enclosing scalars (Phase A: by-ref via the enclosing frame pointer) }
  capSi   : array[0..MAX_PFCAP-1] of Integer;   { Syms index }
  capNmOff: array[0..MAX_PFCAP-1] of Integer;   { name string-pool offset }
  capNmLen: array[0..MAX_PFCAP-1] of Integer;
  capKwOff: array[0..MAX_PFCAP-1] of Integer;   { type-keyword string-pool offset }
  capKwLen: array[0..MAX_PFCAP-1] of Integer;
  capOfs  : array[0..MAX_PFCAP-1] of Integer;   { rbp-relative frame offset }
  capHandle: array[0..MAX_PFCAP-1] of Boolean;  { dyn array / ansistring: value at frame slot is a HANDLE (needs an extra deref) }
  capCount, ci, absOff, ptrCastOff, niCastOff, pniOff: Integer;
  found: Boolean;
  policyNode, ppiP, a5, polAddr: Integer; hasPolicy: Boolean;
  { named-arg policy clause `parallel(dist pdX, cap N, ...)` -> constant-folded to
    five ints passed to PXXParallelForN. }
  hasNamedPolicy: Boolean; ppiN, o, an, ai, prevArg: Integer;
  polDistOrd, polWorkersOrd, polFixedN, polCapPct, polMinChunk: Integer;
  polVals: array[0..4] of Integer;
  polKey: AnsiString;
  { reduction(op: v, ...) — each captured scalar v gets a private __pfred<K>
    partial folded into v^ under PXXReduceLock after the loop. One entry per var;
    a clause with a comma-list = several entries sharing the op; repeated clauses
    = entries with different ops. }
  redN, rk, rj: Integer;
  redOpA: array[0..MAX_REDVARS-1] of TTokenKind;
  redIsMinMaxA, redIsMaxA, redIsAndA: array[0..MAX_REDVARS-1] of Boolean;
  redCapIdxA, red0OffA, redKwOffA, redKwLenA, redIdentValA: array[0..MAX_REDVARS-1] of Integer;
  redTypeTokA: array[0..MAX_REDVARS-1] of TTokenKind;
  redVarNameA: array[0..MAX_REDVARS-1] of AnsiString;
  redOpTok: TTokenKind; redThisMinMax, redThisMax, redThisAnd: Boolean; redThisIdent: Integer;
begin
  ln := CurTok.Line;
  Next;  { consume 'parallel' }

  { optional policy clause: parallel(P) for ... — P is a TParPolicy-typed lvalue
    (a preset like ParPolite, or a const/var); passed by address to
    PXXParallelForPP (feature-parallel-for-scheduling-policy). }
  hasPolicy := False; policyNode := -1; ppiP := -1;
  hasNamedPolicy := False; ppiN := -1;
  polDistOrd := 0; polWorkersOrd := 0; polFixedN := 0; polCapPct := 0; polMinChunk := 0;
  if CurTok.Kind = tkLParen then
  begin
    Next;  { consume '(' }
    if (CurTok.Kind = tkIdent) and PFIsNamedPolicyStart(CurTok.SVal) then
    begin
      { NAMED-ARG list: comma-separated `key value` pairs and/or bare enum values.
        keys: cap/chunk/n -> ints; dist/workers -> enum; bare pd*/pw* -> dist/workers. }
      hasNamedPolicy := True;
      while True do
      begin
        if CurTok.Kind <> tkIdent then Error('parallel(...): expected a policy key or value');
        polKey := CurTok.SVal;
        o := PFDistOrd(polKey);
        if o >= 0 then begin polDistOrd := o; Next; end
        else if PFWorkersOrd(polKey) >= 0 then begin polWorkersOrd := PFWorkersOrd(polKey); Next; end
        else if CaseEqual(polKey, 'dist') then
        begin
          Next; if CurTok.Kind <> tkIdent then Error('parallel(dist ...): expected pdChunked/pdGuided/pdOnDemand');
          o := PFDistOrd(CurTok.SVal); if o < 0 then Error('parallel(dist ...): unknown distribution');
          polDistOrd := o; Next;
        end
        else if CaseEqual(polKey, 'workers') then
        begin
          Next; if CurTok.Kind <> tkIdent then Error('parallel(workers ...): expected pwAllCores/pwFixed/pwLoadOnce/pwLoadCont');
          o := PFWorkersOrd(CurTok.SVal); if o < 0 then Error('parallel(workers ...): unknown worker mode');
          polWorkersOrd := o; Next;
        end
        else if CaseEqual(polKey, 'cap') then
        begin Next; if CurTok.Kind <> tkInteger then Error('parallel(cap ...): expected an integer'); polCapPct := CurTok.IVal; Next; end
        else if CaseEqual(polKey, 'chunk') then
        begin Next; if CurTok.Kind <> tkInteger then Error('parallel(chunk ...): expected an integer'); polMinChunk := CurTok.IVal; Next; end
        else if CaseEqual(polKey, 'n') then
        begin
          Next; if CurTok.Kind <> tkInteger then Error('parallel(n ...): expected an integer'); polFixedN := CurTok.IVal; Next;
          if polWorkersOrd = 0 then polWorkersOrd := 1;   { `n` implies pwFixed unless overridden }
        end
        else Error('parallel(...): unknown policy key ''' + polKey + '''');
        if CurTok.Kind = tkComma then Next else Break;
      end;
    end
    else
    begin
      ParseExpr; policyNode := CurASTNode;
      hasPolicy := True;
    end;
    Expect(tkRParen, ')');
  end;

  if CurTok.Kind <> tkFor then Error('parallel: expected `for`');
  Next;  { consume 'for' }

  if CurProc < 0 then
    Error('parallel for must be inside a procedure or function (not the main program body)');
  if not ThreadSafeMode then
    Error('parallel for requires --threadsafe or {$threadsafe on}: the default heap/ARC/console-I/O runtime is not thread-safe');
  ppi := FindProc('PXXParallelFor');
  if ppi < 0 then
    Error('parallel for: the palparallel unit is not in scope (add `uses palparallel;`)');
  if hasPolicy then
  begin
    ppiP := FindProc('PXXParallelForPP');
    if ppiP < 0 then
      Error('parallel(policy) for: palparallel too old (PXXParallelForPP not found)');
  end;
  if hasNamedPolicy then
  begin
    ppiN := FindProc('PXXParallelForN');
    if ppiN < 0 then
      Error('parallel(named args) for: palparallel too old (PXXParallelForN not found)');
  end;

  if CurTok.Kind <> tkIdent then Error('parallel for: expected loop variable');
  Vname := CurTok.SVal;
  Next;
  Expect(tkAssign, ':=');
  ParseExpr; loNode := CurASTNode;
  if CurTok.Kind = tkDownto then
    Error('parallel for: `downto` not supported (iteration order is unspecified) — use `to`');
  Expect(tkTo, 'to');
  ParseExpr; hiNode := CurASTNode;

  { optional `reduction(op: v, ...)` clause(s) between the range and `do`. Ops:
      + or xor  — private starts at identity 0, combined `v^ := v^ op partial`
      min max   — private starts at v^ (current), combined `if partial </> v^ ...`
    combined under PXXReduceLock. One entry per var; a comma-list shares the op;
    repeated `reduction(...)` clauses stack entries with different ops. NOTE `*` is
    NOT offered: `(*` is Pascal's comment opener, so `reduction(*:...)` lexes as a
    comment (`*`/`and` need a different spelling — follow-up). }
  redN := 0;
  while (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'reduction') do
  begin
    Next; Expect(tkLParen, '(');
    redThisMinMax := False; redThisMax := False; redThisAnd := False;
    redOpTok := tkPlus; redThisIdent := 0;
    if (CurTok.Kind = tkIdent) and (CaseEqual(CurTok.SVal, 'min') or CaseEqual(CurTok.SVal, 'max')) then
    begin
      redThisMinMax := True; redThisMax := CaseEqual(CurTok.SVal, 'max');
    end
    else if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'mul') then
    begin
      { `*` cannot be written here — `(*` is Pascal's comment opener — so multiply
        uses the word `mul`; it combines with a real tkStar mid-expression. }
      redOpTok := tkStar; redThisIdent := 1;
    end
    else
    begin
      redOpTok := CurTok.Kind;
      if (redOpTok = tkPlus) or (redOpTok = tkOr) or (redOpTok = tkXor) then redThisIdent := 0
      else if redOpTok = tkAnd then redThisAnd := True   { identity = all-ones / True, set per type at init }
      else Error('reduction: ops are + or xor and min max mul (not * / div mod; `(*` is a comment, and /,div,mod are not associative)');
    end;
    Next;
    Expect(tkColon, ':');
    { comma-list of vars sharing this op }
    while True do
    begin
      if CurTok.Kind <> tkIdent then Error('reduction: expected a variable name');
      if redN >= MAX_REDVARS then Error('reduction: too many reduction variables (max 8)');
      for rj := 0 to redN - 1 do
        if CaseEqual(redVarNameA[rj], CurTok.SVal) then
          Error('reduction: variable ''' + CurTok.SVal + ''' appears in more than one reduction');
      redVarNameA[redN] := CurTok.SVal;
      redOpA[redN] := redOpTok;
      redIsMinMaxA[redN] := redThisMinMax; redIsMaxA[redN] := redThisMax;
      redIsAndA[redN] := redThisAnd;
      redIdentValA[redN] := redThisIdent;
      redCapIdxA[redN] := -1;
      red0OffA[redN] := NestStrOff('__pfred' + Chr(Ord('0') + redN));   { 8 chars }
      Inc(redN);
      Next;
      if CurTok.Kind = tkComma then Next else Break;
    end;
    Expect(tkRParen, ')');
  end;

  Expect(tkDo, 'do');

  { Reject a NESTED `parallel for` (Phase A): peek the body statement's token span
    (begin/end-depth aware) for a `parallel`+`for` before consuming it — otherwise
    the inner one would recursively desugar during the outer's body-span parse and
    double-process. Peek only; ParseStatementAST below re-reads from here. }
  i := TokPos - 1;
  if Tokens[i].Kind = tkBegin then
  begin
    j := i + 1; scopeBase := 1;   { scopeBase reused as begin/end depth here }
    while (j < TokCount) and (scopeBase > 0) do
    begin
      if (Tokens[j].Kind = tkBegin) or (Tokens[j].Kind = tkCase) then Inc(scopeBase)
      else if Tokens[j].Kind = tkEnd then Dec(scopeBase)
      else if (Tokens[j].Kind = tkIdent) and (j + 1 < TokCount) and (Tokens[j+1].Kind = tkFor) and
              CaseEqual(GetTokenStrFromRaw(Tokens[j].SOffset, Tokens[j].SLen), 'parallel') then
        Error('parallel for: nested `parallel for` is not supported');
      Inc(j);
    end;
  end
  else if (Tokens[i].Kind = tkIdent) and (i + 1 < TokCount) and (Tokens[i+1].Kind = tkFor) and
          CaseEqual(GetTokenStrFromRaw(Tokens[i].SOffset, Tokens[i].SLen), 'parallel') then
    Error('parallel for: nested `parallel for` is not supported');

  { Capture the body TOKEN span by parsing it once (span + validation); the AST is
    discarded — the body is re-parsed inside the worker. }
  bodyStart := TokPos - 1;
  bodyAst := ParseStatementAST;
  bodyEnd := TokPos - 1;
  if bodyEnd <= bodyStart then Error('parallel for: empty loop body');

  { Collect the enclosing locals/params the body captures (any body ident, other
    than the loop var, resolving to a routine-scope symbol). Phase A: SCALARS only
    — passed BY REFERENCE through the enclosing frame pointer (ctx), read in the
    worker at `ctx + Syms[si].Offset`. A non-scalar capture (record/class/array/
    string) is a clear error until Phase B. }
  scopeBase := Procs[CurProc].ScopeBase;
  capCount := 0;
  for i := bodyStart to bodyEnd - 1 do
    if Tokens[i].Kind = tkIdent then
    begin
      capNm := GetTokenStrFromRaw(Tokens[i].SOffset, Tokens[i].SLen);
      if CaseEqual(capNm, Vname) then Continue;
      if (i > bodyStart) and (Tokens[i-1].Kind = tkDot) then Continue;   { qualified field }
      si := FindSym(capNm);
      if (si < 0) or (si < scopeBase) then Continue;                     { global / not a capture }
      found := False;
      for j := 0 to capCount - 1 do
        if capSi[j] = si then begin found := True; Break; end;
      if found then Continue;
      if capCount >= MAX_PFCAP then Error('parallel for: too many captured variables');
      { Accessor type for the worker's `capj: ^<T>`: a scalar maps to a keyword;
        a non-scalar (array/record/class/string) uses its DECLARED type NAME when it
        has one (`x: TGrid` -> `^TGrid`) — must be a unit/global-level named type,
        visible at the worker's top-level scope. An unnamed non-scalar type
        (`array[..] of T` inline) is a clear error (Phase B-2 will synthesize a name). }
      { An array var's TypeKind is its ELEMENT type, so guard the scalar path on
        not-an-array — else a fixed array would masquerade as its scalar element
        (and a dyn array would skip the handle deref and crash). }
      if (not Syms[si].IsArray) and (SymDynDepth[si] = 0) then
        kw := PFScalarKw(Syms[si].TypeKind)
      else
        kw := '';
      if kw <> '' then
      begin
        capKwOff[capCount] := NestStrOff(kw); capKwLen[capCount] := Length(kw);
      end
      else if SymDeclTypeNOff[si] <> 0 then
      begin
        capKwOff[capCount] := SymDeclTypeNOff[si]; capKwLen[capCount] := SymDeclTypeNLen[si];
      end
      else if Syms[si].TypeKind = tyAnsiString then
      begin
        { `s: AnsiString` via the built-in keyword (no user alias) — use it directly.
          Managed but INLINE-style: the frame slot holds the string handle and
          `^AnsiString` derefs it (capHandle stays false; @s = frame slot). Char
          indexing now works through the deref (bug-pascal-ptr-deref-string-index). }
        kw := 'AnsiString'; capKwOff[capCount] := NestStrOff(kw); capKwLen[capCount] := Length(kw);
      end
      else
      begin
        ErrorIdent := capNm;
        Error('parallel for: capturing ''' + capNm + ''' — its type is unnamed; declare it with a named type (e.g. `type TFoo = ...`) to capture it (Phase B-2)');
      end;
      capSi[capCount]    := si;
      capNmOff[capCount] := NestStrOff(capNm);
      capNmLen[capCount] := Length(capNm);
      capOfs[capCount]   := Syms[si].Offset;
      { handle type: a dynamic array's frame slot holds a data POINTER, not inline
        data — the worker derefs it once more (fixed arrays/records are inline). }
      capHandle[capCount] := SymDynDepth[si] > 0;
      Inc(capCount);
    end;

  { resolve each reduction variable to its capture (must be a captured SCALAR) and
    grab the type keyword/token for its private __pfred<K> accumulator. }
  if redN > 0 then
  begin
    if FindProc('PXXReduceLock') < 0 then
      Error('reduction: palparallel too old (PXXReduceLock not found)');
    for rk := 0 to redN - 1 do
    begin
      for ci := 0 to capCount - 1 do
        if CaseEqual(GetTokenStrFromRaw(capNmOff[ci], capNmLen[ci]), redVarNameA[rk]) then
        begin redCapIdxA[rk] := ci; Break; end;
      if redCapIdxA[rk] < 0 then
        Error('reduction: ''' + redVarNameA[rk] + ''' must be an enclosing local written in the body');
      if capHandle[redCapIdxA[rk]] then
        Error('reduction: only scalar variables are supported (not dyn-array/string)');
      redKwOffA[rk] := capKwOff[redCapIdxA[rk]]; redKwLenA[rk] := capKwLen[redCapIdxA[rk]];
      { the private local needs the type's KEYWORD token where one exists — a bare
        `tkIdent('Integer')` does not resolve as a named type (only `^Integer`
        does); Int64/NativeInt/Byte/… have no keyword token and resolve as idents. }
      case Syms[capSi[redCapIdxA[rk]]].TypeKind of
        tyInteger, tyInt32: redTypeTokA[rk] := tkInteger_T;
        tyBoolean:          redTypeTokA[rk] := tkBoolean_T;
        tyChar:             redTypeTokA[rk] := tkChar_T;
        tyUInt32:           redTypeTokA[rk] := tkLongWord_T;
        tySingle:           redTypeTokA[rk] := tkSingle_T;
        tyDouble:           redTypeTokA[rk] := tkDouble_T;
      else                  redTypeTokA[rk] := tkIdent;
      end;
    end;
  end;

  { --- synthesize worker name + intern the string-pool offsets --- }
  wname := '__pf_' + MangleSuffix(ParForSeq);
  Inc(ParForSeq);
  wnameOff := NestStrOff(wname); wnameLen := Length(wname);
  ctxOff := NestStrOff('__pfctx');
  loPOff := NestStrOff('__pflo');
  hiPOff := NestStrOff('__pfhi');
  ptrOff := NestStrOff('Pointer');
  niOff  := NestStrOff('NativeInt');
  vOff   := NestStrOff(Vname); vLen := Length(Vname);

  { header: procedure <wname> ( __pfctx : Pointer ; __pflo , __pfhi : NativeInt ) ; }
  PFScratchN := 0;
  PFSet(tkProcedure, 0, 0, ln);
  PFSet(tkIdent, wnameOff, wnameLen, ln);
  PFSet(tkLParen, 0, 0, ln);
  PFSet(tkIdent, ctxOff, 7, ln);
  PFSet(tkColon, 0, 0, ln);
  PFSet(tkIdent, ptrOff, 7, ln);       { Pointer }
  PFSet(tkSemicolon, 0, 0, ln);
  PFSet(tkIdent, loPOff, 6, ln);
  PFSet(tkComma, 0, 0, ln);
  PFSet(tkIdent, hiPOff, 6, ln);
  PFSet(tkColon, 0, 0, ln);
  PFSet(tkIdent, niOff, 9, ln);        { NativeInt }
  PFSet(tkRParen, 0, 0, ln);
  PFSet(tkSemicolon, 0, 0, ln);

  { (1) register the worker FORWARD signature synchronously (lambda-lift's proven
    re-entrant path) so @<wname> resolves now; code address patched at finalize. }
  savedTokPos := TokPos;
  savedTokCount := TokCount;
  for i := 0 to PFScratchN - 1 do
  begin
    EnsureTokCapacity(TokCount + 1);
    Tokens[TokCount] := PFScratch[i]; Inc(TokCount); EnsureTokCapacity(TokCount+1);
  end;
  EnsureTokCapacity(TokCount + 3);
  Tokens[TokCount].Kind := tkForward; Tokens[TokCount].IVal := 0; Tokens[TokCount].Line := ln;
  Tokens[TokCount].SOffset := 0; Tokens[TokCount].SLen := 0; Inc(TokCount); EnsureTokCapacity(TokCount+1);
  Tokens[TokCount].Kind := tkSemicolon; Tokens[TokCount].IVal := 0; Tokens[TokCount].Line := ln;
  Tokens[TokCount].SOffset := 0; Tokens[TokCount].SLen := 0; Inc(TokCount); EnsureTokCapacity(TokCount+1);

  TokPos := savedTokCount;   { point at the appended 'procedure' }
  Next;
  savedCurProc := CurProc; savedSC := SymCount; savedFS := FrameSize; savedSelf := CurSelfClass;
  ParseSubroutine;           { registers the forward signature; Exits before a body }
  CurProc := savedCurProc; SymCount := savedSC; FrameSize := savedFS; CurSelfClass := savedSelf;
  workerIdx := FindProc(wname);
  if workerIdx < 0 then Error('parallel for: internal — worker registration failed');

  TokCount := savedTokCount;      { drop the appended forward tokens }
  TokPos := savedTokPos - 1;      { restore the caller's stream position }
  Next;

  { (2) stash the FULL worker body for the pass-2 nested-proc flush:
      <header> var <V> : NativeInt ; begin for <V> := __pflo to __pfhi do <BODY> ; end ; }
  if PendNestRtnCount >= MAX_LIFTS then Error('parallel for: too many synthesized routines in one body');
  PendNestRtnStart[PendNestRtnCount] := PendNestCount;
  Inc(PendNestRtnCount);
  ptrCastOff := ptrOff;   { reuse interned 'Pointer' / 'NativeInt' for the casts }
  niCastOff  := niOff;
  pniOff := NestStrOff('PNativeInt');
  for i := 0 to PFScratchN - 1 do
    PFStash(PFScratch[i].Kind, PFScratch[i].SOffset, PFScratch[i].SLen, ln);
  { var i: NativeInt; <cap0>: ^<kw0>; <cap1>: ^<kw1>; ... }
  PFStash(tkVar, 0, 0, ln);
  PFStash(tkIdent, vOff, vLen, ln);
  PFStash(tkColon, 0, 0, ln);
  PFStash(tkIdent, niOff, 9, ln);      { NativeInt }
  PFStash(tkSemicolon, 0, 0, ln);
  for ci := 0 to capCount - 1 do
  begin
    PFStash(tkIdent, capNmOff[ci], capNmLen[ci], ln);
    PFStash(tkColon, 0, 0, ln);
    PFStash(tkCaret, 0, 0, ln);
    PFStash(tkIdent, capKwOff[ci], capKwLen[ci], ln);
    PFStash(tkSemicolon, 0, 0, ln);
  end;
  { reduction: private accumulators `__pfred<K> : <type> ;` }
  for rk := 0 to redN - 1 do
  begin
    PFStash(tkIdent, red0OffA[rk], 8, ln);   { __pfred<K> }
    PFStash(tkColon, 0, 0, ln);
    if redTypeTokA[rk] = tkIdent then
      PFStash(tkIdent, redKwOffA[rk], redKwLenA[rk], ln)
    else
      PFStash(redTypeTokA[rk], 0, 0, ln);    { Integer/Boolean/Char/… keyword token }
    PFStash(tkSemicolon, 0, 0, ln);
  end;
  PFStash(tkBegin, 0, 0, ln);
  { preamble per capture:
      inline (scalar/fixed-array/record): capj := Pointer(NativeInt(__pfctx) +/- off);
      handle (dyn array / ansistring):    capj := Pointer(PNativeInt(NativeInt(__pfctx) +/- off)^);
    — a handle-typed slot holds a data POINTER, so the worker derefs it once more. }
  for ci := 0 to capCount - 1 do
  begin
    PFStash(tkIdent, capNmOff[ci], capNmLen[ci], ln);
    PFStash(tkAssign, 0, 0, ln);
    PFStash(tkIdent, ptrCastOff, 7, ln);      { Pointer( }
    PFStash(tkLParen, 0, 0, ln);
    if capHandle[ci] then
    begin
      PFStash(tkIdent, pniOff, 10, ln);       { PNativeInt( }
      PFStash(tkLParen, 0, 0, ln);
    end;
    PFStash(tkIdent, niCastOff, 9, ln);       { NativeInt( }
    PFStash(tkLParen, 0, 0, ln);
    PFStash(tkIdent, ctxOff, 7, ln);          { __pfctx }
    PFStash(tkRParen, 0, 0, ln);
    if capOfs[ci] >= 0 then
    begin
      PFStash(tkPlus, 0, 0, ln); absOff := capOfs[ci];
    end
    else
    begin
      PFStash(tkMinus, 0, 0, ln); absOff := -capOfs[ci];
    end;
    if PendNestCount >= MAX_NESTED_TOKENS then Error('parallel for: nested token buffer overflow');
    PendNestTok[PendNestCount].Kind := tkInteger; PendNestTok[PendNestCount].IVal := absOff;
    PendNestTok[PendNestCount].Line := ln; PendNestTok[PendNestCount].SOffset := 0; PendNestTok[PendNestCount].SLen := 0;
    Inc(PendNestCount);
    if capHandle[ci] then
    begin
      PFStash(tkRParen, 0, 0, ln);            { ) closing PNativeInt( }
      PFStash(tkCaret, 0, 0, ln);             { ^ deref the handle }
    end;
    PFStash(tkRParen, 0, 0, ln);              { ) closing Pointer( }
    PFStash(tkSemicolon, 0, 0, ln);
  end;
  { reduction: __pfred<K> := <identity> (+/or/xor)  or  := v^ (min/max) ; }
  for rk := 0 to redN - 1 do
  begin
    PFStash(tkIdent, red0OffA[rk], 8, ln);
    PFStash(tkAssign, 0, 0, ln);
    if redIsMinMaxA[rk] then
    begin
      { seed with the shared var's current value: handles an empty worker range
        (combine becomes a no-op) with no need for a typed +/-infinity. }
      PFStash(tkIdent, capNmOff[redCapIdxA[rk]], capNmLen[redCapIdxA[rk]], ln);
      PFStash(tkCaret, 0, 0, ln);
    end
    else if redIsAndA[rk] then
    begin
      { `and` identity = all-ones. Boolean -> True; ordinal -> `not 0` (= -1, which
        truncates to all-ones for the target width on assignment). }
      if redTypeTokA[rk] = tkBoolean_T then
        PFStash(tkTrue, 0, 0, ln)
      else
      begin
        PFStash(tkNot, 0, 0, ln);
        if PendNestCount >= MAX_NESTED_TOKENS then Error('parallel for: nested token buffer overflow');
        PendNestTok[PendNestCount].Kind := tkInteger; PendNestTok[PendNestCount].IVal := 0;
        PendNestTok[PendNestCount].Line := ln; PendNestTok[PendNestCount].SOffset := 0; PendNestTok[PendNestCount].SLen := 0;
        Inc(PendNestCount);
      end;
    end
    else
    begin
      { integer literal identity: 0 (+/or/xor) or 1 (mul) }
      if PendNestCount >= MAX_NESTED_TOKENS then Error('parallel for: nested token buffer overflow');
      PendNestTok[PendNestCount].Kind := tkInteger; PendNestTok[PendNestCount].IVal := redIdentValA[rk];
      PendNestTok[PendNestCount].Line := ln; PendNestTok[PendNestCount].SOffset := 0; PendNestTok[PendNestCount].SLen := 0;
      Inc(PendNestCount);
    end;
    PFStash(tkSemicolon, 0, 0, ln);
  end;
  PFStash(tkFor, 0, 0, ln);
  PFStash(tkIdent, vOff, vLen, ln);
  PFStash(tkAssign, 0, 0, ln);
  PFStash(tkIdent, loPOff, 6, ln);
  PFStash(tkTo, 0, 0, ln);
  PFStash(tkIdent, hiPOff, 6, ln);
  PFStash(tkDo, 0, 0, ln);
  { Copy the body tokens VERBATIM (full record — literals carry their value in
    IVal). Each captured-scalar reference gets a trailing `^`: the worker's `capj`
    is a pointer into the enclosing frame, so `a` -> `a^`, `a := x` -> `a^ := x`. }
  for i := bodyStart to bodyEnd - 1 do
  begin
    if PendNestCount >= MAX_NESTED_TOKENS then Error('parallel for: nested token buffer overflow');
    PendNestTok[PendNestCount] := Tokens[i];
    Inc(PendNestCount);
    if Tokens[i].Kind = tkIdent then
    begin
      capNm := GetTokenStrFromRaw(Tokens[i].SOffset, Tokens[i].SLen);
      { reduction var: redirect the reference to its private __pfred<K> (a plain
        local, NOT a captured pointer), so it accumulates race-free. Rewrite the
        just-stashed token and skip the `^` deref. }
      redThisIdent := -1;
      if not ((i > bodyStart) and (Tokens[i-1].Kind = tkDot)) then
        for rj := 0 to redN - 1 do
          if CaseEqual(capNm, redVarNameA[rj]) then begin redThisIdent := rj; Break; end;
      if redThisIdent >= 0 then
      begin
        PendNestTok[PendNestCount-1].SOffset := red0OffA[redThisIdent];
        PendNestTok[PendNestCount-1].SLen := 8;
        Continue;
      end;
      if (not CaseEqual(capNm, Vname)) and
         (not ((i > bodyStart) and (Tokens[i-1].Kind = tkDot))) then
      begin
        si := FindSym(capNm);
        found := False;
        for j := 0 to capCount - 1 do
          if capSi[j] = si then begin found := True; Break; end;
        if found then PFStash(tkCaret, 0, 0, ln);
      end;
    end;
  end;
  PFStash(tkSemicolon, 0, 0, ln);
  { reduction combine: ONE lock around ALL entries' folds (each fold independent,
    once per worker). Per entry:
      +/or/xor : v^ := v^ op __pfred<K>
      min/max  : if __pfred<K> </> v^ then v^ := __pfred<K> }
  if redN > 0 then
  begin
    PFStash(tkIdent, NestStrOff('PXXReduceLock'), 13, ln);
    PFStash(tkSemicolon, 0, 0, ln);
    for rk := 0 to redN - 1 do
    begin
      if redIsMinMaxA[rk] then
      begin
        PFStash(tkIf, 0, 0, ln);
        PFStash(tkIdent, red0OffA[rk], 8, ln);
        if redIsMaxA[rk] then PFStash(tkGt, 0, 0, ln) else PFStash(tkLt, 0, 0, ln);
        PFStash(tkIdent, capNmOff[redCapIdxA[rk]], capNmLen[redCapIdxA[rk]], ln);
        PFStash(tkCaret, 0, 0, ln);
        PFStash(tkThen, 0, 0, ln);
        PFStash(tkIdent, capNmOff[redCapIdxA[rk]], capNmLen[redCapIdxA[rk]], ln);
        PFStash(tkCaret, 0, 0, ln);
        PFStash(tkAssign, 0, 0, ln);
        PFStash(tkIdent, red0OffA[rk], 8, ln);
        PFStash(tkSemicolon, 0, 0, ln);
      end
      else
      begin
        PFStash(tkIdent, capNmOff[redCapIdxA[rk]], capNmLen[redCapIdxA[rk]], ln);
        PFStash(tkCaret, 0, 0, ln);
        PFStash(tkAssign, 0, 0, ln);
        PFStash(tkIdent, capNmOff[redCapIdxA[rk]], capNmLen[redCapIdxA[rk]], ln);
        PFStash(tkCaret, 0, 0, ln);
        PFStash(redOpA[rk], 0, 0, ln);
        PFStash(tkIdent, red0OffA[rk], 8, ln);
        PFStash(tkSemicolon, 0, 0, ln);
      end;
    end;
    PFStash(tkIdent, NestStrOff('PXXReduceUnlock'), 15, ln);
    PFStash(tkSemicolon, 0, 0, ln);
  end;
  PFStash(tkEnd, 0, 0, ln);
  PFStash(tkSemicolon, 0, 0, ln);

  { (3) PXXParallelFor(lo, hi, @<wname>, ctx) — or, with a policy clause,
    PXXParallelForPP(lo, hi, @<wname>, ctx, @policy) — wrapped in AN_PARFOR.
    ctx = the enclosing frame pointer when the body captures locals (workers read
    each capture at ctx + its frame offset), else nil. }
  a1 := AllocNode(AN_ARG); ASTLeft[a1] := loNode; ASTTk[a1] := Ord(tyInt64);
  a2 := AllocNode(AN_ARG); ASTLeft[a2] := hiNode; ASTTk[a2] := Ord(tyInt64);
  procAddr := AllocNode(AN_PROCADDR); ASTIVal[procAddr] := workerIdx; ASTTk[procAddr] := Ord(tyPointer);
  a3 := AllocNode(AN_ARG); ASTLeft[a3] := procAddr; ASTTk[a3] := Ord(tyPointer);
  if capCount > 0 then
    ctxNode := AllocNode(AN_FRAME)
  else
  begin
    ctxNode := AllocNode(AN_INT_LIT); ASTIVal[ctxNode] := 0;
  end;
  ASTTk[ctxNode] := Ord(tyPointer);
  a4 := AllocNode(AN_ARG); ASTLeft[a4] := ctxNode; ASTTk[a4] := Ord(tyPointer);
  ASTRight[a1] := a2; ASTRight[a2] := a3; ASTRight[a3] := a4;
  if hasPolicy then
  begin
    polAddr := AllocNode(AN_ADDR); ASTLeft[polAddr] := policyNode; ASTTk[polAddr] := Ord(tyPointer);
    a5 := AllocNode(AN_ARG); ASTLeft[a5] := polAddr; ASTTk[a5] := Ord(tyPointer);
    ASTRight[a4] := a5; ASTRight[a5] := -1;
    callNode := AllocNode(AN_CALL); ASTIVal[callNode] := ppiP;
  end
  else if hasNamedPolicy then
  begin
    { 5 folded int args: distOrd, workersOrd, fixedN, capPct, minChunk }
    polVals[0] := polDistOrd; polVals[1] := polWorkersOrd; polVals[2] := polFixedN;
    polVals[3] := polCapPct;  polVals[4] := polMinChunk;
    prevArg := a4;
    for ai := 0 to 4 do
    begin
      an := AllocNode(AN_INT_LIT); ASTIVal[an] := polVals[ai]; ASTTk[an] := Ord(tyInteger);
      a5 := AllocNode(AN_ARG); ASTLeft[a5] := an; ASTTk[a5] := Ord(tyInteger);
      ASTRight[prevArg] := a5; prevArg := a5;
    end;
    ASTRight[prevArg] := -1;
    callNode := AllocNode(AN_CALL); ASTIVal[callNode] := ppiN;
  end
  else
  begin
    ASTRight[a4] := -1;
    callNode := AllocNode(AN_CALL); ASTIVal[callNode] := ppi;
  end;
  ASTLeft[callNode] := a1; ASTRight[callNode] := -1;

  node := AllocNode(AN_PARFOR);
  ASTLeft[node] := callNode;
  Result := node;
end;

function StatementIsAssignment: Boolean;
{ Looking from CurTok, is the statement an ASSIGNMENT (a `:=` at bracket depth
  zero before the statement ends) or a CALL?

  ParseStatementAST decides which hand-rolled lvalue path to take from the
  first token alone, and two of those paths -- the record-name cast and the
  pointer-alias cast -- then walk the `^`/`.field` chain with RecFieldType and
  finish on a hard `Expect(:=)`. A METHOD at the end of that chain is not a
  field, so `PRec(q)^.o.M(1);` and `PPVmt(Self)^.__ClassRef.GetHashList(...);`
  were a syntax error ("Expected: :=") while the very same expression READ
  fine on the right of an assignment. The class-cast path already had the
  answer -- delegate the chain, then take the node if it came back a call --
  and this predicate is what lets the other two ask the question first.
  bug-pascal-cast-deref-method-call-statement }
var i, depth: Integer;
begin
  Result := False;
  depth := 0;
  i := TokPos - 1;                 { index of CurTok }
  while i < TokCount do
  begin
    if (Tokens[i].Kind = tkLParen) or (Tokens[i].Kind = tkLBrack) then
      Inc(depth)
    else if (Tokens[i].Kind = tkRParen) or (Tokens[i].Kind = tkRBrack) then
      Dec(depth)
    else if (Tokens[i].Kind = tkAssign) and (depth <= 0) then
    begin
      Result := True;
      Exit;
    end
    else if (depth <= 0) and
            (Tokens[i].Kind in [tkSemicolon, tkEnd, tkElse, tkUntil,
                                tkFinally, tkExcept, tkEOF]) then
      Exit;
    Inc(i);
  end;
end;


function IsUntypedVarParamSym(symIdx: Integer): Boolean;
{ Is this symbol the current routine's UNTYPED by-ref parameter (`var x` with
  no type)? There is no per-symbol flag -- untypedness lives in the parallel
  ProcParamUntyped array, keyed by proc and slot, because Params[].SymIdx is
  -1 after RegisterProc and a param symbol does not outlive the callee's
  scope. Inside the body being parsed the name is unambiguous, so match on it.
  Used by the cast-as-lvalue arm: an untyped param is declared tyPointer and
  therefore has no declared width for the cast to disagree with, which is
  exactly what makes `Integer(x) := 99` legal there and a size error anywhere
  else. }
var i: Integer;
begin
  Result := False;
  if (CurProc < 0) or (symIdx < 0) or (symIdx >= SymCount) then Exit;
  if Syms[symIdx].Kind <> skParam then Exit;
  for i := 0 to Procs[CurProc].ParamCount - 1 do
    if ProcParamUntyped[CurProc * MAX_PROC_PARAMS + i] and
       CaseEqual(Procs[CurProc].Params[i].Name, Syms[symIdx].Name) then
    begin
      Result := True;
      Exit;
    end;
end;

function ParseStatementAST: Integer;
var
  smmiS, pvSig, pvTarget, smSelfNode, fanSym: Integer;
  pvIsMeth: Boolean;
  name: AnsiString;
   idx, procIdx, i, si, node, valNode, stepsNode, opNode, argSeq, argIdx, exprNode, lastArg, identTokIdx: Integer;
  nArgs, argsHead, currArg: Integer; argTypes: array[0..MAX_PROC_PARAMS-1] of TTypeKind;
  kwIdx, slotIdx: Integer;   { NilPy keyword argument: binding+1, and the param it fills }
  isLn, slIsArrTarget, slIsDynArr, frDot: Boolean;
  smci, smmii, smpii, smcallNode, smselfArg, smLastArg, smArgSeq, smMai, smSelfIdx: Integer;
  aliasIdx, fieldNode, indexNode, castPrevTok, qUnit: Integer;
  castFieldName: AnsiString; castTk: TTypeKind; castRec: Integer;
  decVal, decNode: Integer; strIsFloat: Boolean;
  valTmpSym, valTmpAssign, valTmpIdent: Integer;
  miArg, miEmpty: Integer; miIsFin: Boolean;   { Initialize/Finalize }
  pfIsPF: Boolean; pfK, pfDepth: Integer;
  insSrcSym: Integer;   { Insert(srcArr, arr, i): the source array's symbol, else -1 }
begin
  { `parallel for` soft keyword: `parallel` lexes as a plain ident, so it is a
    parallel-for only when followed by `for`, or by a policy clause `(...)` whose
    matching `)` is itself followed by `for` (`parallel(P) for`). Everywhere else
    (incl. an ordinary `parallel(x)` call) it stays a normal identifier. }
  if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'parallel')
     and (TokPos < TokCount) then
  begin
    pfIsPF := False;
    if Tokens[TokPos].Kind = tkFor then pfIsPF := True
    else if Tokens[TokPos].Kind = tkLParen then
    begin
      { scan to the matching ) then peek for `for` }
      pfDepth := 0; pfK := TokPos;
      while pfK < TokCount do
      begin
        if Tokens[pfK].Kind = tkLParen then Inc(pfDepth)
        else if Tokens[pfK].Kind = tkRParen then
        begin Dec(pfDepth); if pfDepth = 0 then Break; end;
        Inc(pfK);
      end;
      if (pfDepth = 0) and (pfK + 1 < TokCount) and (Tokens[pfK + 1].Kind = tkFor) then
        pfIsPF := True;
    end;
    if pfIsPF then begin Result := ParseParallelFor; Exit; end;
  end;

  { {$R} is governed by the mode at the STATEMENT's first token — a directive
    between the RHS and the statement end must not retro-apply (trange4.pp:
    `x:=y {$R+} end`). AllocNode(AN_ASSIGN) reads this anchor. }
  if (TokPos > 0) and (TokPos <= TokCount) then
    StmtRChecks := TokRChecks[TokPos - 1];
  if (TokPos > 0) and (TokPos <= TokCount) then
    StmtIChecks := TokIChecks[TokPos - 1];
  if (TokPos > 0) and (TokPos <= TokCount) then
    StmtNChecks := Integer(TokNChecks[TokPos - 1]);
  node := -1;
  case CurTok.Kind of
    tkInteger:
    begin
      { A NUMERIC label at statement position -- `1: Writeln(...)`. The
        IDENTIFIER form is handled inside the tkIdent case far below, which a
        number never reaches, so `1:` was a syntax error even with the label
        declared. Only a following ':' makes it a label; anything else keeps
        the diagnostic a statement starting with a number deserves. }
      if (TokPos < TokCount) and (Tokens[TokPos].Kind = tkColon) then
      begin
        node := AllocNode(AN_LABEL);
        LabelSpanOfTok(TokPos-1, ASTSOffset[node], ASTSLen[node]);
        Next; Next;   { the number and the ':' }
        Result := node;
        Exit;
      end;
      Error('a statement cannot start with a number');
    end;
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
      begin
        { `Integer(v) := x` over a plain LVALUE, not a pointer deref: ordinary
          FPC, and the ONLY way to write through an untyped `var x` parameter
          (`procedure SetI(var x); begin Integer(x) := 99; end`) -- the
          Move/FillChar-shaped routine this dialect otherwise supports on the
          READ side, since `Integer(x)` as an r-value already worked.

          Normalised into the shape that already works rather than given a
          second store path: `Integer(v) := x` becomes `PInteger(@v)^ := x`,
          an AN_DEREF over AN_ADDR tagged with the cast's type. The deref arm
          below then retags and stores at the CAST's width, which is the whole
          point -- an untyped param is declared tyPointer, so storing through
          it directly would write 8 bytes into a 4-byte Integer.
          devdocs/dev/normalise-dont-special-case.md }
        if not IsASTLValue(valNode) then
          Error('cast-as-lvalue statement requires a variable or a pointer deref inside the cast');
        { FPC's rule is same-SIZE reinterpretation: `Integer(b) := 5` on a Byte
          is "Typecast has different size" there, and silently writing 4 bytes
          into 1 here would corrupt the neighbour. An UNTYPED var parameter is
          exempt -- it has no declared width to disagree with, which is what
          makes it the interesting case. }
        castPrevTok := -1;
        if ASTKind[valNode] = AN_IDENT then castPrevTok := ASTIVal[valNode];
        if not ((castPrevTok >= 0) and (castPrevTok < SymCount) and
                IsUntypedVarParamSym(castPrevTok)) then
          if TypeSize(castTk) <> TypeSize(IntToTypeKind(ASTTk[valNode])) then
            Error('cast-as-lvalue: the cast type must be the same size as the variable');
        node := AllocNode(AN_ADDR);
        ASTLeft[node] := valNode;
        ASTTk[node] := Ord(tyPointer);
        valNode := AllocNode(AN_DEREF);
        ASTLeft[valNode] := node;
      end;
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
      { Initialize(x) / Finalize(x) — System.

        Both used to be no-ops (Finalize parsed-and-discarded its argument,
        Initialize did not exist), which made `Finalize(s)` leave `len=5
        [hello]` where FPC prints `len=0 []`: FPC-shaped code that compiles,
        runs, and silently does not do what it says. They now lower onto the
        ARC machinery that already exists — see AN_MANAGED_INIT.

        The count form `Finalize(x, n)` (x as the first of n elements) is
        REFUSED rather than accepted-and-ignored: accepting it would put the
        silent no-op straight back, in the one shape where it leaks an array's
        worth of references instead of one. }
      if (qUnit < 0) and (CaseEqual(name, 'Finalize') or CaseEqual(name, 'Initialize')) and
         (Tokens[TokPos].Kind = tkLParen) and
         (FindProc(name) < 0) and (FindSym(name) < 0) and
         ((CurSelfClass < REC_UCLASS_BASE) or
          (FindUMeth(CurSelfClass - REC_UCLASS_BASE, name) < 0)) then
      begin
        miIsFin := CaseEqual(name, 'Finalize');
        Next; Expect(tkLParen, '(');
        ParseExpr;
        miArg := CurASTNode;
        if CurTok.Kind = tkComma then
          Error(name + '(x, n) — the element-count form is not implemented; call it per element (feature-a-implement-initialize-and-finalize-over-the-arc-helpers)');
        Expect(tkRParen, ')');
        { Finalize of a STRING is `x := ''` — literally. Assignment already
          releases the old reference and stores the new one, which is Finalize's
          definition down to both load-bearing properties: idempotent (the
          second one releases '' ) and it drops a REFERENCE, not the object.
          Desugaring here rather than hand-building the release in IR is the
          normalise-dont-special-case call, and it is not academic: the
          hand-built version passed the string's CONTENT to PXXStrDecRef instead
          of its handle and segfaulted, while this path is the one every
          assignment in the language already exercises. A zero-length literal
          needs no source text, so SOffset is irrelevant at SLen = 0. }
        if miIsFin and ((LastExprTk = tyAnsiString) or (LastExprTk = tyString)) then
        begin
          miEmpty := AllocNode(AN_STR_LIT);
          ASTSOffset[miEmpty] := 0; ASTSLen[miEmpty] := 0;
          ASTTk[miEmpty] := Ord(tyString);
          Result := GenMakeAssign(miArg, miEmpty);
          Exit;
        end;
        Result := AllocNode(AN_MANAGED_INIT);
        ASTLeft[Result] := miArg;
        if miIsFin then ASTIVal[Result] := 1 else ASTIVal[Result] := 0;
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
         SoftIntrinsicOpenSym(name, qUnit) and
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

      { Bare Assert(cond) / Assert(cond, msg) — System.Assert, with no `uses`. Same
        soft-alias discipline as Move/FillChar above: no real proc named Assert exists,
        so a user's own Assert (or a method of the enclosing class) still wins. The
        message is a defaulted parameter on the helper. }
      if (qUnit < 0) and CaseEqual(name, 'Assert') and
         (Tokens[TokPos].Kind = tkLParen) and
         (FindProc(name) < 0) and (FindSym(name) < 0) and
         ((qUnit = -2) or (CurSelfClass < REC_UCLASS_BASE) or
          (FindUMeth(CurSelfClass - REC_UCLASS_BASE, name) < 0)) and
         (FindProc('__pxxAssert') >= 0) then
        name := '__pxxAssert';
      { Label definition: 'labelname:' as a statement }
      if Tokens[TokPos].Kind = tkColon then
      begin
        node := AllocNode(AN_LABEL);
        LabelSpanOfTok(TokPos-1, ASTSOffset[node], ASTSLen[node]);
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
              ((qUnit = -2) or (FindProc(name) < 0)) and (Tokens[TokPos].Kind = tkLParen) then
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
      { …and a proc of that name shadows only if a BARE statement could actually
        call it. crtl declares `void exit(int)`, so pulling any C unit made
        every later Pascal unit's `exit;` bind to a routine that needs an
        argument and report "undefined variable (exit)" — order-dependent, and
        it broke lib/pcl/tkinter.pas whenever a C-backed shim was imported
        first. A user's own parameterless `procedure Exit` still shadows.
        bug-c-exit-shadows-pascal-exit. }
      else if (CaseEqual(name, 'Halt') or CaseEqual(name, 'Exit')) and
              ((qUnit = -2) or
               ((((FindProc(name) < 0) or
                  ((Tokens[TokPos].Kind <> tkLParen) and
                   (Procs[FindProc(name)].ParamCount > 0))) and
                 (FindSym(name) < 0)))) then
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
              ((qUnit = -2) or ((FindProc(name) < 0) and (FindSym(name) < 0))) then
      begin
        { Break / Continue: bare soft-keyword statements.

          The SYSTEM-QUALIFIER EXEMPTION, same as the expression-side intrinsics
          (see the note at `High` in ParseFactor): `System.Break` names the
          builtin even where a local is spelled `Break`, and FPC 3.2.2 accepts
          exactly that. The statement path had its own copy of these guards and
          had never been compared against the expression path's list.
          meta-a-second-paths-reimplement-the-first-paths-decisions }
        if CaseEqual(name, 'Break') then node := AllocNode(AN_BREAK)
        else node := AllocNode(AN_CONTINUE);
        Next;
      end
      else if CaseEqual(name, 'FreeAndNil') and (FindSym(name) < 0) and
              (Tokens[TokPos].Kind = tkLParen) and
              (Tokens[TokPos + 1].Kind = tkIdent) and
              (Tokens[TokPos + 2].Kind = tkRParen) and
              (FindSym(GetTokenStr(TokPos + 1)) >= 0) and
              (Syms[FindSym(GetTokenStr(TokPos + 1))].RecName >= REC_UCLASS_BASE) and
              (not UClsIsRecord[Syms[FindSym(GetTokenStr(TokPos + 1))].RecName - REC_UCLASS_BASE]) then
      begin
        { `FreeAndNil(x)` where x is a class-typed VARIABLE.

          It cannot be a library routine and be correct. FPC's takes an untyped `var Obj`, so
          inside it the reference is TObject -- and `Free` through an untyped/TObject reference
          does NOT dispatch Destroy in this compiler (the VMT slot is not known from a
          reference with no class id). So every destructor of every object freed that way was
          SILENTLY SKIPPED: no `inherited`, no child cleanup. It looked fine, because the
          memory really was released.

          At the CALL SITE the variable's static type IS known, and that is exactly what
          `obj.Free` already uses to dispatch Destroy through the VMT -- and GenMakeFreeObject
          already nils the variable afterwards, which is the whole of FreeAndNil. So this is
          the same node `x.Free` builds, and it is correct for free.

          A local named FreeAndNil still wins; anything that is not a plain class variable
          falls through to the library routine. }
        fanSym := FindSym(GetTokenStr(TokPos + 1));
        Next; Next;   { consume 'FreeAndNil' and '(' }
        Next;         { consume the variable }
        Expect(tkRParen, ')');
        node := GenMakeFreeObject(fanSym);
      end
      else if CaseEqual(name, 'get_caller_stackinfo') and
              (FindProc(name) < 0) and (FindSym(name) < 0) and
              (Tokens[TokPos].Kind = tkLParen) then
      begin
        { get_caller_stackinfo(var bp, var addr): FPC's System intrinsic that steps
          one frame up the saved-fp chain, setting addr to the return address into
          bp's caller and bp to that caller's frame. Both args are lvalues, written
          through -- so it is a statement-level soft keyword like Inc/Dec, not an
          expression. IRLowerAST does the two loads and two stores. }
        if CurProc < 0 then
          Error('get_caller_stackinfo needs a stack frame, and the program body has none (it is the outermost frame): call it from a routine');
        FrameIntrinsicUsed := True;
        if CurProc >= 0 then ProcFrameSensitive[CurProc] := True;
        node := AllocNode(AN_CALLERINFO);
        Next; Expect(tkLParen, '(');
        ParseExpr;
        ASTLeft[node] := CurASTNode;    { bp }
        Expect(tkComma, ',');
        ParseExpr;
        ASTRight[node] := CurASTNode;   { addr }
        Expect(tkRParen, ')');
      end
      else if (CaseEqual(name, 'Inc') or CaseEqual(name, 'Dec')) and
              SoftIntrinsicOpenSym(name, qUnit) and
              (Tokens[TokPos].Kind = tkLParen) then
      begin
        { Inc(x[,step]) / Dec(x[,step]): soft-keyword statements lowered to
          x := x +/- step. }
        if CaseEqual(name, 'Inc') then i := Ord(tkInc) else i := Ord(tkDec);
        Next; Expect(tkLParen, '(');
        { A cast-deref/typecast target `Dec(Byte(p^), 32)` / `Dec(Integer(x))`
          (Pascal Script) — a type keyword (Byte/Integer/...) or a
          not-yet-a-symbol ident followed by '(' starts a cast expression
          whose value is an lvalue; ParseExpr yields the addressable node. }
        if (CurTok.Kind in [tkInteger_T, tkLongWord_T, tkBoolean_T, tkChar_T]) or
           ByRefArgStartsExpression(False) then
        begin
          ParseExpr; valNode := CurASTNode;
        end
        else if CurTok.Kind <> tkIdent then Error('expected variable')
        else
        begin
          argIdx := FindSym(CurTok.SVal); identTokIdx := TokPos - 1; Next;
          { Parse the FULL target lvalue (consuming any .field / [i] / ^
            selectors) BEFORE the optional step and ')'. Inc/Dec accept any
            assignable lvalue, exactly like a `var` parameter — a bare-symbol
            parse choked on `Inc(rec.f)` / `Inc(Self.field)`. argIdx may be -1
            (implicit-Self field): ParseLValueAST resolves it. }
          valNode := ParseLValueAST(argIdx, identTokIdx);
        end;

        if Eat(tkComma) then
        begin
          ParseExpr; stepsNode := CurASTNode;
        end
        else
        begin
          { The IMPLICIT step of 1. It must be typed, like any other literal: an
            untyped node reads as tyUnknown, and pointer arithmetic then declined
            to scale it -- so `Inc(p)` on a typed pointer stepped ONE BYTE while
            `Inc(p, 1)`, `Inc(p, 2)` and `p + 1` all stepped SizeOf(element)
            correctly. Silently: the walk just read from the wrong offset. The
            same one node serves Dec, which stepped one byte backwards for the
            same reason. bug-p-inc-of-a-typed-pointer-steps-one-byte }
          stepsNode := AllocNode(AN_INT_LIT);
          ASTIVal[stepsNode] := 1;
          ASTTk[stepsNode] := Ord(tyInteger);
        end;
        Expect(tkRParen, ')');

        { `operator Inc/Dec(a: TFoo): TFoo` overload on a record/class operand
          (toperator11): Inc(x) desugars to x := IncOp(x). Step form excluded
          (FPC's operator Inc takes one operand). }
        smpii := -1;
        if i = Ord(tkInc) then
          smpii := FindOpOverload(OPK_INC, ASTTk[valNode], ResolveNodeRec(valNode))
        else
          smpii := FindOpOverload(OPK_DEC, ASTTk[valNode], ResolveNodeRec(valNode));
        if smpii >= 0 then
        begin
          argSeq := AllocNode(AN_ARG);
          ASTLeft[argSeq] := valNode;
          opNode := AllocNode(AN_CALL);
          ASTIVal[opNode] := smpii;
          ASTTk[opNode] := Ord(Procs[smpii].RetType);
          ASTLeft[opNode] := argSeq;
          node := AllocNode(AN_ASSIGN);
          ASTLeft[node] := CloneAST(valNode);
          ASTRight[node] := opNode;
        end
        else
        begin
        opNode := AllocNode(AN_BINOP);
        if i = Ord(tkInc) then ASTIVal[opNode] := Ord(tkPlus) else ASTIVal[opNode] := Ord(tkMinus);
        ASTLeft[opNode] := valNode;
        ASTRight[opNode] := stepsNode;

        node := AllocNode(AN_ASSIGN);
        ASTLeft[node] := valNode;
        ASTRight[node] := opNode;
        end;
      end
      else if CaseEqual(name, 'FreeMem') and SoftIntrinsicOpenSym(name, qUnit) and
              (Tokens[TokPos].Kind = tkLParen) then
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
      else if CaseEqual(name, 'GetMem') and SoftIntrinsicOpenSym(name, qUnit) and
              (Tokens[TokPos].Kind = tkLParen) then
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
      else if CaseEqual(name, 'SetSignalHandler') and SoftIntrinsicOpen('SetSignalHandler', qUnit) and
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
      else if CaseEqual(name, 'Delete') and SoftIntrinsicOpen('Delete', qUnit) and
              (Tokens[TokPos].Kind = tkLParen) then
      begin
        { Delete(s, index, count): in-place string delete, lowered to the
          __pxxStrDelete builtin (eval-once; the var param + assign inside the
          helper handle managed refcounting). A user `Delete` (e.g. a list
          method as a plain proc) shadows this. A dynamic-array first argument
          takes the AN_DYN_DELETE path below instead. }
        Next; Expect(tkLParen, '(');
        ParseExpr; valNode := CurASTNode;
        if NodeDynDepth(valNode) >= 1 then
        begin
          { Delete(arr, index, count) on a dynamic array: build a fresh array
            with the range removed (AN_DYN_DELETE, AN_DYN_COPY's template) and
            assign it back onto arr — the dyn-array store path retains the new
            handle and releases the old one, and the temp's scope-exit release
            balances the retain. The target is any dyn-array LVALUE, not just a
            bare name: `obj.Items` and `p^.list` are what real code writes.
            Non-managed, depth-1 element types only (a raw byte copy shares
            element handles with the OLD buffer, whose element-aware release
            would dangle them). }
          { Only meaningful for a bare name; the guards below that use it are
            gated on ASTKind = AN_IDENT for exactly that reason. }
          if ASTKind[valNode] = AN_IDENT then i := ASTIVal[valNode] else i := -1;
          if not DynTargetIsRereadable(valNode) then
            Error('Delete: dynamic-array target must be a name, field or dereference (it is read and written back)');
          { AnsiString and managed-field record elements are supported: the
            lowering retains the kept elements in the fresh buffer (records:
            field-walk via the layout descriptor) to balance the old buffer's
            element-aware release (feature-dynarray-insert-delete-managed-
            elements). Frozen strings / nested arrays are still deferred. }
          { NESTED targets (`array of array of T`) are allowed: the lowering
            strides by a handle, gives the temp the source's depth, and retains
            at that depth -- the three things AN_DYN_COPY has to change
            together. Frozen strings are still deferred. }
          if (NodeDynBaseTk(valNode) = tyString) or
             ((ASTKind[valNode] = AN_IDENT) and (SymElemDynDepth[i] > 0)) then
            Error('Delete: frozen-string element type not yet supported for dynamic-array Delete');
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
          { Write-back target: the SAME lvalue expression, cloned so the two
            occurrences do not alias one node. A bare name is retagged
            tyPointer, which is the handle-store shape the ident path has
            always used; a field/deref keeps the type the field resolves to. }
          argIdx := CloneAST(valNode);
          if ASTKind[argIdx] = AN_IDENT then ASTTk[argIdx] := Ord(tyPointer);
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
      else if CaseEqual(name, 'Insert') and SoftIntrinsicOpen('Insert', qUnit) and
              (Tokens[TokPos].Kind = tkLParen) then
      begin
        { Insert(src, s, index): in-place string insert, lowered to __pxxStrInsert.
          src by value, s by ref (var param). A dynamic-array destination takes
          the AN_DYN_INSERT path below instead. }
        Next; Expect(tkLParen, '(');
        ParseExpr; exprNode := CurASTNode;                            { src }
        Expect(tkComma, ','); ParseExpr; valNode := CurASTNode;       { s (dest) }
        if NodeDynDepth(valNode) >= 1 then
        begin
          { Insert(value, arr, index) on a dynamic array: fresh (len+1)-element
            array filled around a gap at the clamped index, value stored into
            the gap, assigned back onto arr (same shape and element-type
            restrictions as dynamic-array Delete above; records/sets need a
            memory store, deferred with them). }
          { Only meaningful for a bare name; the guards below that use it are
            gated on ASTKind = AN_IDENT for exactly that reason. }
          if ASTKind[valNode] = AN_IDENT then i := ASTIVal[valNode] else i := -1;
          { AnsiString and managed-field record elements supported (see Delete
            above; the managed-record gap store is an ARC-correct
            IR_COPY_REC_MANAGED). Non-managed record and set elements too
            (memory-copied into the gap; the value must be addressable).
            Frozen strings / nested arrays still deferred. }
          if not DynTargetIsRereadable(valNode) then
            Error('Insert: dynamic-array destination must be a name, field or dereference (it is read and written back)');
          if (NodeDynBaseTk(valNode) = tyString) or
             ((ASTKind[valNode] = AN_IDENT) and (SymElemDynDepth[i] > 0)) then
            Error('Insert: frozen-string element type not yet supported for dynamic-array Insert');
          { FPC's array-SPLICE form Insert(srcArr, arr, index): the first
            argument is itself a dynamic array and ALL of its elements go in.
            Before this existed the splice compiled as the one-element form and
            stored the source's HANDLE as if it were an element -- `Insert(t, s,
            1)` on two `array of Integer` printed `10 -1428160432 11 12` where
            FPC prints `10 90 91 11 12`. Silent wrong output, so a source array
            whose element type does NOT match is refused rather than left to
            mean something plausible. }
          insSrcSym := -1;
          if (ASTKind[exprNode] = AN_IDENT) and (ASTIVal[exprNode] >= 0) and
             Syms[ASTIVal[exprNode]].IsArray and (Syms[ASTIVal[exprNode]].ArrLen = -1) then
          begin
            insSrcSym := ASTIVal[exprNode];
            if (Syms[insSrcSym].ElemType <> NodeDynBaseTk(valNode)) or
               ((NodeDynBaseTk(valNode) = tyRecord) and
                (Syms[insSrcSym].ElemRecName <> NodeDynBaseRec(valNode))) then
              Error('Insert: the source array''s element type differs from the destination''s');
            { Same depth = the SPLICE. One level shallower = an ordinary
              one-element insert of a sub-array into a nested destination
              (`Insert(row, matrix, i)`), which is not a splice at all. Any
              other relation is a type error. }
            if SymDynDepth[insSrcSym] = NodeDynDepth(valNode) - 1 then
              insSrcSym := -1
            else if SymDynDepth[insSrcSym] <> NodeDynDepth(valNode) then
              Error('Insert: the source array''s nesting differs from the destination''s');
          end;
          { A nested destination's elements are sub-array handles, so a plain
            scalar/record value cannot be one of them. }
          if (NodeDynDepth(valNode) > 1) and (insSrcSym < 0) and
             not ((ASTKind[exprNode] = AN_IDENT) and (ASTIVal[exprNode] >= 0) and
                  Syms[ASTIVal[exprNode]].IsArray) then
            Error('Insert: a nested dynamic array takes a sub-ARRAY as the inserted value');
          { A record/set VALUE no longer has to be an lvalue: those types are
            address-valued in the IR, so a function result or a set expression
            lowers to an address the gap copy can read, live for the statement.
            The old restriction was a limitation of the lowering, not of the
            language -- FPC accepts Insert(MakeP(8, 9), pts, 1). }
          Expect(tkComma, ','); ParseExpr; opNode := CurASTNode;      { index }
          Expect(tkRParen, ')');
          if FindProc('PXXDynInsFill') < 0 then
            Error('Insert: dynamic-array helper unavailable (needs the builtin unit; not on ESP)');
          if (insSrcSym >= 0) and (FindProc('PXXDynInsArrFill') < 0) then
            Error('Insert: array-splice helper unavailable (needs the builtin unit; not on ESP)');
          stepsNode := AllocNode(AN_DYN_INSERT);
          if insSrcSym >= 0 then ASTIVal[stepsNode] := 1 else ASTIVal[stepsNode] := 0;
          ASTLeft[stepsNode] := valNode;
          argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := exprNode;   { value }
          lastArg := AllocNode(AN_ARG); ASTLeft[lastArg] := opNode;   { index }
          ASTRight[argSeq] := lastArg;
          ASTRight[stepsNode] := argSeq;
          ASTTk[stepsNode] := Ord(tyPointer);
          argIdx := CloneAST(valNode);   { see Delete's write-back note }
          if ASTKind[argIdx] = AN_IDENT then ASTTk[argIdx] := Ord(tyPointer);
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
      else if CaseEqual(name, 'SetLength') and SoftIntrinsicOpen('SetLength', qUnit) and
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
          { FindVarSym, not FindSym: a bare `class var` target used to resolve to -1
            here and fall through to the STRING arm of the classification below,
            writing a string header over a dynamic-array handle. }
          idx := FindVarSym(CurTok.SVal);
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
      else if CaseEqual(name, 'New') and SoftIntrinsicOpen('New', qUnit) and
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
      else if CaseEqual(name, 'Dispose') and SoftIntrinsicOpen('Dispose', qUnit) and
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
      else if CaseEqual(name, 'ReallocMem') and SoftIntrinsicOpen('ReallocMem', qUnit) and
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
      else if CaseEqual(name, 'Str') and SoftIntrinsicOpen('Str', qUnit) and
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
        { ...and an UNSIGNED value takes StrQWord, the same dispatch write(Text)
          and stdout make. Str had none at all, so `Str(q, s)` on a QWord >= 2^63
          produced `-1` -- a silent wrong VALUE, while `writeln(q)` two lines
          away was right. bug-p-str-of-a-qword-formats-it-signed }
        if strIsFloat then procIdx := FindProc('StrFloat')
        else if TypeIsOrdinal(IntToTypeKind(ASTTk[exprNode])) and
                (not TypeSigned(IntToTypeKind(ASTTk[exprNode]))) and
                (IntToTypeKind(ASTTk[exprNode]) <> tyChar) and
                (IntToTypeKind(ASTTk[exprNode]) <> tyBoolean) then
          procIdx := FindProc('StrQWord')
        else procIdx := FindProc('StrInt');
        if procIdx < 0 then Error('Str: builtin unit not loaded');
        { float with NO width: -1 selects FPC's default scientific Str form
          (` d.ddd...E+eee`) in StrFloat; an explicit width keeps the fixed/
          natural formatter. Integers keep 0 (plain digits, FPC-identical). }
        if stepsNode < 0 then
        begin
          if strIsFloat and (decNode < 0) then stepsNode := GenMakeIntLit(-1)
          else stepsNode := GenMakeIntLit(0);
        end;
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
        { `code` is OPTIONAL in FPC — `Val(s, i)` is ordinary code, and it was
          refused here with "Expected: ,". Measured against FPC 3.2.2: the
          two-argument form behaves exactly like the three-argument one with
          the code thrown away (a failed conversion leaves the destination 0
          and raises nothing), so a hidden temp is the whole of it.
          bug-p-val-rejects-the-radix-prefixes }
        if CurTok.Kind = tkComma then
        begin
          Next;
          if CurTok.Kind <> tkIdent then Error('Val: expected code variable');
          si := FindSym(CurTok.SVal); argIdx := TokPos - 1; Next;
          stepsNode := ParseLValueAST(si, argIdx);          { code }
        end
        else
        begin
          stepsNode := AllocNode(AN_IDENT);
          ASTIVal[stepsNode] := AllocVar('', tyInteger);
          ASTTk[stepsNode] := Ord(tyInteger);
        end;
        Expect(tkRParen, ')');

        if (idx >= 0) and TypeIsFloat(Syms[idx].TypeKind) then procIdx := FindProc('ValFloat')
        else if (idx >= 0) and (Syms[idx].TypeKind = tyUInt64) then
          { QWord destination: the unsigned, RANGE-CHECKED variant — the Int64
            Val cannot know its caller's signedness (tint642 testqwordstr). }
          procIdx := FindProc('ValQWord')
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
        if (CurTok.Kind <> tkIdent) and (CurTok.Kind <> tkInteger) then
          Error('expected a label name or number after goto');
        node := AllocNode(AN_GOTO);
        LabelSpanOfTok(TokPos-1, ASTSOffset[node], ASTSLen[node]);
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
        { qUnit = -1 ONLY: a `System.`-qualified name (qUnit = -2) explicitly
          names the builtin/RTL routine, so the enclosing class's same-named
          method must NOT shadow it — fpjson's TJSONArray.DoFindPath calls
          System.Delete(E,1,P) precisely because the class has its own
          Delete(Index); the shadow-clear sent it to the METHOD with mangled
          args (silent wrong dispatch, then a crash on FList). }
        { …not in NilPy: Python reaches a method only through `self.`, so a bare
          call names the module-level function even when the class declares one
          of the same name. songformatter has `def select_image(self):
          select_image()` — a method delegating to the module function it
          shadows — and the shadow-clear turned it into a call of ITSELF. }
        { the statement-side twin — see the expression site for why this is
          NilPyUserCode and not isNilPy; the two MUST move together }
        if (procIdx >= 0) and (qUnit = -1) and (si < 0) and (not NilPyUserCode) and
           (CurSelfClass >= REC_UCLASS_BASE) and
           (FindUMeth(CurSelfClass - REC_UCLASS_BASE, name) >= 0) then
          procIdx := -1;

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
      if (procIdx < 0) and (si < 0) and (qUnit < 0) and
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
            Result := node;
            Exit;
          end;
        end;
      end;

        { A SELECTOR after a function call used as a statement:
          `GetRegistry.AddTest(X);` / `GetBox.Val := 5;` / `GetBoxAt(I).M(...)`.
          The plain call branches below consume only the call itself; the trailing
          `.member` then fell into the default skip-to-';' branch and the WHOLE
          statement was silently dropped (fpjson's RegisterTest registered
          nothing). The expression parser already resolves the full chain — incl.
          method calls on the result — so delegate the statement to it, same
          shape as the tkLParen `(o as T).M;` case. A trailing `:=` makes it a
          store through the result's member. (bug-pascal-statement-call-result-selector) }
        if (procIdx >= 0) and (si < 0) and Procs[procIdx].IsFunc then
        begin
          { Every selector token counts, not just `.`: `f(i)^ := v`,
            `f(i)^.fld := v` and `f(i)^[j] := v` are the same statement shape
            reached through `^`/`[`, and while only `.` was recognised those
            stores were silently DROPPED — the call was emitted and the rest of
            the statement skipped to the `;` with no diagnostic
            (bug-a-assignment-through-a-pointer-returned-by-a-function-call-is-dropped). }
          frDot := Tokens[TokPos].Kind in [tkDot, tkCaret, tkLBrack];
          if (not frDot) and (Tokens[TokPos].Kind = tkLParen) then
          begin
            { scan the matching ')' — a selector right after it makes this a
              call-result selector statement }
            i := TokPos; smMai := 0;
            repeat
              if Tokens[i].Kind = tkLParen then Inc(smMai)
              else if Tokens[i].Kind = tkRParen then Dec(smMai);
              Inc(i);
            until (smMai = 0) or (Tokens[i].Kind = tkEOF);
            frDot := Tokens[i].Kind in [tkDot, tkCaret, tkLBrack];
          end;
          if frDot then
          begin
            { A STATEMENT delegated to the expression parser, exactly like the
              tkLParen branch — so the no-result-call check stands down for it.
              `GetBox.Poke;` (test_stmt_call_result_selector_b318) is the shape,
              and TRACK T caught it: gate.sh quick, gate.sh lib, 34 demos and
              the whole fpc probe were green with this false positive in place.
              Only the statement's own expression is wrapped; the RHS after a
              trailing `:=` below is a genuine value context and stays checked. }
            Inc(StmtCallDepth);
            ParseExpr;
            Dec(StmtCallDepth);
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
            Result := node;
            Exit;
          end;
        end;

        if (procIdx >= 0) and (Tokens[TokPos].Kind = tkLParen) then
        begin
          Next;
          { keyword-name-aware overload re-target, statement-position twin of
            the expression-position fix above (bug-nilpy-keyword-arg-vs-overload-set) }
          if isNilPy then procIdx := PyPromoteProcOverloadByKwAt(procIdx, 0, PyKwNamesTokPos);
          Expect(tkLParen, '(');
          argsHead := -1;
          lastArg := -1;
          nArgs := 0;
          while CurTok.Kind <> tkRParen do
          begin
            kwIdx := PyKwArgIndex(procIdx, 0);
            if kwIdx > 0 then slotIdx := kwIdx - 1 else slotIdx := nArgs;
            if (CurTok.Kind = tkLBrack) and ParamIsVarRecArray(procIdx, slotIdx) then
              CurASTNode := ParseVarRecLiteralAST
            else if (CurTok.Kind = tkLBrack) and ParamIsOpenArrayScalar(procIdx, slotIdx) then
              CurASTNode := ParseArrayCtorAST(Procs[procIdx].Params[slotIdx].TypeKind,
              ProcParamElemRowLen[procIdx * MAX_PROC_PARAMS + slotIdx], ProcParamElemRowLo[procIdx * MAX_PROC_PARAMS + slotIdx])
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

          { see the twin site: a builtin TYPE in a callback slot, before the
            types that pick the overload are read }
          if isNilPy then PyFixCallableTypeArgs(name, argsHead, nArgs);
          currArg := argsHead;
          for i := 0 to nArgs - 1 do
          begin
            exprNode := ASTLeft[currArg];
            argTypes[i] := IntToTypeKind(ASTTk[exprNode]);
            { `@obj.Method` fills a method-pointer (`of object`, tyRecord) param —
              see the twin site above (bug-pascal-methodref-arg-to-named-of-object-
              param-no-match). }
            if ASTKind[exprNode] = AN_METHODREF then argTypes[i] := tyRecord;
            currArg := ASTRight[currArg];
          end;

          procIdx := MatchCallDelphiProcAddr(name, qUnit, nArgs, argsHead, argTypes);
          { see the twin expression site: a user iterable meeting a pylib
            container parameter (bug-nilpy-builtins-over-a-user-iterable-
            answer-empty) }
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
            procIdx := TryFillTrailingDefaults(name, qUnit, nArgs, argsHead, lastArg);
          if procIdx < 0 then
            Error('no overload of ' + name + ' matches these arguments' + OverloadReport);

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
                      (ASTKind[exprNode] = AN_DEREF) or IsVarArgLvalueCast(exprNode) or
                      (ASTKind[exprNode] = AN_METHODREF)) then
              begin
                { The OVERLOADED-call twin of the check in pasparser_expr.inc,
                  and the reason both now call one predicate: the two copies had
                  already diverged — this one never learned the promo-int arm,
                  so `f(g())` for a promotable-int parameter was accepted at one
                  call site and refused at the other.
                  bug-a-a-non-lvalue-is-refused-as-an-interface-argument }
                if ByRefArgNeedsLvalue(procIdx, i) then
                  Error('by-reference argument must be a variable');
              end;
            end;
            currArg := ASTRight[currArg];
          end;

          node := AllocNode(AN_CALL);
          ASTIVal[node] := procIdx;
          ASTLeft[node] := argsHead;
        end
        else if (si < 0) and (procIdx >= 0) and
                ((Procs[procIdx].ParamCount = 0) or
                 ((Procs[procIdx].ParamCount > 0) and
                  ProcParamHasDefault[procIdx * MAX_PROC_PARAMS + 0])) then
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
          { ...or every parameter is DEFAULTED, which is paramless at the call
            site: `procedure P(k: Integer = 3)` then `P;`. FPC accepts it, `P()`
            already worked, and so did `b.G` for a METHOD with defaults — the
            member-access route reaches the fill, this one tested ParamCount = 0
            and so never did, dropping the name through to the assignment path
            where it died as "undefined variable (P)". The diagnostic was the
            misleading part: the NAME had resolved, the ARITY had not.

            Testing parameter 0 alone is sufficient because Pascal requires
            defaults to be TRAILING — if the first one has a default, all do.
            bug-p-parenless-call-to-an-all-defaulted-routine-is-an-undefined-variable. }
          if Procs[procIdx].ParamCount > 0 then
          begin
            lastArg := -1;
            FillDefaultArgs(procIdx, 0, node, lastArg);
          end;
          { the twin of the expression site's marker — see ASTCallParenless }
          ASTCallParenless[node] := True;
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
            smmii := FindUMethOverloadAhead(smci, name, CountCallArgsAhead);
            if smmii >= 0 then
            begin
              EnforceMethVis(smmii, name);
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
            if CaseEqual(name, 'TObject') and (FindUClass(name) < 0) and
               (Tokens[TokPos].Kind = tkLParen) then
            begin
              { `TObject(expr).Free;` — cast to the implicit root as a
                statement (Pascal Script's TPSList.Clear). Retag + the
                builtin Free desugar (no Destroy — the root has none). }
              Next; Expect(tkLParen, '(');
              ParseExpr;
              Expect(tkRParen, ')');
              ASTTk[CurASTNode] := Ord(tyClass);
              if (CurTok.Kind = tkDot) and (TokPos < TokCount) and
                 (Tokens[TokPos].Kind = tkIdent) and
                 CaseEqual(GetTokenStr(TokPos), 'Free') and
                 (Tokens[TokPos+1].Kind in [tkSemicolon, tkEnd, tkElse]) then
              begin
                Next; Next;   { '.', 'Free' }
                node := GenMakeFreeObjectExpr(CurASTNode, -1);
                Result := node; Exit;
              end
              else
                Error('TObject(...) as a statement supports only .Free');
            end;
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
              if (ASTKind[valNode] = AN_CALL) or (ASTKind[valNode] = AN_VIRTUAL_CALL) or
                 (ASTKind[valNode] = AN_INTF_CALL) then
                { TClass(x).Method(args); — a method-call statement, not an assign.
                  AN_INTF_CALL covers the interface form IFoo(List[i]).M(args). }
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

          if (node = -1) and (Tokens[TokPos].Kind = tkLParen) and
             (not StatementIsAssignment) and
             ((IsRecordType(name) <> REC_NONE) or (FindTypeAlias(name) >= 0)) then
          begin
            { A cast-headed statement with no `:=` in it is a CALL, so hand the
              whole thing to the expression parser, which already builds this
              chain correctly (it is what the right-hand side of an assignment
              uses). The two lvalue paths below cannot: they resolve every `.name`
              as a FIELD and end on Expect(:=). Same shape as the class-cast path
              above, which delegates its selectors and keeps the node when it
              comes back a call. }
            Inc(StmtCallDepth);   { it IS a statement: a procedure call is fine }
            ParseExpr;
            Dec(StmtCallDepth);
            node := CurASTNode;
            if not ((ASTKind[node] = AN_CALL) or (ASTKind[node] = AN_VIRTUAL_CALL) or
                    (ASTKind[node] = AN_INTF_CALL) or (ASTKind[node] = AN_CALL_IND)) then
              Error('statement is neither a call nor an assignment');
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
              if CurTok.Kind = tkDot then
              begin
                { `TRec(q).field := v` — in-place value typecast, same shape as
                  the expression side: rec-tagged deref of @operand so the field
                  offset resolves (bug-pascal-record-cast-field-offset). }
                fieldNode := AllocNode(AN_ADDR);
                ASTLeft[fieldNode] := ASTLeft[valNode];
                ASTTk[fieldNode] := Ord(tyPointer);
                valNode := AllocNode(AN_DEREF);
                ASTLeft[valNode] := fieldNode;
                ASTIVal[valNode] := castRec;     { pointee rec for ResolveNodeRec }
                ASTTk[valNode] := Ord(tyRecord);
              end;
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
                idx := OwnFieldBeatsSym(FindSym(name), name);
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

              { Bare, PARENLESS call of a proc-var / method-pointer AS A STATEMENT:
                `AMethod;` -- fpcunit's AssertException invokes the TRunMethod it was
                handed exactly so.

                POSITION is the only thing that disambiguates this, and it has to be
                read narrowly. A bare proc-var name is a VALUE nearly everywhere:
                `q := p`, `Foo(cb)`, `Assigned(p)`. It is a CALL only when the whole
                statement is the name -- nothing else it could mean. So the test is
                made HERE, in the statement path, on the token that FOLLOWS the name
                (same shape as `obj.Free;` above), and NOT inside ParseLValueAST:
                that runs for expression atoms too, where the next token is just as
                often a ';' -- putting it there turned `q := p;` into a call of p.

                Zero-parameter signatures only: anything taking arguments has to be
                written with them. }
              if (idx >= 0) and (SymProcSig[idx] >= 0) and
                 (Tokens[TokPos].Kind in [tkSemicolon, tkEnd, tkElse, tkUntil,
                                          tkFinally, tkExcept]) and
                 (Procs[SymProcSig[idx]].ParamCount = 0) then
              begin
                pvSig := SymProcSig[idx];
                pvIsMeth := Syms[idx].TypeKind = tyRecord;
                Next;                      { consume the proc-var name }
                pvTarget := AllocNode(AN_IDENT);
                ASTIVal[pvTarget] := idx;
                if pvIsMeth then ASTTk[pvTarget] := Ord(tyRecord)
                else ASTTk[pvTarget] := Ord(tyPointer);
                node := AllocNode(AN_CALL_IND);
                ASTLeft[node]  := -1;      { no args }
                ASTRight[node] := pvTarget;
                ASTIVal[node]  := pvSig;
                ASTTk[node]    := Ord(Procs[pvSig].RetType);
                if pvIsMeth then ASTSLen[node] := 1 else ASTSLen[node] := 0;
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
              else if CurTok.Kind in [tkPlusEq, tkMinusEq, tkStarEq, tkSlashEq] then
              begin
                { Pascal compound assignment `a += e;` (and -= *= /=) — FPC's
                  {$COPERATORS} extension, always-on here like the rest of the
                  lax dialect (rtl-generics' hash mixers use it heavily). The
                  expression parser already owns the node + IR lowering (the C
                  frontend's path); this just accepts it in statement position. }
                castPrevTok := Ord(CurTok.Kind); Next;
                ParseExpr;
                node := AllocNode(AN_COMPOUND_ASSIGN);
                ASTLeft[node] := valNode; ASTRight[node] := CurASTNode;
                if castPrevTok = Ord(tkPlusEq) then ASTIVal[node] := Ord(tkPlus)
                else if castPrevTok = Ord(tkMinusEq) then ASTIVal[node] := Ord(tkMinus)
                else if castPrevTok = Ord(tkStarEq) then ASTIVal[node] := Ord(tkStar)
                else ASTIVal[node] := Ord(tkSlash);
                ASTTk[node] := ASTTk[valNode];
              end
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
                  ASTRight[CurASTNode] := UMthVirSlot[smmii];   { VMT slot (>=0 virtual) }
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
      { A STATEMENT, parsed with the expression parser — so ParseFactor's
        no-result-call check has to stand down here, or `(o as T).M;` on a
        `procedure M` becomes an error. The probe case as-inline-call is
        exactly that and caught this. }
      Inc(StmtCallDepth);
      ParseExpr;
      Dec(StmtCallDepth);
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
  ASTNodeCount := ASTArenaFloor;
end;

{ The MAIN PROGRAM BODY (its only caller), so the globals' management
  operators are woven in here the way a routine's locals are in
  ParseSubroutine. }
procedure ParseBlock;
var node: Integer;
begin
  node := WrapMainBodyManagementOps(ParseBlockAST);
  CompileAST(node);
  ASTNodeCount := ASTArenaFloor;
end;
