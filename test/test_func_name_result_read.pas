program test_func_name_result_read;

{ Bare function name read as a value inside the function's own body = the result
  variable (FPC `FuncName` synonym for `Result`), for functions WITH parameters
  (the unambiguous case: a bare name with no parens cannot be a call). Recursion
  via `F(args)` still works. Paramless bare-own-name stays a recursive call in
  PXX (see bug-bare-function-name-call-vs-resultvar) and is not exercised here. }

function Accum(n: Integer): Integer;
begin
  Accum := n;
  if n > 0 then Accum := Accum + n * 10;   { read own name as result }
end;

function Tag(const s: AnsiString): AnsiString;
begin
  Tag := s;
  Tag := Tag + '!';                         { managed-string result read }
end;

function Fact(n: Integer): Integer;
begin
  if n <= 1 then Fact := 1
  else Fact := n * Fact(n - 1);             { recursion via () unaffected }
end;

begin
  WriteLn(Accum(3));     { 33 }
  WriteLn(Accum(0));     { 0 }
  WriteLn(Tag('hi'));    { hi! }
  WriteLn(Fact(5));      { 120 }
end.
