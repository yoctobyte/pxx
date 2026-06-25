program test_string_ordering;
{ Regression: AnsiString < <= > >= must be real lexicographic order, not a
  constant (bug-string-ordering-comparison-constant). =/<> were already correct. }
var a, b: AnsiString;
begin
  a := 'b'; b := 'a';
  writeln(Ord(a > b), Ord(a < b), Ord(a >= b), Ord(a <= b),
          Ord(a = b), Ord(a <> b));            { 1 0 1 0 0 1 }

  a := 'apple'; b := 'apply';
  writeln(Ord(a < b), Ord(a > b));             { 1 0 }

  a := 'abc'; b := 'abc';
  writeln(Ord(a < b), Ord(a <= b), Ord(a >= b), Ord(a > b),
          Ord(a = b), Ord(a <> b));            { 0 1 1 0 1 0 }

  a := 'ab'; b := 'abc';                        { prefix: shorter is less }
  writeln(Ord(a < b), Ord(a > b), Ord(b > a));  { 1 0 1 }

  a := ''; b := 'x';                            { empty is least }
  writeln(Ord(a < b), Ord(b > a), Ord(a > b));  { 1 1 0 }
end.
