{ SPDX-License-Identifier: MPL-2.0 }
{ ===== Rust Lexer (skeleton) =====
  Same shape as clexer.inc: single-token RLexOne driven by SrcPos/SrcLine,
  RLexAll fills the shared Tokens[]/TokChars[] buffers that Next()/Eat()/
  Expect() already read for every frontend. }

function RKeyword(const s: AnsiString): TTokenKind;
begin
  Result := tkIdent;
  case Length(s) of
    2: begin
      if s = 'fn' then Result := tkFn;
      if s = 'if' then Result := tkIf;
    end;
    3: begin
      if s = 'let' then Result := tkLet;
      if s = 'mut' then Result := tkMut;
      if s = 'for' then Result := tkFor;
    end;
    4: begin
      if s = 'else' then Result := tkElse;
      if s = 'true' then Result := tkTrue;
      if s = 'loop' then Result := tkLoop;
    end;
    5: begin
      if s = 'while' then Result := tkWhile;
      if s = 'break' then Result := tkBreak;
      if s = 'false' then Result := tkFalse;
    end;
    6: begin
      if s = 'return' then Result := tkExit;
      if s = 'struct' then Result := tkRecord;   { shared record/class machinery }
    end;
    8: begin
      if s = 'continue' then Result := tkContinue;
    end;
  end;
end;

procedure RSkipSpace;
begin
  while (SrcPos <= Length(Source)) do
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
        else Exit;
      end;
      else Exit;
    end;
  end;
end;

procedure RLexOne;
var
  c: Char;
  s: AnsiString;
  n: Int64;
  numStart, valEnd: Integer;
  isFloat: Boolean;
begin
  RSkipSpace;
  CurTok.Line := SrcLine; CurTok.SVal := ''; CurTok.IVal := 0;
  if SrcPos > Length(Source) then begin CurTok.Kind := tkEOF; Exit; end;
  c := Source[SrcPos];

  { Lifetimes ('a) vs char literals ('a') vs plain quoted char ('\n'):
    a lifetime is a lone `'` followed by an identifier NOT closed by another
    `'`. Parsed as a token shape only — never enforced (see the umbrella's
    non-goal list). }
  if c = '''' then
  begin
    { `'a` starts an identifier and the char right after it is NOT a closing
      quote -> a lifetime ('a, 'static, ...), never a char literal (those are
      exactly one char/escape between two quotes, e.g. 'x', '\n'). }
    if (SrcPos + 1 <= Length(Source)) and (Source[SrcPos+1] in ['a'..'z','A'..'Z','_']) and
       not ((SrcPos + 2 <= Length(Source)) and (Source[SrcPos+2] = '''')) then
    begin
      Inc(SrcPos);
      s := '';
      while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['a'..'z','A'..'Z','0'..'9','_']) do
      begin
        AppendChar(s, Source[SrcPos]);
        Inc(SrcPos);
      end;
      CurTok.Kind := tkLifetime; CurTok.SVal := s; Exit;
    end;
    { char literal 'x' or '\n' }
    Inc(SrcPos);
    n := 0;
    if (SrcPos <= Length(Source)) and (Source[SrcPos] = '\') then
    begin
      Inc(SrcPos);
      if SrcPos <= Length(Source) then
      begin
        case Source[SrcPos] of
          'n': n := 10; 't': n := 9; 'r': n := 13; '\': n := Ord('\');
          '''': n := Ord(''''); '"': n := Ord('"'); '0': n := 0;
          else n := Ord(Source[SrcPos]);
        end;
        Inc(SrcPos);
      end;
    end
    else if SrcPos <= Length(Source) then
    begin
      n := Ord(Source[SrcPos]);
      Inc(SrcPos);
    end;
    if (SrcPos <= Length(Source)) and (Source[SrcPos] = '''') then Inc(SrcPos);
    CurTok.Kind := tkInteger; CurTok.IVal := n; Exit;
  end;

  { Raw string r"..." — no escape processing. Cheap to add, not exercised by
    the skeleton's trivial test programs but part of the lexer's scoped token
    set (umbrella + this ticket). }
  if (c = 'r') and (SrcPos < Length(Source)) and (Source[SrcPos+1] = '"') then
  begin
    Inc(SrcPos); Inc(SrcPos);
    s := '';
    while (SrcPos <= Length(Source)) and (Source[SrcPos] <> '"') do
    begin
      AppendChar(s, Source[SrcPos]);
      Inc(SrcPos);
    end;
    if SrcPos <= Length(Source) then Inc(SrcPos);
    CurTok.Kind := tkString; CurTok.SVal := s; Exit;
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
    CurTok.Kind := RKeyword(s);
    CurTok.SVal := s;
    Exit;
  end;

  if c in ['0'..'9'] then
  begin
    numStart := SrcPos;
    n := 0;
    while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'9','_']) do
    begin
      if Source[SrcPos] <> '_' then n := n * 10 + (Ord(Source[SrcPos]) - 48);
      Inc(SrcPos);
    end;
    isFloat := ((SrcPos <= Length(Source)) and (Source[SrcPos] = '.') and
                (SrcPos < Length(Source)) and (Source[SrcPos+1] in ['0'..'9'])) or
               ((SrcPos <= Length(Source)) and (Source[SrcPos] in ['e','E']));
    if isFloat then
    begin
      if (SrcPos <= Length(Source)) and (Source[SrcPos] = '.') then
      begin
        Inc(SrcPos);
        while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'9','_']) do Inc(SrcPos);
      end;
      if (SrcPos <= Length(Source)) and (Source[SrcPos] in ['e','E']) then
      begin
        Inc(SrcPos);
        if (SrcPos <= Length(Source)) and (Source[SrcPos] in ['+','-']) then Inc(SrcPos);
        while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'9']) do Inc(SrcPos);
      end;
      valEnd := SrcPos;
      s := Copy(Source, numStart, valEnd - numStart);
      { integer literal suffix (i32/i64/u32/u64/f32/f64) — consumed, not yet
        used to pick a narrower type; skeleton scalars default to
        tyInteger/tyInt64/tyDouble via the parser's own annotation handling. }
      while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['a'..'z','0'..'9']) do Inc(SrcPos);
      CurTok.Kind := tkFloat; CurTok.IVal := StrToDoubleBits(s); Exit;
    end;
    while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['a'..'z','0'..'9']) do Inc(SrcPos);
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
            '''': AppendChar(s, '''');
            '"': AppendChar(s, '"');
            else AppendChar(s, Source[SrcPos]);
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

  Inc(SrcPos);
  case c of
    '+': begin
           if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then begin Inc(SrcPos); CurTok.Kind := tkPlusEq; end
           else CurTok.Kind := tkPlus;
         end;
    '-': begin
           { `->` is lexed as plain tkMinus here; the following `>` lexes as
             its own tkGt on the next call (same two-token-sequence approach
             pyparser.inc uses for `->`), no dedicated arrow token needed. }
           if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then begin Inc(SrcPos); CurTok.Kind := tkMinusEq; end
           else CurTok.Kind := tkMinus;
         end;
    '*': begin
           if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then begin Inc(SrcPos); CurTok.Kind := tkStarEq; end
           else CurTok.Kind := tkStar;
         end;
    '/': begin
           if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then begin Inc(SrcPos); CurTok.Kind := tkSlashEq; end
           else CurTok.Kind := tkSlash;
         end;
    '%': CurTok.Kind := tkMod;
    '(': CurTok.Kind := tkLParen;
    ')': CurTok.Kind := tkRParen;
    '[': CurTok.Kind := tkLBrack;
    ']': CurTok.Kind := tkRBrack;
    '{': CurTok.Kind := tkBegin;
    '}': CurTok.Kind := tkEnd;
    ';': CurTok.Kind := tkSemicolon;
    ',': CurTok.Kind := tkComma;
    '.': begin
           if (SrcPos <= Length(Source)) and (Source[SrcPos] = '.') then
           begin
             Inc(SrcPos);
             if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then
               begin Inc(SrcPos); CurTok.Kind := tkDotDotEq; end
             else CurTok.Kind := tkDotDot;
           end
           else CurTok.Kind := tkDot;
         end;
    ':': begin
           if (SrcPos <= Length(Source)) and (Source[SrcPos] = ':') then
             begin Inc(SrcPos); CurTok.Kind := tkPathSep; end
           else CurTok.Kind := tkColon;
         end;
    '&': begin
           if (SrcPos <= Length(Source)) and (Source[SrcPos] = '&') then begin Inc(SrcPos); CurTok.Kind := tkAnd; end
           else CurTok.Kind := tkAmp;
         end;
    '|': begin
           if (SrcPos <= Length(Source)) and (Source[SrcPos] = '|') then begin Inc(SrcPos); CurTok.Kind := tkOr; end
           else CurTok.Kind := tkPipe;
         end;
    '!': begin
           if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then
             begin Inc(SrcPos); CurTok.Kind := tkNeq; end
           else CurTok.Kind := tkLogNot;
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
    else CurTok.Kind := tkIdent; { unknown punctuation — parser reports it }
  end;
end;

procedure RLexAll;
var off, len, i: Integer; k: TTokenKind;
begin
  TokCount := 0; TokCharLen := 0;
  repeat
    RLexOne;
    k := CurTok.Kind;
    if TokCount >= MAX_TOKENS then Error('token overflow');
    Tokens[TokCount].Kind := k;
    Tokens[TokCount].IVal := CurTok.IVal;
    Tokens[TokCount].Line := CurTok.Line;
    if (k = tkIdent) or (k = tkString) or (k = tkLifetime) then
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
