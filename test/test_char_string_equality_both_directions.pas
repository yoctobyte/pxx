program test_char_string_equality_both_directions;
{ `c = s` and `s = c` must agree, and neither may WRITE to the string.

  i386 emitted `or dword [ecx], 1` for the char-on-the-LEFT arm where it meant
  `cmp dword [ecx], 1` -- $83 is group-1 and the ModRM reg field picks the
  operation, so $09 (reg=1) is OR and $39 (reg=7) is CMP. Two failures from one
  byte: OR's ZF comes from `len or 1` and is never zero, so the following `jne`
  always took the not-equal arm; and it WROTE, setting bit 0 of the length
  prefix. The str-on-the-left arm nine lines up was correct, so exactly one
  direction was wrong.

  The test asserts AGREEMENT between the two directions plus length stability,
  not a per-target constant, so it carries no expected width and is meaningful
  on every backend. }
var
  s: string[8];
  t: string[8];
begin
  s := 'a';
  WriteLn('1char eq  ', ('a' = s) = (s = 'a'), ' ', 'a' = s);
  WriteLn('1char ne  ', ('b' <> s) = (s <> 'b'), ' ', 'b' <> s);

  { The length-corruption half: 2 has bit 0 clear, so an OR is visible where a
    CMP is not. The comparison is legitimately false here (lengths differ) --
    that is the point, it MASKS the wrong answer and leaves only the write. }
  t := 'ab';
  WriteLn('len before ', Length(t));
  if 'a' = t then WriteLn('unexpected equal') else WriteLn('not equal');
  WriteLn('len after  ', Length(t));
  WriteLn('t is [', t, ']');
end.
