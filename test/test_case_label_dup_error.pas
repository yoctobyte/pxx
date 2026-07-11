program test_case_label_dup_error;
{ Must be REJECTED: duplicate case label (FPC errors too). Regression for
  bug-case-of-string-segfault-and-label-validation symptom 2. }
var i: Integer;
begin
  case i of
    1..5: writeln('a');
    4..9: writeln('b');
  end;
end.
