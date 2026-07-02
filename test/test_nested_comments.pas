program test_nested_comments;
{ FPC-parity comment nesting (verified against FPC 3.2.2): same-type brace
  comments nest by default in fpc/objfpc modes { like this { and this } still
  comment } — historically pxx closed at the first close-brace (the
  "asmcore targets" landmine). Delphi mode and NESTEDCOMMENTS OFF keep the
  flat behavior; mixed-delimiter one-level nesting is inertness and always
  worked. }
(* paren-star with { inert brace } inside *)
{ brace with (* inert paren-star *) inside }
var n: Integer;
begin
  n := 1 { one { nested } still one } + 2;
  writeln(n);
  writeln('NESTED COMMENTS OK');
end.
