program test_ctor_arity_error;
{ Constructor arity is checked at compile time (FPC parity). A missing
  required argument used to compile silently and desync the caller's stack
  by 8 bytes in the ctor marshalling (pops ParamCount registers regardless
  of how many were pushed) — garbage-Self nondeterministic crashes
  (bug-tthread-execute-writeln-crash). This file must NOT compile. }
type TC = class
  a: Integer;
  constructor Create(x: Boolean);
end;
constructor TC.Create(x: Boolean);
begin a := 1; end;
var c: TC;
begin
  c := TC.Create;    { missing required argument }
end.
