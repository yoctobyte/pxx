
{ ===== Error ===== }

procedure Error(const msg: AnsiString);
begin
  writeln('pascal26:', CurTok.Line, ': error: ', msg, ' (', ErrorIdent, ')');
  Halt(1);
end;

{ ===== Lexer ===== }

function Keyword(const s: AnsiString): TTokenKind;
begin
  Result := tkIdent;
  if Length(s) = 2 then
  begin
    if (s[1]='i') and (s[2]='f') then Result := tkIf;
    if (s[1]='i') and (s[2]='n') then Result := tkIn;
    if (s[1]='I') and (s[2]='n') then Result := tkIn;
    if (s[1]='d') and (s[2]='o') then Result := tkDo;
    if (s[1]='t') and (s[2]='o') then Result := tkTo;
    if (s[1]='o') and (s[2]='f') then Result := tkOf;
    if (s[1]='o') and (s[2]='r') then Result := tkOr;
    if (s[1]='o') and (s[2]='n') then Result := tkOn;
    if (s[1]='O') and (s[2]='n') then Result := tkOn;
  end
  else if Length(s) = 3 then
  begin
    if (s[1]='a') and (s[2]='s') and (s[3]='m') then Result := tkAsm;
    if (s[1]='A') and (s[2]='s') and (s[3]='m') then Result := tkAsm;
    if (s[1]='A') and (s[2]='S') and (s[3]='M') then Result := tkAsm;
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
    if (s[1]='t') and (s[2]='r') and (s[3]='y') then Result := tkTry;
    if (s[1]='T') and (s[2]='r') and (s[3]='y') then Result := tkTry;
    if (s[1]='n') and (s[2]='i') and (s[3]='l') then Result := tkNil;
    if (s[1]='N') and (s[2]='i') and (s[3]='l') then Result := tkNil;
  end
  else if Length(s) = 4 then
  begin
    if (s[1]='w') and (s[2]='i') and (s[3]='t') and (s[4]='h') then Result := tkWith;
    if (s[1]='W') and (s[2]='i') and (s[3]='t') and (s[4]='h') then Result := tkWith;
    if (s[1]='W') and (s[2]='I') and (s[3]='T') and (s[4]='H') then Result := tkWith;
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
    if (s[1]='b') and (s[2]='r') and (s[3]='e') and (s[4]='a') and (s[5]='k') then Result := tkBreak;
    if (s[1]='B') and (s[2]='r') and (s[3]='e') and (s[4]='a') and (s[5]='k') then Result := tkBreak;
    if (s[1]='c') and (s[2]='o') and (s[3]='n') and (s[4]='s') and (s[5]='t') then Result := tkConst;
    if (s[1]='w') and (s[2]='h') and (s[3]='i') and (s[4]='l') and (s[5]='e') then Result := tkWhile;
    if (s[1]='u') and (s[2]='n') and (s[3]='t') and (s[4]='i') and (s[5]='l') then Result := tkUntil;
    if (s[1]='a') and (s[2]='r') and (s[3]='r') and (s[4]='a') and (s[5]='y') then Result := tkArray;
    if (s[1]='f') and (s[2]='a') and (s[3]='l') and (s[4]='s') and (s[5]='e') then Result := tkFalse;
    if (s[1]='F') and (s[2]='a') and (s[3]='l') and (s[4]='s') and (s[5]='e') then Result := tkFalse;
    if (s[1]='w') and (s[2]='r') and (s[3]='i') and (s[4]='t') and (s[5]='e') then Result := tkwrite;
    if (s[1]='c') and (s[2]='l') and (s[3]='a') and (s[4]='s') and (s[5]='s') then Result := tkClass;
    if (s[1]='C') and (s[2]='l') and (s[3]='a') and (s[4]='s') and (s[5]='s') then Result := tkClass;
    if (s[1]='r') and (s[2]='a') and (s[3]='i') and (s[4]='s') and (s[5]='e') then Result := tkRaise;
    if (s[1]='R') and (s[2]='a') and (s[3]='i') and (s[4]='s') and (s[5]='e') then Result := tkRaise;
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
    if (s[1]='e') and (s[2]='x') and (s[3]='c') and (s[4]='e') and (s[5]='p') and (s[6]='t') then Result := tkExcept;
    if (s[1]='E') and (s[2]='x') and (s[3]='c') and (s[4]='e') and (s[5]='p') and (s[6]='t') then Result := tkExcept;
    if (s[1]='s') and (s[2]='i') and (s[3]='n') and (s[4]='g') and (s[5]='l') and (s[6]='e') then Result := tkSingle_T;
    if (s[1]='S') and (s[2]='i') and (s[3]='n') and (s[4]='g') and (s[5]='l') and (s[6]='e') then Result := tkSingle_T;
    if (s[1]='d') and (s[2]='o') and (s[3]='u') and (s[4]='b') and (s[5]='l') and (s[6]='e') then Result := tkDouble_T;
    if (s[1]='D') and (s[2]='o') and (s[3]='u') and (s[4]='b') and (s[5]='l') and (s[6]='e') then Result := tkDouble_T;
  end
  else if Length(s) = 7 then
  begin
    if (s[1]='p') and (s[2]='r') and (s[3]='o') and (s[4]='g') and (s[5]='r') and (s[6]='a') and (s[7]='m') then Result := tkProgram;
    if (s[1]='f') and (s[2]='o') and (s[3]='r') and (s[4]='w') and (s[5]='a') and (s[6]='r') and (s[7]='d') then Result := tkForward;
    if (s[1]='f') and (s[2]='r') and (s[3]='e') and (s[4]='e') and (s[5]='m') and (s[6]='e') and (s[7]='m') then Result := tkFreeMem;
    if (s[1]='F') and (s[2]='r') and (s[3]='e') and (s[4]='e') and (s[5]='M') and (s[6]='e') and (s[7]='m') then Result := tkFreeMem;
    if (s[1]='w') and (s[2]='r') and (s[3]='i') and (s[4]='t') and (s[5]='e') and (s[6]='l') and (s[7]='n') then Result := tkwriteln;
    if (s[1]='s') and (s[2]='y') and (s[3]='s') and (s[4]='o') and (s[5]='p') and (s[6]='e') and (s[7]='n') then Result := tkSysOpen;
    if (s[1]='S') and (s[2]='y') and (s[3]='s') and (s[4]='O') and (s[5]='p') and (s[6]='e') and (s[7]='n') then Result := tkSysOpen;
    if (s[1]='s') and (s[2]='y') and (s[3]='s') and (s[4]='r') and (s[5]='e') and (s[6]='a') and (s[7]='d') then Result := tkSysRead;
    if (s[1]='S') and (s[2]='y') and (s[3]='s') and (s[4]='R') and (s[5]='e') and (s[6]='a') and (s[7]='d') then Result := tkSysRead;
    if (s[1]='i') and (s[2]='n') and (s[3]='t') and (s[4]='e') and (s[5]='g') and (s[6]='e') and (s[7]='r') then Result := tkInteger_T;
    if (s[1]='I') and (s[2]='n') and (s[3]='t') and (s[4]='e') and (s[5]='g') and (s[6]='e') and (s[7]='r') then Result := tkInteger_T;
    if (s[1]='b') and (s[2]='o') and (s[3]='o') and (s[4]='l') and (s[5]='e') and (s[6]='a') and (s[7]='n') then Result := tkBoolean_T;
    if (s[1]='B') and (s[2]='o') and (s[3]='o') and (s[4]='l') and (s[5]='e') and (s[6]='a') and (s[7]='n') then Result := tkBoolean_T;
    if (s[1]='f') and (s[2]='i') and (s[3]='n') and (s[4]='a') and (s[5]='l') and (s[6]='l') and (s[7]='y') then Result := tkFinally;
    if (s[1]='F') and (s[2]='i') and (s[3]='n') and (s[4]='a') and (s[5]='l') and (s[6]='l') and (s[7]='y') then Result := tkFinally;
  end
  else if Length(s) = 8 then
  begin
    if (s[1]='c') and (s[2]='o') and (s[3]='n') and (s[4]='t') and (s[5]='i') and (s[6]='n') and (s[7]='u') and (s[8]='e') then Result := tkContinue;
    if (s[1]='C') and (s[2]='o') and (s[3]='n') and (s[4]='t') and (s[5]='i') and (s[6]='n') and (s[7]='u') and (s[8]='e') then Result := tkContinue;
    if (s[1]='o') and (s[2]='v') and (s[3]='e') and (s[4]='r') and (s[5]='l') and (s[6]='o') and (s[7]='a') and (s[8]='d') then Result := tkOverload;
    if (s[1]='O') and (s[2]='v') and (s[3]='e') and (s[4]='r') and (s[5]='l') and (s[6]='o') and (s[7]='a') and (s[8]='d') then Result := tkOverload;
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
    if (s[1]='e') and (s[2]='x') and (s[3]='t') and (s[4]='e') and (s[5]='n') and (s[6]='d') and (s[7]='e') and (s[8]='d') then Result := tkExtended_T;
    if (s[1]='E') and (s[2]='x') and (s[3]='t') and (s[4]='e') and (s[5]='n') and (s[6]='d') and (s[7]='e') and (s[8]='d') then Result := tkExtended_T;
    if (s[1]='p') and (s[2]='r') and (s[3]='o') and (s[4]='p') and (s[5]='e') and (s[6]='r') and (s[7]='t') and (s[8]='y') then Result := tkProperty;
    if (s[1]='P') and (s[2]='r') and (s[3]='o') and (s[4]='p') and (s[5]='e') and (s[6]='r') and (s[7]='t') and (s[8]='y') then Result := tkProperty;
    if (s[1]='P') and (s[2]='R') and (s[3]='O') and (s[4]='P') and (s[5]='E') and (s[6]='R') and (s[7]='T') and (s[8]='Y') then Result := tkProperty;
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

{$ifdef FPC}
function StrToDoubleBits(const s: AnsiString): Int64;
var d: Double; code: Integer;
begin
  Val(s, d, code);
  Move(d, Result, 8);
end;
{$else}
function StrToDoubleBits(const s: AnsiString): Int64;
{ Pure-integer IEEE 754 double. ~18 significant digits.
  Subnormals flushed to zero; overflow = +/-Inf. No shl (not self-hostable). }
var
  i, len, fracDigits, expSign, expVal, decExp, bexp: Integer;
  hasDot: Boolean;
  coeff, N, D, mant, biasedExp, signBit, bitval, be: Int64;
  c: Char;
begin
  Result := 0;
  len := Length(s);
  if len = 0 then Exit;
  i := 1;
  signBit := 0;
  if s[i] = '-' then begin signBit := $8000000000000000; Inc(i); end
  else if s[i] = '+' then Inc(i);

  coeff := 0; fracDigits := 0; hasDot := False;
  while i <= len do
  begin
    c := s[i];
    if (c = '.') and not hasDot then begin hasDot := True; Inc(i); continue; end;
    if (c < '0') or (c > '9') then break;
    if coeff <= 999999999999999999 then
      coeff := coeff * 10 + (Ord(c) - 48);
    if hasDot then Inc(fracDigits);
    Inc(i);
  end;

  expSign := 1; expVal := 0;
  if (i <= len) and ((s[i] = 'e') or (s[i] = 'E')) then
  begin
    Inc(i);
    if (i <= len) and (s[i] = '-') then begin expSign := -1; Inc(i); end
    else if (i <= len) and (s[i] = '+') then Inc(i);
    while (i <= len) and (s[i] >= '0') and (s[i] <= '9') do
    begin
      expVal := expVal * 10 + (Ord(s[i]) - 48);
      Inc(i);
    end;
  end;

  decExp := expSign * expVal - fracDigits;
  if coeff = 0 then begin Result := signBit; Exit; end;

  N := coeff; D := 1; bexp := 0;
  if decExp >= 0 then
  begin
    while decExp > 0 do
    begin
      while N > 1844674407370955161 do begin N := N shr 1; Inc(bexp); end;
      N := N * 5;
      Inc(bexp);
      Dec(decExp);
    end;
  end
  else
  begin
    while decExp < 0 do
    begin
      if D > 922337203685477580 then
      begin
        N := N div 10;
        if N = 0 then begin Result := signBit; Exit; end;
      end
      else
        D := D * 10;
      Inc(decExp);
    end;
  end;

  { normalize N/D into [1,2): multiply by 2 instead of shl for self-hosting.
    Scale the denominator up rather than shifting N down — N shr 1 truncates
    N's low bit and corrupts odd coefficients (e.g. 3.5 -> 3.4). N >= D holds
    after the first loop, so N - D >= D is the overflow-safe form of N >= 2D.
    If D is too large to double safely, fall back to the lossy N shift (only
    reachable for extreme magnitudes where the low bit is below precision). }
  while N < D do begin N := N * 2; Dec(bexp); end;
  while (N - D) >= D do
  begin
    if D <= $3FFFFFFFFFFFFFFF then begin D := D * 2; Inc(bexp); end
    else begin N := N shr 1; Inc(bexp); end;
  end;

  if bexp > 1023 then begin Result := signBit or $7FF0000000000000; Exit; end;
  if bexp < -1022 then begin Result := signBit; Exit; end;

  N := N - D;
  mant := 0;
  bitval := $8000000000000;  { 2^51 = top mantissa bit }
  while bitval > 0 do
  begin
    N := N * 2;
    if N >= D then begin mant := mant or bitval; N := N - D; end;
    bitval := bitval shr 1;
  end;

  be := bexp + 1023; biasedExp := be * $10000000000000;  { be shl 52 }
  Result := signBit or biasedExp or mant;
end;
{$endif}

function PasDirectiveActive: Boolean;
begin
  if PasCondCount = 0 then Result := True
  else Result := PasCondActive[PasCondCount - 1];
end;

function PasDefineMatches(idx: Integer; const name: AnsiString): Boolean;
var i: Integer; c1, c2: Char; match: Boolean;
begin
  Result := False;
  if PasDefineNameLen[idx] = Length(name) then
  begin
    match := True;
    i := 0;
    while i < PasDefineNameLen[idx] do
    begin
      c1 := PasDefineChars[PasDefineNameOff[idx] + i];
      c2 := name[i + 1];
      if (c1 >= 'A') and (c1 <= 'Z') then c1 := Chr(Ord(c1) + 32);
      if (c2 >= 'A') and (c2 <= 'Z') then c2 := Chr(Ord(c2) + 32);
      if c1 <> c2 then match := False;
      Inc(i);
    end;
    Result := match;
  end;
end;

function PasDefineExists(const name: AnsiString): Boolean;
var i: Integer;
begin
  Result := False;
  i := 0;
  while i < PasDefineCount do
  begin
    if PasDefineActive[i] and PasDefineMatches(i, name) then Result := True;
    Inc(i);
  end;
end;

procedure PasDefine(const name: AnsiString);
var i, j, len: Integer;
begin
  if name = '' then Exit;
  if PasDefineExists(name) then Exit;
  i := 0;
  while i < PasDefineCount do
  begin
    if PasDefineMatches(i, name) then
    begin
      PasDefineActive[i] := True;
      Exit;
    end;
    Inc(i);
  end;
  if PasDefineCount >= MAX_PAS_DEFINES then Error('too many Pascal defines');
  len := Length(name);
  if PasDefineCharLen + len >= MAX_PAS_DEFINE_CHARS then Error('Pascal define storage overflow');
  PasDefineNameOff[PasDefineCount] := PasDefineCharLen;
  PasDefineNameLen[PasDefineCount] := len;
  PasDefineActive[PasDefineCount] := True;
  j := 1;
  while j <= len do
  begin
    PasDefineChars[PasDefineCharLen] := name[j];
    Inc(PasDefineCharLen);
    Inc(j);
  end;
  Inc(PasDefineCount);
end;

procedure PasUndefine(const name: AnsiString);
var i: Integer;
begin
  if CaseEqual(name, 'PXX') then Exit;
  i := 0;
  while i < PasDefineCount do
  begin
    if PasDefineMatches(i, name) then PasDefineActive[i] := False;
    Inc(i);
  end;
end;

function PasOptionTail(const value: AnsiString; first: Integer): AnsiString;
var i: Integer;
begin
  Result := '';
  i := first;
  while i <= Length(value) do
  begin
    AppendChar(Result, value[i]);
    Inc(i);
  end;
end;

procedure PasInitDefines;
var name: AnsiString;
begin
  PasDefineCharLen := 0;
  PasDefineCount := 0;
  PasCondCount := 0;
  StrictOverload := False;
  CStyleComments := False;
  NestedComments := False;
  CaseSensitiveMode := False;
  name := 'PXX';
  PasDefine(name);
  name := 'CPU64';
  PasDefine(name);
  name := 'CPUX86_64';
  PasDefine(name);
  name := 'LINUX';
  PasDefine(name);
end;

procedure PasDefineCommandOption(first: Integer);
var name: AnsiString;
begin
  name := PasOptionTail(PasCommandOption, first);
  PasDefine(name);
end;

procedure PasUndefineCommandOption(first: Integer);
var name: AnsiString;
begin
  name := PasOptionTail(PasCommandOption, first);
  PasUndefine(name);
end;

function PasObjFpcModeOption: Boolean;
var name: AnsiString;
begin
  name := PasOptionTail(PasCommandOption, 3);
  Result := CaseEqual(name, 'objfpc');
end;

procedure ReadPasDirectiveWord(var word: AnsiString);
begin
  word := '';
  while (SrcPos <= Length(Source)) and
        (Source[SrcPos] in [' ', #9, #13, #10]) do
  begin
    if Source[SrcPos] = #10 then Inc(SrcLine);
    Inc(SrcPos);
  end;
  while (SrcPos <= Length(Source)) and
        (Source[SrcPos] in ['a'..'z','A'..'Z','0'..'9','_']) do
  begin
    AppendChar(word, Source[SrcPos]);
    Inc(SrcPos);
  end;
end;

procedure ReadPasDirectiveFile(var word: AnsiString);
{ Like ReadPasDirectiveWord but for a filename: keep dots, slashes, dashes. }
begin
  word := '';
  while (SrcPos <= Length(Source)) and
        (Source[SrcPos] in [' ', #9, #13, #10]) do
  begin
    if Source[SrcPos] = #10 then Inc(SrcLine);
    Inc(SrcPos);
  end;
  while (SrcPos <= Length(Source)) and
        not (Source[SrcPos] in [' ', #9, #13, #10, '}']) do
  begin
    AppendChar(word, Source[SrcPos]);
    Inc(SrcPos);
  end;
end;

function ResEndsWithDotRes(const s: AnsiString): Boolean;
{ True for a '*.res'-style compiled-resource file, which we treat as a no-op
  (Lazarus .res holds PE/COFF version info + icons we don't consume). }
var n: Integer;
begin
  n := Length(s);
  ResEndsWithDotRes :=
    (n >= 4) and (s[n-3] = '.') and
    ((s[n-2] = 'r') or (s[n-2] = 'R')) and
    ((s[n-1] = 'e') or (s[n-1] = 'E')) and
    ((s[n] = 's') or (s[n] = 'S'));
end;

function ResolveWildcardFile(const f: AnsiString): AnsiString;
{ Resolve a leading '*' in a $R filename to the current source base name:
  '*.lfm' in main.pas -> 'main.lfm'. Non-wildcard names pass through. }
var i: Integer; r: AnsiString;
begin
  if (Length(f) >= 1) and (f[1] = '*') then
  begin
    r := CurSrcBaseName;
    for i := 2 to Length(f) do AppendChar(r, f[i]);
    ResolveWildcardFile := r;
  end
  else
    ResolveWildcardFile := f;
end;

procedure ProcessPasDirective;
var command, name, fname: AnsiString; parent, cond: Boolean; idx: Integer;
begin
  Inc(SrcPos); { dollar sign }
  ReadPasDirectiveWord(command);
  ReadPasDirectiveWord(name);
  { Resource directive (R name file): capture the filename before skipping. }
  fname := '';
  if CaseEqual(command, 'R') and PasDirectiveActive then
    ReadPasDirectiveFile(fname);
  while (SrcPos <= Length(Source)) and (Source[SrcPos] <> '}') do
  begin
    if Source[SrcPos] = #10 then Inc(SrcLine);
    Inc(SrcPos);
  end;
  if SrcPos <= Length(Source) then Inc(SrcPos);

  if CaseEqual(command, 'ifdef') or CaseEqual(command, 'ifndef') then
  begin
    if PasCondCount >= MAX_PAS_CONDS then Error('conditional directive nesting overflow');
    parent := PasDirectiveActive;
    cond := PasDefineExists(name);
    if CaseEqual(command, 'ifndef') then cond := not cond;
    PasCondParent[PasCondCount] := parent;
    PasCondActive[PasCondCount] := parent and cond;
    PasCondTaken[PasCondCount] := parent and cond;
    Inc(PasCondCount);
  end
  else if CaseEqual(command, 'else') then
  begin
    if PasCondCount = 0 then Error('unexpected else directive');
    idx := PasCondCount - 1;
    PasCondActive[idx] := PasCondParent[idx] and not PasCondTaken[idx];
    PasCondTaken[idx] := True;
  end
  else if CaseEqual(command, 'endif') then
  begin
    if PasCondCount = 0 then Error('unexpected endif directive');
    Dec(PasCondCount);
  end
  else if PasDirectiveActive then
  begin
    if CaseEqual(command, 'define') then PasDefine(name)
    else if CaseEqual(command, 'undef') then PasUndefine(name)
    else if CaseEqual(command, 'strict_overload') then
    begin
      if CaseEqual(name, 'on') then StrictOverload := True
      else if CaseEqual(name, 'off') then StrictOverload := False
      else Error('strict_overload requires on or off');
    end
    else if CaseEqual(command, 'cstylecomments') then
    begin
      if CaseEqual(name, 'on') then CStyleComments := True
      else if CaseEqual(name, 'off') then CStyleComments := False
      else Error('cstylecomments requires on or off');
    end
    else if CaseEqual(command, 'nestedcomments') then
    begin
      if CaseEqual(name, 'on') then NestedComments := True
      else if CaseEqual(name, 'off') then NestedComments := False
      else Error('nestedcomments requires on or off');
    end
    else if CaseEqual(command, 'casesensitive') then
    begin
      if CaseEqual(name, 'on') then CaseSensitiveMode := True
      else if CaseEqual(name, 'off') then CaseSensitiveMode := False
      else Error('casesensitive requires on or off');
    end
    else if CaseEqual(command, 'R') then
    begin
      { R-directive (name file): queue an embedded resource; EmitResources
        reads the file and builds the table after parsing. A leading '*' in the
        filename resolves to the current unit base ($R *.lfm -> unit.lfm);
        a '*.res' compiled-resource file is a no-op. When the name field is
        empty (the wildcard form), EmitResources derives it from the .lfm root
        object's class. }
      if Length(fname) > 0 then
      begin
        fname := ResolveWildcardFile(fname);
        if not ResEndsWithDotRes(fname) then
        begin
          if ResPendCount >= MAX_RESOURCES then Error('too many {$R} resources');
          ResPendName[ResPendCount] := name;
          ResPendFile[ResPendCount] := fname;
          Inc(ResPendCount);
        end;
      end;
    end;
    { Mode and unsupported compatibility directives remain accepted comments. }
  end;
  if DebugTrace and (command <> '') then writeln('Pascal directive: ', command, ' ', name);
end;

procedure SkipSpace;
var commentDepth: Integer; cDone: Boolean;
begin
  if DebugTrace then writeln('Entering SkipSpace. SrcPos = ', SrcPos, ' Length(Source) = ', Length(Source));
  while SrcPos <= Length(Source) do
  begin
    if not PasDirectiveActive then
    begin
      if (Source[SrcPos] = '{') and (SrcPos < Length(Source)) and
         (Source[SrcPos + 1] = '$') then
      begin
        Inc(SrcPos);
        ProcessPasDirective;
      end
      else
      begin
        if Source[SrcPos] = #10 then Inc(SrcLine);
        Inc(SrcPos);
      end;
    end
    else
      case Source[SrcPos] of
        ' ', #9, #13: Inc(SrcPos);
        #10: begin Inc(SrcLine); Inc(SrcPos); end;
        '{':
        begin
          Inc(SrcPos);
          if (SrcPos <= Length(Source)) and (Source[SrcPos] = '$') then
            ProcessPasDirective
          else
          begin
            { Brace comment. With NestedComments on, an inner open-brace raises
              the depth so the matching close-brace ends the right level; off
              (default) keeps the historic flat scan ending at the first one. }
            commentDepth := 1;
            while (SrcPos <= Length(Source)) and (commentDepth > 0) do
            begin
              if Source[SrcPos] = #10 then Inc(SrcLine)
              else if NestedComments and (Source[SrcPos] = '{') then Inc(commentDepth)
              else if Source[SrcPos] = '}' then Dec(commentDepth);
              Inc(SrcPos);
            end;
          end;
        end;
        '(':
          if (SrcPos+1 <= Length(Source)) and (Source[SrcPos+1] = '*') then
          begin
            Inc(SrcPos, 2);
            { Paren-star comment. Nests under NestedComments. Must fall through
              to the outer loop when it ends (not Exit) so code on the same line
              after the close is still skipped. }
            commentDepth := 1;
            while (SrcPos+1 <= Length(Source)) and (commentDepth > 0) do
            begin
              if (Source[SrcPos] = '*') and (Source[SrcPos+1] = ')') then
                begin Dec(commentDepth); Inc(SrcPos, 2); end
              else if NestedComments and (Source[SrcPos] = '(') and (Source[SrcPos+1] = '*') then
                begin Inc(commentDepth); Inc(SrcPos, 2); end
              else
              begin
                if Source[SrcPos] = #10 then Inc(SrcLine);
                Inc(SrcPos);
              end;
            end;
          end
          else Exit;
        '/':
          if (SrcPos+1 <= Length(Source)) and (Source[SrcPos+1] = '/') then
            while (SrcPos <= Length(Source)) and (Source[SrcPos] <> #10) do Inc(SrcPos)
          else if CStyleComments and (SrcPos+1 <= Length(Source)) and (Source[SrcPos+1] = '*') then
          begin
            { C-style slash-star comment, enabled by CStyleComments. Does not
              nest, matching C. }
            Inc(SrcPos, 2);
            cDone := False;
            while (SrcPos+1 <= Length(Source)) and not cDone do
            begin
              if (Source[SrcPos] = '*') and (Source[SrcPos+1] = '/') then
                begin Inc(SrcPos, 2); cDone := True; end
              else
              begin
                if Source[SrcPos] = #10 then Inc(SrcLine);
                Inc(SrcPos);
              end;
            end;
          end
          else Exit;
        else Exit;
      end;
  end;
end;

procedure LexOne;
var
{$ifdef FPC}
  c: Char;
{$else}
  c: Integer;
{$endif}
  s: AnsiString;
  n: Int64;
  floatStart, fpos: Integer;
begin
  if DebugTrace then writeln('Entering Next. SrcPos = ', SrcPos);
  SkipSpace;
  CurTok.Line := SrcLine; CurTok.SVal := '';
  if SrcPos > Length(Source) then
  begin
    if PasCondCount > 0 then Error('unterminated conditional directive');
    CurTok.Kind := tkEOF;
    Exit;
  end;
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
    floatStart := SrcPos;
    while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'9']) do
      begin n := n*10 + (Ord(Source[SrcPos])-48); Inc(SrcPos); end;
    { detect float: '.' followed by digit, or e/E exponent }
    if ((SrcPos < Length(Source)) and (Source[SrcPos] = '.') and (Source[SrcPos+1] in ['0'..'9'])) or
       ((SrcPos <= Length(Source)) and ((Source[SrcPos] = 'e') or (Source[SrcPos] = 'E'))) then
    begin
      if (SrcPos < Length(Source)) and (Source[SrcPos] = '.') and (Source[SrcPos+1] in ['0'..'9']) then
      begin
        Inc(SrcPos);
        while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'9']) do Inc(SrcPos);
      end;
      if (SrcPos <= Length(Source)) and ((Source[SrcPos] = 'e') or (Source[SrcPos] = 'E')) then
      begin
        Inc(SrcPos);
        if (SrcPos <= Length(Source)) and ((Source[SrcPos] = '+') or (Source[SrcPos] = '-')) then Inc(SrcPos);
        while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'9']) do Inc(SrcPos);
      end;
      s := ''; fpos := floatStart;
      while fpos < SrcPos do begin AppendChar(s, Source[fpos]); Inc(fpos); end;
      CurTok.Kind := tkFloat; CurTok.IVal := StrToDoubleBits(s); Exit;
    end;
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
