program test_an_inline_specialize_above_the_generic_routines_body;
{ `specialize F<T>(x)` written between a generic routine's INTERFACE header and
  its implementation BODY was left in the token stream as literal tokens and
  reached the reader as `undefined variable (specialize)`. The rewrite sweep
  started at the routine's DEFINITION and ran forward only.
  bug-p-an-inline-specialize-before-the-generic-routines-body-is-not-rewritten

  THREE ROWS, AND THE THIRD IS THE ONE THAT MUST STILL FAIL — it is not asserted
  here, because a compile error cannot be a row of an output comparison. Say it
  in words instead: a use with NO declaration ahead of it (no interface header,
  body further down) is refused by fpc 3.2.2 too, and moving the sweep start
  backwards must not start accepting it. Measured at compiler 1defef6b62d0 and
  it is still refused, with the same `undefined variable (specialize)`.

    1  before-body  the use is ABOVE the body, below the header   <- the bug
    2  after-body   the use is BELOW the body                     (the control)
    3  no-header    no declaration at all ahead of the use        (must refuse)

  42 and 32 rather than one number twice: the two uses specialize ONE template
  at ONE type, so if the second body were emitted for the first use's mangled
  name — or the sweep collapsed them to one call — the rows would print the same
  value. They must differ. Neither is a zero, a default, or SizeOf(Integer). }
{$mode objfpc}
uses uinlinespecfwd;
begin
  Writeln('before-body ', UsedBeforeBody);   { 42 }
  Writeln('after-body  ', UsedAfterBody);    { 32 }
end.
