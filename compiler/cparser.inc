{ ===== C Parser ===== }

procedure ParseCBlock; forward;

function IsCTypeTok: Boolean;
begin
  Result := CurTok.Kind in [tkInteger_T, tkChar_T];
end;

procedure ParseCPrintf;
{ printf("literal") — hardcoded intrinsic, no format parsing yet }
var strIdx: Integer; s: AnsiString;
begin
  Next; { skip 'printf' }
  Expect(tkLParen, '(');
  if CurTok.Kind = tkString then
  begin
    s := CurTok.SVal;
    strIdx := InternStr(s);
    Next;
    if Strs[strIdx].Len > 0 then
      EmitwriteSyscall(Strs[strIdx].Offset + 8, Strs[strIdx].Len);
  end;
  { skip any remaining args }
  while (CurTok.Kind <> tkRParen) and (CurTok.Kind <> tkEOF) do Next;
  Expect(tkRParen, ')');
  Eat(tkSemicolon);
end;

procedure ParseCStatement;
var retVal: Int64; name: AnsiString;
begin
  if CurTok.Kind = tkEOF then Exit;

  { return expr; }
  if CurTok.Kind = tkExit then
  begin
    Next;
    retVal := 0;
    if CurTok.Kind = tkInteger then begin retVal := CurTok.IVal; Next; end;
    Eat(tkSemicolon);
    EmitExit(retVal);
    Exit;
  end;

  { printf(...) }
  if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'printf') then
  begin
    ParseCPrintf;
    Exit;
  end;

  { nested block }
  if CurTok.Kind = tkBegin then
  begin
    ParseCBlock;
    Exit;
  end;

  { skip type declarations and unknown statements to } ; { }
  while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEnd) and
        (CurTok.Kind <> tkEOF) do Next;
  Eat(tkSemicolon);
end;

procedure ParseCBlock;
begin
  Expect(tkBegin, '{');
  while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
    ParseCStatement;
  Expect(tkEnd, '}');
end;

procedure ParseCProgram;
var jmpPatch: Integer; name: AnsiString;
begin
  BSS_INITIAL_RSP := BSSSize; Inc(BSSSize, 8);

  EmitB($48); EmitB($89); EmitB($24); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
  EmitB($E9); jmpPatch := CodeLen; EmitI32(0);

  { Scan top level for 'main' function definition }
  while CurTok.Kind <> tkEOF do
  begin
    if IsCTypeTok then
    begin
      Next;
      if CurTok.Kind = tkStar then Next;  { pointer return type }
      if CurTok.Kind = tkIdent then
      begin
        name := CurTok.SVal;
        Next;
        if CurTok.Kind = tkLParen then
        begin
          { skip parameter list }
          while (CurTok.Kind <> tkRParen) and (CurTok.Kind <> tkEOF) do Next;
          Expect(tkRParen, ')');
          if CurTok.Kind = tkBegin then
          begin
            if name = 'main' then
            begin
              Patch32(jmpPatch, CodeLen - (jmpPatch + 4));
              ParseCBlock;
              EmitExit(0);
              ApplyCallFixups;
              Exit;
            end
            else
            begin
              { skip non-main function bodies for now }
              ParseCBlock;
            end;
          end;
        end
        else
        begin
          { global variable declaration — skip to ; }
          while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
          Eat(tkSemicolon);
        end;
      end;
    end
    else
      Next;
  end;
  Error('main function not found');
end;
