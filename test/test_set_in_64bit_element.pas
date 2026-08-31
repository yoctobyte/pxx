program test_set_in_64bit_element;
{ `in` with a 64-bit test value. Two shapes, and they take DIFFERENT paths:
  an all-constant set literal never becomes a set at all (the parser emits
  SPECIAL_IN and the backend compares inline), while a set VARIABLE lowers to
  an ordinary IR_BINOP tkIn. Both were wrong on all four 32-bit backends --
  the literal shape silently answered TRUE for 2^32+1, and the variable shape
  failed to compile ("64-bit binop operator not yet supported") because a
  64-bit LEFT operand routed `in` into the 64-bit ARITHMETIC emitter.
  bug-a-set-membership-truncates-the-test-value-on-32-bit-backends

  WE DIVERGE FROM FPC HERE, DELIBERATELY, AND IT IS WORTH KNOWING BEFORE YOU
  "FIX" THIS FILE. FPC 3.2.2 TRUNCATES: it answers TRUE for `2^32+1 in [1,2,3]`,
  agreeing with what the 32-bit backends used to do. 7 of the 21 rows below
  differ from FPC; the other 14 agree. The expected output is pxx's own x86-64
  and aarch64 answer -- out of range means NOT a member -- which those two
  backends already gave, because their compare is REX.W / 64-bit wide.

  So the change did not pick a new semantics: it made four backends agree with
  the two that already disagreed with them. What it could not settle is which
  answer is RIGHT, and that is a fork of intent rather than a bug:
  decide-does-in-truncate-an-out-of-range-element-or-answer-false. If that
  ruling goes the other way, this file's expectations move WITH the x86-64
  backend, never separately -- the one property no ruling changes is that all
  six targets answer alike. }
type
  TS = set of Byte;
var
  s: TS;
  q: Int64;
  u: UInt64;
  i: Integer;
  c: Char;
begin
  s := [1, 2, 3];

  { --- the truncation itself: low 32 bits land inside the set --- }
  q := 4294967297;  WriteLn('lit  2^32+1 : ', q in [1,2,3]);
  q := 4294967297;  WriteLn('var  2^32+1 : ', q in s);
  q := -4294967295; WriteLn('lit -2^32+1 : ', q in [1,2,3]);
  q := -4294967295; WriteLn('var -2^32+1 : ', q in s);
  u := 4294967297;  WriteLn('lit  u2^32+1: ', u in [1,2,3]);
  u := 4294967297;  WriteLn('var  u2^32+1: ', u in s);

  { --- in range, and must stay TRUE --- }
  q := 1;   WriteLn('lit       1 : ', q in [1,2,3]);
  q := 1;   WriteLn('var       1 : ', q in s);
  q := 3;   WriteLn('var       3 : ', q in s);

  { --- out of range for ordinary reasons --- }
  q := 0;   WriteLn('var       0 : ', q in s);
  q := 300; WriteLn('lit     300 : ', q in [1,2,3]);
  q := 300; WriteLn('var     300 : ', q in s);
  q := -1;  WriteLn('var      -1 : ', q in s);

  { --- ranges, which are the other SPECIAL_IN item shape --- }
  q := 5;           WriteLn('lit range 5 : ', q in [4..9]);
  q := 4294967301;  WriteLn('lit range +: ', q in [4..9]);
  q := 20;          WriteLn('lit range20 : ', q in [4..9]);

  { --- 32-bit and Char elements must be untouched by the change --- }
  i := 2;   WriteLn('int       2 : ', i in [1,2,3]);
  i := 300; WriteLn('int     300 : ', i in [1,2,3]);
  i := 2;   WriteLn('int var   2 : ', i in s);
  c := 'e'; WriteLn('char      e : ', c in ['a'..'z']);
  c := 'E'; WriteLn('char      E : ', c in ['a'..'z']);
end.
