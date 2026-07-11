program test_case_range_inverted_error;
{ Must be REJECTED: string case range with lo > hi (lexicographic), the
  tcase3 shape. Regression for
  bug-case-of-string-segfault-and-label-validation symptom 2. }
var s: string;
begin
  case s of
    'abba'..'ababaca': writeln('a');
  end;
end.
