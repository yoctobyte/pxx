{ MUST NOT COMPILE. `d := s` with `d: array of LongInt` and `s: array[0..2] of
  LongInt` stored the STATIC array's ADDRESS into the dynamic array's handle
  slot. Length then read the words in front of `s` as a managed-block header:
  measured Length(d) = 4310328 and a SEGFAULT walking it, where fpc prints
  `len=3: 2 4 6`. Silent garbage, then a crash, from four lines of ordinary
  Pascal.

  The kind check could not see it: an array symbol's TypeKind is its ELEMENT's
  kind, so both sides are tyInteger and AssignKindsIncompatible sees a matching
  pair. It is the second pair in that funnel the KIND cannot express.

  REFUSED, not copied -- fpc copies, and the copy is the real fix
  (bug-a-a-static-array-assigned-to-a-dynamic-array-stores-its-address). Until
  then a named refusal, because a fall-through is not a diagnostic.

  Its positive control is a SEPARATE file that must COMPILE:
  test_an_open_array_parameter_still_assigns_to_a_dynamic_array. That is the
  shape an over-broad guard breaks, and it is not hypothetical -- the first
  version of this guard tested `ArrLen > 0`, which refused it, because
  AllocParam stamps ArrLen := 1000 on EVERY array parameter as the open-array
  placeholder. ArrLen does not mean "fixed length". }
program test_a_static_array_is_not_a_dynamic_array_fail;
var
  d: array of LongInt;
  s: array[0..2] of LongInt;
begin
  s[0] := 2; s[1] := 4; s[2] := 6;
  d := s;
  Writeln(Length(d));
end.
