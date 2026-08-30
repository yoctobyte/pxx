program test_alloc_census;

{ Smoke test for -dPXX_ALLOC_CENSUS. The census answers a COST question, so it
  has no expected value to pin — what rots is the define itself: every counter
  and every trigger lives inside `{$ifdef PXX_ALLOC_CENSUS}`, which means the
  ordinary build never compiles them and an edit that breaks them is invisible
  until somebody reaches for the tool, which by construction is the moment they
  are debugging something else.

  So this program only has to allocate. The Makefile row compiles it WITH the
  define and checks that a well-formed census line reaches stderr, and compiles
  it WITHOUT and checks that nothing does. }

var
  s: AnsiString;
  i, n: Int64;

begin
  n := 0;
  for i := 1 to 20000 do
  begin
    s := 'block';
    s := s + 'more';
    n := n + Length(s);
  end;
  writeln('n=', n);
end.
