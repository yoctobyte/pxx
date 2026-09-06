{ The negative half of test_a_const_section_ends_at_a_section_keyword.

  Making the const loop STOP at a section keyword must not make the section
  LEGAL wherever it stops. fpc 3.2.2 refuses `resourcestring` inside a
  routine's declaration part, and so must pxx -- the loop breaks and hands the
  word to a dispatcher that does not accept it.

  Without this row the positive file passes just as well if the const loop had
  been widened to stop at every identifier, which would accept anything.
  feature-pascal-corpus-expansion }
program test_a_resourcestring_in_a_routine_is_refused;
procedure Q;
const c = 1;
resourcestring S = 'hi';
begin
  WriteLn(c, S);
end;
begin
  Q;
end.
