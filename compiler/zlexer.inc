{ SPDX-License-Identifier: MPL-2.0 }
{ ===== Zig Lexer (skeleton) =====
  Same shape as rlexer.inc: single-token ZLexOne driven by SrcPos/SrcLine,
  ZLexAll fills the shared Tokens[]/TokChars[] buffers that Next()/Eat()/
  Expect() already read for every frontend. Zig keywords with a 1:1 shared
  token get one (fn/if/else/while/for/break/continue/return/var/const/
  and/or/true/false); everything else (pub, void, undefined, type names)
  stays tkIdent and is dispatched by text in zparser.inc. Zig is
  case-sensitive with all-lowercase keywords, so the compares are exact.
  See devdocs/progress/working/feature-zig-frontend.md (skeleton scope). }

function ZKeyword(const s: AnsiString): TTokenKind;
begin
  Result := tkIdent;
  case Length(s) of
    2: begin
      if s = 'fn' then Result := tkFn;
      if s = 'if' then Result := tkIf;
      if s = 'or' then Result := tkOr;
    end;
    3: begin
      if s = 'and' then Result := tkAnd;
      if s = 'var' then Result := tkVar;
      if s = 'for' then Result := tkFor;
    end;
    4: begin
      if s = 'else' then Result := tkElse;
      if s = 'true' then Result := tkTrue;
    end;
    5: begin
      if s = 'while' then Result := tkWhile;
      if s = 'break' then Result := tkBreak;
      if s = 'false' then Result := tkFalse;
      if s = 'const' then Result := tkConst;
    end;
    6: begin
      if s = 'return' then Result := tkExit;
    end;
    8: begin
      if s = 'continue' then Result := tkContinue;
    end;
  end;
end;

procedure ZSkipSpace;
begin
  while (SrcPos <= Length(Source)) do
  begin
    case Source[SrcPos] of
      ' ', #9, #13: Inc(SrcPos);
      #10: begin Inc(SrcLine); Inc(SrcPos); end;
      '/':
      begin
        { Zig has line comments only (// and /// doc comments; no block
          comments in the language at all). }
        if (SrcPos < Length(Source)) and (Source[SrcPos+1] = '/') then
        begin
          while (SrcPos <= Length(Source)) and (Source[SrcPos] <> #10) do Inc(SrcPos);
        end
        else Exit;
      end;
      else Exit;
    end;
  end;
end;

procedure ZLexOne;
var
  c: Char;
  s: AnsiString;
  n: Int64;
  d: Integer;
begin
  ZSkipSpace;
  CurTok.Line := SrcLine; CurTok.SVal := ''; CurTok.IVal := 0;
  if SrcPos > Length(Source) then begin CurTok.Kind := tkEOF; Exit; end;
  c := Source[SrcPos];

  { identifiers / keywords; @builtins lex as a single tkIdent with the @
    kept in the text so the parser can reject them with a real message
    instead of a generic unexpected-token error. }
  if (c in ['a'..'z','A'..'Z','_']) or (c = '@') then
  begin
    s := '';
    if c = '@' then begin AppendChar(s, '@'); Inc(SrcPos); end;
    while (SrcPos <= Length(Source)) and
          (Source[SrcPos] in ['a'..'z','A'..'Z','0'..'9','_']) do
    begin
      AppendChar(s, Source[SrcPos]);
      Inc(SrcPos);
    end;
    CurTok.Kind := ZKeyword(s);
    CurTok.SVal := s;
    Exit;
  end;

  { integer literals: decimal with optional _ separators, plus 0x hex.
    (0b/0o and float literals are out of the skeleton subset.) }
  if c in ['0'..'9'] then
  begin
    n := 0;
    if (c = '0') and (SrcPos < Length(Source)) and
       ((Source[SrcPos+1] = 'x') or (Source[SrcPos+1] = 'X')) then
    begin
      Inc(SrcPos, 2);
      while (SrcPos <= Length(Source)) and
            ((Source[SrcPos] in ['0'..'9','a'..'f','A'..'F']) or (Source[SrcPos] = '_')) do
      begin
        if Source[SrcPos] <> '_' then
        begin
          d := Ord(Source[SrcPos]);
          if d >= Ord('a') then d := d - Ord('a') + 10
          else if d >= Ord('A') then d := d - Ord('A') + 10
          else d := d - Ord('0');
          n := n * 16 + d;
        end;
        Inc(SrcPos);
      end;
    end
    else
    begin
      while (SrcPos <= Length(Source)) and
            ((Source[SrcPos] in ['0'..'9']) or (Source[SrcPos] = '_')) do
      begin
        if Source[SrcPos] <> '_' then
          n := n * 10 + (Ord(Source[SrcPos]) - 48);
        Inc(SrcPos);
      end;
    end;
    CurTok.Kind := tkInteger;
    CurTok.IVal := n;
    Exit;
  end;

  { char literal 'x' / '\n' -> integer token (Zig chars are comptime_int;
    the skeleton treats them as plain integers). }
  if c = '''' then
  begin
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
    CurTok.Kind := tkInteger;
    CurTok.IVal := n;
    Exit;
  end;

  { string literal "..." with the usual escapes, decoded here so downstream
    AN_STR_LIT nodes (and the print-fmt splitter in zparser.inc) see the
    final bytes. }
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
            '''': AppendChar(s, '''');
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
             CurTok.Kind := tkDotDot;
           end
           else CurTok.Kind := tkDot;
         end;
    ':': CurTok.Kind := tkColon;
    '?': CurTok.Kind := tkQuestion;
    '&': CurTok.Kind := tkAmp;
    '|': CurTok.Kind := tkPipe;
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

procedure ZLexAll;
var off, len, i: Integer; k: TTokenKind;
begin
  TokCount := 0; TokCharLen := 0;
  repeat
    ZLexOne;
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
