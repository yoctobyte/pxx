{ MUST NOT COMPILE, and it is the RESIDUAL of a fix, not the bug itself.

  `d := s` from a fixed-length array is now COPIED
  (test_a_static_array_is_copied_into_a_dynamic_array). What is copied is an
  element LIST, built through the same array constructor `d := [1, 2, 3]` uses,
  so the shapes whose elements are not values fall outside it:
    - a MULTIDIMENSIONAL source, whose `s[i]` is a row and not a value;
    - a source whose ELEMENT is itself a dynamic array;
    - a DESTINATION whose element is a fixed ROW -- bytes inside the outer
      block rather than a handle, the same limit tarray15 records.

  This file is the first. It is REFUSED rather than left to the bare store,
  because the bare store is the original defect: it wrote the static array's
  ADDRESS into the handle slot and Length read the words in front of it
  (measured 4310328, then a SEGFAULT). fpc accepts a fixed-ROW destination and
  we do not, so that one is a compat gap recorded on the ticket -- a refusal
  rather than silent garbage, which is the whole difference.

  THIS FILE IS ALSO THE ONLY THING THAT NOTICES IF THE REWRITE STOPS BEING
  REACHED. If the materialisation were removed, `d := s` would compile again
  through the bare store and every row of the positive file would still print
  correct values for the two-element cases it happens to fit -- but this row
  would compile too, which it must never do.
  bug-a-a-static-array-assigned-to-a-dynamic-array-stores-its-address }
program test_a_static_array_is_not_a_dynamic_array_fail;
var
  d: array of LongInt;
  s: array[0..1, 0..1] of LongInt;
begin
  s[0, 0] := 2;
  d := s;
  Writeln(Length(d));
end.
