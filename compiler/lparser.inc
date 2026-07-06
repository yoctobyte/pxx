{ SPDX-License-Identifier: MPL-2.0 }
{ ===== LOLCODE Parser (skeleton) =====
  Esoteric-frontend-probe (feature-esoteric-lolcode): hand-builds AST like
  aparser/zparser, reusing rparser.inc's node helpers (RSeqAppend/RMakeIdent/
  RBinOp/RWiden — included earlier in compiler.pas) and only existing AN_*
  nodes. No new AST, no new IR, no backend work.

  v1 subset (statements are newline/comma-separated; keywords are matched
  as UPPERCASE word phrases, canonical LOLCODE spelling):
    HAI [version] ... KTHXBYE          program bounds
    I HAS A x [ITZ expr]               declare (type inferred: NUMBR->Int64,
                                       YARN->string, TROOF->boolean)
    x R expr                           assign
    VISIBLE expr [AN expr]...          print (one writeln, args in order)
    <expr>, O RLY? YA RLY ... [NO WAI ...] OIC     if/else (the expression
                                       is used directly as the condition —
                                       the IT variable is NOT implemented)
    IM IN YR name ... IM OUTTA YR name             infinite loop
    GTFO                               break out of the loop
  Expressions are LOLCODE's prefix forms — no precedence needed:
    SUM OF a AN b / DIFF OF / PRODUKT OF / QUOSHUNT OF / MOD OF
    BOTH SAEM a AN b / DIFFRINT a AN b
    SMOOSH a AN b [AN c]... MKAY       string concat
    WIN / FAIL                         TROOF literals
  Out of scope (probe cap): IT, GIMMEH, NUMBAR floats, MAEK/IS NOW A casts,
  BIGGR/SMALLR OF, ANY/ALL OF, functions (HOW IZ I), buckets. }

function LParseExpr: Integer; forward;
function LParseBlockUntil(const t1a, t1b, t2a, t2b: AnsiString): Integer; forward;

function LTokIs(i: Integer; const kw: AnsiString): Boolean;
begin
  Result := (Tokens[i].Kind = tkIdent) and (GetTokenStr(i) = kw);
end;

function LCurIs(const kw: AnsiString): Boolean;
begin
  Result := (CurTok.Kind = tkIdent) and (CurTok.SVal = kw);
end;

{ two-word phrase check at the current position (CurTok + the next token) }
function LPhraseIs(const w1, w2: AnsiString): Boolean;
begin
  Result := LCurIs(w1) and (TokPos < TokCount) and LTokIs(TokPos, w2);
end;

procedure LEatSep;
begin
  while CurTok.Kind = tkSemicolon do Next;
end;

procedure LExpectWord(const kw: AnsiString);
begin
  if not LCurIs(kw) then Error('LOLCODE: expected ' + kw);
  Next;
end;

{ prefix binary form: <OP> OF a AN b (opWord already consumed by caller) }
function LParseBinTail(op: TTokenKind; boolResult: Boolean): Integer;
var a, b: Integer; rt: TTypeKind;
begin
  a := LParseExpr;
  LExpectWord('AN');
  b := LParseExpr;
  if boolResult then rt := tyBoolean
  else rt := RWiden(IntToTypeKind(ASTTk[a]), IntToTypeKind(ASTTk[b]));
  Result := RBinOp(op, a, b, rt);
end;

function LParseExpr: Integer;
var node, a, b: Integer; name: AnsiString; symIdx: Integer;
begin
  if CurTok.Kind = tkInteger then
  begin
    node := AllocNode(AN_INT_LIT);
    ASTIVal[node] := CurTok.IVal;
    ASTTk[node] := Ord(tyInt64);
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
  if LCurIs('WIN') or LCurIs('FAIL') then
  begin
    node := AllocNode(AN_BOOL_LIT);
    if LCurIs('WIN') then ASTIVal[node] := 1 else ASTIVal[node] := 0;
    ASTTk[node] := Ord(tyBoolean);
    Next; Result := node; Exit;
  end;
  if LPhraseIs('SUM', 'OF') then begin Next; Next; Result := LParseBinTail(tkPlus, False); Exit; end;
  if LPhraseIs('DIFF', 'OF') then begin Next; Next; Result := LParseBinTail(tkMinus, False); Exit; end;
  if LPhraseIs('PRODUKT', 'OF') then begin Next; Next; Result := LParseBinTail(tkStar, False); Exit; end;
  if LPhraseIs('QUOSHUNT', 'OF') then begin Next; Next; Result := LParseBinTail(tkDiv, False); Exit; end;
  if LPhraseIs('MOD', 'OF') then begin Next; Next; Result := LParseBinTail(tkMod, False); Exit; end;
  if LPhraseIs('BOTH', 'SAEM') then begin Next; Next; Result := LParseBinTail(tkEq, True); Exit; end;
  if LCurIs('DIFFRINT') then begin Next; Result := LParseBinTail(tkNeq, True); Exit; end;
  if LCurIs('SMOOSH') then
  begin
    { SMOOSH a AN b [AN c]... MKAY — left-fold string concat on tkPlus,
      the same shared BINOP Pascal's s1 + s2 lowers through. The parens on
      LParseExpr() are load-bearing: a bare name here inside LParseExpr's
      own body reads the Result variable instead of recursing (documented
      project pitfall — and yes, this line shipped without them first). }
    Next;
    a := LParseExpr();
    while LCurIs('AN') do
    begin
      Next;
      b := LParseExpr();
      a := RBinOp(tkPlus, a, b, tyString);
    end;
    if LCurIs('MKAY') then Next;
    Result := a;
    Exit;
  end;
  if CurTok.Kind = tkIdent then
  begin
    name := CurTok.SVal;
    symIdx := FindSym(name);
    if symIdx < 0 then Error('LOLCODE: undefined variable ' + name);
    Next;
    Result := RMakeIdent(symIdx);
    Exit;
  end;
  Error('LOLCODE: unexpected token in expression');
  Result := -1;
end;

function LParseStatement: Integer;
var node, exprNode, thenN, elseN, condN, bodyN, argNode, lastArg: Integer;
    name, loopName: AnsiString;
    symIdx: Integer;
    vtype: TTypeKind;
begin
  Result := -1;

  { I HAS A x [ITZ expr] }
  if LPhraseIs('I', 'HAS') then
  begin
    Next; Next;                 { I HAS }
    LExpectWord('A');
    if CurTok.Kind <> tkIdent then Error('LOLCODE: expected variable name after I HAS A');
    name := CurTok.SVal;
    Next;
    if LCurIs('ITZ') then
    begin
      Next;
      exprNode := LParseExpr;
      vtype := IntToTypeKind(ASTTk[exprNode]);
      if (vtype = tyUnknown) or (vtype = tyInteger) then vtype := tyInt64;
      symIdx := AllocVar(name, vtype);
      node := AllocNode(AN_ASSIGN);
      ASTLeft[node] := RMakeIdent(symIdx);
      ASTRight[node] := exprNode;
      ASTTk[node] := Ord(tyUnknown);
      Result := node;
    end
    else
      AllocVar(name, tyInt64);  { NUMBR by default, BSS-zeroed }
    Exit;
  end;

  { VISIBLE expr [AN expr]... }
  if LCurIs('VISIBLE') then
  begin
    Next;
    node := AllocNode(AN_WRITE);
    ASTKind[node] := AN_WRITELN;
    ASTLeft[node] := -1;
    lastArg := -1;
    while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do
    begin
      exprNode := LParseExpr;
      argNode := AllocNode(AN_ARG);
      ASTLeft[argNode] := exprNode;
      ASTRight[argNode] := -1;
      if lastArg < 0 then ASTLeft[node] := argNode else ASTRight[lastArg] := argNode;
      lastArg := argNode;
      if LCurIs('AN') then Next;
    end;
    Result := node;
    Exit;
  end;

  { GTFO }
  if LCurIs('GTFO') then
  begin
    Next;
    Result := AllocNode(AN_BREAK);
    ASTTk[Result] := Ord(tyUnknown);
    Exit;
  end;

  { IM IN YR name ... IM OUTTA YR name }
  if LPhraseIs('IM', 'IN') then
  begin
    Next; Next;
    LExpectWord('YR');
    if CurTok.Kind <> tkIdent then Error('LOLCODE: expected loop name after IM IN YR');
    loopName := CurTok.SVal;
    Next;
    LEatSep;
    bodyN := LParseBlockUntil('IM', 'OUTTA', '', '');
    Next; Next;                 { IM OUTTA }
    LExpectWord('YR');
    if not LCurIs(loopName) then Error('LOLCODE: IM OUTTA YR names the wrong loop (expected ' + loopName + ')');
    Next;
    condN := AllocNode(AN_BOOL_LIT);
    ASTIVal[condN] := 1;
    ASTTk[condN] := Ord(tyBoolean);
    node := AllocNode(AN_WHILE);
    ASTLeft[node] := condN;
    ASTRight[node] := bodyN;
    ASTTk[node] := Ord(tyUnknown);
    Result := node;
    Exit;
  end;

  { x R expr }
  if (CurTok.Kind = tkIdent) and (TokPos < TokCount) and LTokIs(TokPos, 'R') then
  begin
    name := CurTok.SVal;
    symIdx := FindSym(name);
    if symIdx < 0 then Error('LOLCODE: undefined variable ' + name);
    Next; Next;                 { x R }
    exprNode := LParseExpr;
    node := AllocNode(AN_ASSIGN);
    ASTLeft[node] := RMakeIdent(symIdx);
    ASTRight[node] := exprNode;
    ASTTk[node] := Ord(tyUnknown);
    Result := node;
    Exit;
  end;

  { <expr> , O RLY? YA RLY ... [NO WAI ...] OIC }
  condN := LParseExpr;
  LEatSep;
  if LPhraseIs('O', 'RLY') then
  begin
    Next; Next;
    LEatSep;
    LExpectWord('YA');
    LExpectWord('RLY');
    LEatSep;
    thenN := LParseBlockUntil('NO', 'WAI', 'OIC', '');
    elseN := -1;
    if LPhraseIs('NO', 'WAI') then
    begin
      Next; Next;
      LEatSep;
      elseN := LParseBlockUntil('OIC', '', '', '');
    end;
    LExpectWord('OIC');
    node := AllocNode(AN_IF);
    ASTLeft[node] := condN;
    exprNode := AllocNode(AN_PAIR);
    ASTLeft[exprNode] := thenN;
    ASTRight[exprNode] := elseN;
    ASTRight[node] := exprNode;
    ASTTk[node] := Ord(tyUnknown);
    Result := node;
    Exit;
  end;
  { a bare expression statement with no O RLY? has no effect — LOLCODE's IT
    is out of the probe's scope; reject loudly instead of silently dropping }
  Error('LOLCODE: expression statement without O RLY? (the IT variable is not in the skeleton)');
end;

{ parse statements until phrase (t1a t1b) or (t2a t2b) — one-word
  terminators pass '' as their second word. Does NOT consume the terminator. }
function LParseBlockUntil(const t1a, t1b, t2a, t2b: AnsiString): Integer;
var stmt: Integer;

  function AtTerm(const a, b: AnsiString): Boolean;
  begin
    if a = '' then begin Result := False; Exit; end;
    if b = '' then Result := LCurIs(a)
    else Result := LPhraseIs(a, b);
  end;

begin
  Result := -1;
  LEatSep;
  while not (AtTerm(t1a, t1b) or AtTerm(t2a, t2b)) do
  begin
    if CurTok.Kind = tkEOF then Error('LOLCODE: unterminated block');
    stmt := LParseStatement;
    Result := RSeqAppend(Result, stmt);
    LEatSep;
  end;
end;

procedure ParseLProgram;
var stmtList, stmt: Integer;
begin
  if TargetArch <> TARGET_X86_64 then
    Error('LOLCODE frontend: only the x86-64 target is supported by the skeleton (feature-esoteric-lolcode)');

  BSS_INITIAL_RSP := BSSSize; Inc(BSSSize, 8);
  EmitB($48); EmitB($89); EmitB($24); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);

  LEatSep;
  LExpectWord('HAI');
  { optional version tail (e.g. 1.2 — lexes as loose tokens); skip to
    the end of the HAI line }
  while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;

  stmtList := -1;
  LEatSep;
  while not LCurIs('KTHXBYE') do
  begin
    if CurTok.Kind = tkEOF then Error('LOLCODE: missing KTHXBYE');
    stmt := LParseStatement;
    stmtList := RSeqAppend(stmtList, stmt);
    LEatSep;
  end;

  CurASTNode := AllocNode(AN_BLOCK);
  ASTLeft[CurASTNode] := stmtList;
  ASTTk[CurASTNode] := Ord(tyUnknown);

  CompileAST(CurASTNode);
  EmitExit(0);
end;
