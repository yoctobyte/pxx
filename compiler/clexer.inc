{ ===== C Lexer ===== }

function CKeyword(const s: AnsiString): TTokenKind;
begin
  Result := tkIdent;
  case Length(s) of
    2: begin
      if (s[1]='i') and (s[2]='f') then Result := tkIf;
      if (s[1]='d') and (s[2]='o') then Result := tkDo;
    end;
    3: begin
      if (s[1]='i') and (s[2]='n') and (s[3]='t') then Result := tkInteger_T;
      if (s[1]='f') and (s[2]='o') and (s[3]='r') then Result := tkFor;
    end;
    4: begin
      if (s[1]='c') and (s[2]='h') and (s[3]='a') and (s[4]='r') then Result := tkChar_T;
      if (s[1]='v') and (s[2]='o') and (s[3]='i') and (s[4]='d') then Result := tkInteger_T;
      if (s[1]='e') and (s[2]='l') and (s[3]='s') and (s[4]='e') then Result := tkElse;
      if (s[1]='l') and (s[2]='o') and (s[3]='n') and (s[4]='g') then Result := tkInteger_T;
    end;
    5: begin
      if (s[1]='w') and (s[2]='h') and (s[3]='i') and (s[4]='l') and (s[5]='e') then Result := tkWhile;
      if (s[1]='s') and (s[2]='h') and (s[3]='o') and (s[4]='r') and (s[5]='t') then Result := tkInteger_T;
      if (s[1]='c') and (s[2]='o') and (s[3]='n') and (s[4]='s') and (s[5]='t') then Result := tkConst;
      if (s[1]='b') and (s[2]='r') and (s[3]='e') and (s[4]='a') and (s[5]='k') then Result := tkHalt;
    end;
    6: begin
      if (s[1]='r') and (s[2]='e') and (s[3]='t') and (s[4]='u') and (s[5]='r') and (s[6]='n') then Result := tkExit;
      if (s[1]='s') and (s[2]='t') and (s[3]='r') and (s[4]='u') and (s[5]='c') and (s[6]='t') then Result := tkRecord;
      if (s[1]='s') and (s[2]='i') and (s[3]='g') and (s[4]='n') and (s[5]='e') and (s[6]='d') then Result := tkInteger_T;
      if (s[1]='d') and (s[2]='o') and (s[3]='u') and (s[4]='b') and (s[5]='l') and (s[6]='e') then Result := tkInteger_T;
    end;
    8: begin
      if (s[1]='u') and (s[2]='n') and (s[3]='s') and (s[4]='i') and (s[5]='g') and (s[6]='n') and (s[7]='e') and (s[8]='d') then Result := tkInteger_T;
    end;
  end;
end;

procedure CSkipSpace;
var done: Boolean;
begin
  done := False;
  while (SrcPos <= Length(Source)) and not done do
  begin
    case Source[SrcPos] of
      ' ', #9, #13: Inc(SrcPos);
      #10: begin Inc(SrcLine); Inc(SrcPos); end;
      '/':
      begin
        if (SrcPos < Length(Source)) and (Source[SrcPos+1] = '/') then
        begin
          while (SrcPos <= Length(Source)) and (Source[SrcPos] <> #10) do Inc(SrcPos);
        end
        else if (SrcPos < Length(Source)) and (Source[SrcPos+1] = '*') then
        begin
          Inc(SrcPos); Inc(SrcPos);
          while (SrcPos < Length(Source)) and
                not ((Source[SrcPos] = '*') and (Source[SrcPos+1] = '/')) do
          begin
            if Source[SrcPos] = #10 then Inc(SrcLine);
            Inc(SrcPos);
          end;
          if SrcPos < Length(Source) then begin Inc(SrcPos); Inc(SrcPos); end;
        end
        else done := True;
      end;
      '#':
      begin
        while (SrcPos <= Length(Source)) and (Source[SrcPos] <> #10) do Inc(SrcPos);
      end;
      else done := True;
    end;
  end;
end;

procedure CLexOne;
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
  CSkipSpace;
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
    CurTok.Kind := CKeyword(s);
    CurTok.SVal := s;
    Exit;
  end;

  if c in ['1'..'9'] then
  begin
    n := 0;
    while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'9']) do
      begin n := n * 10 + (Ord(Source[SrcPos]) - 48); Inc(SrcPos); end;
    CurTok.Kind := tkInteger; CurTok.IVal := n; Exit;
  end;

  { 0, 0x hex, or 0 alone }
  if c = '0' then
  begin
    Inc(SrcPos);
    if (SrcPos <= Length(Source)) and
       ((Source[SrcPos] = 'x') or (Source[SrcPos] = 'X')) then
    begin
      Inc(SrcPos); n := 0; done := False;
      while (SrcPos <= Length(Source)) and not done do
      begin
        c := Source[SrcPos];
        if c in ['0'..'9'] then begin n := n*16 + (Ord(c)-48); Inc(SrcPos); end
        else if c in ['a'..'f'] then begin n := n*16 + (Ord(c)-87); Inc(SrcPos); end
        else if c in ['A'..'F'] then begin n := n*16 + (Ord(c)-55); Inc(SrcPos); end
        else done := True;
      end;
    end else begin
      n := 0;
      while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'9']) do
        begin n := n * 10 + (Ord(Source[SrcPos]) - 48); Inc(SrcPos); end;
    end;
    CurTok.Kind := tkInteger; CurTok.IVal := n; Exit;
  end;

  if c = '"' then
  begin
    Inc(SrcPos);
    s := '';
    while (SrcPos <= Length(Source)) and (Source[SrcPos] <> '"') do
    begin
      if Source[SrcPos] = '\' then
      begin
        Inc(SrcPos);
        if SrcPos <= Length(Source) then
        begin
          case Source[SrcPos] of
            'n': AppendChar(s, #10);
            't': AppendChar(s, #9);
            'r': AppendChar(s, #13);
            '\': AppendChar(s, '\');
            '"': AppendChar(s, '"');
            '0': AppendChar(s, #0);
            else  AppendChar(s, Source[SrcPos]);
          end;
          Inc(SrcPos);
        end;
      end
      else
      begin
        AppendChar(s, Source[SrcPos]);
        Inc(SrcPos);
      end;
    end;
    if SrcPos <= Length(Source) then Inc(SrcPos);
    CurTok.Kind := tkString; CurTok.SVal := s; Exit;
  end;

  if c = '''' then
  begin
    Inc(SrcPos);
    if (SrcPos <= Length(Source)) and (Source[SrcPos] = '\') then
    begin
      Inc(SrcPos);
      if SrcPos <= Length(Source) then
      begin
        case Source[SrcPos] of
          'n': CurTok.IVal := 10;
          't': CurTok.IVal := 9;
          'r': CurTok.IVal := 13;
          '\': CurTok.IVal := Ord('\');
          '''': CurTok.IVal := Ord('''');
          '0': CurTok.IVal := 0;
          else  CurTok.IVal := Ord(Source[SrcPos]);
        end;
        Inc(SrcPos);
      end;
    end
    else if SrcPos <= Length(Source) then
    begin
      CurTok.IVal := Ord(Source[SrcPos]);
      Inc(SrcPos);
    end;
    if (SrcPos <= Length(Source)) and (Source[SrcPos] = '''') then Inc(SrcPos);
    CurTok.Kind := tkInteger; Exit;
  end;

  Inc(SrcPos);
  case c of
    '+': begin
           if (SrcPos <= Length(Source)) and (Source[SrcPos] = '+') then Inc(SrcPos)
           else if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then Inc(SrcPos);
           CurTok.Kind := tkPlus;
         end;
    '-': begin
           if (SrcPos <= Length(Source)) and (Source[SrcPos] = '-') then begin Inc(SrcPos); CurTok.Kind := tkMinus; end
           else if (SrcPos <= Length(Source)) and (Source[SrcPos] = '>') then begin Inc(SrcPos); CurTok.Kind := tkDot; end
           else if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then begin Inc(SrcPos); CurTok.Kind := tkMinus; end
           else CurTok.Kind := tkMinus;
         end;
    '*': CurTok.Kind := tkStar;
    '/': CurTok.Kind := tkSlash;
    '%': CurTok.Kind := tkMod;
    '(': CurTok.Kind := tkLParen;
    ')': CurTok.Kind := tkRParen;
    '[': CurTok.Kind := tkLBrack;
    ']': CurTok.Kind := tkRBrack;
    '{': CurTok.Kind := tkBegin;
    '}': CurTok.Kind := tkEnd;
    ';': CurTok.Kind := tkSemicolon;
    ',': CurTok.Kind := tkComma;
    '.': CurTok.Kind := tkDot;
    '~': CurTok.Kind := tkNot;
    '&': begin
           if (SrcPos <= Length(Source)) and (Source[SrcPos] = '&') then Inc(SrcPos);
           CurTok.Kind := tkAnd;
         end;
    '|': begin
           if (SrcPos <= Length(Source)) and (Source[SrcPos] = '|') then Inc(SrcPos);
           CurTok.Kind := tkOr;
         end;
    '!': begin
           if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then
             begin Inc(SrcPos); CurTok.Kind := tkNeq; end
           else CurTok.Kind := tkNot;
         end;
    '=': begin
           if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then
             begin Inc(SrcPos); CurTok.Kind := tkEq; end
           else CurTok.Kind := tkAssign;
         end;
    '<': begin
           if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then
             begin Inc(SrcPos); CurTok.Kind := tkLe; end
           else CurTok.Kind := tkLt;
         end;
    '>': begin
           if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then
             begin Inc(SrcPos); CurTok.Kind := tkGe; end
           else CurTok.Kind := tkGt;
         end;
    else CurTok.Kind := tkIdent; { unknown punctuation — skip }
  end;
end;

procedure CLexAll;
var off, len, i: Integer; k: TTokenKind;
begin
  TokCount := 0; TokCharLen := 0;
  repeat
    CLexOne;
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

function CLexAppend(const srcText: AnsiString): Integer;
var
  savedSource: AnsiString;
  savedSrcPos, savedSrcLine: Integer;
  unitStart, len, i, off: Integer;
  sval: AnsiString;
  k: TTokenKind;
begin
  savedSource := Source;
  savedSrcPos := SrcPos;
  savedSrcLine := SrcLine;

  Source := srcText;
  SrcPos := 1;
  SrcLine := 1;

  if (TokCount > 0) and (Tokens[TokCount-1].Kind = tkEOF) then
  begin
    Dec(TokCount);
    unitStart := TokCount;
  end
  else
    unitStart := TokCount;

  repeat
    CLexOne;
    k := CurTok.Kind;
    if TokCount >= MAX_TOKENS then Error('token buffer overflow');
    Tokens[TokCount].Kind    := k;
    Tokens[TokCount].IVal    := CurTok.IVal;
    Tokens[TokCount].Line    := CurTok.Line;
    sval := CurTok.SVal;
    len  := Length(sval);
    Tokens[TokCount].SOffset := TokCharLen;
    Tokens[TokCount].SLen    := len;
    i := 1;
    while i <= len do
    begin
      TokChars[TokCharLen] := sval[i];
      Inc(TokCharLen);
      Inc(i);
    end;
    Inc(TokCount);
  until k = tkEOF;

  Source := savedSource;
  SrcPos := savedSrcPos;
  SrcLine := savedSrcLine;
  Result := unitStart;
end;
