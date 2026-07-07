{ SPDX-License-Identifier: MPL-2.0 }
{ ===== Erlang Lexer (skeleton) =====
  Esoteric-frontend-probe pass on [[feature-erlang-frontend-scoping]].
  Words stay tkIdent (atoms are lowercase, variables Uppercase — the
  parser splits on the first letter, Erlang's actual rule). Notable
  token mappings: `->` lexes as tkThen (the clause-body arrow), `=<` is
  Erlang's less-or-equal (NOT `<=`), `/=` not-equal, `;` clause
  separator = tkSemicolon, `.` definition terminator = tkDot. `%`
  comments to end of line. div/rem stay tkIdent (parser maps to
  tkDiv/tkMod). No scheduler, no processes, no atoms-as-values — see
  the parser header for the subset. }

procedure ELexOne;
var
  c: Char;
  s: AnsiString;
  n: Int64;
begin
  while (SrcPos <= Length(Source)) do
  begin
    case Source[SrcPos] of
      ' ', #9, #13: Inc(SrcPos);
      #10: begin Inc(SrcLine); Inc(SrcPos); end;
      '%':
        while (SrcPos <= Length(Source)) and (Source[SrcPos] <> #10) do Inc(SrcPos);
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
          (Source[SrcPos] in ['a'..'z','A'..'Z','0'..'9','_','@']) do
    begin
      AppendChar(s, Source[SrcPos]);
      Inc(SrcPos);
    end;
    CurTok.Kind := tkIdent;
    CurTok.SVal := s;
    Exit;
  end;

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

  { strings "..." with \n \t \\ \" escapes }
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
            '\': AppendChar(s, '\');
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
    CurTok.Kind := tkString;
    CurTok.SVal := s;
    Exit;
  end;

  Inc(SrcPos);
  case c of
    '+': CurTok.Kind := tkPlus;
    '*': CurTok.Kind := tkStar;
    '(': CurTok.Kind := tkLParen;
    ')': CurTok.Kind := tkRParen;
    '[': CurTok.Kind := tkLBrack;
    ']': CurTok.Kind := tkRBrack;
    '{': CurTok.Kind := tkBegin;
    '}': CurTok.Kind := tkEnd;
    ',': CurTok.Kind := tkComma;
    ';': CurTok.Kind := tkSemicolon;
    '.': CurTok.Kind := tkDot;
    ':': CurTok.Kind := tkColon;
    '-': begin
      if (SrcPos <= Length(Source)) and (Source[SrcPos] = '>') then
      begin
        Inc(SrcPos);
        CurTok.Kind := tkThen;    { -> the clause-body arrow }
      end
      else
        CurTok.Kind := tkMinus;
    end;
    '/': begin
      if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then
      begin
        Inc(SrcPos);
        CurTok.Kind := tkNeq;     { /= }
      end
      else
        CurTok.Kind := tkSlash;
    end;
    '=': begin
      if (SrcPos <= Length(Source)) and (Source[SrcPos] = '<') then
      begin
        Inc(SrcPos);
        CurTok.Kind := tkLe;      { =< (Erlang spells <= this way) }
      end
      else if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then
      begin
        Inc(SrcPos);
        CurTok.Kind := tkEq;      { == }
      end
      else
        CurTok.Kind := tkAssign;  { = (match/bind) }
    end;
    '<': CurTok.Kind := tkLt;
    '>': begin
      if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then
      begin
        Inc(SrcPos);
        CurTok.Kind := tkGe;
      end
      else
        CurTok.Kind := tkGt;
    end;
    else CurTok.Kind := tkIdent;  { unknown punctuation — parser reports it }
  end;
end;

procedure ELexAll;
var off, len, i: Integer; k: TTokenKind;
begin
  TokCount := 0; TokCharLen := 0;
  repeat
    ELexOne;
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
