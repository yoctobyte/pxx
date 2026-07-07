{ SPDX-License-Identifier: MPL-2.0 }
{ ===== Erlang Parser (skeleton) =====
  Esoteric-frontend-probe pass on [[feature-erlang-frontend-scoping]] —
  NOT the full-language effort (no processes, no scheduler, no message
  passing, no atoms/tuples/lists as runtime values, no GC).

  The probe-interesting shape: MULTI-CLAUSE FUNCTIONS WITH PATTERN
  DISPATCH. `fact(0) -> 1; fact(N) -> N * fact(N - 1).` compiles to one
  proc whose body is a chain of per-clause guards: literal patterns
  become equality tests on the incoming parameter, variable patterns
  bind clause-local names to it, `when` guards AND onto the condition,
  and a fall-off-the-end (no clause matched) is a LOUD runtime
  function_clause error + halt 1, like the real thing. No other
  frontend generates dispatch-on-argument-value shapes, which is the
  point of running it through the shared AST/IR.

  Subset: `-module(...)./-export([...]).` attributes (swallowed),
  integer arithmetic (+ - * div rem), comparisons (== /= < =< > >=),
  single-assignment `Var = expr` bindings (re-binding is a compile
  error, honouring immutability), calls incl. recursion (max 4 params),
  `io:format("fmt~n", [Args])` with ~p/~w/~B placeholders (~n only at
  the end of the format, per the same cut zparser documents).
  Everything is an integer (tyInt64); function return value = value of
  the clause's last expression. }

function EParseExpr: Integer; forward;

function ECurIs(const kw: AnsiString): Boolean;
begin
  Result := (CurTok.Kind = tkIdent) and (CurTok.SVal = kw);
end;

function EIsVarName(const s: AnsiString): Boolean;
begin
  Result := (Length(s) > 0) and ((s[1] in ['A'..'Z']) or (s[1] = '_'));
end;

{ ---- io:format ---- }
function EParseIoFormat: Integer;
var fmtOff, fmtLen, i, segStart: Integer;
    node, lastArg, argNode, litNode: Integer;
    argExprs: array[0..7] of Integer;
    argCount, argUsed: Integer;
    isLn: Boolean;

  procedure AddArg(exprNode: Integer);
  begin
    argNode := AllocNode(AN_ARG);
    ASTLeft[argNode] := exprNode;
    ASTRight[argNode] := -1;
    ASTSOffset[argNode] := -1;   { decimals sentinel (see fparser) }
    if lastArg < 0 then ASTLeft[node] := argNode else ASTRight[lastArg] := argNode;
    lastArg := argNode;
  end;

  procedure AddSegment(off, len: Integer);
  begin
    if len <= 0 then Exit;
    litNode := AllocNode(AN_STR_LIT);
    ASTSOffset[litNode] := off;
    ASTSLen[litNode] := len;
    ASTTk[litNode] := Ord(tyString);
    AddArg(litNode);
  end;

begin
  Next; { io }
  Expect(tkColon, ':');
  if not ECurIs('format') then Error('Erlang: only io:format is supported by the skeleton');
  Next;
  Expect(tkLParen, '(');
  if CurTok.Kind <> tkString then Error('Erlang: io:format needs a literal format string');
  fmtOff := Tokens[TokPos - 1].SOffset;
  fmtLen := Tokens[TokPos - 1].SLen;
  Next;

  argCount := 0;
  if Eat(tkComma) then
  begin
    Expect(tkLBrack, '[');
    if CurTok.Kind <> tkRBrack then
      repeat
        if argCount > 7 then Error('Erlang: io:format supports at most 8 arguments (skeleton)');
        argExprs[argCount] := EParseExpr;
        Inc(argCount);
      until not Eat(tkComma);
    Expect(tkRBrack, ']');
  end;
  Expect(tkRParen, ')');

  { trailing ~n -> WRITELN; ~n anywhere else is a loud skeleton cut }
  isLn := (fmtLen >= 2) and (TokChars[fmtOff + fmtLen - 2] = '~') and
          (TokChars[fmtOff + fmtLen - 1] = 'n');
  if isLn then Dec(fmtLen, 2);

  node := AllocNode(AN_WRITE);
  if isLn then ASTKind[node] := AN_WRITELN;
  ASTLeft[node] := -1;
  lastArg := -1;
  argUsed := 0;

  segStart := 0;
  i := 0;
  while i < fmtLen do
  begin
    if TokChars[fmtOff + i] = '~' then
    begin
      if i + 1 >= fmtLen then Error('Erlang: dangling ~ in format string');
      case TokChars[fmtOff + i + 1] of
        'p', 'w', 'B':
        begin
          AddSegment(fmtOff + segStart, i - segStart);
          if argUsed >= argCount then Error('Erlang: more ~ placeholders than arguments');
          AddArg(argExprs[argUsed]);
          Inc(argUsed);
        end;
        'n': Error('Erlang: ~n mid-format is not in the skeleton (only trailing ~n)');
        else Error('Erlang: unsupported format directive ~' + TokChars[fmtOff + i + 1]);
      end;
      Inc(i, 2);
      segStart := i;
    end
    else
      Inc(i);
  end;
  AddSegment(fmtOff + segStart, fmtLen - segStart);
  if argUsed < argCount then Error('Erlang: more arguments than ~ placeholders');

  Result := node;
end;

{ ---- expressions ---- }
function EParsePrimary: Integer;
var node, argNode, lastArg, procIdx: Integer; name: AnsiString; symIdx: Integer;
begin
  if CurTok.Kind = tkInteger then
  begin
    node := AllocNode(AN_INT_LIT);
    ASTIVal[node] := CurTok.IVal;
    ASTTk[node] := Ord(tyInt64);
    Next; Result := node; Exit;
  end;
  if CurTok.Kind = tkLParen then
  begin
    Next;
    node := EParseExpr;
    Expect(tkRParen, ')');
    Result := node; Exit;
  end;
  if CurTok.Kind = tkMinus then
  begin
    Next;
    node := AllocNode(AN_NEG);
    ASTLeft[node] := EParsePrimary();
    ASTTk[node] := ASTTk[ASTLeft[node]];
    Result := node; Exit;
  end;
  if CurTok.Kind = tkIdent then
  begin
    name := CurTok.SVal;
    if EIsVarName(name) then
    begin
      symIdx := FindSym(name);
      if symIdx < 0 then Error('Erlang: unbound variable ' + name);
      Next;
      Result := RMakeIdent(symIdx);
      Exit;
    end;
    { atom: a local call name (io:format handled at statement level) }
    Next;
    if CurTok.Kind <> tkLParen then
      Error('Erlang: atoms as values are not in the skeleton (' + name + ')');
    procIdx := FindProc(name);
    if procIdx < 0 then Error('Erlang: call to undefined function ' + name);
    Next;
    node := AllocNode(AN_CALL);
    ASTIVal[node] := procIdx;
    ASTTk[node] := Ord(Procs[procIdx].RetType);
    lastArg := -1;
    if CurTok.Kind <> tkRParen then
      repeat
        argNode := AllocNode(AN_ARG);
        ASTLeft[argNode] := EParseExpr;
        ASTRight[argNode] := -1;
        if lastArg < 0 then ASTLeft[node] := argNode else ASTRight[lastArg] := argNode;
        lastArg := argNode;
      until not Eat(tkComma);
    Expect(tkRParen, ')');
    Result := node;
    Exit;
  end;
  Error('Erlang: unexpected token in expression');
  Result := -1;
end;

function EParseMul: Integer;
var left, right: Integer; opTk: TTokenKind; isOp: Boolean;
begin
  left := EParsePrimary;
  isOp := True;
  while isOp do
  begin
    opTk := tkStar; isOp := False;
    if CurTok.Kind = tkStar then begin opTk := tkStar; isOp := True; end
    else if ECurIs('div') then begin opTk := tkDiv; isOp := True; end
    else if ECurIs('rem') then begin opTk := tkMod; isOp := True; end
    else if CurTok.Kind = tkSlash then
      Error('Erlang: / is float division; use div (skeleton is integer-only)');
    if isOp then
    begin
      Next;
      right := EParsePrimary;
      left := RBinOp(opTk, left, right, tyInt64);
    end;
  end;
  Result := left;
end;

function EParseAdd: Integer;
var left, right: Integer; opTk: TTokenKind;
begin
  left := EParseMul;
  while CurTok.Kind in [tkPlus, tkMinus] do
  begin
    opTk := CurTok.Kind; Next;
    right := EParseMul;
    left := RBinOp(opTk, left, right, tyInt64);
  end;
  Result := left;
end;

function EParseExpr: Integer;
var left, right: Integer; opTk: TTokenKind;
begin
  left := EParseAdd;
  if CurTok.Kind in [tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe] then
  begin
    opTk := CurTok.Kind; Next;
    right := EParseAdd;
    left := RBinOp(opTk, left, right, tyBoolean);
  end;
  Result := left;
end;

{ ---- top level ---- }

{ prescan: register every name/arity at a clause start (position 0, or
  right after a terminating '.'). One PXX proc per NAME — clauses of the
  same name/arity share it; a second arity for one name is an error. }
procedure ERegisterFnSignatures;
var i, j, depth, arity, procIdx, k: Integer;
    name: AnsiString;
    atStart: Boolean;
    pnames: array[0..3] of AnsiString; ptypes: array[0..3] of TTypeKind;
begin
  i := 0;
  atStart := True;
  while Tokens[i].Kind <> tkEOF do
  begin
    if atStart and (Tokens[i].Kind = tkIdent) and (i + 1 < TokCount) and
       (Tokens[i + 1].Kind = tkLParen) and not EIsVarName(GetTokenStr(i)) then
    begin
      name := GetTokenStr(i);
      { count arity: commas at depth 1 }
      j := i + 2; depth := 1; arity := 0;
      if Tokens[j].Kind <> tkRParen then arity := 1;
      while (depth > 0) and (Tokens[j].Kind <> tkEOF) do
      begin
        if Tokens[j].Kind = tkLParen then Inc(depth)
        else if Tokens[j].Kind = tkRParen then Dec(depth)
        else if (Tokens[j].Kind = tkComma) and (depth = 1) then Inc(arity);
        Inc(j);
      end;
      if arity > 4 then Error('Erlang: more than 4 parameters (skeleton limit): ' + name);
      procIdx := FindProc(name);
      if procIdx < 0 then
      begin
        for k := 0 to 3 do begin pnames[k] := ''; ptypes[k] := tyInt64; end;
        for k := 0 to arity - 1 do pnames[k] := 'p' + Chr(Ord('0') + k);
        procIdx := RegisterProc(name, True, tyInt64, arity, pnames, ptypes);
      end
      else if Procs[procIdx].ParamCount <> arity then
        Error('Erlang: ' + name + ' defined with two arities (skeleton allows one)');
    end;
    atStart := (Tokens[i].Kind = tkDot) or (Tokens[i].Kind = tkSemicolon);
    Inc(i);
  end;
end;

{ one clause body: comma-separated exprs / bindings; value of the LAST
  expression is assigned to Result, then AN_EXIT skips later clauses. }
function EParseClauseBody(retSym: Integer): Integer;
var stmts, node, exprNode: Integer;
    name: AnsiString;
    symIdx: Integer;
    more: Boolean;
begin
  stmts := -1;
  more := True;
  while more do
  begin
    { binding: Var = expr (single assignment — rebinding is an error) }
    if (CurTok.Kind = tkIdent) and EIsVarName(CurTok.SVal) and
       (TokPos < TokCount) and (Tokens[TokPos].Kind = tkAssign) then
    begin
      name := CurTok.SVal;
      if FindSym(name) >= 0 then
        Error('Erlang: variable ' + name + ' is already bound (single assignment)');
      Next; Next;
      exprNode := EParseExpr;
      symIdx := AllocVar(name, tyInt64);
      node := AllocNode(AN_ASSIGN);
      ASTLeft[node] := RMakeIdent(symIdx);
      ASTRight[node] := exprNode;
      ASTTk[node] := Ord(tyUnknown);
      exprNode := RMakeIdent(symIdx);   { the binding's value, if last }
    end
    else if ECurIs('io') then
    begin
      node := EParseIoFormat;
      exprNode := AllocNode(AN_INT_LIT);   { io:format's value = ok ~ 0 }
      ASTIVal[exprNode] := 0;
      ASTTk[exprNode] := Ord(tyInt64);
    end
    else
    begin
      node := -1;
      exprNode := EParseExpr;
    end;

    more := Eat(tkComma);
    if node <> -1 then
      stmts := RSeqAppend(stmts, node);
    if more then
    begin
      { non-last expression evaluated for effect only (calls) }
      if (node = -1) and (ASTKind[exprNode] = AN_CALL) then
        stmts := RSeqAppend(stmts, exprNode);
    end
    else
    begin
      { last expression: its value is the clause's return value }
      node := AllocNode(AN_ASSIGN);
      ASTLeft[node] := RMakeIdent(retSym);
      ASTRight[node] := exprNode;
      ASTTk[node] := Ord(tyUnknown);
      stmts := RSeqAppend(stmts, node);
      node := AllocNode(AN_EXIT);
      ASTTk[node] := Ord(tyUnknown);
      stmts := RSeqAppend(stmts, node);
    end;
  end;
  Result := stmts;
end;

{ all clauses of one function definition, ending at '.' }
procedure EParseFunction;
var name, errMsg: AnsiString;
    procIdx, nparams, i, idx, savedSC, savedFS, patchPos: Integer;
    bodySeq, clauseCond, clauseBody, clauseNode, pairNode, term: Integer;
    patKind: array[0..3] of Integer;      { 0 = literal, 1 = variable }
    patLit: array[0..3] of Int64;
    patVar: array[0..3] of AnsiString;
    done: Boolean;
begin
  if CurTok.Kind <> tkIdent then Error('Erlang: expected function name');
  name := CurTok.SVal;
  procIdx := FindProc(name);
  if procIdx < 0 then Error('Erlang: internal error — prescan missed ' + name);
  nparams := Procs[procIdx].ParamCount;

  savedSC := SymCount; savedFS := FrameSize;
  FrameSize := 0; CurProc := procIdx;
  Procs[procIdx].BodyAddr := CodeLen;
  Procs[procIdx].ScopeBase := SymCount;
  for i := 0 to nparams - 1 do
  begin
    idx := AllocParam('p' + Chr(Ord('0') + i), tyInt64, False, False);
    Procs[procIdx].Params[i].SymIdx := idx;
  end;
  idx := AllocVar('Result', tyInt64);
  Procs[procIdx].RetSymIdx := idx;

  patchPos := EmitProcPrologue;
  Procs[procIdx].FramePatch := patchPos;
  for i := 0 to nparams - 1 do
  begin
    idx := Procs[procIdx].Params[i].SymIdx;
    if ParamSize(idx) = 8 then EmitB($48);
    EmitB($89);
    case i of
      0: EmitB($BD);
      1: EmitB($B5);
      2: EmitB($95);
      3: EmitB($8D);
    end;
    EmitI32(Syms[idx].Offset);
  end;

  bodySeq := -1;
  done := False;
  while not done do
  begin
    { clause head: name(patterns) [when guard] -> }
    if not ECurIs(name) then Error('Erlang: expected another clause of ' + name);
    Next;
    Expect(tkLParen, '(');
    for i := 0 to nparams - 1 do
    begin
      if CurTok.Kind = tkInteger then
      begin
        patKind[i] := 0; patLit[i] := CurTok.IVal; Next;
      end
      else if (CurTok.Kind = tkIdent) and EIsVarName(CurTok.SVal) then
      begin
        patKind[i] := 1; patVar[i] := CurTok.SVal; Next;
      end
      else
        Error('Erlang: only integer-literal and variable patterns are in the skeleton');
      if i < nparams - 1 then Expect(tkComma, ',');
    end;
    Expect(tkRParen, ')');

    { variable patterns bind clause-local names to the parameter.
      NOTE: no per-clause SymRollbackTo — the whole function body is
      CompileAST'd once at the end, and IR lowering validates every
      symIdx against the live SymCount, so rolling back mid-parse makes
      store_sym reject the earlier clauses' bindings (found by testing:
      'invalid IR symbol reference in store_sym'). Same-named vars in
      later clauses simply shadow via FindSym-newest; everything is
      rolled back together at function end (savedSC). }
    clauseCond := -1;
    for i := 0 to nparams - 1 do
      if patKind[i] = 1 then
      begin
        if (Length(patVar[i]) > 0) and (patVar[i] <> '_') then
        begin
          idx := AllocVar(patVar[i], tyInt64);
          { N := p<i> at clause entry, folded into the clause body below }
          clauseNode := AllocNode(AN_ASSIGN);
          ASTLeft[clauseNode] := RMakeIdent(idx);
          ASTRight[clauseNode] := RMakeIdent(Procs[procIdx].Params[i].SymIdx);
          ASTTk[clauseNode] := Ord(tyUnknown);
          bodySeq := RSeqAppend(bodySeq, clauseNode);
          { NOTE: binding emitted unconditionally before the clause test —
            harmless (write of a param copy), keeps the desugar simple. }
        end;
      end
      else
      begin
        clauseNode := RBinOp(tkEq, RMakeIdent(Procs[procIdx].Params[i].SymIdx),
                             -1, tyBoolean);
        { literal: p<i> == lit }
        ASTRight[clauseNode] := AllocNode(AN_INT_LIT);
        ASTIVal[ASTRight[clauseNode]] := patLit[i];
        ASTTk[ASTRight[clauseNode]] := Ord(tyInt64);
        if clauseCond = -1 then clauseCond := clauseNode
        else clauseCond := RBinOp(tkAnd, clauseCond, clauseNode, tyBoolean);
      end;

    if ECurIs('when') then
    begin
      Next;
      clauseNode := EParseExpr;
      if clauseCond = -1 then clauseCond := clauseNode
      else clauseCond := RBinOp(tkAnd, clauseCond, clauseNode, tyBoolean);
    end;

    Expect(tkThen, '->');
    clauseBody := EParseClauseBody(Procs[procIdx].RetSymIdx);

    if clauseCond = -1 then
      bodySeq := RSeqAppend(bodySeq, clauseBody)   { unconditional clause }
    else
    begin
      clauseNode := AllocNode(AN_IF);
      ASTLeft[clauseNode] := clauseCond;
      pairNode := AllocNode(AN_PAIR);
      ASTLeft[pairNode] := clauseBody;
      ASTRight[pairNode] := -1;
      ASTRight[clauseNode] := pairNode;
      ASTTk[clauseNode] := Ord(tyUnknown);
      bodySeq := RSeqAppend(bodySeq, clauseNode);
    end;
    if CurTok.Kind = tkSemicolon then Next
    else
    begin
      Expect(tkDot, '.');
      done := True;
    end;
  end;

  { fell off every clause: function_clause, loudly (never silent) }
  errMsg := 'RUNTIME ERROR: no function clause matching ' + name;
  term := AllocNode(AN_WRITE);
  ASTKind[term] := AN_WRITELN;
  pairNode := AllocNode(AN_STR_LIT);
  ASTSOffset[pairNode] := RStoredName(errMsg);
  ASTSLen[pairNode] := Length(errMsg);
  ASTTk[pairNode] := Ord(tyString);
  clauseNode := AllocNode(AN_ARG);
  ASTLeft[clauseNode] := pairNode;
  ASTRight[clauseNode] := -1;
  ASTLeft[term] := clauseNode;
  bodySeq := RSeqAppend(bodySeq, term);
  term := AllocNode(AN_HALT);
  ASTLeft[term] := AllocNode(AN_INT_LIT);
  ASTIVal[ASTLeft[term]] := 1;
  ASTTk[ASTLeft[term]] := Ord(tyInteger);
  ASTTk[term] := Ord(tyUnknown);
  bodySeq := RSeqAppend(bodySeq, term);

  CompileAST(bodySeq);
  EmitProcEpilog(Procs[procIdx].RetSymIdx);
  PatchProcPrologue(patchPos, FrameSize);
  SymRollbackTo(savedSC);
  FrameSize := savedFS;
  CurProc := -1;
end;

procedure ParseEProgram;
var callPatch, mainIdx: Integer;
begin
  if TargetArch <> TARGET_X86_64 then
    Error('Erlang frontend: only the x86-64 target is supported by the skeleton (feature-erlang-frontend-scoping)');

  ERegisterFnSignatures;
  mainIdx := FindProc('main');
  if mainIdx < 0 then Error('Erlang: no main/0 found');
  if Procs[mainIdx].ParamCount <> 0 then Error('Erlang: main must have arity 0');

  BSS_INITIAL_RSP := BSSSize; Inc(BSSSize, 8);
  EmitB($48); EmitB($89); EmitB($24); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
  EmitB($E8); callPatch := CodeLen; EmitI32(0);   { call main }
  EmitB($31); EmitB($FF);            { xor edi, edi — exit 0 }
  EmitB($B8); EmitI32(231);          { mov eax, 231 (exit_group) }
  EmitB($0F); EmitB($05);            { syscall }

  while CurTok.Kind <> tkEOF do
  begin
    { -module(x). / -export([...]). and any other attribute: swallow to '.' }
    if CurTok.Kind = tkMinus then
    begin
      while (CurTok.Kind <> tkDot) and (CurTok.Kind <> tkEOF) do Next;
      Expect(tkDot, '.');
    end
    else if CurTok.Kind = tkIdent then
      EParseFunction
    else
      Error('Erlang: expected a function definition or attribute at top level');
  end;

  ApplyCallFixups;
  Patch32(callPatch, Procs[mainIdx].BodyAddr - (callPatch + 4));
end;
