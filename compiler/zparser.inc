{ SPDX-License-Identifier: MPL-2.0 }
{ ===== Zig Parser (skeleton) =====
  Hand-builds AST directly, same technique as rparser.inc/aparser.inc,
  reusing the shared AN_* node kinds and rparser.inc's small node helpers
  (RSeqAppend/RMakeIdent/RBinOp/RWiden/RIntToStr — included earlier in
  compiler.pas, so plain calls work) — no new AST nodes, no new IR, no
  backend work. This is the esoteric-frontend-probe skeleton
  (devdocs/progress/working/feature-zig-frontend.md, sub-ticket 1): the
  goal is exercising the shared AST->IR->codegen pipeline with a Zig-shaped
  program, NOT making Zig usable.

  v1 subset: top-level `[pub] fn name(a: i64, ...) RetType { ... }`
  functions (max 4 scalar params, same limit as the Rust skeleton),
  `var`/`const` declarations with optional type annotation (type inferred
  from the initializer otherwise, incl. `= undefined` for declare-only),
  assignment and compound assignment (+= -= *= /=), if/else if/else,
  while with optional `: (continue-expression)`, range for
  `for (lo..hi) |i|` (exclusive upper bound, per Zig), break/continue,
  return, integer/bool/string expressions with and/or, function calls,
  and `std.debug.print("fmt", .{args})` lowered onto the same
  AN_WRITE/AN_WRITELN machinery Pascal's writeln and BASIC's PRINT use
  ({}/{d}/{s}/{c}/{any} placeholders; {{ }} escapes NOT handled).

  Known semantic deviations, accepted for a probe skeleton:
  - `continue` inside a `while ... : (expr)` loop skips the continue
    expression (Zig runs it); the test avoids that combination.
  - No integer overflow/underflow safety checks, no comptime, no error
    unions/optionals/slices/structs — see the umbrella ticket's non-goals.
  - `const` is not enforced as immutable (parsed like `var`).
  - `/` and `%` follow the shared IR's division semantics (no divTrunc
    distinction), fine for the positive-operand test programs. }

function ZParseExpr: Integer; forward;
function ZParseBlock: Integer; forward;
function ZParseStatement: Integer; forward;
function ZParseIf: Integer; forward;

function ZTypeKindFromName(const name: AnsiString): TTypeKind;
begin
  Result := tyUnknown;
  if name = 'i8' then Result := tyInt8
  else if name = 'u8' then Result := tyUInt8
  else if name = 'i16' then Result := tyInt16
  else if name = 'u16' then Result := tyUInt16
  else if name = 'i32' then Result := tyInteger
  else if name = 'u32' then Result := tyUInt32
  else if name = 'i64' then Result := tyInt64
  else if name = 'u64' then Result := tyUInt64
  else if name = 'isize' then Result := tyNativeInt
  else if name = 'usize' then Result := tyNativeUInt
  else if name = 'bool' then Result := tyBoolean
  { void: callers ignore the value; the unused Result slot trick C's void
    and the Rust skeleton's () already use. }
  else if name = 'void' then Result := tyInteger
  else Error('Zig: unknown type ' + name + ' (skeleton supports the fixed-width integer types, bool and void only)');
end;

function ZParsePrimary: Integer;
var node, symIdx, procIdx, argNode, lastArg: Integer;
    name: AnsiString;
begin
  case CurTok.Kind of
    tkInteger:
    begin
      node := AllocNode(AN_INT_LIT); ASTIVal[node] := CurTok.IVal; ASTTk[node] := Ord(tyInteger);
      Next; Result := node;
    end;
    tkTrue:
    begin
      node := AllocNode(AN_BOOL_LIT); ASTIVal[node] := 1; ASTTk[node] := Ord(tyBoolean);
      Next; Result := node;
    end;
    tkFalse:
    begin
      node := AllocNode(AN_BOOL_LIT); ASTIVal[node] := 0; ASTTk[node] := Ord(tyBoolean);
      Next; Result := node;
    end;
    tkString:
    begin
      node := AllocNode(AN_STR_LIT);
      ASTSOffset[node] := Tokens[TokPos - 1].SOffset;
      ASTSLen[node] := Tokens[TokPos - 1].SLen;
      ASTTk[node] := Ord(tyString);
      Next; Result := node;
    end;
    tkLParen:
    begin
      Next; node := ZParseExpr; Expect(tkRParen, ')'); Result := node;
    end;
    tkIdent:
    begin
      name := CurTok.SVal;
      if (Length(name) > 0) and (name[1] = '@') then
        Error('Zig: builtin ' + name + ' is not supported by the frontend skeleton (feature-zig-frontend)');
      Next;
      if CurTok.Kind = tkLParen then
      begin
        procIdx := FindProc(name);
        if procIdx < 0 then Error('Zig: call to undefined function ' + name);
        Next;
        node := AllocNode(AN_CALL);
        ASTIVal[node] := procIdx;
        ASTTk[node] := Ord(Procs[procIdx].RetType);
        lastArg := -1;
        if CurTok.Kind <> tkRParen then
          repeat
            argNode := AllocNode(AN_ARG);
            ASTLeft[argNode] := ZParseExpr;
            ASTRight[argNode] := -1;
            if lastArg < 0 then ASTLeft[node] := argNode else ASTRight[lastArg] := argNode;
            lastArg := argNode;
          until not Eat(tkComma);
        Expect(tkRParen, ')');
        Result := node;
        Exit;
      end;
      symIdx := FindSym(name);
      if symIdx < 0 then Error('Zig: undefined variable ' + name);
      Result := RMakeIdent(symIdx);
    end;
    else
    begin
      Error('Zig: unexpected token in expression');
      Result := -1;
    end;
  end;
end;

function ZParseUnary: Integer;
var node: Integer;
begin
  if CurTok.Kind = tkMinus then
  begin
    Next;
    node := AllocNode(AN_NEG);
    ASTLeft[node] := ZParseUnary();
    ASTTk[node] := ASTTk[ASTLeft[node]];
    Result := node;
    Exit;
  end;
  if CurTok.Kind = tkLogNot then
  begin
    Next;
    node := AllocNode(AN_NOT);
    ASTLeft[node] := ZParseUnary();
    ASTTk[node] := Ord(tyBoolean);
    Result := node;
    Exit;
  end;
  Result := ZParsePrimary;
end;

function ZParseMul: Integer;
var left, right: Integer; opTk: TTokenKind; rt: TTypeKind;
begin
  left := ZParseUnary;
  while CurTok.Kind in [tkStar, tkSlash, tkMod] do
  begin
    opTk := CurTok.Kind; Next;
    right := ZParseUnary;
    rt := RWiden(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right]));
    { Zig / on integers is trunc division — the shared tkSlash BINOP is
      Pascal's REAL division (yields double bits; reinterpreted as int64
      that's garbage, found by the probe's own first run). All skeleton
      types are integers, so lower / as tkDiv (integer div) always. }
    if opTk = tkSlash then opTk := tkDiv;
    left := RBinOp(opTk, left, right, rt);
  end;
  Result := left;
end;

function ZParseAdd: Integer;
var left, right: Integer; opTk: TTokenKind;
begin
  left := ZParseMul;
  while CurTok.Kind in [tkPlus, tkMinus] do
  begin
    opTk := CurTok.Kind; Next;
    right := ZParseMul;
    left := RBinOp(opTk, left, right, RWiden(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])));
  end;
  Result := left;
end;

function ZParseCmp: Integer;
var left, right: Integer; opTk: TTokenKind;
begin
  left := ZParseAdd;
  if CurTok.Kind in [tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe] then
  begin
    opTk := CurTok.Kind; Next;
    right := ZParseAdd;
    left := RBinOp(opTk, left, right, tyBoolean);
  end;
  Result := left;
end;

function ZParseAnd: Integer;
var left, right: Integer;
begin
  left := ZParseCmp;
  while CurTok.Kind = tkAnd do
  begin
    Next;
    right := ZParseCmp;
    left := RBinOp(tkAnd, left, right, tyBoolean);
  end;
  Result := left;
end;

function ZParseExpr: Integer;
var left, right: Integer;
begin
  left := ZParseAnd;
  while CurTok.Kind = tkOr do
  begin
    Next;
    right := ZParseAnd;
    left := RBinOp(tkOr, left, right, tyBoolean);
  end;
  Result := left;
end;

function ZParseIf: Integer;
var node, pairNode, condNode, thenNode, elseNode: Integer;
begin
  Next; { if }
  Expect(tkLParen, '(');   { Zig requires parens around the condition }
  condNode := ZParseExpr;
  Expect(tkRParen, ')');
  Expect(tkBegin, '{');
  thenNode := ZParseBlock;
  Expect(tkEnd, '}');
  elseNode := -1;
  if CurTok.Kind = tkElse then
  begin
    Next;
    if CurTok.Kind = tkIf then
      { Parens force a real recursive call — a bare name here would read the
        implicit Result alias instead (documented project pitfall, see
        frank2-paramless-name-semantics / rparser.inc's identical comment). }
      elseNode := ZParseIf()
    else
    begin
      Expect(tkBegin, '{');
      elseNode := ZParseBlock;
      Expect(tkEnd, '}');
    end;
  end;
  pairNode := AllocNode(AN_PAIR);
  ASTLeft[pairNode] := thenNode;
  ASTRight[pairNode] := elseNode;
  node := AllocNode(AN_IF);
  ASTLeft[node] := condNode;
  ASTRight[node] := pairNode;
  Result := node;
end;

{ Shared by plain assignment statements and the while-loop continue
  expression: `name = expr` / `name op= expr`, desugaring compound forms to
  name = name op expr. Does NOT consume a trailing `;`. }
function ZParseAssign: Integer;
var name: AnsiString; symIdx, rhsNode, node: Integer; opTk: TTokenKind;
begin
  if CurTok.Kind <> tkIdent then Error('Zig: expected variable name in assignment');
  name := CurTok.SVal;
  symIdx := FindSym(name);
  if symIdx < 0 then Error('Zig: assignment to undefined variable ' + name);
  Next;
  opTk := CurTok.Kind;
  if not (opTk in [tkAssign, tkPlusEq, tkMinusEq, tkStarEq, tkSlashEq]) then
    Error('Zig: expected = or compound assignment after ' + name);
  Next;
  rhsNode := ZParseExpr;
  case opTk of
    tkPlusEq:  rhsNode := RBinOp(tkPlus,  RMakeIdent(symIdx), rhsNode, Syms[symIdx].TypeKind);
    tkMinusEq: rhsNode := RBinOp(tkMinus, RMakeIdent(symIdx), rhsNode, Syms[symIdx].TypeKind);
    tkStarEq:  rhsNode := RBinOp(tkStar,  RMakeIdent(symIdx), rhsNode, Syms[symIdx].TypeKind);
    tkSlashEq: rhsNode := RBinOp(tkSlash, RMakeIdent(symIdx), rhsNode, Syms[symIdx].TypeKind);
    else ;
  end;
  node := AllocNode(AN_ASSIGN);
  ASTLeft[node] := RMakeIdent(symIdx);
  ASTRight[node] := rhsNode;
  Result := node;
end;

function ZParseWhile: Integer;
var node, condNode, bodyNode, contNode: Integer;
begin
  Next; { while }
  Expect(tkLParen, '(');
  condNode := ZParseExpr;
  Expect(tkRParen, ')');
  contNode := -1;
  if CurTok.Kind = tkColon then
  begin
    { `while (cond) : (i += 1) { ... }` — the continue expression runs after
      each iteration; desugared by appending it to the body end. (Deviation:
      `continue` skips it here — see the header note.) }
    Next;
    Expect(tkLParen, '(');
    contNode := ZParseAssign;
    Expect(tkRParen, ')');
  end;
  Expect(tkBegin, '{');
  bodyNode := ZParseBlock;
  Expect(tkEnd, '}');
  if contNode <> -1 then
    bodyNode := RSeqAppend(bodyNode, contNode);
  node := AllocNode(AN_WHILE);
  ASTLeft[node] := condNode;
  ASTRight[node] := bodyNode;
  Result := node;
end;

{ `for (lo..hi) |name| { ... }` — Zig's range for; upper bound EXCLUSIVE
  (unlike Pascal/Ada/BASIC), so the desugared loop compares with < :
  i := lo; while i < hi { body; i := i + 1 } — same AN_ASSIGN/AN_WHILE
  shape aparser.inc's for-lowering uses. }
function ZParseFor: Integer;
var vname: AnsiString;
    symIdx, loNode, hiNode, bodyNode, initNode, condNode, incNode, oneNode, whileNode: Integer;
begin
  Next; { for }
  Expect(tkLParen, '(');
  loNode := ZParseExpr;
  Expect(tkDotDot, '..');
  hiNode := ZParseExpr;
  Expect(tkRParen, ')');
  Expect(tkPipe, '|');
  if CurTok.Kind <> tkIdent then Error('Zig: expected capture name in |x|');
  vname := CurTok.SVal;
  Next;
  Expect(tkPipe, '|');

  symIdx := AllocVar(vname, tyInt64);

  Expect(tkBegin, '{');
  bodyNode := ZParseBlock;
  Expect(tkEnd, '}');

  initNode := AllocNode(AN_ASSIGN);
  ASTLeft[initNode] := RMakeIdent(symIdx);
  ASTRight[initNode] := loNode;

  condNode := RBinOp(tkLt, RMakeIdent(symIdx), hiNode, tyBoolean);

  incNode := AllocNode(AN_INT_LIT);
  ASTIVal[incNode] := 1;
  ASTTk[incNode] := Ord(tyInteger);
  incNode := RBinOp(tkPlus, RMakeIdent(symIdx), incNode, tyInt64);
  oneNode := incNode;
  incNode := AllocNode(AN_ASSIGN);
  ASTLeft[incNode] := RMakeIdent(symIdx);
  ASTRight[incNode] := oneNode;
  bodyNode := RSeqAppend(bodyNode, incNode);

  whileNode := AllocNode(AN_WHILE);
  ASTLeft[whileNode] := condNode;
  ASTRight[whileNode] := bodyNode;

  Result := RSeqAppend(RSeqAppend(-1, initNode), whileNode);
end;

{ `var name [: T] = expr;` / `const name [: T] = expr;` — const is parsed
  like var (no immutability enforcement in the skeleton). `= undefined`
  declares without initializing. Type inferred from the initializer when
  no annotation is given (Zig infers pervasively). Trailing `;` left to
  the caller. }
function ZParseVarDecl: Integer;
var name: AnsiString; symIdx, rhsNode, node: Integer;
    vtype: TTypeKind; hasType: Boolean;
begin
  Next; { var / const }
  if CurTok.Kind <> tkIdent then Error('Zig: expected name after var/const');
  name := CurTok.SVal;
  Next;
  vtype := tyInt64; hasType := False;
  if CurTok.Kind = tkColon then
  begin
    Next;
    if CurTok.Kind <> tkIdent then Error('Zig: expected type name after :');
    vtype := ZTypeKindFromName(CurTok.SVal);
    hasType := True;
    Next;
  end;
  Expect(tkAssign, '=');
  if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'undefined') then
  begin
    Next;
    if not hasType then Error('Zig: `= undefined` needs an explicit type annotation');
    AllocVar(name, vtype);
    Result := -1;
    Exit;
  end;
  rhsNode := ZParseExpr;
  if not hasType then
  begin
    vtype := IntToTypeKind(ASTTk[rhsNode]);
    if vtype = tyUnknown then vtype := tyInt64;
    { Zig's `const x = 42` makes a comptime_int; the closest runtime type
      the skeleton has is i64 for integers, so widen small literals. }
    if vtype = tyInteger then vtype := tyInt64;
  end;
  symIdx := AllocVar(name, vtype);
  node := AllocNode(AN_ASSIGN);
  ASTLeft[node] := RMakeIdent(symIdx);
  ASTRight[node] := rhsNode;
  Result := node;
end;

{ `std.debug.print("fmt", .{arg, ...});` — the only std call the skeleton
  understands. The fmt string is split on {...} placeholders; literal
  segments become AN_STR_LIT nodes pointing straight into the fmt token's
  already-decoded TokChars bytes (segments are substrings, so offset
  arithmetic suffices — no copying), each placeholder consumes the next
  .{...} argument, and everything is chained as one AN_ARG list under a
  single AN_WRITE / AN_WRITELN (WRITELN when fmt ends in \n, which is then
  stripped), exactly the shape BASIC's PRINT emits. {{ }} escapes are not
  handled (skeleton). }
function ZParseStdDebugPrint: Integer;
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
  Next; { std }
  Expect(tkDot, '.');
  if not ((CurTok.Kind = tkIdent) and (CurTok.SVal = 'debug')) then
    Error('Zig: only std.debug.print is supported by the frontend skeleton');
  Next;
  Expect(tkDot, '.');
  if not ((CurTok.Kind = tkIdent) and (CurTok.SVal = 'print')) then
    Error('Zig: only std.debug.print is supported by the frontend skeleton');
  Next;
  Expect(tkLParen, '(');
  if CurTok.Kind <> tkString then Error('Zig: std.debug.print needs a string literal format');
  fmtOff := Tokens[TokPos - 1].SOffset;
  fmtLen := Tokens[TokPos - 1].SLen;
  Next;

  { collect the .{...} argument expressions up front }
  argCount := 0;
  if Eat(tkComma) then
  begin
    Expect(tkDot, '.');
    Expect(tkBegin, '{');
    if CurTok.Kind <> tkEnd then
      repeat
        if argCount > 7 then Error('Zig: std.debug.print supports at most 8 arguments (skeleton)');
        argExprs[argCount] := ZParseExpr;
        Inc(argCount);
      until not Eat(tkComma);
    Expect(tkEnd, '}');
  end;
  Expect(tkRParen, ')');

  isLn := (fmtLen > 0) and (TokChars[fmtOff + fmtLen - 1] = #10);
  if isLn then Dec(fmtLen);

  node := AllocNode(AN_WRITE);
  if isLn then ASTKind[node] := AN_WRITELN;
  ASTLeft[node] := -1;
  lastArg := -1;
  argUsed := 0;

  segStart := 0;
  i := 0;
  while i < fmtLen do
  begin
    if TokChars[fmtOff + i] = '{' then
    begin
      AddSegment(fmtOff + segStart, i - segStart);
      while (i < fmtLen) and (TokChars[fmtOff + i] <> '}') do Inc(i);
      if i >= fmtLen then Error('Zig: unterminated {} placeholder in format string');
      Inc(i); { step past the closing brace }
      segStart := i;
      if argUsed >= argCount then Error('Zig: more {} placeholders than .{} arguments');
      AddArg(argExprs[argUsed]);
      Inc(argUsed);
    end
    else
      Inc(i);
  end;
  AddSegment(fmtOff + segStart, fmtLen - segStart);
  if argUsed < argCount then Error('Zig: more .{} arguments than {} placeholders');

  Result := node;
end;

function ZParseStatement: Integer;
var node: Integer;
begin
  case CurTok.Kind of
    tkIf: begin Result := ZParseIf; Exit; end;
    tkWhile: begin Result := ZParseWhile; Exit; end;
    tkFor: begin Result := ZParseFor; Exit; end;
    tkBegin: begin Next; Result := ZParseBlock; Expect(tkEnd, '}'); Exit; end;
    tkSemicolon: begin Next; Result := -1; Exit; end;
    tkVar, tkConst:
    begin
      Result := ZParseVarDecl;
      Expect(tkSemicolon, ';');
      Exit;
    end;
    tkExit:
    begin
      Next;
      node := AllocNode(AN_EXIT);
      if CurTok.Kind <> tkSemicolon then ASTLeft[node] := ZParseExpr;
      Expect(tkSemicolon, ';');
      Result := node;
      Exit;
    end;
    tkBreak: begin Next; Expect(tkSemicolon, ';'); Result := AllocNode(AN_BREAK); Exit; end;
    tkContinue: begin Next; Expect(tkSemicolon, ';'); Result := AllocNode(AN_CONTINUE); Exit; end;
  end;

  if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'std') and
     (Tokens[TokPos].Kind = tkDot) then
  begin
    Result := ZParseStdDebugPrint;
    Expect(tkSemicolon, ';');
    Exit;
  end;

  { `_ = expr;` discard — common in Zig for unused results. Must be checked
    BEFORE the general assignment branch, which would otherwise report `_`
    as an undefined variable. }
  if (CurTok.Kind = tkIdent) and (CurTok.SVal = '_') and
     (Tokens[TokPos].Kind = tkAssign) then
  begin
    Next; Next;
    Result := ZParseExpr;   { evaluated for side effects, value dropped }
    Expect(tkSemicolon, ';');
    Exit;
  end;

  if (CurTok.Kind = tkIdent) and
     (Tokens[TokPos].Kind in [tkAssign, tkPlusEq, tkMinusEq, tkStarEq, tkSlashEq]) then
  begin
    Result := ZParseAssign;
    Expect(tkSemicolon, ';');
    Exit;
  end;

  Result := ZParseExpr;   { bare call statement }
  Expect(tkSemicolon, ';');
end;

function ZParseBlock: Integer;
var stmt: Integer;
begin
  Result := -1;
  while CurTok.Kind <> tkEnd do
  begin
    if CurTok.Kind = tkEOF then Error('Zig: unterminated block (missing })');
    stmt := ZParseStatement;
    Result := RSeqAppend(Result, stmt);
  end;
end;

{ ===== Top-level: fn signature prescan, then body compilation ===== }

{ Registers the fn signature starting at Tokens[i] (must be tkFn); returns
  nothing useful beyond the registration side effect. Zig signature shape:
  fn name(p: T, ...) RetType — return type directly after ), no arrow. }
procedure ZRegisterFnSignatureAt(i: Integer; var mainIsVoid: Boolean);
var j, nparams, k, procIdx: Integer; name, retName: AnsiString;
    pnames: array[0..3] of AnsiString; ptypes: array[0..3] of TTypeKind;
    retType: TTypeKind;
begin
  name := GetTokenStr(i + 1);
  j := i + 2;
  if Tokens[j].Kind <> tkLParen then Error('Zig: expected ( after fn ' + name);
  Inc(j); nparams := 0;
  while Tokens[j].Kind <> tkRParen do
  begin
    if nparams >= 4 then Error('Zig: too many parameters (skeleton limit is 4)');
    if Tokens[j].Kind <> tkIdent then Error('Zig: expected parameter name in ' + name);
    pnames[nparams] := GetTokenStr(j); Inc(j);
    if Tokens[j].Kind <> tkColon then Error('Zig: expected : in parameter list of ' + name);
    Inc(j);
    if Tokens[j].Kind <> tkIdent then Error('Zig: expected parameter type in ' + name);
    ptypes[nparams] := ZTypeKindFromName(GetTokenStr(j));
    Inc(j);
    Inc(nparams);
    if Tokens[j].Kind = tkComma then Inc(j);
  end;
  Inc(j); { consume ) }
  if Tokens[j].Kind <> tkIdent then Error('Zig: expected return type after ) in fn ' + name);
  retName := GetTokenStr(j);
  retType := ZTypeKindFromName(retName);
  if (name = 'main') and (retName = 'void') then mainIsVoid := True;
  procIdx := RegisterProc(name, True, retType, nparams, pnames, ptypes);
  k := procIdx; { silence unused warning on compilers that care }
  if k < 0 then Error('Zig: internal error registering ' + name);
end;

procedure ZRegisterFnSignatures(var mainIsVoid: Boolean);
var i, depth: Integer;
begin
  i := 0; depth := 0;
  while Tokens[i].Kind <> tkEOF do
  begin
    if Tokens[i].Kind = tkBegin then Inc(depth)
    else if Tokens[i].Kind = tkEnd then Dec(depth)
    else if (depth = 0) and (Tokens[i].Kind = tkFn) and (Tokens[i + 1].Kind = tkIdent) then
      ZRegisterFnSignatureAt(i, mainIsVoid);
    Inc(i);
  end;
end;

procedure ZParseTopLevelFn;
var name, pname: AnsiString;
    procIdx, nparams, i, idx, savedSC, savedFS, patchPos, bodyNode: Integer;
    pnames: array[0..3] of AnsiString; ptypes: array[0..3] of TTypeKind;
begin
  Next; { fn }
  if CurTok.Kind <> tkIdent then Error('Zig: expected function name');
  name := CurTok.SVal; Next;
  procIdx := FindProc(name);
  if procIdx < 0 then Error('Zig: internal error — signature prescan missed ' + name);
  Expect(tkLParen, '(');
  nparams := 0;
  while CurTok.Kind <> tkRParen do
  begin
    if CurTok.Kind <> tkIdent then Error('Zig: expected parameter name');
    pname := CurTok.SVal; Next;
    Expect(tkColon, ':');
    if CurTok.Kind <> tkIdent then Error('Zig: expected parameter type');
    ptypes[nparams] := ZTypeKindFromName(CurTok.SVal);
    pnames[nparams] := pname;
    Next;
    Inc(nparams);
    if not Eat(tkComma) then Break;
  end;
  Expect(tkRParen, ')');
  if CurTok.Kind <> tkIdent then Error('Zig: expected return type after )');
  Next; { return type — already registered by the prescan }

  savedSC := SymCount; savedFS := FrameSize;
  FrameSize := 0; CurProc := procIdx;
  Procs[procIdx].BodyAddr := CodeLen;
  Procs[procIdx].ScopeBase := SymCount;
  for i := 0 to nparams - 1 do
  begin
    idx := AllocParam(pnames[i], ptypes[i], False, False);
    Procs[procIdx].Params[i].SymIdx := idx;
  end;
  idx := AllocVar('Result', Procs[procIdx].RetType);
  Procs[procIdx].RetSymIdx := idx;

  patchPos := EmitProcPrologue;
  Procs[procIdx].FramePatch := patchPos;
  { spill the SysV integer arg registers (rdi/rsi/rdx/rcx) into the frame
    slots — byte-for-byte the sequence RParseTopLevelFn emits. }
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

  Expect(tkBegin, '{');
  bodyNode := ZParseBlock;
  Expect(tkEnd, '}');

  CompileAST(bodyNode);
  EmitProcEpilog(Procs[procIdx].RetSymIdx);
  PatchProcPrologue(patchPos, FrameSize);
  SymRollbackTo(savedSC);
  FrameSize := savedFS;
  CurProc := -1;
end;

procedure ParseZigProgram;
var callPatch, mainIdx: Integer;
    mainIsVoid: Boolean;
begin
  if TargetArch <> TARGET_X86_64 then
    Error('Zig frontend: only the x86-64 target is supported by the skeleton (feature-zig-frontend)');

  mainIsVoid := False;
  ZRegisterFnSignatures(mainIsVoid);
  mainIdx := FindProc('main');
  if mainIdx < 0 then Error('Zig: no fn main() found');

  BSS_INITIAL_RSP := BSSSize; Inc(BSSSize, 8);
  { Entry stub: call main(), then exit_group — with main's return value as
    the exit code when main returns an integer, or 0 for `fn main() void`
    (whose Result slot is never written, so its eax is garbage). Same
    convention as the Rust skeleton's stub. }
  EmitB($48); EmitB($89); EmitB($24); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
  EmitB($E8); callPatch := CodeLen; EmitI32(0);   { call main }
  if mainIsVoid then
  begin
    EmitB($31); EmitB($FF);          { xor edi, edi }
  end
  else
  begin
    EmitB($89); EmitB($C7);          { mov edi, eax }
  end;
  EmitB($B8); EmitI32(231);          { mov eax, 231 (exit_group) }
  EmitB($0F); EmitB($05);            { syscall }

  while CurTok.Kind <> tkEOF do
  begin
    { `pub` is accepted and ignored (no module system in the skeleton). }
    if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'pub') then Next
    { `const std = @import("std");` — accepted and swallowed whole so real
      Zig program headers parse; std is special-cased in ZParseStatement. }
    else if (CurTok.Kind = tkConst) and (Tokens[TokPos].Kind = tkIdent) and
            (GetTokenStr(TokPos) = 'std') then
    begin
      while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
      Expect(tkSemicolon, ';');
    end
    else if CurTok.Kind = tkFn then ZParseTopLevelFn
    else Error('Zig: expected fn (or pub fn) at top level');
  end;

  ApplyCallFixups;
  Patch32(callPatch, Procs[mainIdx].BodyAddr - (callPatch + 4));
end;
