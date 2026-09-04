{ FPC's assertion failure LINE SHAPE, which is not what this ticket originally
  sketched. Measured on fpc 3.2.2, 2026-09-04:

    Assert(1=2, 'boom')   ->  boom (af.pas, line 4).
    Assert(1=2)           ->  Assertion failed (afn.pas, line 3).
    ...uses sysutils      ->  EAssertionFailed: boom (afs.pas, line 4)

  So the message REPLACES `Assertion failed` rather than following it, the file
  is the BASENAME (not the path the compiler was given), and the trailing period
  belongs to the default PRINTER — the hook path does not get one. pxx printed
  `Assertion failed: boom` with no position, a different shape and not merely a
  missing suffix.

  THE LINE NUMBER IS THE ASSERTION HERE, and it is why this file has a leading
  block of filler: an off-by-one, or a position taken from the wrong token,
  reads as plausible on line 1 and cannot on line 20. The message is checked in
  full rather than grepped for the filename, because the failure this replaces
  was a line SHAPE and a grep for `boom` passed on it.
  feature-p-assertions-directive-and-position }
program test_assert_message_position;
var
  filler: Integer;
begin
  filler := 0;
  filler := filler + 1;
  filler := filler + 1;
  WriteLn('before ', filler);
  Assert(1 = 2, 'boom');
  WriteLn('after');
end.
