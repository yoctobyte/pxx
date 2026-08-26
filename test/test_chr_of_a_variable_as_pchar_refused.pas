{ `Chr(i)` for a VARIABLE i is not a PChar either, and for the same reason:
  it is not a constant. `Chr(45)` and `Chr(K)` for a const K both ARE, and
  test_char_to_pchar_conversion.pas pins them.

  This is the row that makes the Chr fold honest — folding a constant Chr into a
  character literal must not quietly make the NON-constant one convert too.
  fpc 3.2.2 gives the same "Incompatible type for arg no. 1" here.
  bug-p-three-mechanisms-decide-what-becomes-a-pchar-and-they-disagree }
program test_chr_of_a_variable_as_pchar_refused;
procedure Show(p: PChar);
begin
  WriteLn(p);
end;
var
  i: Integer;
begin
  i := 45;
  Show(Chr(i));
end.
