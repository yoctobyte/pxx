{ SPDX-License-Identifier: MPL-2.0 }
{ ===== Ada Lexer (skeleton) =====
  Mirrors blexer.inc's shape: tokenize Ada source, emitting the SAME shared
  TTokenKind values Pascal/BASIC/Rust already use wherever a concept matches
  1:1 (if/then/else/begin/end/while/for/in/loop/exit/assign/mod/and/or/not),
  so the shared ParseExpr + AllocNode/AllocVar/CompileAST machinery is reused
  unchanged (no new AST nodes, no new IR, no backend work). Keywords with no
  existing 1:1 token (is/elsif/when, and the Put_Line builtin) are left as
  plain tkIdent and dispatched by comparing lowercased text in aparser.inc —
  simpler than inventing/repurposing more token kinds for a handful of
  single-use markers. See devdocs/progress/backlog/feature-esoteric-ada.md. }

function AKeyword(const s: AnsiString): TTokenKind;
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
      if lower = 'or' then Result := tkOr;
      if lower = 'in' then Result := tkIn;
    end;
    3: begin
      if lower = 'end' then Result := tkEnd;
      if lower = 'for' then Result := tkFor;
      if lower = 'and' then Result := tkAnd;
      if lower = 'not' then Result := tkNot;
      if lower = 'mod' then Result := tkMod;
      if lower = 'rem' then Result := tkMod;   { approximation: rem ~ mod for v1, see ticket }
    end;
    4: begin
      if lower = 'then' then Result := tkThen;
      if lower = 'else' then Result := tkElse;
      if lower = 'loop' then Result := tkLoop;
      if lower = 'exit' then Result := tkBreak;   { Ada `exit`/`exit when` = loop break, NOT tkExit (that's procedure/function exit -- see AN_EXIT vs AN_BREAK) }
    end;
    5: begin
      if lower = 'begin' then Result := tkBegin;
      if lower = 'while' then Result := tkWhile;
    end;
    9: begin
      if lower = 'procedure' then Result := tkProcedure;
    end;
  end;
  { 'is', 'elsif', 'when', 'declare', 'Put_Line', type names (Integer/
    Boolean/String), and any other identifier all fall through as tkIdent;
    aparser.inc dispatches on the lowercased text where it needs to. }
end;

procedure ALexOne;
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
  done := False;
  while (SrcPos <= Length(Source)) and not done do
  begin
    case Source[SrcPos] of
      ' ', #9, #13: Inc(SrcPos);
      #10: begin Inc(SrcPos); Inc(SrcLine); end;
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

  { Ada line comment: -- to end of line }
  if (c = '-') and (SrcPos < Length(Source)) and (Source[SrcPos + 1] = '-') then
  begin
    while (SrcPos <= Length(Source)) and (Source[SrcPos] <> #10) do
      Inc(SrcPos);
    ALexOne;
    Exit;
  end;

  { identifiers and keywords }
  if c in ['a'..'z', 'A'..'Z', '_'] then
  begin
    s := '';
    while (SrcPos <= Length(Source)) and
          (Source[SrcPos] in ['a'..'z', 'A'..'Z', '0'..'9', '_']) do
    begin
      AppendChar(s, Source[SrcPos]);
      Inc(SrcPos);
    end;
    CurTok.Kind := AKeyword(s);
    CurTok.SVal := s;
    Exit;
  end;

  { integer literals (decimal only, no underscores/based-literals in v1) }
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
    Exit;
  end;

  { Ada string literals are double-quoted; "" is an escaped quote }
  if c = '"' then
  begin
    Inc(SrcPos);
    s := '';
    while SrcPos <= Length(Source) do
    begin
      if Source[SrcPos] = '"' then
      begin
        if (SrcPos < Length(Source)) and (Source[SrcPos + 1] = '"') then
        begin
          AppendChar(s, '"');
          Inc(SrcPos, 2);
        end
        else
        begin
          Inc(SrcPos);
          Break;
        end;
      end
      else
      begin
        AppendChar(s, Source[SrcPos]);
        Inc(SrcPos);
      end;
    end;
    CurTok.Kind := tkString;
    CurTok.SVal := s;
    Exit;
  end;

  { operators and punctuation }
  Inc(SrcPos);
  case c of
    '+': CurTok.Kind := tkPlus;
    '-': CurTok.Kind := tkMinus;
    '*': CurTok.Kind := tkStar;
    '(': CurTok.Kind := tkLParen;
    ')': CurTok.Kind := tkRParen;
    ',': CurTok.Kind := tkComma;
    ';': CurTok.Kind := tkSemicolon;
    '/': begin
      if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then
      begin
        Inc(SrcPos);
        CurTok.Kind := tkNeq;
      end
      else
        CurTok.Kind := tkSlash;
    end;
    ':': begin
      if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then
      begin
        Inc(SrcPos);
        CurTok.Kind := tkAssign;
      end
      else
        CurTok.Kind := tkColon;
    end;
    '.': begin
      if (SrcPos <= Length(Source)) and (Source[SrcPos] = '.') then
      begin
        Inc(SrcPos);
        CurTok.Kind := tkDotDot;
      end
      else
        CurTok.Kind := tkDot;
    end;
    '=': CurTok.Kind := tkEq;
    '<': begin
      if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then
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
      CurTok.Kind := tkIdent; { unknown char, treated as an empty ident rather than crashing the lexer }
  end;
end;

procedure ALexAll;
var
  off, len, i: Integer;
  k: TTokenKind;
begin
  TokCount := 0;
  TokCharLen := 0;
  repeat
    ALexOne;
    k := CurTok.Kind;
    if TokCount >= MAX_TOKENS then Error('token overflow');
    Tokens[TokCount].Kind := k;
    Tokens[TokCount].IVal := CurTok.IVal;
    Tokens[TokCount].Line := CurTok.Line;
    if (k = tkIdent) or (k = tkString) then
    begin
      off := TokCharLen;
      len := Length(CurTok.SVal);
      if TokCharLen + len > STRING_CAP then Error('token char pool overflow');
      Tokens[TokCount].SOffset := off;
      Tokens[TokCount].SLen := len;
      for i := 1 to len do
      begin
        TokChars[TokCharLen] := CurTok.SVal[i];
        Inc(TokCharLen);
      end;
    end
    else
    begin
      Tokens[TokCount].SOffset := 0;
      Tokens[TokCount].SLen := 0;
    end;
    Inc(TokCount);
  until k = tkEOF;
end;
