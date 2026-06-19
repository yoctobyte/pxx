{$ifdef FPC}
procedure LoadFile(const path: AnsiString; var dst: AnsiString); forward;
{$endif}
function GetFilePath(const path: AnsiString): AnsiString; forward;
function GetFileBaseName(const path: AnsiString): AnsiString; forward;
procedure NormalizePath(var p: AnsiString); forward;
procedure ExpandIncludes(var src: AnsiString; const baseDir: AnsiString); forward;
procedure ParseCUnit; forward;
procedure RegisterCMacroConsts; forward;
procedure EmitAnsiStringRuntime; forward;


function AllocNode(kind: Integer): Integer;
begin
  if ASTNodeCount >= MAX_AST then Error('AST node overflow');
  ASTKind[ASTNodeCount]    := kind;
  ASTIVal[ASTNodeCount]    := 0;
  ASTSOffset[ASTNodeCount] := 0;
  ASTSLen[ASTNodeCount]    := 0;
  ASTLeft[ASTNodeCount]    := -1;
  ASTRight[ASTNodeCount]   := -1;
  ASTTk[ASTNodeCount]      := 0;
  ASTLiftedVar[ASTNodeCount] := -1;
  Result := ASTNodeCount;
  Inc(ASTNodeCount);
end;

procedure InferSymTypeFromNode(symIdx: Integer; node: Integer);
var tk: TTypeKind; pi, recId, varIdx: Integer;
begin
  tk := IntToTypeKind(ASTTk[node]);
  Syms[symIdx].TypeKind := tk;
  
  if tk = tyRecord then
    Syms[symIdx].RecName := ResolveNodeRec(node)
  else if tk = tyClass then
    Syms[symIdx].RecName := ResolveNodeRec(node)
  else if tk = tyPointer then
  begin
    { If it's an identifier }
    if ASTKind[node] = AN_IDENT then
    begin
      varIdx := ASTIVal[node];
      if (varIdx >= 0) and (varIdx < SymCount) then
      begin
        Syms[symIdx].PtrElemTk := Syms[varIdx].PtrElemTk;
        Syms[symIdx].PtrElemRec := Syms[varIdx].PtrElemRec;
      end;
    end
    { If it's a field }
    else if ASTKind[node] = AN_FIELD then
    begin
      recId := ResolveNodeRec(ASTLeft[node]);
      if recId <> REC_NONE then
      begin
        Syms[symIdx].PtrElemTk := RecFieldPtrElemTk(recId, GetASTIdentName(node));
        Syms[symIdx].PtrElemRec := RecFieldPtrElemRec(recId, GetASTIdentName(node));
      end;
    end
    { If it's a function call }
    else if ASTKind[node] = AN_CALL then
    begin
      pi := ASTIVal[node];
      if (pi >= 0) and (pi < ProcCount) then
      begin
        Syms[symIdx].PtrElemTk := IntToTypeKind(ProcRetPtrElemTk[pi]);
        Syms[symIdx].PtrElemRec := ProcRetPtrElemRec[pi];
      end;
    end
    { If it's a typecast }
    else if ASTKind[node] = AN_PTR_CAST then
    begin
      if ASTIVal[node] = -2 then
      begin
        Syms[symIdx].PtrElemTk := tyChar;
        Syms[symIdx].PtrElemRec := REC_NONE;
      end
      else if ASTIVal[node] >= 0 then
      begin
        Syms[symIdx].PtrElemTk := IntToTypeKind(AliasElemTk[ASTIVal[node]]);
        Syms[symIdx].PtrElemRec := AliasElemRec[ASTIVal[node]];
      end;
    end
    { If it's an address-of operator }
    else if ASTKind[node] = AN_ADDR then
    begin
      Syms[symIdx].PtrElemTk := IntToTypeKind(ASTTk[ASTLeft[node]]);
      if (Syms[symIdx].PtrElemTk = tyRecord) or (Syms[symIdx].PtrElemTk = tyClass) then
        Syms[symIdx].PtrElemRec := ResolveNodeRec(ASTLeft[node]);
    end;
  end;
end;

procedure AllocateSymOffset(idx: Integer);
var sz, align: Integer; tk: TTypeKind;
begin
  tk := Syms[idx].TypeKind;
  sz := TypeSize(tk);
  if tk = tyString then
  begin
    if Syms[idx].Kind = skGlobal then sz := STRING_CAP + 8
    else sz := LOCAL_STR_CAP + 8;
  end
  else if tk = tyRecord then sz := RecSize(Syms[idx].RecName);
  align := TypeAlign(tk);

  if Syms[idx].Kind = skGlobal then
  begin
    BSSSize := AlignTo(BSSSize, align);
    Syms[idx].Offset := BSSSize;
    Inc(BSSSize, sz);
  end
  else
  begin
    FrameSize := AlignTo(FrameSize + sz, align);
    Syms[idx].Offset := -FrameSize;
  end;
end;

function GetTokenStr(idx: Integer): AnsiString;
var s: AnsiString; i: Integer;
begin
  s := '';
  if (idx >= 0) and (idx < TokCount) then
  begin
    for i := Tokens[idx].SOffset to Tokens[idx].SOffset + Tokens[idx].SLen - 1 do
      AppendChar(s, TokChars[i]);
  end;
  Result := s;
end;

procedure ParseExpr; forward;
procedure PyParseBoolExpr; forward;  { Nil Python boolean layer (defined in pyparser.inc) }

function ConsumeUnitQualifier(var name: AnsiString): Integer;
begin
  Result := -1;
  if (CurTok.Kind = tkIdent) and (TokPos + 1 < TokCount) and
     (Tokens[TokPos].Kind = tkDot) and
     (Tokens[TokPos + 1].Kind = tkIdent) then
  begin
    Result := FindCompiledUnit(name);
    if Result >= 0 then
    begin
      Next;                 { consume unit name }
      Expect(tkDot, '.');
      name := CurTok.SVal;  { leave parser on the member name }
    end;
  end;
end;

function LastDotName(const s: AnsiString): AnsiString;
{ Part of s after the last '.', else s. }
var i, p: Integer;
begin
  p := 0;
  for i := 1 to Length(s) do
    if s[i] = '.' then p := i;
  Result := '';
  for i := p + 1 to Length(s) do
    AppendChar(Result, s[i]);
end;

procedure SkipSelectors;
begin
  while CurTok.Kind in [tkDot, tkLBrack] do
  begin
    if CurTok.Kind = tkDot then
    begin
      Next;
      if CurTok.Kind in [tkEOF, tkSemicolon, tkAssign, tkRBrack, tkRParen] then Error('expected field name');
      Next;
    end
    else
    begin
      Next;
      ParseExpr;
      Expect(tkRBrack, ']');
    end;
  end;
end;

function ParseSetConst: Int64;
var idx: Integer;
begin
  if CurTok.Kind = tkInteger then
  begin
    Result := CurTok.IVal;
    Next;
  end
  else if CurTok.Kind = tkString then
  begin
    if Length(CurTok.SVal) <> 1 then Error('set item must be one character');
    Result := Ord(CurTok.SVal[1]);
    Next;
  end
  else if CurTok.Kind = tkIdent then
  begin
    idx := FindSym(CurTok.SVal);
    if (idx < 0) or (Syms[idx].Kind <> skConst) then Error('set item must be constant');
    Result := Syms[idx].ConstVal;
    Next;
  end
  else Error('expected set item');
end;

procedure ParseSetMembership;
const MAX_SET_JUMPS = 128;
var
  lo, hi: Int64;
  trueJumps: array[0..MAX_SET_JUMPS-1] of Integer;
  trueCount, falseJmp, nextJmp, i: Integer;
  done: Boolean;
begin
  { Left expression is in rax. Keep it in rcx and produce boolean in rax. }
  EmitB($48); EmitB($89); EmitB($C1);       { mov rcx, rax }
  Expect(tkLBrack, '[');
  trueCount := 0;
  if CurTok.Kind <> tkRBrack then
  begin
    done := False;
    while not done do
    begin
      lo := ParseSetConst;
      hi := lo;
      if Eat(tkDotDot) then hi := ParseSetConst;

      if lo = hi then
      begin
        EmitB($48); EmitB($81); EmitB($F9); EmitI32(lo); { cmp rcx, imm32 }
        EmitB($0F); EmitB($84);
        if trueCount >= MAX_SET_JUMPS then Error('set expression too large');
        trueJumps[trueCount] := CodeLen; Inc(trueCount);
        EmitI32(0);
      end
      else
      begin
        EmitB($48); EmitB($81); EmitB($F9); EmitI32(lo); { cmp rcx, lo }
        EmitB($0F); EmitB($8C); nextJmp := CodeLen; EmitI32(0); { jl next }
        EmitB($48); EmitB($81); EmitB($F9); EmitI32(hi); { cmp rcx, hi }
        EmitB($0F); EmitB($8E);
        if trueCount >= MAX_SET_JUMPS then Error('set expression too large');
        trueJumps[trueCount] := CodeLen; Inc(trueCount);
        EmitI32(0);
        Patch32(nextJmp, CodeLen - (nextJmp + 4));
      end;

      if not Eat(tkComma) then done := True;
    end;
  end;
  Expect(tkRBrack, ']');
  MovRaxImm(0);
  EmitB($E9); falseJmp := CodeLen; EmitI32(0);
  for i := 0 to trueCount-1 do
    Patch32(trueJumps[i], CodeLen - (trueJumps[i] + 4));
  MovRaxImm(1);
  Patch32(falseJmp, CodeLen - (falseJmp + 4));
end;

procedure CompileLValueAddressInternal(idx: Integer; var tk: TTypeKind; var recName: Integer); forward;
procedure CompileLValueAddress(const name: AnsiString; var tk: TTypeKind; var recName: Integer); forward;
procedure ParseLValue(const name: AnsiString); forward;
procedure EmitArgvToAddr; forward;

function ParseLValueAST(idx: Integer; identTokIdx: Integer): Integer; forward;
function ParseSetMembershipAST(leftExpr: Integer): Integer; forward;
function ParseSetLiteralAST: Integer; forward;
function ParseVarRecLiteralAST: Integer; forward;
function ParseStatementAST: Integer; forward;
procedure EnableCoroutineRuntime; forward;
function ParseWithStatementAST: Integer; forward;
function ParseAsmStatementAST: Integer; forward;
function ParseBlockAST: Integer; forward;
procedure CompileAST(node: Integer); forward;
function ParseTypeKind: TTypeKind; forward;
procedure ParseSubroutine; forward;
procedure ParseGenericFunctionDef; forward;
procedure ParseOperatorDef; forward;

function GetTokenStrFromRaw(off, len: Integer): AnsiString;
var s: AnsiString; i: Integer;
begin
  s := '';
  for i := 0 to len - 1 do
    AppendChar(s, TokChars[off + i]);
  Result := s;
end;

procedure SpecializeStream(tokStart, count: Integer; const specName, paramName, concreteName: AnsiString; concreteType: TTokenKind);
var
  i, j: Integer;
  subCount: Integer;
  s: AnsiString;
begin
  subCount := 0;
  i := 0;
  while i < count do
  begin
    SpecializeTokens[subCount].Kind := TemplateTokens[tokStart + i].Kind;
    SpecializeTokens[subCount].IVal := TemplateTokens[tokStart + i].IVal;
    SpecializeTokens[subCount].Line := TemplateTokens[tokStart + i].Line;
    SpecializeTokens[subCount].SOffset := TemplateTokens[tokStart + i].SOffset;
    SpecializeTokens[subCount].SLen := TemplateTokens[tokStart + i].SLen;

    if SpecializeTokens[subCount].Kind = tkIdent then
    begin
      s := GetTokenStrFromRaw(SpecializeTokens[subCount].SOffset, SpecializeTokens[subCount].SLen);
      if CaseEqual(s, SpecializeTemplateName) then
      begin
        SpecializeTokens[subCount].SOffset := TokCharLen;
        SpecializeTokens[subCount].SLen := Length(specName);
        j := 1;
        while j <= Length(specName) do
        begin
          TokChars[TokCharLen] := specName[j];
          Inc(TokCharLen);
          Inc(j);
        end;
      end
      else if CaseEqual(s, paramName) then
      begin
        SpecializeTokens[subCount].Kind := concreteType;
        SpecializeTokens[subCount].SOffset := TokCharLen;
        SpecializeTokens[subCount].SLen := Length(concreteName);
        j := 1;
        while j <= Length(concreteName) do
        begin
          TokChars[TokCharLen] := concreteName[j];
          Inc(TokCharLen);
          Inc(j);
        end;
      end;
    end;

    Inc(subCount);
    Inc(i);
  end;

  if TokCount + subCount >= MAX_TOKENS then Error('token buffer overflow');
  i := TokCount - 1;
  while i >= TokPos do
  begin
    Tokens[i + subCount].Kind := Tokens[i].Kind;
    Tokens[i + subCount].IVal := Tokens[i].IVal;
    Tokens[i + subCount].Line := Tokens[i].Line;
    Tokens[i + subCount].SOffset := Tokens[i].SOffset;
    Tokens[i + subCount].SLen := Tokens[i].SLen;
    Dec(i);
  end;
  i := 0;
  while i < subCount do
  begin
    Tokens[TokPos + i].Kind := SpecializeTokens[i].Kind;
    Tokens[TokPos + i].IVal := SpecializeTokens[i].IVal;
    Tokens[TokPos + i].Line := SpecializeTokens[i].Line;
    Tokens[TokPos + i].SOffset := SpecializeTokens[i].SOffset;
    Tokens[TokPos + i].SLen := SpecializeTokens[i].SLen;
    Inc(i);
  end;
  Inc(TokCount, subCount);
end;

procedure ParseGenericTemplate;
var
  templateName, paramName: AnsiString;
  depth, startTok, cur, finalCur: Integer;
begin
  Next; { consume 'generic' }
  if CurTok.Kind <> tkIdent then Error('expected generic class name');
  templateName := CurTok.SVal; Next;

  Expect(tkLt, '<');
  if CurTok.Kind <> tkIdent then Error('expected generic parameter name');
  paramName := CurTok.SVal; Next;
  Expect(tkGt, '>');
  Expect(tkEq, '=');

  if CurTok.Kind <> tkClass then Error('generic templates must be class declarations');

  startTok := TokPos - 1;
  depth := 1;
  cur := TokPos;
  while (cur < TokCount) and (depth > 0) do
  begin
    if Tokens[cur].Kind in [tkClass, tkRecord] then
      Inc(depth)
    else if Tokens[cur].Kind = tkEnd then
      Dec(depth);
    Inc(cur);
  end;

  if (cur < TokCount) and (Tokens[cur].Kind = tkSemicolon) then
    Inc(cur);

  finalCur := cur;  { save before for-loop clobbers 'cur' }

  if TemplateCount >= MAX_TEMPLATES then Error('too many generic templates');
  Templates[TemplateCount].Name := templateName;
  Templates[TemplateCount].Param := paramName;
  Templates[TemplateCount].TokStart := TemplateTokenCount;
  Templates[TemplateCount].TokCount := 0;

  for cur := startTok to finalCur - 1 do
  begin
    if TemplateTokenCount >= MAX_TEMPLATE_TOKENS then
      Error('generic template tokens overflow');
    TemplateTokens[TemplateTokenCount].Kind := Tokens[cur].Kind;
    TemplateTokens[TemplateTokenCount].IVal := Tokens[cur].IVal;
    TemplateTokens[TemplateTokenCount].Line := Tokens[cur].Line;
    TemplateTokens[TemplateTokenCount].SOffset := Tokens[cur].SOffset;
    TemplateTokens[TemplateTokenCount].SLen := Tokens[cur].SLen;
    Inc(TemplateTokenCount);
    Templates[TemplateCount].TokCount := Templates[TemplateCount].TokCount + 1;
  end;

  Inc(TemplateCount);

  TokPos := finalCur;
  Next;
end;

procedure ParseSpecialization(const specName: AnsiString);
var
  templateName, concreteName: AnsiString;
  concreteType: TTokenKind;
  ti, i: Integer;
begin
  Next; { consume 'specialize' }
  if CurTok.Kind <> tkIdent then Error('expected generic template name');
  templateName := CurTok.SVal; Next;

  Expect(tkLt, '<');
  if (CurTok.Kind <> tkIdent) and (CurTok.Kind <> tkInteger_T) and (CurTok.Kind <> tkBoolean_T) and (CurTok.Kind <> tkChar_T) and (CurTok.Kind <> tkString_T) then
    Error('expected concrete type name');
  concreteName := CurTok.SVal;
  concreteType := CurTok.Kind;
  Next;
  Expect(tkGt, '>');
  { Leave CurTok on the trailing ';' (do NOT Eat) so SpecializeStream inserts
    the class-body tokens right after it; the final Next then lands CurTok on
    the inserted 'class', and the caller falls through to the class-binding
    branch (which names the concrete class from the saved tnOff/tnLen). }

  ti := -1;
  for i := 0 to TemplateCount - 1 do
    if CaseEqual(Templates[i].Name, templateName) then
      ti := i;
  if ti < 0 then Error('generic template ' + templateName + ' not found');

  if SpecializationCount >= MAX_SPECIALIZATIONS then Error('too many specializations');
  Specializations[SpecializationCount].Name := specName;
  Specializations[SpecializationCount].TemplateName := templateName;
  Specializations[SpecializationCount].ConcreteType := concreteType;
  Specializations[SpecializationCount].ConcreteName := concreteName;
  Inc(SpecializationCount);

  { Stream the concrete class body inline so the fall-through binds the alias
    name. Methods that were buffered BEFORE this specialization (template in a
    used unit) cannot be streamed here — a `procedure` token would close the
    type section and orphan any following specialization — so defer them to a
    pending queue that ParseTypeSection flushes once the section ends. Methods
    buffered AFTER this point are streamed by BufferGenericMethod, so each
    (method, specialization) pair is materialised exactly once. }
  if GenericMethodCount > 0 then
  begin
    if PendingSpecCount >= MAX_PENDING_SPECS then Error('too many pending specializations');
    PendingSpecTi[PendingSpecCount] := ti;
    PendingSpecIdx[PendingSpecCount] := SpecializationCount - 1;
    Inc(PendingSpecCount);
  end;

  SpecializeTemplateName := Templates[ti].Name;
  SpecializeStream(Templates[ti].TokStart, Templates[ti].TokCount, specName, Templates[ti].Param, concreteName, concreteType);
  Next;
end;

{ Materialise the methods of every class specialization buffered during the
  type section just parsed. Called once the section's token loop exits, so the
  streamed `procedure`/`function` bodies land after the whole `type` block and
  are parsed as ordinary top-level subroutines. Inserting at TokPos prepends
  before the section-terminating token, which was un-read by the caller. }
procedure FlushPendingClassSpecializations;
var p, gm, ti, si: Integer;
begin
  for p := 0 to PendingSpecCount - 1 do
  begin
    ti := PendingSpecTi[p];
    si := PendingSpecIdx[p];
    SpecializeTemplateName := Templates[ti].Name;
    for gm := 0 to GenericMethodCount - 1 do
      if GenericMethods[gm].TemplateIdx = ti then
        SpecializeStream(GenericMethods[gm].TokStart, GenericMethods[gm].TokCount,
          Specializations[si].Name, Templates[ti].Param,
          Specializations[si].ConcreteName, Specializations[si].ConcreteType);
  end;
  PendingSpecCount := 0;
end;

procedure BufferGenericMethod(ti, startTokIdx: Integer);
var
  depth, cur, finalCur: Integer;
  si, mStart, mCount: Integer;
begin
  depth := 0;
  cur := startTokIdx;
  while (cur < TokCount) and (Tokens[cur].Kind <> tkBegin) do
    Inc(cur);
  if cur >= TokCount then Error('expected begin in generic method');

  depth := 1;
  Inc(cur);
  while (cur < TokCount) and (depth > 0) do
  begin
    if Tokens[cur].Kind in [tkBegin, tkCase] then
      Inc(depth)
    else if Tokens[cur].Kind = tkEnd then
      Dec(depth);
    Inc(cur);
  end;

  if (cur < TokCount) and (Tokens[cur].Kind = tkSemicolon) then
    Inc(cur);

  finalCur := cur;  { save before for-loop clobbers 'cur' }

  mStart := TemplateTokenCount;
  mCount := 0;
  for cur := startTokIdx to finalCur - 1 do
  begin
    if TemplateTokenCount >= MAX_TEMPLATE_TOKENS then
      Error('generic template tokens overflow');
    TemplateTokens[TemplateTokenCount].Kind := Tokens[cur].Kind;
    TemplateTokens[TemplateTokenCount].IVal := Tokens[cur].IVal;
    TemplateTokens[TemplateTokenCount].Line := Tokens[cur].Line;
    TemplateTokens[TemplateTokenCount].SOffset := Tokens[cur].SOffset;
    TemplateTokens[TemplateTokenCount].SLen := Tokens[cur].SLen;
    Inc(TemplateTokenCount);
    mCount := mCount + 1;
  end;

  { Remember the buffered method so a later specialization (parsed after this
    method, e.g. template in a unit + `specialize` in the program) can still
    materialise it. See ParseSpecialization. }
  if GenericMethodCount >= MAX_GENERIC_METHODS then Error('too many generic methods');
  GenericMethods[GenericMethodCount].TemplateIdx := ti;
  GenericMethods[GenericMethodCount].TokStart := mStart;
  GenericMethods[GenericMethodCount].TokCount := mCount;
  Inc(GenericMethodCount);

  { Insert specializations AFTER the template method body, not at the dot
    position. Only specializations already registered are streamed here; ones
    declared later stream this method from ParseSpecialization, so each
    (method, specialization) pair is materialised exactly once. }
  TokPos := finalCur;
  for si := 0 to SpecializationCount - 1 do
  begin
    if CaseEqual(Specializations[si].TemplateName, Templates[ti].Name) then
    begin
      SpecializeTemplateName := Templates[ti].Name;
      SpecializeStream(mStart, mCount, Specializations[si].Name, Templates[ti].Param, Specializations[si].ConcreteName, Specializations[si].ConcreteType);
    end;
  end;

  { TokPos = finalCur (InsertTokens doesn't change it); parser reads from first specialization }
  Next;
end;

function FindGenericFunc(const name: AnsiString): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to GenericFuncCount - 1 do
    if CaseEqual(GenericFuncs[i].Name, name) then begin Result := i; Exit; end;
end;

{ Parses: generic function Max<T>(A, B: T): T; begin...end;
  Called when CurTok = tkIdent('generic') }
procedure ParseGenericFunctionDef;
var isFunc: Boolean; funcName, paramName: AnsiString;
    gfi, j, cur, finalCur, depth: Integer;
begin
  Next; { consume 'generic' }
  if (CurTok.Kind <> tkFunction) and (CurTok.Kind <> tkProcedure) then
    Error('expected function or procedure after generic');
  isFunc := CurTok.Kind = tkFunction;
  Next; { consume function/procedure }

  if CurTok.Kind <> tkIdent then Error('expected generic function name');
  funcName := CurTok.SVal; Next;

  Expect(tkLt, '<');
  if CurTok.Kind <> tkIdent then Error('expected generic type parameter');
  paramName := CurTok.SVal; Next;
  Expect(tkGt, '>');
  { CurTok = '(' of param list, or ';' / ':' if no params }

  if GenericFuncCount >= MAX_GENERIC_FUNCS then Error('too many generic functions');
  gfi := GenericFuncCount;
  GenericFuncs[gfi].Name     := funcName;
  GenericFuncs[gfi].Param    := paramName;
  GenericFuncs[gfi].IsFunc   := isFunc;
  GenericFuncs[gfi].TokStart := TemplateTokenCount;
  GenericFuncs[gfi].TokCount := 0;

  { Prepend synthetic 'function/procedure funcName' tokens into template buffer }
  TemplateTokens[TemplateTokenCount].IVal := 0;
  TemplateTokens[TemplateTokenCount].Line := 0;
  if isFunc then TemplateTokens[TemplateTokenCount].Kind := tkFunction
  else TemplateTokens[TemplateTokenCount].Kind := tkProcedure;
  TemplateTokens[TemplateTokenCount].SOffset := TokCharLen;
  TemplateTokens[TemplateTokenCount].SLen := 0;
  Inc(TemplateTokenCount);
  GenericFuncs[gfi].TokCount := GenericFuncs[gfi].TokCount + 1;

  TemplateTokens[TemplateTokenCount].Kind := tkIdent;
  TemplateTokens[TemplateTokenCount].IVal := 0;
  TemplateTokens[TemplateTokenCount].Line := 0;
  TemplateTokens[TemplateTokenCount].SOffset := TokCharLen;
  TemplateTokens[TemplateTokenCount].SLen := Length(funcName);
  for j := 1 to Length(funcName) do
  begin
    TokChars[TokCharLen] := funcName[j];
    Inc(TokCharLen);
  end;
  Inc(TemplateTokenCount);
  GenericFuncs[gfi].TokCount := GenericFuncs[gfi].TokCount + 1;

  { Buffer remaining tokens: (A,B:T):T; begin...end; }
  { TokPos-1 = index of current token '(' in Tokens array }
  cur := TokPos - 1;
  while (cur < TokCount) and (Tokens[cur].Kind <> tkBegin) do Inc(cur);
  depth := 1; Inc(cur);
  while (cur < TokCount) and (depth > 0) do
  begin
    if Tokens[cur].Kind in [tkBegin, tkCase] then Inc(depth)
    else if Tokens[cur].Kind = tkEnd then Dec(depth);
    Inc(cur);
  end;
  if (cur < TokCount) and (Tokens[cur].Kind = tkSemicolon) then Inc(cur);
  finalCur := cur;

  for cur := TokPos - 1 to finalCur - 1 do
  begin
    if TemplateTokenCount >= MAX_TEMPLATE_TOKENS then Error('generic template tokens overflow');
    TemplateTokens[TemplateTokenCount].Kind := Tokens[cur].Kind;
    TemplateTokens[TemplateTokenCount].IVal := Tokens[cur].IVal;
    TemplateTokens[TemplateTokenCount].Line := Tokens[cur].Line;
    TemplateTokens[TemplateTokenCount].SOffset := Tokens[cur].SOffset;
    TemplateTokens[TemplateTokenCount].SLen := Tokens[cur].SLen;
    Inc(TemplateTokenCount);
    GenericFuncs[gfi].TokCount := GenericFuncs[gfi].TokCount + 1;
  end;

  Inc(GenericFuncCount);
  TokPos := finalCur;
  Next;
end;

{ Parses: specialize Max<Integer> as MaxInt;
  Called when CurTok = tkIdent('specialize') at top level }
procedure ParseTopLevelSpecialize;
var templateName, concreteName, specName: AnsiString;
    concreteKind: TTokenKind; gfi, i: Integer;
begin
  Next; { consume 'specialize' }
  if CurTok.Kind <> tkIdent then Error('expected generic function name after specialize');
  templateName := CurTok.SVal; Next;

  Expect(tkLt, '<');
  if (CurTok.Kind = tkIdent) or (CurTok.Kind = tkInteger_T) or
     (CurTok.Kind = tkBoolean_T) or (CurTok.Kind = tkChar_T) or
     (CurTok.Kind = tkString_T) then
  begin
    concreteName := CurTok.SVal;
    concreteKind := CurTok.Kind;
    Next;
  end
  else
    Error('expected concrete type in specialize');
  Expect(tkGt, '>');

  { Optional 'as Name' }
  if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'as') then
  begin
    Next;
    if CurTok.Kind <> tkIdent then Error('expected name after as');
    specName := CurTok.SVal; Next;
  end
  else
  begin
    { Auto-generate: Max_Integer }
    specName := templateName;
    AppendChar(specName, '_');
    i := 1;
    while i <= Length(concreteName) do begin AppendChar(specName, concreteName[i]); Inc(i); end;
  end;
  { CurTok = ';' — do NOT Eat here. Insert at TokPos (after ';') so that
    after ParseSubroutine finishes its own 'end;', CurTok lands on the next
    top-level token (next specialize/begin/etc.) rather than skipping it. }

  gfi := FindGenericFunc(templateName);
  if gfi < 0 then Error('generic function ' + templateName + ' not found');

  SpecializeTemplateName := GenericFuncs[gfi].Name;
  SpecializeStream(GenericFuncs[gfi].TokStart, GenericFuncs[gfi].TokCount,
    specName, GenericFuncs[gfi].Param, concreteName, concreteKind);
  Next;
  ParseSubroutine;
end;

{ Parses: operator < (a, b: TMyType): Boolean; begin...end;
  Called when CurTok = tkIdent('operator') at top level }
procedure ParseOperatorDef;
var
  opKind: TTokenKind;
  synName: AnsiString;
  typeName: AnsiString;
  recId: Integer;
  opTypeKind: Integer;
  ci: Integer;
  depth, i, j: Integer;
  isFunc, foundClose: Boolean;
  nameOff, nameLen: Integer;
  procIdx: Integer;
begin
  Next; { consume 'operator' }
  opKind := CurTok.Kind;
  if not (opKind in [tkPlus, tkMinus, tkStar, tkDiv, tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe]) then
    Error('expected operator symbol after operator keyword');
  { Stay on operator token — do NOT call Next. TokPos → '(' }

  { Lookahead: find first ':' inside '()' to get operand type name }
  typeName := '';
  depth := 0;
  i := TokPos; { Tokens[TokPos] = '(' }
  while (i < TokCount) and (typeName = '') do
  begin
    if Tokens[i].Kind = tkLParen then Inc(depth)
    else if Tokens[i].Kind = tkRParen then Dec(depth)
    else if (Tokens[i].Kind = tkColon) and (depth = 1) then
    begin
      Inc(i);
      if i < TokCount then
      begin
        if Tokens[i].Kind = tkIdent then
          typeName := GetTokenStrFromRaw(Tokens[i].SOffset, Tokens[i].SLen)
        else if Tokens[i].Kind = tkInteger_T then typeName := 'Integer'
        else if Tokens[i].Kind = tkBoolean_T then typeName := 'Boolean'
        else if Tokens[i].Kind = tkChar_T then typeName := 'Char'
        else if Tokens[i].Kind = tkString_T then typeName := 'String';
      end;
      i := TokCount; { break }
    end;
    Inc(i);
  end;
  if typeName = '' then Error('operator: cannot determine operand type');

  { Resolve recId for the operand type. Record the operand's real type kind so
    the registration tag matches how the use site looks it up (a record operand
    carries ASTTk=tyRecord, a class operand tyClass). Registering everything as
    tyClass made FindOpOverload miss for record operands, so `a + b` on records
    silently fell through to a scalar binop. }
  recId := IsRecordType(typeName);
  if recId = REC_NONE then
  begin
    ci := FindUClass(typeName);
    if ci < 0 then Error('operator overloading: ' + typeName + ' is not a record or class type');
    recId := REC_UCLASS_BASE + ci;
    opTypeKind := Ord(tyClass);
  end
  else
    opTypeKind := Ord(tyRecord);

  { Determine function vs procedure: find matching ')' then check for ':' }
  depth := 0;
  i := TokPos;
  foundClose := False;
  while (i < TokCount) and not foundClose do
  begin
    if Tokens[i].Kind = tkLParen then Inc(depth)
    else if Tokens[i].Kind = tkRParen then
    begin
      Dec(depth);
      if depth = 0 then begin Inc(i); foundClose := True; end;
    end;
    if not foundClose then Inc(i);
  end;
  isFunc := (i < TokCount) and (Tokens[i].Kind = tkColon);

  { Synthesize unique proc name __op__NN }
  synName := '__op__';
  AppendChar(synName, Chr(Ord('0') + OvrlCount div 10));
  AppendChar(synName, Chr(Ord('0') + OvrlCount mod 10));

  { Insert 'function/procedure synName' at TokPos (before '(') }
  if TokCount + 2 >= MAX_TOKENS then Error('token buffer overflow in operator def');
  for j := TokCount - 1 downto TokPos do
  begin
    Tokens[j + 2].Kind := Tokens[j].Kind;
    Tokens[j + 2].IVal := Tokens[j].IVal;
    Tokens[j + 2].Line := Tokens[j].Line;
    Tokens[j + 2].SOffset := Tokens[j].SOffset;
    Tokens[j + 2].SLen := Tokens[j].SLen;
  end;
  Inc(TokCount, 2);

  if isFunc then Tokens[TokPos].Kind := tkFunction
  else Tokens[TokPos].Kind := tkProcedure;
  Tokens[TokPos].IVal := 0; Tokens[TokPos].Line := 0;
  Tokens[TokPos].SOffset := 0; Tokens[TokPos].SLen := 0;

  nameOff := TokCharLen;
  nameLen := Length(synName);
  for j := 1 to nameLen do
  begin
    TokChars[TokCharLen] := synName[j];
    Inc(TokCharLen);
  end;
  Tokens[TokPos+1].Kind := tkIdent;
  Tokens[TokPos+1].IVal := 0; Tokens[TokPos+1].Line := 0;
  Tokens[TokPos+1].SOffset := nameOff;
  Tokens[TokPos+1].SLen := nameLen;

  { Advance into the injected 'function/procedure' token }
  Next;
  ParseSubroutine;

  { After ParseSubroutine, the proc is registered — look it up by synName }
  procIdx := FindProc(synName);
  if procIdx < 0 then Error('operator: internal error, proc not found after parse');
  RegisterOpOverload(Ord(opKind), opTypeKind, recId, procIdx);
end;

{ Linear (row-major) index of an N-D fixed array element, built from AST nodes so
  it feeds the ordinary 1-D AN_INDEX (no codegen change). Reads the dims from
  NDInfoLo/Span and the parsed index exprs from NDIdxNode; nd dimensions.
  Horner form: acc = (i0-lo0); acc = acc*span_d + (i_d - lo_d) for d = 1..nd-1. }
function BuildFlatNDIndex(nd: Integer): Integer;
var d, loLit, spanLit, diff, scaled, acc: Integer;
begin
  loLit := AllocNode(AN_INT_LIT); ASTIVal[loLit] := NDInfoLo[0]; ASTTk[loLit] := Ord(tyInteger);
  acc := AllocNode(AN_BINOP); ASTIVal[acc] := Ord(tkMinus);
  ASTLeft[acc] := NDIdxNode[0]; ASTRight[acc] := loLit; ASTTk[acc] := Ord(tyInteger);
  for d := 1 to nd - 1 do
  begin
    spanLit := AllocNode(AN_INT_LIT); ASTIVal[spanLit] := NDInfoSpan[d]; ASTTk[spanLit] := Ord(tyInteger);
    scaled := AllocNode(AN_BINOP); ASTIVal[scaled] := Ord(tkStar);   { acc * span_d }
    ASTLeft[scaled] := acc; ASTRight[scaled] := spanLit; ASTTk[scaled] := Ord(tyInteger);
    loLit := AllocNode(AN_INT_LIT); ASTIVal[loLit] := NDInfoLo[d]; ASTTk[loLit] := Ord(tyInteger);
    diff := AllocNode(AN_BINOP); ASTIVal[diff] := Ord(tkMinus);    { i_d - lo_d }
    ASTLeft[diff] := NDIdxNode[d]; ASTRight[diff] := loLit; ASTTk[diff] := Ord(tyInteger);
    acc := AllocNode(AN_BINOP); ASTIVal[acc] := Ord(tkPlus);       { scaled + diff }
    ASTLeft[acc] := scaled; ASTRight[acc] := diff; ASTTk[acc] := Ord(tyInteger);
  end;
  Result := acc;
end;

{ If `node` is an N-D fixed array reference (a SymArrNDims ident or an
  UFldArrNDims record field), fill NDInfo* and return True. Lets m[..] and
  r.m[..] share one path. }
function NodeArrNDInfo(node: Integer): Boolean;
var baseRec, fIdx, sym, d, base: Integer; fname: AnsiString;
begin
  Result := False;
  if (ASTKind[node] = AN_IDENT) and (ASTIVal[node] >= 0) and (SymArrNDims[ASTIVal[node]] >= 2) then
  begin
    sym := ASTIVal[node];
    NDInfoNDims := SymArrNDims[sym];
    base := sym * MAX_ARR_DIMS;
    for d := 0 to NDInfoNDims - 1 do
    begin NDInfoLo[d] := SymArrDimLo[base + d]; NDInfoSpan[d] := SymArrDimSpan[base + d]; end;
    Result := True;
  end
  else if ASTKind[node] = AN_FIELD then
  begin
    baseRec := ResolveNodeRec(ASTLeft[node]);
    if baseRec >= REC_UCLASS_BASE then
    begin
      fname := GetASTIdentName(node);
      fIdx := FindUField(baseRec - REC_UCLASS_BASE, fname);
      if (fIdx >= 0) and (UFldArrNDims[fIdx] >= 2) then
      begin
        NDInfoNDims := UFldArrNDims[fIdx];
        base := fIdx * MAX_ARR_DIMS;
        for d := 0 to NDInfoNDims - 1 do
        begin NDInfoLo[d] := UFldArrDimLo[base + d]; NDInfoSpan[d] := UFldArrDimSpan[base + d]; end;
        Result := True;
      end;
    end;
  end;
end;

function ParseLValueAST(idx: Integer; identTokIdx: Integer): Integer;
var
  node, indexNode, fieldNode, prevTok, recName, i: Integer;
  baseNode, baseRec, fIdx, aliasIdx, firstIdxNode: Integer;
  isND: Boolean; nIdx: Integer; alreadyResolved: Boolean;
  tk: TTypeKind;
  fieldName: AnsiString;
  mci, mmi, mpi, mcallNode, mselfArg, mlastArg, margSeq, margIdx, mexprNode, mai, pri, ci: Integer;
  methName: AnsiString;
  isAssign: Boolean;
  selfClassCi, selfIdx, fldIdx, selfNode: Integer;
  w, withNode, recId: Integer;
  propFOff, propFLen: Integer;
  withResolved: Boolean;
begin
  prevTok := identTokIdx;
  if DebugTrace then writeln('ParseLValueAST: idx = ', idx, ' prevTok = ', prevTok, ' TokenStr = "', GetTokenStr(prevTok), '" CurTok.Line = ', CurTok.Line, ' TokPos = ', TokPos);

  fieldName := GetTokenStr(prevTok);
  withResolved := False;

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

      if fldIdx >= 0 then
    begin
      selfIdx := Procs[CurProc].Params[0].SymIdx;
      selfNode := AllocNode(AN_IDENT);
      ASTIVal[selfNode] := selfIdx;
      ASTTk[selfNode] := Ord(tyClass);

      fieldNode := AllocNode(AN_FIELD);
      ASTLeft[fieldNode] := selfNode;
      ASTSOffset[fieldNode] := Tokens[prevTok].SOffset;
      ASTSLen[fieldNode] := Tokens[prevTok].SLen;

      tk := IntToTypeKind(UFldTk[fldIdx]);
      recName := UFldRec_[fldIdx];
      ASTTk[fieldNode] := Ord(tk);

      node := fieldNode;
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
        if ci >= 0 then
        begin
          if CurTok.Kind <> tkDot then
          begin
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
          if CurTok.Kind <> tkIdent then Error('expected class method name');
          fieldName := CurTok.SVal;
          Next;

          mmi := FindUMeth(ci, fieldName);
          if mmi < 0 then Error('class method not found: ' + fieldName);
          mpi := UMthProc_[mmi];

          if not UMthIsStatic[mmi] then
            Error('cannot call non-static method on class type directly');

          mcallNode := AllocNode(AN_CALL);
          ASTIVal[mcallNode] := mpi;
          ASTTk[mcallNode] := Ord(Procs[mpi].RetType);
          mlastArg := -1;

          if CurTok.Kind = tkLParen then
          begin
            Next;
            mai := 0;
            while mai <= Procs[mpi].ParamCount-1 do
            begin
              if Procs[mpi].Params[mai].IsRef or Procs[mpi].Params[mai].IsArray then
              begin
                if CurTok.Kind <> tkIdent then Error('expected variable');
                margIdx := FindSym(CurTok.SVal); Next;
                mexprNode := ParseLValueAST(margIdx, TokPos - 2);
              end
              else
              begin
                ParseExpr; mexprNode := CurASTNode;
              end;
              margSeq := AllocNode(AN_ARG); ASTLeft[margSeq] := mexprNode;
              if mlastArg = -1 then
                ASTLeft[mcallNode] := margSeq
              else
                ASTRight[mlastArg] := margSeq;
              mlastArg := margSeq;
              if mai < Procs[mpi].ParamCount-1 then Expect(tkComma, ',');
              Inc(mai);
            end;
            Expect(tkRParen, ')');
          end;

          Result := mcallNode;
          Exit;
        end
        else
        begin
          ErrorIdent := fieldName;
          Error('undefined variable');
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
    ASTTk[node] := Ord(tk);
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
        if ASTKind[node] = AN_IDENT then
        begin
          tk := Syms[ASTIVal[node]].PtrElemTk;
          recName := Syms[ASTIVal[node]].PtrElemRec;
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
      else
        Error('dereferenced value is not a pointer');
      ASTTk[indexNode] := Ord(tk);
      node := indexNode;
    end
    else if CurTok.Kind = tkLBrack then
    begin
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
        ASTTk[indexNode] := Ord(tk);
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
          ASTTk[indexNode] := Ord(tk);
          node := indexNode;
        end;
        Expect(tkRBrack, ']');
        alreadyResolved := True;
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
      else if (tk = tyString) or (tk = tyAnsiString) then
        tk := tyChar
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
      ASTTk[indexNode] := Ord(tk);
      node := indexNode;
    end
    else
    begin
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
      { Check if it is a property on a class }
      mci := -1; pri := -1;
      if recName >= REC_UCLASS_BASE then
      begin
        mci := recName - REC_UCLASS_BASE;
        pri := FindUProp(mci, fieldName);
      end;

      if pri >= 0 then
      begin
        isAssign := (CurTok.Kind = tkAssign) or ((TokPos < TokCount) and (Tokens[TokPos].Kind = tkAssign));
        if isAssign then
        begin
          if UPropWriteFLen[pri] > 0 then
          begin
            fieldName := '';
            for i := 0 to UPropWriteFLen[pri] - 1 do
              AppendChar(fieldName, TokChars[UPropWriteFOff[pri] + i]);
            propFOff := UPropWriteFOff[pri];
            propFLen := UPropWriteFLen[pri];
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
            ASTLeft[margSeq] := CurASTNode;
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

            node := mcallNode;
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
        mmi := FindUMeth(mci, fieldName);
      end;
      if mmi >= 0 then
      begin
        mpi := UMthProc_[mmi];
        Next; { consume method name }
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
            while mai <= Procs[mpi].ParamCount-1 do
            begin
              if Procs[mpi].Params[mai].IsRef or Procs[mpi].Params[mai].IsArray then
              begin
                if CurTok.Kind <> tkIdent then Error('expected variable');
                margIdx := FindSym(CurTok.SVal); Next;
                mexprNode := ParseLValueAST(margIdx, TokPos - 2);
              end
              else begin ParseExpr; mexprNode := CurASTNode; end;
              margSeq := AllocNode(AN_ARG); ASTLeft[margSeq] := mexprNode;
              if mlastArg = -1 then ASTLeft[mcallNode] := margSeq
              else ASTRight[mlastArg] := margSeq;
              mlastArg := margSeq;
              if mai < Procs[mpi].ParamCount-1 then Expect(tkComma, ',');
              Inc(mai);
            end;
            Expect(tkRParen, ')');
          end;
          node := mcallNode;
          Result := node; Exit;
        end;
        if UMthIsStatic[mmi] then
        begin
          mcallNode := AllocNode(AN_CALL);
          ASTIVal[mcallNode] := mpi;
          ASTTk[mcallNode] := Ord(Procs[mpi].RetType);
          mlastArg := -1;
          if CurTok.Kind = tkLParen then
          begin
            Next;
            mai := 0;
            while mai <= Procs[mpi].ParamCount-1 do
            begin
              if Procs[mpi].Params[mai].IsRef or Procs[mpi].Params[mai].IsArray then
              begin
                if CurTok.Kind <> tkIdent then Error('expected variable');
                margIdx := FindSym(CurTok.SVal); Next;
                mexprNode := ParseLValueAST(margIdx, TokPos - 2);
              end
              else
              begin
                ParseExpr; mexprNode := CurASTNode;
              end;
              margSeq := AllocNode(AN_ARG); ASTLeft[margSeq] := mexprNode;
              if mlastArg = -1 then
                ASTLeft[mcallNode] := margSeq
              else
                ASTRight[mlastArg] := margSeq;
              mlastArg := margSeq;
              if mai < Procs[mpi].ParamCount-1 then Expect(tkComma, ',');
              Inc(mai);
            end;
            Expect(tkRParen, ')');
          end;
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
            while mai <= Procs[mpi].ParamCount-1 do
            begin
              if Procs[mpi].Params[mai].IsRef or Procs[mpi].Params[mai].IsArray then
              begin
                if CurTok.Kind <> tkIdent then Error('expected variable');
                margIdx := FindSym(CurTok.SVal); Next;
                mexprNode := ParseLValueAST(margIdx, TokPos - 2);
              end
              else
              begin
                ParseExpr; mexprNode := CurASTNode;
              end;
              margSeq := AllocNode(AN_ARG); ASTLeft[margSeq] := mexprNode;
              ASTRight[mlastArg] := margSeq; mlastArg := margSeq;
              if mai < Procs[mpi].ParamCount-1 then Expect(tkComma, ',');
              Inc(mai);
            end;
            Expect(tkRParen, ')');
          end;
          node := mcallNode;
          Result := node; Exit;
        end;
      end;
      fieldNode := AllocNode(AN_FIELD);
      ASTLeft[fieldNode] := node;
      ASTSOffset[fieldNode] := propFOff;
      ASTSLen[fieldNode] := propFLen;
      tk := RecFieldType(recName, fieldName);
      recName := RecFieldRecId(recName, fieldName);
      ASTTk[fieldNode] := Ord(tk);
      Next;
      node := fieldNode;
    end;
  end;
  Result := node;
end;

function ParseSetMembershipAST(leftExpr: Integer): Integer;
var node, argNode, lastArg, loVal, hiVal, itemNode: Integer; done: Boolean;
begin
  node := AllocNode(AN_CALL);
  ASTIVal[node] := -SPECIAL_IN;

  argNode := AllocNode(AN_ARG);
  ASTLeft[argNode] := leftExpr;
  ASTLeft[node] := argNode;
  lastArg := argNode;

  Expect(tkLBrack, '[');
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
  Result := node;
end;

function ParseSetLiteralAST: Integer;
var node, argNode, lastArg, loVal, hiVal, itemNode: Integer; done: Boolean;
begin
  node := AllocNode(AN_SET_LIT);
  ASTTk[node] := Ord(tySet);
  ASTLeft[node] := -1;
  lastArg := -1;

  Expect(tkLBrack, '[');
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

function ParamIsVarRecArray(pi, argNo: Integer): Boolean;
{ True when proc pi's parameter argNo is an `array of const` (open array whose
  element record is TVarRec) — the signal to parse a `[...]` argument as a
  TVarRec element vector rather than a set literal. }
begin
  { Use the durable Proc/Param signature, not the param's frame symbol — that
    symbol slot is reused once the callee's scope closes, so by the time a later
    routine's call is parsed it no longer holds the param. An open array whose
    element type is a record is, in this dialect, only ever `array of const`. }
  Result := (pi >= 0) and (TVarRecId <> REC_NONE) and
            (argNo >= 0) and (argNo < Procs[pi].ParamCount) and
            Procs[pi].Params[argNo].IsArray and
            (Procs[pi].Params[argNo].TypeKind = tyRecord);
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
       (Syms[idx].IsRef or Syms[idx].IsArray or (Syms[idx].TypeKind = tyString)) then
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
    ErrorIdent := name;
    Error('undefined variable');
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
    ErrorIdent := name;
    Error('undefined variable');
  end;

  Next; { consume identifier }
  isComplex := CurTok.Kind in [tkLBrack, tkDot];

  if not isComplex then
  begin
    Expect(tkAssign, ':=');
    if Syms[idx].TypeKind = tyString then
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
        if (si2 >= 0) and (Syms[si2].TypeKind = tyString) then
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

procedure ParseCallArg(pi, argNo: Integer);
var idx: Integer; tk: TTypeKind; recName: Integer;
begin
  if Procs[pi].Params[argNo].IsRef or Procs[pi].Params[argNo].IsArray then
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
  if parentCi < 0 then Error('inherited call has no parent class');

  Next; { consume inherited }
  if CurTok.Kind = tkIdent then
  begin
    name := CurTok.SVal;
    Next;
  end
  else
    name := LastDotName(Procs[CurProc].Name);

  mmi := FindUMeth(parentCi, name);
  if mmi < 0 then Error('inherited method not found: ' + name);
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
  Result := node;
end;

{ Apply a chain of ^, [i], and .field to a function-call result that is a typed
  pointer, using the callee's recorded return element type (ProcRetPtrElemTk/Rec).
  Lets `f()^`, `f()^.field`, and `f()[i]` resolve without a typed intermediate
  variable. Sets CurASTNode and LastExprTk; consumes nothing when the result is
  not a typed pointer. }
procedure ApplyCallResultPtrSuffix(node, pi: Integer);
var tk: TTypeKind; elemTk, elemRec, recId, sub, prevTok: Integer; fieldName: AnsiString;
begin
  tk := Procs[pi].RetType;
  recId := REC_NONE;
  elemTk := ProcRetPtrElemTk[pi];
  elemRec := ProcRetPtrElemRec[pi];
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
        ASTTk[sub] := Ord(tk);
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
        ASTTk[sub] := Ord(tk);
        node := sub;
      end
      else { tkDot — field of the pointed-at record }
      begin
        Next;
        if CurTok.Kind in [tkEOF, tkSemicolon, tkAssign, tkRBrack, tkRParen] then
          Error('expected field name after .');
        prevTok := TokPos - 1;
        fieldName := GetTokenStr(prevTok);
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
  end;
  CurASTNode := node;
  LastExprTk := tk;
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
  Result := node;
end;

procedure ParseFactor;
var name: AnsiString; recName: Integer; idx, pi, i, node, left, prevTok, valNode: Integer; tk: TTypeKind; op, argSeq, argSeq2, argSeq3, lastArg, argIdx, exprNode, szArg: Integer;
    nArgs, argsHead, currArg: Integer; argTypes: array[0..15] of TTypeKind;
    ci, mmi, mpi, mcallNode, mlastArg, smSelfIdx, smselfArg: Integer;
    aliasIdx, fieldNode, indexNode, baseNode, baseRec, fIdx, mci, margSeq, margIdx, mexprNode, mai, pri, qUnit: Integer;
    fieldName, methName: AnsiString; isAssign: Boolean; castTk: TTypeKind;
    liftedVar, identNode, addrNode: Integer;
    helperPi, wrapperArg, wrapperCall, sci: Integer;
    isLiftedCall, isCStringCall: Boolean;
begin
  LastExprTk := tyInteger;
  case CurTok.Kind of
    tkInteger:
    begin
      node := AllocNode(AN_INT_LIT); ASTIVal[node] := CurTok.IVal;
      { A literal that does not fit a signed 32-bit Integer is an Int64; the
        i386 backend keys its 64-bit codegen off this type. }
      if (CurTok.IVal > 2147483647) or (CurTok.IVal < -2147483648) then
        ASTTk[node] := Ord(tyInt64)
      else
        ASTTk[node] := Ord(tyInteger);
      CurASTNode := node; Next;
    end;
    tkLBrack:
    begin
      CurASTNode := ParseSetLiteralAST;
      LastExprTk := tySet;
    end;
    tkNil:
    begin
      node := AllocNode(AN_INT_LIT); ASTIVal[node] := 0; ASTTk[node] := Ord(tyPointer); CurASTNode := node; Next; LastExprTk := tyPointer;
    end;
    tkDefault:
    begin
      node := AllocNode(AN_DEFAULT);
      ASTTk[node] := Ord(tyUnknown);
      CurASTNode := node;
      LastExprTk := tyUnknown;
      Next;
    end;
    tkAt:
    begin
      Next;
      if CurTok.Kind <> tkIdent then Error('expected identifier after @');
      name := CurTok.SVal;
      idx := FindSym(name);
      { @obj.method yields a TMethod (Code+Data): obj is a class instance var,
        method one of its methods. Code = method proc address,
        Data = the instance pointer. Only valid as the RHS of an assignment to
        a TMethod-shaped target (handled in AN_ASSIGN). }
      if (idx >= 0) and (Syms[idx].RecName >= REC_UCLASS_BASE) and
         (not UClsIsRecord[Syms[idx].RecName - REC_UCLASS_BASE]) and
         (TokPos < TokCount) and (Tokens[TokPos].Kind = tkDot) then
      begin
        ci := Syms[idx].RecName - REC_UCLASS_BASE;
        Next;            { consume obj name (CurTok = '.') }
        Next;            { consume '.' (CurTok = method name) }
        if CurTok.Kind <> tkIdent then Error('expected method name after @obj.');
        mmi := FindUMeth(ci, CurTok.SVal);
        if mmi < 0 then Error('@obj.method: unknown method');
        valNode := AllocNode(AN_IDENT);   { object value = the instance pointer }
        ASTIVal[valNode] := idx;
        ASTTk[valNode] := Ord(tyClass);
        node := AllocNode(AN_METHODREF);
        ASTIVal[node] := UMthProc_[mmi];
        ASTLeft[node] := valNode;
        ASTTk[node] := Ord(tyRecord);
        Next;            { consume method name }
        CurASTNode := node;
        LastExprTk := tyRecord;
      end
      { @proc: not a variable but a known routine → absolute code address }
      else if (idx < 0) and (FindProc(name) >= 0) then
      begin
        node := AllocNode(AN_PROCADDR);
        ASTIVal[node] := FindProc(name);
        ASTTk[node] := Ord(tyPointer);
        Next;
        CurASTNode := node;
        LastExprTk := tyPointer;
      end
      else
      begin
        Next;
        valNode := ParseLValueAST(idx, TokPos - 2);
        node := AllocNode(AN_ADDR);
        ASTLeft[node] := valNode;
        ASTTk[node] := Ord(tyPointer);
        CurASTNode := node;
        LastExprTk := tyPointer;
      end;
    end;
    tkFloat:
    begin
      node := AllocNode(AN_FLOAT_LIT); ASTIVal[node] := CurTok.IVal; ASTTk[node] := Ord(tyDouble);
      CurASTNode := node; LastExprTk := tyDouble; Next;
    end;
    tkTrue:
    begin
      node := AllocNode(AN_BOOL_LIT); ASTIVal[node] := 1; ASTTk[node] := Ord(tyBoolean); CurASTNode := node; Next; LastExprTk := tyBoolean;
    end;
    tkFalse:
    begin
      node := AllocNode(AN_BOOL_LIT); ASTIVal[node] := 0; ASTTk[node] := Ord(tyBoolean); CurASTNode := node; Next; LastExprTk := tyBoolean;
    end;
    tkString:
    begin
      prevTok := TokPos - 1;
      if Length(CurTok.SVal) = 1 then
      begin
        node := AllocNode(AN_INT_LIT); ASTIVal[node] := Ord(CurTok.SVal[1]); ASTTk[node] := Ord(tyChar);
        ASTSOffset[node] := Tokens[prevTok].SOffset; ASTSLen[node] := Tokens[prevTok].SLen;
        CurASTNode := node; Next; LastExprTk := tyChar;
      end
      else
      begin
        prevTok := TokPos - 1; Next;
        node := AllocNode(AN_STR_LIT);
        ASTSOffset[node] := Tokens[prevTok].SOffset; ASTSLen[node] := Tokens[prevTok].SLen;
        ASTTk[node] := Ord(tyString); CurASTNode := node;
        LastExprTk := tyString;
      end;
    end;
    tkLParen:
    begin
      Next; if PyExprMode then PyParseBoolExpr else ParseExpr; Expect(tkRParen, ')');
      { Postfix suffix on a parenthesised expression: `(p)^`, `(p+k)^`, `(r).f`,
        `(a)[i]`. Without this the `^`/`.`/`[` were left dangling and the grouped
        value was used as-is (e.g. `(p)^` returned the pointer, not the pointee). }
      node := CurASTNode;
      while CurTok.Kind in [tkCaret, tkDot, tkLBrack] do
      begin
        if CurTok.Kind = tkCaret then
        begin
          Next;
          indexNode := AllocNode(AN_DEREF);
          ASTLeft[indexNode] := node;
          { Resolve the pointee type from the inner node, mirroring the direct
            `ident^` path. A non-trivial pointer expression (binop/cast) carries
            no element-type tag, so default to Integer (matches `else` below). }
          tk := tyInteger; recName := REC_NONE;
          if IntToTypeKind(ASTTk[node]) = tyPointer then
          begin
            if ASTKind[node] = AN_IDENT then
            begin
              tk := Syms[ASTIVal[node]].PtrElemTk;
              recName := Syms[ASTIVal[node]].PtrElemRec;
            end
            else if (ASTKind[node] = AN_INDEX) and (ASTKind[ASTLeft[node]] = AN_IDENT) then
            begin
              tk := Syms[ASTIVal[ASTLeft[node]]].PtrElemTk;
              recName := Syms[ASTIVal[ASTLeft[node]]].PtrElemRec;
            end;
          end;
          ASTTk[indexNode] := Ord(tk);
          node := indexNode;
        end
        else if CurTok.Kind = tkLBrack then
        begin
          Next;
          indexNode := AllocNode(AN_INDEX);
          ASTLeft[indexNode] := node;
          ParseExpr;
          ASTRight[indexNode] := CurASTNode;
          Expect(tkRBrack, ']');
          ASTTk[indexNode] := ASTTk[node];
          node := indexNode;
        end
        else { tkDot — field or method of the grouped record/class value }
        begin
          Next;
          if CurTok.Kind in [tkEOF, tkSemicolon, tkAssign, tkRBrack, tkRParen] then
            Error('expected field name after .');
          prevTok := TokPos - 1;
          fieldName := GetTokenStr(prevTok);
          baseRec := ResolveNodeRec(node);
          mci := -1; mmi := -1;
          if baseRec >= REC_UCLASS_BASE then
          begin
            mci := baseRec - REC_UCLASS_BASE;
            mmi := FindUMeth(mci, fieldName);
          end;
          if (mmi >= 0) and (mci >= 0) and UClsIsInterface[mci] then
          begin
            { `(iface-expr).M(args)` — dispatch through the IMT slot, exactly like
              the direct `iface.M` path. The grouped node is the interface value. }
            mpi := UMthProc_[mmi];
            Next; { consume method name }
            mcallNode := AllocNode(AN_INTF_CALL);
            ASTRight[mcallNode] := node;
            ASTIVal[mcallNode] := mpi;
            ASTSOffset[mcallNode] := UMthVirSlot[mmi];
            ASTTk[mcallNode] := Ord(Procs[mpi].RetType);
            mlastArg := -1;
            if CurTok.Kind = tkLParen then
            begin
              Next;
              mai := 1; { param 0 = Self (provided by the fat pointer) }
              while mai <= Procs[mpi].ParamCount-1 do
              begin
                if Procs[mpi].Params[mai].IsRef or Procs[mpi].Params[mai].IsArray then
                begin
                  if CurTok.Kind <> tkIdent then Error('expected variable');
                  margIdx := FindSym(CurTok.SVal); Next;
                  mexprNode := ParseLValueAST(margIdx, TokPos - 2);
                end
                else begin ParseExpr; mexprNode := CurASTNode; end;
                margSeq := AllocNode(AN_ARG); ASTLeft[margSeq] := mexprNode;
                if mlastArg = -1 then ASTLeft[mcallNode] := margSeq
                else ASTRight[mlastArg] := margSeq;
                mlastArg := margSeq;
                if mai < Procs[mpi].ParamCount-1 then Expect(tkComma, ',');
                Inc(mai);
              end;
              Expect(tkRParen, ')');
            end;
            node := mcallNode;
          end
          else
          begin
            fieldNode := AllocNode(AN_FIELD);
            ASTLeft[fieldNode] := node;
            ASTSOffset[fieldNode] := Tokens[prevTok].SOffset;
            ASTSLen[fieldNode] := Tokens[prevTok].SLen;
            ASTTk[fieldNode] := Ord(RecFieldType(baseRec, fieldName));
            Next;
            node := fieldNode;
          end;
        end;
      end;
      CurASTNode := node;
    end;
    tkMinus:
    begin
      Next; ParseFactor;
      left := CurASTNode;
      node := AllocNode(AN_NEG); ASTLeft[node] := left; CurASTNode := node;
    end;
    tkNot:
    begin
      Next; ParseFactor;
      left := CurASTNode;
      { `not` is bitwise complement for integer operands (matches FPC), logical
        for Boolean and everything else. The earlier all-logical rule existed
        because a prior attempt keyed bitwise-vs-logical off the GLOBAL
        LastExprTk tracker, which is clobbered between factors — so a boolean
        `while not done` was mistyped as bitwise and hung self-compile.

        Drive it off the operand node's OWN type, but ONLY trust that type for
        operand node kinds whose type is authoritative: an integer LITERAL or an
        IDENTIFIER (its symbol's declared type). Computed expressions — AN_BINOP
        (comparisons / boolean ops) and AN_CALL (boolean-returning functions) —
        are NOT trusted here: PXX tags some of them tyInteger/tyInt64 even when
        they are logically Boolean (e.g. `not (a = b)`, `not Eat(...)` appear in
        compiler.pas with ASTTk = tyInteger), and promoting those to bitwise
        diverges from FPC and breaks self-host / cross-bootstrap. So those keep
        the long-standing logical behaviour. The IR_NOT codegen already emits
        `not rax` for ordinal-non-boolean types. }
      node := AllocNode(AN_NOT); ASTLeft[node] := left;
      if ((ASTKind[left] = AN_INT_LIT) or (ASTKind[left] = AN_IDENT)) and
         ((ASTTk[left] = 1) or ((ASTTk[left] >= 7) and (ASTTk[left] <= 16))) then
      begin
        ASTTk[node] := ASTTk[left];
        LastExprTk := IntToTypeKind(ASTTk[left]);
      end
      else
      begin
        ASTTk[node] := Ord(tyBoolean);
        LastExprTk := tyBoolean;
      end;
      CurASTNode := node;
    end;
    tkOrd, tkChr:
    begin
      if CurTok.Kind = tkChr then LastExprTk := tyChar else LastExprTk := tyInteger;
      op := Ord(CurTok.Kind);
      Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
      node := AllocNode(AN_CALL); ASTIVal[node] := -op;
      if op = Ord(tkChr) then ASTTk[node] := Ord(tyChar) else ASTTk[node] := Ord(tyInteger);
      argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
      ASTLeft[node] := argSeq;
      CurASTNode := node;
    end;
    tkInteger_T, tkLongWord_T:
    begin
      op := Ord(CurTok.Kind);
      Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
      node := AllocNode(AN_CALL); ASTIVal[node] := -op;
      ASTTk[node] := Ord(tyInteger);
      argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
      ASTLeft[node] := argSeq;
      CurASTNode := node;
    end;
    tkChar_T, tkBoolean_T:
    begin
      { `Char(x)` / `Boolean(x)` value-puns — same passthrough model as Chr/Ord:
        the result type is the cast type, the bit pattern is the operand's. }
      op := Ord(CurTok.Kind);
      if CurTok.Kind = tkChar_T then LastExprTk := tyChar else LastExprTk := tyBoolean;
      Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
      node := AllocNode(AN_CALL); ASTIVal[node] := -op;
      if op = Ord(tkChar_T) then ASTTk[node] := Ord(tyChar) else ASTTk[node] := Ord(tyBoolean);
      argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
      ASTLeft[node] := argSeq;
      CurASTNode := node;
    end;
    tkString_T:
    begin
      { `String(x)`. For a string operand it is identity (passthrough). For a Char
        operand it must produce a *string value*; route through AN_STR_FROM_CHAR
        which reuses the `s := c` store into a hidden temp, then yields the temp —
        so it works in both frozen and managed string modes with no backend code. }
      LastExprTk := tyString;
      Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
      if (IntToTypeKind(ASTTk[CurASTNode]) = tyString) or
         (IntToTypeKind(ASTTk[CurASTNode]) = tyAnsiString) then
      begin
        node := AllocNode(AN_CALL); ASTIVal[node] := -Ord(tkString_T);
        ASTTk[node] := ASTTk[CurASTNode];
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
        ASTLeft[node] := argSeq;
        CurASTNode := node;
      end
      else if IntToTypeKind(ASTTk[CurASTNode]) = tyChar then
      begin
        { Build the desugar at parse time so it goes through the same AST passes
          as hand-written code: a hidden string temp, `__t := c` (char->string
          store), and a read of __t. AN_STR_FROM_CHAR.Left = the assign (side
          effect), .Right = the temp read (the yielded value). The temp is tyString
          to match the `String` keyword (always frozen tyString in this dialect,
          even under PXX_MANAGED_STRING where only `AnsiString` is managed). }
        op := AllocVar('', tyString);
        node := AllocNode(AN_STR_FROM_CHAR);
        argSeq := AllocNode(AN_IDENT);       { LHS of the store }
        ASTIVal[argSeq] := op; ASTTk[argSeq] := Ord(Syms[op].TypeKind);
        left := AllocNode(AN_ASSIGN);
        ASTLeft[left] := argSeq; ASTRight[left] := CurASTNode;
        ASTTk[left] := Ord(Syms[op].TypeKind);
        ASTLeft[node] := left;
        identNode := AllocNode(AN_IDENT);     { the yielded value }
        ASTIVal[identNode] := op; ASTTk[identNode] := Ord(Syms[op].TypeKind);
        ASTRight[node] := identNode;
        ASTTk[node] := Ord(Syms[op].TypeKind);
        CurASTNode := node;
      end
      else
        Error('String(): operand must be Char or string');
    end;
    tkLength:
    begin
      Next; Expect(tkLParen, '(');
      if CurTok.Kind <> tkIdent then Error('Length: expected string variable');
      idx := FindSym(CurTok.SVal); Next;
      valNode := ParseLValueAST(idx, TokPos - 2);
      if idx < 0 then Error('Length: undefined variable');
      Expect(tkRParen, ')');
      node := AllocNode(AN_CALL); ASTIVal[node] := -Ord(tkLength); ASTTk[node] := Ord(tyInteger);
      argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := valNode;
      ASTLeft[node] := argSeq;
      CurASTNode := node;
    end;
    tkHigh:
    begin
      { High(arr) := Length(arr) - 1. Reuses the Length call + a subtraction, so
        no new IR/codegen — works for open arrays, dyn arrays and (via Length)
        static arrays alike. }
      Next; Expect(tkLParen, '(');
      if CurTok.Kind <> tkIdent then Error('High: expected array variable');
      idx := FindSym(CurTok.SVal); Next;
      valNode := ParseLValueAST(idx, TokPos - 2);
      if idx < 0 then Error('High: undefined variable');
      Expect(tkRParen, ')');
      node := AllocNode(AN_CALL); ASTIVal[node] := -Ord(tkLength); ASTTk[node] := Ord(tyInteger);
      argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := valNode;
      ASTLeft[node] := argSeq;
      valNode := AllocNode(AN_INT_LIT); ASTIVal[valNode] := 1; ASTTk[valNode] := Ord(tyInteger);
      CurASTNode := AllocNode(AN_BINOP);
      ASTIVal[CurASTNode] := Ord(tkMinus);
      ASTLeft[CurASTNode] := node; ASTRight[CurASTNode] := valNode;
      ASTTk[CurASTNode] := Ord(tyInteger);
    end;
    tkGetMem:
    begin
      Next; Expect(tkLParen, '(');
      ParseExpr;
      valNode := CurASTNode;
      Expect(tkRParen, ')');
      node := AllocNode(AN_CALL); ASTIVal[node] := -Ord(tkGetMem);
      argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := valNode;
      ASTLeft[node] := argSeq;
      CurASTNode := node;
    end;
    tkSysOpen:
    begin
      Next; Expect(tkLParen, '(');
      if CurTok.Kind <> tkIdent then Error('SysOpen: expected string var');
      idx := FindSym(CurTok.SVal); Next;
      valNode := ParseLValueAST(idx, TokPos - 2);
      if (idx < 0) or ((Syms[idx].TypeKind <> tyString) and
                       (Syms[idx].TypeKind <> tyAnsiString)) then Error('SysOpen: not a string var');
      Expect(tkComma, ',');

      argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := valNode;
      ParseExpr;
      argSeq2 := AllocNode(AN_ARG); ASTLeft[argSeq2] := CurASTNode;
      ASTRight[argSeq] := argSeq2;
      Expect(tkRParen, ')');

      node := AllocNode(AN_CALL); ASTIVal[node] := -Ord(tkSysOpen);
      ASTLeft[node] := argSeq;
      CurASTNode := node;
    end;
    tkSysRead:
    begin
      Next; Expect(tkLParen, '(');
      ParseExpr;
      argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
      Expect(tkComma, ',');
      if CurTok.Kind <> tkIdent then Error('SysRead: expected array var');
      idx := FindSym(CurTok.SVal); Next;
      valNode := ParseLValueAST(idx, TokPos - 2);
      if (idx < 0) or not Syms[idx].IsArray then Error('SysRead: not an array var');
      Expect(tkComma, ',');

      argSeq2 := AllocNode(AN_ARG); ASTLeft[argSeq2] := valNode;
      ASTRight[argSeq] := argSeq2;
      ParseExpr;
      argSeq3 := AllocNode(AN_ARG); ASTLeft[argSeq3] := CurASTNode;
      ASTRight[argSeq2] := argSeq3;
      Expect(tkRParen, ')');

      node := AllocNode(AN_CALL); ASTIVal[node] := -Ord(tkSysRead);
      ASTLeft[node] := argSeq;
      CurASTNode := node;
    end;
    tkSyswrite:
    begin
      Next; Expect(tkLParen, '(');
      ParseExpr;
      argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
      Expect(tkComma, ',');
      if CurTok.Kind <> tkIdent then Error('Syswrite: expected array var');
      idx := FindSym(CurTok.SVal); Next;
      valNode := ParseLValueAST(idx, TokPos - 2);
      if (idx < 0) or not Syms[idx].IsArray then Error('Syswrite: not an array var');
      Expect(tkComma, ',');

      argSeq2 := AllocNode(AN_ARG); ASTLeft[argSeq2] := valNode;
      ASTRight[argSeq] := argSeq2;
      ParseExpr;
      argSeq3 := AllocNode(AN_ARG); ASTLeft[argSeq3] := CurASTNode;
      ASTRight[argSeq2] := argSeq3;
      Expect(tkRParen, ')');

      node := AllocNode(AN_CALL); ASTIVal[node] := -Ord(tkSyswrite);
      ASTLeft[node] := argSeq;
      CurASTNode := node;
    end;
    tkArgCount:
    begin
      Next;
      if CurTok.Kind = tkLParen then begin Next; Expect(tkRParen, ')'); end;
      node := AllocNode(AN_CALL); ASTIVal[node] := -Ord(tkArgCount); CurASTNode := node;
    end;
    tkArgStr:
    begin
      Next; Expect(tkLParen, '(');
      ParseExpr;
      Expect(tkRParen, ')');
      node := AllocNode(AN_CALL); ASTIVal[node] := -Ord(tkArgStr);
      argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
      ASTLeft[node] := argSeq;
      CurASTNode := node;
    end;
    tkIdent:
    begin
      name := CurTok.SVal;
      if CaseEqual(name, 'await') and CurProcIsAsync then
      begin
        { `await E` as an expression. Binds tightly (a unary/primary operand, like
          Python) so `await f() + 1` is `(await f()) + 1`. STACKFUL: documentary —
          AN_AWAIT lowers straight to its operand; the awaited call suspends on its
          own via the reactor/CoYield. STACKLESS (later): the transform split point. }
        Next;
        ParseFactor;
        node := AllocNode(AN_AWAIT);
        ASTLeft[node] := CurASTNode;
        ASTTk[node]   := Ord(LastExprTk);
        CurASTNode := node;
        Exit;
      end;
      if isNilPy and (name = 'int') then
      begin
        Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
        node := AllocNode(AN_CALL); ASTIVal[node] := -200;
        ASTTk[node] := Ord(tyInteger);
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
        ASTLeft[node] := argSeq;
        CurASTNode := node;
        LastExprTk := tyInteger;
        Exit;
      end
      else if isNilPy and (name = 'str') then
      begin
        Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
        node := AllocNode(AN_CALL); ASTIVal[node] := -201;
        ASTTk[node] := Ord(tyString);
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
        ASTLeft[node] := argSeq;
        CurASTNode := node;
        LastExprTk := tyString;
        Exit;
      end
      else if (CaseEqual(name, 'trunc') or CaseEqual(name, 'round') or
               CaseEqual(name, 'frac') or CaseEqual(name, 'int')) and
              (Tokens[TokPos].Kind = tkLParen) then
      begin
        { only a call `name(...)` is the float intrinsic; a bare identifier of the
          same name (e.g. the FRAC const) falls through to normal handling }
        { Float intrinsics via SSE conversions (specialId 203-206):
          Trunc -> Int64 (toward zero), Round -> Int64 (nearest-even),
          Frac/Int -> Double (fractional part / integer part as float). }
        if CaseEqual(name, 'trunc') then prevTok := -203
        else if CaseEqual(name, 'round') then prevTok := -204
        else if CaseEqual(name, 'frac') then prevTok := -205
        else prevTok := -206;
        Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
        node := AllocNode(AN_CALL); ASTIVal[node] := prevTok;
        if (prevTok = -203) or (prevTok = -204) then ASTTk[node] := Ord(tyInt64)
        else ASTTk[node] := Ord(tyDouble);
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
        ASTLeft[node] := argSeq;
        CurASTNode := node;
        LastExprTk := IntToTypeKind(ASTTk[node]);
        Exit;
      end;
      qUnit := ConsumeUnitQualifier(name);
      prevTok := TokPos - 1;
      if CaseEqual(name, 'inherited') then
      begin
        CurASTNode := ParseInheritedCallAST;
        LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
        Exit;
      end;
      if CaseEqual(name, 'puint8') then
        writeln('ParseFactor PUInt8 found! Tokens[TokPos].Kind=', Ord(Tokens[TokPos].Kind), ' CurTok.Line=', CurTok.Line);

      { ---- SizeOf(TypeName) intrinsic: resolved at parse time to AN_INT_LIT ---- }
      if CaseEqual(name, 'sizeof') then
      begin
        Next; { consume 'SizeOf' }
        Expect(tkLParen, '(');
        { Peek at the type token to determine the kind }
        name := CurTok.SVal;
        if CurTok.Kind = tkInteger_T then
        begin
          { 'Integer', 'LongInt', 'ShortInt', 'Byte', 'Word', 'SmallInt', 'Cardinal', 'LongWord' }
          if CaseEqual(name, 'shortint') then
            prevTok := TypeSize(tyInt8)
          else if CaseEqual(name, 'byte') then
            prevTok := TypeSize(tyUInt8)
          else if CaseEqual(name, 'smallint') then
            prevTok := TypeSize(tyInt16)
          else if CaseEqual(name, 'word') then
            prevTok := TypeSize(tyUInt16)
          else if CaseEqual(name, 'longint') or CaseEqual(name, 'integer') then
            prevTok := TypeSize(tyInt32)
          else if CaseEqual(name, 'cardinal') then
            prevTok := TypeSize(tyUInt32)
          else
            prevTok := TypeSize(tyInt32);  { default integer-family }
        end
        else if CurTok.Kind = tkLongWord_T then
          prevTok := TypeSize(tyUInt32)
        else if CurTok.Kind = tkBoolean_T then
          prevTok := TypeSize(tyUInt8)   { Boolean is 1 byte per FPC ObjFPC }
        else if CurTok.Kind = tkChar_T then
          prevTok := TypeSize(tyChar)
        else if CurTok.Kind = tkString_T then
          prevTok := TypeSize(tyString)
        else if CurTok.Kind = tkIdent then
        begin
          { Named type: check for known types by name }
          if CaseEqual(name, 'shortint') then
            prevTok := TypeSize(tyInt8)
          else if CaseEqual(name, 'byte') then
            prevTok := TypeSize(tyUInt8)
          else if CaseEqual(name, 'smallint') then
            prevTok := TypeSize(tyInt16)
          else if CaseEqual(name, 'word') then
            prevTok := TypeSize(tyUInt16)
          else if CaseEqual(name, 'longint') or CaseEqual(name, 'integer') then
            prevTok := TypeSize(tyInt32)
          else if CaseEqual(name, 'cardinal') or CaseEqual(name, 'longword') then
            prevTok := TypeSize(tyUInt32)
          else if CaseEqual(name, 'int64') then
            prevTok := TypeSize(tyInt64)
          else if CaseEqual(name, 'qword') then
            prevTok := TypeSize(tyUInt64)
          else if CaseEqual(name, 'nativeint') or CaseEqual(name, 'ptrint') then
            prevTok := TypeSize(tyNativeInt)
          else if CaseEqual(name, 'nativeuint') or CaseEqual(name, 'ptruint') then
            prevTok := TypeSize(tyNativeUInt)
          else if CaseEqual(name, 'pointer') then
            prevTok := TypeSize(tyPointer)
          else if CaseEqual(name, 'boolean') then
            prevTok := TypeSize(tyUInt8)
          else if CaseEqual(name, 'char') or CaseEqual(name, 'ansichar') then
            prevTok := TypeSize(tyChar)
          else if CaseEqual(name, 'ansistring') then
          begin
            if PasDefineExists('PXX_MANAGED_STRING') then
              prevTok := TypeSize(tyAnsiString)
            else
              prevTok := TypeSize(tyString);
          end
          else if CaseEqual(name, 'string') then
            prevTok := TypeSize(tyString)
          else
          begin
            { Try record/class type }
            idx := IsRecordType(name);
            if idx = REC_NONE then
            begin
              ci := FindUClass(name);
              if ci >= 0 then
                idx := REC_UCLASS_BASE + ci;
            end;
            if idx <> REC_NONE then
              prevTok := RecSize(idx)
            else
            begin
              Error('SizeOf: unknown type');
              prevTok := 0;
            end;
          end;
        end
        else
        begin
          Error('SizeOf: expected type name');
          prevTok := 0;
        end;
        Next; { consume type token }
        Expect(tkRParen, ')');
        node := AllocNode(AN_INT_LIT);
        ASTIVal[node] := prevTok;
        ASTTk[node] := Ord(tyInteger);
        CurASTNode := node;
        Exit;
      end;

      if CaseEqual(name, '__pxxrawsyscall') then
      begin
        { Raw syscall intrinsic: lowered to the target's native syscall
          instruction. First arg = syscall number, then up to 6 arguments. }
        Next; { consume '__pxxrawsyscall' }
        Expect(tkLParen, '(');
        node := AllocNode(AN_SYSCALL);
        ASTTk[node] := Ord(tyInt64);
        lastArg := -1;
        nArgs := 0;
        repeat
          ParseExpr;
          exprNode := CurASTNode;
          argSeq := AllocNode(AN_ARG);
          ASTLeft[argSeq] := exprNode;
          if lastArg = -1 then
            ASTLeft[node] := argSeq
          else
            ASTRight[lastArg] := argSeq;
          lastArg := argSeq;
          Inc(nArgs);
        until not Eat(tkComma);
        Expect(tkRParen, ')');
        if nArgs > 7 then Error('__pxxrawsyscall: at most 7 arguments (nr + 6)');
        LastExprTk := tyInt64;
        CurASTNode := node;
        Exit;
      end;

      if CaseEqual(name, '__pxxcoswitch') then
      begin
        { Low-level coroutine context switch: __pxxcoswitch(pfrom, pto: Pointer).
          Both args are the addresses of the from/to TCoroCtx records. Lowers to
          a call to the bare CoSwitch runtime stub. }
        Next; { consume '__pxxcoswitch' }
        Expect(tkLParen, '(');
        node := AllocNode(AN_COSWITCH);
        ASTTk[node] := Ord(tyPointer);
        lastArg := -1;
        nArgs := 0;
        repeat
          ParseExpr;
          exprNode := CurASTNode;
          argSeq := AllocNode(AN_ARG);
          ASTLeft[argSeq] := exprNode;
          if lastArg = -1 then
            ASTLeft[node] := argSeq
          else
            ASTRight[lastArg] := argSeq;
          lastArg := argSeq;
          Inc(nArgs);
        until not Eat(tkComma);
        Expect(tkRParen, ')');
        if nArgs <> 2 then Error('__pxxcoswitch: expects exactly 2 arguments (pfrom, pto)');
        LastExprTk := tyPointer;
        CurASTNode := node;
        Exit;
      end;

      if CaseEqual(name, '__resources') then
      begin
        Next; { consume '__resources' }
        if CurTok.Kind = tkLParen then
        begin
          Next;
          Expect(tkRParen, ')');
        end;
        node := AllocNode(AN_RESOURCES);
        ASTTk[node] := Ord(tyPointer);
        CurASTNode := node;
        Exit;
      end;

      if CaseEqual(name, '__rttireg') then
      begin
        Next; { consume '__rttireg' }
        if CurTok.Kind = tkLParen then
        begin
          Next;
          Expect(tkRParen, ')');
        end;
        node := AllocNode(AN_RTTI_REG);
        ASTTk[node] := Ord(tyPointer);
        CurASTNode := node;
        Exit;
      end;

      if qUnit >= 0 then
      begin
        idx := FindSymInUnit(name, qUnit);
        pi := FindProcInUnit(name, qUnit);
      end
      else
      begin
        idx := FindSym(name);
        pi := FindProc(name);
      end;

      if (idx >= 0) and (Syms[idx].TypeKind = tyAuto) then
        Error('use of auto variable before type is inferred');

      { `Supports(obj, IFoo): Boolean` — the function form of `obj is IFoo`.
        Reuses the interface implementation query (AN_IS_TEST). }
      if CaseEqual(name, 'Supports') and (pi < 0) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        ParseExpr; exprNode := CurASTNode;
        Expect(tkComma, ',');
        if CurTok.Kind <> tkIdent then Error('Supports: expected interface name');
        ci := FindUClass(CurTok.SVal);
        if (ci < 0) or not UClsIsInterface[ci] then Error('Supports: second argument must be an interface');
        Next;
        Expect(tkRParen, ')');
        node := AllocNode(AN_IS_TEST);
        ASTLeft[node] := exprNode; ASTIVal[node] := ci; ASTTk[node] := Ord(tyBoolean);
        CurASTNode := node; LastExprTk := tyBoolean;
        Exit;
      end;

      { Indirect call through a procedural-type variable: v(args) as an expression. }
      if (idx >= 0) and (SymProcSig[idx] >= 0) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        node := ParseProcVarCallAST(idx, SymProcSig[idx]);
        CurASTNode := node;
        LastExprTk := IntToTypeKind(ASTTk[node]);
        Exit;
      end;

      { C4: pointer-type-alias cast — PFoo(expr) where PFoo = ^TFoo }
      if (idx < 0) and (pi < 0) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        aliasIdx := FindTypeAlias(name);
        if aliasIdx >= 0 then
        begin
          Next; { consume alias type name }
          Expect(tkLParen, '(');
          ParseExpr;
          Expect(tkRParen, ')');
          node := AllocNode(AN_PTR_CAST);
          ASTLeft[node] := CurASTNode;
          ASTIVal[node] := aliasIdx;
          ASTTk[node]   := Ord(tyPointer);
          { Set locals so the suffix loop below can resolve ^ and .field }
          tk      := tyPointer;
          recName := AliasElemRec[aliasIdx];  { pointee record id, used after ^ }
          { Run suffix loop: handle chains of ^, .field, and [i] on the cast result. }
          while CurTok.Kind in [tkCaret, tkDot, tkLBrack] do
          begin
            if CurTok.Kind = tkCaret then
            begin
              Next;
              indexNode := AllocNode(AN_DEREF);
              ASTLeft[indexNode] := node;
              { After ^, type becomes the pointee }
              tk      := IntToTypeKind(AliasElemTk[aliasIdx]);
              recName := AliasElemRec[aliasIdx];
              ASTTk[indexNode] := Ord(tk);
              node := indexNode;
            end
            else if CurTok.Kind = tkLBrack then
            begin
              Next;
              indexNode := AllocNode(AN_INDEX);
              ASTLeft[indexNode] := node;
              ParseExpr;
              ASTRight[indexNode] := CurASTNode;
              Expect(tkRBrack, ']');
              if tk = tyPointer then
              begin
                tk := IntToTypeKind(AliasElemTk[aliasIdx]);
                recName := AliasElemRec[aliasIdx];
              end
              else
              begin
                tk := tyUnknown;
                recName := REC_NONE;
              end;
              ASTTk[indexNode] := Ord(tk);
              node := indexNode;
            end
            else { tkDot }
            begin
              Next;
              if CurTok.Kind in [tkEOF, tkSemicolon, tkAssign, tkRBrack, tkRParen] then
                Error('expected field name after .');
              prevTok  := TokPos - 1;
              fieldName := '';
              for i := Tokens[prevTok].SOffset to Tokens[prevTok].SOffset + Tokens[prevTok].SLen - 1 do
                AppendChar(fieldName, TokChars[i]);
              fieldNode := AllocNode(AN_FIELD);
              ASTLeft[fieldNode] := node;
              ASTSOffset[fieldNode] := Tokens[prevTok].SOffset;
              ASTSLen[fieldNode]   := Tokens[prevTok].SLen;
              tk      := RecFieldType(recName, fieldName);
              recName := RecFieldRecId(recName, fieldName);
              ASTTk[fieldNode] := Ord(tk);
              Next;
              node := fieldNode;
            end;
          end;
          CurASTNode := node;
          LastExprTk := tk;
          Exit;
        end
        else
        begin
          { Built-in typecast }
          castTk := tyUnknown;
          if CaseEqual(name, 'pchar') or CaseEqual(name, 'pansichar') then
          begin
            { PChar(s): yields a C `const char*` into the string's char data.
              Lowered specially (sentinel -2) to skip the inline length prefix
              for string operands; a plain Pointer reinterpret otherwise. }
            Next; { consume type name }
            Expect(tkLParen, '(');
            ParseExpr;
            Expect(tkRParen, ')');
            node := AllocNode(AN_PTR_CAST);
            ASTLeft[node] := CurASTNode;
            ASTIVal[node] := -2; { PChar adapter }
            ASTTk[node]   := Ord(tyPointer);
            CurASTNode    := node;
            LastExprTk    := tyPointer;
            Exit;
          end;
          if CaseEqual(name, 'pointer') then castTk := tyPointer
          else if CaseEqual(name, 'int64') then castTk := tyInt64
          else if CaseEqual(name, 'qword') then castTk := tyUInt64
          else if CaseEqual(name, 'integer') or CaseEqual(name, 'longint') then castTk := tyInteger
          else if CaseEqual(name, 'cardinal') or CaseEqual(name, 'longword') then castTk := tyUInt32
          else if CaseEqual(name, 'smallint') then castTk := tyInt16
          else if CaseEqual(name, 'word') then castTk := tyUInt16
          else if CaseEqual(name, 'shortint') then castTk := tyInt8
          else if CaseEqual(name, 'byte') then castTk := tyUInt8
          else if CaseEqual(name, 'char') or CaseEqual(name, 'ansichar') then castTk := tyChar
          else if CaseEqual(name, 'boolean') then castTk := tyBoolean
          else if CaseEqual(name, 'ansistring') then
          begin
            if PasDefineExists('PXX_MANAGED_STRING') then
              castTk := tyAnsiString
            else
              castTk := tyString;
          end
          else if CaseEqual(name, 'string') then castTk := tyString;

          if castTk <> tyUnknown then
          begin
            Next; { consume type name }
            Expect(tkLParen, '(');
            ParseExpr;
            Expect(tkRParen, ')');
            node := AllocNode(AN_PTR_CAST);
            ASTLeft[node] := CurASTNode;
            ASTIVal[node] := -1; { indicates built-in cast }
            ASTTk[node]   := Ord(castTk);
            CurASTNode    := node;
            LastExprTk    := castTk;
            Exit;
          end;
        end;
      end;

      if (idx < 0) and (pi < 0) and IsClassType(name) and
         (CurTok.Kind = tkIdent) and (Tokens[TokPos].Kind = tkDot) and
         (Tokens[TokPos+1].Kind = tkIdent) and
         ((GetTokenStr(TokPos+1) = 'Create') or (GetTokenStr(TokPos+1) = 'create')) then
      begin
        Next; { Eat class name }
        Next; { Eat dot }
        Next; { Eat 'Create' }

        argsHead := -1;
        lastArg := -1;
        if CurTok.Kind = tkLParen then
        begin
          Next;
          while CurTok.Kind <> tkRParen do
          begin
            ParseExpr;
            argSeq := AllocNode(AN_ARG);
            ASTLeft[argSeq] := CurASTNode;
            if argsHead = -1 then
              argsHead := argSeq
            else
              ASTRight[lastArg] := argSeq;
            lastArg := argSeq;
            if CurTok.Kind = tkComma then
              Next
            else if CurTok.Kind <> tkRParen then
              Error('expected comma or close parenthesis');
          end;
          Expect(tkRParen, ')');
        end;

        idx := IsRecordType(name);
        if idx = REC_NONE then
        begin
          ci := FindUClass(name);
          if ci >= 0 then
            idx := REC_UCLASS_BASE + ci;
        end;
        prevTok := RecSize(idx);

        { Construct GetMem(sz) AST node }
        node := AllocNode(AN_CALL);
        ASTIVal[node] := -Ord(tkGetMem);
        ASTTk[node] := Ord(tyClass);
        ASTRight[node] := idx; { preserve created user-class id }

        exprNode := AllocNode(AN_INT_LIT);
        ASTIVal[exprNode] := prevTok;
        ASTTk[exprNode] := Ord(tyInteger);

        { The first argument to the GetMem call is the size }
        szArg := AllocNode(AN_ARG);
        ASTLeft[szArg] := exprNode;
        ASTLeft[node] := szArg;

        { The rest of the arguments are constructor arguments! }
        if argsHead <> -1 then
          ASTRight[szArg] := argsHead;

        CurASTNode := node;
        Exit;
      end;
      if (idx < 0) and (pi < 0) and IsClassType(name) and
         (Tokens[TokPos].Kind = tkDot) and (Tokens[TokPos+1].Kind = tkIdent) then
      begin
        ci := FindUClass(name);
        mmi := FindUMeth(ci, GetTokenStr(TokPos+1));
        if mmi >= 0 then
        begin
          if UMthIsStatic[mmi] then
          begin
            mpi := UMthProc_[mmi];
            Next; { consume class name }
            Expect(tkDot, '.');
            Next; { consume method name }
            mcallNode := AllocNode(AN_CALL);
            ASTIVal[mcallNode] := mpi;
            ASTTk[mcallNode] := Ord(Procs[mpi].RetType);
            mlastArg := -1;
            if CurTok.Kind = tkLParen then
            begin
              Next;
              i := 0;
              while i <= Procs[mpi].ParamCount-1 do
              begin
                if Procs[mpi].Params[i].IsRef or Procs[mpi].Params[i].IsArray then
                begin
                  if CurTok.Kind <> tkIdent then Error('expected variable');
                  argIdx := FindSym(CurTok.SVal); Next;
                  exprNode := ParseLValueAST(argIdx, TokPos - 2);
                end
                else
                begin
                  ParseExpr; exprNode := CurASTNode;
                end;
                argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := exprNode;
                if mlastArg = -1 then
                  ASTLeft[mcallNode] := argSeq
                else
                  ASTRight[mlastArg] := argSeq;
                mlastArg := argSeq;
                if i < Procs[mpi].ParamCount-1 then Expect(tkComma, ',');
                Inc(i);
              end;
              Expect(tkRParen, ')');
            end;
            CurASTNode := mcallNode;
            Exit;
          end;
        end;
      end;
      sci := FindStrConst(name);
      if sci >= 0 then
      begin
        { Untyped string constant — expand to a string literal over its span. }
        node := AllocNode(AN_STR_LIT);
        ASTSOffset[node] := StrConstSOff[sci]; ASTSLen[node] := StrConstSLen[sci];
        ASTTk[node] := Ord(tyString); CurASTNode := node; Next;
      end
      else if (idx >= 0) and (Syms[idx].Kind = skConst) then
      begin
        node := AllocNode(AN_INT_LIT); ASTIVal[node] := Syms[idx].ConstVal; ASTTk[node] := Ord(Syms[idx].TypeKind); CurASTNode := node; Next;
      end
      else if (pi >= 0) and Procs[pi].IsFunc and (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next;
        Expect(tkLParen, '(');
        argsHead := -1;
        lastArg := -1;
        nArgs := 0;
        while CurTok.Kind <> tkRParen do
        begin
          ParseExpr;
          argSeq := AllocNode(AN_ARG);
          ASTLeft[argSeq] := CurASTNode;
          if argsHead = -1 then
            argsHead := argSeq
          else
            ASTRight[lastArg] := argSeq;
          lastArg := argSeq;
          Inc(nArgs);
          if CurTok.Kind = tkComma then
            Next
          else if CurTok.Kind <> tkRParen then
            Error('expected comma or close parenthesis');
        end;
        Expect(tkRParen, ')');

        currArg := argsHead;
        for i := 0 to nArgs - 1 do
        begin
          exprNode := ASTLeft[currArg];
          argTypes[i] := IntToTypeKind(ASTTk[exprNode]);
          currArg := ASTRight[currArg];
        end;

        if qUnit >= 0 then
          pi := MatchProcCallInUnit(name, qUnit, nArgs, argTypes)
        else
          pi := MatchProcCall(name, nArgs, argTypes);
        if pi < 0 then
          Error('no overload of ' + name + ' matches these arguments');

        isLiftedCall := (pi >= 0) and (Procs[pi].ParamCount > nArgs) and
                        (ProcParamPtrDepth[pi * 16 + nArgs] = 2);

        if isLiftedCall then
        begin
          liftedVar := AllocVar('', tyPointer);
          identNode := AllocNode(AN_IDENT);
          ASTIVal[identNode] := liftedVar;
          ASTTk[identNode] := Ord(tyPointer);

          addrNode := AllocNode(AN_ADDR);
          ASTLeft[addrNode] := identNode;
          ASTTk[addrNode] := Ord(tyPointer);

          argSeq := AllocNode(AN_ARG);
          ASTLeft[argSeq] := addrNode;

          if argsHead = -1 then
          begin
            argsHead := argSeq;
            lastArg := argSeq;
          end
          else
          begin
            ASTRight[lastArg] := argSeq;
            lastArg := argSeq;
          end;

          argTypes[nArgs] := tyPointer;
          Inc(nArgs);

          while nArgs < Procs[pi].ParamCount do
          begin
            addrNode := AllocNode(AN_INT_LIT);
            ASTIVal[addrNode] := 0;
            ASTTk[addrNode] := Ord(tyPointer);

            argSeq := AllocNode(AN_ARG);
            ASTLeft[argSeq] := addrNode;

            if argsHead = -1 then
            begin
              argsHead := argSeq;
              lastArg := argSeq;
            end
            else
            begin
              ASTRight[lastArg] := argSeq;
              lastArg := argSeq;
            end;

            argTypes[nArgs] := tyPointer;
            Inc(nArgs);
          end;
        end;

        isCStringCall := PyExprMode and (Procs[pi].RetType = tyPointer) and
                         ((ProcRetPtrElemTk[pi] = Ord(tyChar)) or
                          (ProcRetPtrElemTk[pi] = Ord(tyUInt8)) or
                          (ProcRetPtrElemTk[pi] = Ord(tyInt8)));

        currArg := argsHead;
        for i := 0 to nArgs - 1 do
        begin
          exprNode := ASTLeft[currArg];
          if (Procs[pi].Params[i].TypeKind = tyString) and (IntToTypeKind(ASTTk[exprNode]) = tyChar) then
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
          if Procs[pi].Params[i].IsRef or Procs[pi].Params[i].IsArray then
          begin
            if not ((ASTKind[exprNode] = AN_IDENT) or (ASTKind[exprNode] = AN_INDEX) or (ASTKind[exprNode] = AN_FIELD)) then
              Error('by-reference argument must be a variable');
          end;
          currArg := ASTRight[currArg];
        end;

        node := AllocNode(AN_CALL);
        ASTIVal[node] := pi;
        ASTTk[node] := Ord(Procs[pi].RetType);
        ASTLeft[node] := argsHead;
        if isLiftedCall then
        begin
          ASTLiftedVar[node] := liftedVar;
          ASTTk[node] := Ord(tyPointer);
        end;

        if isCStringCall then
        begin
          helperPi := FindProc('PCharToString');
          if helperPi < 0 then Error('builtin: PCharToString not found in Nil Python mode');
          wrapperArg := AllocNode(AN_ARG);
          ASTLeft[wrapperArg] := node;
          wrapperCall := AllocNode(AN_CALL);
          ASTIVal[wrapperCall] := helperPi;
          ASTTk[wrapperCall] := Ord(tyString);
          ASTLeft[wrapperCall] := wrapperArg;
          node := wrapperCall;

          CurASTNode := node;
          LastExprTk := tyString;
        end
        else
        begin
          ApplyCallResultPtrSuffix(node, pi);  { f(...)^ / ^.field / [i] }
          if isLiftedCall then
          begin
            CurASTNode := node;
            LastExprTk := tyPointer;
          end;
        end;
        Exit;
      end
      else if (pi >= 0) and Procs[pi].IsFunc and (Procs[pi].ParamCount = 0) then
      begin
        Next;
        node := AllocNode(AN_CALL);
        ASTIVal[node] := pi;
        ASTTk[node] := Ord(Procs[pi].RetType);
        ApplyCallResultPtrSuffix(node, pi);  { f()^ / ^.field / [i] }
        Exit;
      end
      else
      begin
        { Implicit Self.method dispatch for methods called bare inside a class body in expression context }
        node := -1;
        if (idx < 0) and (pi < 0) and (CurSelfClass >= REC_UCLASS_BASE) then
        begin
          ci := CurSelfClass - REC_UCLASS_BASE;
          mmi := FindUMeth(ci, name);
          if mmi >= 0 then
          begin
            mpi := UMthProc_[mmi];
            Next; { consume method name }
            smSelfIdx := Procs[CurProc].Params[0].SymIdx;
            smselfArg := AllocNode(AN_ARG);
            valNode := AllocNode(AN_IDENT);
            ASTIVal[valNode] := smSelfIdx;
            ASTTk[valNode] := Ord(tyClass);
            ASTLeft[smselfArg] := valNode;
            if UMthVirSlot[mmi] >= 0 then
            begin
              mcallNode := AllocNode(AN_VIRTUAL_CALL);
              ASTRight[mcallNode] := UMthVirSlot[mmi];
            end
            else
              mcallNode := AllocNode(AN_CALL);
            ASTIVal[mcallNode] := mpi;
            if (mpi >= 0) then
              ASTTk[mcallNode] := Ord(Procs[mpi].RetType)
            else
              ASTTk[mcallNode] := Ord(tyInteger);
            ASTLeft[mcallNode] := smselfArg;
            mlastArg := smselfArg;
            if CurTok.Kind = tkLParen then
            begin
              Next;
              i := 1;
              while CurTok.Kind <> tkRParen do
              begin
                ParseExpr;
                argSeq := AllocNode(AN_ARG);
                ASTLeft[argSeq] := CurASTNode;
                ASTRight[mlastArg] := argSeq;
                mlastArg := argSeq;
                Inc(i);
                if CurTok.Kind = tkComma then Next;
              end;
              Expect(tkRParen, ')');
            end;
            CurASTNode := mcallNode;
            node := mcallNode;
          end;
        end;
        if node = -1 then
        begin
          Next;
          CurASTNode := ParseLValueAST(idx, TokPos - 2);
          LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
        end;
      end;
    end;
    else Error('expected expression');
  end;
end;

procedure ParseTerm;
var op: TTokenKind; left, right, node, opSOffset, opSLen, opci: Integer;
begin
  ParseFactor;
  while ((CurTok.Kind in [tkStar, tkSlash, tkDiv, tkMod, tkAnd, tkShl]) or
        ((CurTok.Kind = tkIdent) and (CurTok.SVal = 'shr'))) and
        not (PyExprMode and (CurTok.Kind = tkAnd)) do
  begin
    opSOffset := Tokens[TokPos - 1].SOffset;
    opSLen := Tokens[TokPos - 1].SLen;
    op := CurTok.Kind; Next;
    left := CurASTNode;
    ParseFactor;
    right := CurASTNode;
    node := AllocNode(AN_BINOP); ASTIVal[node] := Ord(op); ASTLeft[node] := left; ASTRight[node] := right;
    ASTSOffset[node] := opSOffset; ASTSLen[node] := opSLen;
    opci := -1;
    if (IntToTypeKind(ASTTk[left]) = tyRecord) or (IntToTypeKind(ASTTk[left]) = tyClass) then
      opci := FindOpOverload(Ord(op), ASTTk[left], ResolveNodeRec(left));
    if opci >= 0 then
      { Overloaded operator on a record/class operand returns its result type. }
      ASTTk[node] := Ord(Procs[opci].RetType)
    else if (ASTTk[left] = Ord(tyVariant)) or (ASTTk[right] = Ord(tyVariant)) then
      ASTTk[node] := Ord(tyVariant)
    else if (op = tkAnd) and (ASTTk[left] = Ord(tyBoolean)) and (ASTTk[right] = Ord(tyBoolean)) then
      ASTTk[node] := Ord(tyBoolean)
    else if (ASTTk[left] = Ord(tySet)) or (ASTTk[right] = Ord(tySet)) then
      ASTTk[node] := Ord(tySet)
    else if op = tkSlash then
      ASTTk[node] := Ord(tyDouble)  { '/' always produces Double }
    else if op = tkDiv then
      ASTTk[node] := Ord(TypeDivideResult(IntToTypeKind(ASTTk[left])))
    else if op = tkMod then
      ASTTk[node] := Ord(TypeDivideResult(IntToTypeKind(ASTTk[left])))
    else if (op = tkIdent) or (op = tkShl) then
      ASTTk[node] := ASTTk[left]
    else if (ASTTk[left] = Ord(tySingle)) or (ASTTk[left] = Ord(tyDouble)) or (ASTTk[left] = Ord(tyExtended)) or
            (ASTTk[right] = Ord(tySingle)) or (ASTTk[right] = Ord(tyDouble)) or (ASTTk[right] = Ord(tyExtended)) then
    begin
      if (ASTTk[left] = Ord(tyExtended)) or (ASTTk[right] = Ord(tyExtended)) then
        ASTTk[node] := Ord(tyExtended)
      else
        ASTTk[node] := Ord(tyDouble);
    end
    else if TypeIsOrdinal(IntToTypeKind(ASTTk[left])) and TypeIsOrdinal(IntToTypeKind(ASTTk[right])) then
      ASTTk[node] := Ord(TypeArithmeticResult(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])))
    else
      ASTTk[node] := Ord(tyInteger);
    CurASTNode := node;
  end;
end;

procedure ParseSimpleExpr;
var op: TTokenKind; neg: Boolean; left, right, node, opci: Integer;
begin
  neg := CurTok.Kind = tkMinus; Eat(tkMinus); Eat(tkPlus);
  ParseTerm;
  if neg then
  begin
    node := AllocNode(AN_NEG); ASTLeft[node] := CurASTNode; ASTTk[node] := ASTTk[CurASTNode]; CurASTNode := node;
  end;
  while (CurTok.Kind in [tkPlus, tkMinus, tkOr]) and
        not (PyExprMode and (CurTok.Kind = tkOr)) do
  begin
    op := CurTok.Kind; Next;
    left := CurASTNode;
    ParseTerm;
    right := CurASTNode;
    node := AllocNode(AN_BINOP); ASTIVal[node] := Ord(op); ASTLeft[node] := left; ASTRight[node] := right;
    opci := -1;
    if (IntToTypeKind(ASTTk[left]) = tyRecord) or (IntToTypeKind(ASTTk[left]) = tyClass) then
      opci := FindOpOverload(Ord(op), ASTTk[left], ResolveNodeRec(left));
    if opci >= 0 then
      { Overloaded operator on a record/class operand: the node's type is the
        operator's result type, so an inferred target and the aggregate-return
        copy are sized correctly (not the tyInteger catch-all below). }
      ASTTk[node] := Ord(Procs[opci].RetType)
    else if (ASTTk[left] = Ord(tyVariant)) or (ASTTk[right] = Ord(tyVariant)) then
      ASTTk[node] := Ord(tyVariant)
    else if (op = tkPlus) and ((ASTTk[left] = Ord(tyAnsiString)) or (ASTTk[right] = Ord(tyAnsiString))) then
      ASTTk[node] := Ord(tyAnsiString)
    else if (op = tkPlus) and ((ASTTk[left] = Ord(tyString)) or (ASTTk[right] = Ord(tyString)) or
                          ((ASTTk[left] = Ord(tyChar)) and (ASTTk[right] = Ord(tyChar)))) then
      ASTTk[node] := Ord(tyString)
    else if ((op = tkPlus) or (op = tkMinus)) and
            (ASTTk[left] = Ord(tyPointer)) and
            TypeIsOrdinal(IntToTypeKind(ASTTk[right])) then
      ASTTk[node] := Ord(tyPointer)
    else if (op = tkPlus) and
            TypeIsOrdinal(IntToTypeKind(ASTTk[left])) and
            (ASTTk[right] = Ord(tyPointer)) then
      ASTTk[node] := Ord(tyPointer)
    else if (ASTTk[left] = Ord(tySet)) or (ASTTk[right] = Ord(tySet)) then
      ASTTk[node] := Ord(tySet)
    else if (op = tkOr) and (ASTTk[left] = Ord(tyBoolean)) and (ASTTk[right] = Ord(tyBoolean)) then
      ASTTk[node] := Ord(tyBoolean)
    else if (ASTTk[left] = Ord(tySingle)) or (ASTTk[left] = Ord(tyDouble)) or (ASTTk[left] = Ord(tyExtended)) or
            (ASTTk[right] = Ord(tySingle)) or (ASTTk[right] = Ord(tyDouble)) or (ASTTk[right] = Ord(tyExtended)) then
    begin
      if (ASTTk[left] = Ord(tyExtended)) or (ASTTk[right] = Ord(tyExtended)) then
        ASTTk[node] := Ord(tyExtended)
      else
        ASTTk[node] := Ord(tyDouble);
    end
    else if TypeIsOrdinal(IntToTypeKind(ASTTk[left])) and TypeIsOrdinal(IntToTypeKind(ASTTk[right])) then
      ASTTk[node] := Ord(TypeArithmeticResult(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])))
    else
      ASTTk[node] := Ord(tyInteger);
    CurASTNode := node;
  end;
end;

procedure ParseExpr;
var op: TTokenKind; left, right, node, isci: Integer; isIsTest: Boolean;
begin
  ParseSimpleExpr;
  { `X is T` / `X as T` — is/as are contextual identifiers (not reserved tokens),
    treated as operators only when followed by a known class name, so a stray
    identifier is never hijacked. Parser-resolved into their own AST nodes (per
    the and/or lesson: never key behaviour off a global flag). }
  if (CurTok.Kind = tkIdent) and
     (CaseEqual(CurTok.SVal, 'is') or CaseEqual(CurTok.SVal, 'as')) and
     (TokPos < TokCount) and (Tokens[TokPos].Kind = tkIdent) and
     (FindUClass(GetTokenStr(TokPos)) >= 0) then
  begin
    isIsTest := CaseEqual(CurTok.SVal, 'is');
    Next;
    isci := FindUClass(CurTok.SVal);
    Next;
    left := CurASTNode;
    if isIsTest then
    begin
      node := AllocNode(AN_IS_TEST);
      ASTLeft[node] := left; ASTIVal[node] := isci; ASTTk[node] := Ord(tyBoolean);
    end
    else
    begin
      node := AllocNode(AN_AS_CAST);
      ASTLeft[node] := left; ASTIVal[node] := isci;
      { `obj as IFoo` yields an interface VALUE (a CORBA fat pointer, a 2-word
        record); `obj as TClass` yields a class reference. }
      if UClsIsInterface[isci] then ASTTk[node] := Ord(tyRecord)
      else ASTTk[node] := Ord(tyClass);
    end;
    CurASTNode := node;
    Exit;
  end;
  if CurTok.Kind = tkIn then
  begin
    Next;
    if CurTok.Kind = tkLBrack then
    begin
      CurASTNode := ParseSetMembershipAST(CurASTNode);
    end
    else
    begin
      left := CurASTNode;
      ParseSimpleExpr;
      right := CurASTNode;
      node := AllocNode(AN_BINOP);
      ASTIVal[node] := Ord(tkIn);
      ASTLeft[node] := left;
      ASTRight[node] := right;
      ASTTk[node] := Ord(tyBoolean);
      CurASTNode := node;
    end;
    Exit;
  end;
  if CurTok.Kind in [tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe] then
  begin
    op := CurTok.Kind; Next;
    left := CurASTNode;
    ParseSimpleExpr;
    right := CurASTNode;
    node := AllocNode(AN_BINOP); ASTIVal[node] := Ord(op); ASTLeft[node] := left; ASTRight[node] := right;
    ASTTk[node] := Ord(tyBoolean); CurASTNode := node;
  end;
end;

function ConstEval: Int64;
{ Evaluate a compile-time constant expression (no code emitted) }
var r, v: Int64; idx, i: Integer; op: TTokenKind; s: AnsiString;
begin
  r := 0;
  if CurTok.Kind = tkInteger then begin r := CurTok.IVal; Next; end
  else if CurTok.Kind = tkTrue  then begin r := 1; Next; end
  else if CurTok.Kind = tkFalse then begin r := 0; Next; end
  else if CurTok.Kind = tkMinus then begin Next; r := -ConstEval(); end
  else if CurTok.Kind = tkIdent then
  begin
    idx := FindSym(CurTok.SVal);
    if (idx >= 0) and (Syms[idx].Kind = skConst) then
      r := Syms[idx].ConstVal
    else
    begin
      writeln('ConstEval error at SrcLine ', SrcLine, ': SVal = ', CurTok.SVal, ' Kind = ', Ord(CurTok.Kind), ' TokPos = ', TokPos);
      writeln('Tokens nearby:');
      for idx := TokPos - 5 to TokPos + 5 do
      begin
        if (idx >= 0) and (idx < TokCount) then
        begin
          writeln('  Token ', idx, ': Line = ', Tokens[idx].Line, ' Kind = ', Ord(Tokens[idx].Kind), ' SOffset = ', Tokens[idx].SOffset, ' SLen = ', Tokens[idx].SLen);
        end;
      end;
      Error('not a constant');
    end;
    Next;
  end
  else if CurTok.Kind = tkLParen then
  begin
    Next; r := ConstEval; Expect(tkRParen, ')');
  end;
  while (CurTok.Kind in [tkPlus, tkMinus, tkStar, tkDiv, tkMod, tkAnd, tkOr, tkShl]) or
        ((CurTok.Kind = tkIdent) and (CurTok.SVal = 'shr')) do
  begin
    { `shr` is lexed as an identifier (no tkShr token), like the runtime term
      parser; everything else is a real operator token. }
    if CurTok.Kind = tkIdent then
    begin
      Next; v := ConstEval(); r := r shr v;
    end
    else
    begin
      op := CurTok.Kind; Next; v := ConstEval();
      case op of
        tkPlus:  r := r + v;
        tkMinus: r := r - v;
        tkStar:  r := r * v;
        tkDiv:   r := r div v;
        tkMod:   r := r mod v;
        tkAnd:   r := r and v;
        tkOr:    r := r or v;
        tkShl:   r := r shl v;
      end;
    end;
  end;
  Result := r;
end;

{ Parse one constant initializer value (scalar). A float literal yields its IEEE
  754 bit pattern (carried as Int64, same as AN_FLOAT_LIT); everything else goes
  through the integer ConstEval. Lets a `Double` initializer like 3.14 work. }
function ParseInitVal: Int64;
begin
  if CurTok.Kind = tkFloat then begin Result := CurTok.IVal; Next; end
  else Result := ConstEval;
end;

{ ===== Statement parser ===== }

procedure ParseStatement; forward;
procedure ParseBlock; forward;

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

function ParseForInGeneratorAST(varIdx, gpi: Integer): Integer;
var
  bodyNode, nargs, gIdx: Integer;
  a0, a1, a2, a3: Integer;
  procAddr, nargsLit, callAlloc, callNext, callCur, callFree: Integer;
  assignG, assignX, whileNode, innerSeq, instLit: Integer;
  sa1, sa2, sa3, sa4: Integer;
  paCoAlloc, paCoNext, paCoCurrent, paCoFree: Integer;
begin
  { unused args default to 0 (no local array — must cross-compile) }
  a0 := GenZeroLit; a1 := GenZeroLit; a2 := GenZeroLit; a3 := GenZeroLit;
  nargs := 0;
  if Eat(tkLParen) then
  begin
    if CurTok.Kind <> tkRParen then
      repeat
        ParseExpr;
        case nargs of
          0: a0 := CurASTNode;
          1: a1 := CurASTNode;
          2: a2 := CurASTNode;
          3: a3 := CurASTNode;
          else Error('for-in generator: at most 4 arguments (v1)');
        end;
        Inc(nargs);
      until not Eat(tkComma);
    Expect(tkRParen, ')');
  end;
  Expect(tkDo, 'do');
  bodyNode := ParseStatementAST;

  gIdx := AllocVar('', tyPointer);
  nargsLit := AllocNode(AN_INT_LIT);  ASTIVal[nargsLit] := nargs; ASTTk[nargsLit] := Ord(tyInt64);

  if ProcIsStackless[gpi] then
  begin
    { Stackless: alloc + zero an instance, store args; advance by calling the
      generator's step function directly (the compiler knows it — PXX cannot call
      through a stored proc pointer with args). CoCurrent/free are shared shape.
        __g := SlAlloc(instSize, nargs, a0..a3);
        while Gen(__g) do begin x := SlCurrent(__g); BODY end;
        SlFree(__g); }
    if (FindProc('SlAlloc') < 0) or (FindProc('SlCurrent') < 0) or (FindProc('SlFree') < 0) then
      Error('for-in generator: the slgen unit is not in scope (add `uses slgen;`)');
    instLit := AllocNode(AN_INT_LIT); ASTIVal[instLit] := ProcGenInstSize[gpi]; ASTTk[instLit] := Ord(tyInt64);
    callAlloc := GenMakeCall6(FindProc('SlAlloc'), tyPointer, instLit, nargsLit, a0, a1, a2, a3);
    assignG := GenMakeAssign(GenMakeIdent(gIdx, tyPointer), callAlloc);

    { advance = a direct call to the step function with the instance pointer.
      The step proc's ABI is (self + the declared params); only self is real (the
      declared params are restored from the instance), but the call must provide
      one arg per param — the internal-call codegen pops ParamCount registers, so
      a short arg list would unbalance the stack. Pad with zeros. }
    sa1 := -1; sa2 := -1; sa3 := -1; sa4 := -1;
    if ProcGenParamCnt[gpi] >= 1 then sa1 := GenZeroLit;
    if ProcGenParamCnt[gpi] >= 2 then sa2 := GenZeroLit;
    if ProcGenParamCnt[gpi] >= 3 then sa3 := GenZeroLit;
    if ProcGenParamCnt[gpi] >= 4 then sa4 := GenZeroLit;
    callNext := GenMakeCall6(gpi, tyBoolean, GenMakeIdent(gIdx, tyPointer), sa1, sa2, sa3, sa4, -1);
    callCur := GenMakeCall6(FindProc('SlCurrent'), tyInt64, GenMakeIdent(gIdx, tyPointer), -1, -1, -1, -1, -1);
    assignX := GenMakeAssign(GenMakeIdent(varIdx, Syms[varIdx].TypeKind), callCur);

    innerSeq := GenMakeSeq(assignX, GenMakeSeq(bodyNode, -1));
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
var pri, fIdx, i, fnode: Integer; mname: AnsiString;
begin
  pri := FindUProp(enumIdx, 'Current');
  if pri >= 0 then
  begin
    if UPropReadMLen[pri] > 0 then
    begin
      mname := '';
      for i := 0 to UPropReadMLen[pri] - 1 do AppendChar(mname, TokChars[UPropReadMOff[pri] + i]);
      Result := GenMakeMethodCall0(GenMakeIdent(eSym, tyClass), enumIdx, mname);
      Exit;
    end
    else if UPropReadFLen[pri] > 0 then
    begin
      fnode := AllocNode(AN_FIELD);
      ASTLeft[fnode] := GenMakeIdent(eSym, tyClass);
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
  ASTLeft[fnode] := GenMakeIdent(eSym, tyClass);
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
  contTk: TTypeKind;
begin
  Expect(tkDo, 'do');
  bodyNode := ParseStatementAST;

  contTk := Syms[contSym].TypeKind;
  gepi := UMthProc_[FindUMeth(contClassIdx, 'GetEnumerator')];
  enumRec := ProcRetRecId[gepi];
  if enumRec < REC_UCLASS_BASE then Error('for-in: GetEnumerator must return a class/record');
  enumIdx := enumRec - REC_UCLASS_BASE;

  eSym := AllocVar('', tyClass);
  Syms[eSym].RecName := enumRec;

  geCall := GenMakeMethodCall0(GenMakeIdent(contSym, contTk), contClassIdx, 'GetEnumerator');
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
    while X <= hi do begin if X in S then BODY; X := X + 1; end;
  X (the loop var) doubles as the scan ordinal. Range from the set element type:
  `set of <enum>` → 0..count-1; `set of Char` → 0..255. }
function ParseForInSetAST(varIdx, setSym: Integer): Integer;
var
  bodyNode, loV, hiV, vtk, oSym, isChar: Integer;
  initN, scanCond, condIn, pairN, ifN, incN, innerSeq, whileN: Integer;
  valNode, assignE, chrArg: Integer;
begin
  Expect(tkDo, 'do');
  bodyNode := ParseStatementAST;

  isChar := 0;
  if SymSetEnumId[setSym] >= 0 then
  begin loV := 0; hiV := EnumTypeValCount[SymSetEnumId[setSym]] - 1; end
  else if SymSetElemTk[setSym] = Ord(tyChar) then
  begin loV := 0; hiV := 255; isChar := 1; end
  else
    Error('for-in: set iteration supports `set of <enum>` or `set of Char` only');

  { Scan with a separate Integer ordinal so the `<= hi` test cannot wrap on a
    narrow loop var (a Char counter overflows 255 -> 0 and loops forever). }
  oSym := AllocVar('', tyInteger);
  vtk := Ord(Syms[varIdx].TypeKind);
  initN := GenMakeAssign(GenMakeIdent(oSym, tyInteger), GenMakeIntLit(loV));
  scanCond := GenMakeBinop(tkLe, GenMakeIdent(oSym, tyInteger), GenMakeIntLit(hiV), tyBoolean);

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

  condIn := GenMakeBinop(tkIn, GenMakeIdent(oSym, tyInteger),
                         GenMakeIdent(setSym, tySet), tyBoolean);
  ifN := AllocNode(AN_IF);
  ASTLeft[ifN] := condIn;
  pairN := AllocNode(AN_PAIR);
  ASTLeft[pairN] := bodyNode;
  ASTRight[pairN] := -1;
  ASTRight[ifN] := pairN;

  incN := GenMakeAssign(GenMakeIdent(oSym, tyInteger),
    GenMakeBinop(tkPlus, GenMakeIdent(oSym, tyInteger), GenMakeIntLit(1), tyInteger));
  innerSeq := GenMakeSeq(assignE, GenMakeSeq(ifN, GenMakeSeq(incN, -1)));
  whileN := AllocNode(AN_WHILE);
  ASTLeft[whileN] := scanCond;
  ASTRight[whileN] := innerSeq;
  Result := GenMakeSeq(initN, GenMakeSeq(whileN, -1));
end;

{ for x in <string|static array|dynarray|open-array var> do BODY:
    __i := lo;
    while __i <= hi do begin x := C[__i]; BODY; __i := __i + 1; end;
  lo/hi pick the right base: strings 1..Length, arrays 0..count-1.
  A class/record container with GetEnumerator routes to the enumerator desugar;
  a set var routes to the membership-scan desugar. }
function ParseForInVarAST(varIdx, contSym: Integer): Integer;
var
  bodyNode, idxSym, loNode, hiNode, elemTk: Integer;
  condNode, elemAccess, assignX, incNode, whileNode, innerSeq, initI: Integer;
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
  if (not ((Syms[contSym].TypeKind = tyString) or (Syms[contSym].TypeKind = tyAnsiString)))
     and (not Syms[contSym].IsArray) and (recId >= REC_UCLASS_BASE)
     and (FindUMeth(recId - REC_UCLASS_BASE, 'GetEnumerator') >= 0) then
  begin
    Result := ParseForInEnumeratorAST(varIdx, contSym, recId - REC_UCLASS_BASE);
    Exit;
  end;

  Expect(tkDo, 'do');
  bodyNode := ParseStatementAST;

  contTk := Syms[contSym].TypeKind;
  { A real string container is a non-array string var. For `array of String` /
    `array of AnsiString` the var's TypeKind is the element base type
    (tyAnsiString), so the array check MUST win — otherwise it is mis-iterated
    char-by-char. }
  isString := (not Syms[contSym].IsArray) and ((contTk = tyString) or (contTk = tyAnsiString));
  isStaticArr := Syms[contSym].IsArray and (Syms[contSym].ArrLen >= 0);
  idxSym := AllocVar('', tyInteger);

  if isString then
  begin
    loNode := GenMakeIntLit(1);
    elemTk := Ord(tyChar);
  end
  else if Syms[contSym].IsArray then
  begin
    loNode := GenMakeIntLit(0);
    elemTk := Ord(Syms[contSym].ElemType);
  end
  else
    Error('for-in: variable is not a string or array');

  initI := GenMakeAssign(GenMakeIdent(idxSym, tyInteger), loNode);

  if isStaticArr then
    hiNode := GenMakeIntLit(Syms[contSym].ArrLen - 1)
  else if isString then
    hiNode := GenMakeLengthCall(contSym, contTk)
  else
    hiNode := GenMakeBinop(tkMinus, GenMakeLengthCall(contSym, contTk),
                           GenMakeIntLit(1), tyInteger);

  condNode := GenMakeBinop(tkLe, GenMakeIdent(idxSym, tyInteger), hiNode, tyBoolean);

  elemAccess := AllocNode(AN_INDEX);
  ASTLeft[elemAccess] := GenMakeIdent(contSym, contTk);
  ASTRight[elemAccess] := GenMakeIdent(idxSym, tyInteger);
  ASTTk[elemAccess] := elemTk;
  assignX := GenMakeAssign(GenMakeIdent(varIdx, Syms[varIdx].TypeKind), elemAccess);

  incNode := GenMakeAssign(GenMakeIdent(idxSym, tyInteger),
    GenMakeBinop(tkPlus, GenMakeIdent(idxSym, tyInteger), GenMakeIntLit(1), tyInteger));

  innerSeq := GenMakeSeq(assignX, GenMakeSeq(bodyNode, GenMakeSeq(incNode, -1)));
  whileNode := AllocNode(AN_WHILE);
  ASTLeft[whileNode] := condNode;
  ASTRight[whileNode] := innerSeq;

  Result := GenMakeSeq(initI, GenMakeSeq(whileNode, -1));
end;

{ for x in <EnumType> do BODY iterates ALL enum ordinals low..high. The loop
  variable itself holds the ordinal (enum vars are integer-sized), so no separate
  index is needed:  x := 0; while x <= count-1 do begin BODY; x := x + 1; end; }
function ParseForInEnumTypeAST(varIdx, etid: Integer): Integer;
var
  bodyNode, initN, condN, incN, whileN, innerSeq: Integer;
  cnt, vtk: Integer;
begin
  Expect(tkDo, 'do');
  bodyNode := ParseStatementAST;

  cnt := EnumTypeValCount[etid];
  vtk := Ord(Syms[varIdx].TypeKind);
  initN := GenMakeAssign(GenMakeIdent(varIdx, IntToTypeKind(vtk)), GenMakeIntLit(0));
  condN := GenMakeBinop(tkLe, GenMakeIdent(varIdx, IntToTypeKind(vtk)),
                        GenMakeIntLit(cnt - 1), tyBoolean);
  incN := GenMakeAssign(GenMakeIdent(varIdx, IntToTypeKind(vtk)),
    GenMakeBinop(tkPlus, GenMakeIdent(varIdx, IntToTypeKind(vtk)),
                 GenMakeIntLit(1), tyInteger));
  innerSeq := GenMakeSeq(bodyNode, GenMakeSeq(incN, -1));
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
    else
      if SLHasYield(node) then
        Error('stackless generator: yield only allowed at top level or inside for/while/if (not in this construct)');
  end;
end;

{ Build a sequence of SlSet(self, slotOff, localValue) for every persistent slot
  allocated so far — called at each yield to checkpoint live locals. }
function SLSaveLocals(selfSym: Integer): Integer;
var i, head, tail, stmt: Integer;
begin
  head := -1; tail := -1;
  for i := CurGenScopeBase to SymCount - 1 do
    if SymGenSlot[i] >= 0 then
    begin
      stmt := GenSlSetStmt(selfSym, SL_OFF_SLOTS + 8 * SymGenSlot[i],
                           GenMakeIdent(i, Syms[i].TypeKind));
      if head < 0 then begin head := GenMakeSeq(stmt, -1); tail := head; end
      else begin ASTRight[tail] := GenMakeSeq(stmt, -1); tail := ASTRight[tail]; end;
    end;
  Result := head;
end;

{ Build assignments restoring every persistent slot into its local at step entry. }
function SLRestoreLocals(selfSym: Integer): Integer;
var i, head, tail, stmt: Integer;
begin
  head := -1; tail := -1;
  for i := CurGenScopeBase to SymCount - 1 do
    if SymGenSlot[i] >= 0 then
    begin
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

{ yield E -> current:=E; state:=k; save locals; Result:=True; Exit; Lk: }
function SLLowerYield(node, selfSym, retSym: Integer): Integer;
var k, resumeLbl, setCur, setState, saveSeq, setRes, exitNode: Integer;
begin
  k := CurGenStateCtr; Inc(CurGenStateCtr);
  if k >= MAX_GEN_STATES then Error('stackless generator: too many yields');
  resumeLbl := NewSyntheticLabel;
  GenStateLabelIdx[k] := resumeLbl;

  setCur   := GenSlSetStmt(selfSym, SL_OFF_CURRENT, ASTLeft[node]);
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

function SLLowerWhile(node, selfSym, retSym: Integer): Integer;
var cond, body, topLbl, endLbl, test, bodyLo: Integer;
begin
  cond := ASTLeft[node];
  body := ASTRight[node];
  topLbl := NewSyntheticLabel;
  endLbl := NewSyntheticLabel;
  test := GenMakeIfGoto(GenMakeCmp(Ord(tkEq), cond, GenMakeBoolLit(0)), endLbl);
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
    limSym, topLbl, endLbl: Integer;
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

  setVar := GenMakeAssign(GenMakeIdent(varSym, vTk), initN);
  setLim := GenMakeAssign(GenMakeIdent(limSym, tyInt64), limitN);

  if isDown <> 0 then cmpOp := Ord(tkLt) else cmpOp := Ord(tkGt);
  { ascending: exit when var > limit; descending: exit when var < limit }
  test := GenMakeIfGoto(
            GenMakeCmp(cmpOp, GenMakeIdent(varSym, vTk), GenMakeIdent(limSym, tyInt64)),
            endLbl);

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
            GenMakeSeq(incN,
            GenMakeSeq(GenMakeGoto(topLbl),
            GenMakeSeq(GenMakeLabel(endLbl), -1))))))));
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
    else      Error('stackless generator: unsupported construct around yield');
  end;
end;

{ Build the full step-function body AST for a stackless generator proc `pi`.
  Persistent slots for the declared params + body locals must already be assigned
  (SymGenSlot). Returns the AST to CompileAST; sets CurGenSlotNext to its final
  value (caller derives ProcGenInstSize). }
function BuildStacklessStep(bodyAST, pi: Integer): Integer;
var selfSym, retSym, bodyLo, dispatch, dtail, restore: Integer;
    setDone, setRes, k, stmt: Integer;
begin
  if (FindProc('SlGet') < 0) or (FindProc('SlSet') < 0) then
    Error('stackless generator: the slgen unit is not in scope (add `uses slgen;`)');
  selfSym := Procs[pi].Params[0].SymIdx;
  retSym  := Procs[pi].RetSymIdx;

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
procedure AssignStacklessSlots(pi: Integer);
var i, selfS, retS: Integer; tk: TTypeKind;
begin
  selfS := Procs[pi].Params[0].SymIdx;
  retS  := Procs[pi].RetSymIdx;
  CurGenSlotNext := 0;
  CurGenScopeBase := Procs[pi].ScopeBase;
  for i := Procs[pi].ScopeBase to SymCount - 1 do
  begin
    if (i = selfS) or (i = retS) then Continue;
    if (Syms[i].Kind <> skParam) and (Syms[i].Kind <> skLocal) then Continue;
    tk := Syms[i].TypeKind;
    if Syms[i].IsArray or Syms[i].IsRef or
       (tk = tyString) or (tk = tyAnsiString) or (tk = tyRecord) or
       (tk = tySet) or (tk = tyVariant) then
      Error('stackless generator: only ordinal/pointer locals are supported (v1)');
    SymGenSlot[i] := CurGenSlotNext;
    Inc(CurGenSlotNext);
  end;
end;

function ParseForStatementAST: Integer;
var
  varIdx, initNode, limitNode, bodyNode, node: Integer;
  pair1, pair2, pair3, isDownNode: Integer;
  gpi, fsym: Integer;
  down: Boolean;
begin
  if CurTok.Kind <> tkIdent then Error('for: expected variable');
  varIdx := FindSym(CurTok.SVal);
  if varIdx < 0 then Error('for: undefined');
  Next;
  if CurTok.Kind = tkIn then
  begin
    Next;
    if CurTok.Kind <> tkIdent then Error('for-in: expected a generator, enum type, or iterable variable');
    { generator call → existing coroutine/stackless desugar }
    gpi := FindProc(CurTok.SVal);
    if (gpi >= 0) and ProcIsGenerator[gpi] then
    begin
      Next;
      Result := ParseForInGeneratorAST(varIdx, gpi);
      Exit;
    end;
    { enum type name → iterate all ordinals }
    fsym := FindEnumType(CurTok.SVal);
    if fsym >= 0 then
    begin
      Next;
      Result := ParseForInEnumTypeAST(varIdx, fsym);
      Exit;
    end;
    { iterable variable (string / array / dynarray / open-array param) }
    fsym := FindSym(CurTok.SVal);
    if fsym >= 0 then
    begin
      Next;
      Result := ParseForInVarAST(varIdx, fsym);
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

function ParseCaseStatementAST: Integer;
var
  condNode, branchSeq, lastBranch, branchPair, labelsHead, lastLabel, labelValNode: Integer;
  stmtNode, node, si, hiNode: Integer;
  hasElse: Boolean;
  cv, cvHi: Int64;
begin
  ParseExpr; condNode := CurASTNode;
  Expect(tkOf, 'of');

  branchSeq := AllocNode(AN_SEQ);
  lastBranch := branchSeq;
  hasElse := False;

  while (not (CurTok.Kind in [tkEnd, tkEOF])) and not hasElse do
  begin
    if CurTok.Kind = tkElse then
    begin
      hasElse := True;
      Next;
      stmtNode := ParseStatementAST;
      Eat(tkSemicolon);

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
        if CurTok.Kind = tkInteger then cv := CurTok.IVal
        else if CurTok.Kind = tkString then
        begin
          if Length(CurTok.SVal) = 0 then Error('case string label must not be empty');
          cv := Ord(CurTok.SVal[1]);
        end
        else if CurTok.Kind = tkIdent then
        begin
          si := FindSym(CurTok.SVal);
          if (si >= 0) and (Syms[si].Kind = skConst) then cv := Syms[si].ConstVal
          else Error('case label must be constant');
        end
        else Error('expected case label');
        Next;

        labelValNode := AllocNode(AN_INT_LIT);
        ASTIVal[labelValNode] := cv;

        { Range label `lo..hi`: stash hi in a second AN_INT_LIT hung off
          ASTRight of the value node; the IR lowering reads it as a [lo,hi]
          inclusive range test instead of a single equality. }
        if Eat(tkDotDot) then
        begin
          if CurTok.Kind = tkInteger then cvHi := CurTok.IVal
          else if CurTok.Kind = tkString then
          begin
            if Length(CurTok.SVal) = 0 then Error('case string label must not be empty');
            cvHi := Ord(CurTok.SVal[1]);
          end
          else if CurTok.Kind = tkIdent then
          begin
            si := FindSym(CurTok.SVal);
            if (si >= 0) and (Syms[si].Kind = skConst) then cvHi := Syms[si].ConstVal
            else Error('case range upper bound must be constant');
          end
          else Error('expected case range upper bound');
          Next;
          hiNode := AllocNode(AN_INT_LIT);
          ASTIVal[hiNode] := cvHi;
          ASTRight[labelValNode] := hiNode;
        end;

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

function ParseReadArgsAST(isLn: Boolean): Integer;
{ readln/read(target, ...): each target is an lvalue (ident/field/index). The
  args are kept as an AN_ARG chain; IR lowering takes each one's address and
  parses a value from the line buffer by the target's type. }
var node, argNode, lastArg: Integer;
begin
  node := AllocNode(AN_READLN);
  if not isLn then ASTKind[node] := AN_READ;
  ASTLeft[node] := -1;
  if CurTok.Kind = tkLParen then
  begin
    Next;
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
    lastArg := -1;
    if CurTok.Kind = tkIdent then
    begin
      vidx := FindSym(CurTok.SVal);
      if (vidx >= 0) and (Syms[vidx].Kind = skConst) and (Syms[vidx].TypeKind = tyInteger) and (Syms[vidx].Name = 'StdErr') then
      begin
        Next; Eat(tkComma);
      end;
    end;
    repeat
      ParseExpr; exprNode := CurASTNode;
      argNode := AllocNode(AN_ARG);
      ASTLeft[argNode] := exprNode;
      { Parse optional :width[:decimals] format specifiers }
      widthVal := 0; decimalsVal := -1;
      if CurTok.Kind = tkColon then
      begin
        Next;
        if CurTok.Kind <> tkInteger then Error('write: expected integer width after :');
        widthVal := CurTok.IVal; Next;
        if CurTok.Kind = tkColon then
        begin
          Next;
          if CurTok.Kind <> tkInteger then Error('write: expected integer decimals after :');
          decimalsVal := CurTok.IVal; Next;
        end;
      end;
      ASTIVal[argNode] := widthVal;
      ASTSOffset[argNode] := decimalsVal;
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
  seqNode, lastSeq, stmtNode, savedBlockId: Integer;
begin
  savedBlockId := CurBlockId;
  if EnableLazyVar then
  begin
    if BlockCount >= 8191 then Error('too many blocks');
    Inc(BlockCount);
    BlockParent[BlockCount] := CurBlockId;
    CurBlockId := BlockCount;
  end;

  seqNode := AllocNode(AN_SEQ);
  lastSeq := seqNode;
  while not (CurTok.Kind in [tkEnd, tkEOF, tkUntil]) do
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
        Expect(tkColon, ':');
        if CurTok.Kind <> tkIdent then Error('on: expected class type');
        className := CurTok.SVal;
        ci := FindUClass(className);
        if ci < 0 then Error('on: unknown exception class');
        recId := REC_UCLASS_BASE + ci;
        Next;
        Expect(tkDo, 'do');
        handlerVar := AllocVar(handlerName, tyClass);
        Syms[handlerVar].RecName := recId;
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
  varNode, bodyNode: Integer;
begin
  ParseExpr;
  varNode := CurASTNode;

  if Eat(tkComma) then
  begin
    { Push with variable }
    WithStack[WithStackDepth] := varNode;
    Inc(WithStackDepth);

    bodyNode := ParseWithStatementAST;

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
        arrLo := ConstEval;
        Expect(tkDotDot, '..');
        arrHi := ConstEval;
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
    if isArr then
    begin
      Syms[idx].IsArray := True;
      Syms[idx].ArrLen := arrHi - arrLo + 1;
    end;
    
    if Syms[idx].TypeKind = tyAuto then
    begin
      if ASTKind[valueNode] = AN_DEFAULT then
        Error('cannot infer type from default; specify type explicitly');
      if (LastExprTk = tyUnknown) or (LastExprTk = tyAuto) then
        Error('cannot infer type for auto variable');
      InferSymTypeFromNode(idx, valueNode);
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
      if isArr then
      begin
        Syms[idx].IsArray := True;
        Syms[idx].ArrLen := arrHi - arrLo + 1;
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

function ParseStatementAST: Integer;
var
  name: AnsiString;
   idx, pi, i, si, node, valNode, stepsNode, opNode, argSeq, argIdx, exprNode, lastArg, identTokIdx: Integer;
  nArgs, argsHead, currArg: Integer; argTypes: array[0..15] of TTypeKind;
  isLn, slIsArrTarget: Boolean;
  smci, smmii, smpii, smcallNode, smselfArg, smLastArg, smArgSeq, smMai, smSelfIdx: Integer;
  aliasIdx, fieldNode, indexNode, castPrevTok, qUnit: Integer;
  castFieldName: AnsiString; castTk: TTypeKind; castRec: Integer;
  decVal, decNode: Integer; strIsFloat: Boolean;
begin
  node := -1;
  case CurTok.Kind of
    tkVar:
    begin
      if not EnableLazyVar then Error('Lazy Variable Declarations are disabled; use --lazy-var to enable');
      Next;
      node := ParseLazyVarDeclAST;
    end;

    tkwriteln, tkwrite:
    begin
      isLn := CurTok.Kind = tkwriteln; Next;
      node := ParsewriteArgsAST(isLn);
    end;

    tkReadln, tkRead:
    begin
      isLn := CurTok.Kind = tkReadln; Next;
      node := ParseReadArgsAST(isLn);
    end;

    tkHalt, tkExit:
    begin
      idx := Ord(CurTok.Kind); Next;
      if idx = Ord(tkHalt) then
        node := AllocNode(AN_HALT)
      else
        node := AllocNode(AN_EXIT);

      if CurTok.Kind = tkLParen then
      begin
        Next; ParseExpr; Expect(tkRParen, ')');
        ASTLeft[node] := CurASTNode;
      end;
    end;

    tkBreak:
    begin
      Next;
      node := AllocNode(AN_BREAK);
    end;

    tkContinue:
    begin
      Next;
      node := AllocNode(AN_CONTINUE);
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
      end;
      node := AllocNode(AN_RAISE);
      ASTLeft[node] := valNode;
    end;

    tkInc, tkDec:
    begin
      idx := Ord(CurTok.Kind); Next;
      Expect(tkLParen, '(');
      if CurTok.Kind <> tkIdent then Error('expected variable');
      argIdx := FindSym(CurTok.SVal); identTokIdx := TokPos - 1; Next;
      if argIdx < 0 then Error('undefined');

      if Eat(tkComma) then
      begin
        ParseExpr; stepsNode := CurASTNode;
      end
      else
      begin
        stepsNode := AllocNode(AN_INT_LIT);
        ASTIVal[stepsNode] := 1;
      end;
      Expect(tkRParen, ')');

      valNode := ParseLValueAST(argIdx, identTokIdx);
      opNode := AllocNode(AN_BINOP);
      if idx = Ord(tkInc) then ASTIVal[opNode] := Ord(tkPlus) else ASTIVal[opNode] := Ord(tkMinus);
      ASTLeft[opNode] := valNode;
      ASTRight[opNode] := stepsNode;

      node := AllocNode(AN_ASSIGN);
      ASTLeft[node] := valNode;
      ASTRight[node] := opNode;
    end;

    tkFreeMem:
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
    end;

    tkGetMem:
    begin
      { Two-argument procedure form GetMem(dest, size): allocate `size` bytes and
        store the pointer into the lvalue `dest`. (The function form
        `p := GetMem(size)` is handled in ParseFactor.) Without this, a bare
        GetMem statement fell through to the default branch and was discarded —
        the destination was never written. }
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
      if (argIdx < 0) or (Syms[argIdx].TypeKind <> tyString) then Error('ArgStr: not a string var');
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
      { Label definition: 'labelname:' as a statement }
      if Tokens[TokPos].Kind = tkColon then
      begin
        node := AllocNode(AN_LABEL);
        ASTSOffset[node] := Tokens[TokPos-1].SOffset;
        ASTSLen[node]    := Tokens[TokPos-1].SLen;
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
          Error('yield outside a generator');
        if GenTryDepth > 0 then
          Error('yield inside try/except/finally is not allowed (v1)');
        Next;
        ParseExpr;
        node := AllocNode(AN_YIELD);
        ASTLeft[node] := CurASTNode;
        ASTIVal[node] := CurGenSelfSym;
        CurGenSeenYield := True;
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
          ASTLeft[node] := ParseStatementAST;
        ASTTk[node]   := Ord(tyUnknown);
      end
      else if CaseEqual(name, 'AsyncGo') then
      begin
        { Spawn a `; async; stackless;` coroutine onto the stackless scheduler.
          AsyncGo(@Body) desugars to SLSpawn(@Body, SlAlloc(instSize,0,0,0,0,0)):
          the compiler supplies the step fn (the rewritten Body) and a zero-inited
          heap instance; the scheduler resumes it via an indirect (proc-typed)
          call (SLRunUntilDone). v1: the routine takes no params. }
        Next;
        Expect(tkLParen, '(');
        Expect(tkAt, '@');
        if CurTok.Kind <> tkIdent then Error('AsyncGo: expected @<an async stackless routine>');
        pi := FindProc(CurTok.SVal);
        if (pi < 0) or not ProcIsAsync[pi] or not ProcIsStackless[pi] then
          Error('AsyncGo: argument must be @<an `; async; stackless;` routine>');
        Next;
        Expect(tkRParen, ')');
        if (FindProc('SLSpawn') < 0) or (FindProc('SlAlloc') < 0) then
          Error('AsyncGo: slsched/slgen not in scope (add `uses slgen, slsched;`)');
        idx := AllocNode(AN_PROCADDR); ASTIVal[idx] := pi; ASTTk[idx] := Ord(tyPointer);
        valNode := AllocNode(AN_INT_LIT); ASTIVal[valNode] := ProcGenInstSize[pi]; ASTTk[valNode] := Ord(tyInt64);
        node := GenMakeCall6(FindProc('SLSpawn'), tyPointer, idx,
                  GenMakeCall6(FindProc('SlAlloc'), tyPointer, valNode,
                    GenZeroLit, GenZeroLit, GenZeroLit, GenZeroLit, GenZeroLit),
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
      else if (name = 'LoadFile') or (name = 'loadfile') then
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
      else if (name = 'SetLength') or (name = 'setlength') then
      begin
        Next; Expect(tkLParen, '(');
        if CurTok.Kind <> tkIdent then Error('SetLength: expected string or array variable');
        idx := FindSym(CurTok.SVal); identTokIdx := TokPos - 1; Next;
        valNode := ParseLValueAST(idx, identTokIdx);
        Expect(tkComma, ',');

        ParseExpr; Expect(tkRParen, ')');

        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := valNode;
        ASTRight[argSeq] := AllocNode(AN_ARG);
        ASTLeft[ASTRight[argSeq]] := CurASTNode;

        node := AllocNode(AN_CALL);
        { -101 = string SetLength; -102 = dynamic-array (and managed AnsiString)
          SetLength (heap alloc). Classify from the resolved lvalue, not the
          base symbol: `SetLength(obj.field, n)` resolves `idx` to the object,
          so a dynamic-array field would otherwise be misrouted to the string
          path. }
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
        if slIsArrTarget then
          ASTIVal[node] := -102
        else
          ASTIVal[node] := -101;
        ASTLeft[node] := argSeq;
      end
      else if (name = 'New') or (name = 'new') then
      begin
        { New(p): allocate SizeOf(p^) and store the block into the pointer p.
          Equivalent to p := GetMem(SizeOf(p^)); size comes from p's element
          type. }
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
      else if (name = 'Dispose') or (name = 'dispose') then
      begin
        { Dispose(p): return the block to the free list (= FreeMem(p)). }
        Next; Expect(tkLParen, '(');
        ParseExpr; valNode := CurASTNode;
        Expect(tkRParen, ')');
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := valNode;
        node := AllocNode(AN_CALL);
        ASTIVal[node] := -Ord(tkFreeMem);
        ASTLeft[node] := argSeq; ASTTk[node] := Ord(tyInteger);
      end
      else if (name = 'ReallocMem') or (name = 'reallocmem') then
      begin
        { ReallocMem(p, newsize): resize the block p points at, preserving
          min(oldsize, newsize) bytes, and store the new pointer back into p.
          Old size comes from the block's header; old block is freed. Modelled
          as p := <realloc>(p, newsize) (special id -103). p must be a simple
          pointer variable. }
        Next; Expect(tkLParen, '(');
        if CurTok.Kind <> tkIdent then Error('ReallocMem: expected pointer variable');
        idx := FindSym(CurTok.SVal); identTokIdx := TokPos - 1; Next;
        valNode := ParseLValueAST(idx, identTokIdx);   { assign target }
        Expect(tkComma, ',');
        ParseExpr;                                      { new size -> CurASTNode }
        Expect(tkRParen, ')');

        exprNode := AllocNode(AN_IDENT);                { old pointer value }
        ASTIVal[exprNode] := idx; ASTTk[exprNode] := Ord(tyPointer);
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := exprNode;
        ASTRight[argSeq] := AllocNode(AN_ARG);
        ASTLeft[ASTRight[argSeq]] := CurASTNode;        { new size }

        opNode := AllocNode(AN_CALL);
        ASTIVal[opNode] := -103;
        ASTLeft[opNode] := argSeq; ASTTk[opNode] := Ord(tyPointer);
        node := AllocNode(AN_ASSIGN);
        ASTLeft[node] := valNode; ASTRight[node] := opNode;
      end
      else if (name = 'Str') or (name = 'str') then
      begin
        { Str(x[:w[:d]], s): format integer x into string s, right-justified to
          width w. Parsed like write's value:w:d (literal width/decimals;
          decimals ignored for integer Str). Rewritten to s := StrInt(x, w),
          which lives in the auto-included builtin unit. }
        Next; Expect(tkLParen, '(');
        ParseExpr; exprNode := CurASTNode;        { value }
        castPrevTok := 0;                          { width default }
        decVal := -1;                              { decimals: -1 = none (natural for float) }
        if CurTok.Kind = tkColon then
        begin
          Next;
          if CurTok.Kind <> tkInteger then Error('Str: expected integer width after :');
          castPrevTok := CurTok.IVal; Next;
          if CurTok.Kind = tkColon then
          begin
            Next;
            if CurTok.Kind <> tkInteger then Error('Str: expected integer decimals after :');
            decVal := CurTok.IVal; Next;
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
        if strIsFloat then pi := FindProc('StrFloat') else pi := FindProc('StrInt');
        if pi < 0 then Error('Str: builtin unit not loaded');
        stepsNode := AllocNode(AN_INT_LIT);
        ASTIVal[stepsNode] := castPrevTok; ASTTk[stepsNode] := Ord(tyInteger);
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := exprNode;
        ASTRight[argSeq] := AllocNode(AN_ARG);
        ASTLeft[ASTRight[argSeq]] := stepsNode;
        if strIsFloat then
        begin
          { third arg: decimals }
          decNode := AllocNode(AN_INT_LIT);
          ASTIVal[decNode] := decVal; ASTTk[decNode] := Ord(tyInteger);
          ASTRight[ASTRight[argSeq]] := AllocNode(AN_ARG);
          ASTLeft[ASTRight[ASTRight[argSeq]]] := decNode;
        end;
        opNode := AllocNode(AN_CALL);
        ASTIVal[opNode] := pi; ASTLeft[opNode] := argSeq; ASTTk[opNode] := Ord(tyString);
        node := AllocNode(AN_ASSIGN);
        ASTLeft[node] := valNode; ASTRight[node] := opNode;
      end
      else if ((name = 'Val') or (name = 'val')) and (Tokens[TokPos].Kind = tkLParen) then
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
        Expect(tkComma, ',');
        if CurTok.Kind <> tkIdent then Error('Val: expected code variable');
        si := FindSym(CurTok.SVal); argIdx := TokPos - 1; Next;
        stepsNode := ParseLValueAST(si, argIdx);            { code }
        Expect(tkRParen, ')');

        if (idx >= 0) and TypeIsFloat(Syms[idx].TypeKind) then pi := FindProc('ValFloat')
        else pi := FindProc('Val');
        if pi < 0 then Error('Val: builtin unit not loaded');
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := exprNode;
        lastArg := AllocNode(AN_ARG); ASTLeft[lastArg] := valNode; ASTRight[argSeq] := lastArg;
        opNode := AllocNode(AN_ARG); ASTLeft[opNode] := stepsNode; ASTRight[lastArg] := opNode;
        node := AllocNode(AN_CALL);
        ASTIVal[node] := pi; ASTLeft[node] := argSeq; ASTTk[node] := Ord(Procs[pi].RetType);
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
        if CurTok.Kind <> tkIdent then Error('expected label name after goto');
        node := AllocNode(AN_GOTO);
        ASTSOffset[node] := Tokens[TokPos-1].SOffset;
        ASTSLen[node]    := Tokens[TokPos-1].SLen;
        Next;
      end
      else
      begin
        if qUnit >= 0 then
          pi := FindProcInUnit(name, qUnit)
        else
          pi := FindProc(name);
        if (pi >= 0) and (Tokens[TokPos].Kind = tkLParen) then
        begin
          Next;
          Expect(tkLParen, '(');
          argsHead := -1;
          lastArg := -1;
          nArgs := 0;
          while CurTok.Kind <> tkRParen do
          begin
            if (CurTok.Kind = tkLBrack) and ParamIsVarRecArray(pi, nArgs) then
              CurASTNode := ParseVarRecLiteralAST
            else
              ParseExpr;
            argSeq := AllocNode(AN_ARG);
            ASTLeft[argSeq] := CurASTNode;
            if argsHead = -1 then
              argsHead := argSeq
            else
              ASTRight[lastArg] := argSeq;
            lastArg := argSeq;
            Inc(nArgs);
            if CurTok.Kind = tkComma then
              Next
            else if CurTok.Kind <> tkRParen then
              Error('expected comma or close parenthesis');
          end;
          Expect(tkRParen, ')');

          currArg := argsHead;
          for i := 0 to nArgs - 1 do
          begin
            exprNode := ASTLeft[currArg];
            argTypes[i] := IntToTypeKind(ASTTk[exprNode]);
            currArg := ASTRight[currArg];
          end;

          if qUnit >= 0 then
            pi := MatchProcCallInUnit(name, qUnit, nArgs, argTypes)
          else
            pi := MatchProcCall(name, nArgs, argTypes);
          if pi < 0 then
            Error('no overload of ' + name + ' matches these arguments');

          currArg := argsHead;
          for i := 0 to nArgs - 1 do
          begin
            exprNode := ASTLeft[currArg];
            if (Procs[pi].Params[i].TypeKind = tyString) and (IntToTypeKind(ASTTk[exprNode]) = tyChar) then
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
            if (Procs[pi].Params[i].IsRef or Procs[pi].Params[i].IsArray) and
               (ASTKind[exprNode] <> AN_VARREC_ARRAY) then
            begin
              if not ((ASTKind[exprNode] = AN_IDENT) or (ASTKind[exprNode] = AN_INDEX) or (ASTKind[exprNode] = AN_FIELD)) then
                Error('by-reference argument must be a variable');
            end;
            currArg := ASTRight[currArg];
          end;

          node := AllocNode(AN_CALL);
          ASTIVal[node] := pi;
          ASTLeft[node] := argsHead;
        end
        else if (pi >= 0) and (Procs[pi].ParamCount = 0) then
        begin
          Next;
          node := AllocNode(AN_CALL);
          ASTIVal[node] := pi;
        end;

        if node = -1 then
        begin
          { Implicit Self.method dispatch for methods called bare inside a class body }
          if CurSelfClass >= REC_UCLASS_BASE then
          begin
            smci := CurSelfClass - REC_UCLASS_BASE;
            smmii := FindUMeth(smci, name);
            if smmii >= 0 then
            begin
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
                idx := FindSym(name);
              Next;
              valNode := ParseLValueAST(idx, TokPos - 2);
              if (ASTKind[valNode] = AN_CALL) or (ASTKind[valNode] = AN_VIRTUAL_CALL) or
                 (ASTKind[valNode] = AN_INTF_CALL) then
                node := valNode
              else
              begin
                Expect(tkAssign, ':=');
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
                node := AllocNode(AN_ASSIGN);
                ASTLeft[node] := valNode;
                ASTRight[node] := CurASTNode;
              end;
            end;
          end;
        end;
      end;
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
  ASTNodeCount := 0;
end;

procedure ParseBlock;
var node: Integer;
begin
  node := ParseBlockAST;
  CompileAST(node);
  ASTNodeCount := 0;
end;

{ ===== Declaration parsing ===== }

function ParseTypeKind: TTypeKind;
var lo: AnsiString; elemTk: TTypeKind; aliasIdx, ci: Integer;
begin
  LastTypeRecId := REC_NONE;
  LastTypePointerElemTk := tyUnknown;
  LastTypePointerElemRec := REC_NONE;
  LastTypeProcSig := -1;
  LastTypeEnumId := -1;
  case CurTok.Kind of
    tkCaret:
    begin
      Next;
      elemTk := ParseTypeKind();
      LastTypePointerElemTk := elemTk;
      LastTypePointerElemRec := LastTypeRecId;
      Result := tyPointer;
      Exit;
    end;
    tkInteger_T:
    begin
      lo := CurTok.SVal;
      if CaseEqual(lo, 'shortint') then Result := tyInt8
      else if CaseEqual(lo, 'byte') then Result := tyUInt8
      else if CaseEqual(lo, 'smallint') then Result := tyInt16
      else if CaseEqual(lo, 'word') then Result := tyUInt16
      else if CaseEqual(lo, 'longint') then Result := tyInt32
      else if CaseEqual(lo, 'cardinal') then Result := tyUInt32
      else Result := tyInteger; { Integer }
    end;
    tkLongWord_T: Result := tyUInt32;
    tkBoolean_T: Result := tyBoolean;
    tkChar_T:    Result := tyChar;
    tkString_T:  Result := tyString;
    tkReal_T:     Result := tyDouble;
    tkSingle_T:   Result := tySingle;
    tkDouble_T:   Result := tyDouble;
    tkExtended_T: Result := tyExtended;
    else
    begin
      lo := CurTok.SVal;
      if CaseEqual(lo, 'set') then
      begin
        Next;
        Expect(tkOf, 'of');
        LastTypeEnumId := -1;
        if CurTok.Kind = tkInteger then
        begin
          { `set of <subrange>` e.g. `set of 1..10` — consume lo..hi (the element
            is an integer subrange). Without this the `..hi` leaked and the
            type-skip loop in ParseVarSection corrupted the variable's type away
            from tySet, so set ops/membership read garbage. }
          ConstEval;
          Expect(tkDotDot, '..');
          ConstEval;
          elemTk := tyInteger;
        end
        else
          elemTk := ParseTypeKind();
        { inline `set of TFoo`: the element parse records the enum identity in
          LastTypeEnumId; carry it as the set's element enum for RTTI. }
        LastTypeSetEnumId := LastTypeEnumId;
        LastTypeSetElemTk := Ord(elemTk);
        Result := tySet;
        Exit;
      end;
      if CaseEqual(lo, 'ansistring') then
      begin
        if PasDefineExists('PXX_MANAGED_STRING') then
          Result := tyAnsiString
        else
          Result := tyString;
      end
      else if CaseEqual(lo, 'real') then Result := tyDouble
      else if CaseEqual(lo, 'single') then Result := tySingle
      else if CaseEqual(lo, 'double') then Result := tyDouble
      else if CaseEqual(lo, 'extended') then Result := tyExtended
      else if CaseEqual(lo, 'shortint') then Result := tyInt8
      else if CaseEqual(lo, 'byte') then Result := tyUInt8
      else if CaseEqual(lo, 'smallint') then Result := tyInt16
      else if CaseEqual(lo, 'word') then Result := tyUInt16
      else if CaseEqual(lo, 'longint') then Result := tyInt32
      else if CaseEqual(lo, 'cardinal') or CaseEqual(lo, 'longword') then Result := tyUInt32
      else if CaseEqual(lo, 'int64') then Result := tyInt64
      else if CaseEqual(lo, 'qword') then Result := tyUInt64
      else if CaseEqual(lo, 'nativeint') or CaseEqual(lo, 'ptrint') then Result := tyNativeInt
      else if CaseEqual(lo, 'nativeuint') or CaseEqual(lo, 'ptruint') then Result := tyNativeUInt
      else if CaseEqual(lo, 'pointer') then Result := tyPointer
      else if CaseEqual(lo, 'pchar') or CaseEqual(lo, 'pansichar') then
      begin
        LastTypePointerElemTk := tyChar;
        Result := tyPointer;
      end
      else if CaseEqual(lo, 'variant') then Result := tyVariant
      else if EnableAutoVar and CaseEqual(lo, 'auto') then Result := tyAuto
      else
      begin
        ci := FindUClass(lo);
        if (ci >= 0) and UClsIsInterface[ci] then
        begin
          { Interface-typed variable: a 16-byte fat pointer {IMT, instance}.
            Modelled as a tyRecord whose rec id is the interface's UCls entry. }
          LastTypeRecId := REC_UCLASS_BASE + ci;
          Result := tyRecord;
        end
        else if IsClassType(lo) then
        begin
          if CaseEqual(lo, 'TMyClass') then
            LastTypeRecId := REC_TMYCLASS
          else
          begin
            ci := FindUClass(lo);
            if ci >= 0 then
              LastTypeRecId := REC_UCLASS_BASE + ci
            else
              LastTypeRecId := REC_NONE;
          end;
          Result := tyClass;
        end
        else
        begin
          LastTypeRecId := IsRecordType(lo);
          if LastTypeRecId <> REC_NONE then
            Result := tyRecord
          else
          begin
            aliasIdx := FindTypeAlias(lo);
            if aliasIdx >= 0 then
            begin
              if AliasTk[aliasIdx] = Ord(tySet) then
              begin
                { Named set type: element enum kept in AliasElemTk but not
                  exposed as LastTypeEnumId, so the property kind stays SET.
                  Expose it as LastTypeSetEnumId for RTTI typeRef. }
                LastTypeSetEnumId := AliasElemTk[aliasIdx];
                Result := tySet;
              end
              else if AliasTk[aliasIdx] = Ord(tyPointer) then
              begin
                LastTypePointerElemTk := IntToTypeKind(AliasElemTk[aliasIdx]);
                LastTypePointerElemRec := AliasElemRec[aliasIdx];
                LastTypeProcSig := AliasProcSig[aliasIdx];
                Result := tyPointer;
              end
              else
              begin
                LastTypeRecId := AliasElemRec[aliasIdx];
                LastTypeProcSig := AliasProcSig[aliasIdx];  { method-pointer record carries a call signature }
                Result := IntToTypeKind(AliasTk[aliasIdx]);
              end;
            end
            else
            begin
              LastTypeEnumId := FindEnumType(lo);
              Result := tyInteger;  { enums are ordinal/integer-sized at codegen }
            end;
          end;
        end;
      end;
    end;
  end;
  Next;
end;

procedure ParseVarSection;
var names: array[0..MAX_DECL_NAMES-1] of AnsiString; n, i, idx: Integer; tk: TTypeKind;
    isArr, isDyn: Boolean; arrLo, arrHi: Integer; elemTk: TTypeKind; dynDepth: Integer;
    initElem: Integer; initVal: Int64;
    isArrND: Boolean; ndCnt, dLo, dHi, di, flatLen, ai: Integer;
    ndDimLo, ndDimSpan: array[0..MAX_ARR_DIMS-1] of Integer;
begin
  Next;
  { Stop at section keywords: these are plain identifiers in this dialect, so
    an interface-level `var` block would otherwise consume `implementation`
    (or initialization/finalization) as a variable name. }
  while (CurTok.Kind = tkIdent) and
        not CaseEqual(CurTok.SVal, 'implementation') and
        not CaseEqual(CurTok.SVal, 'initialization') and
        not CaseEqual(CurTok.SVal, 'finalization') do
  begin
    n := 0;
    repeat
      if n >= MAX_DECL_NAMES then Error('too many comma-separated names in one var declaration');
      names[n] := CurTok.SVal; Inc(n); Next;
    until not Eat(tkComma);
    Expect(tkColon, ':');
    isArr := False; isDyn := False; arrLo := 0; arrHi := 0; elemTk := tyInteger;
    isArrND := False; ndCnt := 0;
    ai := -1;
    if CurTok.Kind = tkIdent then ai := FindArrayType(CurTok.SVal);
    if ai >= 0 then
    begin
      { Variable of a named array type. }
      isArr := True;
      elemTk := IntToTypeKind(ArrTypeElemTk[ai]); tk := elemTk;
      LastTypeRecId := ArrTypeElemRec[ai];
      if ArrTypeIsDyn[ai] then
      begin
        { dynamic-array alias -> AllocDynArray below }
        isDyn := True; dynDepth := ArrTypeDynDepth[ai];
      end
      else
      begin
        arrLo := ArrTypeLo[ai]; arrHi := ArrTypeHi[ai];
        if ArrTypeNDims[ai] >= 2 then
        begin
          isArrND := True; ndCnt := ArrTypeNDims[ai];
          for di := 0 to ndCnt - 1 do
          begin
            ndDimLo[di]   := ArrTypeDimLo[ai * MAX_ARR_DIMS + di];
            ndDimSpan[di] := ArrTypeDimSpan[ai * MAX_ARR_DIMS + di];
          end;
        end;
      end;
      Next; { consume the type name }
    end
    else if CurTok.Kind = tkArray then
    begin
      isArr := True; Next;
      if CurTok.Kind = tkLBrack then
      begin
        Next;
        { One or more comma-separated dimensions: `array[a..b, c..d, ...] of T`.
          1 dimension is an ordinary array; >=2 flattens to 1-D (N-D indexing via
          BuildFlatNDIndex). }
        ndCnt := 0;
        repeat
          dLo := ConstEval; Expect(tkDotDot, '..'); dHi := ConstEval;
          if ndCnt >= MAX_ARR_DIMS then Error('too many array dimensions');
          ndDimLo[ndCnt] := dLo; ndDimSpan[ndCnt] := dHi - dLo + 1; Inc(ndCnt);
        until not Eat(tkComma);
        Expect(tkRBrack, ']');
        Expect(tkOf, 'of');
        if ndCnt = 1 then
        begin arrLo := ndDimLo[0]; arrHi := ndDimLo[0] + ndDimSpan[0] - 1; end
        else
        begin
          isArrND := True;
          flatLen := 1;
          for di := 0 to ndCnt - 1 do flatLen := flatLen * ndDimSpan[di];
          arrLo := 0; arrHi := flatLen - 1;
        end;
      end
      else
      begin
        isDyn := True;   { 'array of T' without bounds is a dynamic array }
        dynDepth := 1;
        Expect(tkOf, 'of');
        { Nested dynamic arrays: array of array of ... of BaseType. }
        while CurTok.Kind = tkArray do
        begin
          Next;
          if CurTok.Kind = tkLBrack then
            Error('mixed static/dynamic nested arrays not supported');
          Inc(dynDepth);
          Expect(tkOf, 'of');
        end;
      end;
      elemTk := ParseTypeKind;
      tk := elemTk;
    end
    else
    begin
      { Skip qualifiers like pointer, ^, etc. Stop at `=` so a scalar
        initializer (`var x: Integer = 5`) is left for the init handler below. }
      while not (CurTok.Kind in [tkSemicolon, tkEq, tkBegin, tkVar, tkConst, tkType,
                 tkProcedure, tkFunction, tkEOF]) do
      begin
        tk := ParseTypeKind;
      end;
    end;
	    if isArr then
	      for i := 0 to n-1 do
	      begin
	        if isDyn then
	          idx := AllocDynArray(names[i], elemTk, dynDepth)
	        else
	        begin
	          idx := AllocArray(names[i], elemTk, arrLo, arrHi);
	          if elemTk = tyRecord then
	            Syms[idx].ElemRecName := LastTypeRecId;
	          if isArrND then
	          begin
	            SymArrNDims[idx] := ndCnt;
	            for di := 0 to ndCnt - 1 do
	            begin
	              SymArrDimLo[idx * MAX_ARR_DIMS + di]   := ndDimLo[di];
	              SymArrDimSpan[idx * MAX_ARR_DIMS + di] := ndDimSpan[di];
	            end;
	          end;
	        end;
	      end
	    else
	      for i := 0 to n-1 do
	      begin
	        idx := AllocVar(names[i], tk);
	        if (tk = tyRecord) or (tk = tyClass) then
	        begin
	          Syms[idx].RecName := LastTypeRecId;
	          SymProcSig[idx] := LastTypeProcSig;   { method-pointer record: callable }
	        end
	        else if tk = tyPointer then
	        begin
	          Syms[idx].PtrElemTk := LastTypePointerElemTk;
	          Syms[idx].PtrElemRec := LastTypePointerElemRec;
	          SymProcSig[idx] := LastTypeProcSig;
	        end
	        else if tk = tySet then
	        begin
	          SymSetEnumId[idx] := LastTypeSetEnumId;
	          SymSetElemTk[idx] := LastTypeSetElemTk;
	        end;
	      end;
	    if Eat(tkEq) then
	    begin
	      { Constant initializer `= v` / `= (e0,e1,...)`. Recorded as pending
	        assignments compiled into the program entry just before `main begin`
	        (was silently discarded → globals read 0). Constants only; globals
	        only — a local section initializer should use inline `var x := v`. }
	      if n <> 1 then Error('initializer requires a single variable');
	      if CurProc >= 0 then
	        Error('local var-section initializer not supported; use `var x := value;`');
	      if isDyn then Error('dynamic array initializer not supported');
	      if CurTok.Kind = tkLParen then
	      begin
	        if not isArr then Error('parenthesised initializer requires an array variable');
	        Next;
	        initElem := 0;
	        repeat
	          if PendingInitCount >= MAX_PENDING_INITS then Error('too many global initializers');
	          if initElem > (arrHi - arrLo) then Error('too many array initializer elements');
	          initVal := ParseInitVal;
	          PendingInitSym[PendingInitCount]  := idx;
	          PendingInitElem[PendingInitCount] := arrLo + initElem;
	          PendingInitVal[PendingInitCount]  := initVal;
	          PendingInitTk[PendingInitCount]   := Ord(elemTk);
	          Inc(PendingInitCount);
	          Inc(initElem);
	        until not Eat(tkComma);
	        Expect(tkRParen, ')');
	      end
	      else
	      begin
	        if isArr then Error('array initializer must be parenthesised');
	        if PendingInitCount >= MAX_PENDING_INITS then Error('too many global initializers');
	        initVal := ParseInitVal;
	        PendingInitSym[PendingInitCount]  := idx;
	        PendingInitElem[PendingInitCount] := -1;
	        PendingInitVal[PendingInitCount]  := initVal;
	        PendingInitTk[PendingInitCount]   := Ord(tk);
	        Inc(PendingInitCount);
	      end;
	    end;
	    Eat(tkSemicolon);
	  end;
	end;

procedure ParseConstSection;
var name: AnsiString; v: Int64;
    cTk, cElemTk: TTypeKind; cLo, cHi, cIdx, cElem: Integer;
begin
  Next;
  while CurTok.Kind = tkIdent do
  begin
    name := CurTok.SVal; Next;
    if CurTok.Kind = tkColon then
    begin
      { Typed constant: `const Name: type = value | (e0,e1,...)`. FPC typed
        constants are writable globals with an initial value, so allocate
        storage and reuse the pending-init machinery (same as a `var = init`).
        Globals only; constants of ordinal/Int64 element type. }
      if CurProc >= 0 then
        Error('local typed constant not supported; use a const expression or a var');
      Next;
      if CurTok.Kind = tkArray then
      begin
        Next;
        Expect(tkLBrack, '[');
        cLo := ConstEval;
        Expect(tkDotDot, '..');
        cHi := ConstEval;
        Expect(tkRBrack, ']');
        Expect(tkOf, 'of');
        cElemTk := ParseTypeKind;
        cIdx := AllocArray(name, cElemTk, cLo, cHi);
        Expect(tkEq, '=');
        Expect(tkLParen, '(');
        cElem := 0;
        repeat
          if PendingInitCount >= MAX_PENDING_INITS then Error('too many global initializers');
          if cElem > (cHi - cLo) then Error('too many array constant elements');
          PendingInitSym[PendingInitCount]  := cIdx;
          PendingInitElem[PendingInitCount] := cLo + cElem;
          PendingInitVal[PendingInitCount]  := ParseInitVal;
          PendingInitTk[PendingInitCount]   := Ord(cElemTk);
          Inc(PendingInitCount);
          Inc(cElem);
        until not Eat(tkComma);
        Expect(tkRParen, ')');
      end
      else
      begin
        cTk := ParseTypeKind;
        cIdx := AllocVar(name, cTk);
        Expect(tkEq, '=');
        if PendingInitCount >= MAX_PENDING_INITS then Error('too many global initializers');
        PendingInitSym[PendingInitCount]  := cIdx;
        PendingInitElem[PendingInitCount] := -1;
        PendingInitVal[PendingInitCount]  := ParseInitVal;
        PendingInitTk[PendingInitCount]   := Ord(cTk);
        Inc(PendingInitCount);
      end;
    end
    else
    begin
      Expect(tkEq, '=');
      if CurTok.Kind = tkString then
      begin
        { Untyped string constant: remember the literal's source span; a use of
          the name builds an AN_STR_LIT over it. }
        if StrConstCount >= MAX_TYPEALIAS then Error('too many string constants');
        StrConstName[StrConstCount] := name;
        StrConstSOff[StrConstCount] := Tokens[TokPos-1].SOffset;
        StrConstSLen[StrConstCount] := Tokens[TokPos-1].SLen;
        Inc(StrConstCount);
        Next;
      end
      else
      begin
        v := ConstEval;
        AddConst(name, tyInteger, v);
      end;
    end;
    Eat(tkSemicolon);
  end;
end;

procedure ParseTypeSection;
{ Handles enum types, record/class type declarations }
var
  ordinal: Int64;
  tname: AnsiString;
  done, stopTypes: Boolean; loVal, hiVal, arrLen: Integer; isArr: Boolean; isPackedRecord: Boolean;
  fIsDyn: Boolean; fDynDepth: Integer;
  tnOff, tnLen, ci, fnOff, fnLen, curFieldOff, fRec, fSize, fAlign, classAlign, depth, targetNOff, targetNLen: Integer;
  fTk: TTypeKind;
  parentCi, slot, mmi, mnOff, mnLen, pnOff, pnLen, rFOff, rFLen, rMOff, rMLen, wFOff, wFLen, wMOff, wMLen, rnOff, rnLen, wnOff, wnLen, propRec, i, vmtSlots: Integer;
  implIntf: array[0..15] of Integer; implCnt, tmpCi, ii, imSlot, imProc: Integer;
  parentIntfCi, ancCur, ij, implOrig: Integer; alreadyImpl: Boolean;
  imName: AnsiString;
  isConstructor, isDestructor, isVirtual, isOverride, isAbstract, isClassMethod: Boolean;
  mname, propName, readName, writeName: AnsiString;
  propTk: TTypeKind;
  mIsFunc, mDoneArgs, mDoneParam, mIsArr, mIsByRef: Boolean;
  mRetType, mTk: TTypeKind;
  mNParams, mStartIdx, mTokKindOrd, mpi, mSelfIdx, mFullNameOff, mFullNameLen: Integer;
  curPublished: Integer;  { 1 while inside a published section of the current class body }
  etid, propEnumId, propSetEnumId: Integer;
  mFullName: AnsiString;
  aLo, aHi: Integer; aElemTk: TTypeKind;
  tdCnt, tdLo, tdHi, tdi, tflatLen, fNDims: Integer;
  tdDimLo, tdDimSpan: array[0..MAX_ARR_DIMS-1] of Integer;
  mPNames: array[0..15] of AnsiString;
  mPTypes: array[0..15] of TTypeKind;
  mPTypesRec: array[0..15] of Integer;
  mPArr: array[0..15] of Boolean;
  fldNOffs: array[0..31] of Integer;   { comma-separated field-name spans }
  fldNLens: array[0..31] of Integer;
  nFldNames, fni: Integer;
  mPByRef: array[0..15] of Boolean;
begin
  Next;
  stopTypes := False;
  while (CurTok.Kind = tkIdent) and (not CaseEqual(CurTok.SVal, 'constructor')) and (not CaseEqual(CurTok.SVal, 'destructor')) and (not CaseEqual(CurTok.SVal, 'implementation')) and (not CaseEqual(CurTok.SVal, 'initialization')) and (not CaseEqual(CurTok.SVal, 'finalization')) and not stopTypes do
  begin
    if CaseEqual(CurTok.SVal, 'generic') then
    begin
      ParseGenericTemplate;
    end
    else if CaseEqual(CurTok.SVal, 'operator') then
      stopTypes := True  { top-level operator def follows type section }
    else
    begin
      tnOff := Tokens[TokPos-1].SOffset;
      tnLen := Tokens[TokPos-1].SLen;
      tname := CurTok.SVal; Next;
      Expect(tkEq, '=');
      { A generic class specialization streams the concrete class body in place
        and leaves CurTok on 'class', falling through to the class-binding
        branch below — the concrete name comes from the saved tnOff/tnLen. }
      if CaseEqual(CurTok.SVal, 'specialize') then
        ParseSpecialization(tname);
      if CurTok.Kind = tkLParen then
      begin
        etid := RegisterEnumType(tnOff, tnLen);
        Next; ordinal := 0;
        done := False;
        while (CurTok.Kind = tkIdent) and not done do
        begin
          AddEnumVal(Tokens[TokPos-1].SOffset, Tokens[TokPos-1].SLen);
          AddConst(CurTok.SVal, tyInteger, ordinal);
          Inc(ordinal); Next;
          if not Eat(tkComma) then done := True;
        end;
        Expect(tkRParen, ')');
        EnumTypeValCount[etid] := EnumValCount - EnumTypeValBase[etid];
      end
      else if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'interface') then
      begin
        { `IFoo = interface [guid] <method signatures> end;` — CORBA-style.
          The interface is a UCls entry with no fields; its methods are slot
          signatures (declaration order = IMT slot). A var of it is a 16-byte
          fat pointer {IMT, instance}. }
        Next;
        { optional parent interface: `IBar = interface(IFoo)`. IFoo's method
          signatures are inherited at the leading IMT slots, so a value of IBar
          dispatches its inherited methods and a class implementing IBar also
          satisfies IFoo (the ancestor IMTs are built at the class below). }
        parentIntfCi := -1;
        if CurTok.Kind = tkLParen then
        begin
          Next;
          if CurTok.Kind <> tkIdent then Error('expected parent interface name');
          parentIntfCi := FindUClass(CurTok.SVal);
          if (parentIntfCi < 0) or not UClsIsInterface[parentIntfCi] then
            Error('the parent of an interface must be an interface');
          Next;
          Expect(tkRParen, ')');
        end;
        { COM/ARC interface ({$interfaces com}): with no explicit parent, derive
          implicitly from IInterface so the three reserved slots QueryInterface /
          _AddRef / _Release occupy IMT slots 0..2 (ARC dispatches _Release via
          slot 2). IInterface's own declaration finds no prior IInterface, so it
          does not self-parent and supplies the three slots itself. }
        if InterfacesComMode and (parentIntfCi < 0) then
        begin
          parentIntfCi := FindUClass('IInterface');
          if parentIntfCi < 0 then parentIntfCi := FindUClass('IUnknown');
          if (parentIntfCi >= 0) and not UClsIsInterface[parentIntfCi] then
            parentIntfCi := -1;
        end;
        ci := AddUClass(tnOff, tnLen);
        UClsIsInterface[ci] := True;
        UClsIsComInterface[ci] := InterfacesComMode;
        if InterfacesComMode then ComInterfaceUsed := True;
        UClsSize_[ci] := 2 * TARGET_PTR_SIZE;   { fat pointer {IMT, instance} }
        UClsAlign[ci] := TARGET_PTR_SIZE;
        UClsParent[ci] := parentIntfCi;
        { Inherit the parent interface's methods first (contiguously, before this
          interface's own), so IMT slot order is [parent methods..., own...]. }
        if parentIntfCi >= 0 then
          for i := 0 to UClsMCount[parentIntfCi] - 1 do
          begin
            AddUMeth(ci, UMthNOff[UClsMBase[parentIntfCi] + i],
                     UMthNLen[UClsMBase[parentIntfCi] + i],
                     UMthProc_[UClsMBase[parentIntfCi] + i]);
            UMthVirSlot[UMthCount - 1] := UClsMCount[ci] - 1;
            UMthIsStatic[UMthCount - 1] := False;
          end;
        { optional GUID literal ['{...}'] — parsed and ignored (v1) }
        if CurTok.Kind = tkLBrack then
        begin
          while (CurTok.Kind <> tkRBrack) and (CurTok.Kind <> tkEOF) do Next;
          Expect(tkRBrack, ']');
        end;
        while (CurTok.Kind = tkProcedure) or (CurTok.Kind = tkFunction) do
        begin
          mIsFunc := CurTok.Kind = tkFunction;
          Next;
          if CurTok.Kind <> tkIdent then Error('expected interface method name');
          mname := CurTok.SVal;
          mnOff := Tokens[TokPos-1].SOffset; mnLen := Tokens[TokPos-1].SLen;
          Next;
          mNParams := 0; mRetType := tyInteger;
          if CurTok.Kind = tkLParen then
          begin
            Next; mDoneArgs := False;
            while (CurTok.Kind <> tkRParen) and not mDoneArgs do
            begin
              mIsByRef := False;
              if (CurTok.Kind = tkVar) or ((CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'out')) then
              begin mIsByRef := True; Next; end
              else if CurTok.Kind = tkConst then Next;
              mStartIdx := mNParams; mDoneParam := False;
              while (CurTok.Kind = tkIdent) and not mDoneParam do
              begin
                mPNames[mNParams] := CurTok.SVal; Inc(mNParams); Next;
                if not Eat(tkComma) then mDoneParam := True;
                if CurTok.Kind = tkColon then mDoneParam := True;
              end;
              Expect(tkColon, ':');
              mIsArr := False;
              if CurTok.Kind = tkArray then begin Next; Expect(tkOf, 'of'); mTk := ParseTypeKind; mIsArr := True; end
              else mTk := ParseTypeKind;
              for i := mStartIdx to mNParams-1 do
              begin mPTypes[i] := mTk; mPTypesRec[i] := LastTypeRecId; mPArr[i] := mIsArr; mPByRef[i] := mIsByRef; end;
              if not Eat(tkSemicolon) then mDoneArgs := True;
            end;
            Expect(tkRParen, ')');
          end;
          if mIsFunc then begin Expect(tkColon, ':'); mRetType := ParseTypeKind; end;
          Eat(tkSemicolon);
          { inject implicit Self (the instance) at param 0, like a class method }
          for i := mNParams downto 1 do
          begin mPNames[i] := mPNames[i-1]; mPTypes[i] := mPTypes[i-1]; mPArr[i] := mPArr[i-1]; mPByRef[i] := mPByRef[i-1]; end;
          mPNames[0] := 'Self'; mPTypes[0] := tyClass; mPArr[0] := False; mPByRef[0] := False;
          mNParams := mNParams + 1;
          mFullName := tname; AppendChar(mFullName, '.');
          for i := 1 to Length(mname) do AppendChar(mFullName, mname[i]);
          mpi := RegisterProc(mFullName, mIsFunc, mRetType, mNParams, mPNames, mPTypes);
          Procs[mpi].BodyAddr := -1;
          for i := 0 to mNParams-1 do
          begin Procs[mpi].Params[i].IsArray := mPArr[i]; Procs[mpi].Params[i].IsRef := mPByRef[i]; end;
          AddUMeth(ci, mnOff, mnLen, mpi);
          { slot = method position within this interface (IMT index) }
          UMthVirSlot[UMthCount-1] := UClsMCount[ci] - 1;
          UMthIsStatic[UMthCount-1] := False;
        end;
        Expect(tkEnd, 'end');
        Eat(tkSemicolon);
      end
      else if (CurTok.Kind = tkClass) and (Tokens[TokPos].Kind = tkOf) then
      begin
        { Named metaclass alias: TFooClass = class of TFoo. Values use the
          existing RTTI-pointer class-reference representation. }
        Next;
        Expect(tkOf, 'of');
        if CurTok.Kind <> tkIdent then Error('expected base class after class of');
        ci := FindUClass(CurTok.SVal);
        if ci < 0 then Error('class of base type not found: ' + CurTok.SVal);
        RegisterClassRefAlias(tnOff, tnLen, REC_UCLASS_BASE + ci);
        Next;
        Eat(tkSemicolon);
      end
      else if CurTok.Kind = tkClass then
      begin
        Next;
        parentCi := -1;
        implCnt := 0;
        if Eat(tkLParen) then
        begin
          { (ParentClass) and/or (Iface1, Iface2, ...): an interface name in the
            list is an implemented interface; a class name is the parent. }
          repeat
            if CurTok.Kind <> tkIdent then Error('expected base class or interface name');
            tmpCi := FindUClass(CurTok.SVal);
            if tmpCi < 0 then Error('base type not found: ' + CurTok.SVal);
            if UClsIsInterface[tmpCi] then
            begin
              if implCnt > 15 then Error('too many implemented interfaces (v1: max 16)');
              implIntf[implCnt] := tmpCi; Inc(implCnt);
            end
            else
            begin
              if parentCi >= 0 then Error('a class may have only one parent class');
              parentCi := tmpCi;
            end;
            Next;
          until not Eat(tkComma);
          Expect(tkRParen, ')');
        end;

        { A class implementing a derived interface also implements every ancestor
          interface — add the ancestors so an IMT is built for each, making
          `is`/`as`/`Supports` and class->base-interface assignment work. }
        implOrig := implCnt;
        for ii := 0 to implOrig - 1 do
        begin
          ancCur := UClsParent[implIntf[ii]];
          while ancCur >= 0 do
          begin
            alreadyImpl := False;
            for ij := 0 to implCnt - 1 do
              if implIntf[ij] = ancCur then alreadyImpl := True;
            if not alreadyImpl then
            begin
              if implCnt > 15 then Error('too many implemented interfaces (v1: max 16)');
              implIntf[implCnt] := ancCur; Inc(implCnt);
            end;
            ancCur := UClsParent[ancCur];
          end;
        end;

        ci := AddUClass(tnOff, tnLen);
        UClsParent[ci] := parentCi;

        curFieldOff := 0;
        classAlign := 1;
        if parentCi >= 0 then
        begin
          curFieldOff := UClsSize_[parentCi];
          UClsVirtCount[ci] := UClsVirtCount[parentCi];
        end
        else
        begin
          curFieldOff := 8; { reserve offset 0 for VMT pointer }
        end;

        { Implicit first section defaults to published, as Delphi/Lazarus do for
          $M+ (TPersistent-descended) classes — so a stock TForm's fields and
          event handlers are streamable/reflectable without an explicit
          `published`. We don't track $M+, so this applies to every class; the
          only effect is extra RTTI, which is harmless. }
        curPublished := 1;
        while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
        begin
          { Visibility section markers. Not reserved words, so treat as section
            switch only when immediately at member-start position. Access is not
            enforced (project policy); we only record the published flag for RTTI. }
          if (CurTok.Kind = tkIdent) and
             (CaseEqual(CurTok.SVal, 'private') or CaseEqual(CurTok.SVal, 'protected') or
              CaseEqual(CurTok.SVal, 'public') or CaseEqual(CurTok.SVal, 'published')) then
          begin
            if CaseEqual(CurTok.SVal, 'published') then curPublished := 1
            else curPublished := 0;
            Next;
            continue;
          end;

          isClassMethod := False;
          if (CurTok.Kind = tkClass) and ((Tokens[TokPos].Kind = tkProcedure) or (Tokens[TokPos].Kind = tkFunction)) then
          begin
            isClassMethod := True;
            Next; { consume 'class' }
          end;

          if (CurTok.Kind = tkProcedure) or (CurTok.Kind = tkFunction) or
             ((CurTok.Kind = tkIdent) and (CaseEqual(CurTok.SVal, 'constructor') or CaseEqual(CurTok.SVal, 'destructor'))) then
          begin
            mIsFunc := CurTok.Kind = tkFunction;
            isConstructor := False;
            isDestructor := False;
            if CurTok.Kind = tkIdent then
            begin
              isConstructor := CaseEqual(CurTok.SVal, 'constructor');
              isDestructor := CaseEqual(CurTok.SVal, 'destructor');
              Next;
            end
            else
              Next;

            if CurTok.Kind <> tkIdent then Error('expected method name');
            mname := CurTok.SVal;
            mnOff := Tokens[TokPos-1].SOffset;
            mnLen := Tokens[TokPos-1].SLen;
            Next;

            mNParams := 0;
            mRetType := tyInteger;
            if CurTok.Kind = tkLParen then
            begin
              Next;
              mDoneArgs := False;
              while (CurTok.Kind <> tkRParen) and not mDoneArgs do
              begin
                mIsByRef := False;
                if (CurTok.Kind = tkVar) or
                   ((CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'out')) then
                begin
                  mIsByRef := True;
                  Next;
                end
                else if CurTok.Kind = tkConst then
                  Next;
                mStartIdx := mNParams;
                mDoneParam := False;
                while (CurTok.Kind = tkIdent) and not mDoneParam do
                begin
                  mPNames[mNParams] := CurTok.SVal; Inc(mNParams); Next;
                  if not Eat(tkComma) then mDoneParam := True;
                  if CurTok.Kind = tkColon then mDoneParam := True;
                end;
                Expect(tkColon, ':');
                mIsArr := False;
                if CurTok.Kind = tkArray then
                begin
                  Next;
                  Expect(tkOf, 'of');
                  mTk := ParseTypeKind;
                  mIsArr := True;
                end
                else
                  mTk := ParseTypeKind;
                for i := mStartIdx to mNParams-1 do
                begin
                  mPTypes[i] := mTk;
                  mPTypesRec[i] := LastTypeRecId;
                  mPArr[i] := mIsArr;
                  mPByRef[i] := mIsByRef;
                end;
                if not Eat(tkSemicolon) then mDoneArgs := True;
              end;
              Expect(tkRParen, ')');
            end;

            if mIsFunc then
            begin
              Expect(tkColon, ':');
              mRetType := ParseTypeKind;
            end;
            Eat(tkSemicolon);

            if not isClassMethod then
            begin
              for i := mNParams downto 1 do
              begin
                mPNames[i] := mPNames[i-1];
                mPTypes[i] := mPTypes[i-1];
                mPArr[i]   := mPArr[i-1];
                mPByRef[i] := mPByRef[i-1];
              end;
              mPNames[0] := 'Self';
              mPTypes[0] := tyClass;
              mPArr[0]   := False;
              mPByRef[0] := False;
              mNParams := mNParams + 1;
            end;

            mFullName := tname;
            AppendChar(mFullName, '.');
            for i := 1 to Length(mname) do AppendChar(mFullName, mname[i]);

            mpi := FindProcOverload(mFullName, mNParams, mPTypes, mPArr, mPByRef);
            if mpi < 0 then
            begin
              mpi := RegisterProc(mFullName, mIsFunc, mRetType, mNParams, mPNames, mPTypes);
              Procs[mpi].BodyAddr := -1;
              for i := 0 to mNParams-1 do
              begin
                Procs[mpi].Params[i].IsArray := mPArr[i];
                Procs[mpi].Params[i].IsRef := mPByRef[i];
                if (mPTypes[i] = tyClass) or (mPTypes[i] = tyRecord) then
                  Procs[mpi].Params[i].SymIdx := -1;
              end;
            end;

            isVirtual := False;
            isOverride := False;
            isAbstract := False;
            while (CurTok.Kind = tkIdent) and
                  (CaseEqual(CurTok.SVal, 'virtual') or
                   CaseEqual(CurTok.SVal, 'override') or
                   CaseEqual(CurTok.SVal, 'abstract')) do
            begin
              if CaseEqual(CurTok.SVal, 'virtual') then isVirtual := True;
              if CaseEqual(CurTok.SVal, 'override') then isOverride := True;
              if CaseEqual(CurTok.SVal, 'abstract') then
              begin
                isVirtual := True;   { abstract implies virtual }
                isAbstract := True;
              end;
              Next;
              Eat(tkSemicolon);
            end;

            AddUMeth(ci, mnOff, mnLen, mpi);
            mmi := UMthCount - 1;
            UMthIsStatic[mmi] := isClassMethod;
            UMthPub[mmi] := curPublished;

            if isVirtual then
            begin
              slot := UClsVirtCount[ci];
              UClsVirtCount[ci] := UClsVirtCount[ci] + 1;
              UMthVirSlot[mmi] := slot;
            end
            else if isOverride then
            begin
              slot := FindParentVirtualSlot(parentCi, mname);
              if slot < 0 then Error('cannot override: no virtual method found in parent chain: ' + mname);
              UMthVirSlot[mmi] := slot;
            end;
          end
          else if CurTok.Kind = tkProperty then
          begin
            Next;
            if CurTok.Kind <> tkIdent then Error('expected property name');
            propName := CurTok.SVal;
            pnOff := Tokens[TokPos-1].SOffset;
            pnLen := Tokens[TokPos-1].SLen;
            Next;
            Expect(tkColon, ':');
            LastTypeSetEnumId := -1;
            propTk := ParseTypeKind;
            propRec := LastTypeRecId;
            propEnumId := LastTypeEnumId;
            propSetEnumId := LastTypeSetEnumId;

            rFOff := 0; rFLen := 0;
            rMOff := 0; rMLen := 0;
            wFOff := 0; wFLen := 0;
            wMOff := 0; wMLen := 0;

            if CurTok.Kind = tkRead then
            begin
              Next;
              if CurTok.Kind <> tkIdent then Error('expected read field or method name');
              readName := CurTok.SVal;
              rnOff := Tokens[TokPos-1].SOffset;
              rnLen := Tokens[TokPos-1].SLen;
              Next;
              if FindUField(ci, readName) >= 0 then
              begin
                rFOff := rnOff; rFLen := rnLen;
              end
              else
              begin
                rMOff := rnOff; rMLen := rnLen;
              end;
            end;

            if CurTok.Kind = tkwrite then
            begin
              Next;
              if CurTok.Kind <> tkIdent then Error('expected write field or method name');
              writeName := CurTok.SVal;
              wnOff := Tokens[TokPos-1].SOffset;
              wnLen := Tokens[TokPos-1].SLen;
              Next;
              if FindUField(ci, writeName) >= 0 then
              begin
                wFOff := wnOff; wFLen := wnLen;
              end
              else
              begin
                wMOff := wnOff; wMLen := wnLen;
              end;
            end;

            Eat(tkSemicolon);
            i := AddUProperty(ci, pnOff, pnLen, Ord(propTk), propRec);
            UPropReadFOff[i] := rFOff; UPropReadFLen[i] := rFLen;
            UPropReadMOff[i] := rMOff; UPropReadMLen[i] := rMLen;
            UPropWriteFOff[i] := wFOff; UPropWriteFLen[i] := wFLen;
            UPropWriteMOff[i] := wMOff; UPropWriteMLen[i] := wMLen;
            UPropPub[i] := curPublished;
            UPropEnumId[i] := propEnumId;
            UPropSetEnumId[i] := propSetEnumId;
          end
          else if CurTok.Kind = tkIdent then
          begin
            { comma-separated names share one type: `A, B: Integer` }
            fldNOffs[0] := Tokens[TokPos-1].SOffset;
            fldNLens[0] := Tokens[TokPos-1].SLen;
            nFldNames := 1;
            Next;
            while CurTok.Kind = tkComma do
            begin
              Next;
              if CurTok.Kind <> tkIdent then Error('expected field name after ","');
              fldNOffs[nFldNames] := Tokens[TokPos-1].SOffset;
              fldNLens[nFldNames] := Tokens[TokPos-1].SLen;
              Inc(nFldNames);
              Next;
            end;
            Expect(tkColon, ':');
            isArr := False;
            arrLen := 1;
            fIsDyn := False;
            fDynDepth := 0;
            fNDims := 0;
            if CurTok.Kind = tkArray then
            begin
              Next;
              if CurTok.Kind = tkLBrack then
              begin
                Next;
                if CurTok.Kind = tkInteger then
                begin
                  loVal := CurTok.IVal;
                  Next;
                  Expect(tkDotDot, '..');
                  if CurTok.Kind = tkInteger then
                  begin
                    hiVal := CurTok.IVal;
                    arrLen := hiVal - loVal + 1;
                    Next;
                  end;
                  { N-D field: collect dim0 then any comma dims. }
                  fNDims := 1; tdDimLo[0] := loVal; tdDimSpan[0] := hiVal - loVal + 1;
                  while CurTok.Kind = tkComma do
                  begin
                    Eat(tkComma);
                    if CurTok.Kind = tkInteger then begin tdLo := CurTok.IVal; Next; end;
                    Expect(tkDotDot, '..');
                    if CurTok.Kind = tkInteger then begin tdHi := CurTok.IVal; Next; end;
                    if fNDims >= MAX_ARR_DIMS then Error('too many array dimensions');
                    tdDimLo[fNDims] := tdLo; tdDimSpan[fNDims] := tdHi - tdLo + 1;
                    arrLen := arrLen * tdDimSpan[fNDims];
                    Inc(fNDims);
                  end;
                end;
                Expect(tkRBrack, ']');
                Expect(tkOf, 'of');
                fTk := ParseTypeKind;
                fRec := LastTypeRecId;
                isArr := True;
              end
              else
              begin
                { Dynamic-array field: `array of T`, including nested. The slot is
                  a pointer-sized handle; fTk/fRec carry the base element type. }
                fIsDyn := True;
                fDynDepth := 1;
                Expect(tkOf, 'of');
                while CurTok.Kind = tkArray do
                begin
                  Next;
                  Inc(fDynDepth);
                  Expect(tkOf, 'of');
                end;
                fTk := ParseTypeKind;
                fRec := LastTypeRecId;
              end;
            end
            else
            begin
              fTk := ParseTypeKind;
              fRec := LastTypeRecId;
            end;
            if fIsDyn then
            begin
              fSize := TARGET_PTR_SIZE;
              fAlign := TARGET_PTR_SIZE;
            end
            else if fTk = tyString then
            begin
              fSize := LOCAL_STR_CAP + 8;
              fAlign := TARGET_PTR_SIZE;
            end
            else if fTk = tyRecord then
            begin
              fSize := RecSize(fRec);
              fAlign := TARGET_PTR_SIZE;
            end
            else
            begin
              fSize := TypeSize(fTk);
              fAlign := TypeAlign(fTk);
            end;
            if isArr then
              fSize := fSize * arrLen;
            for fni := 0 to nFldNames - 1 do
            begin
              curFieldOff := AlignTo(curFieldOff, fAlign);
              AddUField(ci, fldNOffs[fni], fldNLens[fni], curFieldOff, Ord(fTk), fRec);
              UFldIsArray[UFldCount-1] := isArr or fIsDyn;
              if fIsDyn then UFldArrLen[UFldCount-1] := -1
              else UFldArrLen[UFldCount-1] := arrLen;
              UFldDynDepth[UFldCount-1] := fDynDepth;
              if fNDims >= 2 then
              begin
                UFldArrNDims[UFldCount-1] := fNDims;
                for tdi := 0 to fNDims - 1 do
                begin
                  UFldArrDimLo[(UFldCount-1) * MAX_ARR_DIMS + tdi]   := tdDimLo[tdi];
                  UFldArrDimSpan[(UFldCount-1) * MAX_ARR_DIMS + tdi] := tdDimSpan[tdi];
                end;
              end;
              UFldPub[UFldCount-1] := curPublished;
              curFieldOff := curFieldOff + fSize;
            end;
            if fAlign > classAlign then classAlign := fAlign;
            Eat(tkSemicolon);
          end
          else
            Next;
        end;
        UClsSize_[ci] := AlignTo(curFieldOff, classAlign);
        Expect(tkEnd, 'end');

        UClsVMTOffset[ci] := DataLen;
        { Always reserve at least one slot so every class has a DISTINCT VMT
          address — that address is the per-class runtime identity used by is/as
          and stored at [instance+0]. Without this, classes with no virtual
          methods get 0-byte VMTs that all alias the same offset, so `obj is
          AnyClass` would match every class. The padding slot is never dispatched
          (the class has no virtuals), so it is harmless. }
        vmtSlots := UClsVirtCount[ci];
        if vmtSlots < 1 then vmtSlots := 1;
        for i := 0 to vmtSlots * 8 - 1 do
        begin
          if DataLen >= MAX_DATA then Error('data overflow');
          Data[DataLen] := 0;
          Inc(DataLen);
        end;
        { Fill every VMT slot from the effective method (own override or an
          inherited one). The per-override fixup loop only covers subclasses
          that already exist when the override is parsed, so a subclass
          declared later (or in a later unit) would leave inherited slots null
          and crash on dispatch. This makes each class's VMT self-contained. }
        for i := 0 to UClsVirtCount[ci] - 1 do
        begin
          slot := ResolveVMTSlotProc(ci, i);
          if slot >= 0 then
          begin
            if MethodFixCount >= MAX_METHFIX then Error('too many virtual method fixups');
            MethodFixups[MethodFixCount].DataPos := UClsVMTOffset[ci] + i * 8;
            MethodFixups[MethodFixCount].ProcIdx := slot;
            Inc(MethodFixCount);
          end;
        end;

        { Build one Interface Method Table per implemented interface: a Data[]
          array of code addresses, slot k = the class method implementing the
          interface's method k (matched by name), wired via MethodFixups like the
          VMT. A class->interface assignment captures the IMT address. }
        for ii := 0 to implCnt - 1 do
        begin
          tmpCi := implIntf[ii];
          if IMTCount >= MAX_IMT then Error('too many interface method tables');
          IMTClass[IMTCount] := ci;
          IMTIntf[IMTCount] := tmpCi;
          IMTOff[IMTCount] := DataLen;
          Inc(IMTCount);
          for imSlot := 0 to UClsMCount[tmpCi] - 1 do
          begin
            imName := '';
            for i := 0 to UMthNLen[UClsMBase[tmpCi] + imSlot] - 1 do
              AppendChar(imName, TokChars[UMthNOff[UClsMBase[tmpCi] + imSlot] + i]);
            mmi := FindUMeth(ci, imName);
            if mmi < 0 then Error('class does not implement interface method: ' + imName);
            imProc := UMthProc_[mmi];
            if MethodFixCount >= MAX_METHFIX then Error('too many method fixups (IMT)');
            MethodFixups[MethodFixCount].DataPos := DataLen;
            MethodFixups[MethodFixCount].ProcIdx := imProc;
            Inc(MethodFixCount);
            for i := 0 to 7 do begin if DataLen >= MAX_DATA then Error('data overflow'); Data[DataLen] := 0; Inc(DataLen); end;
          end;
        end;
      end
      else if (CurTok.Kind = tkPacked) or (CurTok.Kind = tkRecord) then
      begin
        isPackedRecord := CurTok.Kind = tkPacked;
        if isPackedRecord then
        begin
          Next;
          Expect(tkRecord, 'record');
        end
        else
          Next;
        ci := AddUClass(tnOff, tnLen);
        UClsParent[ci] := -1;
        UClsIsRecord[ci] := True;
        curFieldOff := 0;
        classAlign := 1;
        while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
        begin
          if CurTok.Kind = tkIdent then
          begin
            { comma-separated names share one type: `X, Y: Integer` }
            fldNOffs[0] := Tokens[TokPos-1].SOffset;
            fldNLens[0] := Tokens[TokPos-1].SLen;
            nFldNames := 1;
            Next;
            while CurTok.Kind = tkComma do
            begin
              Next;
              if CurTok.Kind <> tkIdent then Error('expected field name after ","');
              fldNOffs[nFldNames] := Tokens[TokPos-1].SOffset;
              fldNLens[nFldNames] := Tokens[TokPos-1].SLen;
              Inc(nFldNames);
              Next;
            end;
            Expect(tkColon, ':');
            isArr := False;
            arrLen := 1;
            fIsDyn := False;
            fDynDepth := 0;
            fNDims := 0;
            if CurTok.Kind = tkArray then
            begin
              Next;
              if CurTok.Kind = tkLBrack then
              begin
                Next;
                if CurTok.Kind = tkInteger then
                begin
                  loVal := CurTok.IVal;
                  Next;
                  Expect(tkDotDot, '..');
                  if CurTok.Kind = tkInteger then
                  begin
                    hiVal := CurTok.IVal;
                    arrLen := hiVal - loVal + 1;
                    Next;
                  end;
                  { N-D field: collect dim0 then any comma dims. }
                  fNDims := 1; tdDimLo[0] := loVal; tdDimSpan[0] := hiVal - loVal + 1;
                  while CurTok.Kind = tkComma do
                  begin
                    Eat(tkComma);
                    if CurTok.Kind = tkInteger then begin tdLo := CurTok.IVal; Next; end;
                    Expect(tkDotDot, '..');
                    if CurTok.Kind = tkInteger then begin tdHi := CurTok.IVal; Next; end;
                    if fNDims >= MAX_ARR_DIMS then Error('too many array dimensions');
                    tdDimLo[fNDims] := tdLo; tdDimSpan[fNDims] := tdHi - tdLo + 1;
                    arrLen := arrLen * tdDimSpan[fNDims];
                    Inc(fNDims);
                  end;
                end;
                Expect(tkRBrack, ']');
                Expect(tkOf, 'of');
                fTk := ParseTypeKind;
                fRec := LastTypeRecId;
                isArr := True;
              end
              else
              begin
                { Dynamic-array field: `array of T`, including nested. }
                fIsDyn := True;
                fDynDepth := 1;
                Expect(tkOf, 'of');
                while CurTok.Kind = tkArray do
                begin
                  Next;
                  Inc(fDynDepth);
                  Expect(tkOf, 'of');
                end;
                fTk := ParseTypeKind;
                fRec := LastTypeRecId;
              end;
            end
            else
            begin
              fTk := ParseTypeKind;
              fRec := LastTypeRecId;
            end;
            if fIsDyn then
            begin
              fSize := TARGET_PTR_SIZE;
              fAlign := TARGET_PTR_SIZE;
            end
            else if fTk = tyString then
            begin
              fSize := LOCAL_STR_CAP + 8;
              fAlign := TARGET_PTR_SIZE;
            end
            else if fTk = tyRecord then
            begin
              fSize := RecSize(fRec);
              if fRec >= REC_UCLASS_BASE then
                fAlign := UClsAlign[fRec - REC_UCLASS_BASE]
              else
                fAlign := TARGET_PTR_SIZE;
            end
            else
            begin
              fSize := TypeSize(fTk);
              fAlign := TypeAlign(fTk);
            end;
            if isPackedRecord then
              fAlign := 1
            else if fAlign > TokPackRecords[TokPos - 1] then
              fAlign := TokPackRecords[TokPos - 1];
            if isArr then
              fSize := fSize * arrLen;
            for fni := 0 to nFldNames - 1 do
            begin
              curFieldOff := AlignTo(curFieldOff, fAlign);
              AddUField(ci, fldNOffs[fni], fldNLens[fni], curFieldOff, Ord(fTk), fRec);
              UFldIsArray[UFldCount-1] := isArr or fIsDyn;
              if fIsDyn then UFldArrLen[UFldCount-1] := -1
              else UFldArrLen[UFldCount-1] := arrLen;
              UFldDynDepth[UFldCount-1] := fDynDepth;
              if fNDims >= 2 then
              begin
                UFldArrNDims[UFldCount-1] := fNDims;
                for tdi := 0 to fNDims - 1 do
                begin
                  UFldArrDimLo[(UFldCount-1) * MAX_ARR_DIMS + tdi]   := tdDimLo[tdi];
                  UFldArrDimSpan[(UFldCount-1) * MAX_ARR_DIMS + tdi] := tdDimSpan[tdi];
                end;
              end;
              curFieldOff := curFieldOff + fSize;
            end;
            if fAlign > classAlign then classAlign := fAlign;
            Eat(tkSemicolon);
          end
          else
            Next;
        end;
        UClsSize_[ci] := AlignTo(curFieldOff, classAlign);
        UClsAlign[ci] := classAlign;
        Expect(tkEnd, 'end');
      end
      else if CurTok.Kind = tkCaret then
      begin
        { Named pointer type alias: PFoo = ^TFoo }
        Next;
        targetNOff := Tokens[TokPos-1].SOffset;
        targetNLen := Tokens[TokPos-1].SLen;
        fTk := ParseTypeKind;
        RegisterPtrAlias(tnOff, tnLen, Ord(fTk), LastTypeRecId, targetNOff, targetNLen);
        Eat(tkSemicolon);
      end
      else if CaseEqual(CurTok.SVal, 'set') then
      begin
        { Named set type: TFooSet = set of TFoo }
        Next;
        Expect(tkOf, 'of');
        propEnumId := FindEnumType(CurTok.SVal);
        RegisterSetAlias(tnOff, tnLen, propEnumId);
        while not (CurTok.Kind in [tkSemicolon,tkEOF]) do Next;
      end
      else if CurTok.Kind = tkArray then
      begin
        Next; { consume 'array' }
        if CurTok.Kind = tkLBrack then
        begin
          { Named fixed-array type `TA = array[a..b (, c..d, ...)] of T` —
            register it so a var/field/param of type TA becomes a real array
            (1-D or flattened N-D). Previously skipped → TA was not an array. }
          Next;
          tdCnt := 0;
          repeat
            tdLo := ConstEval; Expect(tkDotDot, '..'); tdHi := ConstEval;
            if tdCnt >= MAX_ARR_DIMS then Error('too many array dimensions');
            tdDimLo[tdCnt] := tdLo; tdDimSpan[tdCnt] := tdHi - tdLo + 1; Inc(tdCnt);
          until not Eat(tkComma);
          Expect(tkRBrack, ']');
          Expect(tkOf, 'of');
          aElemTk := ParseTypeKind;
          if tdCnt = 1 then
          begin aLo := tdDimLo[0]; aHi := tdDimLo[0] + tdDimSpan[0] - 1; end
          else
          begin
            tflatLen := 1;
            for tdi := 0 to tdCnt - 1 do tflatLen := tflatLen * tdDimSpan[tdi];
            aLo := 0; aHi := tflatLen - 1;
          end;
          if ArrTypeCount >= MAX_TYPEALIAS then Error('too many array types');
          ArrTypeName[ArrTypeCount] := tname;
          ArrTypeLo[ArrTypeCount] := aLo;
          ArrTypeHi[ArrTypeCount] := aHi;
          ArrTypeElemTk[ArrTypeCount] := Ord(aElemTk);
          ArrTypeElemRec[ArrTypeCount] := LastTypeRecId;
          if tdCnt >= 2 then ArrTypeNDims[ArrTypeCount] := tdCnt
          else ArrTypeNDims[ArrTypeCount] := 0;
          for tdi := 0 to tdCnt - 1 do
          begin
            ArrTypeDimLo[ArrTypeCount * MAX_ARR_DIMS + tdi]   := tdDimLo[tdi];
            ArrTypeDimSpan[ArrTypeCount * MAX_ARR_DIMS + tdi] := tdDimSpan[tdi];
          end;
          ArrTypeIsDyn[ArrTypeCount] := False;
          Inc(ArrTypeCount);
        end
        else
        begin
          { Dynamic-array type alias `TArr = array of T` (nested: array of array
            of T). Register it so `var a: TArr` becomes a real dynamic array. }
          Expect(tkOf, 'of');
          tdCnt := 1; { reuse as dyn depth }
          while CurTok.Kind = tkArray do
          begin Next; Inc(tdCnt); Expect(tkOf, 'of'); end;
          aElemTk := ParseTypeKind;
          if ArrTypeCount >= MAX_TYPEALIAS then Error('too many array types');
          ArrTypeName[ArrTypeCount] := tname;
          ArrTypeElemTk[ArrTypeCount] := Ord(aElemTk);
          ArrTypeElemRec[ArrTypeCount] := LastTypeRecId;
          ArrTypeNDims[ArrTypeCount] := 0;
          ArrTypeIsDyn[ArrTypeCount] := True;
          ArrTypeDynDepth[ArrTypeCount] := tdCnt;
          Inc(ArrTypeCount);
        end;
      end
      else if (CurTok.Kind = tkProcedure) or (CurTok.Kind = tkFunction) then
      begin
        { Procedural type: `T = procedure(...)` / `function(...): R [of object]`.
          The signature is parsed into a body-less Procs[] entry; the alias keeps
          its index (AliasProcSig) so an indirect call `v(args)` through a var of
          this type marshals args/return via the same machinery as a direct call. }
        mIsFunc := (CurTok.Kind = tkFunction);
        Next;
        mNParams := 0;
        mRetType := tyInteger;
        if CurTok.Kind = tkLParen then
        begin
          Next;
          mDoneArgs := False;
          while (CurTok.Kind <> tkRParen) and not mDoneArgs do
          begin
            mIsByRef := False;
            if (CurTok.Kind = tkVar) or
               ((CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'out')) then
            begin mIsByRef := True; Next; end
            else if CurTok.Kind = tkConst then
              Next;
            mStartIdx := mNParams;
            mDoneParam := False;
            while (CurTok.Kind = tkIdent) and not mDoneParam do
            begin
              mPNames[mNParams] := CurTok.SVal; Inc(mNParams); Next;
              if not Eat(tkComma) then mDoneParam := True;
              if CurTok.Kind = tkColon then mDoneParam := True;
            end;
            Expect(tkColon, ':');
            mIsArr := False;
            if CurTok.Kind = tkArray then
            begin
              Next; Expect(tkOf, 'of'); mTk := ParseTypeKind; mIsArr := True;
            end
            else
              mTk := ParseTypeKind;
            for i := mStartIdx to mNParams-1 do
            begin
              mPTypes[i] := mTk;
              mPTypesRec[i] := LastTypeRecId;
              mPArr[i] := mIsArr;
              mPByRef[i] := mIsByRef;
            end;
            if not Eat(tkSemicolon) then mDoneArgs := True;
          end;
          Expect(tkRParen, ')');
        end;
        if mIsFunc then
        begin
          Expect(tkColon, ':');
          mRetType := ParseTypeKind;
        end;
        mpi := RegisterProc('$proctype', mIsFunc, mRetType, mNParams, mPNames, mPTypes);
        Procs[mpi].BodyAddr := -1;
        for i := 0 to mNParams-1 do
        begin
          Procs[mpi].Params[i].IsArray := mPArr[i];
          Procs[mpi].Params[i].IsRef := mPByRef[i];
        end;
        if CurTok.Kind = tkOf then
        begin
          { `of object` — a method pointer: a 16-byte {Code,Data} value. The
            signature drives arg marshalling; Self (Data) is injected at the call. }
          Next;
          if CurTok.Kind = tkIdent then Next;   { consume `object` }
          RegisterMethodPtrTypeAlias(tnOff, tnLen, mpi, EnsureMethodPtrRec);
        end
        else
          RegisterProcTypeAlias(tnOff, tnLen, mpi);
      end
      else
      begin
        { Named simple type alias: PFoo = BaseType }
        fTk := ParseTypeKind;
        RegisterGeneralAlias(tnOff, tnLen, Ord(fTk), LastTypeRecId);
      end;
      Eat(tkSemicolon);
    end;
  end;
  { Materialise deferred class-specialization methods after the section. The
    loop exited with the terminating token already loaded into CurTok (TokPos
    points past it); un-read it so the streamed methods are inserted before it,
    then reload CurTok from the first streamed token (or the terminator again if
    nothing was streamed). }
  if PendingSpecCount > 0 then
  begin
    Dec(TokPos);
    FlushPendingClassSpecializations;
    Next;
  end;
  ResolvePendingPointerAliases;
end;

{ ===== Procedure/function parser ===== }

procedure ParseSubroutine;
var
  isFunc   : Boolean;
  name     : AnsiString;
  retType  : TTypeKind;
  tk       : TTypeKind;
  pnames    : array[0..15] of AnsiString;
  ptypes    : array[0..15] of TTypeKind;
  ptypesRec : array[0..15] of Integer;
  ptypesPtrElemTk : array[0..15] of TTypeKind;
  ptypesPtrElemRec : array[0..15] of Integer;
  ptypesProcSig : array[0..15] of Integer;  { proc-typed param: signature index, -1 otherwise }
  parr      : array[0..15] of Boolean;
  pbyref    : array[0..15] of Boolean;
  pNDims    : array[0..15] of Integer;
  pDynDepth : array[0..15] of Integer;  { named dynamic-array param: dyn nesting depth (>0), 0 = not a dyn-array param }
  pDimLo    : array[0..16*MAX_ARR_DIMS-1] of Integer;
  pDimSpan  : array[0..16*MAX_ARR_DIMS-1] of Integer;
  paramNDims, paramDynDepth, paramAi, pdi: Integer;
  psLo, psSpan: array[0..MAX_ARR_DIMS-1] of Integer;
  nparams  : Integer;
  pi, i, sz, retRecId, savedLastTypeRecId: Integer;
  zeroBytes : Integer;
  zfLoop, zfDone : Integer;
  retIsDynArr : Boolean; retElemTk : TTypeKind; retElemRec : Integer;
  retPtrElemTk, retPtrElemRec : Integer;
  savedSC, savedFS, savedCurProc : Integer;
  savedGLC, savedGFC, j: Integer;
  cleanupJnePatch, cleanupJmpPatch: Integer;
  patchPos : Integer;
  depth    : Integer;
  doneArgs, doneParam, isArr, isByRef, isConst, declOverload, isClassKeyword, isStaticMethod: Boolean;
  needsProcCleanupFrame, savedProcCleanupFrameActive: Boolean;
  isAsmFunc: Boolean;
  isGenerator, isStackless, isAsync: Boolean;
  isIram, isInterrupt: Boolean;
  savedGenIsGen, savedGenSeen, savedGenStackless, savedProcIsAsync: Boolean;
  savedGenSelf, savedGenTry, savedGenStateCtr, savedGenSlotNext: Integer;
  genBodyAST, genStepAST, declElemTk: Integer;
  genSelfIdx, gpi: Integer;
  asmNode: Integer;
  startIdx, idx: Integer;
  tokKindOrd: Integer;
  methOwnerCi, methOwnerRec, methSNOff, methSNLen, mmi, slot, otherCi: Integer;
  pw, pnWords, wlo, whi: Integer;   { ARM32 word-based param spill (int64 = 2 words) }
  methName: AnsiString;
  extLib: AnsiString;
begin
  isClassKeyword := False;
  isAsmFunc := False;
  isGenerator := False;
  isStackless := False;
  isAsync := False;
  isIram := False;
  isInterrupt := False;
  if CurTok.Kind = tkClass then
  begin
    isClassKeyword := True;
    Next;
  end;
  isFunc := CurTok.Kind = tkFunction;
  Next;
  if CurTok.Kind <> tkIdent then Error('expected name');
  name := CurTok.SVal; Next;

  { Check for ClassName.MethodName pattern }
  methOwnerCi := -1;
  methOwnerRec := REC_NONE;
  methSNOff := 0; methSNLen := 0;
  if CurTok.Kind = tkDot then
  begin
    depth := -1;
    for i := 0 to TemplateCount - 1 do
      if CaseEqual(Templates[i].Name, name) then
        depth := i;
    if depth >= 0 then
    begin
      { Start the captured range at the 'procedure'/'function' keyword (one
        token before the template name) so the specialized stream is a complete
        standalone subroutine the top-level loop can parse. }
      BufferGenericMethod(depth, TokPos - 3);
      Exit;
    end;
      methOwnerCi := FindUClass(name);
      if methOwnerCi >= 0 then
      begin
        methOwnerRec := REC_UCLASS_BASE + methOwnerCi;
        Next; { consume dot }
        if CurTok.Kind <> tkIdent then Error('expected method name');
        methName := CurTok.SVal;
        methSNOff := Tokens[TokPos-1].SOffset;
        methSNLen := Tokens[TokPos-1].SLen;
        AppendChar(name, '.');
        i := 1;
        while i <= Length(CurTok.SVal) do begin AppendChar(name, CurTok.SVal[i]); Inc(i); end;
        Next; { consume method name }
      end;
  end;

  nparams := 0; retType := tyInteger; retRecId := REC_NONE;
  retIsDynArr := False; retElemTk := tyUnknown; retElemRec := REC_NONE;
  retPtrElemTk := Ord(tyUnknown); retPtrElemRec := REC_NONE;

  if CurTok.Kind = tkLParen then
  begin
    Next;
    doneArgs := False;
    while (CurTok.Kind <> tkRParen) and not doneArgs do
    begin
      isByRef := False;
      isConst := False;
      if (CurTok.Kind = tkVar) or
         ((CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'out')) then
      begin
        isByRef := True;
        Next;
      end
      else if CurTok.Kind = tkConst then
      begin
        isConst := True;
        Next;
      end;
      startIdx := nparams;
      doneParam := False;
      while (CurTok.Kind = tkIdent) and not doneParam do
      begin
        pnames[nparams] := CurTok.SVal; Inc(nparams); Next;
        if not Eat(tkComma) then doneParam := True;
        if CurTok.Kind = tkColon then doneParam := True;
      end;
      Expect(tkColon, ':');
      isArr := False;
      paramNDims := 0;
      paramDynDepth := 0;
      tokKindOrd := Ord(CurTok.Kind);
      if DebugTrace then writeln('After colon, CurTok.Kind = ', tokKindOrd, ', CurTok.SVal = ', CurTok.SVal);
      paramAi := -1;
      if CurTok.Kind = tkIdent then paramAi := FindArrayType(CurTok.SVal);
      if paramAi >= 0 then
      begin
        { Named fixed-array type param — pass like an open array (by the data
          pointer); the element type drives indexing, N-D dims drive flattening.
          (Previously ParseTypeKind didn't know the name was an array, so the
          param was scalar and indexing it read garbage.) }
        tk := IntToTypeKind(ArrTypeElemTk[paramAi]);
        LastTypeRecId := ArrTypeElemRec[paramAi];
        isArr := True;
        { Named dynamic-array type param (`TDynArr = array of T`): mark it a real
          dynamic array so SetLength routes to -102 and (when var/out) the
          by-ref-handle ABI applies. Distinct from a named *fixed* array, which
          stays an open-array fat-ptr param. }
        if ArrTypeIsDyn[paramAi] then
          paramDynDepth := ArrTypeDynDepth[paramAi];
        if ArrTypeNDims[paramAi] >= 2 then
        begin
          paramNDims := ArrTypeNDims[paramAi];
          for pdi := 0 to paramNDims - 1 do
          begin
            psLo[pdi]   := ArrTypeDimLo[paramAi * MAX_ARR_DIMS + pdi];
            psSpan[pdi] := ArrTypeDimSpan[paramAi * MAX_ARR_DIMS + pdi];
          end;
        end;
        Next;
      end
      else if CurTok.Kind = tkArray then
      begin
        Next;
        Expect(tkOf, 'of');
        if CurTok.Kind = tkConst then
        begin
          { `array of const` (TVarRec open array): each element is a TVarRec
            record from builtinheap. The callee reads it like any open array of
            records; the call site builds the element vector (AN_VARREC_ARRAY). }
          if TVarRecId = REC_NONE then
            Error('array of const requires the builtinheap unit (use an array/heap feature)');
          Next;
          tk := tyRecord;
          LastTypeRecId := TVarRecId;
        end
        else
          tk := ParseTypeKind;
        isArr := True;
      end
      else
        tk := ParseTypeKind;
      { A `const` record param is passed by reference (like FPC). Passing it by
        value truncates to a single qword, dropping all but the first field. }
      if isConst and ((tk = tyRecord) or (tk = tyVariant)) and not isArr then
        isByRef := True;
      for i := startIdx to nparams-1 do
      begin
        ptypes[i] := tk;
        ptypesRec[i] := LastTypeRecId;
        ptypesPtrElemTk[i] := LastTypePointerElemTk;
        ptypesPtrElemRec[i] := LastTypePointerElemRec;
        ptypesProcSig[i] := LastTypeProcSig;
        parr[i] := isArr;
        pbyref[i] := isByRef;
        pNDims[i] := paramNDims;
        pDynDepth[i] := paramDynDepth;
        for pdi := 0 to paramNDims - 1 do
        begin
          pDimLo[i * MAX_ARR_DIMS + pdi]   := psLo[pdi];
          pDimSpan[i * MAX_ARR_DIMS + pdi] := psSpan[pdi];
        end;
      end;
      if not Eat(tkSemicolon) then doneArgs := True;
    end;
    Expect(tkRParen, ')');
  end;

  if isFunc then
  begin
    Expect(tkColon, ':');
    if CurTok.Kind = tkArray then
    begin
      { `array of T` result: a pointer-sized dynamic-array handle. retType holds
        the element type so the result is non-aggregate; the dyn-array nature is
        tracked separately in ProcRetIsDynArray. }
      Next;
      Expect(tkOf, 'of');
      retType := ParseTypeKind;
      retIsDynArr := True;
      retElemTk := retType;
      retElemRec := LastTypeRecId;
    end
    else
    begin
      retType := ParseTypeKind;
      if (retType = tyRecord) or (retType = tyClass) then
        retRecId := LastTypeRecId;
      if retType = tyPointer then
      begin
        retPtrElemTk := Ord(LastTypePointerElemTk);
        retPtrElemRec := LastTypePointerElemRec;
      end;
    end;
  end;

  Eat(tkSemicolon);
  declOverload := False;
  while ((CurTok.Kind = tkIdent) and
         ((CurTok.SVal = 'inline') or (CurTok.SVal = 'Inline') or (CurTok.SVal = 'INLINE') or
          (CurTok.SVal = 'register') or (CurTok.SVal = 'Register') or (CurTok.SVal = 'REGISTER') or
          (CurTok.SVal = 'cdecl') or (CurTok.SVal = 'Cdecl') or (CurTok.SVal = 'CDECL') or
          CaseEqual(CurTok.SVal, 'assembler') or
          CaseEqual(CurTok.SVal, 'generator') or
          CaseEqual(CurTok.SVal, 'async') or
          CaseEqual(CurTok.SVal, 'stackful') or
          CaseEqual(CurTok.SVal, 'stackless') or
          CaseEqual(CurTok.SVal, 'iram') or
          CaseEqual(CurTok.SVal, 'interrupt'))) or
        (CurTok.Kind = tkOverload) do
  begin
    if CurTok.Kind = tkOverload then declOverload := True;
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'assembler') then isAsmFunc := True;
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'generator') then isGenerator := True;
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'async') then isAsync := True;
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'stackless') then isStackless := True;
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'iram') then isIram := True;
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'interrupt') then
    begin
      isInterrupt := True;
      isIram := True;   { interrupt handlers must also be IRAM-resident }
    end;
    { `stackful` is the implemented default strategy; accept it as a no-op modifier. }
    Next;
    Eat(tkSemicolon);
  end;
  if isGenerator and not isFunc then
    Error('generator must be a function (its result type is the yielded element type)');
  if isGenerator and isAsmFunc then
    Error('a routine cannot be both generator and assembler');
  if isAsync and isGenerator then
    Error('a routine cannot be both async and generator');
  if isAsync and isAsmFunc then
    Error('a routine cannot be both async and assembler');
  { `stackless` selects the state-machine backend; valid after `generator` or
    `async`, meaningless on its own. }
  if isStackless and not (isGenerator or isAsync) then
    Error('stackless directive is only valid on a generator or async routine');

  { External binding: `procedure foo(...); cdecl; external 'libname.so' [name 'sym'];`
    Marks the routine as a dynamically-linked import. Symbol defaults to the
    routine's own name (GTK symbols are valid lowercase identifiers); an
    optional `name 'sym'` clause overrides the emitted symbol. }
  if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'external') then
  begin
    Next;
    extLib := '';
    if CurTok.Kind = tkString then begin extLib := CurTok.SVal; Next; end;
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'name') then
    begin
      Next;
      if CurTok.Kind = tkString then begin name := CurTok.SVal; Next; end;
    end;
    Eat(tkSemicolon);
    pi := FindProcOverload(name, nparams, ptypes, parr, pbyref);
    if pi < 0 then
      pi := RegisterProc(name, isFunc, retType, nparams, pnames, ptypes);
    ProcRetRecId[pi] := retRecId;
    for i := 0 to nparams-1 do
    begin
      Procs[pi].Params[i].IsArray := parr[i];
      Procs[pi].Params[i].IsRef := pbyref[i];
    end;
    Procs[pi].BodyAddr := -1;
    ProcExternal[pi] := True;
    ProcLibrary[pi] := InternStr(extLib);
    Exit;
  end;

  { Inject implicit Self parameter at index 0 for methods (unless static) }
  isStaticMethod := False;
  if methOwnerCi >= 0 then
  begin
    mmi := FindUMeth(methOwnerCi, methName);
    if mmi >= 0 then
      if UMthIsStatic[mmi] then
        isStaticMethod := True;
  end;

  if (methOwnerCi >= 0) and not isStaticMethod then
  begin
    for i := nparams downto 1 do
    begin
      pnames[i] := pnames[i-1];
      ptypes[i] := ptypes[i-1];
      ptypesRec[i] := ptypesRec[i-1];
      ptypesPtrElemTk[i] := ptypesPtrElemTk[i-1];
      ptypesPtrElemRec[i] := ptypesPtrElemRec[i-1];
      ptypesProcSig[i] := ptypesProcSig[i-1];
      parr[i]   := parr[i-1];
      pbyref[i] := pbyref[i-1];
      pNDims[i] := pNDims[i-1];
      pDynDepth[i] := pDynDepth[i-1];
      for pdi := 0 to MAX_ARR_DIMS - 1 do
      begin
        pDimLo[i * MAX_ARR_DIMS + pdi]   := pDimLo[(i-1) * MAX_ARR_DIMS + pdi];
        pDimSpan[i * MAX_ARR_DIMS + pdi] := pDimSpan[(i-1) * MAX_ARR_DIMS + pdi];
      end;
    end;
    pnames[0] := 'Self';
    ptypes[0] := tyClass;
    ptypesRec[0] := REC_NONE;   { Self's RecName is wired to the owner class below }
    ptypesPtrElemTk[0] := tyUnknown;
    ptypesPtrElemRec[0] := REC_NONE;
    ptypesProcSig[0] := -1;
    parr[0]   := False;
    pbyref[0] := False;
    pNDims[0] := 0;
    pDynDepth[0] := 0;
    nparams := nparams + 1;
  end;

  { Stackless generator: rewrite the ABI to `function(__genself: Pointer): Boolean`.
    The declared params/result describe the produced SEQUENCE; the step function
    itself takes the heap-instance pointer and returns has-next. Declared params
    shift to 1..n and become persistent locals (restored from the instance each
    step); the declared (yielded) element type is remembered for for-in loop-var
    typing. }
  if isStackless then
  begin
    if methOwnerCi >= 0 then
      Error('stackless generator/async methods are not supported (v1)');
    if isAsync then
    begin
      { async stackless takes no declared params in v1 (the coroutine carries its
        own state in persistent locals); the spawn surface allocs the instance. }
      if nparams > 0 then
        Error('async stackless: parameters are not supported in v1');
      isFunc := True;     { a procedure becomes the function(self): Boolean step }
    end;
    declElemTk := Ord(retType);
    for i := nparams downto 1 do
    begin
      pnames[i] := pnames[i-1];
      ptypes[i] := ptypes[i-1];
      ptypesRec[i] := ptypesRec[i-1];
      ptypesPtrElemTk[i] := ptypesPtrElemTk[i-1];
      ptypesPtrElemRec[i] := ptypesPtrElemRec[i-1];
      ptypesProcSig[i] := ptypesProcSig[i-1];
      parr[i]   := parr[i-1];
      pbyref[i] := pbyref[i-1];
      pNDims[i] := pNDims[i-1];
      pDynDepth[i] := pDynDepth[i-1];
      for pdi := 0 to MAX_ARR_DIMS - 1 do
      begin
        pDimLo[i * MAX_ARR_DIMS + pdi]   := pDimLo[(i-1) * MAX_ARR_DIMS + pdi];
        pDimSpan[i * MAX_ARR_DIMS + pdi] := pDimSpan[(i-1) * MAX_ARR_DIMS + pdi];
      end;
    end;
    pnames[0] := '__genself';
    ptypes[0] := tyPointer;
    ptypesRec[0] := REC_NONE;
    ptypesPtrElemTk[0] := tyUnknown;
    ptypesPtrElemRec[0] := REC_NONE;
    ptypesProcSig[0] := -1;
    parr[0]   := False;
    pbyref[0] := False;
    pNDims[0] := 0;
    pDynDepth[0] := 0;
    nparams := nparams + 1;
    retType := tyBoolean;
  end;

  if (name = 'LoadFile') or (name = 'loadfile') then
  begin
    while not (CurTok.Kind in [tkBegin, tkEOF]) do Next;
    if CurTok.Kind = tkBegin then
    begin
      depth := 1;
      Next;
      while (depth > 0) and (CurTok.Kind <> tkEOF) do
      begin
        if CurTok.Kind = tkBegin then Inc(depth)
        else if CurTok.Kind = tkEnd then Dec(depth);
        Next;
      end;
      Eat(tkSemicolon);
    end;
    Exit;
  end;

  { Forward declaration or interface declaration? }
  if (CurTok.Kind = tkForward) or InInterface then
  begin
    if CurTok.Kind = tkForward then
    begin
      Next; Eat(tkSemicolon);
    end;
    pi := FindProcOverload(name, nparams, ptypes, parr, pbyref);
    if pi < 0 then
    begin
      if StrictOverload and (FindProc(name) >= 0) then
      begin
        if not declOverload then Error('overloaded routine requires overload directive');
        if HasNonOverloadProc(name) then Error('all overloaded routines require overload directive');
      end;
      pi := RegisterProc(name, isFunc, retType, nparams, pnames, ptypes);
      ProcRetRecId[pi] := retRecId;
      ProcOverloadDirective[pi] := declOverload;
      Procs[pi].BodyAddr := -1;
      for i := 0 to nparams-1 do
      begin
        Procs[pi].Params[i].IsArray := parr[i];
        Procs[pi].Params[i].IsRef := pbyref[i];
      end;
    end
    else if declOverload then
      ProcOverloadDirective[pi] := True;
    ProcRetRecId[pi] := retRecId;
    ProcRetIsDynArray[pi] := retIsDynArr;
    ProcRetElemTk[pi] := retElemTk;
    ProcRetElemRec[pi] := retElemRec;
    ProcRetPtrElemTk[pi] := retPtrElemTk;
    ProcRetPtrElemRec[pi] := retPtrElemRec;
    if retIsDynArr then Procs[pi].RetType := tyPointer; { 8-byte heap handle ABI }
    Exit;
  end;

  { Register or resolve }
  pi := FindProcOverload(name, nparams, ptypes, parr, pbyref);
  if pi < 0 then
  begin
    if StrictOverload and (FindProc(name) >= 0) then
    begin
      if not declOverload then Error('overloaded routine requires overload directive');
      if HasNonOverloadProc(name) then Error('all overloaded routines require overload directive');
    end;
    pi := RegisterProc(name, isFunc, retType, nparams, pnames, ptypes);
    ProcOverloadDirective[pi] := declOverload;
  end
  else if declOverload then
    ProcOverloadDirective[pi] := True;
  ProcRetRecId[pi] := retRecId;
  ProcRetIsDynArray[pi] := retIsDynArr;
  ProcRetElemTk[pi] := retElemTk;
  ProcRetElemRec[pi] := retElemRec;
  ProcRetPtrElemTk[pi] := retPtrElemTk;
  ProcRetPtrElemRec[pi] := retPtrElemRec;
  ProcIsAsync[pi] := isAsync;
  ProcIsGenerator[pi] := isGenerator;
  ProcIsStackless[pi] := isStackless;
  if isInterrupt then
    Error('interrupt directive: raw hardware-vector codegen (full register save/restore + iret) not yet implemented; use `iram;` for an IDF-registered ISR');
  { `iram;` places the body in .iram1.text on ESP; on other targets (e.g. the
    x86-64 oracle build of a shared test) it is an accepted no-op. }
  ProcIram[pi] := isIram and ((TargetArch = TARGET_XTENSA) or (TargetArch = TARGET_RISCV32));
  ProcIsInterrupt[pi] := isInterrupt;
  if isStackless then
  begin
    ProcGenElemTk[pi] := IntToTypeKind(declElemTk);
    ProcGenParamCnt[pi] := nparams - 1;   { exclude the injected __genself }
    if (nparams - 1) > CO_MAX_PARAMS then
      Error('generator: at most 4 parameters in v1');
  end
  else if isGenerator and (nparams > CO_MAX_PARAMS) then
    Error('generator: at most 4 parameters in v1');
  if retIsDynArr then Procs[pi].RetType := tyPointer; { 8-byte heap handle ABI }
  if TargetArch = TARGET_XTENSA then
    while (CodeLen mod 4) <> 0 do xtensa_nop; { CALL0 targets must be 4-aligned }
  Procs[pi].BodyAddr := CodeLen;
  for i := 0 to nparams-1 do
  begin
    Procs[pi].Params[i].IsArray := parr[i];
    Procs[pi].Params[i].IsRef := pbyref[i];
  end;

  { Save scope }
  savedSC := SymCount;
  savedFS := FrameSize;
  savedGLC := GotoLabelCount;
  savedGFC := GotoFixupCount;
  savedProcCleanupFrameActive := ProcExceptionCleanupFrameActive;
  ProcExceptionCleanupFrameActive := False;
  GotoLabelCount := 0;
  GotoFixupCount := 0;
  for j := 0 to MAX_GOTO_LABELS - 1 do GotoLabelIRId[j] := -1;
  FrameSize := 0;
  CurProc := pi;
  Procs[pi].ScopeBase := SymCount;

  { Set method context before allocating params }
  if methOwnerCi >= 0 then
  begin
    mmi := FindUMeth(methOwnerCi, methName);
    if mmi >= 0 then
    begin
      UMthProc_[mmi] := pi;
    end
    else
    begin
      AddUMeth(methOwnerCi, methSNOff, methSNLen, pi);
      mmi := UMthCount - 1;
    end;

    if not UMthIsStatic[mmi] then
      CurSelfClass := methOwnerRec;

    if UMthVirSlot[mmi] >= 0 then
    begin
      slot := UMthVirSlot[mmi];
      if MethodFixCount >= MAX_METHFIX then Error('too many virtual method fixups');
      MethodFixups[MethodFixCount].DataPos := UClsVMTOffset[methOwnerCi] + slot * 8;
      MethodFixups[MethodFixCount].ProcIdx := pi;
      Inc(MethodFixCount);

      for otherCi := 0 to UClsCount-1 do
      begin
        if IsSubclassOf(otherCi, methOwnerCi) then
        begin
          if MethodFixCount >= MAX_METHFIX then Error('too many virtual method fixups');
          MethodFixups[MethodFixCount].DataPos := UClsVMTOffset[otherCi] + slot * 8;
          MethodFixups[MethodFixCount].ProcIdx := pi;
          Inc(MethodFixCount);
        end;
      end;
    end;
  end;

  { Allocate param slots }
  for i := 0 to nparams-1 do
  begin
    idx := AllocParam(pnames[i], ptypes[i], pbyref[i], parr[i]);
    Procs[pi].Params[i].SymIdx := idx;
    if pDynDepth[i] > 0 then
    begin
      { Named dynamic-array type param: a real dynamic array, NOT an open-array
        fat ptr. ArrLen = -1 routes SetLength to -102; SymDynDepth drives nested
        element typing. When var/out, the slot will hold &caller_slot (see the
        call-site lowering + the IsRef read-deref). }
      Syms[idx].ArrLen := -1;
      SymDynDepth[idx] := pDynDepth[i];
      if (pi >= 0) and (i < 16) then ProcParamDynDepth[pi * 16 + i] := pDynDepth[i];
    end;
    if pNDims[i] >= 2 then
    begin
      SymArrNDims[idx] := pNDims[i];
      for pdi := 0 to pNDims[i] - 1 do
      begin
        SymArrDimLo[idx * MAX_ARR_DIMS + pdi]   := pDimLo[i * MAX_ARR_DIMS + pdi];
        SymArrDimSpan[idx * MAX_ARR_DIMS + pdi] := pDimSpan[i * MAX_ARR_DIMS + pdi];
      end;
    end;
    if parr[i] and (ptypes[i] = tyRecord) then
    begin
      { Open array of records (e.g. `array of const`): the slot holds a dyn-array
        data pointer; element type/record live in ElemType/ElemRecName, not a
        by-value RecName, and it must NOT be promoted to by-ref. }
      Syms[idx].ElemType := tyRecord;
      Syms[idx].ElemRecName := ptypesRec[i];
    end
    else if (ptypes[i] = tyClass) or (ptypes[i] = tyRecord) then
    begin
      Syms[idx].RecName := ptypesRec[i];
      { Persist the param's rec id: param sym slots are reused across procs, so
        overload matching / call-arg coercion cannot read it back from the sym. }
      if (pi >= 0) and (i < 16) then ProcParamRecId[pi * 16 + i] := ptypesRec[i];
      { Records larger than a qword are passed by reference. A CORBA interface is
        a fat pointer ({IMT, instance}); on 64-bit that is 16 bytes (already >8),
        but on 32-bit targets it is only 8 bytes — force by-ref there too so the
        whole fat pointer crosses the call uniformly instead of being squeezed
        into one machine word. (No-op on 64-bit, so self-host stays identical.) }
      if (ptypes[i] = tyRecord) and
         ((RecSize(ptypesRec[i]) > 8) or
          ((ptypesRec[i] >= REC_UCLASS_BASE) and UClsIsInterface[ptypesRec[i] - REC_UCLASS_BASE])) then
      begin
        Syms[idx].IsRef := True;
        Procs[pi].Params[i].IsRef := True;
      end;
    end;
    if ptypes[i] = tyPointer then
    begin
      Syms[idx].PtrElemTk := ptypesPtrElemTk[i];
      Syms[idx].PtrElemRec := ptypesPtrElemRec[i];
      SymProcSig[idx] := ptypesProcSig[i];
    end;
  end;
  { Wire Self's RecName so field lookups resolve against the owner class }
  if (methOwnerCi >= 0) and not isStaticMethod then
    Syms[Procs[pi].Params[0].SymIdx].RecName := methOwnerRec;

  { Return value slot }
  if isFunc then
  begin
    savedLastTypeRecId := LastTypeRecId;
    if retType = tyRecord then
      LastTypeRecId := ProcRetRecId[pi];
    if retIsDynArr then
    begin
      { Result is a dynamic array: a pointer-sized local heap handle. Indexing,
        Length, and SetLength operate on it like any dyn-array local. }
      LastTypeRecId := retElemRec;
      idx := AllocDynArray('Result', retElemTk, 1);
      Procs[pi].RetSymIdx := idx;
    end
    else if retType = tyString then
    begin
      savedCurProc := CurProc;
      CurProc := -1;
      AllocVar('Result', retType);
      CurProc := savedCurProc;
      Procs[pi].RetSymIdx := SymCount - 1;
      Syms[SymCount-1].Kind := skGlobal;
    end
    else
    begin
      AllocVar('Result', retType);
      Procs[pi].RetSymIdx := SymCount - 1;
      Syms[SymCount-1].Kind := skLocal;
    end;
    LastTypeRecId := savedLastTypeRecId;
    if not retIsDynArr and TypeIsAggregate(retType) then
    begin
      idx := AllocVar('', tyPointer);
      ProcAggregateDestSym[pi] := idx;
    end;
  end;

  { Generator body context: a `; generator;` routine is compiled as a stackful
    coroutine body (see lib/rtl/coroutine.pas). Allocate a hidden self-pointer
    local; the body prologue copies the instance ptr (handed off in rbx by
    CoSwitch) into it, then loads params from the instance. yield/finish use it.
    Save/restore any enclosing generator context for nested routine defs. }
  savedGenIsGen := CurProcIsGenerator;
  savedGenSelf  := CurGenSelfSym;
  savedGenSeen  := CurGenSeenYield;
  savedGenTry   := GenTryDepth;
  savedGenStackless := CurProcIsStackless;
  savedGenStateCtr  := CurGenStateCtr;
  savedGenSlotNext  := CurGenSlotNext;
  savedProcIsAsync  := CurProcIsAsync;
  CurProcIsAsync := isAsync;
  CurProcIsGenerator := isGenerator;
  CurProcIsStackless := isStackless;
  CurGenSelfSym := -1;
  CurGenSeenYield := False;
  GenTryDepth := 0;
  if isGenerator and not isStackless then
  begin
    { Stackful lowering: the body runs on a heap coroutine stack, swapped in by
      CoSwitch (x86-64 asm). The instance pointer arrives in the rbx slot. }
    if TargetArch <> TARGET_X86_64 then
      Error('generator: only the x86-64 target is supported for the stackful backend (use `stackless` for other targets)');
    EnableCoroutineRuntime;
    genSelfIdx := AllocVar('', tyPointer);   { hidden self pointer }
    CurGenSelfSym := genSelfIdx;
  end;

  { Prologue }
  patchPos := EmitProcPrologue;
  Procs[pi].FramePatch := patchPos;
  if ProcAggregateDestSym[pi] >= 0 then
  begin
    idx := ProcAggregateDestSym[pi];
    if TargetArch = TARGET_I386 then
      { i386 carries the hidden destination pointer in ecx; stash it before the
        param-copy loop clobbers ecx. }
      begin EmitB($89); EmitB($8D); EmitI32(Syms[idx].Offset); end { mov [ebp+off], ecx }
    else if TargetArch = TARGET_AARCH64 then
    begin
      { aarch64 carries the hidden destination in x8 (AAPCS XR). }
      EmitLoadImmA64(9, Syms[idx].Offset);
      EmitI32($8B0903A9);                                 { add x9, x29, x9 }
      EmitI32($F9000128);                                 { str x8, [x9] }
    end
    else if TargetArch = TARGET_ARM32 then
    begin
      { arm32 carries the hidden destination in r12 (ip, a scratch reg). }
      EmitLoadImmArm32(9, Syms[idx].Offset);
      EmitI32($E08B9009);                                 { add r9, fp, r9 }
      EmitI32($E589C000);                                 { str r12, [r9] }
    end
    else
      begin EmitB($4C); EmitB($89); EmitB($95); EmitI32(Syms[idx].Offset); end; { mov [rbp+off], r10 }
  end;

  if TargetArch = TARGET_I386 then
  begin
    { i386 internal convention: the caller evaluated and pushed args left to
      right (leftmost ends up deepest), so param i of n sits at
      [ebp + 8 + (n-1-i)*4]. Copy each into its frame slot; the caller cleans
      the arg area after the call. Ordinal by-value params only for now. }
    for i := 0 to nparams-1 do
    begin
      idx := Procs[pi].Params[i].SymIdx;
      { Ordinals and pointer-sized handles (pointer/string/class) are passed as
        one 4-byte stack slot. 8-byte ordinals (Int64) use the low dword only,
        consistent with the rest of the i386 backend's fat-slot model. }
      { A by-ref param (var/const aggregate) is a pointer-sized handle whatever
        its declared type, and the caller pushes the argument's address; the
        4-byte copy below moves that pointer into the slot. tyVariant is passed
        the same way (pointer to the 16-byte value). Reject only true >4-byte
        by-value payloads (records/sets; Int64 is still low-dword only). }
      if (not Syms[idx].IsRef) and (not Syms[idx].IsArray) and
         not (TypeIsOrdinal(Syms[idx].TypeKind) or
              TypeIsFloat(Syms[idx].TypeKind) or
              (Syms[idx].TypeKind in [tyString, tyAnsiString, tyPointer, tyClass, tyVariant])) then
        Error('target i386: only ordinal/pointer parameters supported yet');
      sz := 0;
      for j := i + 1 to nparams - 1 do
      begin
        if parr[j] then
        begin
          { Open-array param stack width must match how the caller pushes the
            argument (the i386 caller dispatches on the param's element type, so
            `ptypes[j]` here is the element type). A 64-bit element (Int64/UInt64/
            Double) goes through the 8-byte push path; `array of const` (a single
            dyn-array handle) and 32-bit-element open arrays are one 4-byte slot.
            NOTE: regular open arrays don't yet carry a real high word, so
            Length() over them is unreliable — tracked separately. }
          if (ptypes[j] = tyInt64) or (ptypes[j] = tyUInt64) or (ptypes[j] = tyDouble) then
            Inc(sz, 8)
          else
            Inc(sz, 4);
        end
        else if pbyref[j] or (ptypes[j] = tyString) or
           (ptypes[j] in [tyAnsiString, tyPointer, tyClass, tyVariant]) then
          Inc(sz, 4)
        else if ptypes[j] = tyDouble then
          Inc(sz, 8)
        else if ptypes[j] = tySingle then
          Inc(sz, 4)
        else if (ptypes[j] = tyInt64) or (ptypes[j] = tyUInt64) then
          Inc(sz, 8)                                 { 64-bit by-value param }
        else
          Inc(sz, 4);
      end;
      if Syms[idx].TypeKind = tyDouble then
      begin
        EmitB($8B); EmitB($85); EmitI32(8 + sz);     { mov eax, [ebp+disp] }
        EmitB($89); EmitB($85); EmitI32(Syms[idx].Offset);
        EmitB($8B); EmitB($85); EmitI32(12 + sz);    { mov eax, [ebp+disp+4] }
        EmitB($89); EmitB($85); EmitI32(Syms[idx].Offset + 4);
      end
      else if (not Syms[idx].IsRef) and (not Syms[idx].IsArray) and
              ((Syms[idx].TypeKind = tyInt64) or (Syms[idx].TypeKind = tyUInt64)) then
      begin
        { Int64/UInt64 by-value param: the caller pushes both dwords (8-byte arg
          slot), so copy the full 64-bit value into the frame slot. }
        EmitB($8B); EmitB($85); EmitI32(8 + sz);     { mov eax, [ebp+disp] }
        EmitB($89); EmitB($85); EmitI32(Syms[idx].Offset);            { mov [off], eax }
        EmitB($8B); EmitB($85); EmitI32(12 + sz);    { mov eax, [ebp+disp+4] }
        EmitB($89); EmitB($85); EmitI32(Syms[idx].Offset + 4);        { mov [off+4], eax }
      end
      else
      begin
        EmitB($8B); EmitB($85); EmitI32(8 + sz);     { mov eax, [ebp+disp] }
        { Store at the param's type width: frame slots are packed by size, so a
          1-byte char/boolean sits adjacent to the next slot. A blanket 4-byte
          store would clobber that neighbour (e.g. a var-param pointer next to a
          Char arg). By-ref/array/handle params are always 4-byte. }
        if (not Syms[idx].IsRef) and (not Syms[idx].IsArray) and
           not (Syms[idx].TypeKind in [tyString, tyAnsiString, tyPointer, tyClass, tyVariant]) and
           (TypeSize(Syms[idx].TypeKind) = 1) then
          begin EmitB($88); EmitB($85); EmitI32(Syms[idx].Offset); end          { mov [ebp+off], al }
        else if (not Syms[idx].IsRef) and (not Syms[idx].IsArray) and
           not (Syms[idx].TypeKind in [tyString, tyAnsiString, tyPointer, tyClass, tyVariant]) and
           (TypeSize(Syms[idx].TypeKind) = 2) then
          begin EmitB($66); EmitB($89); EmitB($85); EmitI32(Syms[idx].Offset); end { mov [ebp+off], ax }
        else
          begin EmitB($89); EmitB($85); EmitI32(Syms[idx].Offset); end;          { mov [ebp+off], eax }
      end;
    end;
  end
  else if TargetArch = TARGET_AARCH64 then
  begin
    for i := 0 to nparams-1 do
    begin
      idx := Procs[pi].Params[i].SymIdx;
      sz := ParamSize(idx);
      if i < 8 then
      begin
        { Load local offset into x9 }
        EmitLoadImmA64(9, Syms[idx].Offset);
        { add x8, x29, x9 }
        EmitI32($8B0903A8);
        { Store parameter register i (x0..x7) into [x8] }
        if sz = 1 then
          EmitI32($39000100 + i)
        else if sz = 2 then
          EmitI32($79000100 + i)
        else if sz = 4 then
          EmitI32($B9000100 + i)
        else
          EmitI32($F9000100 + i);
      end
      else
      begin
        { Stack-passed param (AAPCS): the caller left args 8.. in an outgoing
          block; after the prologue `stp x29,x30,[sp,#-16]!` the incoming block
          sits at [x29 + 16 + (i-8)*8]. Copy it into this param's local slot. }
        EmitLoadImmA64(9, 16 + (i - 8) * 8);
        EmitI32($8B0903A8);              { add x8, x29, x9  -> &incoming arg }
        EmitI32($F9400109);              { ldr x9, [x8]     -> arg value }
        EmitLoadImmA64(10, Syms[idx].Offset);
        EmitI32($8B0A03A8);              { add x8, x29, x10 -> &local slot }
        if sz = 1 then
          EmitI32($39000109)            { strb w9, [x8] }
        else if sz = 2 then
          EmitI32($79000109)            { strh w9, [x8] }
        else if sz = 4 then
          EmitI32($B9000109)            { str w9, [x8] }
        else
          EmitI32($F9000109);           { str x9, [x8] }
      end;
    end;
  end
  else if TargetArch = TARGET_ARM32 then
  begin
    { Word-based spill: each scalar param is one machine word, an Int64/UInt64
      param is two (lo then hi). Word k arrives in r[k] when k<4, else on the
      stack at [fp + 8 + (pnWords-1-k)*4] (the caller pushed words in index
      order, leaving the lowest-index stack word at the highest address; see
      ir_codegen_arm32.inc IR_CALL). }
    { A by-ref or open-array Int64 param is a single pointer word, not a 64-bit
      value, so only count/spill it as two words when passed by value. }
    pnWords := 0;
    for i := 0 to nparams-1 do
      if ((Procs[pi].Params[i].TypeKind = tyInt64) or
          (Procs[pi].Params[i].TypeKind = tyUInt64)) and
         (not Procs[pi].Params[i].IsRef) and (not Procs[pi].Params[i].IsArray) then
        Inc(pnWords, 2)
      else Inc(pnWords, 1);
    pw := 0;
    for i := 0 to nparams-1 do
    begin
      idx := Procs[pi].Params[i].SymIdx;
      sz := ParamSize(idx);
      EmitLoadImmArm32(9, Syms[idx].Offset);
      EmitI32($E08B9009);   { add r9, fp, r9 (slot addr) }
      if ((Syms[idx].TypeKind = tyInt64) or (Syms[idx].TypeKind = tyUInt64)) and
         (not Syms[idx].IsRef) and (not Syms[idx].IsArray) then
      begin
        { lo = word pw -> [r9]; hi = word pw+1 -> [r9, #4] }
        if pw < 4 then EmitI32($E5890000 or (pw shl 12))
        else begin EmitI32($E59B0000 or (8 + (pnWords-1-pw)*4)); EmitI32($E5890000); end;
        whi := pw + 1;
        if whi < 4 then EmitI32($E5890004 or (whi shl 12))
        else begin EmitI32($E59B0000 or (8 + (pnWords-1-whi)*4)); EmitI32($E5890004); end;
        Inc(pw, 2);
      end
      else
      begin
        if pw < 4 then
        begin
          if sz = 1 then EmitI32($E5C90000 or (pw shl 12))  { strb r[pw], [r9] }
          else if sz = 2 then EmitI32($E1C900B0 or (pw shl 12))
          else EmitI32($E5890000 or (pw shl 12));            { str r[pw], [r9] }
        end
        else
        begin
          EmitI32($E59B0000 or (8 + (pnWords - 1 - pw) * 4)); { ldr r0, [fp, #off] }
          if sz = 1 then EmitI32($E5C90000)
          else if sz = 2 then EmitI32($E1C900B0)
          else EmitI32($E5890000);
        end;
        Inc(pw, 1);
      end;
    end;
  end
  else if TargetArch = TARGET_RISCV32 then
  begin
    { RV32 convention: args arrive in a0..a7; spill each into its frame slot.
      8-byte ordinals store the low word only (fat-slot model, like i386). }
    for i := 0 to nparams-1 do
    begin
      idx := Procs[pi].Params[i].SymIdx;
      sz := ParamSize(idx);
      if i >= 8 then
        Error('target riscv32: more than 8 parameters not yet supported');
      EmitLoadImmRISCV32(reg_t0, Syms[idx].Offset);
      rv32_add(reg_t0, reg_s0, reg_t0);
      if sz = 1 then
        rv32_sb(reg_a0 + i, reg_t0, 0)
      else if sz = 2 then
        rv32_sh(reg_a0 + i, reg_t0, 0)
      else
        rv32_sw(reg_a0 + i, reg_t0, 0);
    end;
  end
  else if TargetArch = TARGET_XTENSA then
  begin
    { Call0 ABI: args arrive in a2..a7; spill each into its frame slot. }
    for i := 0 to nparams-1 do
    begin
      idx := Procs[pi].Params[i].SymIdx;
      sz := ParamSize(idx);
      if i >= 6 then
        Error('target xtensa: more than 6 parameters not yet supported');
      if XtensaABI = XTENSA_ABI_WINDOWED then
      begin
        if (Syms[idx].Offset >= -128) and (Syms[idx].Offset <= 127) then
          xtensa_addi(reg_xtensa_a8, reg_xtensa_a15, Syms[idx].Offset)
        else
          Error('target xtensa windowed: parameter frame offset out of range');
      end
      else
        EmitFrameAddrXtensa(reg_xtensa_a8, Syms[idx].Offset);
      if sz = 1 then
        xtensa_s8i(reg_xtensa_a2 + i, reg_xtensa_a8, 0)
      else if sz = 2 then
        xtensa_s16i(reg_xtensa_a2 + i, reg_xtensa_a8, 0)
      else
        xtensa_s32i(reg_xtensa_a2 + i, reg_xtensa_a8, 0);
    end;
    if XtensaABI = XTENSA_ABI_WINDOWED then
      xtensa_mov(reg_xtensa_a7, reg_xtensa_a15);
  end
  else
  if nparams > 6 then
  begin
    { All-stack internal convention for procs with more than 6 parameters
      (bug-many-param-call-corruption: the register convention silently
      shifted arguments). The caller pushed every arg left to right and
      cleans up after the call, so param i of n sits at
      [rbp + 16 + (n-1-i)*8]. Copy each into its frame slot. }
    for i := 0 to nparams-1 do
    begin
      idx := Procs[pi].Params[i].SymIdx;
      sz := ParamSize(idx);
      EmitB($48); EmitB($8B); EmitB($85);
      EmitI32(16 + (nparams - 1 - i) * 8);        { mov rax, [rbp+disp] }
      if sz = 1 then
      begin
        EmitB($88); EmitB($85);                   { mov [rbp+off], al }
      end
      else if sz = 2 then
      begin
        EmitB($66); EmitB($89); EmitB($85);       { mov [rbp+off], ax }
      end
      else if sz = 4 then
      begin
        EmitB($89); EmitB($85);                   { mov [rbp+off], eax }
      end
      else
      begin
        EmitB($48); EmitB($89); EmitB($85);       { mov [rbp+off], rax }
      end;
      EmitI32(Syms[idx].Offset);
    end;
  end
  else
  { Copy params from registers to stack: mov [rbp+off], rdi/rsi/rdx/rcx/r8/r9 }
  for i := 0 to nparams-1 do
  begin
    idx := Procs[pi].Params[i].SymIdx;
    sz := ParamSize(idx);
    if i < 4 then
    begin
      if sz = 1 then
      begin
        if (i = 0) or (i = 1) then EmitB($40); { REX prefix for dil, sil }
        EmitB($88);
      end
      else if sz = 2 then
      begin
        EmitB($66); EmitB($89);
      end
      else if sz = 4 then
      begin
        EmitB($89);
      end
      else
      begin
        EmitB($48); EmitB($89);
      end;

      case i of
        0: EmitB($BD);   { rdi }
        1: EmitB($B5);   { rsi }
        2: EmitB($95);   { rdx }
        3: EmitB($8D);   { rcx }
      end;
      EmitI32(Syms[idx].Offset);
    end
    else if i = 4 then
    begin
      if sz = 1 then
      begin
        EmitB($44); EmitB($88); EmitB($85);
      end
      else if sz = 2 then
      begin
        EmitB($66); EmitB($44); EmitB($89); EmitB($85);
      end
      else if sz = 4 then
      begin
        EmitB($44); EmitB($89); EmitB($85);
      end
      else
      begin
        EmitB($4C); EmitB($89); EmitB($85);
      end;
      EmitI32(Syms[idx].Offset);
    end
    else if i = 5 then
    begin
      if sz = 1 then
      begin
        EmitB($44); EmitB($88); EmitB($8D);
      end
      else if sz = 2 then
      begin
        EmitB($66); EmitB($44); EmitB($89); EmitB($8D);
      end
      else if sz = 4 then
      begin
        EmitB($44); EmitB($89); EmitB($8D);
      end
      else
      begin
        EmitB($4C); EmitB($89); EmitB($8D);
      end;
      EmitI32(Syms[idx].Offset);
    end;
  end;

  { Optional var/const/type/label sections }
  while CurTok.Kind in [tkVar, tkConst, tkType] do
    case CurTok.Kind of
      tkVar:   ParseVarSection;
      tkConst: ParseConstSection;
      tkType:  ParseTypeSection;
    end;
  { Managed locals (dynamic arrays, AnsiStrings, and records/arrays containing
    them) hold managed pointer slots. Zero their full extent before the body so
    a first SetLength / assignment sees nil rather than stale stack bytes — and
    so an ARC-correct whole-record copy can safely release the (nil) old fields. }
  for i := savedSC to SymCount - 1 do
    if Syms[i].Kind = skLocal then
    begin
      zeroBytes := 0;
      if Syms[i].IsArray and (Syms[i].ArrLen = -1) then
        zeroBytes := TARGET_PTR_SIZE                          { dyn-array handle }
      else if Syms[i].TypeKind = tyAnsiString then
      begin
        if Syms[i].IsArray then
          zeroBytes := Syms[i].ArrLen * TARGET_PTR_SIZE       { static array of AnsiString }
        else
          zeroBytes := TARGET_PTR_SIZE;                       { scalar AnsiString }
      end
      else if Syms[i].TypeKind = tyVariant then
        zeroBytes := TypeSize(tyVariant)
      else if (Syms[i].TypeKind = tyRecord) and not Syms[i].IsArray and
              RecordHasManagedFields(Syms[i].RecName) then
        zeroBytes := RecSize(Syms[i].RecName)
      else if (Syms[i].TypeKind = tyRecord) and Syms[i].IsArray and
              RecordHasManagedFields(Syms[i].ElemRecName) then
        zeroBytes := Syms[i].ArrLen * RecSize(Syms[i].ElemRecName)
      else if SymIsComInterface(i) then
        { COM/ARC interface fat pointer: must start nil so the ARC release at
          first overwrite / scope exit sees an empty slot, not stale stack bytes
          (a garbage IMT would dispatch _Release into nowhere). }
        zeroBytes := RecSize(Syms[i].RecName);
      { i386: only pointer-sized managed handles (scalar AnsiString / dyn-array)
        are supported; the larger managed aggregates (records/variants/arrays of
        managed) are not on this target yet. }
      if (zeroBytes > TARGET_PTR_SIZE) and (TargetArch = TARGET_ARM32) then
      begin
        { Zero the full extent of a managed-aggregate local (record with managed
          fields / variant / array of managed) so first use sees nil fields and
          an ARC-correct copy releases nil, not stale stack bytes. Byte loop. }
        EmitLoadImmArm32(0, Syms[i].Offset);
        EmitI32($E08B0000);                  { add r0, fp, r0 (dest) }
        EmitLoadImmArm32(1, zeroBytes);       { r1 = count }
        EmitI32($E3A02000);                  { mov r2, #0 }
        zfLoop := CodeLen;
        EmitI32($E3510000);                  { cmp r1, #0 }
        zfDone := CodeLen; EmitI32($0A000000); { beq done }
        EmitI32($E5C02000);                  { strb r2, [r0] }
        EmitI32($E2800001);                  { add r0, r0, #1 }
        EmitI32($E2411001);                  { sub r1, r1, #1 }
        EmitI32($EA000000 or ((((zfLoop - CodeLen) div 4) - 2) and $00ffffff)); { b loop }
        Patch32(zfDone, $0A000000 or ((((CodeLen - zfDone) div 4) - 2) and $00ffffff));
      end
      else if (zeroBytes > TARGET_PTR_SIZE) and (TargetArch = TARGET_AARCH64) then
      begin
        EmitLoadImmA64(9, Syms[i].Offset);
        EmitI32($8B0903A0);                  { add x0, x29, x9 (dest) }
        EmitLoadImmA64(1, zeroBytes);         { x1 = count }
        pi := FindProc('PXXMemZero');
        if pi < 0 then Error('compiler error: PXXMemZero not found');
        EmitCallProc(pi);
      end
      else if (zeroBytes > TARGET_PTR_SIZE) and (TargetArch = TARGET_I386) then
      begin
        EmitB($8D); EmitB($85); EmitI32(Syms[i].Offset); { lea eax, [ebp+off] }
        EmitB($50);                                      { push dest }
        EmitB($68); EmitI32(zeroBytes);                  { push count }
        pi := FindProc('PXXMemZero');
        if pi < 0 then Error('compiler error: PXXMemZero not found');
        EmitCallProc(pi);
        EmitB($81); EmitB($C4); EmitI32(8);              { add esp, 8 }
      end
      else if (zeroBytes > TARGET_PTR_SIZE) and (TargetArch <> TARGET_X86_64) then
        Error('target: managed aggregate locals not yet supported');
      if (zeroBytes = TARGET_PTR_SIZE) and (TargetArch = TARGET_I386) then
      begin
        EmitB($C7); EmitB($85); EmitI32(Syms[i].Offset); EmitI32(0);  { mov dword [ebp+off], 0 }
      end
      else if (zeroBytes = TARGET_PTR_SIZE) and (TargetArch = TARGET_ARM32) then
      begin
        EmitLoadImmArm32(9, Syms[i].Offset);
        EmitI32($E08B9009);                                          { add r9, fp, r9 }
        EmitI32($E3A00000);                                          { mov r0, #0 }
        EmitI32($E5890000);                                          { str r0, [r9] }
      end
      else if (zeroBytes = TARGET_PTR_SIZE) and (TargetArch = TARGET_AARCH64) then
      begin
        EmitLoadImmA64(9, Syms[i].Offset);
        EmitI32($8B0903A9);                                          { add x9, x29, x9 }
        EmitI32($F900013F);                                          { str xzr, [x9] }
      end
      else if (zeroBytes = TARGET_PTR_SIZE) and (TargetArch = TARGET_XTENSA) then
      begin
        { Nil the pointer-sized managed handle so an uninitialised local reads as
          nil (Length 0, scope-exit DecRef is a no-op rather than a wild free). }
        EmitFrameAddrXtensa(reg_xtensa_a8, Syms[i].Offset);
        xtensa_movi(reg_xtensa_a9, 0);
        xtensa_s32i(reg_xtensa_a9, reg_xtensa_a8, 0);
      end
      else if (zeroBytes = TARGET_PTR_SIZE) and (TargetArch = TARGET_RISCV32) then
      begin
        EmitLoadImmRISCV32(reg_t0, Syms[i].Offset);
        rv32_add(reg_t0, reg_s0, reg_t0);
        rv32_sw(reg_zero, reg_t0, 0);
      end
      else if zeroBytes = TARGET_PTR_SIZE then
      begin
        EmitB($48); EmitB($C7); EmitB($85); EmitI32(Syms[i].Offset); EmitI32(0); { mov qword [rbp+off], 0 }
      end
      else if (zeroBytes > 0) and (TargetArch = TARGET_X86_64) then
      begin
        EmitB($48); EmitB($8D); EmitB($BD); EmitI32(Syms[i].Offset);  { lea rdi, [rbp+off] }
        EmitB($48); EmitB($31); EmitB($C0);                           { xor rax, rax }
        EmitB($48); EmitB($C7); EmitB($C1); EmitI32(zeroBytes);       { mov rcx, zeroBytes }
        EmitB($F3); EmitB($AA);                                       { rep stosb }
      end;
    end;
  { label declarations: label foo, bar; }
  while (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'label') do
  begin
    Next;
    while CurTok.Kind = tkIdent do
    begin
      if GotoLabelCount >= MAX_GOTO_LABELS then Error('too many labels');
      GotoLabelNOff[GotoLabelCount]    := Tokens[TokPos-1].SOffset;
      GotoLabelNLen[GotoLabelCount]    := Tokens[TokPos-1].SLen;
      GotoLabelCodePos[GotoLabelCount] := -1;
      Inc(GotoLabelCount);
      Next;
      if not Eat(tkComma) then break;
    end;
    Eat(tkSemicolon);
  end;

  needsProcCleanupFrame := (TargetArch = TARGET_X86_64) and ExceptionUsed and
                           (not isAsmFunc) and ProcHasManagedLocalCleanup(pi, -1);
  if needsProcCleanupFrame then
  begin
    EmitB($48); EmitB($83); EmitB($EC); EmitB(EXC_FRAME_SIZE);
    EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_TOP);
    EmitB($48); EmitB($89); EmitB($04); EmitB($24);
    EmitB($48); EmitB($89); EmitB($E0);
    EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_TOP);
    EmitB($48); EmitB($8D); EmitB($7C); EmitB($24); EmitB(EXC_JMP_OFFSET);
    IREmitCodeCall(ExcSetJmpAddr);
    EmitB($85); EmitB($C0);
    EmitB($0F); EmitB($85); cleanupJnePatch := CodeLen; EmitI32(0);
    ProcExceptionCleanupFrameActive := True;
  end;

  { Generator body prologue: this proc is entered not by a normal `call` but by
    CoSwitch `ret`ing into it, with the instance pointer handed off in rbx (the
    initial frame's rbx slot, set by CoAlloc). Copy it into the hidden self
    local, then load each declared param from the instance (the ABI param regs
    hold garbage since there was no real call). }
  if isGenerator and not isStackless then
  begin
    { mov [rbp+selfOff], rbx }
    EmitB($48); EmitB($89); EmitB($9D); EmitI32(Syms[CurGenSelfSym].Offset);
    for i := 0 to nparams - 1 do
    begin
      gpi := Procs[pi].Params[i].SymIdx;
      sz := ParamSize(gpi);
      { rax = self }
      EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[CurGenSelfSym].Offset);
      { rax = [rax + CO_OFF_PARAMS + 8*i]  (instance stores each param as a qword) }
      EmitB($48); EmitB($8B); EmitB($80); EmitI32(CO_OFF_PARAMS + 8 * i);
      { Store only the param's own width into its frame slot — slots are packed by
        size, so a qword store would clobber the adjacent param slot. }
      if sz = 1 then
        begin EmitB($88); EmitB($85); end                  { mov [rbp+off], al }
      else if sz = 2 then
        begin EmitB($66); EmitB($89); EmitB($85); end       { mov [rbp+off], ax }
      else if sz = 4 then
        begin EmitB($89); EmitB($85); end                   { mov [rbp+off], eax }
      else
        begin EmitB($48); EmitB($89); EmitB($85); end;       { mov [rbp+off], rax }
      EmitI32(Syms[gpi].Offset);
    end;
  end;

  { Body }
  if isAsmFunc then
  begin
    { Whole-function asm body: 'asm ... end;'. Params already copied to their
      stack slots, so the asm can read/write them by name. The asm is
      responsible for leaving the result in rax (FPC accumulator convention),
      so the epilogue below must not reload Result. }
    Expect(tkAsm, 'asm');
    asmNode := ParseAsmStatementAST;
    CompileAST(asmNode);
    ASTNodeCount := 0;
  end
  else if isStackless then
  begin
    { Stackless generator: parse the body to AST, verify yield placement, assign
      persistent instance slots, transform to a flat goto/label state machine,
      and compile that as the step function. No asm, no coroutine stack — runs on
      every target through the shared IR. }
    Expect(tkBegin, 'begin');
    genBodyAST := ParseBlockAST;
    Expect(tkEnd, 'end');
    Eat(tkSemicolon);
    if isAsync then
    begin
      if not SLHasYield(genBodyAST) then
        Error('async stackless routine has no await (cannot suspend)');
    end
    else if not CurGenSeenYield then
      Error('generator has no yield');
    SLCheckEligible(genBodyAST);
    AssignStacklessSlots(pi);
    genStepAST := BuildStacklessStep(genBodyAST, pi);
    ProcGenInstSize[pi] := SL_OFF_SLOTS + 8 * CurGenSlotNext;
    CompileAST(genStepAST);
    ASTNodeCount := 0;
  end
  else
  begin
    Expect(tkBegin, 'begin');
    ParseBlock;
    Expect(tkEnd, 'end');
    Eat(tkSemicolon);
  end;

  { Generator body epilogue: falling off the end means exhaustion. Mark done and
    CoSwitch back to the consumer; this never returns (the consumer's CoNext
    sees done and stops, never resuming this stack). Emitted before the normal
    epilogue, which is therefore unreachable for a generator. Validation: a
    generator with no yield is almost certainly a mistake. }
  if isGenerator and not isStackless then
  begin
    if not CurGenSeenYield then
      Error('generator has no yield');
    EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[CurGenSelfSym].Offset);  { mov rax, [rbp+selfOff] }
    EmitB($48); EmitB($C7); EmitB($80); EmitI32(CO_OFF_DONE); EmitI32(1);      { mov qword [rax+DONE], 1 }
    EmitB($48); EmitB($8D); EmitB($78); EmitB(CO_OFF_GENCTX);                  { lea rdi, [rax+genctx]  (from) }
    EmitB($48); EmitB($8D); EmitB($70); EmitB(CO_OFF_CALLERCTX);               { lea rsi, [rax+callerctx] (to) }
    IREmitCodeCall(CoSwitchAddr);
  end;

  if needsProcCleanupFrame then
  begin
    EmitB($E9); cleanupJmpPatch := CodeLen; EmitI32(0);
    Patch32(cleanupJnePatch, CodeLen - (cleanupJnePatch + 4));
    EmitLeaveExceptionFrameX64;
    EmitManagedLocalCleanup(-1);
    IREmitCodeCall(ExcRaiseAddr);
    Patch32(cleanupJmpPatch, CodeLen - (cleanupJmpPatch + 4));
  end;

  { Verify all forward goto fixups were resolved }
  for i := 0 to GotoLabelCount - 1 do
    if GotoLabelCodePos[i] = -1 then
    begin
      for j := 0 to GotoFixupCount - 1 do
        if TokSlicesMatch(GotoFixupNOff[j], GotoFixupNLen[j], GotoLabelNOff[i], GotoLabelNLen[i]) then
          Error('goto target label never placed: ' +
            GetTokenStrFromRaw(GotoLabelNOff[i], GotoLabelNLen[i]));
    end;

  { Epilogue. For assembler functions the asm body already set rax, so pass
    -1 to skip reloading Result (which would clobber the asm's return value). }
  if isAsmFunc then
    EmitProcEpilog(-1)
  else
    EmitProcEpilog(Procs[pi].RetSymIdx);
  ProcExceptionCleanupFrameActive := savedProcCleanupFrameActive;

  { End of this proc's body bytes — the iram byte-range is [BodyAddr, ProcBodyEnd). }
  ProcBodyEnd[pi] := CodeLen;

  { Patch frame size }
  PatchProcPrologue(patchPos, FrameSize);

  { Restore scope }
  SymCount  := savedSC;
  FrameSize := savedFS;
  GotoLabelCount := savedGLC;
  GotoFixupCount := savedGFC;
  CurProc   := -1;
  CurSelfClass := REC_NONE;
  CurProcIsAsync := savedProcIsAsync;
  CurProcIsGenerator := savedGenIsGen;
  CurProcIsStackless := savedGenStackless;
  CurGenSelfSym := savedGenSelf;
  CurGenSeenYield := savedGenSeen;
  GenTryDepth := savedGenTry;
  CurGenStateCtr := savedGenStateCtr;
  CurGenSlotNext := savedGenSlotNext;
end;

function LowerCase(const s: AnsiString): AnsiString;
var
  i: Integer;
  res: AnsiString;
begin
  res := s;
  for i := 1 to Length(res) do
  begin
    if res[i] in ['A'..'Z'] then
      res[i] := Chr(Ord(res[i]) + 32);
  end;
  Result := res;
end;

procedure ParseUnit; forward;

procedure ConcatThree(const s1, s2, s3: AnsiString; var dst: AnsiString);
var
  i, len1, len2, len3: Integer;
begin
  len1 := Length(s1);
  len2 := Length(s2);
  len3 := Length(s3);
  SetLength(dst, len1 + len2 + len3);
  for i := 1 to len1 do
    dst[i] := s1[i];
  for i := 1 to len2 do
    dst[len1 + i] := s2[i];
  for i := 1 to len3 do
    dst[len1 + len2 + i] := s3[i];
end;

procedure EnableExceptionRuntime;
begin
  if not ExceptionUsed then
  begin
    ExceptionUsed := True;
    BSS_EXC_TOP := BSSSize; Inc(BSSSize, 8);
    BSS_EXC_OBJ := BSSSize; Inc(BSSSize, 8);
    BSS_EXC_CLS := BSSSize; Inc(BSSSize, 8);
    EmitExceptionRuntime;
  end;
end;

procedure EnableCoroutineRuntime;
begin
  if not CoroutineUsed then
  begin
    CoroutineUsed := True;
    { CoSwitch saves/restores BSS_EXC_TOP, so the exception slot must exist even
      if the program itself has no try/except. }
    EnableExceptionRuntime;
    EmitCoroutineRuntime;
  end;
end;

procedure ParseUsesUnit(const name: AnsiString);
var
  lo, path: AnsiString;
  startPos, savedTokPos, strIdx, i, savedCurrentUnitIdx: Integer;
  savedCurTokKind: TTokenKind;
  savedCurTokSVal: AnsiString;
  savedCurTokIVal: Int64;
  savedCurTokLine: Integer;
  savedSrcBase, savedUnitDir: AnsiString;
  cdir, bdir, rtldir, lcldir: AnsiString;
  basePath, ext, emsg: AnsiString;
  lastSlash, lastDot: Integer;
  isCompiled, isCUnit, isCHeader, isPath, savedCaseMode: Boolean;
begin
  isPath := False;
  for i := 1 to Length(name) do
    if name[i] = '/' then isPath := True;
  if isPath then
    lo := LowerCase(GetFileBaseName(name))
  else
    lo := LowerCase(name);
  if (lo = 'sysutils') or (lo = 'baseunix') or (lo = 'unix') then Exit;

  { Check if already compiled }
  strIdx := InternStr(lo);
  isCompiled := False;
  for i := 0 to CompiledUnitCount - 1 do
  begin
    if CompiledUnits[i] = strIdx then
      isCompiled := True;
  end;
  if isCompiled then Exit;

  { Mark as compiled }
  if CompiledUnitCount < 256 then
  begin
    CompiledUnits[CompiledUnitCount] := strIdx;
    Inc(CompiledUnitCount);
  end;

  isCUnit := False;
  isCHeader := False;
  CurrentCLibrary := '';
  UnitContent := '';

  if isPath then
  begin
    { Path-form reference (uses './sub/unit' or '/abs/unit'): resolve relative
      to the directory of the file containing the directive (CurUnitDir);
      absolute paths are used as-is. Extension may be omitted (.pas then .pp
      inferred); an explicit .pas/.pp/.c/.h is honoured. The path is
      authoritative — no directory search chain, miss is an error. }
    lastSlash := 0; lastDot := 0;
    for i := 1 to Length(name) do
    begin
      if name[i] = '/' then lastSlash := i;
      if name[i] = '.' then lastDot := i;
    end;
    if name[1] = '/' then
      basePath := name
    else
      ConcatThree(CurUnitDir, name, '', basePath);
    NormalizePath(basePath);
    if lastDot > lastSlash then
    begin
      ext := '';
      for i := lastDot + 1 to Length(name) do AppendChar(ext, name[i]);
      ext := LowerCase(ext);
      if (Length(ext) = 1) and (ext[1] = 'c') then isCUnit := True;
      if (Length(ext) = 1) and (ext[1] = 'h') then
      begin
        isCUnit := True; isCHeader := True;
      end;
      path := basePath;
      LoadFile(path, UnitContent);
    end
    else
    begin
      ConcatThree(basePath, '.pas', '', path);
      LoadFile(path, UnitContent);
      if Length(UnitContent) = 0 then
      begin
        ConcatThree(basePath, '.pp', '', path);
        LoadFile(path, UnitContent);
      end;
    end;
    if Length(UnitContent) = 0 then
    begin
      ConcatThree('uses: unit source not found: ', basePath, '', emsg);
      Error(emsg);
    end;
  end;

  if Length(UnitContent) = 0 then
  begin
    ConcatThree(SourceFileDir, lo, '.pas', path);
    LoadFile(path, UnitContent);
  end;
  if Length(UnitContent) = 0 then
  begin
    ConcatThree(SourceFileDir, lo, '.pp', path);
    LoadFile(path, UnitContent);
  end;
  if Length(UnitContent) = 0 then
  begin
    ConcatThree(SourceFileDir, lo, '.c', path);
    LoadFile(path, UnitContent);
    if Length(UnitContent) > 0 then isCUnit := True;
  end;
  if Length(UnitContent) = 0 then
  begin
    ConcatThree(SourceFileDir, lo, '.h', path);
    LoadFile(path, UnitContent);
    if Length(UnitContent) > 0 then begin isCUnit := True; isCHeader := True; end;
  end;

  { Library directories, anchored to the compiler binary (ExeDir) so units
    resolve regardless of CWD. ExeDir is e.g. <root>/compiler/, so the RTL/LCL
    dirs are its siblings via '../lib/...'. Falls back to CWD-relative when the
    binary path carried no directory (run via a bare name). }
  if ExeDir = '' then
  begin
    cdir := 'compiler/'; bdir := 'compiler/builtin/';
    rtldir := 'lib/rtl/'; lcldir := 'lib/lcl/';
  end
  else
  begin
    cdir := ExeDir;
    ConcatThree(ExeDir, 'builtin/', '', bdir);   { ExeDir is <root>/compiler/ }
    ConcatThree(ExeDir, '../lib/rtl/', '', rtldir);
    ConcatThree(ExeDir, '../lib/lcl/', '', lcldir);
  end;

  if Length(UnitContent) = 0 then
  begin
    { If not found in base dir, try compiler's local directory or common locations }
    ConcatThree(cdir, lo, '.pas', path);
    LoadFile(path, UnitContent);
    if Length(UnitContent) = 0 then
    begin
      ConcatThree(cdir, lo, '.pp', path);
      LoadFile(path, UnitContent);
    end;
    if Length(UnitContent) = 0 then
    begin
      ConcatThree(cdir, lo, '.c', path);
      LoadFile(path, UnitContent);
      if Length(UnitContent) > 0 then isCUnit := True;
    end;
    if Length(UnitContent) = 0 then
    begin
      ConcatThree(cdir, lo, '.h', path);
      LoadFile(path, UnitContent);
      if Length(UnitContent) > 0 then begin isCUnit := True; isCHeader := True; end;
    end;
  end;

  if Length(UnitContent) = 0 then
  begin
    { Compiler-specific runtime units (builtin: the auto-included heap allocator
      and Str/Val/variant helpers). Not user RTL, so it lives with the compiler. }
    ConcatThree(bdir, lo, '.pas', path);
    LoadFile(path, UnitContent);
    if Length(UnitContent) = 0 then
    begin
      ConcatThree(bdir, lo, '.pp', path);
      LoadFile(path, UnitContent);
    end;
  end;

  if Length(UnitContent) = 0 then
  begin
    { RTL library units }
    ConcatThree(rtldir, lo, '.pas', path);
    LoadFile(path, UnitContent);
    if Length(UnitContent) = 0 then
    begin
      ConcatThree(rtldir, lo, '.pp', path);
      LoadFile(path, UnitContent);
    end;
    if Length(UnitContent) = 0 then
    begin
      ConcatThree(rtldir, lo, '.h', path);
      LoadFile(path, UnitContent);
      if Length(UnitContent) > 0 then begin isCUnit := True; isCHeader := True; end;
    end;
  end;

  if Length(UnitContent) = 0 then
  begin
    { LCL widgetset units }
    ConcatThree(lcldir, lo, '.pas', path);
    LoadFile(path, UnitContent);
    if Length(UnitContent) = 0 then
    begin
      ConcatThree(lcldir, lo, '.pp', path);
      LoadFile(path, UnitContent);
    end;
  end;

  { CWD-relative fallback (only meaningful when ExeDir is set and differs from
    the repo root, e.g. the self-host tests run a /tmp copy of the compiler with
    CWD at the repo root where compiler/ + lib/ live). }
  if (Length(UnitContent) = 0) and (ExeDir <> '') then
  begin
    ConcatThree('compiler/', lo, '.pas', path);
    LoadFile(path, UnitContent);
    if Length(UnitContent) = 0 then begin ConcatThree('compiler/builtin/', lo, '.pas', path); LoadFile(path, UnitContent); end;
    if Length(UnitContent) = 0 then begin ConcatThree('lib/rtl/', lo, '.pas', path); LoadFile(path, UnitContent); end;
    if Length(UnitContent) = 0 then begin ConcatThree('lib/lcl/', lo, '.pas', path); LoadFile(path, UnitContent); end;
    if Length(UnitContent) = 0 then begin ConcatThree('compiler/', lo, '.pp', path); LoadFile(path, UnitContent); end;
    if Length(UnitContent) = 0 then begin ConcatThree('lib/rtl/', lo, '.pp', path); LoadFile(path, UnitContent); end;
    if Length(UnitContent) = 0 then begin ConcatThree('lib/lcl/', lo, '.pp', path); LoadFile(path, UnitContent); end;
    if Length(UnitContent) = 0 then
    begin
      ConcatThree('lib/rtl/', lo, '.h', path); LoadFile(path, UnitContent);
      if Length(UnitContent) = 0 then begin ConcatThree('compiler/', lo, '.h', path); LoadFile(path, UnitContent); end;
      if Length(UnitContent) > 0 then begin isCUnit := True; isCHeader := True; end;
    end;
    if Length(UnitContent) = 0 then
    begin
      ConcatThree('compiler/', lo, '.c', path); LoadFile(path, UnitContent);
      if Length(UnitContent) > 0 then isCUnit := True;
    end;
  end;

  if Length(UnitContent) = 0 then
  begin
    ConcatThree('/usr/include/', lo, '.h', path);
    LoadFile(path, UnitContent);
    if Length(UnitContent) > 0 then begin isCUnit := True; isCHeader := True; end;
  end;

  if Length(UnitContent) = 0 then
  begin
    ConcatThree('/usr/include/gtk-2.0/gtk/', lo, '.h', path);
    LoadFile(path, UnitContent);
    if Length(UnitContent) > 0 then begin isCUnit := True; isCHeader := True; end;
  end;

  if Length(UnitContent) = 0 then
  begin
    ConcatThree('uses: unit source not found: ', lo, '', emsg);
    Error(emsg);
  end;

  if isCUnit then
  begin
    if isCHeader then
    begin
      { Map the header/unit name to the DT_NEEDED soname the system ships.
        Versioned sonames (not the unversioned dev symlink lib<name>.so) so
        the emitted ELF loads against the runtime libraries present on a
        stock system without -dev packages. Dynamic ld.so.cache probing is a
        later refinement; this table covers the FFI targets in use. }
      if (lo = 'ctype') or (lo = 'math_ext') or (lo = 'stdio') or
         (lo = 'stdlib') or (lo = 'string') or (lo = 'unistd') then
        CurrentCLibrary := 'libc.so.6'
      else if (lo = 'math') or (lo = 'm') then
        CurrentCLibrary := 'libm.so.6'
      else if (lo = 'pthread') then
        CurrentCLibrary := 'libpthread.so.0'
      else if (lo = 'gtk3_c') then
        CurrentCLibrary := 'libgtk-3.so.0'
      else if (lo = 'gtk') then
        CurrentCLibrary := 'libgtk-x11-2.0.so.0'
      else if (lo = 'dl') then
        CurrentCLibrary := 'libdl.so.2'
      else if (lo = 'rt') then
        CurrentCLibrary := 'librt.so.1'
      else if (lo = 'z') then
        CurrentCLibrary := 'libz.so.1'
      else if (lo = 'sqlite3') then
        CurrentCLibrary := 'libsqlite3.so.0'
      else
        ConcatThree('lib', lo, '.so', CurrentCLibrary);
    end;
    savedTokPos := TokPos;
    savedCurTokKind := CurTok.Kind;
    savedCurTokSVal := CurTok.SVal;
    savedCurTokIVal := CurTok.IVal;
    savedCurTokLine := CurTok.Line;

    CPreprocess(UnitContent, GetFilePath(path));

    { Append preprocessed tokens using C Lexer }
    startPos := CLexAppend(UnitContent);

    TokPos := startPos;
    Next;

    { C symbols are case-sensitive: force the mode so their proc names match
      exactly (the link symbol is exact), independent of the host's setting.
      Restored after so it does not leak into the including unit. }
    savedCaseMode := CaseSensitiveMode;
    savedCurrentUnitIdx := CurrentUnitIdx;
    CurrentUnitIdx := strIdx;
    CaseSensitiveMode := True;
    CHeaderMode := isCHeader;
    ParseCUnit;
    { Surface object-like integer #define macros (e.g. SQLITE_ROW) as constants,
      still under the header's case-sensitive mode and unit index. }
    RegisterCMacroConsts;
    CaseSensitiveMode := savedCaseMode;
    CurrentUnitIdx := savedCurrentUnitIdx;

    TokPos := savedTokPos;
    CurTok.Kind := savedCurTokKind;
    CurTok.SVal := savedCurTokSVal;
    CurTok.IVal := savedCurTokIVal;
    CurTok.Line := savedCurTokLine;
  end
  else
  begin
    savedTokPos := TokPos;
    savedCurTokKind := CurTok.Kind;
    savedCurTokSVal := CurTok.SVal;
    savedCurTokIVal := CurTok.IVal;
    savedCurTokLine := CurTok.Line;
    { A unit's own CASESENSITIVE directive (processed during LexAppend below)
      applies to that unit only — saved here, restored after ParseUnit, so it
      does not leak into the including file. A unit with no directive inherits
      the caller's mode. }
    savedCaseMode := CaseSensitiveMode;
    savedCurrentUnitIdx := CurrentUnitIdx;
    CurrentUnitIdx := strIdx;

    ExpandIncludes(UnitContent, GetFilePath(path));

    { This unit's name resolves the `*` in its own $R *.lfm (processed during
      LexAppend below). Restored after, so a nested `uses` doesn't leak its base. }
    savedSrcBase := CurSrcBaseName;
    CurSrcBaseName := lo;

    { Nested path-form `uses` inside this unit resolve relative to the unit's
      own directory. Restored after, like CurSrcBaseName. }
    savedUnitDir := CurUnitDir;
    CurUnitDir := GetFilePath(path);

    { Append tokens to global Token stream }
    startPos := LexAppend(UnitContent);
    i := startPos;
    while i < TokCount do
    begin
      if Tokens[i].Kind in [tkTry, tkRaise] then EnableExceptionRuntime;
      { A unit (e.g. coroutine.pas) using the low-level __pxxcoswitch intrinsic
        needs the CoSwitch stub emitted before its body compiles. }
      if (Tokens[i].Kind = tkIdent) and CaseEqual(GetTokenStr(i), '__pxxcoswitch') then
        EnableCoroutineRuntime;
      Inc(i);
    end;

    { Point parser to first token of the unit }
    TokPos := startPos;
    Next;

    { Parse the unit }
    ParseUnit;

    { Restore parser position }
    TokPos := savedTokPos;
    CurTok.Kind := savedCurTokKind;
    CurTok.SVal := savedCurTokSVal;
    CurTok.IVal := savedCurTokIVal;
    CurTok.Line := savedCurTokLine;
    CurSrcBaseName := savedSrcBase;
    CurUnitDir := savedUnitDir;
    CaseSensitiveMode := savedCaseMode;
    CurrentUnitIdx := savedCurrentUnitIdx;
  end;
end;

{ Compile a unit's `initialization` section into a synthesized parameterless
  proc and register it in InitProcs[]. The dialect has no real init execution,
  so ParseUnit used to drop these tokens; this emits a normal proc body that the
  program entry calls (in dependency order) before `main begin`. Precondition:
  the `initialization` keyword has been consumed; statements run until `end` or
  `finalization`. Leaves the parser positioned at that terminator. }
procedure ParseInitializationSection(const uname: AnsiString);
var
  pi, savedSC, savedFS, savedGLC, savedGFC, j, patchPos: Integer;
  seqNode, lastSeq, stmtNode: Integer;
  dummyNames: array[0..0] of AnsiString;
  dummyTypes: array[0..0] of TTypeKind;
begin
  pi := RegisterProc('__init_' + uname, False, tyInteger, 0, dummyNames, dummyTypes);
  if TargetArch = TARGET_XTENSA then
    while (CodeLen mod 4) <> 0 do xtensa_nop; { CALL0 targets must be 4-aligned }
  Procs[pi].BodyAddr := CodeLen;

  savedSC := SymCount; savedFS := FrameSize;
  savedGLC := GotoLabelCount; savedGFC := GotoFixupCount;
  GotoLabelCount := 0; GotoFixupCount := 0;
  for j := 0 to MAX_GOTO_LABELS - 1 do GotoLabelIRId[j] := -1;
  FrameSize := 0;
  CurProc := pi;
  Procs[pi].ScopeBase := SymCount;

  patchPos := EmitProcPrologue;
  Procs[pi].FramePatch := patchPos;
  if (TargetArch = TARGET_XTENSA) and (XtensaABI = XTENSA_ABI_WINDOWED) then
    xtensa_mov(reg_xtensa_a7, reg_xtensa_a15);

  { Optional local var/const/type sections (rare in init, but harmless). }
  while CurTok.Kind in [tkVar, tkConst, tkType] do
    case CurTok.Kind of
      tkVar:   ParseVarSection;
      tkConst: ParseConstSection;
      tkType:  ParseTypeSection;
    end;
  for j := savedSC to SymCount - 1 do
    if (Syms[j].Kind = skLocal) and Syms[j].IsArray and (Syms[j].ArrLen = -1) then
    begin
      EmitB($48); EmitB($C7); EmitB($85); EmitI32(Syms[j].Offset); EmitI32(0);
    end;

  { Statements until `end` or `finalization` (an identifier, not a token). }
  seqNode := AllocNode(AN_SEQ);
  lastSeq := seqNode;
  while not (CurTok.Kind in [tkEnd, tkEOF]) and
        not ((CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'finalization')) do
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
  CompileAST(seqNode);
  ASTNodeCount := 0;

  EmitProcEpilog(-1);
  PatchProcPrologue(patchPos, FrameSize);

  SymCount := savedSC; FrameSize := savedFS;
  GotoLabelCount := savedGLC; GotoFixupCount := savedGFC;
  CurProc := -1;

  if InitProcCount < 256 then
  begin
    InitProcs[InitProcCount] := pi;
    Inc(InitProcCount);
  end;
end;

procedure ParseUnit;
var
  uname: AnsiString;
  doneUses, savedInterface, doneImp: Boolean;
begin
  Expect(tkUnit, 'unit');
  if CurTok.Kind <> tkIdent then Error('expected unit name');
  uname := CurTok.SVal; Next;
  Expect(tkSemicolon, ';');

  if CurTok.Kind <> tkIdent then Error('expected interface section');
  if (CurTok.SVal <> 'interface') and (CurTok.SVal <> 'Interface') then
    Error('expected interface section');
  Next;

  savedInterface := InInterface;
  InInterface := True;

  while (CurTok.Kind <> tkEOF) and not ((CurTok.Kind = tkIdent) and ((CurTok.SVal = 'implementation') or (CurTok.SVal = 'Implementation'))) do
  begin
    case CurTok.Kind of
      tkUses:
      begin
        Next;
        doneUses := False;
        while (CurTok.Kind in [tkIdent, tkString]) and not doneUses do
        begin
          ParseUsesUnit(CurTok.SVal);
          Next;
          if not Eat(tkComma) then doneUses := True;
        end;
        Eat(tkSemicolon);
      end;
      tkVar:      ParseVarSection;
      tkConst:    ParseConstSection;
      tkType:     ParseTypeSection;
      tkClass,
      tkProcedure,
      tkFunction: ParseSubroutine;
      else
        Next;
    end;
  end;

  if CurTok.Kind = tkEOF then Error('expected implementation section');
  Next; { Skip 'implementation' }

  InInterface := False;

  doneImp := False;
  while (CurTok.Kind <> tkEOF) and not doneImp do
  begin
    if CurTok.Kind = tkEnd then
    begin
      { Could be 'end.' or end of a case/begin inside a subroutine. }
      { However, at top level of implementation, a standalone 'end' is the end of the unit. }
      { Let's see if the next token is tkDot. }
      if (TokPos < TokCount) and (Tokens[TokPos].Kind = tkDot) then
        doneImp := True
      else
        Next;
    end
    else
    begin
      case CurTok.Kind of
        tkUses:
        begin
          Next;
          doneUses := False;
          while (CurTok.Kind in [tkIdent, tkString]) and not doneUses do
          begin
            ParseUsesUnit(CurTok.SVal);
            Next;
            if not Eat(tkComma) then doneUses := True;
          end;
          Eat(tkSemicolon);
        end;
        tkVar:      ParseVarSection;
        tkConst:    ParseConstSection;
        tkType:     ParseTypeSection;
        tkClass,
        tkProcedure,
        tkFunction: ParseSubroutine;
        tkIdent:
          { constructor/destructor are identifiers in this dialect, not tokens;
            their method bodies live in the unit implementation just like
            procedure/function bodies. }
          if CaseEqual(CurTok.SVal, 'constructor') or CaseEqual(CurTok.SVal, 'destructor') then
            ParseSubroutine
          else if CaseEqual(CurTok.SVal, 'initialization') then
          begin
            Next;                       { consume 'initialization' }
            ParseInitializationSection(uname);
          end
          else
            Next;                       { 'finalization' + its body are skipped }
        else
          Next;
      end;
    end;
  end;

  InInterface := savedInterface;

  Expect(tkEnd, 'end');
  Expect(tkDot, '.');
end;

{ ===== Program ===== }

procedure DetectPascalRuntimeNeeds(var needsHeap, needsAnsiRuntime: Boolean);
{ Conservative pre-scan for optional emitted runtime support. Imported units
  are treated as opaque: keep the support bundle if uses is present. }
var i: Integer; name: AnsiString;
begin
  needsHeap := False;
  needsAnsiRuntime := PasDefineExists('PXX_MANAGED_STRING');
  i := 0;
  while i < TokCount do
  begin
    if Tokens[i].Kind in [tkUses, tkArray, tkClass, tkGetMem, tkFreeMem] then
      needsHeap := True;
    { 32-bit cross targets write floats through the builtinheap Pascal
      helpers (PXXWriteFloat*), so any float-producing token pulls the unit.
      tkSlash counts: integer / integer yields a float. }
    if ((TargetArch = TARGET_I386) or (TargetArch = TARGET_ARM32) or
        (TargetArch = TARGET_XTENSA) or (TargetArch = TARGET_RISCV32)) and
       (Tokens[i].Kind in [tkFloat, tkSlash]) then
      needsHeap := True;
    if Tokens[i].Kind = tkUses then
      needsAnsiRuntime := True;
    if Tokens[i].Kind = tkIdent then
    begin
      name := GetTokenStr(i);
      if CaseEqual(name, 'AnsiString') or CaseEqual(name, 'Variant') then
        needsAnsiRuntime := True;
      if ((TargetArch = TARGET_I386) or (TargetArch = TARGET_ARM32) or
          (TargetArch = TARGET_XTENSA) or (TargetArch = TARGET_RISCV32)) and
         (CaseEqual(name, 'Single') or CaseEqual(name, 'Double') or
          CaseEqual(name, 'Real') or CaseEqual(name, 'Extended')) then
        needsHeap := True;
      if CaseEqual(name, 'New') or CaseEqual(name, 'Dispose') or
         CaseEqual(name, 'ReallocMem') or CaseEqual(name, 'SetLength') then
        needsHeap := True;
    end;
    Inc(i);
  end;
  if needsAnsiRuntime then needsHeap := True;
end;

procedure FixupTVarRecLayout;
{ builtinheap declares TVarRec with three sequential fields; here we overlap
  VAnsiString onto the value union (VInteger's offset) and right-size the record
  to a pointer-sized tag plus one pointer-sized value slot — exactly FPC's
  system.TVarRec (SizeOf 16 on x86-64, 8 on i386). Records the resolved id in
  TVarRecId for the `array of const` parser/lowering paths. }
var ci, fi: Integer;
begin
  TVarRecId := REC_NONE;
  ci := FindUClass('TVarRec');
  if ci < 0 then Exit;
  TVarRecId := REC_UCLASS_BASE + ci;
  { Overlap every value-union field onto the single pointer-sized value slot at
    offset TARGET_PTR_SIZE (field 0 = VType stays at offset 0). VInteger already
    lands there from the sequential layout; VAnsiString/VBoolean/VChar/VPointer/
    VPChar/VInt64/VExtended are forced onto it so `array of const` element reads
    by tag all hit the same slot — exactly FPC's variant TVarRec. }
  for fi := UClsFBase[ci] + 1 to UClsFBase[ci] + UClsFCount[ci] - 1 do
    UFldOff_[fi] := TARGET_PTR_SIZE;
  UClsSize_[ci] := 2 * TARGET_PTR_SIZE;
  UClsAlign[ci] := TARGET_PTR_SIZE;
end;

procedure CompilePendingGlobalInits;
{ Emit the recorded constant global-var initializers as assignments, at the
  current code position (just before `main begin`). }
var i, identNode, valNode, idxLit, target, assignNode: Integer;
begin
  for i := 0 to PendingInitCount - 1 do
  begin
    identNode := AllocNode(AN_IDENT);
    ASTIVal[identNode] := PendingInitSym[i];
    ASTTk[identNode] := Ord(Syms[PendingInitSym[i]].TypeKind);

    if PendingInitElem[i] >= 0 then
    begin
      idxLit := AllocNode(AN_INT_LIT);
      ASTIVal[idxLit] := PendingInitElem[i];
      ASTTk[idxLit] := Ord(tyInteger);
      target := AllocNode(AN_INDEX);
      ASTLeft[target] := identNode;
      ASTRight[target] := idxLit;
      ASTTk[target] := PendingInitTk[i];
    end
    else
      target := identNode;

    valNode := AllocNode(AN_INT_LIT);
    ASTIVal[valNode] := PendingInitVal[i];
    ASTTk[valNode] := PendingInitTk[i];

    assignNode := AllocNode(AN_ASSIGN);
    ASTLeft[assignNode] := target;
    ASTRight[assignNode] := valNode;

    CompileAST(assignNode);
    ASTNodeCount := 0;
  end;
end;

procedure ParseProgram;
var jmpPatch, i, j: Integer; doneUses, doneDecls, hasExceptions, needsBuiltin,
    needsHeap, needsAnsiRuntime, needHeapUnit, hasCoroutine: Boolean;
    savedUnitIdx: Integer;
    dummyNames: array[0..7] of AnsiString;
    dummyTypes: array[0..7] of TTypeKind;
begin
  PendingInitCount := 0;
  ArrTypeCount := 0;
  StrConstCount := 0;
  Expect(tkProgram, 'program');
  if CurTok.Kind = tkEOF then Error('expected program name');
  Next;  { program name can be any identifier (even keyword) }
  if CurTok.Kind = tkLParen then
    begin Next; while CurTok.Kind <> tkRParen do Next; Next; end;
  Eat(tkSemicolon);

  { Reserve BSS[0..7] for initial rsp (argv access) }
  BSS_INITIAL_RSP := BSSSize; Inc(BSSSize, 8);
  BSS_HEAP_PTR    := BSSSize; Inc(BSSSize, 8);
  BSS_HEAP_END    := BSSSize; Inc(BSSSize, 8);
  BSS_FREE_LIST   := BSSSize; Inc(BSSSize, 8);
  BSS_HEAP_LOCK   := BSSSize; Inc(BSSSize, 8);
  BSS_LINE_POS    := BSSSize; Inc(BSSSize, 8);
  BSS_LINE_LEN    := BSSSize; Inc(BSSSize, 8);
  BSS_LINE_BUF    := BSSSize; Inc(BSSSize, LINE_BUF_SIZE);
  BSS_INTBUF      := BSSSize; Inc(BSSSize, INTBUF_SIZE);
  ExceptionUsed := False;
  CoroutineUsed := False;
  hasExceptions := False;
  hasCoroutine := False;
  needsBuiltin := False;
  DetectPascalRuntimeNeeds(needsHeap, needsAnsiRuntime);
  { Full builtin (Str/Val/Variant) is pulled only for AnsiString/exception
    programs and on demand for Str/Val (token loop below). The heap allocator
    and managed-string helpers live in the separate `builtinheap` unit so a
    heap-only program does not drag in the conversion routines (which need
    features not yet on every target). }
  { Plain AnsiString needs only builtinheap (allocator + PXXStr*), not the full
    builtin conversions. Variant/Str/Val/uses pull builtin in the token loop. }
  needHeapUnit := needsHeap or needsAnsiRuntime or ComInterfaceUsed;

  if needHeapUnit then
  begin
    savedUnitIdx := CurrentUnitIdx;
    CurrentUnitIdx := InternStr('builtinheap');

    dummyNames[0] := 'size';  dummyTypes[0] := tyNativeInt;
    dummyNames[1] := 'align'; dummyTypes[1] := tyInteger;
    i := RegisterProc('PXXAlloc', True, tyPointer, 2, dummyNames, dummyTypes);

    dummyNames[0] := 'p';     dummyTypes[0] := tyPointer;
    i := RegisterProc('PXXFree', False, tyPointer, 1, dummyNames, dummyTypes);

    dummyNames[0] := 'p';     dummyTypes[0] := tyPointer;
    dummyNames[1] := 'newSize'; dummyTypes[1] := tyNativeInt;
    dummyNames[2] := 'align'; dummyTypes[2] := tyInteger;
    i := RegisterProc('PXXRealloc', True, tyPointer, 3, dummyNames, dummyTypes);

  { Managed-string ARC helpers are target-independent (allocator-backed), so
    register them on every target including ESP. }
  dummyNames[0] := 'len';   dummyTypes[0] := tyNativeInt;
  dummyNames[1] := 'src';   dummyTypes[1] := tyPointer;
  i := RegisterProc('PXXStrFromLit', True, tyPointer, 2, dummyNames, dummyTypes);

  dummyNames[0] := 'lenA';  dummyTypes[0] := tyNativeInt;
  dummyNames[1] := 'srcA';  dummyTypes[1] := tyPointer;
  dummyNames[2] := 'srcB';  dummyTypes[2] := tyPointer;
  dummyNames[3] := 'lenB';  dummyTypes[3] := tyNativeInt;
  i := RegisterProc('PXXStrConcat', True, tyPointer, 4, dummyNames, dummyTypes);

  dummyNames[0] := 'p';     dummyTypes[0] := tyPointer;
  i := RegisterProc('PXXStrIncRef', False, tyPointer, 1, dummyNames, dummyTypes);
  i := RegisterProc('PXXStrDecRef', False, tyPointer, 1, dummyNames, dummyTypes);
  dummyNames[0] := 'fatptr'; dummyTypes[0] := tyPointer;
  i := RegisterProc('PXXIntfAddRef', True, tyNativeInt, 1, dummyNames, dummyTypes);
  i := RegisterProc('PXXIntfRelease', True, tyNativeInt, 1, dummyNames, dummyTypes);
  dummyNames[0] := 'imt';  dummyTypes[0] := tyPointer;
  dummyNames[1] := 'inst'; dummyTypes[1] := tyPointer;
  i := RegisterProc('PXXIntfAddRefRaw', True, tyNativeInt, 2, dummyNames, dummyTypes);
  dummyNames[0] := 'dest'; dummyTypes[0] := tyPointer;
  dummyNames[1] := 'src';  dummyTypes[1] := tyPointer;
  i := RegisterProc('PXXIntfAssign', False, tyPointer, 2, dummyNames, dummyTypes);
  dummyNames[0] := 'strSlot'; dummyTypes[0] := tyPointer;
  i := RegisterProc('PXXStrUnique', True, tyPointer, 1, dummyNames, dummyTypes);
  dummyNames[0] := 'strSlot'; dummyTypes[0] := tyPointer;
  dummyNames[1] := 'newLen';  dummyTypes[1] := tyNativeInt;
  i := RegisterProc('PXXStrSetLen', False, tyPointer, 2, dummyNames, dummyTypes);

  dummyNames[0] := 'lenA';  dummyTypes[0] := tyNativeInt;
  dummyNames[1] := 'srcA';  dummyTypes[1] := tyPointer;
  dummyNames[2] := 'lenB';  dummyTypes[2] := tyNativeInt;
  dummyNames[3] := 'srcB';  dummyTypes[3] := tyPointer;
  i := RegisterProc('PXXStrEq', True, tyInt64, 4, dummyNames, dummyTypes);

  { Xtensa software integer-divide helpers: only when targeting an LX6 part
    (--xtensa-cpu=lx6). Registered (hence emitted) only then so LX7 images
    stay lean and keep their native quos/rems. }
  if (TargetArch = TARGET_XTENSA) and XtensaSoftDivide then
  begin
    dummyNames[0] := 'n'; dummyTypes[0] := tyUInt32;
    dummyNames[1] := 'd'; dummyTypes[1] := tyUInt32;
    i := RegisterProc('__pxx_udivsi3', True, tyUInt32, 2, dummyNames, dummyTypes);
    dummyNames[0] := 'a'; dummyTypes[0] := tyInteger;
    dummyNames[1] := 'b'; dummyTypes[1] := tyInteger;
    i := RegisterProc('__pxx_divsi3', True, tyInteger, 2, dummyNames, dummyTypes);
    i := RegisterProc('__pxx_modsi3', True, tyInteger, 2, dummyNames, dummyTypes);
  end;

  { File load, variant and float-format helpers are not on ESP yet. }
  if (TargetArch <> TARGET_XTENSA) and (TargetArch <> TARGET_RISCV32) then
  begin
    dummyNames[0] := 'path';  dummyTypes[0] := tyPointer;
    i := RegisterProc('PXXStrLoadFile', True, tyPointer, 1, dummyNames, dummyTypes);

    dummyNames[0] := 'dest';      dummyTypes[0] := tyPointer;
    dummyNames[1] := 'left';      dummyTypes[1] := tyPointer;
    dummyNames[2] := 'right';     dummyTypes[2] := tyPointer;
    dummyNames[3] := 'opTk';      dummyTypes[3] := tyNativeInt;
    dummyNames[4] := 'isCompare'; dummyTypes[4] := tyNativeInt;
    i := RegisterProc('PXXVarBinOp', True, tyInt64, 5, dummyNames, dummyTypes);

    dummyNames[0] := 'v';         dummyTypes[0] := tyPointer;
    i := RegisterProc('PXXVarClear', False, tyPointer, 1, dummyNames, dummyTypes);
    i := RegisterProc('PXXVarRetain', False, tyPointer, 1, dummyNames, dummyTypes);
    i := RegisterProc('PXXWriteVariant', False, tyPointer, 1, dummyNames, dummyTypes);

    dummyNames[0] := 'p';         dummyTypes[0] := tyPointer;
    i := RegisterProc('PXXWriteFloatNat', False, tyPointer, 1, dummyNames, dummyTypes);
    i := RegisterProc('PXXWriteFloatSci', False, tyPointer, 1, dummyNames, dummyTypes);
    dummyNames[1] := 'decimals';  dummyTypes[1] := tyNativeInt;
    i := RegisterProc('PXXWriteFloatFixed', False, tyPointer, 2, dummyNames, dummyTypes);
  end;

    CurrentUnitIdx := savedUnitIdx;
  end;
  for i := 0 to MAX_GOTO_LABELS - 1 do GotoLabelIRId[i] := -1;
  i := 0;
  while i < TokCount do
  begin
    if Tokens[i].Kind in [tkTry, tkRaise] then hasExceptions := True;
    { The coroutine context-switch stub must be emitted before the main body
      (it is reached only by `call`), so detect any use of the low-level
      __pxxcoswitch intrinsic up front. }
    if (Tokens[i].Kind = tkIdent) and CaseEqual(GetTokenStr(i), '__pxxcoswitch') then
      hasCoroutine := True;
    { Pull in the builtin unit (Str/Val backing) only if the program calls
      Str(...) or Val(...) — name immediately followed by '(', so plain
      variables/params named str/val don't drag it in. No DCE, so this keeps it
      out of programs that never use them. }
    if (Tokens[i].Kind = tkIdent) and (i + 1 < TokCount) and
       (Tokens[i + 1].Kind = tkLParen) and
       (CaseEqual(GetTokenStr(i), 'str') or CaseEqual(GetTokenStr(i), 'val')) then
      needsBuiltin := True;
    { Variant use needs VariantToStr (in builtin) for variant writes — on
      x86-64. Cross targets serve variants from builtinheap (PXXVar* helpers)
      and cannot compile the full builtin unit yet. }
    if (Tokens[i].Kind = tkIdent) and CaseEqual(GetTokenStr(i), 'Variant') and
       (TargetArch = TARGET_X86_64) then
      needsBuiltin := True;
    if Tokens[i].Kind = tkUses then
      needsBuiltin := True;
    Inc(i);
  end;

  if TargetArch = TARGET_I386 then
  begin
    { Cross-target i386: heap (New/Dispose/GetMem), managed strings, and exception runtime. }
    { Entry stub: save esp for argv access, then jmp to main body.
      mov [abs32], esp: 89 25 <GlobRef> }
    EmitB($89); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
    EmitB($E9); jmpPatch := CodeLen; EmitI32(0);
  end
  else if TargetArch = TARGET_ARM32 then
  begin
    { ARM32 entry stub: save sp for argv access, then branch to main body. }
    EmitI32($E59F1000);  { ldr r1, [pc] }
    EmitI32($EA000000);  { b .+8 }
    EmitGlobRef(BSS_INITIAL_RSP);
    EmitI32($E581D000);  { str sp, [r1] }
    jmpPatch := CodeLen;
    EmitI32($EA000000);
  end
  else if TargetArch = TARGET_AARCH64 then
  begin
    { AArch64 entry stub: save sp for argv access, then branch to main body. }
    EmitI32($18000041);  { ldr w1, [pc+8] }
    EmitI32($14000002);  { b [pc+8] }
    EmitGlobRef(BSS_INITIAL_RSP);
    EmitI32($910003E0);  { mov x0, sp }
    EmitI32($F9000020);  { str x0, [x1] }
    jmpPatch := CodeLen;
    EmitI32($14000000);
  end
  else if TargetArch = TARGET_XTENSA then
  begin
    { Bare-metal (Call0 only): no kernel set up a stack, so establish sp at the
      top of SRAM before entering main. EmitLoadConstXtensa drops a literal
      island for the 32-bit address. Must run before any call. }
    if EspBareBoot then
      EmitLoadConstXtensa(reg_xtensa_sp, ESP_BARE_STACK_TOP);
    if XtensaABI = XTENSA_ABI_WINDOWED then
    begin
      { app_main: program-level vars are globals (BSS), so no stack locals --
        but the body still uses the constant-sp expression stack, so reserve
        the spill region up front (no patchable addi on this path). }
      xtensa_entry(reg_xtensa_sp, 32 + XT_EXPR_REGION);
      xtensa_mov(reg_xtensa_a7, reg_xtensa_sp);
      XtSpillDepth := 0;
    end;
    { Xtensa entry stub: jump to main body. }
    jmpPatch := CodeLen;
    xtensa_j(0);
  end
  else if TargetArch = TARGET_RISCV32 then
  begin
    { Bare-metal: no kernel set up a stack, so establish sp at the top of SRAM
      (grows down toward the image) before entering main. lui+addi covers any
      low bits in the stack-top constant. }
    if EspBareBoot then
    begin
      EmitI32((((ESP_BARE_STACK_TOP + $800) shr 12) shl 12) or (2 shl 7) or $37); { lui sp,hi }
      EmitI32(((ESP_BARE_STACK_TOP and $FFF) shl 20) or (2 shl 15) or (2 shl 7) or $13); { addi sp,sp,lo }
    end;
    { RISC-V entry stub: jump to main body. }
    jmpPatch := CodeLen;
    EmitI32($0000006F);
  end
  else
  begin
    { Emit entry stub: save rsp then jmp to main body }
    { mov [bss_initial_rsp], rsp: 48 89 24 25 <GlobRef(0)> }
    EmitB($48); EmitB($89); EmitB($24); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
    EmitB($E9); jmpPatch := CodeLen; EmitI32(0);
  end;
  { The emitted AnsiString runtime is x86-64 machine code; i386 string IR ops
    call the builtinheap Pascal helpers directly instead, so skip the shim
    emission there (its AnsiStr*Addr labels stay 0 and are never referenced). }
  if needsAnsiRuntime and (TargetArch = TARGET_X86_64) then EmitAnsiStringRuntime;
  if hasExceptions then EnableExceptionRuntime;
  if hasCoroutine then EnableCoroutineRuntime;

  { Compile the runtime units before user declarations, so their proc bodies
    land in the proc region after the entry jump and are resolvable. builtinheap
    (allocator + PXXStr*) first, then the Str/Val/Variant conversions. }
  if needHeapUnit then ParseUsesUnit('builtinheap');
  if needsBuiltin then ParseUsesUnit('builtin');
  FixupTVarRecLayout;

  doneDecls := False;
  while not doneDecls do
    case CurTok.Kind of
      tkUses:
      begin
        Next;
        doneUses := False;
        while (CurTok.Kind in [tkIdent, tkString]) and not doneUses do
        begin
          ParseUsesUnit(CurTok.SVal);
          Next;
          if not Eat(tkComma) then doneUses := True;
        end;
        Eat(tkSemicolon);
      end;
      tkVar:      ParseVarSection;
      tkConst:    ParseConstSection;
      tkType:     ParseTypeSection;
      tkClass,
      tkProcedure,
      tkFunction: ParseSubroutine;
      tkIdent:
        if CaseEqual(CurTok.SVal, 'generic') then
          ParseGenericFunctionDef
        else if CaseEqual(CurTok.SVal, 'specialize') then
          ParseTopLevelSpecialize
        else if CaseEqual(CurTok.SVal, 'operator') then
          ParseOperatorDef
        else if CaseEqual(CurTok.SVal, 'constructor') or CaseEqual(CurTok.SVal, 'destructor') then
          ParseSubroutine
        else if CaseEqual(CurTok.SVal, 'label') then
        begin
          Next;
          while CurTok.Kind = tkIdent do
          begin
            if GotoLabelCount >= MAX_GOTO_LABELS then Error('too many labels');
            GotoLabelNOff[GotoLabelCount]    := Tokens[TokPos-1].SOffset;
            GotoLabelNLen[GotoLabelCount]    := Tokens[TokPos-1].SLen;
            GotoLabelCodePos[GotoLabelCount] := -1;
            Inc(GotoLabelCount);
            Next;
            if not Eat(tkComma) then Break;
          end;
          Eat(tkSemicolon);
        end
        else
          doneDecls := True;
      else
        doneDecls := True;
    end;

  { Patch jmp to point here (start of main body) }
  if TargetArch = TARGET_ARM32 then
    Patch32(jmpPatch, $EA000000 or ((((CodeLen - jmpPatch) div 4) - 2) and $00ffffff))
  else if TargetArch = TARGET_AARCH64 then
    Patch32(jmpPatch, $14000000 or (((CodeLen - jmpPatch) div 4) and $03ffffff))
  else if TargetArch = TARGET_XTENSA then
    Patch24(jmpPatch, EncodeXtensaJ(CodeLen - jmpPatch))
  else if TargetArch = TARGET_RISCV32 then
    Patch32(jmpPatch, EncodeRISCVJAL(0, CodeLen - jmpPatch))
  else
    Patch32(jmpPatch, CodeLen - (jmpPatch + 4));

  { Run unit initialization sections before the program body, in dependency
    order (a used unit is fully parsed — and its init proc registered — before
    the using unit). This is where e.g. the LCL `Forms` unit creates Application. }
  for i := 0 to InitProcCount - 1 do
    EmitCallProc(InitProcs[i]);

  { Constant global-var initializers run after unit init, before the body. }
  CompilePendingGlobalInits;

  Expect(tkBegin, 'begin');
  ParseBlock;
  Expect(tkEnd, 'end');
  Eat(tkDot);

  { Verify all forward goto fixups were resolved }
  for i := 0 to GotoLabelCount - 1 do
    if GotoLabelCodePos[i] = -1 then
    begin
      for j := 0 to GotoFixupCount - 1 do
        if TokSlicesMatch(GotoFixupNOff[j], GotoFixupNLen[j], GotoLabelNOff[i], GotoLabelNLen[i]) then
          Error('goto target label never placed: ' +
            GetTokenStrFromRaw(GotoLabelNOff[i], GotoLabelNLen[i]));
    end;

  EmitExit(0);
  ApplyCallFixups;
end;
