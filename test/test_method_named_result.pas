program test_method_named_result;
{ Assigning to a method's own name (function-name-as-result) inside a method
  body used to segfault: the bare name resolved to a self method-call instead
  of the result slot, because Procs[].Name for a method is 'TClass.Method'.
  Fixed by matching the method short name (after last '.') with a ':=' lookahead.
  Covers recursion (Self.Fac and bare Fac) and a string-typed named result. }
type
  TC = class
  public
    function Fac(n: Integer): Integer;
    function Greet(s: string): string;
  end;
function TC.Fac(n: Integer): Integer;
begin
  if n <= 1 then Fac := 1
  else Fac := n * Fac(n - 1);
end;
function TC.Greet(s: string): string;
begin
  Greet := 'Hi ' + s;
end;
var c: TC;
begin
  c := TC.Create;
  writeln(c.Fac(5));
  writeln(c.Greet('Bob'));
end.
