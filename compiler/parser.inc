{$ifdef FPC}
procedure LoadFile(const path: AnsiString; var dst: AnsiString); forward;
{$endif}
function GetFilePath(const path: AnsiString): AnsiString; forward;
procedure ExpandIncludes(var src: AnsiString; const baseDir: AnsiString); forward;
procedure ParseCUnit; forward;

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
  Result := ASTNodeCount;
  Inc(ASTNodeCount);
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
function ParseStatementAST: Integer; forward;
function ParseWithStatementAST: Integer; forward;
function ParseAsmStatementAST: Integer; forward;
function ParseBlockAST: Integer; forward;
procedure CompileAST(node: Integer); forward;
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
  Eat(tkSemicolon);
  
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
  
  SpecializeTemplateName := Templates[ti].Name;
  SpecializeStream(Templates[ti].TokStart, Templates[ti].TokCount, specName, Templates[ti].Param, concreteName, concreteType);
  Next;
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
  
  { Insert specializations AFTER the template method body, not at the dot position }
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

  { Resolve recId for the operand type }
  recId := IsRecordType(typeName);
  if recId = REC_NONE then
  begin
    ci := FindUClass(typeName);
    if ci < 0 then Error('operator overloading: ' + typeName + ' is not a record or class type');
    recId := REC_UCLASS_BASE + ci;
  end;

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
  RegisterOpOverload(Ord(opKind), Ord(tyClass), recId, procIdx);
end;

function ParseLValueAST(idx: Integer; identTokIdx: Integer): Integer;
var
  node, indexNode, fieldNode, prevTok, recName, i: Integer;
  baseNode, baseRec, fIdx, aliasIdx: Integer;
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
      indexNode := AllocNode(AN_INDEX);
      ASTLeft[indexNode] := node;
      ParseExpr;
      ASTRight[indexNode] := CurASTNode;
      Expect(tkRBrack, ']');
      if IsNodeArray(node) then
      begin
        if ASTKind[node] = AN_IDENT then
        begin
          tk := Syms[ASTIVal[node]].ElemType;
          recName := Syms[ASTIVal[node]].ElemRecName;
        end
        else
          recName := ResolveNodeRec(node);
      end
      else if tk = tyString then
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
          if (mmi >= 0) and (UMthVirSlot[mmi] >= 0) then
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

procedure ParseFactor;
var name: AnsiString; recName: Integer; idx, pi, i, node, left, prevTok, valNode: Integer; tk: TTypeKind; op, argSeq, argSeq2, argSeq3, lastArg, argIdx, exprNode, szArg: Integer;
    nArgs, argsHead, currArg: Integer; argTypes: array[0..15] of TTypeKind;
    ci, mmi, mpi, mcallNode, mlastArg, smSelfIdx, smselfArg: Integer;
    aliasIdx, fieldNode, indexNode, baseNode, baseRec, fIdx, mci, margSeq, margIdx, mexprNode, mai, pri, qUnit: Integer;
    fieldName, methName: AnsiString; isAssign: Boolean; castTk: TTypeKind;
begin
  LastExprTk := tyInteger;
  case CurTok.Kind of
    tkInteger:
    begin
      node := AllocNode(AN_INT_LIT); ASTIVal[node] := CurTok.IVal; ASTTk[node] := Ord(tyInteger); CurASTNode := node; Next;
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
    tkLParen:  begin Next; ParseExpr; Expect(tkRParen, ')'); end;
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
      LastExprTk := tyBoolean;
      node := AllocNode(AN_NOT); ASTLeft[node] := left; ASTTk[node] := Ord(tyBoolean); CurASTNode := node;
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
      if (idx < 0) or (Syms[idx].TypeKind <> tyString) then Error('SysOpen: not a string var');
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
          else if CaseEqual(name, 'ansistring') or CaseEqual(name, 'string') then
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
          else if CaseEqual(name, 'string') or CaseEqual(name, 'ansistring') then castTk := tyString;

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
        if (mmi >= 0) and UMthIsStatic[mmi] then
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
      if (idx >= 0) and (Syms[idx].Kind = skConst) then
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
        CurASTNode := node;
      end
      else if (pi >= 0) and Procs[pi].IsFunc and (Procs[pi].ParamCount = 0) then
      begin
        Next;
        node := AllocNode(AN_CALL);
        ASTIVal[node] := pi;
        ASTTk[node] := Ord(Procs[pi].RetType);
        CurASTNode := node;
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
            if (mmi >= 0) and (UMthVirSlot[mmi] >= 0) then
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
        end;
      end;
    end;
    else Error('expected expression');
  end;
end;

procedure ParseTerm;
var op: TTokenKind; left, right, node, opSOffset, opSLen: Integer;
begin
  ParseFactor;
  while (CurTok.Kind in [tkStar, tkSlash, tkDiv, tkMod, tkAnd, tkShl]) or
        ((CurTok.Kind = tkIdent) and (CurTok.SVal = 'shr')) do
  begin
    opSOffset := Tokens[TokPos - 1].SOffset;
    opSLen := Tokens[TokPos - 1].SLen;
    op := CurTok.Kind; Next;
    left := CurASTNode;
    ParseFactor;
    right := CurASTNode;
    node := AllocNode(AN_BINOP); ASTIVal[node] := Ord(op); ASTLeft[node] := left; ASTRight[node] := right;
    ASTSOffset[node] := opSOffset; ASTSLen[node] := opSLen;
    if (op = tkAnd) and (ASTTk[left] = Ord(tyBoolean)) and (ASTTk[right] = Ord(tyBoolean)) then
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
var op: TTokenKind; neg: Boolean; left, right, node: Integer;
begin
  neg := CurTok.Kind = tkMinus; Eat(tkMinus); Eat(tkPlus);
  ParseTerm;
  if neg then
  begin
    node := AllocNode(AN_NEG); ASTLeft[node] := CurASTNode; ASTTk[node] := ASTTk[CurASTNode]; CurASTNode := node;
  end;
  while CurTok.Kind in [tkPlus, tkMinus, tkOr] do
  begin
    op := CurTok.Kind; Next;
    left := CurASTNode;
    ParseTerm;
    right := CurASTNode;
    node := AllocNode(AN_BINOP); ASTIVal[node] := Ord(op); ASTLeft[node] := left; ASTRight[node] := right;
    if (op = tkPlus) and ((ASTTk[left] = Ord(tyString)) or (ASTTk[right] = Ord(tyString)) or
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
var op: TTokenKind; left, right, node: Integer;
begin
  ParseSimpleExpr;
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
  while CurTok.Kind in [tkPlus, tkMinus, tkStar, tkDiv] do
  begin
    op := CurTok.Kind; Next; v := ConstEval();
    case op of
      tkPlus:  r := r + v;
      tkMinus: r := r - v;
      tkStar:  r := r * v;
      tkDiv:   r := r div v;
    end;
  end;
  Result := r;
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

function ParseForStatementAST: Integer;
var
  varIdx, initNode, limitNode, bodyNode, node: Integer;
  pair1, pair2, pair3, isDownNode: Integer;
  down: Boolean;
begin
  if CurTok.Kind <> tkIdent then Error('for: expected variable');
  varIdx := FindSym(CurTok.SVal);
  if varIdx < 0 then Error('for: undefined');
  Next;
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
  stmtNode, node, si: Integer;
  hasElse: Boolean;
  cv: Int64;
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
  seqNode, lastSeq, stmtNode: Integer;
begin
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
  Result := seqNode;
end;

function ParseTryStatementAST: Integer;
var
  trySeq, tryLast, actionSeq, stmtNode, node: Integer;
  handlerHead, lastHandler, handlerNode, handlerVar, ci, recId: Integer;
  handlerName, className: AnsiString;
begin
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

function ParseStatementAST: Integer;
var
  name: AnsiString;
   idx, pi, i, si, node, valNode, stepsNode, opNode, argSeq, argIdx, exprNode, lastArg, identTokIdx: Integer;
  nArgs, argsHead, currArg: Integer; argTypes: array[0..15] of TTypeKind;
  isLn: Boolean;
  smci, smmii, smpii, smcallNode, smselfArg, smLastArg, smArgSeq, smMai, smSelfIdx: Integer;
  aliasIdx, fieldNode, indexNode, castPrevTok, qUnit: Integer;
  castFieldName: AnsiString; castTk: TTypeKind; castRec: Integer;
begin
  node := -1;
  case CurTok.Kind of
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
      if CaseEqual(name, 'inherited') then
        node := ParseInheritedCallAST
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
        { -101 = string SetLength; -102 = dynamic-array SetLength (heap alloc). }
        if (idx >= 0) and Syms[idx].IsArray and (Syms[idx].ArrLen = -1) then
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
        if CurTok.Kind = tkColon then
        begin
          Next;
          if CurTok.Kind <> tkInteger then Error('Str: expected integer width after :');
          castPrevTok := CurTok.IVal; Next;
          if CurTok.Kind = tkColon then
          begin
            Next;
            if CurTok.Kind <> tkInteger then Error('Str: expected integer decimals after :');
            Next;                                  { decimals: parsed, ignored }
          end;
        end;
        Expect(tkComma, ',');
        if CurTok.Kind <> tkIdent then Error('Str: expected destination string variable');
        idx := FindSym(CurTok.SVal); identTokIdx := TokPos - 1; Next;
        valNode := ParseLValueAST(idx, identTokIdx);
        Expect(tkRParen, ')');

        pi := FindProc('StrInt');
        if pi < 0 then Error('Str: builtin unit not loaded');
        stepsNode := AllocNode(AN_INT_LIT);
        ASTIVal[stepsNode] := castPrevTok; ASTTk[stepsNode] := Ord(tyInteger);
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := exprNode;
        ASTRight[argSeq] := AllocNode(AN_ARG);
        ASTLeft[ASTRight[argSeq]] := stepsNode;
        opNode := AllocNode(AN_CALL);
        ASTIVal[opNode] := pi; ASTLeft[opNode] := argSeq; ASTTk[opNode] := Ord(tyString);
        node := AllocNode(AN_ASSIGN);
        ASTLeft[node] := valNode; ASTRight[node] := opNode;
      end
      else if (CurProc >= 0) and Procs[CurProc].IsFunc and
              (Tokens[TokPos].Kind = tkAssign) and
              ((name = Procs[CurProc].Name) or
               CaseEqual(name, LastDotName(Procs[CurProc].Name))) then
      begin
        Next; Expect(tkAssign, ':=');
        valNode := AllocNode(AN_IDENT);
        ASTIVal[valNode] := Procs[CurProc].RetSymIdx;

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
            if Procs[pi].Params[i].IsRef or Procs[pi].Params[i].IsArray then
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
              if (smmii >= 0) and (UMthVirSlot[smmii] >= 0) then
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
              if (ASTKind[valNode] = AN_CALL) or (ASTKind[valNode] = AN_VIRTUAL_CALL) then
                node := valNode
              else
              begin
                Expect(tkAssign, ':=');
                ParseExpr;
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
  LastTypeEnumId := -1;
  case CurTok.Kind of
    tkCaret:
    begin
      Next;
      elemTk := ParseTypeKind;
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
        elemTk := ParseTypeKind;
        { inline `set of TFoo`: the element parse records the enum identity in
          LastTypeEnumId; carry it as the set's element enum for RTTI. }
        LastTypeSetEnumId := LastTypeEnumId;
        Result := tySet;
        Exit;
      end;
      if CaseEqual(lo, 'ansistring') then Result := tyString
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
      else
      begin
        if IsClassType(lo) then
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
                Result := tyPointer;
              end
              else
              begin
                LastTypeRecId := AliasElemRec[aliasIdx];
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
var names: array[0..63] of AnsiString; n, i, idx: Integer; tk: TTypeKind;
    isArr, isDyn: Boolean; arrLo, arrHi: Integer; elemTk: TTypeKind;
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
      names[n] := CurTok.SVal; Inc(n); Next;
    until not Eat(tkComma);
    Expect(tkColon, ':');
    isArr := False; isDyn := False; arrLo := 0; arrHi := 0; elemTk := tyInteger;
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
      end
      else
        isDyn := True;   { 'array of T' without bounds is a dynamic array }
      Expect(tkOf, 'of');
      elemTk := ParseTypeKind;
      tk := elemTk;
    end
    else
    begin
      { Skip qualifiers like pointer, ^, etc. }
      while not (CurTok.Kind in [tkSemicolon, tkBegin, tkVar, tkConst, tkType,
                 tkProcedure, tkFunction, tkEOF]) do
      begin
        tk := ParseTypeKind;
      end;
    end;
	    if isArr then
	      for i := 0 to n-1 do
	      begin
	        if isDyn then
	          idx := AllocDynArray(names[i], elemTk)
	        else
	        begin
	          idx := AllocArray(names[i], elemTk, arrLo, arrHi);
	          if elemTk = tyRecord then
	            Syms[idx].ElemRecName := LastTypeRecId;
	        end;
	      end
	    else
	      for i := 0 to n-1 do
	      begin
	        idx := AllocVar(names[i], tk);
	        if (tk = tyRecord) or (tk = tyClass) then
	          Syms[idx].RecName := LastTypeRecId
	        else if tk = tyPointer then
	        begin
	          Syms[idx].PtrElemTk := LastTypePointerElemTk;
	          Syms[idx].PtrElemRec := LastTypePointerElemRec;
	        end;
	      end;
	    if Eat(tkEq) then
	    begin
	      while not (CurTok.Kind in [tkSemicolon, tkEOF]) do Next;
	    end;
	    Eat(tkSemicolon);
	  end;
	end;

procedure ParseConstSection;
var name: AnsiString; v: Int64;
begin
  Next;
  while CurTok.Kind = tkIdent do
  begin
    name := CurTok.SVal; Next;
    Expect(tkEq, '=');
    v := ConstEval;
    AddConst(name, tyInteger, v);
    Eat(tkSemicolon);
  end;
end;

procedure ParseTypeSection;
{ Handles enum types, record/class type declarations }
var
  ordinal: Int64;
  tname: AnsiString;
  done, stopTypes: Boolean; loVal, hiVal, arrLen: Integer; isArr: Boolean; isPackedRecord: Boolean;
  tnOff, tnLen, ci, fnOff, fnLen, curFieldOff, fRec, fSize, fAlign, classAlign, depth: Integer;
  fTk: TTypeKind;
  parentCi, slot, mmi, mnOff, mnLen, pnOff, pnLen, rFOff, rFLen, rMOff, rMLen, wFOff, wFLen, wMOff, wMLen, rnOff, rnLen, wnOff, wnLen, propRec, i: Integer;
  isConstructor, isDestructor, isVirtual, isOverride, isAbstract, isClassMethod: Boolean;
  mname, propName, readName, writeName: AnsiString;
  propTk: TTypeKind;
  mIsFunc, mDoneArgs, mDoneParam, mIsArr, mIsByRef: Boolean;
  mRetType, mTk: TTypeKind;
  mNParams, mStartIdx, mTokKindOrd, mpi, mSelfIdx, mFullNameOff, mFullNameLen: Integer;
  curPublished: Integer;  { 1 while inside a published section of the current class body }
  etid, propEnumId, propSetEnumId: Integer;
  mFullName: AnsiString;
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
      if CaseEqual(CurTok.SVal, 'specialize') then
      begin
        ParseSpecialization(tname);
      end
      else if CurTok.Kind = tkLParen then
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
        if Eat(tkLParen) then
        begin
          if CurTok.Kind <> tkIdent then Error('expected parent class name');
          parentCi := FindUClass(CurTok.SVal);
          if parentCi < 0 then Error('parent class not found: ' + CurTok.SVal);
          Next;
          Expect(tkRParen, ')');
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
            if CurTok.Kind = tkArray then
            begin
              Next;
              Expect(tkLBrack, '[');
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
              end;
              Expect(tkRBrack, ']');
              Expect(tkOf, 'of');
              fTk := ParseTypeKind;
              fRec := LastTypeRecId;
              isArr := True;
            end
            else
            begin
              fTk := ParseTypeKind;
              fRec := LastTypeRecId;
            end;
            if fTk = tyString then
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
        for i := 0 to UClsVirtCount[ci] * 8 - 1 do
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
            if CurTok.Kind = tkArray then
            begin
              Next;
              Expect(tkLBrack, '[');
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
              end;
              Expect(tkRBrack, ']');
              Expect(tkOf, 'of');
              fTk := ParseTypeKind;
              fRec := LastTypeRecId;
              isArr := True;
            end
            else
            begin
              fTk := ParseTypeKind;
              fRec := LastTypeRecId;
            end;
            if fTk = tyString then
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
        fTk := ParseTypeKind;
        RegisterPtrAlias(tnOff, tnLen, Ord(fTk), LastTypeRecId);
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
      else if (CurTok.Kind = tkArray) or (CurTok.Kind = tkProcedure) or (CurTok.Kind = tkFunction) then
      begin
        { Skip named array/subroutine type defs (not supported as simple aliases) }
        while not (CurTok.Kind in [tkSemicolon,tkEOF]) do Next;
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
  parr      : array[0..15] of Boolean;
  pbyref    : array[0..15] of Boolean;
  nparams  : Integer;
  pi, i, sz, retRecId, savedLastTypeRecId: Integer;
  savedSC, savedFS, savedCurProc : Integer;
  savedGLC, savedGFC, j: Integer;
  patchPos : Integer;
  depth    : Integer;
  doneArgs, doneParam, isArr, isByRef, isConst, declOverload, isClassKeyword, isStaticMethod: Boolean;
  isAsmFunc: Boolean;
  asmNode: Integer;
  startIdx, idx: Integer;
  tokKindOrd: Integer;
  methOwnerCi, methOwnerRec, methSNOff, methSNLen, mmi, slot, otherCi: Integer;
  methName: AnsiString;
  extLib: AnsiString;
begin
  isClassKeyword := False;
  isAsmFunc := False;
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
      BufferGenericMethod(depth, TokPos - 2);
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
      tokKindOrd := Ord(CurTok.Kind);
      if DebugTrace then writeln('After colon, CurTok.Kind = ', tokKindOrd, ', CurTok.SVal = ', CurTok.SVal);
      if CurTok.Kind = tkArray then
      begin
        Next;
        Expect(tkOf, 'of');
        tk := ParseTypeKind;
        isArr := True;
      end
      else
        tk := ParseTypeKind;
      { A `const` record param is passed by reference (like FPC). Passing it by
        value truncates to a single qword, dropping all but the first field. }
      if isConst and (tk = tyRecord) and not isArr then
        isByRef := True;
      for i := startIdx to nparams-1 do
      begin
        ptypes[i] := tk;
        ptypesRec[i] := LastTypeRecId;
        ptypesPtrElemTk[i] := LastTypePointerElemTk;
        ptypesPtrElemRec[i] := LastTypePointerElemRec;
        parr[i] := isArr;
        pbyref[i] := isByRef;
      end;
      if not Eat(tkSemicolon) then doneArgs := True;
    end;
    Expect(tkRParen, ')');
  end;

  if isFunc then
  begin
    Expect(tkColon, ':');
    retType := ParseTypeKind;
    if retType = tyRecord then
      retRecId := LastTypeRecId;
  end;

  Eat(tkSemicolon);
  declOverload := False;
  while ((CurTok.Kind = tkIdent) and
         ((CurTok.SVal = 'inline') or (CurTok.SVal = 'Inline') or (CurTok.SVal = 'INLINE') or
          (CurTok.SVal = 'register') or (CurTok.SVal = 'Register') or (CurTok.SVal = 'REGISTER') or
          (CurTok.SVal = 'cdecl') or (CurTok.SVal = 'Cdecl') or (CurTok.SVal = 'CDECL') or
          CaseEqual(CurTok.SVal, 'assembler'))) or
        (CurTok.Kind = tkOverload) do
  begin
    if CurTok.Kind = tkOverload then declOverload := True;
    if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'assembler') then isAsmFunc := True;
    Next;
    Eat(tkSemicolon);
  end;

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
    if (mmi >= 0) and UMthIsStatic[mmi] then
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
      parr[i]   := parr[i-1];
      pbyref[i] := pbyref[i-1];
    end;
    pnames[0] := 'Self';
    ptypes[0] := tyClass;
    ptypesRec[0] := REC_NONE;   { Self's RecName is wired to the owner class below }
    ptypesPtrElemTk[0] := tyUnknown;
    ptypesPtrElemRec[0] := REC_NONE;
    parr[0]   := False;
    pbyref[0] := False;
    nparams := nparams + 1;
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
    if (ptypes[i] = tyClass) or (ptypes[i] = tyRecord) then
      Syms[idx].RecName := ptypesRec[i];
    if ptypes[i] = tyPointer then
    begin
      Syms[idx].PtrElemTk := ptypesPtrElemTk[i];
      Syms[idx].PtrElemRec := ptypesPtrElemRec[i];
    end;
  end;
  { Wire Self's RecName so field lookups resolve against the owner class }
  if (methOwnerCi >= 0) and not UMthIsStatic[mmi] then
    Syms[Procs[pi].Params[0].SymIdx].RecName := methOwnerRec;

  { Return value slot }
  if isFunc then
  begin
    savedLastTypeRecId := LastTypeRecId;
    if retType = tyRecord then
      LastTypeRecId := ProcRetRecId[pi];
    if retType = tyString then
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
    if TypeIsAggregate(retType) then
    begin
      idx := AllocVar('', tyPointer);
      ProcAggregateDestSym[pi] := idx;
    end;
  end;

  { Prologue }
  patchPos := EmitProcPrologue;
  Procs[pi].FramePatch := patchPos;
  if ProcAggregateDestSym[pi] >= 0 then
  begin
    idx := ProcAggregateDestSym[pi];
    EmitB($4C); EmitB($89); EmitB($95); EmitI32(Syms[idx].Offset); { mov [rbp+off], r10 }
  end;

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
  else
  begin
    Expect(tkBegin, 'begin');
    ParseBlock;
    Expect(tkEnd, 'end');
    Eat(tkSemicolon);
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

  { Patch frame size }
  PatchProcPrologue(patchPos, FrameSize);

  { Restore scope }
  SymCount  := savedSC;
  FrameSize := savedFS;
  GotoLabelCount := savedGLC;
  GotoFixupCount := savedGFC;
  CurProc   := -1;
  CurSelfClass := REC_NONE;
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

procedure ParseUsesUnit(const name: AnsiString);
var
  lo, path: AnsiString;
  startPos, savedTokPos, strIdx, i, savedCurrentUnitIdx: Integer;
  savedCurTokKind: TTokenKind;
  savedCurTokSVal: AnsiString;
  savedCurTokIVal: Int64;
  savedCurTokLine: Integer;
  savedSrcBase: AnsiString;
  cdir, rtldir, lcldir: AnsiString;
  isCompiled, isCUnit, isCHeader, savedCaseMode: Boolean;
begin
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
  ConcatThree(SourceFileDir, lo, '.pas', path);
  LoadFile(path, UnitContent);
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
    cdir := 'compiler/'; rtldir := 'lib/rtl/'; lcldir := 'lib/lcl/';
  end
  else
  begin
    cdir := ExeDir;
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
    Error('uses: unit source not found');
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
      else if (lo = 'dl') then
        CurrentCLibrary := 'libdl.so.2'
      else if (lo = 'rt') then
        CurrentCLibrary := 'librt.so.1'
      else if (lo = 'z') then
        CurrentCLibrary := 'libz.so.1'
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
    ParseCUnit;
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

    { Append tokens to global Token stream }
    startPos := LexAppend(UnitContent);
    i := startPos;
    while i < TokCount do
    begin
      if Tokens[i].Kind in [tkTry, tkRaise] then EnableExceptionRuntime;
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

  { Optional local var/const/type sections (rare in init, but harmless). }
  while CurTok.Kind in [tkVar, tkConst, tkType] do
    case CurTok.Kind of
      tkVar:   ParseVarSection;
      tkConst: ParseConstSection;
      tkType:  ParseTypeSection;
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
        while (CurTok.Kind = tkIdent) and not doneUses do
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
          while (CurTok.Kind = tkIdent) and not doneUses do
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

procedure ParseProgram;
var jmpPatch, i, j: Integer; doneUses, doneDecls, hasExceptions, needsBuiltin: Boolean;
begin
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
  ExceptionUsed := False;
  hasExceptions := False;
  needsBuiltin := False;
  for i := 0 to MAX_GOTO_LABELS - 1 do GotoLabelIRId[i] := -1;
  i := 0;
  while i < TokCount do
  begin
    if Tokens[i].Kind in [tkTry, tkRaise] then hasExceptions := True;
    { Pull in the builtin unit (Str/Val backing) only if the program calls
      Str(...) or Val(...) — name immediately followed by '(', so plain
      variables/params named str/val don't drag it in. No DCE, so this keeps it
      out of programs that never use them. }
    if (Tokens[i].Kind = tkIdent) and (i + 1 < TokCount) and
       (Tokens[i + 1].Kind = tkLParen) and
       (CaseEqual(GetTokenStr(i), 'str') or CaseEqual(GetTokenStr(i), 'val')) then
      needsBuiltin := True;
    Inc(i);
  end;

  { Emit entry stub: save rsp then jmp to main body }
  { mov [bss_initial_rsp], rsp: 48 89 24 25 <GlobRef(0)> }
  EmitB($48); EmitB($89); EmitB($24); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);

  { Initialize heap: reserve an arena via mmap (NOT brk). libc/GTK manage the
    program break for their own malloc, so a brk-based heap would corrupt it. }
  MovRsiImm(HEAP_ARENA_SIZE);
  EmitMmapArena;                                          { rax = arena base }
  EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_HEAP_PTR);
  EmitB($48); EmitB($89); EmitB($C2);                     { mov rdx, rax }
  EmitB($48); EmitB($81); EmitB($C2); EmitI32(HEAP_ARENA_SIZE); { add rdx, ARENA }
  EmitB($48); EmitB($89); EmitB($14); EmitB($25); EmitGlobRef(BSS_HEAP_END);

  EmitB($E9); jmpPatch := CodeLen; EmitI32(0);
  if hasExceptions then EnableExceptionRuntime;

  { Compile the builtin unit (Str/Val) before user declarations, so its proc
    bodies land in the proc region after the entry jump and are resolvable. }
  if needsBuiltin then ParseUsesUnit('builtin');

  doneDecls := False;
  while not doneDecls do
    case CurTok.Kind of
      tkUses:
      begin
        Next;
        doneUses := False;
        while (CurTok.Kind = tkIdent) and not doneUses do
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
  Patch32(jmpPatch, CodeLen - (jmpPatch + 4));

  { Run unit initialization sections before the program body, in dependency
    order (a used unit is fully parsed — and its init proc registered — before
    the using unit). This is where e.g. the LCL `Forms` unit creates Application. }
  for i := 0 to InitProcCount - 1 do
    EmitCallProc(InitProcs[i]);

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
