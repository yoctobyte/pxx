{ ===== C Preprocessor =====
  Text rewriting only: directives and macros are removed before C lexing. }

function CPIsIdentStart(c: Char): Boolean;
begin
  Result := (c in ['a'..'z']) or (c in ['A'..'Z']) or (c = '_');
end;

function CPIsIdentChar(c: Char): Boolean;
begin
  Result := CPIsIdentStart(c) or (c in ['0'..'9']);
end;

procedure CPAppendRange(var dst: AnsiString; const src: AnsiString; a, b: Integer);
var i: Integer;
begin
  i := a;
  while i <= b do
  begin
    AppendChar(dst, src[i]);
    Inc(i);
  end;
end;

procedure CPConcat2(const a, b: AnsiString; var dst: AnsiString);
var i: Integer;
begin
  SetLength(dst, 0);
  for i := 1 to Length(a) do AppendChar(dst, a[i]);
  for i := 1 to Length(b) do AppendChar(dst, b[i]);
end;

function CPStoreRange(const src: AnsiString; a, b: Integer): Integer;
var i: Integer;
begin
  Result := CPrepCharLen;
  i := a;
  while i <= b do
  begin
    if CPrepCharLen >= MAX_CPREP_CHARS then Error('C preprocessor text overflow');
    CPrepChars[CPrepCharLen] := src[i];
    Inc(CPrepCharLen);
    Inc(i);
  end;
end;

function CPStoreLiteral(const src: AnsiString): Integer;
begin
  Result := CPStoreRange(src, 1, Length(src));
end;

function CPPoolEquals(off, len: Integer; const src: AnsiString; a, b: Integer): Boolean;
var i: Integer;
begin
  Result := False;
  if len <> b - a + 1 then Exit;
  i := 0;
  while i < len do
  begin
    if CPrepChars[off + i] <> src[a + i] then Exit;
    Inc(i);
  end;
  Result := True;
end;

function CPPoolNameEquals(off, len, off2, len2: Integer): Boolean;
var i: Integer;
begin
  Result := False;
  if len <> len2 then Exit;
  i := 0;
  while i < len do
  begin
    if CPrepChars[off + i] <> CPrepChars[off2 + i] then Exit;
    Inc(i);
  end;
  Result := True;
end;

function CPRangeIsLiteral(const src: AnsiString; a, b: Integer;
  const lit: AnsiString): Boolean;
var i: Integer;
begin
  Result := False;
  if b - a + 1 <> Length(lit) then Exit;
  i := 1;
  while i <= Length(lit) do
  begin
    if src[a + i - 1] <> lit[i] then Exit;
    Inc(i);
  end;
  Result := True;
end;

function CPFindMacro(const src: AnsiString; a, b: Integer): Integer;
var i: Integer;
begin
  Result := -1;
  for i := CPMCount - 1 downto 0 do
    if CPPoolEquals(CPMNameOff[i], CPMNameLen[i], src, a, b) then
    begin
      Result := i;
      Exit;
    end;
end;

function CPFindMacroPool(off, len: Integer): Integer;
var i: Integer;
begin
  Result := -1;
  for i := CPMCount - 1 downto 0 do
    if CPPoolNameEquals(CPMNameOff[i], CPMNameLen[i], off, len) then
    begin
      Result := i;
      Exit;
    end;
end;

function CPMacroDefined(const src: AnsiString; a, b: Integer): Boolean;
begin
  Result := CPFindMacro(src, a, b) >= 0;
end;

procedure CPAddLiteral(const name, value: AnsiString);
var mi: Integer;
begin
  if CPMCount >= MAX_CPREP_MACROS then Error('too many C macros');
  mi := CPMCount;
  Inc(CPMCount);
  CPMNameOff[mi] := CPStoreLiteral(name);
  CPMNameLen[mi] := Length(name);
  CPMValueOff[mi] := CPStoreLiteral(value);
  CPMValueLen[mi] := Length(value);
  CPMFunction[mi] := False;
  CPMParamBase[mi] := CPPCount;
  CPMParamCount[mi] := 0;
end;

procedure CPDefine(const line: AnsiString; p, last: Integer);
var
  mi, nameStart, nameEnd, valueStart, valueEnd, paramStart, paramEnd: Integer;
begin
  while (p <= last) and (line[p] in [' ', #9]) do Inc(p);
  if (p > last) or not CPIsIdentStart(line[p]) then Exit;
  nameStart := p;
  while (p <= last) and CPIsIdentChar(line[p]) do Inc(p);
  nameEnd := p - 1;
  if CPMCount >= MAX_CPREP_MACROS then Error('too many C macros');
  mi := CPMCount;
  Inc(CPMCount);
  CPMNameOff[mi] := CPStoreRange(line, nameStart, nameEnd);
  CPMNameLen[mi] := nameEnd - nameStart + 1;
  CPMParamBase[mi] := CPPCount;
  CPMParamCount[mi] := 0;
  CPMFunction[mi] := False;

  { The opening parenthesis must immediately follow a function-like name. }
  if (p <= last) and (line[p] = '(') then
  begin
    CPMFunction[mi] := True;
    Inc(p);
    while (p <= last) and (line[p] <> ')') do
    begin
      while (p <= last) and (line[p] in [' ', #9, ',']) do Inc(p);
      if (p <= last) and CPIsIdentStart(line[p]) then
      begin
        paramStart := p;
        while (p <= last) and CPIsIdentChar(line[p]) do Inc(p);
        paramEnd := p - 1;
        if CPPCount >= MAX_CPREP_PARAMS then Error('too many C macro parameters');
        CPPNameOff[CPPCount] := CPStoreRange(line, paramStart, paramEnd);
        CPPNameLen[CPPCount] := paramEnd - paramStart + 1;
        Inc(CPPCount);
        CPMParamCount[mi] := CPMParamCount[mi] + 1;
      end
      else
        Inc(p);
    end;
    if (p <= last) and (line[p] = ')') then Inc(p);
  end;
  while (p <= last) and (line[p] in [' ', #9]) do Inc(p);
  valueStart := p;
  valueEnd := last;
  while (valueEnd >= valueStart) and (line[valueEnd] in [' ', #9]) do Dec(valueEnd);
  CPMValueOff[mi] := CPStoreRange(line, valueStart, valueEnd);
  if valueEnd >= valueStart then
    CPMValueLen[mi] := valueEnd - valueStart + 1
  else
    CPMValueLen[mi] := 0;
  if DebugTrace then
    writeln('C preprocessor: define #', mi, ' name-len=', CPMNameLen[mi],
      ' value-len=', CPMValueLen[mi], ' function=', Ord(CPMFunction[mi]));
end;

procedure CPUndef(const line: AnsiString; p, last: Integer);
var mi, a, b: Integer;
begin
  while (p <= last) and (line[p] in [' ', #9]) do Inc(p);
  a := p;
  while (p <= last) and CPIsIdentChar(line[p]) do Inc(p);
  b := p - 1;
  mi := CPFindMacro(line, a, b);
  if mi >= 0 then
  begin
    CPMNameLen[mi] := -1;
    if DebugTrace then writeln('C preprocessor: undef #', mi);
  end;
end;

function CPActive: Boolean;
begin
  if CPCondCount = 0 then Result := True
  else Result := CPCondActive[CPCondCount - 1];
end;

procedure CPSkipExprSpace;
begin
  while (CPExprPos <= CPExprEnd) and (CPExprText[CPExprPos] in [' ', #9]) do
    Inc(CPExprPos);
end;

function CPParsePoolNumber(mi: Integer): Int64;
var p, last: Integer; negative: Boolean;
begin
  Result := 0;
  p := CPMValueOff[mi];
  last := p + CPMValueLen[mi] - 1;
  while (p <= last) and (CPrepChars[p] in [' ', #9]) do Inc(p);
  negative := False;
  if (p <= last) and (CPrepChars[p] = '-') then
  begin
    negative := True;
    Inc(p);
  end;
  while (p <= last) and (CPrepChars[p] in ['0'..'9']) do
  begin
    Result := (Result * 10) + Ord(CPrepChars[p]) - Ord('0');
    Inc(p);
  end;
  if negative then Result := -Result;
end;

function CPExprOr: Int64; forward;

function CPExprAtom: Int64;
var a, b, mi: Integer;
begin
  CPSkipExprSpace;
  Result := 0;
  if CPExprPos > CPExprEnd then Exit;
  if CPExprText[CPExprPos] = '(' then
  begin
    Inc(CPExprPos);
    Result := CPExprOr;
    CPSkipExprSpace;
    if (CPExprPos <= CPExprEnd) and (CPExprText[CPExprPos] = ')') then Inc(CPExprPos);
    Exit;
  end;
  if CPExprText[CPExprPos] in ['0'..'9'] then
  begin
    while (CPExprPos <= CPExprEnd) and (CPExprText[CPExprPos] in ['0'..'9']) do
    begin
      Result := (Result * 10) + Ord(CPExprText[CPExprPos]) - Ord('0');
      Inc(CPExprPos);
    end;
    Exit;
  end;
  if CPIsIdentStart(CPExprText[CPExprPos]) then
  begin
    a := CPExprPos;
    while (CPExprPos <= CPExprEnd) and CPIsIdentChar(CPExprText[CPExprPos]) do Inc(CPExprPos);
    b := CPExprPos - 1;
    if (b - a + 1 = 7) and
       (CPExprText[a] = 'd') and (CPExprText[a+1] = 'e') and
       (CPExprText[a+2] = 'f') and (CPExprText[a+3] = 'i') and
       (CPExprText[a+4] = 'n') and (CPExprText[a+5] = 'e') and
       (CPExprText[a+6] = 'd') then
    begin
      CPSkipExprSpace;
      if (CPExprPos <= CPExprEnd) and (CPExprText[CPExprPos] = '(') then Inc(CPExprPos);
      CPSkipExprSpace;
      a := CPExprPos;
      while (CPExprPos <= CPExprEnd) and CPIsIdentChar(CPExprText[CPExprPos]) do Inc(CPExprPos);
      b := CPExprPos - 1;
      if CPMacroDefined(CPExprText, a, b) then Result := 1 else Result := 0;
      CPSkipExprSpace;
      if (CPExprPos <= CPExprEnd) and (CPExprText[CPExprPos] = ')') then Inc(CPExprPos);
    end
    else
    begin
      mi := CPFindMacro(CPExprText, a, b);
      if mi >= 0 then Result := CPParsePoolNumber(mi) else Result := 0;
    end;
  end;
end;

function CPExprUnary: Int64;
begin
  CPSkipExprSpace;
  if (CPExprPos <= CPExprEnd) and (CPExprText[CPExprPos] = '!') then
  begin
    Inc(CPExprPos);
    if CPExprUnary() = 0 then Result := 1 else Result := 0;
  end
  else
    Result := CPExprAtom;
end;

function CPExprCompare: Int64;
var left, right: Int64; op1, op2: Char;
begin
  left := CPExprUnary;
  CPSkipExprSpace;
  if CPExprPos <= CPExprEnd then
  begin
    op1 := CPExprText[CPExprPos];
    op2 := #0;
    if CPExprPos < CPExprEnd then op2 := CPExprText[CPExprPos + 1];
    if (op1 in ['=', '!', '<', '>']) then
    begin
      Inc(CPExprPos);
      if op2 = '=' then Inc(CPExprPos);
      right := CPExprUnary;
      if (op1 = '=') and (op2 = '=') then begin if left = right then left := 1 else left := 0; end
      else if (op1 = '!') and (op2 = '=') then begin if left <> right then left := 1 else left := 0; end
      else if (op1 = '<') and (op2 = '=') then begin if left <= right then left := 1 else left := 0; end
      else if (op1 = '>') and (op2 = '=') then begin if left >= right then left := 1 else left := 0; end
      else if op1 = '<' then begin if left < right then left := 1 else left := 0; end
      else if op1 = '>' then begin if left > right then left := 1 else left := 0; end;
    end;
  end;
  Result := left;
end;

function CPExprAnd: Int64;
var v: Int64;
begin
  Result := CPExprCompare;
  CPSkipExprSpace;
  while (CPExprPos < CPExprEnd) and (CPExprText[CPExprPos] = '&') and
        (CPExprText[CPExprPos + 1] = '&') do
  begin
    Inc(CPExprPos); Inc(CPExprPos);
    v := CPExprCompare;
    if (Result <> 0) and (v <> 0) then Result := 1 else Result := 0;
    CPSkipExprSpace;
  end;
end;

function CPExprOr: Int64;
var v: Int64;
begin
  Result := CPExprAnd;
  CPSkipExprSpace;
  while (CPExprPos < CPExprEnd) and (CPExprText[CPExprPos] = '|') and
        (CPExprText[CPExprPos + 1] = '|') do
  begin
    Inc(CPExprPos); Inc(CPExprPos);
    v := CPExprAnd;
    if (Result <> 0) or (v <> 0) then Result := 1 else Result := 0;
    CPSkipExprSpace;
  end;
end;

function CPEvalExpr(const line: AnsiString; p, last: Integer): Boolean;
begin
  CPExprText := line;
  CPExprPos := p;
  CPExprEnd := last;
  Result := CPExprOr <> 0;
end;

procedure CPExpandRange(const src: AnsiString; first, last, level: Integer;
  var dst: AnsiString); forward;

function CPMacroIsActive(mi: Integer): Boolean;
var i: Integer;
begin
  Result := False;
  for i := 0 to CPActiveMacroCount - 1 do
    if CPActiveMacros[i] = mi then
    begin
      Result := True;
      Exit;
    end;
end;

procedure CPExpandObject(mi, level: Integer; var dst: AnsiString);
var p, last: Integer;
begin
  if DebugTrace then writeln('C preprocessor: expand object #', mi, ' level=', level);
  p := CPMValueOff[mi];
  last := p + CPMValueLen[mi] - 1;
  while p <= last do
  begin
    AppendChar(dst, CPrepChars[p]);
    Inc(p);
  end;
end;

function CPParamIndex(mi, off, len: Integer): Integer;
var i, pi: Integer;
begin
  Result := -1;
  for i := 0 to CPMParamCount[mi] - 1 do
  begin
    pi := CPMParamBase[mi] + i;
    if CPPoolNameEquals(CPPNameOff[pi], CPPNameLen[pi], off, len) then
    begin
      Result := i;
      Exit;
    end;
  end;
end;

procedure CPExpandFunction(mi: Integer; const src: AnsiString;
  argCount, level: Integer; var dst: AnsiString);
var p, last, a, b, ai, argBase, argP: Integer;
    expandedArg: AnsiString;
begin
  if DebugTrace then writeln('C preprocessor: expand function #', mi, ' level=', level);
  argBase := level * 16;
  p := CPMValueOff[mi];
  last := p + CPMValueLen[mi] - 1;
  while p <= last do
  begin
    if CPIsIdentStart(CPrepChars[p]) then
    begin
      a := p;
      while (p <= last) and CPIsIdentChar(CPrepChars[p]) do Inc(p);
      b := p - 1;
      ai := CPParamIndex(mi, a, b - a + 1);
      if (ai >= 0) and (ai < argCount) then
      begin
        SetLength(expandedArg, 0);
        CPExpandRange(src, CPArgStart[argBase + ai], CPArgEnd[argBase + ai],
          level + 1, expandedArg);
        for argP := 1 to Length(expandedArg) do
          AppendChar(dst, expandedArg[argP]);
      end
      else
      begin
        while a <= b do
        begin
          AppendChar(dst, CPrepChars[a]);
          Inc(a);
        end;
      end;
    end
    else
    begin
      AppendChar(dst, CPrepChars[p]);
      Inc(p);
    end;
  end;
end;

procedure CPExpandRange(const src: AnsiString; first, last, level: Integer;
  var dst: AnsiString);
var
  p, a, b, mi, q, depth, argc, argBase: Integer;
  quote: Char;
  quotedDone: Boolean;
  tmp: AnsiString;
begin
  if level > 32 then Error('C macro recursion');
  p := first;
  while p <= last do
  begin
    if (src[p] = '"') or (src[p] = '''') then
    begin
      quote := src[p];
      AppendChar(dst, src[p]);
      Inc(p);
      quotedDone := False;
      while (p <= last) and not quotedDone do
      begin
        AppendChar(dst, src[p]);
        if (src[p] = '\') and (p < last) then
        begin
          Inc(p);
          AppendChar(dst, src[p]);
        end
        else if src[p] = quote then
        begin
          Inc(p);
          quotedDone := True;
        end;
        if not quotedDone then Inc(p);
      end;
    end
    else if CPIsIdentStart(src[p]) then
    begin
      a := p;
      while (p <= last) and CPIsIdentChar(src[p]) do Inc(p);
      b := p - 1;
      mi := CPFindMacro(src, a, b);
      if (mi < 0) then
        CPAppendRange(dst, src, a, b)
      else if not CPMFunction[mi] then
      begin
        if CPMacroIsActive(mi) then
          CPAppendRange(dst, src, a, b)
        else
        begin
          CPActiveMacros[CPActiveMacroCount] := mi;
          Inc(CPActiveMacroCount);
          
          SetLength(tmp, 0);
          CPExpandObject(mi, level + 1, tmp);
          CPExpandRange(tmp, 1, Length(tmp), level + 1, dst);
          
          Dec(CPActiveMacroCount);
        end;
      end
      else
      begin
        q := p;
        while (q <= last) and (src[q] in [' ', #9]) do Inc(q);
        if (q > last) or (src[q] <> '(') then
          CPAppendRange(dst, src, a, b)
        else
        begin
          if level >= 32 then Error('C macro recursion');
          Inc(q);
          argc := 0;
          depth := 0;
          argBase := (level + 1) * 16;
          if (q <= last) and (src[q] <> ')') then
          begin
            CPArgStart[argBase] := q;
            argc := 1;
          end;
          while (q <= last) and ((depth > 0) or (src[q] <> ')')) do
          begin
            if src[q] = '(' then Inc(depth)
            else if src[q] = ')' then Dec(depth)
            else if (src[q] = ',') and (depth = 0) and (argc < 16) then
            begin
              CPArgEnd[argBase + argc - 1] := q - 1;
              CPArgStart[argBase + argc] := q + 1;
              Inc(argc);
            end;
            Inc(q);
          end;
          if argc > 0 then CPArgEnd[argBase + argc - 1] := q - 1;
          
          if CPMacroIsActive(mi) then
            CPAppendRange(dst, src, a, q)
          else
          begin
            CPActiveMacros[CPActiveMacroCount] := mi;
            Inc(CPActiveMacroCount);
            
            SetLength(tmp, 0);
            CPExpandFunction(mi, src, argc, level + 1, tmp);
            CPExpandRange(tmp, 1, Length(tmp), level + 1, dst);
            
            Dec(CPActiveMacroCount);
          end;
          
          if (q <= last) and (src[q] = ')') then Inc(q);
          p := q;
        end;
      end;
    end
    else
    begin
      AppendChar(dst, src[p]);
      Inc(p);
    end;
  end;
end;

procedure CPReadLine(const src: AnsiString; var pos: Integer;
  var inComment: Boolean; var line: AnsiString);
var inString, inChar, done: Boolean; c: Char;
begin
  SetLength(line, 0);
  inString := False;
  inChar := False;
  done := False;
  while (pos <= Length(src)) and not done do
  begin
    c := src[pos];
    if inComment then
    begin
      if (c = '*') and (pos < Length(src)) and (src[pos + 1] = '/') then
      begin
        inComment := False;
        Inc(pos); Inc(pos);
        AppendChar(line, ' ');
      end
      else
      begin
        if c = #10 then done := True;
        Inc(pos);
      end;
    end
    else if (not inString) and (not inChar) and (c = '/') and
            (pos < Length(src)) and (src[pos + 1] = '*') then
    begin
      inComment := True;
      Inc(pos); Inc(pos);
      AppendChar(line, ' ');
    end
    else if (not inString) and (not inChar) and (c = '/') and
            (pos < Length(src)) and (src[pos + 1] = '/') then
    begin
      while (pos <= Length(src)) and (src[pos] <> #10) do Inc(pos);
      done := True;
      if pos <= Length(src) then Inc(pos);
    end
    else if (not inString) and (not inChar) and (c = '\') and
            (pos < Length(src)) and (src[pos + 1] = #10) then
    begin
      AppendChar(line, ' ');
      Inc(pos); Inc(pos);
    end
    else if c = #10 then
    begin
      Inc(pos);
      done := True;
    end
    else
    begin
      AppendChar(line, c);
      if (c = '"') and not inChar then inString := not inString
      else if (c = '''') and not inString then inChar := not inChar;
      if (c = '\') and (inString or inChar) and (pos < Length(src)) then
      begin
        Inc(pos);
        AppendChar(line, src[pos]);
      end;
      Inc(pos);
    end;
  end;
end;

procedure CPProcessText(const src, baseDir: AnsiString; depth: Integer); forward;

procedure CPLoadInclude(depth: Integer);
begin
  case depth of
    0: LoadFile(CPrepPath, CPrepInclude0);
    1: LoadFile(CPrepPath, CPrepInclude1);
    2: LoadFile(CPrepPath, CPrepInclude2);
    3: LoadFile(CPrepPath, CPrepInclude3);
    4: LoadFile(CPrepPath, CPrepInclude4);
    5: LoadFile(CPrepPath, CPrepInclude5);
    6: LoadFile(CPrepPath, CPrepInclude6);
    7: LoadFile(CPrepPath, CPrepInclude7);
    8: LoadFile(CPrepPath, CPrepInclude8);
    9: LoadFile(CPrepPath, CPrepInclude9);
    10: LoadFile(CPrepPath, CPrepInclude10);
    11: LoadFile(CPrepPath, CPrepInclude11);
    12: LoadFile(CPrepPath, CPrepInclude12);
    13: LoadFile(CPrepPath, CPrepInclude13);
    14: LoadFile(CPrepPath, CPrepInclude14);
    15: LoadFile(CPrepPath, CPrepInclude15);
  end;
end;

function CPIncludeLength(depth: Integer): Integer;
begin
  case depth of
    0: Result := Length(CPrepInclude0);
    1: Result := Length(CPrepInclude1);
    2: Result := Length(CPrepInclude2);
    3: Result := Length(CPrepInclude3);
    4: Result := Length(CPrepInclude4);
    5: Result := Length(CPrepInclude5);
    6: Result := Length(CPrepInclude6);
    7: Result := Length(CPrepInclude7);
    8: Result := Length(CPrepInclude8);
    9: Result := Length(CPrepInclude9);
    10: Result := Length(CPrepInclude10);
    11: Result := Length(CPrepInclude11);
    12: Result := Length(CPrepInclude12);
    13: Result := Length(CPrepInclude13);
    14: Result := Length(CPrepInclude14);
    15: Result := Length(CPrepInclude15);
  end;
end;

procedure CPProcessInclude(depth: Integer; const baseDir: AnsiString);
begin
  case depth of
    0: CPProcessText(CPrepInclude0, baseDir, depth + 1);
    1: CPProcessText(CPrepInclude1, baseDir, depth + 1);
    2: CPProcessText(CPrepInclude2, baseDir, depth + 1);
    3: CPProcessText(CPrepInclude3, baseDir, depth + 1);
    4: CPProcessText(CPrepInclude4, baseDir, depth + 1);
    5: CPProcessText(CPrepInclude5, baseDir, depth + 1);
    6: CPProcessText(CPrepInclude6, baseDir, depth + 1);
    7: CPProcessText(CPrepInclude7, baseDir, depth + 1);
    8: CPProcessText(CPrepInclude8, baseDir, depth + 1);
    9: CPProcessText(CPrepInclude9, baseDir, depth + 1);
    10: CPProcessText(CPrepInclude10, baseDir, depth + 1);
    11: CPProcessText(CPrepInclude11, baseDir, depth + 1);
    12: CPProcessText(CPrepInclude12, baseDir, depth + 1);
    13: CPProcessText(CPrepInclude13, baseDir, depth + 1);
    14: CPProcessText(CPrepInclude14, baseDir, depth + 1);
    15: CPProcessText(CPrepInclude15, baseDir, depth + 1);
  end;
end;

procedure CPInclude(const line: AnsiString; p, last, depth: Integer;
  const baseDir: AnsiString);
var a, b: Integer;
begin
  if depth >= MAX_CPREP_INCLUDES then Error('C include nesting overflow');
  while (p <= last) and (line[p] in [' ', #9]) do Inc(p);
  if p > last then Exit;
  if (line[p] = '"') or (line[p] = '<') then
  begin
    if line[p] = '"' then b := Ord('"') else b := Ord('>');
    Inc(p);
    a := p;
    while (p <= last) and (Ord(line[p]) <> b) do Inc(p);
    CPConcat2(baseDir, '', CPrepPath);
    CPAppendRange(CPrepPath, line, a, p - 1);
    CPLoadInclude(depth);
    if CPIncludeLength(depth) = 0 then
    begin
      SetLength(CPrepPath, 0);
      CPAppendRange(CPrepPath, '/usr/include/', 1, 13);
      CPAppendRange(CPrepPath, line, a, p - 1);
      CPLoadInclude(depth);
    end;
    if CPIncludeLength(depth) = 0 then
    begin
      SetLength(CPrepPath, 0);
      CPAppendRange(CPrepPath, '/usr/include/x86_64-linux-gnu/', 1, 30);
      CPAppendRange(CPrepPath, line, a, p - 1);
      CPLoadInclude(depth);
    end;
    if CPIncludeLength(depth) = 0 then
    begin
      SetLength(CPrepPath, 0);
      CPAppendRange(CPrepPath, '/usr/lib/gcc/x86_64-linux-gnu/13/include/', 1, 41);
      CPAppendRange(CPrepPath, line, a, p - 1);
      CPLoadInclude(depth);
    end;
    if CPIncludeLength(depth) = 0 then
    begin
      SetLength(CPrepPath, 0);
      CPAppendRange(CPrepPath, '/usr/lib/llvm-18/lib/clang/18/include/', 1, 38);
      CPAppendRange(CPrepPath, line, a, p - 1);
      CPLoadInclude(depth);
    end;
    if CPIncludeLength(depth) = 0 then
    begin
      ErrorIdent := CPrepPath;
      Error('C include file not found');
    end;
    if DebugTrace then writeln('C preprocessor: include ', CPrepPath);
    CPProcessInclude(depth, GetFilePath(CPrepPath));
  end;
end;

procedure CPDirective(const line: AnsiString; p, last, depth: Integer;
  const baseDir: AnsiString);
var a, b: Integer; cond, parent: Boolean;
begin
  Inc(p);
  while (p <= last) and (line[p] in [' ', #9]) do Inc(p);
  a := p;
  while (p <= last) and CPIsIdentChar(line[p]) do Inc(p);
  b := p - 1;

  if CPRangeIsLiteral(line, a, b, 'if') then
  begin
    if CPCondCount >= MAX_CPREP_CONDS then Error('C conditional nesting overflow');
    parent := CPActive;
    cond := CPEvalExpr(line, p, last);
    CPCondParent[CPCondCount] := parent;
    CPCondTaken[CPCondCount] := cond;
    CPCondActive[CPCondCount] := parent and cond;
    Inc(CPCondCount);
    if DebugTrace then writeln('C preprocessor: if active=', Ord(CPActive));
  end
  else if CPRangeIsLiteral(line, a, b, 'ifdef') or
          CPRangeIsLiteral(line, a, b, 'ifndef') then
  begin
    if CPCondCount >= MAX_CPREP_CONDS then Error('C conditional nesting overflow');
    parent := CPActive;
    while (p <= last) and (line[p] in [' ', #9]) do Inc(p);
    a := p;
    while (p <= last) and CPIsIdentChar(line[p]) do Inc(p);
    cond := CPMacroDefined(line, a, p - 1);
    if CPRangeIsLiteral(line, b - 5, b, 'ifndef') then cond := not cond;
    CPCondParent[CPCondCount] := parent;
    CPCondTaken[CPCondCount] := cond;
    CPCondActive[CPCondCount] := parent and cond;
    Inc(CPCondCount);
    if DebugTrace then writeln('C preprocessor: ifdef active=', Ord(CPActive));
  end
  else if CPRangeIsLiteral(line, a, b, 'elif') then
  begin
    if CPCondCount = 0 then Error('C elif without if');
    cond := CPEvalExpr(line, p, last);
    CPCondActive[CPCondCount - 1] := CPCondParent[CPCondCount - 1] and
      (not CPCondTaken[CPCondCount - 1]) and cond;
    if cond then CPCondTaken[CPCondCount - 1] := True;
    if DebugTrace then writeln('C preprocessor: elif active=', Ord(CPActive));
  end
  else if CPRangeIsLiteral(line, a, b, 'else') then
  begin
    if CPCondCount = 0 then Error('C else without if');
    CPCondActive[CPCondCount - 1] := CPCondParent[CPCondCount - 1] and
      (not CPCondTaken[CPCondCount - 1]);
    CPCondTaken[CPCondCount - 1] := True;
    if DebugTrace then writeln('C preprocessor: else active=', Ord(CPActive));
  end
  else if CPRangeIsLiteral(line, a, b, 'endif') then
  begin
    if CPCondCount = 0 then Error('C endif without if');
    Dec(CPCondCount);
  end
  else if CPActive and CPRangeIsLiteral(line, a, b, 'define') then
    CPDefine(line, p, last)
  else if CPActive and CPRangeIsLiteral(line, a, b, 'undef') then
    CPUndef(line, p, last)
  else if CPActive and CPRangeIsLiteral(line, a, b, 'include') then
    CPInclude(line, p, last, depth, baseDir);
end;

procedure CPProcessText(const src, baseDir: AnsiString; depth: Integer);
var pos, p: Integer; inComment: Boolean;
begin
  pos := 1;
  inComment := False;
  while pos <= Length(src) do
  begin
    CPReadLine(src, pos, inComment, CPrepLine);
    p := 1;
    while (p <= Length(CPrepLine)) and (CPrepLine[p] in [' ', #9]) do Inc(p);
    if (p <= Length(CPrepLine)) and (CPrepLine[p] = '#') then
      CPDirective(CPrepLine, p, Length(CPrepLine), depth, baseDir)
    else if CPActive then
    begin
      CPExpandRange(CPrepLine, 1, Length(CPrepLine), 0, CPrepOut);
      AppendChar(CPrepOut, #10);
    end;
  end;
end;

procedure CPreprocess(var src: AnsiString; const baseDir: AnsiString);
begin
  SetLength(CPrepOut, 0);
  CPrepCharLen := 0;
  CPMCount := 0;
  CPPCount := 0;
  CPCondCount := 0;
  CPActiveMacroCount := 0;
  CPAddLiteral('__linux__', '01');
  CPAddLiteral('__x86_64__', '01');
  CPAddLiteral('__STDC__', '01');
  CPProcessText(src, baseDir, 0);
  if CPCondCount <> 0 then Error('unterminated C conditional');
  src := CPrepOut;
end;
