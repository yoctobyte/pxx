{ SPDX-License-Identifier: MPL-2.0 }
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
      if (s[1]='v') and (s[2]='o') and (s[3]='i') and (s[4]='d') then Result := tkCVoid;
      if (s[1]='e') and (s[2]='l') and (s[3]='s') and (s[4]='e') then Result := tkElse;
      if (s[1]='l') and (s[2]='o') and (s[3]='n') and (s[4]='g') then Result := tkCLong;
    end;
    5: begin
      if (s[1]='w') and (s[2]='h') and (s[3]='i') and (s[4]='l') and (s[5]='e') then Result := tkWhile;
      if (s[1]='s') and (s[2]='h') and (s[3]='o') and (s[4]='r') and (s[5]='t') then Result := tkCShort;
      if (s[1]='c') and (s[2]='o') and (s[3]='n') and (s[4]='s') and (s[5]='t') then Result := tkConst;
      if (s[1]='b') and (s[2]='r') and (s[3]='e') and (s[4]='a') and (s[5]='k') then Result := tkBreak;
      if (s[1]='f') and (s[2]='l') and (s[3]='o') and (s[4]='a') and (s[5]='t') then Result := tkCFloat;
      if (s[1]='_') and (s[2]='B') and (s[3]='o') and (s[4]='o') and (s[5]='l') then Result := tkCBool;
    end;
    6: begin
      if (s[1]='r') and (s[2]='e') and (s[3]='t') and (s[4]='u') and (s[5]='r') and (s[6]='n') then Result := tkExit;
      if (s[1]='s') and (s[2]='t') and (s[3]='r') and (s[4]='u') and (s[5]='c') and (s[6]='t') then Result := tkRecord;
      if (s[1]='s') and (s[2]='i') and (s[3]='g') and (s[4]='n') and (s[5]='e') and (s[6]='d') then Result := tkCSigned;
      if (s[1]='d') and (s[2]='o') and (s[3]='u') and (s[4]='b') and (s[5]='l') and (s[6]='e') then Result := tkCDouble;
    end;
    8: begin
      if (s[1]='u') and (s[2]='n') and (s[3]='s') and (s[4]='i') and (s[5]='g') and (s[6]='n') and (s[7]='e') and (s[8]='d') then Result := tkCUnsigned;
      if (s[1]='c') and (s[2]='o') and (s[3]='n') and (s[4]='t') and (s[5]='i') and (s[6]='n') and (s[7]='u') and (s[8]='e') then Result := tkContinue;
    end;
  end;
end;

function CStrContains(const s, sub: AnsiString): Boolean;
var i, j: Integer;
    match: Boolean;
begin
  Result := False;
  if Length(sub) = 0 then Exit;
  if Length(s) < Length(sub) then Exit;
  for i := 1 to Length(s) - Length(sub) + 1 do
  begin
    match := True;
    for j := 1 to Length(sub) do
    begin
      if s[i + j - 1] <> sub[j] then
      begin
        match := False;
        Break;
      end;
    end;
    if match then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

function CAttrAlignedValueOf(const s: AnsiString): Integer;
var i, j, v: Integer;
begin
  Result := 0;
  i := 1;
  while i <= Length(s) - 6 do
  begin
    if (s[i] = 'a') and (s[i+1] = 'l') and (s[i+2] = 'i') and
       (s[i+3] = 'g') and (s[i+4] = 'n') and (s[i+5] = 'e') and
       (s[i+6] = 'd') then
    begin
      j := i + 7;
      while (j <= Length(s)) and (s[j] in [' ', #9, #10, #13]) do Inc(j);
      if (j <= Length(s)) and (s[j] = '(') then
      begin
        Inc(j);
        while (j <= Length(s)) and (s[j] in [' ', #9, #10, #13]) do Inc(j);
        v := 0;
        while (j <= Length(s)) and (s[j] in ['0'..'9']) do
        begin
          v := v * 10 + Ord(s[j]) - Ord('0');
          Inc(j);
        end;
        Result := v;
        Exit;
      end;
      Exit;
    end;
    Inc(i);
  end;
end;

procedure CSkipSpace;
var done, idDone: Boolean;
    p, depth, nameLen: Integer;
    s: AnsiString;
    attrText: AnsiString;
    c_char: Char;
begin
  done := False;
  while (SrcPos <= Length(Source)) and not done do
  begin
    if Source[SrcPos] in ['a'..'z','A'..'Z','_'] then
    begin
      { Parse the identifier/word first using AppendChar }
      s := '';
      p := SrcPos;
      while (p <= Length(Source)) and (Source[p] in ['a'..'z','A'..'Z','0'..'9','_']) do
      begin
        AppendChar(s, Source[p]);
        Inc(p);
      end;
      nameLen := Length(s);
      
      idDone := False;
      if (s = '__attribute__') or (s = '__attribute') then
      begin
        SrcPos := p;
        { Skip spaces }
        while (SrcPos <= Length(Source)) and (Source[SrcPos] in [' ', #9, #10, #13]) do
        begin
          if Source[SrcPos] = #10 then Inc(SrcLine);
          Inc(SrcPos);
        end;
        { Skip balanced parens if present }
        if (SrcPos <= Length(Source)) and (Source[SrcPos] = '(') then
        begin
          Inc(SrcPos);
          depth := 1;
          attrText := '';
          while (SrcPos <= Length(Source)) and (depth > 0) do
          begin
            if Source[SrcPos] = '(' then Inc(depth)
            else if Source[SrcPos] = ')' then Dec(depth)
            else if Source[SrcPos] = #10 then Inc(SrcLine);
            
            if depth > 0 then
            begin
              c_char := Source[SrcPos];
              if c_char in ['A'..'Z'] then
                c_char := Chr(Ord(c_char) + 32);
              AppendChar(attrText, c_char);
            end;
            Inc(SrcPos);
          end;
          if CStrContains(attrText, 'packed') then
            CAttrPacked := True;
          if CStrContains(attrText, 'aligned') then
          begin
            CAttrAligned := True;
            CAttrAlignValue := CAttrAlignedValueOf(attrText);
          end;
        end;
        idDone := True;
      end
      else if (s = '__extension__') or (s = '__inline') or (s = '__inline__') or (s = 'inline') or
              (s = '__restrict') or (s = '__restrict__') or (s = 'restrict') or
              (s = 'volatile') or (s = '__volatile') or (s = '__volatile__') or
              (s = '__const') or (s = '__const__') then
      begin
        SrcPos := p;
        idDone := True;
      end
      else if ((nameLen >= 7) and (s[1] = 'G') and (s[2] = '_') and (s[3] = 'G') and (s[4] = 'N') and (s[5] = 'U') and (s[6] = 'C') and (s[7] = '_')) or
              ((nameLen >= 9) and (s[1] = '_') and (s[2] = 'G') and (s[3] = 'L') and (s[4] = 'I') and (s[5] = 'B') and (s[6] = 'C') and (s[7] = 'X') and (s[8] = 'X') and (s[9] = '_')) then
      begin
        SrcPos := p;
        { Skip spaces }
        while (SrcPos <= Length(Source)) and (Source[SrcPos] in [' ', #9, #10, #13]) do
        begin
          if Source[SrcPos] = #10 then Inc(SrcLine);
          Inc(SrcPos);
        end;
        { Skip balanced parens if present }
        if (SrcPos <= Length(Source)) and (Source[SrcPos] = '(') then
        begin
          Inc(SrcPos);
          depth := 1;
          while (SrcPos <= Length(Source)) and (depth > 0) do
          begin
            if Source[SrcPos] = '(' then Inc(depth)
            else if Source[SrcPos] = ')' then Dec(depth)
            else if Source[SrcPos] = #10 then Inc(SrcLine);
            Inc(SrcPos);
          end;
        end;
        idDone := True;
      end;

      if not idDone then
        done := True;
    end
    else
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
        else done := True;
      end;
    end;
  end;
end;

{ Scan the fractional/exponent/suffix tail of a C float literal that begins at
  numStart (SrcPos is positioned at the `.` or `e`/`E`), and emit a tkFloat whose
  IVal carries the IEEE-754 double bit pattern (matching the Pascal lexer). }
procedure CLexFloatTail(numStart: Integer);
var fs: AnsiString; valEnd: Integer;
begin
  if (SrcPos <= Length(Source)) and (Source[SrcPos] = '.') then
  begin
    Inc(SrcPos);
    while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'9']) do Inc(SrcPos);
  end;
  if (SrcPos <= Length(Source)) and (Source[SrcPos] in ['e','E']) then
  begin
    Inc(SrcPos);
    if (SrcPos <= Length(Source)) and (Source[SrcPos] in ['+','-']) then Inc(SrcPos);
    while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'9']) do Inc(SrcPos);
  end;
  valEnd := SrcPos;   { value text ends before any f/F/l/L suffix }
  if (SrcPos <= Length(Source)) and (Source[SrcPos] in ['f','F','l','L']) then Inc(SrcPos);
  fs := Copy(Source, numStart, valEnd - numStart);
  CurTok.Kind := tkFloat;
  CurTok.IVal := StrToDoubleBits(fs);
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
  numStart, valEnd: Integer;
begin
  CSkipSpace;
  CurTok.Line := SrcLine; CurTok.SVal := ''; CurTok.IVal := 0;
  CLexUnsignedSuffix := False;
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
    numStart := SrcPos;
    n := 0;
    while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'9']) do
      begin n := n * 10 + (Ord(Source[SrcPos]) - 48); Inc(SrcPos); end;
    { Float literal: a `.` after the digits (`1.5`, `2.`), or an exponent
      `e`/`E` followed by digits or a sign (`1e308`, `1e-3`). }
    if ((SrcPos <= Length(Source)) and (Source[SrcPos] = '.')) or
       ((SrcPos <= Length(Source)) and (Source[SrcPos] in ['e','E']) and
        (SrcPos < Length(Source)) and (Source[SrcPos+1] in ['0'..'9','+','-'])) then
    begin
      CLexFloatTail(numStart);
      Exit;
    end;
    { consume an integer suffix (u/U/l/L, e.g. UL/LL/ULL) — else it dangles as a
      separate identifier token and breaks const expressions like `MAX/sizeof(t)`.
      A u/U suffix marks the literal unsigned (SVal='u'); the parser tags it
      tyUInt32 so `5u - 10` wraps modulo 2^32 like C. }
    while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['u','U','l','L']) do
    begin
      if Source[SrcPos] in ['u','U'] then CLexUnsignedSuffix := True;
      Inc(SrcPos);
    end;
    CurTok.Kind := tkInteger; CurTok.IVal := n; Exit;
  end;

  { 0, 0x hex, or 0 alone }
  if c = '0' then
  begin
    numStart := SrcPos;
    Inc(SrcPos);
    { `0.5` / `0e3` — a float beginning with 0 (but not `0x` hex) }
    if (SrcPos <= Length(Source)) and
       ((Source[SrcPos] = '.') or
        ((Source[SrcPos] in ['e','E']) and (SrcPos < Length(Source)) and
         (Source[SrcPos+1] in ['0'..'9','+','-']))) then
    begin
      CLexFloatTail(numStart);
      Exit;
    end;
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
      { C octal: a leading 0 followed by digits is base 8 (e.g. 0100 = 64, as in
        the O_* fcntl flags). The leading 0 was already consumed above. }
      n := 0;
      while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'7']) do
        begin n := n * 8 + (Ord(Source[SrcPos]) - 48); Inc(SrcPos); end;
    end;
    { consume an integer suffix (u/U/l/L) on hex/octal/decimal-zero literals;
      u/U marks unsigned (SVal='u') -> parser tags tyUInt32 }
    while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['u','U','l','L']) do
    begin
      if Source[SrcPos] in ['u','U'] then CLexUnsignedSuffix := True;
      Inc(SrcPos);
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
            'a': AppendChar(s, #7);
            'b': AppendChar(s, #8);
            'f': AppendChar(s, #12);
            'v': AppendChar(s, #11);
            '\': AppendChar(s, '\');
            '"': AppendChar(s, '"');
            '''': AppendChar(s, '''');
            '0'..'7': begin
              { Octal escape \N / \NN / \NNN — consume leading digit here,
                extra digits inside; outer Inc handles the last digit. }
              n := Ord(Source[SrcPos]) - 48;
              if (SrcPos + 1 <= Length(Source)) and (Source[SrcPos+1] in ['0'..'7']) then
              begin
                Inc(SrcPos); n := n * 8 + (Ord(Source[SrcPos]) - 48);
                if (SrcPos + 1 <= Length(Source)) and (Source[SrcPos+1] in ['0'..'7']) then
                begin Inc(SrcPos); n := n * 8 + (Ord(Source[SrcPos]) - 48); end;
              end;
              AppendChar(s, Chr(n and 255));
            end;
            'x': begin
              { Hex escape \xNN... — SrcPos on 'x', consume hex digits; last
                digit is left for outer Inc. }
              n := 0;
              while (SrcPos + 1 <= Length(Source)) and
                    (Source[SrcPos+1] in ['0'..'9','a'..'f','A'..'F']) do
              begin
                Inc(SrcPos);
                c := Source[SrcPos];
                if c in ['0'..'9'] then n := n*16 + (Ord(c)-48)
                else if c in ['a'..'f'] then n := n*16 + (Ord(c)-87)
                else n := n*16 + (Ord(c)-55);
              end;
              AppendChar(s, Chr(n and 255));
            end;
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
          'a': CurTok.IVal := 7;
          'b': CurTok.IVal := 8;
          'f': CurTok.IVal := 12;
          'v': CurTok.IVal := 11;
          '\': CurTok.IVal := Ord('\');
          '''': CurTok.IVal := Ord('''');
          '"': CurTok.IVal := Ord('"');
          '0'..'7': begin
            n := Ord(Source[SrcPos]) - 48;
            if (SrcPos + 1 <= Length(Source)) and (Source[SrcPos+1] in ['0'..'7']) then
            begin
              Inc(SrcPos); n := n * 8 + (Ord(Source[SrcPos]) - 48);
              if (SrcPos + 1 <= Length(Source)) and (Source[SrcPos+1] in ['0'..'7']) then
              begin Inc(SrcPos); n := n * 8 + (Ord(Source[SrcPos]) - 48); end;
            end;
            CurTok.IVal := n and 255;
          end;
          'x': begin
            n := 0;
            while (SrcPos + 1 <= Length(Source)) and
                  (Source[SrcPos+1] in ['0'..'9','a'..'f','A'..'F']) do
            begin
              Inc(SrcPos);
              c := Source[SrcPos];
              if c in ['0'..'9'] then n := n*16 + (Ord(c)-48)
              else if c in ['a'..'f'] then n := n*16 + (Ord(c)-87)
              else n := n*16 + (Ord(c)-55);
            end;
            CurTok.IVal := n and 255;
          end;
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
           if (SrcPos <= Length(Source)) and (Source[SrcPos] = '+') then begin Inc(SrcPos); CurTok.Kind := tkPlusPlus; end
           else if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then begin Inc(SrcPos); CurTok.Kind := tkPlusEq; end
           else CurTok.Kind := tkPlus;
         end;
    '-': begin
           if (SrcPos <= Length(Source)) and (Source[SrcPos] = '-') then begin Inc(SrcPos); CurTok.Kind := tkMinusMinus; end
           else if (SrcPos <= Length(Source)) and (Source[SrcPos] = '>') then begin Inc(SrcPos); CurTok.Kind := tkDot; end
           else if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then begin Inc(SrcPos); CurTok.Kind := tkMinusEq; end
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
    '%': begin
           if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then begin Inc(SrcPos); CurTok.Kind := tkModEq; end
           else CurTok.Kind := tkMod;
         end;
    '(': CurTok.Kind := tkLParen;
    ')': CurTok.Kind := tkRParen;
    '[': CurTok.Kind := tkLBrack;
    ']': CurTok.Kind := tkRBrack;
    '{': CurTok.Kind := tkBegin;
    '}': CurTok.Kind := tkEnd;
    ';': CurTok.Kind := tkSemicolon;
    ',': CurTok.Kind := tkComma;
    '.': CurTok.Kind := tkDot;
    ':': CurTok.Kind := tkColon;
    '?': CurTok.Kind := tkQuestion;
    '~': CurTok.Kind := tkNot;
    '^': begin
           if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then begin Inc(SrcPos); CurTok.Kind := tkXorEq; end
           else CurTok.Kind := tkXor;
         end;
    '&': begin
           if (SrcPos <= Length(Source)) and (Source[SrcPos] = '&') then begin Inc(SrcPos); CurTok.Kind := tkAnd; end
           else if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then begin Inc(SrcPos); CurTok.Kind := tkAmpEq; end
           else CurTok.Kind := tkAmp;
         end;
    '|': begin
           if (SrcPos <= Length(Source)) and (Source[SrcPos] = '|') then begin Inc(SrcPos); CurTok.Kind := tkOr; end
           else if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then begin Inc(SrcPos); CurTok.Kind := tkPipeEq; end
           else CurTok.Kind := tkPipe;
         end;
    '!': begin
           if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then
             begin Inc(SrcPos); CurTok.Kind := tkNeq; end
           else CurTok.Kind := tkLogNot;   { logical not; `~` stays tkNot }
         end;
    '=': begin
           if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then
             begin Inc(SrcPos); CurTok.Kind := tkEq; end
           else CurTok.Kind := tkAssign;
         end;
    '<': begin
           if (SrcPos <= Length(Source)) and (Source[SrcPos] = '<') then
             begin
               Inc(SrcPos);
               if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then
                 begin Inc(SrcPos); CurTok.Kind := tkShlEq; end
               else CurTok.Kind := tkShl;
             end
           else if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then
             begin Inc(SrcPos); CurTok.Kind := tkLe; end
           else CurTok.Kind := tkLt;
         end;
    '>': begin
           if (SrcPos <= Length(Source)) and (Source[SrcPos] = '>') then
             begin
               Inc(SrcPos);
               if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then
                 begin Inc(SrcPos); CurTok.Kind := tkShrEq; end
               else CurTok.Kind := tkShr;
             end
           else if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then
             begin Inc(SrcPos); CurTok.Kind := tkGe; end
           else CurTok.Kind := tkGt;
         end;
    else CurTok.Kind := tkIdent; { unknown punctuation — skip }
  end;
end;

procedure CLexAll;
var off, len, i: Integer; k: TTokenKind;
begin
  CAttrPacked := False;
  CAttrAligned := False;
  CAttrAlignValue := 0;
  TokCount := 0; TokCharLen := 0;
  repeat
    CLexOne;
    k := CurTok.Kind;
    if TokCount >= MAX_TOKENS then Error('token overflow');
    Tokens[TokCount].Kind    := k;
    Tokens[TokCount].IVal    := CurTok.IVal;
    Tokens[TokCount].Line    := CurTok.Line;
    CAttrFlags[TokCount] := 0;
    if CAttrPacked then CAttrFlags[TokCount] := CAttrFlags[TokCount] or 1;
    if CAttrAligned then CAttrFlags[TokCount] := CAttrFlags[TokCount] or 2;
    if CLexUnsignedSuffix then CAttrFlags[TokCount] := CAttrFlags[TokCount] or 4;
    CAttrAlignValues[TokCount] := CAttrAlignValue;
    CAttrPacked := False;
    CAttrAligned := False;
    CAttrAlignValue := 0;
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
  savedSrcPos, savedSrcLine: Integer;
  unitStart, len, i, off: Integer;
  sval: AnsiString;
  k: TTokenKind;
begin
  CAttrPacked := False;
  CAttrAligned := False;
  CAttrAlignValue := 0;
  SavedLexSource := Source;
  savedSrcPos := SrcPos;
  savedSrcLine := SrcLine;

  Source := srcText;
  SrcPos := 1;
  SrcLine := 1;

  if (MainProgramTokCount = MAX_TOKENS) and (TokCount > 0) and (Tokens[TokCount-1].Kind = tkEOF) then
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
    CAttrFlags[TokCount] := 0;
    if CAttrPacked then CAttrFlags[TokCount] := CAttrFlags[TokCount] or 1;
    if CAttrAligned then CAttrFlags[TokCount] := CAttrFlags[TokCount] or 2;
    if CLexUnsignedSuffix then CAttrFlags[TokCount] := CAttrFlags[TokCount] or 4;
    CAttrAlignValues[TokCount] := CAttrAlignValue;
    CAttrPacked := False;
    CAttrAligned := False;
    CAttrAlignValue := 0;
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

  Source := SavedLexSource;
  SrcPos := savedSrcPos;
  SrcLine := savedSrcLine;
  Result := unitStart;
end;
