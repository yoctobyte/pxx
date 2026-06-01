{ ===== Nil Python Lexer ===== }

function PyKeyword(const s: AnsiString): TTokenKind;
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
      if lower = 'in' then Result := tkIn;
      if lower = 'or' then Result := tkOr;
    end;
    3: begin
      if lower = 'def' then Result := tkFunction;
      if lower = 'and' then Result := tkAnd;
      if lower = 'not' then Result := tkNot;
      if lower = 'try' then Result := tkTry;
    end;
    4: begin
      if lower = 'else' then Result := tkElse;
      if lower = 'elif' then Result := tkIdent;
      if lower = 'pass' then Result := tkIdent;
      if lower = 'true' then Result := tkTrue;
      if lower = 'none' then Result := tkNil;
    end;
    5: begin
      if lower = 'while' then Result := tkWhile;
      if lower = 'false' then Result := tkFalse;
      if lower = 'print' then Result := tkwriteln;
      if lower = 'break' then Result := tkBreak;
      if lower = 'class' then Result := tkClass;
      if lower = 'raise' then Result := tkRaise;
    end;
    6: begin
      if lower = 'return' then Result := tkExit;
      if lower = 'except' then Result := tkExcept;
    end;
    7: begin
      if lower = 'finally' then Result := tkFinally;
    end;
  end;
end;

procedure PyEmitToken(k: TTokenKind; ival: Int64; line: Integer; const sval: AnsiString);
var
  off, len, i: Integer;
begin
  if TokCount >= MAX_TOKENS then
  begin
    CurTok.Line := line;
    Error('token overflow');
  end;
  Tokens[TokCount].Kind := k;
  Tokens[TokCount].IVal := ival;
  Tokens[TokCount].Line := line;
  if (k = tkIdent) or (k = tkString) then
  begin
    off := TokCharLen;
    len := Length(sval);
    if TokCharLen + len >= STRING_CAP then
    begin
      CurTok.Line := line;
      Error('token char buffer overflow');
    end;
    Tokens[TokCount].SOffset := off;
    Tokens[TokCount].SLen := len;
    for i := 1 to len do
    begin
      TokChars[TokCharLen] := sval[i];
      Inc(TokCharLen);
    end;
  end
  else
  begin
    Tokens[TokCount].SOffset := 0;
    Tokens[TokCount].SLen := 0;
  end;
  Inc(TokCount);
end;

procedure PyLexAll(SupportLineNumbers: Boolean);
var
  P: Integer;
  IndentStack: array[0..1024] of Integer;
  IndentStackTop: Integer;
  parenDepth: Integer;
  HasSpaceIndent: Boolean;
  HasTabIndent: Boolean;
  IndentWidth: Integer;
  IsBlankOrComment: Boolean;
  IsLogicalLine: Boolean;
  c, quoteChar: Char;
  s: AnsiString;
  n: Int64;
  floatStart, fpos: Integer;
  k: TTokenKind;
begin
  TokCount := 0;
  TokCharLen := 0;
  P := 1;
  SrcLine := 1;

  IndentStack[0] := 0;
  IndentStackTop := 0;
  parenDepth := 0;
  HasSpaceIndent := False;
  HasTabIndent := False;

  while P <= Length(Source) do
  begin
    { 1. Measure indentation width at the start of a physical line }
    IndentWidth := 0;
    while (P <= Length(Source)) and ((Source[P] = ' ') or (Source[P] = #9)) do
    begin
      if Source[P] = ' ' then HasSpaceIndent := True;
      if Source[P] = #9 then HasTabIndent := True;
      if HasSpaceIndent and HasTabIndent then
      begin
        CurTok.Line := SrcLine;
        Error('mixing tabs and spaces for indentation');
      end;
      Inc(IndentWidth);
      Inc(P);
    end;

    { 2. Check if the line is blank or comment-only }
    IsBlankOrComment := False;
    if P > Length(Source) then
      IsBlankOrComment := True
    else if (Source[P] = #10) or (Source[P] = #13) then
      IsBlankOrComment := True
    else if Source[P] = '#' then
      IsBlankOrComment := True;

    if not IsBlankOrComment then
    begin
      { If parenDepth = 0, process indentation changes }
      if parenDepth = 0 then
      begin
        if IndentWidth > IndentStack[IndentStackTop] then
        begin
          Inc(IndentStackTop);
          if IndentStackTop > 1024 then
          begin
            CurTok.Line := SrcLine;
            Error('indentation stack overflow');
          end;
          IndentStack[IndentStackTop] := IndentWidth;
          PyEmitToken(tkIndent, 0, SrcLine, '');
        end
        else if IndentWidth < IndentStack[IndentStackTop] then
        begin
          while IndentWidth < IndentStack[IndentStackTop] do
          begin
            Dec(IndentStackTop);
            PyEmitToken(tkDedent, 0, SrcLine, '');
          end;
          if IndentWidth <> IndentStack[IndentStackTop] then
          begin
            CurTok.Line := SrcLine;
            Error('inconsistent dedent');
          end;
        end;
      end;
    end;

    { 3. Tokenize the physical line until we hit a newline or EOF }
    IsLogicalLine := False;
    while (P <= Length(Source)) and (Source[P] <> #10) and (Source[P] <> #13) do
    begin
      c := Source[P];

      { Skip non-newline whitespace }
      if (c = ' ') or (c = #9) then
      begin
        Inc(P);
        continue;
      end;

      { Skip comment to end of line }
      if c = '#' then
      begin
        while (P <= Length(Source)) and (Source[P] <> #10) and (Source[P] <> #13) do
          Inc(P);
        break;
      end;

      { An actual token is about to be read, making this a logical line }
      IsLogicalLine := True;

      { Identifiers and Keywords }
      if c in ['a'..'z','A'..'Z','_'] then
      begin
        s := '';
        while (P <= Length(Source)) and (Source[P] in ['a'..'z','A'..'Z','0'..'9','_']) do
        begin
          AppendChar(s, Source[P]);
          Inc(P);
        end;
        k := PyKeyword(s);
        PyEmitToken(k, 0, SrcLine, s);
        continue;
      end;

      { Numbers (Integers or Floats) }
      if c in ['0'..'9'] then
      begin
        n := 0;
        floatStart := P;
        while (P <= Length(Source)) and (Source[P] in ['0'..'9']) do
        begin
          n := n * 10 + (Ord(Source[P]) - 48);
          Inc(P);
        end;
        { detect float: '.' followed by digit, or e/E exponent }
        if ((P < Length(Source)) and (Source[P] = '.') and (Source[P+1] in ['0'..'9'])) or
           ((P <= Length(Source)) and ((Source[P] = 'e') or (Source[P] = 'E'))) then
        begin
          if (P < Length(Source)) and (Source[P] = '.') and (Source[P+1] in ['0'..'9']) then
          begin
            Inc(P);
            while (P <= Length(Source)) and (Source[P] in ['0'..'9']) do Inc(P);
          end;
          if (P <= Length(Source)) and ((Source[P] = 'e') or (Source[P] = 'E')) then
          begin
            Inc(P);
            if (P <= Length(Source)) and ((Source[P] = '+') or (Source[P] = '-')) then Inc(P);
            while (P <= Length(Source)) and (Source[P] in ['0'..'9']) do Inc(P);
          end;
          s := ''; fpos := floatStart;
          while fpos < P do begin AppendChar(s, Source[fpos]); Inc(fpos); end;
          PyEmitToken(tkFloat, StrToDoubleBits(s), SrcLine, '');
        end
        else
        begin
          PyEmitToken(tkInteger, n, SrcLine, '');
        end;
        continue;
      end;

      { String Literals }
      if (c = '"') or (c = '''') then
      begin
        quoteChar := c;
        Inc(P);
        s := '';
        while (P <= Length(Source)) and (Source[P] <> quoteChar) do
        begin
          if Source[P] = '\' then
          begin
            Inc(P);
            if P <= Length(Source) then
            begin
              case Source[P] of
                'n': AppendChar(s, #10);
                't': AppendChar(s, #9);
                '\': AppendChar(s, '\');
                '''': AppendChar(s, '''');
                '"': AppendChar(s, '"');
                else begin AppendChar(s, '\'); AppendChar(s, Source[P]); end;
              end;
              Inc(P);
            end;
          end
          else
          begin
            AppendChar(s, Source[P]);
            Inc(P);
          end;
        end;
        if P <= Length(Source) then Inc(P);
        PyEmitToken(tkString, 0, SrcLine, s);
        continue;
      end;

      { Operators and Punctuation }
      Inc(P);
      case c of
        '+': PyEmitToken(tkPlus, 0, SrcLine, '');
        '-': PyEmitToken(tkMinus, 0, SrcLine, '');
        '*': PyEmitToken(tkStar, 0, SrcLine, '');
        '/': begin
          if (P <= Length(Source)) and (Source[P] = '/') then
          begin
            Inc(P);
            PyEmitToken(tkDiv, 0, SrcLine, '');
          end
          else
            PyEmitToken(tkSlash, 0, SrcLine, '');
          end;
        '%': PyEmitToken(tkMod, 0, SrcLine, '');
        '(': begin PyEmitToken(tkLParen, 0, SrcLine, ''); Inc(parenDepth); end;
        ')': begin
          PyEmitToken(tkRParen, 0, SrcLine, '');
          Dec(parenDepth);
          if parenDepth < 0 then
          begin
            CurTok.Line := SrcLine;
            Error('unmatched closing parenthesis');
          end;
        end;
        '[': begin PyEmitToken(tkLBrack, 0, SrcLine, ''); Inc(parenDepth); end;
        ']': begin
          PyEmitToken(tkRBrack, 0, SrcLine, '');
          Dec(parenDepth);
          if parenDepth < 0 then
          begin
            CurTok.Line := SrcLine;
            Error('unmatched closing bracket');
          end;
        end;
        '{': begin PyEmitToken(tkLParen, 0, SrcLine, ''); Inc(parenDepth); end;
        '}': begin
          PyEmitToken(tkRParen, 0, SrcLine, '');
          Dec(parenDepth);
          if parenDepth < 0 then
          begin
            CurTok.Line := SrcLine;
            Error('unmatched closing brace');
          end;
        end;
        ':': PyEmitToken(tkColon, 0, SrcLine, '');
        ',': PyEmitToken(tkComma, 0, SrcLine, '');
        '.': PyEmitToken(tkDot, 0, SrcLine, '');
        ';': PyEmitToken(tkSemicolon, 0, SrcLine, '');
        '=': begin
          if (P <= Length(Source)) and (Source[P] = '=') then
          begin
            Inc(P);
            PyEmitToken(tkEq, 0, SrcLine, '');
          end
          else
            PyEmitToken(tkAssign, 0, SrcLine, '');
        end;
        '!': begin
          if (P <= Length(Source)) and (Source[P] = '=') then
          begin
            Inc(P);
            PyEmitToken(tkNeq, 0, SrcLine, '');
          end
          else
          begin
            CurTok.Line := SrcLine;
            Error('unexpected character !');
          end;
        end;
        '<': begin
          if (P <= Length(Source)) and (Source[P] = '=') then
          begin
            Inc(P);
            PyEmitToken(tkLe, 0, SrcLine, '');
          end
          else
            PyEmitToken(tkLt, 0, SrcLine, '');
        end;
        '>': begin
          if (P <= Length(Source)) and (Source[P] = '=') then
          begin
            Inc(P);
            PyEmitToken(tkGe, 0, SrcLine, '');
          end
          else
            PyEmitToken(tkGt, 0, SrcLine, '');
        end;
        else
        begin
          CurTok.Line := SrcLine;
          Error('unexpected character: ' + c);
        end;
      end;
    end;

    { 4. End of physical line: emit tkNewline if logical line and paren depth is 0 }
    if IsLogicalLine and (parenDepth = 0) then
    begin
      PyEmitToken(tkNewline, 0, SrcLine, '');
    end;

    { Consume physical newline }
    if P <= Length(Source) then
    begin
      if Source[P] = #13 then
      begin
        Inc(P);
        if (P <= Length(Source)) and (Source[P] = #10) then Inc(P);
        Inc(SrcLine);
      end
      else if Source[P] = #10 then
      begin
        Inc(P);
        Inc(SrcLine);
      end;
    end;
  end;

  { EOF Validation }
  if parenDepth > 0 then
  begin
    CurTok.Line := SrcLine;
    Error('unmatched opening parenthesis/bracket/brace at end of file');
  end;

  { 5. EOF: emit tkDedent down to baseline, and then emit tkEOF }
  while IndentStackTop > 0 do
  begin
    Dec(IndentStackTop);
    PyEmitToken(tkDedent, 0, SrcLine, '');
  end;

  PyEmitToken(tkEOF, 0, SrcLine, '');
end;
