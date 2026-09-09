program test_a_string_literal_bound_to_a_pwidechar;
{$mode delphi}{$H+}
{ `pw := 'abcd'` with `pw: PWideChar`. Until 2026-09-09 the operand read
  `4 0 0 0 25185` as UTF-16 units -- a 64-bit length of 4, then 'ab' and 'cd'
  NARROW, two characters packed into each WideChar -- because two independent
  things both keyed off IsNodePChar, which does not and must not answer for a
  pointer to tyWideChar: the literal kept its narrow payload AND kept pointing at
  the block start instead of at character 0.

  THE PChar ROW IS THE CONTROL and it is why this is a wide-side defect rather
  than a literal-addressing one: the same literal, the same program, bound to a
  PChar, was always correct.

  THE HAND-BUILT ROW IS THE OTHER CONTROL: `p := @buf[0]` over a correct
  `array[0..4] of WideChar` indexed perfectly before the fix too, so a wide
  pointer was never broken as a pointer -- only the literal binding was.

  NOT ASSERTED HERE: `Length(pw)`, which is a SEPARATE defect on the same type
  and is wrong for a hand-built pointer too, with no literal in sight. It has its
  own ticket and its own repro; asserting it here would tie two independent
  fixes to one file.
  bug-p-a-string-literal-bound-to-a-pwidechar-is-emitted-narrow }
var
  buf: array[0..4] of WideChar;
  p, pw: PWideChar;
  pc: PChar;
  i: LongInt;
begin
  buf[0] := 'a'; buf[1] := 'b'; buf[2] := 'c'; buf[3] := 'd'; buf[4] := #0;
  p := @buf[0];
  Write('hand-built:');
  for i := 0 to 4 do Write(' ', Ord(p[i]));
  WriteLn;
  pw := 'abcd';
  Write('literal   :');
  for i := 0 to 4 do Write(' ', Ord(pw[i]));
  WriteLn;
  pc := 'abcd';
  Write('pchar ctrl:');
  for i := 0 to 4 do Write(' ', Ord(pc[i]));
  WriteLn;
end.
