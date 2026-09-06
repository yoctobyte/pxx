program test_a_dynamic_array_concatenates_with_an_element_list;

{$mode objfpc}
{$modeswitch arrayoperators}
{$COperators on}

{ `a + [4]`, `[0] + a`, `a += [5]`, `Concat(a, [x])`. fpc-testsuite tarray17.

  An element list arrives as a SET -- `[...]` is a set until something names its
  element type -- and the something is normally the assignment's left-hand side.
  In a concatenation there is no assignment to ask: `Concat(a, [6])` is an
  argument and `a += [5]` has the array on the other side of the operator. So
  the SIBLING OPERAND names it, which is the same retag the assignment and
  `TDynArr.Create(...)` already use.

  VALUES ARE DISTINCT AND ASCENDING ON PURPOSE. A concatenation that dropped an
  operand, reversed one, or spliced at the wrong index still produces an array
  of plausible length, so every row prints the CONTENTS and not only Length --
  and no two elements are equal, so a mis-ordering cannot look like a match.

  THE `+ []` ROW IS THE IDENTITY CASE AND IS MARKED AS ONE. It is the argument
  on which concatenation and its absence agree, so it can only ever report that
  the call compiles. It is here to pin that fpc and pxx agree about the empty
  list, never as evidence that concatenation works. }

function Show(const r: array of LongInt): AnsiString;
var i: LongInt; s, d: AnsiString;
begin
  s := '[';
  for i := 0 to High(r) do
  begin
    if i > 0 then s := s + ',';
    Str(r[i], d);
    s := s + d;
  end;
  Str(Length(r), d);
  Show := s + '] n=' + d;
end;

var
  a, b, c: array of LongInt;
begin
  a := [1, 2, 3];
  b := [7, 8];

  WriteLn('base        ', Show(a));
  WriteLn('a+[4]       ', Show(a + [4]));
  c := [0] + a;
  WriteLn('[0]+a       ', Show(c));
  WriteLn('a+b         ', Show(a + b));
  WriteLn('b+a         ', Show(b + a));
  WriteLn('a+[4,5,6]   ', Show(a + [4, 5, 6]));
  c := [9] + ([0] + a);
  WriteLn('[9]+[0]+a   ', Show(c));

  { the operand list must not be mutated by the concatenation }
  WriteLn('a unchanged ', Show(a));
  WriteLn('b unchanged ', Show(b));

  { the Concat door, both orders and a mixed pair }
  WriteLn('Cc(a,[4])   ', Show(Concat(a, [4])));
  c := Concat([0], a);
  WriteLn('Cc([0],a)   ', Show(c));
  WriteLn('Cc(a,b)     ', Show(Concat(a, b)));

  { compound assignment: rewritten to `a := a + e`, both operand shapes }
  c := [1];
  c += [2];
  WriteLn('c+=[2]      ', Show(c));
  c += b;
  WriteLn('c+=b        ', Show(c));
  c += [3, 4];
  WriteLn('c+=[3,4]    ', Show(c));

  { A LEADING bracket used to be bound through a variable here because it could
    not be written inline: `Show([0] + a)` was REFUSED -- `expected comma or
    close parenthesis` -- since a `[` at the HEAD of an argument was consumed as
    the whole argument and could never become an operator's left operand. The
    rows above still bind through a variable on purpose, so that what they
    assert is CONCATENATION and not the argument door.

    THE DOOR IS FIXED (frankB, 2026-09-06) and the inline spelling is asserted in the
    door's own fixture rather than here: the
    door's own fixture is
    test_a_bracket_at_the_head_of_an_argument_is_an_operators_left_operand.pas,
    which asks every call path and carries the inline spelling. Deliberately NOT
    added here: this file has a .expected, so a new row is a second seat editing
    a fixture's recorded output, and the rows it already has assert the thing
    this file is named for.
    bug-p-a-bracket-at-the-head-of-an-argument-cannot-be-an-operators-left-operand }
  { IDENTITY ROW -- see the header. Reports only that the call compiles. }
  WriteLn('a+[] ident  ', Show(a + []));
end.
