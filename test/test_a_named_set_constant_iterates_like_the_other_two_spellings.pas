{ A named SET CONSTANT as a `for ... in` source. Set iteration was already here
  and already correct -- a set VARIABLE and a bare `[a, b]` constructor both walk
  the members in ORDINAL order and match fpc 3.2.2 -- so this is not the feature,
  it is the THIRD SPELLING of it. A named set constant lives in the SetConst
  table and not in Syms, so the bare-name arm that resolves an iterable variable
  could never see one; it fell through to `for-in: not a generator, enum type, or
  iterable variable`, which is true and names none of the three things it is.

  ALL THREE SPELLINGS ARE IN THIS ONE FILE, DELIBERATELY. The claim is not "a set
  constant iterates" -- it is "a set constant iterates the SAME WAY the two
  working spellings do". Split across two files each would print a plausible run
  of ordinals and neither would be anomalous on its own; side by side, a spelling
  that diverges is visible as a difference rather than as a number someone has to
  already know. (frankD's rule, from the shadowed-intrinsic work: two files would
  each print a plausible number.)

  NO ROW'S EXPECTED VALUE IS THE FULL RANGE. `[clRed, clBlue]` is 0 and 2, not
  0 1 2, so a bug that ignored the mask and walked the element type's whole range
  -- which is exactly what the scan loop does before the `in` test filters it --
  still prints ascending ordinals and is caught only because a member is MISSING
  from the middle. The `ns` row is declared out of order, `[9, 3, 5]`, because
  ordinal order is the property under test and source order would print the same
  three numbers.

  The char rows print LETTERS: an element kind resolved as ordinal rather than
  Char prints 98 100 102, which is a visibly different answer and not a subtly
  wrong one. }
program test_a_named_set_constant_iterates_like_the_other_two_spellings;
type
  TColor = (clRed, clGreen, clBlue);
  TColors = set of TColor;
const
  cs  = [clRed, clBlue];
  ns  = [9, 3, 5];
  chs = ['d', 'b', 'f'];
var
  v: TColors;
  c: TColor;
  i: LongInt;
  ch: Char;
begin
  { the two spellings that already worked, as the comparison }
  v := [clRed, clBlue];
  Write('var   :'); for c in v do Write(' ', Ord(c)); Writeln;
  Write('lit   :'); for c in [clRed, clBlue] do Write(' ', Ord(c)); Writeln;

  { …and the one this change adds. Same members, so the three rows must agree. }
  Write('const :'); for c in cs do Write(' ', Ord(c)); Writeln;

  { the head of an EXPRESSION, not just a bare name: the trigger is the set
    constant at the head and ParseExpr takes the rest, so a union reads its mask
    the same way `x in cs + [clGreen]` does. This row is the whole range, and it
    is the one row where that is the right answer rather than the failure value
    -- the rows above are what make it readable. }
  Write('union :'); for c in cs + [clGreen] do Write(' ', Ord(c)); Writeln;

  { an ordinal set constant, declared OUT of order }
  Write('ord   :'); for i in ns do Write(' ', i); Writeln;

  { a Char set constant, also out of order }
  Write('char  :'); for ch in chs do Write(' ', ch); Writeln;

  { empty set: the loop body must not run at all. This row can only report that
    it printed nothing, which is why it is last and labelled. }
  v := [];
  Write('empty :'); for c in v do Write(' ', Ord(c)); Writeln;
end.
