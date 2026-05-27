
{ ===== Error ===== }

procedure Error(const msg: AnsiString);
begin
  writeln('pascal26:', SrcLine, ': error: ', msg, ' (', ErrorIdent, ')');
  Halt(1);
end;

{ ===== Lexer ===== }

procedure SkipSpace;
var doneSkip: Boolean;
begin
  if DebugTrace then writeln('Entering SkipSpace. SrcPos = ', SrcPos, ' Length(Source) = ', Length(Source));
  while SrcPos <= Length(Source) do
    case Source[SrcPos] of
      ' ', #9, #13: Inc(SrcPos);
      #10: begin Inc(SrcLine); Inc(SrcPos); end;
      '{':
      begin
        Inc(SrcPos);
        { Is it $ifdef FPC ? }
        if (SrcPos + 9 <= Length(Source)) and (Source[SrcPos] = '$') and
           ((Source[SrcPos+1] = 'i') or (Source[SrcPos+1] = 'I')) and
           ((Source[SrcPos+2] = 'f') or (Source[SrcPos+2] = 'F')) and
           ((Source[SrcPos+3] = 'd') or (Source[SrcPos+3] = 'D')) and
           ((Source[SrcPos+4] = 'e') or (Source[SrcPos+4] = 'E')) and
           ((Source[SrcPos+5] = 'f') or (Source[SrcPos+5] = 'F')) and
           (Source[SrcPos+6] = ' ') and
           ((Source[SrcPos+7] = 'F') or (Source[SrcPos+7] = 'f')) and
           ((Source[SrcPos+8] = 'P') or (Source[SrcPos+8] = 'p')) and
           ((Source[SrcPos+9] = 'C') or (Source[SrcPos+9] = 'c')) then
        begin
          { Skip the dollar-ifdef FPC comment itself }
          while (SrcPos <= Length(Source)) and (Source[SrcPos] <> '}') do
          begin
            if Source[SrcPos] = #10 then Inc(SrcLine);
            Inc(SrcPos);
          end;
          if SrcPos <= Length(Source) then Inc(SrcPos);
          
          { Now skip all text until next dollar-else or dollar-endif }
          doneSkip := False;
          while (SrcPos <= Length(Source)) and not doneSkip do
          begin
            if Source[SrcPos] = #10 then
            begin
              Inc(SrcLine);
              Inc(SrcPos);
            end
            else if (Source[SrcPos] = '{') and (SrcPos + 5 <= Length(Source)) and 
                    (Source[SrcPos+1] = '$') and
                    ((Source[SrcPos+2] = 'e') or (Source[SrcPos+2] = 'E')) and
                    ((Source[SrcPos+3] = 'l') or (Source[SrcPos+3] = 'L')) and
                    ((Source[SrcPos+4] = 's') or (Source[SrcPos+4] = 'S')) and
                    ((Source[SrcPos+5] = 'e') or (Source[SrcPos+5] = 'E')) then
            begin
              { Found dollar-else. Stop skipping, consume the dollar-else comment }
              Inc(SrcPos);
              while (SrcPos <= Length(Source)) and (Source[SrcPos] <> '}') do
              begin
                if Source[SrcPos] = #10 then Inc(SrcLine);
                Inc(SrcPos);
              end;
              if SrcPos <= Length(Source) then Inc(SrcPos);
              doneSkip := True;
            end
            else if (Source[SrcPos] = '{') and (SrcPos + 6 <= Length(Source)) and 
                    (Source[SrcPos+1] = '$') and
                    ((Source[SrcPos+2] = 'e') or (Source[SrcPos+2] = 'E')) and
                    ((Source[SrcPos+3] = 'n') or (Source[SrcPos+3] = 'N')) and
                    ((Source[SrcPos+4] = 'd') or (Source[SrcPos+4] = 'D')) and
                    ((Source[SrcPos+5] = 'i') or (Source[SrcPos+5] = 'I')) and
                    ((Source[SrcPos+6] = 'f') or (Source[SrcPos+6] = 'F')) then
            begin
              { Found dollar-endif. Stop skipping, consume the dollar-endif comment }
              Inc(SrcPos);
              while (SrcPos <= Length(Source)) and (Source[SrcPos] <> '}') do
              begin
                if Source[SrcPos] = #10 then Inc(SrcLine);
                Inc(SrcPos);
              end;
              if SrcPos <= Length(Source) then Inc(SrcPos);
              doneSkip := True;
            end
            else
              Inc(SrcPos);
          end;
        end
        else if (SrcPos + 4 <= Length(Source)) and (Source[SrcPos] = '$') and
                ((Source[SrcPos+1] = 'e') or (Source[SrcPos+1] = 'E')) and
                ((Source[SrcPos+2] = 'l') or (Source[SrcPos+2] = 'L')) and
                ((Source[SrcPos+3] = 's') or (Source[SrcPos+3] = 'S')) and
                ((Source[SrcPos+4] = 'e') or (Source[SrcPos+4] = 'E')) then
        begin
          { This is a dollar-else without an active skip. This means we just compiled the }
          { dollar-ifndef FPC block, and now we reached the FPC else block. We must skip it to dollar-endif }
          while (SrcPos <= Length(Source)) and (Source[SrcPos] <> '}') do
          begin
            if Source[SrcPos] = #10 then Inc(SrcLine);
            Inc(SrcPos);
          end;
          if SrcPos <= Length(Source) then Inc(SrcPos);
          
          doneSkip := False;
          while (SrcPos <= Length(Source)) and not doneSkip do
          begin
            if Source[SrcPos] = #10 then
            begin
              Inc(SrcLine);
              Inc(SrcPos);
            end
            else if (Source[SrcPos] = '{') and (SrcPos + 6 <= Length(Source)) and 
                    (Source[SrcPos+1] = '$') and
                    ((Source[SrcPos+2] = 'e') or (Source[SrcPos+2] = 'E')) and
                    ((Source[SrcPos+3] = 'n') or (Source[SrcPos+3] = 'N')) and
                    ((Source[SrcPos+4] = 'd') or (Source[SrcPos+4] = 'D')) and
                    ((Source[SrcPos+5] = 'i') or (Source[SrcPos+5] = 'I')) and
                    ((Source[SrcPos+6] = 'f') or (Source[SrcPos+6] = 'F')) then
            begin
              { Found dollar-endif. Stop skipping, consume the dollar-endif comment }
              Inc(SrcPos);
              while (SrcPos <= Length(Source)) and (Source[SrcPos] <> '}') do
              begin
                if Source[SrcPos] = #10 then Inc(SrcLine);
                Inc(SrcPos);
              end;
              if SrcPos <= Length(Source) then Inc(SrcPos);
              doneSkip := True;
            end
            else
              Inc(SrcPos);
          end;
        end
        else
        begin
          { Regular comment, skip to next close curly brace }
          while (SrcPos <= Length(Source)) and (Source[SrcPos] <> '}') do
          begin
            if Source[SrcPos] = #10 then Inc(SrcLine);
            Inc(SrcPos);
          end;
          if SrcPos <= Length(Source) then Inc(SrcPos);
        end;
      end;
      '(':
        if (SrcPos+1 <= Length(Source)) and (Source[SrcPos+1] = '*') then
        begin
          Inc(SrcPos, 2);
          while SrcPos+1 <= Length(Source) do
          begin
            if (Source[SrcPos] = '*') and (Source[SrcPos+1] = ')') then
              begin Inc(SrcPos, 2); Exit; end;
            if Source[SrcPos] = #10 then Inc(SrcLine);
            Inc(SrcPos);
          end;
        end
        else Exit;
      '/':
        if (SrcPos+1 <= Length(Source)) and (Source[SrcPos+1] = '/') then
          while (SrcPos <= Length(Source)) and (Source[SrcPos] <> #10) do
            Inc(SrcPos)
        else Exit;
      else Exit;
    end;
end;

function Keyword(const s: AnsiString): TTokenKind;
begin
  Result := tkIdent;
  if Length(s) = 2 then
  begin
    if (s[1]='i') and (s[2]='f') then Result := tkIf;
    if (s[1]='d') and (s[2]='o') then Result := tkDo;
    if (s[1]='t') and (s[2]='o') then Result := tkTo;
    if (s[1]='o') and (s[2]='f') then Result := tkOf;
    if (s[1]='o') and (s[2]='r') then Result := tkOr;
  end
  else if Length(s) = 3 then
  begin
    if (s[1]='e') and (s[2]='n') and (s[3]='d') then Result := tkEnd;
    if (s[1]='v') and (s[2]='a') and (s[3]='r') then Result := tkVar;
    if (s[1]='f') and (s[2]='o') and (s[3]='r') then Result := tkFor;
    if (s[1]='a') and (s[2]='n') and (s[3]='d') then Result := tkAnd;
    if (s[1]='n') and (s[2]='o') and (s[3]='t') then Result := tkNot;
    if (s[1]='d') and (s[2]='i') and (s[3]='v') then Result := tkDiv;
    if (s[1]='m') and (s[2]='o') and (s[3]='d') then Result := tkMod;
    if (s[1]='i') and (s[2]='n') and (s[3]='c') then Result := tkInc;
    if (s[1]='I') and (s[2]='n') and (s[3]='c') then Result := tkInc;
    if (s[1]='d') and (s[2]='e') and (s[3]='c') then Result := tkDec;
    if (s[1]='D') and (s[2]='e') and (s[3]='c') then Result := tkDec;
    if (s[1]='o') and (s[2]='r') and (s[3]='d') then Result := tkOrd;
    if (s[1]='O') and (s[2]='r') and (s[3]='d') then Result := tkOrd;
    if (s[1]='c') and (s[2]='h') and (s[3]='r') then Result := tkChr;
    if (s[1]='C') and (s[2]='h') and (s[3]='r') then Result := tkChr;
  end
  else if Length(s) = 4 then
  begin
    if (s[1]='t') and (s[2]='y') and (s[3]='p') and (s[4]='e') then Result := tkType;
    if (s[1]='u') and (s[2]='s') and (s[3]='e') and (s[4]='s') then Result := tkUses;
    if (s[1]='u') and (s[2]='n') and (s[3]='i') and (s[4]='t') then Result := tkUnit;
    if (s[1]='t') and (s[2]='h') and (s[3]='e') and (s[4]='n') then Result := tkThen;
    if (s[1]='e') and (s[2]='l') and (s[3]='s') and (s[4]='e') then Result := tkElse;
    if (s[1]='c') and (s[2]='a') and (s[3]='s') and (s[4]='e') then Result := tkCase;
    if (s[1]='t') and (s[2]='r') and (s[3]='u') and (s[4]='e') then Result := tkTrue;
    if (s[1]='T') and (s[2]='r') and (s[3]='u') and (s[4]='e') then Result := tkTrue;
    if (s[1]='r') and (s[2]='e') and (s[3]='a') and (s[4]='d') then Result := tkRead;
    if (s[1]='h') and (s[2]='a') and (s[3]='l') and (s[4]='t') then Result := tkHalt;
    if (s[1]='H') and (s[2]='a') and (s[3]='l') and (s[4]='t') then Result := tkHalt;
    if (s[1]='e') and (s[2]='x') and (s[3]='i') and (s[4]='t') then Result := tkExit;
    if (s[1]='E') and (s[2]='x') and (s[3]='i') and (s[4]='t') then Result := tkExit;
    if (s[1]='c') and (s[2]='h') and (s[3]='a') and (s[4]='r') then Result := tkChar_T;
    if (s[1]='C') and (s[2]='h') and (s[3]='a') and (s[4]='r') then Result := tkChar_T;
    if (s[1]='r') and (s[2]='e') and (s[3]='a') and (s[4]='l') then Result := tkReal_T;
    if (s[1]='R') and (s[2]='e') and (s[3]='a') and (s[4]='l') then Result := tkReal_T;
    if (s[1]='b') and (s[2]='y') and (s[3]='t') and (s[4]='e') then Result := tkInteger_T;
    if (s[1]='B') and (s[2]='y') and (s[3]='t') and (s[4]='e') then Result := tkInteger_T;
  end
  else if Length(s) = 5 then
  begin
    if (s[1]='b') and (s[2]='e') and (s[3]='g') and (s[4]='i') and (s[5]='n') then Result := tkBegin;
    if (s[1]='c') and (s[2]='o') and (s[3]='n') and (s[4]='s') and (s[5]='t') then Result := tkConst;
    if (s[1]='w') and (s[2]='h') and (s[3]='i') and (s[4]='l') and (s[5]='e') then Result := tkWhile;
    if (s[1]='u') and (s[2]='n') and (s[3]='t') and (s[4]='i') and (s[5]='l') then Result := tkUntil;
    if (s[1]='a') and (s[2]='r') and (s[3]='r') and (s[4]='a') and (s[5]='y') then Result := tkArray;
    if (s[1]='f') and (s[2]='a') and (s[3]='l') and (s[4]='s') and (s[5]='e') then Result := tkFalse;
    if (s[1]='F') and (s[2]='a') and (s[3]='l') and (s[4]='s') and (s[5]='e') then Result := tkFalse;
    if (s[1]='w') and (s[2]='r') and (s[3]='i') and (s[4]='t') and (s[5]='e') then Result := tkwrite;
    if (s[1]='c') and (s[2]='l') and (s[3]='a') and (s[4]='s') and (s[5]='s') then Result := tkClass;
    if (s[1]='C') and (s[2]='l') and (s[3]='a') and (s[4]='s') and (s[5]='s') then Result := tkClass;
  end
  else if Length(s) = 6 then
  begin
    if (s[1]='d') and (s[2]='o') and (s[3]='w') and (s[4]='n') and (s[5]='t') and (s[6]='o') then Result := tkDownto;
    if (s[1]='r') and (s[2]='e') and (s[3]='p') and (s[4]='e') and (s[5]='a') and (s[6]='t') then Result := tkRepeat;
    if (s[1]='r') and (s[2]='e') and (s[3]='c') and (s[4]='o') and (s[5]='r') and (s[6]='d') then Result := tkRecord;
    if (s[1]='r') and (s[2]='e') and (s[3]='a') and (s[4]='d') and (s[5]='l') and (s[6]='n') then Result := tkReadln;
    if (s[1]='l') and (s[2]='e') and (s[3]='n') and (s[4]='g') and (s[5]='t') and (s[6]='h') then Result := tkLength;
    if (s[1]='L') and (s[2]='e') and (s[3]='n') and (s[4]='g') and (s[5]='t') and (s[6]='h') then Result := tkLength;
    if (s[1]='g') and (s[2]='e') and (s[3]='t') and (s[4]='m') and (s[5]='e') and (s[6]='m') then Result := tkGetMem;
    if (s[1]='G') and (s[2]='e') and (s[3]='t') and (s[4]='M') and (s[5]='e') and (s[6]='m') then Result := tkGetMem;
    if (s[1]='a') and (s[2]='r') and (s[3]='g') and (s[4]='s') and (s[5]='t') and (s[6]='r') then Result := tkArgStr;
    if (s[1]='A') and (s[2]='r') and (s[3]='g') and (s[4]='S') and (s[5]='t') and (s[6]='r') then Result := tkArgStr;
    if (s[1]='s') and (s[2]='t') and (s[3]='r') and (s[4]='i') and (s[5]='n') and (s[6]='g') then Result := tkString_T;
    if (s[1]='S') and (s[2]='t') and (s[3]='r') and (s[4]='i') and (s[5]='n') and (s[6]='g') then Result := tkString_T;
  end
  else if Length(s) = 7 then
  begin
    if (s[1]='p') and (s[2]='r') and (s[3]='o') and (s[4]='g') and (s[5]='r') and (s[6]='a') and (s[7]='m') then Result := tkProgram;
    if (s[1]='f') and (s[2]='o') and (s[3]='r') and (s[4]='w') and (s[5]='a') and (s[6]='r') and (s[7]='d') then Result := tkForward;
    if (s[1]='w') and (s[2]='r') and (s[3]='i') and (s[4]='t') and (s[5]='e') and (s[6]='l') and (s[7]='n') then Result := tkwriteln;
    if (s[1]='s') and (s[2]='y') and (s[3]='s') and (s[4]='o') and (s[5]='p') and (s[6]='e') and (s[7]='n') then Result := tkSysOpen;
    if (s[1]='S') and (s[2]='y') and (s[3]='s') and (s[4]='O') and (s[5]='p') and (s[6]='e') and (s[7]='n') then Result := tkSysOpen;
    if (s[1]='s') and (s[2]='y') and (s[3]='s') and (s[4]='r') and (s[5]='e') and (s[6]='a') and (s[7]='d') then Result := tkSysRead;
    if (s[1]='S') and (s[2]='y') and (s[3]='s') and (s[4]='R') and (s[5]='e') and (s[6]='a') and (s[7]='d') then Result := tkSysRead;
    if (s[1]='i') and (s[2]='n') and (s[3]='t') and (s[4]='e') and (s[5]='g') and (s[6]='e') and (s[7]='r') then Result := tkInteger_T;
    if (s[1]='I') and (s[2]='n') and (s[3]='t') and (s[4]='e') and (s[5]='g') and (s[6]='e') and (s[7]='r') then Result := tkInteger_T;
    if (s[1]='b') and (s[2]='o') and (s[3]='o') and (s[4]='l') and (s[5]='e') and (s[6]='a') and (s[7]='n') then Result := tkBoolean_T;
    if (s[1]='B') and (s[2]='o') and (s[3]='o') and (s[4]='l') and (s[5]='e') and (s[6]='a') and (s[7]='n') then Result := tkBoolean_T;
  end
  else if Length(s) = 8 then
  begin
    if (s[1]='f') and (s[2]='u') and (s[3]='n') and (s[4]='c') and (s[5]='t') and (s[6]='i') and (s[7]='o') and (s[8]='n') then Result := tkFunction;
    if (s[1]='s') and (s[2]='y') and (s[3]='s') and (s[4]='w') and (s[5]='r') and (s[6]='i') and (s[7]='t') and (s[8]='e') then Result := tkSyswrite;
    if (s[1]='S') and (s[2]='y') and (s[3]='s') and (s[4]='W') and (s[5]='r') and (s[6]='i') and (s[7]='t') and (s[8]='e') then Result := tkSyswrite;
    if (s[1]='s') and (s[2]='y') and (s[3]='s') and (s[4]='c') and (s[5]='l') and (s[6]='o') and (s[7]='s') and (s[8]='e') then Result := tkSysClose;
    if (s[1]='S') and (s[2]='y') and (s[3]='s') and (s[4]='C') and (s[5]='l') and (s[6]='o') and (s[7]='s') and (s[8]='e') then Result := tkSysClose;
    if (s[1]='a') and (s[2]='r') and (s[3]='g') and (s[4]='c') and (s[5]='o') and (s[6]='u') and (s[7]='n') and (s[8]='t') then Result := tkArgCount;
    if (s[1]='p') and (s[2]='a') and (s[3]='r') and (s[4]='a') and (s[5]='m') and (s[6]='s') and (s[7]='t') and (s[8]='r') then Result := tkArgStr;
    if (s[1]='A') and (s[2]='r') and (s[3]='g') and (s[4]='C') and (s[5]='o') and (s[6]='u') and (s[7]='n') and (s[8]='t') then Result := tkArgCount;
    if (s[1]='P') and (s[2]='a') and (s[3]='r') and (s[4]='a') and (s[5]='m') and (s[6]='S') and (s[7]='t') and (s[8]='r') then Result := tkArgStr;
    if (s[1]='l') and (s[2]='o') and (s[3]='n') and (s[4]='g') and (s[5]='w') and (s[6]='o') and (s[7]='r') and (s[8]='d') then Result := tkLongWord_T;
    if (s[1]='L') and (s[2]='o') and (s[3]='n') and (s[4]='g') and (s[5]='W') and (s[6]='o') and (s[7]='r') and (s[8]='d') then Result := tkLongWord_T;
  end
  else if Length(s) = 9 then
  begin
    if (s[1]='p') and (s[2]='r') and (s[3]='o') and (s[4]='c') and (s[5]='e') and (s[6]='d') and (s[7]='u') and (s[8]='r') and (s[9]='e') then Result := tkProcedure;
    if (s[1]='s') and (s[2]='y') and (s[3]='s') and (s[4]='f') and (s[5]='c') and (s[6]='h') and (s[7]='m') and (s[8]='o') and (s[9]='d') then Result := tkSysFchmod;
    if (s[1]='S') and (s[2]='y') and (s[3]='s') and (s[4]='F') and (s[5]='c') and (s[6]='h') and (s[7]='m') and (s[8]='o') and (s[9]='d') then Result := tkSysFchmod;
  end
  else if Length(s) = 10 then
  begin
    if (s[1]='p') and (s[2]='a') and (s[3]='r') and (s[4]='a') and (s[5]='m') and (s[6]='c') and (s[7]='o') and (s[8]='u') and (s[9]='n') and (s[10]='t') then Result := tkArgCount;
    if (s[1]='P') and (s[2]='a') and (s[3]='r') and (s[4]='a') and (s[5]='m') and (s[6]='C') and (s[7]='o') and (s[8]='u') and (s[9]='n') and (s[10]='t') then Result := tkArgCount;
  end
end;
{$ifdef FPC}
procedure AppendChar(var dst: AnsiString; c: Char);
begin
  dst := dst + c;
end;
{$else}
procedure AppendChar(var dst: AnsiString; c: Char);
var len: Integer;
begin
  len := Length(dst);
  SetLength(dst, len + 1);
  dst[len + 1] := c;
end;
{$endif}

procedure LexOne;
var
{$ifdef FPC}
  c: Char;
{$else}
  c: Integer;
{$endif}
  s: AnsiString;
  n: Int64;
  i: Integer;
begin
  if DebugTrace then writeln('Entering Next. SrcPos = ', SrcPos);
  SkipSpace;
  CurTok.Line := SrcLine; CurTok.SVal := '';
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
    if DebugTrace then writeln('Scanned token s: ', s, ' len: ', Length(s));
    CurTok.Kind := Keyword(s);
    if DebugTrace then writeln('Keyword returned kind: ', Ord(CurTok.Kind));
    CurTok.SVal := s; Exit;
  end;

  if c in ['0'..'9'] then
  begin
    n := 0;
    while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'9']) do
      begin n := n*10 + (Ord(Source[SrcPos])-48); Inc(SrcPos); end;
    CurTok.Kind := tkInteger; CurTok.IVal := n; Exit;
  end;

  if c = '$' then
  begin
    Inc(SrcPos); n := 0;
    while SrcPos <= Length(Source) do
    begin
      c := Source[SrcPos];
      if c in ['0'..'9'] then n := n*16 + (Ord(c)-48)
      else if c in ['a'..'f'] then n := n*16 + (Ord(c)-87)
      else if c in ['A'..'F'] then n := n*16 + (Ord(c)-55)
      else begin CurTok.Kind := tkInteger; CurTok.IVal := n; Exit; end;
      Inc(SrcPos);
    end;
    CurTok.Kind := tkInteger; CurTok.IVal := n; Exit;
  end;

  if c = '&' then
  begin
    Inc(SrcPos); n := 0;
    while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'7']) do
      begin n := n*8 + (Ord(Source[SrcPos])-48); Inc(SrcPos); end;
    CurTok.Kind := tkInteger; CurTok.IVal := n; Exit;
  end;

  if c = '''' then
  begin
    Inc(SrcPos); s := '';
    while SrcPos <= Length(Source) do
    begin
      if Source[SrcPos] = '''' then
      begin
        Inc(SrcPos);
        if (SrcPos <= Length(Source)) and (Source[SrcPos] = '''') then
        begin
          AppendChar(s, '''');
          Inc(SrcPos);
        end
        else begin CurTok.Kind := tkString; CurTok.SVal := s; Exit; end;
      end
      else
      begin
        AppendChar(s, Source[SrcPos]);
        Inc(SrcPos);
      end;
    end;
    CurTok.Kind := tkString; CurTok.SVal := s; Exit;
  end;

  if c = '#' then
  begin
    s := '';
    while (SrcPos <= Length(Source)) and (Source[SrcPos] = '#') do
    begin
      Inc(SrcPos); n := 0;
      while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'9']) do
        begin n := n*10 + (Ord(Source[SrcPos])-48); Inc(SrcPos); end;
      AppendChar(s, Chr(n));
    end;
    CurTok.Kind := tkString; CurTok.SVal := s; Exit;
  end;

  Inc(SrcPos);
  case c of
    '+': CurTok.Kind := tkPlus;
    '-': CurTok.Kind := tkMinus;
    '*': CurTok.Kind := tkStar;
    '/': CurTok.Kind := tkSlash;
    '(': CurTok.Kind := tkLParen;
    ')': CurTok.Kind := tkRParen;
    '[': CurTok.Kind := tkLBrack;
    ']': CurTok.Kind := tkRBrack;
    ';': CurTok.Kind := tkSemicolon;
    ',': CurTok.Kind := tkComma;
    '@': CurTok.Kind := tkAt;
    '^': CurTok.Kind := tkCaret;
    '.': if (SrcPos <= Length(Source)) and (Source[SrcPos] = '.') then
           begin Inc(SrcPos); CurTok.Kind := tkDotDot; end
         else CurTok.Kind := tkDot;
    ':': if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then
           begin Inc(SrcPos); CurTok.Kind := tkAssign; end
         else CurTok.Kind := tkColon;
    '=': CurTok.Kind := tkEq;
    '<': if SrcPos <= Length(Source) then
           case Source[SrcPos] of
             '>': begin Inc(SrcPos); CurTok.Kind := tkNeq; end;
             '=': begin Inc(SrcPos); CurTok.Kind := tkLe;  end;
             else CurTok.Kind := tkLt;
           end
         else CurTok.Kind := tkLt;
    '>': if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then
           begin Inc(SrcPos); CurTok.Kind := tkGe; end
         else CurTok.Kind := tkGt;
    else Error('unexpected character');
  end;
end;

procedure LexAll;
var len, i: Integer; sval: AnsiString;
begin
  TokCharLen := 0;
  TokCount   := 0;
  repeat
    LexOne;
    if TokCount >= MAX_TOKENS then Error('token buffer overflow');
    Tokens[TokCount].Kind    := CurTok.Kind;
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
  until CurTok.Kind = tkEOF;
end;

function LexAppend(const srcText: AnsiString): Integer;
var
  savedSrcPos, savedSrcLine: Integer;
  len, i, unitStart: Integer;
  sval: AnsiString;
begin
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
    LexOne;
    if TokCount >= MAX_TOKENS then Error('token buffer overflow');
    Tokens[TokCount].Kind    := CurTok.Kind;
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
  until CurTok.Kind = tkEOF;

  Source := SavedLexSource;
  SrcPos := savedSrcPos;
  SrcLine := savedSrcLine;
  Result := unitStart;
end;

procedure InsertTokens(insertPos: Integer; const srcTokens: array of TRawToken; count: Integer);
var i: Integer;
begin
  if TokCount + count >= MAX_TOKENS then Error('token buffer overflow');
  { Shift right }
  for i := TokCount - 1 downto insertPos do
    Tokens[i + count] := Tokens[i];
  { Copy }
  for i := 0 to count - 1 do
    Tokens[insertPos + i] := srcTokens[i];
  Inc(TokCount, count);
end;

procedure Next;
var i, off, len, j: Integer;
begin
  if TokPos >= TokCount then begin CurTok.Kind := tkEOF; Exit; end;
  CurTok.Kind := Tokens[TokPos].Kind;
  CurTok.IVal := Tokens[TokPos].IVal;
  CurTok.Line := Tokens[TokPos].Line;
  CurTok.SVal := '';
  off := Tokens[TokPos].SOffset;
  len := Tokens[TokPos].SLen;
  i := 0;
  while i < len do
  begin
    j := off + i;
    AppendChar(CurTok.SVal, TokChars[j]);
    Inc(i);
  end;
  Inc(TokPos);
end;

function Eat(k: TTokenKind): Boolean;
begin Result := CurTok.Kind = k; if Result then Next; end;

procedure Expect(k: TTokenKind; const name: AnsiString);
var s2: AnsiString;
begin
  if CurTok.Kind <> k then
  begin
    s2 := CurTok.SVal;
    writeln('Expected: ', name, ', but got: ', s2, ' (Kind: ', Ord(CurTok.Kind),
            ', Line: ', CurTok.Line, ')');
    writeln('SrcPos: ', SrcPos);
    writeln('Ords around SrcPos: ', Ord(Source[SrcPos-2]), ' ', Ord(Source[SrcPos-1]), ' [', Ord(Source[SrcPos]), '] ', Ord(Source[SrcPos+1]), ' ', Ord(Source[SrcPos+2]));
    Error('unexpected token');
  end;
  Next;
end;
