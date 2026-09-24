{ MUST NOT COMPILE. `var x: Int64` takes the caller's address and the callee
  writes eight bytes through it; handed a LongInt, the other four land on the
  frame's neighbour -- this printed `a=-1 guard=-1`, a variable the program
  never passed. fpc: "Call by var for arg no. 1 has to match exactly".
  The METHOD spelling is the call here on purpose: the plain and overloaded
  paths were covered first, and the method path was the one that slipped.
  bug-p-a-var-parameter-accepts-a-narrower-actual-and-writes-past-it }
program test_var_param_refuses_a_narrower_variable;
{$mode objfpc}
type
  TC = class
    procedure M(var x: Int64);
  end;
procedure TC.M(var x: Int64); begin x := -1; end;
var guard, a: LongInt; o: TC;
begin
  guard := 12345; a := 0;
  o := TC.Create;
  o.M(a);
  writeln('a=', a, ' guard=', guard);
end.
