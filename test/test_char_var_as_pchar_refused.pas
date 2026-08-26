{ A character VARIABLE is not a PChar. fpc 3.2.2:
    "Incompatible type for arg no. 1: Got "Char", expected "PChar""
  pxx used to COMPILE this and pass the ordinal, so the callee dereferenced
  address 45 — the worst of the three outcomes available.

  The Makefile asserts only that this does NOT compile; the wording is not
  pinned. Its sibling test_char_to_pchar_conversion.pas pins everything that
  DOES convert, and the two belong together: the constant case is not an
  exception to FPC's rule, it IS FPC's rule.
  bug-p-three-mechanisms-decide-what-becomes-a-pchar-and-they-disagree }
program test_char_var_as_pchar_refused;
procedure Show(p: PChar);
begin
  WriteLn(p);
end;
var
  c: Char;
begin
  c := '-';
  Show(c);
end.
