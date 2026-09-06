{ The record half of
  test_a_stray_token_in_a_class_or_record_body_is_refused -- a SECOND file
  because it is a second arm, not a second spelling. The record member loop at
  pasparser_decl.inc:5042 and the class one at :7230 are independent copies of
  the same shape with DIFFERENT allow-lists (a record body admits `class`, a
  class body does not), so one file cannot fail for both.

  The record loop is also where a dead instrument nearly went unnoticed: the
  first probe for this bug was placed here and fired ZERO on a known-bad
  program, which read as "nothing reaches the catch-all". The program declared
  a CLASS. A census of the wrong arm answers, and answers cleanly.
  bug-p-a-class-or-record-body-silently-swallows-any-token-it-does-not-recognise }
program test_a_stray_token_in_a_record_body_is_refused;
type
  TR = record
    x: Integer;
    42 43;
  end;
var r: TR;
begin
  r.x := 5;
  WriteLn('unreachable: the stray literals above must not compile');
end.
