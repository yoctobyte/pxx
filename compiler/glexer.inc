{ SPDX-License-Identifier: MPL-2.0 }
{ ===== Algol 60 Lexer (skeleton) =====
  Esoteric-frontend-probe (feature-esoteric-algol) — the kinship probe:
  Algol 60 is Pascal's DIRECT ancestor, so this mirrors alexer.inc (Ada)
  almost exactly: keywords with a 1:1 shared token get one (begin/end/if/
  then/else/for/do + := and the operators), everything else (step/until/
  integer/real/Boolean/outinteger/outstring/comment/true/false) stays
  tkIdent and gparser.inc dispatches on lowercased text. Case-insensitive
  per Algol practice. `comment ... ;` is skipped here in the lexer.
  Strings accept both '...' and "..." (the RRS's typographic quotes are
  not in any practical character set). }

function GKeyword(const s: AnsiString): TTokenKind;
var lower: AnsiString; i: Integer;
begin
  SetLength(lower, Length(s));
  for i := 1 to Length(s) do
  begin
    if s[i] in ['A'..'Z'] then lower[i] := Chr(Ord(s[i]) + 32)
    else lower[i] := s[i];
  end;
  Result := tkIdent;
  case Length(lower) of
    2: begin
      if lower = 'if' then Result := tkIf;
      if lower = 'do' then Result := tkDo;
      if lower = 'or' then Result := tkOr;
    end;
    3: begin
      if lower = 'end' then Result := tkEnd;
      if lower = 'for' then Result := tkFor;
      if lower = 'and' then Result := tkAnd;
      if lower = 'not' then Result := tkNot;
    end;
    4: begin
      if lower = 'then' then Result := tkThen;
      if lower = 'else' then Result := tkElse;
    end;
    5: begin
      if lower = 'begin' then Result := tkBegin;
      if lower = 'while' then Result := tkWhile;
    end;
  end;
  { 'step', 'until', 'integer', 'real', 'Boolean', 'true', 'false',
    'outinteger', 'outstring', 'procedure' (rejected with a real message),
    and identifiers fall through as tkIdent. }
end;

procedure GLexOne;
var
  c: Char;
  s: AnsiString;
  n: Int64;
  numStart, valEnd: Integer;
  isFloat: Boolean;
  q: Char;
begin
  while (SrcPos <= Length(Source)) do
  begin
    case Source[SrcPos] of
      ' ', #9, #13: Inc(SrcPos);
      #10: begin Inc(SrcLine); Inc(SrcPos); end;
      else Break;
    end;
  end;

  CurTok.Line := SrcLine; CurTok.SVal := ''; CurTok.IVal := 0;
  if SrcPos > Length(Source) then begin CurTok.Kind := tkEOF; Exit; end;
  c := Source[SrcPos];

  if c in ['a'..'z','A'..'Z','_'] then
  begin
    s := '';
    while (SrcPos <= Length(Source)) and
          (Source[SrcPos] in ['a'..'z','A'..'Z','0'..'9','_']) do
    begin
      AppendChar(s, Source[SrcPos]);
      Inc(SrcPos);
    end;
    { `comment ... ;` — Algol's comment runs to the next semicolon }
    if (Length(s) = 7) and
       ((s = 'comment') or (s = 'COMMENT') or (s = 'Comment')) then
    begin
      while (SrcPos <= Length(Source)) and (Source[SrcPos] <> ';') do
      begin
        if Source[SrcPos] = #10 then Inc(SrcLine);
        Inc(SrcPos);
      end;
      if SrcPos <= Length(Source) then Inc(SrcPos);   { the ; }
      GLexOne;
      Exit;
    end;
    CurTok.Kind := GKeyword(s);
    CurTok.SVal := s;
    Exit;
  end;

  if c in ['0'..'9'] then
  begin
    numStart := SrcPos;
    n := 0;
    while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'9']) do
    begin
      n := n * 10 + (Ord(Source[SrcPos]) - 48);
      Inc(SrcPos);
    end;
    isFloat := (SrcPos <= Length(Source)) and (Source[SrcPos] = '.') and
               (SrcPos < Length(Source)) and (Source[SrcPos+1] in ['0'..'9']);
    if isFloat then
    begin
      Inc(SrcPos);
      while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'9']) do Inc(SrcPos);
      valEnd := SrcPos;
      s := Copy(Source, numStart, valEnd - numStart);
      CurTok.Kind := tkFloat;
      CurTok.IVal := StrToDoubleBits(s);
      Exit;
    end;
    CurTok.Kind := tkInteger;
    CurTok.IVal := n;
    Exit;
  end;

  if (c = '''') or (c = '"') then
  begin
    q := c;
    Inc(SrcPos);
    s := '';
    while (SrcPos <= Length(Source)) and (Source[SrcPos] <> q) do
    begin
      AppendChar(s, Source[SrcPos]);
      Inc(SrcPos);
    end;
    if SrcPos <= Length(Source) then Inc(SrcPos);
    CurTok.Kind := tkString;
    CurTok.SVal := s;
    Exit;
  end;

  Inc(SrcPos);
  case c of
    '+': CurTok.Kind := tkPlus;
    '-': CurTok.Kind := tkMinus;
    '*': CurTok.Kind := tkStar;
    '/': CurTok.Kind := tkSlash;
    '(': CurTok.Kind := tkLParen;
    ')': CurTok.Kind := tkRParen;
    ',': CurTok.Kind := tkComma;
    ';': CurTok.Kind := tkSemicolon;
    '=': CurTok.Kind := tkEq;
    ':': begin
      if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then
      begin
        Inc(SrcPos);
        CurTok.Kind := tkAssign;
      end
      else
        CurTok.Kind := tkColon;
    end;
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
    '#': CurTok.Kind := tkNeq;   { practical stand-in for the RRS's not-equal }
    else CurTok.Kind := tkIdent; { unknown char — parser reports it }
  end;
end;

procedure GLexAll;
var off, len, i: Integer; k: TTokenKind;
begin
  TokCount := 0; TokCharLen := 0;
  repeat
    GLexOne;
    k := CurTok.Kind;
    if TokCount >= MAX_TOKENS then Error('token overflow');
    Tokens[TokCount].Kind := k;
    Tokens[TokCount].IVal := CurTok.IVal;
    Tokens[TokCount].Line := CurTok.Line;
    if (k = tkIdent) or (k = tkString) then
    begin
      off := TokCharLen;
      len := Length(CurTok.SVal);
      if TokCharLen + len >= STRING_CAP then Error('token char buffer overflow');
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
