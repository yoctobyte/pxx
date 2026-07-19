{ SPDX-License-Identifier: MPL-2.0 }
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
      if lower = 'import' then Result := tkUses;
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
  EnsureTokCapacity(TokCount + 1);
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
  Inc(TokCount); EnsureTokCapacity(TokCount+1);
end;

{ ===== f-string expansion =====

  Rewrites the SOURCE before lexing: f"a{x}b" becomes ("a" + str(x) + "b").
  A source-level rewrite, not a lexer mode, for one reason — the text inside a
  hole is ordinary Python source, and the only thing that can tokenise it
  correctly is the ordinary lexer. Anything else re-implements the expression
  grammar a second time, which is the exact duplication this frontend keeps
  paying for elsewhere.

  Line count is PRESERVED: the rewrite never adds or removes a newline, so
  every later line number is unaffected. A hole containing a newline is
  therefore refused rather than silently shifting the whole file.

  v1 covers a plain hole. A conversion or a format spec is a clean error
  naming the construct: both change what is PRINTED, so emitting str() for
  them would be quietly wrong OUTPUT rather than an honest missing feature. }

const
  QuoteCh = #39;   { a single quote, spelled by code point to keep this
                     source readable inside a Pascal string }

function PyFStrIsQuote(c: Char): Boolean;
begin
  Result := (c = '"') or (c = QuoteCh);
end;

procedure PyFStrFlush(var outS, lit: AnsiString; var wroteAny: Boolean);
begin
  if Length(lit) = 0 then Exit;
  if wroteAny then outS := outS + ' + ';
  outS := outS + '"' + lit + '"';
  lit := '';
  wroteAny := True;
end;

{ Turn the innermost still-open pystr_of( into pyrepr_of( — the hole's call
  was appended by this same pass, so the LAST occurrence is that hole's. Done
  by rewriting rather than by deciding up front because the conversion suffix
  (!r) appears only at the END of the hole, after the expression text has
  already been emitted. }
function PyFStrSwapLastCall(const outS: AnsiString;
                            const newCall: AnsiString): AnsiString;
var i, k: Integer;
begin
  Result := outS;
  for i := Length(outS) - 8 downto 1 do
    if Copy(outS, i, 9) = 'pystr_of(' then
    begin
      Result := Copy(outS, 1, i - 1) + newCall;
      for k := i + 9 to Length(outS) do AppendChar(Result, outS[k]);
      Exit;
    end;
end;

procedure PyExpandFStrings;
var
  outS, lit: AnsiString;
  i, n, depth, ln: Integer;
  q, c, hq: Char;
  inHole, wroteAny, sawTriple: Boolean;
begin
  n := Length(Source);
  outS := '';
  i := 1;
  { This pass runs BEFORE the lexer, so nothing else is counting lines yet and
    an Error here would report line 1 for a file of any size. }
  ln := 1;
  while i <= n do
  begin
    c := Source[i];
    { a comment runs to end of line, copied verbatim }
    if c = '#' then
    begin
      while (i <= n) and (Source[i] <> #10) do
      begin outS := outS + Source[i]; Inc(i); end;
      continue;
    end;
    { an ORDINARY string literal is copied verbatim, escapes and all, so a
      brace inside one is never mistaken for a hole }
    if PyFStrIsQuote(c) then
    begin
      q := c;
      sawTriple := (i + 2 <= n) and (Source[i + 1] = q) and (Source[i + 2] = q);
      if sawTriple then
      begin
        outS := outS + q + q + q;
        Inc(i, 3);
        while i <= n do
        begin
          if (Source[i] = q) and (i + 2 <= n) and (Source[i + 1] = q) and
             (Source[i + 2] = q) then
          begin
            outS := outS + q + q + q;
            Inc(i, 3);
            break;
          end;
          if Source[i] = #10 then Inc(ln);
          outS := outS + Source[i];
          Inc(i);
        end;
      end
      else
      begin
        outS := outS + q;
        Inc(i);
        while i <= n do
        begin
          if Source[i] = '\' then
          begin
            outS := outS + Source[i];
            Inc(i);
            if i <= n then begin outS := outS + Source[i]; Inc(i); end;
            continue;
          end;
          if Source[i] = q then begin outS := outS + q; Inc(i); break; end;
          if Source[i] = #10 then break;
          outS := outS + Source[i];
          Inc(i);
        end;
      end;
      continue;
    end;
    { f"..." — the prefix must not be the tail of a longer identifier }
    if ((c = 'f') or (c = 'F')) and (i + 1 <= n) and PyFStrIsQuote(Source[i + 1]) and
       ((i = 1) or (not (Source[i - 1] in ['A'..'Z', 'a'..'z', '0'..'9', '_']))) then
    begin
      q := Source[i + 1];
      if (i + 3 <= n) and (Source[i + 2] = q) and (Source[i + 3] = q) then
        ErrorAt(ln, 'Nil Python: a triple-quoted f-string is not supported yet');
      i := i + 2;
      outS := outS + '(';
      lit := '';
      wroteAny := False;
      inHole := False;
      depth := 0;
      while i <= n do
      begin
        c := Source[i];
        if not inHole then
        begin
          if c = q then begin Inc(i); break; end;
          if c = #10 then ErrorAt(ln, 'Nil Python: an unterminated f-string');
          if c = '\' then
          begin
            lit := lit + c;
            Inc(i);
            if i <= n then begin lit := lit + Source[i]; Inc(i); end;
            continue;
          end;
          if (c = '{') and (i + 1 <= n) and (Source[i + 1] = '{') then
          begin lit := lit + '{'; Inc(i, 2); continue; end;
          if (c = '}') and (i + 1 <= n) and (Source[i + 1] = '}') then
          begin lit := lit + '}'; Inc(i, 2); continue; end;
          if c = '{' then
          begin
            PyFStrFlush(outS, lit, wroteAny);
            if wroteAny then outS := outS + ' + ';
            outS := outS + 'pystr_of(';
            wroteAny := True;
            inHole := True;
            depth := 0;
            Inc(i);
            continue;
          end;
          lit := lit + c;
          Inc(i);
          continue;
        end;
        { inside a hole }
        if PyFStrIsQuote(c) then
        begin
          hq := c;
          outS := outS + c;
          Inc(i);
          while (i <= n) and (Source[i] <> hq) do
          begin outS := outS + Source[i]; Inc(i); end;
          if i <= n then begin outS := outS + Source[i]; Inc(i); end;
          continue;
        end;
        if (c = '(') or (c = '[') or (c = '{') then Inc(depth)
        else if (c = ')') or (c = ']') or (c = '}') then
        begin
          if (c = '}') and (depth = 0) then
          begin
            outS := outS + ')';
            inHole := False;
            Inc(i);
            continue;
          end;
          Dec(depth);
        end
        else if (depth = 0) and (c = '!') and (i + 1 <= n) and
                ((Source[i + 1] = 'r') or (Source[i + 1] = 's')) and
                (i + 2 <= n) and (Source[i + 2] = '}') then
        begin
          { !r / !s. !s is str(), which is what the hole already emits; !r has
            to quote a STRING and leave everything else alone, so it swaps the
            call rather than wrapping it — pyrepr_of carries the same per-type
            overload set as pystr_of. }
          if Source[i + 1] = 'r' then
            outS := PyFStrSwapLastCall(outS, 'pyrepr_of(');
          outS := outS + ')';
          inHole := False;
          Inc(i, 3);
          continue;
        end
        else if (depth = 0) and (c = '!') then
          ErrorAt(ln, 'Nil Python: only the !r and !s f-string conversions are supported')
        else if (depth = 0) and (c = ':') then
        begin
          { A format spec. Captured verbatim and passed to the runtime as a
            STRING rather than compiled here: the spec mini-language belongs
            with the formatting code, and keeping it in one place is what
            stops the parser and the formatter from disagreeing about what
            "05x" means. pyformat_of rejects anything it does not implement,
            at run time, by name. }
          outS := PyFStrSwapLastCall(outS, 'pyformat_of(');
          outS := outS + ', "';
          Inc(i);
          while (i <= n) and (Source[i] <> '}') do
          begin
            if (Source[i] = #10) or (Source[i] = '"') then
              ErrorAt(ln, 'Nil Python: an f-string format spec must be a plain literal');
            outS := outS + Source[i];
            Inc(i);
          end;
          if i > n then ErrorAt(ln, 'Nil Python: an unterminated f-string hole');
          outS := outS + '")';
          inHole := False;
          Inc(i);
          continue;
        end;
        if c = #10 then
          ErrorAt(ln, 'Nil Python: a newline inside an f-string hole is not supported');
        outS := outS + c;
        Inc(i);
      end;
      if inHole then ErrorAt(ln, 'Nil Python: an unterminated f-string hole');
      PyFStrFlush(outS, lit, wroteAny);
      if not wroteAny then outS := outS + '""';
      outS := outS + ')';
      continue;
    end;
    if c = #10 then Inc(ln);
    outS := outS + c;
    Inc(i);
  end;
  Source := outS;
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
  c, quoteChar, c2: Char;
  s: AnsiString;
  n: Int64;
  floatStart, fpos: Integer;
  k: TTokenKind;
  numBase, digit, startLine: Integer;
  hasDigit, isTriple: Boolean;
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
        { Hex / octal / binary prefixes (0x / 0o / 0b), Python 3 style.
          Underscore digit separators are permitted and ignored. }
        if (c = '0') and (P < Length(Source)) and
           (Source[P+1] in ['x','X','o','O','b','B']) then
        begin
          case Source[P+1] of
            'x', 'X': numBase := 16;
            'o', 'O': numBase := 8;
            else numBase := 2;
          end;
          Inc(P, 2);
          hasDigit := False;
          while P <= Length(Source) do
          begin
            c2 := Source[P];
            if c2 = '_' then begin Inc(P); continue; end;
            if c2 in ['0'..'9'] then digit := Ord(c2) - 48
            else if c2 in ['a'..'f'] then digit := Ord(c2) - 87
            else if c2 in ['A'..'F'] then digit := Ord(c2) - 55
            else break;
            if digit >= numBase then break;
            n := n * numBase + digit;
            hasDigit := True;
            Inc(P);
          end;
          if not hasDigit then
          begin
            CurTok.Line := SrcLine;
            Error('invalid numeric literal');
          end;
          PyEmitToken(tkInteger, n, SrcLine, '');
          continue;
        end;
        while (P <= Length(Source)) and (Source[P] in ['0'..'9','_']) do
        begin
          if Source[P] <> '_' then
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
          while fpos < P do
          begin
            if Source[fpos] <> '_' then AppendChar(s, Source[fpos]);
            Inc(fpos);
          end;
          PyEmitToken(tkFloat, StrToDoubleBits(s), SrcLine, '');
        end
        else
        begin
          PyEmitToken(tkInteger, n, SrcLine, '');
        end;
        continue;
      end;

      { String Literals — single- and triple-quoted. Newlines inside a body
        (triple-quoted, or a stray one) must bump SrcLine or every later
        error/line number drifts. Token carries the START line. }
      if (c = '"') or (c = '''') then
      begin
        quoteChar := c;
        startLine := SrcLine;
        isTriple := (P + 2 <= Length(Source)) and
                    (Source[P+1] = quoteChar) and (Source[P+2] = quoteChar);
        if isTriple then Inc(P, 3) else Inc(P);
        s := '';
        while P <= Length(Source) do
        begin
          if Source[P] = quoteChar then
          begin
            if not isTriple then begin Inc(P); break; end;
            if (P + 2 <= Length(Source)) and
               (Source[P+1] = quoteChar) and (Source[P+2] = quoteChar) then
            begin
              Inc(P, 3);
              break;
            end;
            AppendChar(s, Source[P]);
            Inc(P);
          end
          else if Source[P] = '\' then
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
            if Source[P] = #10 then Inc(SrcLine);
            AppendChar(s, Source[P]);
            Inc(P);
          end;
        end;
        PyEmitToken(tkString, 0, startLine, s);
        continue;
      end;

      { Operators and Punctuation }
      Inc(P);
      case c of
        '+': begin
          if (P <= Length(Source)) and (Source[P] = '=') then
          begin Inc(P); PyEmitToken(tkPlusEq, 0, SrcLine, ''); end
          else PyEmitToken(tkPlus, 0, SrcLine, '');
        end;
        '-': begin
          if (P <= Length(Source)) and (Source[P] = '=') then
          begin Inc(P); PyEmitToken(tkMinusEq, 0, SrcLine, ''); end
          else PyEmitToken(tkMinus, 0, SrcLine, '');
        end;
        '*': begin
          if (P <= Length(Source)) and (Source[P] = '=') then
          begin Inc(P); PyEmitToken(tkStarEq, 0, SrcLine, ''); end
          else PyEmitToken(tkStar, 0, SrcLine, '');
        end;
        '/': begin
          if (P <= Length(Source)) and (Source[P] = '/') then
          begin
            Inc(P);
            if (P <= Length(Source)) and (Source[P] = '=') then
            begin Inc(P); PyEmitToken(tkSlashEq, 0, SrcLine, ''); end
            else PyEmitToken(tkDiv, 0, SrcLine, '');
          end
          else
            PyEmitToken(tkSlash, 0, SrcLine, '');
          end;
        '%': begin
          if (P <= Length(Source)) and (Source[P] = '=') then
          begin Inc(P); PyEmitToken(tkModEq, 0, SrcLine, ''); end
          else PyEmitToken(tkMod, 0, SrcLine, '');
        end;
        '&': begin
          if (P <= Length(Source)) and (Source[P] = '=') then
          begin Inc(P); PyEmitToken(tkAmpEq, 0, SrcLine, ''); end
          else PyEmitToken(tkAmp, 0, SrcLine, '');
        end;
        '|': begin
          if (P <= Length(Source)) and (Source[P] = '=') then
          begin Inc(P); PyEmitToken(tkPipeEq, 0, SrcLine, ''); end
          else PyEmitToken(tkPipe, 0, SrcLine, '');
        end;
        '^': begin
          if (P <= Length(Source)) and (Source[P] = '=') then
          begin Inc(P); PyEmitToken(tkXorEq, 0, SrcLine, ''); end
          else PyEmitToken(tkXor, 0, SrcLine, '');
        end;
        { `~` reuses tkLogNot as a shape token (C's `!`); NilPy-side meaning
          is bitwise not. tkNot stays the `not` keyword. }
        '~': PyEmitToken(tkLogNot, 0, SrcLine, '');
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
        { set/dict literal braces: distinct kinds (tkBegin/tkEnd reused as
          shape tokens) so the parser can desugar them; still counted for
          implicit line continuation }
        '{': begin PyEmitToken(tkBegin, 0, SrcLine, ''); Inc(parenDepth); end;
        '}': begin
          PyEmitToken(tkEnd, 0, SrcLine, '');
          Dec(parenDepth);
          if parenDepth < 0 then
          begin
            CurTok.Line := SrcLine;
            Error('unmatched closing brace');
          end;
        end;
        '@': PyEmitToken(tkAt, 0, SrcLine, '');
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
          else if (P <= Length(Source)) and (Source[P] = '<') then
          begin
            Inc(P);
            if (P <= Length(Source)) and (Source[P] = '=') then
            begin Inc(P); PyEmitToken(tkShlEq, 0, SrcLine, ''); end
            else PyEmitToken(tkShl, 0, SrcLine, '');
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
          else if (P <= Length(Source)) and (Source[P] = '>') then
          begin
            Inc(P);
            if (P <= Length(Source)) and (Source[P] = '=') then
            begin Inc(P); PyEmitToken(tkShrEq, 0, SrcLine, ''); end
            else PyEmitToken(tkShr, 0, SrcLine, '');
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
