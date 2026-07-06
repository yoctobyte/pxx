{ SPDX-License-Identifier: MPL-2.0 }
{ ===== BASIC Lexer ===== }

function BKeyword(const s: AnsiString): TTokenKind;
var
  lower: AnsiString;
  i: Integer;
begin
  SetLength(lower, Length(s));
  for i := 1 to Length(s) do
  begin
    if s[i] in ['A'..'Z'] then
      lower[i] := Chr(Ord(s[i]) + 32)
    else
      lower[i] := s[i];
  end;
  
  Result := tkIdent;
  case Length(lower) of
    2: begin
      if lower = 'if' then Result := tkIf;
      if lower = 'to' then Result := tkTo;
      if lower = 'or' then Result := tkOr;
    end;
    3: begin
      if lower = 'let' then Result := tkVar;
      if lower = 'dim' then Result := tkVar;
      if lower = 'sub' then Result := tkProcedure;
      if lower = 'end' then Result := tkEnd;
      if lower = 'for' then Result := tkFor;
      if lower = 'and' then Result := tkAnd;
      if lower = 'not' then Result := tkNot;
    end;
    4: begin
      if lower = 'then' then Result := tkThen;
      if lower = 'else' then Result := tkElse;
      { 'goto' stays tkIdent — dispatched by text in bparser.inc and lowered
        to a real AN_GOTO (bug-basic-goto-gosub-halts-program: the old
        goto->tkHalt alias silently ENDED the program at the jump). }
      if lower = 'next' then Result := tkEnd;
      if lower = 'wend' then Result := tkEnd;
      if lower = 'step' then Result := tkTo;
      if lower = 'uses' then Result := tkUses;
    end;
    5: begin
      if lower = 'print' then Result := tkwriteln;
      if lower = 'while' then Result := tkWhile;
      { 'gosub' stays tkIdent — same fix as 'goto' above. }
    end;
    6: begin
      if lower = 'return' then Result := tkExit;
    end;
    7: begin
      if lower = 'default' then Result := tkDefault;
    end;
    8: begin
      if lower = 'function' then Result := tkFunction;
    end;
  end;
end;

procedure BLexOne(SupportLineNumbers: Boolean; var IsAtLineStart: Boolean);
var
{$ifdef FPC}
  c: Char;
{$else}
  c: Integer;
{$endif}
  s: AnsiString;
  n: Int64;
  done: Boolean;
begin
  { Skip non-newline whitespace }
  done := False;
  while (SrcPos <= Length(Source)) and not done do
  begin
    case Source[SrcPos] of
      ' ', #9, #13: Inc(SrcPos);
      else done := True;
    end;
  end;

  CurTok.Line := SrcLine;
  CurTok.SVal := '';
  CurTok.IVal := 0;

  if SrcPos > Length(Source) then
  begin
    CurTok.Kind := tkEOF;
    Exit;
  end;

  c := Source[SrcPos];

  { Handle statement separators: newline or colon }
  if (c = #10) or (c = ':') then
  begin
    if c = #10 then Inc(SrcLine);
    Inc(SrcPos);
    CurTok.Kind := tkSemicolon;
    IsAtLineStart := True;
    Exit;
  end;

  { Handle single quote comment }
  if c = '''' then
  begin
    while (SrcPos <= Length(Source)) and (Source[SrcPos] <> #10) do
      Inc(SrcPos);
    { Recursively call BLexOne to get the next actual token or newline }
    BLexOne(SupportLineNumbers, IsAtLineStart);
    Exit;
  end;

  { Handle standard identifiers and keywords }
  if c in ['a'..'z','A'..'Z','_'] then
  begin
    s := '';
    while (SrcPos <= Length(Source)) and
          (Source[SrcPos] in ['a'..'z','A'..'Z','0'..'9','_']) do
    begin
      AppendChar(s, Source[SrcPos]);
      Inc(SrcPos);
    end;
    
    { Check if it is a REM comment }
    if (Length(s) = 3) and 
       ((s[1]='r') or (s[1]='R')) and 
       ((s[2]='e') or (s[2]='E')) and 
       ((s[3]='m') or (s[3]='M')) then
    begin
      while (SrcPos <= Length(Source)) and (Source[SrcPos] <> #10) do
        Inc(SrcPos);
      BLexOne(SupportLineNumbers, IsAtLineStart);
      Exit;
    end;

    CurTok.Kind := BKeyword(s);
    CurTok.SVal := s;
    IsAtLineStart := False;
    Exit;
  end;

  { Handle numbers (line numbers or literal integers) }
  if c in ['0'..'9'] then
  begin
    n := 0;
    while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'9']) do
    begin
      n := n * 10 + (Ord(Source[SrcPos]) - 48);
      Inc(SrcPos);
    end;
    CurTok.Kind := tkInteger;
    CurTok.IVal := n;
    IsAtLineStart := False;
    Exit;
  end;

  { Handle double quoted string literals }
  if c = '"' then
  begin
    Inc(SrcPos);
    s := '';
    while (SrcPos <= Length(Source)) and (Source[SrcPos] <> '"') do
    begin
      AppendChar(s, Source[SrcPos]);
      Inc(SrcPos);
    end;
    if SrcPos <= Length(Source) then Inc(SrcPos);
    CurTok.Kind := tkString;
    CurTok.SVal := s;
    IsAtLineStart := False;
    Exit;
  end;

  { Handle operators and punctuation }
  Inc(SrcPos);
  IsAtLineStart := False;
  case c of
    '+': CurTok.Kind := tkPlus;
    '-': CurTok.Kind := tkMinus;
    '*': CurTok.Kind := tkStar;
    '/': CurTok.Kind := tkSlash;
    '(': CurTok.Kind := tkLParen;
    ')': CurTok.Kind := tkRParen;
    ',': CurTok.Kind := tkComma;
    '=': CurTok.Kind := tkEq;
    '<': begin
      if (SrcPos <= Length(Source)) and (Source[SrcPos] = '>') then
      begin
        Inc(SrcPos);
        CurTok.Kind := tkNeq;
      end
      else if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then
      begin
        Inc(SrcPos);
        CurTok.Kind := tkLe;
      end
      else
        CurTok.Kind := tkLt;
    end;
    '>': begin
      if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then
      begin
        Inc(SrcPos);
        CurTok.Kind := tkGe;
      end
      else
        CurTok.Kind := tkGt;
    end;
    else
      CurTok.Kind := tkIdent; { unknown, treated as ident }
  end;
end;

procedure BLexAll(SupportLineNumbers: Boolean);
var
  off, len, i: Integer;
  k: TTokenKind;
  IsAtLineStart: Boolean;
begin
  TokCount := 0;
  TokCharLen := 0;
  IsAtLineStart := True;
  repeat
    BLexOne(SupportLineNumbers, IsAtLineStart);
    k := CurTok.Kind;
    if TokCount >= MAX_TOKENS then Error('token overflow');
    Tokens[TokCount].Kind    := k;
    Tokens[TokCount].IVal    := CurTok.IVal;
    Tokens[TokCount].Line    := CurTok.Line;
    if (k = tkIdent) or (k = tkString) then
    begin
      off := TokCharLen;
      len := Length(CurTok.SVal);
      Tokens[TokCount].SOffset := off;
      Tokens[TokCount].SLen    := len;
      for i := 1 to len do
      begin
        TokChars[TokCharLen] := CurTok.SVal[i];
        Inc(TokCharLen);
      end;
    end
    else
    begin
      Tokens[TokCount].SOffset := 0;
      Tokens[TokCount].SLen    := 0;
    end;
    Inc(TokCount);
  until k = tkEOF;
end;
