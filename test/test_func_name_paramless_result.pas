program test_func_name_paramless_result;

{ The paramless flip (bug-bare-function-name-call-vs-resultvar): a bare own-name
  read inside a PARAMLESS function's body is the result variable (FPC-faithful),
  NOT a recursive call. Recursion now requires explicit `F()`. Validated equal to
  FPC: `Gate` reads its own result var (no recursion → no infinite loop), `Fib`
  recurses only via `Fib(n)`. }

var calls: Integer;

function Gate: Integer;
begin
  Inc(calls);
  if calls < 3 then Gate := Gate   { read result var (0), NOT recurse }
  else Gate := 42;
end;

function Plain: Integer;
begin
  Plain := 7;
  Plain := Plain + 1;              { bare read = result var → 8 }
end;

function Fib(n: Integer): Integer;
begin
  if n < 2 then Fib := n
  else Fib := Fib(n - 1) + Fib(n - 2);   { paren recursion unaffected }
end;

begin
  calls := 0;
  WriteLn(Gate, ' ', calls);   { 0 1 }
  WriteLn(Plain);              { 8 }
  WriteLn(Fib(10));            { 55 }
end.
