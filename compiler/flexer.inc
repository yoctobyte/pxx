{ SPDX-License-Identifier: MPL-2.0 }
{ ===== Fortran Lexer (skeleton) =====
  Esoteric-frontend-probe (feature-esoteric-fortran). FREE-FORM (F90-style)
  source per the ticket's scope call — no fixed-form column rules. Words
  stay tkIdent (Fortran is case-insensitive; fparser.inc upcases for
  keyword/phrase dispatch, the BASIC/Ada pattern). Newlines separate
  statements and lex as tkSemicolon; `!` comments to end of line. Both
  modern operators (==, /=, <=) and single-char forms are lexed; the
  old-style .EQ./.AND. dot-forms are NOT in the skeleton. }

procedure FLexOne;
var
  c: Char;
  s: AnsiString;
  n: Int64;
  numStart, valEnd: Integer;
  isFloat: Boolean;
begin
  { skip spaces/tabs/CR; newline is a statement separator }
  while (SrcPos <= Length(Source)) and (Source[SrcPos] in [' ', #9, #13]) do
    Inc(SrcPos);

  CurTok.Line := SrcLine; CurTok.SVal := ''; CurTok.IVal := 0;
  if SrcPos > Length(Source) then begin CurTok.Kind := tkEOF; Exit; end;
  c := Source[SrcPos];

  if c = '!' then
  begin
    while (SrcPos <= Length(Source)) and (Source[SrcPos] <> #10) do Inc(SrcPos);
    FLexOne;
    Exit;
  end;

  if c = #10 then
  begin
    Inc(SrcLine); Inc(SrcPos);
    CurTok.Kind := tkSemicolon;
    Exit;
  end;

  if c in ['a'..'z','A'..'Z','_'] then
  begin
    s := '';
    while (SrcPos <= Length(Source)) and
          (Source[SrcPos] in ['a'..'z','A'..'Z','0'..'9','_']) do
    begin
      AppendChar(s, Source[SrcPos]);
      Inc(SrcPos);
    end;
    CurTok.Kind := tkIdent;
    CurTok.SVal := s;
    Exit;
  end;

  { numbers: INTEGER or REAL (1.5, 2.0e3); no leading-dot floats (.5) }
  if c in ['0'..'9'] then
  begin
    numStart := SrcPos;
    n := 0;
    while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'9']) do
    begin
      n := n * 10 + (Ord(Source[SrcPos]) - 48);
      Inc(SrcPos);
    end;
    isFloat := ((SrcPos <= Length(Source)) and (Source[SrcPos] = '.') and
                (SrcPos < Length(Source)) and (Source[SrcPos+1] in ['0'..'9'])) or
               ((SrcPos <= Length(Source)) and (Source[SrcPos] in ['e','E','d','D']) and
                (SrcPos < Length(Source)) and (Source[SrcPos+1] in ['0'..'9','+','-']));
    if isFloat then
    begin
      if (SrcPos <= Length(Source)) and (Source[SrcPos] = '.') then
      begin
        Inc(SrcPos);
        while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'9']) do Inc(SrcPos);
      end;
      if (SrcPos <= Length(Source)) and (Source[SrcPos] in ['e','E','d','D']) then
      begin
        { Fortran d/D exponent marker = double; normalize to e for
          StrToDoubleBits below via the copy-and-patch }
        Inc(SrcPos);
        if (SrcPos <= Length(Source)) and (Source[SrcPos] in ['+','-']) then Inc(SrcPos);
        while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'9']) do Inc(SrcPos);
      end;
      valEnd := SrcPos;
      s := Copy(Source, numStart, valEnd - numStart);
      for valEnd := 1 to Length(s) do
        if (s[valEnd] = 'd') or (s[valEnd] = 'D') then s[valEnd] := 'e';
      CurTok.Kind := tkFloat;
      CurTok.IVal := StrToDoubleBits(s);
      Exit;
    end;
    CurTok.Kind := tkInteger;
    CurTok.IVal := n;
    Exit;
  end;

  { strings: 'single' (doubled quote escapes) or "double" quoted }
  if (c = '''') or (c = '"') then
  begin
    Inc(SrcPos);
    s := '';
    while SrcPos <= Length(Source) do
    begin
      if Source[SrcPos] = c then
      begin
        if (SrcPos < Length(Source)) and (Source[SrcPos + 1] = c) then
        begin
          AppendChar(s, c);
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

  Inc(SrcPos);
  case c of
    '+': CurTok.Kind := tkPlus;
    '-': CurTok.Kind := tkMinus;
    '*': CurTok.Kind := tkStar;    { ** (power) = two tkStar; parser rejects }
    '(': CurTok.Kind := tkLParen;
    ')': CurTok.Kind := tkRParen;
    ',': CurTok.Kind := tkComma;
    ':': CurTok.Kind := tkColon;
    ';': CurTok.Kind := tkSemicolon;
    '/': begin
      if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then
      begin
        Inc(SrcPos);
        CurTok.Kind := tkNeq;      { /= }
      end
      else
        CurTok.Kind := tkSlash;
    end;
    '=': begin
      if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then
      begin
        Inc(SrcPos);
        CurTok.Kind := tkEq;       { == }
      end
      else
        CurTok.Kind := tkAssign;   { = }
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
    else
      CurTok.Kind := tkIdent;      { unknown punctuation — parser reports it }
  end;
end;

procedure FLexAll;
var off, len, i: Integer; k: TTokenKind; prevSep: Boolean;
begin
  TokCount := 0; TokCharLen := 0;
  prevSep := True;   { swallow leading blank lines }
  repeat
    FLexOne;
    k := CurTok.Kind;
    if (k = tkSemicolon) and prevSep then
      { collapse runs of blank lines }
    else
    begin
      prevSep := (k = tkSemicolon);
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
    end;
  until k = tkEOF;
end;
