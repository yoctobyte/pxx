program test_case_of_string;
{ case-of-string: full-string equality + lexicographic ranges, plus the char
  selector keeping the ordinal path. Regression for
  bug-case-of-string-segfault-and-label-validation (labels used to collapse to
  Ord(SVal[1]) and the string selector was compared as a char -> SIGSEGV). }
var
  s: AnsiString;
  n: Integer;

function Sel(const x: string): Integer;
begin
  case x of
    '': Result := 1;
    'a': Result := 2;
    'ba'..'bz': Result := 3;
    'cab': Result := 4;
    else Result := 0;
  end;
end;

function SelChar(c: Char): Integer;
begin
  case c of
    'a'..'w': Result := 1;
    'x': Result := 2;
    else Result := 0;
  end;
end;

begin
  writeln(Sel(''));      { 1 }
  writeln(Sel('a'));     { 2 }
  writeln(Sel('bq'));    { 3: inside 'ba'..'bz' }
  writeln(Sel('b'));     { 0: below the range }
  writeln(Sel('bzz'));   { 0: above the range }
  writeln(Sel('cab'));   { 4 }
  writeln(Sel('zzz'));   { 0: else }
  s := 'cab';
  case s of
    'a'..'b': n := 1;
    'cab': n := 2;
    else n := 0;
  end;
  writeln(n);            { 2: AnsiString selector, char-literal range bounds }
  s := 'ab';
  case s of
    'a'..'b': n := 1;    { lexicographic: 'a' < 'ab' < 'b' }
    else n := 0;
  end;
  writeln(n);            { 1 }
  writeln(SelChar('x')); { 2: char selector unchanged }
end.
