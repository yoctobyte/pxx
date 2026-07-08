{ SPDX-License-Identifier: MPL-2.0 }
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

{ Amortized append to the main preprocessor output CPrepOut. CPrepOut holds
  geometric spare capacity (physical Length); CPrepOutLen is the live byte count.
  Ensures the per-char SetLength(len+1) O(n^2) reallocation storm is replaced by
  doubling growth — one realloc per ~log2(n) appends. CPreprocess trims CPrepOut
  back to CPrepOutLen before handing it out. }
procedure CPrepOutEnsure(extra: NativeInt);
var need, cap: NativeInt;
begin
  need := CPrepOutLen + extra;
  cap := Length(CPrepOut);
  if need <= cap then Exit;
  if cap < 256 then cap := 256;
  while cap < need do cap := cap * 2;
  SetLength(CPrepOut, cap);
end;

procedure CPrepOutAppendStr(const s: AnsiString);
var i, n: NativeInt;
begin
  n := Length(s);
  if n <= 0 then Exit;
  CPrepOutEnsure(n);
  for i := 1 to n do
    CPrepOut[CPrepOutLen + i] := s[i];
  CPrepOutLen := CPrepOutLen + n;
end;

procedure CPrepOutAppendCh(c: Char);
begin
  CPrepOutEnsure(1);
  CPrepOut[CPrepOutLen + 1] := c;
  CPrepOutLen := CPrepOutLen + 1;
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
  CPMVariadic[mi] := False;
  CPMParamBase[mi] := CPPCount;
  CPMParamCount[mi] := 0;
end;

procedure CPDefine(const line: AnsiString; p, last: Integer);
var
  mi, nameStart, nameEnd, valueStart, valueEnd, paramStart, paramEnd, j: Integer;
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
  CPMVariadic[mi] := False;

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
      else if (p <= last) and (line[p] = '.') then
      begin
        { `...` -> variadic macro; the tail args bind to __VA_ARGS__. }
        CPMVariadic[mi] := True;
        while (p <= last) and (line[p] = '.') do Inc(p);
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
  begin
    write('C preprocessor: define #', mi, ' name=');
    for j := 0 to CPMNameLen[mi] - 1 do write(CPrepChars[CPMNameOff[mi] + j]);
    write(' value=');
    for j := 0 to CPMValueLen[mi] - 1 do write(CPrepChars[CPMValueOff[mi] + j]);
    writeln(' function=', Ord(CPMFunction[mi]));
  end;
end;

procedure CPUndef(const line: AnsiString; p, last: Integer);
var mi, a, b: Integer;
begin
  while (p <= last) and (line[p] in [' ', #9]) do Inc(p);
  a := p;
  while (p <= last) and CPIsIdentChar(line[p]) do Inc(p);
  b := p - 1;
  { Kill EVERY live entry with this name: repeated #define of the same macro
    stacks entries (newest-wins lookup), so a single tombstone would just
    re-expose the previous definition. tcc re-includes tcc.h per file, each
    pass re-defining `_tcc_error`; its `#undef _tcc_error` must clear them all
    or the real function definition gets renamed by a stale macro. }
  mi := CPFindMacro(line, a, b);
  while mi >= 0 do
  begin
    CPMNameLen[mi] := -1;
    if DebugTrace then writeln('C preprocessor: undef #', mi);
    mi := CPFindMacro(line, a, b);
  end;
end;

{ Restore macro `name` (line[nameA..nameB]) to snapshot `mi`: append a fresh
  macro entry cloning mi's value/params (newest-wins, so it becomes active), or
  tombstone the name when the snapshot was "undefined" (mi < 0). mi's value
  fields survive an intervening #undef (which only sets NameLen := -1). }
procedure CPPragmaRestore(mi: Integer; const line: AnsiString; nameA, nameB: Integer);
var ni, cur: Integer;
begin
  if mi < 0 then
  begin
    cur := CPFindMacro(line, nameA, nameB);
    if cur >= 0 then CPMNameLen[cur] := -1;
    Exit;
  end;
  if CPMCount >= MAX_CPREP_MACROS then Error('too many C macros');
  ni := CPMCount; Inc(CPMCount);
  CPMNameOff[ni]    := CPStoreRange(line, nameA, nameB);
  CPMNameLen[ni]    := nameB - nameA + 1;
  CPMValueOff[ni]   := CPMValueOff[mi];
  CPMValueLen[ni]   := CPMValueLen[mi];
  CPMFunction[ni]   := CPMFunction[mi];
  CPMVariadic[ni]   := CPMVariadic[mi];
  CPMParamBase[ni]  := CPMParamBase[mi];
  CPMParamCount[ni] := CPMParamCount[mi];
end;

{ `#pragma push_macro("NAME")` / `pop_macro("NAME")` (GCC/MSVC). Other pragmas
  are ignored. Handled at directive level (before macro expansion), so a user
  macro also named push_macro/pop_macro — c-testsuite 00206 defines both — does
  not interfere. }
procedure CPPragma(const line: AnsiString; p, last: Integer);
var a, b, nameA, nameB, mi, k, kk: Integer; isPush, isPop: Boolean;
begin
  while (p <= last) and (line[p] in [' ', #9]) do Inc(p);
  a := p;
  while (p <= last) and CPIsIdentChar(line[p]) do Inc(p);
  b := p - 1;
  isPush := CPRangeIsLiteral(line, a, b, 'push_macro');
  isPop  := CPRangeIsLiteral(line, a, b, 'pop_macro');
  if not (isPush or isPop) then Exit;
  while (p <= last) and (line[p] <> '"') do Inc(p);
  if p > last then Exit;
  Inc(p);                    { past opening quote }
  nameA := p;
  while (p <= last) and (line[p] <> '"') do Inc(p);
  nameB := p - 1;
  if nameB < nameA then Exit;
  if isPush then
  begin
    if CPPushCount > High(CPPushMi) then Error('C #pragma push_macro stack overflow');
    mi := CPFindMacro(line, nameA, nameB);
    CPPushNameOff[CPPushCount] := CPStoreRange(line, nameA, nameB);
    CPPushNameLen[CPPushCount] := nameB - nameA + 1;
    CPPushMi[CPPushCount]      := mi;
    Inc(CPPushCount);
  end
  else
  begin
    { pop the topmost stack entry for this name (per-name LIFO) }
    k := -1;
    for kk := CPPushCount - 1 downto 0 do
      if CPPoolEquals(CPPushNameOff[kk], CPPushNameLen[kk], line, nameA, nameB) then
      begin k := kk; Break; end;
    if k < 0 then Exit;      { pop without matching push — ignore }
    mi := CPPushMi[k];
    for kk := k to CPPushCount - 2 do
    begin
      CPPushNameOff[kk] := CPPushNameOff[kk + 1];
      CPPushNameLen[kk] := CPPushNameLen[kk + 1];
      CPPushMi[kk]      := CPPushMi[kk + 1];
    end;
    Dec(CPPushCount);
    CPPragmaRestore(mi, line, nameA, nameB);
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

{ Forward decls for the recursive macro expander, hoisted above CPExprAtom
  which calls them at #if-eval time. pascal26 sees these via whole-section
  forward-visibility regardless of position; FPC needs them before first use. }
procedure CPSetTempStrLength(level: Integer; len: Integer); forward;
procedure CPExpandObjectForLevel(mi, level: Integer); forward;
procedure CPExpandRangeForLevel(level: Integer; var dst: AnsiString); forward;
procedure CPExpandFunctionForLevel(mi: Integer; const src: AnsiString; argCount, level: Integer); forward;
procedure CPSetExpandedArgLength(level, len: Integer); forward;
procedure CPExpandRangeForArgLevel(level: Integer; const src: AnsiString; first, last: Integer); forward;
procedure CPAppendExpandedArgToDst(level: Integer; var dst: AnsiString); forward;

function CPExprAtom: Int64;
var a, b, mi, p, q, depth, argc, argBase, ai: Integer;
    savedText, expanded: AnsiString; savedPos, savedEnd: Integer;
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
    while (CPExprPos <= CPExprEnd) and (CPExprText[CPExprPos] in ['u','U','l','L']) do
      Inc(CPExprPos);
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
      if mi < 0 then
        Result := 0
      else if CPMFunction[mi] then
      begin
        q := CPExprPos;
        CPSkipExprSpace;
        q := CPExprPos;
        if (q <= CPExprEnd) and (CPExprText[q] = '(') then
        begin
          Inc(q);
          argc := 0;
          depth := 0;
          argBase := 16;
          if (q <= CPExprEnd) and (CPExprText[q] <> ')') then
          begin
            CPArgStart[argBase] := q;
            argc := 1;
          end;
          while (q <= CPExprEnd) and ((depth > 0) or (CPExprText[q] <> ')')) do
          begin
            if CPExprText[q] = '(' then Inc(depth)
            else if CPExprText[q] = ')' then Dec(depth)
            else if (CPExprText[q] = ',') and (depth = 0) and (argc < 16) then
            begin
              CPArgEnd[argBase + argc - 1] := q - 1;
              CPArgStart[argBase + argc] := q + 1;
              Inc(argc);
            end;
            Inc(q);
          end;
          if argc > 0 then CPArgEnd[argBase + argc - 1] := q - 1;
          for ai := 0 to argc - 1 do
          begin
            while (CPArgStart[argBase + ai] <= CPArgEnd[argBase + ai]) and
                  (CPExprText[CPArgStart[argBase + ai]] in [' ', #9]) do
              Inc(CPArgStart[argBase + ai]);
            while (CPArgEnd[argBase + ai] >= CPArgStart[argBase + ai]) and
                  (CPExprText[CPArgEnd[argBase + ai]] in [' ', #9]) do
              Dec(CPArgEnd[argBase + ai]);
          end;
          if (q <= CPExprEnd) and (CPExprText[q] = ')') then Inc(q);
          CPExprPos := q;

          if CPExprDepth >= 64 then
            Result := 0
          else
          begin
            SetLength(expanded, 0);
            CPActiveMacros[CPActiveMacroCount] := mi;
            Inc(CPActiveMacroCount);
            CPSetTempStrLength(0, 0);
            CPExpandFunctionForLevel(mi, CPExprText, argc, 0);
            CPExpandRangeForLevel(0, expanded);
            Dec(CPActiveMacroCount);

            savedText := CPExprText; savedPos := CPExprPos; savedEnd := CPExprEnd;
            CPExprText := expanded;
            CPExprPos := 1; CPExprEnd := Length(CPExprText);
            Inc(CPExprDepth);
            if CPExprEnd >= 1 then Result := CPExprOr else Result := 0;
            Dec(CPExprDepth);
            CPExprText := savedText; CPExprPos := savedPos; CPExprEnd := savedEnd;
          end;
        end
        else
          Result := 0;
      end
      else
      begin
        { Recursively EVALUATE the macro's body as a sub-expression, so a chained
          object macro (`T -> DEF -> LL -> 3`, the lua LUA_INT_TYPE/LUA_INTEGER
          pattern) and an arithmetic body both resolve — not just a literal number.
          Depth-guarded against self-referential `#define X X`. }
        if CPExprDepth >= 64 then
          Result := CPParsePoolNumber(mi)
        else
        begin
          savedText := CPExprText; savedPos := CPExprPos; savedEnd := CPExprEnd;
          CPExprText := '';
          for p := CPMValueOff[mi] to CPMValueOff[mi] + CPMValueLen[mi] - 1 do
            CPExprText := CPExprText + CPrepChars[p];
          CPExprPos := 1; CPExprEnd := Length(CPExprText);
          Inc(CPExprDepth);
          if CPExprEnd >= 1 then Result := CPExprOr else Result := 0;
          Dec(CPExprDepth);
          CPExprText := savedText; CPExprPos := savedPos; CPExprEnd := savedEnd;
        end;
      end;
    end;
  end;
end;

function CPExprUnary: Int64;
begin
  CPSkipExprSpace;
  if (CPExprPos <= CPExprEnd) and (CPExprText[CPExprPos] = '!') and
     not ((CPExprPos < CPExprEnd) and (CPExprText[CPExprPos + 1] = '=')) then
  begin
    Inc(CPExprPos);
    if CPExprUnary() = 0 then Result := 1 else Result := 0;
  end
  else if (CPExprPos <= CPExprEnd) and (CPExprText[CPExprPos] = '~') then
  begin
    Inc(CPExprPos);
    Result := not CPExprUnary();
  end
  else if (CPExprPos <= CPExprEnd) and (CPExprText[CPExprPos] = '-') then
  begin
    Inc(CPExprPos);
    Result := -CPExprUnary();
  end
  else if (CPExprPos <= CPExprEnd) and (CPExprText[CPExprPos] = '+') then
  begin
    Inc(CPExprPos);
    Result := CPExprUnary();
  end
  else
    Result := CPExprAtom;
end;

{ The C `#if` constant-expression grammar, high precedence (innermost) to low:
  unary -> * / % -> + - -> << >> -> < <= > >= -> == != -> & -> ^ -> | -> && -> ||.
  Each level parses the next-higher level then folds its own left-associative
  operators. Without the arithmetic/bitwise/shift levels, `defined(A)+defined(B)
  ==0` (sqlite's SQLITE_SYSTEM_MALLOC auto-select) and `FLAGS&MASK` / `1<<n`
  directives mis-evaluated — the trailing operators were silently dropped. }
function CPExprMul: Int64;
var v: Int64; op: Char;
begin
  Result := CPExprUnary;
  CPSkipExprSpace;
  while (CPExprPos <= CPExprEnd) and (CPExprText[CPExprPos] in ['*', '/', '%']) do
  begin
    op := CPExprText[CPExprPos];
    Inc(CPExprPos);
    v := CPExprUnary;
    if op = '*' then Result := Result * v
    else if op = '/' then begin if v <> 0 then Result := Result div v else Result := 0; end
    else begin if v <> 0 then Result := Result mod v else Result := 0; end;
    CPSkipExprSpace;
  end;
end;

function CPExprAdd: Int64;
var v: Int64; op: Char;
begin
  Result := CPExprMul;
  CPSkipExprSpace;
  { A leading-position `+`/`-` was handled by CPExprUnary; here both sides exist. }
  while (CPExprPos <= CPExprEnd) and (CPExprText[CPExprPos] in ['+', '-']) do
  begin
    op := CPExprText[CPExprPos];
    Inc(CPExprPos);
    v := CPExprMul;
    if op = '+' then Result := Result + v else Result := Result - v;
    CPSkipExprSpace;
  end;
end;

function CPExprShift: Int64;
var v: Int64; op: Char;
begin
  Result := CPExprAdd;
  CPSkipExprSpace;
  while (CPExprPos < CPExprEnd) and
        (((CPExprText[CPExprPos] = '<') and (CPExprText[CPExprPos + 1] = '<')) or
         ((CPExprText[CPExprPos] = '>') and (CPExprText[CPExprPos + 1] = '>'))) do
  begin
    op := CPExprText[CPExprPos];
    Inc(CPExprPos); Inc(CPExprPos);
    v := CPExprAdd;
    if op = '<' then Result := Result shl v else Result := Result shr v;
    CPSkipExprSpace;
  end;
end;

function CPExprRel: Int64;
var right: Int64; op1, op2: Char;
begin
  Result := CPExprShift;
  CPSkipExprSpace;
  { `<` / `<=` / `>` / `>=`, but a `<<`/`>>` belongs to the shift operand already
    consumed below us — guard against grabbing one half of it. }
  while (CPExprPos <= CPExprEnd) and (CPExprText[CPExprPos] in ['<', '>']) do
  begin
    op1 := CPExprText[CPExprPos];
    op2 := #0;
    if CPExprPos < CPExprEnd then op2 := CPExprText[CPExprPos + 1];
    if op2 = op1 then Break;        { `<<` / `>>` — not relational }
    Inc(CPExprPos);
    if op2 = '=' then Inc(CPExprPos);
    right := CPExprShift;
    if (op1 = '<') and (op2 = '=') then begin if Result <= right then Result := 1 else Result := 0; end
    else if (op1 = '>') and (op2 = '=') then begin if Result >= right then Result := 1 else Result := 0; end
    else if op1 = '<' then begin if Result < right then Result := 1 else Result := 0; end
    else begin if Result > right then Result := 1 else Result := 0; end;
    CPSkipExprSpace;
  end;
end;

function CPExprEq: Int64;
var right: Int64; op1, op2: Char;
begin
  Result := CPExprRel;
  CPSkipExprSpace;
  while (CPExprPos < CPExprEnd) and
        ((CPExprText[CPExprPos] in ['=', '!']) and (CPExprText[CPExprPos + 1] = '=')) do
  begin
    op1 := CPExprText[CPExprPos];
    op2 := CPExprText[CPExprPos + 1];
    Inc(CPExprPos); Inc(CPExprPos);
    right := CPExprRel;
    if op1 = '=' then begin if Result = right then Result := 1 else Result := 0; end
    else begin if Result <> right then Result := 1 else Result := 0; end;
    CPSkipExprSpace;
  end;
end;

function CPExprBitAnd: Int64;
var v: Int64;
begin
  Result := CPExprEq;
  CPSkipExprSpace;
  { single `&` only — `&&` belongs to the logical level above. }
  while (CPExprPos <= CPExprEnd) and (CPExprText[CPExprPos] = '&') and
        not ((CPExprPos < CPExprEnd) and (CPExprText[CPExprPos + 1] = '&')) do
  begin
    Inc(CPExprPos);
    v := CPExprEq;
    Result := Result and v;
    CPSkipExprSpace;
  end;
end;

function CPExprBitXor: Int64;
var v: Int64;
begin
  Result := CPExprBitAnd;
  CPSkipExprSpace;
  while (CPExprPos <= CPExprEnd) and (CPExprText[CPExprPos] = '^') do
  begin
    Inc(CPExprPos);
    v := CPExprBitAnd;
    Result := Result xor v;
    CPSkipExprSpace;
  end;
end;

function CPExprBitOr: Int64;
var v: Int64;
begin
  Result := CPExprBitXor;
  CPSkipExprSpace;
  { single `|` only — `||` belongs to the logical level above. }
  while (CPExprPos <= CPExprEnd) and (CPExprText[CPExprPos] = '|') and
        not ((CPExprPos < CPExprEnd) and (CPExprText[CPExprPos + 1] = '|')) do
  begin
    Inc(CPExprPos);
    v := CPExprBitXor;
    Result := Result or v;
    CPSkipExprSpace;
  end;
end;

function CPExprAnd: Int64;
var v: Int64;
begin
  Result := CPExprBitOr;
  CPSkipExprSpace;
  while (CPExprPos < CPExprEnd) and (CPExprText[CPExprPos] = '&') and
        (CPExprText[CPExprPos + 1] = '&') do
  begin
    Inc(CPExprPos); Inc(CPExprPos);
    v := CPExprBitOr;
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
  CPExprDepth := 0;
  Result := CPExprOr <> 0;
end;

procedure CPExpandRange(const src: AnsiString; first, last, level: Integer;
  var dst: AnsiString); forward;

function CPMacroIsActive(mi: Integer): Boolean;
var i: Integer;
begin
  Result := False;
  if DebugTrace then
  begin
    write('Active macros (count=', CPActiveMacroCount, '): ');
    for i := 0 to CPActiveMacroCount - 1 do
      write(CPActiveMacros[i], ' ');
    writeln;
  end;
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
var i, procIdx: Integer;
begin
  Result := -1;
  for i := 0 to CPMParamCount[mi] - 1 do
  begin
    procIdx := CPMParamBase[mi] + i;
    if CPPoolNameEquals(CPPNameOff[procIdx], CPPNameLen[procIdx], off, len) then
    begin
      Result := i;
      Exit;
    end;
  end;
end;

function CPRangeIsVaArgs(a, b: Integer): Boolean;
const VA = '__VA_ARGS__';
var i: Integer;
begin
  Result := (b - a + 1) = Length(VA);
  if not Result then Exit;
  for i := 1 to Length(VA) do
    if CPrepChars[a + i - 1] <> VA[i] then begin Result := False; Exit; end;
end;

procedure CPExpandFunction(mi: Integer; const src: AnsiString;
  argCount, level: Integer; var dst: AnsiString);
var p, last, a, b, ai, argBase, argP, k, savedSlot, q: Integer;
begin
  if DebugTrace then writeln('C preprocessor: expand function #', mi, ' level=', level);
  argBase := level * 16;
  p := CPMValueOff[mi];
  last := p + CPMValueLen[mi] - 1;
  while p <= last do
  begin
    { Token-paste operator `a ## b`: drop the `##` (and whitespace around it) so the
      left operand's last token abuts the right operand's first token. The pasted
      result is re-scanned by the caller, so `DBL_ ## n` -> `DBL_MANT_DIG` then
      expands as an object macro (lua's l_mathlim). }
    if (CPrepChars[p] = '#') and (p < last) and (CPrepChars[p + 1] = '#') then
    begin
      while (Length(dst) > 0) and (dst[Length(dst)] in [' ', #9]) do
        SetLength(dst, Length(dst) - 1);
      p := p + 2;
      while (p <= last) and (CPrepChars[p] in [' ', #9]) do Inc(p);
      { Right operand is a parameter with an EMPTY argument (C99 placemarker):
        `a ## <empty>` yields just `a`, and the NEXT body token must stay a
        SEPARATE token — emit a space so `A ## B+` with B empty gives `+ +`,
        not `++` (00202). A following `##` re-trims the space, so paste
        chains like `a##b##c` with an empty middle stay glued. }
      if (p <= last) and CPIsIdentStart(CPrepChars[p]) then
      begin
        a := p;
        q := p;
        while (q <= last) and CPIsIdentChar(CPrepChars[q]) do Inc(q);
        ai := CPParamIndex(mi, a, q - a);
        if (ai >= 0) and (ai < argCount) and
           (CPArgStart[argBase + ai] > CPArgEnd[argBase + ai]) then
        begin
          AppendChar(dst, ' ');
          p := q;
        end;
      end;
      Continue;
    end;
    { Stringize `#param` -> a string literal of the parameter's RAW (unexpanded)
      argument text, e.g. lua's `#t` for a type name. Only fires when a parameter
      name follows; a bare `#` otherwise falls through as a normal char. }
    if CPrepChars[p] = '#' then
    begin
      q := p + 1;
      while (q <= last) and (CPrepChars[q] in [' ', #9]) do Inc(q);
      a := q;
      while (q <= last) and CPIsIdentChar(CPrepChars[q]) do Inc(q);
      b := q - 1;
      if b >= a then
      begin
        ai := CPParamIndex(mi, a, b - a + 1);
        if (ai >= 0) and (ai < argCount) then
        begin
          AppendChar(dst, '"');
          for k := CPArgStart[argBase + ai] to CPArgEnd[argBase + ai] do
          begin
            if src[k] = #1 then Continue;   { strip paint markers }
            if (src[k] = '"') or (src[k] = '\') then AppendChar(dst, '\');
            AppendChar(dst, src[k]);
          end;
          AppendChar(dst, '"');
          p := q;
          Continue;
        end;
      end;
    end;
    if CPIsIdentStart(CPrepChars[p]) then
    begin
      a := p;
      while (p <= last) and CPIsIdentChar(CPrepChars[p]) do Inc(p);
      b := p - 1;
      if CPMVariadic[mi] and CPRangeIsVaArgs(a, b) then
      begin
        { __VA_ARGS__ -> the raw comma-joined tail arguments (indices
          namedCount..argCount-1). Copied raw; the caller rescans and expands. }
        if argCount > CPMParamCount[mi] then
          for k := CPArgStart[argBase + CPMParamCount[mi]] to CPArgEnd[argBase + argCount - 1] do
            AppendChar(dst, src[k]);
        Continue;
      end;
      ai := CPParamIndex(mi, a, b - a + 1);
      if (ai >= 0) and (ai < argCount) then
      begin
        CPSetExpandedArgLength(level, 0);
        { Expand this argument with the CURRENT macro (mi) de-activated: per C, a
          macro's arguments are macro-expanded outside its own replacement, so a
          nested call to the SAME macro inside an argument (lua's `check_exp`
          inside `check_exp` via `gco2ccl`) must expand. Enclosing active macros
          stay active; nested arg macros push above, leaving mi's slot intact. }
        savedSlot := -1;
        for k := CPActiveMacroCount - 1 downto 0 do
          if CPActiveMacros[k] = mi then begin savedSlot := k; CPActiveMacros[k] := -1; Break; end;
        CPExpandRangeForArgLevel(level, src, CPArgStart[argBase + ai], CPArgEnd[argBase + ai]);
        if savedSlot >= 0 then CPActiveMacros[savedSlot] := mi;
        CPAppendExpandedArgToDst(level, dst);
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

{ If object macro mi's entire body is a single identifier that names a FUNCTION
  macro, return that function macro's index (else -1). Handles aliases like
  `#define setsvalue2n setsvalue`, where `setsvalue2n(args)` must expand the
  inner function macro with the args that follow in the source. }
function CPObjectAliasFuncMacro(mi: Integer): Integer;
var off, len, i, fm: Integer;
begin
  Result := -1;
  off := CPMValueOff[mi]; len := CPMValueLen[mi];
  if (len <= 0) or (not CPIsIdentStart(CPrepChars[off])) then Exit;
  for i := 0 to len - 1 do
    if not CPIsIdentChar(CPrepChars[off + i]) then Exit;
  fm := CPFindMacroPool(off, len);
  if (fm >= 0) and CPMFunction[fm] then Result := fm;
end;

{ True iff s (after trimming trailing whitespace) ends in an identifier that
  names a FUNCTION macro; returns its index in mi. Used for the C99 6.10.3.4
  rescan where a macro's fully-expanded output ends in a function-like macro
  name and the call's '(...)' follows in the source, e.g. CAT(A,B)(x) or tcc's
  ELFW(ST_VISIBILITY)(sym->st_other). }
function CPStrTailFuncMacro(const s: AnsiString; var mi: Integer): Boolean;
var e, a: Integer;
begin
  Result := False;
  e := Length(s);
  while (e >= 1) and (s[e] in [' ', #9]) do Dec(e);
  if (e < 1) or (not CPIsIdentChar(s[e])) then Exit;
  a := e;
  while (a > 1) and CPIsIdentChar(s[a - 1]) do Dec(a);
  if not CPIsIdentStart(s[a]) then Exit;
  if (a > 1) and (s[a - 1] = #1) then Exit;   { blue-painted — not a callee }
  mi := CPFindMacro(s, a, e);
  if (mi >= 0) and CPMFunction[mi] then Result := True;
end;

{ src[start] must be '('. Returns the index just past the matching ')',
  honoring nesting and skipping string/char literals; 0 if unbalanced. }
function CPBalancedGroupEnd(const src: AnsiString; start, last: Integer): Integer;
var q, depth: Integer;
    quote: Char;
begin
  Result := 0;
  q := start;
  depth := 0;
  while q <= last do
  begin
    if (src[q] = '"') or (src[q] = '''') then
    begin
      quote := src[q];
      Inc(q);
      while (q <= last) and (src[q] <> quote) do
      begin
        if (src[q] = '\') and (q < last) then Inc(q);
        Inc(q);
      end;
      Inc(q);
    end
    else
    begin
      if src[q] = '(' then Inc(depth)
      else if src[q] = ')' then
      begin
        Dec(depth);
        if depth = 0 then
        begin
          Result := q + 1;
          Exit;
        end;
      end;
      Inc(q);
    end;
  end;
end;

procedure CPExpandRange(const src: AnsiString; first, last, level: Integer;
  var dst: AnsiString);
var
  p, a, b, mi, q, depth, argc, argBase, ai, innerMi: Integer;
  q2, grpEnd, tailMi: Integer;
  expanded, combined: AnsiString;
  quote: Char;
  quotedDone: Boolean;
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
    else if src[p] = #1 then
    begin
      { Blue-paint marker: the identifier that follows was produced by its own
        macro's expansion (C 6.10.3.4 non-replacement) — copy verbatim, never
        re-expand. Without this, `#define x s1->x` re-expands on every rescan
        of an enclosing macro's output (tcc's section shorthands gave
        `s1->s1->x`). The marker survives rescans; the C lexer skips it. }
      AppendChar(dst, src[p]);
      Inc(p);
      while (p <= last) and CPIsIdentChar(src[p]) do
      begin
        AppendChar(dst, src[p]);
        Inc(p);
      end;
    end
    else if CPIsIdentStart(src[p]) then
    begin
      a := p;
      while (p <= last) and CPIsIdentChar(src[p]) do Inc(p);
      b := p - 1;
      mi := CPFindMacro(src, a, b);
      { Object-macro alias of a function macro `#define A FUNC` used as `A(args)`:
        redirect to FUNC so the function-macro path below pulls the args that
        follow in the source (lua's setsvalue2n / setobj2n). }
      if (mi >= 0) and (not CPMFunction[mi]) then
      begin
        innerMi := CPObjectAliasFuncMacro(mi);
        if innerMi >= 0 then
        begin
          q := p;
          while (q <= last) and (src[q] in [' ', #9]) do Inc(q);
          if (q <= last) and (src[q] = '(') then mi := innerMi;
        end;
      end;
      if (mi < 0) then
        CPAppendRange(dst, src, a, b)
      else if not CPMFunction[mi] then
      begin
        if CPMacroIsActive(mi) then
        begin
          AppendChar(dst, #1);   { paint: never re-expand on later rescans }
          CPAppendRange(dst, src, a, b);
        end
        else
        begin
          CPActiveMacros[CPActiveMacroCount] := mi;
          Inc(CPActiveMacroCount);
          
          CPSetTempStrLength(level, 0);
          CPExpandObjectForLevel(mi, level);
          CPExpandRangeForLevel(level, dst);
          
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
          { Trim leading/trailing whitespace of each argument (standard C), so a
            spaced call like `CAT(1, 7)` pastes `17`, not `1 7`. }
          for ai := 0 to argc - 1 do
          begin
            while (CPArgStart[argBase + ai] <= CPArgEnd[argBase + ai]) and
                  (src[CPArgStart[argBase + ai]] in [' ', #9]) do
              Inc(CPArgStart[argBase + ai]);
            while (CPArgEnd[argBase + ai] >= CPArgStart[argBase + ai]) and
                  (src[CPArgEnd[argBase + ai]] in [' ', #9]) do
              Dec(CPArgEnd[argBase + ai]);
          end;

          if CPMacroIsActive(mi) then
          begin
            AppendChar(dst, #1);   { paint the name; args copy as-is }
            CPAppendRange(dst, src, a, q);
          end
          else
          begin
            CPActiveMacros[CPActiveMacroCount] := mi;
            Inc(CPActiveMacroCount);

            CPSetTempStrLength(level, 0);
            CPExpandFunctionForLevel(mi, src, argc, level);
            expanded := '';
            CPExpandRangeForLevel(level, expanded);

            Dec(CPActiveMacroCount);
            { C99 6.10.3.4 rescan across the expansion boundary: if the FULLY
              expanded output ends in a function-like macro name and the next
              source token is '(', the trailing '(...)' belongs to that macro —
              splice and re-expand (CAT(A,B)(x) -> AB(x) -> 42; tcc's ELFW).
              mi is popped above so the trailing rescan is not blue-painted by
              the macro that produced the name. }
            q2 := q;
            if (q2 <= last) and (src[q2] = ')') then Inc(q2);
            while (q2 <= last) and (src[q2] in [' ', #9]) do Inc(q2);
            grpEnd := 0;
            if (q2 <= last) and (src[q2] = '(') and
               CPStrTailFuncMacro(expanded, tailMi) and
               (not CPMacroIsActive(tailMi)) then
              grpEnd := CPBalancedGroupEnd(src, q2, last);
            if grpEnd > 0 then
            begin
              combined := expanded + Copy(src, q2, grpEnd - q2);
              CPExpandRange(combined, 1, Length(combined), level + 1, dst);
              q := grpEnd - 1; { at the group's ')'; consumed below }
            end
            else
              dst := dst + expanded;
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

procedure CPSetTempStrLength(level: Integer; len: Integer);
begin
  case level of
    0: SetLength(CPTempStr0, len);
    1: SetLength(CPTempStr1, len);
    2: SetLength(CPTempStr2, len);
    3: SetLength(CPTempStr3, len);
    4: SetLength(CPTempStr4, len);
    5: SetLength(CPTempStr5, len);
    6: SetLength(CPTempStr6, len);
    7: SetLength(CPTempStr7, len);
    8: SetLength(CPTempStr8, len);
    9: SetLength(CPTempStr9, len);
    10: SetLength(CPTempStr10, len);
    11: SetLength(CPTempStr11, len);
    12: SetLength(CPTempStr12, len);
    13: SetLength(CPTempStr13, len);
    14: SetLength(CPTempStr14, len);
    15: SetLength(CPTempStr15, len);
    16: SetLength(CPTempStr16, len);
    17: SetLength(CPTempStr17, len);
    18: SetLength(CPTempStr18, len);
    19: SetLength(CPTempStr19, len);
    20: SetLength(CPTempStr20, len);
    21: SetLength(CPTempStr21, len);
    22: SetLength(CPTempStr22, len);
    23: SetLength(CPTempStr23, len);
    24: SetLength(CPTempStr24, len);
    25: SetLength(CPTempStr25, len);
    26: SetLength(CPTempStr26, len);
    27: SetLength(CPTempStr27, len);
    28: SetLength(CPTempStr28, len);
    29: SetLength(CPTempStr29, len);
    30: SetLength(CPTempStr30, len);
    31: SetLength(CPTempStr31, len);
    32: SetLength(CPTempStr32, len);
  end;
end;

procedure CPExpandObjectForLevel(mi, level: Integer);
begin
  case level of
    0: CPExpandObject(mi, level + 1, CPTempStr0);
    1: CPExpandObject(mi, level + 1, CPTempStr1);
    2: CPExpandObject(mi, level + 1, CPTempStr2);
    3: CPExpandObject(mi, level + 1, CPTempStr3);
    4: CPExpandObject(mi, level + 1, CPTempStr4);
    5: CPExpandObject(mi, level + 1, CPTempStr5);
    6: CPExpandObject(mi, level + 1, CPTempStr6);
    7: CPExpandObject(mi, level + 1, CPTempStr7);
    8: CPExpandObject(mi, level + 1, CPTempStr8);
    9: CPExpandObject(mi, level + 1, CPTempStr9);
    10: CPExpandObject(mi, level + 1, CPTempStr10);
    11: CPExpandObject(mi, level + 1, CPTempStr11);
    12: CPExpandObject(mi, level + 1, CPTempStr12);
    13: CPExpandObject(mi, level + 1, CPTempStr13);
    14: CPExpandObject(mi, level + 1, CPTempStr14);
    15: CPExpandObject(mi, level + 1, CPTempStr15);
    16: CPExpandObject(mi, level + 1, CPTempStr16);
    17: CPExpandObject(mi, level + 1, CPTempStr17);
    18: CPExpandObject(mi, level + 1, CPTempStr18);
    19: CPExpandObject(mi, level + 1, CPTempStr19);
    20: CPExpandObject(mi, level + 1, CPTempStr20);
    21: CPExpandObject(mi, level + 1, CPTempStr21);
    22: CPExpandObject(mi, level + 1, CPTempStr22);
    23: CPExpandObject(mi, level + 1, CPTempStr23);
    24: CPExpandObject(mi, level + 1, CPTempStr24);
    25: CPExpandObject(mi, level + 1, CPTempStr25);
    26: CPExpandObject(mi, level + 1, CPTempStr26);
    27: CPExpandObject(mi, level + 1, CPTempStr27);
    28: CPExpandObject(mi, level + 1, CPTempStr28);
    29: CPExpandObject(mi, level + 1, CPTempStr29);
    30: CPExpandObject(mi, level + 1, CPTempStr30);
    31: CPExpandObject(mi, level + 1, CPTempStr31);
    32: CPExpandObject(mi, level + 1, CPTempStr32);
  end;
end;

procedure CPExpandRangeForLevel(level: Integer; var dst: AnsiString);
begin
  case level of
    0: CPExpandRange(CPTempStr0, 1, Length(CPTempStr0), level + 1, dst);
    1: CPExpandRange(CPTempStr1, 1, Length(CPTempStr1), level + 1, dst);
    2: CPExpandRange(CPTempStr2, 1, Length(CPTempStr2), level + 1, dst);
    3: CPExpandRange(CPTempStr3, 1, Length(CPTempStr3), level + 1, dst);
    4: CPExpandRange(CPTempStr4, 1, Length(CPTempStr4), level + 1, dst);
    5: CPExpandRange(CPTempStr5, 1, Length(CPTempStr5), level + 1, dst);
    6: CPExpandRange(CPTempStr6, 1, Length(CPTempStr6), level + 1, dst);
    7: CPExpandRange(CPTempStr7, 1, Length(CPTempStr7), level + 1, dst);
    8: CPExpandRange(CPTempStr8, 1, Length(CPTempStr8), level + 1, dst);
    9: CPExpandRange(CPTempStr9, 1, Length(CPTempStr9), level + 1, dst);
    10: CPExpandRange(CPTempStr10, 1, Length(CPTempStr10), level + 1, dst);
    11: CPExpandRange(CPTempStr11, 1, Length(CPTempStr11), level + 1, dst);
    12: CPExpandRange(CPTempStr12, 1, Length(CPTempStr12), level + 1, dst);
    13: CPExpandRange(CPTempStr13, 1, Length(CPTempStr13), level + 1, dst);
    14: CPExpandRange(CPTempStr14, 1, Length(CPTempStr14), level + 1, dst);
    15: CPExpandRange(CPTempStr15, 1, Length(CPTempStr15), level + 1, dst);
    16: CPExpandRange(CPTempStr16, 1, Length(CPTempStr16), level + 1, dst);
    17: CPExpandRange(CPTempStr17, 1, Length(CPTempStr17), level + 1, dst);
    18: CPExpandRange(CPTempStr18, 1, Length(CPTempStr18), level + 1, dst);
    19: CPExpandRange(CPTempStr19, 1, Length(CPTempStr19), level + 1, dst);
    20: CPExpandRange(CPTempStr20, 1, Length(CPTempStr20), level + 1, dst);
    21: CPExpandRange(CPTempStr21, 1, Length(CPTempStr21), level + 1, dst);
    22: CPExpandRange(CPTempStr22, 1, Length(CPTempStr22), level + 1, dst);
    23: CPExpandRange(CPTempStr23, 1, Length(CPTempStr23), level + 1, dst);
    24: CPExpandRange(CPTempStr24, 1, Length(CPTempStr24), level + 1, dst);
    25: CPExpandRange(CPTempStr25, 1, Length(CPTempStr25), level + 1, dst);
    26: CPExpandRange(CPTempStr26, 1, Length(CPTempStr26), level + 1, dst);
    27: CPExpandRange(CPTempStr27, 1, Length(CPTempStr27), level + 1, dst);
    28: CPExpandRange(CPTempStr28, 1, Length(CPTempStr28), level + 1, dst);
    29: CPExpandRange(CPTempStr29, 1, Length(CPTempStr29), level + 1, dst);
    30: CPExpandRange(CPTempStr30, 1, Length(CPTempStr30), level + 1, dst);
    31: CPExpandRange(CPTempStr31, 1, Length(CPTempStr31), level + 1, dst);
    32: CPExpandRange(CPTempStr32, 1, Length(CPTempStr32), level + 1, dst);
  end;
end;

procedure CPExpandFunctionForLevel(mi: Integer; const src: AnsiString; argCount, level: Integer);
begin
  case level of
    0: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr0);
    1: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr1);
    2: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr2);
    3: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr3);
    4: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr4);
    5: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr5);
    6: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr6);
    7: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr7);
    8: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr8);
    9: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr9);
    10: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr10);
    11: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr11);
    12: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr12);
    13: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr13);
    14: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr14);
    15: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr15);
    16: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr16);
    17: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr17);
    18: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr18);
    19: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr19);
    20: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr20);
    21: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr21);
    22: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr22);
    23: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr23);
    24: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr24);
    25: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr25);
    26: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr26);
    27: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr27);
    28: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr28);
    29: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr29);
    30: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr30);
    31: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr31);
    32: CPExpandFunction(mi, src, argCount, level + 1, CPTempStr32);
  end;
end;

procedure CPSetExpandedArgLength(level, len: Integer);
begin
  case level of
    0: SetLength(CPExpandedArg0, len);
    1: SetLength(CPExpandedArg1, len);
    2: SetLength(CPExpandedArg2, len);
    3: SetLength(CPExpandedArg3, len);
    4: SetLength(CPExpandedArg4, len);
    5: SetLength(CPExpandedArg5, len);
    6: SetLength(CPExpandedArg6, len);
    7: SetLength(CPExpandedArg7, len);
    8: SetLength(CPExpandedArg8, len);
    9: SetLength(CPExpandedArg9, len);
    10: SetLength(CPExpandedArg10, len);
    11: SetLength(CPExpandedArg11, len);
    12: SetLength(CPExpandedArg12, len);
    13: SetLength(CPExpandedArg13, len);
    14: SetLength(CPExpandedArg14, len);
    15: SetLength(CPExpandedArg15, len);
    16: SetLength(CPExpandedArg16, len);
    17: SetLength(CPExpandedArg17, len);
    18: SetLength(CPExpandedArg18, len);
    19: SetLength(CPExpandedArg19, len);
    20: SetLength(CPExpandedArg20, len);
    21: SetLength(CPExpandedArg21, len);
    22: SetLength(CPExpandedArg22, len);
    23: SetLength(CPExpandedArg23, len);
    24: SetLength(CPExpandedArg24, len);
    25: SetLength(CPExpandedArg25, len);
    26: SetLength(CPExpandedArg26, len);
    27: SetLength(CPExpandedArg27, len);
    28: SetLength(CPExpandedArg28, len);
    29: SetLength(CPExpandedArg29, len);
    30: SetLength(CPExpandedArg30, len);
    31: SetLength(CPExpandedArg31, len);
    32: SetLength(CPExpandedArg32, len);
  end;
end;

procedure CPExpandRangeForArgLevel(level: Integer; const src: AnsiString; first, last: Integer);
begin
  case level of
    0: CPExpandRange(src, first, last, level + 1, CPExpandedArg0);
    1: CPExpandRange(src, first, last, level + 1, CPExpandedArg1);
    2: CPExpandRange(src, first, last, level + 1, CPExpandedArg2);
    3: CPExpandRange(src, first, last, level + 1, CPExpandedArg3);
    4: CPExpandRange(src, first, last, level + 1, CPExpandedArg4);
    5: CPExpandRange(src, first, last, level + 1, CPExpandedArg5);
    6: CPExpandRange(src, first, last, level + 1, CPExpandedArg6);
    7: CPExpandRange(src, first, last, level + 1, CPExpandedArg7);
    8: CPExpandRange(src, first, last, level + 1, CPExpandedArg8);
    9: CPExpandRange(src, first, last, level + 1, CPExpandedArg9);
    10: CPExpandRange(src, first, last, level + 1, CPExpandedArg10);
    11: CPExpandRange(src, first, last, level + 1, CPExpandedArg11);
    12: CPExpandRange(src, first, last, level + 1, CPExpandedArg12);
    13: CPExpandRange(src, first, last, level + 1, CPExpandedArg13);
    14: CPExpandRange(src, first, last, level + 1, CPExpandedArg14);
    15: CPExpandRange(src, first, last, level + 1, CPExpandedArg15);
    16: CPExpandRange(src, first, last, level + 1, CPExpandedArg16);
    17: CPExpandRange(src, first, last, level + 1, CPExpandedArg17);
    18: CPExpandRange(src, first, last, level + 1, CPExpandedArg18);
    19: CPExpandRange(src, first, last, level + 1, CPExpandedArg19);
    20: CPExpandRange(src, first, last, level + 1, CPExpandedArg20);
    21: CPExpandRange(src, first, last, level + 1, CPExpandedArg21);
    22: CPExpandRange(src, first, last, level + 1, CPExpandedArg22);
    23: CPExpandRange(src, first, last, level + 1, CPExpandedArg23);
    24: CPExpandRange(src, first, last, level + 1, CPExpandedArg24);
    25: CPExpandRange(src, first, last, level + 1, CPExpandedArg25);
    26: CPExpandRange(src, first, last, level + 1, CPExpandedArg26);
    27: CPExpandRange(src, first, last, level + 1, CPExpandedArg27);
    28: CPExpandRange(src, first, last, level + 1, CPExpandedArg28);
    29: CPExpandRange(src, first, last, level + 1, CPExpandedArg29);
    30: CPExpandRange(src, first, last, level + 1, CPExpandedArg30);
    31: CPExpandRange(src, first, last, level + 1, CPExpandedArg31);
    32: CPExpandRange(src, first, last, level + 1, CPExpandedArg32);
  end;
end;

procedure CPAppendExpandedArgToDst(level: Integer; var dst: AnsiString);
var argP: Integer;
begin
  case level of
    0: for argP := 1 to Length(CPExpandedArg0) do AppendChar(dst, CPExpandedArg0[argP]);
    1: for argP := 1 to Length(CPExpandedArg1) do AppendChar(dst, CPExpandedArg1[argP]);
    2: for argP := 1 to Length(CPExpandedArg2) do AppendChar(dst, CPExpandedArg2[argP]);
    3: for argP := 1 to Length(CPExpandedArg3) do AppendChar(dst, CPExpandedArg3[argP]);
    4: for argP := 1 to Length(CPExpandedArg4) do AppendChar(dst, CPExpandedArg4[argP]);
    5: for argP := 1 to Length(CPExpandedArg5) do AppendChar(dst, CPExpandedArg5[argP]);
    6: for argP := 1 to Length(CPExpandedArg6) do AppendChar(dst, CPExpandedArg6[argP]);
    7: for argP := 1 to Length(CPExpandedArg7) do AppendChar(dst, CPExpandedArg7[argP]);
    8: for argP := 1 to Length(CPExpandedArg8) do AppendChar(dst, CPExpandedArg8[argP]);
    9: for argP := 1 to Length(CPExpandedArg9) do AppendChar(dst, CPExpandedArg9[argP]);
    10: for argP := 1 to Length(CPExpandedArg10) do AppendChar(dst, CPExpandedArg10[argP]);
    11: for argP := 1 to Length(CPExpandedArg11) do AppendChar(dst, CPExpandedArg11[argP]);
    12: for argP := 1 to Length(CPExpandedArg12) do AppendChar(dst, CPExpandedArg12[argP]);
    13: for argP := 1 to Length(CPExpandedArg13) do AppendChar(dst, CPExpandedArg13[argP]);
    14: for argP := 1 to Length(CPExpandedArg14) do AppendChar(dst, CPExpandedArg14[argP]);
    15: for argP := 1 to Length(CPExpandedArg15) do AppendChar(dst, CPExpandedArg15[argP]);
    16: for argP := 1 to Length(CPExpandedArg16) do AppendChar(dst, CPExpandedArg16[argP]);
    17: for argP := 1 to Length(CPExpandedArg17) do AppendChar(dst, CPExpandedArg17[argP]);
    18: for argP := 1 to Length(CPExpandedArg18) do AppendChar(dst, CPExpandedArg18[argP]);
    19: for argP := 1 to Length(CPExpandedArg19) do AppendChar(dst, CPExpandedArg19[argP]);
    20: for argP := 1 to Length(CPExpandedArg20) do AppendChar(dst, CPExpandedArg20[argP]);
    21: for argP := 1 to Length(CPExpandedArg21) do AppendChar(dst, CPExpandedArg21[argP]);
    22: for argP := 1 to Length(CPExpandedArg22) do AppendChar(dst, CPExpandedArg22[argP]);
    23: for argP := 1 to Length(CPExpandedArg23) do AppendChar(dst, CPExpandedArg23[argP]);
    24: for argP := 1 to Length(CPExpandedArg24) do AppendChar(dst, CPExpandedArg24[argP]);
    25: for argP := 1 to Length(CPExpandedArg25) do AppendChar(dst, CPExpandedArg25[argP]);
    26: for argP := 1 to Length(CPExpandedArg26) do AppendChar(dst, CPExpandedArg26[argP]);
    27: for argP := 1 to Length(CPExpandedArg27) do AppendChar(dst, CPExpandedArg27[argP]);
    28: for argP := 1 to Length(CPExpandedArg28) do AppendChar(dst, CPExpandedArg28[argP]);
    29: for argP := 1 to Length(CPExpandedArg29) do AppendChar(dst, CPExpandedArg29[argP]);
    30: for argP := 1 to Length(CPExpandedArg30) do AppendChar(dst, CPExpandedArg30[argP]);
    31: for argP := 1 to Length(CPExpandedArg31) do AppendChar(dst, CPExpandedArg31[argP]);
    32: for argP := 1 to Length(CPExpandedArg32) do AppendChar(dst, CPExpandedArg32[argP]);
  end;
end;

procedure CPReadLine(const src: AnsiString; var pos: Integer;
  var inComment: Boolean; var line: AnsiString);
var inString, inChar, done: Boolean; c: Char; wln, wk: Integer;
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
      else if (c = '/') and (pos < Length(src)) and (src[pos + 1] = '*') then
      begin
        { -Wcomment (gcc/clang): a `/*` inside a block comment is a likely
          mistake — C comments do not nest, so it is ignored. Warn at the
          physical line (counted up to here; only on the rare hit). }
        wln := 1;
        for wk := 1 to pos - 1 do if src[wk] = #10 then Inc(wln);
        writeln('pascal26:', wln, ': warning: "/*" within comment');
        Inc(pos); Inc(pos);
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

{ Register a `-I` C include search root. Normalised to a trailing '/'. }
procedure AddCIncludeDir(const dir: AnsiString);
var s: AnsiString; j: Integer;
begin
  if CIncludeDirCount >= MAX_C_INCLUDE_DIRS then Error('too many -I include directories');
  s := '';
  for j := 1 to Length(dir) do AppendChar(s, dir[j]);
  if (Length(s) > 0) and (s[Length(s)] <> '/') then AppendChar(s, '/');
  CIncludeDirs[CIncludeDirCount] := s;
  Inc(CIncludeDirCount);
end;

{ Auto-register pxx's own C headers (lib/crtl/include) as a default `<>` search
  root, like a real C compiler searching its own freestanding/hosted headers.
  Anchored to the compiler binary (ExeDir = <root>/compiler/) so it resolves
  regardless of CWD; falls back CWD-relative when ExeDir is empty (bare name).
  These map <stdarg.h> etc to pxx's __builtin_va_* helpers — without them the
  /usr/include fallback grabs host headers with the wrong ABI. Appended AFTER
  user -I roots (registered at option-parse time), so -I still wins. Suppressed
  by -nostdinc. }
procedure AddDefaultCIncludeDirs;
var d: AnsiString;
begin
  if NoStdInc then Exit;
  { ExeDir-anchored (installed/normal: ExeDir = <root>/compiler/) ... }
  if ExeDir <> '' then
  begin
    ConcatThree(ExeDir, '../lib/crtl/include/', '', d);
    AddCIncludeDir(d);
  end;
  { ... and CWD-relative (run from repo root), like the Pascal PAL dir auto-add.
    Both are appended after user -I, so -I still wins; harmless if absent. }
  AddCIncludeDir('lib/crtl/include/');
end;

{ Register a Pascal-unit (`uses`) search root (`-Fu`, also fed by `-I`).
  Normalised to a trailing '/'. Deduped so `-I` + `-Fu` of the same dir, or a
  repeated flag, do not bloat the list. }
procedure AddPasUnitDir(const dir: AnsiString);
var s: AnsiString; j: Integer;
begin
  s := '';
  for j := 1 to Length(dir) do AppendChar(s, dir[j]);
  if (Length(s) > 0) and (s[Length(s)] <> '/') then AppendChar(s, '/');
  for j := 0 to PasUnitDirCount - 1 do
    if PasUnitDirs[j] = s then Exit;
  if PasUnitDirCount >= MAX_PAS_UNIT_DIRS then Error('too many -Fu/-I unit directories');
  PasUnitDirs[PasUnitDirCount] := s;
  Inc(PasUnitDirCount);
end;

{ 1-based index of the first occurrence of `sub` in `s`, else 0. }
function CPFindSub(const s, sub: AnsiString): Integer;
var i, j, n, m: Integer; ok: Boolean;
begin
  Result := 0;
  n := Length(s); m := Length(sub);
  if (m = 0) or (m > n) then Exit;
  for i := 1 to n - m + 1 do
  begin
    ok := True;
    for j := 1 to m do
      if s[i + j - 1] <> sub[j] then begin ok := False; Break; end;
    if ok then begin Result := i; Exit; end;
  end;
end;

{ If `hdr` is a crtl include header (path contains `crtl/include/` and ends
  `.h`), build the sibling impl path `crtl/src/<name>.c` into `src` and return
  True. The auto-pull "link" target — see CrtlSrcPulled in defs.inc. }
function CPCrtlSrcOf(const hdr: AnsiString; var src: AnsiString): Boolean;
var idx, i, n: Integer;
begin
  Result := False;
  src := '';
  n := Length(hdr);
  if (n < 2) or (hdr[n] <> 'h') or (hdr[n-1] <> '.') then Exit;
  idx := CPFindSub(hdr, 'crtl/include/');
  if idx = 0 then Exit;
  { prefix up to (not including) 'crtl/include/' }
  for i := 1 to idx - 1 do AppendChar(src, hdr[i]);
  AppendString(src, 'crtl/src/');
  { the part after 'crtl/include/', with the trailing '.h' rewritten to '.c' }
  for i := idx + 13 to n - 1 do AppendChar(src, hdr[i]);   { 13 = Length('crtl/include/') }
  AppendChar(src, 'c');
  Result := True;
end;

{ Extract the crtl header module name (`math`, `sys/socket`, ...), without .h. }
function CPCrtlHeaderName(const hdr: AnsiString; var name: AnsiString): Boolean;
var idx, i, n: Integer;
begin
  Result := False;
  name := '';
  n := Length(hdr);
  if (n < 2) or (hdr[n] <> 'h') or (hdr[n-1] <> '.') then Exit;
  idx := CPFindSub(hdr, 'crtl/include/');
  if idx = 0 then Exit;
  for i := idx + 13 to n - 2 do AppendChar(name, hdr[i]);
  Result := Length(name) > 0;
end;

{ True if `path` is a crtl impl source (`.../crtl/src/<name>.c`). Such a file is
  pulled at most once per compile whether reached by the auto-pull or by an
  explicit `#include "...c"` (a unity build like lua's runner.c), so the two
  never double-define the same functions. }
function CPIsCrtlSrcPath(const path: AnsiString): Boolean;
var n: Integer;
begin
  n := Length(path);
  Result := (n >= 2) and (path[n] = 'c') and (path[n-1] = '.') and
            (CPFindSub(path, 'crtl/src/') > 0);
end;

{ True if this crtl impl path was already pulled in this compile. }
function CPCrtlSrcPulled(const src: AnsiString): Boolean;
var i: Integer;
begin
  Result := False;
  for i := 0 to CrtlSrcPulledCount - 1 do
    if CrtlSrcPulled[i] = src then begin Result := True; Exit; end;
end;

{ Record a crtl impl path as pulled (dedup register). }
procedure CPMarkCrtlSrcPulled(const src: AnsiString);
begin
  if CrtlSrcPulledCount < MAX_C_INCLUDE_DIRS then
  begin
    CrtlSrcPulled[CrtlSrcPulledCount] := src;
    Inc(CrtlSrcPulledCount);
  end;
end;

{ After a crtl `<header>` is processed, auto-pull its sibling `src/<name>.c`
  impl once (the missing link step). `depth`/`hdrPath` are the just-processed
  header's include slot and resolved path; the impl reuses the same depth slot
  (the header's buffer is already consumed). No-op under --system-libs, when the
  header is not a crtl header, when the impl file is absent, or when already
  pulled. The impl's own `#include <name.h>` re-resolves the header (guarded,
  empty) and finds the impl already pulled, so there is no recursion. }
procedure CPAutoPullCrtlImpl(depth: Integer; const hdrPath: AnsiString);
var src, srcDir, hdrName: AnsiString;
begin
  if CPCrtlHeaderName(hdrPath, hdrName) and CHeaderUsesSystemLib(hdrName) then Exit;
  if not CPCrtlSrcOf(hdrPath, src) then Exit;
  if CPCrtlSrcPulled(src) then Exit;
  CPrepPath := src;
  CPLoadInclude(depth);
  if CPIncludeLength(depth) = 0 then Exit;   { no sibling impl — pure-header module }
  CPMarkCrtlSrcPulled(src);
  if DebugTrace then writeln('C preprocessor: auto-pull crtl impl ', src);
  srcDir := GetFilePath(src);
  CPProcessInclude(depth, srcDir);
end;

procedure CPInclude(const line: AnsiString; p, last, depth: Integer;
  const baseDir: AnsiString);
var a, b, k: Integer; hdrResolved, incName, searchList: AnsiString;
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
    { 1. The including file's own directory (baseDir is threaded as the resolved
         dir of each nested include via CPProcessInclude below). }
    CPConcat2(baseDir, '', CPrepPath);
    CPAppendRange(CPrepPath, line, a, p - 1);
    CPLoadInclude(depth);
    { 2. User `-I` project/library roots, in order — these win over any system
         header so a project's own header (e.g. our zlib.h) is not shadowed. }
    k := 0;
    while (CPIncludeLength(depth) = 0) and (k < CIncludeDirCount) do
    begin
      CPConcat2(CIncludeDirs[k], '', CPrepPath);
      CPAppendRange(CPrepPath, line, a, p - 1);
      CPLoadInclude(depth);
      Inc(k);
    end;
    { 3. Host system fallbacks. Only for a native (x86_64) build, and only when
         -nostdinc is not set: these are the host's headers, wrong for any cross
         target — our libraries are meant to be cross-platform and must resolve
         from project/-I roots or pxx's own crtl headers, not /usr. -nostdinc
         disables both this fallback and the default crtl search. }
    if (CPIncludeLength(depth) = 0) and (TargetArch = TARGET_X86_64) and (not NoStdInc) then
    begin
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
      CPAppendRange(CPrepPath, '/usr/include/gtk-2.0/', 1, 21);
      CPAppendRange(CPrepPath, line, a, p - 1);
      CPLoadInclude(depth);
    end;
    if CPIncludeLength(depth) = 0 then
    begin
      SetLength(CPrepPath, 0);
      CPAppendRange(CPrepPath, '/usr/lib/x86_64-linux-gnu/gtk-2.0/include/', 1, 42);
      CPAppendRange(CPrepPath, line, a, p - 1);
      CPLoadInclude(depth);
    end;
    if CPIncludeLength(depth) = 0 then
    begin
      SetLength(CPrepPath, 0);
      CPAppendRange(CPrepPath, '/usr/include/glib-2.0/', 1, 22);
      CPAppendRange(CPrepPath, line, a, p - 1);
      CPLoadInclude(depth);
    end;
    if CPIncludeLength(depth) = 0 then
    begin
      SetLength(CPrepPath, 0);
      CPAppendRange(CPrepPath, '/usr/lib/x86_64-linux-gnu/glib-2.0/include/', 1, 43);
      CPAppendRange(CPrepPath, line, a, p - 1);
      CPLoadInclude(depth);
    end;
    if CPIncludeLength(depth) = 0 then
    begin
      SetLength(CPrepPath, 0);
      CPAppendRange(CPrepPath, '/usr/include/pango-1.0/', 1, 23);
      CPAppendRange(CPrepPath, line, a, p - 1);
      CPLoadInclude(depth);
    end;
    if CPIncludeLength(depth) = 0 then
    begin
      SetLength(CPrepPath, 0);
      CPAppendRange(CPrepPath, '/usr/include/cairo/', 1, 19);
      CPAppendRange(CPrepPath, line, a, p - 1);
      CPLoadInclude(depth);
    end;
    if CPIncludeLength(depth) = 0 then
    begin
      SetLength(CPrepPath, 0);
      CPAppendRange(CPrepPath, '/usr/include/gdk-pixbuf-2.0/', 1, 28);
      CPAppendRange(CPrepPath, line, a, p - 1);
      CPLoadInclude(depth);
    end;
    if CPIncludeLength(depth) = 0 then
    begin
      SetLength(CPrepPath, 0);
      CPAppendRange(CPrepPath, '/usr/include/atk-1.0/', 1, 21);
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
      CPAppendRange(CPrepPath, '/usr/include/harfbuzz/', 1, 22);
      CPAppendRange(CPrepPath, line, a, p - 1);
      CPLoadInclude(depth);
    end;
    if CPIncludeLength(depth) = 0 then
    begin
      SetLength(CPrepPath, 0);
      CPAppendRange(CPrepPath, '/usr/include/freetype2/', 1, 23);
      CPAppendRange(CPrepPath, line, a, p - 1);
      CPLoadInclude(depth);
    end;
    if CPIncludeLength(depth) = 0 then
    begin
      SetLength(CPrepPath, 0);
      CPAppendRange(CPrepPath, '/usr/include/pixman-1/', 1, 22);
      CPAppendRange(CPrepPath, line, a, p - 1);
      CPLoadInclude(depth);
    end;
    if CPIncludeLength(depth) = 0 then
    begin
      SetLength(CPrepPath, 0);
      CPAppendRange(CPrepPath, '/usr/include/fontconfig/', 1, 24);
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
    end;  { native (x86_64) system-fallback block }
    if CPIncludeLength(depth) = 0 then
    begin
      { Report the requested NAME and the search list, not the last dir probed
        (which pointed triage at the wrong place — bug-cpp-include-not-found-
        diagnostic-path). }
      incName := '';
      for k := a to p - 1 do incName := incName + line[k];
      searchList := '';
      if baseDir <> '' then searchList := baseDir;
      for k := 0 to CIncludeDirCount - 1 do
      begin
        if searchList <> '' then searchList := searchList + ', ';
        searchList := searchList + CIncludeDirs[k];
      end;
      if (TargetArch = TARGET_X86_64) and (not NoStdInc) then
      begin
        if searchList <> '' then searchList := searchList + ', ';
        searchList := searchList + '<host system dirs>';
      end;
      ErrorIdent := 'searched: ' + searchList;
      Error('C include file not found: "' + incName + '"');
    end;
    if DebugTrace then writeln('C preprocessor: include ', CPrepPath);
    hdrResolved := CPrepPath;   { capture before CPProcessInclude / the auto-pull mutate CPrepPath }
    if CPIsCrtlSrcPath(CPrepPath) then
    begin
      { An explicit `#include "...c"` of a crtl impl (a unity build like lua's
        runner.c). Process it once and record it, so a later `<header>` auto-pull
        does not include the same impl again and double-define its functions. }
      if not CPCrtlSrcPulled(CPrepPath) then
      begin
        CPMarkCrtlSrcPulled(CPrepPath);
        CPProcessInclude(depth, GetFilePath(CPrepPath));
      end;
    end
    else
    begin
      CPProcessInclude(depth, GetFilePath(CPrepPath));
      { pxx has no link step: a crtl `<header>` also pulls its libc-free impl. }
      CPAutoPullCrtlImpl(depth, hdrResolved);
    end;
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
    CPInclude(line, p, last, depth, baseDir)
  else if CPActive and CPRangeIsLiteral(line, a, b, 'pragma') then
    CPPragma(line, p, last);
end;

{ Net parenthesis depth of a line, ignoring `"..."` / `'...'` literals. Used to
  detect a (function-macro) call whose arguments continue on the next line. }
function CPLineParenDepth(const line: AnsiString): Integer;
var i: Integer; inStr, inCh: Boolean; c: Char;
begin
  Result := 0; inStr := False; inCh := False; i := 1;
  while i <= Length(line) do
  begin
    c := line[i];
    if inStr then begin if c = '\' then Inc(i) else if c = '"' then inStr := False; end
    else if inCh then begin if c = '\' then Inc(i) else if c = '''' then inCh := False; end
    else if c = '"' then inStr := True
    else if c = '''' then inCh := True
    else if c = '(' then Inc(Result)
    else if c = ')' then Dec(Result);
    Inc(i);
  end;
end;

procedure CPProcessText(const src, baseDir: AnsiString; depth: Integer);
var pos, p, q: Integer; inComment, emitted: Boolean; cont: AnsiString;
begin
  pos := 1;
  inComment := False;
  while pos <= Length(src) do
  begin
    CPReadLine(src, pos, inComment, CPrepLine);
    emitted := False;
    p := 1;
    while p <= Length(CPrepLine) do
    begin
      if not (CPrepLine[p] in [' ', #9]) then Break;
      Inc(p);
    end;
    { Join continuation physical lines while a call's parentheses stay unbalanced,
      so a function-macro invocation whose arguments span newlines (common in
      lua/sqlite) expands as a whole. Directives use `\` continuation, already
      handled in CPReadLine, so skip them. }
    if (p > Length(CPrepLine)) or (CPrepLine[p] <> '#') then
      while (pos <= Length(src)) and (CPLineParenDepth(CPrepLine) > 0) do
      begin
        CPReadLine(src, pos, inComment, cont);
        q := 1;
        while q <= Length(cont) do
        begin
          if not (cont[q] in [' ', #9]) then Break;
          Inc(q);
        end;
        if (q <= Length(cont)) and (cont[q] = '#') then
        begin
          if CPActive then
          begin
            SetLength(CPrepLineExp, 0);
            CPExpandRange(CPrepLine, 1, Length(CPrepLine), 0, CPrepLineExp);
            CPrepOutAppendStr(CPrepLineExp);
            CPrepOutAppendCh(#10);
          end;
          CPDirective(cont, q, Length(cont), depth, baseDir);
          emitted := True;
          Break;
        end
        else
          CPrepLine := CPrepLine + ' ' + cont;
      end;
    if emitted then
    begin
      { Already emitted the source line and consumed one directive line. }
    end
    else if p <= Length(CPrepLine) then
    begin
      if CPrepLine[p] = '#' then
        CPDirective(CPrepLine, p, Length(CPrepLine), depth, baseDir)
      else if CPActive then
      begin
        SetLength(CPrepLineExp, 0);
        CPExpandRange(CPrepLine, 1, Length(CPrepLine), 0, CPrepLineExp);
        CPrepOutAppendStr(CPrepLineExp);
        CPrepOutAppendCh(#10);
      end;
    end
    else if CPActive then
    begin
      SetLength(CPrepLineExp, 0);
      CPExpandRange(CPrepLine, 1, Length(CPrepLine), 0, CPrepLineExp);
      CPrepOutAppendStr(CPrepLineExp);
      CPrepOutAppendCh(#10);
    end;
  end;
end;

procedure CPreprocess(var src: AnsiString; const baseDir: AnsiString);
begin
  SetLength(CPrepOut, 0);
  CPrepOutLen := 0;
  CPrepCharLen := 0;
  CPMCount := 0;
  CPPCount := 0;
  CPCondCount := 0;
  CPActiveMacroCount := 0;
  CPPushCount := 0;
  CPAddLiteral('__linux__', '01');
  CPAddLiteral('__x86_64__', '01');
  { Data-model predefines (C 5.2.4.2): real code branches on these to size long
    (c-testsuite 00212). 64-bit targets are LP64 (long/pointer = 8), 32-bit are
    ILP32 (long/pointer = 4) — matches the native-`long` model (see the C
    `long`=native work). }
  if (TargetArch = TARGET_X86_64) or (TargetArch = TARGET_AARCH64) then
  begin
    CPAddLiteral('__LP64__', '01');
    CPAddLiteral('_LP64', '01');
  end
  else
  begin
    CPAddLiteral('__ILP32__', '01');
    CPAddLiteral('_ILP32', '01');
  end;
  CPAddLiteral('__STDC__', '01');
  CPProcessText(src, baseDir, 0);
  if CPCondCount <> 0 then Error('unterminated C conditional');
  SetLength(CPrepOut, CPrepOutLen);   { trim geometric spare capacity to the live length }
  src := CPrepOut;
end;
