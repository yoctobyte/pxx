program test_a_whole_array_destination_refuses_a_scalar;
{ bug-p-a-whole-array-assignment-destination-is-never-type-checked

  THIS FILE MUST NOT COMPILE. Every statement below assigned a managed string
  to a WHOLE array and was accepted; two of the four then SIGSEGV'd, because the
  store landed on managed-string slots. fpc 3.2.2 refuses all four.

  It is here in its own file for the reason the object-value refusal fixtures
  are: a program that must be rejected cannot share a file with one that must
  run. The Makefile asserts the diagnostic text, so this file is aimed as well
  as asserted -- a `!` on the compiler alone would pass on a typo.

  The shapes that must KEEP compiling are the other half of this pair and they
  are drawn from a census rather than from imagination:
  test_a_whole_array_destination_takes_every_shape_the_census_found.pas. }

type
  TSA = array[0..2] of AnsiString;
  PSA = ^TSA;
  TC  = class
          SA: TSA;
          DA: array of AnsiString;
        end;

var
  sa: TSA;
  p: PSA;
  c: TC;
  s: AnsiString;

begin
  s := 'x';
  New(p);
  c := TC.Create;
  sa := s;        { plain identifier destination -- SIGSEGV before the refusal }
  c.SA := s;      { class field destination      -- SIGSEGV before the refusal }
  p^ := s;        { deref destination }
  c.DA := s;      { dynamic-array field destination }
  WriteLn('this program must never be built');
end.
