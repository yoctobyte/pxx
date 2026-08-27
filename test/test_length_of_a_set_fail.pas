{ %fail }
{ A set has no length, and FPC says so — `Type mismatch`.

  pxx fell through to the runtime Length path, which read the 32-byte bitset as
  a string handle and answered the low word of the BITMASK: `s := [1,2];
  Length(s)` printed 6, `[5,9]` printed 544, a char set printed 0. A small set
  produces a small plausible number, which is how it survived.

  Refused rather than given a meaning: FPC has no `Length(set)`, so any answer
  invented here would be pxx-only, and a caller almost certainly means the
  element COUNT — which is not what any spelling of this used to return.

  test_open_array_constructor_bounds is the other half: `Length([1,2])` is the
  open-array constructor and answers 2, and an array whose ELEMENT is a set
  keeps its ordinary length.
  bug-p-length-low-and-high-of-a-set-answer-the-bitmask }
program test_length_of_a_set_fail;
type
  TDay = (dMo, dTu, dWe);
var
  s: set of Byte;
  e: set of TDay;
begin
  s := [1, 2];
  e := [dMo];
  writeln(Length(s));
  writeln(Length(e));
end.
