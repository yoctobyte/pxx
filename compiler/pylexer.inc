{ SPDX-License-Identifier: MPL-2.0 }
{ ===== Nil Python Lexer ===== }

function PyKeyword(const s: AnsiString): TTokenKind;
{ Python keywords are case-SENSITIVE and all-lowercase (except the three
  capitalised literals True/False/None), so the comparison below is EXACT.
  It used to case-fold first, which made `For`, `Not`, `If`, `Print` lex as
  keywords — they are ordinary identifiers in Python, and a program that binds
  one failed to parse at all (bug-nilpy-identifiers-are-case-insensitive). }
var
  lower: AnsiString;
begin
  lower := s;

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
      if lower = 'True' then Result := tkTrue;
      if lower = 'None' then Result := tkNil;
    end;
    5: begin
      if lower = 'while' then Result := tkWhile;
      if lower = 'False' then Result := tkFalse;
      { `print` stays an ORDINARY IDENTIFIER. It used to lex as Pascal's
        tkwriteln, which cost the one thing a keyword costs: `def print(x)` was
        refused with "expected function name", because by the time the parser
        saw the name it was not a name. CPython lets a def shadow print like
        any other builtin, and PyParsePrint — NilPy's OWN print statement,
        which has existed all along — is reached by name from pyparser, so the
        shared token bought nothing and hid a divergence.
        print() is not writeln(): different defaults, different separator
        rules, different argument model. Duplicate, do not over-abstract
        (feedback_duplicate_helpers_per_language_shared_ast). }
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
  { A tkInteger carries text only when the literal is wider than Int64: the
    exact decimal digits, for the promotable-int lowering (the Pascal lexer's
    CurTok.SVal convention, ferried through the NilPy token pool). }
  if (k = tkIdent) or (k = tkString) or ((k = tkInteger) and (sval <> '')) then
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

{ `1j` / `2.5J` — Python's imaginary literal. CPython has no integer complex,
  so the imaginary PART is a double whichever way the digits were written.

  Consumes the suffix and emits the token sequence for
  `pycomplex_make(0.0, <value>)`, so the literal needs no new token kind, no
  parser arm and no constant folding of its own -- it IS a call from the moment
  it is lexed, which is also what makes `1j` usable in every expression
  position for free. The RADIX path deliberately does not call this: CPython
  rejects `0x1j`. bug-nilpy-no-complex-number-type }
function PyImaginarySuffix(var P: Integer): Boolean;
begin
  Result := (P <= Length(Source)) and ((Source[P] = 'j') or (Source[P] = 'J'));
  { A suffix must END the literal -- `1jj` and `1john` are not imaginaries. }
  if Result and (P < Length(Source)) and
     (Source[P+1] in ['a'..'z','A'..'Z','0'..'9','_']) then
    Result := False;
  if Result then Inc(P);
end;

procedure PyEmitImaginary(bits: Int64; line: Integer);
begin
  PyEmitToken(tkIdent, 0, line, 'pycomplex_make');
  PyEmitToken(tkLParen, 0, line, '');
  PyEmitToken(tkFloat, StrToDoubleBits('0.0'), line, '');
  PyEmitToken(tkComma, 0, line, '');
  PyEmitToken(tkFloat, bits, line, '');
  PyEmitToken(tkRParen, 0, line, '');
end;

{ dec := dec*base + digit, on a decimal digit string (`''` = 0). Carries the
  exact value of a radix literal (0x/0o/0b) wider than Int64: the promotable-int
  runtime takes DECIMAL text (PXXPromoFromStr), so the base conversion happens
  here where the digits stream by. Literals are short; the quadratic string
  arithmetic is irrelevant. }
procedure PyDecMulAdd(var dec: AnsiString; base, digit: Integer);
var i, carry, v: Integer;
begin
  carry := digit;
  for i := Length(dec) downto 1 do
  begin
    v := (Ord(dec[i]) - 48) * base + carry;
    dec[i] := Chr(48 + v mod 10);
    carry := v div 10;
  end;
  while carry > 0 do
  begin
    dec := Chr(48 + carry mod 10) + dec;
    carry := carry div 10;
  end;
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

{ The expander copies the WHOLE source, so its output has to be built with a
  growable buffer rather than by repeated concatenation: appending one
  character at a time is quadratic in file size, and it showed — 30 KB took a
  second and uforth.py's 150 KB took 107. Capacity doubles; PyFsDone trims. }
var
  PyFsOut: AnsiString;
  PyFsLen: Integer;
  PyFsCap: Integer;

procedure PyFsReset(hint: Integer);
begin
  PyFsCap := hint + 64;
  SetLength(PyFsOut, PyFsCap);
  PyFsLen := 0;
end;

procedure PyFsPut(const t: AnsiString);
var k, n: Integer;
begin
  n := Length(t);
  if n = 0 then Exit;
  while PyFsLen + n > PyFsCap do
  begin
    PyFsCap := PyFsCap * 2;
    SetLength(PyFsOut, PyFsCap);
  end;
  for k := 1 to n do PyFsOut[PyFsLen + k] := t[k];
  PyFsLen := PyFsLen + n;
end;

procedure PyFsPutCh(c: Char);
begin
  if PyFsLen + 1 > PyFsCap then
  begin
    PyFsCap := PyFsCap * 2;
    SetLength(PyFsOut, PyFsCap);
  end;
  PyFsOut[PyFsLen + 1] := c;
  PyFsLen := PyFsLen + 1;
end;

function PyFsDone: AnsiString;
begin
  SetLength(PyFsOut, PyFsLen);
  Result := PyFsOut;
  PyFsOut := '';
  PyFsCap := 0;
  PyFsLen := 0;
end;

const
  QuoteCh = #39;   { a single quote, spelled by code point to keep this
                     source readable inside a Pascal string }

function PyFStrIsQuote(c: Char): Boolean;
begin
  Result := (c = '"') or (c = QuoteCh);
end;

procedure PyFStrFlush(var lit: AnsiString; var wroteAny: Boolean);
begin
  if Length(lit) = 0 then Exit;
  if wroteAny then PyFsPut(' + ');
  PyFsPutCh('"');
  PyFsPut(lit);
  PyFsPutCh('"');
  lit := '';
  wroteAny := True;
end;

{ Turn the innermost still-open pystr_of( into pyrepr_of( — the hole's call
  was appended by this same pass, so the LAST occurrence is that hole's. Done
  by rewriting rather than by deciding up front because the conversion suffix
  (!r) appears only at the END of the hole, after the expression text has
  already been emitted. }
{ Rewrite the innermost still-open pystr_of( in the buffer to newCall. The
  hole's call was appended by this same pass, so the LAST occurrence is that
  hole's, and both names are 9 or 10 characters — the tail is shifted rather
  than the buffer rebuilt. }
{ Does the emitted text hold `lit` starting at i? }
function PyFsHasAt(i: Integer; const lit: AnsiString): Boolean;
var k: Integer;
begin
  Result := False;
  if i + Length(lit) - 1 > PyFsLen then Exit;
  for k := 1 to Length(lit) do
    if PyFsOut[i + k - 1] <> lit[k] then Exit;
  Result := True;
end;

{ Replace the most recently emitted hole call with `newCall`.

  It must recognise BOTH openers, not just `pystr_of(`: a hole normally starts
  as pystr_of, but the self-documenting `expr=` form starts as `pyrepr_of`
  because that form defaults to repr. Searching only for the pystr_of spelling
  meant a `:` format spec after `=` found nothing to swap and the spec was
  handed to pyrepr_of as a SECOND ARGUMENT — "no overload of pyrepr_of matches
  (Double, ShortString)". The two spellings are different LENGTHS, so the shift
  has to be driven by the matched one rather than by a constant 9. }
procedure PyFStrSwapLastCall(const newCall: AnsiString);
var i, k, delta, oldLen, oldCallLen: Integer;
begin
  for i := PyFsLen downto 1 do
  begin
    oldCallLen := 0;
    if PyFsHasAt(i, 'pystr_of(') then oldCallLen := 9
    else if PyFsHasAt(i, 'pyrepr_of(') then oldCallLen := 10;
    if oldCallLen > 0 then
    begin
      delta := Length(newCall) - oldCallLen;
      oldLen := PyFsLen;
      if delta > 0 then
      begin
        for k := 1 to delta do PyFsPutCh(' ');
        for k := oldLen downto i + oldCallLen do PyFsOut[k + delta] := PyFsOut[k];
      end
      else if delta < 0 then
      begin
        for k := i + oldCallLen to oldLen do PyFsOut[k + delta] := PyFsOut[k];
        PyFsLen := oldLen + delta;
      end;
      for k := 1 to Length(newCall) do PyFsOut[i + k - 1] := newCall[k];
      Exit;
    end;
  end;
end;

{ Python concatenates adjacent string/f-string literals: `"a" "b"` and, across
  lines inside parentheses, `f"a"\n f"b"`. After a literal is emitted, peek past
  the whitespace that follows; if another string literal begins (optionally
  prefixed f/r/b), splice in a ` + `. Newlines only count as "still adjacent"
  inside brackets — at statement level a newline separates a docstring from the
  next string, so pdepth guards that. `src`/`ln` are threaded so line counting
  and the comment skip stay correct. Returns the index of the first char NOT
  consumed (the whitespace is left for the main loop to copy/count). }
function PyFsAdjacentStringAt(src: AnsiString; from, srcLen, pdepth: Integer): Boolean;
var j: Integer; ch: Char;
begin
  Result := False;
  j := from;
  while j <= srcLen do
  begin
    ch := src[j];
    if (ch = ' ') or (ch = #9) or (ch = #13) then Inc(j)
    else if ch = '\' then
    begin
      { A BACKSLASH CONTINUATION keeps the next line adjacent, exactly as an
        open bracket does — `"x" \` then `"y"` is one string in Python. The
        pdepth test below is the bracket half of the same rule; without this
        arm the continuation form joined nothing and `"x" \ / "y"` evaluated to
        just "x", silently losing the second half. }
      Inc(j);
      while (j <= srcLen) and ((src[j] = ' ') or (src[j] = #9) or (src[j] = #13)) do
        Inc(j);
      if (j > srcLen) or (src[j] <> #10) then Exit;
      Inc(j);
    end
    else if ch = #10 then
    begin
      if pdepth <= 0 then Exit;   { statement-level newline: not adjacent }
      Inc(j);
    end
    else break;
  end;
  if j > srcLen then Exit;
  ch := src[j];
  { an optional string prefix letter directly before the quote }
  if (ch = 'f') or (ch = 'F') or (ch = 'r') or (ch = 'R') or
     (ch = 'b') or (ch = 'B') then
  begin
    if (j + 1 <= srcLen) and PyFStrIsQuote(src[j + 1]) then Result := True;
  end
  else if PyFStrIsQuote(ch) then Result := True;
end;

{ Python's self-documenting f-string hole — the `expr=` form, which prints the
  EXPRESSION TEXT, an `=`, and then the value: f"n=" with n in the hole gives
  `n=42`. (Braces are spelled out in this comment rather than written, because
  Pascal comments do not nest and a literal closing brace would end it early —
  which is exactly how this function first failed to compile.)

  Returns the index of the `=` that ends the expression, or 0 when this hole is
  not that form. The whole point is that it must be answered BEFORE the hole is
  emitted: the expression text becomes LITERAL text, and the literal is flushed
  ahead of the call that produces the value, so there is no going back once the
  hole has started.

  The `=` must be the last thing in the hole — before the closing brace, a `:`
  format spec or a `!r` conversion — and must not be part of a comparison:
  `a == b`, `a != b`, `x <= 1` and the augmented spellings all have to keep
  meaning what they say. Quotes and nesting are skipped the same way the hole
  scanner skips them, so `d["a=b"]` and `f(a=1)` are not mistaken for it (a
  keyword argument is inside parentheses, hence the depth test). }
function PyFStrSelfDocEq(const src: AnsiString; st, n: Integer): Integer;
var j, d: Integer; qq: Char;
begin
  Result := 0;
  d := 0;
  j := st;
  while j <= n do
  begin
    if PyFStrIsQuote(src[j]) then
    begin
      qq := src[j];
      Inc(j);
      while (j <= n) and (src[j] <> qq) do
      begin
        if src[j] = '\' then Inc(j);
        Inc(j);
      end;
      if j > n then Exit;
      Inc(j);
      continue;
    end;
    if src[j] = #10 then Exit;
    if (src[j] = '(') or (src[j] = '[') or (src[j] = '{') then Inc(d)
    else if (src[j] = ')') or (src[j] = ']') or (src[j] = '}') then
    begin
      if (src[j] = '}') and (d = 0) then Exit;   { hole ended without one }
      Dec(d);
    end
    else if (d = 0) and (src[j] = '=') then
    begin
      if (j + 1 <= n) and (src[j + 1] = '=') then begin Inc(j, 2); continue; end;
      if (j > st) and
         ((src[j - 1] = '=') or (src[j - 1] = '!') or (src[j - 1] = '<') or
          (src[j - 1] = '>') or (src[j - 1] = '+') or (src[j - 1] = '-') or
          (src[j - 1] = '*') or (src[j - 1] = '/') or (src[j - 1] = '%') or
          (src[j - 1] = '&') or (src[j - 1] = '|') or (src[j - 1] = '^')) then
      begin Inc(j); continue; end;
      { trailing spaces are part of the printed text: f"{n = }" gives `n = 42` }
      d := j + 1;
      while (d <= n) and (src[d] = ' ') do Inc(d);
      if (d <= n) and ((src[d] = '}') or (src[d] = ':') or (src[d] = '!')) then
      begin
        Result := j;
        Exit;
      end;
      Exit;
    end;
    Inc(j);
  end;
end;

procedure PyExpandFStrings;
var
  lit: AnsiString;
  i, n, depth, ln, pdepth: Integer;
  sdEq, sdK: Integer;      { `{expr=}`: index of the `=`, and a copy cursor }
  q, c, hq: Char;
  inHole, wroteAny, sawTriple: Boolean;
begin
  pdepth := 0;
  n := Length(Source);
  PyFsReset(n);
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
      begin PyFsPutCh(Source[i]); Inc(i); end;
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
        PyFsPutCh(q); PyFsPutCh(q); PyFsPutCh(q);
        Inc(i, 3);
        while i <= n do
        begin
          if (Source[i] = q) and (i + 2 <= n) and (Source[i + 1] = q) and
             (Source[i + 2] = q) then
          begin
            PyFsPutCh(q); PyFsPutCh(q); PyFsPutCh(q);
            Inc(i, 3);
            break;
          end;
          if Source[i] = #10 then Inc(ln);
          PyFsPutCh(Source[i]);
          Inc(i);
        end;
      end
      else
      begin
        PyFsPutCh(q);
        Inc(i);
        while i <= n do
        begin
          if Source[i] = '\' then
          begin
            PyFsPutCh(Source[i]);
            Inc(i);
            if i <= n then begin PyFsPutCh(Source[i]); Inc(i); end;
            continue;
          end;
          if Source[i] = q then begin PyFsPutCh(q); Inc(i); break; end;
          if Source[i] = #10 then break;
          PyFsPutCh(Source[i]);
          Inc(i);
        end;
      end;
      { adjacent literal after this plain string -> implicit concatenation, so
        `"a" "b"` and a plain string followed by an f-string both join }
      if PyFsAdjacentStringAt(Source, i, n, pdepth) then PyFsPut(' + ');
      continue;
    end;
    { b"..." / b'...' — a BYTES literal, rewritten to bytes("...") so it lands
      on the pylib bytes(str) overload. Same not-tail-of-an-ident guard as f. }
    if ((c = 'b') or (c = 'B')) and (i + 1 <= n) and PyFStrIsQuote(Source[i + 1]) and
       ((i = 1) or (not (Source[i - 1] in ['A'..'Z', 'a'..'z', '0'..'9', '_']))) then
    begin
      q := Source[i + 1];
      PyFsPut('bytes(');
      PyFsPutCh(q);
      Inc(i, 2);
      while i <= n do
      begin
        if Source[i] = '\' then
        begin
          PyFsPutCh(Source[i]); Inc(i);
          if i <= n then begin PyFsPutCh(Source[i]); Inc(i); end;
          continue;
        end;
        if Source[i] = q then begin PyFsPutCh(q); Inc(i); break; end;
        if Source[i] = #10 then break;
        PyFsPutCh(Source[i]); Inc(i);
      end;
      PyFsPutCh(')');
      if PyFsAdjacentStringAt(Source, i, n, pdepth) then PyFsPut(' + ');
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
      PyFsPutCh('(');
      lit := '';
      wroteAny := False;
      inHole := False;
      depth := 0;
      sdEq := 0;
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
            { The self-documenting `expr=` form is decided HERE, before
              anything is emitted: the expression TEXT joins the literal, and
              the literal is flushed ahead of the call producing the value. }
            sdEq := PyFStrSelfDocEq(Source, i + 1, n);
            if sdEq > 0 then
            begin
              for sdK := i + 1 to sdEq do lit := lit + Source[sdK];
              sdK := sdEq + 1;
              while (sdK <= n) and (Source[sdK] = ' ') do
              begin lit := lit + ' '; Inc(sdK); end;
            end;
            PyFStrFlush(lit, wroteAny);
            if wroteAny then PyFsPut(' + ');
            { the `=` form defaults to REPR, not str — it yields s='hi', not
              s=hi. An explicit !s or a `:` spec still overrides it below,
              because both swap the call rather than wrapping it. }
            if sdEq > 0 then PyFsPut('pyrepr_of(') else PyFsPut('pystr_of(');
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
          PyFsPutCh(c);
          Inc(i);
          while (i <= n) and (Source[i] <> hq) do
          begin
            { an ESCAPED quote does not close the string — without this,
              f"...{d['a\'b']}..." ended the hole's string early and the rest
              of the expression was copied as literal text }
            if Source[i] = '\' then
            begin
              PyFsPutCh(Source[i]);
              Inc(i);
              if i > n then Break;
            end;
            PyFsPutCh(Source[i]);
            Inc(i);
          end;
          if i <= n then begin PyFsPutCh(Source[i]); Inc(i); end;
          continue;
        end;
        { the self-documenting `=` is text, not part of the expression — skip
          it and any spaces after it. Matched by POSITION, so the guard that
          decided it (comparison operators, quotes, nesting) lives in exactly
          one place and cannot drift. }
        if (sdEq > 0) and (i = sdEq) then
        begin
          Inc(i);
          while (i <= n) and (Source[i] = ' ') do Inc(i);
          sdEq := 0;
          continue;
        end;
        if (c = '(') or (c = '[') or (c = '{') then Inc(depth)
        else if (c = ')') or (c = ']') or (c = '}') then
        begin
          if (c = '}') and (depth = 0) then
          begin
            PyFsPutCh(')');
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
            PyFStrSwapLastCall('pyrepr_of(')
          else
            { !s used to be a no-op, because the hole was always pystr_of
              already. The self-documenting `expr=` form opens as pyrepr_of, so
              an explicit !s now has to UNDO that default rather than assume it.
              This is what makes `s=` with !s print s=hi, not s='hi'. }
            PyFStrSwapLastCall('pystr_of(');
          PyFsPutCh(')');
          inHole := False;
          Inc(i, 3);
          continue;
        end
        else if (depth = 0) and (c = '!') and (i + 1 <= n) and (Source[i + 1] = '=') then
        begin
          { `!=` is the INEQUALITY OPERATOR, not a conversion. Every f-string
            containing one failed to compile — `f"...{a != b}..."` — because the
            conversion arm claims any `!` at depth 0. The `!r`/`!s` arm above
            requires the hole to END right after, so reaching here with a `=`
            next means an operator, unambiguously.
            bug-nilpy-fstring-hole-cannot-contain-an-inequality }
          PyFsPutCh(c);
          PyFsPutCh('=');
          Inc(i, 2);
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
          PyFStrSwapLastCall('pyformat_of(');
          PyFsPut(', "');
          Inc(i);
          while (i <= n) and (Source[i] <> '}') do
          begin
            if (Source[i] = #10) or (Source[i] = '"') then
              ErrorAt(ln, 'Nil Python: an f-string format spec must be a plain literal');
            { A NESTED replacement field inside the spec — a computed
              precision, which is how a report makes its decimal places
              configurable. The spec is still a string handed to the formatter,
              so the nested hole becomes a CONCATENATION rather than a second
              grammar: a spec of dot, open-brace, n, close-brace, f emits
              '"." + pystr_of(n) + "f"'. Taken literally before this, the
              formatter met a spec ending mid-field and said so at run time.
              (The shape is spelled out in words here on purpose: a brace
              comment ENDS at the first closing brace it contains, which is how
              this very block first failed to compile.)
              bug-nilpy-builtin-surface-gaps-found-by-the-2026-08-12-sweep item 3 }
            if Source[i] = '{' then
            begin
              PyFsPut('" + pystr_of(');
              Inc(i);
              while (i <= n) and (Source[i] <> '}') do
              begin
                if (Source[i] = #10) or (Source[i] = '"') then
                  ErrorAt(ln, 'Nil Python: a nested f-string spec field must be '
                            + 'a plain expression');
                PyFsPutCh(Source[i]);
                Inc(i);
              end;
              if i > n then ErrorAt(ln, 'Nil Python: an unterminated f-string hole');
              PyFsPut(') + "');
              Inc(i);        { step past the nested field's closing brace }
            end
            else
            begin
              PyFsPutCh(Source[i]);
              Inc(i);
            end;
          end;
          if i > n then ErrorAt(ln, 'Nil Python: an unterminated f-string hole');
          PyFsPut('")');
          inHole := False;
          Inc(i);
          continue;
        end;
        if c = #10 then
          ErrorAt(ln, 'Nil Python: a newline inside an f-string hole is not supported');
        PyFsPutCh(c);
        Inc(i);
      end;
      if inHole then ErrorAt(ln, 'Nil Python: an unterminated f-string hole');
      PyFStrFlush(lit, wroteAny);
      if not wroteAny then PyFsPut('""');
      PyFsPutCh(')');
      { adjacent literal after this f-string -> implicit concatenation }
      if PyFsAdjacentStringAt(Source, i, n, pdepth) then PyFsPut(' + ');
      continue;
    end;
    if c = #10 then Inc(ln);
    { Braces count too: a dict/set display continues a logical line exactly as
      parentheses and brackets do, so a string literal wrapped across lines
      inside one is still ADJACENT. Without `{`/`}` here,
      `{"k": "aa "\n      "bb"}` spliced nothing and the parser met the second
      literal where it wanted the closing brace — a compile error, and the
      idiom html5lib/constants.py is written in. }
    if (c = '(') or (c = '[') or (c = '{') then Inc(pdepth)
    else if (c = ')') or (c = ']') or (c = '}') then begin if pdepth > 0 then Dec(pdepth); end;
    PyFsPutCh(c);
    Inc(i);
  end;
  Source := PyFsDone;
end;

function PyTrailingDotFloat(P: Integer): Boolean;
{ At a '.' that ends a digit run: does the dot belong to the number? True when
  it terminates the literal (`5.`, `5.)`, `5. + 1`) or introduces an exponent
  (`5.e3`); false for `5.real`, which stays an integer and a selector the way
  it does today. bug-nilpy-bare-dot-float-literals-do-not-lex }
begin
  PyTrailingDotFloat := False;
  if (P > Length(Source)) or (Source[P] <> '.') then Exit;
  if P >= Length(Source) then begin PyTrailingDotFloat := True; Exit; end;
  if (Source[P + 1] = 'e') or (Source[P + 1] = 'E') then
  begin
    PyTrailingDotFloat := ((P + 2 <= Length(Source)) and
                           (Source[P + 2] in ['0'..'9'])) or
                          ((P + 3 <= Length(Source)) and
                           ((Source[P + 2] = '+') or (Source[P + 2] = '-')) and
                           (Source[P + 3] in ['0'..'9']));
    Exit;
  end;
  PyTrailingDotFloat := not (Source[P + 1] in ['.', 'a'..'z', 'A'..'Z', '_', '0'..'9']);
end;

procedure PyLexAll(SupportLineNumbers: Boolean);
var
  P: Integer;
  IndentStack: array[0..1024] of Integer;
  IndentStackTop: Integer;
  parenDepth: Integer;
  { `def f(x): return x + 1` — Python's one-line suite. Rather than teach the
    PARSER a second body shape, the lexer normalises it here into the canonical
    NEWLINE INDENT ... NEWLINE DEDENT the multi-line form already produces. That
    matters because a def body is read by several TOKEN-LEVEL scanners as well
    as by the parser (PyRegisterDefShells, PyCollectModuleLocalsAST,
    PyScanDefGlobals — all of which hunt for the body's tkIndent), and every one
    of them would otherwise need the second shape too. Getting one of them wrong
    is silent: the scan finds a different region and the def is typed from it.

    Restricted to `def` and `class`. `if c: break` and `while n < 3: n += 1`
    already work through PyParseSuite's own inline branch, and routing them
    through a synthetic block instead would change paths that are not broken.

    The IndentStack is deliberately untouched: the INDENT/DEDENT pair is emitted
    and closed within one physical line, so the next line's real indentation is
    measured against exactly the stack it would have seen. }
  lineIsDefClass: Boolean;   { this logical line opened with `def` or `class` }
  lineSawColon: Boolean;     { ...and its depth-0 `:` has been passed }
  inlineSuite: Boolean;      { ...and an INDENT was synthesised, so a DEDENT is owed }
  peekP: Integer;
  { where THIS lex started writing. Not always 0: PyLexAppend leaves the stream
    in place and appends a `.py` module after it, so "no token emitted yet, hence
    a line start" has to be asked about this invocation, not about the stream. }
  streamBase: Integer;
  HasSpaceIndent: Boolean;
  HasTabIndent: Boolean;
  IndentWidth: Integer;
  IsBlankOrComment: Boolean;
  IsLogicalLine: Boolean;
  contLine, wasCont: Boolean;   { backslash line continuation }
  c, quoteChar, c2: Char;
  s: AnsiString;
  n: Int64;
  floatStart, fpos: Integer;
  k: TTokenKind;
  numBase, digit, startLine: Integer;
  hasDigit, isTriple, rawStr: Boolean;
  decText: AnsiString;   { the literal's exact decimal digits, for the over-Int64 case }
begin
  if not PyLexAppending then
  begin
    TokCount := 0;
    TokCharLen := 0;
  end;
  streamBase := TokCount;
  P := 1;
  SrcLine := 1;

  { Skip a leading UTF-8 BOM. CPython accepts one and ignores it, and .py files
    written on Windows routinely carry it; without this the first token is the
    BOM's first byte and the file dies at "unexpected character" on line 1. }
  if (Length(Source) >= 3) and (Source[1] = #$EF) and (Source[2] = #$BB) and
     (Source[3] = #$BF) then
    P := 4;

  IndentStack[0] := 0;
  IndentStackTop := 0;
  parenDepth := 0;
  contLine := False;
  lineIsDefClass := False;
  lineSawColon := False;
  inlineSuite := False;
  HasSpaceIndent := False;
  HasTabIndent := False;

  while P <= Length(Source) do
  begin
    { A backslash-continued line is a CONTINUATION of the previous one, so it
      has no indentation of its own and ends no logical line — exactly the two
      things being inside parentheses already suppresses. Taken (and cleared)
      here so the flag set while tokenizing line N governs line N+1. }
    wasCont := contLine;
    contLine := False;
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
      if (parenDepth = 0) and (not wasCont) then
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
    if parenDepth = 0 then
    begin
      lineIsDefClass := False;
      lineSawColon := False;
    end;
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

      { A RAW string prefix: r'...' / R"..." keeps every backslash literal, which
        is what regex patterns are written with (`re.match(r'^([A-G][b#]?)')`).
        Checked BEFORE the identifier branch, which would otherwise lex the
        prefix as a one-letter name followed by an ordinary string. }
      rawStr := False;
      if ((c = 'r') or (c = 'R')) and (P + 1 <= Length(Source)) and
         ((Source[P + 1] = '"') or (Source[P + 1] = '''')) then
      begin
        rawStr := True;
        Inc(P);
        c := Source[P];
      end;

      { Identifiers and Keywords }
      if (not rawStr) and (c in ['a'..'z','A'..'Z','_']) then
      begin
        s := '';
        while (P <= Length(Source)) and (Source[P] in ['a'..'z','A'..'Z','0'..'9','_']) do
        begin
          AppendChar(s, Source[P]);
          Inc(P);
        end;
        k := PyKeyword(s);
        { There is DELIBERATELY no `Exception` -> `PyException` rename here any
          more. It existed while pylib's root had to carry a different name
          from sysutils', and it renamed the identifier on the way IN but never
          on the way out — so `repr(e)` and `type(e).__name__` printed
          `PyException('x')` where CPython says `Exception('x')`
          (bug-nilpy-exception-repr-and-type-name-say-pyexception). That
          asymmetry is the lesson: a rename at the token boundary is invisible
          to the user until something prints the name back.

          Both units now declare their OWN class named `Exception` under the
          shared `ExceptionBase` (compiler/builtin/exceptions.pas), so the
          spelling no longer needs to be unique — the LOOKUP does. pyparser
          resolves NilPy's `Exception` with FindUClassInUnit against pylib
          rather than by flat first match, which is precise where this was
          merely early. }
        { the FIRST token of the logical line decides whether an inline suite is
          possible at all — `x = {1: 2}` must not be mistaken for a header }
        if (parenDepth = 0) and (not lineSawColon) and
           ((k = tkFunction) or (k = tkClass)) and
           ((TokCount = streamBase) or
            (Tokens[TokCount - 1].Kind in [tkNewline, tkIndent, tkDedent])) then
          lineIsDefClass := True;
        PyEmitToken(k, 0, SrcLine, s);
        continue;
      end;

      { Numbers (Integers or Floats). `.5` also enters here: NilPy accepts
        Python's two dot-edge float spellings, `.5` and `5.`, which the SHARED
        Pascal scanner cannot (it starts only on a digit and only makes a float
        when the dot is followed by one — both load-bearing there, since `5.`
        must not swallow the first dot of `5..10` nor the selector in
        `5.Field`). NilPy has neither subranges nor a numeric-literal selector,
        and it lexes here rather than in lexer.inc, so this costs Pascal
        nothing. bug-nilpy-bare-dot-float-literals-do-not-lex }
      if (c in ['0'..'9']) or
         ((c = '.') and (P < Length(Source)) and (Source[P+1] in ['0'..'9'])) then
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
          decText := '';
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
            PyDecMulAdd(decText, numBase, digit);
            hasDigit := True;
            Inc(P);
          end;
          if not hasDigit then
          begin
            CurTok.Line := SrcLine;
            Error('invalid numeric literal');
          end;
          { Wider than Int64: the wrapped n has no correct signed reading, so
            carry the exact decimal for the promotable-int lowering (same
            convention as the Pascal lexer's decimal path). }
          if DecDigitsExceed(decText, '9223372036854775807') then
            PyEmitToken(tkInteger, n, SrcLine, decText)
          else
            PyEmitToken(tkInteger, n, SrcLine, '');
          continue;
        end;
        decText := '';
        while (P <= Length(Source)) and (Source[P] in ['0'..'9','_']) do
        begin
          if Source[P] <> '_' then
          begin
            n := n * 10 + (Ord(Source[P]) - 48);
            AppendChar(decText, Source[P]);
          end;
          Inc(P);
        end;
        { detect float: '.' followed by digit, a TRAILING '.' (`5.`, `5.e3` —
          see PyTrailingDotFloat), or an e/E exponent }
        if ((P < Length(Source)) and (Source[P] = '.') and (Source[P+1] in ['0'..'9'])) or
           PyTrailingDotFloat(P) or
           ((P <= Length(Source)) and ((Source[P] = 'e') or (Source[P] = 'E'))) then
        begin
          if (P < Length(Source)) and (Source[P] = '.') and (Source[P+1] in ['0'..'9']) then
          begin
            Inc(P);
            while (P <= Length(Source)) and (Source[P] in ['0'..'9']) do Inc(P);
          end
          else if PyTrailingDotFloat(P) then
            Inc(P);   { `5.` / `5.e3`: take the dot; the exponent follows below }
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
          if PyImaginarySuffix(P) then
            PyEmitImaginary(StrToDoubleBits(s), SrcLine)
          else
            PyEmitToken(tkFloat, StrToDoubleBits(s), SrcLine, '');
        end
        else if PyImaginarySuffix(P) then
          { `2j` — an INTEGER with the imaginary suffix. CPython has no integer
            complex, so the part is a float either way. }
          PyEmitImaginary(StrToDoubleBits(decText), SrcLine)
        else if DecDigitsExceed(decText, '9223372036854775807') then
          { decimal wider than Int64: carry the exact digits (promo lowering) }
          PyEmitToken(tkInteger, n, SrcLine, decText)
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
          else if (Source[P] = '\') and rawStr then
          begin
            { raw: the backslash is DATA, and it still stops the next character
              from closing the string — Python's own rule for r'a\'b' }
            AppendChar(s, Source[P]);
            Inc(P);
            if P <= Length(Source) then
            begin
              AppendChar(s, Source[P]);
              Inc(P);
            end;
          end
          else if Source[P] = '\' then
          begin
            Inc(P);
            if P <= Length(Source) then
            begin
              case Source[P] of
                'n': AppendChar(s, #10);
                't': AppendChar(s, #9);
                'r': AppendChar(s, #13);
                'a': AppendChar(s, #7);
                'b': AppendChar(s, #8);
                'f': AppendChar(s, #12);
                'v': AppendChar(s, #11);
                '\': AppendChar(s, '\');
                '''': AppendChar(s, '''');
                '"': AppendChar(s, '"');
                'x':
                  begin
                    { \xHH — two hex digits, CPython's numeric byte escape
                      (bug-nilpy-bytes-literal-escapes-not-decoded). A
                      malformed \x stays literal text, the lax-dialect
                      fallback below. }
                    if (P + 2 <= Length(Source)) and
                       (Source[P+1] in ['0'..'9', 'a'..'f', 'A'..'F']) and
                       (Source[P+2] in ['0'..'9', 'a'..'f', 'A'..'F']) then
                    begin
                      digit := 0;
                      case Source[P+1] of
                        '0'..'9': digit := Ord(Source[P+1]) - Ord('0');
                        'a'..'f': digit := Ord(Source[P+1]) - Ord('a') + 10;
                        'A'..'F': digit := Ord(Source[P+1]) - Ord('A') + 10;
                      end;
                      digit := digit * 16;
                      case Source[P+2] of
                        '0'..'9': digit := digit + Ord(Source[P+2]) - Ord('0');
                        'a'..'f': digit := digit + Ord(Source[P+2]) - Ord('a') + 10;
                        'A'..'F': digit := digit + Ord(Source[P+2]) - Ord('A') + 10;
                      end;
                      AppendChar(s, Chr(digit));
                      Inc(P, 2);
                    end
                    else begin AppendChar(s, '\'); AppendChar(s, 'x'); end;
                  end;
                '0'..'7':
                  begin
                    { \ooo — one to three octal digits (\0 = NUL). }
                    digit := Ord(Source[P]) - Ord('0');
                    if (P + 1 <= Length(Source)) and (Source[P+1] in ['0'..'7']) then
                    begin
                      digit := digit * 8 + Ord(Source[P+1]) - Ord('0');
                      Inc(P);
                      if (P + 1 <= Length(Source)) and (Source[P+1] in ['0'..'7']) and
                         (digit * 8 + Ord(Source[P+1]) - Ord('0') <= 255) then
                      begin
                        digit := digit * 8 + Ord(Source[P+1]) - Ord('0');
                        Inc(P);
                      end;
                    end;
                    AppendChar(s, Chr(digit));
                  end;
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
          { `**=` must be ONE token — `**` itself is two tkStar the parser pairs
            up, but the augmented form would otherwise read as `*` then `*=`.
            Checked before the plain `*=` so the longer spelling wins. }
          if (P + 1 <= Length(Source)) and (Source[P] = '*') and
             (Source[P + 1] = '=') then
          begin Inc(P); Inc(P); PyEmitToken(tkPowEq, 0, SrcLine, ''); end
          else if (P <= Length(Source)) and (Source[P] = '=') then
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
          else if (P <= Length(Source)) and (Source[P] = '=') then
          begin Inc(P); PyEmitToken(tkTrueDivEq, 0, SrcLine, ''); end
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
        { `@` is BOTH the decorator prefix and the infix matrix-multiply
          operator; they are told apart by position (statement start), not by
          the token. `@=` must be one token though — see tkAtEq. }
        '@': begin
          if (P <= Length(Source)) and (Source[P] = '=') then
          begin Inc(P); PyEmitToken(tkAtEq, 0, SrcLine, ''); end
          else PyEmitToken(tkAt, 0, SrcLine, '');
        end;
        ':':
        begin
          PyEmitToken(tkColon, 0, SrcLine, '');
          { a header colon with anything but a comment or the line end after it
            opens an inline suite }
          if lineIsDefClass and (parenDepth = 0) and (not lineSawColon) then
          begin
            lineSawColon := True;
            peekP := P;
            while (peekP <= Length(Source)) and
                  ((Source[peekP] = ' ') or (Source[peekP] = #9)) do Inc(peekP);
            if (peekP <= Length(Source)) and (Source[peekP] <> #10) and
               (Source[peekP] <> #13) and (Source[peekP] <> '#') then
            begin
              PyEmitToken(tkNewline, 0, SrcLine, '');
              PyEmitToken(tkIndent, 0, SrcLine, '');
              inlineSuite := True;
            end;
          end;
        end;
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
        '\':
        begin
          { LINE CONTINUATION. A backslash may only be the last thing on the
            line; anything else after it (bar trailing blanks and the CR of a
            CRLF) is a syntax error in Python too, and saying so beats lexing
            the rest of the line as if the backslash were not there.

            The continuation is then handled exactly as an open parenthesis is:
            no tkNewline here, and no indentation processing on the next
            physical line. Both suppressions already exist for parenDepth; this
            reuses them rather than adding a second notion of "still the same
            logical line".

            6 of html5lib's 33 files use this, all in the same shape — a long
            `if a and \` condition split across lines
            (feature-nilpy-thirdparty-libraries-as-targets). }
          while (P <= Length(Source)) and
                ((Source[P] = ' ') or (Source[P] = #9) or (Source[P] = #13)) do
            Inc(P);
          if (P <= Length(Source)) and (Source[P] <> #10) then
          begin
            CurTok.Line := SrcLine;
            Error('a backslash must be the last character on its line');
          end;
          contLine := True;
        end;
        else
        begin
          CurTok.Line := SrcLine;
          Error('unexpected character: ' + c);
        end;
      end;
    end;

    { 4. End of physical line: emit tkNewline if logical line and paren depth is 0 }
    if IsLogicalLine and (parenDepth = 0) and (not contLine) then
    begin
      PyEmitToken(tkNewline, 0, SrcLine, '');
    end;
    { close a synthesised inline suite: the multi-line form's DEDENT comes from
      the NEXT line's indent measurement, so it sits after that newline too }
    if inlineSuite and (parenDepth = 0) then
    begin
      PyEmitToken(tkDedent, 0, SrcLine, '');
      inlineSuite := False;
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

{ Lex a `.py` MODULE into the token stream, after whatever is already there,
  and return the index of its first token. The importer parses from there and
  restores its own position afterwards — the same shape LexAppend gives a
  Pascal unit and CLexAppend a C one (feature-nilpy-py-module-loader). }
function PyLexAppend(const src: AnsiString): Integer;
var savedSource: AnsiString; savedLine: Integer;
begin
  savedSource := Source;
  savedLine := SrcLine;
  Source := src;
  PyExpandFStrings;            { operates on Source, like the main program's }
  Result := TokCount;
  PyLexAppending := True;
  PyLexAll(False);
  PyLexAppending := False;
  Source := savedSource;
  SrcLine := savedLine;
end;
