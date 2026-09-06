program test_generic_routine_type_parameter_arity;
{ A generic ROUTINE may declare more than one type parameter.

  `generic procedure Pair<T, S>(a: T; b: S)` was refused at its IMPLEMENTATION
  header with `expected '>' before ','`, which pointed at the wrong section --
  the interface line is buffered rather than parsed there, so neither form was
  supported and the reader was told the two lines differed. Generic CLASSES have
  always taken several, which is what said this was routines only.
  bug-p-a-generic-routine-supports-exactly-one-type-parameter

  .expected is fpc 3.2.2's own output.

  ROW D IS THE ONE THAT MATTERS AND IT IS WHY THE ROWS ARE NOT ALL ONE ARITY.
  `Pair<string, Integer>` and `Pair<Integer, string>` must be two DIFFERENT
  specializations. A key built from the argument list distinguishes them; a key
  built from the first argument, or from the template name alone, does not --
  and either of those degenerate keys still prints every other row here
  correctly. Row D is the only row that can fail if the mangled name stops
  carrying the whole list.

  ROW A IS THE REGRESSION CONTROL. One type parameter is the shape that already
  worked; the change rewrote the matcher and the substitution load that serve
  it, so a file testing only the new arities cannot tell a fix from a fix that
  broke the old case.

  ROW F IS THE GUARD WITH TEETH. The bare `F<A, B>(` use surface is spelled the
  same as a comparison chain, so widening the matcher from one argument to a
  comma-separated LIST widens exactly the pattern that can eat `a < b > (c)`.
  It asserts real comparisons still evaluate as comparisons.

  Not asserted here, verified separately: the Delphi surface
  `function Combine<T, S>(a: T; b: S): Integer` agrees with fpc when the result
  is assigned through `Result` (fpc refuses the `Combine :=` spelling of its own
  accord, reading the function's own name as the generic template -- we accept
  it, which is not a defect), and an arity mismatch under the `specialize`
  keyword is refused with `generic routine Pair takes 2 type argument(s), not
  1`. Both are compile-time outcomes rather than printed values. That refusal
  is asserted in test_generic_routine_arity_with_no_such_overload_fail.pas, and
  it holds only when NOTHING declares the name at the arity asked for -- a name
  overloaded across type-parameter counts is legal, and is
  test_generic_routine_overloaded_on_type_parameter_count.pas. }
{$mode objfpc}
uses ugra;
var a, b, c: Integer;
begin
  { A — one type parameter: the shape that already worked }
  specialize Solo<Integer>(5);

  { B, C — two and three }
  specialize Pair<Integer, string>(7, 'hi');
  specialize Trio<Integer, string, Boolean>(1, 'two', True);

  { D — the SWAPPED instantiation: a different tuple is a different
    specialization, and this is the only row that says the key carries the
    whole list }
  specialize Pair<string, Integer>('swap', 9);

  { E — the same specialization asked for twice: one routine, not two }
  specialize Pair<Integer, string>(7, 'again');

  { F — comparisons must still be comparisons }
  a := 1; b := 2; c := 3;
  WriteLn('cmp=', (a < b), ' ', (b > c));
end.
