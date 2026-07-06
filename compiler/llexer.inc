{ SPDX-License-Identifier: MPL-2.0 }
{ ===== LOLCODE Lexer (skeleton) =====
  Esoteric-frontend-probe (feature-esoteric-lolcode): word-based lexer.
  Every bare word is a tkIdent (LOLCODE keywords are multi-word phrases —
  "I HAS A", "SUM OF" — so lparser.inc matches word SEQUENCES by text
  instead of the lexer inventing composite tokens). Newlines and commas
  (LOLCODE's soft line break) both lex as tkSemicolon = statement
  separator. `?` (as in `O RLY?`) is skipped as decoration. BTW comments
  to end of line; OBTW ... TLDR block comments. }

procedure LLexOne;
var
  c: Char;
  s: AnsiString;
  n: Int64;
begin
  { skip spaces/tabs/CR — newline is significant (statement separator) }
  while (SrcPos <= Length(Source)) and
        (Source[SrcPos] in [' ', #9, #13, '?']) do
    Inc(SrcPos);

  CurTok.Line := SrcLine; CurTok.SVal := ''; CurTok.IVal := 0;
  if SrcPos > Length(Source) then begin CurTok.Kind := tkEOF; Exit; end;
  c := Source[SrcPos];

  if (c = #10) or (c = ',') then
  begin
    if c = #10 then Inc(SrcLine);
    Inc(SrcPos);
    CurTok.Kind := tkSemicolon;
    Exit;
  end;

  { words (keywords stay tkIdent; parser matches phrases by text) }
  if c in ['a'..'z','A'..'Z','_'] then
  begin
    s := '';
    while (SrcPos <= Length(Source)) and
          (Source[SrcPos] in ['a'..'z','A'..'Z','0'..'9','_']) do
    begin
      AppendChar(s, Source[SrcPos]);
      Inc(SrcPos);
    end;
    { BTW comment to end of line; OBTW ... TLDR block comment }
    if s = 'BTW' then
    begin
      while (SrcPos <= Length(Source)) and (Source[SrcPos] <> #10) do Inc(SrcPos);
      LLexOne;
      Exit;
    end;
    if s = 'OBTW' then
    begin
      while SrcPos <= Length(Source) do
      begin
        if Source[SrcPos] = #10 then Inc(SrcLine);
        if (Source[SrcPos] = 'T') and (SrcPos + 3 <= Length(Source)) and
           (Source[SrcPos+1] = 'L') and (Source[SrcPos+2] = 'D') and (Source[SrcPos+3] = 'R') then
        begin
          Inc(SrcPos, 4);
          Break;
        end;
        Inc(SrcPos);
      end;
      LLexOne;
      Exit;
    end;
    CurTok.Kind := tkIdent;
    CurTok.SVal := s;
    Exit;
  end;

  { NUMBRs (integers only in the skeleton; no NUMBARs/floats) }
  if (c in ['0'..'9']) or
     ((c = '-') and (SrcPos < Length(Source)) and (Source[SrcPos+1] in ['0'..'9'])) then
  begin
    n := 0;
    if c = '-' then Inc(SrcPos);
    while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'9']) do
    begin
      n := n * 10 + (Ord(Source[SrcPos]) - 48);
      Inc(SrcPos);
    end;
    if c = '-' then n := -n;
    CurTok.Kind := tkInteger;
    CurTok.IVal := n;
    Exit;
  end;

  { YARNs: double-quoted; :" escaped quote, :) newline, :: literal colon }
  if c = '"' then
  begin
    Inc(SrcPos);
    s := '';
    while (SrcPos <= Length(Source)) and (Source[SrcPos] <> '"') do
    begin
      if (Source[SrcPos] = ':') and (SrcPos < Length(Source)) then
      begin
        Inc(SrcPos);
        case Source[SrcPos] of
          ')': AppendChar(s, #10);
          '>': AppendChar(s, #9);
          '"': AppendChar(s, '"');
          ':': AppendChar(s, ':');
          else begin AppendChar(s, ':'); AppendChar(s, Source[SrcPos]); end;
        end;
        Inc(SrcPos);
      end
      else
      begin
        AppendChar(s, Source[SrcPos]);
        Inc(SrcPos);
      end;
    end;
    if SrcPos <= Length(Source) then Inc(SrcPos);
    CurTok.Kind := tkString;
    CurTok.SVal := s;
    Exit;
  end;

  { anything else: skip and re-lex (LOLCODE has no operator punctuation) }
  Inc(SrcPos);
  LLexOne;
end;

procedure LLexAll;
var off, len, i: Integer; k: TTokenKind; prevNl: Boolean;
begin
  TokCount := 0; TokCharLen := 0;
  prevNl := True;   { swallow leading blank lines }
  repeat
    LLexOne;
    k := CurTok.Kind;
    { collapse runs of separators (blank lines, trailing commas) }
    if (k = tkSemicolon) and prevNl then
      { skip: consecutive separator adds nothing }
    else
    begin
      prevNl := (k = tkSemicolon);
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
