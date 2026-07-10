{ SPDX-License-Identifier: MPL-2.0 }
{ ===== Whitespace Frontend (skeleton) =====
  Esoteric-frontend-probe (feature-esoteric-whitespace). Two deliberate
  extremes in one probe:
  - LEXER SHAPE: the only meaningful characters are space, tab and
    linefeed; EVERYTHING else is a comment. There is no token stream at
    all — this frontend never touches Tokens[]/CurTok/Next and reads
    Source[] directly, character by character.
  - LOWERING DIRECTION: Whitespace is a flat stack machine, not an
    AST-shaped language. Lowering runs BACKWARDS from every other
    frontend: instructions are folded through a compile-time stack of
    AST NODE IDS — push puts an AN_INT_LIT node on it, arithmetic pops
    two nodes and pushes an AN_BINOP over them, and only the I/O
    instructions emit actual statements (AN_WRITE over whatever
    expression tree the stack reconstructed). dup re-pushes the same
    node id (safe: the skeleton's expressions are pure).

  Instruction subset (S=space, T=tab, L=linefeed):
    S S <sign><binary>L    push number (sign: S=+, T=-; digits: S=0, T=1)
    S L S                  dup top
    S L T? / heap / ...    NOT in the skeleton
    T S S S                add        T S S T   sub       T S S L  mul
    T S T S                div        T S T T   mod
    T L S S                output top as CHAR
    T L S T                output top as NUMBER
    L L L                  end program
  Flow control (labels/jumps/call) and heap access are explicitly out of
  scope — the ticket caps this at proving the pipe end-to-end. }

{ Frontend-local transient state. A var section this late in the include chain
  once tripped a false "global declared later" from the impl prescan: pass-2
  nested-routine excisions renumbered token indices and shifted the body-header
  horizon while the globals' recorded token indices went stale. Fixed by keying
  decl-order on the immutable SOffset (char-pool position) instead of the token
  index — see the note in ParseSubroutine (bug-impl-prescan-late-include-var-section).
  Keeping the state here (not in defs.inc) doubles as the self-host regression
  guard for that fix. }
var
  WsPos: Integer;                                 { read cursor into Source }
  WsStk: array[0..MAX_WS_STACK-1] of Integer;     { AST node ids }
  WsSp: Integer;
  WsStmtList: Integer;
  WsDone: Boolean;

{ next meaningful char: 's', 't', 'n', or #0 at end of input }
function WsNext: Char;
begin
  Result := #0;
  while WsPos <= Length(Source) do
  begin
    case Source[WsPos] of
      ' ':  begin Inc(WsPos); Result := 's'; Exit; end;
      #9:   begin Inc(WsPos); Result := 't'; Exit; end;
      #10:  begin Inc(WsPos); Result := 'n'; Exit; end;
      else Inc(WsPos);   { any other character is a comment }
    end;
  end;
end;

function WsNextOrDie: Char;
begin
  Result := WsNext;
  if Result = #0 then Error('Whitespace: unexpected end of input mid-instruction');
end;

{ <sign><binary digits>L }
function WsReadNumber: Int64;
var c: Char; neg: Boolean; v: Int64;
begin
  c := WsNextOrDie;
  neg := (c = 't');
  v := 0;
  c := WsNextOrDie;
  while c <> 'n' do
  begin
    v := v * 2;
    if c = 't' then v := v + 1;
    c := WsNextOrDie;
  end;
  if neg then v := -v;
  Result := v;
end;

procedure WsPush(node: Integer);
begin
  if WsSp >= MAX_WS_STACK then Error('Whitespace: stack too deep (skeleton limit)');
  WsStk[WsSp] := node;
  Inc(WsSp);
end;

function WsPop: Integer;
begin
  if WsSp <= 0 then Error('Whitespace: stack underflow');
  Dec(WsSp);
  Result := WsStk[WsSp];
end;

function WsMkInt(v: Int64): Integer;
begin
  Result := AllocNode(AN_INT_LIT);
  ASTIVal[Result] := v;
  ASTTk[Result] := Ord(tyInt64);
end;

{ pop b, pop a, push a <op> b (operand order per the Whitespace spec) }
procedure WsArith(op: TTokenKind);
var a, b, node: Integer;
begin
  b := WsPop;
  a := WsPop;
  node := AllocNode(AN_BINOP);
  ASTIVal[node] := Ord(op);
  ASTLeft[node] := a;
  ASTRight[node] := b;
  ASTTk[node] := Ord(tyInt64);
  WsPush(node);
end;

{ AN_WRITE (no newline — Whitespace output is explicit char-by-char) }
procedure WsEmitWrite(exprNode: Integer; asChar: Boolean);
var wr, arg: Integer;
begin
  if asChar then
  begin
    { same expression, viewed as a char: the write lowering picks the
      formatting by the arg node's type tag }
    arg := AllocNode(AN_BINOP);
    ASTIVal[arg] := Ord(tkPlus);
    ASTLeft[arg] := exprNode;
    ASTRight[arg] := WsMkInt(0);
    ASTTk[arg] := Ord(tyChar);
    exprNode := arg;
  end;
  arg := AllocNode(AN_ARG);
  ASTLeft[arg] := exprNode;
  ASTRight[arg] := -1;
  wr := AllocNode(AN_WRITE);
  ASTLeft[wr] := arg;
  WsStmtList := RSeqAppend(WsStmtList, wr);
end;

procedure WsInstr;
var c: Char; d: Integer;
begin
  c := WsNext;
  if c = #0 then begin WsDone := True; Exit; end;   { implicit end at EOF }
  if c = 's' then
  begin
    { Stack Manipulation IMP }
    c := WsNextOrDie;
    if c = 's' then WsPush(WsMkInt(WsReadNumber))
    else if c = 'n' then
    begin
      c := WsNextOrDie;
      if c = 's' then
      begin
        if WsSp <= 0 then Error('Whitespace: dup on empty stack');
        WsPush(WsStk[WsSp - 1]);                   { dup (pure exprs only) }
      end
      else if c = 'n' then
        d := WsPop                                 { discard top }
      else Error('Whitespace: S L T (swap) is not in the skeleton subset');
    end
    else Error('Whitespace: S T (copy/slide) is not in the skeleton subset');
  end
  else if c = 't' then
  begin
    c := WsNextOrDie;
    if c = 's' then
    begin
      { Arithmetic IMP }
      c := WsNextOrDie;
      if c = 's' then
      begin
        c := WsNextOrDie;
        if c = 's' then WsArith(tkPlus)
        else if c = 't' then WsArith(tkMinus)
        else WsArith(tkStar)
      end
      else
      begin
        c := WsNextOrDie;
        if c = 's' then WsArith(tkDiv)
        else if c = 't' then WsArith(tkMod)
        else Error('Whitespace: bad arithmetic instruction');
      end;
    end
    else if c = 'n' then
    begin
      { I/O IMP }
      c := WsNextOrDie;
      if c <> 's' then Error('Whitespace: read instructions (T L T *) are not in the skeleton subset');
      c := WsNextOrDie;
      if c = 's' then WsEmitWrite(WsPop, True)
      else if c = 't' then WsEmitWrite(WsPop, False)
      else Error('Whitespace: bad I/O instruction');
    end
    else Error('Whitespace: heap access (T T *) is not in the skeleton subset');
  end
  else { 'n' — Flow Control IMP }
  begin
    c := WsNextOrDie;
    if c = 'n' then
    begin
      c := WsNextOrDie;
      if c = 'n' then WsDone := True                { L L L: end program }
      else Error('Whitespace: bad flow-control instruction');
    end
    else Error('Whitespace: labels/jumps/call (L S *, L T *) are not in the skeleton subset');
  end;
end;

procedure ParseWsProgram;
begin
  if TargetArch <> TARGET_X86_64 then
    Error('Whitespace frontend: only the x86-64 target is supported by the skeleton (feature-esoteric-whitespace)');

  BSS_INITIAL_RSP := BSSSize; Inc(BSSSize, 8);
  EmitB($48); EmitB($89); EmitB($24); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);

  WsPos := 1;
  WsSp := 0;
  WsStmtList := -1;
  WsDone := False;
  while not WsDone do
    WsInstr;

  CurASTNode := AllocNode(AN_BLOCK);
  ASTLeft[CurASTNode] := WsStmtList;
  ASTTk[CurASTNode] := Ord(tyUnknown);

  CompileAST(CurASTNode);
  EmitExit(0);
end;
