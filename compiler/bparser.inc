{ SPDX-License-Identifier: MPL-2.0 }
{ ===== BASIC Parser ===== }

function ParseBStatement: Integer; forward;
function ParseBBlock(endKind1, endKind2: TTokenKind): Integer; forward;

{ ---- GOTO / GOSUB / RETURN (bug-basic-goto-gosub-halts-program) ----
  Line-number jumps ride the shared AN_LABEL/AN_GOTO + GotoLabel* machinery
  the C frontend already uses: a prescan over the main-program tokens finds
  every `GOTO n` / `GOSUB n`, registers a label name "L<n>" per distinct
  target line (and "G<k>" per gosub site for its return point), and
  ParseBBlock emits an AN_LABEL when it meets a line number that is a
  registered target (other line numbers are skipped as before).

  GOSUB/RETURN return addresses use a shift-register stack in one Int64
  (__gosub_ret): each of the (max 63) gosub SITES has a 6-bit id k; GOSUB
  pushes `ret := ret*64 + k`, jumps, and places return label G<k> after
  itself; RETURN pops `id := ret mod 64; ret := ret div 64` and dispatches
  over an if/else chain to the matching G<k>. Depth limit 10 (10*6 = 60
  bits), guarded at runtime: overflow or RETURN-without-GOSUB prints a
  message and halts 1 — never silently wrong, per the ticket's whole point. }

const
  MAX_BASIC_GOSUB_SITES  = 63;    { 6-bit ids in the Int64 shift-register }
  MAX_BASIC_LINE_TARGETS = 512;
  { push guard: one more 6-bit push overflows past this (2^57) }
  BASIC_GOSUB_DEPTH_CAP  = 144115188075855872;

var
  BLineTargetCount: Integer;
  BLineTargetLine : array[0..MAX_BASIC_LINE_TARGETS-1] of Int64;
  BLineTargetNOff : array[0..MAX_BASIC_LINE_TARGETS-1] of Integer;
  BLineTargetNLen : array[0..MAX_BASIC_LINE_TARGETS-1] of Integer;
  BLineTargetPlaced: array[0..MAX_BASIC_LINE_TARGETS-1] of Boolean;
  BGosubSiteCount: Integer;   { ids assigned in token order by the prescan }
  BGosubRetNOff  : array[1..MAX_BASIC_GOSUB_SITES] of Integer;  { "G<k>" }
  BGosubRetNLen  : array[1..MAX_BASIC_GOSUB_SITES] of Integer;
  BGosubParseIdx : Integer;   { id of the LAST gosub met during the parse }
  BGosubRetSym   : Integer;   { __gosub_ret symbol }
  BGosubIdSym    : Integer;   { __gosub_id pop scratch symbol }

function BIntToStr(n: Int64): AnsiString;
var rev, res: AnsiString; i: Integer;
begin
  rev := '';
  if n = 0 then AppendChar(rev, '0')
  else
    while n > 0 do
    begin
      AppendChar(rev, Chr(Ord('0') + (n mod 10)));
      n := n div 10;
    end;
  res := '';
  for i := Length(rev) downto 1 do AppendChar(res, rev[i]);
  Result := res;
end;

{ case-insensitive text check of an arbitrary token (BASIC is case-blind) }
function BTokTextIs(i: Integer; const kw: AnsiString): Boolean;
var s, lower: AnsiString; j: Integer;
begin
  Result := False;
  if Tokens[i].Kind <> tkIdent then Exit;
  s := GetTokenStr(i);
  if Length(s) <> Length(kw) then Exit;
  SetLength(lower, Length(s));
  for j := 1 to Length(s) do
  begin
    if s[j] in ['A'..'Z'] then lower[j] := Chr(Ord(s[j]) + 32)
    else lower[j] := s[j];
  end;
  Result := lower = kw;
end;

function BCurIs(const kw: AnsiString): Boolean;
begin
  Result := (CurTok.Kind = tkIdent) and BTokTextIs(TokPos - 1, kw);
end;

{ store a synthetic name / message into TokChars, return its offset }
function BStoreChars(const s: AnsiString): Integer;
var i: Integer;
begin
  Result := TokCharLen;
  for i := 1 to Length(s) do
  begin
    if TokCharLen >= STRING_CAP then Error('BASIC: token char buffer overflow');
    TokChars[TokCharLen] := s[i];
    Inc(TokCharLen);
  end;
end;

procedure BAddGotoLabel(off, len: Integer);
begin
  if GotoLabelCount >= MAX_GOTO_LABELS then Error('BASIC: too many labels');
  GotoLabelNOff[GotoLabelCount] := off;
  GotoLabelNLen[GotoLabelCount] := len;
  GotoLabelCodePos[GotoLabelCount] := -1;
  GotoLabelIRId[GotoLabelCount] := -1;
  Inc(GotoLabelCount);
end;

function BFindLineTarget(line: Int64): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to BLineTargetCount - 1 do
    if BLineTargetLine[i] = line then begin Result := i; Exit; end;
end;

procedure BScanJumpTargets;
var i: Integer; nm: AnsiString; isGosub: Boolean;
begin
  BLineTargetCount := 0; BGosubSiteCount := 0; BGosubParseIdx := 0;
  i := 0;
  while i + 1 < MainProgramTokCount do
  begin
    isGosub := BTokTextIs(i, 'gosub');
    if (isGosub or BTokTextIs(i, 'goto')) and (Tokens[i + 1].Kind = tkInteger) then
    begin
      if BFindLineTarget(Tokens[i + 1].IVal) < 0 then
      begin
        if BLineTargetCount >= MAX_BASIC_LINE_TARGETS then
          Error('BASIC: too many distinct GOTO/GOSUB target lines');
        nm := 'L' + BIntToStr(Tokens[i + 1].IVal);
        BLineTargetLine[BLineTargetCount] := Tokens[i + 1].IVal;
        BLineTargetNOff[BLineTargetCount] := BStoreChars(nm);
        BLineTargetNLen[BLineTargetCount] := Length(nm);
        BLineTargetPlaced[BLineTargetCount] := False;
        BAddGotoLabel(BLineTargetNOff[BLineTargetCount], BLineTargetNLen[BLineTargetCount]);
        Inc(BLineTargetCount);
      end;
      if isGosub then
      begin
        if BGosubSiteCount >= MAX_BASIC_GOSUB_SITES then
          Error('BASIC: more than 63 GOSUB statements (shift-register return-stack limit)');
        Inc(BGosubSiteCount);
        nm := 'G' + BIntToStr(BGosubSiteCount);
        BGosubRetNOff[BGosubSiteCount] := BStoreChars(nm);
        BGosubRetNLen[BGosubSiteCount] := Length(nm);
        BAddGotoLabel(BGosubRetNOff[BGosubSiteCount], BGosubRetNLen[BGosubSiteCount]);
      end;
      Inc(i, 2);
    end
    else
      Inc(i);
  end;
end;

{ small node builders, local names to avoid cross-frontend coupling }
function BMkInt(v: Int64): Integer;
begin
  Result := AllocNode(AN_INT_LIT);
  ASTIVal[Result] := v;
  ASTTk[Result] := Ord(tyInt64);
end;

function BMkIdentN(symIdx: Integer): Integer;
begin
  Result := AllocNode(AN_IDENT);
  ASTIVal[Result] := symIdx;
  ASTTk[Result] := Ord(Syms[symIdx].TypeKind);
end;

function BMkAssign(l, r: Integer): Integer;
begin
  Result := AllocNode(AN_ASSIGN);
  ASTLeft[Result] := l;
  ASTRight[Result] := r;
  ASTTk[Result] := Ord(tyUnknown);
end;

function BMkBin(op: TTokenKind; l, r: Integer; tk: TTypeKind): Integer;
begin
  Result := AllocNode(AN_BINOP);
  ASTIVal[Result] := Ord(op);
  ASTLeft[Result] := l;
  ASTRight[Result] := r;
  ASTTk[Result] := Ord(tk);
end;

function BMkGoto(nOff, nLen: Integer): Integer;
begin
  Result := AllocNode(AN_GOTO);
  ASTSOffset[Result] := nOff;
  ASTSLen[Result] := nLen;
  ASTTk[Result] := Ord(tyUnknown);
end;

{ append stmt to an AN_SEQ chain (head = -1 starts one); returns the head }
function BSeqAppend(head, stmt: Integer): Integer;
var curr: Integer;
begin
  if stmt = -1 then begin Result := head; Exit; end;
  if head = -1 then
  begin
    Result := AllocNode(AN_SEQ);
    ASTLeft[Result] := stmt;
    ASTRight[Result] := -1;
    Exit;
  end;
  curr := head;
  while ASTRight[curr] <> -1 do curr := ASTRight[curr];
  ASTRight[curr] := AllocNode(AN_SEQ);
  curr := ASTRight[curr];
  ASTLeft[curr] := stmt;
  ASTRight[curr] := -1;
  Result := head;
end;

{ PRINT "<msg>"; HALT 1 — the runtime-error tail for the gosub guards }
function BMkRuntimeError(const msg: AnsiString): Integer;
var wr, arg, lit, halt: Integer; off: Integer;
begin
  off := BStoreChars(msg);
  lit := AllocNode(AN_STR_LIT);
  ASTSOffset[lit] := off;
  ASTSLen[lit] := Length(msg);
  ASTTk[lit] := Ord(tyString);
  arg := AllocNode(AN_ARG);
  ASTLeft[arg] := lit;
  ASTRight[arg] := -1;
  wr := AllocNode(AN_WRITE);
  ASTKind[wr] := AN_WRITELN;
  ASTLeft[wr] := arg;
  halt := AllocNode(AN_HALT);
  ASTLeft[halt] := BMkInt(1);
  ASTTk[halt] := Ord(tyUnknown);
  Result := BSeqAppend(BSeqAppend(-1, wr), halt);
end;

function BMkIf(cond, thenN, elseN: Integer): Integer;
var pairNode: Integer;
begin
  Result := AllocNode(AN_IF);
  ASTLeft[Result] := cond;
  pairNode := AllocNode(AN_PAIR);
  ASTLeft[pairNode] := thenN;
  ASTRight[pairNode] := elseN;
  ASTRight[Result] := pairNode;
  ASTTk[Result] := Ord(tyUnknown);
end;

function ParseBPrint: Integer;
var
  node, argNode, lastArg, exprNode: Integer;
begin
  node := AllocNode(AN_WRITE);
  ASTKind[node] := AN_WRITELN;
  
  lastArg := -1;
  repeat
    ParseExpr;
    exprNode := CurASTNode;
    argNode := AllocNode(AN_ARG);
    ASTLeft[argNode] := exprNode;
    ASTRight[argNode] := -1;
    
    if lastArg = -1 then
      ASTLeft[node] := argNode
    else
      ASTRight[lastArg] := argNode;
    lastArg := argNode;
  until not Eat(tkComma);
  
  Result := node;
end;

function ParseBStatement: Integer;
var
  stmtNode: Integer;
  vname: AnsiString;
  symIdx: Integer;
  lhsNode, rhsNode: Integer;
  vtype: TTypeKind;
  condNode, thenNode, elseNode, pairNode: Integer;
  bodyNode, whileNode: Integer;
  initNode, limitNode: Integer;
  stepVal: Int64;
  bodySeq: Integer;
  lhsValNode, lhsIncNode, stepConstNode, lhsValIncNode, addNode, incAssignNode, initAssignNode, curr: Integer;
  procIdx: Integer;
  tgtIdx, gk, lblNode, dispNode: Integer;
begin
  stmtNode := -1;

  if CurTok.Kind = tkUses then
  begin
    Next;
    if CurTok.Kind <> tkIdent then Error('BASIC uses: expected unit name');
    vname := CurTok.SVal;
    Next;
    ParseUsesUnit(vname);
  end
  else if CurTok.Kind = tkVar then
  begin
    Next;
    if CurTok.Kind <> tkIdent then Error('Expected identifier');
    vname := CurTok.SVal;
    Next;
    if CurTok.Kind <> tkEq then Error('Expected =');
    Next;
    ParseExpr;
    rhsNode := CurASTNode;
    
    symIdx := FindSym(vname);
    if symIdx < 0 then
    begin
      vtype := tyInteger;
      if ASTTk[rhsNode] = Ord(tyString) then
        vtype := tyString;
      symIdx := AllocVar(vname, vtype);
    end;
    
    lhsNode := AllocNode(AN_IDENT);
    ASTIVal[lhsNode] := symIdx;
    ASTTk[lhsNode] := Ord(Syms[symIdx].TypeKind);

    stmtNode := AllocNode(AN_ASSIGN);
    ASTLeft[stmtNode] := lhsNode;
    ASTRight[stmtNode] := rhsNode;
    ASTTk[stmtNode] := Ord(tyUnknown);
  end
  else if CurTok.Kind = tkwriteln then
  begin
    Next;
    stmtNode := ParseBPrint;
  end
  else if CurTok.Kind = tkIf then
  begin
    Next;
    ParseExpr;
    condNode := CurASTNode;
    Expect(tkThen, 'THEN');
    
    if CurTok.Kind = tkSemicolon then
    begin
      Next;
      thenNode := ParseBBlock(tkElse, tkEnd);
      elseNode := -1;
      if CurTok.Kind = tkElse then
      begin
        Next;
        if CurTok.Kind = tkSemicolon then Next;
        elseNode := ParseBBlock(tkEnd, tkEOF);
      end;
      Expect(tkEnd, 'END');
      Expect(tkIf, 'IF');
    end
    else
    begin
      thenNode := ParseBStatement();
      elseNode := -1;
      if Eat(tkElse) then
        elseNode := ParseBStatement();
    end;
      
    stmtNode := AllocNode(AN_IF);
    ASTLeft[stmtNode] := condNode;
    pairNode := AllocNode(AN_PAIR);
    ASTLeft[pairNode] := thenNode;
    ASTRight[pairNode] := elseNode;
    ASTRight[stmtNode] := pairNode;
    ASTTk[stmtNode] := Ord(tyUnknown);
  end
  else if CurTok.Kind = tkWhile then
  begin
    Next;
    ParseExpr;
    condNode := CurASTNode;
    bodyNode := ParseBBlock(tkEnd, tkEOF);
    Expect(tkEnd, 'WEND');
    
    stmtNode := AllocNode(AN_WHILE);
    ASTLeft[stmtNode] := condNode;
    ASTRight[stmtNode] := bodyNode;
    ASTTk[stmtNode] := Ord(tyUnknown);
  end
  else if CurTok.Kind = tkFor then
  begin
    Next;
    if CurTok.Kind <> tkIdent then Error('Expected identifier after FOR');
    vname := CurTok.SVal;
    Next;
    
    symIdx := FindSym(vname);
    if symIdx < 0 then
      symIdx := AllocVar(vname, tyInteger);
      
    Expect(tkEq, '=');
    ParseExpr;
    initNode := CurASTNode;
    
    Expect(tkTo, 'TO');
    ParseExpr;
    limitNode := CurASTNode;
    
    stepVal := 1;
    if Eat(tkTo) then
    begin
      if CurTok.Kind <> tkInteger then Error('Expected step integer');
      stepVal := CurTok.IVal;
      Next;
    end;
    
    bodySeq := ParseBBlock(tkEnd, tkEOF);
    Expect(tkEnd, 'NEXT');
    if CurTok.Kind = tkIdent then Next;
    
    lhsNode := AllocNode(AN_IDENT);
    ASTIVal[lhsNode] := symIdx;
    ASTTk[lhsNode] := Ord(Syms[symIdx].TypeKind);
    
    initAssignNode := AllocNode(AN_ASSIGN);
    ASTLeft[initAssignNode] := lhsNode;
    ASTRight[initAssignNode] := initNode;
    ASTTk[initAssignNode] := Ord(tyUnknown);
    
    lhsValNode := AllocNode(AN_IDENT);
    ASTIVal[lhsValNode] := symIdx;
    ASTTk[lhsValNode] := Ord(Syms[symIdx].TypeKind);
    
    condNode := AllocNode(AN_BINOP);
    ASTIVal[condNode] := Ord(tkLe);
    ASTLeft[condNode] := lhsValNode;
    ASTRight[condNode] := limitNode;
    ASTTk[condNode] := Ord(tyBoolean);
    
    lhsIncNode := AllocNode(AN_IDENT);
    ASTIVal[lhsIncNode] := symIdx;
    ASTTk[lhsIncNode] := Ord(Syms[symIdx].TypeKind);
    
    stepConstNode := AllocNode(AN_INT_LIT);
    ASTIVal[stepConstNode] := stepVal;
    ASTTk[stepConstNode] := Ord(tyInteger);
    
    lhsValIncNode := AllocNode(AN_IDENT);
    ASTIVal[lhsValIncNode] := symIdx;
    ASTTk[lhsValIncNode] := Ord(Syms[symIdx].TypeKind);
    
    addNode := AllocNode(AN_BINOP);
    ASTIVal[addNode] := Ord(tkPlus);
    ASTLeft[addNode] := lhsValIncNode;
    ASTRight[addNode] := stepConstNode;
    ASTTk[addNode] := Ord(tyInteger);
    
    incAssignNode := AllocNode(AN_ASSIGN);
    ASTLeft[incAssignNode] := lhsIncNode;
    ASTRight[incAssignNode] := addNode;
    ASTTk[incAssignNode] := Ord(tyUnknown);
    
    if bodySeq = -1 then
      bodySeq := incAssignNode
    else
    begin
      curr := bodySeq;
      while ASTRight[curr] <> -1 do
        curr := ASTRight[curr];
      ASTRight[curr] := AllocNode(AN_SEQ);
      curr := ASTRight[curr];
      ASTLeft[curr] := incAssignNode;
      ASTRight[curr] := -1;
    end;
    
    whileNode := AllocNode(AN_WHILE);
    ASTLeft[whileNode] := condNode;
    ASTRight[whileNode] := bodySeq;
    ASTTk[whileNode] := Ord(tyUnknown);
    
    stmtNode := AllocNode(AN_SEQ);
    ASTLeft[stmtNode] := initAssignNode;
    ASTRight[stmtNode] := AllocNode(AN_SEQ);
    ASTLeft[ASTRight[stmtNode]] := whileNode;
    ASTRight[ASTRight[stmtNode]] := -1;
  end
  else if CurTok.Kind = tkEnd then
  begin
    Next;
    stmtNode := AllocNode(AN_HALT);
    ASTTk[stmtNode] := Ord(tyUnknown);
  end
  else if BCurIs('goto') then
  begin
    Next;
    if CurTok.Kind <> tkInteger then Error('BASIC: expected line number after GOTO');
    tgtIdx := BFindLineTarget(CurTok.IVal);
    if tgtIdx < 0 then Error('BASIC: internal error — GOTO target missed by prescan');
    Next;
    stmtNode := BMkGoto(BLineTargetNOff[tgtIdx], BLineTargetNLen[tgtIdx]);
  end
  else if BCurIs('gosub') then
  begin
    Next;
    if CurTok.Kind <> tkInteger then Error('BASIC: expected line number after GOSUB');
    tgtIdx := BFindLineTarget(CurTok.IVal);
    if tgtIdx < 0 then Error('BASIC: internal error — GOSUB target missed by prescan');
    Next;
    { site id in token order — the prescan assigned them the same way }
    Inc(BGosubParseIdx);
    gk := BGosubParseIdx;
    if gk > BGosubSiteCount then Error('BASIC: internal error — GOSUB site count mismatch');
    { 1) depth guard  2) push id  3) jump  4) return label G<k> }
    stmtNode := BSeqAppend(-1,
      BMkIf(BMkBin(tkGe, BMkIdentN(BGosubRetSym), BMkInt(BASIC_GOSUB_DEPTH_CAP), tyBoolean),
            BMkRuntimeError('RUNTIME ERROR: GOSUB nesting deeper than 10'), -1));
    stmtNode := BSeqAppend(stmtNode,
      BMkAssign(BMkIdentN(BGosubRetSym),
                BMkBin(tkPlus,
                       BMkBin(tkStar, BMkIdentN(BGosubRetSym), BMkInt(64), tyInt64),
                       BMkInt(gk), tyInt64)));
    stmtNode := BSeqAppend(stmtNode, BMkGoto(BLineTargetNOff[tgtIdx], BLineTargetNLen[tgtIdx]));
    lblNode := AllocNode(AN_LABEL);
    ASTSOffset[lblNode] := BGosubRetNOff[gk];
    ASTSLen[lblNode] := BGosubRetNLen[gk];
    ASTTk[lblNode] := Ord(tyUnknown);
    stmtNode := BSeqAppend(stmtNode, lblNode);
  end
  else if CurTok.Kind = tkExit then
  begin
    Next;
    if CurProc >= 0 then
    begin
      { RETURN inside a proc = plain function return }
      stmtNode := AllocNode(AN_EXIT);
      ASTTk[stmtNode] := Ord(tyUnknown);
    end
    else
    begin
      { main-line RETURN = gosub return: pop the shift-register, dispatch
        to the matching G<k>; id 0 = stack empty = RETURN without GOSUB. }
      dispNode := BMkRuntimeError('RUNTIME ERROR: RETURN without GOSUB');
      for gk := BGosubSiteCount downto 1 do
        dispNode := BMkIf(BMkBin(tkEq, BMkIdentN(BGosubIdSym), BMkInt(gk), tyBoolean),
                          BMkGoto(BGosubRetNOff[gk], BGosubRetNLen[gk]),
                          dispNode);
      stmtNode := BSeqAppend(-1,
        BMkAssign(BMkIdentN(BGosubIdSym),
                  BMkBin(tkMod, BMkIdentN(BGosubRetSym), BMkInt(64), tyInt64)));
      stmtNode := BSeqAppend(stmtNode,
        BMkAssign(BMkIdentN(BGosubRetSym),
                  BMkBin(tkDiv, BMkIdentN(BGosubRetSym), BMkInt(64), tyInt64)));
      stmtNode := BSeqAppend(stmtNode, dispNode);
    end;
  end;
  
  if stmtNode = -1 then
  begin
    if CurTok.Kind = tkIdent then
    begin
      vname := CurTok.SVal;
      symIdx := FindSym(vname);
      if symIdx < 0 then
      begin
        procIdx := FindProc(vname);
        if procIdx >= 0 then
        begin
          ParseExpr;
          stmtNode := CurASTNode;
        end
        else
        begin
          { CurTok is Tokens[TokPos-1], so the token AFTER the identifier is
            Tokens[TokPos] — the old TokPos+1 check looked one too far and
            made every LET-less first assignment (`I = 0`) an "Undefined
            variable" error (pre-existing off-by-one, verified against the
            pinned stable binary while fixing the GOTO ticket). }
          if (TokPos < TokCount) and (Tokens[TokPos].Kind = tkEq) then
          begin
            Next;
            Next;
            ParseExpr;
            rhsNode := CurASTNode;
            vtype := tyInteger;
            if ASTTk[rhsNode] = Ord(tyString) then
              vtype := tyString;
            symIdx := AllocVar(vname, vtype);
            
            lhsNode := AllocNode(AN_IDENT);
            ASTIVal[lhsNode] := symIdx;
            ASTTk[lhsNode] := Ord(Syms[symIdx].TypeKind);

            stmtNode := AllocNode(AN_ASSIGN);
            ASTLeft[stmtNode] := lhsNode;
            ASTRight[stmtNode] := rhsNode;
            ASTTk[stmtNode] := Ord(tyUnknown);
          end
          else
            Error('Undefined variable or procedure: ' + vname);
        end;
      end
      else
      begin
        Next;
        if CurTok.Kind <> tkEq then Error('Expected =');
        Next;
        ParseExpr;
        rhsNode := CurASTNode;

        lhsNode := AllocNode(AN_IDENT);
        ASTIVal[lhsNode] := symIdx;
        ASTTk[lhsNode] := Ord(Syms[symIdx].TypeKind);

        stmtNode := AllocNode(AN_ASSIGN);
        ASTLeft[stmtNode] := lhsNode;
        ASTRight[stmtNode] := rhsNode;
        ASTTk[stmtNode] := Ord(tyUnknown);
      end;
    end;
  end;
  
  Result := stmtNode;
end;

function ParseBBlock(endKind1, endKind2: TTokenKind): Integer;
var
  stmtList, lastStmt, stmtNode, lblNode: Integer;
begin
  stmtList := -1;
  lastStmt := -1;
  while (CurTok.Kind <> tkEOF) and (TokPos - 1 < MainProgramTokCount) and (CurTok.Kind <> endKind1) and (CurTok.Kind <> endKind2) do
  begin
    if CurTok.Kind = tkSemicolon then
    begin
      Next;
    end
    else if CurTok.Kind = tkInteger then
    begin
      { a line number: emit an AN_LABEL if some GOTO/GOSUB targets it,
        otherwise skip it as before }
      stmtNode := BFindLineTarget(CurTok.IVal);
      if stmtNode >= 0 then
      begin
        if BLineTargetPlaced[stmtNode] then
          Error('BASIC: duplicate line number ' + BIntToStr(CurTok.IVal) + ' (GOTO/GOSUB target)');
        BLineTargetPlaced[stmtNode] := True;
        lblNode := AllocNode(AN_LABEL);
        ASTSOffset[lblNode] := BLineTargetNOff[stmtNode];
        ASTSLen[lblNode] := BLineTargetNLen[stmtNode];
        ASTTk[lblNode] := Ord(tyUnknown);
        if stmtList = -1 then
        begin
          stmtList := AllocNode(AN_SEQ);
          ASTLeft[stmtList] := lblNode;
          ASTRight[stmtList] := -1;
          lastStmt := stmtList;
        end
        else
        begin
          ASTRight[lastStmt] := AllocNode(AN_SEQ);
          lastStmt := ASTRight[lastStmt];
          ASTLeft[lastStmt] := lblNode;
          ASTRight[lastStmt] := -1;
        end;
      end;
      Next;
    end
    else
    begin
      stmtNode := ParseBStatement;
      if stmtNode <> -1 then
      begin
        if stmtList = -1 then
        begin
          stmtList := AllocNode(AN_SEQ);
          ASTLeft[stmtList] := stmtNode;
          ASTRight[stmtList] := -1;
          lastStmt := stmtList;
        end
        else
        begin
          ASTRight[lastStmt] := AllocNode(AN_SEQ);
          lastStmt := ASTRight[lastStmt];
          ASTLeft[lastStmt] := stmtNode;
          ASTRight[lastStmt] := -1;
        end;
      end;
    end;
  end;
  Result := stmtList;
end;

procedure ParseBProgram;
var
  stmtList: Integer;
  jmpPatch, i: Integer;
begin
  BSS_INITIAL_RSP := BSSSize; Inc(BSSSize, 8);

  EmitB($48); EmitB($89); EmitB($24); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
  EmitB($E9); jmpPatch := CodeLen; EmitI32(0);

  { GOTO/GOSUB: reset the shared label table (C resets it per function; the
    BASIC main program is one scope), prescan for jump targets, and allocate
    the gosub shift-register stack (globals — BSS-zeroed, so the empty-stack
    state 0 needs no explicit init). }
  GotoLabelCount := 0;
  BScanJumpTargets;
  BGosubRetSym := AllocVar('__gosub_ret', tyInt64);
  BGosubIdSym := AllocVar('__gosub_id', tyInt64);

  stmtList := ParseBBlock(tkEOF, tkEOF);

  Patch32(jmpPatch, CodeLen - (jmpPatch + 4));

  { A `USES unit` met during the parse compiles that unit through the Pascal
    parser, which resets GotoLabelCount per scope — wiping the L*/G* labels
    the prescan registered. The AST references labels by NAME (TokChars
    slices), so re-registering them here, right before lowering, restores
    resolution. }
  GotoLabelCount := 0;
  for i := 0 to BLineTargetCount - 1 do
    BAddGotoLabel(BLineTargetNOff[i], BLineTargetNLen[i]);
  for i := 1 to BGosubSiteCount do
    BAddGotoLabel(BGosubRetNOff[i], BGosubRetNLen[i]);

  CurASTNode := AllocNode(AN_BLOCK);
  ASTLeft[CurASTNode] := stmtList;
  ASTTk[CurASTNode] := Ord(tyUnknown);

  CompileAST(CurASTNode);
  EmitExit(0);
end;
