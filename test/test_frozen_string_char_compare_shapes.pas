program test_frozen_string_char_compare_shapes;
{ A one-character frozen string compares equal to that Char, from EVERY lvalue
  shape and in BOTH directions.

  Two distinct defects met here and only one of them was about the flip.

  THE CRASH IS PRE-EXISTING AND SHIPS TODAY. x86-64's `String = Char` and
  `Char = String` arms guarded on `lhsTk = tyString` -- a test for the GENERIC
  frozen tag, not for membership. A variable's IR_LEA carries that legacy tag,
  so `s = 'X'` matched; an ARRAY ELEMENT and a RECORD FIELD are tagged with
  their real frozen kind, so they did not, and the comparison fell through to
  EmitStrCmpReg, which takes the Char's ORDINAL as a string ADDRESS and
  dereferences it. `a[0] = 'X'` for `a: array[0..1] of string[8]` SIGSEGVs on
  the pinned compiler in DEFAULT mode -- verified before the fix, and that is
  this file's positive control.

  THE WRONG ANSWER WAS THE FLIP'S. Those same arms read the length with
  `mov rcx, [rax]` and the character at `[rax+8]`. Under a byte prefix the
  first eight bytes are the length byte followed by seven characters, so the
  length test never matched and every comparison answered "not equal" -- in
  BOTH directions, which is why test_char_string_equality_both_directions,
  whose assertion is that the two directions AGREE, stayed green while both
  were wrong.

  ASSERTED AS RELATIONS, not as constants: every row is a Boolean about
  agreement with the Char, so this file carries no per-target width and means
  the same thing on all seven backends and in both prefix modes.
  bug-a-char-vs-frozen-string-comparison-misses-every-shape-but-a-variable }
{$mode objfpc}
type
  TS = string[8];
  TR = record s: TS; n: LongInt; end;
  TA = array[0..1] of TS;
var
  v: TS;
  sh: shortstring;
  r: TR;
  a: TA;
  p: ^TS;
  c: char;
begin
  c := 'X';
  v := 'X'; sh := 'X'; r.s := 'X'; r.n := 77; a[0] := 'X'; a[1] := 'Y';
  p := @v;

  WriteLn('var    ', (v = 'X'),    ' ', ('X' = v),    ' ', (v = c),    ' ', (c = v));
  WriteLn('short  ', (sh = 'X'),   ' ', ('X' = sh),   ' ', (sh = c),   ' ', (c = sh));
  WriteLn('field  ', (r.s = 'X'),  ' ', ('X' = r.s),  ' ', (r.s = c),  ' ', (c = r.s));
  WriteLn('elem   ', (a[0] = 'X'), ' ', ('X' = a[0]), ' ', (a[0] = c), ' ', (c = a[0]));
  WriteLn('deref  ', (p^ = 'X'),   ' ', ('X' = p^),   ' ', (p^ = c),   ' ', (c = p^));

  { the NEGATIVE half -- a guard that only ever says TRUE cannot fail }
  WriteLn('neq    ', (v = 'Y'),    ' ', (a[1] = 'X'), ' ', (r.s = 'Z'), ' ', ('Q' = sh));

  { and a longer string is not equal to any single char, from every shape }
  v := 'ab'; r.s := 'ab'; a[0] := 'ab'; sh := 'ab';
  WriteLn('len2   ', (v = 'a'),    ' ', (r.s = 'a'),  ' ', (a[0] = 'a'), ' ', (sh = 'a'));

  { the neighbour is intact: a comparison must not WRITE }
  WriteLn('intact ', (r.n = 77),   ' ', (a[1] = 'Y'));
end.
