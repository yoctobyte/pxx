{ The assignment type check must reach an EXPRESSION RESULT, not just a literal
  or an identifier. Every row below is a BINOP on the right-hand side, and each
  one was ACCEPTED before AssignSideKind grew its AN_BINOP arm -- not refused
  and not diagnosed, but never CHECKED: the function returned False for a shape
  it could not type, and the `and` chain short-circuited, which looks exactly
  like a check that fired and passed.

  What that cost: `c := s + 'x'` compiled to a byte move of a string HANDLE's
  low byte into a Char and printed garbage. Through a nested dynamic-array
  field, whose element mis-types, the same accepted write went through a bogus
  slot and SIGSEGV'd.

  The COUNT is the assertion, as for the two sibling files -- the check recovers,
  so one compile must report every row rather than stopping at the first, and a
  plain grep would be satisfied by a check that halted after row one.
  fpc 3.2.2 rejects all six. }
program test_assign_expr_result_fail;
type TR = record a: Integer; end;
var c: Char; s: AnsiString; i: Integer; r: TR; b: Boolean;
begin
  s := 'ab'; i := 1; b := True; r.a := 0;
  c := s + 'x';        { AnsiString expression -> Char }
  c := s + s;          { same, both sides dynamic }
  s := i + 1;          { Integer expression -> AnsiString }
  r := s + 'x';        { AnsiString expression -> record }
  s := b and b;        { Boolean expression -> AnsiString }
  i := s + 'x';        { AnsiString expression -> Integer }
  WriteLn(c, s, i, r.a);
end.
