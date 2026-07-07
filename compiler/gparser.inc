{ SPDX-License-Identifier: MPL-2.0 }
{ ===== Algol 60 Parser (skeleton) =====
  Esoteric-frontend-probe (feature-esoteric-algol): the kinship probe —
  Algol 60 is Pascal's direct ancestor, so if this subset does NOT lower
  cleanly onto the shared AST/IR, the IR has baked in Pascal-specific
  assumptions (that finding would be the probe's payoff; a clean pass is
  the expected boring-good outcome). Hand-built AST over existing AN_*
  nodes, rparser.inc node helpers, Ada-parser structure.

  v1 subset: one top-level `begin <declarations>; <statements> end`
  block, declarations `integer a, b; real x; Boolean f;`, assignment
  `:=`, `if <cond> then <stmt> [else <stmt>]`, `while <cond> do <stmt>`
  (the RRS spells it `for ... while`, but bare while is accepted in
  every practical Algol dialect and keeps the probe focused),
  `for v := lo step s until hi do <stmt>` (constant integer step,
  positive or negative, inclusive bound — Algol's more general for-list
  is cut), compound statements via nested begin/end, and I/O as
  `outinteger(1, expr)` / `outreal(1, expr)` / `outstring(1, 'text')`
  (channel argument accepted and ignored; each call emits one writeln —
  a formatting simplification, documented here).

  Explicit cuts, loud not silent: call-by-name (Jensen's device) and all
  procedure declarations — `procedure` errors with a real message; `own`
  variables — same. }

function GParseStatement: Integer; forward;
function GParseExpr: Integer; forward;

function GCurIs(const kw: AnsiString): Boolean;
var lower: AnsiString; i: Integer;
begin
  if CurTok.Kind <> tkIdent then begin Result := False; Exit; end;
  SetLength(lower, Length(CurTok.SVal));
  for i := 1 to Length(CurTok.SVal) do
  begin
    if CurTok.SVal[i] in ['A'..'Z'] then lower[i] := Chr(Ord(CurTok.SVal[i]) + 32)
    else lower[i] := CurTok.SVal[i];
  end;
  Result := lower = kw;
end;

function GParsePrimary: Integer;
var node: Integer; name: AnsiString; symIdx: Integer;
begin
  if CurTok.Kind = tkInteger then
  begin
    node := AllocNode(AN_INT_LIT);
    ASTIVal[node] := CurTok.IVal;
    ASTTk[node] := Ord(tyInt64);
    Next; Result := node; Exit;
  end;
  if CurTok.Kind = tkFloat then
  begin
    node := AllocNode(AN_FLOAT_LIT);
    ASTIVal[node] := CurTok.IVal;
    ASTTk[node] := Ord(tyDouble);
    Next; Result := node; Exit;
  end;
  if CurTok.Kind = tkString then
  begin
    node := AllocNode(AN_STR_LIT);
    ASTSOffset[node] := Tokens[TokPos - 1].SOffset;
    ASTSLen[node] := Tokens[TokPos - 1].SLen;
    ASTTk[node] := Ord(tyString);
    Next; Result := node; Exit;
  end;
  if GCurIs('true') or GCurIs('false') then
  begin
    node := AllocNode(AN_BOOL_LIT);
    if GCurIs('true') then ASTIVal[node] := 1 else ASTIVal[node] := 0;
    ASTTk[node] := Ord(tyBoolean);
    Next; Result := node; Exit;
  end;
  if CurTok.Kind = tkLParen then
  begin
    Next;
    node := GParseExpr;
    Expect(tkRParen, ')');
    Result := node; Exit;
  end;
  if CurTok.Kind = tkMinus then
  begin
    Next;
    node := AllocNode(AN_NEG);
    ASTLeft[node] := GParsePrimary();
    ASTTk[node] := ASTTk[ASTLeft[node]];
    Result := node; Exit;
  end;
  if CurTok.Kind = tkNot then
  begin
    Next;
    node := AllocNode(AN_NOT);
    ASTLeft[node] := GParsePrimary();
    ASTTk[node] := Ord(tyBoolean);
    Result := node; Exit;
  end;
  if CurTok.Kind = tkIdent then
  begin
    name := CurTok.SVal;
    symIdx := FindSym(name);
    if symIdx < 0 then Error('Algol: undeclared identifier ' + name + ' (Algol declares before use)');
    Next;
    Result := RMakeIdent(symIdx);
    Exit;
  end;
  Error('Algol: unexpected token in expression');
  Result := -1;
end;

function GParseMul: Integer;
var left, right: Integer; opTk: TTokenKind;
begin
  left := GParsePrimary;
  while CurTok.Kind in [tkStar, tkSlash] do
  begin
    opTk := CurTok.Kind; Next;
    right := GParsePrimary;
    left := RBinOp(opTk, left, right, RWiden(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])));
  end;
  Result := left;
end;

function GParseAdd: Integer;
var left, right: Integer; opTk: TTokenKind;
begin
  left := GParseMul;
  while CurTok.Kind in [tkPlus, tkMinus] do
  begin
    opTk := CurTok.Kind; Next;
    right := GParseMul;
    left := RBinOp(opTk, left, right, RWiden(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])));
  end;
  Result := left;
end;

function GParseCmp: Integer;
var left, right: Integer; opTk: TTokenKind;
begin
  left := GParseAdd;
  if CurTok.Kind in [tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe] then
  begin
    opTk := CurTok.Kind; Next;
    right := GParseAdd;
    left := RBinOp(opTk, left, right, tyBoolean);
  end;
  Result := left;
end;

function GParseAnd: Integer;
var left, right: Integer;
begin
  left := GParseCmp;
  while CurTok.Kind = tkAnd do
  begin
    Next;
    right := GParseCmp;
    left := RBinOp(tkAnd, left, right, tyBoolean);
  end;
  Result := left;
end;

function GParseExpr: Integer;
var left, right: Integer;
begin
  left := GParseAnd;
  while CurTok.Kind = tkOr do
  begin
    Next;
    right := GParseAnd;
    left := RBinOp(tkOr, left, right, tyBoolean);
  end;
  Result := left;
end;

{ outinteger/outreal/outstring(channel, value) -> one writeln per call;
  channel parsed and discarded (must be a literal integer in v1) }
function GParseOutCall: Integer;
var node, argNode, exprNode: Integer;
begin
  Next;   { outinteger / outreal / outstring }
  Expect(tkLParen, '(');
  if CurTok.Kind <> tkInteger then Error('Algol: expected literal channel number in out-call');
  Next;   { channel — ignored }
  Expect(tkComma, ',');
  exprNode := GParseExpr;
  Expect(tkRParen, ')');
  node := AllocNode(AN_WRITE);
  ASTKind[node] := AN_WRITELN;
  argNode := AllocNode(AN_ARG);
  ASTLeft[argNode] := exprNode;
  ASTRight[argNode] := -1;
  ASTSOffset[argNode] := -1;   { decimals sentinel: -1 = none (see fparser) }
  ASTLeft[node] := argNode;
  Result := node;
end;

{ a <statement>: single statement or a begin ... end compound }
function GParseStatement: Integer;
var node, condNode, thenNode, elseNode, pairNode, bodyNode: Integer;
    loNode, hiNode, initNode, incNode, whileNode: Integer;
    name: AnsiString;
    symIdx: Integer;
    stepVal: Int64;
    stmtList, stmt: Integer;
begin
  Result := -1;

  { compound statement }
  if CurTok.Kind = tkBegin then
  begin
    Next;
    stmtList := -1;
    while CurTok.Kind <> tkEnd do
    begin
      if CurTok.Kind = tkEOF then Error('Algol: unterminated begin block');
      if CurTok.Kind = tkSemicolon then begin Next; end
      else
      begin
        stmt := GParseStatement();
        stmtList := RSeqAppend(stmtList, stmt);
      end;
    end;
    Next;   { end }
    Result := stmtList;
    Exit;
  end;

  if CurTok.Kind = tkIf then
  begin
    Next;
    condNode := GParseExpr;
    Expect(tkThen, 'then');
    thenNode := GParseStatement();
    elseNode := -1;
    if CurTok.Kind = tkElse then
    begin
      Next;
      elseNode := GParseStatement();
    end;
    node := AllocNode(AN_IF);
    ASTLeft[node] := condNode;
    pairNode := AllocNode(AN_PAIR);
    ASTLeft[pairNode] := thenNode;
    ASTRight[pairNode] := elseNode;
    ASTRight[node] := pairNode;
    ASTTk[node] := Ord(tyUnknown);
    Result := node;
    Exit;
  end;

  if CurTok.Kind = tkWhile then
  begin
    Next;
    condNode := GParseExpr;
    Expect(tkDo, 'do');
    bodyNode := GParseStatement();
    node := AllocNode(AN_WHILE);
    ASTLeft[node] := condNode;
    ASTRight[node] := bodyNode;
    ASTTk[node] := Ord(tyUnknown);
    Result := node;
    Exit;
  end;

  { for v := lo step s until hi do <stmt> — inclusive; desugared like the
    BASIC/Ada/Fortran counting loops (v := lo; while v <=/>= hi do body+inc) }
  if CurTok.Kind = tkFor then
  begin
    Next;
    if CurTok.Kind <> tkIdent then Error('Algol: expected control variable after for');
    name := CurTok.SVal;
    symIdx := FindSym(name);
    if symIdx < 0 then Error('Algol: undeclared for-variable ' + name);
    Next;
    Expect(tkAssign, ':=');
    loNode := GParseExpr;
    stepVal := 1;
    if GCurIs('step') then
    begin
      Next;
      if CurTok.Kind = tkMinus then
      begin
        Next;
        if CurTok.Kind <> tkInteger then Error('Algol: for step must be an integer constant (skeleton)');
        stepVal := -CurTok.IVal;
        Next;
      end
      else
      begin
        if CurTok.Kind <> tkInteger then Error('Algol: for step must be an integer constant (skeleton)');
        stepVal := CurTok.IVal;
        Next;
      end;
      if stepVal = 0 then Error('Algol: for step of 0');
    end;
    if not GCurIs('until') then Error('Algol: expected until in for (the general for-list is not in the skeleton)');
    Next;
    hiNode := GParseExpr;
    Expect(tkDo, 'do');
    bodyNode := GParseStatement();

    initNode := AllocNode(AN_ASSIGN);
    ASTLeft[initNode] := RMakeIdent(symIdx);
    ASTRight[initNode] := loNode;
    ASTTk[initNode] := Ord(tyUnknown);

    if stepVal > 0 then
      condNode := RBinOp(tkLe, RMakeIdent(symIdx), hiNode, tyBoolean)
    else
      condNode := RBinOp(tkGe, RMakeIdent(symIdx), hiNode, tyBoolean);

    incNode := AllocNode(AN_INT_LIT);
    ASTIVal[incNode] := stepVal;
    ASTTk[incNode] := Ord(tyInt64);
    incNode := RBinOp(tkPlus, RMakeIdent(symIdx), incNode, tyInt64);
    node := AllocNode(AN_ASSIGN);
    ASTLeft[node] := RMakeIdent(symIdx);
    ASTRight[node] := incNode;
    ASTTk[node] := Ord(tyUnknown);
    { bodyNode from GParseStatement can be a RAW statement node (Algol's
      do-body needs no begin/end) — RSeqAppend walks ASTRight, which on a
      raw AN_ASSIGN is the rhs EXPRESSION, so appending directly corrupts
      the tree and drops the increment (first symptom: this very loop
      never terminated). Wrap it into a fresh seq first; a compound body
      (already a chain) nests fine as a seq's Left. }
    bodyNode := RSeqAppend(RSeqAppend(-1, bodyNode), node);

    whileNode := AllocNode(AN_WHILE);
    ASTLeft[whileNode] := condNode;
    ASTRight[whileNode] := bodyNode;
    ASTTk[whileNode] := Ord(tyUnknown);

    Result := RSeqAppend(RSeqAppend(-1, initNode), whileNode);
    Exit;
  end;

  if GCurIs('outinteger') or GCurIs('outreal') or GCurIs('outstring') then
  begin
    Result := GParseOutCall;
    Exit;
  end;

  if GCurIs('procedure') or GCurIs('own') then
    Error('Algol: procedure declarations / own variables are not in the skeleton subset (feature-esoteric-algol non-goals; call-by-name is the documented cut)');

  { assignment }
  if CurTok.Kind = tkIdent then
  begin
    name := CurTok.SVal;
    symIdx := FindSym(name);
    if symIdx < 0 then Error('Algol: undeclared identifier ' + name);
    Next;
    Expect(tkAssign, ':=');
    node := AllocNode(AN_ASSIGN);
    ASTLeft[node] := RMakeIdent(symIdx);
    ASTRight[node] := GParseExpr;
    ASTTk[node] := Ord(tyUnknown);
    Result := node;
    Exit;
  end;

  Error('Algol: unexpected statement');
end;

procedure ParseGProgram;
var stmtList, stmt: Integer;
    vtype: TTypeKind;
begin
  if TargetArch <> TARGET_X86_64 then
    Error('Algol frontend: only the x86-64 target is supported by the skeleton (feature-esoteric-algol)');

  BSS_INITIAL_RSP := BSSSize; Inc(BSSSize, 8);
  EmitB($48); EmitB($89); EmitB($24); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);

  Expect(tkBegin, 'begin');

  { declaration part: `integer a, b; real x; Boolean f;` until a
    non-declaration statement starts }
  while GCurIs('integer') or GCurIs('real') or GCurIs('boolean') do
  begin
    if GCurIs('integer') then vtype := tyInt64
    else if GCurIs('real') then vtype := tyDouble
    else vtype := tyBoolean;
    Next;
    repeat
      if CurTok.Kind <> tkIdent then Error('Algol: expected identifier in declaration');
      AllocVar(CurTok.SVal, vtype);
      Next;
    until not Eat(tkComma);
    Expect(tkSemicolon, ';');
  end;

  stmtList := -1;
  while CurTok.Kind <> tkEnd do
  begin
    if CurTok.Kind = tkEOF then Error('Algol: missing final end');
    if CurTok.Kind = tkSemicolon then begin Next; end
    else
    begin
      stmt := GParseStatement;
      stmtList := RSeqAppend(stmtList, stmt);
    end;
  end;
  Next;   { the final end }

  CurASTNode := AllocNode(AN_BLOCK);
  ASTLeft[CurASTNode] := stmtList;
  ASTTk[CurASTNode] := Ord(tyUnknown);

  CompileAST(CurASTNode);
  EmitExit(0);
end;
