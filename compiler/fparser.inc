{ SPDX-License-Identifier: MPL-2.0 }
{ ===== Fortran Parser (skeleton) =====
  Esoteric-frontend-probe (feature-esoteric-fortran). Free-form F90-style
  subset, hand-built AST over existing AN_* nodes, reusing rparser.inc's
  node helpers. The probe-interesting part is Fortran's IMPLICIT TYPING:
  a variable springs into existence at first assignment, typed by its
  FIRST LETTER (I-N = INTEGER -> tyInt64, anything else = REAL ->
  tyDouble) — a different inference rule than any other frontend, and it
  drags the tyDouble path through a brand-new frontend (Zig/LOLCODE/
  Whitespace were integer-only).

  Subset: PROGRAM name / END [PROGRAM [name]], IMPLICIT NONE (accepted,
  ignored — implicit typing stays on, it IS the probe), assignment with
  implicit declaration, PRINT *, expr-list, IF (cond) THEN / ELSE /
  END IF, DO v = lo, hi [, step] / END DO (inclusive bounds, constant
  integer step), integer/real/string literals, arithmetic with the
  shared int->double widening, comparisons (modern ==, /=, <, <=, >, >=
  only — the .EQ./.AND. dot-forms and ** are out of scope, as are
  arrays, functions/subroutines, modules, COMMON, FORMAT). }

function FParseExpr: Integer; forward;
function FParseBlock: Integer; forward;
function FParseStatement: Integer; forward;

function FUpcase(const s: AnsiString): AnsiString;
var i: Integer;
begin
  SetLength(Result, Length(s));
  for i := 1 to Length(s) do
  begin
    if s[i] in ['a'..'z'] then Result[i] := Chr(Ord(s[i]) - 32)
    else Result[i] := s[i];
  end;
end;

function FCurIs(const kw: AnsiString): Boolean;
begin
  Result := (CurTok.Kind = tkIdent) and (FUpcase(CurTok.SVal) = kw);
end;

function FNextIs(const kw: AnsiString): Boolean;
begin
  Result := (TokPos < TokCount) and (Tokens[TokPos].Kind = tkIdent) and
            (FUpcase(GetTokenStr(TokPos)) = kw);
end;

procedure FExpectWord(const kw: AnsiString);
begin
  if not FCurIs(kw) then Error('Fortran: expected ' + kw);
  Next;
end;

procedure FEatSep;
begin
  while CurTok.Kind = tkSemicolon do Next;
end;

{ Fortran's implicit-typing rule: first letter I-N = INTEGER, else REAL }
function FImplicitType(const name: AnsiString): TTypeKind;
var c: Char;
begin
  c := name[1];
  if c in ['a'..'z'] then c := Chr(Ord(c) - 32);
  if (c >= 'I') and (c <= 'N') then Result := tyInt64
  else Result := tyDouble;
end;

{ find-or-implicitly-declare }
function FSymFor(const name: AnsiString): Integer;
begin
  Result := FindSym(name);
  if Result < 0 then
    Result := AllocVar(name, FImplicitType(name));
end;

function FParsePrimary: Integer;
var node: Integer; name: AnsiString;
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
    ASTIVal[node] := CurTok.IVal;      { double bits, packed by the lexer }
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
  if CurTok.Kind = tkLParen then
  begin
    Next;
    node := FParseExpr;
    Expect(tkRParen, ')');
    Result := node; Exit;
  end;
  if CurTok.Kind = tkMinus then
  begin
    Next;
    node := AllocNode(AN_NEG);
    ASTLeft[node] := FParsePrimary();
    ASTTk[node] := ASTTk[ASTLeft[node]];
    Result := node; Exit;
  end;
  if CurTok.Kind = tkIdent then
  begin
    name := CurTok.SVal;
    Next;
    if CurTok.Kind = tkLParen then
      Error('Fortran: array indexing / function calls are not in the skeleton subset');
    Result := RMakeIdent(FSymFor(name));
    Exit;
  end;
  Error('Fortran: unexpected token in expression');
  Result := -1;
end;

function FParseMul: Integer;
var left, right: Integer; opTk: TTokenKind;
begin
  left := FParsePrimary;
  while CurTok.Kind in [tkStar, tkSlash] do
  begin
    opTk := CurTok.Kind; Next;
    if (opTk = tkStar) and (CurTok.Kind = tkStar) then
      Error('Fortran: ** (power) is not in the skeleton subset');
    right := FParsePrimary;
    left := RBinOp(opTk, left, right, RWiden(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])));
  end;
  Result := left;
end;

function FParseAdd: Integer;
var left, right: Integer; opTk: TTokenKind;
begin
  left := FParseMul;
  while CurTok.Kind in [tkPlus, tkMinus] do
  begin
    opTk := CurTok.Kind; Next;
    right := FParseMul;
    left := RBinOp(opTk, left, right, RWiden(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])));
  end;
  Result := left;
end;

function FParseExpr: Integer;
var left, right: Integer; opTk: TTokenKind;
begin
  left := FParseAdd;
  if CurTok.Kind in [tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe] then
  begin
    opTk := CurTok.Kind; Next;
    right := FParseAdd;
    left := RBinOp(opTk, left, right, tyBoolean);
  end;
  Result := left;
end;

function FParseStatement: Integer;
var node, exprNode, argNode, lastArg: Integer;
    condNode, thenNode, elseNode, pairNode: Integer;
    loNode, hiNode, bodyNode, initNode, incNode, whileNode: Integer;
    name: AnsiString;
    symIdx: Integer;
    stepVal: Int64;
begin
  Result := -1;

  { PRINT *, expr [, expr]... }
  if FCurIs('PRINT') then
  begin
    Next;
    if CurTok.Kind <> tkStar then Error('Fortran: only list-directed PRINT * is in the skeleton');
    Next;
    node := AllocNode(AN_WRITE);
    ASTKind[node] := AN_WRITELN;
    ASTLeft[node] := -1;
    lastArg := -1;
    while Eat(tkComma) do
    begin
      exprNode := FParseExpr;
      argNode := AllocNode(AN_ARG);
      ASTLeft[argNode] := exprNode;
      ASTRight[argNode] := -1;
      { IR_WRITE reads the :w:d formatting from the ARG node: ASTIVal =
        field width (0 = none), ASTSOffset = decimals where -1 = none.
        AllocNode leaves ASTSOffset at 0, which silently formats REALs
        with ZERO decimals (2.5 printed as "2") — found by this probe's
        first run. }
      ASTSOffset[argNode] := -1;
      if lastArg < 0 then ASTLeft[node] := argNode else ASTRight[lastArg] := argNode;
      lastArg := argNode;
    end;
    Result := node;
    Exit;
  end;

  { IF (cond) THEN <block> [ELSE <block>] END IF }
  if FCurIs('IF') then
  begin
    Next;
    Expect(tkLParen, '(');
    condNode := FParseExpr;
    Expect(tkRParen, ')');
    FExpectWord('THEN');
    FEatSep;
    thenNode := FParseBlock;
    elseNode := -1;
    if FCurIs('ELSE') then
    begin
      Next;
      FEatSep;
      elseNode := FParseBlock;
    end;
    FExpectWord('END');
    FExpectWord('IF');
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

  { DO v = lo, hi [, step] <block> END DO — INCLUSIVE bounds; desugars to
    v := lo; while v <= hi { body; v := v + step } (or >= for negative
    constant steps), the same shape the BASIC/Ada for-lowerings use. }
  if FCurIs('DO') then
  begin
    Next;
    if CurTok.Kind <> tkIdent then Error('Fortran: expected loop variable after DO');
    name := CurTok.SVal;
    Next;
    symIdx := FSymFor(name);
    if Syms[symIdx].TypeKind = tyDouble then
      Error('Fortran: REAL DO variables are not in the skeleton (name your loop variable I-N)');
    Expect(tkAssign, '=');
    loNode := FParseExpr;
    Expect(tkComma, ',');
    hiNode := FParseExpr;
    stepVal := 1;
    if Eat(tkComma) then
    begin
      if CurTok.Kind = tkMinus then
      begin
        Next;
        if CurTok.Kind <> tkInteger then Error('Fortran: DO step must be an integer constant (skeleton)');
        stepVal := -CurTok.IVal;
        Next;
      end
      else
      begin
        if CurTok.Kind <> tkInteger then Error('Fortran: DO step must be an integer constant (skeleton)');
        stepVal := CurTok.IVal;
        Next;
      end;
      if stepVal = 0 then Error('Fortran: DO step of 0');
    end;
    FEatSep;
    bodyNode := FParseBlock;
    FExpectWord('END');
    FExpectWord('DO');

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
    exprNode := AllocNode(AN_ASSIGN);
    ASTLeft[exprNode] := RMakeIdent(symIdx);
    ASTRight[exprNode] := incNode;
    ASTTk[exprNode] := Ord(tyUnknown);
    bodyNode := RSeqAppend(bodyNode, exprNode);

    whileNode := AllocNode(AN_WHILE);
    ASTLeft[whileNode] := condNode;
    ASTRight[whileNode] := bodyNode;
    ASTTk[whileNode] := Ord(tyUnknown);

    Result := RSeqAppend(RSeqAppend(-1, initNode), whileNode);
    Exit;
  end;

  { IMPLICIT NONE — accepted and ignored (implicit typing IS the probe) }
  if FCurIs('IMPLICIT') then
  begin
    Next;
    if CurTok.Kind = tkIdent then Next;
    Result := -1;
    Exit;
  end;

  { assignment: name = expr (declares implicitly on first use) }
  if (CurTok.Kind = tkIdent) and (TokPos < TokCount) and
     (Tokens[TokPos].Kind = tkAssign) then
  begin
    name := CurTok.SVal;
    Next; Next;
    exprNode := FParseExpr;
    symIdx := FSymFor(name);
    node := AllocNode(AN_ASSIGN);
    ASTLeft[node] := RMakeIdent(symIdx);
    ASTRight[node] := exprNode;
    ASTTk[node] := Ord(tyUnknown);
    Result := node;
    Exit;
  end;

  Error('Fortran: unexpected statement');
end;

{ statements until END / ELSE (callers consume the terminator words) }
function FParseBlock: Integer;
var stmt: Integer;
begin
  Result := -1;
  FEatSep;
  while not (FCurIs('END') or FCurIs('ELSE')) do
  begin
    if CurTok.Kind = tkEOF then Error('Fortran: unterminated block');
    stmt := FParseStatement;
    Result := RSeqAppend(Result, stmt);
    FEatSep;
  end;
end;

procedure ParseFProgram;
var stmtList: Integer;
begin
  if TargetArch <> TARGET_X86_64 then
    Error('Fortran frontend: only the x86-64 target is supported by the skeleton (feature-esoteric-fortran)');

  BSS_INITIAL_RSP := BSSSize; Inc(BSSSize, 8);
  EmitB($48); EmitB($89); EmitB($24); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);

  FEatSep;
  FExpectWord('PROGRAM');
  if CurTok.Kind <> tkIdent then Error('Fortran: expected program name');
  Next;
  FEatSep;

  stmtList := FParseBlock;

  FExpectWord('END');
  if FCurIs('PROGRAM') then
  begin
    Next;
    if CurTok.Kind = tkIdent then Next;   { optional trailing program name }
  end;

  CurASTNode := AllocNode(AN_BLOCK);
  ASTLeft[CurASTNode] := stmtList;
  ASTTk[CurASTNode] := Ord(tyUnknown);

  CompileAST(CurASTNode);
  EmitExit(0);
end;
